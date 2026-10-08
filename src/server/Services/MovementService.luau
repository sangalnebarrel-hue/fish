--[[
	Скорость бега считает только сервер: ласты, ведро с рыбой, замедления (медузы, оглушение).
	Остальные сервисы не трогают WalkSpeed напрямую, а вызывают refresh / debuff.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local MovementService = {}

type Debuff = { multiplier: number, expires: number }

local debuffs: { [Player]: { [string]: Debuff } } = {}

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

-- Скорость без временных замедлений — по ней античит проверяет перемещения.
function MovementService.baseSpeed(player: Player): number
	local data = DataService.get(player)
	local fins = if data then data.FinsLevel else 0
	local carrySize = player:GetAttribute("CarrySize") :: string?
	return Formulas.walkSpeed(fins, carrySize)
end

-- Максимальная скорость, которую игрок мог иметь (без ведра) — запас для античита.
function MovementService.maxSpeed(player: Player): number
	local data = DataService.get(player)
	return Formulas.walkSpeed(if data then data.FinsLevel else Config.Movement.MaxFinsLevel, nil)
end

function MovementService.currentSpeed(player: Player): number
	local speed = MovementService.baseSpeed(player)
	local now = os.clock()
	local active: { [string]: Debuff } = debuffs[player] or {}
	for _, debuff in active do
		if debuff.expires > now then
			speed *= debuff.multiplier
		end
	end
	return speed
end

function MovementService.refresh(player: Player)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.WalkSpeed = MovementService.currentSpeed(player)
	end
end

-- Временное замедление: multiplier 0 — оглушение, 0.5 — вдвое медленнее.
function MovementService.debuff(player: Player, key: string, multiplier: number, duration: number)
	debuffs[player] = debuffs[player] or {}
	debuffs[player][key] = { multiplier = multiplier, expires = os.clock() + duration }
	MovementService.refresh(player)
	task.delay(duration + 0.05, function()
		if player.Parent == Players then
			MovementService.refresh(player)
		end
	end)
end

function MovementService.isDebuffed(player: Player, key: string): boolean
	local debuff = debuffs[player] and debuffs[player][key]
	return debuff ~= nil and debuff.expires > os.clock()
end

-- Отбросить игрока: скорость персонажа считает его клиент, поэтому импульс применяет он.
function MovementService.knockback(player: Player, velocity: Vector3)
	Net.event("Knockback"):FireClient(player, velocity)
end

function MovementService.start()
	local function hookCharacter(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
			if humanoid then
				humanoid.WalkSpeed = MovementService.currentSpeed(player)
			end
		end)
		player:GetAttributeChangedSignal("CarrySize"):Connect(function()
			MovementService.refresh(player)
		end)
	end
	Players.PlayerAdded:Connect(hookCharacter)
	for _, player in Players:GetPlayers() do
		hookCharacter(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		debuffs[player] = nil
	end)
	DataService.onLoaded(function(player)
		MovementService.refresh(player)
	end)
end

return MovementService
