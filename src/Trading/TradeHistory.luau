--!strict
--[[
	TradeHistory.luau
	Persistent analytics and trade history tracker.
	Strictly separates Potential Profit, Pending Profit, and Confirmed Profit
	so only verified completed trades count as realized profit.
]]

local TradeHistory = {}
TradeHistory.__index = TradeHistory

export type CompletedTrade = {
	id: string,
	timestamp: number,
	offeredItems: { any },
	receivedItems: { any },
	offeredValue: number,
	receivedValue: number,
	profitValue: number,
	profitPercent: number,
	source: string, -- "manual_confirmed" | "game_verified"
}

function TradeHistory.new(options: { filePath: string?, fs: any?, json: any?, eventBus: any?, clockFn: (() -> number)? }?)
	local opts = options or {}
	local self = setmetatable({}, TradeHistory)
	self._filePath = opts.filePath or "KiriaAutoTrader/analytics.json"
	self._fs = opts.fs
	self._json = opts.json
	self._eventBus = opts.eventBus
	self._clock = opts.clockFn or os.time

	self._trades = {} :: { CompletedTrade }
	self._counters = {
		inspectedListings = 0,
		goodDeals = 0,
		draftedOffers = 0,
		submittedOffers = 0,
		acceptedTrades = 0,
		declinedOffers = 0,
		expiredOffers = 0,
		cancelledOffers = 0,
	}
	return self
end

function TradeHistory:recordListingStats(inspectedDelta: number, goodDealsDelta: number)
	self._counters.inspectedListings += math.max(0, inspectedDelta)
	self._counters.goodDeals += math.max(0, goodDealsDelta)
	self:save()
end

function TradeHistory:recordOfferOutcome(outcome: string)
	if outcome == "DRAFTED" then
		self._counters.draftedOffers += 1
	elseif outcome == "SUBMITTED" or outcome == "PENDING" then
		self._counters.submittedOffers += 1
	elseif outcome == "DECLINED" then
		self._counters.declinedOffers += 1
	elseif outcome == "EXPIRED" then
		self._counters.expiredOffers += 1
	elseif outcome == "CANCELLED" then
		self._counters.cancelledOffers += 1
	end
	self:save()
end

function TradeHistory:recordConfirmedTrade(trade: {
	id: string?,
	offeredItems: { any },
	receivedItems: { any },
	offeredValue: number,
	receivedValue: number,
	source: string?,
}): CompletedTrade
	local diff = trade.receivedValue - trade.offeredValue
	local pct = if trade.offeredValue > 0 then (diff / trade.offeredValue) * 100 else 0
	local entry: CompletedTrade = {
		id = tostring(trade.id or ("trd_" .. tostring(self._clock()) .. "_" .. tostring(#self._trades + 1))),
		timestamp = self._clock(),
		offeredItems = trade.offeredItems,
		receivedItems = trade.receivedItems,
		offeredValue = trade.offeredValue,
		receivedValue = trade.receivedValue,
		profitValue = diff,
		profitPercent = pct,
		source = trade.source or "manual_confirmed",
	}
	table.insert(self._trades, entry)
	self._counters.acceptedTrades += 1
	self:save()

	if self._eventBus then
		self._eventBus:emit("Trade:Confirmed", entry)
	end
	return entry
end

function TradeHistory:getSummary(context: {
	potentialProfit: number?,
	pendingProfit: number?,
	inventoryValue: number?,
}?): {
	counters: any,
	confirmedProfit: number,
	pendingProfit: number,
	potentialProfit: number,
	averageProfit: number,
	bestTrade: CompletedTrade?,
	worstTrade: CompletedTrade?,
	acceptanceRate: number,
	currentInventoryValue: number,
	bestPerformingPets: { { name: string, totalProfit: number, trades: number } },
	profitSeries: { { timestamp: number, cumulativeProfit: number } },
}
	local ctx = context or {}
	local confirmedTotal = 0
	local best: CompletedTrade? = nil
	local worst: CompletedTrade? = nil
	local petPerf: { [string]: { name: string, totalProfit: number, trades: number } } = {}
	local series = {}

	for _, t in ipairs(self._trades) do
		confirmedTotal += t.profitValue
		if not best or t.profitValue > best.profitValue then
			best = t
		end
		if not worst or t.profitValue < worst.profitValue then
			worst = t
		end
		table.insert(series, { timestamp = t.timestamp, cumulativeProfit = confirmedTotal })

		for _, pet in ipairs(t.receivedItems) do
			local name = tostring(pet.name or "Unknown")
			if not petPerf[name] then
				petPerf[name] = { name = name, totalProfit = 0, trades = 0 }
			end
			petPerf[name].totalProfit += t.profitValue
			petPerf[name].trades += 1
		end
	end

	local topPets = {}
	for _, p in pairs(petPerf) do
		table.insert(topPets, p)
	end
	table.sort(topPets, function(a, b)
		return a.totalProfit > b.totalProfit
	end)

	local resolved = self._counters.acceptedTrades + self._counters.declinedOffers + self._counters.expiredOffers
	local acceptanceRate = if resolved > 0 then (self._counters.acceptedTrades / resolved) * 100 else 0
	local avgProfit = if #self._trades > 0 then confirmedTotal / #self._trades else 0

	return {
		counters = table.clone(self._counters),
		confirmedProfit = confirmedTotal,
		pendingProfit = ctx.pendingProfit or 0,
		potentialProfit = ctx.potentialProfit or 0,
		averageProfit = avgProfit,
		bestTrade = best,
		worstTrade = worst,
		acceptanceRate = acceptanceRate,
		currentInventoryValue = ctx.inventoryValue or 0,
		bestPerformingPets = topPets,
		profitSeries = series,
	}
end

function TradeHistory:getTrades(): { CompletedTrade }
	return table.clone(self._trades)
end

function TradeHistory:save(): boolean
	if not (self._fs and self._json and self._fs.write) then
		return false
	end
	local okEnc, encoded = pcall(self._json.encode, {
		counters = self._counters,
		trades = self._trades,
	})
	if not okEnc or type(encoded) ~= "string" then
		return false
	end
	return pcall(self._fs.write, self._filePath, encoded)
end

function TradeHistory:load(): boolean
	if not (self._fs and self._json and self._fs.exists and self._fs.read) then
		return false
	end
	if not self._fs.exists(self._filePath) then
		return false
	end
	local okRead, raw = pcall(self._fs.read, self._filePath)
	if not okRead or type(raw) ~= "string" then
		return false
	end
	local okDec, decoded = pcall(self._json.decode, raw)
	if not okDec or type(decoded) ~= "table" then
		return false
	end
	if type(decoded.counters) == "table" then
		for k, v in pairs(decoded.counters) do
			if self._counters[k] ~= nil and type(v) == "number" then
				self._counters[k] = v
			end
		end
	end
	if type(decoded.trades) == "table" then
		self._trades = decoded.trades
	end
	return true
end

return TradeHistory
