--!strict
--[[
	InventoryPage.luau
	Inventory search, filtering, AMVGG valuation sorting, top pet highlight,
	manual pet editor, JSON import/export, and game sync.
]]

local InventoryPage = {}
InventoryPage.__index = InventoryPage

function InventoryPage.new(deps: { inventoryReader: any, inventoryValuator: any })
	local self = setmetatable({}, InventoryPage)
	self._reader = deps.inventoryReader
	self._valuator = deps.inventoryValuator
	self._filter = {
		query = "",
		neonOnly = false,
		megaOnly = false,
		flyOnly = false,
		rideOnly = false,
		tradeableOnly = false,
		sortDescending = true,
	}
	self._draftName = ""
	self._draftN = false
	self._draftM = false
	self._draftF = true
	self._draftR = true
	self._statusMsg = ""
	return self
end

function InventoryPage:setFilter(patch: { [string]: any })
	for k, v in pairs(patch) do
		self._filter[k] = v
	end
end

function InventoryPage:getViewModel()
	return self._valuator:evaluateAll(self._filter)
end

function InventoryPage:addPet(petData: { [string]: any })
	return self._reader:addPet(petData)
end

function InventoryPage:toggleSelectForListing(uid: string, selected: boolean): boolean
	return self._reader:updatePet(uid, { selectedForListing = selected })
end

function InventoryPage:toggleLock(uid: string, locked: boolean): boolean
	return self._reader:updatePet(uid, { locked = locked })
end

function InventoryPage:removePet(uid: string): boolean
	return self._reader:removePet(uid)
end

function InventoryPage:importJson(jsonText: string, replace: boolean?)
	return self._reader:importJson(jsonText, replace)
end

function InventoryPage:exportJson(): string?
	return self._reader:exportJson()
end

function InventoryPage:syncFromGame()
	return self._reader:syncFromGame()
end

