local base = _G

module("twitch.client")

local os = base.os
local io = base.io
local require = base.require
local string = base.string
local tostring = base.tostring
local math = base.math
local table = base.table
local pairs = base.pairs
local ipairs = base.ipairs

local Server = require("twitch.server")
local UI = require("twitch.ui")
local Handlers = require("twitch.handlers")
local Commands = require("twitch.commands")
local Format = require("twitch.format")
local Roster = require("twitch.roster")
local Skins = require("twitch.skins")
local Update = require("twitch.update")
local lfs = require("lfs")

local TwitchClient = {}
local TwitchClient_mt = { __index = TwitchClient }

function TwitchClient:new(config, session, tracer)
	local self = base.setmetatable({}, TwitchClient_mt)

	self.config = config
	self.session = session
	self.tracer = tracer

	self.server = Server:new()
	self.ui = nil
	self.roster = Roster:new()
	self.skins = nil
	self.broadcasterColor = nil
	self.lastViewerUpdate = os.time()
	self.chatLog = nil
	self.update = nil

	self.username = nil
	self.authenticatedDisplayName = nil
	self.authenticatedLogin = nil

	self.isStaff = false
	self.isModerator = false
	self.isVIP = false
	self.isSubscriber = false

	self.pendingClearRequest = false
	self.clearRequestTime = nil

	self._subgiftSuppress = {}

	local logDir = lfs.writedir() .. "Logs\\"
	local fullPath = logDir .. "Twitch2DCS-chat-log.txt"
	self.chatLog = io.open(fullPath, "w")
	if self.chatLog then
		self.chatLog:write("=== Twitch2DCS Chat Log Started " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n\n")
		self.chatLog:flush()
	end

	local ok, uiErr = base.pcall(function()
		self.ui = UI:new(config)
		self.ui.lockUIPosition = config:getLockUIPosition()
	end)

	if not ok then
		tracer:error("Failed to create UI: " .. tostring(uiErr))
		error("UI creation failed: " .. tostring(uiErr))
	end

	self.skins = Skins:new(config, self.ui)
	self.update = Update:new(self, tracer)

	Handlers.register(self.server, self, config, session, tracer)

	self.ui:setCallbacks({
		onUISendMessage = function(args) self:onUISendMessage(args) end,
		onUIPositionChanged = function(args) self:onUIPositionChanged(args) end,
		onUIColorModeChanged = function()
			if self.skins then
				self.skins:clearAssignedSkins()
			end
			if self.ui then
				self.ui:refreshAllMessageSkins(function(login)
					return self:getSkinForUser(login)
				end)
			end
		end,
	})

	return self
end

function TwitchClient:logChat(direction, line)
	if not self.chatLog then return end

	local ts = self:getTimeStamp()
	local dir = (direction == "SENT" and "SENT") or
				(direction == "RECEIVE" and "RCVD") or direction

	self.chatLog:write(string.format("[%s] %s | %s\r\n", ts, dir, line))
	self.chatLog:flush()
end

function TwitchClient:getSkinForUser(user, twitchColor)
	if not self.skins then
		return self.ui and self.ui.messageSkin or nil
	end
	return self.skins:getSkinForUser(user, twitchColor)
end

function TwitchClient:addViewer(displayName, userId, login, skipTitleUpdate)
	if self.roster:addViewer(displayName, userId, login, skipTitleUpdate) then
		self:updateTitle()
	end
end

function TwitchClient:removeViewer(displayName, userId, login)
	if self.roster:removeViewer(displayName, userId, login) then
		if self.skins and self.skins.userSkins then
			local key = (login or displayName or ""):lower()
			if key ~= "" then
				self.skins.userSkins[key] = nil
			end
		end
		self:updateTitle()
	end
end

function TwitchClient:addModerator(login, displayName)
	self.roster:addModerator(login, displayName)
end

function TwitchClient:removeModerator(login)
	self.roster:removeModerator(login)
end

function TwitchClient:onUISendMessage(args)
	local msg = args.message
	local displayMsg = args.displayMessage or msg
	local session = self.session
	local config = self.config

	if Commands.handle(self, msg) then
		return
	end

	if not session:isVerified() then
		if self.ui then
			self.ui:addMessage(Format.systemMessage("Not authenticated. No message sent."))
		end
		return
	end

	local auth = config:getAuthInfo()
	local channel = self.username or string.lower(auth.username or "")

	self.server:send("PRIVMSG #" .. channel .. " :" .. msg)
	self:logChat("SENT", (self.authenticatedDisplayName or auth.username) .. ": " .. msg)

	local name = self.authenticatedDisplayName
	if not name or name == "" then
		name = self.server.displayNameHint or auth.username or channel
	end

	local skin = self:getSkinForUser(channel, self.broadcasterColor)
	local timestamp = config:getShowTimestamps() and self:getTimeStamp() or ""
	local prefix = Format.userPrefix(config, timestamp, {
		isStaff = self.isStaff,
		isModerator = self.isModerator or session:isVerified(),
		isVIP = self.isVIP,
		isSubscriber = self.isSubscriber,
	}, name)

	self.ui:addMessage(prefix, prefix .. displayMsg, skin, nil, channel)
end

function TwitchClient:onUIPositionChanged(args)
	self.config:setPosition({ x = args.x, y = args.y })
end

function TwitchClient:updateTitle()
	if not self.session:isVerified() then
		if self.ui then self.ui:setTitle(0) end
		return
	end

	if self.config:getShowViewerCount() then
		self.ui:setTitle(self.roster:count())
	else
		self.ui:setTitle(0)
	end
end

function TwitchClient:checkViewerCountTimer()
	self:updateTitle()
end

function TwitchClient:connect()
	local auth = self.config:getAuthInfo()

	self.username = string.lower(auth.username or "")
	self.authenticatedDisplayName = nil
	self.authenticatedLogin = nil
	self.broadcasterColor = nil
	self.isStaff = false
	self.isModerator = false
	self.isVIP = false
	self.isSubscriber = false
	self.pendingClearRequest = false
	self.clearRequestTime = nil
	self._subgiftSuppress = {}

	self.roster:reset()
	self.roster:setUsername(self.username)
	if self.skins then
		self.skins:reset()
	end

	self.session:onConnectStart()
	self.server:connect(auth)
end

function TwitchClient:reconnect()
	self.server:reset()
	self:connect()
end

function TwitchClient:receive()
	local err = self.server:receive()
	if err and err ~= "timeout" then
		if err == "closed" then
			if self.server then
				self.server:reset()
			end
			local session = self.session
			if not session.manualDisconnect and not session.authFailureRecovery and not session.connectionLostRecovery then
				self.tracer:warn("Connection closed.")
			end
		end
	end
end

function TwitchClient:getTimeStamp()
	local t = os.date('*t')
	return string.format("%02i:%02i:%02i", t.hour, t.min, t.sec)
end

return TwitchClient
