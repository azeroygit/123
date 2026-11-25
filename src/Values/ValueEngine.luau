--!strict
--[[
	ValueEngine.luau
	Computes individual pet values, offer totals, value differences, percentage
	gains, overpay/underpay %, and configurable deal ratings strictly from AMVGG.
	Marks missing or unverified variants as INCOMPLETE without faking accuracy.
]]

local ValueEngine = {}
ValueEngine.__index = ValueEngine

export type PetItem = {
	name: string,
	neon: boolean?,
	mega: boolean?,
	fly: boolean?,
	ride: boolean?,
	quantity: number?,
}

export type ItemEvaluation = {
	name: string,
	variantKey: string,
	variantLabel: string,
	unitValue: number?,
	totalValue: number?,
	quantity: number,
	demand: string?,
	complete: boolean,
	reason: string?,
}

export type TradeEvaluation = {
	yourValue: number,
	theirValue: number,
	difference: number,
	percentDifference: number,
	overpayPercent: number,
	underpayPercent: number,
	potentialProfit: number,
	rating: string, -- "EXCELLENT_DEAL" | "GOOD_DEAL" | "FAIR_TRADE" | "SMALL_LOSS" | "BAD_TRADE" | "INCOMPLETE"
	complete: boolean,
	missingItems: { string },
	yourBreakdown: { ItemEvaluation },
	theirBreakdown: { ItemEvaluation },
}

function ValueEngine.new(cache: any, validator: any, config: any)
	local self = setmetatable({}, ValueEngine)
	self._cache = cache
	self._validator = validator
	self._config = config
	return self
end

function ValueEngine.resolveVariant(item: PetItem): (string, string)
	local isMega = item.mega == true
	local isNeon = (not isMega) and (item.neon == true)
	local isFly = item.fly == true
	local isRide = item.ride == true

	if isMega then
		if isFly and isRide then
			return "mega", "MFR"
		elseif isFly then
			return "mf", "MF"
		elseif isRide then
			return "mr", "MR"
		else
			return "npMega", "M (No-Pot)"
		end
	elseif isNeon then
		if isFly and isRide then
			return "neon", "NFR"
		elseif isFly then
			return "nf", "NF"
		elseif isRide then
			return "nr", "NR"
		else
			return "npNeon", "N (No-Pot)"
		end
	else
		if isFly and isRide then
			return "regular", "FR"
		elseif isFly then
			return "f", "F"
		elseif isRide then
			return "r", "R"
		else
			return "npRegular", "No-Pot"
		end
	end
end

function ValueEngine:evaluatePet(item: PetItem): ItemEvaluation
	local qty = math.max(1, math.floor(tonumber(item.quantity) or 1))
	local variantKey, variantLabel = ValueEngine.resolveVariant(item)
	local record = self._cache:getPet(tostring(item.name or ""))

	if not record then
		return {
			name = tostring(item.name or "Unknown"),
			variantKey = variantKey,
			variantLabel = variantLabel,
			unitValue = nil,
			totalValue = nil,
			quantity = qty,
			demand = nil,
			complete = false,
			reason = "Pet not found in AMVGG dataset",
		}
	end

	local unitVal = record.values and record.values[variantKey]
	if type(unitVal) ~= "number" or unitVal <= 0 then
		return {
			name = record.name,
			variantKey = variantKey,
			variantLabel = variantLabel,
			unitValue = nil,
			totalValue = nil,
			quantity = qty,
			demand = record.demands and record.demands[variantKey] or nil,
			complete = false,
			reason = string.format("Missing AMVGG value for %s (%s)", record.name, variantLabel),
		}
	end

	return {
		name = record.name,
		variantKey = variantKey,
		variantLabel = variantLabel,
		unitValue = unitVal,
		totalValue = unitVal * qty,
		quantity = qty,
		demand = record.demands and record.demands[variantKey] or nil,
		complete = true,
		reason = nil,
	}
end

function ValueEngine:evaluateList(items: { PetItem }): { totalValue: number, complete: boolean, missingItems: { string }, breakdown: { ItemEvaluation } }
	local total = 0
	local complete = true
	local missing = {}
	local breakdown = {}

	if type(items) ~= "table" or #items == 0 then
		return { totalValue = 0, complete = false, missingItems = { "Empty item list" }, breakdown = {} }
	end

	for _, item in ipairs(items) do
		local ev = self:evaluatePet(item)
		table.insert(breakdown, ev)
		if ev.complete and ev.totalValue then
			total += ev.totalValue
		else
			complete = false
			table.insert(missing, ev.reason or ev.name)
		end
	end

	return {
		totalValue = total,
		complete = complete,
		missingItems = missing,
		breakdown = breakdown,
	}
end

function ValueEngine:classifyPercent(pctDiff: number): string
	local excellentMin = tonumber(self._config:get("Thresholds.ExcellentDealMinPct")) or 25.0
	local goodMin = tonumber(self._config:get("Thresholds.GoodDealMinPct")) or 8.0
	local fairMin = tonumber(self._config:get("Thresholds.FairTradeMinPct")) or -3.0
	local smallLossMin = tonumber(self._config:get("Thresholds.SmallLossMinPct")) or -12.0

	if pctDiff >= excellentMin then
		return "EXCELLENT_DEAL"
	elseif pctDiff >= goodMin then
		return "GOOD_DEAL"
	elseif pctDiff >= fairMin then
		return "FAIR_TRADE"
	elseif pctDiff >= smallLossMin then
		return "SMALL_LOSS"
	else
		return "BAD_TRADE"
	end
end

function ValueEngine:evaluateTrade(yourItems: { PetItem }, theirItems: { PetItem }): TradeEvaluation
	local yourRes = self:evaluateList(yourItems)
	local theirRes = self:evaluateList(theirItems)

	local missing = {}
	for _, m in ipairs(yourRes.missingItems) do
		table.insert(missing, "Your: " .. m)
	end
	for _, m in ipairs(theirRes.missingItems) do
		table.insert(missing, "Their: " .. m)
	end

	local complete = yourRes.complete and theirRes.complete and yourRes.totalValue > 0
	local diff = theirRes.totalValue - yourRes.totalValue
	local pct = if yourRes.totalValue > 0 then (diff / yourRes.totalValue) * 100 else 0
	local overpayPct = if diff < 0 and yourRes.totalValue > 0 then (math.abs(diff) / yourRes.totalValue) * 100 else 0
	local underpayPct = if diff > 0 and yourRes.totalValue > 0 then (diff / yourRes.totalValue) * 100 else 0

	local rating = if complete then self:classifyPercent(pct) else "INCOMPLETE"

	return {
		yourValue = yourRes.totalValue,
		theirValue = theirRes.totalValue,
		difference = diff,
		percentDifference = pct,
		overpayPercent = overpayPct,
		underpayPercent = underpayPct,
		potentialProfit = diff,
		rating = rating,
		complete = complete,
		missingItems = missing,
		yourBreakdown = yourRes.breakdown,
		theirBreakdown = theirRes.breakdown,
	}
end

return ValueEngine
