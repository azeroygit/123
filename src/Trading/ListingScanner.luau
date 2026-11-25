--!strict
--[[
	ListingScanner.luau
	Scans Trade Hub listings from a permitted game adapter or manual/JSON import,
	deduplicates and tracks inspected listings, evaluates AMVGG profit/status,
	and ranks opportunities. Never fabricates listings.
]]

local ListingScanner = {}
ListingScanner.__index = ListingScanner

export type ScannedListing = {
	listingId: string,
	sellerId: string?,
	offeredItems: { any }, -- what the seller is offering (you receive)
	requestedItems: { any }, -- what the seller is asking for (you give)
	totalAmvggOffered: number,
	totalAmvggRequested: number,
	estimatedProfit: number,
	profitPercent: number,
	confidenceStatus: string,
	listingStatus: string, -- "GOOD DEAL" | "FAIR DEAL" | "BAD DEAL" | "INCOMPLETE DATA" | "EXPIRED LISTING"
	liquidityNote: string,
	riskScore: number,
	timestamp: number,
	inspected: boolean,
	source: string, -- "game" | "manual" | "import"
}

function ListingScanner.new(deps: {
	tradeEvaluator: any,
	config: any,
	eventBus: any?,
	state: any?,
	logger: any?,
	json: any?,
	gameAdapter: any?,
	clockFn: (() -> number)?,
})
	local self = setmetatable({}, ListingScanner)
	self._evaluator = deps.tradeEvaluator
	self._config = deps.config
	self._eventBus = deps.eventBus
	self._state = deps.state
	self._logger = deps.logger
	self._json = deps.json
	self._gameAdapter = deps.gameAdapter
	self._clock = deps.clockFn or os.time

	self._listings = {} :: { [string]: ScannedListing }
	self._orderedIds = {} :: { string }
	self._seenSignatures = {} :: { [string]: boolean }
	self._scanCount = 0
	self._lastScanAt = nil :: number?
	self._integrationWarning = nil :: string?
	return self
end

local function makeSignature(raw: any): string
	local parts = {}
	for _, it in ipairs(raw.offeredItems or {}) do
		table.insert(parts, string.format("O:%s:%s:%s:%s:%s", tostring(it.name), tostring(it.neon), tostring(it.mega), tostring(it.fly), tostring(it.ride)))
	end
	for _, it in ipairs(raw.requestedItems or {}) do
		table.insert(parts, string.format("R:%s:%s:%s:%s:%s", tostring(it.name), tostring(it.neon), tostring(it.mega), tostring(it.fly), tostring(it.ride)))
	end
	return tostring(raw.listingId or "") .. "|" .. table.concat(parts, ";")
end

