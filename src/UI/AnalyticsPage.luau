--!strict
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