function InventoryPage:render(container: any, theme: any, widgets: any)
	if not (container and widgets and widgets.isRobloxGuiAvailable()) then
		return
	end
	widgets.clearChildren(container)
	local vm = self:getViewModel()
	local cText = theme.toColor3(theme.Colors.TextPrimary)
	local cMuted = theme.toColor3(theme.Colors.TextMuted)
	local cCard = theme.toColor3(theme.Colors.SurfaceAlt)
	local cBorder = theme.toColor3(theme.Colors.Border)
	local cAccent = theme.toColor3(theme.Colors.Accent)
	local cProfit = theme.toColor3(theme.Colors.Profit)
	local cLoss = theme.toColor3(theme.Colors.Loss)

	local topName = if vm.topPet then vm.topPet.pet.name else "None"
	local topVal = if vm.topPet then vm.topPet.value else 0
	widgets.createLabel(container, {
		text = string.format("Inventory (%d pets)  |  Total AMVGG: %.2f  |  Top: %s (%.2f)", vm.totalCount, vm.totalValue, topName, topVal),
		size = UDim2.new(1, -120, 0, 22),
		textColor = cText,
		textSize = 15,
		bold = true,
	})

	widgets.createButton(container, {
		text = "Sync Game",
		size = UDim2.new(0, 110, 0, 28),
		position = UDim2.new(1, -110, 0, 0),
		bgColor = cCard,
		textColor = cText,
		onClick = function()
			local _, err = self:syncFromGame()
			self._statusMsg = err or "Synced from game"
			self:render(container, theme, widgets)
		end,
	})

	-- Manual Add Pet Bar
	widgets.createTextBox(container, {
		text = self._draftName,
		placeholder = "Add pet name (e.g. Frost Dragon)...",
		size = UDim2.new(0, 220, 0, 30),
		position = UDim2.new(0, 0, 0, 34),
		bgColor = theme.toColor3(theme.Colors.Background),
		textColor = cText,
		placeholderColor = cMuted,
		borderColor = cBorder,
		onFocusLost = function(txt)
			self._draftName = txt
		end,
	})

	local function flagBtn(label: string, active: boolean, x: number, toggleFn: () -> ())
		widgets.createButton(container, {
			text = label,
			size = UDim2.new(0, 34, 0, 30),
			position = UDim2.new(0, x, 0, 34),
			bgColor = if active then cAccent else cCard,
			textColor = cText,
			onClick = function()
				toggleFn()
				self:render(container, theme, widgets)
			end,
		})
	end
	flagBtn("N", self._draftN, 226, function() self._draftN = not self._draftN end)
	flagBtn("M", self._draftM, 264, function() self._draftM = not self._draftM end)
	flagBtn("F", self._draftF, 302, function() self._draftF = not self._draftF end)
	flagBtn("R", self._draftR, 340, function() self._draftR = not self._draftR end)

	widgets.createButton(container, {
		text = "+ Add Pet",
		size = UDim2.new(0, 96, 0, 30),
		position = UDim2.new(0, 382, 0, 34),
		bgColor = cProfit,
		textColor = cText,
		onClick = function()
			if self._draftName ~= "" then
				self:addPet({
					name = self._draftName,
					neon = self._draftN,
					mega = self._draftM,
					fly = self._draftF,
					ride = self._draftR,
				})
				self._draftName = ""
				self._statusMsg = "Added pet to inventory"
				self:render(container, theme, widgets)
			end
		end,
	})

	-- Search & Status
	widgets.createTextBox(container, {
		text = self._filter.query,
		placeholder = "Search inventory...",
		size = UDim2.new(0, 220, 0, 28),
		position = UDim2.new(0, 0, 0, 72),
		bgColor = theme.toColor3(theme.Colors.Background),
		textColor = cText,
		placeholderColor = cMuted,
		borderColor = cBorder,
		onFocusLost = function(txt)
			self:setFilter({ query = txt })
			self:render(container, theme, widgets)
		end,
	})

	if self._statusMsg ~= "" then
		widgets.createLabel(container, {
			text = self._statusMsg,
			position = UDim2.new(0, 230, 0, 75),
			size = UDim2.new(1, -230, 0, 22),
			textColor = cMuted,
			textSize = 11,
		})
	end

	local scroll = widgets.createScrollFrame(container, {
		size = UDim2.new(1, 0, 1, -110),
		position = UDim2.new(0, 0, 0, 108),
		gap = 6,
	})

	if #vm.items == 0 then
		widgets.createLabel(scroll, {
			text = "Inventory is empty. Add pets above using their AMVGG name (e.g. Shadow Dragon, Turtle, Cow).",
			textColor = cMuted,
		})
		return
	end

	for _, entry in ipairs(vm.items) do
		local pet = entry.pet
		local ev = entry.evaluation
		local row = widgets.createRoundedFrame(scroll, {
			size = UDim2.new(1, -8, 0, 42),
			bgColor = cCard,
			borderColor = if pet.locked then theme.toColor3(theme.Colors.Warning) else cBorder,
			cornerRadius = 6,
			padding = 8,
		})
		local valStr = if ev.complete then string.format("%.2f", entry.value) else "INCOMPLETE"
		widgets.createLabel(row, {
			text = string.format("%s [%s]  •  %s AMVGG%s", pet.name, ev.variantLabel, valStr, if pet.locked then "  (LOCKED)" else ""),
			size = UDim2.new(1, -150, 0, 24),
			textColor = if ev.complete then cText else theme.toColor3(theme.Colors.Warning),
			textSize = 13,
		})
		widgets.createButton(row, {
			text = if pet.locked then "Unlock" else "Lock",
			size = UDim2.new(0, 64, 0, 26),
			position = UDim2.new(1, -138, 0, 0),
			bgColor = theme.toColor3(theme.Colors.Background),
			textColor = cText,
			onClick = function()
				self:toggleLock(pet.uid, not pet.locked)
				self:render(container, theme, widgets)
			end,
		})
		widgets.createButton(row, {
			text = "Remove",
			size = UDim2.new(0, 68, 0, 26),
			position = UDim2.new(1, -68, 0, 0),
			bgColor = cLoss,
			textColor = cText,
			onClick = function()
				self:removePet(pet.uid)
				self:render(container, theme, widgets)
			end,
		})
	end
end

return InventoryPage
