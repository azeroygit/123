--!strict
--[[
	SettingsPage.luau
	Live configuration controls for AMVGG refresh, scanner/timers, profit thresholds,
	UI customization, notifications, and data management.
]]

local SettingsPage = {}
SettingsPage.__index = SettingsPage

function SettingsPage.new(deps: { config: any, amvggProvider: any, scheduler: any, logger: any })
	local self = setmetatable({}, SettingsPage)
	self._config = deps.config
	self._amvgg = deps.amvggProvider
	self._scheduler = deps.scheduler
	self._logger = deps.logger
	return self
end

function SettingsPage:setSetting(path: string, value: any): boolean
	local ok = self._config:set(path, value)
	if not ok then
		return false
	end
	if path == "AMVGG.RefreshIntervalSeconds" and self._scheduler then
		self._scheduler:setJobInterval("amvgg_refresh", tonumber(value) or 1800)
	elseif path == "Trading.ScanIntervalSeconds" and self._scheduler then
		self._scheduler:setJobInterval("listing_scan", tonumber(value) or 15)
	elseif path == "Data.LogLevel" and self._logger then
		self._logger:setLevel(tostring(value))
	end
	self._config:saveToFile()
	return true
end

function SettingsPage:getAllSettings()
	return self._config:getAll()
end

function SettingsPage:refreshAmvggNow()
	return self._amvgg:refresh({ force = true })
end

function SettingsPage:resetDefaults()
	self._config:resetDefaults()
	self._config:saveToFile()
end

function SettingsPage:render(container: any, theme: any, widgets: any)
	if not (container and widgets and widgets.isRobloxGuiAvailable()) then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
	local s = self:getAllSettings()
	widgets.createLabel(container, {
		text = string.format(
			"Settings  |  Listing TTL: %ds  |  Offer Check: %ds  |  Min Profit: %.1f%%  |  Mode: %s",
			s.Trading.ListingExpirationSeconds, s.Trading.OfferResponseIntervalSeconds, s.Trading.MinProfitPercent, s.Trading.Mode
		),
		textColor = theme.toColor3(theme.Colors.TextPrimary),
		bold = true,
	})
	widgets.createButton(container, {
		text = "Reset Defaults",
		position = UDim2.new(0, 0, 0, 32),
		bgColor = theme.toColor3(theme.Colors.Loss),
		textColor = theme.toColor3(theme.Colors.TextPrimary),
		onClick = function()
			self:resetDefaults()
		end,
	})
end

return SettingsPage
