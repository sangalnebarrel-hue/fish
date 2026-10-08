--[[
	Чат-команды для разработчика и админ-ивентов:

		/money 1e6                — добавить денег
		/event shoal|storm [сек]  — запустить ивент
		/stopevent shoal|storm    — остановить запущенный вручную ивент
		/give FishId [Size] [Mutation] — положить рыбу в аквариум (например /give ChefOcto Large Golden)
		/unlock                   — открыть все зоны MVP
		/reset                    — сбросить свои данные (только в Studio)

	Доступны в Studio, создателю плейса и игрокам из Config.AdminUserIds.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FishData = require(Shared.FishData)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local EconomyService = require(script.Parent.EconomyService)
local BaseService = require(script.Parent.BaseService)

local AdminService = {}

local EVENT_IDS: { [string]: string } = { shoal = "Shoal", storm = "Storm" }

local function isAdmin(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if table.find(Config.AdminUserIds :: { number }, player.UserId) then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId
end

local function reply(player: Player, text: string)
	Net.event("Notify"):FireClient(player, `[admin] {text}`, "info")
end

local COMMANDS: { [string]: (Player, { string }) -> () } = {
	money = function(player, args)
		local amount = tonumber(args[1]) or 1000000
		EconomyService.add(player, amount)
		reply(player, `+${amount}`)
	end,
	event = function(player, args)
		local eventId = EVENT_IDS[(args[1] or ""):lower()]
		if not eventId then
			reply(player, "Ивенты: shoal, storm")
			return
		end
		EventService.force(eventId, tonumber(args[2]))
		reply(player, `Ивент {eventId} запущен`)
	end,
	stopevent = function(player, args)
		local eventId = EVENT_IDS[(args[1] or ""):lower()]
		if eventId then
			EventService.stop(eventId)
			reply(player, `Ивент {eventId} остановлен`)
		end
	end,
	give = function(player, args)
		local fishId = args[1]
		if not fishId or not FishData.Fish[fishId] then
			reply(player, "Нет такой рыбы. Пример: /give ChefOcto Large Golden")
			return
		end
		local size = if args[2] and FishData.Sizes[args[2]] then args[2] else "Normal"
		local mutation = if args[3] and FishData.Mutations[args[3]] then args[3] else nil
		local ok = BaseService.addFish(player, {
			Uid = HttpService:GenerateGUID(false),
			Id = fishId,
			Size = size,
			Mutation = mutation,
		})
		reply(player, if ok then `Выдана {fishId}` else "Аквариум полон")
	end,
	unlock = function(player)
		local data = DataService.get(player)
		if data then
			local zones: { [string]: boolean } = Config.EnabledZones
			for zoneId in zones do
				data.UnlockedZones[zoneId] = true
			end
			DataService.markDirty(player)
			reply(player, "Все зоны открыты")
		end
	end,
	reset = function(player)
		if not RunService:IsStudio() then
			reply(player, "/reset работает только в Studio")
			return
		end
		local data = DataService.get(player) :: any
		if data then
			for key, value in DataService.Template :: any do
				data[key] = if type(value) == "table" then table.clone(value) else value
			end
			data.OwnedRods = { Stick = true }
			data.OwnedBuckets = { Leaky = true }
			data.Fish = {}
			data.Index = {}
			data.UnlockedZones = { Pier = true }
			BaseService.render(player)
			DataService.markDirty(player)
			reply(player, "Данные сброшены")
		end
	end,
}

local function onChatted(player: Player, message: string)
	if message:sub(1, 1) ~= "/" or not isAdmin(player) then
		return
	end
	local words = message:sub(2):split(" ")
	local name = table.remove(words, 1)
	local command = name and COMMANDS[name:lower()]
	if command then
		command(player, words)
	end
end

function AdminService.start()
	local function hook(player: Player)
		player.Chatted:Connect(function(message)
			onChatted(player, message)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
end

return AdminService
