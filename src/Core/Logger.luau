--!strict
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
