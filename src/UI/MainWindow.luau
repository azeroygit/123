--!strict
--[[
	MainWindow.luau
	Root Dark Trading Terminal window coordinating navigation, top status bar,
	Roblox ScreenGui lifecycle (when available), and clean teardown.
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
	self._gui = nil :: any
	self._contentFrame = nil :: any
	self._connections = {} :: { any }
	return self
end

function MainWindow:getActivePage(): string
	return self._activePage
end

function MainWindow:navigate(pageName: string): boolean
	if not self._pages[pageName] then
		return false
	end
	self._activePage = pageName
	if self._contentFrame then
		self._pages[pageName]:render(self._contentFrame, self._theme, self._widgets)
	end
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

	-- Keybind toggle (default RightShift)
	pcall(function()
		local UserInputService = game:GetService("UserInputService")
		local keyName = tostring(self._config and self._config:get("UI.Keybind") or "RightShift")
		local conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.KeyCode and input.KeyCode.Name == keyName then
				self:setVisible(not self._visible)
			end
		end)
		table.insert(self._connections, conn)
	end)

	local root = self._widgets.createRoundedFrame(screenGui, {
		name = "TerminalRoot",
		size = UDim2.new(0, 860, 0, 540),
		position = UDim2.new(0.5, -430, 0.5, -270),
		bgColor = self._theme.toColor3(self._theme.Colors.Background),
		borderColor = self._theme.toColor3(self._theme.Colors.Accent),
		cornerRadius = 12,
	})

	local sidebar = self._widgets.createRoundedFrame(root, {
		name = "Sidebar",
		size = UDim2.new(0, self._theme.Layout.SidebarWidth, 1, -20),
		position = UDim2.new(0, 10, 0, 10),
		bgColor = self._theme.toColor3(self._theme.Colors.Surface),
		cornerRadius = 10,
	})

	for idx, pageName in ipairs(MainWindow.Pages) do
		self._widgets.createButton(sidebar, {
			name = "Nav_" .. pageName,
			text = pageName,
			size = UDim2.new(1, -16, 0, 34),
			position = UDim2.new(0, 8, 0, 12 + (idx - 1) * 42),
			bgColor = self._theme.toColor3(self._theme.Colors.SurfaceAlt),
			textColor = self._theme.toColor3(self._theme.Colors.TextPrimary),
			onClick = function()
				self:navigate(pageName)
			end,
		})
	end

	self._contentFrame = self._widgets.createRoundedFrame(root, {
		name = "Content",
		size = UDim2.new(1, -(self._theme.Layout.SidebarWidth + 30), 1, -20),
		position = UDim2.new(0, self._theme.Layout.SidebarWidth + 20, 0, 10),
		bgColor = self._theme.toColor3(self._theme.Colors.Surface),
		cornerRadius = 10,
	})

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
