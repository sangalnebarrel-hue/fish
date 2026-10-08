--[[
	Таблица всех рыб, редкостей, размеров, мутаций и зон рыбалки.
	Цвета хранятся как {r, g, b}, чтобы модуль оставался чистым и тестировался вне Roblox.
]]

local FishData = {}

export type Rarity = {
	Id: string,
	Name: string,
	Order: number,
	Oxygen: number,
	SellSeconds: number?,
	Color: { number },
}

export type Size = {
	Id: string,
	Name: string,
	IncomeMult: number,
	Chance: number,
	OxygenMult: number,
	Scale: number,
	Capacity: number,
	CarrySpeed: number,
}

export type Mutation = {
	Id: string,
	Name: string,
	Mult: number,
	Chance: number?,
	Condition: string?,
	OxygenDrain: number?,
	Color: { number },
}

export type Zone = {
	Id: string,
	Name: string,
	Order: number,
	UnlockPrice: number?,
	UnlockRebirths: number?,
	RunTime: number?,
	Danger: string?,
	Rarities: { [string]: number },
}

export type Fish = {
	Id: string,
	Name: string,
	NameRu: string,
	Rarity: string,
	Income: number,
	Zones: { string },
	Shape: string,
	Color: { number },
	Color2: { number },
	Accessory: string?,
	Special: string?,
}

-- Редкости ------------------------------------------------------------------

local RARITIES: { Rarity } = {
	{ Id = "Common", Name = "Обычная", Order = 1, Oxygen = 60, SellSeconds = 10, Color = { 190, 190, 190 } },
	{ Id = "Uncommon", Name = "Необычная", Order = 2, Oxygen = 50, SellSeconds = 20, Color = { 90, 210, 95 } },
	{ Id = "Rare", Name = "Редкая", Order = 3, Oxygen = 40, SellSeconds = 33, Color = { 70, 150, 255 } },
	{ Id = "Epic", Name = "Эпическая", Order = 4, Oxygen = 30, SellSeconds = 75, Color = { 180, 90, 255 } },
	{
		Id = "Legendary",
		Name = "Легендарная",
		Order = 5,
		Oxygen = 22,
		SellSeconds = 160,
		Color = { 255, 175, 30 },
	},
	{
		Id = "Mythic",
		Name = "Мифическая",
		Order = 6,
		Oxygen = 15,
		SellSeconds = 330,
		Color = { 255, 70, 110 },
	},
	-- Secret не продаётся, только кража
	{ Id = "Secret", Name = "Секретная", Order = 7, Oxygen = 10, SellSeconds = nil, Color = { 40, 255, 230 } },
}

FishData.RarityList = RARITIES
FishData.Rarities = {} :: { [string]: Rarity }
for _, rarity in RARITIES do
	FishData.Rarities[rarity.Id] = rarity
end

-- Размеры -------------------------------------------------------------------

-- Capacity: какое ведро нужно (1 — любое, 2 — Большое, 3 — Аквариум-рюкзак).
-- CarrySpeed: множитель бега, пока рыба в ведре.
local SIZES: { Size } = {
	{
		Id = "Fry",
		Name = "Малёк",
		IncomeMult = 0.5,
		Chance = 20,
		OxygenMult = 1.2,
		Scale = 0.65,
		Capacity = 1,
		CarrySpeed = 0.9,
	},
	{
		Id = "Normal",
		Name = "Обычная",
		IncomeMult = 1,
		Chance = 60,
		OxygenMult = 1,
		Scale = 1,
		Capacity = 1,
		CarrySpeed = 0.9,
	},
	{
		Id = "Large",
		Name = "Крупная",
		IncomeMult = 2,
		Chance = 15,
		OxygenMult = 1,
		Scale = 1.35,
		Capacity = 1,
		CarrySpeed = 0.9,
	},
	{
		Id = "Giant",
		Name = "Гигантская",
		IncomeMult = 4,
		Chance = 4.9,
		OxygenMult = 1,
		Scale = 1.9,
		Capacity = 2,
		CarrySpeed = 0.85,
	},
	{
		Id = "Whale",
		Name = "Китовая",
		IncomeMult = 10,
		Chance = 0.1,
		OxygenMult = 1,
		Scale = 2.8,
		Capacity = 3,
		CarrySpeed = 0.7,
	},
}

