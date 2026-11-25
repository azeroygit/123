--!strict
--[[
	EventBus.luau
	Decoupled publish/subscribe event bus with safe listener invocation,
	one-shot subscriptions, and clean disconnection to prevent memory leaks.
]]

local EventBus = {}
EventBus.__index = EventBus

export type Connection = {
	connected: boolean,
	disconnect: (self: Connection) -> (),
}

function EventBus.new(logger: any?)
	local self = setmetatable({}, EventBus)
	self._listeners = {} :: { [string]: { { id: number, fn: (...any) -> () } } }
	self._nextId = 0
	self._logger = logger
	return self
end

function EventBus:subscribe(eventName: string, callback: (...any) -> ()): Connection
	assert(type(eventName) == "string" and eventName ~= "", "EventBus:subscribe requires a non-empty event name")
	assert(type(callback) == "function", "EventBus:subscribe requires a callback function")

	self._nextId += 1
	local id = self._nextId
	local bucket = self._listeners[eventName]
	if not bucket then
		bucket = {}
		self._listeners[eventName] = bucket
	end
	table.insert(bucket, { id = id, fn = callback })

	local connection = { connected = true }
	function connection:disconnect()
		if not self.connected then
			return
		end
		self.connected = false
		local list = bucket
		if not list then
			return
		end
		for i, item in ipairs(list) do
			if item.id == id then
				table.remove(list, i)
				break
			end
		end
	end

	return connection :: any
end

function EventBus:once(eventName: string, callback: (...any) -> ()): Connection
	local conn: Connection
	conn = self:subscribe(eventName, function(...)
		conn:disconnect()
		callback(...)
	end)
	return conn
end

function EventBus:emit(eventName: string, ...: any)
	local bucket = self._listeners[eventName]
	if not bucket or #bucket == 0 then
		return
	end

	local snapshot = table.clone(bucket)
	for _, item in ipairs(snapshot) do
		local ok, err = pcall(item.fn, ...)
		if not ok and self._logger then
			self._logger:error("EventBus", string.format("Listener error on '%s': %s", eventName, tostring(err)))
		end
	end
end

function EventBus:listenerCount(eventName: string): number
	local bucket = self._listeners[eventName]
	return bucket and #bucket or 0
end

function EventBus:clear(eventName: string?)
	if eventName then
		self._listeners[eventName] = nil
	else
		table.clear(self._listeners)
	end
end

function EventBus:destroy()
	table.clear(self._listeners)
end

return EventBus
