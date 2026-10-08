--[[
	Вся математика игры: броски улова, доход, кислород, скорость, цены.
	Чистые функции без Roblox API. Случайность приходит снаружи как rng(): число в [0, 1).
	Сервер — единственный, кто вызывает броски; клиент использует только расчёты для UI.
]]

local Config = require(script.Parent.Config)
local FishData = require(script.Parent.FishData)
local ShopData = require(script.Parent.ShopData)

local Formulas = {}

export type FishRecord = {
	Uid: string,
	Id: string,
	Size: string,
	Mutation: string?,
}

export type Passes = { [string]: boolean }

export type CatchContext = {
	luck: number,
	epicPlusMult: number?, -- Светлячок ночью
	secretMult: number?, -- Секретная приманка
	goldenMult: number?, -- удочка × наживка
	conditions: { [string]: boolean }?, -- активные ивенты/сезоны: Storm, Halloween, Winter
}

type WeightedEntry = { key: string, weight: number }

local function weightedPick(entries: { WeightedEntry }, rng: () -> number): string?
	local total = 0
	for _, entry in entries do
		total += entry.weight
	end
	if total <= 0 then
		return nil
	end
	local roll = rng() * total
	for _, entry in entries do
		roll -= entry.weight
		if roll < 0 then
			return entry.key
		end
	end
	return entries[#entries].key
end

Formulas.weightedPick = weightedPick

-- Улов ----------------------------------------------------------------------

-- Веса редкостей зоны с учётом удачи. Удача умножает вес каждой ступени выше самой частой
-- редкости зоны на luck^ступень: на Рифе Epic получает ×luck, на Озере Rare — ×luck².
function Formulas.rarityWeights(zoneId: string, ctx: CatchContext): { WeightedEntry }
	local zone = FishData.Zones[zoneId]
	assert(zone, `Unknown zone {zoneId}`)

	local minOrder = math.huge
	for rarityId in zone.Rarities do
		minOrder = math.min(minOrder, FishData.Rarities[rarityId].Order)
	end

	local epicOrder = FishData.Rarities.Epic.Order
	local entries = {}
	for _, rarity in FishData.RarityList do
		local weight = zone.Rarities[rarity.Id]
		if weight and weight > 0 and #FishData.fishIn(zoneId, rarity.Id) > 0 then
			weight *= math.max(ctx.luck, 1) ^ (rarity.Order - minOrder)
			if ctx.epicPlusMult and rarity.Order >= epicOrder then
				weight *= ctx.epicPlusMult
			end
			if ctx.secretMult and rarity.Id == "Secret" then
				weight *= ctx.secretMult
			end
			table.insert(entries, { key = rarity.Id, weight = weight })
		end
	end
	return entries
end

function Formulas.rollFish(zoneId: string, ctx: CatchContext, rng: () -> number): string
	local rarityId = weightedPick(Formulas.rarityWeights(zoneId, ctx), rng)
	assert(rarityId, `Zone {zoneId} has no fish`)
	local pool = FishData.fishIn(zoneId, rarityId)
	return pool[math.clamp(math.floor(rng() * #pool) + 1, 1, #pool)]
end

function Formulas.rollSize(rng: () -> number): string
	local entries = {}
	for _, size in FishData.SizeList do
		if Config.EnabledSizes[size.Id] then
			table.insert(entries, { key = size.Id, weight = size.Chance })
		end
	end
	return weightedPick(entries, rng) or "Normal"
end

-- Одна мутация на рыбу. Сначала мутации активных условий (Шторм → Электрическая),
-- потом случайные от самой редкой к самой частой.
function Formulas.rollMutation(ctx: CatchContext, rng: () -> number): string?
	local conditions = ctx.conditions or {}
	for _, mutation in FishData.MutationList do
		if mutation.Condition and Config.EnabledMutations[mutation.Id] and conditions[mutation.Condition] then
			local chance = mutation.Chance
			if mutation.Id == "Electric" then
				chance = Config.Fishing.ElectricChanceInStorm
			end
			if chance and rng() < chance then
				return mutation.Id
			end
		end
	end
	for _, mutation in FishData.MutationList do
		if mutation.Condition == nil and Config.EnabledMutations[mutation.Id] then
			local chance = mutation.Chance or 0
			if mutation.Id == "Golden" then
				chance *= ctx.goldenMult or 1
			end
			if rng() < chance then
				return mutation.Id
			end
		end
	end
	return nil
end

function Formulas.rollCatch(zoneId: string, ctx: CatchContext, rng: () -> number): { Id: string, Size: string, Mutation: string? }
	return {
		Id = Formulas.rollFish(zoneId, ctx, rng),
		Size = Formulas.rollSize(rng),
		Mutation = Formulas.rollMutation(ctx, rng),
	}
end

-- Удача удочки, наживки и геймпасса.
function Formulas.luck(rodId: string, baitId: string?, passes: Passes): number
	local rod = ShopData.Rods[rodId] or ShopData.Rods.Stick
	local luck = rod.Luck
	local bait = baitId and ShopData.Baits[baitId]
	if bait and bait.Luck then
		luck *= bait.Luck
	end
	if passes.DoubleLuck then
		luck *= Config.Luck.DoubleLuckPassMultiplier
	end
	return luck
end

function Formulas.catchContext(rodId: string, baitId: string?, passes: Passes, conditions: { [string]: boolean }, isNight: boolean): CatchContext
	local rod = ShopData.Rods[rodId] or ShopData.Rods.Stick
	local bait = baitId and ShopData.Baits[baitId]
	return {
		luck = Formulas.luck(rodId, baitId, passes),
		epicPlusMult = if bait and bait.NightEpicMult and isNight then bait.NightEpicMult else nil,
		secretMult = if bait then bait.SecretMult else nil,
		goldenMult = rod.GoldenMult * (if bait and bait.GoldenMult then bait.GoldenMult else 1),
		conditions = conditions,
	}
end

-- Мини-игра подсечки ---------------------------------------------------------

local MARKER_SPEED = { Common = 0.7, Uncommon = 0.85, Rare = 1.05, Epic = 1.3, Legendary = 1.55, Mythic = 1.8, Secret = 2.1 }
local ZONE_WIDTH = { Common = 0.3, Uncommon = 0.26, Rare = 0.22, Epic = 0.18, Legendary = 0.15, Mythic = 0.12, Secret = 0.1 }

-- zoneCenter/zoneWidth — доли полоски [0..1], speed — полных проходов в секунду.
function Formulas.hookParams(rarityId: string, rodId: string, rng: () -> number)
	local rod = ShopData.Rods[rodId] or ShopData.Rods.Stick
	local width = math.min((ZONE_WIDTH[rarityId] or 0.2) * rod.HookZone, 0.6)
	local autoHook = false
	if rod.AutoHookFrom then
		autoHook = FishData.Rarities[rarityId].Order >= FishData.Rarities[rod.AutoHookFrom].Order
	end
	return {
		zoneWidth = width,
		zoneCenter = width / 2 + rng() * (1 - width),
		speed = MARKER_SPEED[rarityId] or 1,
		window = Config.Fishing.HookWindow,
		autoHook = autoHook,
	}
end

-- Положение маркера в момент t: «пила» туда-обратно по полоске.
function Formulas.markerPosition(t: number, speed: number): number
	local phase = (t * speed) % 2
	return if phase <= 1 then phase else 2 - phase
end

function Formulas.biteDelay(rng: () -> number, rodId: string, shoalActive: boolean): number
	local rod = ShopData.Rods[rodId] or ShopData.Rods.Stick
	local cfg = Config.Fishing
	local delay = cfg.BiteDelayMin + rng() * (cfg.BiteDelayMax - cfg.BiteDelayMin)
	delay *= rod.BiteSpeed
	if shoalActive then
		delay *= Config.Events.Shoal.BiteSpeedMultiplier
	end
	return delay
end

-- Доход и цены ---------------------------------------------------------------

-- Доход одной рыбы без бонусов игрока: база × размер × мутация.
function Formulas.fishIncome(record: { Id: string, Size: string, Mutation: string? }): number
	local fish = FishData.Fish[record.Id]
	if not fish then
		return 0
	end
	local size = FishData.Sizes[record.Size] or FishData.Sizes.Normal
	local mutation = record.Mutation and FishData.Mutations[record.Mutation]
	return fish.Income * size.IncomeMult * (if mutation then mutation.Mult else 1)
end

function Formulas.incomeMultiplier(rebirths: number, passes: Passes): number
	local mult = 1 + rebirths * Config.Income.RebirthBonus
	if passes.VIP then
		mult *= Config.Income.VIPMultiplier
	end
	if passes.DoubleMoney then
		mult *= Config.Income.DoubleMoneyMultiplier
	end
	return mult
end

-- Цена на рынке. nil — рыба не продаётся (Secret).
function Formulas.sellPrice(record: { Id: string, Size: string, Mutation: string? }): number?
	local fish = FishData.Fish[record.Id]
	if not fish then
		return nil
	end
	local rarity = FishData.Rarities[fish.Rarity]
	if not rarity.SellSeconds then
		return nil
	end
	return math.max(1, math.floor(Formulas.fishIncome(record) * rarity.SellSeconds))
end

function Formulas.offlineEarnings(incomePerSecond: number, elapsedSeconds: number): number
	local seconds = math.clamp(elapsedSeconds, 0, Config.Income.OfflineMaxSeconds)
	return math.floor(incomePerSecond * Config.Income.OfflineRate * seconds)
end

-- Кислород ------------------------------------------------------------------

function Formulas.maxOxygen(record: { Id: string, Size: string, Mutation: string? }, bucketId: string, passes: Passes): number
	local fish = FishData.Fish[record.Id]
	local rarity = FishData.Rarities[fish.Rarity]
	local size = FishData.Sizes[record.Size] or FishData.Sizes.Normal
	local bucket = ShopData.Buckets[bucketId] or ShopData.Buckets.Leaky
	local oxygen = rarity.Oxygen * size.OxygenMult * bucket.Oxygen
	if passes.OxygenTank then
		oxygen *= Config.Oxygen.OxygenTankPassMultiplier
	end
	return oxygen
end

-- Сколько секунд кислорода тратится за секунду (Ледяная — вдвое медленнее).
function Formulas.oxygenDrain(record: { Mutation: string? }, onGround: boolean, drought: boolean): number
	local rate = 1
	local mutation = record.Mutation and FishData.Mutations[record.Mutation]
	if mutation and mutation.OxygenDrain then
		rate *= mutation.OxygenDrain
	end
	if onGround then
		rate *= Config.Oxygen.GroundDrainMultiplier
	end
	if drought then
		rate *= Config.Oxygen.DroughtDrainMultiplier
	end
	return rate
end

function Formulas.puddleBonus(bucketId: string): number
	local bucket = ShopData.Buckets[bucketId]
	return if bucket and bucket.PuddleBonus then bucket.PuddleBonus else Config.Oxygen.PuddleBonus
end

function Formulas.canCarry(sizeId: string, bucketId: string): boolean
	local size = FishData.Sizes[sizeId] or FishData.Sizes.Normal
	local bucket = ShopData.Buckets[bucketId] or ShopData.Buckets.Leaky
	return bucket.Capacity >= size.Capacity
end

-- Скорость ------------------------------------------------------------------

function Formulas.walkSpeed(finsLevel: number, carrySizeId: string?): number
	local cfg = Config.Movement
	local speed = cfg.BaseWalkSpeed * (1 + math.clamp(finsLevel, 0, cfg.MaxFinsLevel) * cfg.FinsBonusPerLevel)
	if carrySizeId then
		local size = FishData.Sizes[carrySizeId] or FishData.Sizes.Normal
		speed *= size.CarrySpeed
	end
	return speed
end

-- Цена следующего уровня ласт (уровни 1..20), каждый ×1,6.
function Formulas.finsPrice(level: number): number
	return math.floor(300 * 1.6 ^ (level - 1) / 10 + 0.5) * 10
end

-- Аквариум ------------------------------------------------------------------

function Formulas.aquariumSlots(tier: number, passes: Passes): number
	local tierData = ShopData.AquariumTiers[math.clamp(tier, 1, #ShopData.AquariumTiers)]
	local slots = tierData.Slots
	if passes.VIP then
		slots += Config.VIPExtraSlots
	end
	if passes.SecondFloor then
		slots += Config.SecondFloorSlots
	end
	return slots
end

-- Самое большое число мест, которое может понадобиться с текущими настройками (для постройки базы).
function Formulas.maxPossibleSlots(): number
	local tier = math.min(Config.MaxAquariumTier, #ShopData.AquariumTiers)
	local enabled: { [string]: boolean } = Config.EnabledPasses
	local passes: Passes = {
		VIP = enabled.VIP == true,
		SecondFloor = enabled.SecondFloor == true,
	}
	return Formulas.aquariumSlots(tier, passes)
end

return Formulas
