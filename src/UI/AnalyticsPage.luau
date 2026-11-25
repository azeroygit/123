--!strict
--[[
	AnalyticsPage.luau
	Displays inspected listings, good deals, offer outcomes, Potential vs Pending
	vs Confirmed Profit, acceptance rate, best/worst trade, and chart series.
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
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
	local vm = self:getViewModel()
	widgets.createLabel(container, {
		text = string.format(
			"Analytics  |  Confirmed: %+.2f  |  Pending: %+.2f  |  Potential: %+.2f  |  Accept Rate: %.1f%%",
			vm.confirmedProfit, vm.pendingProfit, vm.potentialProfit, vm.acceptanceRate
		),
		textColor = theme.toColor3(theme.Colors.TextPrimary),
		bold = true,
	})
end

return AnalyticsPage
