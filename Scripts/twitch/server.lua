local base = _G

module("twitch.server")

local require = base.require
local string = base.string
local tostring = base.tostring
local table = base.table
local ipairs = base.ipairs
local pcall = base.pcall

local socket = require("socket")
local tracer = require("twitch.tracer")
local irc = require("twitch.irc")

local Server = {
	isConnected = false,
	connection = nil,
	username = nil,
	displayNameHint = nil,
}

local Server_mt = { __index = Server }

function Server:new()
	local server = base.setmetatable({}, Server_mt)
	server.recvBuf = ""
	server.commandHandlers = {}
	server.isConnected = false
	server.connection = nil
	server.username = nil
	server.displayNameHint = nil
	return server
end

function Server:reset()
	local hadConnection = (self.connection ~= nil) or self.isConnected
	if self.connection then
		pcall(function() self.connection:close() end)
		self.connection = nil
	end
	self.isConnected = false
	self.recvBuf = ""
	if hadConnection then
		tracer:info("Server connection reset.")
	end
end

function Server:connect(authInfo)
	if self.isConnected then
		self:reset()
	end

	tracer:info("Connecting to " .. authInfo.hostAddress .. ":" .. authInfo.port)

	local sock, err = socket.tcp()
	if not sock then
		tracer:error("Failed to create socket: " .. tostring(err))
		self.isConnected = false
		return false
	end

	sock:settimeout(3)

	local ok, connectErr = sock:connect(authInfo.hostAddress, authInfo.port)
	if not ok then
		tracer:error("Failed to connect: " .. tostring(connectErr))
		pcall(function() sock:close() end)
		self.isConnected = false
		return false
	end

	sock:settimeout(authInfo.timeout or 0)
	self.connection = sock

	local token = authInfo.accessToken or ""
	local login = string.lower(authInfo.username or "")

	self:send("CAP REQ :" .. table.concat(authInfo.caps or {}, " "))
	self:send("PASS " .. token)
	self:send("NICK " .. login)
	self:send("JOIN #" .. login)

	self.username = login
	self.displayNameHint = authInfo.username
	self.isConnected = true

	return true
end

function Server:send(data)
	if not self.connection then
		return
	end

	local success, err = pcall(function()
		if self.connection then
			self.connection:send(data .. "\r\n")
		end
	end)

	if not success then
		tracer:error("DCS -> Twitch: " .. (err or "send failed"))
	end
end

function Server:receive()
	local conn = self.connection
	if not conn then
		return "closed"
	end

	local MAX_LINES_PER_FRAME = 40
	local linesProcessed = 0
	local err

	while linesProcessed < MAX_LINES_PER_FRAME do
		if not self.connection then
			return "closed"
		end

		local buffer, partial
		buffer, err, partial = conn:receive("*l")

		if err then
			if err == "timeout" then
				if partial and partial ~= "" then
					self.recvBuf = (self.recvBuf or "") .. partial
				end
				return "timeout"
			end

			if partial and partial ~= "" then
				self.recvBuf = (self.recvBuf or "") .. partial
			end

			if self.connection then
				tracer:error("Receive error: " .. tostring(err))
			end
			return err
		end

		linesProcessed = linesProcessed + 1
		buffer = (self.recvBuf or "") .. buffer
		self.recvBuf = ""

		local pingPayload = string.match(buffer, "^PING%s*:?(.*)$")
		if pingPayload then
			if pingPayload ~= "" then
				self:send("PONG :" .. pingPayload)
			else
				self:send("PONG :tmi.twitch.tv")
			end
		else
			local parsed = irc.parseLine(buffer)
			if parsed then
				local handlers = self.commandHandlers[parsed.cmd]
				if handlers then
					local user, userhost = nil, nil
					local displayName = ""
					local userId = nil
					local loginTag = ""
					local isStaff, isModerator, isVIP, isSubscriber = false, false, false, false
					local msgId, targetMsgId, systemMsg, msgIdType, bits = nil, nil, nil, nil, nil
					local color = ""
					local recipientDisplayName = ""
					local recipientName = ""
					local massGiftCount = ""

					if parsed.prefix then
						user, userhost = string.match(parsed.prefix, "^([^!]+)!(.*)$")
						if not user then
							local bare = parsed.prefix
							if bare ~= "" and bare ~= "tmi.twitch.tv" and not string.find(bare, ".", 1, true) then
								user = bare
							end
						end
					end

					if parsed.tagsStr then
						local tags = irc.parseTags(parsed.tagsStr)

						displayName = tags["display-name"] or user or ""
						userId = tags["user-id"]
						loginTag = tags["login"] or ""
						msgId = tags["id"]
						msgIdType = tags["msg-id"]
						targetMsgId = tags["target-msg-id"]
						systemMsg = tags["system-msg"]
						bits = tags["bits"]
						color = tags["color"] or ""

						recipientDisplayName = tags["msg-param-recipient-display-name"] or ""
						recipientName = tags["msg-param-recipient-name"] or ""
						massGiftCount = tags["msg-param-mass-gift-count"] or ""

						if tags["badges"] then
							for badge in string.gmatch(tags["badges"], "([^,]+)") do
								if badge:find("^staff/") or badge:find("^admin/") then
									isStaff = true
								elseif badge:find("^moderator/") or badge:find("^broadcaster/") then
									isModerator = true
								elseif badge:find("^vip/") then
									isVIP = true
								elseif badge:find("^subscriber/") then
									isSubscriber = true
								end
							end
						end

						if tags["mod"] == "1" then
							isModerator = true
						end
						if tags["vip"] == "1" then
							isVIP = true
						end
						if tags["user-type"] == "staff" or tags["user-type"] == "admin" then
							isStaff = true
						end
					end

					if (not user or user == "") and loginTag ~= "" then
						user = loginTag
					end

					if displayName == "" then
						displayName = user or ""
					end

					for _, handler in ipairs(handlers) do
						handler({
							prefix = parsed.prefix,
							user = user or "",
							login = loginTag,
							displayName = displayName,
							userId = userId,
							userhost = userhost,
							param1 = parsed.param1,
							param2 = parsed.param2,
							tags = parsed.tagsStr,
							isStaff = isStaff,
							isModerator = isModerator,
							isVIP = isVIP,
							isSubscriber = isSubscriber,
							msgId = msgId,
							msgIdType = msgIdType,
							targetMsgId = targetMsgId,
							systemMsg = systemMsg,
							bits = bits,
							color = color,
							recipientDisplayName = recipientDisplayName,
							recipientName = recipientName,
							massGiftCount = massGiftCount
						})
					end
				end
			end
		end
	end

	return "timeout"
end

function Server:addCommandHandler(cmd, handler)
	if not self.commandHandlers then
		self.commandHandlers = {}
	end
	if not self.commandHandlers[cmd] then
		self.commandHandlers[cmd] = {}
	end
	table.insert(self.commandHandlers[cmd], handler)
end

function Server:removeCommandHandler(cmd, handler)
	if not self.commandHandlers or not self.commandHandlers[cmd] then return end

	for i = #self.commandHandlers[cmd], 1, -1 do
		if self.commandHandlers[cmd][i] == handler then
			table.remove(self.commandHandlers[cmd], i)
			break
		end
	end
end

return Server