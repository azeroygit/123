--!strict
--[[
	OffersPage.luau
	Offer Engine candidate generator + Offer Queue management with mandatory
	user confirmation for final trade acceptance.
]]

local OffersPage = {}
OffersPage.__index = OffersPage

function OffersPage.new(deps: { offerAnalyzer: any, offerQueue: any, tradeHistory: any })
	local self = setmetatable({}, OffersPage)
	self._analyzer = deps.offerAnalyzer
	self._queue = deps.offerQueue
	self._history = deps.tradeHistory
	self._lastCandidates = {} :: { any }
	self._targetPetName = "Frost Dragon"
	self._statusMsg = ""
	return self
end

function OffersPage:generateForTarget(targetItems: { any }, options: { [string]: any }?)
	local reserved = self._queue:getReservedPetUids()
	local opts = if options then table.clone(options) else {}
	opts.reservedUids = reserved
	local res = self._analyzer:generateCandidates(targetItems, opts)
	self._lastCandidates = res.candidates
	return res
end

function OffersPage:queueCandidate(candidate: any, listingId: string?)
	local rec, err = self._queue:enqueue({
		listingId = listingId,
		direction = "OUTGOING",
		offeredItems = candidate.offeredPets,
		requestedItems = candidate.targetItems,
	})
	if rec then
		self._history:recordOfferOutcome("SUBMITTED")
	end
	return rec, err
end

function OffersPage:confirmAcceptOffer(offerId: string, userConfirmed: boolean): (boolean, string?)
	local ok, err = self._queue:updateStatus(offerId, "ACCEPTED", { userConfirmed = userConfirmed })
	if not ok then
		return false, err
	end
	for _, off in ipairs(self._queue:getAll()) do
		if off.offerId == offerId then
			self._history:recordConfirmedTrade({
				id = off.offerId,
				offeredItems = off.offeredItems,
				receivedItems = off.requestedItems,
				offeredValue = off.evaluation.yourValue,
				receivedValue = off.evaluation.theirValue,
				source = "manual_confirmed",
			})
			break
		end
	end
	return true, nil
end

function OffersPage:declineOffer(offerId: string)
	local ok, err = self._queue:updateStatus(offerId, "DECLINED")
	if ok then
		self._history:recordOfferOutcome("DECLINED")
	end
	return ok, err
end

function OffersPage:cancelOffer(offerId: string)
	local ok, err = self._queue:updateStatus(offerId, "CANCELLED")
	if ok then
		self._history:recordOfferOutcome("CANCELLED")
	end
	return ok, err
end

function OffersPage:getOffers()
	return self._queue:getAll()
end

