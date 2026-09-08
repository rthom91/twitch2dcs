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
	self.userSkins = {}
	self.userTwitchColors = {}
	self.userNames = {}
	self.userLastActive = {}
	self.userDisplayNames = {}
	self.broadcasterKey = nil
	self.broadcasterColor = nil
	self.lastViewerUpdate = os.time()
	self.chatLog = nil

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
	self.recentPaletteIndices = {}
	self.activeMods = {}

	local logDir = lfs.writedir() .. "Logs\\"
	local fullPath = logDir .. "Twitch2DCS-chat-log.txt"
	self.chatLog = io.open(fullPath, "w")
	if self.chatLog then
		self.chatLog:write("=== Twitch2DCS Chat Log Started " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n\n")
		self.chatLog:flush()
	end

	local ok, uiErr = base.pcall(function()
		self.ui = UI:new()
		self.ui.lockUIPosition = config:getLockUIPosition()
	end)

	if not ok then
		tracer:error("Failed to create UI: " .. tostring(uiErr))
		error("UI creation failed: " .. tostring(uiErr))
	end

	Handlers.register(self.server, self, config, session, tracer)

	self.ui:setCallbacks({
		onUISendMessage = function(args) self:onUISendMessage(args) end,
		onUIPositionChanged = function(args) self:onUIPositionChanged(args) end,
		onUIColorModeChanged = function()
			self.userSkins = {}
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
	user = (user or ""):lower()
	if user == "" then
		return self.ui.messageSkin
	end

	local colorMode = self.config:getColorMode()
	local colorUpdated = false

	if twitchColor and twitchColor ~= "" and string.sub(twitchColor, 1, 1) == "#" then
		if self.userTwitchColors[user] ~= twitchColor then
			self.userTwitchColors[user] = twitchColor
			colorUpdated = true
		end
	end

	local skin = self.userSkins[user]
	local isNew = false
	if not skin then
		skin = self.ui.skinFactory:getSkin()
		self.userSkins[user] = skin
		isNew = true
	end

	local textState = skin.skinData.states.released[2].text
	local colorHex = nil
	local storedColor = self.userTwitchColors[user]

	if colorMode == "twitch" and storedColor then
		colorHex = "0x" .. string.sub(storedColor, 2) .. "ff"
	elseif isNew then
		local colors = self.config:getMessageColors()
		local available = {}

		for i = 1, #colors do
			local usedRecently = false
			for _, recent in ipairs(self.recentPaletteIndices) do
				if recent == i then
					usedRecently = true
					break
				end
			end
			if not usedRecently then
				table.insert(available, i)
			end
		end

		if #available == 0 then
			for i = 1, #colors do
				table.insert(available, i)
			end
		end

		local chosenIndex = available[math.random(1, #available)]
		colorHex = self.config:rgbToHex(colors[chosenIndex])

		table.insert(self.recentPaletteIndices, chosenIndex)
		if #self.recentPaletteIndices > 10 then
			table.remove(self.recentPaletteIndices, 1)
		end
	end

	if colorHex and textState.color ~= colorHex then
		textState.color = colorHex
		colorUpdated = true
	end

	textState.fontSize = self.ui.fontSize or self.config:getFontSize()

	if colorUpdated and colorMode == "twitch" and not isNew and self.ui then
		self.ui:updateListM(true)
	end

	return skin
end

function TwitchClient:addViewer(displayName, userId, login, skipTitleUpdate)
	login = (login or displayName or ""):lower()
	if login == "" then return end

	local key = login
	local isNew = not self.userNames[key]

	self.userNames[key] = true
	self.userLastActive[key] = os.time()

	if displayName and displayName ~= "" then
		self.userDisplayNames[key] = displayName
	elseif not self.userDisplayNames[key] then
		self.userDisplayNames[key] = login
	end

	if isNew and not skipTitleUpdate then
		self:updateTitle()
	end

	if self.username and key == self.username then
		self.broadcasterKey = key
	end
end

function TwitchClient:removeViewer(displayName, userId, login)
	login = (login or displayName or ""):lower()
	if login == "" then return end

	local key = login

	if self.userNames[key] then
		self.userNames[key] = nil
		self.userLastActive[key] = nil
		self.userDisplayNames[key] = nil
		self.userSkins[key] = nil

		if self.broadcasterKey == key then
			self.broadcasterKey = nil
		end

		self:updateTitle()
	end
end

function TwitchClient:addModerator(login, displayName)
	login = (login or ""):lower()
	if login == "" then return end
	if self.username and login == self.username then return end
	self.activeMods[login] = displayName or login
end

function TwitchClient:removeModerator(login)
	login = (login or ""):lower()
	if login == "" then return end
	self.activeMods[login] = nil
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
			self.ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Not authenticated. No message sent.", nil)
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
	local timestamp = config:getShowTimestamps() and self:getTimeStamp() .. " " or ""

	local tag = ""
	if config:getShowUserTags() then
		if self.isStaff then
			tag = "[STAFF] "
		elseif self.isModerator or self.session:isVerified() then
			tag = "[MOD] "
		elseif self.isVIP then
			tag = "[VIP] "
		elseif self.isSubscriber then
			tag = "[SUB] "
		end
	end

	local prefix = timestamp .. tag .. name .. ": "
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
		local activeCount = 0
		for _ in pairs(self.userNames) do
			activeCount = activeCount + 1
		end
		self.ui:setTitle(activeCount)
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
	self.userNames = {}
	self.userLastActive = {}
	self.userDisplayNames = {}
	self.userSkins = {}
	self.userTwitchColors = {}
	self.broadcasterKey = nil
	self.broadcasterColor = nil
	self.isStaff = false
	self.isModerator = false
	self.isVIP = false
	self.isSubscriber = false
	self.pendingClearRequest = false
	self.clearRequestTime = nil
	self._subgiftSuppress = {}
	self.recentPaletteIndices = {}
	self.activeMods = {}

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