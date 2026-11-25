--!strict
--[[
	ListingManager.luau
	Manages listing drafts, AMVGG previews, published listings, incoming offers,
	and configurable stale-listing detection (30, 45, 60 default, 90, 120s).
	Never auto-cancels or reposts without explicit user confirmation/permission.
]]

local ListingManager = {}
ListingManager.__index = ListingManager

export type ListingRecord = {
	id: string,
	offeredItems: { any },
	requestedItems: { any }?,
	offeredValue: number,
	requestedValue: number,
	expectedProfitPct: number,
	status: string, -- "DRAFT" | "ACTIVE" | "STALE" | "CANCELLED" | "COMPLETED"
	createdAt: number,
	expiresAfterSeconds: number,
	incomingOffers: { any },
	staleNotified: boolean,
	suggestion: string?,
}

function ListingManager.new(deps: {
	valueEngine: any,
	config: any,
	eventBus: any?,
	state: any?,
	logger: any?,
	clockFn: (() -> number)?,
})
	local self = setmetatable({}, ListingManager)
	self._valueEngine = deps.valueEngine
	self._config = deps.config
	self._eventBus = deps.eventBus
	self._state = deps.state
	self._logger = deps.logger
	self._clock = deps.clockFn or os.time

	self._listings = {} :: { [string]: ListingRecord }
	self._order = {} :: { string }
	self._nextId = 1
	return self
end

function ListingManager:previewDraft(offeredItems: { any }, requestedItems: { any }?): {
	offeredValue: number,
	requestedValue: number,
	profitValue: number,
	profitPercent: number,
	complete: boolean,
}
	local offEval = self._valueEngine:evaluateList(offeredItems)
	if requestedItems and #requestedItems > 0 then
		local tradeEval = self._valueEngine:evaluateTrade(offeredItems, requestedItems)
		return {
			offeredValue = tradeEval.yourValue,
			requestedValue = tradeEval.theirValue,
			profitValue = tradeEval.difference,
			profitPercent = tradeEval.percentDifference,
			complete = tradeEval.complete,
		}
	end
	return {
		offeredValue = offEval.totalValue,
		requestedValue = 0,
		profitValue = 0,
		profitPercent = 0,
		complete = offEval.complete,
	}
end

function ListingManager:createDraft(offeredItems: { any }, requestedItems: { any }?, expiresAfterSeconds: number?): ListingRecord
	local preview = self:previewDraft(offeredItems, requestedItems)
	local id = string.format("lst_%d_%d", self._clock(), self._nextId)
	self._nextId += 1

	local ttl = tonumber(expiresAfterSeconds) or tonumber(self._config:get("Trading.ListingExpirationSeconds")) or 60
	local rec: ListingRecord = {
		id = id,
		offeredItems = offeredItems,
		requestedItems = requestedItems,
		offeredValue = preview.offeredValue,
		requestedValue = preview.requestedValue,
		expectedProfitPct = preview.profitPercent,
		status = "DRAFT",
		createdAt = self._clock(),
		expiresAfterSeconds = ttl,
		incomingOffers = {},
		staleNotified = false,
		suggestion = nil,
	}
	self._listings[id] = rec
	table.insert(self._order, id)
	return rec
end

function ListingManager:publishListing(id: string): (boolean, string?)
	local rec = self._listings[id]
	if not rec then
		return false, "Listing not found"
	end
	local maxActive = tonumber(self._config:get("Trading.MaxActiveListings")) or 5
	local activeCount = #self:getActive()
	if activeCount >= maxActive then
		return false, string.format("Max active listings limit (%d) reached", maxActive)
	end
	rec.status = "ACTIVE"
	rec.createdAt = self._clock()
	rec.staleNotified = false
	if self._eventBus then
		self._eventBus:emit("Listing:Published", rec)
	end
	return true, nil
end

function ListingManager:attachIncomingOffer(listingId: string, offerSummary: any): boolean
	local rec = self._listings[listingId]
	if not rec then
		return false
	end
	table.insert(rec.incomingOffers, offerSummary)
	if self._eventBus then
		self._eventBus:emit("Listing:IncomingOffer", { listing = rec, offer = offerSummary })
	end
	return true
end

function ListingManager:checkStaleListings(): { ListingRecord }
	local now = self._clock()
	local staleList = {}

	for _, id in ipairs(self._order) do
		local rec = self._listings[id]
		if rec and rec.status == "ACTIVE" then
			local age = now - rec.createdAt
			if age >= rec.expiresAfterSeconds then
				rec.status = "STALE"
				-- Recalculate attractiveness against current AMVGG values
				local preview = self:previewDraft(rec.offeredItems, rec.requestedItems)
				rec.offeredValue = preview.offeredValue
				rec.requestedValue = preview.requestedValue
				rec.expectedProfitPct = preview.profitPercent
				rec.suggestion = if #rec.incomingOffers > 0
					then "Has pending incoming offers — review before cancelling"
					elseif preview.profitPercent > 20 then "Ask % may be too high; consider lowering ask or open offers"
					else "Refresh listing to regain Trade Hub visibility"

				if not rec.staleNotified then
					rec.staleNotified = true
					if self._eventBus then
						self._eventBus:emit("Listing:Stale", {
							listing = rec,
							ageSeconds = age,
							hasIncomingOffers = #rec.incomingOffers > 0,
						})
					end
				end
				table.insert(staleList, rec)
			end
		end
	end
	return staleList
end

function ListingManager:cancelListing(id: string, confirmed: boolean): (boolean, string?)
	local rec = self._listings[id]
	if not rec then
		return false, "Listing not found"
	end
	if not confirmed then
		if #rec.incomingOffers > 0 then
			return false, "Confirmation required: listing has pending incoming offers"
		end
		return false, "Explicit user confirmation required to cancel listing"
	end
	rec.status = "CANCELLED"
	if self._eventBus then
		self._eventBus:emit("Listing:Cancelled", rec)
	end
	return true, nil
end

function ListingManager:getActive(): { ListingRecord }
	local out = {}
	for _, id in ipairs(self._order) do
		local rec = self._listings[id]
		if rec and (rec.status == "ACTIVE" or rec.status == "STALE") then
			table.insert(out, rec)
		end
	end
	return out
end

function ListingManager:getAll(): { ListingRecord }
	local out = {}
	for _, id in ipairs(self._order) do
		if self._listings[id] then
			table.insert(out, self._listings[id])
		end
	end
	return out
end

return ListingManager
