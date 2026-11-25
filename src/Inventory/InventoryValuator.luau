--!strict
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
