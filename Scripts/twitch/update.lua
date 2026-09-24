local base = _G

module("twitch.update")

local os = base.os
local io = base.io
local require = base.require
local string = base.string
local tostring = base.tostring
local tonumber = base.tonumber
local pcall = base.pcall

local Format = require("twitch.format")
local lfs = require("lfs")

local CURRENT_VERSION = "2.2.1"
local RELEASES_URL = "https://api.github.com/repos/rthom91/twitch2dcs/releases/latest"
local CHECK_DELAY = 10

local Update = {}
local Update_mt = { __index = Update }

local function parseVersion(s)
	s = string.match(tostring(s or ""), "(%d+[%d%.]*)") or ""
	local a, b, c = string.match(s, "^(%d+)%.?(%d*)%.?(%d*)")
	return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

local function isNewer(remote, localVer)
	local r1, r2, r3 = parseVersion(remote)
	local l1, l2, l3 = parseVersion(localVer)
	if r1 ~= l1 then return r1 > l1 end
	if r2 ~= l2 then return r2 > l2 end
	return r3 > l3
end

local function quote(s)
	return '"' .. string.gsub(tostring(s or ""), '"', "") .. '"'
end

local function outputPath()
	local dir = lfs.writedir() .. "Logs\\"
	if lfs.tempdir then
		dir = lfs.tempdir()
		if string.sub(dir, -1) ~= "\\" and string.sub(dir, -1) ~= "/" then
			dir = dir .. "\\"
		end
	end
	return dir .. "Twitch2DCS-update-check.json"
end

local function readFile(path)
	if not path or not io.open then
		return nil
	end
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local body = f:read("*a") or ""
	f:close()
	return body
end

local function deleteFile(path)
	if not path then
		return
	end
	pcall(function()
		if os.remove then
			os.remove(path)
		end
	end)
end

local function extractTag(body)
	if not body or body == "" then
		return nil
	end
	local tag = string.match(body, '"tag_name"%s*:%s*"([^"]+)"')
	if tag and tag ~= "" then
		return tag
	end
	return nil
end

local function fetchViaPopen()
	local popen = io and io.popen
	if not popen then
		return nil
	end

	local cmd = "curl.exe -sS --max-time 3 -A Twitch2DCS " .. quote(RELEASES_URL)
	local pipe = popen(cmd)
	if not pipe then
		return nil
	end
	local body = pipe:read("*a") or ""
	pipe:close()
	return extractTag(body)
end

local function fetchViaExecute()
	if not os.execute then
		return nil
	end

	local path = outputPath()
	deleteFile(path)

	local cmd = "cmd /C curl.exe -sS --max-time 3 -A Twitch2DCS "
		.. quote(RELEASES_URL)
		.. " > "
		.. quote(path)
		.. " 2>nul"

	os.execute(cmd)

	local body = readFile(path)
	deleteFile(path)
	return extractTag(body)
end

local function fetchLatestTag()
	local tag = fetchViaPopen()
	if tag then
		return tag
	end
	return fetchViaExecute()
end

function Update:new(client, tracer)
	local self = base.setmetatable({}, Update_mt)
	self.client = client
	self.tracer = tracer
	self.startedAt = os.time()
	self.done = false
	return self
end

function Update:tick(now)
	if self.done then
		return
	end
	if now - self.startedAt < CHECK_DELAY then
		return
	end
	self.done = true

	local config = self.client and self.client.config
	if config and config.getShowUpdates and not config:getShowUpdates() then
		if self.tracer then
			self.tracer:info("Update check disabled.")
		end
		return
	end

	if not os.execute and not (io and io.popen) then
		if self.tracer then
			self.tracer:warn("Update check skipped: DCS blocked process execution.")
		end
		return
	end

	local ok, tagOrErr = pcall(fetchLatestTag)
	if not ok then
		if self.tracer then
			self.tracer:warn("Update check failed: " .. tostring(tagOrErr))
		end
		return
	end

	local tag = tagOrErr
	if not tag then
		if self.tracer then
			self.tracer:info("Update check: no tag (offline or curl missing).")
		end
		return
	end

	if not isNewer(tag, CURRENT_VERSION) then
		if self.tracer then
			self.tracer:info("Update check: up to date (" .. CURRENT_VERSION .. ").")
		end
		return
	end

	local displayTag = string.gsub(tag, "^[vV]", "")

	if self.tracer then
		self.tracer:info("Update available: " .. displayTag .. " (installed " .. CURRENT_VERSION .. ")")
	end

	local ui = self.client and self.client.ui
	if ui and ui.addMessage then
		ui:addMessage(Format.systemMessage("Update available: " .. displayTag))
	end
end

return Update
