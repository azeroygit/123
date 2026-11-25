--!strict
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
