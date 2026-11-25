--!strict
--[[
	Dashboard.luau
	Overview page: inventory value, best pet, AMVGG status + refresh,
	scanned listings, good deals, pending offers, confirmed profit, quick pet lookup,
	and Kiria companion card.
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
	self._lookupQuery = "Shadow Dragon"
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

function Dashboard:render(container: any, theme: any, widgets: any, navigateFn: ((string) -> ())?)
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
	local cAccent = theme.toColor3(theme.Colors.Accent)
	local cBright = theme.toColor3(theme.Colors.AccentBright)

	widgets.createLabel(container, {
		text = "Dashboard Overview",
		size = UDim2.new(1, -150, 0, 24),
		textColor = cText,
		textSize = 18,
		bold = true,
	})

	widgets.createButton(container, {
		text = "Refresh AMVGG",
		size = UDim2.new(0, 140, 0, 30),
		position = UDim2.new(1, -140, 0, 0),
		bgColor = cAccent,
		textColor = cText,
		onClick = function()
			self:refreshAmvgg()
		end,
	})

	-- Row 1 of Stat Cards
	local bestName = if vm.bestPet then vm.bestPet.pet.name else "None"
	local bestVal = if vm.bestPet then string.format("%.2f", vm.bestPet.value) else "0.00"

	widgets.createStatCard(container, {
		title = "INVENTORY VALUE",
		value = string.format("%.2f", vm.inventoryValue),
		subtitle = "AMVGG Total",
		position = UDim2.new(0, 0, 0, 40),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cText,
	})
	widgets.createStatCard(container, {
		title = "TOP PET",
		value = bestName,
		subtitle = bestVal .. " AMVGG",
		position = UDim2.new(0.25, 4, 0, 40),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cBright,
	})
	widgets.createStatCard(container, {
		title = "AMVGG FEED",
		value = string.format("%s (%d)", vm.amvgg.status, vm.amvgg.petCount),
		subtitle = if vm.amvgg.isStale then "Cached Fallback" else "amvgg.com/values/pets",
		position = UDim2.new(0.50, 8, 0, 40),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted,
		valueColor = if vm.amvgg.status == "LIVE" then cProfit else theme.toColor3(theme.Colors.Warning),
	})
	widgets.createStatCard(container, {
		title = "CONFIRMED PROFIT",
		value = string.format("%+.2f", vm.confirmedProfit),
		subtitle = string.format("Pending: %+.2f", vm.pendingProfit),
		position = UDim2.new(0.75, 12, 0, 40),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cProfit,
	})

	-- Row 2 of Stat Cards
	widgets.createStatCard(container, {
		title = "SCANNED LISTINGS",
		value = tostring(vm.scannedListings),
		subtitle = "Hub & Imported",
		position = UDim2.new(0, 0, 0, 118),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cText,
	})
	widgets.createStatCard(container, {
		title = "GOOD DEALS",
		value = tostring(vm.goodDeals),
		subtitle = "Ranked Opportunities",
		position = UDim2.new(0.25, 4, 0, 118),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cProfit,
	})
	widgets.createStatCard(container, {
		title = "PENDING OFFERS",
		value = tostring(vm.pendingOffers),
		subtitle = "Awaiting Response",
		position = UDim2.new(0.50, 8, 0, 118),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cText,
	})
	widgets.createStatCard(container, {
		title = "KIRIA RANK",
		value = vm.kiria.rank,
		subtitle = string.format("%d XP • %s", vm.kiria.xp, vm.kiria.mood),
		position = UDim2.new(0.75, 12, 0, 118),
		bgColor = cCard, borderColor = cBorder, titleColor = cMuted, valueColor = cBright,
	})

	-- Quick AMVGG Pet Lookup Card
	local lookupCard = widgets.createRoundedFrame(container, {
		name = "QuickLookup",
		size = UDim2.new(1, 0, 0, 110),
		position = UDim2.new(0, 0, 0, 198),
		bgColor = cCard,
		borderColor = cBorder,
		cornerRadius = 8,
		padding = 10,
	})
	widgets.createLabel(lookupCard, {
		text = "Quick AMVGG Pet Value Lookup",
		size = UDim2.new(0.5, 0, 0, 20),
		textColor = cText,
		bold = true,
	})
	widgets.createTextBox(lookupCard, {
		text = self._lookupQuery,
		placeholder = "Type pet name (e.g. Shadow Dragon)...",
		size = UDim2.new(0, 240, 0, 30),
		position = UDim2.new(0, 0, 0, 26),
		bgColor = theme.toColor3(theme.Colors.Background),
		textColor = cText,
		placeholderColor = cMuted,
		borderColor = cBorder,
		onFocusLost = function(txt)
			self._lookupQuery = txt
			self:render(container, theme, widgets, navigateFn)
		end,
	})

	local petRec = self._invValuator._valueEngine._cache:getPet(self._lookupQuery)
	local lookupText = if petRec
		then string.format(
			"%s  |  FR: %s  |  No-Pot: %s  |  NFR: %s  |  MFR: %s  |  Demand: %s",
			petRec.name,
			tostring(petRec.values.regular or "-"),
			tostring(petRec.values.npRegular or "-"),
			tostring(petRec.values.neon or "-"),
			tostring(petRec.values.mega or "-"),
			tostring(petRec.demands.regular or "N/A")
		)
		else "Pet not found in AMVGG dataset (press Enter after typing)."
	widgets.createLabel(lookupCard, {
		text = lookupText,
		position = UDim2.new(0, 0, 0, 64),
		size = UDim2.new(1, 0, 0, 24),
		textColor = if petRec then cProfit else cMuted,
		textSize = 13,
	})

	-- Kiria Companion Card
	local kiriaCard = widgets.createRoundedFrame(container, {
		name = "KiriaCard",
		size = UDim2.new(1, 0, 0, 130),
		position = UDim2.new(0, 0, 0, 320),
		bgColor = cCard,
		borderColor = cAccent,
		cornerRadius = 8,
		padding = 12,
	})
	widgets.createLabel(kiriaCard, {
		text = string.format("Kiria Companion  •  %s (%s)", vm.kiria.rank, vm.kiria.mood),
		size = UDim2.new(1, 0, 0, 20),
		textColor = cBright,
		bold = true,
	})
	widgets.createLabel(kiriaCard, {
		text = vm.kiria.latestMessage or "Ready at the Trade Hub terminal.",
		position = UDim2.new(0, 0, 0, 28),
		size = UDim2.new(1, 0, 0, 74),
		textColor = cText,
		textSize = 13,
	})
end

return Dashboard
