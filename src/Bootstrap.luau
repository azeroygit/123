--!strict
--[[
	Bootstrap.luau
	Composition root wiring Core, Values, Inventory, Trading, Kiria, and UI
	using relative module loading with zero globals and clean shutdown.
]]

local Bootstrap = {}

export type EnvironmentAdapters = {
	fs: { exists: (string) -> boolean, read: (string) -> string, write: (string, string) -> (), append: ((string, string) -> ())? }?,
	json: { encode: (any) -> string, decode: (string) -> any }?,
	httpGet: ((string) -> (boolean, number, string))?,
	gameAdapter: any?,
	clockFn: (() -> number)?,
	initialConfig: { [string]: any }?,
	autoStartScheduler: boolean?,
	skipInitialFetch: boolean?,
}

local function makeDefaultFs()
	if type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function" then
		return {
			exists = function(p: string): boolean
				local ok, res = pcall(isfile, p)
				return ok and res == true
			end,
			read = function(p: string): string
				return readfile(p)
			end,
			write = function(p: string, content: string)
				if type(makefolder) == "function" and type(isfolder) == "function" then
					local dir = string.match(p, "^(.+)/[^/]+$")
					if dir and not isfolder(dir) then
						pcall(makefolder, dir)
					end
				end
				writefile(p, content)
			end,
			append = function(p: string, content: string)
				if type(appendfile) == "function" then
					appendfile(p, content)
				end
			end,
		}
	end
	return nil
end

local function makeDefaultJson()
	if type(game) == "userdata" or type(game) == "table" then
		local ok, HttpService = pcall(function()
			return game:GetService("HttpService")
		end)
		if ok and HttpService then
			return {
				encode = function(v: any): string
					return HttpService:JSONEncode(v)
				end,
				decode = function(s: string): any
					return HttpService:JSONDecode(s)
				end,
			}
		end
	end
	return nil
end

local function makeDefaultHttpGet(): ((string) -> (boolean, number, string))?
	local reqFn: any = nil
	if type(request) == "function" then
		reqFn = request
	elseif type(http_request) == "function" then
		reqFn = http_request
	elseif type(syn) == "table" and type(syn.request) == "function" then
		reqFn = syn.request
	end
	if reqFn then
		return function(url: string)
			local ok, resp = pcall(reqFn, { Url = url, Method = "GET" })
			if not ok or type(resp) ~= "table" then
				return false, 0, tostring(resp)
			end
			return true, tonumber(resp.StatusCode) or 0, tostring(resp.Body or "")
		end
	end
	return nil
end

