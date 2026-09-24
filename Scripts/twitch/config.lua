local base = _G

module("twitch.config")

local require = base.require
local string = base.string
local table = base.table
local math = base.math
local type = base.type

local OptionsData = require("Options.Data")
local lfs = require("lfs")
local Tools = require("tools")
local U = require("me_utilities")

Config = {}
local Config_mt = { __index = Config }

local currentPosition = { x = 0, y = 0 }
local POSITION_FILE = lfs.writedir() .. "Config/Twitch2DCS_Position.lua"

local function loadPosition()
	local tbl = Tools.safeDoFile(POSITION_FILE, false)
	if tbl and tbl.chatPos and tbl.chatPos.x and tbl.chatPos.y then
		currentPosition.x = tbl.chatPos.x
		currentPosition.y = tbl.chatPos.y
	end
end

local function savePosition()
	U.saveInFile(currentPosition, "chatPos", POSITION_FILE)
end

function Config:new()
	local config = base.setmetatable({}, Config_mt)
	loadPosition()
	return config
end

function Config:getOption(name)
	return OptionsData.getPlugin("Twitch2DCS", name)
end

function Config:setOption(name, value)
	OptionsData.setPlugin("Twitch2DCS", name, value)
	OptionsData.saveChanges()
end

function Config:getColorMode()
	return self:getOption("colorSelection") or "twitch"
end

function Config:formatAccessToken(token)
	token = string.gsub(token or "", "^%s*(.-)%s*$", "%1")
	if token == "" then
		return ""
	end
	if not string.find(token, "^oauth:") then
		return "oauth:" .. token
	end
	return token
end

function Config:getShowUpdates()
	local value = self:getOption("showUpdates")
	if value == nil then
		return true
	end
	return value
end

-- Main
function Config:isEnabled() return self:getOption("isEnabled") end
function Config:getFontSize() return self:getOption("fontSize") end
function Config:getLockUIPosition() return self:getOption("lockUIPosition") end
function Config:getHideShowHotkey() return self:getOption("hideShowHotkey") end
function Config:getHideInactiveTimer() return self:getOption("hideInactiveTimer") or 0 end

-- Display
function Config:getShowUserTags() return self:getOption("showUserTags") end
function Config:getShowTimestamps() return self:getOption("showTimestamps") end
function Config:getShowViewerCount() return self:getOption("showViewerCount") end

-- Notifs
function Config:getShowRaids() return self:getOption("showRaids") end
function Config:getShowFollows() return self:getOption("showFollows") end
function Config:getShowSubscribers() return self:getOption("showSubscribers") end
function Config:getShowBits() return self:getOption("showBits") end
function Config:getShowCharity() return self:getOption("showCharity") end

-- Position
function Config:getPosition()
	return { x = currentPosition.x, y = currentPosition.y }
end

function Config:setPosition(value)
	if type(value) == "table" and value.x ~= nil and value.y ~= nil then
		currentPosition.x = value.x
		currentPosition.y = value.y
		savePosition()
	end
end

-- Connection
function Config:getAuthInfo()
	return {
		username = self:getOption("username"),
		accessToken = self:formatAccessToken(self:getOption("oauth")),
		hostAddress = "irc.chat.twitch.tv",
		port = 6667,
		timeout = 0,
		caps = {
			"twitch.tv/commands",
			"twitch.tv/membership",
			"twitch.tv/tags"
		}
	}
end

return Config