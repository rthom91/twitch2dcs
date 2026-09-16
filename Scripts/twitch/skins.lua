local base = _G

module("twitch.skins")

local string = base.string
local math = base.math
local table = base.table
local ipairs = base.ipairs

local Skins = {}
local Skins_mt = { __index = Skins }

local function getMessageColors()
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

local function rgbToHex(rgb)
	local r = math.floor(math.max(0, math.min(1, rgb.r or 0)) * 255)
	local g = math.floor(math.max(0, math.min(1, rgb.g or 0)) * 255)
	local b = math.floor(math.max(0, math.min(1, rgb.b or 0)) * 255)
	return string.format("0x%02X%02X%02XFF", r, g, b)
end

function Skins:new(config, ui)
	local skins = base.setmetatable({}, Skins_mt)
	skins.config = config
	skins.ui = ui
	skins:reset()
	return skins
end

function Skins:reset()
	self.userSkins = {}
	self.userTwitchColors = {}
	self.recentPaletteIndices = {}
end

function Skins:clearAssignedSkins()
	self.userSkins = {}
end

function Skins:getSkinForUser(user, twitchColor)
	user = (user or ""):lower()
	if user == "" then
		return self.ui.messageSkin
	end

	local colorMode = self.config:getColorMode()
	local colorUpdated = false

	if twitchColor and twitchColor ~= "" and string.sub(twitchColor, 1, 1) == "#" then
		if self.userTwitchColors[user] ~= twitchColor then
			self.userTwitchColors[user] = twitchColor
			colorUpdated = true
		end
	end

	local skin = self.userSkins[user]
	local isNew = false
	if not skin then
		skin = self.ui.skinFactory:getSkin()
		self.userSkins[user] = skin
		isNew = true
	end

	local textState = skin.skinData.states.released[2].text
	local colorHex = nil
	local storedColor = self.userTwitchColors[user]

	if colorMode == "twitch" and storedColor then
		colorHex = "0x" .. string.sub(storedColor, 2) .. "ff"
	elseif isNew then
		local colors = getMessageColors()
		local available = {}

		for i = 1, #colors do
			local usedRecently = false
			for _, recent in ipairs(self.recentPaletteIndices) do
				if recent == i then
					usedRecently = true
					break
				end
			end
			if not usedRecently then
				table.insert(available, i)
			end
		end

		if #available == 0 then
			for i = 1, #colors do
				table.insert(available, i)
			end
		end

		local chosenIndex = available[math.random(1, #available)]
		colorHex = rgbToHex(colors[chosenIndex])

		table.insert(self.recentPaletteIndices, chosenIndex)
		if #self.recentPaletteIndices > 10 then
			table.remove(self.recentPaletteIndices, 1)
		end
	end

	if colorHex and textState.color ~= colorHex then
		textState.color = colorHex
		colorUpdated = true
	end

	textState.fontSize = self.ui.fontSize or self.config:getFontSize()

	if colorUpdated and colorMode == "twitch" and not isNew and self.ui then
		self.ui:updateListM(true)
	end

	return skin
end

Skins.getMessageColors = getMessageColors
Skins.rgbToHex = rgbToHex

return Skins