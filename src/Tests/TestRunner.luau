--!strict
--[[
	TestRunner.luau
	Executes all unit and integration test suites using relative module loading.
	Compatible with Lune (`lune run src/Tests/TestRunner.luau`) and Roblox Studio.
]]

local serde = require("@lune/serde")

local json = {
	encode = function(v: any): string
		return serde.encode("json", v)
	end,
	decode = function(s: string): any
		return serde.decode("json", s)
	end,
}

local function requireRelative(relPath: string): any
	return require("../" .. relPath)
end

-- Verify all modules load without syntax or circular-dependency errors
local allModules = {
	"Core/Logger",
	"Core/EventBus",
	"Core/StateManager",
	"Core/ErrorHandler",
	"Core/TaskScheduler",
	"Core/ConfigManager",
	"Values/ValueParser",
	"Values/ValueValidator",
	"Values/ValueCache",
	"Values/AMVGGProvider",
	"Values/ValueEngine",
	"Inventory/PetDatabase",
	"Inventory/InventoryReader",
	"Inventory/InventoryValuator",
	"Trading/ProfitCalculator",
	"Trading/TradeEvaluator",
	"Trading/ListingScanner",
	"Trading/OfferAnalyzer",
	"Trading/ListingManager",
	"Trading/OfferTimer",
	"Trading/OfferQueue",
	"Trading/TradeHistory",
	"Kiria/Personality",
	"Kiria/Memory",
	"Kiria/Reactions",
	"Kiria/Companion",
	"UI/Components/Theme",
	"UI/Components/Widgets",
	"UI/Notifications",
	"UI/Dashboard",
	"UI/ListingsPage",
	"UI/OffersPage",
	"UI/InventoryPage",
	"UI/AnalyticsPage",
	"UI/SettingsPage",
	"UI/MainWindow",
	"Bootstrap",
}

for _, modPath in ipairs(allModules) do
	requireRelative(modPath)
end
print(string.format("[Syntax/Load] All %d modules loaded cleanly.", #allModules))

local suites = {
	{ name = "ValueTests", mod = requireRelative("Tests/ValueTests") },
	{ name = "TradingTests", mod = requireRelative("Tests/TradingTests") },
	{ name = "TimerTests", mod = requireRelative("Tests/TimerTests") },
	{ name = "IntegrationTests", mod = requireRelative("Tests/IntegrationTests") },
}

local totalPassed = 0
local totalFailed = 0

for _, suite in ipairs(suites) do
	local res = suite.mod.run(requireRelative, json)
	totalPassed += res.passed
	totalFailed += res.failed
	print(string.format("[%s] Passed: %d, Failed: %d", suite.name, res.passed, res.failed))
end

print(string.format("[TOTAL] Passed: %d, Failed: %d", totalPassed, totalFailed))
if totalFailed > 0 then
	error("Test suite failed")
end
