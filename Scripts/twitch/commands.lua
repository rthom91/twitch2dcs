local base = _G

module("twitch.commands")

local string = base.string
local table = base.table
local pairs = base.pairs

local Commands = {}

function Commands.handle(client, msg)
	if not msg or msg == "" then
		return false
	end

	local lower = msg:lower()
	local session = client.session
	local ui = client.ui

	if lower == "/clear" then
		client.pendingClearRequest = false
		client.clearRequestTime = nil
		ui:clearChat()
		ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Chat cleared locally.", nil)
		client:logChat("SYSTEM", "Chat cleared locally.")
		return true
	end

	if lower == "/yes" then
		if client.pendingClearRequest then
			client.pendingClearRequest = false
			client.clearRequestTime = nil
			ui:clearChat()
			ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Chat cleared.", nil)
			client:logChat("SYSTEM", "Chat clear request accepted.")
		else
			ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] No pending clear request.", nil)
		end
		return true
	end

	if lower == "/no" then
		if client.pendingClearRequest then
			client.pendingClearRequest = false
			client.clearRequestTime = nil
			ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Clear request denied.", nil)
			client:logChat("SYSTEM", "Chat clear request denied.")
		else
			ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] No pending clear request.", nil)
		end
		return true
	end

	if lower == "/listmods" then
		local mods = {}

		if client.activeMods then
			for login, displayName in pairs(client.activeMods) do
				table.insert(mods, displayName or login)
			end
		end

		table.sort(mods, function(a, b)
			return string.lower(a) < string.lower(b)
		end)

		local list
		if #mods == 0 then
			list = "none"
		else
			list = table.concat(mods, ", ")
		end

		ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Active moderators (" .. #mods .. "): " .. list, nil)
		return true
	end

	if lower == "/disconnect" then
		session:onManualDisconnect()
		if client.server then
			client.server:reset()
		end
		client.pendingClearRequest = false
		client.clearRequestTime = nil
		ui:setTitle(0)
		ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Connection disabled.", nil)
		return true
	end

	if lower == "/connect" or lower == "/reconnect" then
		if client.server and client.server.isConnected and session:isVerified() then
			ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Connection already established.", nil)
			return true
		end

		session:onManualConnect()
		ui:addMessage(">> [SYSTEM] ", ">> [SYSTEM] Connecting to Twitch.", nil)
		client:connect()
		return true
	end

	return false
end

return Commands