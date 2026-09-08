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

function Config:rgbToHex(rgb)
	local r = math.floor(math.max(0, math.min(1, rgb.r or 0)) * 255)
	local g = math.floor(math.max(0, math.min(1, rgb.g or 0)) * 255)
	local b = math.floor(math.max(0, math.min(1, rgb.b or 0)) * 255)
	return string.format("0x%02X%02X%02XFF", r, g, b)
end

function Config:getColorMode()
	return self:getOption("colorSelection") or "twitch"
end

function Config:getMessageColors()
	return {
		{ r = 0.95, g = 0.40, b = 0.40 }, -- #F26666 Soft Red
		{ r = 0.98, g = 0.60, b = 0.30 }, -- #FA9933 Warm Orange
		{ r = 0.95, g = 0.80, b = 0.25 }, -- #F2CC40 Gold
		{ r = 0.45, g = 0.85, b = 0.40 }, -- #73D966 Soft Green
		{ r = 0.25, g = 0.80, b = 0.70 }, -- #40CCB3 Teal
		{ r = 0.30, g = 0.70, b = 0.95 }, -- #4DB3F2 Sky Blue
		{ r = 0.40, g = 0.50, b = 0.95 }, -- #6680F2 Blue
		{ r = 0.65, g = 0.40, b = 0.95 }, -- #A666F2 Purple
		{ r = 0.95, g = 0.40, b = 0.70 }, -- #F266B3 Pink
		{ r = 0.90, g = 0.50, b = 0.60 }, -- #E68099 Dusty Rose
		{ r = 0.90, g = 0.70, b = 0.35 }, -- #E6B359 Amber
		{ r = 0.50, g = 0.85, b = 0.55 }, -- #80D98C Pale Green
		{ r = 0.30, g = 0.85, b = 0.85 }, -- #4DD9D9 Cyan
		{ r = 0.75, g = 0.45, b = 0.90 }, -- #BF73E6 Lavender
		{ r = 0.95, g = 0.45, b = 0.55 }, -- #F2738C Coral Pink
		{ r = 0.85, g = 0.55, b = 0.40 }, -- #D98C66 Terracotta
		{ r = 0.40, g = 0.75, b = 0.60 }, -- #66BF99 Sea Green
		{ r = 0.80, g = 0.45, b = 0.80 }, -- #CC73CC Magenta
		{ r = 0.55, g = 0.80, b = 0.45 }, -- #8CCC73 Moss
		{ r = 0.45, g = 0.55, b = 0.90 }, -- #738CE6 Steel Blue
		{ r = 0.85, g = 0.75, b = 0.40 }, -- #D9BF66 Khaki
		{ r = 0.55, g = 0.40, b = 0.90 }, -- #8C66E6 Indigo
		{ r = 0.35, g = 0.85, b = 0.65 }, -- #59D9A6 Mint
		{ r = 0.85, g = 0.55, b = 0.45 }, -- #D98C73 Soft Brown
		{ r = 0.70, g = 0.55, b = 0.90 }, -- #B38CE6 Soft Violet
		{ r = 1.00, g = 0.55, b = 0.45 }, -- #FF8C73 Coral
		{ r = 0.50, g = 0.45, b = 0.95 }, -- #8073F2 Periwinkle
		{ r = 1.00, g = 0.75, b = 0.55 }, -- #FFBF8C Peach
		{ r = 0.65, g = 0.75, b = 0.35 }, -- #A6BF59 Olive
		{ r = 0.60, g = 0.50, b = 0.95 }, -- #9980F2 Soft Indigo
	}
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
		accessToken = self:getOption("oauth"),
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