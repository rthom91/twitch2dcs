local base = _G

module("twitch.format")

local string = base.string
local tonumber = base.tonumber

local SYSTEM_PREFIX = ">> [SYSTEM] "
local NOTIF_PREFIX = ">> [NOTIF] "

local function badgeTag(config, flags)
	flags = flags or {}
	if not config or not config.getShowUserTags or not config:getShowUserTags() then
		return ""
	end

	if flags.isStaff then
		return "[STAFF] "
	elseif flags.isModerator then
		return "[MOD] "
	elseif flags.isVIP then
		return "[VIP] "
	elseif flags.isSubscriber then
		return "[SUB] "
	end

	return ""
end

local function userPrefix(config, timestamp, flags, displayName)
	local prefix = ""

	if config and config.getShowTimestamps and config:getShowTimestamps() then
		if timestamp and timestamp ~= "" then
			prefix = timestamp .. " "
		end
	end

	prefix = prefix .. badgeTag(config, flags)
	prefix = prefix .. (displayName or "") .. ": "
	return prefix
end

local function rewriteCheerMessage(messageText, bits, showBits)
	messageText = messageText or ""

	if not bits or not tonumber(bits) or not showBits then
		return messageText
	end

	local bitsAmount = tonumber(bits)
	local bitWord = (bitsAmount == 1) and "bit" or "bits"
	local cheerNote = string.format("[Cheered with %d %s]", bitsAmount, bitWord)

	messageText = messageText:gsub("^[Cc]heer%d+%s*", "")
	messageText = messageText:gsub("%s*[Cc]heer%d+%s*", " ")
	messageText = messageText:gsub("^%s+", "")
	messageText = messageText:gsub("%s+$", "")

	if messageText == "" then
		return cheerNote
	end

	return cheerNote .. " " .. messageText
end

local function mysteryGiftMessage(gifter, count)
	if not gifter or gifter == "" then
		gifter = "Anonymous"
	end

	count = tonumber(count) or 1

	if count <= 1 then
		return gifter .. " has gifted a sub to the community."
	end

	return gifter .. " has gifted " .. count .. " subs to the community."
end

local function subGiftMessage(gifter, recipientDisplayName, recipientName)
	if not gifter or gifter == "" then
		gifter = "Anonymous"
	end

	local recipient = recipientDisplayName
	if not recipient or recipient == "" then
		recipient = recipientName
	end

	if recipient and recipient ~= "" then
		return gifter .. " has gifted a sub to " .. recipient .. "."
	end

	return gifter .. " has gifted a sub."
end

local function systemMessage(text)
	return SYSTEM_PREFIX, SYSTEM_PREFIX .. (text or "")
end

local function notifMessage(text)
	return NOTIF_PREFIX, NOTIF_PREFIX .. (text or "")
end

return {
	badgeTag = badgeTag,
	userPrefix = userPrefix,
	rewriteCheerMessage = rewriteCheerMessage,
	mysteryGiftMessage = mysteryGiftMessage,
	subGiftMessage = subGiftMessage,
	systemMessage = systemMessage,
	notifMessage = notifMessage,
}