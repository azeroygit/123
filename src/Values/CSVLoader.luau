--!strict
--[[
	CSVLoader.luau
	Loads pet values from pets_ridepots.csv (AMVGG-sourced) into ValueCache
	as instant offline fallback when HTTP fetch is unavailable.

	CSV columns (from header):
	  name, rarity, year, demand, demandScore, stars,
	  demandNP, demandNeon, demandMega,
	  valueRP (FR), rideRP (R), flyRP (F), npRP (NP),
	  neonRP (NFR), megaRP (MFR),
	  category, valueSource
]]

local CSVLoader = {}
CSVLoader.__index = CSVLoader

-- ── helpers ──────────────────────────────────────────────────────────────────

local function trim(s: string): string
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parseLine(line: string): { string }
	local fields = {}
	local i = 1
	local len = #line
	while i <= len do
		if line:sub(i, i) == '"' then
			-- quoted field
			i += 1
			local start = i
			local field = ""
			while i <= len do
				if line:sub(i, i) == '"' then
					if line:sub(i + 1, i + 1) == '"' then
						field = field .. line:sub(start, i - 1) .. '"'
						i += 2
						start = i
					else
						field = field .. line:sub(start, i - 1)
						i += 1
						break
					end
				else
					i += 1
				end
			end
			table.insert(fields, field)
			if i <= len and line:sub(i, i) == "," then i += 1 end
		else
			local comma = line:find(",", i, true)
			if comma then
				table.insert(fields, trim(line:sub(i, comma - 1)))
				i = comma + 1
			else
				table.insert(fields, trim(line:sub(i)))
				break
			end
		end
	end
	return fields
end

local function toNum(s: string?): number?
	if not s or s == "" or s == "N/A" then return nil end
	local n = tonumber(s)
	return n
end

-- Map demand string → score
local DEMAND_SCORE: { [string]: number } = {
	Horrible = 0.1, Low = 0.3, Medium = 0.5,
	High = 0.8, ["Very High"] = 0.95,
}

-- ── normalise pet name → lookup key ──────────────────────────────────────────

local function nameKey(name: string): string
	return name:lower():gsub("[%s%-_]+", "_"):gsub("[^%w_]", "")
end

-- ── CSVLoader.new ─────────────────────────────────────────────────────────────

export type Options = {
	fs: { read: (string) -> string }?,
	logger: any?,
	csvPath: string?,
}

function CSVLoader.new(opts: Options?)
	local o = opts or {}
	local self = setmetatable({}, CSVLoader)
	self._fs     = o.fs
	self._logger = o.logger
	self._path   = o.csvPath or "pets_ridepots.csv"
	self._records = {}   -- key → record (string -> any)
	self._loaded = false
	return self
end

function CSVLoader:_log(level: string, msg: string)
	if self._logger and type(self._logger[level:lower()]) == "function" then
		self._logger[level:lower()](self._logger, "[CSVLoader] " .. msg)
	end
end

-- ── load() ────────────────────────────────────────────────────────────────────

function CSVLoader:load(): boolean
	if self._loaded then return true end
	local fs = self._fs
	if not fs then
		-- Try executor readfile global
		if type(readfile) == "function" then
			fs = { read = function(p) return readfile(p) end }
		else
			self:_log("WARN", "No fs adapter and no readfile global — CSV unavailable")
			return false
		end
	end

	local ok, raw = pcall(function() return fs.read(self._path) end)
	if not ok or type(raw) ~= "string" or #raw == 0 then
		self:_log("WARN", "Could not read CSV at: " .. tostring(self._path))
		return false
	end

	local lines = {}
	for line in (raw .. "\n"):gmatch("([^\r\n]*)\r?\n") do
		table.insert(lines, line)
	end

	if #lines < 2 then
		self:_log("WARN", "CSV too short")
		return false
	end

	-- Parse header
	local header = parseLine(lines[1])
	local colIdx: { [string]: number } = {}
	for i, col in ipairs(header) do colIdx[trim(col)] = i end

	local function col(fields: { string }, name: string): string?
		local i = colIdx[name]
		return i and fields[i] or nil
	end

	local count = 0
	for lineNum = 2, #lines do
		local line = lines[lineNum]
		if line ~= "" then
			local fields = parseLine(line)
			local name = trim(col(fields, "name") or "")
			if name ~= "" then
				local frV  = toNum(col(fields, "valueRP"))
				local rideV = toNum(col(fields, "rideRP"))
				local flyV  = toNum(col(fields, "flyRP"))
				local npV   = toNum(col(fields, "npRP"))
				local neonV = toNum(col(fields, "neonRP"))
				local megaV = toNum(col(fields, "megaRP"))
				local demand = trim(col(fields, "demand") or "")
				local demandScore = toNum(col(fields, "demandScore")) or DEMAND_SCORE[demand] or 0.5

				local record = {
					name           = name,
					rarity         = trim(col(fields, "rarity") or ""),
					demand         = demand,
					demandScore    = demandScore,
					-- FR value (fly+ride) is the standard "normal" value in AMVGG
					regular        = frV,
					npRegular      = npV,
					r              = rideV,
					f              = flyV,
					neon           = neonV,
					npNeon         = nil,  -- not in CSV
					nr             = nil,
					nf             = nil,
					mega           = megaV,
					npMega         = nil,
					mr             = nil,
					mf             = nil,
					source         = "CSV_AMVGG",
					fetchedAt      = os.time(),
				}

				local key = nameKey(name)
				self._records[key] = record
				self._records[name:lower()] = record   -- also by exact lower
				count += 1
			end
		end
	end

	self._loaded = true
	self:_log("INFO", string.format("Loaded %d pets from CSV (%s)", count, self._path))
	return true
end

-- ── get(name) ─────────────────────────────────────────────────────────────────

function CSVLoader:get(name: string): any?
	if not self._loaded then self:load() end
	local key = nameKey(name)
	return self._records[key] or self._records[name:lower()]
end

-- ── seedCache(valueCache) ─────────────────────────────────────────────────────
-- Seed a ValueCache instance with all CSV records (only where cache is empty)

function CSVLoader:seedCache(valueCache: any)
	if not self._loaded then self:load() end
	local seeded = 0
	for _, record in pairs(self._records) do
		-- avoid duplicates by keying on name lower
		local existing = valueCache:get(record.name)
		if not existing or not existing.regular then
			valueCache:set(record.name, record)
			seeded += 1
		end
	end
	self:_log("INFO", string.format("Seeded cache with %d CSV records", seeded))
	return seeded
end

-- ── count() ──────────────────────────────────────────────────────────────────

function CSVLoader:count(): number
	if not self._loaded then self:load() end
	local n = 0
	for _ in pairs(self._records) do n += 1 end
	return math.floor(n / 2) -- divided by 2 because we store key+lowercase
end

function CSVLoader:isLoaded(): boolean
	return self._loaded
end

return CSVLoader