local function makeDefaultGameAdapter()
	if type(game) ~= "userdata" and type(game) ~= "table" then
		return nil
	end
	local ok, ReplicatedStorage = pcall(function()
		return game:GetService("ReplicatedStorage")
	end)
	if not ok or not ReplicatedStorage then
		return nil
	end

	local function kindToName(kind: string): string
		-- Convert e.g. "shadow_dragon" or "halloween_2024_shadow_dragon" -> "Shadow Dragon"
		-- Strip year/event prefixes (e.g. "halloween_2026_stray_cat" -> "Stray Cat")
		local s = tostring(kind or "")
		-- Remove common event/year prefixes
		s = s:gsub("^%a+_%d%d%d%d_", "")
		s = s:gsub("_", " ")
		s = s:gsub("(%a)([%w']*)", function(first, rest)
			return string.upper(first) .. string.lower(rest)
		end)
		return s
	end

	-- Try to get a usable ClientData handle using all known Adopt Me approaches
	local function getClientData(): any?
		-- Method 1: require module directly
		local okM, ClientData = pcall(function()
			return require(
				ReplicatedStorage
					:WaitForChild("ClientModules", 3)
					:WaitForChild("Core", 3)
					:WaitForChild("ClientData", 3)
			)
		end)
		if okM and type(ClientData) == "table" then
			return ClientData
		end

		-- Method 2: try alternate paths
		local paths = {
			{ "ClientModules", "ClientData" },
			{ "Modules", "ClientData" },
			{ "SharedModules", "ClientData" },
		}
		for _, path in ipairs(paths) do
			local ok2, m = pcall(function()
				local cur: any = ReplicatedStorage
				for _, segment in ipairs(path) do
					cur = cur:WaitForChild(segment, 2)
				end
				return require(cur)
			end)
			if ok2 and type(m) == "table" then
				return m
			end
		end
		return nil
	end

	-- Parse inventory from raw table returned by get("inventory") or get_data()
	local function parseInventoryTable(inv: any): { any }
		if type(inv) ~= "table" then return {} end
		local petsTable = type(inv.pets) == "table" and inv.pets or nil
		if not petsTable then
			-- Maybe inv IS the pets table (some versions)
			petsTable = inv
		end
		local out = {}
		for uid, pet in pairs(petsTable) do
			if type(pet) == "table" then
				local props = type(pet.properties) == "table" and pet.properties
				           or type(pet.props) == "table" and pet.props
				           or {}
				-- Some versions store neon/mega directly on pet
				local isNeon = props.neon == true or pet.neon == true
				local isMega = props.mega_neon == true or props.megaNeon == true
				         or pet.mega_neon == true or pet.mega == true
				local isFly  = props.flyable == true or props.fly == true
				         or pet.flyable == true
				local isRide = props.rideable == true or props.ride == true
				         or pet.rideable == true
				local petKind = tostring(pet.kind or pet.id or pet.petId or "Unknown")
				table.insert(out, {
					uid      = tostring(uid),
					name     = kindToName(petKind),
					rawKind  = petKind,
					neon     = isNeon,
					mega     = isMega,
					fly      = isFly,
					ride     = isRide,
					locked   = props.locked == true or pet.locked == true,
					favorite = props.favorite == true or pet.favorite == true,
					age      = tonumber(props.age or pet.age),
				})
			end
		end
		return out
	end

	return {
		readInventory = function()
			-- Step 1: get ClientData module
			local cd = getClientData()
			if not cd then
				error("Adopt Me ClientData module unavailable — not in Adopt Me?")
			end

			local inv = nil

			-- Step 2a: try get_data() first (returns full data snapshot)
			if type(cd.get_data) == "function" then
				local ok2, allData = pcall(cd.get_data, cd)
				if ok2 and type(allData) == "table" then
					inv = allData["inventory"] or allData.inventory
				end
			end

			-- Step 2b: try get("inventory")
			if not inv and type(cd.get) == "function" then
				local ok3, v = pcall(cd.get, cd, "inventory")
				if ok3 and type(v) == "table" then
					inv = v
				end
			end

			-- Step 2c: try direct get_data() without self
			if not inv and type(cd.get_data) == "function" then
				local ok4, v = pcall(cd.get_data)
				if ok4 and type(v) == "table" then
					inv = v["inventory"] or v.inventory
				end
			end

			if not inv then
				error("Could not read inventory from ClientData (tried get_data() and get('inventory'))")
			end

			return parseInventoryTable(inv)
		end,

		-- Fetch Trade Hub listings (returns { listings: {...}, error: string? })
		fetchListings = nil,  -- filled in after TradeHubAdapter is wired
		sendOffer = nil,       -- filled in after TradeHubAdapter is wired
	}
end

