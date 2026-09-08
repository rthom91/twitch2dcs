local base = _G

module("twitch.sanitizer")

local require = base.require
local string = base.string
local table = base.table
local pairs = base.pairs
local ipairs = base.ipairs

local emojis = require("twitch.emojis")

local emojiKeys = {}
for k in pairs(emojis) do
	table.insert(emojiKeys, k)
end
table.sort(emojiKeys, function(a, b) return #a > #b end)

local function isVariationSelector(b1, b2, b3)
	return b1 == 0xEF and b2 == 0xB8 and b3 >= 0x80 and b3 <= 0x8F
end

local function isZWJ(b1, b2, b3)
	return b1 == 0xE2 and b2 == 0x80 and b3 == 0x8D
end

local function isSkinTone(b1, b2, b3, b4)
	return b1 == 0xF0 and b2 == 0x9F and b3 == 0x8F and b4 >= 0xBB and b4 <= 0xBF
end

local function skipModifiers(text, i, len)
	while true do
		if i + 3 <= len then
			local b1, b2, b3, b4 = string.byte(text, i, i + 3)
			if isSkinTone(b1, b2, b3, b4) then
				i = i + 4
			elseif isVariationSelector(b1, b2, b3) or isZWJ(b1, b2, b3) then
				i = i + 3
			else
				break
			end
		elseif i + 2 <= len then
			local b1, b2, b3 = string.byte(text, i, i + 2)
			if isVariationSelector(b1, b2, b3) or isZWJ(b1, b2, b3) then
				i = i + 3
			else
				break
			end
		else
			break
		end
	end
	return i
end

local function sanitizeMessage(text)
	if not text or text == "" then return "" end

	local hasHighByte = false
	for i = 1, #text do
		if string.byte(text, i) >= 128 then
			hasHighByte = true
			break
		end
	end
	if not hasHighByte then
		return text
	end

	local result = ""
	local i = 1
	local len = #text

	while i <= len do
		local matched = false

		for _, emoji in ipairs(emojiKeys) do
			local elen = #emoji
			if i + elen - 1 <= len and string.sub(text, i, i + elen - 1) == emoji then
				result = result .. emojis[emoji]
				i = i + elen
				i = skipModifiers(text, i, len)
				matched = true
				break
			end
		end

		if not matched then
			local byte = string.byte(text, i)

			if byte >= 240 and byte <= 244 then
				if i + 3 <= len then
					result = result .. ":emoji:"
					i = i + 4
					i = skipModifiers(text, i, len)
				else
					result = result .. string.sub(text, i)
					i = len + 1
				end

			elseif byte >= 224 and byte <= 239 then
				if i + 2 <= len then
					local b1, b2, b3 = string.byte(text, i, i + 2)

					if isVariationSelector(b1, b2, b3) or isZWJ(b1, b2, b3) then
						i = i + 3
					elseif b1 == 0xE2 then
						result = result .. ":emoji:"
						i = i + 3
					else
						result = result .. string.sub(text, i, i + 2)
						i = i + 3
					end
				else
					result = result .. string.sub(text, i)
					i = len + 1
				end

			elseif byte >= 192 and byte <= 223 then
				if i + 1 <= len then
					result = result .. string.sub(text, i, i + 1)
					i = i + 2
				else
					result = result .. string.sub(text, i)
					i = len + 1
				end

			else
				result = result .. string.sub(text, i, i)
				i = i + 1
			end
		end
	end

	return result
end

return {
	sanitizeMessage = sanitizeMessage
}