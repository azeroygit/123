--!strict
--[[
	ListingsPage.luau
	Trade Hub Listing Scanner + Smart Listing Management UI controller.
]]

local ListingsPage = {}
ListingsPage.__index = ListingsPage

function ListingsPage.new(deps: { listingScanner: any, listingManager: any, inventoryReader: any })
	local self = setmetatable({}, ListingsPage)
	self._scanner = deps.listingScanner
	self._manager = deps.listingManager
	self._inventory = deps.inventoryReader
	self._filters = { petQuery = "", minProfit = 0, minPctGain = 0, includeIncomplete = false }
	self._manualOfferName = ""
	self._manualAskName = ""
	self._statusMsg = ""
	return self
end

function ListingsPage:setFilters(filters: { [string]: any })
	for k, v in pairs(filters) do
		self._filters[k] = v
	end
end

function ListingsPage:scanNow()
	return self._scanner:scanOnce()
end

function ListingsPage:importListingsJson(jsonText: string)
	return self._scanner:importJson(jsonText)
end

function ListingsPage:getScannedListings()
	return self._scanner:getRankedOpportunities(self._filters)
end

function ListingsPage:createAndPublishDraft(offeredItems: { any }, requestedItems: { any }?, ttlSeconds: number?)
	local draft = self._manager:createDraft(offeredItems, requestedItems, ttlSeconds)
	local ok, err = self._manager:publishListing(draft.id)
	return draft, ok, err
end

function ListingsPage:cancelListing(id: string, confirmed: boolean)
	return self._manager:cancelListing(id, confirmed)
end

function ListingsPage:getManagedListings()
	return self._manager:getAll()
end

function ListingsPage:render(container: any, theme: any, widgets: any)
	if not (container and widgets and widgets.isRobloxGuiAvailable()) then
		return
	end
	widgets.clearChildren(container)
	local opps = self:getScannedListings()
	local managed = self._manager:getAll()
	local cText = theme.toColor3(theme.Colors.TextPrimary)
	local cMuted = theme.toColor3(theme.Colors.TextMuted)
	local cCard = theme.toColor3(theme.Colors.SurfaceAlt)
	local cBorder = theme.toColor3(theme.Colors.Border)
	local cAccent = theme.toColor3(theme.Colors.Accent)
	local cProfit = theme.toColor3(theme.Colors.Profit)
	local cWarn = theme.toColor3(theme.Colors.Warning)

	widgets.createLabel(container, {
		text = string.format("Listings Scanner (%d opportunities) & My Listings (%d)", #opps, #managed),
		size = UDim2.new(1, -130, 0, 22),
		textColor = cText,
		textSize = 15,
		bold = true,
	})

	widgets.createButton(container, {
		text = "Scan Hub Now",
		size = UDim2.new(0, 120, 0, 28),
		position = UDim2.new(1, -120, 0, 0),
		bgColor = cAccent,
		textColor = cText,
		onClick = function()
			local res = self:scanNow()
			self._statusMsg = res.warning or string.format("Scanned %d listings (%d good deals)", res.total, res.goodDeals)
			self:render(container, theme, widgets)
		end,
	})

	-- Manual Listing Ingestion Bar (evaluate any Hub listing manually)
	widgets.createTextBox(container, {
		text = self._manualOfferName,
		placeholder = "They offer (e.g. Frost Dragon)",
		size = UDim2.new(0, 200, 0, 28),
		position = UDim2.new(0, 0, 0, 34),
		bgColor = theme.toColor3(theme.Colors.Background),
		textColor = cText,
		placeholderColor = cMuted,
		borderColor = cBorder,
		onFocusLost = function(txt) self._manualOfferName = txt end,
	})
	widgets.createTextBox(container, {
		text = self._manualAskName,
		placeholder = "They ask (e.g. Shadow Dragon)",
		size = UDim2.new(0, 200, 0, 28),
		position = UDim2.new(0, 208, 0, 34),
		bgColor = theme.toColor3(theme.Colors.Background),
		textColor = cText,
		placeholderColor = cMuted,
		borderColor = cBorder,
		onFocusLost = function(txt) self._manualAskName = txt end,
	})
	widgets.createButton(container, {
		text = "+ Evaluate Listing",
		size = UDim2.new(0, 130, 0, 28),
		position = UDim2.new(0, 416, 0, 34),
		bgColor = cProfit,
		textColor = cText,
		onClick = function()
			if self._manualOfferName ~= "" and self._manualAskName ~= "" then
				self._scanner:ingestListing({
					offeredItems = { { name = self._manualOfferName, fly = true, ride = true } },
					requestedItems = { { name = self._manualAskName, fly = true, ride = true } },
				}, "manual")
				self._statusMsg = "Evaluated manual listing"
				self:render(container, theme, widgets)
			end
		end,
	})

	if self._statusMsg ~= "" then
		widgets.createLabel(container, {
			text = self._statusMsg,
			position = UDim2.new(0, 0, 0, 68),
			size = UDim2.new(1, 0, 0, 18),
			textColor = cWarn,
			textSize = 11,
		})
	end

	local scroll = widgets.createScrollFrame(container, {
		size = UDim2.new(1, 0, 1, -94),
		position = UDim2.new(0, 0, 0, 90),
		gap = 6,
	})

	if #opps == 0 then
		widgets.createLabel(scroll, {
			text = "No listings scanned yet. Click 'Scan Hub Now' or enter a listing above to evaluate AMVGG profit.",
			textColor = cMuted,
		})
	else
		for _, item in ipairs(opps) do
			local card = widgets.createRoundedFrame(scroll, {
				size = UDim2.new(1, -8, 0, 56),
				bgColor = cCard,
				borderColor = if item.listingStatus == "GOOD DEAL" then cProfit else cBorder,
				cornerRadius = 6,
				padding = 8,
			})
			local offName = item.offeredItems[1] and item.offeredItems[1].name or "?"
			local reqName = item.requestedItems[1] and item.requestedItems[1].name or "?"
			widgets.createLabel(card, {
				text = string.format("[%s]  Get: %s (%.2f)  |  Give: %s (%.2f)  |  %+.2f (%+.1f%%)",
					item.listingStatus, offName, item.totalAmvggOffered, reqName, item.totalAmvggRequested, item.estimatedProfit, item.profitPercent),
				size = UDim2.new(1, 0, 0, 20),
				textColor = if item.estimatedProfit >= 0 then cProfit else theme.toColor3(theme.Colors.Loss),
				textSize = 12,
				bold = true,
			})
			widgets.createLabel(card, {
				text = string.format("Risk: %d/100  •  %s", item.riskScore, item.liquidityNote),
				position = UDim2.new(0, 0, 0, 22),
				size = UDim2.new(1, 0, 0, 18),
				textColor = cMuted,
				textSize = 11,
			})
		end
	end
end

return ListingsPage
