--!strict
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
