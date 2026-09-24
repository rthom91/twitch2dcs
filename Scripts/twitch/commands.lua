local base = _G

module("twitch.commands")

local os = base.os
local require = base.require
local string = base.string
local table = base.table
local pairs = base.pairs

local Format = require("twitch.format")

local UPDATE_URL = "https://github.com/rthom91/twitch2dcs/releases/latest"

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
		ui:addMessage(Format.systemMessage("Chat cleared locally."))
		client:logChat("SYSTEM", "Chat cleared locally.")
		return true
	end

	if lower == "/yes" then
		if client.pendingClearRequest then
			client.pendingClearRequest = false
			client.clearRequestTime = nil
			ui:clearChat()
			ui:addMessage(Format.systemMessage("Chat cleared."))
			client:logChat("SYSTEM", "Chat clear request accepted.")
		else
			ui:addMessage(Format.systemMessage("No pending clear request."))
		end
		return true
	end

	if lower == "/no" then
		if client.pendingClearRequest then
			client.pendingClearRequest = false
			client.clearRequestTime = nil
			ui:addMessage(Format.systemMessage("Clear request denied."))
			client:logChat("SYSTEM", "Chat clear request denied.")
		else
			ui:addMessage(Format.systemMessage("No pending clear request."))
		end
		return true
	end

	if lower == "/listmods" then
		local mods = {}

		if client.roster and client.roster.listMods then
			mods = client.roster:listMods()
		end

		local list
		if #mods == 0 then
			list = "none"
		else
			list = table.concat(mods, ", ")
		end

		ui:addMessage(Format.systemMessage("Active moderators (" .. #mods .. "): " .. list))
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
		ui:addMessage(Format.systemMessage("Connection disabled."))
		return true
	end

	if lower == "/connect" or lower == "/reconnect" then
		if client.server and client.server.isConnected and session:isVerified() then
			ui:addMessage(Format.systemMessage("Connection already established."))
			return true
		end

		session:onManualConnect()
		ui:addMessage(Format.systemMessage("Connecting to Twitch."))
		client:connect()
		return true
	end

	if lower == "/update" then
		local opened = false

		if os.execute then
			os.execute('cmd /C start "" "' .. UPDATE_URL .. '"')
			opened = true
		end

		if opened then
			ui:addMessage(Format.systemMessage("Opening download page."))
		else
			ui:addMessage(Format.systemMessage("Could not open browser."))
		end

		client:logChat("SYSTEM", "Update page requested.")
		return true
	end

	return false
end

return Commands
