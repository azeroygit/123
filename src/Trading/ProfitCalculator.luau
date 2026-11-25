--!strict
--[[
	ProfitCalculator.luau
	Computes AMVGG profit, risk score, and demand/liquidity notes.
	Explicitly avoids assuming equal AMVGG value means equal trade liquidity.
]]

local ProfitCalculator = {}

local DEMAND_SCORE = {
	High = 1.0,
	Medium = 0.65,
	Low = 0.3,
}

export type ProfitMetrics = {
	profitValue: number,
	profitPercent: number,
	riskScore: number, -- 0 (low risk) to 100 (high risk)
	liquidityNote: string,
}

local function averageDemandScore(breakdown: { any }): (number, boolean)
	if #breakdown == 0 then
		return 0.5, false
	end
	local sum = 0
	local counted = 0
	for _, item in ipairs(breakdown) do
		local d = item.demand
		if type(d) == "string" and DEMAND_SCORE[d] then
			sum += DEMAND_SCORE[d]
			counted += 1
		end
	end
	if counted == 0 then
		return 0.5, false
	end
	return sum / counted, true
end

function ProfitCalculator.analyze(evaluation: any): ProfitMetrics
	local profitVal = evaluation.difference or 0
	local profitPct = evaluation.percentDifference or 0

	if not evaluation.complete then
		return {
			profitValue = profitVal,
			profitPercent = profitPct,
			riskScore = 100,
			liquidityNote = "Incomplete AMVGG data; cannot verify liquidity or risk",
		}
	end

	local yourDemand, hasYourD = averageDemandScore(evaluation.yourBreakdown or {})
	local theirDemand, hasTheirD = averageDemandScore(evaluation.theirBreakdown or {})

	local risk = 20
	-- Receiving many low-demand items or downgrading into many items increases liquidity risk
	local theirCount = #(evaluation.theirBreakdown or {})
	local yourCount = #(evaluation.yourBreakdown or {})
	if theirCount > yourCount + 2 then
		risk += 15
	end
	if theirDemand < yourDemand then
		risk += math.floor((yourDemand - theirDemand) * 40)
	end
	if profitPct < 0 then
		risk += math.min(40, math.abs(profitPct))
	end
	if not hasYourD or not hasTheirD then
		risk += 10
	end
	risk = math.clamp(math.floor(risk), 0, 100)

	local note = "Balanced AMVGG demand"
	if theirDemand < 0.5 and yourDemand >= 0.7 then
		note = "Caution: equal/higher AMVGG value may have lower trade liquidity (downgrading demand)"
	elseif theirDemand >= 0.85 then
		note = "High-demand target pets; strong AMVGG liquidity"
	elseif theirCount > yourCount + 2 then
		note = "Multi-pet downgrade: verify slot liquidity before confirming"
	end

	return {
		profitValue = profitVal,
		profitPercent = profitPct,
		riskScore = risk,
		liquidityNote = note,
	}
end

return ProfitCalculator
