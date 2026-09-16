local base = _G

module("twitch.irc")

local string = base.string
local table = base.table

local TAG_UNESCAPE = {
	[":"] = ";",
	["s"] = " ",
	["\\"] = "\\",
	["r"] = "\r",
	["n"] = "\n",
}

local function unescapeTagValue(value)
	if not value or value == "" then
		return value or ""
	end

	if not string.find(value, "\\", 1, true) then
		return value
	end

	local out = {}
	local i = 1
	local len = #value

	while i <= len do
		local c = string.sub(value, i, i)
		if c == "\\" then
			if i == len then
				break
			end
			local n = string.sub(value, i + 1, i + 1)
			out[#out + 1] = TAG_UNESCAPE[n] or n
			i = i + 2
		else
			out[#out + 1] = c
			i = i + 1
		end
	end

	return table.concat(out)
end

local function parseTags(tagString)
	if not tagString then return {} end

	local tags = {}
	for pair in string.gmatch(tagString, "([^;]+)") do
		local key, value = string.match(pair, "^([^=]+)=?(.*)$")
		if key then
			tags[key] = unescapeTagValue(value or "")
		end
	end
	return tags
end

local function parseParams(paramRest)
	local middle = {}
	local trailing = nil

	paramRest = string.match(paramRest or "", "^%s*(.-)%s*$") or ""
	if paramRest == "" then
		return middle, trailing
	end

	if string.sub(paramRest, 1, 1) == ":" then
		return middle, string.sub(paramRest, 2)
	end

	local trailingStart = string.find(paramRest, " :", 1, true)
	if trailingStart then
		local before = string.sub(paramRest, 1, trailingStart - 1)
		trailing = string.sub(paramRest, trailingStart + 2)
		for token in string.gmatch(before, "%S+") do
			middle[#middle + 1] = token
		end
	else
		for token in string.gmatch(paramRest, "%S+") do
			middle[#middle + 1] = token
		end
	end

	return middle, trailing
end

local function stripCtcpAction(text)
	if not text or text == "" then
		return text or ""
	end

	local inner = string.match(text, "^\001ACTION (.*)\001$")
	if inner then
		return inner
	end

	inner = string.match(text, "^\001ACTION (.*)$")
	if inner then
		return inner
	end

	return text
end

local function parseLine(buffer)
	if not buffer or buffer == "" then
		return nil
	end

	local tagsStr = nil
	local rest = buffer

	if string.sub(rest, 1, 1) == "@" then
		local tagPart, afterTags = string.match(rest, "^@([^ ]+) ?(.*)$")
		if not tagPart then
			return nil
		end
		tagsStr = tagPart
		rest = afterTags or ""
	end

	if rest == "" then
		return nil
	end

	local prefix = nil
	if string.sub(rest, 1, 1) == ":" then
		local pfx, afterPrefix = string.match(rest, "^:([^ ]+) ?(.*)$")
		if not pfx then
			return nil
		end
		prefix = pfx
		rest = afterPrefix or ""
	end

	if rest == "" then
		return nil
	end

	local cmd, paramRest = string.match(rest, "^([^ ]+)(.*)$")
	if not cmd or cmd == "" then
		return nil
	end

	local middle, trailing = parseParams(paramRest)
	local param1 = middle[1]
	local param2 = trailing

	if cmd == "PRIVMSG" or cmd == "WHISPER" then
		param2 = stripCtcpAction(param2 or "")
	end

	return {
		tagsStr = tagsStr,
		prefix = prefix,
		cmd = cmd,
		middle = middle,
		trailing = trailing,
		param1 = param1,
		param2 = param2,
	}
end

return {
	unescapeTagValue = unescapeTagValue,
	parseTags = parseTags,
	parseParams = parseParams,
	stripCtcpAction = stripCtcpAction,
	parseLine = parseLine,
}