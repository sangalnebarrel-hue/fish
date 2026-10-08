local Config = Shared.Config
local FishData = Shared.FishData
local ShopData = Shared.ShopData
local Formulas = Shared.Formulas

local function seeded(seed)
	math.randomseed(seed)
	return function()
		return math.random()
	end
end

local function countRolls(n, fn)
	local counts = {}
	for _ = 1, n do
		local key = fn()
		if key ~= nil then
			counts[key] = (counts[key] or 0) + 1
		end
	end
	return counts
end

test("в данных 20 рыб и все ссылки корректны", function()
	expect(#FishData.FishList == 20, "ожидалось 20 рыб, а их " .. #FishData.FishList)
	for _, fish in FishData.FishList do
		expect(FishData.Rarities[fish.Rarity] ~= nil, fish.Id .. ": неизвестная редкость")
		for _, zoneId in fish.Zones do
			expect(FishData.Zones[zoneId] ~= nil, fish.Id .. ": неизвестная зона " .. zoneId)
		end
		expect(#fish.Color == 3 and #fish.Color2 == 3, fish.Id .. ": цвет должен быть {r, g, b}")
	end
end)

test("в MVP можно поймать ровно 12 рыб", function()
	local obtainable = FishData.obtainableFish(Config.EnabledZones)
	expect(#obtainable == 12, "ожидалось 12, получилось " .. #obtainable)
end)

test("в каждой редкости зоны есть хотя бы одна рыба", function()
	for _, zone in FishData.ZoneList do
		for rarityId, weight in zone.Rarities do
			if weight > 0 then
				expect(#FishData.fishIn(zone.Id, rarityId) > 0, zone.Id .. " / " .. rarityId .. ": пусто")
			end
		end
	end
end)

test("лучшая рыба зон совпадает с диздоком", function()
	local expected = {
		Pier = "Uncommon",
		Lake = "Rare",
		Reef = "Epic",
		StormSea = "Legendary",
		SharkBay = "Mythic",
		Abyss = "Secret",
	}
	for zoneId, rarityId in expected do
		local best = 0
		for _, fishId in FishData.fishIn(zoneId) do
			best = math.max(best, FishData.Rarities[FishData.Fish[fishId].Rarity].Order)
		end
		expect(best == FishData.Rarities[rarityId].Order, zoneId .. ": лучшая редкость не " .. rarityId)
	end
end)

test("удача сдвигает улов к редким", function()
	local rng = seeded(1)
	local base = countRolls(20000, function()
		return FishData.Fish[Formulas.rollFish("Reef", { luck = 1 }, rng)].Rarity
	end)
	local lucky = countRolls(20000, function()
		return FishData.Fish[Formulas.rollFish("Reef", { luck = 4 }, rng)].Rarity
	end)
	local baseEpic = (base.Epic or 0) / 20000
	local luckyEpic = (lucky.Epic or 0) / 20000
	expect(baseEpic > 0.11 and baseEpic < 0.17, "Epic на Рифе без удачи ≈14%, а вышло " .. baseEpic)
	expect(luckyEpic > baseEpic * 2, "удача ×4 должна заметно поднимать Epic: " .. luckyEpic)
end)

test("Светлячок ночью удваивает вес Epic+", function()
	local plain = Formulas.rarityWeights("Reef", { luck = 1 })
	local firefly = Formulas.rarityWeights("Reef", { luck = 1, epicPlusMult = 2 })
	local function weightOf(entries, key)
		for _, entry in entries do
			if entry.key == key then
				return entry.weight
			end
		end
		return 0
	end
	expect(near(weightOf(firefly, "Epic"), weightOf(plain, "Epic") * 2), "Epic должен удвоиться")
	expect(near(weightOf(firefly, "Rare"), weightOf(plain, "Rare")), "Rare не должен меняться")
end)

test("в MVP выпадают только 3 размера", function()
	local rng = seeded(2)
	local sizes = countRolls(20000, function()
		return Formulas.rollSize(rng)
	end)
	expect(sizes.Giant == nil and sizes.Whale == nil, "Гигантские и Китовые выключены в MVP")
	expect(sizes.Fry and sizes.Normal and sizes.Large, "должны выпадать Малёк, Обычная и Крупная")
	expect(sizes.Normal > sizes.Fry and sizes.Fry > sizes.Large, "порядок частот: Обычная > Малёк > Крупная")
end)

test("Электрическая мутация только в Шторм, Алмазной в MVP нет", function()
	local rng = seeded(3)
	local calm = countRolls(20000, function()
		return Formulas.rollMutation({ luck = 1, conditions = {} }, rng)
	end)
	local storm = countRolls(20000, function()
		return Formulas.rollMutation({ luck = 1, conditions = { Storm = true } }, rng)
	end)
	expect(calm.Electric == nil, "без Шторма Электрической быть не должно")
	expect(calm.Diamond == nil and calm.Rainbow == nil, "Алмазная и Радужная выключены в MVP")
	local golden = (calm.Golden or 0) / 20000
	expect(golden > 0.02 and golden < 0.04, "Золотая ≈3%, а вышло " .. golden)
	local electric = (storm.Electric or 0) / 20000
	expect(electric > 0.17 and electric < 0.23, "Электрическая в Шторм ≈20%, а вышло " .. electric)
end)

test("Золотая удочка и наживка повышают шанс Золотой", function()
	local ctx = Formulas.catchContext("Golden", "GoldenBait", {}, {}, false)
	expect(ctx.goldenMult == 6, "удочка ×2 и наживка ×3 = ×6")
	local rng = seeded(4)
	local counts = countRolls(20000, function()
		return Formulas.rollMutation(ctx, rng)
	end)
	local golden = (counts.Golden or 0) / 20000
	expect(golden > 0.15 and golden < 0.21, "Золотая с ×6 ≈18%, а вышло " .. golden)
end)

test("цены на рынке совпадают с таблицей редкостей", function()
	local ranges = {
		Common = { 10, 50 },
		Uncommon = { 200, 500 },
		Rare = { 1900, 5000 },
		Epic = { 30000, 70000 },
		Legendary = { 450000, 1300000 },
		Mythic = { 8000000, 20000000 },
	}
	for _, fish in FishData.FishList do
		local range = ranges[fish.Rarity]
		local price = Formulas.sellPrice({ Id = fish.Id, Size = "Normal" })
		if range then
			expect(price >= range[1] and price <= range[2], fish.Id .. ": цена " .. tostring(price))
		else
			expect(price == nil, fish.Id .. ": Secret не продаётся")
		end
	end
end)

test("держать рыбу выгоднее, чем продать: цена ≤ 400 сек дохода", function()
	for _, fish in FishData.FishList do
		local record = { Id = fish.Id, Size = "Normal" }
		local price = Formulas.sellPrice(record)
		if price then
			expect(price / Formulas.fishIncome(record) <= 400, fish.Id)
		end
	end
end)

test("доход: размер и мутация перемножаются", function()
	-- Гигантская Радужная Epic-рыба даёт ×40 (пример из диздока)
	local income = Formulas.fishIncome({ Id = "ChefOcto", Size = "Giant", Mutation = "Rainbow" })
	expect(income == 400 * 40, "ожидалось 16000, вышло " .. income)
	expect(Formulas.incomeMultiplier(0, {}) == 1)
	expect(Formulas.incomeMultiplier(1, { VIP = true, DoubleMoney = true }) == 1.5 * 1.5 * 2)
end)

test("кислород: редкость, Малёк, ведро и геймпасс", function()
	expect(Formulas.maxOxygen({ Id = "ChefOcto", Size = "Normal" }, "Leaky", {}) == 30)
	expect(near(Formulas.maxOxygen({ Id = "SockFish", Size = "Fry" }, "Leaky", {}), 72))
	expect(near(Formulas.maxOxygen({ Id = "ChefOcto", Size = "Normal" }, "Big", { OxygenTank = true }), 30 * 1.6 * 1.3))
	expect(Formulas.oxygenDrain({ Mutation = "Ice" }, false, false) == 0.5)
	expect(Formulas.oxygenDrain({}, true, false) == 2)
	expect(Formulas.puddleBonus("Leaky") == 10 and Formulas.puddleBonus("Tank") == 20)
end)

test("Гигантских можно нести только в Большом ведре", function()
	expect(Formulas.canCarry("Large", "Leaky"))
	expect(not Formulas.canCarry("Giant", "Plastic"))
	expect(Formulas.canCarry("Giant", "Big"))
	expect(not Formulas.canCarry("Whale", "Big"))
	expect(Formulas.canCarry("Whale", "Backpack"))
end)

test("скорость: ласты +4% за уровень, ведро −10%", function()
	expect(Formulas.walkSpeed(0, nil) == 16)
	expect(near(Formulas.walkSpeed(0, "Normal"), 14.4))
	expect(near(Formulas.walkSpeed(20, nil), 28.8))
	expect(near(Formulas.walkSpeed(25, nil), 28.8), "уровень ласт ограничен 20")
	expect(Formulas.finsPrice(1) == 300)
	for level = 2, 20 do
		local ratio = Formulas.finsPrice(level) / Formulas.finsPrice(level - 1)
		expect(ratio > 1.55 and ratio < 1.65, "ласты дорожают ×1,6")
	end
end)

test("с Эпиком с Рифа можно успеть только через бочки", function()
	-- 30 сек бега стартовой скоростью, с ведром бег на 10% медленнее
	local runWithBucket = FishData.Zones.Reef.RunTime / 0.9
	local oxygen = Formulas.maxOxygen({ Id = "ChefOcto", Size = "Normal" }, "Leaky", {})
	expect(oxygen < runWithBucket, "без луж не успеть — в этом весь смысл таймера")
	expect(oxygen + Config.Oxygen.PuddleBonus > runWithBucket, "с одной лужей успеть можно")
end)

test("аквариум: 6 мест, расширение до 10, VIP +2", function()
	expect(Formulas.aquariumSlots(1, {}) == 6)
	expect(Formulas.aquariumSlots(2, {}) == 10)
	expect(Formulas.aquariumSlots(1, { VIP = true }) == 8)
	expect(Formulas.maxPossibleSlots() == 12)
end)

test("мини-игра: зона внутри полоски, Нептун подсекает редких сам", function()
	local rng = seeded(5)
	for _, rarity in FishData.RarityList do
		for _, rod in ShopData.RodList do
			local params = Formulas.hookParams(rarity.Id, rod.Id, rng)
			expect(params.zoneCenter - params.zoneWidth / 2 >= 0 and params.zoneCenter + params.zoneWidth / 2 <= 1)
		end
	end
	expect(Formulas.hookParams("Rare", "Neptune", rng).autoHook)
	expect(not Formulas.hookParams("Uncommon", "Neptune", rng).autoHook)
	expect(not Formulas.hookParams("Mythic", "Golden", rng).autoHook)
	expect(Formulas.markerPosition(0, 1) == 0 and Formulas.markerPosition(1, 1) == 1 and near(Formulas.markerPosition(1.5, 1), 0.5))
end)

test("поклёвка: Карбоновая и Косяк ускоряют", function()
	local rng = seeded(6)
	for _ = 1, 200 do
		local delay = Formulas.biteDelay(rng, "Stick", false)
		expect(delay >= Config.Fishing.BiteDelayMin and delay <= Config.Fishing.BiteDelayMax)
		local fast = Formulas.biteDelay(rng, "Carbon", true)
		expect(fast <= Config.Fishing.BiteDelayMax * 0.7 * 0.5 + 1e-9)
	end
end)

test("офлайн-доход: 50% и не больше 4 часов", function()
	expect(Formulas.offlineEarnings(100, 60) == 3000)
	expect(Formulas.offlineEarnings(100, 10 * 3600) == 100 * 0.5 * 4 * 3600)
	expect(Formulas.offlineEarnings(100, -5) == 0)
end)

test("цены снаряжения растут ступенями", function()
	for _, list in { ShopData.RodList, ShopData.BucketList } do
		for i = 3, #list do
			local ratio = list[i].Price / list[i - 1].Price
			expect(ratio >= 20 and ratio <= 65, list[i].Id .. ": шаг цены ×" .. ratio)
		end
	end
end)
