local status, err = pcall(function()

	local base = _G

	package.path = package.path .. ";.\\LuaSocket\\?.lua;" .. '.\\Scripts\\?.lua;' .. '.\\Scripts\\UI\\?.lua;' .. lfs.writedir() .. 'Scripts\\?.lua;'
	package.cpath = package.cpath .. ";.\\LuaSocket\\?.dll;"

	local os = base.os
	local io = base.io
	local require = base.require
	local table = base.table
	local string = base.string
	local tostring = base.tostring
	local ipairs = base.ipairs
	local type = base.type
	local net = require("net")
	local MsgWindow = require("MsgWindow")
	local lfs = require("lfs")

	local Config = require("twitch.config")
	local Server = require("twitch.server")
	local tracer = require("twitch.tracer")
	local UI = require("twitch.ui")

	cdata = {
		ALLIES = "ALLIES",
		ALL = "ALL",
		MESSAGE = "MESSAGE:",
	}

	function table.contains(t, value)
		for _, v in ipairs(t) do
			if v == value then return true end
		end
		return false
	end

	function table.removeValue(t, value)
		for i = #t, 1, -1 do
			if t[i] == value then
				table.remove(t, i)
				return true
			end
		end
		return false
	end

	local TwitchClient = {
		server = nil,
		ui = nil,
		userSkins = {},
		nextUserIndex = 1,
		userNames = {},
		chatLog = nil,
		lastViewerUpdate = 0,
	}

	local TwitchClient_mt = { __index = TwitchClient }
	local client = nil
	local config = Config:new()
	local lastLockUIPosition = config:getLockUIPosition()
	local lastFontSize = config:getFontSize()

	function TwitchClient:new()
		local self = base.setmetatable({}, TwitchClient_mt)

		self.server = Server:new()

		local logDir = lfs.writedir() .. "Logs\\"
		local fullPath = logDir .. "Twitch2DCS-chat-log.txt"
		self.chatLog = io.open(fullPath, "w")
		if self.chatLog then
			self.chatLog:write("=== Twitch2DCS Chat Log Started " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n\n")
			self.chatLog:flush()
		end

		local ok, uiErr = pcall(function()
			self.ui = UI:new()
			self.ui.lockUIPosition = config:getLockUIPosition()
		end)

		if not ok then
			tracer:error("Failed to create UI: " .. tostring(uiErr))
			error("UI creation failed: " .. tostring(uiErr))
		end

		self:setupCommandHandlers()
		self.lastViewerUpdate = os.time()

		return self
	end

	function TwitchClient:logChat(direction, line)
		if self.chatLog then
			local ts = self:getTimeStamp()
			local dir
			if direction == "SENT" then
				dir = "SENT"
			elseif direction == "RECEIVE" then
				dir = "RCVD"
			else
				dir = direction
			end
			self.chatLog:write("[" .. ts .. "] " .. dir .. " | " .. line .. "\r\n")
			self.chatLog:flush()
		end
	end

	function TwitchClient:setupCommandHandlers()
		tracer:info("Setting up command handlers.")
		self.server:addCommandHandler("PRIVMSG", self.onUserMessage)
		self.server:addCommandHandler("JOIN", self.onUserJoin)
		self.server:addCommandHandler("PART", self.onUserPart)
		self.server:addCommandHandler("CLEARCHAT", self.onClearChat)
		self.server:addCommandHandler("CLEARMSG", self.onClearMsg)
		self.server:addCommandHandler("USERNOTICE", self.onUserNotice)
		self.ui:setCallbacks(self)
	end

	function TwitchClient.onClearChat(cmd)
		tracer:info("CLEARCHAT received from Twitch.")
		client:logChat("SYSTEM", "Chat cleared by moderator.")
		if client.ui then client.ui:clearChat() end
	end

	function TwitchClient.onClearMsg(cmd)
		if cmd.targetMsgId and client.ui then
			client.ui:removeMessage(cmd.targetMsgId)
		end
	end

	function TwitchClient.onUserNotice(cmd)
		if not cmd.systemMsg then return end
		local msg = cmd.systemMsg:gsub("\\s", " ")

		local show = false
		if string.find(cmd.msgIdType or "", "follow") or string.find(msg, "followed") then
			show = config:getShowFollows()
		elseif string.find(cmd.msgIdType or "", "sub") or string.find(msg, "subscribed") then
			show = config:getShowSubscribers()
		elseif string.find(cmd.msgIdType or "", "cheer") or cmd.bits then
			show = config:getShowBits()
		elseif string.find(cmd.msgIdType or "", "charity") or string.find(msg, "charity") then
			show = config:getShowCharity()
		elseif string.find(cmd.msgIdType or "", "raid") or string.find(msg, "raided") then
			show = config:getShowRaids()
		end

		if show and client.ui then
			client.ui:addMessage(">> [NOTIF] ", ">> [NOTIF] " .. msg, nil)
		end
	end

	function TwitchClient:getSkinForUser(user)
		if not self.userSkins[user] then
			local colors = config:getMessageColors()
			local skin = self.ui.skinFactory:getSkin()
			local color = config:rgbToHex(colors[self.nextUserIndex])

			skin.skinData.states.released[2].text.color = color
			skin.skinData.states.released[2].text.fontSize = config:getFontSize()

			self.userSkins[user] = skin
			self.nextUserIndex = self.nextUserIndex + 1
			if self.nextUserIndex > #colors then 
				self.nextUserIndex = 1
			end
		end
		return self.userSkins[user]
	end

	function TwitchClient:canLogin()
		local auth = config:getAuthInfo()
		return config:isEnabled() and
			auth.username and auth.username ~= "" and
			auth.accessToken and auth.accessToken ~= ""
	end

	function TwitchClient:addViewer(user)
		local auth = config:getAuthInfo()
		if user == auth.username then return end
		if not table.contains(self.userNames, user) then
			table.insert(self.userNames, user)
			client:updateTitle()
		end
	end

	function TwitchClient:removeViewer(user)
		table.removeValue(self.userNames, user)
		client:updateTitle()
	end

	function TwitchClient.onUISendMessage(args)
		local msg = args.message
		if msg:lower() == "/clear" then
			client.ui:clearChat()
			client.ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Chat cleared locally.", nil)
			client:logChat("SYSTEM", "Chat cleared locally.")
			return
		end

		local auth = config:getAuthInfo()
		client.server:send("PRIVMSG #" .. auth.username .. " :" .. msg)
		client:logChat("SENT", auth.username .. ": " .. msg)

		local skin = client:getSkinForUser(auth.username)
		local prefix = (config:getShowTimestamps() and client:getTimeStamp() .. " " or "") ..
					   (config:getShowUserTags() and "[MOD] " or "") ..
					   auth.username .. ": "
		client.ui:addMessage(prefix, prefix .. msg, skin)
	end

	function TwitchClient.onUIPositionChanged(args)
		config:setPosition({x = args.x, y = args.y})
	end

	function TwitchClient.onUserJoin(cmd)
		client:addViewer(cmd.displayName)
		client:logChat("RECEIVE", cmd.displayName .. " joined")
	end

	function TwitchClient.onUserPart(cmd)
		client:removeViewer(cmd.displayName)
		client:logChat("RECEIVE", cmd.displayName .. " left")
	end

	function TwitchClient.onUserMessage(cmd)
		client:addViewer(cmd.displayName)
		local skin = client:getSkinForUser(cmd.displayName)

		local timestamp = config:getShowTimestamps() and client:getTimeStamp() .. " " or ""
		local tag = ""
		if config:getShowUserTags() then
			if cmd.isStaff then tag = "[STAFF] "
			elseif cmd.isModerator then tag = "[MOD] "
			elseif cmd.isVIP then tag = "[VIP] "
			elseif cmd.isSubscriber then tag = "[SUB] " end
		end

		local prefix = timestamp .. tag .. cmd.displayName .. ": "
		client.ui:addMessage(prefix, prefix .. cmd.param2, skin, cmd.msgId)
		client:logChat("RECEIVE", cmd.displayName .. ": " .. cmd.param2)
	end

	function TwitchClient:updateTitle()
		if config:getShowViewerCount() then
			client.ui:setTitle(#client.userNames)
		else
			client.ui:setTitle(0)
		end
	end

	function TwitchClient:checkViewerCountTimer()
		local now = os.time()
		if now - self.lastViewerUpdate >= 30 then
			self:updateTitle()
			self.lastViewerUpdate = now
		end
	end

	function TwitchClient:connect()
		local auth = config:getAuthInfo()
		self.server:connect(auth)
	end

	function TwitchClient:reconnect()
		self.server:reset()
		self:connect()
	end

	function TwitchClient:receive()
		local err = self.server:receive()
		if err and err ~= "timeout" and err == "closed" and config:isEnabled() then
			tracer:warn("Connection closed, attempting reconnect...")
			self:reconnect()
		end
	end

	function TwitchClient:getTimeStamp()
		local t = os.date('*t')
		return string.format("%02i:%02i:%02i", t.hour, t.min, t.sec)
	end

	local callbacks = {
		onSimulationFrame = function()
			local status, innerErr = pcall(function()
				if client == nil then
					tracer:info("Creating client.")
					client = TwitchClient:new()

					if not client:canLogin() then
						tracer:warn("Twitch2DCS disabled or missing credentials.")
						return
					end

					client:connect()
				end

				local fontSize = config:getFontSize()
				if fontSize ~= lastFontSize then
					client.ui:setFontSize(fontSize)
					lastFontSize = fontSize
				end

				local lock = config:getLockUIPosition()
				if lock ~= lastLockUIPosition then
					client.ui.lockUIPosition = lock
					lastLockUIPosition = lock
					client.ui:updateCursor()
				end

				if client.ui then
					client.ui:checkSettingChanges()
					client.ui:checkInactivity()
				end

				if client:canLogin() then
					client:receive()
					client:checkViewerCountTimer()
				end
			end)

			if innerErr then
				net.log("Twitch2DCS error: " .. innerErr)
				MsgWindow.warning(innerErr, "Twitch2DCS"):show()
			end
		end
	}

	DCS.setUserCallbacks(callbacks)
	tracer:info("Loaded.")
	net.log("Twitch2DCS loaded.")
end)

if err then
	net.log("Twitch2DCS failed to load: " .. err)
	MsgWindow.warning(err, "Twitch2DCS Failure"):show()
end