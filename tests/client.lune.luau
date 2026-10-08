--[[
	Смоук-тест клиента без Roblox Studio: поднимает в Lune весь клиент (init.client),
	открывает все панели и проигрывает основные сценарии: заброс → поклёвка → подсечка → улов,
	уведомления, тревогу, эффекты, ведро с рыбой. Любая ошибка или warn в клиентском коде —
	провал теста.

		rojo build default.project.json -o build/game.rbxl
		lune run tests/client.lune.luau build/game.rbxl [touch|desktop]
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Runtime = require("./lune/runtime")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local placePath = process.args[1] or "build/game.rbxl"
local device = process.args[2] or "touch"
local rt = Runtime.load(placePath)
local game = rt.game
local suite = Runtime.suite()
local test, expect = suite.test, suite.expect

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:FindFirstChild("Shared")
local Services = game:GetService("ServerScriptService"):FindFirstChild("Server"):FindFirstChild("Services")
local ClientScript = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")

-- Сервер: remote'ы, состояние ивентов и карта (клиент опирается на теги мира) ---------------------

rt.mode.server = true
local Net = rt.require(Shared.Net)
local state = Net.state()
local now = Workspace:GetServerTimeNow()
state:SetAttribute("Shoal_EndsAt", now + 120)
state:SetAttribute("Shoal_NextAt", now + 1800)
state:SetAttribute("Storm_EndsAt", now + 60)
state:SetAttribute("Storm_NextAt", now + 2700)
state:SetAttribute("IsNight", true)
local MapService = rt.require(Services.MapService)
MapService.init()
rt.syncPositions(Workspace:FindFirstChild("Map"))

-- Клиент: игрок стоит на пирсе ------------------------------------------------------------

rt.mode.server = false
local players = game:GetService("Players")
local player = Instance.new("Player")
player.Name = "Tester"
player.DisplayName = "Tester"
player.UserId = 4242
player.Parent = players
players.LocalPlayer = player
Instance.new("PlayerGui").Parent = player
player:SetAttribute("Money", 12345)
player:SetAttribute("Income", 42)
player:SetAttribute("BaseIndex", 1)

local character = Instance.new("Model")
character.Name = "Tester"
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2, 2, 1)
root.CFrame = CFrame.new(0, 5.2, -200)
root.Parent = character
local head = Instance.new("Part")
head.Name = "Head"
head.Parent = character
local humanoid = Instance.new("Humanoid")
humanoid.Health = 100 -- у Lune нет значений по умолчанию для части свойств
humanoid.Parent = character
character.PrimaryPart = root
character.Parent = Workspace
rt.syncPositions(character)
player.Character = character

local camera = Instance.new("Camera")
camera.Parent = Workspace
Workspace.CurrentCamera = camera
-- В Roblox эти свойства только для чтения, а в Lune их можно задать — так эмулируем устройство.
camera.ViewportSize = if device == "touch" then Vector2.new(844, 390) else Vector2.new(1920, 1080)
local UserInputService = game:GetService("UserInputService")
UserInputService.TouchEnabled = device == "touch"
UserInputService.KeyboardEnabled = device ~= "touch"

local myBase = Workspace:FindFirstChild("Map"):FindFirstChild("Bases"):FindFirstChild("Base1")
myBase:SetAttribute("OwnerUserId", player.UserId)

-- Ответы «сервера» --------------------------------------------------------------------------

local snapshot = {
	Money = 12345,
	TotalEarned = 20000,
	Rod = "Bamboo",
	OwnedRods = { Stick = true, Bamboo = true },
	Bucket = "Leaky",
	OwnedBuckets = { Leaky = true },
	FinsLevel = 3,
	AquariumTier = 1,
	Fish = {
		{ Uid = "u1", Id = "SockFish", Size = "Fry" },
		{ Uid = "u2", Id = "ShadesPerch", Size = "Large", Mutation = "Golden" },
		{ Uid = "u3", Id = "ChefOcto", Size = "Normal", Mutation = "Electric" },
	},
	SafeUid = "u2",
	Baits = { Shrimp = 4, Firefly = 0, GoldenBait = 0, SecretLure = 0 },
	SelectedBait = "Shrimp",
	Index = { SockFish = true, ShadesPerch = true, ChefOcto = true },
	IndexRewards = 0,
	UnlockedZones = { Pier = true },
	Rebirths = 0,
	LastLogout = 0,
	LastIncome = 0,
	Stats = { Caught = 3, Stolen = 0, LostToThieves = 0, Sold = 0 },
	Onboarding = 3,
	Transit = { "u3" },
	MaxSlots = 6,
}

local fired: { { any } } = {}
local invokeHandlers: { [string]: (...any) -> ...any } = {
	RequestSync = function()
		return snapshot
	end,
	Cast = function()
		return true, { castId = 1, zoneId = "Pier", baitId = "Shrimp" }
	end,
	Purchase = function()
		return true, "Куплено"
	end,
	Sell = function()
		return true, "Продано"
	end,
	SetSafe = function()
		return true, "Сейф"
	end,
}
roblox.implementMethod("RemoteFunction", "InvokeServer", function(self, ...)
	local handler = invokeHandlers[self.Name]
	assert(handler, `no server handler for {self.Name}`)
	return handler(...)
end)
roblox.implementMethod("RemoteEvent", "FireServer", function(self, ...)
	table.insert(fired, { self.Name, ... })
end)

local function remote(name: string)
	return Net.event(name)
end

local function fireRemote(name: string, ...)
	rt.signalOf(remote(name), "OnClientEvent"):Fire(...)
end

local function firedCount(name: string): number
	local count = 0
	for _, entry in fired do
		if entry[1] == name then
			count += 1
		end
	end
	return count
end

local function activate(button)
	rt.signalOf(button, "MouseButton1Down"):Fire()
	rt.signalOf(button, "MouseButton1Up"):Fire()
	rt.signalOf(button, "Activated"):Fire()
end

local function renderFrames(count: number)
	local runService = game:GetService("RunService")
	for _ = 1, count do
		rt.signalOf(runService, "RenderStepped"):Fire(1 / 60)
		task.wait(1 / 60)
	end
end

-- Запуск клиента ------------------------------------------------------------------------------

rt.runScript(ClientScript)
task.wait(0.3)

local Controllers = ClientScript:FindFirstChild("Controllers")
local Hud = rt.require(Controllers.Hud)
local ShopPanel = rt.require(Controllers.ShopPanel)
local AquariumPanel = rt.require(Controllers.AquariumPanel)
local IndexPanel = rt.require(Controllers.IndexPanel)
local State = rt.require(Controllers.State)
local playerGui = player:FindFirstChild("PlayerGui")

test(`[{device}] интерфейс собран`, function()
	for _, name in { "FishHud", "FishPanels", "FishOverlay" } do
		expect(playerGui:FindFirstChild(name), `нет {name}`)
	end
	expect(State.data ~= nil, "клиент запросил снимок данных")
	expect(Hud.castButton and Hud.baitButton, "кнопки рыбалки")
end)

test(`[{device}] у воды появляется кнопка «Закинуть» и наживка`, function()
	fireRemote("DataSync", snapshot)
	task.wait(0.4)
	expect(Hud.castButton.Visible, "кнопка заброса на пирсе")
	expect(Hud.baitButton.Text:find("Креветка"), `наживка: {Hud.baitButton.Text}`)
end)

test(`[{device}] заброс → поклёвка → подсечка → улов`, function()
	activate(Hud.castButton)
	task.wait(0.2)
	expect(Hud.castButton.Text:find("Ждём"), `после заброса: {Hud.castButton.Text}`)
	fireRemote("FishingBite", 1, "Epic", { zoneCenter = 0.5, zoneWidth = 0.3, speed = 1.3, window = 4, autoHook = false })
	renderFrames(10)
	local overlay = playerGui:FindFirstChild("FishOverlay"):FindFirstChild("HookGame")
	expect(overlay and overlay.Visible, "мини-игра на экране")
	activate(overlay)
	expect(firedCount("Hook") == 1, "подсечка ушла на сервер")
	fireRemote("FishingEnded", 1, "caught", { Uid = "new", Id = "ChefOcto", Size = "Large", Mutation = "Golden" })
	task.wait(0.6)
	expect(not overlay.Visible, "мини-игра закрылась")
	-- второй заброс с сорвавшейся рыбой и автоподсечкой
	activate(Hud.castButton)
	task.wait(0.1)
	fireRemote("FishingBite", 1, "Rare", { zoneCenter = 0.2, zoneWidth = 0.4, speed = 1, window = 4, autoHook = true })
	expect(firedCount("Hook") == 2, "Нептун подсекает сам")
	fireRemote("FishingEnded", 1, "escaped")
	task.wait(0.5)
end)

test(`[{device}] все панели и вкладки открываются`, function()
	ShopPanel.openShop()
	local shop = playerGui:FindFirstChild("FishPanels"):FindFirstChild("Shop")
	local tabs = shop:FindFirstChild("Frame"):FindFirstChild("Content"):FindFirstChild("Tabs")
	local tabCount = 0
	for _, button in tabs:GetChildren() do
		if button:IsA("TextButton") then
			activate(button)
			tabCount += 1
		end
	end
	expect(tabCount == 5, "пять вкладок магазина")
	player:SetAttribute("Money", 999999)
	rt.signalOf(player, "attribute:Money"):Fire()
	AquariumPanel.open()
	expect(not shop.Visible, "одновременно открыта одна панель")
	IndexPanel.open()
	ShopPanel.openPasses()
	-- покупка и продажа из панелей
	ShopPanel.openShop()
	local list = shop:FindFirstChild("Frame"):FindFirstChild("Content"):FindFirstChild("Body"):FindFirstChildOfClass("ScrollingFrame")
	for _, card in list:GetChildren() do
		local button = card:IsA("Frame") and card:FindFirstChildOfClass("TextButton")
		if button then
			activate(button)
		end
	end
	expect(true)
	task.wait(0.2)
end)

test(`[{device}] уведомления, тревога и офлайн-доход`, function()
	fireRemote("Notify", "Привет", "good")
	fireRemote("Notify", "Плохо", "bad")
	for i = 1, 6 do
		fireRemote("Notify", `Тост {i}`, "info")
	end
	fireRemote("Alarm", "Вор")
	fireRemote("OfflineEarnings", 5000, 7300)
	fireRemote("OpenUI", "Market")
	fireRemote("OpenUI", "Shop")
	task.wait(0.3)
	local toasts = playerGui:FindFirstChild("FishOverlay"):FindFirstChild("Toasts")
	local count = 0
	for _, child in toasts:GetChildren() do
		if child:IsA("Frame") then
			count += 1
		end
	end
	expect(count <= 4, `не больше 4 уведомлений, а их {count}`)
end)

test(`[{device}] шлепок, замок и наживка с клавиатуры и кнопок`, function()
	local inputBegan = rt.signalOf(UserInputService, "InputBegan")
	inputBegan:Fire({ KeyCode = Enum.KeyCode.F, UserInputType = Enum.UserInputType.Keyboard }, false)
	inputBegan:Fire({ KeyCode = Enum.KeyCode.L, UserInputType = Enum.UserInputType.Keyboard }, false)
	expect(firedCount("Slap") == 1 and firedCount("Lock") == 1, "F — шлепок, L — замок")
	activate(Hud.baitButton)
	expect(firedCount("SelectBait") == 1, "смена наживки")
	-- игрок на своей базе: появляется кнопка замка
	root.CFrame = myBase:FindFirstChild("Floor").CFrame * CFrame.new(0, 3, 0)
	rt.syncPositions(root)
	player:SetAttribute("LockCooldownUntil", Workspace:GetServerTimeNow() + 100)
	task.wait(0.4)
end)

test(`[{device}] ведро: полоска кислорода, метки дома и луж`, function()
	player:SetAttribute("CarryFish", "SockFish")
	local bar = Instance.new("BillboardGui")
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Parent = back
	local time = Instance.new("TextLabel")
	time.Name = "Time"
	time.Parent = back
	bar:SetAttribute("Oxygen", 20)
	bar:SetAttribute("OxygenMax", 30)
	bar:SetAttribute("Rate", 1)
	bar:SetAttribute("Stamp", Workspace:GetServerTimeNow())
	bar:AddTag("OxygenBar")
	bar.Parent = head
	renderFrames(5)
	expect(time.Text:find("с"), `таймер кислорода: {time.Text}`)
	task.wait(0.4)
end)

test(`[{device}] рыбы в аквариуме плавают, медузы двигаются`, function()
	local fish = rt.require(Shared.FishModel).build({ Id = "DJPuffer", Size = "Normal" }, { anchored = true })
	fish:SetAttribute("OwnerUserId", player.UserId)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Parent = fish.PrimaryPart
	fish:AddTag("AquariumFish")
	fish.Parent = myBase:FindFirstChild("Fish")
	rt.announceTags(myBase)
	task.wait(2.5)
	expect(prompt.Enabled == false, "на своей рыбе нет кнопки «Украсть»")
	renderFrames(3)
end)

test(`[{device}] эффекты и тег VIP в чате`, function()
	fireRemote("Knockback", Vector3.new(30, 25, 0))
	fireRemote("Effect", "Lightning", Vector3.new(0, 1, 0))
	fireRemote("Effect", "Slap", Vector3.new(0, 1, 0))
	renderFrames(3)
	player:SetAttribute("VIP", true)
	local callback = rt.textChatService.OnIncomingMessage
	expect(type(callback) == "function", "колбэк чата установлен")
	local properties = callback({ TextSource = { UserId = player.UserId }, PrefixText = "Tester:" })
	expect(properties and properties.PrefixText:find("VIP"), "префикс VIP")
	task.wait(0.8)
end)

test(`[{device}] в клиенте не было ошибок и warn`, function()
	expect(#rt.failures == 0, table.concat(rt.failures, "\n"))
end)

print(`{suite.passed} passed, {suite.failed} failed`)
process.exit(if suite.failed > 0 then 1 else 0)
