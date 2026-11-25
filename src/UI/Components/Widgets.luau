--!strict
--[[
	Widgets.luau
	Reusable Roblox UI component builders with safe headless fallback for tests.
]]

local Widgets = {}

function Widgets.isRobloxGuiAvailable(): boolean
	return type(Instance) == "table" or type(Instance) == "userdata"
end

function Widgets.createRoundedFrame(parent: any, props: {
	name: string?,
	size: any?,
	position: any?,
	bgColor: any?,
	borderColor: any?,
	cornerRadius: number?,
}): any
	if not Widgets.isRobloxGuiAvailable() then
		return nil
	end
	local frame = Instance.new("Frame")
	frame.Name = props.name or "Card"
	frame.Size = props.size or UDim2.new(1, 0, 0, 100)
	frame.Position = props.position or UDim2.new(0, 0, 0, 0)
	frame.BackgroundColor3 = props.bgColor
	frame.BorderSizePixel = 0
	if parent then
		frame.Parent = parent
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, props.cornerRadius or 10)
	corner.Parent = frame

	if props.borderColor then
		local stroke = Instance.new("UIStroke")
		stroke.Color = props.borderColor
		stroke.Thickness = 1
		stroke.Parent = frame
	end

	return frame
end

function Widgets.createButton(parent: any, props: {
	name: string?,
	text: string,
	size: any?,
	position: any?,
	bgColor: any?,
	textColor: any?,
	onClick: () -> (),
}): any
	if not Widgets.isRobloxGuiAvailable() then
		return {
			Name = props.name or "Button",
			Text = props.text,
			trigger = props.onClick,
		}
	end
	local btn = Instance.new("TextButton")
	btn.Name = props.name or "Button"
	btn.Text = props.text
	btn.Size = props.size or UDim2.new(0, 130, 0, 32)
	btn.Position = props.position or UDim2.new(0, 0, 0, 0)
	btn.BackgroundColor3 = props.bgColor
	btn.TextColor3 = props.textColor
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamSemibold
	btn.TextSize = 13
	btn.BorderSizePixel = 0
	if parent then
		btn.Parent = parent
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn

	btn.MouseButton1Click:Connect(props.onClick)
	return btn
end

function Widgets.createLabel(parent: any, props: {
	text: string,
	size: any?,
	position: any?,
	textColor: any?,
	textSize: number?,
	bold: boolean?,
	xAlign: any?,
}): any
	if not Widgets.isRobloxGuiAvailable() then
		return nil
	end
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Text = props.text
	lbl.Size = props.size or UDim2.new(1, 0, 0, 22)
	lbl.Position = props.position or UDim2.new(0, 0, 0, 0)
	lbl.TextColor3 = props.textColor
	lbl.TextSize = props.textSize or 14
	lbl.Font = if props.bold then Enum.Font.GothamBold else Enum.Font.Gotham
	lbl.TextXAlignment = props.xAlign or Enum.TextXAlignment.Left
	lbl.TextWrapped = true
	if parent then
		lbl.Parent = parent
	end
	return lbl
end

return Widgets
