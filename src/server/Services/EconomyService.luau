--[[
	Деньги и доход. Доход начисляет один серверный цикл раз в секунду на всех игроков,
	а не скрипт в каждой рыбе. Офлайн-доход: 50% обычного, не больше 4 часов.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local BaseService = require(script.Parent.BaseService)
local Analytics = require(script.Parent.Analytics)

local EconomyService = {}

local moneyValues: { [Player]: IntValue } = {}

local function publish(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	player:SetAttribute("Money", data.Money)
	local value = moneyValues[player]
	if value then
		value.Value = math.floor(data.Money)
	end
end

function EconomyService.money(player: Player): number
	local data = DataService.get(player)
	return if data then data.Money else 0
end

function EconomyService.add(player: Player, amount: number)
	local data = DataService.get(player)
	if not data or amount <= 0 then
		return
	end
	data.Money += amount
	data.TotalEarned += amount
	publish(player)
end

-- Списать деньги, если хватает. sku — что купили (для аналитики).
function EconomyService.trySpend(player: Player, price: number, sku: string): boolean
	local data = DataService.get(player)
	if not data or price < 0 or data.Money < price then
		return false
	end
	data.Money -= price
	publish(player)
	if price > 0 then
		Analytics.spend(player, price, data.Money, sku)
		Analytics.onboarding(player, data, "FirstPurchase")
	end
	return true
end

-- Доход в секунду со всеми бонусами игрока (VIP, ×2 Деньги, ребёрты).
function EconomyService.incomePerSecond(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	local total = 0
	for _, record in BaseService.activeFish(player) do
		total += Formulas.fishIncome(record)
	end
	return total * Formulas.incomeMultiplier(data.Rebirths, MonetizationService.passes(player))
end

local function onLoaded(player: Player, data: DataService.PlayerData)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local money = Instance.new("IntValue")
	money.Name = "Деньги"
	money.Parent = leaderstats
	leaderstats.Parent = player
	moneyValues[player] = money

	if data.LastLogout > 0 and data.LastIncome > 0 then
		local elapsed = os.time() - data.LastLogout
		local earned = Formulas.offlineEarnings(data.LastIncome, elapsed)
		if earned > 0 then
			EconomyService.add(player, earned)
			Analytics.earn(player, earned, data.Money, Enum.AnalyticsEconomyTransactionType.TimedReward.Name, "OfflineIncome")
			Net.event("OfflineEarnings"):FireClient(player, earned, elapsed)
		end
	end
	Analytics.onboarding(player, data, "Joined")
	publish(player)
	player:SetAttribute("Income", EconomyService.incomePerSecond(player))
end

-- LastIncome обновляется каждую секунду в цикле дохода: при выходе геймпассы игрока
-- уже могут быть выгружены, а офлайн-доход должен считаться с ними.
local function onRemoving(player: Player, data: DataService.PlayerData)
	data.LastLogout = os.time()
	moneyValues[player] = nil
end

function EconomyService.start()
	DataService.onLoaded(onLoaded)
	DataService.onRemoving(onRemoving)

	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data then
					local income = EconomyService.incomePerSecond(player)
					player:SetAttribute("Income", income)
					data.LastIncome = income
					EconomyService.add(player, income)
				end
			end
		end
	end)
end

return EconomyService
