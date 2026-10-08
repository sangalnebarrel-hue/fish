--[[
	Серверные ивенты по таймеру и цикл дня и ночи.

	Расписание считается от серверного времени Roblox, поэтому на всех серверах ивенты
	начинаются одновременно и их можно анонсировать заранее. В MVP: Косяк и Шторм.
	Состояние публикуется атрибутами папки ReplicatedStorage.GameState.
]]

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local MapService = require(script.Parent.MapService)
local MovementService = require(script.Parent.MovementService)
local AntiCheatService = require(script.Parent.AntiCheatService)

local EventService = {}

-- (eventId, isActive)
EventService.Changed = Signal.new()

type EventConfig = { Period: number, Duration: number, Offset: number }

local EVENT_ORDER = { "Shoal", "Storm" }
local EVENT_INFO = {
	Shoal = {
		Icon = "🐟",
		Title = "Косяк",
		Started = "Начался Косяк! Клёв ×2 во всех зонах",
		Ended = "Косяк уплыл",
	},
	Storm = {
		Icon = "⛈",
		Title = "Шторм",
		Started = "Начался Шторм! Пойманная рыба может стать Электрической ⚡",
		Ended = "Шторм закончился",
	},
}

local active: { [string]: boolean } = {}
local forcedUntil: { [string]: number } = {}
local state: Folder
local calmLighting = { Brightness = 0, OutdoorAmbient = Color3.new(), Density = 0, Cover = 0 }

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Активен ли ивент по расписанию, когда закончится и когда начнётся следующий.
local function schedule(eventId: string, t: number): (boolean, number, number)
	local cfg = (Config.Events :: any)[eventId] :: EventConfig
	local phase = (t - cfg.Offset) % cfg.Period
	local cycleStart = t - phase
	local isActive = phase < cfg.Duration
	return isActive, cycleStart + cfg.Duration, cycleStart + cfg.Period
end

function EventService.isActive(eventId: string): boolean
	return active[eventId] == true
end

function EventService.isNight(): boolean
	local clock = Lighting.ClockTime
	return clock >= 19 or clock < 6
end

-- Условия для мутаций: ивенты и сезоны.
function EventService.conditions(): { [string]: boolean }
	local date = os.date("!*t")
	local month, day = date.month, date.day
	return {
		Storm = EventService.isActive("Storm"),
		Halloween = month == 10,
		Winter = (month == 12 and day >= 20) or (month == 1 and day <= 10),
	}
end

-- Запустить ивент вручную (админ-ивенты по выходным, тесты).
function EventService.force(eventId: string, duration: number?)
	local cfg = (Config.Events :: any)[eventId] :: EventConfig?
	if not cfg then
		return
	end
	forcedUntil[eventId] = now() + (duration or cfg.Duration)
end

function EventService.stop(eventId: string)
	forcedUntil[eventId] = nil
end

-- Шторм ---------------------------------------------------------------------

local function setStormLighting(on: boolean)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	if on then
		calmLighting.Brightness = Lighting.Brightness
		calmLighting.OutdoorAmbient = Lighting.OutdoorAmbient
		calmLighting.Density = if atmosphere then atmosphere.Density else 0
		calmLighting.Cover = if clouds then clouds.Cover else 0
		Lighting.Brightness = 0.8
		Lighting.OutdoorAmbient = Color3.fromRGB(80, 85, 100)
		if atmosphere then
			atmosphere.Density = 0.45
		end
		if clouds then
			clouds.Cover = 0.95
			clouds.Color = Color3.fromRGB(90, 95, 110)
		end
	else
		Lighting.Brightness = calmLighting.Brightness
		Lighting.OutdoorAmbient = calmLighting.OutdoorAmbient
		if atmosphere then
			atmosphere.Density = calmLighting.Density
		end
		if clouds then
			clouds.Cover = calmLighting.Cover
			clouds.Color = Color3.new(1, 1, 1)
		end
	end
end

local function groundBelow(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	params.FilterDescendantsInstances = characters
	local result = Workspace:Raycast(position + Vector3.new(0, 150, 0), Vector3.new(0, -300, 0), params)
	return if result then result.Position else Vector3.new(position.X, MapService.WaterLevel, position.Z)
end

local function strikeTarget(): Vector3
	local players = Players:GetPlayers()
	if #players > 0 and math.random() < 0.6 then
		local player = players[math.random(1, #players)]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local angle = math.random() * math.pi * 2
			local distance = 6 + math.random() * 22
			return root.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		end
	end
	local angle = math.random() * math.pi * 2
	local distance = math.random() * 140
	return Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function lightningStrike()
	local cfg = Config.Events.Storm
	local point = groundBelow(strikeTarget())
	local map = Workspace:FindFirstChild("Map") or Workspace

	-- Предупреждение за 1.2 секунды: красный круг на земле
	local warning = Instance.new("Part")
	warning.Name = "LightningWarning"
	warning.Shape = Enum.PartType.Cylinder
	warning.Anchored = true
	warning.CanCollide = false
	warning.CanQuery = false
	warning.CanTouch = false
	warning.Material = Enum.Material.Neon
	warning.Color = Color3.fromRGB(255, 70, 70)
	warning.Transparency = 0.5
	warning.Size = Vector3.new(0.2, cfg.StrikeRadius * 2, cfg.StrikeRadius * 2)
	warning.CFrame = CFrame.new(point + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	warning.Parent = map
	Debris:AddItem(warning, 1.4)

	task.delay(1.2, function()
		local bolt = Instance.new("Part")
		bolt.Name = "LightningBolt"
		bolt.Anchored = true
		bolt.CanCollide = false
		bolt.CanQuery = false
		bolt.CanTouch = false
		bolt.Material = Enum.Material.Neon
		bolt.Color = Color3.fromRGB(200, 230, 255)
		bolt.Size = Vector3.new(1.2, 160, 1.2)
		bolt.CFrame = CFrame.new(point + Vector3.new(0, 80, 0))
		bolt.Parent = map
		local thunder = Instance.new("Sound")
		thunder.SoundId = Config.Sounds.Thunder
		thunder.Volume = 1
		thunder.RollOffMaxDistance = 400
		thunder.Parent = bolt
		thunder:Play()
		Debris:AddItem(bolt, 0.6)
		Net.event("Effect"):FireAllClients("Lightning", point)

		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - point).Magnitude <= cfg.StrikeRadius + 2 then
				MovementService.debuff(player, "Lightning", 0, 1)
				AntiCheatService.grace(player, 2)
				local away = Vector3.new(root.Position.X - point.X, 0, root.Position.Z - point.Z)
				local direction = if away.Magnitude > 0.1 then away.Unit else Vector3.new(1, 0, 0)
				MovementService.knockback(player, direction * 30 + Vector3.new(0, 35, 0))
				Net.event("Notify"):FireClient(player, "⚡ Тебя ударило молнией!", "bad")
			end
		end
	end)
end

-- Цикл ----------------------------------------------------------------------

local function setActive(eventId: string, isActive: boolean)
	-- при старте сервера ивенты считаются выключенными: «закончился» не объявляем и свет не трогаем
	if (active[eventId] or false) == isActive then
		return
	end
	active[eventId] = isActive
	local info = (EVENT_INFO :: any)[eventId]
	if eventId == "Shoal" then
		for _, emitter in MapService.ShoalEmitters do
			emitter.Enabled = isActive
		end
	elseif eventId == "Storm" then
		setStormLighting(isActive)
	end
	Net.event("Notify"):FireAllClients(`{info.Icon} {if isActive then info.Started else info.Ended}`, "event")
	EventService.Changed:Fire(eventId, isActive)
end

local function updateEvents()
	local t = now()
	local lines = {}
	for _, eventId in EVENT_ORDER do
		if Config.EnabledEvents[eventId] then
			local isActive, endsAt, nextAt = schedule(eventId, t)
			local forced = forcedUntil[eventId]
			if forced and forced > t then
				isActive = true
				endsAt = math.max(endsAt, forced)
			elseif forced then
				forcedUntil[eventId] = nil
			end
			setActive(eventId, isActive)
			state:SetAttribute(`{eventId}_EndsAt`, if isActive then endsAt else 0)
			state:SetAttribute(`{eventId}_NextAt`, nextAt)

			local info = (EVENT_INFO :: any)[eventId]
			if isActive then
				table.insert(lines, `{info.Icon} <b>{info.Title}</b> — идёт! {Format.time(endsAt - t)}`)
			else
				table.insert(lines, `{info.Icon} {info.Title} через {Format.time(nextAt - t)}`)
			end
		end
	end
	local board = MapService.EventBoardLabel
	if board then
		board.Text = "ИВЕНТЫ\n" .. table.concat(lines, "\n")
	end
end

local function updateDayNight()
	local t = now()
	local progress = (t % Config.DayLength) / Config.DayLength
	Lighting.ClockTime = (6 + progress * 24) % 24
	state:SetAttribute("IsNight", EventService.isNight())
end

function EventService.init()
	state = Net.state()
end

function EventService.start()
	task.spawn(function()
		while true do
			updateEvents()
			updateDayNight()
			task.wait(0.5)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Events.Storm.StrikeInterval * (0.6 + math.random() * 0.8))
			if active.Storm then
				lightningStrike()
			end
		end
	end)
end

return EventService
