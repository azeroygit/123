--!strict
--[[
	Companion.luau
	Decoupled Kiria companion controller. Subscribes to EventBus events,
	updates Memory, produces Reactions, and notifies UI via `Kiria:Message`.
]]

local Companion = {}
Companion.__index = Companion

function Companion.new(deps: {
	personality: any,
	memory: any,
	reactions: any,
	eventBus: any?,
	config: any?,
	clockFn: (() -> number)?,
})
	local self = setmetatable({}, Companion)
	self._personality = deps.personality
	self._memory = deps.memory
	self._reactions = deps.reactions
	self._eventBus = deps.eventBus
	self._config = deps.config
	self._clock = deps.clockFn or os.time

	self._connections = {} :: { any }
	self._history = {} :: { { timestamp: number, event: string, message: string, mood: string } }
	self._lastMood = "calm"
	self:_bindEvents()
	return self
end

function Companion:_emitReaction(eventName: string, ctx: { [string]: any }?)
	if self._config and self._config:get("UI.KiriaEnabled") == false then
		return nil
	end
	local res = self._reactions.react(self._personality, self._memory, eventName, ctx, self._clock)
	self._lastMood = res.mood
	if res.message then
		local entry = {
			timestamp = self._clock(),
			event = eventName,
			message = res.message,
			mood = res.mood,
			rank = res.rank,
			xp = res.xp,
		}
		table.insert(self._history, entry)
		while #self._history > 100 do
			table.remove(self._history, 1)
		end
		if self._eventBus then
			self._eventBus:emit("Kiria:Message", entry)
		end
	end
	return res
end

function Companion:_bindEvents()
	if not self._eventBus then
		return
	end

	table.insert(self._connections, self._eventBus:subscribe("AMVGG:Refreshed", function(info)
		self:_emitReaction("amvgg_refresh", { petCount = info and info.petCount or 0 })
	end))

	table.insert(self._connections, self._eventBus:subscribe("AMVGG:Error", function(info)
		self:_emitReaction("amvgg_error", { error = info and info.message or "Unknown error" })
	end))

	table.insert(self._connections, self._eventBus:subscribe("Trade:Confirmed", function(trade)
		self._memory:recordConfirmedTrade(trade.profitValue or 0, trade.profitPercent or 0)
		local giveNames = {}
		for _, it in ipairs(trade.offeredItems or {}) do
			table.insert(giveNames, tostring(it.name))
		end
		local getNames = {}
		for _, it in ipairs(trade.receivedItems or {}) do
			table.insert(getNames, tostring(it.name))
		end
		self:_emitReaction("trade_confirmed", {
			give = table.concat(giveNames, " + "),
			get = table.concat(getNames, " + "),
			gain = trade.profitValue or 0,
			pct = trade.profitPercent or 0,
		})
	end))

	table.insert(self._connections, self._eventBus:subscribe("Offer:Queued", function(offer)
		if offer.evaluation and not offer.evaluation.complete then
			self:_emitReaction("incomplete_data", {})
		elseif (offer.profitPercent or 0) < 0 then
			self:_emitReaction("bad_offer", { pct = offer.profitPercent, gain = offer.profitValue })
		else
			self:_emitReaction("offer_queued", { pct = offer.profitPercent or 0 })
		end
	end))

	table.insert(self._connections, self._eventBus:subscribe("Offer:Expired", function()
		self:_emitReaction("offer_expired", {})
	end))

	table.insert(self._connections, self._eventBus:subscribe("Offer:StatusChanged", function(offer)
		if offer.status == "DECLINED" then
			self:_emitReaction("offer_declined", {})
		end
	end))

	table.insert(self._connections, self._eventBus:subscribe("Listing:Published", function(lst)
		self:_emitReaction("listing_published", { offeredValue = lst.offeredValue or 0 })
	end))

	table.insert(self._connections, self._eventBus:subscribe("Listing:Stale", function(info)
		self:_emitReaction("listing_stale", { age = info and info.ageSeconds or 60 })
	end))

	table.insert(self._connections, self._eventBus:subscribe("System:Error", function(info)
		self:_emitReaction("warning", { message = info and info.message or "Unexpected error" })
	end))
end

function Companion:startSession()
	self._memory:incrementSession()
	return self:_emitReaction("start", {})
end

function Companion:notifyGoodDeal(itemsLabel: string, pct: number, gain: number)
	return self:_emitReaction("good_deal", { items = itemsLabel, pct = pct, gain = gain })
end

function Companion:getStatus(): { mood: string, rank: string, xp: number, sessions: number, trades: number, latestMessage: string? }
	local data = self._memory:getData()
	local latest = self._history[#self._history]
	return {
		mood = self._lastMood,
		rank = self._personality.getRank(data.xp),
		xp = data.xp,
		sessions = data.sessions,
		trades = data.trades,
		latestMessage = latest and latest.message or nil,
	}
end

function Companion:getHistory(): { any }
	return table.clone(self._history)
end

function Companion:destroy()
	for _, conn in ipairs(self._connections) do
		if conn and type(conn.disconnect) == "function" then
			conn:disconnect()
		end
	end
	table.clear(self._connections)
end

return Companion
