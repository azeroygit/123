--!strict
--[[
	MainWindow.luau
	Root Dark Trading Terminal window coordinating navigation, draggable header bar,
	AMVGG status pill, auto-refresh on events, and clean teardown.
]]

local MainWindow = {}
MainWindow.__index = MainWindow

MainWindow.Pages = { "Dashboard", "Listings", "Offers", "Inventory", "Analytics", "Settings" }

function MainWindow.new(deps: {
	theme: any,
	widgets: any,
	pages: { [string]: any },
	notifications: any,
	eventBus: any?,
	config: any?,
})
	local self = setmetatable({}, MainWindow)
	self._theme = deps.theme
	self._widgets = deps.widgets
	self._pages = deps.pages
	self._notifications = deps.notifications
	self._eventBus = deps.eventBus
	self._config = deps.config

	self._activePage = "Dashboard"
	self._visible = true
	self._minimized = false
	self._gui = nil :: any
	self._root = nil :: any
	self._contentFrame = nil :: any
	self._navButtons = {} :: { [string]: any }
	self._statusPill = nil :: any
	self._connections = {} :: { any }
	return self
end

function MainWindow:getActivePage(): string
	return self._activePage
end

function MainWindow:_refreshNavHighlights()
	for name, btn in pairs(self._navButtons) do
		if btn and btn.BackgroundColor3 ~= nil then
			local isActive = (name == self._activePage)
			btn.BackgroundColor3 = self._theme.toColor3(
				if isActive then self._theme.Colors.Accent else self._theme.Colors.SurfaceAlt
			)
		end
	end
end

function MainWindow:refreshCurrentPage()
	if self._contentFrame and self._pages[self._activePage] then
		self._pages[self._activePage]:render(self._contentFrame, self._theme, self._widgets, function(pageName: string)
			self:navigate(pageName)
		end)
	end
end

function MainWindow:navigate(pageName: string): boolean
	if not self._pages[pageName] then
		return false
	end
	self._activePage = pageName
	self:_refreshNavHighlights()
	self:refreshCurrentPage()
	if self._eventBus then
		self._eventBus:emit("UI:Navigated", pageName)
	end
	return true
end

function MainWindow:setVisible(visible: boolean)
	self._visible = visible
	if self._gui and self._gui.Enabled ~= nil then
		self._gui.Enabled = visible
	end
end

function MainWindow:isVisible(): boolean
	return self._visible
end

