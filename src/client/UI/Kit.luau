--[[
	Маленький набор UI-хелперов: интерфейс целиком собирается кодом, без ассетов.
	Стиль: крупные скруглённые кнопки, толстая обводка — удобно пальцем на телефоне.
]]

local TweenService = game:GetService("TweenService")

local Kit = {}

Kit.Font = Enum.Font.FredokaOne

Kit.Colors = {
	Panel = Color3.fromRGB(28, 38, 68),
	PanelLight = Color3.fromRGB(44, 58, 98),
	Stroke = Color3.fromRGB(12, 16, 30),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(170, 180, 205),
	Green = Color3.fromRGB(70, 200, 95),
	Blue = Color3.fromRGB(55, 140, 240),
	Orange = Color3.fromRGB(250, 150, 40),
	Purple = Color3.fromRGB(150, 90, 240),
	Red = Color3.fromRGB(230, 70, 70),
	Gold = Color3.fromRGB(255, 200, 50),
	Grey = Color3.fromRGB(110, 115, 130),
}

export type Props = { [string]: any }

function Kit.make(className: string, props: Props?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	local properties: Props = props or {}
	local kids: { Instance } = children or {}
	for key, value in properties do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	for _, child in kids do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Kit.corner(parent: Instance, radius: number?): UICorner
	return Kit.make("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = parent })
end

function Kit.stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	return Kit.make("UIStroke", {
		Color = color or Kit.Colors.Stroke,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Kit.padding(parent: Instance, pixels: number): UIPadding
	local p = UDim.new(0, pixels)
	return Kit.make("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p, Parent = parent })
end

function Kit.list(parent: Instance, direction: Enum.FillDirection, padding: number?, alignment: Enum.HorizontalAlignment?): UIListLayout
	return Kit.make("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, padding or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = alignment or Enum.HorizontalAlignment.Left,
		Parent = parent,
	})
end

-- Текст с обводкой (читается на любом фоне).
function Kit.text(props: Props): TextLabel
	local label = Kit.make("TextLabel", {
		BackgroundTransparency = 1,
		Font = Kit.Font,
		TextColor3 = Kit.Colors.Text,
		TextScaled = true,
		RichText = true,
		Text = "",
	})
	for key, value in props do
		(label :: any)[key] = value
	end
	Kit.make("UIStroke", { Color = Kit.Colors.Stroke, Thickness = 2, Parent = label })
	return label
end

-- Кнопка с «нажатием»: при касании слегка сжимается.
function Kit.button(text: string, color: Color3, props: Props?, onClick: (() -> ())?): TextButton
	local button = Kit.make("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = color,
		Font = Kit.Font,
		Text = text,
		TextColor3 = Kit.Colors.Text,
		TextScaled = true,
		RichText = true,
	})
	local properties: Props = props or {}
	for key, value in properties do
		(button :: any)[key] = value
	end
	Kit.corner(button, 14)
	Kit.stroke(button, Kit.Colors.Stroke, 3)
	Kit.make("UIStroke", {
		Color = Kit.Colors.Stroke,
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = button,
	})
	Kit.make("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = button,
	})
	local scale = Kit.make("UIScale", { Parent = button })
	local pressInfo = TweenInfo.new(0.08)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, pressInfo, { Scale = 0.92 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, pressInfo, { Scale = 1 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, pressInfo, { Scale = 1 }):Play()
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

function Kit.rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

return Kit