FishData.SizeList = SIZES
FishData.Sizes = {} :: { [string]: Size }
for _, size in SIZES do
	FishData.Sizes[size.Id] = size
end

-- Мутации -------------------------------------------------------------------

-- Condition: мутация выпадает только при активном условии (ивент или сезон).
-- Random-мутации проверяются от самой редкой к самой частой.
local MUTATIONS: { Mutation } = {
	{ Id = "Rainbow", Name = "Радужная", Mult = 10, Chance = 0.002, Color = { 255, 120, 220 } },
	{ Id = "Diamond", Name = "Алмазная", Mult = 5, Chance = 0.01, Color = { 150, 235, 255 } },
	{ Id = "Golden", Name = "Золотая", Mult = 3, Chance = 0.03, Color = { 255, 205, 40 } },
	{ Id = "Electric", Name = "Электрическая", Mult = 4, Condition = "Storm", Color = { 80, 220, 255 } },
	{
		Id = "Ghost",
		Name = "Призрачная",
		Mult = 6,
		Condition = "Halloween",
		Chance = 0.08,
		Color = { 220, 220, 255 },
	},
	{
		Id = "Ice",
		Name = "Ледяная",
		Mult = 6,
		Condition = "Winter",
		Chance = 0.08,
		OxygenDrain = 0.5,
		Color = { 170, 220, 255 },
	},
}

FishData.MutationList = MUTATIONS
FishData.Mutations = {} :: { [string]: Mutation }
for _, mutation in MUTATIONS do
	FishData.Mutations[mutation.Id] = mutation
end

-- Зоны ----------------------------------------------------------------------

-- Rarities: базовые веса редкостей в зоне. Удача сдвигает их к редким (см. Formulas).
-- RunTime: сколько секунд бежать до баз со стартовой скоростью (для баланса и подсказок).
local ZONES: { Zone } = {
	{
		Id = "Pier",
		Name = "Пирс",
		Order = 1,
		UnlockPrice = 0,
		RunTime = 5,
		Rarities = { Common = 90, Uncommon = 10 },
	},
	{
		Id = "Lake",
		Name = "Озеро",
		Order = 2,
		UnlockPrice = 1000,
		RunTime = 15,
		Rarities = { Common = 45, Uncommon = 47, Rare = 8 },
	},
	{
		Id = "Reef",
		Name = "Коралловый риф",
		Order = 3,
		UnlockPrice = 25000,
		RunTime = 30,
		Danger = "Медузы жалят: замедление на 2 сек",
		Rarities = { Rare = 86, Epic = 14 },
	},
	{
		Id = "StormSea",
		Name = "Штормовое море",
		Order = 4,
		UnlockPrice = 500000,
		RunTime = 45,
		Danger = "Волны сбивают с ног, ведро падает",
		Rarities = { Epic = 80, Legendary = 20 },
	},
	{
		Id = "SharkBay",
		Name = "Акулья бухта",
		Order = 5,
		UnlockPrice = 10000000,
		RunTime = 60,
		Danger = "Акула кусает: ведро падает",
		Rarities = { Legendary = 85, Mythic = 15 },
	},
	{
		Id = "Abyss",
		Name = "Бездна",
		Order = 6,
		UnlockRebirths = 1,
		Danger = "Темнота, нужен фонарь",
		-- В диздоке в Бездне пока только Малыш-Кракен. К апдейту Бездны сюда нужны свои глубоководные рыбы.
		Rarities = { Secret = 100 },
	},
}

FishData.ZoneList = ZONES
FishData.Zones = {} :: { [string]: Zone }
for _, zone in ZONES do
	FishData.Zones[zone.Id] = zone
end

-- Рыбы ----------------------------------------------------------------------

