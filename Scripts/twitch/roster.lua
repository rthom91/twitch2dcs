local base = _G

module("twitch.roster")

local os = base.os
local string = base.string
local table = base.table
local pairs = base.pairs

local Roster = {}
local Roster_mt = { __index = Roster }

function Roster:new()
	local roster = base.setmetatable({}, Roster_mt)
	roster.username = nil
	roster:reset()
	return roster
end

function Roster:reset()
	self.userNames = {}
	self.userLastActive = {}
	self.userDisplayNames = {}
	self.activeMods = {}
	self.broadcasterKey = nil
end

function Roster:setUsername(username)
	self.username = string.lower(username or "")
end

function Roster:addViewer(displayName, userId, login, skipTitleUpdate)
	login = (login or displayName or ""):lower()
	if login == "" then
		return false
	end

	local key = login
	local isNew = not self.userNames[key]

	self.userNames[key] = true
	self.userLastActive[key] = os.time()

	if displayName and displayName ~= "" then
		self.userDisplayNames[key] = displayName
	elseif not self.userDisplayNames[key] then
		self.userDisplayNames[key] = login
	end

	if self.username and key == self.username then
		self.broadcasterKey = key
	end

	return isNew and not skipTitleUpdate
end

function Roster:removeViewer(displayName, userId, login)
	login = (login or displayName or ""):lower()
	if login == "" then
		return false
	end

	local key = login

	if not self.userNames[key] then
		return false
	end

	self.userNames[key] = nil
	self.userLastActive[key] = nil
	self.userDisplayNames[key] = nil

	if self.broadcasterKey == key then
		self.broadcasterKey = nil
	end

	return true
end

function Roster:addModerator(login, displayName)
	login = (login or ""):lower()
	if login == "" then
		return
	end
	if self.username and login == self.username then
		return
	end
	self.activeMods[login] = displayName or login
end

function Roster:removeModerator(login)
	login = (login or ""):lower()
	if login == "" then
		return
	end
	self.activeMods[login] = nil
end

function Roster:count()
	local activeCount = 0
	local selfLogin = self.username or self.broadcasterKey

	for key in pairs(self.userNames) do
		if key ~= selfLogin and key ~= self.broadcasterKey then
			activeCount = activeCount + 1
		end
	end

	return activeCount
end

function Roster:listMods()
	local mods = {}

	for login, displayName in pairs(self.activeMods) do
		table.insert(mods, displayName or login)
	end

	table.sort(mods, function(a, b)
		return string.lower(a) < string.lower(b)
	end)

	return mods
end

return Roster