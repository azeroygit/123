--!strict
--[[
	IntegrationTests.luau
	End-to-end integration test across Bootstrap, AMVGG import, Inventory,
	ListingScanner, OfferEngine, OfferQueue, TradeHistory, Kiria, and UI pages.
]]

local function run(requireRelative: (string) -> any, json: any)
	local Bootstrap = requireRelative("Bootstrap")

	local passed, failed = 0, 0
	local function check(name: string, cond: boolean, detail: string?)
		if cond then
			passed += 1
		else
			failed += 1
			error(string.format("[IntegrationTests] FAIL %s: %s", name, tostring(detail or "")))
		end
	end

	local now = 5000
	local memFiles: { [string]: string } = {}
	local fs = {
		exists = function(p: string) return memFiles[p] ~= nil end,
		read = function(p: string) return memFiles[p] end,
		write = function(p: string, c: string) memFiles[p] = c end,
	}

	local app = Bootstrap.createApp(requireRelative, {
		fs = fs,
		json = json,
		clockFn = function() return now end,
		skipInitialFetch = true,
		autoStartScheduler = false,
	})

	-- 1. Import AMVGG dataset
	local okImport = app.values.provider:importPayload(json.encode({
		pets = {
			{ id = "1", name = "Frost Dragon", regularValue = "125", regularDemand = "High" },
			{ id = "2", name = "Shadow Dragon", regularValue = "100", regularDemand = "High" },
		},
	}))
	check("AMVGG payload imported", okImport == true)

	-- 2. Add pet to Inventory via UI InventoryPage
	local invPage = app.ui.pages.Inventory
	invPage:addPet({ name = "Shadow Dragon", fly = true, ride = true })
	local invVm = invPage:getViewModel()
	check("Inventory UI shows 100 AMVGG", invVm.totalValue == 100)

	-- 3. Import listing via UI ListingsPage
	local lstPage = app.ui.pages.Listings
	local okList = lstPage:importListingsJson(json.encode({
		{
			listingId = "HUB_99",
			offeredItems = { { name = "Frost Dragon", fly = true, ride = true } },
			requestedItems = { { name = "Shadow Dragon", fly = true, ride = true } },
		},
	}))
	check("Listing imported", okList == true)
	check("1 GOOD DEAL ranked", #lstPage:getScannedListings() == 1)

	-- 4. Generate offer via OffersPage, queue it, and confirm trade
	local offPage = app.ui.pages.Offers
	local gen = offPage:generateForTarget({ { name = "Frost Dragon", fly = true, ride = true } })
	check("Generated 1 offer candidate", #gen.candidates == 1)
	local queued = offPage:queueCandidate(gen.candidates[1], "HUB_99")
	check("Candidate queued", queued ~= nil)

	local okConfirm = offPage:confirmAcceptOffer(queued.offerId, true)
	check("Confirmed trade accepted", okConfirm == true)

	-- 5. Verify Analytics & Kiria & Dashboard reflect the real confirmed trade
	local analyticsVm = app.ui.pages.Analytics:getViewModel()
	check("Confirmed profit is 25", analyticsVm.confirmedProfit == 25)
	local kiriaStatus = app.kiria:getStatus()
	check("Kiria recorded 1 trade", kiriaStatus.trades == 1)
	local dashVm = app.ui.pages.Dashboard:getViewModel()
	check("Dashboard confirmedProfit is 25", dashVm.confirmedProfit == 25)

	-- 6. Navigation & shutdown
	check("Navigate to Analytics", app.ui.window:navigate("Analytics") == true)
	app.shutdown()
	check("Scheduler stopped cleanly", not app.core.scheduler:isRunning())

	return { passed = passed, failed = failed }
end

return { run = run }
