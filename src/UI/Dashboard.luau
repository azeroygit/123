--!strict
--[[
	Dashboard.luau
	Overview page: inventory value, best pet, AMVGG status + refresh,
	scanned listings, good deals, pending offers, confirmed profit, and Kiria card.
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
})
	local self = setmetatable({}, Dashboard)
	self._amvgg = deps.amvggProvider
	self._invValuator = deps.inventoryValuator
	self._scanner = deps.listingScanner
	self._offerQueue = deps.offerQueue
	self._history = deps.tradeHistory
	self._kiria = deps.kiria
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

function Dashboard:render(container: any, theme: any, widgets: any)
	if not (container and widgets and widgets.isRobloxGuiAvailable()) then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
	local vm = self:getViewModel()
	widgets.createLabel(container, {
		text = string.format("Dashboard  |  Inventory: %.2f AMVGG  |  Confirmed Profit: %+.2f  |  AMVGG: %s (%d pets)",
			vm.inventoryValue, vm.confirmedProfit, vm.amvgg.status, vm.amvgg.petCount),
		textColor = theme.toColor3(theme.Colors.TextPrimary),
		bold = true,
	})
	widgets.createButton(container, {
		text = "Refresh AMVGG",
		position = UDim2.new(0, 0, 0, 32),
		bgColor = theme.toColor3(theme.Colors.Accent),
		textColor = theme.toColor3(theme.Colors.TextPrimary),
		onClick = function()
			self:refreshAmvgg()
		end,
	})
	if vm.kiria and vm.kiria.latestMessage then
		widgets.createLabel(container, {
			text = string.format("Kiria (%s • %s): %s", vm.kiria.rank, vm.kiria.mood, vm.kiria.latestMessage),
			position = UDim2.new(0, 0, 0, 76),
			size = UDim2.new(1, 0, 0, 48),
			textColor = theme.toColor3(theme.Colors.AccentBright),
		})
	end
end

return Dashboard
