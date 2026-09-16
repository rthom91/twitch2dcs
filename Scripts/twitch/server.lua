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

local Server = {
	isConnected = false,
	connection = nil,
	username = nil,
	displayNameHint = nil,
}

local Server_mt = { __index = Server }

local TAG_UNESCAPE = {
	[":"] = ";",
	["s"] = " ",
	["\\"] = "\\",
	["r"] = "\r",
	["n"] = "\n",
}

local function unescapeTagValue(value)
	if not value or value == "" then
		return value or ""
	end

	if not string.find(value, "\\", 1, true) then
		return value
	end

	local out = {}
	local i = 1
	local len = #value

	while i <= len do
		local c = string.sub(value, i, i)
		if c == "\\" then
			if i == len then
				break
			end
			local n = string.sub(value, i + 1, i + 1)
			out[#out + 1] = TAG_UNESCAPE[n] or n
			i = i + 2
		else
			out[#out + 1] = c
			i = i + 1
		end
	end

	return table.concat(out)
end

local function formatAccessToken(token)
	token = string.gsub(token or "", "^%s*(.-)%s*$", "%1")
	if token == "" then
		return ""
	end
	if not string.find(token, "^oauth:") then
		return "oauth:" .. token
	end
	return token
end

local function parseIrcTags(tagString)
	if not tagString then return {} end

	local tags = {}
	for pair in string.gmatch(tagString, "([^;]+)") do
		local key, value = string.match(pair, "^([^=]+)=?(.*)$")
		if key then
			tags[key] = unescapeTagValue(value or "")
		end
	end
	return tags
end

local function parseIrcParams(paramRest)
	local middle = {}
	local trailing = nil

	paramRest = string.match(paramRest or "", "^%s*(.-)%s*$") or ""
	if paramRest == "" then
		return middle, trailing
	end

	if string.sub(paramRest, 1, 1) == ":" then
		return middle, string.sub(paramRest, 2)
	end

	local trailingStart = string.find(paramRest, " :", 1, true)
	if trailingStart then
		local before = string.sub(paramRest, 1, trailingStart - 1)
		trailing = string.sub(paramRest, trailingStart + 2)
		for token in string.gmatch(before, "%S+") do
			middle[#middle + 1] = token
		end
	else
		for token in string.gmatch(paramRest, "%S+") do
			middle[#middle + 1] = token
		end
	end

	return middle, trailing
end

local function stripCtcpAction(text)
	if not text or text == "" then
		return text or ""
	end

	local inner = string.match(text, "^\001ACTION (.*)\001$")
	if inner then
		return inner
	end

	inner = string.match(text, "^\001ACTION (.*)$")
	if inner then
		return inner
	end

	return text
end

local function parseIrcLine(buffer)
	if not buffer or buffer == "" then
		return nil
	end

	local tagsStr = nil
	local rest = buffer

	if string.sub(rest, 1, 1) == "@" then
		local tagPart, afterTags = string.match(rest, "^@([^ ]+) ?(.*)$")
		if not tagPart then
			return nil
		end
		tagsStr = tagPart
		rest = afterTags or ""
	end

	if rest == "" then
		return nil
	end

	local prefix = nil
	if string.sub(rest, 1, 1) == ":" then
		local pfx, afterPrefix = string.match(rest, "^:([^ ]+) ?(.*)$")
		if not pfx then
			return nil
		end
		prefix = pfx
		rest = afterPrefix or ""
	end

	if rest == "" then
		return nil
	end

	local cmd, paramRest = string.match(rest, "^([^ ]+)(.*)$")
	if not cmd or cmd == "" then
		return nil
	end

	local middle, trailing = parseIrcParams(paramRest)
	local param1 = middle[1]
	local param2 = trailing

	if cmd == "PRIVMSG" or cmd == "WHISPER" then
		param2 = stripCtcpAction(param2 or "")
	end

	return {
		tagsStr = tagsStr,
		prefix = prefix,
		cmd = cmd,
		middle = middle,
		trailing = trailing,
		param1 = param1,
		param2 = param2,
	}
end

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

	local token = formatAccessToken(authInfo.accessToken)
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
			local parsed = parseIrcLine(buffer)
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
						local tags = parseIrcTags(parsed.tagsStr)

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