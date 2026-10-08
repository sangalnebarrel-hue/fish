--[[
	Все настройки баланса и правил игры в одном месте.
	Модуль чистый (без Roblox API), поэтому его можно гонять в тестах через luau CLI.
]]

local Config = {}

Config.GameName = "Catch & Steal a Fish"
Config.DataStoreName = "PlayerData_v1"

-- Что входит в MVP. Остальной контент уже описан в данных и включается одной строкой.
Config.EnabledZones = { Pier = true, Lake = true, Reef = true }
Config.EnabledSizes = { Fry = true, Normal = true, Large = true }
Config.EnabledMutations = { Golden = true, Electric = true }
Config.EnabledPasses = { VIP = true, DoubleMoney = true, OxygenTank = true }
Config.EnabledEvents = { Shoal = true, Storm = true }
Config.MaxAquariumTier = 2 -- 1 = 6 мест, 2 = 10 мест

Config.MaxPlayers = 8

Config.Movement = {
	BaseWalkSpeed = 16,
	FinsBonusPerLevel = 0.04,
	MaxFinsLevel = 20,
}

Config.Fishing = {
	BiteDelayMin = 2.5,
	BiteDelayMax = 6,
	HookWindow = 4, -- сколько секунд длится мини-игра подсечки
	LatencyAllowance = 1.5,
	CastCooldown = 0.75,
	AreaMargin = 6, -- насколько можно отойти от зоны, пока ждёшь поклёвку
	ElectricChanceInStorm = 0.2,
}

Config.Oxygen = {
	PuddleBonus = 10,
	PuddleCooldown = 30,
	GroundDrainMultiplier = 2,
	DroughtDrainMultiplier = 1.2,
	OxygenTankPassMultiplier = 1.3,
}

Config.Steal = {
	HoldDuration = 1.5,
	MaxDistance = 8,
	DistanceTolerance = 2.5,
}

Config.Slap = {
	Cooldown = 3,
	Range = 9,
	KnockbackSpeed = 55,
	StunDuration = 0.6,
}

Config.Lock = {
	Duration = 60,
	Cooldown = 180,
}

Config.NewbieProtection = 300

Config.Income = {
	RebirthBonus = 0.5,
	VIPMultiplier = 1.5,
	DoubleMoneyMultiplier = 2,
	OfflineRate = 0.5,
	OfflineMaxSeconds = 4 * 60 * 60,
}

Config.Luck = {
	DoubleLuckPassMultiplier = 2,
}

Config.VIPExtraSlots = 2
Config.SecondFloorSlots = 10

Config.AutoSavePeriod = 60

-- Серверные ивенты идут по мировым часам, поэтому на всех серверах начинаются одновременно.
Config.Events = {
	Shoal = { Period = 30 * 60, Duration = 5 * 60, Offset = 0, BiteSpeedMultiplier = 0.5 },
	Storm = { Period = 45 * 60, Duration = 4 * 60, Offset = 20 * 60, StrikeInterval = 3, StrikeRadius = 9 },
}

Config.DayLength = 12 * 60 -- полный цикл дня и ночи, секунд

-- ID геймпассов из Creator Dashboard. Пока стоит 0, пасс в игре не продаётся.
Config.GamePassIds = {
	VIP = 0,
	DoubleMoney = 0,
	DoubleLuck = 0,
	OxygenTank = 0,
	AutoFish = 0,
	SecondFloor = 0,
}

-- Админы могут пользоваться чат-командами (/money, /event ...). В Studio команды доступны всем.
Config.AdminUserIds = {}

Config.Sounds = {
	Splash = "rbxasset://sounds/impact_water.mp3",
	Click = "rbxasset://sounds/button.wav",
	Bite = "rbxasset://sounds/electronicpingshort.wav",
	Slap = "rbxasset://sounds/swordslash.wav",
	Alarm = "rbxasset://sounds/electronicpingshort.wav",
	Coins = "rbxasset://sounds/electronicpingshort.wav",
	Fail = "rbxasset://sounds/uuhhh.mp3",
	Thunder = "rbxasset://sounds/collide.wav",
}

return Config
