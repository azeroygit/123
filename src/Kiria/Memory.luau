--!strict
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
