--!strict
--[[
	AMVGGProvider.luau
	Exclusive AMVGG valuation provider (https://amvgg.com/values/pets).
	Enforces AMVGG-only sourcing, rate-limiting, exponential backoff, non-blocking
	execution, and cache preservation on failure. Never bypasses Cloudflare or auth.
]]

local AMVGGProvider = {}
AMVGGProvider.__index = AMVGGProvider

local ALLOWED_HOST = "amvgg.com"
local MIN_REQUEST_COOLDOWN_SECONDS = 10

export type ProviderDeps = {
	config: any,
	cache: any,
	parser: any,
	validator: any,
	errorHandler: any,
	eventBus: any?,
	state: any?,
	logger: any?,
	httpGet: ((string) -> (boolean, number, string))?,
	jsonDecode: (string) -> any,
	clockFn: (() -> number)?,
}

local function isAllowedAmvggUrl(url: string): boolean
	if type(url) ~= "string" then
		return false
	end
	local host = string.match(string.lower(url), "^https://([^/]+)")
	return host == ALLOWED_HOST or host == ("www." .. ALLOWED_HOST)
end

function AMVGGProvider.new(deps: ProviderDeps)
	local self = setmetatable({}, AMVGGProvider)
	self._config = deps.config
	self._cache = deps.cache
	self._parser = deps.parser
	self._validator = deps.validator
	self._errorHandler = deps.errorHandler
	self._eventBus = deps.eventBus
	self._state = deps.state
	self._logger = deps.logger
	self._httpGet = deps.httpGet
	self._jsonDecode = deps.jsonDecode
	self._clock = deps.clockFn or os.time

	self._status = "IDLE" -- "IDLE" | "FETCHING" | "LIVE" | "CACHED_FALLBACK" | "UNAVAILABLE"
	self._lastError = nil :: string?
	self._lastAttemptAt = 0
	self._inFlight = false
	return self
end

function AMVGGProvider:_setStatus(status: string, errMsg: string?)
	self._status = status
	self._lastError = errMsg
	local cacheStatus = self._cache:getStatus()
	if self._state then
		self._state:set("amvgg.status", status, "AMVGGProvider")
		self._state:set("amvgg.lastUpdatedAt", cacheStatus.updatedAt, "AMVGGProvider")
		self._state:set("amvgg.petCount", cacheStatus.petCount, "AMVGGProvider")
		self._state:set("amvgg.lastError", errMsg, "AMVGGProvider")
	end
	if self._eventBus then
		self._eventBus:emit("AMVGG:StatusChanged", {
			status = status,
			error = errMsg,
			petCount = cacheStatus.petCount,
			updatedAt = cacheStatus.updatedAt,
			isStale = cacheStatus.isStale,
		})
	end
end

function AMVGGProvider:getStatus(): { status: string, lastError: string?, petCount: number, updatedAt: number?, isStale: boolean, sourceUrl: string }
	local cs = self._cache:getStatus()
	return {
		status = self._status,
		lastError = self._lastError,
		petCount = cs.petCount,
		updatedAt = cs.updatedAt,
		isStale = cs.isStale,
		sourceUrl = cs.sourceUrl,
	}
end

function AMVGGProvider:initFromCache(): boolean
	local loaded = self._cache:load()
	if loaded then
		self:_setStatus("CACHED_FALLBACK", nil)
		if self._logger then
			local st = self._cache:getStatus()
			self._logger:info("AMVGGProvider", string.format("Loaded %d pets from local AMVGG cache", st.petCount))
		end
	else
		self:_setStatus("IDLE", nil)
	end
	return loaded
end

function AMVGGProvider:refresh(options: { force: boolean? }?): (boolean, string?)
	local opts = options or {}
	if self._inFlight then
		return false, "AMVGG refresh already in progress"
	end

	local now = self._clock()
	if not opts.force and self._lastAttemptAt > 0 and (now - self._lastAttemptAt) < MIN_REQUEST_COOLDOWN_SECONDS then
		return false, "Rate limit cooldown active; please wait before refreshing AMVGG again"
	end

	local url = tostring(self._config:get("AMVGG.EndpointUrl") or "https://amvgg.com/values/pets")
	if not isAllowedAmvggUrl(url) then
		local msg = "Blocked non-AMVGG endpoint URL: " .. url
		self:_setStatus(if self._cache:hasData() then "CACHED_FALLBACK" else "UNAVAILABLE", msg)
		return false, msg
	end

	if type(self._httpGet) ~= "function" then
		local msg = "No HTTP client available in this environment; using preserved AMVGG cache/manual import"
		if self._cache:hasData() then
			self._cache:markStale()
			self:_setStatus("CACHED_FALLBACK", msg)
		else
			self:_setStatus("UNAVAILABLE", msg)
		end
		return false, msg
	end

	self._inFlight = true
	self._lastAttemptAt = now
	self:_setStatus("FETCHING", nil)

	local maxRetries = tonumber(self._config:get("AMVGG.MaxRetries")) or 3
	local ok, resultOrErr = self._errorHandler:retry("AMVGGProvider", function()
		local callOk, statusCode, body = self._httpGet(url)
		if not callOk then
			return false, "Network request failed: " .. tostring(statusCode)
		end
		if statusCode == 403 or statusCode == 429 or statusCode == 503 then
			return false, string.format("AMVGG HTTP %d (rate-limited or protected)", statusCode)
		end
		if statusCode < 200 or statusCode >= 300 then
			return false, string.format("AMVGG HTTP error %d", statusCode)
		end

		local parsed = self._parser.parse(body, self._jsonDecode)
		if not parsed.ok then
			return false, parsed.error or "Failed to parse AMVGG payload"
		end

		local summary = self._validator.validateDataset(parsed.pets, self._clock())
		if summary.validCount == 0 then
			return false, "AMVGG dataset had zero valid pet records after validation"
		end

		return true, summary
	end, {
		maxAttempts = maxRetries,
		baseDelay = 1.0,
		maxDelay = 12.0,
		shouldRetry = function(errStr: string)
			-- Do not hammer Cloudflare challenges
			return not string.find(errStr, "Cloudflare", 1, true)
		end,
	})

	self._inFlight = false

	if ok and type(resultOrErr) == "table" then
		self._cache:setValidatedDataset(resultOrErr, self._clock(), url)
		self._cache:save()
		self:_setStatus("LIVE", nil)
		if self._logger then
			self._logger:success("AMVGGProvider", string.format("Refreshed %d pets from AMVGG", resultOrErr.validCount))
		end
		if self._eventBus then
			self._eventBus:emit("AMVGG:Refreshed", {
				petCount = resultOrErr.validCount,
				rejectedCount = resultOrErr.rejectedCount,
				updatedAt = self._clock(),
			})
		end
		return true, nil
	end

	local errMsg = tostring(resultOrErr or "Unknown AMVGG error")
	if self._cache:hasData() then
		self._cache:markStale()
		self:_setStatus("CACHED_FALLBACK", errMsg)
		if self._logger then
			self._logger:warn("AMVGGProvider", "AMVGG refresh failed; preserved last valid cache: " .. errMsg)
		end
	else
		self:_setStatus("UNAVAILABLE", errMsg)
		if self._logger then
			self._logger:error("AMVGGProvider", "AMVGG refresh failed with no cache: " .. errMsg)
		end
	end

	if self._eventBus then
		self._eventBus:emit("AMVGG:Error", { message = errMsg, hasCache = self._cache:hasData() })
	end
	return false, errMsg
end

function AMVGGProvider:importPayload(rawBody: string): (boolean, string?)
	local parsed = self._parser.parse(rawBody, self._jsonDecode)
	if not parsed.ok then
		return false, parsed.error
	end
	local summary = self._validator.validateDataset(parsed.pets, self._clock())
	if summary.validCount == 0 then
		return false, "No valid AMVGG pet records found in imported payload"
	end
	self._cache:setValidatedDataset(summary, self._clock(), "https://amvgg.com/values/pets")
	self._cache:save()
	self:_setStatus("LIVE", nil)
	if self._eventBus then
		self._eventBus:emit("AMVGG:Refreshed", { petCount = summary.validCount, imported = true, updatedAt = self._clock() })
	end
	return true, nil
end

return AMVGGProvider
