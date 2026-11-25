--!strict
--[[
	SettingsPage.luau
	Interactive configuration controls for AMVGG refresh, timers, profit thresholds,
	UI customization, notifications, and data management.
]]

local SettingsPage = {}
SettingsPage.__index = SettingsPage

local LISTING_TTLS = { 30, 45, 60, 90, 120 }
local OFFER_INTERVALS = { 30, 45, 60 }

function SettingsPage.new(deps: { config: any, amvggProvider: any, scheduler: any, logger: any })
	local self = setmetatable({}, SettingsPage)
	self._config = deps.config
	self._amvgg = deps.amvggProvider
	self._scheduler = deps.scheduler
	self._logger = deps.logger
	self._statusMsg = ""
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

local function nextInCycle(list: { number }, current: number): number
	for i, v in ipairs(list) do
		if v == current then
			return list[(i % #list) + 1]
		end
	end
	return list[1]
end

function SettingsPage:render(container: any, theme: any, widgets: any)
	if not (container and widgets and widgets.isRobloxGuiAvailable()) then
		return
	end
	widgets.clearChildren(container)
	local s = self:getAllSettings()
	local cText = theme.toColor3(theme.Colors.TextPrimary)
	local cMuted = theme.toColor3(theme.Colors.TextMuted)
	local cCard = theme.toColor3(theme.Colors.SurfaceAlt)
	local cBorder = theme.toColor3(theme.Colors.Border)
	local cAccent = theme.toColor3(theme.Colors.Accent)
	local cProfit = theme.toColor3(theme.Colors.Profit)
	local cLoss = theme.toColor3(theme.Colors.Loss)

	widgets.createLabel(container, {
		text = "Settings & Safety Controls",
		size = UDim2.new(1, 0, 0, 24),
		textColor = cText,
		textSize = 17,
		bold = true,
	})

	local scroll = widgets.createScrollFrame(container, {
		size = UDim2.new(1, 0, 1, -76),
		position = UDim2.new(0, 0, 0, 32),
		gap = 8,
	})

	local function addSettingRow(label: string, btnText: string, btnColor: any, onClick: () -> ())
		local row = widgets.createRoundedFrame(scroll, {
			size = UDim2.new(1, -8, 0, 44),
			bgColor = cCard,
			borderColor = cBorder,
			cornerRadius = 6,
			padding = 8,
		})
		widgets.createLabel(row, {
			text = label,
			size = UDim2.new(1, -150, 0, 26),
			textColor = cText,
			textSize = 13,
		})
		widgets.createButton(row, {
			text = btnText,
			size = UDim2.new(0, 136, 0, 28),
			position = UDim2.new(1, -136, 0, 0),
			bgColor = btnColor,
			textColor = cText,
			onClick = onClick,
		})
	end

	addSettingRow(
		"Listing Stale Timer (30 / 45 / 60 / 90 / 120s)",
		tostring(s.Trading.ListingExpirationSeconds) .. "s",
		cAccent,
		function()
			local nxt = nextInCycle(LISTING_TTLS, s.Trading.ListingExpirationSeconds)
			self:setSetting("Trading.ListingExpirationSeconds", nxt)
			self:render(container, theme, widgets)
		end
	)

	addSettingRow(
		"Offer Response Check Interval (30 / 45 / 60s)",
		tostring(s.Trading.OfferResponseIntervalSeconds) .. "s",
		cAccent,
		function()
			local nxt = nextInCycle(OFFER_INTERVALS, s.Trading.OfferResponseIntervalSeconds)
			self:setSetting("Trading.OfferResponseIntervalSeconds", nxt)
			self:render(container, theme, widgets)
		end
	)

	addSettingRow(
		"Minimum Profit % Filter (cycles +5%)",
		string.format("%.1f%%", s.Trading.MinProfitPercent),
		cAccent,
		function()
			local nxt = if s.Trading.MinProfitPercent >= 25 then 0 else s.Trading.MinProfitPercent + 5
			self:setSetting("Trading.MinProfitPercent", nxt)
			self:render(container, theme, widgets)
		end
	)

	addSettingRow(
		"Trading Mode (manual_confirm / practice)",
		tostring(s.Trading.Mode),
		cAccent,
		function()
			local nxt = if s.Trading.Mode == "manual_confirm" then "practice" else "manual_confirm"
			self:setSetting("Trading.Mode", nxt)
			self:render(container, theme, widgets)
		end
	)

	addSettingRow(
		"Kiria Companion Reactions",
		if s.UI.KiriaEnabled then "ENABLED" else "DISABLED",
		if s.UI.KiriaEnabled then cProfit else cLoss,
		function()
			self:setSetting("UI.KiriaEnabled", not s.UI.KiriaEnabled)
			self:render(container, theme, widgets)
		end
	)

	addSettingRow(
		"Toast Notifications",
		if s.UI.NotificationsEnabled then "ENABLED" else "DISABLED",
		if s.UI.NotificationsEnabled then cProfit else cLoss,
		function()
			self:setSetting("UI.NotificationsEnabled", not s.UI.NotificationsEnabled)
			self:render(container, theme, widgets)
		end
	)

	-- Footer Actions
	widgets.createButton(container, {
		text = "Refresh AMVGG Now",
		size = UDim2.new(0, 160, 0, 32),
		position = UDim2.new(0, 0, 1, -34),
		bgColor = cAccent,
		textColor = cText,
		onClick = function()
			local ok, err = self:refreshAmvggNow()
			self._statusMsg = if ok then "AMVGG refreshed" else tostring(err)
			self:render(container, theme, widgets)
		end,
	})

	widgets.createButton(container, {
		text = "Reset Defaults",
		size = UDim2.new(0, 140, 0, 32),
		position = UDim2.new(0, 170, 1, -34),
		bgColor = cLoss,
		textColor = cText,
		onClick = function()
			self:resetDefaults()
			self._statusMsg = "Defaults restored"
			self:render(container, theme, widgets)
		end,
	})

	if self._statusMsg ~= "" then
		widgets.createLabel(container, {
			text = self._statusMsg,
			position = UDim2.new(0, 320, 1, -30),
			size = UDim2.new(1, -320, 0, 22),
			textColor = cMuted,
			textSize = 12,
		})
	end
end

return SettingsPage
