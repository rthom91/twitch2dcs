local base = _G

module("twitch.server")

local require = base.require
local table = base.table
local string = base.string
local ipairs = base.ipairs
local pcall = base.pcall

local socket = require("socket")
local tracer = require("twitch.tracer")

local Server = {
	commandHandlers = {},
	isConnected = false,
	connection = nil,
	username = nil,
}
local Server_mt = { __index = Server }

function Server:new()
	local server = base.setmetatable({}, Server_mt)
	return server
end

function Server:reset()
	if self.connection then
		pcall(function() self.connection:close() end)
		self.connection = nil
	end
	self.isConnected = false
	tracer:info("Server connection reset.")
end

local function formatAccessToken(token)
	token = string.gsub(token or "", "^%s*(.-)%s*$", "%1")
	if token == "" then return "" end
	if not string.find(token, "^oauth:") then
		return "oauth:" .. token
	end
	return token
end

function Server:connect(authInfo)
	if self.isConnected then
		self:reset()
	end

	tracer:info("Connecting to " .. authInfo.hostAddress .. ":" .. authInfo.port)

	local success, err = pcall(function()
		self.connection = socket.connect(authInfo.hostAddress, authInfo.port)
	end)

	if not success or not self.connection then
		tracer:error("Failed to connect: " .. (err or "unknown error"))
		return false
	end

	self.connection:settimeout(authInfo.timeout or 0)

	local token = formatAccessToken(authInfo.accessToken)

	self:send("CAP REQ :" .. table.concat(authInfo.caps or {}, " "))
	self:send("PASS " .. token)
	self:send("NICK " .. authInfo.username)
	self:send("JOIN #" .. string.lower(authInfo.username))

	self.username = authInfo.username
	self.isConnected = true

	tracer:info("Successfully connected and authenticated as " .. authInfo.username)
	return true
end

function Server:send(data)
	if not self.connection then
		tracer:error("Cannot send - no active connection.")
		return
	end

	local success, err = pcall(function()
		self.connection:send(data .. "\r\n")
	end)

	if not success then
		tracer:error("DCS -> Twitch: " .. (err or "send failed"))
	end
	-- tracer:info("DCS -> Twitch: " .. data)   -- debugging
end

function Server:receive()
	if not self.connection then
		return "closed"
	end

	local buffer, err
	repeat
		buffer, err = self.connection:receive("*l")

		if not err then
			if string.sub(buffer, 1, 4) == "PING" then
				self:send(string.gsub(buffer, "PING", "PONG", 1))
			else
				local tags, rest = string.match(buffer, "^@([^ ]+) (.*)$")
				local line = rest or buffer

				local prefix, cmd, param = string.match(line, "^:([^ ]+) ([^ ]+)(.*)$")

				local handlers = self.commandHandlers[cmd]
				if param and handlers then
					param = string.sub(param, 2)

					local param1, param2 = string.match(param, "^([^:]+) :(.*)$")

					local user, userhost, displayName = nil, nil, ""
					local isStaff, isModerator, isVIP, isSubscriber = false, false, false, false
					local msgId, targetMsgId, systemMsg, msgIdType, bits = nil, nil, nil, nil, nil

					if prefix then
						user, userhost = string.match(prefix, "^([^!]+)!(.*)$")
					end

					if tags then
						displayName = string.match(tags, "display%-name=([^;]+)") or user or ""
						msgId = string.match(tags, "id=([^;]+)")
						targetMsgId = string.match(tags, "target%-msg%-id=([^;]+)")
						systemMsg = string.match(tags, "system%-msg=([^;]+)")
						msgIdType = string.match(tags, "msg%-id=([^;]+)")
						bits = string.match(tags, "bits=([^;]+)")

						local badges = string.match(tags, "badges=([^;]+)")
						if badges then
							for badge in string.gmatch(badges, "([^,]+)") do
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
						if string.match(tags, "mod=1") then isModerator = true end
					end

					if displayName == "" then displayName = user or "" end

					for _, handler in ipairs(handlers) do
						handler({
							prefix = prefix,
							user = user or "",
							displayName = displayName,
							userhost = userhost,
							param1 = param1,
							param2 = param2,
							tags = tags,
							isStaff = isStaff,
							isModerator = isModerator,
							isVIP = isVIP,
							isSubscriber = isSubscriber,
							msgId = msgId,
							targetMsgId = targetMsgId,
							systemMsg = systemMsg,
							msgIdType = msgIdType,
							bits = bits
						})
					end
				end
			end
		elseif err ~= "timeout" then
			tracer:error("Receive error: " .. err)
		end
	until err

	return err
end

function Server:addCommandHandler(cmd, handler)
	if not self.commandHandlers[cmd] then
		self.commandHandlers[cmd] = {}
	end
	table.insert(self.commandHandlers[cmd], handler)
end

function Server:removeCommandHandler(cmd, handler)
	if not self.commandHandlers[cmd] then return end
	for i = #self.commandHandlers[cmd], 1, -1 do
		if self.commandHandlers[cmd][i] == handler then
			table.remove(self.commandHandlers[cmd], i)
		end
	end
end

return Server