-- Shape: Fish | Long | Flat | Round | Octo | Shark | Jelly — форма процедурной модели.
-- Accessory: смешная деталь на голове (см. FishModel).
-- Special = "Hourly": не попадается в обычном улове, спавнится отдельно раз в час.
local FISH: { Fish } = {
	{
		Id = "SockFish",
		Name = "Sock Fish",
		NameRu = "Рыба-Носок",
		Rarity = "Common",
		Income = 1,
		Zones = { "Pier" },
		Shape = "Long",
		Color = { 245, 245, 245 },
		Color2 = { 220, 60, 60 },
	},
	{
		Id = "BreadFish",
		Name = "Bread Fish",
		NameRu = "Рыба-Батон",
		Rarity = "Common",
		Income = 2,
		Zones = { "Pier" },
		Shape = "Fish",
		Color = { 220, 170, 100 },
		Color2 = { 160, 105, 50 },
	},
	{
		Id = "GrumpyGoby",
		Name = "Grumpy Goby",
		NameRu = "Бычок-Ворчун",
		Rarity = "Common",
		Income = 3,
		Zones = { "Pier" },
		Shape = "Fish",
		Color = { 120, 110, 80 },
		Color2 = { 80, 70, 50 },
		Accessory = "Brows",
	},
	{
		Id = "SardineSam",
		Name = "Sardine Sam",
		NameRu = "Сардина Сэм",
		Rarity = "Common",
		Income = 5,
		Zones = { "Pier", "Lake" },
		Shape = "Long",
		Color = { 170, 190, 210 },
		Color2 = { 90, 110, 140 },
		Accessory = "Cap",
	},
	{
		Id = "ShadesPerch",
		Name = "Shades Perch",
		NameRu = "Окунь в очках",
		Rarity = "Uncommon",
		Income = 10,
		Zones = { "Pier", "Lake" },
		Shape = "Fish",
		Color = { 150, 190, 70 },
		Color2 = { 60, 90, 30 },
		Accessory = "Shades",
	},
	{
		Id = "PizzaRay",
		Name = "Pizza Ray",
		NameRu = "Скат-Пицца",
		Rarity = "Uncommon",
		Income = 15,
		Zones = { "Lake" },
		Shape = "Flat",
		Color = { 250, 200, 80 },
		Color2 = { 200, 50, 40 },
	},
	{
		Id = "BurgerBass",
		Name = "Burger Bass",
		NameRu = "Окунь-Бургер",
		Rarity = "Uncommon",
		Income = 25,
		Zones = { "Lake" },
		Shape = "Round",
		Color = { 200, 130, 60 },
		Color2 = { 90, 170, 60 },
	},
	{
		Id = "DJPuffer",
		Name = "DJ Puffer",
		NameRu = "Фугу-Диджей",
		Rarity = "Rare",
		Income = 60,
		Zones = { "Lake", "Reef" },
		Shape = "Round",
		Color = { 160, 90, 230 },
		Color2 = { 40, 40, 40 },
		Accessory = "Headphones",
	},
	{
		Id = "SkaterSalmon",
		Name = "Skater Salmon",
		NameRu = "Лосось-Скейтер",
		Rarity = "Rare",
		Income = 100,
		Zones = { "Reef" },
		Shape = "Fish",
		Color = { 250, 140, 120 },
		Color2 = { 60, 60, 60 },
		Accessory = "Cap",
	},
	{
		Id = "BananaEel",
		Name = "Banana Eel",
		NameRu = "Угорь-Банан",
		Rarity = "Rare",
		Income = 150,
		Zones = { "Reef" },
		Shape = "Long",
		Color = { 255, 225, 60 },
		Color2 = { 120, 90, 30 },
	},
	{
		Id = "ChefOcto",
		Name = "Chef Octo",
		NameRu = "Осьминог-Шеф",
		Rarity = "Epic",
		Income = 400,
		Zones = { "Reef" },
		Shape = "Octo",
		Color = { 230, 80, 70 },
		Color2 = { 255, 255, 255 },
		Accessory = "ChefHat",
	},
	{
		Id = "NinjaClownfish",
		Name = "Ninja Clownfish",
		NameRu = "Рыба-клоун Ниндзя",
		Rarity = "Epic",
		Income = 650,
		Zones = { "Reef" },
		Shape = "Fish",
		Color = { 255, 130, 30 },
		Color2 = { 30, 30, 30 },
		Accessory = "Headband",
	},
	{
		Id = "GamerGoldfish",
		Name = "Gamer Goldfish",
		NameRu = "Золотая рыбка-Геймер",
		Rarity = "Epic",
		Income = 900,
		Zones = { "StormSea" },
		Shape = "Fish",
		Color = { 255, 170, 40 },
		Color2 = { 60, 200, 90 },
		Accessory = "Headphones",
	},
	{
		Id = "KingCod",
		Name = "King Cod",
		NameRu = "Король-Треска",
		Rarity = "Legendary",
		Income = 3000,
		Zones = { "StormSea" },
		Shape = "Fish",
		Color = { 120, 140, 170 },
		Color2 = { 255, 210, 60 },
		Accessory = "Crown",
	},
	{
		Id = "RocketTuna",
		Name = "Rocket Tuna",
		NameRu = "Тунец-Ракета",
		Rarity = "Legendary",
		Income = 5000,
		Zones = { "StormSea" },
		Shape = "Long",
		Color = { 70, 90, 140 },
		Color2 = { 255, 90, 40 },
	},
	{
		Id = "DiscoShark",
		Name = "Disco Shark",
		NameRu = "Акула-Диско",
		Rarity = "Legendary",
		Income = 8000,
		Zones = { "SharkBay" },
		Shape = "Shark",
		Color = { 120, 130, 150 },
		Color2 = { 255, 80, 200 },
		Accessory = "Shades",
	},
	{
		Id = "CosmicJelly",
		Name = "Cosmic Jelly",
		NameRu = "Космическая медуза",
		Rarity = "Mythic",
		Income = 25000,
		Zones = { "SharkBay" },
		Shape = "Jelly",
		Color = { 90, 60, 200 },
		Color2 = { 255, 255, 180 },
	},
	{
		Id = "DragonKoi",
		Name = "Dragon Koi",
		NameRu = "Карп-Дракон",
		Rarity = "Mythic",
		Income = 60000,
		Zones = { "SharkBay" },
		Shape = "Long",
		Color = { 230, 50, 40 },
		Color2 = { 255, 215, 80 },
		Accessory = "Horns",
	},
	{
		Id = "BabyKraken",
		Name = "Baby Kraken",
		NameRu = "Малыш-Кракен",
		Rarity = "Secret",
		Income = 250000,
		Zones = { "Abyss" },
		Shape = "Octo",
		Color = { 40, 160, 130 },
		Color2 = { 200, 255, 230 },
	},
	{
		Id = "TheFishfather",
		Name = "The Fishfather",
		NameRu = "Крёстный Рыбец",
		Rarity = "Secret",
		Income = 500000,
		Zones = {},
		Special = "Hourly",
		Shape = "Fish",
		Color = { 40, 40, 50 },
		Color2 = { 200, 30, 40 },
		Accessory = "Fedora",
	},
}

