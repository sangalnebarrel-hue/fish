--[[
	Ведро и кислород. Любая рыба вне воды тратит кислород, полоска над головой видна всем.

	- Не успел со своим уловом: рыба выскальзывает в воду, наживка потрачена.
	- Не успел с краденой: рыба «уплывает домой» к владельцу, он ничего не теряет.
	- Лужи, фонтан и бочки дают +10 сек (у каждой перезарядка 30 сек).
	- Ведро выбили: рыба бьётся на земле, кислород тратится вдвое быстрее, поднять может любой.

	Время считает сервер. Клиенту уходят атрибуты (запас, скорость расхода, отметка времени),
	по ним он плавно рисует полоску.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FishData = require(Shared.FishData)
local FishModel = require(Shared.FishModel)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local MonetizationService = require(script.Parent.MonetizationService)
local EventService = require(script.Parent.EventService)
local BaseService = require(script.Parent.BaseService)
local Analytics = require(script.Parent.Analytics)

type FishRecord = DataService.FishRecord

export type Carry = {
	fish: FishRecord,
	origin: string, -- "catch" | "steal"
	owner: Player?, -- у кого украли
	oxygen: number,
	maxOxygen: number,
	rate: number,
	visual: Instance?,
	bar: BillboardGui?,
	lastFullWarning: number,
}

local BucketService = {}

local BUCKET_COLORS: { [string]: Color3 } = {
	Leaky = Color3.fromRGB(140, 120, 100),
	Plastic = Color3.fromRGB(60, 140, 240),
	Big = Color3.fromRGB(80, 190, 90),
	Backpack = Color3.fromRGB(160, 230, 255),
	Tank = Color3.fromRGB(250, 200, 50),
}

local carries: { [Player]: Carry } = {}
local dropped: { [Model]: Carry } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function notify(player: Player, text: string, kind: string?)
	Net.event("Notify"):FireClient(player, text, kind or "info")
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

function BucketService.isCarrying(player: Player): boolean
	return carries[player] ~= nil
end

function BucketService.carryOf(player: Player): Carry?
	return carries[player]
end

-- Визуал ----------------------------------------------------------------------

local function createBar(parent: BasePart, carry: Carry, offsetY: number): BillboardGui
	local fish = FishData.Fish[carry.fish.Id]
	local rarity = FishData.Rarities[fish.Rarity]

	local gui = Instance.new("BillboardGui")
	gui.Name = "OxygenBar"
	gui.Size = UDim2.fromOffset(190, 50)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 300
	gui.LightInfluence = 0

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.5)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = FishModel.rgb(rarity.Color)
	title.TextStrokeTransparency = 0.2
	title.Text = FishData.fullName(carry.fish)
	title.Parent = gui

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Position = UDim2.fromScale(0.05, 0.55)
	back.Size = UDim2.fromScale(0.9, 0.4)
	back.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
	back.BorderSizePixel = 0
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 220, 120)
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner:Clone().Parent = fill

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "Time"
	timeLabel.BackgroundTransparency = 1
	timeLabel.Size = UDim2.fromScale(1, 1)
	timeLabel.Font = Enum.Font.FredokaOne
	timeLabel.TextScaled = true
	timeLabel.TextColor3 = Color3.new(1, 1, 1)
	timeLabel.TextStrokeTransparency = 0.3
	timeLabel.Text = ""
	timeLabel.ZIndex = 2
	timeLabel.Parent = back

	gui:AddTag("OxygenBar")
	gui.Parent = parent
	return gui
end

local function syncBar(carry: Carry)
	local bar = carry.bar
	if bar then
		bar:SetAttribute("Oxygen", carry.oxygen)
		bar:SetAttribute("OxygenMax", carry.maxOxygen)
		bar:SetAttribute("Rate", carry.rate)
		bar:SetAttribute("Stamp", serverNow())
	end
end

