local base = _G

module("twitch.handlers")

local os = base.os
local string = base.string
local tonumber = base.tonumber

local Handlers = {}

function Handlers.register(server, client, config, session, tracer)
	server:addCommandHandler("PRIVMSG", function(cmd)
		client:addViewer(cmd.displayName, cmd.userId, cmd.user)

		if cmd.isModerator and not cmd.isStaff then
			local login = (cmd.user or ""):lower()
			if login ~= "" and login ~= (client.username or ""):lower() then
				client:addModerator(cmd.user, cmd.displayName)
			end
		end

		local skin = client:getSkinForUser(cmd.user, cmd.color)
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

		if cmd.user and cmd.user ~= "" then
			local expected = (client.username or ""):lower()
			local login = cmd.user:lower()

			if expected ~= "" and login == expected then
				client.authenticatedLogin = login

				if client.session then
					client.session:markVerified()
				end
			elseif not client.authenticatedLogin then
				client.authenticatedLogin = login
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
			client.ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Moderator requested to clear chat. Type /yes or /no", nil)
		end
	end)

	server:addCommandHandler("CLEARMSG", function(cmd)
		if cmd.targetMsgId and client.ui then
			client.ui:removeMessage(cmd.targetMsgId)
		end
	end)

	server:addCommandHandler("USERNOTICE", function(cmd)
		if not cmd.systemMsg then return end

		local msg = cmd.systemMsg:gsub("\\s", " ")
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

			client._subgiftSuppress[gifterKey] = count

			local finalMsg
			if count <= 1 then
				finalMsg = gifter .. " has gifted a sub to the community."
			else
				finalMsg = gifter .. " has gifted " .. count .. " subs to the community."
			end

			client.ui:addMessage(">> [NOTIF] ", ">> [NOTIF] " .. finalMsg, nil)
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

			local recipient = cmd.recipientDisplayName
			if not recipient or recipient == "" then
				recipient = cmd.recipientName
			end

			local finalMsg
			if recipient and recipient ~= "" then
				finalMsg = gifter .. " has gifted a sub to " .. recipient .. "."
			else
				finalMsg = gifter .. " has gifted a sub."
			end

			client.ui:addMessage(">> [NOTIF] ", ">> [NOTIF] " .. finalMsg, nil)
			return
		end

		client.ui:addMessage(">> [NOTIF] ", ">> [NOTIF] " .. msg, nil)
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

		if client.session then
			client.session:markVerified()
		end
	end)

	server:addCommandHandler("USERSTATE", function(cmd)
		if cmd.color and cmd.color ~= "" then
			client.broadcasterColor = cmd.color
		end

		if cmd.displayName and cmd.displayName ~= "" then
			if client.username and (
				(cmd.user and cmd.user:lower() == client.username) or
				(cmd.displayName:lower() == client.username)
			) then
				client.authenticatedDisplayName = cmd.displayName
			end
		end

		if client.username and (
			(cmd.user and cmd.user:lower() == client.username) or
			(cmd.displayName and cmd.displayName:lower() == client.username)
		) then
			client.isStaff = cmd.isStaff or client.isStaff
			client.isModerator = cmd.isModerator or client.isModerator
			client.isVIP = cmd.isVIP or client.isVIP
			client.isSubscriber = cmd.isSubscriber or client.isSubscriber
		end
	end)

	server:addCommandHandler("NOTICE", function(cmd)
		local msg = (cmd.param2 or ""):lower()
		if string.find(msg, "login authentication failed") or string.find(msg, "authentication failed") then
			if client.server then
				client.server:reset()
			end
			session:onAuthFailed()
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