FishData.FishList = FISH
FishData.Fish = {} :: { [string]: Fish }
for _, fish in FISH do
	FishData.Fish[fish.Id] = fish
end

-- Хелперы -------------------------------------------------------------------

-- Рыбы конкретной редкости, которые ловятся в зоне обычным уловом.
function FishData.fishIn(zoneId: string, rarityId: string?): { string }
	local result = {}
	for _, fish in FishData.FishList do
		if fish.Special == nil and (rarityId == nil or fish.Rarity == rarityId) and table.find(fish.Zones, zoneId) then
			table.insert(result, fish.Id)
		end
	end
	return result
end

-- Рыбы, которые сейчас можно добыть (по включённым зонам). Это и есть «индекс».
function FishData.obtainableFish(enabledZones: { [string]: boolean }): { string }
	local result = {}
	for _, fish in FishData.FishList do
		if fish.Special == nil then
			for _, zoneId in fish.Zones do
				if enabledZones[zoneId] then
					table.insert(result, fish.Id)
					break
				end
			end
		end
	end
	return result
end

function FishData.displayName(fishId: string): string
	local fish = FishData.Fish[fishId]
	return if fish then fish.NameRu else fishId
end

-- «Крупная Золотая Рыба-Батон»
function FishData.fullName(record: { Id: string, Size: string?, Mutation: string? }): string
	local parts = {}
	local size = record.Size and FishData.Sizes[record.Size]
	if size and record.Size ~= "Normal" then
		table.insert(parts, size.Name)
	end
	local mutation = record.Mutation and FishData.Mutations[record.Mutation]
	if mutation then
		table.insert(parts, mutation.Name)
	end
	table.insert(parts, FishData.displayName(record.Id))
	return table.concat(parts, " ")
end

return FishData
