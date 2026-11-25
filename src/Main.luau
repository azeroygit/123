--!strict
--[[
	Main.luau
	Primary entry point for KIRIA AUTOTRADER (standalone Luau script / Roblox client).
	Supports:
	  1. Executor/workspace file loader (`readfile` + `loadstring` relative to `KiriaAutoTrader/src/`)
	  2. Lune / standard relative `require("./...")`
	  3. Roblox `script.Parent` ModuleScript hierarchy
	No global variables.
]]

local function makeRelativeLoader()
	-- 1. Executor / filesystem loader (`readfile` + `loadstring`)
	if type(readfile) == "function" and type(loadstring) == "function" then
		local cache = {} :: { [string]: any }
		local loading = {}
		local baseRoots = { "KiriaAutoTrader/src/", "src/", "" }

		local function resolveFile(relPath: string): string?
			local clean = relPath:gsub("^%./", "")
			if not clean:match("%.luau?$") then
				clean = clean .. ".luau"
			end
			for _, root in ipairs(baseRoots) do
				local candidate = root .. clean
				local ok, exists = pcall(function()
					return type(isfile) == "function" and isfile(candidate)
				end)
				if ok and exists then
					return candidate
				end
			end
			return nil
		end

		local function loadRel(relPath: string): any
			local cached = cache[relPath]
			if cached == loading then
				error("Circular import: " .. relPath)
			end
			if cached ~= nil then
				return cached
			end
			local filePath = resolveFile(relPath)
			if not filePath then
				error("Module not found: " .. relPath)
			end
			loading[relPath] = true
			cache[relPath] = loading
			local src = readfile(filePath)
			local chunk, err = loadstring(src, "@" .. filePath)
			if not chunk then
				error("Syntax error in " .. filePath .. ": " .. tostring(err))
			end
			local result = chunk()
			cache[relPath] = result
			return result
		end
		return loadRel
	end

	-- 2. Roblox Studio ModuleScript hierarchy
	if type(script) == "userdata" and script.Parent then
		local srcRoot = script.Parent
		return function(relPath: string): any
			local node: any = srcRoot
			for part in string.gmatch(relPath, "[^/]+") do
				node = node:FindFirstChild(part)
				if not node then
					error("Module not found relative to src/: " .. relPath)
				end
			end
			return require(node)
		end
	end

	-- 3. Standard Luau / Lune relative require
	return function(relPath: string): any
		return require("./" .. relPath)
	end
end

local requireRelative = makeRelativeLoader()
local Bootstrap = requireRelative("Bootstrap")

local app = Bootstrap.createApp(requireRelative, {
	autoStartScheduler = true,
})

app.ui.window:mount()

return app
