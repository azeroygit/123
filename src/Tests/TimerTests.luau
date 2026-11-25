--!strict
--[[
	TimerTests.luau
	Unit tests for ListingManager stale timers and OfferTimer/OfferQueue
	response monitoring, expiration, and mandatory user confirmation.
]]

local function run(requireRelative: (string) -> any, json: any)
	local ConfigManager = requireRelative("Core/ConfigManager")
	local ValueValidator = requireRelative("Values/ValueValidator")
	local ValueCache = requireRelative("Values/ValueCache")
	local ValueEngine = requireRelative("Values/ValueEngine")
	local ListingManager = requireRelative("Trading/ListingManager")
	local OfferTimer = requireRelative("Trading/OfferTimer")
	local OfferQueue = requireRelative("Trading/OfferQueue")

	local passed, failed = 0, 0
	local function check(name: string, cond: boolean, detail: string?)
		if cond then
			passed += 1
		else
			failed += 1
			error(string.format("[TimerTests] FAIL %s: %s", name, tostring(detail or "")))
		end
	end

	local now = 1000
	local clockFn = function()
		return now
	end

	local cfg = ConfigManager.new({})
	local cache = ValueCache.new({ validator = ValueValidator, json = json })
	cache:setValidatedDataset(ValueValidator.validateDataset({
		{ id = "1", name = "Pet A", regularValue = "100" },
		{ id = "2", name = "Pet B", regularValue = "130" },
	}, now), now)
	local engine = ValueEngine.new(cache, ValueValidator, cfg)

	-- 1. ListingManager stale detection at 60s default
	local lm = ListingManager.new({ valueEngine = engine, config = cfg, clockFn = clockFn })
	local draft = lm:createDraft({ { name = "Pet A", fly = true, ride = true } }, { { name = "Pet B", fly = true, ride = true } }, 60)
	local okPub = lm:publishListing(draft.id)
	check("Listing published", okPub == true)

	now = 1030
	check("Not stale at 30s", #lm:checkStaleListings() == 0)

	now = 1065
	local stale = lm:checkStaleListings()
	check("Stale at 65s", #stale == 1 and stale[1].status == "STALE")

	-- Cancel requires explicit confirmation
	local okCancelNo = lm:cancelListing(draft.id, false)
	check("Cancel blocked without confirmation", okCancelNo == false)
	local okCancelYes = lm:cancelListing(draft.id, true)
	check("Cancel succeeds with confirmation", okCancelYes == true and draft.status == "CANCELLED")

	-- 2. OfferTimer & OfferQueue lifecycle
	local timer = OfferTimer.new(cfg, clockFn)
	local queue = OfferQueue.new({ valueEngine = engine, offerTimer = timer, config = cfg, clockFn = clockFn })

	now = 2000
	local off, err = queue:enqueue({
		listingId = "LST_1",
		offeredItems = { { name = "Pet A", fly = true, ride = true, uid = "u1" } },
		requestedItems = { { name = "Pet B", fly = true, ride = true } },
		expirationSeconds = 120,
	})
	check("Offer enqueued", off ~= nil and err == nil)

	-- Duplicate offer prevention
	local dup, dupErr = queue:enqueue({
		listingId = "LST_1",
		offeredItems = { { name = "Pet A", fly = true, ride = true, uid = "u1" } },
		requestedItems = { { name = "Pet B", fly = true, ride = true } },
	})
	check("Duplicate offer prevented", dup == nil and dupErr ~= nil)

	-- Cannot accept without user confirmation
	local okAcceptNo = queue:updateStatus(off.offerId, "ACCEPTED", { userConfirmed = false })
	check("Accept blocked without confirmation", okAcceptNo == false)

	-- No-response notification after 45s default
	now = 2050
	local check1 = queue:checkPendingTimers()
	check("No-response triggered at 50s", #check1.awaitingResponse == 1 and #check1.expired == 0)

	-- Expiration at 120s
	now = 2125
	local check2 = queue:checkPendingTimers()
	check("Expired at 125s", #check2.expired == 1 and off.status == "EXPIRED")

	return { passed = passed, failed = failed }
end

return { run = run }
