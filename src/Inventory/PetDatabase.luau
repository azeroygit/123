--!strict
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
