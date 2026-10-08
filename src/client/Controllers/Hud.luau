--[[
	Основной интерфейс: деньги и доход, таймеры ивентов, подсказка «что делать дальше»,
	меню (аквариум, индекс, VIP) и крупные кнопки действий для телефона:
	«Закинуть» (C), «Шлёп» (F), «Замок» (L).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local ShopData = require(Shared.ShopData)

local UI = script.Parent.Parent:WaitForChild("UI")
local Gui = require(UI:WaitForChild("Gui"))
local Kit = require(UI:WaitForChild("Kit"))

local State = require(script.Parent.State)
local Notifications = require(script.Parent.Notifications)
local ShopPanel = require(script.Parent.ShopPanel)
local AquariumPanel = require(script.Parent.AquariumPanel)
local IndexPanel = require(script.Parent.IndexPanel)

local Hud = {}

local player = Players.LocalPlayer

Hud.castButton = nil :: TextButton?
Hud.baitButton = nil :: TextButton?

local moneyLabel: TextLabel
local incomeLabel: TextLabel
local eventLabel: TextLabel
local hintLabel: TextLabel
local slapButton: TextButton
local lockButton: TextButton

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- Верх: деньги ---------------------------------------------------------------------

local function buildMoney()
	local pill = Kit.make("Frame", {
		Name = "Money",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(300, 82),
		BackgroundColor3 = Kit.Colors.Panel,
		BackgroundTransparency = 0.1,
		Parent = Gui.hud,
	})
	Kit.corner(pill, 20)
	Kit.stroke(pill, Kit.Colors.Stroke, 3)
	moneyLabel = Kit.text({
		Position = UDim2.fromOffset(10, 4),
		Size = UDim2.new(1, -20, 0, 46),
		Text = "💰 $0",
		TextColor3 = Kit.Colors.Gold,
		Parent = pill,
	})
	incomeLabel = Kit.text({
		Position = UDim2.fromOffset(10, 50),
		Size = UDim2.new(1, -20, 0, 26),
		Text = "+$0/с",
		TextColor3 = Kit.Colors.Green,
		Parent = pill,
	})
	local function update()
		moneyLabel.Text = `💰 {Format.money(State.money())}`
		incomeLabel.Text = `+{Format.perSecond(State.income())}`
	end
	player:GetAttributeChangedSignal("Money"):Connect(update)
	player:GetAttributeChangedSignal("Income"):Connect(update)
	update()
end

-- Ивенты и подсказка ----------------------------------------------------------------

local EVENT_LINES = {
	{ Id = "Shoal", Icon = "🐟", Name = "Косяк", Active = "клёв ×2" },
	{ Id = "Storm", Icon = "⛈", Name = "Шторм", Active = "⚡ Электрические рыбы" },
}

local function buildEvents()
	eventLabel = Kit.text({
		Name = "Events",
		Position = UDim2.fromOffset(12, 60),
		Size = UDim2.fromOffset(330, 78),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextScaled = false,
		TextSize = 22,
		Parent = Gui.hud,
	})
	hintLabel = Kit.text({
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(640, 34),
		TextColor3 = Color3.fromRGB(255, 240, 160),
		Parent = Gui.hud,
	})
end

local function updateEvents()
	local state = ReplicatedStorage:FindFirstChild("GameState")
	if not state then
		return
	end
	local t = serverNow()
	local lines = {}
	for _, line in EVENT_LINES do
		local endsAt = (state:GetAttribute(`{line.Id}_EndsAt`) :: number?) or 0
		local nextAt = (state:GetAttribute(`{line.Id}_NextAt`) :: number?) or 0
		if endsAt > t then
			table.insert(lines, `<font color="#FFD54A">{line.Icon} {line.Name}: {Format.time(endsAt - t)} — {line.Active}</font>`)
		elseif nextAt > t then
			table.insert(lines, `{line.Icon} {line.Name} через {Format.time(nextAt - t)}`)
		end
	end
	if state:GetAttribute("IsNight") then
		table.insert(lines, "🌙 Ночь: Светлячок ловит Epic ×2")
	end
	eventLabel.Text = table.concat(lines, "\n")
end

local function goalHint(): string
	local data = State.data
	if State.isCarrying() then
		return "🪣 Неси рыбу в свой аквариум, пока она не задохнулась! 💧 Лужи добавляют кислород"
	end
	if not data then
		return ""
	end
	local fishCount = #(data.Fish :: { any })
	if data.MaxSlots and fishCount >= data.MaxSlots then
		return "🐠 Аквариум полон: продай рыбу на 💰 рынке или расширь его в магазине"
	end
	if (data.Stats.Caught or 0) == 0 and fishCount == 0 then
		return "🎣 Иди на Пирс (дорожка на север) и закинь удочку у воды"
	end
	local money = State.money()
	if not data.UnlockedZones.Lake and money >= 1000 then
		return "🔓 Озеро можно открыть у ворот на востоке — там рыба получше"
	end
	if not data.UnlockedZones.Reef and money >= 25000 then
		return "🔓 Коралловый риф открывается у ворот на юге. Туда далеко — бери ведро получше!"
	end
	return ""
end

-- Кнопки действий -------------------------------------------------------------------

local function insideOwnBase(margin: number): boolean
	local base = State.myBase()
	local floor = base and base:FindFirstChild("Floor") :: BasePart?
	local root = State.root()
	if not floor or not root then
		return false
	end
	local localPos = floor.CFrame:PointToObjectSpace(root.Position)
	local half = floor.Size.X / 2 + margin
	return math.abs(localPos.X) <= half and math.abs(localPos.Z) <= half
end

local function slap()
	local readyAt = (player:GetAttribute("SlapReadyAt") :: number?) or 0
	if readyAt > serverNow() then
		return
	end
	Net.event("Slap"):FireServer()
end

local function lock()
	Net.event("Lock"):FireServer()
end

local function cycleBait()
	local data = State.data
	if not data then
		return
	end
	local list = ShopData.BaitList
	local currentIndex = 1
	for index, bait in list do
		if bait.Id == data.SelectedBait then
			currentIndex = index
		end
	end
	for step = 1, #list do
		local bait = list[(currentIndex - 1 + step) % #list + 1]
		if bait.Infinite or (data.Baits[bait.Id] or 0) > 0 then
			Net.event("SelectBait"):FireServer(bait.Id)
			Notifications.show(`Наживка: {bait.Name}`, "info")
			return
		end
	end
end

local function buildActions()
	local column = Kit.make("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		-- на телефоне справа внизу кнопка прыжка — поднимаем колонку над ней
		Position = if Gui.isTouch then UDim2.new(1, -16, 1, -190) else UDim2.new(1, -20, 1, -24),
		Size = UDim2.fromOffset(210, 330),
		BackgroundTransparency = 1,
		Parent = Gui.hud,
	})
	local layout = Kit.list(column, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Right)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom

	local keyHint = if Gui.isTouch then "" else " [L]"
	lockButton = Kit.button(`🔒 ЗАМОК{keyHint}`, Kit.Colors.Purple, {
		Size = UDim2.fromOffset(190, 62),
		LayoutOrder = 1,
		Visible = false,
		Parent = column,
	}, lock)

	slapButton = Kit.button(`👋 ШЛЁП{if Gui.isTouch then "" else " [F]"}`, Kit.Colors.Orange, {
		Size = UDim2.fromOffset(190, 68),
		LayoutOrder = 2,
		Parent = column,
	}, slap)

	Hud.baitButton = Kit.button("🪱 Червяк", Kit.Colors.PanelLight, {
		Size = UDim2.fromOffset(190, 44),
		LayoutOrder = 3,
		Visible = false,
		Parent = column,
	}, cycleBait)

	Hud.castButton = Kit.button(`🎣 ЗАКИНУТЬ{if Gui.isTouch then "" else " [C]"}`, Kit.Colors.Blue, {
		Size = UDim2.fromOffset(206, 92),
		LayoutOrder = 4,
		Visible = false,
		Parent = column,
	})
end

local function updateActions()
	local t = serverNow()
	local slapReady = (player:GetAttribute("SlapReadyAt") :: number?) or 0
	local suffix = if Gui.isTouch then "" else " [F]"
	if slapReady > t then
		slapButton.Text = `👋 {string.format("%.1f", slapReady - t)}`
		slapButton.BackgroundColor3 = Kit.Colors.Grey
	else
		slapButton.Text = `👋 ШЛЁП{suffix}`
		slapButton.BackgroundColor3 = Kit.Colors.Orange
	end

	local atBase = insideOwnBase(4)
	lockButton.Visible = atBase
	if atBase then
		local base = State.myBase()
		local lockedUntil = if base then (base:GetAttribute("LockedUntil") :: number?) or 0 else 0
		local cooldown = (player:GetAttribute("LockCooldownUntil") :: number?) or 0
		if lockedUntil > t then
			lockButton.Text = `🔒 {Format.time(lockedUntil - t)}`
			lockButton.BackgroundColor3 = Kit.Colors.Gold
		elseif cooldown > t then
			lockButton.Text = `🔒 {Format.time(cooldown - t)}`
			lockButton.BackgroundColor3 = Kit.Colors.Grey
		else
			lockButton.Text = `🔒 ЗАМОК{if Gui.isTouch then "" else " [L]"}`
			lockButton.BackgroundColor3 = Kit.Colors.Purple
		end
	end

	local data = State.data
	local bait = Hud.baitButton
	if data and bait then
		local info = ShopData.Baits[data.SelectedBait] or ShopData.Baits.Worm
		local count = if info.Infinite then "∞" else tostring(data.Baits[info.Id] or 0)
		bait.Text = `🪱 {info.Name}: {count}`
	end
end

-- Меню слева -------------------------------------------------------------------------

local function buildMenu()
	local column = Kit.make("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.44, 0),
		Size = UDim2.fromOffset(150, 220),
		BackgroundTransparency = 1,
		Parent = Gui.hud,
	})
	Kit.list(column, Enum.FillDirection.Vertical, 10)
	Kit.button("🐠 Аквариум", Kit.Colors.Blue, { Size = UDim2.fromOffset(150, 58), LayoutOrder = 1, Parent = column }, AquariumPanel.open)
	Kit.button("📖 Индекс", Kit.Colors.Purple, { Size = UDim2.fromOffset(150, 58), LayoutOrder = 2, Parent = column }, IndexPanel.open)
	Kit.button("⭐ VIP", Kit.Colors.Gold, { Size = UDim2.fromOffset(150, 58), LayoutOrder = 3, Parent = column }, ShopPanel.openPasses)
end

function Hud.start()
	buildMoney()
	buildEvents()
	buildActions()
	buildMenu()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F then
			slap()
		elseif input.KeyCode == Enum.KeyCode.L then
			lock()
		end
	end)

	task.spawn(function()
		while true do
			updateEvents()
			updateActions()
			hintLabel.Text = goalHint()
			task.wait(0.2)
		end
	end)
end

return Hud