function ListingScanner:ingestListing(raw: any, source: string?): (ScannedListing?, boolean)
	if type(raw) ~= "table" or type(raw.offeredItems) ~= "table" or type(raw.requestedItems) ~= "table" then
		return nil, false
	end
	local id = tostring(raw.listingId or ("manual_" .. tostring(#self._orderedIds + 1) .. "_" .. tostring(self._clock())))
	local sig = makeSignature(raw)
	local isNew = not self._seenSignatures[sig]
	self._seenSignatures[sig] = true

	-- Note: from our perspective, we GIVE requestedItems and RECEIVE offeredItems
	local res = self._evaluator:evaluate(raw.requestedItems, raw.offeredItems, { isExpired = raw.expired == true })
	local eval = res.evaluation

	local entry: ScannedListing = {
		listingId = id,
		sellerId = if raw.sellerId ~= nil then tostring(raw.sellerId) else nil,
		offeredItems = raw.offeredItems,
		requestedItems = raw.requestedItems,
		totalAmvggOffered = eval.theirValue,
		totalAmvggRequested = eval.yourValue,
		estimatedProfit = eval.potentialProfit,
		profitPercent = eval.percentDifference,
		confidenceStatus = res.confidence,
		listingStatus = res.listingStatus,
		liquidityNote = res.metrics.liquidityNote,
		riskScore = res.metrics.riskScore,
		timestamp = tonumber(raw.timestamp) or self._clock(),
		inspected = true,
		source = source or "manual",
	}

	if not self._listings[id] then
		table.insert(self._orderedIds, id)
	end
	self._listings[id] = entry
	return entry, isNew
end

function ListingScanner:scanOnce(): { ok: boolean, total: number, fresh: number, goodDeals: number, warning: string? }
	self._scanCount += 1
	self._lastScanAt = self._clock()

	if not (self._gameAdapter and type(self._gameAdapter.fetchListings) == "function") then
		local warnMsg = "Live Trade Hub listing adapter unavailable in this environment; use Manual/Import Listing Scanner"
		self._integrationWarning = warnMsg
		local all = self:getRankedOpportunities({})
		local good = 0
		for _, l in ipairs(all) do
			if l.listingStatus == "GOOD DEAL" then
				good += 1
			end
		end
		if self._state then
			self._state:set("scanner.warning", warnMsg, "ListingScanner")
			self._state:set("scanner.inspectedCount", #self._orderedIds, "ListingScanner")
			self._state:set("scanner.goodDealCount", good, "ListingScanner")
		end
		return { ok = false, total = #self._orderedIds, fresh = 0, goodDeals = good, warning = warnMsg }
	end

	self._integrationWarning = nil
	local ok, rawListings = pcall(self._gameAdapter.fetchListings)
	if not ok or type(rawListings) ~= "table" then
		local err = "Trade Hub scan failed: " .. tostring(rawListings)
		if self._logger then
			self._logger:warn("ListingScanner", err)
		end
		return { ok = false, total = #self._orderedIds, fresh = 0, goodDeals = 0, warning = err }
	end

	local fresh = 0
	local goodDeals = 0
	for _, raw in ipairs(rawListings) do
		local entry, isNew = self:ingestListing(raw, "game")
		if entry then
			if isNew then
				fresh += 1
			end
			if entry.listingStatus == "GOOD DEAL" then
				goodDeals += 1
			end
		end
	end

	if self._state then
		self._state:set("scanner.warning", nil, "ListingScanner")
		self._state:set("scanner.inspectedCount", #self._orderedIds, "ListingScanner")
		self._state:set("scanner.goodDealCount", goodDeals, "ListingScanner")
	end
	if self._eventBus then
		self._eventBus:emit("Scanner:Completed", {
			total = #self._orderedIds,
			fresh = fresh,
			goodDeals = goodDeals,
		})
	end

	return { ok = true, total = #self._orderedIds, fresh = fresh, goodDeals = goodDeals, warning = nil }
end

function ListingScanner:importJson(jsonText: string): (boolean, string?, number)
	if not (self._json and type(self._json.decode) == "function") then
		return false, "JSON decoder unavailable", 0
	end
	local ok, decoded = pcall(self._json.decode, jsonText)
	if not ok or type(decoded) ~= "table" then
		return false, "Malformed listing JSON", 0
	end
	local list = if type(decoded.listings) == "table" then decoded.listings else decoded
	local added = 0
	local goodDeals = 0
	for _, raw in ipairs(list) do
		local entry = self:ingestListing(raw, "import")
		if entry then
			added += 1
			if entry.listingStatus == "GOOD DEAL" then
				goodDeals += 1
			end
		end
	end
	if self._state then
		self._state:set("scanner.inspectedCount", #self._orderedIds, "ListingScanner")
		self._state:set("scanner.goodDealCount", goodDeals, "ListingScanner")
	end
	if self._eventBus then
		self._eventBus:emit("Scanner:Completed", { total = #self._orderedIds, fresh = added, goodDeals = goodDeals })
	end
	return true, nil, added
end

function ListingScanner:markExpired(listingId: string): boolean
	local item = self._listings[listingId]
	if not item then
		return false
	end
	item.listingStatus = "EXPIRED LISTING"
	return true
end

function ListingScanner:getRankedOpportunities(filters: {
	petQuery: string?,
	minValue: number?,
	minProfit: number?,
	minPctGain: number?,
	includeIncomplete: boolean?,
}?): { ScannedListing }
	local f = filters or {}
	local q = string.lower(tostring(f.petQuery or "")):match("^%s*(.-)%s*$") or ""
	local out = {}

	for _, id in ipairs(self._orderedIds) do
		local l = self._listings[id]
		if l and l.listingStatus ~= "EXPIRED LISTING" then
			local ok = true
			if not f.includeIncomplete and l.listingStatus == "INCOMPLETE DATA" then
				ok = false
			end
			if ok and f.minValue and l.totalAmvggOffered < f.minValue then
				ok = false
			end
			if ok and f.minProfit and l.estimatedProfit < f.minProfit then
				ok = false
			end
			if ok and f.minPctGain and l.profitPercent < f.minPctGain then
				ok = false
			end
			if ok and q ~= "" then
				local found = false
				for _, it in ipairs(l.offeredItems) do
					if string.find(string.lower(tostring(it.name or "")), q, 1, true) then
						found = true
						break
					end
				end
				if not found then
					for _, it in ipairs(l.requestedItems) do
						if string.find(string.lower(tostring(it.name or "")), q, 1, true) then
							found = true
							break
						end
					end
				end
				ok = found
			end
			if ok then
				table.insert(out, l)
			end
		end
	end

	table.sort(out, function(a, b)
		if a.estimatedProfit ~= b.estimatedProfit then
			return a.estimatedProfit > b.estimatedProfit
		end
		return a.profitPercent > b.profitPercent
	end)

	return out
end

function ListingScanner:getStats(): { inspectedCount: number, goodDeals: number, scanCount: number, lastScanAt: number?, warning: string? }
	local good = 0
	for _, id in ipairs(self._orderedIds) do
		local l = self._listings[id]
		if l and l.listingStatus == "GOOD DEAL" then
			good += 1
		end
	end
	return {
		inspectedCount = #self._orderedIds,
		goodDeals = good,
		scanCount = self._scanCount,
		lastScanAt = self._lastScanAt,
		warning = self._integrationWarning,
	}
end

return ListingScanner
