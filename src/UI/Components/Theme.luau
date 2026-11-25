--!strict
--[[
	Theme.luau
	Kiria Dark Trading Terminal visual palette and typography tokens.
]]

local Theme = {}

Theme.Colors = {
	Background = "#0B0E17",
	Surface = "#121726",
	SurfaceAlt = "#181F33",
	Border = "#2A3352",
	Accent = "#9D4EDD",
	AccentBright = "#C77DFF",
	TextPrimary = "#F1F5F9",
	TextMuted = "#94A3B8",
	Profit = "#22C55E",
	Loss = "#EF4444",
	Warning = "#F59E0B",
	Info = "#38BDF8",
}

Theme.Layout = {
	CornerRadius = 10,
	SmallCorner = 6,
	Padding = 12,
	Gap = 10,
	SidebarWidth = 180,
	HeaderHeight = 48,
}

function Theme.toColor3(hex: string): any
	if type(Color3) ~= "table" and type(Color3) ~= "userdata" then
		return hex
	end
	local clean = hex:gsub("#", "")
	local r = tonumber(string.sub(clean, 1, 2), 16) or 157
	local g = tonumber(string.sub(clean, 3, 4), 16) or 78
	local b = tonumber(string.sub(clean, 5, 6), 16) or 221
	return Color3.fromRGB(r, g, b)
end

return Theme
