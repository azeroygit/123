--!strict
--[[
	ValueCache.luau
	Local cache manager for validated AMVGG pet datasets.
	Preserves the last valid dataset on refresh failures and tracks freshness metadata.
]]

local ValueCache = {}
ValueCache.__index = ValueCache

export type CachePayload = {
	source: string,
	sourceUrl: string,
	updatedAt: number,
	petCount: number,
	pets: { any },
}

function ValueCache.new(options: { filePath: string?, fs: any?, json: any?, validator: any?, logger: any? }?)
	local opts = options or {}
	local self = setmetatable({}, ValueCache)
	self._filePath = opts.filePath or "KiriaAutoTrader/amvgg_cache.json"
	self._fs = opts.fs
	self._json = opts.json
	self._validator = opts.validator
	self._logger = opts.logger

	self._records = {} :: { [string]: any }
	self._ordered = {} :: { any }
	self._updatedAt = nil :: number?
	self._sourceUrl = "https://amvgg.com/values/pets"
	self._isStale = false
	return self
end

function ValueCache:hasData(): boolean
	return #self._ordered > 0
end

function ValueCache:getRecords(): { [string]: any }
	return self._records
end

function ValueCache:getOrdered(): { any }
	return self._ordered
end

function ValueCache:getPet(name: string): any?
	if not self._validator then
		return self._records[string.lower(name)]
	end
	return self._records[self._validator.normalizeKey(name)]
end

function ValueCache:getStatus(): { hasData: boolean, petCount: number, updatedAt: number?, isStale: boolean, sourceUrl: string }
	return {
		hasData = #self._ordered > 0,
		petCount = #self._ordered,
		updatedAt = self._updatedAt,
		isStale = self._isStale,
		sourceUrl = self._sourceUrl,
	}
end

function ValueCache:markStale()
	self._isStale = true
end

function ValueCache:setValidatedDataset(summary: { records: { [string]: any }, ordered: { any } }, updatedAt: number?, sourceUrl: string?): boolean
	if not summary or not summary.ordered or #summary.ordered == 0 then
		return false
	end
	self._records = summary.records
	self._ordered = summary.ordered
	self._updatedAt = updatedAt or os.time()
	if sourceUrl then
		self._sourceUrl = sourceUrl
	end
	self._isStale = false
	return true
end

function ValueCache:save(): boolean
	if not (self._fs and self._json and self._fs.write) or #self._ordered == 0 then
		return false
	end
	local payload: CachePayload = {
		source = "AMVGG",
		sourceUrl = self._sourceUrl,
		updatedAt = self._updatedAt or os.time(),
		petCount = #self._ordered,
		pets = self._ordered,
	}
	local okEnc, encoded = pcall(self._json.encode, payload)
	if not okEnc or type(encoded) ~= "string" then
		return false
	end
	local okWrite, err = pcall(self._fs.write, self._filePath, encoded)
	if not okWrite and self._logger then
		self._logger:warn("ValueCache", "Failed to save AMVGG cache: " .. tostring(err))
	end
	return okWrite
end

function ValueCache:load(): boolean
	if not (self._fs and self._json and self._fs.exists and self._fs.read and self._validator) then
		return false
	end
	if not self._fs.exists(self._filePath) then
		return false
	end
	local okRead, raw = pcall(self._fs.read, self._filePath)
	if not okRead or type(raw) ~= "string" or raw == "" then
		return false
	end
	local okDec, decoded = pcall(self._json.decode, raw)
	if not okDec or type(decoded) ~= "table" or type(decoded.pets) ~= "table" then
		return false
	end
	if decoded.source ~= nil and decoded.source ~= "AMVGG" then
		if self._logger then
			self._logger:warn("ValueCache", "Rejected non-AMVGG cache source: " .. tostring(decoded.source))
		end
		return false
	end

	local summary = self._validator.validateDataset(decoded.pets, tonumber(decoded.updatedAt))
	if summary.validCount == 0 then
		return false
	end

	self._records = summary.records
	self._ordered = summary.ordered
	self._updatedAt = tonumber(decoded.updatedAt) or os.time()
	self._sourceUrl = tostring(decoded.sourceUrl or "https://amvgg.com/values/pets")
	self._isStale = true -- Marked stale until live refresh confirms freshness
	return true
end

return ValueCache
