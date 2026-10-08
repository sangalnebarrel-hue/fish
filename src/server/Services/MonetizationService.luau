--[[
	Геймпассы. Донат ускоряет прогресс, но не защищает от краж и не продаёт готовую рыбу.
	Владение кешируется на игроке атрибутами Pass_<Id>, клиент читает их для интерфейса.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Formulas = require(Shared.Formulas)
local ShopData = require(Shared.ShopData)
local Signal = require(Shared.Signal)

local DataService = require(script.Parent.DataService)
local Analytics = require(script.Parent.Analytics)

local MonetizationService = {}

-- (player, passId) — пасс куплен прямо в игре
MonetizationService.PassGranted = Signal.new()

local owned: { [Player]: { [string]: boolean } } = {}

local passIds: { [string]: number } = Config.GamePassIds
local enabledPasses: { [string]: boolean } = Config.EnabledPasses

local function passIdByAssetId(assetId: number): string?
	for passId, id in passIds do
		if id == assetId and id ~= 0 then
			return passId
		end
	end
	return nil
end

-- Какие пассы есть у игрока: { VIP = true, ... }. Выключенные в MVP пассы не действуют.
function MonetizationService.passes(player: Player): Formulas.Passes
	local result: Formulas.Passes = {}
	local playerPasses: { [string]: boolean } = owned[player] or {}
	for passId, value in playerPasses do
		if value and enabledPasses[passId] then
			result[passId] = true
		end
	end
	return result
end

function MonetizationService.has(player: Player, passId: string): boolean
	return MonetizationService.passes(player)[passId] == true
end

local function grant(player: Player, passId: string)
	owned[player] = owned[player] or {}
	owned[player][passId] = true
	player:SetAttribute(`Pass_{passId}`, true)
	if passId == "VIP" then
		player:SetAttribute("VIP", true)
	end
end

local function loadPasses(player: Player)
	owned[player] = {}
	for _, pass in ShopData.PassList do
		local assetId = passIds[pass.Id]
		if enabledPasses[pass.Id] and assetId and assetId ~= 0 then
			local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, assetId)
			if ok and result then
				grant(player, pass.Id)
			elseif not ok then
				warn(`[Monetization] UserOwnsGamePassAsync failed for {player.Name}: {result}`)
			end
		end
	end
end

function MonetizationService.start()
	DataService.onLoaded(function(player)
		loadPasses(player)
	end)
	DataService.onRemoving(function(player)
		owned[player] = nil
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, assetId: number, purchased: boolean)
		if not purchased then
			return
		end
		local passId = passIdByAssetId(assetId)
		if passId and player.Parent == Players then
			grant(player, passId)
			Analytics.custom(player, "GamePassPurchased", nil, { Pass = passId })
			MonetizationService.PassGranted:Fire(player, passId)
		end
	end)
end

return MonetizationService