local function attachBucket(player: Player, carry: Carry)
	local character = player.Character
	if not character then
		return
	end
	local hand = (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
	local head = (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not hand or not head then
		return
	end
	local data = DataService.get(player)
	local bucketId = if data then data.Bucket else "Leaky"

	local model = Instance.new("Model")
	model.Name = "FishBucket"

	local bucket = Instance.new("Part")
	bucket.Name = "Bucket"
	bucket.Shape = Enum.PartType.Cylinder
	bucket.Size = Vector3.new(2, 2.2, 2.2)
	bucket.Color = BUCKET_COLORS[bucketId] or BUCKET_COLORS.Leaky
	bucket.Material = Enum.Material.Metal
	bucket.CanCollide = false
	bucket.CanQuery = false
	bucket.CanTouch = false
	bucket.Massless = true
	local bucketCf = hand.CFrame * CFrame.new(0, -1.3, -0.4)
	bucket.CFrame = CFrame.new(bucketCf.Position) * CFrame.Angles(0, 0, math.rad(90))
	bucket.Parent = model

	local water = Instance.new("Part")
	water.Name = "Water"
	water.Shape = Enum.PartType.Cylinder
	water.Size = Vector3.new(0.1, 1.9, 1.9)
	water.Color = Color3.fromRGB(90, 190, 240)
	water.Transparency = 0.3
	water.CanCollide = false
	water.CanQuery = false
	water.CanTouch = false
	water.Massless = true
	water.CFrame = CFrame.new(bucketCf.Position + Vector3.new(0, 0.95, 0)) * CFrame.Angles(0, 0, math.rad(90))
	water.Parent = model
	local waterWeld = Instance.new("WeldConstraint")
	waterWeld.Part0 = bucket
	waterWeld.Part1 = water
	waterWeld.Parent = water

	-- рыба торчит из ведра головой вверх
	local fishModel = FishModel.build(carry.fish, { anchored = false, scale = 0.45 })
	fishModel:PivotTo(CFrame.new(bucketCf.Position + Vector3.new(0, 1.4, 0)) * CFrame.Angles(math.rad(-70), 0, 0))
	local fishBody = fishModel.PrimaryPart :: BasePart
	local fishWeld = Instance.new("WeldConstraint")
	fishWeld.Part0 = bucket
	fishWeld.Part1 = fishBody
	fishWeld.Parent = fishBody
	fishModel.Parent = model

	local handWeld = Instance.new("WeldConstraint")
	handWeld.Part0 = hand
	handWeld.Part1 = bucket
	handWeld.Parent = bucket
	model.Parent = character

	carry.visual = model
	carry.bar = createBar(head, carry, 2.6)
	syncBar(carry)
end

local function destroyVisual(carry: Carry)
	if carry.visual then
		carry.visual:Destroy()
		carry.visual = nil
	end
	if carry.bar then
		carry.bar:Destroy()
		carry.bar = nil
	end
end

-- Взять / отдать ведро ---------------------------------------------------------------

function BucketService.give(player: Player, fish: FishRecord, origin: string, owner: Player?, oxygen: number?): boolean
	local data = DataService.get(player)
	if carries[player] or not data then
		return false
	end
	local maxOxygen = Formulas.maxOxygen(fish, data.Bucket, MonetizationService.passes(player))
	local carry: Carry = {
		fish = fish,
		origin = origin,
		owner = owner,
		oxygen = math.min(oxygen or maxOxygen, maxOxygen),
		maxOxygen = maxOxygen,
		rate = Formulas.oxygenDrain(fish, false, EventService.isActive("Drought")),
		lastFullWarning = 0,
	}
	carries[player] = carry
	attachBucket(player, carry)
	player:SetAttribute("CarrySize", fish.Size)
	player:SetAttribute("CarryFish", fish.Id)
	return true
end

local function take(player: Player): Carry?
	local carry = carries[player]
	if not carry then
		return nil
	end
	carries[player] = nil
	destroyVisual(carry)
	player:SetAttribute("CarrySize", nil)
	player:SetAttribute("CarryFish", nil)
	return carry
end

-- Рыба задохнулась (в руках или на земле).
local function expire(carry: Carry, carrier: Player?)
	local name = FishData.fullName(carry.fish)
	if carry.origin == "steal" and carry.owner then
		BaseService.clearTransit(carry.fish.Uid)
		if carrier then
			notify(carrier, `💨 {name} задохнулась и уплыла домой`, "bad")
		end
		if carry.owner.Parent == Players then
			notify(carry.owner, `🏠 Твоя {name} вернулась в аквариум!`, "good")
		end
	elseif carrier then
		notify(carrier, `💦 {name} выскользнула обратно в воду…`, "bad")
	end
end

-- Рыба на земле ----------------------------------------------------------------------

local function spawnDropped(carry: Carry, position: Vector3, dropper: Player?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -60, 0), params)

	-- Упала в воду: своя рыба уплывает, краденая возвращается домой
	if not hit or hit.Material == Enum.Material.Water then
		expire(carry, dropper)
		return
	end

	local model = FishModel.build(carry.fish, { anchored = true, scale = 0.8 })
	model.Name = "DroppedFish"
	model:PivotTo(CFrame.new(hit.Position + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, math.rad(90)))
	local body = model.PrimaryPart :: BasePart

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Поднять"
	prompt.ObjectText = FishData.fullName(carry.fish)
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	carry.rate = Formulas.oxygenDrain(carry.fish, true, EventService.isActive("Drought"))
	carry.visual = model
	carry.bar = createBar(body, carry, 2.5)
	syncBar(carry)
	model:AddTag("DroppedFish")
	model.Parent = Workspace:FindFirstChild("Map") or Workspace
	dropped[model] = carry
end

-- Продать рыбу прямо из ведра на рынке. Краденое на рынке не берут.
function BucketService.takeCatchForSale(player: Player): (FishRecord?, string?)
	local carry = carries[player]
	if not carry then
		return nil, "Ведро пустое"
	end
	if carry.origin ~= "catch" then
		return nil, "Краденое на рынке не берут! Неси к себе в аквариум"
	end
	take(player)
	return carry.fish, nil
end

-- Выбить ведро (шлепок, волна, акула).
function BucketService.drop(player: Player): boolean
	local root = rootOf(player)
	local carry = take(player)
	if not carry then
		return false
	end
	if root then
		spawnDropped(carry, root.Position + root.CFrame.LookVector * 3, player)
	else
		expire(carry, player)
	end
	return true
end

-- Рыбу подобрали: прячем сразу, а саму модель удаляем в конце кадра — на её кнопку
-- «Поднять» в этот момент ещё смотрят другие обработчики PromptTriggered.
local function retireDropped(carry: Carry)
	local model = carry.visual
	carry.visual = nil
	if carry.bar then
		carry.bar:Destroy()
		carry.bar = nil
	end
	if model then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("ProximityPrompt") then
				descendant.Enabled = false
			elseif descendant:IsA("BasePart") then
				descendant.Transparency = 1
			end
		end
		task.defer(function()
			model:Destroy()
		end)
	end
end

local function pickUp(player: Player, model: Model)
	local carry = dropped[model]
	local data = DataService.get(player)
	if not carry or not data then
		return
	end
	if carries[player] then
		notify(player, "Руки заняты — сначала отнеси рыбу домой", "bad")
		return
	end
	local root = rootOf(player)
	local body = model.PrimaryPart
	if not root or not body or (root.Position - body.Position).Magnitude > 14 then
		return
	end

	-- Хозяин поднял свою украденную рыбу — она сразу дома
	if carry.origin == "steal" and carry.owner == player then
		dropped[model] = nil
		retireDropped(carry)
		BaseService.clearTransit(carry.fish.Uid)
		notify(player, `🏠 {FishData.fullName(carry.fish)} снова в твоём аквариуме!`, "good")
		return
	end

	if not Formulas.canCarry(carry.fish.Size, data.Bucket) then
		notify(player, "Нужно ведро побольше для такой рыбы", "bad")
		return
	end
	dropped[model] = nil
	retireDropped(carry)
	if carry.origin == "steal" and carry.owner then
		BaseService.setTransit(carry.fish.Uid, carry.owner, player)
	end
	BucketService.give(player, carry.fish, carry.origin, carry.owner, carry.oxygen)
	notify(player, "🪣 Подобрал! Неси в свой аквариум", "good")
end

-- Доставка в аквариум ------------------------------------------------------------------

local function tryDeposit(player: Player, carry: Carry)
	local name = FishData.fullName(carry.fish)
	local income = Formulas.fishIncome(carry.fish)
	if carry.origin == "steal" and carry.owner and carry.owner ~= player then
		local owner = carry.owner
		local ok, message = BaseService.transfer(owner, carry.fish.Uid, player)
		if ok then
			take(player)
			notify(player, `🦹 Украдено: {name}! +{Format.perSecond(income)}`, "good")
			notify(owner, `😱 {player.DisplayName} украл твою {name}`, "bad")
			Analytics.custom(player, "FishStolen", income, { Fish = carry.fish.Id })
		elseif message and os.clock() - carry.lastFullWarning > 3 then
			carry.lastFullWarning = os.clock()
			notify(player, message, "bad")
		end
		return
	end

	if BaseService.addFish(player, carry.fish) then
		take(player)
		notify(player, `🐟 {name} в аквариуме! +{Format.perSecond(income)}`, "good")
		local data = DataService.get(player)
		if data then
			Analytics.onboarding(player, data, "FirstDeposit")
		end
		Analytics.custom(player, "FishDelivered", carry.oxygen, { Fish = carry.fish.Id })
	elseif os.clock() - carry.lastFullWarning > 3 then
		carry.lastFullWarning = os.clock()
		notify(player, "Аквариум полон! Продай рыбу на рынке или расширь аквариум", "bad")
	end
end

-- Лужи --------------------------------------------------------------------------------

local function setPuddleReady(puddle: BasePart, ready: boolean)
	puddle.Transparency = if ready then 0.15 else 0.7
	puddle.Color = if ready then Color3.fromRGB(70, 170, 230) else Color3.fromRGB(120, 100, 80)
end

local function checkPuddles(player: Player, carry: Carry, position: Vector3)
	if carry.oxygen >= carry.maxOxygen - 0.5 then
		return
	end
	local t = serverNow()
	for _, puddle in MapService.Puddles do
		local readyAt = (puddle:GetAttribute("ReadyAt") :: number?) or 0
		local radius = (puddle:GetAttribute("Radius") :: number?) or 5
		local offset = position - puddle.Position
		if t >= readyAt and math.abs(offset.Y) < 7 and Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius then
			local data = DataService.get(player)
			local bonus = Formulas.puddleBonus(if data then data.Bucket else "Leaky")
			carry.oxygen = math.min(carry.maxOxygen, carry.oxygen + bonus)
			syncBar(carry)
			puddle:SetAttribute("ReadyAt", t + Config.Oxygen.PuddleCooldown)
			setPuddleReady(puddle, false)
			task.delay(Config.Oxygen.PuddleCooldown, function()
				setPuddleReady(puddle, true)
			end)
			notify(player, `💧 +{bonus} сек кислорода`, "good")
			return
		end
	end
end

-- Тик --------------------------------------------------------------------------------

local function stealHandler(thief: Player, owner: Player, record: FishRecord): (boolean, string?)
	local data = DataService.get(thief)
	if not data then
		return false, nil
	end
	if carries[thief] then
		return false, "Руки заняты — сначала отнеси рыбу домой"
	end
	if not Formulas.canCarry(record.Size, data.Bucket) then
		return false, "Нужно ведро побольше для такой рыбы"
	end
	return BucketService.give(thief, record, "steal", owner), nil
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		if carries[player] then
			BucketService.drop(player)
		end
	end)
