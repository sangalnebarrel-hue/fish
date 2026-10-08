--[[
	Сценарный смоук-тест сервера без Roblox Studio: в Lune запускаются все сервисы,
	на сервер заходят два игрока и проходят основной цикл диздока:
	рыбалка → ведро и кислород → лужа → аквариум → доход → кража → шлепок → подбор →
	доставка вором → магазин и рынок → ворота зоны → ивенты → замок → выход вора с рыбой.

		rojo build default.project.json -o build/game.rbxl
		lune run tests/server.lune.luau build/game.rbxl

	Сохранения работают на заглушке ProfileStore (как в Studio без доступа к API).
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Runtime = require("./lune/runtime")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local placePath = process.args[1] or "build/game.rbxl"
local rt = Runtime.load(placePath)
local game = rt.game
local suite = Runtime.suite()
local test, expect = suite.test, suite.expect

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
local ServerScript = game:GetService("ServerScriptService"):FindFirstChild("Server")
local Services = ServerScript:FindFirstChild("Services")

-- Ускоряем ожидание поклёвки и выключаем защиту новичка, чтобы тест шёл секунды.
rt.mode.server = true
local Config = rt.require(Shared.Config)
Config.Fishing.BiteDelayMin = 0.05
Config.Fishing.BiteDelayMax = 0.1
Config.Fishing.CastCooldown = 0.05
Config.NewbieProtection = 0

rt.runScript(ServerScript)
rt.syncPositions(Workspace:FindFirstChild("Map"))

local Net = rt.require(Shared.Net)
local DataService = rt.require(Services.DataService)
local MapService = rt.require(Services.MapService)
local BaseService = rt.require(Services.BaseService)
local BucketService = rt.require(Services.BucketService)
local EconomyService = rt.require(Services.EconomyService)
local EventService = rt.require(Services.EventService)

-- Хелперы ---------------------------------------------------------------------------------

local function makeCharacter(name: string)
	local character = Instance.new("Model")
	character.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(0, 5, 30)
	root.Parent = character
	for _, partName in { "Head", "RightHand" } do
		local part = Instance.new("Part")
		part.Name = partName
		part.Size = Vector3.new(1, 1, 1)
		part.CFrame = root.CFrame * CFrame.new(0, 1.5, 0)
		part.Parent = character
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.Parent = character
	character.PrimaryPart = root
	rt.syncPositions(character)
	return character
end

local function addPlayer(name: string, userId: number)
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.Parent = Players
	local character = makeCharacter(name)
	character.Parent = Workspace
	player.Character = character
	rt.signalOf(Players, "PlayerAdded"):Fire(player)
	for _ = 1, 100 do
		if DataService.isLoaded(player) and BaseService.plotOf(player) then
			break
		end
		task.wait(0.05)
	end
	rt.signalOf(player, "CharacterAdded"):Fire(character)
	task.wait(0.1)
	return player
end

local function rootOf(player)
	return player.Character:FindFirstChild("HumanoidRootPart")
end

local function moveTo(player, cf)
	local character = player.Character
	character:PivotTo(if typeof(cf) == "Vector3" then CFrame.new(cf) else cf)
	rt.syncPositions(character)
end

local function heartbeat(dt: number, times: number?)
	for _ = 1, times or 1 do
		rt.signalOf(RunService, "Heartbeat"):Fire(dt)
	end
	task.wait(0.02)
	rt.flushAttributes()
	task.wait(0.02)
end

local function invoke(name: string, player, ...)
	local callback = rt.callbacks[Net.func(name)]
	assert(callback, `{name}: OnServerInvoke не назначен`)
	return callback(player, ...)
end

local function fireServer(name: string, player, ...)
	rt.signalOf(Net.event(name), "OnServerEvent"):Fire(player, ...)
end

local function lastClientEvent(remote: string, player)
	for index = #rt.clientEvents, 1, -1 do
		local entry = rt.clientEvents[index]
		if entry.remote == remote and (player == nil or entry.player == player) then
			return entry
		end
	end
	return nil
end

local function notifications(player): string
	local texts = {}
	for _, entry in rt.clientEvents do
		if entry.remote == "Notify" and entry.player == player then
			table.insert(texts, tostring(entry.args[1]))
		end
	end
	return table.concat(texts, " | ")
end

local function catchFish(player)
	moveTo(player, Vector3.new(0, 5.2, -200))
	local ok, info = invoke("Cast", player)
	assert(ok, `заброс не удался: {tostring(info)}`)
	local bite
	for _ = 1, 40 do
		bite = lastClientEvent("FishingBite", player)
		if bite and bite.args[1] == info.castId then
			break
		end
		task.wait(0.05)
	end
	assert(bite and bite.args[1] == info.castId, "поклёвки не было")
	fireServer("Hook", player, info.castId, true)
	task.wait(0.05)
	rt.flushAttributes()
	task.wait(0.02)
	assert(BucketService.isCarrying(player), "рыба не попала в ведро")
end

local function goHome(player)
	local plot = BaseService.plotOf(player)
	moveTo(player, plot.CFrame * CFrame.new(0, 3, 0))
	heartbeat(0.2)
end

local function standAtTank(player, owner, slot: number)
	local plot = BaseService.plotOf(owner)
	local slotLocal = plot.CFrame:PointToObjectSpace(plot.SlotCFrames[slot].Position)
	moveTo(player, plot.CFrame * CFrame.new(slotLocal.X, 4.6, 8.8))
end

local function stealPrompt(owner, uid: string)
	local plot = BaseService.plotOf(owner)
	local model = plot.FishFolder:FindFirstChild(uid)
	return model and model:FindFirstChild("Body") and model.Body:FindFirstChild("StealPrompt")
end

local function trySteal(thief, owner, uid: string)
	local prompt = stealPrompt(owner, uid)
	assert(prompt, "у чужой рыбы нет кнопки «Украсть»")
	rt.signalOf(ProximityPromptService, "PromptButtonHoldBegan"):Fire(prompt, thief)
	task.wait(Config.Steal.HoldDuration)
	rt.signalOf(ProximityPromptService, "PromptTriggered"):Fire(prompt, thief)
	task.wait(0.05)
end

-- Сценарий ----------------------------------------------------------------------------------

local alice = addPlayer("Alice", 1001)
local bob = addPlayer("Bob", 1002)

test("игроки загрузились и получили разные базы", function()
	expect(DataService.isLoaded(alice) and DataService.isLoaded(bob), "профили загружены")
	local plotA, plotB = BaseService.plotOf(alice), BaseService.plotOf(bob)
	expect(plotA and plotB and plotA ~= plotB, "у каждого своя база")
	expect(alice:GetAttribute("BaseIndex") == plotA.Index, "атрибут BaseIndex")
	expect(alice:FindFirstChild("leaderstats"), "leaderstats")
	expect(MapService.isInsidePlot(plotA, rootOf(alice).Position), "игрок появился на своей базе")
	expect(plotA.SignTitle.Text == "Alice", "табличка с именем")
end)

local aliceData = DataService.get(alice)
local bobData = DataService.get(bob)

test("рыбалка на пирсе: заброс → поклёвка → подсечка → рыба в ведре", function()
	catchFish(alice)
	expect(alice:GetAttribute("CarryFish") ~= nil, "атрибут CarryFish для клиента")
	expect(alice:GetAttribute("CarrySize") ~= nil, "атрибут CarrySize для скорости")
	expect(aliceData.Stats.Caught == 1, "счётчик улова")
	local ended = lastClientEvent("FishingEnded", alice)
	expect(ended and ended.args[2] == "caught", "клиенту ушёл итог улова")
	local humanoid = alice.Character:FindFirstChildOfClass("Humanoid")
	expect(math.abs(humanoid.WalkSpeed - 14.4) < 0.01, `с ведром бег медленнее: {humanoid.WalkSpeed}`)
end)

test("кислород убывает, фонтан добавляет +10 сек", function()
	local carry = BucketService.carryOf(alice)
	local start = carry.oxygen
	heartbeat(1, 5)
	expect(math.abs(carry.oxygen - (start - 5)) < 0.01, `кислород: {carry.oxygen}`)
	moveTo(alice, Vector3.new(0, 4, 2))
	heartbeat(0.2)
	expect(carry.oxygen > start - 5 + 4, `фонтан не сработал: {carry.oxygen}`)
	local fountain = Workspace.Map.Harbor:FindFirstChild("FountainWater")
	expect(fountain:GetAttribute("ReadyAt") > Workspace:GetServerTimeNow(), "фонтан ушёл на перезарядку")
end)

test("доставка в аквариум и доход раз в секунду", function()
	goHome(alice)
	expect(not BucketService.isCarrying(alice), "ведро опустело")
	expect(#aliceData.Fish == 1, "рыба в сохранении")
	local plot = BaseService.plotOf(alice)
	expect(#plot.FishFolder:GetChildren() == 1, "рыба плавает в аквариуме")
	expect(aliceData.Index[aliceData.Fish[1].Id], "рыба открыта в индексе")
	local before = aliceData.Money
	task.wait(1.2)
	expect(aliceData.Money > before, "доход начислился")
	expect((alice:GetAttribute("Income") or 0) > 0, "доход в секунду для HUD")
end)

test("свой улов задыхается и выскальзывает в воду", function()
	catchFish(alice)
	heartbeat(10, 8)
	expect(not BucketService.isCarrying(alice), "рыба задохнулась")
	expect(notifications(alice):find("выскользнула"), "игроку сказали, что рыба уплыла")
end)

test("кража: вор держит кнопку 1,5 сек, рыба помечается «в пути»", function()
	catchFish(alice)
	goHome(alice)
	expect(#aliceData.Fish == 2, "у Алисы две рыбы")
	local uid = aliceData.Fish[1].Uid
	standAtTank(bob, alice, 1)
	trySteal(bob, alice, uid)
	expect(BucketService.isCarrying(bob), `вор взял рыбу: {notifications(bob)}`)
	expect(BaseService.isInTransit(uid), "рыба помечена «в пути»")
	expect(lastClientEvent("Alarm", alice), "у Алисы сработала тревога")
	expect(#BaseService.activeFish(alice) == 1, "украденная рыба не приносит доход, пока в пути")
end)

test("шлепок выбивает ведро, хозяйка поднимает свою рыбу", function()
	local bobRoot = rootOf(bob)
	local behind = bobRoot.Position + Vector3.new(0, 0, 4)
	moveTo(alice, rt.lookAt(behind, bobRoot.Position))
	fireServer("Slap", alice)
	task.wait(0.05)
	expect(not BucketService.isCarrying(bob), "Боб уронил ведро")
	local dropped
	for _, child in Workspace.Map:GetChildren() do
		if child.Name == "DroppedFish" then
			dropped = child
		end
	end
	expect(dropped, "рыба бьётся на земле")
	local prompt = dropped.Body:FindFirstChild("PickupPrompt")
	rt.syncPositions(dropped)
	moveTo(alice, dropped.Body.CFrame.Position + Vector3.new(2, 2, 0))
	rt.signalOf(ProximityPromptService, "PromptTriggered"):Fire(prompt, alice)
	task.wait(0.05)
	expect(not BucketService.isCarrying(alice), "рыба вернулась сразу, а не в ведро")
	expect(not BaseService.isInTransit(aliceData.Fish[1].Uid), "пометка «в пути» снята")
	expect(#BaseService.activeFish(alice) == 2, "обе рыбы снова приносят доход")
end)

test("вор доносит рыбу — владелец меняется одним действием", function()
	local uid = aliceData.Fish[2].Uid
	standAtTank(bob, alice, 2)
	trySteal(bob, alice, uid)
	expect(BucketService.isCarrying(bob), `вор взял рыбу: {notifications(bob)}`)
	goHome(bob)
	expect(not BucketService.isCarrying(bob), "Боб донёс рыбу")
	expect(#aliceData.Fish == 1 and #bobData.Fish == 1, "рыба перешла от Алисы к Бобу")
	expect(bobData.Fish[1].Uid == uid, "та же рыба")
	expect(bobData.Stats.Stolen == 1 and aliceData.Stats.LostToThieves == 1, "статистика краж")
end)

test("сейф: рыбу в сейфе не украсть", function()
	local uid = aliceData.Fish[1].Uid
	local ok = invoke("SetSafe", alice, uid)
	task.wait(0.05) -- аквариум перерисовывается в конце кадра
	expect(ok and aliceData.SafeUid == uid, "рыба в сейфе")
	expect(stealPrompt(alice, uid) == nil, "у рыбы в сейфе нет кнопки «Украсть»")
	invoke("SetSafe", alice, uid)
	task.wait(0.05)
	expect(aliceData.SafeUid == "", "сейф освобождён")
	expect(stealPrompt(alice, uid) ~= nil, "кнопка «Украсть» вернулась")
end)

test("магазин, рынок и ворота зоны", function()
	EconomyService.add(alice, 200000)
	moveTo(alice, MapService.ShopPosition + Vector3.new(0, 2, 6))
	local ok, message = invoke("Purchase", alice, "Rod", "Bamboo")
	expect(ok and aliceData.Rod == "Bamboo", `удочка: {message}`)
	ok, message = invoke("Purchase", alice, "Bucket", "Plastic")
	expect(ok and aliceData.Bucket == "Plastic", `ведро: {message}`)
	ok = invoke("Purchase", alice, "Fins")
	expect(ok and aliceData.FinsLevel == 1, "ласты")
	ok = invoke("Purchase", alice, "Aquarium")
	expect(ok and aliceData.AquariumTier == 2, "аквариум на 10 мест")
	ok = invoke("Purchase", alice, "Aquarium")
	expect(not ok, "дальше 10 мест в MVP нельзя")
	ok = invoke("Purchase", alice, "Bait", "Shrimp")
	expect(ok and aliceData.Baits.Shrimp == 10, "креветки")
	local poor = invoke("Purchase", bob, "Rod", "Neptune")
	expect(not poor, "без денег не купить")

	moveTo(alice, Vector3.new(0, 5, 0))
	ok = invoke("Sell", alice, aliceData.Fish[1].Uid)
	expect(not ok, "продавать можно только у рынка")
	moveTo(alice, MapService.MarketPosition + Vector3.new(0, 2, 6))
	local money = aliceData.Money
	ok, message = invoke("Sell", alice, aliceData.Fish[1].Uid)
	expect(ok and #aliceData.Fish == 0 and aliceData.Money > money, `продажа: {message}`)

	local gate = MapService.Gates.Lake
	moveTo(alice, gate.CFrame * CFrame.new(0, -3, 4))
	rt.signalOf(ProximityPromptService, "PromptTriggered"):Fire(gate:FindFirstChild("UnlockPrompt"), alice)
	task.wait(0.05)
	expect(aliceData.UnlockedZones.Lake, "Озеро открыто")
end)

test("наживка тратится по одной за заброс", function()
	fireServer("SelectBait", alice, "Shrimp")
	task.wait(0.05)
	expect(aliceData.SelectedBait == "Shrimp", "выбрана креветка")
	catchFish(alice)
	expect(aliceData.Baits.Shrimp == 9, `осталось {aliceData.Baits.Shrimp}`)
	moveTo(alice, MapService.MarketPosition + Vector3.new(0, 2, 6))
	local ok, message = invoke("Sell", alice, "bucket")
	expect(ok and not BucketService.isCarrying(alice), `продажа улова из ведра: {message}`)
end)

test("ивенты Косяк и Шторм", function()
	EventService.force("Shoal", 5)
	EventService.force("Storm", 5)
	task.wait(0.7)
	expect(EventService.isActive("Shoal") and EventService.isActive("Storm"), "ивенты идут")
	expect(EventService.conditions().Storm, "Шторм включает Электрическую мутацию")
	local state = Net.state()
	expect(state:GetAttribute("Storm_EndsAt") > Workspace:GetServerTimeNow(), "таймер для HUD")
	EventService.stop("Shoal")
	EventService.stop("Storm")
	task.wait(0.7)
end)

test("замок: барьер, вора выталкивает, украсть нельзя, перезарядка", function()
	catchFish(alice)
	goHome(alice)
	Config.Lock.Duration = 1.5 -- в игре 60 сек, в тесте короче, чтобы дождаться конца
	fireServer("Lock", alice)
	task.wait(0.05)
	local plot = BaseService.plotOf(alice)
	expect(BaseService.isLocked(plot), "база закрыта")
	for _, wall in plot.Barrier do
		expect(wall.CanCollide, "барьер включён")
	end
	standAtTank(bob, alice, 1)
	trySteal(bob, alice, aliceData.Fish[1].Uid)
	expect(not BucketService.isCarrying(bob), "из закрытой базы не украсть")
	task.wait(0.4)
	expect(not MapService.isInsidePlot(plot, rootOf(bob).Position), "барьер вытолкнул вора")
	task.wait(1.2)
	expect(not BaseService.isLocked(plot), "замок закончился")
	for _, wall in plot.Barrier do
		expect(not wall.CanCollide, "барьер выключен")
	end
	fireServer("Lock", alice)
	task.wait(0.05)
	expect(not BaseService.isLocked(plot), "перезарядка 3 минуты: второй раз сразу не включить")
	expect(notifications(alice):find("перезаряжается"), "игроку показали перезарядку")
end)

test("вор вышел с краденой рыбой — она остаётся у хозяина", function()
	local uid = aliceData.Fish[1].Uid
	standAtTank(bob, alice, 1)
	trySteal(bob, alice, uid)
	expect(BucketService.isCarrying(bob), `Боб несёт рыбу: {notifications(bob)}`)
	rt.signalOf(Players, "PlayerRemoving"):Fire(bob)
	task.wait(0.1)
	expect(not BaseService.isInTransit(uid), "рыба вернулась хозяйке")
	expect(#BaseService.activeFish(alice) == 1, "и снова приносит доход")
	expect(BaseService.plotOf(bob) == nil, "база Боба освободилась")
	expect(bobData.LastLogout > 0, "время выхода сохранено для офлайн-дохода")
end)

test("в сервере не было ошибок и warn", function()
	expect(#rt.failures == 0, table.concat(rt.failures, "\n"))
end)

print(`{suite.passed} passed, {suite.failed} failed`)
process.exit(if suite.failed > 0 then 1 else 0)
