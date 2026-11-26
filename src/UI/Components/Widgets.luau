--!strict
--[[
	Widgets.luau
	Reusable Roblox UI component builders with safe headless fallback for tests.
]]

local Widgets = {}

function Widgets.isRobloxGuiAvailable(): boolean
	return type(Instance) == "table" or type(Instance) == "userdata"
end

function Widgets.clearChildren(container: any)
	if not container then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UILayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

function Widgets.createRoundedFrame(parent: any, props: {
	name: string?,
	size: any?,
	position: any?,
	bgColor: any?,
	borderColor: any?,
	cornerRadius: number?,
	padding: number?,
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

	if props.padding and props.padding > 0 then
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, props.padding)
		pad.PaddingBottom = UDim.new(0, props.padding)
		pad.PaddingLeft = UDim.new(0, props.padding)
		pad.PaddingRight = UDim.new(0, props.padding)
		pad.Parent = frame
	end

	return frame
end

function Widgets.createScrollFrame(parent: any, props: {
	name: string?,
	size: any?,
	position: any?,
	bgColor: any?,
	gap: number?,
}): any
	if not Widgets.isRobloxGuiAvailable() then
		return nil
	end
	local sf = Instance.new("ScrollingFrame")
	sf.Name = props.name or "Scroll"
	sf.Size = props.size or UDim2.new(1, 0, 1, 0)
	sf.Position = props.position or UDim2.new(0, 0, 0, 0)
	if props.bgColor then
		sf.BackgroundColor3 = props.bgColor
		sf.BackgroundTransparency = 0
	else
		sf.BackgroundTransparency = 1
	end
	sf.BorderSizePixel = 0
	sf.ScrollBarThickness = 5
	sf.CanvasSize = UDim2.new(0, 0, 0, 0)
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	if parent then
		sf.Parent = parent
	end

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, props.gap or 8)
	layout.Parent = sf

	return sf
end

function Widgets.createButton(parent: any, props: {
	name: string?,
	text: string,
	size: any?,
	position: any?,
	bgColor: any?,
	textColor: any?,
	textSize: number?,
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
	btn.TextSize = props.textSize or 13
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

function Widgets.createTextBox(parent: any, props: {
	name: string?,
	text: string?,
	placeholder: string?,
	size: any?,
	position: any?,
	bgColor: any?,
	textColor: any?,
	placeholderColor: any?,
	borderColor: any?,
	onFocusLost: ((string, boolean) -> ())?,
}): any
	if not Widgets.isRobloxGuiAvailable() then
		return { Text = props.text or "" }
	end
	local tb = Instance.new("TextBox")
	tb.Name = props.name or "Input"
	tb.Text = props.text or ""
	tb.PlaceholderText = props.placeholder or ""
	tb.Size = props.size or UDim2.new(0, 200, 0, 32)
	tb.Position = props.position or UDim2.new(0, 0, 0, 0)
	tb.BackgroundColor3 = props.bgColor
	tb.TextColor3 = props.textColor
	if props.placeholderColor then
		tb.PlaceholderColor3 = props.placeholderColor
	end
	tb.Font = Enum.Font.Gotham
	tb.TextSize = 13
	tb.TextXAlignment = Enum.TextXAlignment.Left
	tb.ClearTextOnFocus = false
	tb.BorderSizePixel = 0
	if parent then
		tb.Parent = parent
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = tb

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = tb

	if props.borderColor then
		local stroke = Instance.new("UIStroke")
		stroke.Color = props.borderColor
		stroke.Thickness = 1
		stroke.Parent = tb
	end

	if props.onFocusLost then
		tb.FocusLost:Connect(function(enterPressed)
			props.onFocusLost(tb.Text, enterPressed)
		end)
	end
	return tb
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

function Widgets.createStatCard(parent: any, props: {
	title: string,
	value: string,
	subtitle: string?,
	size: any?,
	position: any?,
	bgColor: any?,
	borderColor: any?,
	titleColor: any?,
	valueColor: any?,
}): any
	if not Widgets.isRobloxGuiAvailable() then
		return nil
	end
	local card = Widgets.createRoundedFrame(parent, {
		name = "Stat_" .. props.title,
		size = props.size or UDim2.new(0.24, -6, 0, 68),
		position = props.position,
		bgColor = props.bgColor,
		borderColor = props.borderColor,
		cornerRadius = 8,
		padding = 8,
	})
	Widgets.createLabel(card, {
		text = props.title,
		size = UDim2.new(1, 0, 0, 16),
		textColor = props.titleColor,
		textSize = 11,
	})
	Widgets.createLabel(card, {
		text = props.value,
		position = UDim2.new(0, 0, 0, 18),
		size = UDim2.new(1, 0, 0, 22),
		textColor = props.valueColor,
		textSize = 16,
		bold = true,
	})
	if props.subtitle then
		Widgets.createLabel(card, {
			text = props.subtitle,
			position = UDim2.new(0, 0, 0, 40),
			size = UDim2.new(1, 0, 0, 14),
			textColor = props.titleColor,
			textSize = 10,
		})
	end
	return card
end

function Widgets.makeDraggable(targetFrame: any, handle: any): { any }
	if not Widgets.isRobloxGuiAvailable() then
		return {}
	end
	local conns = {}
	local dragging = false
	local dragStart: any = nil
	local startPos: any = nil

	table.insert(conns, handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = targetFrame.Position
		end
	end))

	table.insert(conns, handle.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	local okUis, UserInputService = pcall(function()
		return game:GetService("UserInputService")
	end)
	if okUis and UserInputService then
		table.insert(conns, UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - dragStart
				targetFrame.Position = UDim2.new(
					startPos.X.Scale,
					startPos.X.Offset + delta.X,
					startPos.Y.Scale,
					startPos.Y.Offset + delta.Y
				)
			end
		end))
	end

	return conns
end

return Widgets