end

local function onRemoving(player: Player)
	local carry = take(player)
	if carry then
		expire(carry, nil)
	end
	-- Хозяин ушёл: его рыба уходит вместе с ним
	for carrier, other in carries do
		if other.owner == player then
			take(carrier)
			notify(carrier, "Хозяин рыбы ушёл с сервера — рыба уплыла с ним", "bad")
		end
	end
	for model, other in dropped do
		if other.owner == player then
			dropped[model] = nil
			destroyVisual(other)
		end
	end
end

function BucketService.start()
	BaseService.stealHandler = stealHandler
	DataService.onRemoving(onRemoving)

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		-- персонажа убрали без смерти (например, перезагрузка) — ведро падает там, где он стоял
		player.CharacterRemoving:Connect(function()
			if carries[player] then
				BucketService.drop(player)
			end
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name ~= "PickupPrompt" then
			return
		end
		local model = prompt:FindFirstAncestorOfClass("Model")
		if model and dropped[model] then
			pickUp(player, model)
		end
	end)

	local checkAccumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		for player, carry in carries do
			carry.oxygen -= dt * carry.rate
			if carry.oxygen <= 0 then
				take(player)
				expire(carry, player)
			end
		end
		for model, carry in dropped do
			carry.oxygen -= dt * carry.rate
			if carry.oxygen <= 0 then
				dropped[model] = nil
				destroyVisual(carry)
				expire(carry, nil)
			end
		end

		checkAccumulator += dt
		if checkAccumulator < 0.1 then
			return
		end
		checkAccumulator = 0
		for player, carry in carries do
			local root = rootOf(player)
			if root then
				checkPuddles(player, carry, root.Position)
				local plot = BaseService.plotOf(player)
				if plot and MapService.isInsidePlot(plot, root.Position) then
					tryDeposit(player, carry)
				end
			end
		end
	end)
end

return BucketService
