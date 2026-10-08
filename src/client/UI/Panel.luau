--[[
	Модальная панель (магазин, аквариум, индекс, VIP). Одновременно открыта только одна.
]]

local TweenService = game:GetService("TweenService")

local Gui = require(script.Parent.Gui)
local Kit = require(script.Parent.Kit)

local Panel = {}

export type Panel = {
	root: TextButton,
	frame: Frame,
	content: Frame,
	title: TextLabel,
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	onOpen: (() -> ())?,
}

local current: Panel? = nil

function Panel.create(name: string, titleText: string, accent: Color3, size: Vector2?): Panel
	local panelSize = size or Vector2.new(760, 480)
	local root = Kit.make("TextButton", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Parent = Gui.panels,
	})
	local frame = Kit.make("Frame", {
		Name = "Frame",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(panelSize.X, panelSize.Y),
		BackgroundColor3 = Kit.Colors.Panel,
		Active = true, -- клики внутри панели не должны закрывать её
		Parent = root,
	})
	Kit.corner(frame, 22)
	Kit.stroke(frame, Kit.Colors.Stroke, 5)
	local scale = Kit.make("UIScale", { Parent = frame })

	local header = Kit.make("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = accent,
		Parent = frame,
	})
	Kit.corner(header, 22)
	-- закрываем нижние скругления шапки
	Kit.make("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 1, -22),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Parent = header,
	})
	local title = Kit.text({
		Size = UDim2.new(1, -140, 0, 46),
		Position = UDim2.fromOffset(20, 9),
		Text = titleText,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		Parent = header,
	})

	local content = Kit.make("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(16, 76),
		Size = UDim2.new(1, -32, 1, -92),
		BackgroundTransparency = 1,
		Parent = frame,
	})

	local panel: Panel

	local function close()
		if current == panel then
			current = nil
		end
		root.Visible = false
	end

	local function open()
		if current and current ~= panel then
			current.close()
		end
		current = panel
		root.Visible = true
		scale.Scale = 0.85
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if panel.onOpen then
			panel.onOpen()
		end
	end

	Kit.button("✕", Kit.Colors.Red, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(52, 48),
		ZIndex = 3,
		Parent = header,
	}, close)

	-- клик по затемнению вокруг панели закрывает её
	root.Activated:Connect(close)

	panel = {
		root = root,
		frame = frame,
		content = content,
		title = title,
		open = open,
		close = close,
		isOpen = function()
			return root.Visible
		end,
		onOpen = nil,
	}
	return panel
end

function Panel.closeAll()
	if current then
		current.close()
	end
end

-- Вкладки сверху панели. Возвращает функцию выбора вкладки и контейнер содержимого.
function Panel.tabs(panel: Panel, names: { string }, onSelect: (string) -> ()): (Frame, (string) -> ())
	local bar = Kit.make("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Parent = panel.content,
	})
	Kit.list(bar, Enum.FillDirection.Horizontal, 8)
	local body = Kit.make("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 1, -54),
		BackgroundTransparency = 1,
		Parent = panel.content,
	})
	local buttons: { [string]: TextButton } = {}
	local function selectTab(name: string)
		for tabName, button in buttons do
			button.BackgroundColor3 = if tabName == name then Kit.Colors.Blue else Kit.Colors.PanelLight
		end
		onSelect(name)
	end
	for index, name in names do
		buttons[name] = Kit.button(name, Kit.Colors.PanelLight, {
			Size = UDim2.new(1 / #names, -8, 1, 0),
			LayoutOrder = index,
			Parent = bar,
		}, function()
			selectTab(name)
		end)
	end
	return body, selectTab
end

-- Прокручиваемый список карточек.
function Panel.scroll(parent: Instance, cellSize: Vector2?): ScrollingFrame
	local scroll = Kit.make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	})
	if cellSize then
		Kit.make("UIGridLayout", {
			CellSize = UDim2.fromOffset(cellSize.X, cellSize.Y),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = scroll,
		})
	else
		Kit.list(scroll, Enum.FillDirection.Vertical, 8)
	end
	Kit.make("UIPadding", { PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 2), Parent = scroll })
	return scroll
end

function Panel.clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIGridStyleLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

return Panel
