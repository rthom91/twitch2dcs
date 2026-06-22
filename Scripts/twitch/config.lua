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

function Config:getMessageColors()
	return {
		{ r = 1.000, g = 0.200, b = 0.200 }, -- #FF3333 Bright Red
		{ r = 1.000, g = 0.550, b = 0.000 }, -- #FF8C00 Orange
		{ r = 1.000, g = 0.900, b = 0.000 }, -- #FFE500 Golden Yellow
		{ r = 0.300, g = 1.000, b = 0.300 }, -- #4CFF4C Lime Green
		{ r = 0.000, g = 1.000, b = 0.800 }, -- #00FFCC Turquoise
		{ r = 0.000, g = 0.800, b = 1.000 }, -- #00CCFF Sky Blue
		{ r = 0.200, g = 0.600, b = 1.000 }, -- #3399FF Bright Blue
		{ r = 0.600, g = 0.400, b = 1.000 }, -- #9966FF Purple
		{ r = 1.000, g = 0.300, b = 0.800 }, -- #FF4CCC Hot Pink
		{ r = 1.000, g = 0.400, b = 0.600 }, -- #FF6699 Pink
		{ r = 1.000, g = 0.700, b = 0.000 }, -- #FFB200 Amber
		{ r = 0.400, g = 1.000, b = 0.400 }, -- #66FF66 Light Lime
		{ r = 0.000, g = 1.000, b = 1.000 }, -- #00FFFF Pure Cyan
		{ r = 0.800, g = 0.200, b = 1.000 }, -- #CC33FF Bright Violet
		{ r = 1.000, g = 0.000, b = 0.500 }, -- #FF007F Deep Pink
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