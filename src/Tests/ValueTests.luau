--!strict
--[[
	ValueTests.luau
	Unit tests for AMVGG ValueParser, ValueValidator, ValueCache, AMVGGProvider, and ValueEngine.
]]

local function run(requireRelative: (string) -> any, json: any)
	local ValueParser = requireRelative("Values/ValueParser")
	local ValueValidator = requireRelative("Values/ValueValidator")
	local ValueCache = requireRelative("Values/ValueCache")
	local AMVGGProvider = requireRelative("Values/AMVGGProvider")
	local ValueEngine = requireRelative("Values/ValueEngine")
	local ConfigManager = requireRelative("Core/ConfigManager")
	local ErrorHandler = requireRelative("Core/ErrorHandler")

	local passed, failed = 0, 0
	local function check(name: string, cond: boolean, detail: string?)
		if cond then
			passed += 1
		else
			failed += 1
			error(string.format("[ValueTests] FAIL %s: %s", name, tostring(detail or "")))
		end
	end

	-- 1. Parse Next.js RSC HTML payload from AMVGG
	local sampleRscHtml = [[
		<html><script>self.__next_f.push([1,"12:[{\"id\":\"64b0ef9fca18db5174630884\",\"name\":\"Shadow Dragon\",\"regularValue\":\"100\",\"npRegularValue\":\"115\",\"neonValue\":\"250\",\"megaValue\":\"600\",\"regularDemand\":\"High\",\"lastUpdatedAt\":\"$D2026-11-23T13:26:04.111Z\"},{\"id\":\"64b0ef9fca18db5174630885\",\"name\":\"Frost Dragon\",\"regularValue\":\"125\",\"npRegularValue\":\"135\",\"neonValue\":\"300\",\"megaValue\":\"720\",\"regularDemand\":\"High\",\"rValue\":\"120\"},{\"id\":\"badzero\",\"name\":\"Zero Pet\",\"regularValue\":\"0\"}]"])</script></html>
	]]
	local parsed = ValueParser.parse(sampleRscHtml, json.decode)
	check("RSC parse ok", parsed.ok == true, parsed.error)
	check("RSC parsed 3 raw objects", #parsed.pets == 3)

	-- 2. Cloudflare challenge detection & malformed JSON rejection
	local cf = ValueParser.parse("<html><title>Just a moment...</title>Cloudflare</html>", json.decode)
	check("Cloudflare detected", cf.ok == false and cf.errorType == "CLOUDFLARE_BLOCK")
	local badJson = ValueParser.parse("{bad json", json.decode)
	check("Malformed JSON rejected", badJson.ok == false and badJson.errorType == "MALFORMED_JSON")

	-- 3. Validation rejects zero-value pet and preserves valid pets
	local summary = ValueValidator.validateDataset(parsed.pets, 1000)
	check("Valid count is 2", summary.validCount == 2)
	check("Rejected count is 1", summary.rejectedCount == 1)

	-- 4. ValueEngine calculations & variants
	local cfg = ConfigManager.new({})
	local cache = ValueCache.new({ validator = ValueValidator, json = json })
	cache:setValidatedDataset(summary, 1000, "https://amvgg.com/values/pets")
	local engine = ValueEngine.new(cache, ValueValidator, cfg)

	local eval = engine:evaluateTrade(
		{ { name = "Shadow Dragon", fly = true, ride = true } }, -- 100
		{ { name = "Frost Dragon", fly = true, ride = true } } -- 125
	)
	check("Trade complete", eval.complete == true)
	check("Your value 100", eval.yourValue == 100)
	check("Their value 125", eval.theirValue == 125)
	check("Difference +25", eval.difference == 25)
	check("Percent +25%", math.abs(eval.percentDifference - 25) < 0.001)
	check("Rating EXCELLENT_DEAL", eval.rating == "EXCELLENT_DEAL")

	-- Neon / Mega / No-Pot / Ride variants
	local npEval = engine:evaluatePet({ name = "Shadow Dragon" })
	check("No-pot Shadow Dragon = 115", npEval.complete and npEval.unitValue == 115)
	local megaEval = engine:evaluatePet({ name = "Shadow Dragon", mega = true, fly = true, ride = true })
	check("MFR Shadow Dragon = 600", megaEval.complete and megaEval.unitValue == 600)
	local rideEval = engine:evaluatePet({ name = "Frost Dragon", ride = true })
	check("R Frost Dragon = 120", rideEval.complete and rideEval.unitValue == 120)

	-- Missing pet / missing variant -> INCOMPLETE
	local missingEval = engine:evaluateTrade(
		{ { name = "Shadow Dragon", fly = true, ride = true } },
		{ { name = "Nonexistent Pet", fly = true, ride = true } }
	)
	check("Missing pet marked INCOMPLETE", missingEval.complete == false and missingEval.rating == "INCOMPLETE")

	-- 5. AMVGGProvider preserves last valid cache on refresh failure & blocks non-AMVGG URLs
	local provider = AMVGGProvider.new({
		config = cfg,
		cache = cache,
		parser = ValueParser,
		validator = ValueValidator,
		errorHandler = ErrorHandler.new(nil, nil),
		httpGet = function()
			return true, 503, "Service Unavailable"
		end,
		jsonDecode = json.decode,
	})
	local okRefresh = provider:refresh({ force = true })
	check("Refresh fails on 503", okRefresh == false)
	check("Cache preserved after 503", cache:hasData() == true and provider:getStatus().status == "CACHED_FALLBACK")

	cfg:set("AMVGG.EndpointUrl", "https://elvebredd.com/api")
	local okNonAmvgg, errNonAmvgg = provider:refresh({ force = true })
	check("Non-AMVGG URL blocked", okNonAmvgg == false and string.find(tostring(errNonAmvgg), "Blocked non-AMVGG", 1, true) ~= nil)

	return { passed = passed, failed = failed }
end

return { run = run }
