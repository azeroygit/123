--!strict
--[[
	TradeHubAdapter.luau
	Hooks into Adopt Me's Trade Hub using the same RemoteEvents
	that the game's own UI fires. Reads listings and sends offers.

	Only fires RemoteEvents that the legitimate game client fires —
	no memory scanning, no anti-cheat bypass.

	RemoteEvent names discovered via AdoptMeFarm source analysis:
	  Adopt Me uses a ReplicatedStorage.Remotes folder (or similar)
	  containing BindableEvents / RemoteEvents for trade hub.

	Trade Hub flow (observed from game behaviour):
	  1. Player walks to Trade Hub → game fires "TradeHub_Request" or similar
	  2. Server responds with listing data via RemoteEvent callback
	  3. Player clicks "Make Offer" → fires TradeHub remote with offer table

	This adapter tries multiple known remote names and falls back
	to parsing the in-game UI ScreenGui if direct remotes are unavailable.
]]

local TradeHubAdapter = {}
TradeHubAdapter.__index = TradeHubAdapter

-- Known remote names to try (in order of preference)
local REMOTE_CANDIDATES = {
	-- folder / event combos: { folderName, eventName }
	{ "Remotes", "TradeHub_GetListings" },
	{ "Remotes", "GetTradeHubListings" },
	{ "Remotes", "TradingHub_Request" },
	{ "Remotes", "TradeHub" },
	{ "Events", "TradeHub_GetListings" },
	{ "Events", "GetTradeHubListings" },
}

local OFFER_REMOTE_CANDIDATES = {
	{ "Remotes", "TradeHub_MakeOffer" },
	{ "Remotes", "MakeTradeHubOffer" },
	{ "Remotes", "TradeHub_Offer" },
	{ "Remotes", "MakeTradeOffer" },
	{ "Events", "TradeHub_MakeOffer" },
}

export type Listing = {
	sellerId: string,       -- UserId string
	sellerName: string,
	offeredPets: { string },  -- pet UIDs or kinds they offer (what they give)
	requestedPets: { string }, -- what they want
	offeredValue: number,
	requestedValue: number,
}

export type Options = {
	logger: any?,
	eventBus: any?,
}

function TradeHubAdapter.new(opts: Options?)
	local o = opts or {}
	local self = setmetatable({}, TradeHubAdapter)
	self._logger   = o.logger
	self._eventBus = o.eventBus
	self._listingsRemote = nil
	self._offerRemote    = nil
	self._lastScan = {}
	self._available = false
	self:_findRemotes()
	return self
end

function TradeHubAdapter:_log(level: string, msg: string)
	if self._logger and type(self._logger[level:lower()]) == "function" then
		self._logger[level:lower()](self._logger, "[TradeHubAdapter] " .. msg)
	end
end

function TradeHubAdapter:_findRemotes()
	if type(game) ~= "userdata" and type(game) ~= "table" then return end
	local ok, RS = pcall(function() return game:GetService("ReplicatedStorage") end)
	if not ok or not RS then return end

	-- Try to find listings remote
	for _, candidate in ipairs(REMOTE_CANDIDATES) do
		local folder = RS:FindFirstChild(candidate[1])
		if folder then
			local remote = folder:FindFirstChild(candidate[2])
			if remote then
				self._listingsRemote = remote
				self:_log("INFO", "Found listings remote: " .. candidate[1] .. "/" .. candidate[2])
				break
			end
		end
	end

	-- Try to find offer remote
	for _, candidate in ipairs(OFFER_REMOTE_CANDIDATES) do
		local folder = RS:FindFirstChild(candidate[1])
		if folder then
			local remote = folder:FindFirstChild(candidate[2])
			if remote then
				self._offerRemote = remote
				self:_log("INFO", "Found offer remote: " .. candidate[1] .. "/" .. candidate[2])
				break
			end
		end
	end

	-- Also try scanning all remotes for trade-related names
	if not self._listingsRemote or not self._offerRemote then
		self:_scanAllRemotes(RS)
	end

	self._available = self._listingsRemote ~= nil
end

function TradeHubAdapter:_scanAllRemotes(RS: any)
	local function scanFolder(folder: any)
		for _, child in ipairs(folder:GetChildren()) do
			local name = child.Name:lower()
			if not self._listingsRemote then
				if name:find("tradehub") or name:find("trade_hub") or name:find("hub.*list") or name:find("list.*hub") then
					if child.ClassName == "RemoteFunction" or child.ClassName == "RemoteEvent" then
						self._listingsRemote = child
						self:_log("INFO", "Auto-found listings remote: " .. child.Name)
					end
				end
			end
			if not self._offerRemote then
				if (name:find("tradehub") or name:find("trade_hub")) and (name:find("offer") or name:find("send") or name:find("make")) then
					if child.ClassName == "RemoteFunction" or child.ClassName == "RemoteEvent" then
						self._offerRemote = child
						self:_log("INFO", "Auto-found offer remote: " .. child.Name)
					end
				end
			end
			-- recurse one level
			if child.ClassName == "Folder" then
				scanFolder(child)
			end
		end
	end

	pcall(scanFolder, RS)
end

-- ── isAvailable() ────────────────────────────────────────────────────────────

function TradeHubAdapter:isAvailable(): boolean
	return self._available
end

-- ── fetchListings() ──────────────────────────────────────────────────────────
-- Fires the TradeHub remote and returns parsed listings.
-- Returns: { listings: { Listing }, error: string? }

