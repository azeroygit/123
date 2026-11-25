--!strict
--[[
	ConfigManager.luau
	Schema-validated configuration manager with deep-merge defaults,
	live updates, and safe file persistence.
]]

local ConfigManager = {}
ConfigManager.__index = ConfigManager

ConfigManager.Defaults = {
	AMVGG = {
		EndpointUrl = "https://amvgg.com/values/pets",
		HubUrl = "https://amvgg.com/values",
		RefreshIntervalSeconds = 1800,
		RequestTimeoutSeconds = 15,
		MaxRetries = 3,
		CacheFile = "KiriaAutoTrader/amvgg_cache.json",
		AllowStaleCacheFallback = true,
	},
	Trading = {
		Mode = "manual_confirm", -- "manual_confirm" | "practice"
		MaxItemsPerOffer = 4,
		MinProfitValue = 1.0,
		MinProfitPercent = 5.0,
		MaxOverpayPercent = 0.0,
		AllowIncompleteEvaluations = false,
		RequireExplicitConfirmation = true,
		AutoCancelStaleListings = false, -- Always off unless explicitly permitted & enabled
		ScanIntervalSeconds = 15,
		ListingExpirationSeconds = 60, -- 30, 45, 60 (default), 90, 120
		OfferResponseIntervalSeconds = 45, -- 30-60s default
		OfferExpirationSeconds = 180,
		MaxPendingOffers = 20,
		MaxActiveListings = 5,
	},
	Thresholds = {
		ExcellentDealMinPct = 25.0,
		GoodDealMinPct = 8.0,
		FairTradeMinPct = -3.0,
		SmallLossMinPct = -12.0,
	},
	UI = {
		Theme = "KiriaDark",
		Keybind = "RightShift",
		AccentColorHex = "#9D4EDD",
		CompactMode = false,
		AnimationsEnabled = true,
		NotificationsEnabled = true,
		KiriaEnabled = true,
	},
	Data = {
		ConfigFile = "KiriaAutoTrader/config.json",
		AnalyticsFile = "KiriaAutoTrader/analytics.json",
		KiriaMemoryFile = "KiriaAutoTrader/kiria_memory.json",
		InventoryFile = "KiriaAutoTrader/inventory.json",
		LogLevel = "INFO",
	},
}

local function deepCopy(tbl: any): any
	if type(tbl) ~= "table" then
		return tbl
	end
	local copy = {}
	for k, v in pairs(tbl) do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function deepMerge(base: { [string]: any }, overrides: { [string]: any }?, warnings: { string }, prefix: string): { [string]: any }
	local out = deepCopy(base)
	if type(overrides) ~= "table" then
		return out
	end
	for k, v in pairs(overrides) do
		local path = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
		if base[k] == nil then
			table.insert(warnings, "Unknown config key ignored: " .. path)
		elseif type(base[k]) == "table" and type(v) == "table" then
			out[k] = deepMerge(base[k], v, warnings, path)
		elseif type(base[k]) == type(v) then
			out[k] = v
		else
			table.insert(warnings, string.format("Type mismatch for %s (expected %s, got %s)", path, type(base[k]), type(v)))
		end
	end
	return out
end

function ConfigManager.new(options: { initial: { [string]: any }?, json: any?, fs: any?, logger: any?, eventBus: any? }?)
	local opts = options or {}
	local self = setmetatable({}, ConfigManager)
	self._json = opts.json
	self._fs = opts.fs
	self._logger = opts.logger
	self._eventBus = opts.eventBus
	self._warnings = {} :: { string }
	self._data = deepMerge(ConfigManager.Defaults, opts.initial, self._warnings, "")
	-- Enforce safety invariant: explicit trade confirmation is always required
	self._data.Trading.RequireExplicitConfirmation = true
	return self
end

function ConfigManager:get(path: string): any
	local cur: any = self._data
	for part in string.gmatch(path, "[^%.]+") do
		if type(cur) ~= "table" then
			return nil
		end
		cur = cur[part]
	end
	return cur
end

function ConfigManager:set(path: string, value: any): boolean
	if path == "Trading.RequireExplicitConfirmation" and value == false then
		if self._logger then
			self._logger:warn("ConfigManager", "RequireExplicitConfirmation cannot be disabled for safety")
		end
		return false
	end

	local parts = {}
	for part in string.gmatch(path, "[^%.]+") do
		table.insert(parts, part)
	end
	if #parts == 0 then
		return false
	end

	local cur: any = self._data
	for i = 1, #parts - 1 do
		if type(cur[parts[i]]) ~= "table" then
			return false
		end
		cur = cur[parts[i]]
	end

	local leaf = parts[#parts]
	if cur[leaf] == nil then
		return false
	end
	cur[leaf] = value

	if self._eventBus then
		self._eventBus:emit("Config:Changed", path, value)
	end
	return true
end

function ConfigManager:getAll(): { [string]: any }
	return deepCopy(self._data)
end

function ConfigManager:getWarnings(): { string }
	return table.clone(self._warnings)
end

function ConfigManager:loadFromFile(): boolean
	if not (self._fs and self._json and self._fs.exists and self._fs.read) then
		return false
	end
	local path = self._data.Data.ConfigFile
	if not self._fs.exists(path) then
		return false
	end
	local okRead, raw = pcall(self._fs.read, path)
	if not okRead or type(raw) ~= "string" then
		return false
	end
	local okDec, decoded = pcall(self._json.decode, raw)
	if not okDec or type(decoded) ~= "table" then
		return false
	end
	local warnings = {}
	self._data = deepMerge(ConfigManager.Defaults, decoded, warnings, "")
	self._data.Trading.RequireExplicitConfirmation = true
	self._warnings = warnings
	return true
end

function ConfigManager:saveToFile(): boolean
	if not (self._fs and self._json and self._fs.write) then
		return false
	end
	local okEnc, raw = pcall(self._json.encode, self._data)
	if not okEnc or type(raw) ~= "string" then
		return false
	end
	local okWrite = pcall(self._fs.write, self._data.Data.ConfigFile, raw)
	return okWrite
end

function ConfigManager:resetDefaults()
	self._data = deepCopy(ConfigManager.Defaults)
	self._warnings = {}
	if self._eventBus then
		self._eventBus:emit("Config:Reset")
	end
end

return ConfigManager
