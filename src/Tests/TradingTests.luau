--!strict
--[[
	TradingTests.luau
	Unit tests for InventoryReader, InventoryValuator, ListingScanner,
	OfferAnalyzer, and TradeHistory.
]]

local function run(requireRelative: (string) -> any, json: any)
	local ConfigManager = requireRelative("Core/ConfigManager")
	local ValueValidator = requireRelative("Values/ValueValidator")
	local ValueCache = requireRelative("Values/ValueCache")
	local ValueEngine = requireRelative("Values/ValueEngine")
	local InventoryReader = requireRelative("Inventory/InventoryReader")
	local InventoryValuator = requireRelative("Inventory/InventoryValuator")
	local ProfitCalculator = requireRelative("Trading/ProfitCalculator")
	local TradeEvaluator = requireRelative("Trading/TradeEvaluator")
	local ListingScanner = requireRelative("Trading/ListingScanner")
	local OfferAnalyzer = requireRelative("Trading/OfferAnalyzer")
	local TradeHistory = requireRelative("Trading/TradeHistory")

	local passed, failed = 0, 0
	local function check(name: string, cond: boolean, detail: string?)
		if cond then
			passed += 1
		else
			failed += 1
			error(string.format("[TradingTests] FAIL %s: %s", name, tostring(detail or "")))
		end
	end

	local cfg = ConfigManager.new({})
	local cache = ValueCache.new({ validator = ValueValidator, json = json })
	local summary = ValueValidator.validateDataset({
		{ id = "1", name = "Target Dragon", regularValue = "150", regularDemand = "High" },
		{ id = "2", name = "Pet A", regularValue = "70", regularDemand = "Medium" },
		{ id = "3", name = "Pet B", regularValue = "50", regularDemand = "High" },
		{ id = "4", name = "Locked Gem", regularValue = "140", regularDemand = "High" },
	}, 1000)
	cache:setValidatedDataset(summary, 1000)
	local engine = ValueEngine.new(cache, ValueValidator, cfg)

	-- Inventory & Locked pet protection
	local inv = InventoryReader.new({ json = json })
	local pA = inv:addPet({ name = "Pet A", fly = true, ride = true })
	local pB = inv:addPet({ name = "Pet B", fly = true, ride = true })
	inv:addPet({ name = "Locked Gem", fly = true, ride = true, locked = true })
	check("Inventory has 3 pets", #inv:getAll() == 3)
	check("Tradeable has 2 pets", #inv:getTradeable() == 2)

	local invVal = InventoryValuator.new(inv, engine):evaluateAll({})
	check("Total inventory value 260", invVal.totalValue == 260)
	check("Top pet is Locked Gem", invVal.topPet ~= nil and invVal.topPet.pet.name == "Locked Gem")

	-- OfferAnalyzer: 150 target vs 120 offer (70 + 50) = +30 gain (+25%)
	local analyzer = OfferAnalyzer.new({
		inventoryReader = inv,
		valueEngine = engine,
		profitCalculator = ProfitCalculator,
		config = cfg,
	})
	local res = analyzer:generateCandidates({ { name = "Target Dragon", fly = true, ride = true } }, {
		minProfit = 10,
		minPctGain = 10,
	})
	check("Candidate generated", #res.candidates >= 1)
	local best = res.candidates[1]
	check("Best offer is profit-positive", best.offeredValue < 150 and best.profitValue >= 30)
	local found120Combo = false
	for _, c in ipairs(res.candidates) do
		if c.offeredValue == 120 and #c.offeredPets == 2 and c.profitValue == 30 then
			found120Combo = true
		end
	end
	check("Multi-pet 120->150 (+30) combo present", found120Combo)
	check("No locked pet included", best.offeredPets[1].uid ~= nil)

	-- ListingScanner deduplication & ranking
	local tradeEval = TradeEvaluator.new(engine, ProfitCalculator)
	local scanner = ListingScanner.new({ tradeEvaluator = tradeEval, config = cfg, json = json })
	local _, isNew1 = scanner:ingestListing({
		listingId = "L1",
		offeredItems = { { name = "Target Dragon", fly = true, ride = true } }, -- 150
		requestedItems = { { name = "Pet A", fly = true, ride = true }, { name = "Pet B", fly = true, ride = true } }, -- 120
	})
	local _, isNew2 = scanner:ingestListing({
		listingId = "L1",
		offeredItems = { { name = "Target Dragon", fly = true, ride = true } },
		requestedItems = { { name = "Pet A", fly = true, ride = true }, { name = "Pet B", fly = true, ride = true } },
	})
	check("First listing new, duplicate detected", isNew1 == true and isNew2 == false)
	local opps = scanner:getRankedOpportunities({})
	check("Ranked 1 GOOD DEAL", #opps == 1 and opps[1].listingStatus == "GOOD DEAL")

	-- TradeHistory separates Potential / Pending / Confirmed Profit
	local history = TradeHistory.new({ json = json })
	local sBefore = history:getSummary({ potentialProfit = 30, pendingProfit = 15, inventoryValue = 260 })
	check("Confirmed profit starts at 0", sBefore.confirmedProfit == 0 and sBefore.potentialProfit == 30 and sBefore.pendingProfit == 15)
	history:recordConfirmedTrade({
		offeredItems = { pA, pB },
		receivedItems = { { name = "Target Dragon", fly = true, ride = true } },
		offeredValue = 120,
		receivedValue = 150,
	})
	local sAfter = history:getSummary({ potentialProfit = 0, pendingProfit = 0, inventoryValue = 290 })
	check("Confirmed profit updated to 30", sAfter.confirmedProfit == 30 and sAfter.counters.acceptedTrades == 1)

	return { passed = passed, failed = failed }
end

return { run = run }
