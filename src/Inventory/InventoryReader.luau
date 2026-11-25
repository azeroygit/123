--!strict
--[[
	InventoryReader.luau
	Manages the user's pet inventory via a permitted game adapter (if provided)
	or manual editor + local JSON persistence/import.
	Respects `locked` and `favorite` flags so protected pets are never offered.
]]

local InventoryReader = {}
InventoryReader.__index = InventoryReader

export type InventoryPet = {
	uid: string,
	name: string,
	neon: boolean,
	mega: boolean,
	fly: boolean,
	ride: boolean,
	locked: boolean,
	favorite: boolean,
	selectedForListing: boolean,
	source: string, -- "game" | "manual" | "import"
}

function InventoryReader.new(options: { filePath: string?, fs: any?, json: any?, eventBus: any?, logger: any?, gameAdapter: any? }?)
	local opts = options or {}
	local self = setmetatable({}, InventoryReader)
	self._filePath = opts.filePath or "KiriaAutoTrader/inventory.json"
	self._fs = opts.fs
	self._json = opts.json
	self._eventBus = opts.eventBus
	self._logger = opts.logger
	self._gameAdapter = opts.gameAdapter
	self._pets = {} :: { InventoryPet }
	self._nextId = 1
	return self
end

function InventoryReader:_generateUid(): string
	local id = string.format("pet_%d_%d", os.time(), self._nextId)
	self._nextId += 1
	return id
end

function InventoryReader:_normalizePet(raw: any, defaultSource: string): InventoryPet?
	if type(raw) ~= "table" or type(raw.name) ~= "string" or raw.name:match("^%s*(.-)%s*$") == "" then
		return nil
	end
	return {
		uid = tostring(raw.uid or self:_generateUid()),
		name = raw.name:match("^%s*(.-)%s*$") or raw.name,
		neon = raw.neon == true,
		mega = raw.mega == true,
		fly = raw.fly == true,
		ride = raw.ride == true,
		locked = raw.locked == true,
		favorite = raw.favorite == true,
		selectedForListing = raw.selectedForListing == true,
		source = tostring(raw.source or defaultSource),
	}
end

function InventoryReader:getAll(): { InventoryPet }
	return table.clone(self._pets)
end

function InventoryReader:getTradeable(): { InventoryPet }
	local out = {}
	for _, pet in ipairs(self._pets) do
		if not pet.locked and not pet.favorite then
			table.insert(out, pet)
		end
	end
	return out
end

function InventoryReader:getSelected(): { InventoryPet }
	local out = {}
	for _, pet in ipairs(self._pets) do
		if pet.selectedForListing then
			table.insert(out, pet)
		end
	end
	return out
end

function InventoryReader:addPet(petData: { name: string, neon: boolean?, mega: boolean?, fly: boolean?, ride: boolean?, locked: boolean?, favorite: boolean?, uid: string? }): InventoryPet?
	local pet = self:_normalizePet(petData, "manual")
	if not pet then
		return nil
	end
	table.insert(self._pets, pet)
	self:save()
	if self._eventBus then
		self._eventBus:emit("Inventory:Updated", { count = #self._pets })
	end
	return pet
end

function InventoryReader:updatePet(uid: string, patch: { [string]: any }): boolean
	for _, pet in ipairs(self._pets) do
		if pet.uid == uid then
			for k, v in pairs(patch) do
				if k ~= "uid" and (pet :: any)[k] ~= nil then
					(pet :: any)[k] = v
				end
			end
			self:save()
			if self._eventBus then
				self._eventBus:emit("Inventory:Updated", { count = #self._pets })
			end
			return true
		end
	end
	return false
end

function InventoryReader:removePet(uid: string): boolean
	for i, pet in ipairs(self._pets) do
		if pet.uid == uid then
			table.remove(self._pets, i)
			self:save()
			if self._eventBus then
				self._eventBus:emit("Inventory:Updated", { count = #self._pets })
			end
			return true
		end
	end
	return false
end

function InventoryReader:syncFromGame(): (boolean, string?)
	if not (self._gameAdapter and type(self._gameAdapter.readInventory) == "function") then
		return false, "Automatic inventory sync unavailable in this environment; use Manual Editor or JSON Import"
	end
	local ok, listOrErr = pcall(self._gameAdapter.readInventory)
	if not ok or type(listOrErr) ~= "table" then
		return false, "Failed to read permitted game inventory: " .. tostring(listOrErr)
	end
	local nextList = {}
	for _, raw in ipairs(listOrErr) do
		local p = self:_normalizePet(raw, "game")
		if p then
			table.insert(nextList, p)
		end
	end
	self._pets = nextList
	self:save()
	if self._eventBus then
		self._eventBus:emit("Inventory:Updated", { count = #self._pets, source = "game" })
	end
	return true, nil
end

function InventoryReader:importJson(jsonText: string, replace: boolean?): (boolean, string?, number)
	if not (self._json and type(self._json.decode) == "function") then
		return false, "JSON decoder unavailable", 0
	end
	local ok, decoded = pcall(self._json.decode, jsonText)
	if not ok or type(decoded) ~= "table" then
		return false, "Invalid inventory JSON", 0
	end
	local sourceList = if type(decoded.pets) == "table" then decoded.pets else decoded
	local imported = {}
	for _, raw in ipairs(sourceList) do
		local p = self:_normalizePet(raw, "import")
		if p then
			table.insert(imported, p)
		end
	end
	if replace then
		self._pets = imported
	else
		for _, p in ipairs(imported) do
			table.insert(self._pets, p)
		end
	end
	self:save()
	if self._eventBus then
		self._eventBus:emit("Inventory:Updated", { count = #self._pets, imported = #imported })
	end
	return true, nil, #imported
end

function InventoryReader:exportJson(): string?
	if not (self._json and type(self._json.encode) == "function") then
		return nil
	end
	local ok, encoded = pcall(self._json.encode, { pets = self._pets })
	return if ok then encoded else nil
end

function InventoryReader:save(): boolean
	if not (self._fs and self._json and self._fs.write) then
		return false
	end
	local encoded = self:exportJson()
	if not encoded then
		return false
	end
	return pcall(self._fs.write, self._filePath, encoded)
end

function InventoryReader:load(): boolean
	if not (self._fs and self._json and self._fs.exists and self._fs.read) then
		return false
	end
	if not self._fs.exists(self._filePath) then
		return false
	end
	local okRead, raw = pcall(self._fs.read, self._filePath)
	if not okRead or type(raw) ~= "string" then
		return false
	end
	local ok = self:importJson(raw, true)
	return ok
end

return InventoryReader
