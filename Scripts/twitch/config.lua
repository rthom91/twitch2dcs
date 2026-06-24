local base = _G

module("twitch.config")

local require = base.require
local table = base.table
local string = base.string
local math = base.math
local type = base.type

local OptionsData = require("Options.Data")

Config = {}
local Config_mt = { __index = Config }

local currentPosition = { x = 0, y = 0 }

function Config:new()
	local config = base.setmetatable({}, Config_mt)
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
		{ r = 0.95, g = 0.35, b = 0.35 }, -- #F25A5A Soft Red
		{ r = 0.98, g = 0.55, b = 0.30 }, -- #F98C4D Warm Orange
		{ r = 0.95, g = 0.78, b = 0.25 }, -- #F2C640 Muted Gold
		{ r = 0.45, g = 0.85, b = 0.45 }, -- #73D973 Soft Green
		{ r = 0.25, g = 0.80, b = 0.75 }, -- #40CCC0 Teal
		{ r = 0.35, g = 0.75, b = 0.95 }, -- #59BFF2 Sky Blue
		{ r = 0.40, g = 0.65, b = 0.95 }, -- #66A6F2 Muted Blue
		{ r = 0.65, g = 0.45, b = 0.95 }, -- #A673F2 Soft Purple
		{ r = 0.92, g = 0.40, b = 0.70 }, -- #EB66B2 Muted Pink
		{ r = 0.88, g = 0.50, b = 0.65 }, -- #E080A6 Dusty Rose
		{ r = 0.90, g = 0.65, b = 0.35 }, -- #E6A65A Soft Amber
		{ r = 0.55, g = 0.85, b = 0.55 }, -- #8CD98C Pale Green
		{ r = 0.30, g = 0.82, b = 0.82 }, -- #4DD1D1 Soft Cyan
		{ r = 0.70, g = 0.45, b = 0.90 }, -- #B273E6 Lavender Purple
		{ r = 0.88, g = 0.30, b = 0.55 }, -- #E04C8C Deep Pink
		{ r = 0.85, g = 0.55, b = 0.40 }, -- #D98C66 Terracotta
		{ r = 0.40, g = 0.75, b = 0.65 }, -- #66BFA6 Sea Green
		{ r = 0.75, g = 0.45, b = 0.75 }, -- #BF73BF Muted Magenta
		{ r = 0.55, g = 0.80, b = 0.50 }, -- #8CCC80 Moss Green
		{ r = 0.45, g = 0.60, b = 0.90 }, -- #7399E6 Steel Blue
		{ r = 0.85, g = 0.70, b = 0.40 }, -- #D9B366 Khaki Gold
		{ r = 0.60, g = 0.40, b = 0.85 }, -- #9966D9 Deep Lavender
		{ r = 0.35, g = 0.85, b = 0.70 }, -- #59D9B3 Mint
		{ r = 0.80, g = 0.50, b = 0.35 }, -- #CC8059 Warm Brown
		{ r = 0.65, g = 0.55, b = 0.85 }, -- #A58CD9 Soft Violet
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