--!strict
--[[
	ValueParser.luau
	Parses pet valuation data exclusively from AMVGG (https://amvgg.com/values/pets).
	Supports:
	  1. Next.js App Router RSC payload (`self.__next_f.push([1,"..."])` chunks)
	  2. Direct JSON array or `{ pets = [...] }` object (cached / manual AMVGG export)
	Detects Cloudflare challenges, rate-limits, and malformed HTML/JSON without bypassing.
]]

local ValueParser = {}

export type ParseResult = {
	ok: boolean,
	pets: { [number]: any },
	error: string?,
	errorType: string?, -- "CLOUDFLARE_BLOCK" | "MALFORMED_HTML" | "MALFORMED_JSON" | "EMPTY_DATASET"
}

local function unescapeRscString(raw: string): string
	-- Unescape JSON string literal content extracted from self.__next_f.push([1,"..."])
	local out = raw:gsub('\\"', '"')
	out = out:gsub("\\/", "/")
	out = out:gsub("\\n", "\n")
	out = out:gsub("\\r", "\r")
	out = out:gsub("\\t", "\t")
	out = out:gsub("\\\\", "\\")
	return out
end

local function extractRscChunks(html: string): string
	local chunks = {}
	-- Pattern matches self.__next_f.push([1,"..."])
	local pos = 1
	local marker = 'self.__next_f.push([1,"'
	while true do
		local startIdx = string.find(html, marker, pos, true)
		if not startIdx then
			break
		end
		local contentStart = startIdx + #marker
		local i = contentStart
		local len = #html
		local closed = false
		while i <= len do
			local ch = string.sub(html, i, i)
			if ch == "\\" then
				i += 2
			elseif ch == '"' then
				closed = true
				break
			else
				i += 1
			end
		end
		if closed then
			local rawChunk = string.sub(html, contentStart, i - 1)
			table.insert(chunks, unescapeRscString(rawChunk))
			pos = i + 1
		else
			break
		end
	end
	return table.concat(chunks, "")
end

local function extractPetObjectsFromRsc(rscText: string, jsonDecode: (string) -> any): { any }
	local pets = {}
	local seenIds = {}
	local pos = 1
	local len = #rscText

	while pos <= len do
		local objStart = string.find(rscText, '{"id":"', pos, true)
		if not objStart then
			break
		end
		-- Balance braces from objStart
		local depth = 0
		local inStr = false
		local escaped = false
		local objEnd: number? = nil

		for i = objStart, len do
			local ch = string.sub(rscText, i, i)
			if inStr then
				if escaped then
					escaped = false
				elseif ch == "\\" then
					escaped = true
				elseif ch == '"' then
					inStr = false
				end
			else
				if ch == '"' then
					inStr = true
				elseif ch == "{" then
					depth += 1
				elseif ch == "}" then
					depth -= 1
					if depth == 0 then
						objEnd = i
						break
					end
				end
			end
		end

		if not objEnd then
			break
		end

		local jsonSlice = string.sub(rscText, objStart, objEnd)
		local ok, obj = pcall(jsonDecode, jsonSlice)
		if ok and type(obj) == "table" and type(obj.name) == "string" and obj.name ~= "" then
			-- Verify this is an AMVGG pet record (has at least one value field)
			if obj.regularValue ~= nil or obj.neonValue ~= nil or obj.megaValue ~= nil or obj.npRegularValue ~= nil then
				local key = tostring(obj.id or obj.name)
				if not seenIds[key] then
					seenIds[key] = true
					table.insert(pets, obj)
				end
			end
		end
		pos = objEnd + 1
	end

	return pets
end

function ValueParser.isCloudflareChallenge(body: string): boolean
	if type(body) ~= "string" then
		return false
	end
	local lower = string.lower(body)
	if string.find(lower, "just a moment...", 1, true) and string.find(lower, "cloudflare", 1, true) then
		return true
	end
	if string.find(lower, "cf-browser-verification", 1, true) or string.find(lower, "attention required! | cloudflare", 1, true) then
		return true
	end
	return false
end

function ValueParser.parse(rawBody: string, jsonDecode: (string) -> any): ParseResult
	if type(rawBody) ~= "string" or rawBody == "" then
		return { ok = false, pets = {}, error = "Empty response from AMVGG", errorType = "EMPTY_DATASET" }
	end

	if ValueParser.isCloudflareChallenge(rawBody) then
		return {
			ok = false,
			pets = {},
			error = "AMVGG returned a Cloudflare protection challenge; cannot fetch automatically without bypassing",
			errorType = "CLOUDFLARE_BLOCK",
		}
	end

	local trimmed = rawBody:match("^%s*(.-)%s*$") or rawBody
	-- 1. Direct JSON check (cached or manual AMVGG export)
	local firstChar = string.sub(trimmed, 1, 1)
	if firstChar == "[" or firstChar == "{" then
		local ok, decoded = pcall(jsonDecode, trimmed)
		if not ok or type(decoded) ~= "table" then
			return { ok = false, pets = {}, error = "Malformed JSON in AMVGG payload", errorType = "MALFORMED_JSON" }
		end
		local list = if type(decoded.pets) == "table" then decoded.pets else decoded
		if type(list) ~= "table" or #list == 0 then
			return { ok = false, pets = {}, error = "AMVGG JSON contained zero pet records", errorType = "EMPTY_DATASET" }
		end
		return { ok = true, pets = list }
	end

	-- 2. Next.js RSC HTML payload from https://amvgg.com/values/pets
	local rscText = extractRscChunks(rawBody)
	if rscText == "" then
		return {
			ok = false,
			pets = {},
			error = "AMVGG HTML did not contain expected Next.js RSC pet payload",
			errorType = "MALFORMED_HTML",
		}
	end

	local pets = extractPetObjectsFromRsc(rscText, jsonDecode)
	if #pets == 0 then
		return {
			ok = false,
			pets = {},
			error = "No valid pet records found in AMVGG RSC payload",
			errorType = "EMPTY_DATASET",
		}
	end

	return { ok = true, pets = pets }
end

return ValueParser
