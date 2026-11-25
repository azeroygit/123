--!strict
--[[
	OfferTimer.luau
	Tracks response monitoring intervals (30-60s default) and expiration
	countdowns for pending offers without blocking or spamming.
]]

local OfferTimer = {}
OfferTimer.__index = OfferTimer

function OfferTimer.new(config: any, clockFn: (() -> number)?)
	local self = setmetatable({}, OfferTimer)
	self._config = config
	self._clock = clockFn or os.time
	self._lastCheckAt = 0
	return self
end

function OfferTimer:getAgeSeconds(createdAt: number): number
	return math.max(0, self._clock() - createdAt)
end

function OfferTimer:getRemainingSeconds(createdAt: number, expirationSeconds: number?): number
	local exp = expirationSeconds or tonumber(self._config:get("Trading.OfferExpirationSeconds")) or 180
	return math.max(0, exp - self:getAgeSeconds(createdAt))
end

function OfferTimer:isExpired(createdAt: number, expirationSeconds: number?): boolean
	return self:getRemainingSeconds(createdAt, expirationSeconds) <= 0
end

function OfferTimer:shouldNotifyNoResponse(lastCheckedAt: number?): boolean
	local interval = tonumber(self._config:get("Trading.OfferResponseIntervalSeconds")) or 45
	local now = self._clock()
	if not lastCheckedAt then
		return false
	end
	return (now - lastCheckedAt) >= interval
end

return OfferTimer
