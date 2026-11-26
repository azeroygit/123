--[[
  KIRIA AUTOTRADER (Standalone Single-File Bundle)
  Exclusive AMVGG Valuation (https://amvgg.com/values/pets)
  Generated from src/ modules. Zero globals, zero circular dependencies.
]]

local __moduleSources = {}
local __moduleCache = {}
local __LOADING = {}
local function import(moduleName)
    local cached = __moduleCache[moduleName]
    if cached == __LOADING then error("Circular import: " .. moduleName, 2) end
    if cached ~= nil then return cached end
    local source = __moduleSources[moduleName]
    if not source then error("Unknown module: " .. moduleName, 2) end
    __moduleCache[moduleName] = __LOADING
    local result = source(import)
    __moduleCache[moduleName] = result
    return result
end

__moduleSources["Core/Logger"] = function(...)
--[[
	Logger.luau
	Structured level-filtered logger with ring-buffer history, listener hooks,
	and optional file persistence. No global state.
]]

local Logger = {}
Logger.__index = Logger

Logger.Levels = {
	DEBUG = 1,
	INFO = 2,
	SUCCESS = 3,
	WARN = 4,
	ERROR = 5,
	OFF = 99,
}

local LEVEL_NAMES = {
	[1] = "DEBUG",
	[2] = "INFO",
	[3] = "SUCCESS",
	[4] = "WARN",
	[5] = "ERROR",
}

export type LogEntry = {
	timestamp: number,
	level: string,
	source: string,
	message: string,
}

function Logger.new(options: { level: string?, maxEntries: number?, filePath: string?, fs: any? }?)
	local opts = options or {}
	local self = setmetatable({}, Logger)
	self._level = Logger.Levels[opts.level or "INFO"] or Logger.Levels.INFO
	self._maxEntries = math.max(50, opts.maxEntries or 400)
	self._entries = {} :: { LogEntry }
	self._listeners = {} :: { (LogEntry) -> () }
	self._filePath = opts.filePath
	self._fs = opts.fs
	return self
end

function Logger:setLevel(levelName: string)
	local rank = Logger.Levels[levelName]
	if rank then
		self._level = rank
	end
end

function Logger:getLevel(): string
	return LEVEL_NAMES[self._level] or "OFF"
end

function Logger:onLog(callback: (LogEntry) -> ()): () -> ()
	table.insert(self._listeners, callback)
	return function()
		for i, fn in ipairs(self._listeners) do
			if fn == callback then
				table.remove(self._listeners, i)
				break
			end
		end
	end
end

function Logger:log(levelName: string, source: string, message: string)
	local rank = Logger.Levels[levelName] or Logger.Levels.INFO
	if rank < self._level then
		return
	end

	local entry: LogEntry = {
		timestamp = os.time(),
		level = levelName,
		source = tostring(source or "System"),
		message = tostring(message or ""),
	}

	table.insert(self._entries, entry)
	while #self._entries > self._maxEntries do
		table.remove(self._entries, 1)
	end

	if self._filePath and self._fs and type(self._fs.append) == "function" then
		local line = string.format("[%s][%s][%s] %s\n", os.date("%Y-%m-%d %H:%M:%S", entry.timestamp), entry.level, entry.source, entry.message)
		pcall(self._fs.append, self._filePath, line)
	end

	if type(game) == "userdata" then
		local out = string.format("[KIRIA][%s][%s] %s", entry.level, entry.source, entry.message)
		if entry.level == "WARN" or entry.level == "ERROR" then
			warn(out)
		else
			print(out)
		end
	end

	for _, listener in ipairs(table.clone(self._listeners)) do
		pcall(listener, entry)
	end
end

function Logger:debug(source: string, message: string)
	self:log("DEBUG", source, message)
end

function Logger:info(source: string, message: string)
	self:log("INFO", source, message)
end

function Logger:success(source: string, message: string)
	self:log("SUCCESS", source, message)
end

function Logger:warn(source: string, message: string)
	self:log("WARN", source, message)
end

function Logger:error(source: string, message: string)
	self:log("ERROR", source, message)
end

function Logger:getEntries(limit: number?): { LogEntry }
	if not limit or limit >= #self._entries then
		return table.clone(self._entries)
	end
	local out = {}
	local startIdx = math.max(1, #self._entries - limit + 1)
	for i = startIdx, #self._entries do
		table.insert(out, self._entries[i])
	end
	return out
end

function Logger:clear()
	table.clear(self._entries)
end

function Logger:destroy()
	table.clear(self._listeners)
	table.clear(self._entries)
end

return Logger

end

__moduleSources["Core/EventBus"] = function(...)
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

end

__moduleSources["Core/StateManager"] = function(...)
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

end

__moduleSources["Core/ErrorHandler"] = function(...)
--[[
	ErrorHandler.luau
	Safe execution wrappers, error classification, and exponential backoff
	retry utility for network and parser operations.
]]

local ErrorHandler = {}
ErrorHandler.__index = ErrorHandler

export type RetryOptions = {
	maxAttempts: number?,
	baseDelay: number?,
	maxDelay: number?,
	backoffFactor: number?,
	shouldRetry: ((string) -> boolean)?,
	sleepFn: ((number) -> ())?,
}

function ErrorHandler.new(logger: any?, eventBus: any?)
	local self = setmetatable({}, ErrorHandler)
	self._logger = logger
	self._eventBus = eventBus
	self._errorCount = 0
	return self
end

function ErrorHandler:try(context: string, fn: (...any) -> ...any, ...: any): (boolean, ...any)
	local results = table.pack(pcall(fn, ...))
	if results[1] then
		return true, table.unpack(results, 2, results.n)
	end

	self._errorCount += 1
	local errMsg = tostring(results[2])
	if self._logger then
		self._logger:error(context, errMsg)
	end
	if self._eventBus then
		self._eventBus:emit("System:Error", {
			context = context,
			message = errMsg,
			timestamp = os.time(),
		})
	end
	return false, errMsg
end

function ErrorHandler:retry(context: string, fn: () -> (boolean, any), options: RetryOptions?): (boolean, any, number)
	local opts = options or {}
	local maxAttempts = math.max(1, opts.maxAttempts or 3)
	local delaySec = math.max(0.05, opts.baseDelay or 1.0)
	local maxDelay = math.max(delaySec, opts.maxDelay or 16.0)
	local factor = math.max(1.0, opts.backoffFactor or 2.0)
	local sleepFn = opts.sleepFn or function(sec: number)
		if type(task) == "table" and type(task.wait) == "function" then
			task.wait(sec)
		end
	end

	local lastErr: any = nil
	for attempt = 1, maxAttempts do
		local ok, res1, res2 = pcall(fn)
		if ok and res1 then
			return true, res2, attempt
		end

		lastErr = if ok then res2 else res1
		local errStr = tostring(lastErr)
		if self._logger then
			self._logger:warn(context, string.format("Attempt %d/%d failed: %s", attempt, maxAttempts, errStr))
		end

		if opts.shouldRetry and not opts.shouldRetry(errStr) then
			return false, lastErr, attempt
		end

		if attempt < maxAttempts then
			sleepFn(delaySec)
			delaySec = math.min(maxDelay, delaySec * factor)
		end
	end

	self._errorCount += 1
	if self._eventBus then
		self._eventBus:emit("System:Error", {
			context = context,
			message = tostring(lastErr),
			timestamp = os.time(),
			attempts = maxAttempts,
		})
	end
	return false, lastErr, maxAttempts
end

function ErrorHandler:getErrorCount(): number
	return self._errorCount
end

return ErrorHandler

end

__moduleSources["Core/TaskScheduler"] = function(...)
--[[
	TaskScheduler.luau
	Non-blocking cooperative job scheduler with deduplication, failure circuit-breaker,
	pause/resume, and full thread cancellation on stop/destroy.
]]

local TaskScheduler = {}
TaskScheduler.__index = TaskScheduler

local DEFAULT_TICK_SECONDS = 0.25
local SLOW_JOB_SECONDS = 2.0
local MAX_CONSECUTIVE_FAILURES = 5

export type JobOptions = {
	runImmediately: boolean?,
	enabled: boolean?,
}

function TaskScheduler.new(logger: any?, tickSeconds: number?, clockFn: (() -> number)?)
	local self = setmetatable({}, TaskScheduler)
	self._logger = logger
	self._tickSeconds = math.max(0.05, tickSeconds or DEFAULT_TICK_SECONDS)
	self._clock = clockFn or os.clock
	self._jobs = {} :: { [string]: any }
	self._order = {} :: { string }
	self._running = false
	self._paused = false
	self._thread = nil :: thread?
	self.TickCount = 0
	return self
end

function TaskScheduler:addJob(name: string, intervalSeconds: number, callback: (number) -> (), options: JobOptions?)
	assert(type(name) == "string" and name ~= "", "TaskScheduler:addJob requires a job name")
	assert(type(callback) == "function", "TaskScheduler:addJob requires a callback")

	if self._jobs[name] then
		-- Prevent duplicate scan/timer loops by replacing cleanly
		self:removeJob(name)
	end

	local opts = options or {}
	local now = self._clock()
	self._jobs[name] = {
		name = name,
		interval = math.max(0.1, intervalSeconds),
		callback = callback,
		nextRun = if opts.runImmediately then 0 else (now + intervalSeconds),
		failures = 0,
		enabled = if opts.enabled == nil then true else opts.enabled,
		runs = 0,
		inFlight = false,
	}
	table.insert(self._order, name)
end

function TaskScheduler:removeJob(name: string)
	self._jobs[name] = nil
	for i, jobName in ipairs(self._order) do
		if jobName == name then
			table.remove(self._order, i)
			break
		end
	end
end

function TaskScheduler:setJobInterval(name: string, intervalSeconds: number)
	local job = self._jobs[name]
	if job then
		job.interval = math.max(0.1, intervalSeconds)
	end
end

function TaskScheduler:setJobEnabled(name: string, enabled: boolean)
	local job = self._jobs[name]
	if job then
		job.enabled = enabled
		if enabled then
			job.failures = 0
		end
	end
end

function TaskScheduler:getJob(name: string): any?
	return self._jobs[name]
end

function TaskScheduler:_runJob(job: any, now: number)
	if job.inFlight then
		return
	end
	job.inFlight = true
	job.nextRun = now + job.interval

	local startedAt = self._clock()
	local ok, err = pcall(job.callback, now)
	local duration = self._clock() - startedAt
	job.runs += 1
	job.inFlight = false

	if duration > SLOW_JOB_SECONDS and self._logger then
		self._logger:warn("TaskScheduler", string.format("Job '%s' took %.2fs", job.name, duration))
	end

	if ok then
		job.failures = 0
		return
	end

	job.failures += 1
	if self._logger then
		self._logger:error("TaskScheduler", string.format("Job '%s' failed (%d): %s", job.name, job.failures, tostring(err)))
	end
	if job.failures >= MAX_CONSECUTIVE_FAILURES then
		job.enabled = false
		if self._logger then
			self._logger:error("TaskScheduler", string.format("Job '%s' disabled after %d consecutive failures", job.name, job.failures))
		end
	end
end

function TaskScheduler:step()
	self.TickCount += 1
	local now = self._clock()
	for _, name in ipairs(table.clone(self._order)) do
		if self._paused then
			return
		end
		local job = self._jobs[name]
		if job and job.enabled and not job.inFlight and now >= job.nextRun then
			self:_runJob(job, now)
		end
	end
end

function TaskScheduler:start()
	if self._running then
		return
	end
	self._running = true
	self._paused = false

	if type(task) == "table" and type(task.spawn) == "function" then
		self._thread = task.spawn(function()
			while self._running do
				if not self._paused then
					self:step()
				end
				task.wait(self._tickSeconds)
			end
		end)
	end

	if self._logger then
		self._logger:info("TaskScheduler", string.format("Started (%d jobs, tick %.2fs)", #self._order, self._tickSeconds))
	end
end

function TaskScheduler:pause()
	self._paused = true
end

function TaskScheduler:resume()
	self._paused = false
end

function TaskScheduler:isRunning(): boolean
	return self._running and not self._paused
end

function TaskScheduler:stop()
	if not self._running then
		return
	end
	self._running = false
	local thread = self._thread
	self._thread = nil
	if thread and type(task) == "table" and type(task.cancel) == "function" and coroutine.running() ~= thread then
		pcall(task.cancel, thread)
	end
	if self._logger then
		self._logger:info("TaskScheduler", "Stopped")
	end
end

function TaskScheduler:destroy()
	self:stop()
	table.clear(self._jobs)
	table.clear(self._order)
end

return TaskScheduler

end

__moduleSources["Core/ConfigManager"] = function(...)
--[[
	ConfigManager.luau
	Schema-validated configuration manager with deep-merge defaults,
	live updates, and safe file persistence.
]]

local ConfigManager = {}
ConfigManager.__index = ConfigManager

ConfigManager.Defaults = {
	AMVGG = {
		EndpointUrl = "https://amvgg.com/values/pets",
		HubUrl = "https://amvgg.com/values",
		RefreshIntervalSeconds = 1800,
		RequestTimeoutSeconds = 15,
		MaxRetries = 3,
		CacheFile = "KiriaAutoTrader/amvgg_cache.json",
		AllowStaleCacheFallback = true,
	},
	Trading = {
		Mode = "manual_confirm", -- "manual_confirm" | "practice"
		MaxItemsPerOffer = 4,
		MinProfitValue = 1.0,
		MinProfitPercent = 5.0,
		MaxOverpayPercent = 0.0,
		AllowIncompleteEvaluations = false,
		RequireExplicitConfirmation = true,
		AutoCancelStaleListings = false, -- Always off unless explicitly permitted & enabled
		ScanIntervalSeconds = 15,
		ListingExpirationSeconds = 60, -- 30, 45, 60 (default), 90, 120
		OfferResponseIntervalSeconds = 45, -- 30-60s default
		OfferExpirationSeconds = 180,
		MaxPendingOffers = 20,
		MaxActiveListings = 5,
	},
	Thresholds = {
		ExcellentDealMinPct = 25.0,
		GoodDealMinPct = 8.0,
		FairTradeMinPct = -3.0,
		SmallLossMinPct = -12.0,
	},
	UI = {
		Theme = "KiriaDark",
		Keybind = "RightShift",
		AccentColorHex = "#9D4EDD",
		CompactMode = false,
		AnimationsEnabled = true,
		NotificationsEnabled = true,
		KiriaEnabled = true,
	},
	Data = {
		ConfigFile = "KiriaAutoTrader/config.json",
		AnalyticsFile = "KiriaAutoTrader/analytics.json",
		KiriaMemoryFile = "KiriaAutoTrader/kiria_memory.json",
		InventoryFile = "KiriaAutoTrader/inventory.json",
		LogLevel = "INFO",
	},
}

local function deepCopy(tbl: any): any
	if type(tbl) ~= "table" then
		return tbl
	end
	local copy = {}
	for k, v in pairs(tbl) do
		copy[k] = deepCopy(v)
	end
	return copy
end

local function deepMerge(base: { [string]: any }, overrides: { [string]: any }?, warnings: { string }, prefix: string): { [string]: any }
	local out = deepCopy(base)
	if type(overrides) ~= "table" then
		return out
	end
	for k, v in pairs(overrides) do
		local path = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
		if base[k] == nil then
			table.insert(warnings, "Unknown config key ignored: " .. path)
		elseif type(base[k]) == "table" and type(v) == "table" then
			out[k] = deepMerge(base[k], v, warnings, path)
		elseif type(base[k]) == type(v) then
			out[k] = v
		else
			table.insert(warnings, string.format("Type mismatch for %s (expected %s, got %s)", path, type(base[k]), type(v)))
		end
	end
	return out
end

function ConfigManager.new(options: { initial: { [string]: any }?, json: any?, fs: any?, logger: any?, eventBus: any? }?)
	local opts = options or {}
	local self = setmetatable({}, ConfigManager)
	self._json = opts.json
	self._fs = opts.fs
	self._logger = opts.logger
	self._eventBus = opts.eventBus
	self._warnings = {} :: { string }
	self._data = deepMerge(ConfigManager.Defaults, opts.initial, self._warnings, "")
	-- Enforce safety invariant: explicit trade confirmation is always required
	self._data.Trading.RequireExplicitConfirmation = true
	return self
end

function ConfigManager:get(path: string): any
	local cur: any = self._data
	for part in string.gmatch(path, "[^%.]+") do
		if type(cur) ~= "table" then
			return nil
		end
		cur = cur[part]
	end
	return cur
end

function ConfigManager:set(path: string, value: any): boolean
	if path == "Trading.RequireExplicitConfirmation" and value == false then
		if self._logger then
			self._logger:warn("ConfigManager", "RequireExplicitConfirmation cannot be disabled for safety")
		end
		return false
	end

	local parts = {}
	for part in string.gmatch(path, "[^%.]+") do
		table.insert(parts, part)
	end
	if #parts == 0 then
		return false
	end

	local cur: any = self._data
	for i = 1, #parts - 1 do
		if type(cur[parts[i]]) ~= "table" then
			return false
		end
		cur = cur[parts[i]]
	end

	local leaf = parts[#parts]
	if cur[leaf] == nil then
		return false
	end
	cur[leaf] = value

	if self._eventBus then
		self._eventBus:emit("Config:Changed", path, value)
	end
	return true
end

function ConfigManager:getAll(): { [string]: any }
	return deepCopy(self._data)
end

function ConfigManager:getWarnings(): { string }
	return table.clone(self._warnings)
end

function ConfigManager:loadFromFile(): boolean
	if not (self._fs and self._json and self._fs.exists and self._fs.read) then
		return false
	end
	local path = self._data.Data.ConfigFile
	if not self._fs.exists(path) then
		return false
	end
	local okRead, raw = pcall(self._fs.read, path)
	if not okRead or type(raw) ~= "string" then
		return false
	end
	local okDec, decoded = pcall(self._json.decode, raw)
	if not okDec or type(decoded) ~= "table" then
		return false
	end
	local warnings = {}
	self._data = deepMerge(ConfigManager.Defaults, decoded, warnings, "")
	self._data.Trading.RequireExplicitConfirmation = true
	self._warnings = warnings
	return true
end

function ConfigManager:saveToFile(): boolean
	if not (self._fs and self._json and self._fs.write) then
		return false
	end
	local okEnc, raw = pcall(self._json.encode, self._data)
	if not okEnc or type(raw) ~= "string" then
		return false
	end
	local okWrite = pcall(self._fs.write, self._data.Data.ConfigFile, raw)
	return okWrite
end

function ConfigManager:resetDefaults()
	self._data = deepCopy(ConfigManager.Defaults)
	self._warnings = {}
	if self._eventBus then
		self._eventBus:emit("Config:Reset")
	end
end

return ConfigManager

end

__moduleSources["Values/ValueParser"] = function(...)
--[[
	ValueParser.luau
	Parses pet valuation data exclusively from AMVGG (https://amvgg.com/values/pets).
	Supports:
	  1. Next.js App Router RSC payload (`self.__next_f.push([1,"..."])` chunks)
	  2. Direct JSON array or `{ pets = [...] }` object (cached / manual AMVGG export)
	Detects Cloudflare challenges, rate-limits, and malformed HTML/JSON without bypassing.
]]

local ValueParser = {}

export type ParseResult = {
	ok: boolean,
	pets: { [number]: any },
	error: string?,
	errorType: string?, -- "CLOUDFLARE_BLOCK" | "MALFORMED_HTML" | "MALFORMED_JSON" | "EMPTY_DATASET"
}

local function unescapeRscString(raw: string): string
	-- Unescape JSON string literal content extracted from self.__next_f.push([1,"..."])
	local out = raw:gsub('\\"', '"')
	out = out:gsub("\\/", "/")
	out = out:gsub("\\n", "\n")
	out = out:gsub("\\r", "\r")
	out = out:gsub("\\t", "\t")
	out = out:gsub("\\\\", "\\")
	return out
end

local function extractRscChunks(html: string): string
	local chunks = {}
	-- Pattern matches self.__next_f.push([1,"..."])
	local pos = 1
	local marker = 'self.__next_f.push([1,"'
	while true do
		local startIdx = string.find(html, marker, pos, true)
		if not startIdx then
			break
		end
		local contentStart = startIdx + #marker
		local i = contentStart
		local len = #html
		local closed = false
		while i <= len do
			local ch = string.sub(html, i, i)
			if ch == "\\" then
				i += 2
			elseif ch == '"' then
				closed = true
				break
			else
				i += 1
			end
		end
		if closed then
			local rawChunk = string.sub(html, contentStart, i - 1)
			table.insert(chunks, unescapeRscString(rawChunk))
			pos = i + 1
		else
			break
		end
	end
	return table.concat(chunks, "")
end

local function extractPetObjectsFromRsc(rscText: string, jsonDecode: (string) -> any): { any }
	local pets = {}
	local seenIds = {}
	local pos = 1
	local len = #rscText

	while pos <= len do
		local objStart = string.find(rscText, '{"id":"', pos, true)
		if not objStart then
			break
		end
		-- Balance braces from objStart
		local depth = 0
		local inStr = false
		local escaped = false
		local objEnd: number? = nil

		for i = objStart, len do
			local ch = string.sub(rscText, i, i)
			if inStr then
				if escaped then
					escaped = false
				elseif ch == "\\" then
					escaped = true
				elseif ch == '"' then
					inStr = false
				end
			else
				if ch == '"' then
					inStr = true
				elseif ch == "{" then
					depth += 1
				elseif ch == "}" then
					depth -= 1
					if depth == 0 then
						objEnd = i
						break
					end
				end
			end
		end

		if not objEnd then
			break
		end

		local jsonSlice = string.sub(rscText, objStart, objEnd)
		local ok, obj = pcall(jsonDecode, jsonSlice)
		if ok and type(obj) == "table" and type(obj.name) == "string" and obj.name ~= "" then
			-- Verify this is an AMVGG pet record (has at least one value field)
			if obj.regularValue ~= nil or obj.neonValue ~= nil or obj.megaValue ~= nil or obj.npRegularValue ~= nil then
				local key = tostring(obj.id or obj.name)
				if not seenIds[key] then
					seenIds[key] = true
					table.insert(pets, obj)
				end
			end
		end
		pos = objEnd + 1
	end

	return pets
end

function ValueParser.isCloudflareChallenge(body: string): boolean
	if type(body) ~= "string" then
		return false
	end
	local lower = string.lower(body)
	if string.find(lower, "just a moment...", 1, true) and string.find(lower, "cloudflare", 1, true) then
		return true
	end
	if string.find(lower, "cf-browser-verification", 1, true) or string.find(lower, "attention required! | cloudflare", 1, true) then
		return true
	end
	return false
end

function ValueParser.parse(rawBody: string, jsonDecode: (string) -> any): ParseResult
	if type(rawBody) ~= "string" or rawBody == "" then
		return { ok = false, pets = {}, error = "Empty response from AMVGG", errorType = "EMPTY_DATASET" }
	end

	if ValueParser.isCloudflareChallenge(rawBody) then
		return {
			ok = false,
			pets = {},
			error = "AMVGG returned a Cloudflare protection challenge; cannot fetch automatically without bypassing",
			errorType = "CLOUDFLARE_BLOCK",
		}
	end

	local trimmed = rawBody:match("^%s*(.-)%s*$") or rawBody
	-- 1. Direct JSON check (cached or manual AMVGG export)
	local firstChar = string.sub(trimmed, 1, 1)
	if firstChar == "[" or firstChar == "{" then
		local ok, decoded = pcall(jsonDecode, trimmed)
		if not ok or type(decoded) ~= "table" then
			return { ok = false, pets = {}, error = "Malformed JSON in AMVGG payload", errorType = "MALFORMED_JSON" }
		end
		local list = if type(decoded.pets) == "table" then decoded.pets else decoded
		if type(list) ~= "table" or #list == 0 then
			return { ok = false, pets = {}, error = "AMVGG JSON contained zero pet records", errorType = "EMPTY_DATASET" }
		end
		return { ok = true, pets = list }
	end

	-- 2. Next.js RSC HTML payload from https://amvgg.com/values/pets
	local rscText = extractRscChunks(rawBody)
	if rscText == "" then
		return {
			ok = false,
			pets = {},
			error = "AMVGG HTML did not contain expected Next.js RSC pet payload",
			errorType = "MALFORMED_HTML",
		}
	end

	local pets = extractPetObjectsFromRsc(rscText, jsonDecode)
	if #pets == 0 then
		return {
			ok = false,
			pets = {},
			error = "No valid pet records found in AMVGG RSC payload",
			errorType = "EMPTY_DATASET",
		}
	end

	return { ok = true, pets = pets }
end

return ValueParser

end

__moduleSources["Values/ValueValidator"] = function(...)
--[[
	ValueValidator.luau
	Validates and normalizes raw AMVGG pet records into a consistent internal schema.
	Never invents or fabricates missing/zero/invalid values.
]]

local ValueValidator = {}

export type PetRecord = {
	id: string,
	name: string,
	key: string,
	origin: string,
	category: number?,
	lastUpdatedAt: string?,
	values: {
		regular: number?,
		npRegular: number?,
		r: number?,
		f: number?,
		neon: number?,
		npNeon: number?,
		nr: number?,
		nf: number?,
		mega: number?,
		npMega: number?,
		mr: number?,
		mf: number?,
	},
	demands: {
		regular: string?,
		npRegular: string?,
		r: string?,
		f: string?,
		neon: string?,
		npNeon: string?,
		nr: string?,
		nf: string?,
		mega: string?,
		npMega: string?,
		mr: string?,
		mf: string?,
	},
	source: string,
	validatedAt: number,
}

export type ValidationSummary = {
	records: { [string]: PetRecord },
	ordered: { PetRecord },
	totalInput: number,
	validCount: number,
	rejectedCount: number,
	invalidFieldCount: number,
}

local VALUE_FIELDS = {
	regular = "regularValue",
	npRegular = "npRegularValue",
	r = "rValue",
	f = "fValue",
	neon = "neonValue",
	npNeon = "npNeonValue",
	nr = "nrValue",
	nf = "nfValue",
	mega = "megaValue",
	npMega = "npMegaValue",
	mr = "mrValue",
	mf = "mfValue",
}

local DEMAND_FIELDS = {
	regular = "regularDemand",
	npRegular = "npRegularDemand",
	r = "rDemand",
	f = "fDemand",
	neon = "neonDemand",
	npNeon = "npNeonDemand",
	nr = "nrDemand",
	nf = "nfDemand",
	mega = "megaDemand",
	npMega = "npMegaDemand",
	mr = "mrDemand",
	mf = "mfDemand",
}

function ValueValidator.normalizeKey(name: string): string
	local trimmed = tostring(name or ""):match("^%s*(.-)%s*$") or ""
	return string.lower(trimmed):gsub("%s+", " ")
end

local function parsePositiveNumber(raw: any): (number?, boolean)
	if raw == nil or raw == "" then
		return nil, false
	end
	local num = tonumber(raw)
	if num == nil or num ~= num or num == math.huge or num == -math.huge or num <= 0 then
		return nil, true -- invalid/zero value
	end
	return num, false
end

local function cleanTimestamp(raw: any): string?
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	-- Next.js RSC encodes dates as "$D2026-11-23T13:26:04.111Z"
	if string.sub(raw, 1, 2) == "$D" then
		return string.sub(raw, 3)
	end
	return raw
end

function ValueValidator.validateRecord(raw: any, nowTimestamp: number?): (PetRecord?, number)
	if type(raw) ~= "table" then
		return nil, 1
	end
	local name = type(raw.name) == "string" and (raw.name:match("^%s*(.-)%s*$") or "") or ""
	if name == "" then
		return nil, 1
	end

	local values: { [string]: number? } = {}
	local demands: { [string]: string? } = {}
	local invalidFields = 0
	local hasAnyValidValue = false

	-- Support both raw AMVGG fields (`regularValue`) and already-normalized cached records (`values.regular`)
	if type(raw.values) == "table" then
		for k in pairs(VALUE_FIELDS) do
			local num, isInvalid = parsePositiveNumber(raw.values[k])
			if isInvalid then
				invalidFields += 1
			elseif num then
				values[k] = num
				hasAnyValidValue = true
			end
		end
	else
		for k, srcKey in pairs(VALUE_FIELDS) do
			local num, isInvalid = parsePositiveNumber(raw[srcKey])
			if isInvalid then
				invalidFields += 1
			elseif num then
				values[k] = num
				hasAnyValidValue = true
			end
		end
	end

	if not hasAnyValidValue then
		return nil, math.max(1, invalidFields)
	end

	if type(raw.demands) == "table" then
		for k in pairs(DEMAND_FIELDS) do
			if type(raw.demands[k]) == "string" and raw.demands[k] ~= "" then
				demands[k] = raw.demands[k]
			end
		end
	else
		for k, srcKey in pairs(DEMAND_FIELDS) do
			if type(raw[srcKey]) == "string" and raw[srcKey] ~= "" then
				demands[k] = raw[srcKey]
			end
		end
	end

	local record: PetRecord = {
		id = tostring(raw.id or ValueValidator.normalizeKey(name)),
		name = name,
		key = ValueValidator.normalizeKey(name),
		origin = type(raw.origin) == "string" and raw.origin or "Unknown",
		category = tonumber(raw.category),
		lastUpdatedAt = cleanTimestamp(raw.lastUpdatedAt),
		values = values :: any,
		demands = demands :: any,
		source = "AMVGG",
		validatedAt = nowTimestamp or os.time(),
	}

	return record, invalidFields
end

function ValueValidator.validateDataset(rawList: { any }, nowTimestamp: number?): ValidationSummary
	local records: { [string]: PetRecord } = {}
	local ordered: { PetRecord } = {}
	local validCount = 0
	local rejectedCount = 0
	local invalidFieldCount = 0
	local ts = nowTimestamp or os.time()

	if type(rawList) ~= "table" then
		return {
			records = records,
			ordered = ordered,
			totalInput = 0,
			validCount = 0,
			rejectedCount = 0,
			invalidFieldCount = 0,
		}
	end

	for _, item in ipairs(rawList) do
		local rec, badFields = ValueValidator.validateRecord(item, ts)
		invalidFieldCount += badFields
		if rec then
			if not records[rec.key] then
				table.insert(ordered, rec)
				validCount += 1
			end
			records[rec.key] = rec
		else
			rejectedCount += 1
		end
	end

	table.sort(ordered, function(a, b)
		local va = a.values.regular or a.values.npRegular or a.values.neon or 0
		local vb = b.values.regular or b.values.npRegular or b.values.neon or 0
		if va ~= vb then
			return va > vb
		end
		return a.name < b.name
	end)

	return {
		records = records,
		ordered = ordered,
		totalInput = #rawList,
		validCount = validCount,
		rejectedCount = rejectedCount,
		invalidFieldCount = invalidFieldCount,
	}
end

return ValueValidator

end

__moduleSources["Values/ValueCache"] = function(...)
--[[
	ValueCache.luau
	Local cache manager for validated AMVGG pet datasets.
	Preserves the last valid dataset on refresh failures and tracks freshness metadata.
]]

local ValueCache = {}
ValueCache.__index = ValueCache

export type CachePayload = {
	source: string,
	sourceUrl: string,
	updatedAt: number,
	petCount: number,
	pets: { any },
}

function ValueCache.new(options: { filePath: string?, fs: any?, json: any?, validator: any?, logger: any? }?)
	local opts = options or {}
	local self = setmetatable({}, ValueCache)
	self._filePath = opts.filePath or "KiriaAutoTrader/amvgg_cache.json"
	self._fs = opts.fs
	self._json = opts.json
	self._validator = opts.validator
	self._logger = opts.logger

	self._records = {} :: { [string]: any }
	self._ordered = {} :: { any }
	self._updatedAt = nil :: number?
	self._sourceUrl = "https://amvgg.com/values/pets"
	self._isStale = false
	return self
end

function ValueCache:hasData(): boolean
	return #self._ordered > 0
end

function ValueCache:getRecords(): { [string]: any }
	return self._records
end

function ValueCache:getOrdered(): { any }
	return self._ordered
end

function ValueCache:getPet(name: string): any?
	if not self._validator then
		return self._records[string.lower(name)]
	end
	return self._records[self._validator.normalizeKey(name)]
end

function ValueCache:getStatus(): { hasData: boolean, petCount: number, updatedAt: number?, isStale: boolean, sourceUrl: string }
	return {
		hasData = #self._ordered > 0,
		petCount = #self._ordered,
		updatedAt = self._updatedAt,
		isStale = self._isStale,
		sourceUrl = self._sourceUrl,
	}
end

function ValueCache:markStale()
	self._isStale = true
end

function ValueCache:setValidatedDataset(summary: { records: { [string]: any }, ordered: { any } }, updatedAt: number?, sourceUrl: string?): boolean
	if not summary or not summary.ordered or #summary.ordered == 0 then
		return false
	end
	self._records = summary.records
	self._ordered = summary.ordered
	self._updatedAt = updatedAt or os.time()
	if sourceUrl then
		self._sourceUrl = sourceUrl
	end
	self._isStale = false
	return true
end

function ValueCache:save(): boolean
	if not (self._fs and self._json and self._fs.write) or #self._ordered == 0 then
		return false
	end
	local payload: CachePayload = {
		source = "AMVGG",
		sourceUrl = self._sourceUrl,
		updatedAt = self._updatedAt or os.time(),
		petCount = #self._ordered,
		pets = self._ordered,
	}
	local okEnc, encoded = pcall(self._json.encode, payload)
	if not okEnc or type(encoded) ~= "string" then
		return false
	end
	local okWrite, err = pcall(self._fs.write, self._filePath, encoded)
	if not okWrite and self._logger then
		self._logger:warn("ValueCache", "Failed to save AMVGG cache: " .. tostring(err))
	end
	return okWrite
end

function ValueCache:load(): boolean
	if not (self._fs and self._json and self._fs.exists and self._fs.read and self._validator) then
		return false
	end
	if not self._fs.exists(self._filePath) then
		return false
	end
	local okRead, raw = pcall(self._fs.read, self._filePath)
	if not okRead or type(raw) ~= "string" or raw == "" then
		return false
	end
	local okDec, decoded = pcall(self._json.decode, raw)
	if not okDec or type(decoded) ~= "table" or type(decoded.pets) ~= "table" then
		return false
	end
	if decoded.source ~= nil and decoded.source ~= "AMVGG" then
		if self._logger then
			self._logger:warn("ValueCache", "Rejected non-AMVGG cache source: " .. tostring(decoded.source))
		end
		return false
	end

	local summary = self._validator.validateDataset(decoded.pets, tonumber(decoded.updatedAt))
	if summary.validCount == 0 then
		return false
	end

	self._records = summary.records
	self._ordered = summary.ordered
	self._updatedAt = tonumber(decoded.updatedAt) or os.time()
	self._sourceUrl = tostring(decoded.sourceUrl or "https://amvgg.com/values/pets")
	self._isStale = true -- Marked stale until live refresh confirms freshness
	return true
end

return ValueCache

end

__moduleSources["Values/AMVGGProvider"] = function(...)
--[[
	AMVGGProvider.luau
	Exclusive AMVGG valuation provider (https://amvgg.com/values/pets).
	Enforces AMVGG-only sourcing, rate-limiting, exponential backoff, non-blocking
	execution, and cache preservation on failure. Never bypasses Cloudflare or auth.
]]

local AMVGGProvider = {}
AMVGGProvider.__index = AMVGGProvider

local ALLOWED_HOST = "amvgg.com"
local MIN_REQUEST_COOLDOWN_SECONDS = 10

export type ProviderDeps = {
	config: any,
	cache: any,
	parser: any,
	validator: any,
	errorHandler: any,
	eventBus: any?,
	state: any?,
	logger: any?,
	httpGet: ((string) -> (boolean, number, string))?,
	jsonDecode: (string) -> any,
	clockFn: (() -> number)?,
}

local function isAllowedAmvggUrl(url: string): boolean
	if type(url) ~= "string" then
		return false
	end
	local host = string.match(string.lower(url), "^https://([^/]+)")
	return host == ALLOWED_HOST or host == ("www." .. ALLOWED_HOST)
end

function AMVGGProvider.new(deps: ProviderDeps)
	local self = setmetatable({}, AMVGGProvider)
	self._config = deps.config
	self._cache = deps.cache
	self._parser = deps.parser
	self._validator = deps.validator
	self._errorHandler = deps.errorHandler
	self._eventBus = deps.eventBus
	self._state = deps.state
	self._logger = deps.logger
	self._httpGet = deps.httpGet
	self._jsonDecode = deps.jsonDecode
	self._clock = deps.clockFn or os.time

	self._status = "IDLE" -- "IDLE" | "FETCHING" | "LIVE" | "CACHED_FALLBACK" | "UNAVAILABLE"
	self._lastError = nil :: string?
	self._lastAttemptAt = 0
	self._inFlight = false
	return self
end

function AMVGGProvider:_setStatus(status: string, errMsg: string?)
	self._status = status
	self._lastError = errMsg
	local cacheStatus = self._cache:getStatus()
	if self._state then
		self._state:set("amvgg.status", status, "AMVGGProvider")
		self._state:set("amvgg.lastUpdatedAt", cacheStatus.updatedAt, "AMVGGProvider")
		self._state:set("amvgg.petCount", cacheStatus.petCount, "AMVGGProvider")
		self._state:set("amvgg.lastError", errMsg, "AMVGGProvider")
	end
	if self._eventBus then
		self._eventBus:emit("AMVGG:StatusChanged", {
			status = status,
			error = errMsg,
			petCount = cacheStatus.petCount,
			updatedAt = cacheStatus.updatedAt,
			isStale = cacheStatus.isStale,
		})
	end
end

function AMVGGProvider:getStatus(): { status: string, lastError: string?, petCount: number, updatedAt: number?, isStale: boolean, sourceUrl: string }
	local cs = self._cache:getStatus()
	return {
		status = self._status,
		lastError = self._lastError,
		petCount = cs.petCount,
		updatedAt = cs.updatedAt,
		isStale = cs.isStale,
		sourceUrl = cs.sourceUrl,
	}
end

function AMVGGProvider:initFromCache(): boolean
	local loaded = self._cache:load()
	if loaded then
		self:_setStatus("CACHED_FALLBACK", nil)
		if self._logger then
			local st = self._cache:getStatus()
			self._logger:info("AMVGGProvider", string.format("Loaded %d pets from local AMVGG cache", st.petCount))
		end
	else
		self:_setStatus("IDLE", nil)
	end
	return loaded
end

function AMVGGProvider:refresh(options: { force: boolean? }?): (boolean, string?)
	local opts = options or {}
	if self._inFlight then
		return false, "AMVGG refresh already in progress"
	end

	local now = self._clock()
	if not opts.force and self._lastAttemptAt > 0 and (now - self._lastAttemptAt) < MIN_REQUEST_COOLDOWN_SECONDS then
		return false, "Rate limit cooldown active; please wait before refreshing AMVGG again"
	end

	local url = tostring(self._config:get("AMVGG.EndpointUrl") or "https://amvgg.com/values/pets")
	if not isAllowedAmvggUrl(url) then
		local msg = "Blocked non-AMVGG endpoint URL: " .. url
		self:_setStatus(if self._cache:hasData() then "CACHED_FALLBACK" else "UNAVAILABLE", msg)
		return false, msg
	end

	if type(self._httpGet) ~= "function" then
		local msg = "No HTTP client available in this environment; using preserved AMVGG cache/manual import"
		if self._cache:hasData() then
			self._cache:markStale()
			self:_setStatus("CACHED_FALLBACK", msg)
		else
			self:_setStatus("UNAVAILABLE", msg)
		end
		return false, msg
	end

	self._inFlight = true
	self._lastAttemptAt = now
	self:_setStatus("FETCHING", nil)

	local maxRetries = tonumber(self._config:get("AMVGG.MaxRetries")) or 3
	local ok, resultOrErr = self._errorHandler:retry("AMVGGProvider", function()
		local callOk, statusCode, body = self._httpGet(url)
		if not callOk then
			return false, "Network request failed: " .. tostring(statusCode)
		end
		if statusCode == 403 or statusCode == 429 or statusCode == 503 then
			return false, string.format("AMVGG HTTP %d (rate-limited or protected)", statusCode)
		end
		if statusCode < 200 or statusCode >= 300 then
			return false, string.format("AMVGG HTTP error %d", statusCode)
		end

		local parsed = self._parser.parse(body, self._jsonDecode)
		if not parsed.ok then
			return false, parsed.error or "Failed to parse AMVGG payload"
		end

		local summary = self._validator.validateDataset(parsed.pets, self._clock())
		if summary.validCount == 0 then
			return false, "AMVGG dataset had zero valid pet records after validation"
		end

		return true, summary
	end, {
		maxAttempts = maxRetries,
		baseDelay = 1.0,
		maxDelay = 12.0,
		shouldRetry = function(errStr: string)
			-- Do not hammer Cloudflare challenges
			return not string.find(errStr, "Cloudflare", 1, true)
		end,
	})

	self._inFlight = false

	if ok and type(resultOrErr) == "table" then
		self._cache:setValidatedDataset(resultOrErr, self._clock(), url)
		self._cache:save()
		self:_setStatus("LIVE", nil)
		if self._logger then
			self._logger:success("AMVGGProvider", string.format("Refreshed %d pets from AMVGG", resultOrErr.validCount))
		end
		if self._eventBus then
			self._eventBus:emit("AMVGG:Refreshed", {
				petCount = resultOrErr.validCount,
				rejectedCount = resultOrErr.rejectedCount,
				updatedAt = self._clock(),
			})
		end
		return true, nil
	end

	local errMsg = tostring(resultOrErr or "Unknown AMVGG error")
	if self._cache:hasData() then
		self._cache:markStale()
		self:_setStatus("CACHED_FALLBACK", errMsg)
		if self._logger then
			self._logger:warn("AMVGGProvider", "AMVGG refresh failed; preserved last valid cache: " .. errMsg)
		end
	else
		self:_setStatus("UNAVAILABLE", errMsg)
		if self._logger then
			self._logger:error("AMVGGProvider", "AMVGG refresh failed with no cache: " .. errMsg)
		end
	end

	if self._eventBus then
		self._eventBus:emit("AMVGG:Error", { message = errMsg, hasCache = self._cache:hasData() })
	end
	return false, errMsg
end

function AMVGGProvider:importPayload(rawBody: string): (boolean, string?)
	local parsed = self._parser.parse(rawBody, self._jsonDecode)
	if not parsed.ok then
		return false, parsed.error
	end
	local summary = self._validator.validateDataset(parsed.pets, self._clock())
	if summary.validCount == 0 then
		return false, "No valid AMVGG pet records found in imported payload"
	end
	self._cache:setValidatedDataset(summary, self._clock(), "https://amvgg.com/values/pets")
	self._cache:save()
	self:_setStatus("LIVE", nil)
	if self._eventBus then
		self._eventBus:emit("AMVGG:Refreshed", { petCount = summary.validCount, imported = true, updatedAt = self._clock() })
	end
	return true, nil
end

return AMVGGProvider

end

__moduleSources["Values/ValueEngine"] = function(...)
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

end

__moduleSources["Values/CSVLoader"] = function(...)
--[[
	CSVLoader.luau
	Loads pet values from pets_ridepots.csv (AMVGG-sourced) into ValueCache
	as instant offline fallback when HTTP fetch is unavailable.

	CSV columns (from header):
	  name, rarity, year, demand, demandScore, stars,
	  demandNP, demandNeon, demandMega,
	  valueRP (FR), rideRP (R), flyRP (F), npRP (NP),
	  neonRP (NFR), megaRP (MFR),
	  category, valueSource
]]

local CSVLoader = {}
CSVLoader.__index = CSVLoader

-- ── helpers ──────────────────────────────────────────────────────────────────

local function trim(s: string): string
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parseLine(line: string): { string }
	local fields = {}
	local i = 1
	local len = #line
	while i <= len do
		if line:sub(i, i) == '"' then
			-- quoted field
			i += 1
			local start = i
			local field = ""
			while i <= len do
				if line:sub(i, i) == '"' then
					if line:sub(i + 1, i + 1) == '"' then
						field = field .. line:sub(start, i - 1) .. '"'
						i += 2
						start = i
					else
						field = field .. line:sub(start, i - 1)
						i += 1
						break
					end
				else
					i += 1
				end
			end
			table.insert(fields, field)
			if i <= len and line:sub(i, i) == "," then i += 1 end
		else
			local comma = line:find(",", i, true)
			if comma then
				table.insert(fields, trim(line:sub(i, comma - 1)))
				i = comma + 1
			else
				table.insert(fields, trim(line:sub(i)))
				break
			end
		end
	end
	return fields
end

local function toNum(s: string?): number?
	if not s or s == "" or s == "N/A" then return nil end
	local n = tonumber(s)
	return n
end

-- Map demand string → score
local DEMAND_SCORE: { [string]: number } = {
	Horrible = 0.1, Low = 0.3, Medium = 0.5,
	High = 0.8, ["Very High"] = 0.95,
}

-- ── normalise pet name → lookup key ──────────────────────────────────────────

local function nameKey(name: string): string
	return name:lower():gsub("[%s%-_]+", "_"):gsub("[^%w_]", "")
end

-- ── CSVLoader.new ─────────────────────────────────────────────────────────────

export type Options = {
	fs: { read: (string) -> string }?,
	logger: any?,
	csvPath: string?,
}

function CSVLoader.new(opts: Options?)
	local o = opts or {}
	local self = setmetatable({}, CSVLoader)
	self._fs     = o.fs
	self._logger = o.logger
	self._path   = o.csvPath or "pets_ridepots.csv"
	self._records = {}   -- key → record (string -> any)
	self._loaded = false
	return self
end

function CSVLoader:_log(level: string, msg: string)
	if self._logger and type(self._logger[level:lower()]) == "function" then
		self._logger[level:lower()](self._logger, "[CSVLoader] " .. msg)
	end
end

-- ── load() ────────────────────────────────────────────────────────────────────

function CSVLoader:load(): boolean
	if self._loaded then return true end
	local fs = self._fs
	if not fs then
		-- Try executor readfile global
		if type(readfile) == "function" then
			fs = { read = function(p) return readfile(p) end }
		else
			self:_log("WARN", "No fs adapter and no readfile global — CSV unavailable")
			return false
		end
	end

	local ok, raw = pcall(function() return fs.read(self._path) end)
	if not ok or type(raw) ~= "string" or #raw == 0 then
		self:_log("WARN", "Could not read CSV at: " .. tostring(self._path))
		return false
	end

	local lines = {}
	for line in (raw .. "\n"):gmatch("([^\r\n]*)\r?\n") do
		table.insert(lines, line)
	end

	if #lines < 2 then
		self:_log("WARN", "CSV too short")
		return false
	end

	-- Parse header
	local header = parseLine(lines[1])
	local colIdx: { [string]: number } = {}
	for i, col in ipairs(header) do colIdx[trim(col)] = i end

	local function col(fields: { string }, name: string): string?
		local i = colIdx[name]
		return i and fields[i] or nil
	end

	local count = 0
	for lineNum = 2, #lines do
		local line = lines[lineNum]
		if line ~= "" then
			local fields = parseLine(line)
			local name = trim(col(fields, "name") or "")
			if name ~= "" then
				local frV  = toNum(col(fields, "valueRP"))
				local rideV = toNum(col(fields, "rideRP"))
				local flyV  = toNum(col(fields, "flyRP"))
				local npV   = toNum(col(fields, "npRP"))
				local neonV = toNum(col(fields, "neonRP"))
				local megaV = toNum(col(fields, "megaRP"))
				local demand = trim(col(fields, "demand") or "")
				local demandScore = toNum(col(fields, "demandScore")) or DEMAND_SCORE[demand] or 0.5

				local record = {
					name           = name,
					rarity         = trim(col(fields, "rarity") or ""),
					demand         = demand,
					demandScore    = demandScore,
					-- FR value (fly+ride) is the standard "normal" value in AMVGG
					regular        = frV,
					npRegular      = npV,
					r              = rideV,
					f              = flyV,
					neon           = neonV,
					npNeon         = nil,  -- not in CSV
					nr             = nil,
					nf             = nil,
					mega           = megaV,
					npMega         = nil,
					mr             = nil,
					mf             = nil,
					source         = "CSV_AMVGG",
					fetchedAt      = os.time(),
				}

				local key = nameKey(name)
				self._records[key] = record
				self._records[name:lower()] = record   -- also by exact lower
				count += 1
			end
		end
	end

	self._loaded = true
	self:_log("INFO", string.format("Loaded %d pets from CSV (%s)", count, self._path))
	return true
end

-- ── get(name) ─────────────────────────────────────────────────────────────────

function CSVLoader:get(name: string): any?
	if not self._loaded then self:load() end
	local key = nameKey(name)
	return self._records[key] or self._records[name:lower()]
end

-- ── seedCache(valueCache) ─────────────────────────────────────────────────────
-- Seed a ValueCache instance with all CSV records (only where cache is empty)

function CSVLoader:seedCache(valueCache: any)
	if not self._loaded then self:load() end
	local seeded = 0
	for _, record in pairs(self._records) do
		-- avoid duplicates by keying on name lower
		local existing = valueCache:get(record.name)
		if not existing or not existing.regular then
			valueCache:set(record.name, record)
			seeded += 1
		end
	end
	self:_log("INFO", string.format("Seeded cache with %d CSV records", seeded))
	return seeded
end

-- ── count() ──────────────────────────────────────────────────────────────────

function CSVLoader:count(): number
	if not self._loaded then self:load() end
	local n = 0
	for _ in pairs(self._records) do n += 1 end
	return math.floor(n / 2) -- divided by 2 because we store key+lowercase
end

function CSVLoader:isLoaded(): boolean
	return self._loaded
end

return CSVLoader

end

__moduleSources["Inventory/PetDatabase"] = function(...)
--[[
	PetDatabase.luau
	Query interface over the validated AMVGG pet dataset.
]]

local PetDatabase = {}
PetDatabase.__index = PetDatabase

function PetDatabase.new(cache: any, validator: any)
	local self = setmetatable({}, PetDatabase)
	self._cache = cache
	self._validator = validator
	return self
end

function PetDatabase:findByName(name: string): any?
	return self._cache:getPet(name)
end

function PetDatabase:search(query: string?, filters: { category: number?, origin: string?, limit: number? }?): { any }
	local q = string.lower(tostring(query or "")):match("^%s*(.-)%s*$") or ""
	local f = filters or {}
	local limit = f.limit or 100
	local out = {}

	for _, rec in ipairs(self._cache:getOrdered()) do
		local ok = true
		if q ~= "" and not string.find(rec.key, q, 1, true) then
			ok = false
		end
		if ok and f.category ~= nil and rec.category ~= f.category then
			ok = false
		end
		if ok and f.origin and f.origin ~= "" and not string.find(string.lower(rec.origin or ""), string.lower(f.origin), 1, true) then
			ok = false
		end
		if ok then
			table.insert(out, rec)
			if #out >= limit then
				break
			end
		end
	end

	return out
end

function PetDatabase:count(): number
	return #self._cache:getOrdered()
end

return PetDatabase

end

__moduleSources["Inventory/InventoryReader"] = function(...)
--[[
	InventoryReader.luau
	Manages the user's pet inventory via a permitted game adapter (if provided)
	or manual editor + local JSON persistence/import.
	Respects `locked` and `favorite` flags so protected pets are never offered.
]]

local InventoryReader = {}
InventoryReader.__index = InventoryReader

export type InventoryPet = {
	uid: string,
	name: string,
	neon: boolean,
	mega: boolean,
	fly: boolean,
	ride: boolean,
	locked: boolean,
	favorite: boolean,
	selectedForListing: boolean,
	source: string, -- "game" | "manual" | "import"
}

function InventoryReader.new(options: { filePath: string?, fs: any?, json: any?, eventBus: any?, logger: any?, gameAdapter: any? }?)
	local opts = options or {}
	local self = setmetatable({}, InventoryReader)
	self._filePath = opts.filePath or "KiriaAutoTrader/inventory.json"
	self._fs = opts.fs
	self._json = opts.json
	self._eventBus = opts.eventBus
	self._logger = opts.logger
	self._gameAdapter = opts.gameAdapter
	self._pets = {} :: { InventoryPet }
	self._nextId = 1
	return self
end

function InventoryReader:_generateUid(): string
	local id = string.format("pet_%d_%d", os.time(), self._nextId)
	self._nextId += 1
	return id
end

function InventoryReader:_normalizePet(raw: any, defaultSource: string): InventoryPet?
	if type(raw) ~= "table" or type(raw.name) ~= "string" or raw.name:match("^%s*(.-)%s*$") == "" then
		return nil
	end
	return {
		uid = tostring(raw.uid or self:_generateUid()),
		name = raw.name:match("^%s*(.-)%s*$") or raw.name,
		neon = raw.neon == true,
		mega = raw.mega == true,
		fly = raw.fly == true,
		ride = raw.ride == true,
		locked = raw.locked == true,
		favorite = raw.favorite == true,
		selectedForListing = raw.selectedForListing == true,
		source = tostring(raw.source or defaultSource),
	}
end

function InventoryReader:getAll(): { InventoryPet }
	return table.clone(self._pets)
end

function InventoryReader:getTradeable(): { InventoryPet }
	local out = {}
	for _, pet in ipairs(self._pets) do
		if not pet.locked and not pet.favorite then
			table.insert(out, pet)
		end
	end
	return out
end

function InventoryReader:getSelected(): { InventoryPet }
	local out = {}
	for _, pet in ipairs(self._pets) do
		if pet.selectedForListing then
			table.insert(out, pet)
		end
	end
	return out
end

function InventoryReader:addPet(petData: { name: string, neon: boolean?, mega: boolean?, fly: boolean?, ride: boolean?, locked: boolean?, favorite: boolean?, uid: string? }): InventoryPet?
	local pet = self:_normalizePet(petData, "manual")
	if not pet then
		return nil
	end
	table.insert(self._pets, pet)
	self:save()
	if self._eventBus then
		self._eventBus:emit("Inventory:Updated", { count = #self._pets })
	end
	return pet
end

function InventoryReader:updatePet(uid: string, patch: { [string]: any }): boolean
	for _, pet in ipairs(self._pets) do
		if pet.uid == uid then
			for k, v in pairs(patch) do
				if k ~= "uid" and (pet :: any)[k] ~= nil then
					(pet :: any)[k] = v
				end
			end
			self:save()
			if self._eventBus then
				self._eventBus:emit("Inventory:Updated", { count = #self._pets })
			end
			return true
		end
	end
	return false
end

function InventoryReader:removePet(uid: string): boolean
	for i, pet in ipairs(self._pets) do
		if pet.uid == uid then
			table.remove(self._pets, i)
			self:save()
			if self._eventBus then
				self._eventBus:emit("Inventory:Updated", { count = #self._pets })
			end
			return true
		end
	end
	return false
end

function InventoryReader:syncFromGame(): (boolean, string?)
	if not (self._gameAdapter and type(self._gameAdapter.readInventory) == "function") then
		return false, "Automatic inventory sync unavailable in this environment; use Manual Editor or JSON Import"
	end
	local ok, listOrErr = pcall(self._gameAdapter.readInventory)
	if not ok or type(listOrErr) ~= "table" then
		return false, "Failed to read permitted game inventory: " .. tostring(listOrErr)
	end
	local nextList = {}
	for _, raw in ipairs(listOrErr) do
		local p = self:_normalizePet(raw, "game")
		if p then
			table.insert(nextList, p)
		end
	end
	self._pets = nextList
	self:save()
	if self._eventBus then
		self._eventBus:emit("Inventory:Updated", { count = #self._pets, source = "game" })
	end
	return true, nil
end

function InventoryReader:importJson(jsonText: string, replace: boolean?): (boolean, string?, number)
	if not (self._json and type(self._json.decode) == "function") then
		return false, "JSON decoder unavailable", 0
	end
	local ok, decoded = pcall(self._json.decode, jsonText)
	if not ok or type(decoded) ~= "table" then
		return false, "Invalid inventory JSON", 0
	end
	local sourceList = if type(decoded.pets) == "table" then decoded.pets else decoded
	local imported = {}
	for _, raw in ipairs(sourceList) do
		local p = self:_normalizePet(raw, "import")
		if p then
			table.insert(imported, p)
		end
	end
	if replace then
		self._pets = imported
	else
		for _, p in ipairs(imported) do
			table.insert(self._pets, p)
		end
	end
	self:save()
	if self._eventBus then
		self._eventBus:emit("Inventory:Updated", { count = #self._pets, imported = #imported })
	end
	return true, nil, #imported
end

function InventoryReader:exportJson(): string?
	if not (self._json and type(self._json.encode) == "function") then
		return nil
	end
	local ok, encoded = pcall(self._json.encode, { pets = self._pets })
	return if ok then encoded else nil
end

function InventoryReader:save(): boolean
	if not (self._fs and self._json and self._fs.write) then
		return false
	end
	local encoded = self:exportJson()
	if not encoded then
		return false
	end
	return pcall(self._fs.write, self._filePath, encoded)
end

function InventoryReader:load(): boolean
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
	local ok = self:importJson(raw, true)
	return ok
end

return InventoryReader

end

__moduleSources["Inventory/InventoryValuator"] = function(...)
--[[
	InventoryValuator.luau
	Evaluates inventory pets against AMVGG values, supports search/filtering/sorting,
	computes total inventory value, and highlights the top-value pet.
]]

local InventoryValuator = {}
InventoryValuator.__index = InventoryValuator

export type InventoryFilter = {
	query: string?,
	neonOnly: boolean?,
	megaOnly: boolean?,
	flyOnly: boolean?,
	rideOnly: boolean?,
	tradeableOnly: boolean?,
	sortDescending: boolean?,
}

export type ValuatedPet = {
	pet: any,
	evaluation: any,
	value: number,
}

function InventoryValuator.new(inventoryReader: any, valueEngine: any)
	local self = setmetatable({}, InventoryValuator)
	self._reader = inventoryReader
	self._valueEngine = valueEngine
	return self
end

function InventoryValuator:evaluateAll(filter: InventoryFilter?): {
	items: { ValuatedPet },
	totalValue: number,
	topPet: ValuatedPet?,
	incompleteCount: number,
	totalCount: number,
}
	local f = filter or {}
	local q = string.lower(tostring(f.query or "")):match("^%s*(.-)%s*$") or ""
	local items: { ValuatedPet } = {}
	local totalValue = 0
	local incompleteCount = 0
	local topPet: ValuatedPet? = nil

	local allPets = self._reader:getAll()
	for _, pet in ipairs(allPets) do
		local ev = self._valueEngine:evaluatePet(pet)
		local val = ev.unitValue or 0
		if ev.complete then
			totalValue += val
		else
			incompleteCount += 1
		end

		local entry: ValuatedPet = {
			pet = pet,
			evaluation = ev,
			value = val,
		}

		if not topPet or val > topPet.value then
			topPet = entry
		end

		local matches = true
		if q ~= "" and not string.find(string.lower(pet.name), q, 1, true) then
			matches = false
		end
		if matches and f.neonOnly and not pet.neon then
			matches = false
		end
		if matches and f.megaOnly and not pet.mega then
			matches = false
		end
		if matches and f.flyOnly and not pet.fly then
			matches = false
		end
		if matches and f.rideOnly and not pet.ride then
			matches = false
		end
		if matches and f.tradeableOnly and (pet.locked or pet.favorite) then
			matches = false
		end

		if matches then
			table.insert(items, entry)
		end
	end

	local desc = if f.sortDescending == nil then true else f.sortDescending
	table.sort(items, function(a, b)
		if a.value ~= b.value then
			return if desc then a.value > b.value else a.value < b.value
		end
		return a.pet.name < b.pet.name
	end)

	return {
		items = items,
		totalValue = totalValue,
		topPet = topPet,
		incompleteCount = incompleteCount,
		totalCount = #allPets,
	}
end

return InventoryValuator

end

__moduleSources["Trading/ProfitCalculator"] = function(...)
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

end

__moduleSources["Trading/TradeEvaluator"] = function(...)
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

end

__moduleSources["Trading/ListingScanner"] = function(...)
--[[
	ListingScanner.luau
	Scans Trade Hub listings from a permitted game adapter or manual/JSON import,
	deduplicates and tracks inspected listings, evaluates AMVGG profit/status,
	and ranks opportunities. Never fabricates listings.
]]

local ListingScanner = {}
ListingScanner.__index = ListingScanner

export type ScannedListing = {
	listingId: string,
	sellerId: string?,
	offeredItems: { any }, -- what the seller is offering (you receive)
	requestedItems: { any }, -- what the seller is asking for (you give)
	totalAmvggOffered: number,
	totalAmvggRequested: number,
	estimatedProfit: number,
	profitPercent: number,
	confidenceStatus: string,
	listingStatus: string, -- "GOOD DEAL" | "FAIR DEAL" | "BAD DEAL" | "INCOMPLETE DATA" | "EXPIRED LISTING"
	liquidityNote: string,
	riskScore: number,
	timestamp: number,
	inspected: boolean,
	source: string, -- "game" | "manual" | "import"
}

function ListingScanner.new(deps: {
	tradeEvaluator: any,
	config: any,
	eventBus: any?,
	state: any?,
	logger: any?,
	json: any?,
	gameAdapter: any?,
	clockFn: (() -> number)?,
})
	local self = setmetatable({}, ListingScanner)
	self._evaluator = deps.tradeEvaluator
	self._config = deps.config
	self._eventBus = deps.eventBus
	self._state = deps.state
	self._logger = deps.logger
	self._json = deps.json
	self._gameAdapter = deps.gameAdapter
	self._clock = deps.clockFn or os.time

	self._listings = {} :: { [string]: ScannedListing }
	self._orderedIds = {} :: { string }
	self._seenSignatures = {} :: { [string]: boolean }
	self._scanCount = 0
	self._lastScanAt = nil :: number?
	self._integrationWarning = nil :: string?
	return self
end

local function makeSignature(raw: any): string
	local parts = {}
	for _, it in ipairs(raw.offeredItems or {}) do
		table.insert(parts, string.format("O:%s:%s:%s:%s:%s", tostring(it.name), tostring(it.neon), tostring(it.mega), tostring(it.fly), tostring(it.ride)))
	end
	for _, it in ipairs(raw.requestedItems or {}) do
		table.insert(parts, string.format("R:%s:%s:%s:%s:%s", tostring(it.name), tostring(it.neon), tostring(it.mega), tostring(it.fly), tostring(it.ride)))
	end
	return tostring(raw.listingId or "") .. "|" .. table.concat(parts, ";")
end

function ListingScanner:ingestListing(raw: any, source: string?): (ScannedListing?, boolean)
	if type(raw) ~= "table" or type(raw.offeredItems) ~= "table" or type(raw.requestedItems) ~= "table" then
		return nil, false
	end
	local id = tostring(raw.listingId or ("manual_" .. tostring(#self._orderedIds + 1) .. "_" .. tostring(self._clock())))
	local sig = makeSignature(raw)
	local isNew = not self._seenSignatures[sig]
	self._seenSignatures[sig] = true

	-- Note: from our perspective, we GIVE requestedItems and RECEIVE offeredItems
	local res = self._evaluator:evaluate(raw.requestedItems, raw.offeredItems, { isExpired = raw.expired == true })
	local eval = res.evaluation

	local entry: ScannedListing = {
		listingId = id,
		sellerId = if raw.sellerId ~= nil then tostring(raw.sellerId) else nil,
		offeredItems = raw.offeredItems,
		requestedItems = raw.requestedItems,
		totalAmvggOffered = eval.theirValue,
		totalAmvggRequested = eval.yourValue,
		estimatedProfit = eval.potentialProfit,
		profitPercent = eval.percentDifference,
		confidenceStatus = res.confidence,
		listingStatus = res.listingStatus,
		liquidityNote = res.metrics.liquidityNote,
		riskScore = res.metrics.riskScore,
		timestamp = tonumber(raw.timestamp) or self._clock(),
		inspected = true,
		source = source or "manual",
	}

	if not self._listings[id] then
		table.insert(self._orderedIds, id)
	end
	self._listings[id] = entry
	return entry, isNew
end

function ListingScanner:scanOnce(): { ok: boolean, total: number, fresh: number, goodDeals: number, warning: string? }
	self._scanCount += 1
	self._lastScanAt = self._clock()

	if not (self._gameAdapter and type(self._gameAdapter.fetchListings) == "function") then
		local warnMsg = "Live Trade Hub listing adapter unavailable in this environment; use Manual/Import Listing Scanner"
		self._integrationWarning = warnMsg
		local all = self:getRankedOpportunities({})
		local good = 0
		for _, l in ipairs(all) do
			if l.listingStatus == "GOOD DEAL" then
				good += 1
			end
		end
		if self._state then
			self._state:set("scanner.warning", warnMsg, "ListingScanner")
			self._state:set("scanner.inspectedCount", #self._orderedIds, "ListingScanner")
			self._state:set("scanner.goodDealCount", good, "ListingScanner")
		end
		return { ok = false, total = #self._orderedIds, fresh = 0, goodDeals = good, warning = warnMsg }
	end

	self._integrationWarning = nil
	local ok, rawListings = pcall(self._gameAdapter.fetchListings)
	if not ok or type(rawListings) ~= "table" then
		local err = "Trade Hub scan failed: " .. tostring(rawListings)
		if self._logger then
			self._logger:warn("ListingScanner", err)
		end
		return { ok = false, total = #self._orderedIds, fresh = 0, goodDeals = 0, warning = err }
	end

	local fresh = 0
	local goodDeals = 0
	for _, raw in ipairs(rawListings) do
		local entry, isNew = self:ingestListing(raw, "game")
		if entry then
			if isNew then
				fresh += 1
			end
			if entry.listingStatus == "GOOD DEAL" then
				goodDeals += 1
			end
		end
	end

	if self._state then
		self._state:set("scanner.warning", nil, "ListingScanner")
		self._state:set("scanner.inspectedCount", #self._orderedIds, "ListingScanner")
		self._state:set("scanner.goodDealCount", goodDeals, "ListingScanner")
	end
	if self._eventBus then
		self._eventBus:emit("Scanner:Completed", {
			total = #self._orderedIds,
			fresh = fresh,
			goodDeals = goodDeals,
		})
	end

	return { ok = true, total = #self._orderedIds, fresh = fresh, goodDeals = goodDeals, warning = nil }
end

function ListingScanner:importJson(jsonText: string): (boolean, string?, number)
	if not (self._json and type(self._json.decode) == "function") then
		return false, "JSON decoder unavailable", 0
	end
	local ok, decoded = pcall(self._json.decode, jsonText)
	if not ok or type(decoded) ~= "table" then
		return false, "Malformed listing JSON", 0
	end
	local list = if type(decoded.listings) == "table" then decoded.listings else decoded
	local added = 0
	local goodDeals = 0
	for _, raw in ipairs(list) do
		local entry = self:ingestListing(raw, "import")
		if entry then
			added += 1
			if entry.listingStatus == "GOOD DEAL" then
				goodDeals += 1
			end
		end
	end
	if self._state then
		self._state:set("scanner.inspectedCount", #self._orderedIds, "ListingScanner")
		self._state:set("scanner.goodDealCount", goodDeals, "ListingScanner")
	end
	if self._eventBus then
		self._eventBus:emit("Scanner:Completed", { total = #self._orderedIds, fresh = added, goodDeals = goodDeals })
	end
	return true, nil, added
end

function ListingScanner:markExpired(listingId: string): boolean
	local item = self._listings[listingId]
	if not item then
		return false
	end
	item.listingStatus = "EXPIRED LISTING"
	return true
end

function ListingScanner:getRankedOpportunities(filters: {
	petQuery: string?,
	minValue: number?,
	minProfit: number?,
	minPctGain: number?,
	includeIncomplete: boolean?,
}?): { ScannedListing }
	local f = filters or {}
	local q = string.lower(tostring(f.petQuery or "")):match("^%s*(.-)%s*$") or ""
	local out = {}

	for _, id in ipairs(self._orderedIds) do
		local l = self._listings[id]
		if l and l.listingStatus ~= "EXPIRED LISTING" then
			local ok = true
			if not f.includeIncomplete and l.listingStatus == "INCOMPLETE DATA" then
				ok = false
			end
			if ok and f.minValue and l.totalAmvggOffered < f.minValue then
				ok = false
			end
			if ok and f.minProfit and l.estimatedProfit < f.minProfit then
				ok = false
			end
			if ok and f.minPctGain and l.profitPercent < f.minPctGain then
				ok = false
			end
			if ok and q ~= "" then
				local found = false
				for _, it in ipairs(l.offeredItems) do
					if string.find(string.lower(tostring(it.name or "")), q, 1, true) then
						found = true
						break
					end
				end
				if not found then
					for _, it in ipairs(l.requestedItems) do
						if string.find(string.lower(tostring(it.name or "")), q, 1, true) then
							found = true
							break
						end
					end
				end
				ok = found
			end
			if ok then
				table.insert(out, l)
			end
		end
	end

	table.sort(out, function(a, b)
		if a.estimatedProfit ~= b.estimatedProfit then
			return a.estimatedProfit > b.estimatedProfit
		end
		return a.profitPercent > b.profitPercent
	end)

	return out
end

function ListingScanner:getStats(): { inspectedCount: number, goodDeals: number, scanCount: number, lastScanAt: number?, warning: string? }
	local good = 0
	for _, id in ipairs(self._orderedIds) do
		local l = self._listings[id]
		if l and l.listingStatus == "GOOD DEAL" then
			good += 1
		end
	end
	return {
		inspectedCount = #self._orderedIds,
		goodDeals = good,
		scanCount = self._scanCount,
		lastScanAt = self._lastScanAt,
		warning = self._integrationWarning,
	}
end

return ListingScanner

end

__moduleSources["Trading/OfferAnalyzer"] = function(...)
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

end

__moduleSources["Trading/ListingManager"] = function(...)
--[[
	ListingManager.luau
	Manages listing drafts, AMVGG previews, published listings, incoming offers,
	and configurable stale-listing detection (30, 45, 60 default, 90, 120s).
	Never auto-cancels or reposts without explicit user confirmation/permission.
]]

local ListingManager = {}
ListingManager.__index = ListingManager

export type ListingRecord = {
	id: string,
	offeredItems: { any },
	requestedItems: { any }?,
	offeredValue: number,
	requestedValue: number,
	expectedProfitPct: number,
	status: string, -- "DRAFT" | "ACTIVE" | "STALE" | "CANCELLED" | "COMPLETED"
	createdAt: number,
	expiresAfterSeconds: number,
	incomingOffers: { any },
	staleNotified: boolean,
	suggestion: string?,
}

function ListingManager.new(deps: {
	valueEngine: any,
	config: any,
	eventBus: any?,
	state: any?,
	logger: any?,
	clockFn: (() -> number)?,
})
	local self = setmetatable({}, ListingManager)
	self._valueEngine = deps.valueEngine
	self._config = deps.config
	self._eventBus = deps.eventBus
	self._state = deps.state
	self._logger = deps.logger
	self._clock = deps.clockFn or os.time

	self._listings = {} :: { [string]: ListingRecord }
	self._order = {} :: { string }
	self._nextId = 1
	return self
end

function ListingManager:previewDraft(offeredItems: { any }, requestedItems: { any }?): {
	offeredValue: number,
	requestedValue: number,
	profitValue: number,
	profitPercent: number,
	complete: boolean,
}
	local offEval = self._valueEngine:evaluateList(offeredItems)
	if requestedItems and #requestedItems > 0 then
		local tradeEval = self._valueEngine:evaluateTrade(offeredItems, requestedItems)
		return {
			offeredValue = tradeEval.yourValue,
			requestedValue = tradeEval.theirValue,
			profitValue = tradeEval.difference,
			profitPercent = tradeEval.percentDifference,
			complete = tradeEval.complete,
		}
	end
	return {
		offeredValue = offEval.totalValue,
		requestedValue = 0,
		profitValue = 0,
		profitPercent = 0,
		complete = offEval.complete,
	}
end

function ListingManager:createDraft(offeredItems: { any }, requestedItems: { any }?, expiresAfterSeconds: number?): ListingRecord
	local preview = self:previewDraft(offeredItems, requestedItems)
	local id = string.format("lst_%d_%d", self._clock(), self._nextId)
	self._nextId += 1

	local ttl = tonumber(expiresAfterSeconds) or tonumber(self._config:get("Trading.ListingExpirationSeconds")) or 60
	local rec: ListingRecord = {
		id = id,
		offeredItems = offeredItems,
		requestedItems = requestedItems,
		offeredValue = preview.offeredValue,
		requestedValue = preview.requestedValue,
		expectedProfitPct = preview.profitPercent,
		status = "DRAFT",
		createdAt = self._clock(),
		expiresAfterSeconds = ttl,
		incomingOffers = {},
		staleNotified = false,
		suggestion = nil,
	}
	self._listings[id] = rec
	table.insert(self._order, id)
	return rec
end

function ListingManager:publishListing(id: string): (boolean, string?)
	local rec = self._listings[id]
	if not rec then
		return false, "Listing not found"
	end
	local maxActive = tonumber(self._config:get("Trading.MaxActiveListings")) or 5
	local activeCount = #self:getActive()
	if activeCount >= maxActive then
		return false, string.format("Max active listings limit (%d) reached", maxActive)
	end
	rec.status = "ACTIVE"
	rec.createdAt = self._clock()
	rec.staleNotified = false
	if self._eventBus then
		self._eventBus:emit("Listing:Published", rec)
	end
	return true, nil
end

function ListingManager:attachIncomingOffer(listingId: string, offerSummary: any): boolean
	local rec = self._listings[listingId]
	if not rec then
		return false
	end
	table.insert(rec.incomingOffers, offerSummary)
	if self._eventBus then
		self._eventBus:emit("Listing:IncomingOffer", { listing = rec, offer = offerSummary })
	end
	return true
end

function ListingManager:checkStaleListings(): { ListingRecord }
	local now = self._clock()
	local staleList = {}

	for _, id in ipairs(self._order) do
		local rec = self._listings[id]
		if rec and rec.status == "ACTIVE" then
			local age = now - rec.createdAt
			if age >= rec.expiresAfterSeconds then
				rec.status = "STALE"
				-- Recalculate attractiveness against current AMVGG values
				local preview = self:previewDraft(rec.offeredItems, rec.requestedItems)
				rec.offeredValue = preview.offeredValue
				rec.requestedValue = preview.requestedValue
				rec.expectedProfitPct = preview.profitPercent
				rec.suggestion = if #rec.incomingOffers > 0
					then "Has pending incoming offers — review before cancelling"
					elseif preview.profitPercent > 20 then "Ask % may be too high; consider lowering ask or open offers"
					else "Refresh listing to regain Trade Hub visibility"

				if not rec.staleNotified then
					rec.staleNotified = true
					if self._eventBus then
						self._eventBus:emit("Listing:Stale", {
							listing = rec,
							ageSeconds = age,
							hasIncomingOffers = #rec.incomingOffers > 0,
						})
					end
				end
				table.insert(staleList, rec)
			end
		end
	end
	return staleList
end

function ListingManager:cancelListing(id: string, confirmed: boolean): (boolean, string?)
	local rec = self._listings[id]
	if not rec then
		return false, "Listing not found"
	end
	if not confirmed then
		if #rec.incomingOffers > 0 then
			return false, "Confirmation required: listing has pending incoming offers"
		end
		return false, "Explicit user confirmation required to cancel listing"
	end
	rec.status = "CANCELLED"
	if self._eventBus then
		self._eventBus:emit("Listing:Cancelled", rec)
	end
	return true, nil
end

function ListingManager:getActive(): { ListingRecord }
	local out = {}
	for _, id in ipairs(self._order) do
		local rec = self._listings[id]
		if rec and (rec.status == "ACTIVE" or rec.status == "STALE") then
			table.insert(out, rec)
		end
	end
	return out
end

function ListingManager:getAll(): { ListingRecord }
	local out = {}
	for _, id in ipairs(self._order) do
		if self._listings[id] then
			table.insert(out, self._listings[id])
		end
	end
	return out
end

return ListingManager

end

__moduleSources["Trading/OfferTimer"] = function(...)
--[[
	OfferTimer.luau
	Tracks response monitoring intervals (30-60s default) and expiration
	countdowns for pending offers without blocking or spamming.
]]

local OfferTimer = {}
OfferTimer.__index = OfferTimer

function OfferTimer.new(config: any, clockFn: (() -> number)?)
	local self = setmetatable({}, OfferTimer)
	self._config = config
	self._clock = clockFn or os.time
	self._lastCheckAt = 0
	return self
end

function OfferTimer:getAgeSeconds(createdAt: number): number
	return math.max(0, self._clock() - createdAt)
end

function OfferTimer:getRemainingSeconds(createdAt: number, expirationSeconds: number?): number
	local exp = expirationSeconds or tonumber(self._config:get("Trading.OfferExpirationSeconds")) or 180
	return math.max(0, exp - self:getAgeSeconds(createdAt))
end

function OfferTimer:isExpired(createdAt: number, expirationSeconds: number?): boolean
	return self:getRemainingSeconds(createdAt, expirationSeconds) <= 0
end

function OfferTimer:shouldNotifyNoResponse(lastCheckedAt: number?): boolean
	local interval = tonumber(self._config:get("Trading.OfferResponseIntervalSeconds")) or 45
	local now = self._clock()
	if not lastCheckedAt then
		return false
	end
	return (now - lastCheckedAt) >= interval
end

return OfferTimer

end

__moduleSources["Trading/OfferQueue"] = function(...)
--[[
	OfferQueue.luau
	Tracks outgoing and incoming offers with full AMVGG evaluation, status lifecycle,
	anti-spam deduplication, response timer checks, and mandatory user confirmation
	for final trade acceptance.
]]

local OfferQueue = {}
OfferQueue.__index = OfferQueue

export type OfferStatus = "PENDING" | "ACCEPTED" | "DECLINED" | "EXPIRED" | "CANCELLED" | "UNKNOWN"

export type OfferRecord = {
	offerId: string,
	listingId: string?,
	direction: string, -- "OUTGOING" | "INCOMING"
	offeredItems: { any },
	requestedItems: { any },
	evaluation: any,
	profitValue: number,
	profitPercent: number,
	createdAt: number,
	lastCheckedAt: number,
	expiresAt: number,
	status: OfferStatus,
	noResponseNotified: boolean,
}

function OfferQueue.new(deps: {
	valueEngine: any,
	offerTimer: any,
	config: any,
	eventBus: any?,
	state: any?,
	logger: any?,
	clockFn: (() -> number)?,
})
	local self = setmetatable({}, OfferQueue)
	self._valueEngine = deps.valueEngine
	self._timer = deps.offerTimer
	self._config = deps.config
	self._eventBus = deps.eventBus
	self._state = deps.state
	self._logger = deps.logger
	self._clock = deps.clockFn or os.time

	self._offers = {} :: { [string]: OfferRecord }
	self._order = {} :: { string }
	self._nextId = 1
	return self
end

function OfferQueue:hasPendingForListing(listingId: string): boolean
	if not listingId or listingId == "" then
		return false
	end
	for _, id in ipairs(self._order) do
		local o = self._offers[id]
		if o and o.status == "PENDING" and o.listingId == listingId then
			return true
		end
	end
	return false
end

function OfferQueue:getPendingCount(): number
	local count = 0
	for _, id in ipairs(self._order) do
		if self._offers[id] and self._offers[id].status == "PENDING" then
			count += 1
		end
	end
	return count
end

function OfferQueue:enqueue(params: {
	listingId: string?,
	direction: string?,
	offeredItems: { any },
	requestedItems: { any },
	expirationSeconds: number?,
}): (OfferRecord?, string?)
	if params.listingId and self:hasPendingForListing(params.listingId) then
		return nil, "Duplicate offer prevented: already have a pending offer for listing " .. tostring(params.listingId)
	end

	local maxPending = tonumber(self._config:get("Trading.MaxPendingOffers")) or 20
	if self:getPendingCount() >= maxPending then
		return nil, string.format("Max pending offers limit (%d) reached", maxPending)
	end

	local eval = self._valueEngine:evaluateTrade(params.offeredItems, params.requestedItems)
	local now = self._clock()
	local ttl = params.expirationSeconds or tonumber(self._config:get("Trading.OfferExpirationSeconds")) or 180
	local id = string.format("off_%d_%d", now, self._nextId)
	self._nextId += 1

	local rec: OfferRecord = {
		offerId = id,
		listingId = params.listingId,
		direction = params.direction or "OUTGOING",
		offeredItems = params.offeredItems,
		requestedItems = params.requestedItems,
		evaluation = eval,
		profitValue = eval.potentialProfit,
		profitPercent = eval.percentDifference,
		createdAt = now,
		lastCheckedAt = now,
		expiresAt = now + ttl,
		status = "PENDING",
		noResponseNotified = false,
	}

	self._offers[id] = rec
	table.insert(self._order, id)

	if self._state then
		self._state:set("offers.pendingCount", self:getPendingCount(), "OfferQueue")
	end
	if self._eventBus then
		self._eventBus:emit("Offer:Queued", rec)
	end
	return rec, nil
end

function OfferQueue:updateStatus(offerId: string, newStatus: OfferStatus, options: { userConfirmed: boolean? }?): (boolean, string?)
	local rec = self._offers[offerId]
	if not rec then
		return false, "Offer not found"
	end
	if newStatus == "ACCEPTED" and not (options and options.userConfirmed == true) then
		return false, "Explicit user confirmation required before accepting any trade"
	end

	rec.status = newStatus
	if self._state then
		self._state:set("offers.pendingCount", self:getPendingCount(), "OfferQueue")
	end
	if self._eventBus then
		self._eventBus:emit("Offer:StatusChanged", rec)
	end
	return true, nil
end

function OfferQueue:checkPendingTimers(): { expired: { OfferRecord }, awaitingResponse: { OfferRecord } }
	local now = self._clock()
	local expired = {}
	local awaitingResponse = {}

	for _, id in ipairs(self._order) do
		local rec = self._offers[id]
		if rec and rec.status == "PENDING" then
			if now >= rec.expiresAt then
				rec.status = "EXPIRED"
				table.insert(expired, rec)
				if self._eventBus then
					self._eventBus:emit("Offer:Expired", rec)
				end
			elseif self._timer:shouldNotifyNoResponse(rec.lastCheckedAt) then
				rec.lastCheckedAt = now
				rec.noResponseNotified = true
				table.insert(awaitingResponse, rec)
				if self._eventBus then
					self._eventBus:emit("Offer:NoResponse", {
						offer = rec,
						ageSeconds = self._timer:getAgeSeconds(rec.createdAt),
					})
				end
			end
		end
	end

	if #expired > 0 and self._state then
		self._state:set("offers.pendingCount", self:getPendingCount(), "OfferQueue")
	end

	return { expired = expired, awaitingResponse = awaitingResponse }
end

function OfferQueue:getReservedPetUids(): { [string]: boolean }
	local reserved = {}
	for _, id in ipairs(self._order) do
		local rec = self._offers[id]
		if rec and rec.status == "PENDING" then
			for _, pet in ipairs(rec.offeredItems) do
				if pet.uid then
					reserved[tostring(pet.uid)] = true
				end
			end
		end
	end
	return reserved
end

function OfferQueue:getAll(): { OfferRecord }
	local out = {}
	for _, id in ipairs(self._order) do
		if self._offers[id] then
			table.insert(out, self._offers[id])
		end
	end
	return out
end

return OfferQueue

end

__moduleSources["Trading/TradeHistory"] = function(...)
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

end

__moduleSources["Trading/TradeHubAdapter"] = function(...)
--[[
	TradeHubAdapter.luau
	Hooks into Adopt Me's Trade Hub using the same RemoteEvents
	that the game's own UI fires. Reads listings and sends offers.

	Only fires RemoteEvents that the legitimate game client fires —
	no memory scanning, no anti-cheat bypass.

	RemoteEvent names discovered via AdoptMeFarm source analysis:
	  Adopt Me uses a ReplicatedStorage.Remotes folder (or similar)
	  containing BindableEvents / RemoteEvents for trade hub.

	Trade Hub flow (observed from game behaviour):
	  1. Player walks to Trade Hub → game fires "TradeHub_Request" or similar
	  2. Server responds with listing data via RemoteEvent callback
	  3. Player clicks "Make Offer" → fires TradeHub remote with offer table

	This adapter tries multiple known remote names and falls back
	to parsing the in-game UI ScreenGui if direct remotes are unavailable.
]]

local TradeHubAdapter = {}
TradeHubAdapter.__index = TradeHubAdapter

-- Known remote names to try (in order of preference)
local REMOTE_CANDIDATES = {
	-- folder / event combos: { folderName, eventName }
	{ "adoptme_new_net", "adoptme_new.modules.TradeHub.TradeHubNet" },
	{ "Remotes", "TradeHub_GetListings" },
	{ "Remotes", "GetTradeHubListings" },
	{ "Remotes", "TradingHub_Request" },
	{ "Remotes", "TradeHub" },
	{ "Events", "TradeHub_GetListings" },
	{ "Events", "GetTradeHubListings" },
}

local OFFER_REMOTE_CANDIDATES = {
	{ "Remotes", "TradeHub_MakeOffer" },
	{ "Remotes", "MakeTradeHubOffer" },
	{ "Remotes", "TradeHub_Offer" },
	{ "Remotes", "MakeTradeOffer" },
	{ "Events", "TradeHub_MakeOffer" },
}

export type Listing = {
	sellerId: string,       -- UserId string
	sellerName: string,
	offeredPets: { string },  -- pet UIDs or kinds they offer (what they give)
	requestedPets: { string }, -- what they want
	offeredValue: number,
	requestedValue: number,
}

export type Options = {
	logger: any?,
	eventBus: any?,
}

function TradeHubAdapter.new(opts: Options?)
	local o = opts or {}
	local self = setmetatable({}, TradeHubAdapter)
	self._logger   = o.logger
	self._eventBus = o.eventBus
	self._tradeHubNet    = nil
	self._listingsRemote = nil
	self._offerRemote    = nil
	self._lastScan = {}
	self._available = false
	self:_findRemotes()
	return self
end

function TradeHubAdapter:_log(level: string, msg: string)
	if self._logger and type(self._logger[level:lower()]) == "function" then
		self._logger[level:lower()](self._logger, "[TradeHubAdapter] " .. msg)
	end
end

function TradeHubAdapter:_findRemotes()
	if type(game) ~= "userdata" and type(game) ~= "table" then return end
	local ok, RS = pcall(function() return game:GetService("ReplicatedStorage") end)
	if not ok or not RS then return end

	-- 0. Primary: Require ReplicatedStorage.new.modules.TradeHub.TradeHubNet directly
	local okNet, netMod = pcall(function()
		return require(RS:WaitForChild("new", 2):WaitForChild("modules", 2):WaitForChild("TradeHub", 2):WaitForChild("TradeHubNet", 2))
	end)
	if okNet and type(netMod) == "table" and netMod.search_listings_async then
		self._tradeHubNet = netMod
		self._available = true
		self:_log("INFO", "Connected to ReplicatedStorage.new.modules.TradeHub.TradeHubNet")
		return
	end

	-- Try to find listings remote
	for _, candidate in ipairs(REMOTE_CANDIDATES) do
		local folder = RS:FindFirstChild(candidate[1])
		if folder then
			local remote = folder:FindFirstChild(candidate[2])
			if remote then
				self._listingsRemote = remote
				self:_log("INFO", "Found listings remote: " .. candidate[1] .. "/" .. candidate[2])
				break
			end
		end
	end

	-- Try to find offer remote
	for _, candidate in ipairs(OFFER_REMOTE_CANDIDATES) do
		local folder = RS:FindFirstChild(candidate[1])
		if folder then
			local remote = folder:FindFirstChild(candidate[2])
			if remote then
				self._offerRemote = remote
				self:_log("INFO", "Found offer remote: " .. candidate[1] .. "/" .. candidate[2])
				break
			end
		end
	end

	-- Also try scanning all remotes for trade-related names
	if not self._listingsRemote or not self._offerRemote then
		self:_scanAllRemotes(RS)
	end

	self._available = self._listingsRemote ~= nil
end

function TradeHubAdapter:_scanAllRemotes(RS: any)
	-- 1. Check adoptme_new_net folder specifically (Adopt Me's new TradeHub net)
	local newNet = RS:FindFirstChild("adoptme_new_net")
	if newNet then
		for _, child in ipairs(newNet:GetChildren()) do
			local name = child.Name:lower()
			if name:find("tradehub") then
				if not self._listingsRemote and (name:find("listing") or name:find("search") or name:find("get") or name:find("net")) then
					if child.ClassName == "RemoteFunction" or child.ClassName == "RemoteEvent" then
						self._listingsRemote = child
						self:_log("INFO", "Auto-found adoptme_new_net listings remote: " .. child.Name)
					end
				end
				if not self._offerRemote and (name:find("counter") or name:find("offer") or name:find("post")) then
					if child.ClassName == "RemoteFunction" or child.ClassName == "RemoteEvent" then
						self._offerRemote = child
						self:_log("INFO", "Auto-found adoptme_new_net offer remote: " .. child.Name)
					end
				end
			end
		end
	end

	-- 2. Fallback: scan other folders
	local function scanFolder(folder: any)
		for _, child in ipairs(folder:GetChildren()) do
			local name = child.Name:lower()
			if not self._listingsRemote then
				if name:find("tradehub") or name:find("trade_hub") or name:find("hub.*list") or name:find("list.*hub") then
					if child.ClassName == "RemoteFunction" or child.ClassName == "RemoteEvent" then
						self._listingsRemote = child
						self:_log("INFO", "Auto-found listings remote: " .. child.Name)
					end
				end
			end
			if not self._offerRemote then
				if (name:find("tradehub") or name:find("trade_hub")) and (name:find("offer") or name:find("send") or name:find("make")) then
					if child.ClassName == "RemoteFunction" or child.ClassName == "RemoteEvent" then
						self._offerRemote = child
						self:_log("INFO", "Auto-found offer remote: " .. child.Name)
					end
				end
			end
			-- recurse one level
			if child.ClassName == "Folder" then
				scanFolder(child)
			end
		end
	end

	pcall(scanFolder, RS)
end

-- ── isAvailable() ────────────────────────────────────────────────────────────

function TradeHubAdapter:isAvailable(): boolean
	return self._available
end

-- ── fetchListings() ──────────────────────────────────────────────────────────
-- Fires the TradeHub remote and returns parsed listings.
-- Returns: { listings: { Listing }, error: string? }

function TradeHubAdapter:fetchListings(): { listings: { Listing }, error: string? }
	-- Primary: use TradeHubNet.search_listings_async
	if self._tradeHubNet and self._tradeHubNet.search_listings_async then
		local raw = nil
		local ok, err = pcall(function()
			local fn = self._tradeHubNet.search_listings_async
			local req = {
				lister_items_slugs = {},
				responder_items = {},
			}
			if type(fn.invoke) == "function" then
				raw = fn:invoke(req)
			elseif type(fn.Invoke) == "function" then
				raw = fn:Invoke(req)
			elseif type(fn.call) == "function" then
				raw = fn:call(req)
			end
		end)
		if ok and type(raw) == "table" then
			local listings: { Listing } = {}
			self:_parseListings(raw.listings or raw.results or raw, listings)
			self._lastScan = listings
			self:_log("INFO", string.format("TradeHubNet fetched %d listings", #listings))
			return { listings = listings }
		elseif not ok then
			self:_log("WARN", "TradeHubNet.search_listings_async error: " .. tostring(err))
		end
	end

	if not self._listingsRemote then
		return { listings = {}, error = "No Trade Hub remote found in ReplicatedStorage" }
	end

	local raw = nil
	local ok, err = pcall(function()
		local remote = self._listingsRemote
		if remote.ClassName == "RemoteFunction" then
			raw = remote:InvokeServer()
		elseif remote.ClassName == "RemoteEvent" then
			-- For RemoteEvents we can't get a return value directly.
			-- Use a temporary callback pattern.
			local received = false
			local conn
			conn = remote.OnClientEvent:Connect(function(data)
				raw = data
				received = true
				conn:Disconnect()
			end)
			remote:FireServer("GetListings")
			-- Wait up to 5 seconds
			local t = os.clock()
			while not received and (os.clock() - t) < 5 do
				task.wait(0.1)
			end
			if not received then
				conn:Disconnect()
				error("Timeout waiting for Trade Hub response")
			end
		end
	end)

	if not ok then
		self:_log("WARN", "fetchListings error: " .. tostring(err))
		return { listings = {}, error = tostring(err) }
	end

	if type(raw) ~= "table" then
		return { listings = {}, error = "Unexpected response type: " .. type(raw) }
	end

	-- Parse raw listings — Adopt Me uses varying formats; we try common shapes
	local listings: { Listing } = {}
	self:_parseListings(raw, listings)

	self._lastScan = listings
	self:_log("INFO", string.format("Fetched %d Trade Hub listings", #listings))
	return { listings = listings }
end

function TradeHubAdapter:_parseListings(raw: any, out: { Listing })
	-- Shape 1: array of listing tables
	if raw[1] then
		for _, entry in ipairs(raw) do
			if type(entry) == "table" then
				local listing = self:_parseEntry(entry)
				if listing then table.insert(out, listing) end
			end
		end
		return
	end
	-- Shape 2: map of userId -> listing
	for userId, entry in pairs(raw) do
		if type(entry) == "table" then
			local listing = self:_parseEntry(entry)
			if listing then
				listing.sellerId = tostring(userId)
				table.insert(out, listing)
			end
		end
	end
end

function TradeHubAdapter:_parseEntry(entry: any): Listing?
	if type(entry) ~= "table" then return nil end

	-- Common field names observed in Adopt Me trade hub data
	local sellerId   = tostring(entry.listing_id or entry.userId or entry.user_id or entry.seller or entry.id or "?")
	local sellerName = tostring(entry.username or entry.name or entry.playerName or "TradeHub")

	-- What they offer (they give to you): lister_items in TradeHubNet
	local offeredPets: { string } = {}
	local offerSrc = entry.lister_items or entry.offer or entry.offered or entry.giving or entry.pets or entry.items or {}
	if type(offerSrc) == "table" then
		for _, p in ipairs(offerSrc) do
			if type(p) == "string" then
				table.insert(offeredPets, p)
			elseif type(p) == "table" then
				table.insert(offeredPets, tostring(p.kind or p.id or p.name or "unknown"))
			end
		end
	end

	-- What they want (they request from you): responder_items in TradeHubNet
	local requestedPets: { string } = {}
	local reqSrc = entry.responder_items or entry.request or entry.requested or entry.wanting or entry.want or {}
	if type(reqSrc) == "table" then
		for _, p in ipairs(reqSrc) do
			if type(p) == "string" then
				table.insert(requestedPets, p)
			elseif type(p) == "table" then
				table.insert(requestedPets, tostring(p.kind or p.id or p.name or "unknown"))
			end
		end
	end

	if #offeredPets == 0 and #requestedPets == 0 then
		return nil -- skip empty entries
	end

	return {
		sellerId = sellerId,
		sellerName = sellerName,
		offeredPets = offeredPets,
		requestedPets = requestedPets,
		offeredValue  = tonumber(entry.offeredValue or entry.value or 0) or 0,
		requestedValue = tonumber(entry.requestedValue or entry.wantValue or 0) or 0,
	}
end

-- ── sendOffer() ──────────────────────────────────────────────────────────────
-- Sends a trade offer via the game's RemoteEvent.
-- targetUserId: string UserId of the listing owner
-- offeredItems: { string } — UIDs of pets you offer
-- requestedItems: { string } — UIDs or kinds you want from them
-- Returns: { success: boolean, error: string? }

function TradeHubAdapter:sendOffer(
	targetUserId: string,
	offeredItems: { string },
	requestedItems: { string }
): { success: boolean, error: string? }

	-- Primary: use TradeHubNet.post_counter_async (targetUserId holds listing_id when from TradeHubNet)
	if self._tradeHubNet and self._tradeHubNet.post_counter_async then
		local ok, err = pcall(function()
			local fn = self._tradeHubNet.post_counter_async
			local req = {
				listing_id = tostring(targetUserId),
				responder_items_uniques = offeredItems,
				auto_trade_mode = "post_counter_only",
			}
			if type(fn.invoke) == "function" then
				fn:invoke(req)
			elseif type(fn.Invoke) == "function" then
				fn:Invoke(req)
			elseif type(fn.call) == "function" then
				fn:call(req)
			end
		end)
		if ok then
			self:_log("INFO", string.format("TradeHubNet.post_counter_async sent for listing=%s (offered=%d)", tostring(targetUserId), #offeredItems))
			return { success = true }
		else
			self:_log("WARN", "TradeHubNet.post_counter_async error: " .. tostring(err))
			return { success = false, error = tostring(err) }
		end
	end

	if not self._offerRemote then
		-- Try to find it now (remote might have loaded after init)
		self:_findRemotes()
	end

	if not self._offerRemote then
		return { success = false, error = "No Trade Hub offer remote found" }
	end

	local ok, err = pcall(function()
		local remote = self._offerRemote
		local payload = {
			targetUserId  = tonumber(targetUserId) or targetUserId,
			offered       = offeredItems,
			requested     = requestedItems,
		}
		if remote.ClassName == "RemoteFunction" then
			remote:InvokeServer(payload)
		else
			remote:FireServer(payload)
		end
	end)

	if not ok then
		self:_log("WARN", "sendOffer error: " .. tostring(err))
		return { success = false, error = tostring(err) }
	end

	self:_log("INFO", string.format(
		"Sent offer to userId=%s (offered=%d pets, requested=%d pets)",
		targetUserId, #offeredItems, #requestedItems
	))
	return { success = true }
end

-- ── getLastScan() ─────────────────────────────────────────────────────────────

function TradeHubAdapter:getLastScan(): { Listing }
	return self._lastScan
end

return TradeHubAdapter

end

__moduleSources["Kiria/Personality"] = function(...)
--[[
	Personality.luau
	Kiria's voice, rank ladder, moods, and template formatter.
	Honest, calm, and never fabricates trade results.
]]

local Personality = {}

Personality.Name = "Kiria"
Personality.Title = "Kirito's Lost Fragment"

Personality.Ranks = {
	{ xp = 0, title = "Intern" },
	{ xp = 100, title = "Junior Analyst" },
	{ xp = 300, title = "Analyst" },
	{ xp = 700, title = "Trader" },
	{ xp = 1500, title = "Senior Trader" },
	{ xp = 3000, title = "Head of Trading" },
	{ xp = 6000, title = "Chief Trading Officer" },
	{ xp = 12000, title = "Kirito-Tier" },
}

Personality.Lines = {
	hello = {
		night = {
			"It's late. I'll watch the AMVGG values quietly while you review.",
			"Night shift! Fewer traders are online, so we can be extra picky.",
		},
		morning = {
			"Good morning! I'm at the Trade Hub terminal and ready to start.",
			"Morning! Let's check AMVGG values and see what opportunities appear.",
		},
		day = {
			"Hi! I'm ready at the Trade Hub terminal.",
			"Hello again! I'm watching AMVGG values and waiting for solid deals.",
		},
		evening = {
			"Good evening! Many traders are online now, so let's watch for good deals.",
			"Evening! Let's review listings carefully before the day ends.",
		},
	},
	returning = {
		"Session #{sessions}. Together we've confirmed {trades} {trades:trade|trades} so far.",
		"Day {days} together. {trades} confirmed {trades:trade|trades}, and I never invent results.",
	},
	intro = {
		"I'm Kiria, Kirito's lost fragment. I'll evaluate AMVGG values and guide your trades — you always have final confirmation.",
	},
	amvgg_refresh = {
		"AMVGG values refreshed: {petCount} pets verified from amvgg.com.",
	},
	amvgg_error = {
		"AMVGG refresh hit an issue ({error}). I preserved our last valid cache so nothing breaks.",
		"Couldn't reach live AMVGG ({error}). No live values will be faked.",
	},
	good_deal = {
		"Spotted a good deal on {items}: +{pct}% (+{gain} AMVGG). Worth a look.",
		"Nice opportunity: {items} is +{pct}% on AMVGG. Review it when you're ready.",
	},
	bad_offer = {
		"Careful: that offer is {pct}% behind ({gain} AMVGG). I'd pass on this one.",
	},
	trade_confirmed = {
		"Confirmed trade: gave {give} for {get} (+{pct}%, +{gain} AMVGG). Realized profit updated!",
		"Nice! {give} became {get} (+{pct}%). Confirmed profit is now tracked.",
	},
	loss_trade = {
		"That confirmed trade came out behind ({gain} AMVGG). I've logged it honestly.",
	},
	offer_queued = {
		"Offer queued for review (+{pct}% AMVGG). Nothing is finalized until you confirm.",
	},
	offer_declined = {
		"An offer was declined. That's normal at the Trade Hub — one good yes beats many no's.",
	},
	offer_expired = {
		"An offer expired with no response, freeing those pets for new candidates.",
	},
	listing_published = {
		"Listing published ({offeredValue} AMVGG). I'll watch its age and alert you if it goes stale.",
	},
	listing_stale = {
		"A listing went stale after {age}s without a match. You can refresh or cancel it when ready.",
	},
	incomplete_data = {
		"Some items are missing verified AMVGG values, so I marked them INCOMPLETE instead of guessing.",
	},
	warning = {
		"Heads up: {message}",
	},
	promotion = {
		"I reached {rank}! Thank you for trading carefully with me.",
	},
}

local MONEY_KEYS = { gain = true, total = true, offeredValue = true, receivedValue = true }
local PCT_KEYS = { pct = true, rate = true }

function Personality.getRank(xp: number): string
	local current = Personality.Ranks[1].title
	for _, r in ipairs(Personality.Ranks) do
		if xp >= r.xp then
			current = r.title
		end
	end
	return current
end

function Personality.formatLine(template: string, ctx: { [string]: any }): string?
	if type(template) ~= "string" then
		return nil
	end
	local missing = false

	local out = string.gsub(template, "{(%w+):([^|}]*)|([^}]*)}", function(k, one, many)
		local v = tonumber(ctx[k])
		if v == nil then
			missing = true
			return ""
		end
		return if v == 1 then one else many
	end)

	out = string.gsub(out, "{(%w+)}", function(k)
		local v = ctx[k]
		if v == nil or v == "" then
			missing = true
			return ""
		end
		if PCT_KEYS[k] and tonumber(v) then
			local a = math.abs(tonumber(v) :: number)
			return string.format(if a < 10 then "%.1f" else "%.0f", a)
		end
		if MONEY_KEYS[k] and tonumber(v) then
			return string.format("%.2f", tonumber(v) :: number)
		end
		return tostring(v)
	end)

	if missing then
		return nil
	end
	return out
end

function Personality.pickLine(list: { string }?, ctx: { [string]: any }): string?
	if type(list) ~= "table" or #list == 0 then
		return nil
	end
	local valid = {}
	for _, tpl in ipairs(list) do
		local formatted = Personality.formatLine(tpl, ctx)
		if formatted then
			table.insert(valid, formatted)
		end
	end
	if #valid == 0 then
		return nil
	end
	return valid[math.random(1, #valid)]
end

return Personality

end

__moduleSources["Kiria/Memory"] = function(...)
--[[
	Memory.luau
	Persistent companion memory for Kiria (sessions, confirmed trades, XP, ranks).
]]

local Memory = {}
Memory.__index = Memory

function Memory.new(options: { filePath: string?, fs: any?, json: any?, clockFn: (() -> number)? }?)
	local opts = options or {}
	local self = setmetatable({}, Memory)
	self._filePath = opts.filePath or "KiriaAutoTrader/kiria_memory.json"
	self._fs = opts.fs
	self._json = opts.json
	self._clock = opts.clockFn or os.time

	self._data = {
		sessions = 0,
		firstSeen = self._clock(),
		trades = 0,
		totalGain = 0,
		bestGain = 0,
		xp = 0,
	}
	return self
end

function Memory:getData(): { [string]: any }
	return self._data
end

function Memory:incrementSession(): number
	self._data.sessions += 1
	self._data.xp += 2
	self:save()
	return self._data.sessions
end

function Memory:recordConfirmedTrade(gain: number, pct: number)
	self._data.trades += 1
	self._data.totalGain += gain
	if gain > self._data.bestGain then
		self._data.bestGain = gain
	end
	self._data.xp += 10 + math.min(40, math.max(0, math.floor(pct / 2)))
	self:save()
end

function Memory:addXp(amount: number)
	self._data.xp += math.max(0, amount)
	self:save()
end

function Memory:save(): boolean
	if not (self._fs and self._json and self._fs.write) then
		return false
	end
	local okEnc, encoded = pcall(self._json.encode, self._data)
	if not okEnc or type(encoded) ~= "string" then
		return false
	end
	return pcall(self._fs.write, self._filePath, encoded)
end

function Memory:load(): boolean
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
	for k, v in pairs(decoded) do
		if self._data[k] ~= nil and type(v) == "number" then
			self._data[k] = v
		end
	end
	return true
end

return Memory

end

__moduleSources["Kiria/Reactions"] = function(...)
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

end

__moduleSources["Kiria/Companion"] = function(...)
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

end

__moduleSources["UI/Components/Theme"] = function(...)
--[[
	Theme.luau
	Kiria Dark Trading Terminal visual palette and typography tokens.
]]

local Theme = {}

Theme.Colors = {
	Background = "#0B0E17",
	Surface = "#121726",
	SurfaceAlt = "#181F33",
	Border = "#2A3352",
	Accent = "#9D4EDD",
	AccentBright = "#C77DFF",
	TextPrimary = "#F1F5F9",
	TextMuted = "#94A3B8",
	Profit = "#22C55E",
	Loss = "#EF4444",
	Warning = "#F59E0B",
	Info = "#38BDF8",
}

Theme.Layout = {
	CornerRadius = 10,
	SmallCorner = 6,
	Padding = 12,
	Gap = 10,
	SidebarWidth = 180,
	HeaderHeight = 48,
}

function Theme.toColor3(hex: string): any
	if type(Color3) ~= "table" and type(Color3) ~= "userdata" then
		return hex
	end
	local clean = hex:gsub("#", "")
	local r = tonumber(string.sub(clean, 1, 2), 16) or 157
	local g = tonumber(string.sub(clean, 3, 4), 16) or 78
	local b = tonumber(string.sub(clean, 5, 6), 16) or 221
	return Color3.fromRGB(r, g, b)
end

return Theme

end

__moduleSources["UI/Components/Widgets"] = function(...)
--[[
	Widgets.luau
	Reusable Roblox UI component builders with safe headless fallback for tests.
]]

local Widgets = {}

function Widgets.isRobloxGuiAvailable(): boolean
	return type(Instance) == "table" or type(Instance) == "userdata"
end

function Widgets.clearChildren(container: any)
	if not container then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UILayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

function Widgets.createRoundedFrame(parent: any, props: {
	name: string?,
	size: any?,
	position: any?,
	bgColor: any?,
	borderColor: any?,
	cornerRadius: number?,
	padding: number?,
}): any
	if not Widgets.isRobloxGuiAvailable() then
		return nil
	end
	local frame = Instance.new("Frame")
	frame.Name = props.name or "Card"
	frame.Size = props.size or UDim2.new(1, 0, 0, 100)
	frame.Position = props.position or UDim2.new(0, 0, 0, 0)
	frame.BackgroundColor3 = props.bgColor
	frame.BorderSizePixel = 0
	if parent then
		frame.Parent = parent
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, props.cornerRadius or 10)
	corner.Parent = frame

	if props.borderColor then
		local stroke = Instance.new("UIStroke")
		stroke.Color = props.borderColor
		stroke.Thickness = 1
		stroke.Parent = frame
	end

	if props.padding and props.padding > 0 then
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, props.padding)
		pad.PaddingBottom = UDim.new(0, props.padding)
		pad.PaddingLeft = UDim.new(0, props.padding)
		pad.PaddingRight = UDim.new(0, props.padding)
		pad.Parent = frame
	end

	return frame
end

function Widgets.createScrollFrame(parent: any, props: {
	name: string?,
	size: any?,
	position: any?,
	bgColor: any?,
	gap: number?,
}): any
	if not Widgets.isRobloxGuiAvailable() then
		return nil
	end
	local sf = Instance.new("ScrollingFrame")
	sf.Name = props.name or "Scroll"
	sf.Size = props.size or UDim2.new(1, 0, 1, 0)
	sf.Position = props.position or UDim2.new(0, 0, 0, 0)
	if props.bgColor then
		sf.BackgroundColor3 = props.bgColor
		sf.BackgroundTransparency = 0
	else
		sf.BackgroundTransparency = 1
	end
	sf.BorderSizePixel = 0
	sf.ScrollBarThickness = 5
	sf.CanvasSize = UDim2.new(0, 0, 0, 0)
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	if parent then
		sf.Parent = parent
	end

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, props.gap or 8)
	layout.Parent = sf

	return sf
end

function Widgets.createButton(parent: any, props: {
	name: string?,
	text: string,
	size: any?,
	position: any?,
	bgColor: any?,
	textColor: any?,
	textSize: number?,
	onClick: () -> (),
}): any
	if not Widgets.isRobloxGuiAvailable() then
		return {
			Name = props.name or "Button",
			Text = props.text,
			trigger = props.onClick,
		}
	end
	local btn = Instance.new("TextButton")
	btn.Name = props.name or "Button"
	btn.Text = props.text
	btn.Size = props.size or UDim2.new(0, 130, 0, 32)
	btn.Position = props.position or UDim2.new(0, 0, 0, 0)
	btn.BackgroundColor3 = props.bgColor
	btn.TextColor3 = props.textColor
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamSemibold
	btn.TextSize = props.textSize or 13
	btn.BorderSizePixel = 0
	if parent then
		btn.Parent = parent
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn

	btn.MouseButton1Click:Connect(props.onClick)
	return btn
end

function Widgets.createTextBox(parent: any, props: {
	name: string?,
	text: string?,
	placeholder: string?,
	size: any?,
	position: any?,
	bgColor: any?,
	textColor: any?,
	placeholderColor: any?,
	borderColor: any?,
	onFocusLost: ((string, boolean) -> ())?,
}): any
	if not Widgets.isRobloxGuiAvailable() then
		return { Text = props.text or "" }
	end
	local tb = Instance.new("TextBox")
	tb.Name = props.name or "Input"
	tb.Text = props.text or ""
	tb.PlaceholderText = props.placeholder or ""
	tb.Size = props.size or UDim2.new(0, 200, 0, 32)
	tb.Position = props.position or UDim2.new(0, 0, 0, 0)
	tb.BackgroundColor3 = props.bgColor
	tb.TextColor3 = props.textColor
	if props.placeholderColor then
		tb.PlaceholderColor3 = props.placeholderColor
	end
	tb.Font = Enum.Font.Gotham
	tb.TextSize = 13
	tb.TextXAlignment = Enum.TextXAlignment.Left
	tb.ClearTextOnFocus = false
	tb.BorderSizePixel = 0
	if parent then
		tb.Parent = parent
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = tb

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = tb

	if props.borderColor then
		local stroke = Instance.new("UIStroke")
		stroke.Color = props.borderColor
		stroke.Thickness = 1
		stroke.Parent = tb
	end

	if props.onFocusLost then
		tb.FocusLost:Connect(function(enterPressed)
			props.onFocusLost(tb.Text, enterPressed)
		end)
	end
	return tb
end

function Widgets.createLabel(parent: any, props: {
	text: string,
	size: any?,
	position: any?,
	textColor: any?,
	textSize: number?,
	bold: boolean?,
	xAlign: any?,
}): any
	if not Widgets.isRobloxGuiAvailable() then
		return nil
	end
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Text = props.text
	lbl.Size = props.size or UDim2.new(1, 0, 0, 22)
	lbl.Position = props.position or UDim2.new(0, 0, 0, 0)
	lbl.TextColor3 = props.textColor
	lbl.TextSize = props.textSize or 14
	lbl.Font = if props.bold then Enum.Font.GothamBold else Enum.Font.Gotham
	lbl.TextXAlignment = props.xAlign or Enum.TextXAlignment.Left
	lbl.TextWrapped = true
	if parent then
		lbl.Parent = parent
	end
	return lbl
end

function Widgets.createStatCard(parent: any, props: {
	title: string,
	value: string,
	subtitle: string?,
	size: any?,
	position: any?,
	bgColor: any?,
	borderColor: any?,
	titleColor: any?,
	valueColor: any?,
}): any
	if not Widgets.isRobloxGuiAvailable() then
		return nil
	end
	local card = Widgets.createRoundedFrame(parent, {
		name = "Stat_" .. props.title,
		size = props.size or UDim2.new(0.24, -6, 0, 68),
		position = props.position,
		bgColor = props.bgColor,
		borderColor = props.borderColor,
		cornerRadius = 8,
		padding = 8,
	})
	Widgets.createLabel(card, {
		text = props.title,
		size = UDim2.new(1, 0, 0, 16),
		textColor = props.titleColor,
		textSize = 11,
	})
	Widgets.createLabel(card, {
		text = props.value,
		position = UDim2.new(0, 0, 0, 18),
		size = UDim2.new(1, 0, 0, 22),
		textColor = props.valueColor,
		textSize = 16,
		bold = true,
	})
	if props.subtitle then
		Widgets.createLabel(card, {
			text = props.subtitle,
			position = UDim2.new(0, 0, 0, 40),
			size = UDim2.new(1, 0, 0, 14),
			textColor = props.titleColor,
			textSize = 10,
		})
	end
	return card
end

function Widgets.makeDraggable(targetFrame: any, handle: any): { any }
	if not Widgets.isRobloxGuiAvailable() then
		return {}
	end
	local conns = {}
	local dragging = false
	local dragStart: any = nil
	local startPos: any = nil

	table.insert(conns, handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = targetFrame.Position
		end
	end))

	table.insert(conns, handle.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	local okUis, UserInputService = pcall(function()
		return game:GetService("UserInputService")
	end)
	if okUis and UserInputService then
		table.insert(conns, UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - dragStart
				targetFrame.Position = UDim2.new(
					startPos.X.Scale,
					startPos.X.Offset + delta.X,
					startPos.Y.Scale,
					startPos.Y.Offset + delta.Y
				)
			end
		end))
	end

	return conns
end

return Widgets

end

__moduleSources["UI/Notifications"] = function(...)
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

end

__moduleSources["UI/Dashboard"] = function(...)
--[[
	Dashboard.luau
	Overview page: inventory value, best pet, AMVGG status + refresh,
	scanned listings, good deals, pending offers, confirmed profit, quick pet lookup,
	and Kiria companion card.
]]

local Dashboard = {}
Dashboard.__index = Dashboard

function Dashboard.new(deps: {
	amvggProvider: any,
	inventoryValuator: any,
	listingScanner: any,
	offerQueue: any,
	tradeHistory: any,
	kiria: any,
	autoLoop: any?,
})
	local self = setmetatable({}, Dashboard)
	self._amvgg = deps.amvggProvider
	self._invValuator = deps.inventoryValuator
	self._scanner = deps.listingScanner
	self._offerQueue = deps.offerQueue
	self._history = deps.tradeHistory
	self._kiria = deps.kiria
	self._autoLoop = deps.autoLoop
	self._lookupQuery = "Shadow Dragon"
	return self
end

function Dashboard:getViewModel(): { [string]: any }
	local inv = self._invValuator:evaluateAll({})
	local amvggStatus = self._amvgg:getStatus()
	local scanStats = self._scanner:getStats()
	local pendingCount = self._offerQueue:getPendingCount()

	local pendingProfit = 0
	for _, off in ipairs(self._offerQueue:getAll()) do
		if off.status == "PENDING" then
			pendingProfit += (off.profitValue or 0)
		end
	end

	local summary = self._history:getSummary({
		pendingProfit = pendingProfit,
		inventoryValue = inv.totalValue,
	})
	local kiriaStatus = self._kiria:getStatus()

	return {
		inventoryValue = inv.totalValue,
		bestPet = inv.topPet,
		amvgg = amvggStatus,
		scannedListings = scanStats.inspectedCount,
		goodDeals = scanStats.goodDeals,
		pendingOffers = pendingCount,
		confirmedProfit = summary.confirmedProfit,
		pendingProfit = pendingProfit,
		kiria = kiriaStatus,
	}
end

function Dashboard:refreshAmvgg(): (boolean, string?)
	return self._amvgg:refresh({ force = true })
end

function Dashboard:render(container: any, theme: any, widgets: any, navigateFn: ((string) -> ())?)
	if not (container and widgets and widgets.isRobloxGuiAvailable()) then
		return
	end
	widgets.clearChildren(container)
	local vm = self:getViewModel()
	local cText = theme.toColor3(theme.Colors.TextPrimary)
	local cMuted = theme.toColor3(theme.Colors.TextMuted)
	local cCard = theme.toColor3(theme.Colors.SurfaceAlt)
	local cBorder = theme.toColor3(theme.Colors.Border)
	local cProfit = theme.toColor3(theme.Colors.Profit)
	local cAccent = theme.toColor3(theme.Colors.Accent)
	local cBright = theme.toColor3(theme.Colors.AccentBright)

	widgets.createLabel(container, {
		text = "Dashboard Overview",
		size = UDim2.new(1, -430, 0, 24),
		textColor = cText,
		textSize = 18,
		bold = true,
	})

	if self._autoLoop then
		local isAuto = self._autoLoop.getEnabled()
		widgets.createButton(container, {
			text = "Auto-Trade All",
			size = UDim2.new(0, 140, 0, 30),
			position = UDim2.new(1, -420, 0, 0),
			bgColor = cProfit,
			textColor = cText,
			onClick = function()
				self._autoLoop.runNow()
				self:render(container, theme, widgets, navigateFn)
			end,
		})
		widgets.createButton(container, {
			text = if isAuto then "Auto: ON" else "Auto: OFF",
			size = UDim2.new(0, 110, 0, 30),
			position = UDim2.new(1, -270, 0, 0),
			bgColor = if isAuto then cAccent else cCard,
			textColor = cText,
			onClick = function()
				self._autoLoop.setEnabled(not isAuto)
				self:render(container, theme, widgets, navigateFn)
			end,
		})
	end

	widgets.createButton(container, {
		text = "Refresh AMVGG",
		size = UDim2.new(0, 140, 0, 30),
		position = UDim2.new(1, -140, 0, 0),
		bgColor = cAccent,
		textColor = cText,
		onClick = function()
			self:refreshAmvgg()
		end,
	})

	-- Row 1 of Stat Cards
	local bestName = if vm.bestPet then vm.bestPet.pet.name else "None"
	local bestVal = if vm.bestPet then string.format("%.2f", vm.bestPet.value) else "0.00"

	widgets.createStatCard(container, {
		title = "INVENTORY VALUE",
		value = string.format("%.2f", vm.inventoryValue),
		subtitle = "AMVGG Total",
		position = UDim2.new(0, 0, 0, 40),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cText,
	})
	widgets.createStatCard(container, {
		title = "TOP PET",
		value = bestName,
		subtitle = bestVal .. " AMVGG",
		position = UDim2.new(0.25, 4, 0, 40),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cBright,
	})
	widgets.createStatCard(container, {
		title = "AMVGG FEED",
		value = string.format("%s (%d)", vm.amvgg.status, vm.amvgg.petCount),
		subtitle = if vm.amvgg.isStale then "Cached Fallback" else "amvgg.com/values/pets",
		position = UDim2.new(0.50, 8, 0, 40),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted,
		valueColor = if vm.amvgg.status == "LIVE" then cProfit else theme.toColor3(theme.Colors.Warning),
	})
	widgets.createStatCard(container, {
		title = "CONFIRMED PROFIT",
		value = string.format("%+.2f", vm.confirmedProfit),
		subtitle = string.format("Pending: %+.2f", vm.pendingProfit),
		position = UDim2.new(0.75, 12, 0, 40),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cProfit,
	})

	-- Row 2 of Stat Cards
	widgets.createStatCard(container, {
		title = "SCANNED LISTINGS",
		value = tostring(vm.scannedListings),
		subtitle = "Hub & Imported",
		position = UDim2.new(0, 0, 0, 118),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cText,
	})
	widgets.createStatCard(container, {
		title = "GOOD DEALS",
		value = tostring(vm.goodDeals),
		subtitle = "Ranked Opportunities",
		position = UDim2.new(0.25, 4, 0, 118),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cProfit,
	})
	widgets.createStatCard(container, {
		title = "PENDING OFFERS",
		value = tostring(vm.pendingOffers),
		subtitle = "Awaiting Response",
		position = UDim2.new(0.50, 8, 0, 118),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cText,
	})
	widgets.createStatCard(container, {
		title = "KIRIA RANK",
		value = vm.kiria.rank,
		subtitle = string.format("%d XP • %s", vm.kiria.xp, vm.kiria.mood),
		position = UDim2.new(0.75, 12, 0, 118),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cBright,
	})

	-- Quick AMVGG Pet Lookup Card
	local lookupCard = widgets.createRoundedFrame(container, {
		name = "QuickLookup",
		size = UDim2.new(1, 0, 0, 110),
		position = UDim2.new(0, 0, 0, 198),
		bgColor = cCard,
		borderColor = cBorder,
		cornerRadius = 8,
		padding = 10,
	})
	widgets.createLabel(lookupCard, {
		text = "Quick AMVGG Pet Value Lookup",
		size = UDim2.new(0.5, 0, 0, 20),
		textColor = cText,
		bold = true,
	})
	widgets.createTextBox(lookupCard, {
		text = self._lookupQuery,
		placeholder = "Type pet name (e.g. Shadow Dragon)...",
		size = UDim2.new(0, 240, 0, 30),
		position = UDim2.new(0, 0, 0, 26),
		bgColor = theme.toColor3(theme.Colors.Background),
		textColor = cText,
		placeholderColor = cMuted,
		borderColor = cBorder,
		onFocusLost = function(txt)
			self._lookupQuery = txt
			self:render(container, theme, widgets, navigateFn)
		end,
	})

	local petRec = self._invValuator._valueEngine._cache:getPet(self._lookupQuery)
	local lookupText = if petRec
		then string.format(
			"%s  |  FR: %s  |  No-Pot: %s  |  NFR: %s  |  MFR: %s  |  Demand: %s",
			petRec.name,
			tostring(petRec.values.regular or "-"),
			tostring(petRec.values.npRegular or "-"),
			tostring(petRec.values.neon or "-"),
			tostring(petRec.values.mega or "-"),
			tostring(petRec.demands.regular or "N/A")
		)
		else "Pet not found in AMVGG dataset (press Enter after typing)."
	widgets.createLabel(lookupCard, {
		text = lookupText,
		position = UDim2.new(0, 0, 0, 64),
		size = UDim2.new(1, 0, 0, 24),
		textColor = if petRec then cProfit else cMuted,
		textSize = 13,
	})

	-- Kiria Companion Card
	local kiriaCard = widgets.createRoundedFrame(container, {
		name = "KiriaCard",
		size = UDim2.new(1, 0, 0, 130),
		position = UDim2.new(0, 0, 0, 320),
		bgColor = cCard,
		borderColor = cAccent,
		cornerRadius = 8,
		padding = 12,
	})
	widgets.createLabel(kiriaCard, {
		text = string.format("Kiria Companion  •  %s (%s)", vm.kiria.rank, vm.kiria.mood),
		size = UDim2.new(1, 0, 0, 20),
		textColor = cBright,
		bold = true,
	})
	widgets.createLabel(kiriaCard, {
		text = vm.kiria.latestMessage or "Ready at the Trade Hub terminal.",
		position = UDim2.new(0, 0, 0, 28),
		size = UDim2.new(1, 0, 0, 74),
		textColor = cText,
		textSize = 13,
	})
end

return Dashboard

end

__moduleSources["UI/ListingsPage"] = function(...)
--[[
	ListingsPage.luau
	Trade Hub Listing Scanner + Smart Listing Management UI controller.
]]

local ListingsPage = {}
ListingsPage.__index = ListingsPage

function ListingsPage.new(deps: { listingScanner: any, listingManager: any, inventoryReader: any })
	local self = setmetatable({}, ListingsPage)
	self._scanner = deps.listingScanner
	self._manager = deps.listingManager
	self._inventory = deps.inventoryReader
	self._filters = { petQuery = "", minProfit = 0, minPctGain = 0, includeIncomplete = false }
	self._manualOfferName = ""
	self._manualAskName = ""
	self._statusMsg = ""
	return self
end

function ListingsPage:setFilters(filters: { [string]: any })
	for k, v in pairs(filters) do
		self._filters[k] = v
	end
end

function ListingsPage:scanNow()
	return self._scanner:scanOnce()
end

function ListingsPage:importListingsJson(jsonText: string)
	return self._scanner:importJson(jsonText)
end

function ListingsPage:getScannedListings()
	return self._scanner:getRankedOpportunities(self._filters)
end

function ListingsPage:createAndPublishDraft(offeredItems: { any }, requestedItems: { any }?, ttlSeconds: number?)
	local draft = self._manager:createDraft(offeredItems, requestedItems, ttlSeconds)
	local ok, err = self._manager:publishListing(draft.id)
	return draft, ok, err
end

function ListingsPage:cancelListing(id: string, confirmed: boolean)
	return self._manager:cancelListing(id, confirmed)
end

function ListingsPage:getManagedListings()
	return self._manager:getAll()
end

function ListingsPage:render(container: any, theme: any, widgets: any)
	if not (container and widgets and widgets.isRobloxGuiAvailable()) then
		return
	end
	widgets.clearChildren(container)
	local opps = self:getScannedListings()
	local managed = self._manager:getAll()
	local cText = theme.toColor3(theme.Colors.TextPrimary)
	local cMuted = theme.toColor3(theme.Colors.TextMuted)
	local cCard = theme.toColor3(theme.Colors.SurfaceAlt)
	local cBorder = theme.toColor3(theme.Colors.Border)
	local cAccent = theme.toColor3(theme.Colors.Accent)
	local cProfit = theme.toColor3(theme.Colors.Profit)
	local cWarn = theme.toColor3(theme.Colors.Warning)

	widgets.createLabel(container, {
		text = string.format("Listings Scanner (%d opportunities) & My Listings (%d)", #opps, #managed),
		size = UDim2.new(1, -130, 0, 22),
		textColor = cText,
		textSize = 15,
		bold = true,
	})

	widgets.createButton(container, {
		text = "Scan Hub Now",
		size = UDim2.new(0, 120, 0, 28),
		position = UDim2.new(1, -120, 0, 0),
		bgColor = cAccent,
		textColor = cText,
		onClick = function()
			local res = self:scanNow()
			self._statusMsg = res.warning or string.format("Scanned %d listings (%d good deals)", res.total, res.goodDeals)
			self:render(container, theme, widgets)
		end,
	})

	-- Manual Listing Ingestion Bar (evaluate any Hub listing manually)
	widgets.createTextBox(container, {
		text = self._manualOfferName,
		placeholder = "They offer (e.g. Frost Dragon)",
		size = UDim2.new(0, 200, 0, 28),
		position = UDim2.new(0, 0, 0, 34),
		bgColor = theme.toColor3(theme.Colors.Background),
		textColor = cText,
		placeholderColor = cMuted,
		borderColor = cBorder,
		onFocusLost = function(txt) self._manualOfferName = txt end,
	})
	widgets.createTextBox(container, {
		text = self._manualAskName,
		placeholder = "They ask (e.g. Shadow Dragon)",
		size = UDim2.new(0, 200, 0, 28),
		position = UDim2.new(0, 208, 0, 34),
		bgColor = theme.toColor3(theme.Colors.Background),
		textColor = cText,
		placeholderColor = cMuted,
		borderColor = cBorder,
		onFocusLost = function(txt) self._manualAskName = txt end,
	})
	widgets.createButton(container, {
		text = "+ Evaluate Listing",
		size = UDim2.new(0, 130, 0, 28),
		position = UDim2.new(0, 416, 0, 34),
		bgColor = cProfit,
		textColor = cText,
		onClick = function()
			if self._manualOfferName ~= "" and self._manualAskName ~= "" then
				self._scanner:ingestListing({
					offeredItems = { { name = self._manualOfferName, fly = true, ride = true } },
					requestedItems = { { name = self._manualAskName, fly = true, ride = true } },
				}, "manual")
				self._statusMsg = "Evaluated manual listing"
				self:render(container, theme, widgets)
			end
		end,
	})

	if self._statusMsg ~= "" then
		widgets.createLabel(container, {
			text = self._statusMsg,
			position = UDim2.new(0, 0, 0, 68),
			size = UDim2.new(1, 0, 0, 18),
			textColor = cWarn,
			textSize = 11,
		})
	end

	local scroll = widgets.createScrollFrame(container, {
		size = UDim2.new(1, 0, 1, -94),
		position = UDim2.new(0, 0, 0, 90),
		gap = 6,
	})

	if #opps == 0 then
		widgets.createLabel(scroll, {
			text = "No listings scanned yet. Click 'Scan Hub Now' or enter a listing above to evaluate AMVGG profit.",
			textColor = cMuted,
		})
	else
		for _, item in ipairs(opps) do
			local card = widgets.createRoundedFrame(scroll, {
				size = UDim2.new(1, -8, 0, 56),
				bgColor = cCard,
				borderColor = if item.listingStatus == "GOOD DEAL" then cProfit else cBorder,
				cornerRadius = 6,
				padding = 8,
			})
			local offName = item.offeredItems[1] and item.offeredItems[1].name or "?"
			local reqName = item.requestedItems[1] and item.requestedItems[1].name or "?"
			widgets.createLabel(card, {
				text = string.format("[%s]  Get: %s (%.2f)  |  Give: %s (%.2f)  |  %+.2f (%+.1f%%)",
					item.listingStatus, offName, item.totalAmvggOffered, reqName, item.totalAmvggRequested, item.estimatedProfit, item.profitPercent),
				size = UDim2.new(1, 0, 0, 20),
				textColor = if item.estimatedProfit >= 0 then cProfit else theme.toColor3(theme.Colors.Loss),
				textSize = 12,
				bold = true,
			})
			widgets.createLabel(card, {
				text = string.format("Risk: %d/100  •  %s", item.riskScore, item.liquidityNote),
				position = UDim2.new(0, 0, 0, 22),
				size = UDim2.new(1, 0, 0, 18),
				textColor = cMuted,
				textSize = 11,
			})
		end
	end
end

return ListingsPage

end

__moduleSources["UI/OffersPage"] = function(...)
--[[
	OffersPage.luau
	Offer Engine candidate generator + Offer Queue management with mandatory
	user confirmation for final trade acceptance.
]]

local OffersPage = {}
OffersPage.__index = OffersPage

function OffersPage.new(deps: { offerAnalyzer: any, offerQueue: any, tradeHistory: any })
	local self = setmetatable({}, OffersPage)
	self._analyzer = deps.offerAnalyzer
	self._queue = deps.offerQueue
	self._history = deps.tradeHistory
	self._lastCandidates = {} :: { any }
	self._targetPetName = "Frost Dragon"
	self._statusMsg = ""
	return self
end

function OffersPage:generateForTarget(targetItems: { any }, options: { [string]: any }?)
	local reserved = self._queue:getReservedPetUids()
	local opts = if options then table.clone(options) else {}
	opts.reservedUids = reserved
	local res = self._analyzer:generateCandidates(targetItems, opts)
	self._lastCandidates = res.candidates
	return res
end

function OffersPage:queueCandidate(candidate: any, listingId: string?)
	local rec, err = self._queue:enqueue({
		listingId = listingId,
		direction = "OUTGOING",
		offeredItems = candidate.offeredPets,
		requestedItems = candidate.targetItems,
	})
	if rec then
		self._history:recordOfferOutcome("SUBMITTED")
	end
	return rec, err
end

function OffersPage:confirmAcceptOffer(offerId: string, userConfirmed: boolean): (boolean, string?)
	local ok, err = self._queue:updateStatus(offerId, "ACCEPTED", { userConfirmed = userConfirmed })
	if not ok then
		return false, err
	end
	for _, off in ipairs(self._queue:getAll()) do
		if off.offerId == offerId then
			self._history:recordConfirmedTrade({
				id = off.offerId,
				offeredItems = off.offeredItems,
				receivedItems = off.requestedItems,
				offeredValue = off.evaluation.yourValue,
				receivedValue = off.evaluation.theirValue,
				source = "manual_confirmed",
			})
			break
		end
	end
	return true, nil
end

function OffersPage:declineOffer(offerId: string)
	local ok, err = self._queue:updateStatus(offerId, "DECLINED")
	if ok then
		self._history:recordOfferOutcome("DECLINED")
	end
	return ok, err
end

function OffersPage:cancelOffer(offerId: string)
	local ok, err = self._queue:updateStatus(offerId, "CANCELLED")
	if ok then
		self._history:recordOfferOutcome("CANCELLED")
	end
	return ok, err
end

function OffersPage:getOffers()
	return self._queue:getAll()
end

function OffersPage:render(container: any, theme: any, widgets: any)
	if not (container and widgets and widgets.isRobloxGuiAvailable()) then
		return
	end
	widgets.clearChildren(container)
	local cText = theme.toColor3(theme.Colors.TextPrimary)
	local cMuted = theme.toColor3(theme.Colors.TextMuted)
	local cCard = theme.toColor3(theme.Colors.SurfaceAlt)
	local cBorder = theme.toColor3(theme.Colors.Border)
	local cAccent = theme.toColor3(theme.Colors.Accent)
	local cProfit = theme.toColor3(theme.Colors.Profit)
	local cLoss = theme.toColor3(theme.Colors.Loss)

	widgets.createLabel(container, {
		text = string.format("Offers Engine & Queue (%d pending  |  %d candidates)", self._queue:getPendingCount(), #self._lastCandidates),
		size = UDim2.new(1, 0, 0, 22),
		textColor = cText,
		textSize = 15,
		bold = true,
	})

	widgets.createTextBox(container, {
		text = self._targetPetName,
		placeholder = "Target pet (e.g. Frost Dragon)...",
		size = UDim2.new(0, 220, 0, 30),
		position = UDim2.new(0, 0, 0, 32),
		bgColor = theme.toColor3(theme.Colors.Background),
		textColor = cText,
		placeholderColor = cMuted,
		borderColor = cBorder,
		onFocusLost = function(txt) self._targetPetName = txt end,
	})

	widgets.createButton(container, {
		text = "Generate Offers",
		size = UDim2.new(0, 140, 0, 30),
		position = UDim2.new(0, 228, 0, 32),
		bgColor = cAccent,
		textColor = cText,
		onClick = function()
			local res = self:generateForTarget({ { name = self._targetPetName, fly = true, ride = true } })
			self._statusMsg = res.reason or string.format("Generated %d profit-positive candidates", #res.candidates)
			self:render(container, theme, widgets)
		end,
	})

	if self._statusMsg ~= "" then
		widgets.createLabel(container, {
			text = self._statusMsg,
			position = UDim2.new(0, 378, 0, 36),
			size = UDim2.new(1, -378, 0, 22),
			textColor = cMuted,
			textSize = 11,
		})
	end

	local scroll = widgets.createScrollFrame(container, {
		size = UDim2.new(1, 0, 1, -74),
		position = UDim2.new(0, 0, 0, 70),
		gap = 6,
	})

	for idx, cand in ipairs(self._lastCandidates) do
		local row = widgets.createRoundedFrame(scroll, {
			size = UDim2.new(1, -8, 0, 50),
			bgColor = cCard,
			borderColor = cAccent,
			cornerRadius = 6,
			padding = 8,
		})
		local names = {}
		for _, p in ipairs(cand.offeredPets) do
			table.insert(names, p.name)
		end
		widgets.createLabel(row, {
			text = string.format("Candidate #%d: Offer %s (%.2f) -> %.2f  |  %+.2f (%+.1f%%)",
				idx, table.concat(names, " + "), cand.offeredValue, cand.targetValue, cand.profitValue, cand.profitPercent),
			size = UDim2.new(1, -110, 0, 32),
			textColor = cProfit,
			textSize = 12,
		})
		widgets.createButton(row, {
			text = "Queue Offer",
			size = UDim2.new(0, 100, 0, 28),
			position = UDim2.new(1, -100, 0, 2),
			bgColor = cAccent,
			textColor = cText,
			onClick = function()
				local _, err = self:queueCandidate(cand)
				self._statusMsg = err or "Offer queued for confirmation"
				self:render(container, theme, widgets)
			end,
		})
	end

	local offers = self._queue:getAll()
	if #offers == 0 and #self._lastCandidates == 0 then
		widgets.createLabel(scroll, {
			text = "No queued offers yet. Add pets in Inventory, then enter a target pet above and click 'Generate Offers'.",
			textColor = cMuted,
		})
		return
	end

	for _, off in ipairs(offers) do
		local row = widgets.createRoundedFrame(scroll, {
			size = UDim2.new(1, -8, 0, 48),
			bgColor = cCard,
			borderColor = cBorder,
			cornerRadius = 6,
			padding = 8,
		})
		widgets.createLabel(row, {
			text = string.format("[%s] %s  |  Profit: %+.2f (%+.1f%%)",
				off.status, off.offerId, off.profitValue, off.profitPercent),
			size = UDim2.new(1, -220, 0, 28),
			textColor = cText,
			textSize = 12,
		})
		if off.status == "PENDING" then
			widgets.createButton(row, {
				text = "Confirm",
				size = UDim2.new(0, 72, 0, 26),
				position = UDim2.new(1, -214, 0, 2),
				bgColor = cProfit,
				textColor = cText,
				onClick = function()
					self:confirmAcceptOffer(off.offerId, true)
					self:render(container, theme, widgets)
				end,
			})
			widgets.createButton(row, {
				text = "Decline",
				size = UDim2.new(0, 68, 0, 26),
				position = UDim2.new(1, -138, 0, 2),
				bgColor = cLoss,
				textColor = cText,
				onClick = function()
					self:declineOffer(off.offerId)
					self:render(container, theme, widgets)
				end,
			})
			widgets.createButton(row, {
				text = "Cancel",
				size = UDim2.new(0, 64, 0, 26),
				position = UDim2.new(1, -66, 0, 2),
				bgColor = theme.toColor3(theme.Colors.Background),
				textColor = cText,
				onClick = function()
					self:cancelOffer(off.offerId)
					self:render(container, theme, widgets)
				end,
			})
		end
	end
end

return OffersPage

end

__moduleSources["UI/InventoryPage"] = function(...)
--[[
	InventoryPage.luau
	Inventory search, filtering, AMVGG valuation sorting, top pet highlight,
	manual pet editor, JSON import/export, and game sync.
]]

local InventoryPage = {}
InventoryPage.__index = InventoryPage

function InventoryPage.new(deps: { inventoryReader: any, inventoryValuator: any })
	local self = setmetatable({}, InventoryPage)
	self._reader = deps.inventoryReader
	self._valuator = deps.inventoryValuator
	self._filter = {
		query = "",
		neonOnly = false,
		megaOnly = false,
		flyOnly = false,
		rideOnly = false,
		tradeableOnly = false,
		sortDescending = true,
	}
	self._draftName = ""
	self._draftN = false
	self._draftM = false
	self._draftF = true
	self._draftR = true
	self._statusMsg = ""
	return self
end

function InventoryPage:setFilter(patch: { [string]: any })
	for k, v in pairs(patch) do
		self._filter[k] = v
	end
end

function InventoryPage:getViewModel()
	return self._valuator:evaluateAll(self._filter)
end

function InventoryPage:addPet(petData: { [string]: any })
	return self._reader:addPet(petData)
end

function InventoryPage:toggleSelectForListing(uid: string, selected: boolean): boolean
	return self._reader:updatePet(uid, { selectedForListing = selected })
end

function InventoryPage:toggleLock(uid: string, locked: boolean): boolean
	return self._reader:updatePet(uid, { locked = locked })
end

function InventoryPage:removePet(uid: string): boolean
	return self._reader:removePet(uid)
end

function InventoryPage:importJson(jsonText: string, replace: boolean?)
	return self._reader:importJson(jsonText, replace)
end

function InventoryPage:exportJson(): string?
	return self._reader:exportJson()
end

function InventoryPage:syncFromGame()
	return self._reader:syncFromGame()
end

function InventoryPage:render(container: any, theme: any, widgets: any)
	if not (container and widgets and widgets.isRobloxGuiAvailable()) then
		return
	end
	widgets.clearChildren(container)
	local vm = self:getViewModel()
	local cText = theme.toColor3(theme.Colors.TextPrimary)
	local cMuted = theme.toColor3(theme.Colors.TextMuted)
	local cCard = theme.toColor3(theme.Colors.SurfaceAlt)
	local cBorder = theme.toColor3(theme.Colors.Border)
	local cAccent = theme.toColor3(theme.Colors.Accent)
	local cProfit = theme.toColor3(theme.Colors.Profit)
	local cLoss = theme.toColor3(theme.Colors.Loss)

	local topName = if vm.topPet then vm.topPet.pet.name else "None"
	local topVal = if vm.topPet then vm.topPet.value else 0
	widgets.createLabel(container, {
		text = string.format("Inventory (%d pets)  |  Total AMVGG: %.2f  |  Top: %s (%.2f)", vm.totalCount, vm.totalValue, topName, topVal),
		size = UDim2.new(1, -120, 0, 22),
		textColor = cText,
		textSize = 15,
		bold = true,
	})

	widgets.createButton(container, {
		text = "Sync Game",
		size = UDim2.new(0, 110, 0, 28),
		position = UDim2.new(1, -110, 0, 0),
		bgColor = cCard,
		textColor = cText,
		onClick = function()
			local _, err = self:syncFromGame()
			self._statusMsg = err or "Synced from game"
			self:render(container, theme, widgets)
		end,
	})

	-- Manual Add Pet Bar
	widgets.createTextBox(container, {
		text = self._draftName,
		placeholder = "Add pet name (e.g. Frost Dragon)...",
		size = UDim2.new(0, 220, 0, 30),
		position = UDim2.new(0, 0, 0, 34),
		bgColor = theme.toColor3(theme.Colors.Background),
		textColor = cText,
		placeholderColor = cMuted,
		borderColor = cBorder,
		onFocusLost = function(txt)
			self._draftName = txt
		end,
	})

	local function flagBtn(label: string, active: boolean, x: number, toggleFn: () -> ())
		widgets.createButton(container, {
			text = label,
			size = UDim2.new(0, 34, 0, 30),
			position = UDim2.new(0, x, 0, 34),
			bgColor = if active then cAccent else cCard,
			textColor = cText,
			onClick = function()
				toggleFn()
				self:render(container, theme, widgets)
			end,
		})
	end
	flagBtn("N", self._draftN, 226, function() self._draftN = not self._draftN end)
	flagBtn("M", self._draftM, 264, function() self._draftM = not self._draftM end)
	flagBtn("F", self._draftF, 302, function() self._draftF = not self._draftF end)
	flagBtn("R", self._draftR, 340, function() self._draftR = not self._draftR end)

	widgets.createButton(container, {
		text = "+ Add Pet",
		size = UDim2.new(0, 96, 0, 30),
		position = UDim2.new(0, 382, 0, 34),
		bgColor = cProfit,
		textColor = cText,
		onClick = function()
			if self._draftName ~= "" then
				self:addPet({
					name = self._draftName,
					neon = self._draftN,
					mega = self._draftM,
					fly = self._draftF,
					ride = self._draftR,
				})
				self._draftName = ""
				self._statusMsg = "Added pet to inventory"
				self:render(container, theme, widgets)
			end
		end,
	})

	-- Search & Status
	widgets.createTextBox(container, {
		text = self._filter.query,
		placeholder = "Search inventory...",
		size = UDim2.new(0, 220, 0, 28),
		position = UDim2.new(0, 0, 0, 72),
		bgColor = theme.toColor3(theme.Colors.Background),
		textColor = cText,
		placeholderColor = cMuted,
		borderColor = cBorder,
		onFocusLost = function(txt)
			self:setFilter({ query = txt })
			self:render(container, theme, widgets)
		end,
	})

	if self._statusMsg ~= "" then
		widgets.createLabel(container, {
			text = self._statusMsg,
			position = UDim2.new(0, 230, 0, 75),
			size = UDim2.new(1, -230, 0, 22),
			textColor = cMuted,
			textSize = 11,
		})
	end

	local scroll = widgets.createScrollFrame(container, {
		size = UDim2.new(1, 0, 1, -110),
		position = UDim2.new(0, 0, 0, 108),
		gap = 6,
	})

	if #vm.items == 0 then
		widgets.createLabel(scroll, {
			text = "Inventory is empty. Add pets above using their AMVGG name (e.g. Shadow Dragon, Turtle, Cow).",
			textColor = cMuted,
		})
		return
	end

	for _, entry in ipairs(vm.items) do
		local pet = entry.pet
		local ev = entry.evaluation
		local row = widgets.createRoundedFrame(scroll, {
			size = UDim2.new(1, -8, 0, 42),
			bgColor = cCard,
			borderColor = if pet.locked then theme.toColor3(theme.Colors.Warning) else cBorder,
			cornerRadius = 6,
			padding = 8,
		})
		local valStr = if ev.complete then string.format("%.2f", entry.value) else "INCOMPLETE"
		widgets.createLabel(row, {
			text = string.format("%s [%s]  •  %s AMVGG%s", pet.name, ev.variantLabel, valStr, if pet.locked then "  (LOCKED)" else ""),
			size = UDim2.new(1, -150, 0, 24),
			textColor = if ev.complete then cText else theme.toColor3(theme.Colors.Warning),
			textSize = 13,
		})
		widgets.createButton(row, {
			text = if pet.locked then "Unlock" else "Lock",
			size = UDim2.new(0, 64, 0, 26),
			position = UDim2.new(1, -138, 0, 0),
			bgColor = theme.toColor3(theme.Colors.Background),
			textColor = cText,
			onClick = function()
				self:toggleLock(pet.uid, not pet.locked)
				self:render(container, theme, widgets)
			end,
		})
		widgets.createButton(row, {
			text = "Remove",
			size = UDim2.new(0, 68, 0, 26),
			position = UDim2.new(1, -68, 0, 0),
			bgColor = cLoss,
			textColor = cText,
			onClick = function()
				self:removePet(pet.uid)
				self:render(container, theme, widgets)
			end,
		})
	end
end

return InventoryPage

end

__moduleSources["UI/AnalyticsPage"] = function(...)
--[[
	AnalyticsPage.luau
	Displays inspected listings, good deals, offer outcomes, Potential vs Pending
	vs Confirmed Profit, acceptance rate, best/worst trade, and visual bar charts.
]]

local AnalyticsPage = {}
AnalyticsPage.__index = AnalyticsPage

function AnalyticsPage.new(deps: {
	tradeHistory: any,
	listingScanner: any,
	offerQueue: any,
	inventoryValuator: any,
})
	local self = setmetatable({}, AnalyticsPage)
	self._history = deps.tradeHistory
	self._scanner = deps.listingScanner
	self._queue = deps.offerQueue
	self._invValuator = deps.inventoryValuator
	return self
end

function AnalyticsPage:getViewModel()
	local potentialProfit = 0
	for _, l in ipairs(self._scanner:getRankedOpportunities({ minProfit = 0 })) do
		if l.listingStatus == "GOOD DEAL" then
			potentialProfit += (l.estimatedProfit or 0)
		end
	end

	local pendingProfit = 0
	for _, o in ipairs(self._queue:getAll()) do
		if o.status == "PENDING" then
			pendingProfit += (o.profitValue or 0)
		end
	end

	local inv = self._invValuator:evaluateAll({})
	return self._history:getSummary({
		potentialProfit = potentialProfit,
		pendingProfit = pendingProfit,
		inventoryValue = inv.totalValue,
	})
end

function AnalyticsPage:render(container: any, theme: any, widgets: any)
	if not (container and widgets and widgets.isRobloxGuiAvailable()) then
		return
	end
	widgets.clearChildren(container)
	local vm = self:getViewModel()
	local cText = theme.toColor3(theme.Colors.TextPrimary)
	local cMuted = theme.toColor3(theme.Colors.TextMuted)
	local cCard = theme.toColor3(theme.Colors.SurfaceAlt)
	local cBorder = theme.toColor3(theme.Colors.Border)
	local cProfit = theme.toColor3(theme.Colors.Profit)
	local cWarn = theme.toColor3(theme.Colors.Warning)
	local cAccent = theme.toColor3(theme.Colors.Accent)

	widgets.createLabel(container, {
		text = "Trading Analytics & Profit Breakdown",
		size = UDim2.new(1, 0, 0, 24),
		textColor = cText,
		textSize = 17,
		bold = true,
	})

	widgets.createStatCard(container, {
		title = "CONFIRMED PROFIT",
		value = string.format("%+.2f", vm.confirmedProfit),
		subtitle = "Verified Trades Only",
		position = UDim2.new(0, 0, 0, 34),
		bgColor = cCard, borderColor = cProfit, titleColor = cMuted, valueColor = cProfit,
	})
	widgets.createStatCard(container, {
		title = "PENDING PROFIT",
		value = string.format("%+.2f", vm.pendingProfit),
		subtitle = "Awaiting Response",
		position = UDim2.new(0.25, 4, 0, 34),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cWarn,
	})
	widgets.createStatCard(container, {
		title = "POTENTIAL PROFIT",
		value = string.format("%+.2f", vm.potentialProfit),
		subtitle = "Scanned Good Deals",
		position = UDim2.new(0.50, 8, 0, 34),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cAccent,
	})
	widgets.createStatCard(container, {
		title = "ACCEPTANCE RATE",
		value = string.format("%.1f%%", vm.acceptanceRate),
		subtitle = string.format("Avg: %+.2f AMVGG", vm.averageProfit),
		position = UDim2.new(0.75, 12, 0, 34),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cText,
	})

	-- Activity Bar Chart Card
	local chartCard = widgets.createRoundedFrame(container, {
		name = "ActivityBars",
		size = UDim2.new(1, 0, 0, 210),
		position = UDim2.new(0, 0, 0, 114),
		bgColor = cCard,
		borderColor = cBorder,
		cornerRadius = 8,
		padding = 12,
	})
	widgets.createLabel(chartCard, {
		text = "Session & Lifetime Activity",
		size = UDim2.new(1, 0, 0, 20),
		textColor = cText,
		bold = true,
	})

	local bars = {
		{ label = "Inspected Listings", val = vm.counters.inspectedListings, color = cAccent },
		{ label = "Good Deals", val = vm.counters.goodDeals, color = cProfit },
		{ label = "Submitted Offers", val = vm.counters.submittedOffers, color = theme.toColor3(theme.Colors.Info) },
		{ label = "Accepted Trades", val = vm.counters.acceptedTrades, color = cProfit },
		{ label = "Declined / Expired", val = vm.counters.declinedOffers + vm.counters.expiredOffers, color = theme.toColor3(theme.Colors.Loss) },
	}
	local maxVal = 1
	for _, b in ipairs(bars) do
		if b.val > maxVal then
			maxVal = b.val
		end
	end

	for i, b in ipairs(bars) do
		local y = 26 + (i - 1) * 32
		widgets.createLabel(chartCard, {
			text = string.format("%s: %d", b.label, b.val),
			position = UDim2.new(0, 0, 0, y),
			size = UDim2.new(0, 190, 0, 20),
			textColor = cMuted,
			textSize = 12,
		})
		local bgBar = widgets.createRoundedFrame(chartCard, {
			size = UDim2.new(1, -200, 0, 14),
			position = UDim2.new(0, 195, 0, y + 3),
			bgColor = theme.toColor3(theme.Colors.Background),
			cornerRadius = 4,
		})
		local pct = math.clamp(b.val / maxVal, 0.02, 1)
		widgets.createRoundedFrame(bgBar, {
			size = UDim2.new(pct, 0, 1, 0),
			bgColor = b.color,
			cornerRadius = 4,
		})
	end
end

return AnalyticsPage

end

__moduleSources["UI/SettingsPage"] = function(...)
--[[
	SettingsPage.luau
	Interactive configuration controls for AMVGG refresh, timers, profit thresholds,
	UI customization, notifications, and data management.
]]

local SettingsPage = {}
SettingsPage.__index = SettingsPage

local LISTING_TTLS = { 30, 45, 60, 90, 120 }
local OFFER_INTERVALS = { 30, 45, 60 }

function SettingsPage.new(deps: { config: any, amvggProvider: any, scheduler: any, logger: any })
	local self = setmetatable({}, SettingsPage)
	self._config = deps.config
	self._amvgg = deps.amvggProvider
	self._scheduler = deps.scheduler
	self._logger = deps.logger
	self._statusMsg = ""
	return self
end

function SettingsPage:setSetting(path: string, value: any): boolean
	local ok = self._config:set(path, value)
	if not ok then
		return false
	end
	if path == "AMVGG.RefreshIntervalSeconds" and self._scheduler then
		self._scheduler:setJobInterval("amvgg_refresh", tonumber(value) or 1800)
	elseif path == "Trading.ScanIntervalSeconds" and self._scheduler then
		self._scheduler:setJobInterval("listing_scan", tonumber(value) or 15)
	elseif path == "Data.LogLevel" and self._logger then
		self._logger:setLevel(tostring(value))
	end
	self._config:saveToFile()
	return true
end

function SettingsPage:getAllSettings()
	return self._config:getAll()
end

function SettingsPage:refreshAmvggNow()
	return self._amvgg:refresh({ force = true })
end

function SettingsPage:resetDefaults()
	self._config:resetDefaults()
	self._config:saveToFile()
end

local function nextInCycle(list: { number }, current: number): number
	for i, v in ipairs(list) do
		if v == current then
			return list[(i % #list) + 1]
		end
	end
	return list[1]
end

function SettingsPage:render(container: any, theme: any, widgets: any)
	if not (container and widgets and widgets.isRobloxGuiAvailable()) then
		return
	end
	widgets.clearChildren(container)
	local s = self:getAllSettings()
	local cText = theme.toColor3(theme.Colors.TextPrimary)
	local cMuted = theme.toColor3(theme.Colors.TextMuted)
	local cCard = theme.toColor3(theme.Colors.SurfaceAlt)
	local cBorder = theme.toColor3(theme.Colors.Border)
	local cAccent = theme.toColor3(theme.Colors.Accent)
	local cProfit = theme.toColor3(theme.Colors.Profit)
	local cLoss = theme.toColor3(theme.Colors.Loss)

	widgets.createLabel(container, {
		text = "Settings & Safety Controls",
		size = UDim2.new(1, 0, 0, 24),
		textColor = cText,
		textSize = 17,
		bold = true,
	})

	local scroll = widgets.createScrollFrame(container, {
		size = UDim2.new(1, 0, 1, -76),
		position = UDim2.new(0, 0, 0, 32),
		gap = 8,
	})

	local function addSettingRow(label: string, btnText: string, btnColor: any, onClick: () -> ())
		local row = widgets.createRoundedFrame(scroll, {
			size = UDim2.new(1, -8, 0, 44),
			bgColor = cCard,
			borderColor = cBorder,
			cornerRadius = 6,
			padding = 8,
		})
		widgets.createLabel(row, {
			text = label,
			size = UDim2.new(1, -150, 0, 26),
			textColor = cText,
			textSize = 13,
		})
		widgets.createButton(row, {
			text = btnText,
			size = UDim2.new(0, 136, 0, 28),
			position = UDim2.new(1, -136, 0, 0),
			bgColor = btnColor,
			textColor = cText,
			onClick = onClick,
		})
	end

	addSettingRow(
		"Listing Stale Timer (30 / 45 / 60 / 90 / 120s)",
		tostring(s.Trading.ListingExpirationSeconds) .. "s",
		cAccent,
		function()
			local nxt = nextInCycle(LISTING_TTLS, s.Trading.ListingExpirationSeconds)
			self:setSetting("Trading.ListingExpirationSeconds", nxt)
			self:render(container, theme, widgets)
		end
	)

	addSettingRow(
		"Offer Response Check Interval (30 / 45 / 60s)",
		tostring(s.Trading.OfferResponseIntervalSeconds) .. "s",
		cAccent,
		function()
			local nxt = nextInCycle(OFFER_INTERVALS, s.Trading.OfferResponseIntervalSeconds)
			self:setSetting("Trading.OfferResponseIntervalSeconds", nxt)
			self:render(container, theme, widgets)
		end
	)

	addSettingRow(
		"Minimum Profit % Filter (cycles +5%)",
		string.format("%.1f%%", s.Trading.MinProfitPercent),
		cAccent,
		function()
			local nxt = if s.Trading.MinProfitPercent >= 25 then 0 else s.Trading.MinProfitPercent + 5
			self:setSetting("Trading.MinProfitPercent", nxt)
			self:render(container, theme, widgets)
		end
	)

	addSettingRow(
		"Trading Mode (manual_confirm / practice)",
		tostring(s.Trading.Mode),
		cAccent,
		function()
			local nxt = if s.Trading.Mode == "manual_confirm" then "practice" else "manual_confirm"
			self:setSetting("Trading.Mode", nxt)
			self:render(container, theme, widgets)
		end
	)

	addSettingRow(
		"Kiria Companion Reactions",
		if s.UI.KiriaEnabled then "ENABLED" else "DISABLED",
		if s.UI.KiriaEnabled then cProfit else cLoss,
		function()
			self:setSetting("UI.KiriaEnabled", not s.UI.KiriaEnabled)
			self:render(container, theme, widgets)
		end
	)

	addSettingRow(
		"Toast Notifications",
		if s.UI.NotificationsEnabled then "ENABLED" else "DISABLED",
		if s.UI.NotificationsEnabled then cProfit else cLoss,
		function()
			self:setSetting("UI.NotificationsEnabled", not s.UI.NotificationsEnabled)
			self:render(container, theme, widgets)
		end
	)

	-- Footer Actions
	widgets.createButton(container, {
		text = "Refresh AMVGG Now",
		size = UDim2.new(0, 160, 0, 32),
		position = UDim2.new(0, 0, 1, -34),
		bgColor = cAccent,
		textColor = cText,
		onClick = function()
			local ok, err = self:refreshAmvggNow()
			self._statusMsg = if ok then "AMVGG refreshed" else tostring(err)
			self:render(container, theme, widgets)
		end,
	})

	widgets.createButton(container, {
		text = "Reset Defaults",
		size = UDim2.new(0, 140, 0, 32),
		position = UDim2.new(0, 170, 1, -34),
		bgColor = cLoss,
		textColor = cText,
		onClick = function()
			self:resetDefaults()
			self._statusMsg = "Defaults restored"
			self:render(container, theme, widgets)
		end,
	})

	if self._statusMsg ~= "" then
		widgets.createLabel(container, {
			text = self._statusMsg,
			position = UDim2.new(0, 320, 1, -30),
			size = UDim2.new(1, -320, 0, 22),
			textColor = cMuted,
			textSize = 12,
		})
	end
end

return SettingsPage

end

__moduleSources["UI/MainWindow"] = function(...)
--[[
	MainWindow.luau
	Root Dark Trading Terminal window coordinating navigation, draggable header bar,
	AMVGG status pill, auto-refresh on events, and clean teardown.
]]

local MainWindow = {}
MainWindow.__index = MainWindow

MainWindow.Pages = { "Dashboard", "Listings", "Offers", "Inventory", "Analytics", "Settings" }

function MainWindow.new(deps: {
	theme: any,
	widgets: any,
	pages: { [string]: any },
	notifications: any,
	eventBus: any?,
	config: any?,
})
	local self = setmetatable({}, MainWindow)
	self._theme = deps.theme
	self._widgets = deps.widgets
	self._pages = deps.pages
	self._notifications = deps.notifications
	self._eventBus = deps.eventBus
	self._config = deps.config

	self._activePage = "Dashboard"
	self._visible = true
	self._minimized = false
	self._gui = nil :: any
	self._root = nil :: any
	self._contentFrame = nil :: any
	self._navButtons = {} :: { [string]: any }
	self._statusPill = nil :: any
	self._connections = {} :: { any }
	return self
end

function MainWindow:getActivePage(): string
	return self._activePage
end

function MainWindow:_refreshNavHighlights()
	for name, btn in pairs(self._navButtons) do
		if btn and btn.BackgroundColor3 ~= nil then
			local isActive = (name == self._activePage)
			btn.BackgroundColor3 = self._theme.toColor3(
				if isActive then self._theme.Colors.Accent else self._theme.Colors.SurfaceAlt
			)
		end
	end
end

function MainWindow:refreshCurrentPage()
	if self._contentFrame and self._pages[self._activePage] then
		self._pages[self._activePage]:render(self._contentFrame, self._theme, self._widgets, function(pageName: string)
			self:navigate(pageName)
		end)
	end
end

function MainWindow:navigate(pageName: string): boolean
	if not self._pages[pageName] then
		return false
	end
	self._activePage = pageName
	self:_refreshNavHighlights()
	self:refreshCurrentPage()
	if self._eventBus then
		self._eventBus:emit("UI:Navigated", pageName)
	end
	return true
end

function MainWindow:setVisible(visible: boolean)
	self._visible = visible
	if self._gui and self._gui.Enabled ~= nil then
		self._gui.Enabled = visible
	end
end

function MainWindow:isVisible(): boolean
	return self._visible
end

function MainWindow:mount(parentGui: any?)
	if not self._widgets.isRobloxGuiAvailable() then
		return
	end
	local targetParent = parentGui
	if not targetParent and type(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and hui then
			targetParent = hui
		end
	end
	if not targetParent then
		local okCore, CoreGui = pcall(function()
			return game:GetService("CoreGui")
		end)
		if okCore and CoreGui then
			targetParent = CoreGui
		end
	end
	if not targetParent then
		local Players = game:GetService("Players")
		targetParent = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	if not targetParent then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "KiriaAutoTraderUI"
	screenGui.ResetOnSpawn = false
	screenGui.AutoLocalize = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = targetParent
	self._gui = screenGui

	-- Responsive UIScale for smaller viewports (inspired by AdoptMeFarm)
	pcall(function()
		local cam = workspace and workspace.CurrentCamera
		if cam then
			local vp = cam.ViewportSize
			local scale = math.min(1, (vp.X - 40) / 880, (vp.Y - 40) / 560)
			if scale < 0.98 and scale > 0.4 then
				local uiScale = Instance.new("UIScale")
				uiScale.Name = "KiriaScale"
				uiScale.Scale = scale
				uiScale.Parent = screenGui
			end
		end
	end)

	-- Fallback to CoreGui if gethui() didn't render
	if type(task) == "table" and type(task.delay) == "function" then
		task.delay(1.5, function()
			pcall(function()
				if self._gui and self._root and self._root.AbsoluteSize.X == 0 then
					self._gui.Parent = game:GetService("CoreGui")
				end
			end)
		end)
	end

	pcall(function()
		local UserInputService = game:GetService("UserInputService")
		local keyName = tostring(self._config and self._config:get("UI.Keybind") or "RightShift")
		local conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if not gameProcessed and input.KeyCode and input.KeyCode.Name == keyName then
				self:setVisible(not self._visible)
			end
		end)
		table.insert(self._connections, conn)
	end)

	local root = self._widgets.createRoundedFrame(screenGui, {
		name = "TerminalRoot",
		size = UDim2.new(0, 880, 0, 560),
		position = UDim2.new(0.5, -440, 0.5, -280),
		bgColor = self._theme.toColor3(self._theme.Colors.Background),
		borderColor = self._theme.toColor3(self._theme.Colors.Accent),
		cornerRadius = 12,
	})
	self._root = root

	-- Draggable Header Bar
	local header = self._widgets.createRoundedFrame(root, {
		name = "Header",
		size = UDim2.new(1, -20, 0, 42),
		position = UDim2.new(0, 10, 0, 10),
		bgColor = self._theme.toColor3(self._theme.Colors.Surface),
		borderColor = self._theme.toColor3(self._theme.Colors.Border),
		cornerRadius = 8,
	})
	for _, c in ipairs(self._widgets.makeDraggable(root, header)) do
		table.insert(self._connections, c)
	end

	self._widgets.createLabel(header, {
		text = "KIRIA AUTOTRADER  •  AMVGG TERMINAL",
		position = UDim2.new(0, 14, 0, 10),
		size = UDim2.new(0, 340, 0, 22),
		textColor = self._theme.toColor3(self._theme.Colors.AccentBright),
		textSize = 14,
		bold = true,
	})

	self._statusPill = self._widgets.createLabel(header, {
		text = "RightShift: Toggle",
		position = UDim2.new(1, -250, 0, 11),
		size = UDim2.new(0, 160, 0, 20),
		textColor = self._theme.toColor3(self._theme.Colors.TextMuted),
		textSize = 11,
		xAlign = Enum.TextXAlignment.Right,
	})

	self._widgets.createButton(header, {
		name = "BtnMinimize",
		text = "_",
		size = UDim2.new(0, 28, 0, 26),
		position = UDim2.new(1, -70, 0, 8),
		bgColor = self._theme.toColor3(self._theme.Colors.SurfaceAlt),
		textColor = self._theme.toColor3(self._theme.Colors.TextPrimary),
		onClick = function()
			self._minimized = not self._minimized
			if self._root then
				self._root.Size = if self._minimized then UDim2.new(0, 880, 0, 62) else UDim2.new(0, 880, 0, 560)
			end
			if self._contentFrame then
				self._contentFrame.Visible = not self._minimized
			end
		end,
	})

	self._widgets.createButton(header, {
		name = "BtnClose",
		text = "X",
		size = UDim2.new(0, 28, 0, 26),
		position = UDim2.new(1, -36, 0, 8),
		bgColor = self._theme.toColor3(self._theme.Colors.Loss),
		textColor = self._theme.toColor3(self._theme.Colors.TextPrimary),
		onClick = function()
			self:setVisible(false)
		end,
	})

	local sidebar = self._widgets.createRoundedFrame(root, {
		name = "Sidebar",
		size = UDim2.new(0, self._theme.Layout.SidebarWidth, 1, -72),
		position = UDim2.new(0, 10, 0, 60),
		bgColor = self._theme.toColor3(self._theme.Colors.Surface),
		borderColor = self._theme.toColor3(self._theme.Colors.Border),
		cornerRadius = 10,
	})

	for idx, pageName in ipairs(MainWindow.Pages) do
		local btn = self._widgets.createButton(sidebar, {
			name = "Nav_" .. pageName,
			text = pageName,
			size = UDim2.new(1, -16, 0, 36),
			position = UDim2.new(0, 8, 0, 12 + (idx - 1) * 44),
			bgColor = self._theme.toColor3(self._theme.Colors.SurfaceAlt),
			textColor = self._theme.toColor3(self._theme.Colors.TextPrimary),
			onClick = function()
				self:navigate(pageName)
			end,
		})
		self._navButtons[pageName] = btn
	end

	-- Unload button at bottom of sidebar (like menu:CreateButton("Unload"))
	self._widgets.createButton(sidebar, {
		name = "BtnUnload",
		text = "Unload",
		size = UDim2.new(1, -16, 0, 32),
		position = UDim2.new(0, 8, 1, -44),
		bgColor = self._theme.toColor3(self._theme.Colors.Loss),
		textColor = self._theme.toColor3(self._theme.Colors.TextPrimary),
		onClick = function()
			self:destroy()
		end,
	})

	-- Compact Watermark bar at top-left of ScreenGui
	local wm = self._widgets.createRoundedFrame(self._screenGui, {
		name = "KiriaWatermark",
		size = UDim2.new(0, 320, 0, 28),
		position = UDim2.new(0, 14, 0, 14),
		bgColor = self._theme.toColor3(self._theme.Colors.Surface),
		borderColor = self._theme.toColor3(self._theme.Colors.Accent),
		cornerRadius = 6,
		padding = 6,
	})
	self._widgets.createLabel(wm, {
		text = "KIRIA AUTOTRADER  |  AMVGG  |  RightShift",
		size = UDim2.new(1, 0, 1, 0),
		textColor = self._theme.toColor3(self._theme.Colors.AccentBright),
		textSize = 12,
		bold = true,
	})

	self._contentFrame = self._widgets.createRoundedFrame(root, {
		name = "Content",
		size = UDim2.new(1, -(self._theme.Layout.SidebarWidth + 30), 1, -72),
		position = UDim2.new(0, self._theme.Layout.SidebarWidth + 20, 0, 60),
		bgColor = self._theme.toColor3(self._theme.Colors.Surface),
		borderColor = self._theme.toColor3(self._theme.Colors.Border),
		cornerRadius = 10,
		padding = 14,
	})

	-- Auto-refresh active page when live data updates
	if self._eventBus then
		for _, evtName in ipairs({ "AMVGG:Refreshed", "AMVGG:StatusChanged", "Inventory:Updated", "Offer:Queued", "Offer:StatusChanged", "Trade:Confirmed", "Kiria:Message" }) do
			table.insert(self._connections, self._eventBus:subscribe(evtName, function()
				self:refreshCurrentPage()
			end))
		end
	end

	self:navigate(self._activePage)
end

function MainWindow:destroy()
	for _, c in ipairs(self._connections) do
		if c and type(c.disconnect) == "function" then
			c:disconnect()
		end
	end
	table.clear(self._connections)
	if self._gui then
		pcall(function()
			self._gui:Destroy()
		end)
		self._gui = nil
	end
end

return MainWindow

end

__moduleSources["Bootstrap"] = function(...)
--[[
	Bootstrap.luau
	Composition root wiring Core, Values, Inventory, Trading, Kiria, and UI
	using relative module loading with zero globals and clean shutdown.
]]

local Bootstrap = {}

export type EnvironmentAdapters = {
	fs: { exists: (string) -> boolean, read: (string) -> string, write: (string, string) -> (), append: ((string, string) -> ())? }?,
	json: { encode: (any) -> string, decode: (string) -> any }?,
	httpGet: ((string) -> (boolean, number, string))?,
	gameAdapter: any?,
	clockFn: (() -> number)?,
	initialConfig: { [string]: any }?,
	autoStartScheduler: boolean?,
	skipInitialFetch: boolean?,
}

local function makeDefaultFs()
	if type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function" then
		return {
			exists = function(p: string): boolean
				local ok, res = pcall(isfile, p)
				return ok and res == true
			end,
			read = function(p: string): string
				return readfile(p)
			end,
			write = function(p: string, content: string)
				if type(makefolder) == "function" and type(isfolder) == "function" then
					local dir = string.match(p, "^(.+)/[^/]+$")
					if dir and not isfolder(dir) then
						pcall(makefolder, dir)
					end
				end
				writefile(p, content)
			end,
			append = function(p: string, content: string)
				if type(appendfile) == "function" then
					appendfile(p, content)
				end
			end,
		}
	end
	return nil
end

local function makeDefaultJson()
	if type(game) == "userdata" or type(game) == "table" then
		local ok, HttpService = pcall(function()
			return game:GetService("HttpService")
		end)
		if ok and HttpService then
			return {
				encode = function(v: any): string
					return HttpService:JSONEncode(v)
				end,
				decode = function(s: string): any
					return HttpService:JSONDecode(s)
				end,
			}
		end
	end
	return nil
end

local function makeDefaultHttpGet(): ((string) -> (boolean, number, string))?
	local reqFn: any = nil
	if type(request) == "function" then
		reqFn = request
	elseif type(http_request) == "function" then
		reqFn = http_request
	elseif type(syn) == "table" and type(syn.request) == "function" then
		reqFn = syn.request
	end
	if reqFn then
		return function(url: string)
			local ok, resp = pcall(reqFn, { Url = url, Method = "GET" })
			if not ok or type(resp) ~= "table" then
				return false, 0, tostring(resp)
			end
			return true, tonumber(resp.StatusCode) or 0, tostring(resp.Body or "")
		end
	end
	return nil
end

local function makeDefaultGameAdapter()
	if type(game) ~= "userdata" and type(game) ~= "table" then
		return nil
	end
	local ok, ReplicatedStorage = pcall(function()
		return game:GetService("ReplicatedStorage")
	end)
	if not ok or not ReplicatedStorage then
		return nil
	end

	local function kindToName(kind: string): string
		-- Convert e.g. "shadow_dragon" or "halloween_2024_shadow_dragon" -> "Shadow Dragon"
		-- Strip year/event prefixes (e.g. "halloween_2026_stray_cat" -> "Stray Cat")
		local s = tostring(kind or "")
		-- Remove common event/year prefixes
		s = s:gsub("^%a+_%d%d%d%d_", "")
		s = s:gsub("_", " ")
		s = s:gsub("(%a)([%w']*)", function(first, rest)
			return string.upper(first) .. string.lower(rest)
		end)
		return s
	end

	-- Try to get a usable ClientData handle using all known Adopt Me approaches
	local function getClientData(): any?
		-- Method 1: require module directly
		local okM, ClientData = pcall(function()
			return require(
				ReplicatedStorage
					:WaitForChild("ClientModules", 3)
					:WaitForChild("Core", 3)
					:WaitForChild("ClientData", 3)
			)
		end)
		if okM and type(ClientData) == "table" then
			return ClientData
		end

		-- Method 2: try alternate paths
		local paths = {
			{ "ClientModules", "ClientData" },
			{ "Modules", "ClientData" },
			{ "SharedModules", "ClientData" },
		}
		for _, path in ipairs(paths) do
			local ok2, m = pcall(function()
				local cur: any = ReplicatedStorage
				for _, segment in ipairs(path) do
					cur = cur:WaitForChild(segment, 2)
				end
				return require(cur)
			end)
			if ok2 and type(m) == "table" then
				return m
			end
		end
		return nil
	end

	-- Parse inventory from raw table returned by get("inventory") or get_data()
	local function parseInventoryTable(inv: any): { any }
		if type(inv) ~= "table" then return {} end
		local petsTable = type(inv.pets) == "table" and inv.pets or nil
		if not petsTable then
			-- Maybe inv IS the pets table (some versions)
			petsTable = inv
		end
		local out = {}
		for uid, pet in pairs(petsTable) do
			if type(pet) == "table" then
				local props = type(pet.properties) == "table" and pet.properties
				           or type(pet.props) == "table" and pet.props
				           or {}
				-- Some versions store neon/mega directly on pet
				local isNeon = props.neon == true or pet.neon == true
				local isMega = props.mega_neon == true or props.megaNeon == true
				         or pet.mega_neon == true or pet.mega == true
				local isFly  = props.flyable == true or props.fly == true
				         or pet.flyable == true
				local isRide = props.rideable == true or props.ride == true
				         or pet.rideable == true
				local petKind = tostring(pet.kind or pet.id or pet.petId or "Unknown")
				table.insert(out, {
					uid      = tostring(uid),
					name     = kindToName(petKind),
					rawKind  = petKind,
					neon     = isNeon,
					mega     = isMega,
					fly      = isFly,
					ride     = isRide,
					locked   = props.locked == true or pet.locked == true,
					favorite = props.favorite == true or pet.favorite == true,
					age      = tonumber(props.age or pet.age),
				})
			end
		end
		return out
	end

	return {
		readInventory = function()
			-- Step 1: get ClientData module
			local cd = getClientData()
			if not cd then
				error("Adopt Me ClientData module unavailable — not in Adopt Me?")
			end

			local inv = nil

			-- Step 2a: try get_data() first (returns full data snapshot)
			if type(cd.get_data) == "function" then
				local ok2, allData = pcall(cd.get_data, cd)
				if ok2 and type(allData) == "table" then
					inv = allData["inventory"] or allData.inventory
				end
			end

			-- Step 2b: try get("inventory")
			if not inv and type(cd.get) == "function" then
				local ok3, v = pcall(cd.get, cd, "inventory")
				if ok3 and type(v) == "table" then
					inv = v
				end
			end

			-- Step 2c: try direct get_data() without self
			if not inv and type(cd.get_data) == "function" then
				local ok4, v = pcall(cd.get_data)
				if ok4 and type(v) == "table" then
					inv = v["inventory"] or v.inventory
				end
			end

			if not inv then
				error("Could not read inventory from ClientData (tried get_data() and get('inventory'))")
			end

			return parseInventoryTable(inv)
		end,

		-- Fetch Trade Hub listings (returns { listings: {...}, error: string? })
		fetchListings = nil,  -- filled in after TradeHubAdapter is wired
		sendOffer = nil,       -- filled in after TradeHubAdapter is wired
	}
end

function Bootstrap.createApp(requireRelative: (string) -> any, adapters: EnvironmentAdapters?)
	local env = adapters or {}
	local fs = env.fs or makeDefaultFs()
	local json = env.json or makeDefaultJson()
	local httpGet = env.httpGet or makeDefaultHttpGet()
	local gameAdapter = env.gameAdapter or makeDefaultGameAdapter()
	local clockFn = env.clockFn or os.time

	-- Core
	local Logger = requireRelative("Core/Logger")
	local EventBus = requireRelative("Core/EventBus")
	local StateManager = requireRelative("Core/StateManager")
	local ErrorHandler = requireRelative("Core/ErrorHandler")
	local TaskScheduler = requireRelative("Core/TaskScheduler")
	local ConfigManager = requireRelative("Core/ConfigManager")

	local logger = Logger.new({ level = "INFO", filePath = "kiria_debug.log", fs = fs })
	local eventBus = EventBus.new(logger)
	local state = StateManager.new(eventBus)
	local errorHandler = ErrorHandler.new(logger, eventBus)
	local config = ConfigManager.new({
		initial = env.initialConfig,
		json = json,
		fs = fs,
		logger = logger,
		eventBus = eventBus,
	})
	config:loadFromFile()
	logger:setLevel(tostring(config:get("Data.LogLevel") or "INFO"))

	local scheduler = TaskScheduler.new(logger, 0.5)

	-- Values (AMVGG ONLY + CSV fallback)
	local ValueParser = requireRelative("Values/ValueParser")
	local ValueValidator = requireRelative("Values/ValueValidator")
	local ValueCache = requireRelative("Values/ValueCache")
	local AMVGGProvider = requireRelative("Values/AMVGGProvider")
	local ValueEngine = requireRelative("Values/ValueEngine")
	local CSVLoader = requireRelative("Values/CSVLoader")

	local valueCache = ValueCache.new({
		filePath = config:get("AMVGG.CacheFile"),
		fs = fs,
		json = json,
		validator = ValueValidator,
		logger = logger,
	})

	-- Load CSV as instant offline fallback (sourced from AMVGG)
	local csvLoader = CSVLoader.new({
		fs = fs,
		logger = logger,
		csvPath = config:get("Data.CSVPath") or "pets_ridepots.csv",
	})
	local csvLoaded = csvLoader:load()
	if csvLoaded then
		csvLoader:seedCache(valueCache)
		logger:info("[Bootstrap] CSV fallback: " .. csvLoader:count() .. " pets seeded into cache")
	end
	local amvggProvider = AMVGGProvider.new({
		config = config,
		cache = valueCache,
		parser = ValueParser,
		validator = ValueValidator,
		errorHandler = errorHandler,
		eventBus = eventBus,
		state = state,
		logger = logger,
		httpGet = httpGet,
		jsonDecode = if json then json.decode else function() error("No JSON decoder") end,
		clockFn = clockFn,
	})
	local valueEngine = ValueEngine.new(valueCache, ValueValidator, config)

	-- Inventory
	local PetDatabase = requireRelative("Inventory/PetDatabase")
	local InventoryReader = requireRelative("Inventory/InventoryReader")
	local InventoryValuator = requireRelative("Inventory/InventoryValuator")

	local petDatabase = PetDatabase.new(valueCache, ValueValidator)
	local inventoryReader = InventoryReader.new({
		filePath = config:get("Data.InventoryFile"),
		fs = fs,
		json = json,
		eventBus = eventBus,
		logger = logger,
		gameAdapter = gameAdapter,
	})
	inventoryReader:load()
	if gameAdapter then
		pcall(function()
			inventoryReader:syncFromGame()
		end)
	end
	local inventoryValuator = InventoryValuator.new(inventoryReader, valueEngine)

	-- Trading
	local ProfitCalculator = requireRelative("Trading/ProfitCalculator")
	local TradeEvaluator = requireRelative("Trading/TradeEvaluator")
	local ListingScanner = requireRelative("Trading/ListingScanner")
	local OfferAnalyzer = requireRelative("Trading/OfferAnalyzer")
	local ListingManager = requireRelative("Trading/ListingManager")
	local OfferTimer = requireRelative("Trading/OfferTimer")
	local OfferQueue = requireRelative("Trading/OfferQueue")
	local TradeHistory = requireRelative("Trading/TradeHistory")
	local TradeHubAdapter = requireRelative("Trading/TradeHubAdapter")

	-- Wire Trade Hub adapter into gameAdapter
	local tradeHubAdapter = TradeHubAdapter.new({ logger = logger, eventBus = eventBus })
	if gameAdapter and tradeHubAdapter:isAvailable() then
		gameAdapter.fetchListings = function()
			return tradeHubAdapter:fetchListings()
		end
		gameAdapter.sendOffer = function(targetUserId, offeredItems, requestedItems)
			return tradeHubAdapter:sendOffer(tostring(targetUserId), offeredItems, requestedItems)
		end
		logger:info("[Bootstrap] Trade Hub adapter wired: listings + offer sending enabled")
	elseif gameAdapter then
		logger:warn("[Bootstrap] Trade Hub remotes not found — listing scan will use fallback only")
	end

	local tradeEvaluator = TradeEvaluator.new(valueEngine, ProfitCalculator)
	local listingScanner = ListingScanner.new({
		tradeEvaluator = tradeEvaluator,
		config = config,
		eventBus = eventBus,
		state = state,
		logger = logger,
		json = json,
		gameAdapter = gameAdapter,
		clockFn = clockFn,
	})
	local offerAnalyzer = OfferAnalyzer.new({
		inventoryReader = inventoryReader,
		valueEngine = valueEngine,
		profitCalculator = ProfitCalculator,
		config = config,
	})
	local listingManager = ListingManager.new({
		valueEngine = valueEngine,
		config = config,
		eventBus = eventBus,
		state = state,
		logger = logger,
		clockFn = clockFn,
	})
	local offerTimer = OfferTimer.new(config, clockFn)
	local offerQueue = OfferQueue.new({
		valueEngine = valueEngine,
		offerTimer = offerTimer,
		config = config,
		eventBus = eventBus,
		state = state,
		logger = logger,
		clockFn = clockFn,
	})
	local tradeHistory = TradeHistory.new({
		filePath = config:get("Data.AnalyticsFile"),
		fs = fs,
		json = json,
		eventBus = eventBus,
		clockFn = clockFn,
	})
	tradeHistory:load()

	-- Kiria Companion
	local Personality = requireRelative("Kiria/Personality")
	local Memory = requireRelative("Kiria/Memory")
	local Reactions = requireRelative("Kiria/Reactions")
	local Companion = requireRelative("Kiria/Companion")

	local kiriaMemory = Memory.new({
		filePath = config:get("Data.KiriaMemoryFile"),
		fs = fs,
		json = json,
		clockFn = clockFn,
	})
	kiriaMemory:load()
	local kiria = Companion.new({
		personality = Personality,
		memory = kiriaMemory,
		reactions = Reactions,
		eventBus = eventBus,
		config = config,
		clockFn = clockFn,
	})

	-- UI
	local Theme = requireRelative("UI/Components/Theme")
	local Widgets = requireRelative("UI/Components/Widgets")
	local Notifications = requireRelative("UI/Notifications")
	local Dashboard = requireRelative("UI/Dashboard")
	local ListingsPage = requireRelative("UI/ListingsPage")
	local OffersPage = requireRelative("UI/OffersPage")
	local InventoryPage = requireRelative("UI/InventoryPage")
	local AnalyticsPage = requireRelative("UI/AnalyticsPage")
	local SettingsPage = requireRelative("UI/SettingsPage")
	local MainWindow = requireRelative("UI/MainWindow")

	local notifications = Notifications.new({ eventBus = eventBus, config = config, clockFn = clockFn })
	local runAutoTradeCycle: (boolean?) -> ()

	local autoLoopApi = {
		runNow = function()
			runAutoTradeCycle(true)
		end,
		getEnabled = function() return state:get("autoLoop.enabled") end,
		setEnabled = function(v: boolean)
			autoMode = v
			state:set("autoLoop.enabled", v)
			logger:info("[AutoLoop] " .. (v and "ENABLED" or "DISABLED"))
		end,
		getStats = function()
			return {
				offersSent = state:get("autoLoop.offersSentTotal") or 0,
				lastScanAt = state:get("autoLoop.lastScanAt") or 0,
				opportunities = state:get("autoLoop.opportunitiesFound") or 0,
			}
		end,
	}

	local pages = {
		Dashboard = Dashboard.new({
			amvggProvider = amvggProvider,
			inventoryValuator = inventoryValuator,
			listingScanner = listingScanner,
			offerQueue = offerQueue,
			tradeHistory = tradeHistory,
			kiria = kiria,
			autoLoop = autoLoopApi,
		}),
		Listings = ListingsPage.new({
			listingScanner = listingScanner,
			listingManager = listingManager,
			inventoryReader = inventoryReader,
		}),
		Offers = OffersPage.new({
			offerAnalyzer = offerAnalyzer,
			offerQueue = offerQueue,
			tradeHistory = tradeHistory,
		}),
		Inventory = InventoryPage.new({
			inventoryReader = inventoryReader,
			inventoryValuator = inventoryValuator,
		}),
		Analytics = AnalyticsPage.new({
			tradeHistory = tradeHistory,
			listingScanner = listingScanner,
			offerQueue = offerQueue,
			inventoryValuator = inventoryValuator,
		}),
		Settings = SettingsPage.new({
			config = config,
			amvggProvider = amvggProvider,
			scheduler = scheduler,
			logger = logger,
		}),
	}
	local mainWindow = MainWindow.new({
		theme = Theme,
		widgets = Widgets,
		pages = pages,
		notifications = notifications,
		eventBus = eventBus,
		config = config,
	})

	-- Initialize AMVGG cache & background jobs
	amvggProvider:initFromCache()
	kiria:startSession()

	scheduler:addJob("amvgg_refresh", tonumber(config:get("AMVGG.RefreshIntervalSeconds")) or 1800, function()
		amvggProvider:refresh({ force = false })
	end)
	scheduler:addJob("listing_stale_check", 5, function()
		listingManager:checkStaleListings()
	end)
	scheduler:addJob("offer_timer_check", 5, function()
		local res = offerQueue:checkPendingTimers()
		for _ in ipairs(res.expired) do
			tradeHistory:recordOfferOutcome("EXPIRED")
		end
	end)

	-- ── AUTO TRADE LOOP ──────────────────────────────────────────────────────
	-- Every scan_interval seconds: sync inventory → scan listings → auto-send offers
	local autoMode = true  -- can be toggled via config or UI
	local offersSentThisSession = 0
	local lastAutoScanTime = 0

	runAutoTradeCycle = function(checkAll: boolean?)
		if not checkAll and not autoMode then return end
		lastAutoScanTime = clockFn()

		-- 1. Sync inventory from game
		if gameAdapter and type(gameAdapter.readInventory) == "function" then
			local okInv = pcall(function() inventoryReader:syncFromGame() end)
			if not okInv then
				logger:warn("[AutoLoop] Inventory sync failed")
			end
		end

		-- 2. Scan Trade Hub listings
		local scanResult = listingScanner:scanOnce()
		local opportunities = listingScanner:getRankedOpportunities({
			minPctGain = tonumber(config:get("Trading.MinProfitPct")) or 5,
			minProfit  = 0,
		})

		-- 3. For each GOOD DEAL: generate combo offer and auto-send
		local maxOffersPerCycle = if checkAll then math.huge else (tonumber(config:get("Trading.MaxOffersPerCycle")) or 3)
		local sent = 0
		for _, opp in ipairs(opportunities) do
			if sent >= maxOffersPerCycle then break end
			if opp.verdict == "GOOD DEAL" or opp.verdict == "GREAT DEAL" then
				-- Generate offer combos from owned inventory
				local res = offerAnalyzer:generateCandidates(opp.requestedItems or {})
				if res and #res.candidates > 0 then
					local best = res.candidates[1]
					if gameAdapter and type(gameAdapter.sendOffer) == "function" then
						local offerResult = gameAdapter.sendOffer(
							opp.sellerId or "",
							best.offeredPetIds or {},
							opp.requestedItems or {}
						)
						if offerResult and offerResult.success then
							sent += 1
							offersSentThisSession += 1
							tradeHistory:recordOfferSent({
								targetPet = table.concat(opp.requestedItems or {}, ", "),
								offeredPets = best.offeredPetIds or {},
								profit = best.profit,
								pctGain = best.pctGain,
							})
							eventBus:emit("offer:auto_sent", {
								sellerId = opp.sellerId,
								requestedItems = opp.requestedItems,
								offeredPets = best.offeredPetIds,
								profit = best.profit,
							})
							logger:info(string.format(
								"[AutoLoop] Sent offer #%d (profit=+%.2f, +%.1f%%) for %s",
								offersSentThisSession, best.profit or 0, best.pctGain or 0,
								table.concat(opp.requestedItems or {}, "+")
							))
						end
					else
						-- No live offer remote — queue for manual review
						offerQueue:addOffer({
							targetPets   = opp.requestedItems or {},
							offeredPets  = best.offeredPetIds or {},
							profit       = best.profit,
							pctGain      = best.pctGain,
							sellerId     = opp.sellerId or "",
						})
					end
				end
			end
		end

		state:set("autoLoop.lastScanAt", lastAutoScanTime)
		state:set("autoLoop.offersSentTotal", offersSentThisSession)
		state:set("autoLoop.opportunitiesFound", #opportunities)
	end

	local scanInterval = tonumber(config:get("Trading.ScanIntervalSeconds")) or 15
	scheduler:addJob("auto_trade_loop", scanInterval, runAutoTradeCycle)

	-- Run first auto-scan immediately on startup (don't wait 15s)
	if env.autoStartScheduler then
		if type(task) == "table" and type(task.spawn) == "function" then
			task.spawn(function()
				if type(task.wait) == "function" then task.wait(1.5) end
				runAutoTradeCycle(false)
			end)
		end
	end

	-- expose toggle for UI
	state:set("autoLoop.enabled", true)
	state:set("autoLoop.offersSentTotal", 0)

	if not env.skipInitialFetch and httpGet then
		if type(task) == "table" and type(task.spawn) == "function" then
			task.spawn(function()
				amvggProvider:refresh({ force = true })
			end)
		else
			amvggProvider:refresh({ force = true })
		end
	end

	if env.autoStartScheduler then
		scheduler:start()
	end

	local app = {
		core = {
			logger = logger,
			eventBus = eventBus,
			state = state,
			errorHandler = errorHandler,
			scheduler = scheduler,
			config = config,
		},
		values = {
			cache = valueCache,
			provider = amvggProvider,
			engine = valueEngine,
			parser = ValueParser,
			validator = ValueValidator,
			csvLoader = csvLoader,
		},
		inventory = {
			database = petDatabase,
			reader = inventoryReader,
			valuator = inventoryValuator,
		},
		trading = {
			profitCalculator = ProfitCalculator,
			evaluator = tradeEvaluator,
			scanner = listingScanner,
			offerAnalyzer = offerAnalyzer,
			listingManager = listingManager,
			offerTimer = offerTimer,
			offerQueue = offerQueue,
			history = tradeHistory,
			tradeHubAdapter = tradeHubAdapter,
		},
		kiria = kiria,
		ui = {
			theme = Theme,
			widgets = Widgets,
			notifications = notifications,
			pages = pages,
			window = mainWindow,
		},
		autoLoop = {
			getEnabled = function() return state:get("autoLoop.enabled") end,
			setEnabled = function(v: boolean)
				autoMode = v
				state:set("autoLoop.enabled", v)
				logger:info("[AutoLoop] " .. (v and "ENABLED" or "DISABLED"))
			end,
			getStats = function()
				return {
					offersSent = state:get("autoLoop.offersSentTotal") or 0,
					lastScanAt = state:get("autoLoop.lastScanAt") or 0,
					opportunities = state:get("autoLoop.opportunitiesFound") or 0,
				}
			end,
		},
	}

	function app.shutdown()
		scheduler:destroy()
		mainWindow:destroy()
		notifications:destroy()
		kiria:destroy()
		state:destroy()
		eventBus:destroy()
		logger:destroy()
	end

	return app
end

return Bootstrap

end

local Bootstrap = import("Bootstrap")
local app = Bootstrap.createApp(import, { autoStartScheduler = true })
app.ui.window:mount()
return app