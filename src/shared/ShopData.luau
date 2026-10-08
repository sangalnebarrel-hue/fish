--[[
	Снаряжение, наживка, ласты, расширения аквариума и геймпассы.
	Цены растут примерно в 25–60 раз за ступень (см. диздок, раздел «Прогрессия»).
]]

local ShopData = {}

export type Rod = {
	Id: string,
	Name: string,
	Price: number,
	Luck: number,
	HookZone: number,
	BiteSpeed: number,
	GoldenMult: number,
	AutoHookFrom: string?,
	Perk: string?,
}

export type Bucket = {
	Id: string,
	Name: string,
	Price: number,
	Oxygen: number,
	Capacity: number,
	PuddleBonus: number?,
	Perk: string?,
}

export type Bait = {
	Id: string,
	Name: string,
	Price: number?,
	Pack: number,
	Infinite: boolean?,
	Luck: number?,
	NightEpicMult: number?,
	GoldenMult: number?,
	SecretMult: number?,
	Description: string,
}

export type Pass = { Id: string, Name: string, Robux: number, Description: string }

-- Удочки --------------------------------------------------------------------

-- HookZone: множитель ширины зелёной зоны в мини-игре.
-- BiteSpeed: множитель ожидания поклёвки (меньше — быстрее).
-- GoldenMult: множитель шанса Золотой мутации.
-- AutoHookFrom: начиная с этой редкости рыба подсекается сама.
local RODS: { Rod } = {
	{
		Id = "Stick",
		Name = "Палка с ниткой",
		Price = 0,
		Luck = 1,
		HookZone = 1,
		BiteSpeed = 1,
		GoldenMult = 1,
	},
	{
		Id = "Bamboo",
		Name = "Бамбуковая",
		Price = 500,
		Luck = 1.3,
		HookZone = 1.35,
		BiteSpeed = 1,
		GoldenMult = 1,
		Perk = "Зона подсечки шире",
	},
	{
		Id = "Carbon",
		Name = "Карбоновая",
		Price = 15000,
		Luck = 1.7,
		HookZone = 1.35,
		BiteSpeed = 0.7,
		GoldenMult = 1,
		Perk = "Поклёвка быстрее",
	},
	{
		Id = "Golden",
		Name = "Золотая",
		Price = 400000,
		Luck = 2.5,
		HookZone = 1.45,
		BiteSpeed = 0.7,
		GoldenMult = 2,
		Perk = "Шанс Золотой мутации ×2",
	},
	{
		Id = "Neptune",
		Name = "Удочка Нептуна",
		Price = 25000000,
		Luck = 4,
		HookZone = 1.5,
		BiteSpeed = 0.6,
		GoldenMult = 2,
		AutoHookFrom = "Rare",
		Perk = "Редкие подсекаются сами",
	},
}

-- Вёдра ---------------------------------------------------------------------

-- Capacity: максимальный размер рыбы (см. FishData.Sizes.Capacity).
local BUCKETS: { Bucket } = {
	{ Id = "Leaky", Name = "Дырявое ведро", Price = 0, Oxygen = 1, Capacity = 1 },
	{ Id = "Plastic", Name = "Пластиковое ведро", Price = 2000, Oxygen = 1.3, Capacity = 1 },
	{
		Id = "Big",
		Name = "Большое ведро",
		Price = 50000,
		Oxygen = 1.6,
		Capacity = 2,
		Perk = "Можно нести Гигантских",
	},
	{
		Id = "Backpack",
		Name = "Аквариум-рюкзак",
		Price = 2000000,
		Oxygen = 2.2,
		Capacity = 3,
		Perk = "Можно нести Китовых",
	},
	{
		Id = "Tank",
		Name = "Кислородный баллон",
		Price = 50000000,
		Oxygen = 3,
		Capacity = 3,
		PuddleBonus = 20,
		Perk = "Лужи дают +20 сек вместо +10",
	},
}

-- Наживка -------------------------------------------------------------------

-- Червяк бесплатный и бесконечный. Остальное покупается пачками и тратится по одной за заброс.
local BAITS: { Bait } = {
	{
		Id = "Worm",
		Name = "Червяк",
		Price = 0,
		Pack = 0,
		Infinite = true,
		Description = "Бесплатно и бесконечно",
	},
	{ Id = "Shrimp", Name = "Креветка", Price = 300, Pack = 10, Luck = 1.2, Description = "Удача +20%" },
	{
		Id = "Firefly",
		Name = "Светлячок",
		Price = 4000,
		Pack = 5,
		NightEpicMult = 2,
		Description = "Ночью шанс Epic и выше ×2",
	},
	{
		Id = "GoldenBait",
		Name = "Золотая наживка",
		Price = 12000,
		Pack = 5,
		GoldenMult = 3,
		Description = "Шанс Золотой мутации ×3",
	},
	{
		Id = "SecretLure",
		Name = "Секретная приманка",
		Price = nil, -- только из колеса удачи, ивентов и индекса
		Pack = 1,
		SecretMult = 5,
		Description = "Шанс Secret ×5",
	},
}

-- Аквариум ------------------------------------------------------------------

ShopData.AquariumTiers = {
	{ Slots = 6, Price = 0 },
	{ Slots = 10, Price = 7500 },
	{ Slots = 15, Price = 250000 },
	{ Slots = 20, Price = 6000000 },
	{ Slots = 30, Price = 150000000 },
}

-- Геймпассы -----------------------------------------------------------------

local PASSES: { Pass } = {
	{
		Id = "VIP",
		Name = "VIP",
		Robux = 399,
		Description = "Доход ×1,5, тег в чате, +2 места в аквариуме",
	},
	{
		Id = "DoubleMoney",
		Name = "×2 Деньги",
		Robux = 499,
		Description = "Двойной доход навсегда",
	},
	{ Id = "DoubleLuck", Name = "×2 Удача", Robux = 349, Description = "Удача ×2 при рыбалке" },
	{
		Id = "OxygenTank",
		Name = "Кислородный баллон",
		Robux = 249,
		Description = "+30% кислорода к любому ведру",
	},
	{
		Id = "AutoFish",
		Name = "Авто-рыбалка",
		Robux = 299,
		Description = "Ловит сам, пока стоишь у воды",
	},
	{
		Id = "SecondFloor",
		Name = "Второй этаж",
		Robux = 199,
		Description = "+10 мест в аквариуме",
	},
}

-- Индексы по Id --------------------------------------------------------------

local function byId<T>(list: { T }): { [string]: T }
	local map = {}
	for _, item in list do
		map[(item :: any).Id] = item
	end
	return map
end

ShopData.RodList = RODS
ShopData.BucketList = BUCKETS
ShopData.BaitList = BAITS
ShopData.PassList = PASSES
ShopData.Rods = byId(RODS)
ShopData.Buckets = byId(BUCKETS)
ShopData.Baits = byId(BAITS)
ShopData.Passes = byId(PASSES)

-- Награды индекса за каждые 5 открытых рыб.
local INDEX_REWARDS: { [number]: { Bait: string, Amount: number } } = {
	[5] = { Bait = "Shrimp", Amount = 10 },
	[10] = { Bait = "GoldenBait", Amount = 5 },
	[15] = { Bait = "Firefly", Amount = 10 },
	[20] = { Bait = "SecretLure", Amount = 1 },
}
ShopData.IndexRewards = INDEX_REWARDS

return ShopData
