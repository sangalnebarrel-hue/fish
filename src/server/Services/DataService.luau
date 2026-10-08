--[[
	Сохранения игроков: ProfileStore поверх DataStore с блокировкой сессии,
	автосейв раз в 60 секунд и при выходе.

	Другие сервисы подписываются через onLoaded / onRemoving. Обработчики вызываются
	по очереди в порядке подписки, поэтому, например, геймпассы успевают загрузиться
	раньше, чем считаются места в аквариуме.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)

local DataService = {}

DataService.Template = {
	Money = 0,
	TotalEarned = 0,
	Rod = "Stick",
	OwnedRods = { Stick = true },
	Bucket = "Leaky",
	OwnedBuckets = { Leaky = true },
	FinsLevel = 0,
	AquariumTier = 1,
	Fish = {}, -- { {Uid, Id, Size, Mutation?}, ... } — порядок = места в аквариуме
	SafeUid = "",
	Baits = { Shrimp = 0, Firefly = 0, GoldenBait = 0, SecretLure = 0 },
	SelectedBait = "Worm",
	Index = {}, -- { [fishId] = true }
	IndexRewards = 0,
	UnlockedZones = { Pier = true },
	Rebirths = 0,
	LastLogout = 0,
	LastIncome = 0,
	Stats = { Caught = 0, Stolen = 0, LostToThieves = 0, Sold = 0 },
	Onboarding = 0,
}

export type FishRecord = { Uid: string, Id: string, Size: string, Mutation: string? }

export type PlayerData = {
	Money: number,
	TotalEarned: number,
	Rod: string,
	OwnedRods: { [string]: boolean },
	Bucket: string,
	OwnedBuckets: { [string]: boolean },
	FinsLevel: number,
	AquariumTier: number,
	Fish: { FishRecord },
	SafeUid: string,
	Baits: { [string]: number },
	SelectedBait: string,
	Index: { [string]: boolean },
	IndexRewards: number,
	UnlockedZones: { [string]: boolean },
	Rebirths: number,
	LastLogout: number,
	LastIncome: number,
	Stats: { [string]: number },
	Onboarding: number,
}

local store = ProfileStore.New(Config.DataStoreName, DataService.Template)
ProfileStore.SetConstant("AUTO_SAVE_PERIOD", Config.AutoSavePeriod)

local profiles: { [Player]: any } = {}

-- pcall, который всегда возвращает (успех, ошибка) — так проще для строгой типизации.
local function try(fn: (...any) -> ...any, ...: any): (boolean, any)
	local result = table.pack(pcall(fn, ...))
	return result[1], result[2]
end
local loadedHandlers: { (Player, PlayerData) -> () } = {}
local removingHandlers: { (Player, PlayerData) -> () } = {}
local snapshotDecorators: { (Player, { [string]: any }) -> () } = {}
local dirty: { [Player]: boolean } = {}

function DataService.onLoaded(handler: (Player, PlayerData) -> ())
	table.insert(loadedHandlers, handler)
end

function DataService.onRemoving(handler: (Player, PlayerData) -> ())
	table.insert(removingHandlers, handler)
end

-- Дополнительные поля для клиента (например, какие рыбы сейчас в пути).
function DataService.addSnapshotDecorator(decorator: (Player, { [string]: any }) -> ())
	table.insert(snapshotDecorators, decorator)
end

function DataService.get(player: Player): PlayerData?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function DataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

function DataService.players(): { Player }
	local result = {}
	for player in profiles do
		table.insert(result, player)
	end
	return result
end

-- Попросить отправить игроку свежий снимок данных (не чаще 5 раз в секунду).
function DataService.markDirty(player: Player)
	dirty[player] = true
end

-- Принудительно сохранить (после кражи, чтобы не было дюпа при падении сервера).
function DataService.save(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile:Save()
	end
end

function DataService.snapshot(player: Player): { [string]: any }?
	local data = DataService.get(player)
	if not data then
		return nil
	end
	local snapshot = table.clone(data) :: { [string]: any }
	for _, decorate in snapshotDecorators do
		decorate(player, snapshot)
	end
	return snapshot
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		player:Kick("Не удалось загрузить сохранение. Перезайди, пожалуйста.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Сохранение открыто на другом сервере. Перезайди, пожалуйста.")
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profiles[player] = profile
	for _, handler in loadedHandlers do
		if player.Parent ~= Players then
			return
		end
		local ok, err = try(handler, player, profile.Data)
		if not ok then
			warn(`[DataService] onLoaded handler failed for {player.Name}: {err}`)
		end
	end
	DataService.markDirty(player)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	for _, handler in removingHandlers do
		local ok, err = try(handler, player, profile.Data)
		if not ok then
			warn(`[DataService] onRemoving handler failed for {player.Name}: {err}`)
		end
	end
	profiles[player] = nil
	dirty[player] = nil
	profile:EndSession()
end

function DataService.start()
	Net.func("RequestSync").OnServerInvoke = function(player)
		-- Начать загружать игроков. Вызывается последним, когда все сервисы уже подписались на onLoaded.
		function DataService.listen()
			Players.PlayerAdded:Connect(onPlayerAdded)
			Players.PlayerRemoving:Connect(onPlayerRemoving)
			for _, player in Players:GetPlayers() do
				task.spawn(onPlayerAdded, player)
			end
		end

		return DataService.snapshot(player)
	end

	local syncRemote = Net.event("DataSync")
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < 0.2 then
			return
		end
		accumulator = 0
		for player in dirty do
			dirty[player] = nil
			local snapshot = DataService.snapshot(player)
			if snapshot then
				syncRemote:FireClient(player, snapshot)
			end
		end
	end)
end

-- Начать загружать игроков. Вызывается последним, когда все сервисы уже подписались на onLoaded.
function DataService.listen()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService
