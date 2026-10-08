--[[
	Steal-игры чаще всего ломают телепортом и спидхаком.
	Сервер раз в полсекунды сверяет пройденное расстояние со скоростью игрока и при нарушении
	возвращает его на последнюю честную точку. Серверные телепорты и отбрасывания
	помечаются через grace(), чтобы не ловить ложные срабатывания.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local MovementService = require(script.Parent.MovementService)
local Analytics = require(script.Parent.Analytics)

local AntiCheatService = {}

local CHECK_INTERVAL = 0.5
local SPEED_TOLERANCE = 1.4
local DISTANCE_SLACK = 4
local STRIKES_BEFORE_RUBBERBAND = 3

type Track = {
	root: BasePart,
	position: Vector3,
	cframe: CFrame,
	graceUntil: number,
	strikes: number,
	lastStrike: number,
}

local tracks: { [Player]: Track } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Не проверять игрока какое-то время (телепорт на базу, отбрасывание, выталкивание барьером).
function AntiCheatService.grace(player: Player, seconds: number?)
	local track = tracks[player]
	if track then
		track.graceUntil = os.clock() + (seconds or 2)
	end
end

local function check(player: Player, dt: number)
	local root = rootOf(player)
	if not root then
		tracks[player] = nil
		return
	end
	local now = os.clock()
	local track = tracks[player]
	if not track or track.root ~= root then
		-- новый персонаж (респавн) — начинаем отслеживать заново
		tracks[player] = {
			root = root,
			position = root.Position,
			cframe = root.CFrame,
			graceUntil = now + 3,
			strikes = 0,
			lastStrike = 0,
		}
		return
	end

	local position = root.Position
	if now < track.graceUntil then
		track.position = position
		track.cframe = root.CFrame
		return
	end

	local horizontal = Vector3.new(position.X - track.position.X, 0, position.Z - track.position.Z).Magnitude
	local allowed = MovementService.maxSpeed(player) * dt * SPEED_TOLERANCE + DISTANCE_SLACK
	if horizontal > allowed then
		if now - track.lastStrike > 5 then
			track.strikes = 0
		end
		track.strikes += 1
		track.lastStrike = now
		if track.strikes >= STRIKES_BEFORE_RUBBERBAND then
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = track.cframe
			track.strikes = 0
			Analytics.custom(player, "AntiCheatRubberband", horizontal)
			return
		end
	end
	track.position = position
	track.cframe = root.CFrame
end

function AntiCheatService.start()
	Players.PlayerRemoving:Connect(function(player)
		tracks[player] = nil
	end)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < CHECK_INTERVAL then
			return
		end
		local elapsed = accumulator
		accumulator = 0
		for _, player in Players:GetPlayers() do
			check(player, elapsed)
		end
	end)
end

return AntiCheatService
