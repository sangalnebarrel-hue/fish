--[[
	Магазин снаряжения, рыбный рынок и ворота зон.
	Всё, что стоит денег, проверяет сервер: цену, владение и что игрок стоит у прилавка.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FishData = require(Shared.FishData)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local ShopData = require(Shared.ShopData)

local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local MovementService = require(script.Parent.MovementService)
local BaseService = require(script.Parent.BaseService)
local EconomyService = require(script.Parent.EconomyService)
local BucketService = require(script.Parent.BucketService)
local Analytics = require(script.Parent.Analytics)

local ShopService = {}

local COUNTER_RADIUS = 26

local function notify(player: Player, text: string, kind: string?)
	Net.event("Notify"):FireClient(player, text, kind or "info")
end

local function isNear(player: Player, position: Vector3): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and (root.Position - position).Magnitude <= COUNTER_RADIUS
end

local function notEnough(price: number): string
	return `Не хватает денег: нужно {Format.money(price)}`
end

-- Покупки -------------------------------------------------------------------------

local function buyRod(player: Player, data: DataService.PlayerData, id: string): (boolean, string)
	local rod = ShopData.Rods[id]
	if not rod then
		return false, "Нет такой удочки"
	end
	if data.OwnedRods[id] then
		data.Rod = id
		return true, `Взял удочку «{rod.Name}»`
	end
	if not isNear(player, MapService.ShopPosition) then
		return false, "Подойди к магазину снаряжения"
	end
	if not EconomyService.trySpend(player, rod.Price, `Rod_{id}`) then
		return false, notEnough(rod.Price)
	end
	data.OwnedRods[id] = true
	data.Rod = id
	return true, `🎣 Куплена удочка «{rod.Name}»!`
end

local function buyBucket(player: Player, data: DataService.PlayerData, id: string): (boolean, string)
	local bucket = ShopData.Buckets[id]
	if not bucket then
		return false, "Нет такого ведра"
	end
	if BucketService.isCarrying(player) then
		return false, "Нельзя менять ведро, пока в нём рыба"
	end
	if data.OwnedBuckets[id] then
		data.Bucket = id
		return true, `Взял «{bucket.Name}»`
	end
	if not isNear(player, MapService.ShopPosition) then
		return false, "Подойди к магазину снаряжения"
	end
	if not EconomyService.trySpend(player, bucket.Price, `Bucket_{id}`) then
		return false, notEnough(bucket.Price)
	end
	data.OwnedBuckets[id] = true
	data.Bucket = id
	return true, `🪣 Куплено «{bucket.Name}»!`
end

local function buyBait(player: Player, data: DataService.PlayerData, id: string): (boolean, string)
	local bait = ShopData.Baits[id]
	if not bait or bait.Infinite or not bait.Price then
		return false, "Эта наживка не продаётся"
	end
	if not isNear(player, MapService.ShopPosition) then
		return false, "Подойди к магазину снаряжения"
	end
	if not EconomyService.trySpend(player, bait.Price, `Bait_{id}`) then
		return false, notEnough(bait.Price)
	end
	data.Baits[id] = (data.Baits[id] or 0) + bait.Pack
	return true, `🪱 {bait.Name} ×{bait.Pack}`
end

local function buyFins(player: Player, data: DataService.PlayerData): (boolean, string)
	if data.FinsLevel >= Config.Movement.MaxFinsLevel then
		return false, "Ласты уже максимального уровня"
	end
	if not isNear(player, MapService.ShopPosition) then
		return false, "Подойди к магазину снаряжения"
	end
	local level = data.FinsLevel + 1
	local price = Formulas.finsPrice(level)
	if not EconomyService.trySpend(player, price, `Fins_{level}`) then
		return false, notEnough(price)
	end
	data.FinsLevel = level
	MovementService.refresh(player)
	return true, `🩴 Ласты: уровень {level} (+{level * Config.Movement.FinsBonusPerLevel * 100}% к бегу)`
end

local function buyAquarium(player: Player, data: DataService.PlayerData): (boolean, string)
	local nextTier = data.AquariumTier + 1
	local tier = ShopData.AquariumTiers[nextTier]
	if not tier or nextTier > Config.MaxAquariumTier then
		return false, "Больше расширений пока нет"
	end
	if not isNear(player, MapService.ShopPosition) then
		return false, "Подойди к магазину снаряжения"
	end
	if not EconomyService.trySpend(player, tier.Price, `Aquarium_{nextTier}`) then
		return false, notEnough(tier.Price)
	end
	data.AquariumTier = nextTier
	BaseService.render(player)
	return true, `🐠 Аквариум расширен до {tier.Slots} мест!`
end

local function onPurchase(player: Player, category: unknown, id: unknown): (boolean, string)
	local data = DataService.get(player)
	if not data or type(category) ~= "string" then
		return false, "Неверный запрос"
	end
	local itemId = if type(id) == "string" then id else ""
	local ok, message
	if category == "Rod" then
		ok, message = buyRod(player, data, itemId)
	elseif category == "Bucket" then
		ok, message = buyBucket(player, data, itemId)
	elseif category == "Bait" then
		ok, message = buyBait(player, data, itemId)
	elseif category == "Fins" then
		ok, message = buyFins(player, data)
	elseif category == "Aquarium" then
		ok, message = buyAquarium(player, data)
	else
		return false, "Неверный запрос"
	end
	DataService.markDirty(player)
	return ok, message
end

-- Рынок ---------------------------------------------------------------------------

local function sellRecord(player: Player, record: DataService.FishRecord): (boolean, string)
	local price = Formulas.sellPrice(record)
	if not price then
		return false, "Секретную рыбу нельзя продать"
	end
	EconomyService.add(player, price)
	local data = DataService.get(player)
	if data then
		data.Stats.Sold = (data.Stats.Sold or 0) + 1
		Analytics.earn(player, price, data.Money, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, `Sell_{record.Id}`)
	end
	return true, `💰 {FishData.fullName(record)} продана за {Format.money(price)}`
end

local function onSell(player: Player, target: unknown): (boolean, string)
	if not DataService.isLoaded(player) or type(target) ~= "string" then
		return false, "Неверный запрос"
	end
	if not isNear(player, MapService.MarketPosition) then
		return false, "Продавать можно только на рыбном рынке"
	end
	if target == "bucket" then
		local record, message = BucketService.takeCatchForSale(player)
		if not record then
			return false, message or "Ведро пустое"
		end
		return sellRecord(player, record)
	end
	local _, record = BaseService.findFish(player, target)
	if not record then
		return false, "Рыба не найдена"
	end
	if BaseService.isInTransit(target) then
		return false, "Эту рыбу сейчас крадут!"
	end
	if not Formulas.sellPrice(record) then
		return false, "Секретную рыбу нельзя продать"
	end
	BaseService.removeFish(player, target)
	local ok, message = sellRecord(player, record)
	DataService.markDirty(player)
	return ok, message
end

-- Ворота зон -----------------------------------------------------------------------

local function unlockZone(player: Player, gate: BasePart)
	local data = DataService.get(player)
	local zoneId = gate:GetAttribute("ZoneId") :: string?
	local zone = zoneId and FishData.Zones[zoneId]
	if not data or not zoneId or not zone then
		return
	end
	if data.UnlockedZones[zoneId] then
		notify(player, `{zone.Name} уже открыто`)
		return
	end
	local price = zone.UnlockPrice or 0
	if not EconomyService.trySpend(player, price, `Zone_{zoneId}`) then
		notify(player, notEnough(price), "bad")
		return
	end
	data.UnlockedZones[zoneId] = true
	DataService.markDirty(player)
	notify(player, `🔓 Открыто: {zone.Name}! Здесь ловится рыба получше`, "good")
	Analytics.custom(player, "ZoneUnlocked", zone.Order, { Zone = zoneId })
end

function ShopService.start()
	Net.func("Purchase").OnServerInvoke = onPurchase
	Net.func("Sell").OnServerInvoke = onSell

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt == MapService.ShopPrompt then
			Net.event("OpenUI"):FireClient(player, "Shop")
		elseif prompt == MapService.MarketPrompt then
			-- С уловом в ведре продаём сразу, иначе открываем аквариум в режиме продажи
			if BucketService.isCarrying(player) then
				local _, message = onSell(player, "bucket")
				notify(player, message, "info")
			else
				Net.event("OpenUI"):FireClient(player, "Market")
			end
		elseif prompt.Name == "UnlockPrompt" then
			local gate = prompt.Parent
			if gate and gate:IsA("BasePart") and gate:HasTag("ZoneGate") then
				unlockZone(player, gate)
			end
		end
	end)
end

return ShopService
