local status, err = pcall(function()

	local base = _G

	package.path = package.path .. ";.\\LuaSocket\\?.lua;" .. '.\\Scripts\\?.lua;' .. '.\\Scripts\\UI\\?.lua;' .. lfs.writedir() .. 'Scripts\\?.lua;'
	package.cpath = package.cpath .. ";.\\LuaSocket\\?.dll;"

	local os = base.os
	local require = base.require
	local tostring = base.tostring

	local net = require("net")
	local MsgWindow = require("MsgWindow")
	local lfs = require("lfs")

	local Config = require("twitch.config")
	local tracer = require("twitch.tracer")
	local Session = require("twitch.session")
	local TwitchClient = require("twitch.client")

	local client = nil
	local config = Config:new()
	local session = Session:new(config, tracer)

	local lastSettingCheckTime = os.time()	-- Only returns whole seconds
	local shownErrors = {}

	local callbacks = {
		onSimulationFrame = function()
			local status, innerErr = pcall(function()
				if client == nil then
					tracer:info("Creating client.")
					client = TwitchClient:new(config, session, tracer)
					session:setClient(client)

					if not session:initLoginCache() then
						tracer:warn("Twitch2DCS disabled or missing credentials.")
						return
					end

					client:connect()
				end

				local now = os.time()

				if now - lastSettingCheckTime >= 1 then
					lastSettingCheckTime = now

					if client.ui then
						client.ui:checkSettingChanges()
						client.ui:checkInactivity()
					end

					session:tick(now)
				end

				if session:shouldReceive() then
					client:receive()
				end
			end)

			if innerErr then
				local errStr = tostring(innerErr)
				net.log("Twitch2DCS error: " .. errStr)

				if not shownErrors[errStr] then
					shownErrors[errStr] = true
					MsgWindow.warning(errStr, "Twitch2DCS"):show()
				end
			end
		end
	}

	DCS.setUserCallbacks(callbacks)
	tracer:info("Loaded.")
	net.log("Twitch2DCS loaded.")

end)

if err then
	net.log("Twitch2DCS failed to load: " .. tostring(err))
	MsgWindow.warning(tostring(err), "Twitch2DCS Failure"):show()
end