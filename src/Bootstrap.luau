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

function Bootstrap.createApp(requireRelative: (string) -> any, adapters: EnvironmentAdapters?)
	local env = adapters or {}
	local fs = env.fs or makeDefaultFs()
	local json = env.json or makeDefaultJson()
	local httpGet = env.httpGet or makeDefaultHttpGet()
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

	-- Values (AMVGG ONLY)
	local ValueParser = requireRelative("Values/ValueParser")
	local ValueValidator = requireRelative("Values/ValueValidator")
	local ValueCache = requireRelative("Values/ValueCache")
	local AMVGGProvider = requireRelative("Values/AMVGGProvider")
	local ValueEngine = requireRelative("Values/ValueEngine")

	local valueCache = ValueCache.new({
		filePath = config:get("AMVGG.CacheFile"),
		fs = fs,
		json = json,
		validator = ValueValidator,
		logger = logger,
	})
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
		gameAdapter = env.gameAdapter,
	})
	inventoryReader:load()
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

	local tradeEvaluator = TradeEvaluator.new(valueEngine, ProfitCalculator)
	local listingScanner = ListingScanner.new({
		tradeEvaluator = tradeEvaluator,
		config = config,
		eventBus = eventBus,
		state = state,
		logger = logger,
		json = json,
		gameAdapter = env.gameAdapter,
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
		},
		kiria = kiria,
		ui = {
			theme = Theme,
			widgets = Widgets,
			notifications = notifications,
			pages = pages,
			window = mainWindow,
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
