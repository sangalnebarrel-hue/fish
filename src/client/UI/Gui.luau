--[[
	Корневые ScreenGui клиента. Три слоя: HUD, панели и оверлей (уведомления, мини-игра).
	Общий UIScale подгоняет интерфейс под экран: на телефоне всё мельче, но кнопки остаются крупными.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Gui = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- Телефон или планшет без клавиатуры: меньше анимаций, кнопки ниже правого края.
Gui.isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local scales: { UIScale } = {}

local function layer(name: string, displayOrder: number): ScreenGui
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = name
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = displayOrder
	screen.IgnoreGuiInset = false
	local scale = Instance.new("UIScale")
	scale.Parent = screen
	table.insert(scales, scale)
	screen.Parent = playerGui
	return screen
end

Gui.hud = layer("FishHud", 1)
Gui.panels = layer("FishPanels", 5)
Gui.overlay = layer("FishOverlay", 10)

-- Интерфейс рассчитан на 1100×620. На маленьких экранах уменьшаем, но не меньше 0.6.
local function updateScale()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local value = math.clamp(math.min(viewport.X / 1100, viewport.Y / 620), 0.6, 1.3)
	for _, scale in scales do
		scale.Scale = value
	end
end

updateScale()
local function watchCamera()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end
watchCamera()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	watchCamera()
	updateScale()
end)

return Gui