function MainWindow:mount(parentGui: any?)
	if not self._widgets.isRobloxGuiAvailable() then
		return
	end
	local targetParent = parentGui
	if not targetParent and type(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and hui then
			targetParent = hui
		end
	end
	if not targetParent then
		local okCore, CoreGui = pcall(function()
			return game:GetService("CoreGui")
		end)
		if okCore and CoreGui then
			targetParent = CoreGui
		end
	end
	if not targetParent then
		local Players = game:GetService("Players")
		targetParent = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	if not targetParent then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "KiriaAutoTraderUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = targetParent
	self._gui = screenGui

	pcall(function()
		local UserInputService = game:GetService("UserInputService")
		local keyName = tostring(self._config and self._config:get("UI.Keybind") or "RightShift")
		local conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if not gameProcessed and input.KeyCode and input.KeyCode.Name == keyName then
				self:setVisible(not self._visible)
			end
		end)
		table.insert(self._connections, conn)
	end)

	local root = self._widgets.createRoundedFrame(screenGui, {
		name = "TerminalRoot",
		size = UDim2.new(0, 880, 0, 560),
		position = UDim2.new(0.5, -440, 0.5, -280),
		bgColor = self._theme.toColor3(self._theme.Colors.Background),
		borderColor = self._theme.toColor3(self._theme.Colors.Accent),
		cornerRadius = 12,
	})
	self._root = root

	-- Draggable Header Bar
	local header = self._widgets.createRoundedFrame(root, {
		name = "Header",
		size = UDim2.new(1, -20, 0, 42),
		position = UDim2.new(0, 10, 0, 10),
		bgColor = self._theme.toColor3(self._theme.Colors.Surface),
		borderColor = self._theme.toColor3(self._theme.Colors.Border),
		cornerRadius = 8,
	})
	for _, c in ipairs(self._widgets.makeDraggable(root, header)) do
		table.insert(self._connections, c)
	end

	self._widgets.createLabel(header, {
		text = "KIRIA AUTOTRADER  •  AMVGG TERMINAL",
		position = UDim2.new(0, 14, 0, 10),
		size = UDim2.new(0, 340, 0, 22),
		textColor = self._theme.toColor3(self._theme.Colors.AccentBright),
		textSize = 14,
		bold = true,
	})

	self._statusPill = self._widgets.createLabel(header, {
		text = "RightShift: Toggle",
		position = UDim2.new(1, -250, 0, 11),
		size = UDim2.new(0, 160, 0, 20),
		textColor = self._theme.toColor3(self._theme.Colors.TextMuted),
		textSize = 11,
		xAlign = Enum.TextXAlignment.Right,
	})

	self._widgets.createButton(header, {
		name = "BtnMinimize",
		text = "_",
		size = UDim2.new(0, 28, 0, 26),
		position = UDim2.new(1, -70, 0, 8),
		bgColor = self._theme.toColor3(self._theme.Colors.SurfaceAlt),
		textColor = self._theme.toColor3(self._theme.Colors.TextPrimary),
		onClick = function()
			self._minimized = not self._minimized
			if self._root then
				self._root.Size = if self._minimized then UDim2.new(0, 880, 0, 62) else UDim2.new(0, 880, 0, 560)
			end
			if self._contentFrame then
				self._contentFrame.Visible = not self._minimized
			end
		end,
	})

	self._widgets.createButton(header, {
		name = "BtnClose",
		text = "X",
		size = UDim2.new(0, 28, 0, 26),
		position = UDim2.new(1, -36, 0, 8),
		bgColor = self._theme.toColor3(self._theme.Colors.Loss),
		textColor = self._theme.toColor3(self._theme.Colors.TextPrimary),
		onClick = function()
			self:setVisible(false)
		end,
	})

	local sidebar = self._widgets.createRoundedFrame(root, {
		name = "Sidebar",
		size = UDim2.new(0, self._theme.Layout.SidebarWidth, 1, -72),
		position = UDim2.new(0, 10, 0, 60),
		bgColor = self._theme.toColor3(self._theme.Colors.Surface),
		borderColor = self._theme.toColor3(self._theme.Colors.Border),
		cornerRadius = 10,
	})

	for idx, pageName in ipairs(MainWindow.Pages) do
		local btn = self._widgets.createButton(sidebar, {
			name = "Nav_" .. pageName,
			text = pageName,
			size = UDim2.new(1, -16, 0, 36),
			position = UDim2.new(0, 8, 0, 12 + (idx - 1) * 44),
			bgColor = self._theme.toColor3(self._theme.Colors.SurfaceAlt),
			textColor = self._theme.toColor3(self._theme.Colors.TextPrimary),
			onClick = function()
				self:navigate(pageName)
			end,
		})
		self._navButtons[pageName] = btn
	end

	self._contentFrame = self._widgets.createRoundedFrame(root, {
		name = "Content",
		size = UDim2.new(1, -(self._theme.Layout.SidebarWidth + 30), 1, -72),
		position = UDim2.new(0, self._theme.Layout.SidebarWidth + 20, 0, 60),
		bgColor = self._theme.toColor3(self._theme.Colors.Surface),
		borderColor = self._theme.toColor3(self._theme.Colors.Border),
		cornerRadius = 10,
		padding = 14,
	})

	-- Auto-refresh active page when live data updates
	if self._eventBus then
		for _, evtName in ipairs({ "AMVGG:Refreshed", "AMVGG:StatusChanged", "Inventory:Updated", "Offer:Queued", "Offer:StatusChanged", "Trade:Confirmed", "Kiria:Message" }) do
			table.insert(self._connections, self._eventBus:subscribe(evtName, function()
				self:refreshCurrentPage()
			end))
		end
	end

	self:navigate(self._activePage)
end

function MainWindow:destroy()
	for _, c in ipairs(self._connections) do
		if c and type(c.disconnect) == "function" then
			c:disconnect()
		end
	end
	table.clear(self._connections)
	if self._gui then
		pcall(function()
			self._gui:Destroy()
		end)
		self._gui = nil
	end
end

return MainWindow
