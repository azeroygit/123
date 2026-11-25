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
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
	widgets.createLabel(container, {
		text = string.format("Offers Queue (%d pending)  |  Generated Candidates: %d", self._queue:getPendingCount(), #self._lastCandidates),
		textColor = theme.toColor3(theme.Colors.TextPrimary),
		bold = true,
	})
end

return OffersPage
