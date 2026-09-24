local base = _G

module("twitch.handlers")

local os = base.os
local require = base.require
local string = base.string
local tonumber = base.tonumber

local Format = require("twitch.format")

local Handlers = {}

local function isAuthFailureNotice(cmd)
	local msg = (cmd.param2 or ""):lower()
	local msgId = (cmd.msgIdType or ""):lower()

	if msgId == "login_unsuccessful"
		or msgId == "login_failure"
		or msgId == "authentication_failed"
		or msgId:find("login", 1, true) then
		return true
	end

	if string.find(msg, "login authentication failed", 1, true)
		or string.find(msg, "improperly formatted auth", 1, true)
		or string.find(msg, "authentication failed", 1, true) then
		return true
	end

	return false
end

local function setAuthenticatedLogin(client, login)
	login = (login or ""):lower()
	if login == "" or login == "tmi.twitch.tv" then
		return false
	end

	client.authenticatedLogin = login
	return true
end

function Handlers.register(server, client, config, session, tracer)
	server:addCommandHandler("001", function(cmd)
		setAuthenticatedLogin(client, cmd.param1)
	end)

	server:addCommandHandler("PRIVMSG", function(cmd)
		client:addViewer(cmd.displayName, cmd.userId, cmd.user)

		if cmd.isModerator and not cmd.isStaff then
			local login = (cmd.user or ""):lower()
			if login ~= "" and login ~= (client.username or ""):lower() then
				client:addModerator(cmd.user, cmd.displayName)
			end
		end

		local skin = client:getSkinForUser(cmd.user, cmd.color)
		local timestamp = config:getShowTimestamps() and client:getTimeStamp() or ""
		local prefix = Format.userPrefix(config, timestamp, cmd, cmd.displayName)
		local messageText = Format.rewriteCheerMessage(cmd.param2 or "", cmd.bits, config:getShowBits())

		client.ui:addMessage(prefix, prefix .. messageText, skin, cmd.msgId, cmd.user)
		client:logChat("RECEIVE", cmd.displayName .. ": " .. messageText)
	end)

	server:addCommandHandler("JOIN", function(cmd)
		client:addViewer(cmd.displayName, cmd.userId, cmd.user)

		if cmd.isModerator and not cmd.isStaff then
			local login = (cmd.user or ""):lower()
			if login ~= "" and login ~= (client.username or ""):lower() then
				client:addModerator(cmd.user, cmd.displayName)
			end
		end

		client:logChat("RECEIVE", (cmd.displayName or cmd.user) .. " joined.")
	end)

	server:addCommandHandler("PART", function(cmd)
		client:removeViewer(cmd.displayName, cmd.userId, cmd.user)
		client:removeModerator(cmd.user)
		client:logChat("RECEIVE", (cmd.displayName or cmd.user) .. " left.")
	end)

	server:addCommandHandler("353", function(cmd)
		if not cmd.param2 or cmd.param2 == "" then
			return
		end

		for nick in string.gmatch(cmd.param2, "%S+") do
			client:addViewer(nick, nil, nick, true)
		end
	end)

	server:addCommandHandler("366", function(cmd)
		client:updateTitle()
	end)

	server:addCommandHandler("CLEARCHAT", function(cmd)
		if cmd.param2 and cmd.param2 ~= "" then
			local target = cmd.param2:lower()
			if client.ui then
				client.ui:removeMessagesByUser(target)
			end
			return
		end

		client.pendingClearRequest = true
		client.clearRequestTime = os.time()
		tracer:info("CLEARCHAT received. Awaiting confirmation.")
		client:logChat("SYSTEM", "Moderator requested to clear chat.")

		if client.ui then
			client.ui:addMessage(Format.systemMessage("Moderator requested to clear chat. Type /yes or /no"))
		end
	end)

	server:addCommandHandler("CLEARMSG", function(cmd)
		if cmd.targetMsgId and client.ui then
			client.ui:removeMessage(cmd.targetMsgId)
		end
	end)

	server:addCommandHandler("USERNOTICE", function(cmd)
		if not cmd.systemMsg then return end

		local msg = cmd.systemMsg
		local msgIdType = cmd.msgIdType or ""

		local showMap = {
			["sub"] = config:getShowSubscribers(),
			["resub"] = config:getShowSubscribers(),
			["subgift"] = config:getShowSubscribers(),
			["anonsubgift"] = config:getShowSubscribers(),
			["submysterygift"] = config:getShowSubscribers(),
			["giftpaidupgrade"] = config:getShowSubscribers(),
			["anongiftpaidupgrade"] = config:getShowSubscribers(),
			["primepaidupgrade"] = config:getShowSubscribers(),
			["raid"] = config:getShowRaids(),
			["bits"] = config:getShowBits(),
			["cheer"] = config:getShowBits(),
			["charitydonation"] = config:getShowCharity(),
			["charity"] = config:getShowCharity(),
			["follow"] = config:getShowFollows(),
		}

		local show = showMap[msgIdType]
		if show == nil then
			if msgIdType:find("sub") then
				show = config:getShowSubscribers()
			elseif msgIdType:find("raid") then
				show = config:getShowRaids()
			elseif msgIdType:find("charity") then
				show = config:getShowCharity()
			elseif msgIdType:find("follow") then
				show = config:getShowFollows()
			elseif cmd.bits then
				show = config:getShowBits()
			else
				show = false
			end
		end

		if not show or not client.ui then return end

		client._subgiftSuppress = client._subgiftSuppress or {}

		local gifter = cmd.displayName
		if not gifter or gifter == "" then
			gifter = "Anonymous"
		end
		local gifterKey = gifter:lower()

		if msgIdType == "submysterygift" then
			local count = tonumber(cmd.massGiftCount) or 1

			if count > 3 then
				client._subgiftSuppress[gifterKey] = count
			end

			client.ui:addMessage(Format.notifMessage(Format.mysteryGiftMessage(gifter, count)))
			return
		end

		if msgIdType == "subgift" or msgIdType == "anonsubgift" then
			local remaining = client._subgiftSuppress[gifterKey]

			if remaining and remaining > 0 then
				client._subgiftSuppress[gifterKey] = remaining - 1
				if client._subgiftSuppress[gifterKey] <= 0 then
					client._subgiftSuppress[gifterKey] = nil
				end
				return
			end

			client.ui:addMessage(Format.notifMessage(Format.subGiftMessage(gifter, cmd.recipientDisplayName, cmd.recipientName)))
			return
		end

		client.ui:addMessage(Format.notifMessage(msg))
	end)

	server:addCommandHandler("GLOBALUSERSTATE", function(cmd)
		if cmd.color and cmd.color ~= "" then
			client.broadcasterColor = cmd.color
		end

		if cmd.displayName and cmd.displayName ~= "" then
			client.authenticatedDisplayName = cmd.displayName
		end

		client.isStaff = cmd.isStaff or false
		client.isModerator = cmd.isModerator or false
		client.isVIP = cmd.isVIP or false
		client.isSubscriber = cmd.isSubscriber or false

		if cmd.login and cmd.login ~= "" then
			setAuthenticatedLogin(client, cmd.login)
		end

		if client.session then
			client.session:markVerified()
		end
	end)

	server:addCommandHandler("USERSTATE", function(cmd)
		if cmd.color and cmd.color ~= "" then
			client.broadcasterColor = cmd.color
		end

		local stateLogin = (cmd.login or cmd.user or ""):lower()
		local expected = (client.username or ""):lower()
		local display = (cmd.displayName or ""):lower()
		local isSelf = (expected ~= "" and (
			stateLogin == expected or
			(display ~= "" and display == expected)
		))

		if cmd.displayName and cmd.displayName ~= "" and isSelf then
			client.authenticatedDisplayName = cmd.displayName
		end

		if isSelf then
			if stateLogin ~= "" then
				setAuthenticatedLogin(client, stateLogin)
			end
			client.isStaff = cmd.isStaff or client.isStaff
			client.isModerator = cmd.isModerator or client.isModerator
			client.isVIP = cmd.isVIP or client.isVIP
			client.isSubscriber = cmd.isSubscriber or client.isSubscriber

			if client.session then
				client.session:markVerified()
			end
		end
	end)

	server:addCommandHandler("NOTICE", function(cmd)
		if isAuthFailureNotice(cmd) then
			if client.server then
				client.server:reset()
			end
			session:onAuthFailed()
			return
		end
	end)

	server:addCommandHandler("RECONNECT", function(cmd)
		tracer:warn("Twitch sent RECONNECT.")
		if client and client.session then
			client.session.connectionLostRecovery = true
			client.session.connectionLostAttempts = 0
			client.session.lastConnectionLostAttempt = os.time()
			client.session.credentialsVerified = false
		end
		if client and client.server then
			client.server:reset()
		end
	end)
end

return Handlers