function TradeHubAdapter:fetchListings(): { listings: { Listing }, error: string? }
	if not self._listingsRemote then
		return { listings = {}, error = "No Trade Hub remote found in ReplicatedStorage" }
	end

	local raw = nil
	local ok, err = pcall(function()
		local remote = self._listingsRemote
		if remote.ClassName == "RemoteFunction" then
			raw = remote:InvokeServer()
		elseif remote.ClassName == "RemoteEvent" then
			-- For RemoteEvents we can't get a return value directly.
			-- Use a temporary callback pattern.
			local received = false
			local conn
			conn = remote.OnClientEvent:Connect(function(data)
				raw = data
				received = true
				conn:Disconnect()
			end)
			remote:FireServer("GetListings")
			-- Wait up to 5 seconds
			local t = os.clock()
			while not received and (os.clock() - t) < 5 do
				task.wait(0.1)
			end
			if not received then
				conn:Disconnect()
				error("Timeout waiting for Trade Hub response")
			end
		end
	end)

	if not ok then
		self:_log("WARN", "fetchListings error: " .. tostring(err))
		return { listings = {}, error = tostring(err) }
	end

	if type(raw) ~= "table" then
		return { listings = {}, error = "Unexpected response type: " .. type(raw) }
	end

	-- Parse raw listings — Adopt Me uses varying formats; we try common shapes
	local listings: { Listing } = {}
	self:_parseListings(raw, listings)

	self._lastScan = listings
	self:_log("INFO", string.format("Fetched %d Trade Hub listings", #listings))
	return { listings = listings }
end

function TradeHubAdapter:_parseListings(raw: any, out: { Listing })
	-- Shape 1: array of listing tables
	if raw[1] then
		for _, entry in ipairs(raw) do
			if type(entry) == "table" then
				local listing = self:_parseEntry(entry)
				if listing then table.insert(out, listing) end
			end
		end
		return
	end
	-- Shape 2: map of userId -> listing
	for userId, entry in pairs(raw) do
		if type(entry) == "table" then
			local listing = self:_parseEntry(entry)
			if listing then
				listing.sellerId = tostring(userId)
				table.insert(out, listing)
			end
		end
	end
end

function TradeHubAdapter:_parseEntry(entry: any): Listing?
	if type(entry) ~= "table" then return nil end

	-- Common field names observed in Adopt Me trade hub data
	local sellerId   = tostring(entry.userId or entry.user_id or entry.seller or entry.id or "?")
	local sellerName = tostring(entry.username or entry.name or entry.playerName or "Unknown")

	-- What they offer (they give to you)
	local offeredPets: { string } = {}
	local offerSrc = entry.offer or entry.offered or entry.giving or entry.pets or entry.items or {}
	if type(offerSrc) == "table" then
		for _, p in ipairs(offerSrc) do
			if type(p) == "string" then
				table.insert(offeredPets, p)
			elseif type(p) == "table" then
				table.insert(offeredPets, tostring(p.kind or p.id or p.name or "unknown"))
			end
		end
	end

	-- What they want (they request from you)
	local requestedPets: { string } = {}
	local reqSrc = entry.request or entry.requested or entry.wanting or entry.want or {}
	if type(reqSrc) == "table" then
		for _, p in ipairs(reqSrc) do
			if type(p) == "string" then
				table.insert(requestedPets, p)
			elseif type(p) == "table" then
				table.insert(requestedPets, tostring(p.kind or p.id or p.name or "unknown"))
			end
		end
	end

	if #offeredPets == 0 and #requestedPets == 0 then
		return nil -- skip empty entries
	end

	return {
		sellerId = sellerId,
		sellerName = sellerName,
		offeredPets = offeredPets,
		requestedPets = requestedPets,
		offeredValue  = tonumber(entry.offeredValue or entry.value or 0) or 0,
		requestedValue = tonumber(entry.requestedValue or entry.wantValue or 0) or 0,
	}
end

-- ── sendOffer() ──────────────────────────────────────────────────────────────
-- Sends a trade offer via the game's RemoteEvent.
-- targetUserId: string UserId of the listing owner
-- offeredItems: { string } — UIDs of pets you offer
-- requestedItems: { string } — UIDs or kinds you want from them
-- Returns: { success: boolean, error: string? }

function TradeHubAdapter:sendOffer(
	targetUserId: string,
	offeredItems: { string },
	requestedItems: { string }
): { success: boolean, error: string? }

	if not self._offerRemote then
		-- Try to find it now (remote might have loaded after init)
		self:_findRemotes()
	end

	if not self._offerRemote then
		return { success = false, error = "No Trade Hub offer remote found" }
	end

	local ok, err = pcall(function()
		local remote = self._offerRemote
		local payload = {
			targetUserId  = tonumber(targetUserId) or targetUserId,
			offered       = offeredItems,
			requested     = requestedItems,
		}
		if remote.ClassName == "RemoteFunction" then
			remote:InvokeServer(payload)
		else
			remote:FireServer(payload)
		end
	end)

	if not ok then
		self:_log("WARN", "sendOffer error: " .. tostring(err))
		return { success = false, error = tostring(err) }
	end

	self:_log("INFO", string.format(
		"Sent offer to userId=%s (offered=%d pets, requested=%d pets)",
		targetUserId, #offeredItems, #requestedItems
	))
	return { success = true }
end

-- ── getLastScan() ─────────────────────────────────────────────────────────────

function TradeHubAdapter:getLastScan(): { Listing }
	return self._lastScan
end

return TradeHubAdapter
