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

	local function tableContains(t, value)
		for _, v in ipairs(t) do
			if v == value then return true end
		end
		return false
	end

	local function tableRemoveValue(t, value)
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
		userNames = {},
		chatLog = nil,
		lastViewerUpdate = 0,
		broadcasterColor = nil,
	}

	local TwitchClient_mt = { __index = TwitchClient }
	local client = nil
	local config = Config:new()

	local lastLockUIPosition = config:getLockUIPosition()
	local lastFontSize = config:getFontSize()
	local lastColorMode = config:getColorMode()

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
		if not self.chatLog then return end

		local ts = self:getTimeStamp()
		local dir = (direction == "SENT" and "SENT") or
					(direction == "RECEIVE" and "RCVD") or direction

		self.chatLog:write(string.format("[%s] %s | %s\r\n", ts, dir, line))
		self.chatLog:flush()
	end

	function TwitchClient:setupCommandHandlers()
		tracer:info("Setting up command handlers.")

		self.server:addCommandHandler("PRIVMSG", self.onUserMessage)
		self.server:addCommandHandler("JOIN", self.onUserJoin)
		self.server:addCommandHandler("PART", self.onUserPart)
		self.server:addCommandHandler("CLEARCHAT", self.onClearChat)
		self.server:addCommandHandler("CLEARMSG", self.onClearMsg)
		self.server:addCommandHandler("USERNOTICE", self.onUserNotice)
		self.server:addCommandHandler("GLOBALUSERSTATE", self.onGlobalUserState)
		self.server:addCommandHandler("USERSTATE", self.onUserState)

		self.ui:setCallbacks(self)
	end

	function TwitchClient.onGlobalUserState(cmd)
		if cmd.color and cmd.color ~= "" then
			client.broadcasterColor = cmd.color
		end
	end

	function TwitchClient.onUserState(cmd)
		if cmd.color and cmd.color ~= "" then
			client.broadcasterColor = cmd.color
		end
	end

	function TwitchClient.onClearChat()
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
		local msgIdType = cmd.msgIdType or ""

		local show = false

		if string.find(msgIdType, "follow") or string.find(msg, "followed") then
			show = config:getShowFollows()
		elseif string.find(msgIdType, "sub") or string.find(msg, "subscribed") then
			show = config:getShowSubscribers()
		elseif string.find(msgIdType, "cheer") or cmd.bits then
			show = config:getShowBits()
		elseif string.find(msgIdType, "charity") or string.find(msg, "charity") then
			show = config:getShowCharity()
		elseif string.find(msgIdType, "raid") or string.find(msg, "raided") then
			show = config:getShowRaids()
		end

		if show and client.ui then
			client.ui:addMessage(">> [NOTIF] ", ">> [NOTIF] " .. msg, nil)
		end
	end

	function TwitchClient:getSkinForUser(user, twitchColor)
		if self.userSkins[user] then
			return self.userSkins[user]
		end

		local skin = self.ui.skinFactory:getSkin()
		local colorHex

		local colorMode = config:getColorMode()

		if colorMode == "twitch" and twitchColor and twitchColor ~= "" and string.sub(twitchColor, 1, 1) == "#" then
			local hex = string.sub(twitchColor, 2)
			colorHex = "0x" .. hex .. "ff"
		else
			local colors = config:getMessageColors()
			local randomIndex = math.random(1, #colors)
			colorHex = config:rgbToHex(colors[randomIndex])
		end

		skin.skinData.states.released[2].text.color = colorHex
		skin.skinData.states.released[2].text.fontSize = config:getFontSize()

		self.userSkins[user] = skin
		return skin
	end

	function TwitchClient:canLogin()
		local auth = config:getAuthInfo()
		return config:isEnabled()
			and auth.username and auth.username ~= ""
			and auth.accessToken and auth.accessToken ~= ""
	end

	function TwitchClient:addViewer(user)
		local auth = config:getAuthInfo()
		if user == auth.username then return end

		if not tableContains(self.userNames, user) then
			table.insert(self.userNames, user)
			self:updateTitle()
		end
	end

	function TwitchClient:removeViewer(user)
		tableRemoveValue(self.userNames, user)
		self:updateTitle()
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

		local skin = client:getSkinForUser(auth.username, client.broadcasterColor)
		local timestamp = config:getShowTimestamps() and client:getTimeStamp() .. " " or ""
		local tag = config:getShowUserTags() and "[MOD] " or ""

		local prefix = timestamp .. tag .. auth.username .. ": "
		client.ui:addMessage(prefix, prefix .. msg, skin)
	end

	function TwitchClient.onUIPositionChanged(args)
		config:setPosition({ x = args.x, y = args.y })
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

		local skin = client:getSkinForUser(cmd.displayName, cmd.color)
		local timestamp = config:getShowTimestamps() and client:getTimeStamp() .. " " or ""
		local tag = ""

		if config:getShowUserTags() then
			if cmd.isStaff then tag = "[STAFF] "
			elseif cmd.isModerator then tag = "[MOD] "
			elseif cmd.isVIP then tag = "[VIP] "
			elseif cmd.isSubscriber then tag = "[SUB] "
			end
		end

		local messageText = cmd.param2 or ""

		if cmd.bits and tonumber(cmd.bits) and config:getShowBits() then
			local bitsAmount = tonumber(cmd.bits)
			local bitWord = (bitsAmount == 1) and "bit" or "bits"
			local cheerNote = string.format("[Cheered with %d %s]", bitsAmount, bitWord)

			messageText = messageText:gsub("^[Cc]heer%d+%s*", "")
			messageText = messageText:gsub("%s*[Cc]heer%d+%s*", " ")
			messageText = messageText:gsub("^%s+", "")
			messageText = messageText:gsub("%s+$", "")

			if messageText == "" then
				messageText = cheerNote
			else
				messageText = cheerNote .. " " .. messageText
			end
		end

		local prefix = timestamp .. tag .. cmd.displayName .. ": "
		client.ui:addMessage(prefix, prefix .. messageText, skin, cmd.msgId)
		client:logChat("RECEIVE", cmd.displayName .. ": " .. messageText)
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

				local colorMode = config:getColorMode()
				if colorMode ~= lastColorMode then
					lastColorMode = colorMode
					if client then
						client.userSkins = {}
						if client.ui then
							client.ui:updateListM()
						end
					end
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