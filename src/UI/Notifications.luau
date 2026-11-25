--!strict
--[[
	Notifications.luau
	Toast notification manager subscribed to EventBus events.
]]

local Notifications = {}
Notifications.__index = Notifications

export type Toast = {
	id: number,
	title: string,
	message: string,
	level: string, -- "info" | "success" | "warn" | "error"
	timestamp: number,
}

function Notifications.new(deps: { eventBus: any?, config: any?, clockFn: (() -> number)? })
	local self = setmetatable({}, Notifications)
	self._eventBus = deps.eventBus
	self._config = deps.config
	self._clock = deps.clockFn or os.time
	self._toasts = {} :: { Toast }
	self._nextId = 1
	self._connections = {} :: { any }
	self:_bindEvents()
	return self
end

function Notifications:push(level: string, title: string, message: string): Toast?
	if self._config and self._config:get("UI.NotificationsEnabled") == false then
		return nil
	end
	self._nextId += 1
	local toast: Toast = {
		id = self._nextId,
		title = title,
		message = message,
		level = level,
		timestamp = self._clock(),
	}
	table.insert(self._toasts, toast)
	while #self._toasts > 50 do
		table.remove(self._toasts, 1)
	end
	if self._eventBus then
		self._eventBus:emit("UI:Toast", toast)
	end
	return toast
end

function Notifications:_bindEvents()
	if not self._eventBus then
		return
	end
	table.insert(self._connections, self._eventBus:subscribe("AMVGG:Refreshed", function(info)
		self:push("success", "AMVGG Updated", string.format("Loaded %d pets from AMVGG.", info and info.petCount or 0))
	end))
	table.insert(self._connections, self._eventBus:subscribe("AMVGG:Error", function(info)
		self:push("warn", "AMVGG Refresh Issue", tostring(info and info.message or "Preserved last valid cache"))
	end))
	table.insert(self._connections, self._eventBus:subscribe("Listing:Stale", function(info)
		self:push("warn", "Stale Listing", string.format("Listing aged %ds without a match.", info and info.ageSeconds or 60))
	end))
	table.insert(self._connections, self._eventBus:subscribe("Offer:NoResponse", function(info)
		self:push("info", "Offer Waiting", string.format("Offer pending for %ds with no response.", info and info.ageSeconds or 0))
	end))
	table.insert(self._connections, self._eventBus:subscribe("Offer:Expired", function(offer)
		self:push("warn", "Offer Expired", "Offer " .. tostring(offer and offer.offerId or "") .. " expired.")
	end))
	table.insert(self._connections, self._eventBus:subscribe("Trade:Confirmed", function(trade)
		self:push("success", "Trade Confirmed", string.format("Confirmed %+.2f AMVGG profit.", trade and trade.profitValue or 0))
	end))
end

function Notifications:getRecent(limit: number?): { Toast }
	local max = limit or 10
	local out = {}
	local startIdx = math.max(1, #self._toasts - max + 1)
	for i = startIdx, #self._toasts do
		table.insert(out, self._toasts[i])
	end
	return out
end

function Notifications:clear()
	table.clear(self._toasts)
end

function Notifications:destroy()
	for _, c in ipairs(self._connections) do
		if c and type(c.disconnect) == "function" then
			c:disconnect()
		end
	end
	table.clear(self._connections)
end

return Notifications
