--!strict
--[[
	TradeEvaluator.luau
	Combines ValueEngine and ProfitCalculator to evaluate trades and Trade Hub
	listings with normalized listing status tags.
]]

local TradeEvaluator = {}
TradeEvaluator.__index = TradeEvaluator

function TradeEvaluator.new(valueEngine: any, profitCalculator: any)
	local self = setmetatable({}, TradeEvaluator)
	self._valueEngine = valueEngine
	self._profitCalculator = profitCalculator
	return self
end

function TradeEvaluator:evaluate(yourItems: { any }, theirItems: { any }, options: { isExpired: boolean? }?): any
	local opts = options or {}
	local eval = self._valueEngine:evaluateTrade(yourItems, theirItems)
	local metrics = self._profitCalculator.analyze(eval)

	local listingStatus = "BAD DEAL"
	if opts.isExpired then
		listingStatus = "EXPIRED LISTING"
	elseif not eval.complete then
		listingStatus = "INCOMPLETE DATA"
	elseif eval.rating == "EXCELLENT_DEAL" or eval.rating == "GOOD_DEAL" then
		listingStatus = "GOOD DEAL"
	elseif eval.rating == "FAIR_TRADE" then
		listingStatus = "FAIR DEAL"
	else
		listingStatus = "BAD DEAL"
	end

	return {
		evaluation = eval,
		metrics = metrics,
		listingStatus = listingStatus,
		confidence = if eval.complete then "VERIFIED_AMVGG" else "INCOMPLETE",
	}
end

return TradeEvaluator
