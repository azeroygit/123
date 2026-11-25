--!strict
--[[
	Reactions.luau
	Maps real system/trading events to Kiria's dialogue and mood.
]]

local Reactions = {}

export type ReactionResult = {
	message: string?,
	mood: string,
	rank: string,
	xp: number,
	promoted: boolean,
}

function Reactions.react(personality: any, memory: any, eventName: string, ctx: { [string]: any }?, clockFn: (() -> number)?): ReactionResult
	local data = memory:getData()
	local rankBefore = personality.getRank(data.xp)
	local mergedCtx = if type(ctx) == "table" then table.clone(ctx) else {}
	mergedCtx.sessions = data.sessions
	mergedCtx.trades = data.trades

	local lines = personality.Lines
	local out = {}
	local mood = "calm"

	if eventName == "start" then
		local now = (clockFn or os.time)()
		mergedCtx.days = math.max(1, math.floor((now - (data.firstSeen or now)) / 86400) + 1)
		local hour = tonumber(os.date("%H", now)) or 12
		local bucket = if hour < 6 then "night" elseif hour < 12 then "morning" elseif hour < 18 then "day" else "evening"
		local hLine = personality.pickLine(lines.hello[bucket], mergedCtx)
		if hLine then
			table.insert(out, hLine)
		end
		local sLine = personality.pickLine(if data.sessions <= 1 then lines.intro else lines.returning, mergedCtx)
		if sLine then
			table.insert(out, sLine)
		end
		mood = "ready"
	elseif eventName == "trade_confirmed" then
		local gain = tonumber(mergedCtx.gain) or 0
		if gain < 0 then
			local l = personality.pickLine(lines.loss_trade, mergedCtx)
			if l then
				table.insert(out, l)
			end
			mood = "careful"
		else
			local l = personality.pickLine(lines.trade_confirmed, mergedCtx)
			if l then
				table.insert(out, l)
			end
			mood = if (tonumber(mergedCtx.pct) or 0) >= 25 then "excited" else "happy"
		end
	elseif eventName == "amvgg_refresh" then
		local l = personality.pickLine(lines.amvgg_refresh, mergedCtx)
		if l then
			table.insert(out, l)
		end
		mood = "pleased"
	elseif eventName == "amvgg_error" then
		local l = personality.pickLine(lines.amvgg_error, mergedCtx)
		if l then
			table.insert(out, l)
		end
		mood = "worried"
	elseif eventName == "good_deal" then
		local l = personality.pickLine(lines.good_deal, mergedCtx)
		if l then
			table.insert(out, l)
		end
		mood = "hopeful"
	elseif eventName == "bad_offer" then
		local l = personality.pickLine(lines.bad_offer, mergedCtx)
		if l then
			table.insert(out, l)
		end
		mood = "careful"
	elseif eventName == "listing_stale" then
		local l = personality.pickLine(lines.listing_stale, mergedCtx)
		if l then
			table.insert(out, l)
		end
		mood = "patient"
	elseif eventName == "incomplete_data" then
		local l = personality.pickLine(lines.incomplete_data, mergedCtx)
		if l then
			table.insert(out, l)
		end
		mood = "careful"
	else
		local l = personality.pickLine(lines[eventName], mergedCtx)
		if l then
			table.insert(out, l)
		end
	end

	local rankAfter = personality.getRank(data.xp)
	local promoted = rankAfter ~= rankBefore
	if promoted then
		mergedCtx.rank = rankAfter
		local pLine = personality.pickLine(lines.promotion, mergedCtx)
		if pLine then
			table.insert(out, pLine)
		end
		mood = "honored"
	end

	return {
		message = if #out > 0 then table.concat(out, "\n") else nil,
		mood = mood,
		rank = rankAfter,
		xp = data.xp,
		promoted = promoted,
	}
end

return Reactions
