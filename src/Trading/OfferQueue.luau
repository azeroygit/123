--!strict
--[[
	OfferQueue.luau
	Tracks outgoing and incoming offers with full AMVGG evaluation, status lifecycle,
	anti-spam deduplication, response timer checks, and mandatory user confirmation
	for final trade acceptance.
]]

local OfferQueue = {}
OfferQueue.__index = OfferQueue

export type OfferStatus = "PENDING" | "ACCEPTED" | "DECLINED" | "EXPIRED" | "CANCELLED" | "UNKNOWN"

export type OfferRecord = {
	offerId: string,
	listingId: string?,
	direction: string, -- "OUTGOING" | "INCOMING"
	offeredItems: { any },
	requestedItems: { any },
	evaluation: any,
	profitValue: number,
	profitPercent: number,
	createdAt: number,
	lastCheckedAt: number,
	expiresAt: number,
	status: OfferStatus,
	noResponseNotified: boolean,
}

function OfferQueue.new(deps: {
	valueEngine: any,
	offerTimer: any,
	config: any,
	eventBus: any?,
	state: any?,
	logger: any?,
	clockFn: (() -> number)?,
})
	local self = setmetatable({}, OfferQueue)
	self._valueEngine = deps.valueEngine
	self._timer = deps.offerTimer
	self._config = deps.config
	self._eventBus = deps.eventBus
	self._state = deps.state
	self._logger = deps.logger
	self._clock = deps.clockFn or os.time

	self._offers = {} :: { [string]: OfferRecord }
	self._order = {} :: { string }
	self._nextId = 1
	return self
end

function OfferQueue:hasPendingForListing(listingId: string): boolean
	if not listingId or listingId == "" then
		return false
	end
	for _, id in ipairs(self._order) do
		local o = self._offers[id]
		if o and o.status == "PENDING" and o.listingId == listingId then
			return true
		end
	end
	return false
end

function OfferQueue:getPendingCount(): number
	local count = 0
	for _, id in ipairs(self._order) do
		if self._offers[id] and self._offers[id].status == "PENDING" then
			count += 1
		end
	end
	return count
end

function OfferQueue:enqueue(params: {
	listingId: string?,
	direction: string?,
	offeredItems: { any },
	requestedItems: { any },
	expirationSeconds: number?,
}): (OfferRecord?, string?)
	if params.listingId and self:hasPendingForListing(params.listingId) then
		return nil, "Duplicate offer prevented: already have a pending offer for listing " .. tostring(params.listingId)
	end

	local maxPending = tonumber(self._config:get("Trading.MaxPendingOffers")) or 20
	if self:getPendingCount() >= maxPending then
		return nil, string.format("Max pending offers limit (%d) reached", maxPending)
	end

	local eval = self._valueEngine:evaluateTrade(params.offeredItems, params.requestedItems)
	local now = self._clock()
	local ttl = params.expirationSeconds or tonumber(self._config:get("Trading.OfferExpirationSeconds")) or 180
	local id = string.format("off_%d_%d", now, self._nextId)
	self._nextId += 1

	local rec: OfferRecord = {
		offerId = id,
		listingId = params.listingId,
		direction = params.direction or "OUTGOING",
		offeredItems = params.offeredItems,
		requestedItems = params.requestedItems,
		evaluation = eval,
		profitValue = eval.potentialProfit,
		profitPercent = eval.percentDifference,
		createdAt = now,
		lastCheckedAt = now,
		expiresAt = now + ttl,
		status = "PENDING",
		noResponseNotified = false,
	}

	self._offers[id] = rec
	table.insert(self._order, id)

	if self._state then
		self._state:set("offers.pendingCount", self:getPendingCount(), "OfferQueue")
	end
	if self._eventBus then
		self._eventBus:emit("Offer:Queued", rec)
	end
	return rec, nil
end

function OfferQueue:updateStatus(offerId: string, newStatus: OfferStatus, options: { userConfirmed: boolean? }?): (boolean, string?)
	local rec = self._offers[offerId]
	if not rec then
		return false, "Offer not found"
	end
	if newStatus == "ACCEPTED" and not (options and options.userConfirmed == true) then
		return false, "Explicit user confirmation required before accepting any trade"
	end

	rec.status = newStatus
	if self._state then
		self._state:set("offers.pendingCount", self:getPendingCount(), "OfferQueue")
	end
	if self._eventBus then
		self._eventBus:emit("Offer:StatusChanged", rec)
	end
	return true, nil
end

function OfferQueue:checkPendingTimers(): { expired: { OfferRecord }, awaitingResponse: { OfferRecord } }
	local now = self._clock()
	local expired = {}
	local awaitingResponse = {}

	for _, id in ipairs(self._order) do
		local rec = self._offers[id]
		if rec and rec.status == "PENDING" then
			if now >= rec.expiresAt then
				rec.status = "EXPIRED"
				table.insert(expired, rec)
				if self._eventBus then
					self._eventBus:emit("Offer:Expired", rec)
				end
			elseif self._timer:shouldNotifyNoResponse(rec.lastCheckedAt) then
				rec.lastCheckedAt = now
				rec.noResponseNotified = true
				table.insert(awaitingResponse, rec)
				if self._eventBus then
					self._eventBus:emit("Offer:NoResponse", {
						offer = rec,
						ageSeconds = self._timer:getAgeSeconds(rec.createdAt),
					})
				end
			end
		end
	end

	if #expired > 0 and self._state then
		self._state:set("offers.pendingCount", self:getPendingCount(), "OfferQueue")
	end

	return { expired = expired, awaitingResponse = awaitingResponse }
end

function OfferQueue:getReservedPetUids(): { [string]: boolean }
	local reserved = {}
	for _, id in ipairs(self._order) do
		local rec = self._offers[id]
		if rec and rec.status == "PENDING" then
			for _, pet in ipairs(rec.offeredItems) do
				if pet.uid then
					reserved[tostring(pet.uid)] = true
				end
			end
		end
	end
	return reserved
end

function OfferQueue:getAll(): { OfferRecord }
	local out = {}
	for _, id in ipairs(self._order) do
		if self._offers[id] then
			table.insert(out, self._offers[id])
		end
	end
	return out
end

return OfferQueue
