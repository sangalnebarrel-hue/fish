--[[
	Сачок-шлепок: удар по ближайшему игроку. Если у него рыба — он роняет ведро.
	Перезарядка 3 секунды, её ведёт сервер.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local MovementService = require(script.Parent.MovementService)
local AntiCheatService = require(script.Parent.AntiCheatService)
local BucketService = require(script.Parent.BucketService)
local FishingService = require(script.Parent.FishingService)
local Analytics = require(script.Parent.Analytics)

local SlapService = {}

local readyAt: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Ближайшая цель перед игроком. Игроки с рыбой в приоритете.
local function findTarget(slapper: Player, root: BasePart): Player?
	local best: Player? = nil
	local bestScore = math.huge
	for _, other in Players:GetPlayers() do
		local otherRoot = rootOf(other)
		if other ~= slapper and otherRoot and isAlive(other) then
			local offset = otherRoot.Position - root.Position
			local distance = offset.Magnitude
			local facing = if distance > 0.1 then root.CFrame.LookVector:Dot(offset.Unit) else 1
			if distance <= Config.Slap.Range and facing > -0.3 then
				local score = distance - (if BucketService.isCarrying(other) then 100 else 0)
				if score < bestScore then
					bestScore = score
					best = other
				end
			end
		end
	end
	return best
end

local function swingVisual(player: Player)
	local character = player.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")) :: BasePart?
	local root = rootOf(player)
	if not hand or not root then
		return
	end
	local net = Instance.new("Part")
	net.Name = "SlapNet"
	net.Size = Vector3.new(0.25, 0.25, 4)
	net.Color = Color3.fromRGB(130, 90, 55)
	net.CanCollide = false
	net.CanQuery = false
	net.CanTouch = false
	net.Massless = true
	net.CFrame = CFrame.new(hand.Position) * root.CFrame.Rotation * CFrame.new(0, 0, -2)
	local hoop = Instance.new("Part")
	hoop.Name = "Hoop"
	hoop.Shape = Enum.PartType.Cylinder
	hoop.Size = Vector3.new(0.2, 2.2, 2.2)
	hoop.Color = Color3.fromRGB(230, 230, 230)
	hoop.Material = Enum.Material.Fabric
	hoop.Transparency = 0.3
	hoop.CanCollide = false
	hoop.CanQuery = false
	hoop.CanTouch = false
	hoop.Massless = true
	hoop.CFrame = net.CFrame * CFrame.new(0, 0, -2.6) * CFrame.Angles(0, math.rad(90), 0)
	for _, part in { net, hoop } do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = part
		weld.Parent = part
		part.Parent = character
		Debris:AddItem(part, 0.35)
	end
end

local function slap(player: Player)
	local t = Workspace:GetServerTimeNow()
	if (readyAt[player] or 0) > t or not isAlive(player) then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	readyAt[player] = t + Config.Slap.Cooldown
	player:SetAttribute("SlapReadyAt", t + Config.Slap.Cooldown)
	swingVisual(player)

	local target = findTarget(player, root)
	local targetRoot = target and rootOf(target)
	if not target or not targetRoot then
		return
	end

	local hadFish = BucketService.drop(target)
	FishingService.cancel(target)
	MovementService.debuff(target, "Slap", 0, Config.Slap.StunDuration)
	AntiCheatService.grace(target, 2)
	local away = targetRoot.Position - root.Position
	local direction = Vector3.new(away.X, 0, away.Z)
	direction = if direction.Magnitude > 0.1 then direction.Unit else root.CFrame.LookVector
	MovementService.knockback(target, direction * Config.Slap.KnockbackSpeed + Vector3.new(0, 25, 0))

	local sound = Instance.new("Sound")
	sound.SoundId = Config.Sounds.Slap
	sound.Volume = 1
	sound.Parent = targetRoot
	sound:Play()
	Debris:AddItem(sound, 2)

	local notify = Net.event("Notify")
	Net.event("Effect"):FireAllClients("Slap", targetRoot.Position)
	if hadFish then
		notify:FireClient(target, `👋 {player.DisplayName} шлёпнул тебя — ведро упало! Подбери рыбу`, "bad")
		notify:FireClient(player, `👋 Шлёп! {target.DisplayName} уронил ведро`, "good")
		Analytics.custom(player, "SlapDroppedFish")
	else
		notify:FireClient(target, `👋 {player.DisplayName} шлёпнул тебя!`, "bad")
	end
end

function SlapService.start()
	Net.event("Slap").OnServerEvent:Connect(slap)
	Players.PlayerRemoving:Connect(function(player)
		readyAt[player] = nil
	end)
end

return SlapService
