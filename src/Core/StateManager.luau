--!strict
--[[
	StateManager.luau
	Centralized reactive key-value state store with source attribution,
	shallow-equality deduplication, and EventBus/listener notifications.
]]

local StateManager = {}
StateManager.__index = StateManager

local function shallowEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in pairs(a) do
		if b[k] ~= v then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function StateManager.new(eventBus: any?)
	local self = setmetatable({}, StateManager)
	self._values = {} :: { [string]: any }
	self._meta = {} :: { [string]: { source: string, updatedAt: number } }
	self._watchers = {} :: { [string]: { (any, any) -> () } }
	self._eventBus = eventBus
	return self
end

function StateManager:set(key: string, value: any, source: string?): boolean
	assert(type(key) == "string" and key ~= "", "StateManager:set requires a key")
	local src = (type(source) == "string" and source ~= "") and source or "System"
	local oldValue = self._values[key]
	self._meta[key] = { source = src, updatedAt = os.time() }

	if shallowEqual(oldValue, value) then
		return false
	end

	self._values[key] = value

	local watchers = self._watchers[key]
	if watchers then
		for _, fn in ipairs(table.clone(watchers)) do
			pcall(fn, value, oldValue)
		end
	end

	if self._eventBus then
		self._eventBus:emit("State:Changed", key, value, oldValue, src)
	end
	return true
end

function StateManager:get(key: string, defaultValue: any?): any
	local v = self._values[key]
	if v == nil then
		return defaultValue
	end
	return v
end

function StateManager:increment(key: string, delta: number?, source: string?): number
	local nextVal = (tonumber(self._values[key]) or 0) + (delta or 1)
	self:set(key, nextVal, source)
	return nextVal
end

function StateManager:getMeta(key: string): { source: string, updatedAt: number }?
	return self._meta[key]
end

function StateManager:age(key: string): number?
	local meta = self._meta[key]
	return meta and (os.time() - meta.updatedAt) or nil
end

function StateManager:watch(key: string, callback: (any, any) -> ()): () -> ()
	local list = self._watchers[key]
	if not list then
		list = {}
		self._watchers[key] = list
	end
	table.insert(list, callback)
	return function()
		for i, fn in ipairs(list) do
			if fn == callback then
				table.remove(list, i)
				break
			end
		end
	end
end

function StateManager:snapshot(): { [string]: any }
	return table.clone(self._values)
end

function StateManager:destroy()
	table.clear(self._watchers)
	table.clear(self._values)
	table.clear(self._meta)
end

return StateManager