function Bootstrap.createApp(requireRelative: (string) -> any, adapters: EnvironmentAdapters?)
	local env = adapters or {}
	local fs = env.fs or makeDefaultFs()
	local json = env.json or makeDefaultJson()
	local httpGet = env.httpGet or makeDefaultHttpGet()
	local gameAdapter = env.gameAdapter or makeDefaultGameAdapter()
	local clockFn = env.clockFn or os.time

	-- Core
	local Logger = requireRelative("Core/Logger")
	local EventBus = requireRelative("Core/EventBus")
	local StateManager = requireRelative("Core/StateManager")
	local ErrorHandler = requireRelative("Core/ErrorHandler")
	local TaskScheduler = requireRelative("Core/TaskScheduler")
	local ConfigManager = requireRelative("Core/ConfigManager")

	local logger = Logger.new({ level = "INFO", fs = fs })
	local eventBus = EventBus.new(logger)
	local state = StateManager.new(eventBus)
	local errorHandler = ErrorHandler.new(logger, eventBus)
	local config = ConfigManager.new({
		initial = env.initialConfig,
		json = json,
		fs = fs,
		logger = logger,
		eventBus = eventBus,
	})
	config:loadFromFile()
	logger:setLevel(tostring(config:get("Data.LogLevel") or "INFO"))

	local scheduler = TaskScheduler.new(logger, 0.5)

	-- Values (AMVGG ONLY + CSV fallback)
	local ValueParser = requireRelative("Values/ValueParser")
	local ValueValidator = requireRelative("Values/ValueValidator")
	local ValueCache = requireRelative("Values/ValueCache")
	local AMVGGProvider = requireRelative("Values/AMVGGProvider")
	local ValueEngine = requireRelative("Values/ValueEngine")
	local CSVLoader = requireRelative("Values/CSVLoader")

	local valueCache = ValueCache.new({
		filePath = config:get("AMVGG.CacheFile"),
		fs = fs,
		json = json,
		validator = ValueValidator,
		logger = logger,
	})

	-- Load CSV as instant offline fallback (sourced from AMVGG)
	local csvLoader = CSVLoader.new({
		fs = fs,
		logger = logger,
		csvPath = config:get("Data.CSVPath") or "pets_ridepots.csv",
	})
	local csvLoaded = csvLoader:load()
	if csvLoaded then
		csvLoader:seedCache(valueCache)
		logger:info("[Bootstrap] CSV fallback: " .. csvLoader:count() .. " pets seeded into cache")
	end
	local amvggProvider = AMVGGProvider.new({
		config = config,
		cache = valueCache,
		parser = ValueParser,
		validator = ValueValidator,
		errorHandler = errorHandler,
		eventBus = eventBus,
		state = state,
		logger = logger,
		httpGet = httpGet,
		jsonDecode = if json then json.decode else function() error("No JSON decoder") end,
		clockFn = clockFn,
	})
	local valueEngine = ValueEngine.new(valueCache, ValueValidator, config)

	-- Inventory
	local PetDatabase = requireRelative("Inventory/PetDatabase")
	local InventoryReader = requireRelative("Inventory/InventoryReader")
	local InventoryValuator = requireRelative("Inventory/InventoryValuator")

	local petDatabase = PetDatabase.new(valueCache, ValueValidator)
	local inventoryReader = InventoryReader.new({
		filePath = config:get("Data.InventoryFile"),
		fs = fs,
		json = json,
		eventBus = eventBus,
		logger = logger,
		gameAdapter = gameAdapter,
	})
	inventoryReader:load()
	if gameAdapter then
		pcall(function()
			inventoryReader:syncFromGame()
		end)
	end
	local inventoryValuator = InventoryValuator.new(inventoryReader, valueEngine)

	-- Trading
	local ProfitCalculator = requireRelative("Trading/ProfitCalculator")
	local TradeEvaluator = requireRelative("Trading/TradeEvaluator")
	local ListingScanner = requireRelative("Trading/ListingScanner")
	local OfferAnalyzer = requireRelative("Trading/OfferAnalyzer")
	local ListingManager = requireRelative("Trading/ListingManager")
	local OfferTimer = requireRelative("Trading/OfferTimer")
	local OfferQueue = requireRelative("Trading/OfferQueue")
	local TradeHistory = requireRelative("Trading/TradeHistory")
	local TradeHubAdapter = requireRelative("Trading/TradeHubAdapter")

	-- Wire Trade Hub adapter into gameAdapter
	local tradeHubAdapter = TradeHubAdapter.new({ logger = logger, eventBus = eventBus })
	if gameAdapter and tradeHubAdapter:isAvailable() then
		gameAdapter.fetchListings = function()
			return tradeHubAdapter:fetchListings()
		end
		gameAdapter.sendOffer = function(targetUserId, offeredItems, requestedItems)
			return tradeHubAdapter:sendOffer(tostring(targetUserId), offeredItems, requestedItems)
		end
		logger:info("[Bootstrap] Trade Hub adapter wired: listings + offer sending enabled")
	elseif gameAdapter then
		logger:warn("[Bootstrap] Trade Hub remotes not found — listing scan will use fallback only")
	end

	local tradeEvaluator = TradeEvaluator.new(valueEngine, ProfitCalculator)
	local listingScanner = ListingScanner.new({
		tradeEvaluator = tradeEvaluator,
		config = config,
		eventBus = eventBus,
		state = state,
		logger = logger,
		json = json,
		gameAdapter = gameAdapter,
		clockFn = clockFn,
	})
	local offerAnalyzer = OfferAnalyzer.new({
		inventoryReader = inventoryReader,
		valueEngine = valueEngine,
		profitCalculator = ProfitCalculator,
		config = config,
	})
	local listingManager = ListingManager.new({
		valueEngine = valueEngine,
		config = config,
		eventBus = eventBus,
		state = state,
		logger = logger,
		clockFn = clockFn,
	})
	local offerTimer = OfferTimer.new(config, clockFn)
	local offerQueue = OfferQueue.new({
		valueEngine = valueEngine,
		offerTimer = offerTimer,
		config = config,
		eventBus = eventBus,
		state = state,
		logger = logger,
		clockFn = clockFn,
	})
	local tradeHistory = TradeHistory.new({
		filePath = config:get("Data.AnalyticsFile"),
		fs = fs,
		json = json,
		eventBus = eventBus,
		clockFn = clockFn,
	})
	tradeHistory:load()

	-- Kiria Companion
	local Personality = requireRelative("Kiria/Personality")
	local Memory = requireRelative("Kiria/Memory")
	local Reactions = requireRelative("Kiria/Reactions")
	local Companion = requireRelative("Kiria/Companion")

	local kiriaMemory = Memory.new({
		filePath = config:get("Data.KiriaMemoryFile"),
		fs = fs,
		json = json,
		clockFn = clockFn,
	})
	kiriaMemory:load()
	local kiria = Companion.new({
		personality = Personality,
		memory = kiriaMemory,
		reactions = Reactions,
		eventBus = eventBus,
		config = config,
		clockFn = clockFn,
	})

	-- UI
	local Theme = requireRelative("UI/Components/Theme")
	local Widgets = requireRelative("UI/Components/Widgets")
	local Notifications = requireRelative("UI/Notifications")
	local Dashboard = requireRelative("UI/Dashboard")
	local ListingsPage = requireRelative("UI/ListingsPage")
	local OffersPage = requireRelative("UI/OffersPage")
	local InventoryPage = requireRelative("UI/InventoryPage")
	local AnalyticsPage = requireRelative("UI/AnalyticsPage")
	local SettingsPage = requireRelative("UI/SettingsPage")
	local MainWindow = requireRelative("UI/MainWindow")

	local notifications = Notifications.new({ eventBus = eventBus, config = config, clockFn = clockFn })
	local pages = {
		Dashboard = Dashboard.new({
			amvggProvider = amvggProvider,
			inventoryValuator = inventoryValuator,
			listingScanner = listingScanner,
			offerQueue = offerQueue,
			tradeHistory = tradeHistory,
			kiria = kiria,
		}),
		Listings = ListingsPage.new({
			listingScanner = listingScanner,
			listingManager = listingManager,
			inventoryReader = inventoryReader,
		}),
		Offers = OffersPage.new({
			offerAnalyzer = offerAnalyzer,
			offerQueue = offerQueue,
			tradeHistory = tradeHistory,
		}),
		Inventory = InventoryPage.new({
			inventoryReader = inventoryReader,
			inventoryValuator = inventoryValuator,
		}),
		Analytics = AnalyticsPage.new({
			tradeHistory = tradeHistory,
			listingScanner = listingScanner,
			offerQueue = offerQueue,
			inventoryValuator = inventoryValuator,
		}),
		Settings = SettingsPage.new({
			config = config,
			amvggProvider = amvggProvider,
			scheduler = scheduler,
			logger = logger,
		}),
	}
	local mainWindow = MainWindow.new({
		theme = Theme,
		widgets = Widgets,
		pages = pages,
		notifications = notifications,
		eventBus = eventBus,
		config = config,
	})

	-- Initialize AMVGG cache & background jobs
	amvggProvider:initFromCache()
	kiria:startSession()

	scheduler:addJob("amvgg_refresh", tonumber(config:get("AMVGG.RefreshIntervalSeconds")) or 1800, function()
		amvggProvider:refresh({ force = false })
	end)
	scheduler:addJob("listing_stale_check", 5, function()
		listingManager:checkStaleListings()
	end)
	scheduler:addJob("offer_timer_check", 5, function()
		local res = offerQueue:checkPendingTimers()
		for _ in ipairs(res.expired) do
			tradeHistory:recordOfferOutcome("EXPIRED")
		end
	end)

	-- ── AUTO TRADE LOOP ──────────────────────────────────────────────────────
	-- Every scan_interval seconds: sync inventory → scan listings → auto-send offers
	local autoMode = true  -- can be toggled via config or UI
	local offersSentThisSession = 0
	local lastAutoScanTime = 0

	local function runAutoTradeCycle()
		if not autoMode then return end
		lastAutoScanTime = clockFn()

		-- 1. Sync inventory from game
		if gameAdapter and type(gameAdapter.readInventory) == "function" then
			local okInv = pcall(function() inventoryReader:syncFromGame() end)
			if not okInv then
				logger:warn("[AutoLoop] Inventory sync failed")
			end
		end

		-- 2. Scan Trade Hub listings
		local scanResult = listingScanner:scanOnce()
		local opportunities = listingScanner:getRankedOpportunities({
			minPctGain = tonumber(config:get("Trading.MinProfitPct")) or 5,
			minProfit  = 0,
		})

		-- 3. For each GOOD DEAL: generate combo offer and auto-send
		local maxOffersPerCycle = tonumber(config:get("Trading.MaxOffersPerCycle")) or 3
		local sent = 0
		for _, opp in ipairs(opportunities) do
			if sent >= maxOffersPerCycle then break end
			if opp.verdict == "GOOD DEAL" or opp.verdict == "GREAT DEAL" then
				-- Generate offer combos from owned inventory
				local res = offerAnalyzer:generateCandidates(opp.requestedItems or {})
				if res and #res.candidates > 0 then
					local best = res.candidates[1]
					if gameAdapter and type(gameAdapter.sendOffer) == "function" then
						local offerResult = gameAdapter.sendOffer(
							opp.sellerId or "",
							best.offeredPetIds or {},
							opp.requestedItems or {}
						)
						if offerResult and offerResult.success then
							sent += 1
							offersSentThisSession += 1
							tradeHistory:recordOfferSent({
								targetPet = table.concat(opp.requestedItems or {}, ", "),
								offeredPets = best.offeredPetIds or {},
								profit = best.profit,
								pctGain = best.pctGain,
							})
							eventBus:emit("offer:auto_sent", {
								sellerId = opp.sellerId,
								requestedItems = opp.requestedItems,
								offeredPets = best.offeredPetIds,
								profit = best.profit,
							})
							logger:info(string.format(
								"[AutoLoop] Sent offer #%d (profit=+%.2f, +%.1f%%) for %s",
								offersSentThisSession, best.profit or 0, best.pctGain or 0,
								table.concat(opp.requestedItems or {}, "+")
							))
						end
					else
						-- No live offer remote — queue for manual review
						offerQueue:addOffer({
							targetPets   = opp.requestedItems or {},
							offeredPets  = best.offeredPetIds or {},
							profit       = best.profit,
							pctGain      = best.pctGain,
							sellerId     = opp.sellerId or "",
						})
					end
				end
			end
		end

		state:set("autoLoop.lastScanAt", lastAutoScanTime)
		state:set("autoLoop.offersSentTotal", offersSentThisSession)
		state:set("autoLoop.opportunitiesFound", #opportunities)
	end

	local scanInterval = tonumber(config:get("Trading.ScanIntervalSeconds")) or 15
	scheduler:addJob("auto_trade_loop", scanInterval, runAutoTradeCycle)

	-- expose toggle for UI
	state:set("autoLoop.enabled", true)
	state:set("autoLoop.offersSentTotal", 0)

	if not env.skipInitialFetch and httpGet then
		if type(task) == "table" and type(task.spawn) == "function" then
			task.spawn(function()
				amvggProvider:refresh({ force = true })
			end)
		else
			amvggProvider:refresh({ force = true })
		end
	end

	if env.autoStartScheduler then
		scheduler:start()
	end

	local app = {
		core = {
			logger = logger,
			eventBus = eventBus,
			state = state,
			errorHandler = errorHandler,
			scheduler = scheduler,
			config = config,
		},
		values = {
			cache = valueCache,
			provider = amvggProvider,
			engine = valueEngine,
			parser = ValueParser,
			validator = ValueValidator,
			csvLoader = csvLoader,
		},
		inventory = {
			database = petDatabase,
			reader = inventoryReader,
			valuator = inventoryValuator,
		},
		trading = {
			profitCalculator = ProfitCalculator,
			evaluator = tradeEvaluator,
			scanner = listingScanner,
			offerAnalyzer = offerAnalyzer,
			listingManager = listingManager,
			offerTimer = offerTimer,
			offerQueue = offerQueue,
			history = tradeHistory,
			tradeHubAdapter = tradeHubAdapter,
		},
		kiria = kiria,
		ui = {
			theme = Theme,
			widgets = Widgets,
			notifications = notifications,
			pages = pages,
			window = mainWindow,
		},
		autoLoop = {
			getEnabled = function() return state:get("autoLoop.enabled") end,
			setEnabled = function(v: boolean)
				autoMode = v
				state:set("autoLoop.enabled", v)
				logger:info("[AutoLoop] " .. (v and "ENABLED" or "DISABLED"))
			end,
			getStats = function()
				return {
					offersSent = state:get("autoLoop.offersSentTotal") or 0,
					lastScanAt = state:get("autoLoop.lastScanAt") or 0,
					opportunities = state:get("autoLoop.opportunitiesFound") or 0,
				}
			end,
		},
	}

	function app.shutdown()
		scheduler:destroy()
		mainWindow:destroy()
		notifications:destroy()
		kiria:destroy()
		state:destroy()
		eventBus:destroy()
		logger:destroy()
	end

	return app
end

return Bootstrap