function OffersPage:render(container: any, theme: any, widgets: any)
	if not (container and widgets and widgets.isRobloxGuiAvailable()) then
		return
	end
	widgets.clearChildren(container)
	local cText = theme.toColor3(theme.Colors.TextPrimary)
	local cMuted = theme.toColor3(theme.Colors.TextMuted)
	local cCard = theme.toColor3(theme.Colors.SurfaceAlt)
	local cBorder = theme.toColor3(theme.Colors.Border)
	local cAccent = theme.toColor3(theme.Colors.Accent)
	local cProfit = theme.toColor3(theme.Colors.Profit)
	local cLoss = theme.toColor3(theme.Colors.Loss)

	widgets.createLabel(container, {
		text = string.format("Offers Engine & Queue (%d pending  |  %d candidates)", self._queue:getPendingCount(), #self._lastCandidates),
		size = UDim2.new(1, 0, 0, 22),
		textColor = cText,
		textSize = 15,
		bold = true,
	})

	widgets.createTextBox(container, {
		text = self._targetPetName,
		placeholder = "Target pet (e.g. Frost Dragon)...",
		size = UDim2.new(0, 220, 0, 30),
		position = UDim2.new(0, 0, 0, 32),
		bgColor = theme.toColor3(theme.Colors.Background),
		textColor = cText,
		placeholderColor = cMuted,
		borderColor = cBorder,
		onFocusLost = function(txt) self._targetPetName = txt end,
	})

	widgets.createButton(container, {
		text = "Generate Offers",
		size = UDim2.new(0, 140, 0, 30),
		position = UDim2.new(0, 228, 0, 32),
		bgColor = cAccent,
		textColor = cText,
		onClick = function()
			local res = self:generateForTarget({ { name = self._targetPetName, fly = true, ride = true } })
			self._statusMsg = res.reason or string.format("Generated %d profit-positive candidates", #res.candidates)
			self:render(container, theme, widgets)
		end,
	})

	if self._statusMsg ~= "" then
		widgets.createLabel(container, {
			text = self._statusMsg,
			position = UDim2.new(0, 378, 0, 36),
			size = UDim2.new(1, -378, 0, 22),
			textColor = cMuted,
			textSize = 11,
		})
	end

	local scroll = widgets.createScrollFrame(container, {
		size = UDim2.new(1, 0, 1, -74),
		position = UDim2.new(0, 0, 0, 70),
		gap = 6,
	})

	for idx, cand in ipairs(self._lastCandidates) do
		local row = widgets.createRoundedFrame(scroll, {
			size = UDim2.new(1, -8, 0, 50),
			bgColor = cCard,
			borderColor = cAccent,
			cornerRadius = 6,
			padding = 8,
		})
		local names = {}
		for _, p in ipairs(cand.offeredPets) do
			table.insert(names, p.name)
		end
		widgets.createLabel(row, {
			text = string.format("Candidate #%d: Offer %s (%.2f) -> %.2f  |  %+.2f (%+.1f%%)",
				idx, table.concat(names, " + "), cand.offeredValue, cand.targetValue, cand.profitValue, cand.profitPercent),
			size = UDim2.new(1, -110, 0, 32),
			textColor = cProfit,
			textSize = 12,
		})
		widgets.createButton(row, {
			text = "Queue Offer",
			size = UDim2.new(0, 100, 0, 28),
			position = UDim2.new(1, -100, 0, 2),
			bgColor = cAccent,
			textColor = cText,
			onClick = function()
				local _, err = self:queueCandidate(cand)
				self._statusMsg = err or "Offer queued for confirmation"
				self:render(container, theme, widgets)
			end,
		})
	end

	local offers = self._queue:getAll()
	if #offers == 0 and #self._lastCandidates == 0 then
		widgets.createLabel(scroll, {
			text = "No queued offers yet. Add pets in Inventory, then enter a target pet above and click 'Generate Offers'.",
			textColor = cMuted,
		})
		return
	end

	for _, off in ipairs(offers) do
		local row = widgets.createRoundedFrame(scroll, {
			size = UDim2.new(1, -8, 0, 48),
			bgColor = cCard,
			borderColor = cBorder,
			cornerRadius = 6,
			padding = 8,
		})
		widgets.createLabel(row, {
			text = string.format("[%s] %s  |  Profit: %+.2f (%+.1f%%)",
				off.status, off.offerId, off.profitValue, off.profitPercent),
			size = UDim2.new(1, -220, 0, 28),
			textColor = cText,
			textSize = 12,
		})
		if off.status == "PENDING" then
			widgets.createButton(row, {
				text = "Confirm",
				size = UDim2.new(0, 72, 0, 26),
				position = UDim2.new(1, -214, 0, 2),
				bgColor = cProfit,
				textColor = cText,
				onClick = function()
					self:confirmAcceptOffer(off.offerId, true)
					self:render(container, theme, widgets)
				end,
			})
			widgets.createButton(row, {
				text = "Decline",
				size = UDim2.new(0, 68, 0, 26),
				position = UDim2.new(1, -138, 0, 2),
				bgColor = cLoss,
				textColor = cText,
				onClick = function()
					self:declineOffer(off.offerId)
					self:render(container, theme, widgets)
				end,
			})
			widgets.createButton(row, {
				text = "Cancel",
				size = UDim2.new(0, 64, 0, 26),
				position = UDim2.new(1, -66, 0, 2),
				bgColor = theme.toColor3(theme.Colors.Background),
				textColor = cText,
				onClick = function()
					self:cancelOffer(off.offerId)
					self:render(container, theme, widgets)
				end,
			})
		end
	end
end

return OffersPage
