local base = _G

module("twitch.tracer")

local os = base.os
local io = base.io
local require = base.require
local string = base.string
local net = base.net
local lfs = require("lfs")

local Tracer = {}
local Tracer_mt = { __index = Tracer }
local _instance = nil

local function getInstance()
	if not _instance then
		local logDir = lfs.writedir() .. "Logs\\"
		local filename = "Twitch2DCS-mod-log.txt"
		local fullPath = logDir .. filename

		_instance = base.setmetatable({}, Tracer_mt)

		_instance.file = io.open(fullPath, "w")

		if _instance.file then
			_instance.file:write("=== Twitch2DCS Mod Log Started " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n\n")
			_instance.file:flush()
		end
	end
	return _instance
end

function Tracer:info(str)
	self:write("INFO", str or "")
end

function Tracer:warn(str)
	self:write("WARN", str or "")
end

function Tracer:error(str)
	self:write("ERROR", str or "")
end

function Tracer:write(level, message)
	if not self.file or not message then return end

	local timestamp = os.date("%H:%M:%S")
	self.file:write(string.format("[%s] %-4s | %s\r\n", timestamp, level, message))
	self.file:flush()
end

return getInstance()