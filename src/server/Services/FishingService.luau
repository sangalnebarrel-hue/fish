--[[
	Рыбалка одной кнопкой с мини-игрой подсечки.

	1. Клиент просит заброс (Cast). Сервер проверяет зону, ведро и наживку, рисует удочку и поплавок.
	2. Через случайную задержку сервер сам бросает улов (редкость, размер, мутацию) и сообщает
	   клиенту только редкость и параметры мини-игры.
	3. Клиент присылает результат подсечки (Hook). Сервер принимает его только в окне поклёвки.
	Шансы улова клиенту недоступны: подделав мини-игру, можно лишь не промахнуться.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FishData = require(Shared.FishData)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local ShopData = require(Shared.ShopData)

local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local MonetizationService = require(script.Parent.MonetizationService)
local EventService = require(script.Parent.EventService)
local BucketService = require(script.Parent.BucketService)
local Analytics = require(script.Parent.Analytics)

local FishingService = {}

type Catch = { Id: string, Size: string, Mutation: string? }

type Cast = {
	id: number,
	zoneId: string,
	baitId: string,
	phase: string, -- "waiting" | "bite"
	catch: Catch?,
	autoHook: boolean,
	deadline: number,
	rig: Model?,
	bobber: BasePart?,
}

local ROD_COLORS: { [string]: Color3 } = {
	Stick = Color3.fromRGB(130, 90, 55),
	Bamboo = Color3.fromRGB(200, 190, 100),
	Carbon = Color3.fromRGB(40, 40, 45),
	Golden = Color3.fromRGB(255, 205, 40),
	Neptune = Color3.fromRGB(60, 220, 230),
}

local casts: { [Player]: Cast } = {}
local lastCastEnd: { [Player]: number } = {}
local nextCastId = 0
local random = Random.new()

local function roll(): number
	return random:NextNumber()
end

local function notify(player: Player, text: string, kind: string?)
	Net.event("Notify"):FireClient(player, text, kind or "info")
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

function FishingService.isFishing(player: Player): boolean
	return casts[player] ~= nil
end

-- Удочка, леска и поплавок ------------------------------------------------------------

local function createRig(player: Player, rodId: string): (Model?, BasePart?)
	local character = player.Character
	local root = rootOf(player)
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
	if not character or not root or not hand then
		return nil, nil
	end

	local rig = Instance.new("Model")
	rig.Name = `FishingRig_{player.UserId}`

	local rod = Instance.new("Part")
	rod.Name = "Rod"
	rod.Size = Vector3.new(0.22, 0.22, 6)
	rod.Color = ROD_COLORS[rodId] or ROD_COLORS.Stick
	rod.Material = if rodId == "Neptune" then Enum.Material.Neon else Enum.Material.Wood
	rod.CanCollide = false
	rod.CanQuery = false
	rod.CanTouch = false
	rod.Massless = true
	rod.CFrame = CFrame.new(hand.Position) * root.CFrame.Rotation * CFrame.Angles(math.rad(40), 0, 0) * CFrame.new(0, 0, -3)
	rod.Parent = rig
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = rod
	weld.Parent = rod
	local tip = Instance.new("Attachment")
	tip.Position = Vector3.new(0, 0, -3)
	tip.Parent = rod

	local target = root.Position + root.CFrame.LookVector * 14
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(target + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), params)
	local bobberPosition = if hit then hit.Position else Vector3.new(target.X, MapService.WaterLevel, target.Z)

	local bobber = Instance.new("Part")
	bobber.Name = "Bobber"
	bobber.Shape = Enum.PartType.Ball
	bobber.Size = Vector3.new(0.8, 0.8, 0.8)
	bobber.Color = Color3.fromRGB(240, 50, 50)
	bobber.Anchored = true
	bobber.CanCollide = false
	bobber.CanQuery = false
	bobber.CanTouch = false
	bobber.Position = bobberPosition + Vector3.new(0, 0.2, 0)
	bobber.Parent = rig
	local bobberAttachment = Instance.new("Attachment")
	bobberAttachment.Parent = bobber

	local line = Instance.new("Beam")
	line.Attachment0 = tip
	line.Attachment1 = bobberAttachment
	line.Width0 = 0.06
	line.Width1 = 0.06
	line.FaceCamera = true
	line.CurveSize0 = -2
	line.Color = ColorSequence.new(Color3.new(1, 1, 1))
	line.Parent = rod

	local splash = Instance.new("Sound")
	splash.SoundId = Config.Sounds.Splash
	splash.Volume = 0.6
	splash.Parent = bobber
	splash:Play()

	rig.Parent = Workspace:FindFirstChild("Map") or Workspace
	return rig, bobber
end

-- Заброс и подсечка -------------------------------------------------------------------

local function finish(player: Player, cast: Cast, success: boolean, reason: string)
	if casts[player] ~= cast then
		return
	end
	casts[player] = nil
	lastCastEnd[player] = os.clock()
	if cast.rig then
		cast.rig:Destroy()
	end
	local ended = Net.event("FishingEnded")
	local catch = cast.catch
	local data = DataService.get(player)

	if not success or not catch or not data then
		ended:FireClient(player, cast.id, reason)
		return
	end

	local record: DataService.FishRecord = {
		Uid = HttpService:GenerateGUID(false),
		Id = catch.Id,
		Size = catch.Size,
		Mutation = catch.Mutation,
	}
	if not Formulas.canCarry(record.Size, data.Bucket) then
		ended:FireClient(player, cast.id, "tooBig", record)
		notify(player, `{FishData.fullName(record)} не влезла в ведро! Нужно ведро побольше`, "bad")
		return
	end
	if not BucketService.give(player, record, "catch") then
		ended:FireClient(player, cast.id, "busy")
		return
	end
	data.Stats.Caught = (data.Stats.Caught or 0) + 1
	Analytics.onboarding(player, data, "FirstCatch")
	local fish = FishData.Fish[record.Id]
	Analytics.custom(player, "FishCaught", FishData.Rarities[fish.Rarity].Order, {
		Fish = record.Id,
		Size = record.Size,
		Mutation = record.Mutation or "None",
		Zone = cast.zoneId,
	})
	ended:FireClient(player, cast.id, "caught", record)
	DataService.markDirty(player)
end

local function stillInZone(player: Player, zoneId: string): boolean
	local root = rootOf(player)
	return root ~= nil and MapService.zoneAt(root.Position, Config.Fishing.AreaMargin) == zoneId
end

local function bite(player: Player, cast: Cast)
	if casts[player] ~= cast then
		return
	end
	local data = DataService.get(player)
	if not data or not stillInZone(player, cast.zoneId) then
		finish(player, cast, false, "moved")
		return
	end
	local ctx = Formulas.catchContext(data.Rod, cast.baitId, MonetizationService.passes(player), EventService.conditions(), EventService.isNight())
	local catch = Formulas.rollCatch(cast.zoneId, ctx, roll)
	local rarityId = FishData.Fish[catch.Id].Rarity
	local params = Formulas.hookParams(rarityId, data.Rod, roll)
	cast.catch = catch
	cast.phase = "bite"
	cast.autoHook = params.autoHook
	cast.deadline = os.clock() + params.window + Config.Fishing.LatencyAllowance

	if cast.bobber then
		cast.bobber.Position -= Vector3.new(0, 0.5, 0)
		local plop = Instance.new("Sound")
		plop.SoundId = Config.Sounds.Bite
		plop.Volume = 0.7
		plop.Parent = cast.bobber
		plop:Play()
	end
	Net.event("FishingBite"):FireClient(player, cast.id, rarityId, params)
	task.delay(params.window + Config.Fishing.LatencyAllowance + 0.1, function()
		if casts[player] == cast then
			finish(player, cast, false, "timeout")
		end
	end)
end

local function onCast(player: Player): (boolean, any)
	local data = DataService.get(player)
	if not data then
		return false, "Загрузка…"
	end
	if casts[player] then
		return false, nil
	end
	if os.clock() - (lastCastEnd[player] or 0) < Config.Fishing.CastCooldown then
		return false, nil
	end
	if BucketService.isCarrying(player) then
		return false, "Сначала отнеси рыбу домой"
	end
	local root = rootOf(player)
	local zoneId = if root then MapService.zoneAt(root.Position) else nil
	if not zoneId then
		return false, "Подойди к воде в зоне рыбалки"
	end
	if not data.UnlockedZones[zoneId] then
		return false, `Сначала открой зону «{FishData.Zones[zoneId].Name}» у ворот`
	end

	local baitId = data.SelectedBait
	local bait = ShopData.Baits[baitId]
	if not bait or not bait.Infinite then
		if not bait or (data.Baits[baitId] or 0) <= 0 then
			baitId = "Worm"
			data.SelectedBait = "Worm"
		else
			data.Baits[baitId] -= 1
		end
	end
	DataService.markDirty(player)

	nextCastId += 1
	local rig, bobber = createRig(player, data.Rod)
	local cast: Cast = {
		id = nextCastId,
		zoneId = zoneId,
		baitId = baitId,
		phase = "waiting",
		catch = nil,
		autoHook = false,
		deadline = math.huge,
		rig = rig,
		bobber = bobber,
	}
	casts[player] = cast
	local biteIn = Formulas.biteDelay(roll, data.Rod, EventService.isActive("Shoal"))
	task.delay(biteIn, bite, player, cast)
	Analytics.onboarding(player, data, "FirstCast")
	return true, { castId = cast.id, zoneId = zoneId, baitId = baitId }
end

local function onHook(player: Player, castId: unknown, success: unknown)
	local cast = casts[player]
	if not cast or cast.id ~= castId or cast.phase ~= "bite" then
		return
	end
	if os.clock() > cast.deadline then
		finish(player, cast, false, "timeout")
		return
	end
	finish(player, cast, success == true or cast.autoHook, if success == true then "caught" else "escaped")
end

function FishingService.cancel(player: Player)
	local cast = casts[player]
	if cast then
		finish(player, cast, false, "cancelled")
	end
end

function FishingService.start()
	Net.func("Cast").OnServerInvoke = onCast
	Net.event("Hook").OnServerEvent:Connect(onHook)
	Net.event("CancelCast").OnServerEvent:Connect(function(player)
		FishingService.cancel(player)
	end)
	Net.event("SelectBait").OnServerEvent:Connect(function(player, baitId)
		local data = DataService.get(player)
		if not data or type(baitId) ~= "string" or not ShopData.Baits[baitId] then
			return
		end
		if baitId ~= "Worm" and (data.Baits[baitId] or 0) <= 0 then
			return
		end
		data.SelectedBait = baitId
		DataService.markDirty(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		FishingService.cancel(player)
		lastCastEnd[player] = nil
	end)
	local function hook(player: Player)
		player.CharacterRemoving:Connect(function()
			FishingService.cancel(player)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end

	-- Ушёл от воды, пока ждал поклёвку — заброс отменяется
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, cast in casts do
				if not stillInZone(player, cast.zoneId) then
					finish(player, cast, false, "moved")
				end
			end
		end
	end)
end

return FishingService
