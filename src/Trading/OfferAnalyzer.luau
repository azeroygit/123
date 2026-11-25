--!strict
--[[
	OfferAnalyzer.luau
	Inventory-aware multi-pet offer optimizer.
	Generates and ranks candidate combinations of owned, unlocked, unreserved pets
	where offered AMVGG value is lower than target AMVGG value (profit-positive),
	with no duplicate pet instances and configurable constraints.
]]

local OfferAnalyzer = {}
OfferAnalyzer.__index = OfferAnalyzer

export type OfferCandidate = {
	offeredPets: { any },
	targetItems: { any },
	offeredValue: number,
	targetValue: number,
	profitValue: number,
	profitPercent: number,
	riskScore: number,
	liquidityNote: string,
	score: number,
}

function OfferAnalyzer.new(deps: {
	inventoryReader: any,
	valueEngine: any,
	profitCalculator: any,
	config: any,
})
	local self = setmetatable({}, OfferAnalyzer)
	self._inventory = deps.inventoryReader
	self._valueEngine = deps.valueEngine
	self._profitCalc = deps.profitCalculator
	self._config = deps.config
	return self
end

function OfferAnalyzer:generateCandidates(targetItems: { any }, options: {
	reservedUids: { [string]: boolean }?,
	maxItems: number?,
	minProfit: number?,
	minPctGain: number?,
	maxOverpayPct: number?,
	maxCandidates: number?,
}?): { candidates: { OfferCandidate }, targetComplete: boolean, reason: string? }
	local opts = options or {}
	local targetEval = self._valueEngine:evaluateList(targetItems)
	if not targetEval.complete or targetEval.totalValue <= 0 then
		return {
			candidates = {},
			targetComplete = false,
			reason = "Target items have incomplete AMVGG valuation",
		}
	end

	local targetVal = targetEval.totalValue
	local maxItems = math.clamp(opts.maxItems or tonumber(self._config:get("Trading.MaxItemsPerOffer")) or 4, 1, 9)
	local minProfit = opts.minProfit or tonumber(self._config:get("Trading.MinProfitValue")) or 0
	local minPct = opts.minPctGain or tonumber(self._config:get("Trading.MinProfitPercent")) or 0
	local maxOverpayPct = opts.maxOverpayPct or tonumber(self._config:get("Trading.MaxOverpayPercent")) or 0
	local maxCandidates = opts.maxCandidates or 8
	local reserved = opts.reservedUids or {}

	-- Build pool of eligible owned, unlocked, non-favorite, unreserved pets with valid AMVGG values
	local pool = {}
	for _, pet in ipairs(self._inventory:getTradeable()) do
		if not reserved[pet.uid] then
			local ev = self._valueEngine:evaluatePet(pet)
			if ev.complete and ev.unitValue and ev.unitValue > 0 then
				table.insert(pool, { pet = pet, value = ev.unitValue, ev = ev })
			end
		end
	end

	-- Sort descending by value and cap search pool for fast, bounded combinatorics
	table.sort(pool, function(a, b)
		return a.value > b.value
	end)
	local searchPoolSize = math.min(#pool, 18)

	local maxAllowedOfferVal = targetVal * (1 + maxOverpayPct / 100)
	local rawCombos = {} :: { { indices: { number }, total: number } }
	local seenKeys = {} :: { [string]: boolean }

	local function search(startIdx: number, chosen: { number }, currentSum: number)
		if #chosen > 0 and currentSum <= maxAllowedOfferVal then
			local profit = targetVal - currentSum
			local pct = if currentSum > 0 then (profit / currentSum) * 100 else 0
			if profit >= minProfit and pct >= minPct then
				local keyParts = {}
				for _, idx in ipairs(chosen) do
					table.insert(keyParts, pool[idx].pet.uid)
				end
				local sig = table.concat(keyParts, ",")
				if not seenKeys[sig] then
					seenKeys[sig] = true
					table.insert(rawCombos, { indices = table.clone(chosen), total = currentSum })
				end
			end
		end

		if #chosen >= maxItems or #rawCombos >= 64 then
			return
		end

		for i = startIdx, searchPoolSize do
			local nextSum = currentSum + pool[i].value
			if nextSum <= maxAllowedOfferVal then
				table.insert(chosen, i)
				search(i + 1, chosen, nextSum)
				table.remove(chosen)
			end
		end
	end

	search(1, {}, 0)

	local candidates: { OfferCandidate } = {}
	for _, combo in ipairs(rawCombos) do
		local offeredPets = {}
		for _, idx in ipairs(combo.indices) do
			table.insert(offeredPets, pool[idx].pet)
		end

		local eval = self._valueEngine:evaluateTrade(offeredPets, targetItems)
		if eval.complete then
			local metrics = self._profitCalc.analyze(eval)
			-- Score balances profit %, absolute profit, and lower risk
			local score = (eval.percentDifference * 1.5) + (eval.difference * 0.5) - (metrics.riskScore * 0.25)
			table.insert(candidates, {
				offeredPets = offeredPets,
				targetItems = targetItems,
				offeredValue = eval.yourValue,
				targetValue = eval.theirValue,
				profitValue = eval.difference,
				profitPercent = eval.percentDifference,
				riskScore = metrics.riskScore,
				liquidityNote = metrics.liquidityNote,
				score = score,
			})
		end
	end

	table.sort(candidates, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.profitValue > b.profitValue
	end)

	if #candidates > maxCandidates then
		local trimmed = {}
		for i = 1, maxCandidates do
			trimmed[i] = candidates[i]
		end
		candidates = trimmed
	end

	return {
		candidates = candidates,
		targetComplete = true,
		reason = if #candidates == 0 then "No owned pet combinations meet min profit / % gain constraints" else nil,
	}
end

return OfferAnalyzer
