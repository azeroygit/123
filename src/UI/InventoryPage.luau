--!strict
--[[
	InventoryPage.luau
	Inventory search, filtering, AMVGG valuation sorting, top pet highlight,
	listing selection, manual editing, JSON import/export, and game sync.
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
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
	local vm = self:getViewModel()
	local topName = if vm.topPet then vm.topPet.pet.name else "None"
	local topVal = if vm.topPet then vm.topPet.value else 0
	widgets.createLabel(container, {
		text = string.format("Inventory (%d pets)  |  Total AMVGG: %.2f  |  Top Pet: %s (%.2f)", vm.totalCount, vm.totalValue, topName, topVal),
		textColor = theme.toColor3(theme.Colors.TextPrimary),
		bold = true,
	})
end

return InventoryPage
