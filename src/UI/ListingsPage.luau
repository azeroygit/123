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
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
	local opps = self:getScannedListings()
	widgets.createLabel(container, {
		text = string.format("Listings Scanner (%d opportunities) & Active Listings (%d)", #opps, #self._manager:getActive()),
		textColor = theme.toColor3(theme.Colors.TextPrimary),
		bold = true,
	})
	widgets.createButton(container, {
		text = "Scan Hub Now",
		position = UDim2.new(0, 0, 0, 32),
		bgColor = theme.toColor3(theme.Colors.Accent),
		textColor = theme.toColor3(theme.Colors.TextPrimary),
		onClick = function()
			self:scanNow()
		end,
	})
end

return ListingsPage
