--[[
	Смоук-тест мира без Roblox Studio: грузит собранный Rojo плейс в Lune, строит карту
	(MapService) и все модели рыб (FishModel) и проверяет геометрию по правилам диздока.

		rojo build default.project.json -o build/game.rbxl
		lune run tests/world.lune.luau build/game.rbxl [build/map.json]

	Lune проверяет имена и типы свойств по базе Roblox API, поэтому опечатка в свойстве
	или неверный тип значения падают здесь, а не в Studio. Движковые методы, которых
	в Lune нет (теги, группы столкновений, ландшафт), заменены простыми заглушками.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Runtime = require("./lune/runtime")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local placePath = process.args[1] or "build/game.rbxl"
local dumpPath = process.args[2]
local rt = Runtime.load(placePath)
local game = rt.game
local requireModule = rt.require
local modelParts = rt.modelParts
local terrainFills = rt.terrainFills

local Shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
local Services = game:GetService("ServerScriptService"):FindFirstChild("Server"):FindFirstChild("Services")

local suite = Runtime.suite()
local test, expect = suite.test, suite.expect

local Config = requireModule(Shared.Config)
local FishData = requireModule(Shared.FishData)
local Formulas = requireModule(Shared.Formulas)
local FishModel = requireModule(Shared.FishModel)

-- Модели рыб ------------------------------------------------------------------------------

test("все рыбы строятся во всех размерах и мутациях", function()
	local built = 0
	for _, fish in FishData.FishList do
		for _, size in FishData.SizeList do
			local mutations = { false }
			for _, mutation in FishData.MutationList do
				table.insert(mutations, mutation.Id)
			end
			for _, mutationId in mutations do
				local record = { Id = fish.Id, Size = size.Id, Mutation = if mutationId then mutationId else nil }
				local model = FishModel.build(record, { anchored = true })
				expect(model.PrimaryPart and model.PrimaryPart.Name == "Body", `{fish.Id}: нет тела`)
				local parts = modelParts(model)
				expect(#parts >= 4, `{fish.Id}: слишком мало деталей`)
				for _, part in parts do
					expect(part.CanCollide == false, `{fish.Id}.{part.Name}: рыба не должна толкаться`)
					if part ~= model.PrimaryPart then
						expect(part.Anchored == false, `{fish.Id}.{part.Name}: детали двигаются вместе с телом`)
						expect(part:FindFirstChildOfClass("WeldConstraint"), `{fish.Id}.{part.Name}: деталь не приварена`)
					end
				end
				model:PivotTo(CFrame.new(10, 20, 30))
				expect((model.PrimaryPart.CFrame.Position - Vector3.new(10, 20, 30)).Magnitude < 1e-3, "PivotTo сдвигает тело")
				built += 1
			end
		end
	end
	expect(built == 20 * 5 * 7, `построено {built}`)
end)

-- Карта -------------------------------------------------------------------------------------

local MapService = requireModule(Services.MapService)
local mapOk, mapError = pcall(MapService.init)
test("MapService.init отрабатывает без ошибок", function()
	expect(mapOk, tostring(mapError))
end)

if not mapOk then
	print(`{suite.passed} passed, {suite.failed} failed`)
	process.exit(1)
end

local workspace = game:GetService("Workspace")

local function localPoint(cf, point)
	return cf:PointToObjectSpace(point)
end

local function insideBox(part, point, margin)
	local p = localPoint(part.CFrame, point)
	local half = part.Size / 2
	margin = margin or 0
	return math.abs(p.X) <= half.X + margin and math.abs(p.Y) <= half.Y + margin and math.abs(p.Z) <= half.Z + margin
end

test("море и дно залиты ландшафтом", function()
	expect(#terrainFills == 2, "ожидались вода и песчаное дно")
end)

test("8 баз, у каждой места под все рыбы внутри аквариума", function()
	expect(#MapService.Plots == Config.MaxPlayers, "баз должно быть по числу игроков")
	local maxSlots = Formulas.maxPossibleSlots()
	for _, plot in MapService.Plots do
		expect(#plot.SlotCFrames == maxSlots, `база {plot.Index}: мест {#plot.SlotCFrames}`)
		local water = plot.Model:FindFirstChild("TankWater")
		for slot, slotCf in plot.SlotCFrames do
			expect(insideBox(water, slotCf.Position), `база {plot.Index}, место {slot}: рыба вне воды`)
		end
	end
end)

test("вор у стекла дотягивается до любой рыбы (≤ 8 студов)", function()
	for _, plot in MapService.Plots do
		local glassFrontZ = 13 - 3 - 0.6 -- tankZ - tankDepth/2 - полкорпуса
		for slot, slotCf in plot.SlotCFrames do
			local slotLocal = plot.CFrame:PointToObjectSpace(slotCf.Position)
			-- игрок стоит вплотную к стеклу напротив рыбы, корень персонажа ~3 студа над полом
			local stand = plot.CFrame * Vector3.new(slotLocal.X, 1.6 + 3, glassFrontZ - 0.6)
			local distance = (stand - slotCf.Position).Magnitude
			expect(distance <= Config.Steal.MaxDistance, `база {plot.Index}, место {slot}: {distance} студов`)
		end
	end
end)

test("базы смотрят входом в центр гавани и не пересекаются", function()
	for _, plot in MapService.Plots do
		local toCenter = (Vector3.new(0, plot.CFrame.Position.Y, 0) - plot.CFrame.Position).Unit
		expect(plot.CFrame.LookVector:Dot(toCenter) > 0.99, `база {plot.Index} смотрит не в центр`)
		expect(MapService.isInsidePlot(plot, plot.SpawnCFrame.Position), `база {plot.Index}: спавн вне базы`)
		for _, other in MapService.Plots do
			if other ~= plot then
				local distance = (other.CFrame.Position - plot.CFrame.Position).Magnitude
				expect(distance > plot.HalfSize * 2 * 1.3, `базы {plot.Index} и {other.Index} слишком близко`)
			end
		end
	end
end)

test("барьеры замка: свои группы столкновений у каждой базы", function()
	for _, plot in MapService.Plots do
		expect(#plot.Barrier == 4, "четыре стены")
		for _, wall in plot.Barrier do
			expect(wall.CollisionGroup == plot.BarrierGroup, "стена в группе барьера")
			expect(wall.CanCollide == false and wall.Transparency == 1, "по умолчанию барьер выключен")
		end
	end
end)

-- Время бега с ведром (скорость −10%) от ближайшей базы до ближайшего места рыбалки.
local function runSeconds(zoneId)
	local best = math.huge
	for _, area in MapService.FishingAreas do
		if area:GetAttribute("ZoneId") == zoneId then
			for _, plot in MapService.Plots do
				-- ближайшая точка зоны к центру базы и ближайшая точка базы к зоне
				local p = localPoint(area.CFrame, plot.CFrame.Position)
				local half = area.Size / 2
				local clamped = area.CFrame
					* Vector3.new(math.clamp(p.X, -half.X, half.X), math.clamp(p.Y, -half.Y, half.Y), math.clamp(p.Z, -half.Z, half.Z))
				local flat = Vector3.new(clamped.X - plot.CFrame.Position.X, 0, clamped.Z - plot.CFrame.Position.Z)
				best = math.min(best, math.max(0, flat.Magnitude - plot.HalfSize))
			end
		end
	end
	return best / Formulas.walkSpeed(0, "Normal")
end

test("время бега до зон совпадает с диздоком", function()
	local expected = { Pier = { 3, 8 }, Lake = { 13, 18 }, Reef = { 28, 36 } }
	for zoneId, range in expected do
		local seconds = runSeconds(zoneId)
		print(string.format("      %s: %.1f с бега с ведром (в диздоке %d с)", zoneId, seconds, FishData.Zones[zoneId].RunTime))
		expect(seconds >= range[1] and seconds <= range[2], `{zoneId}: {seconds} с`)
	end
end)

test("на пирсе можно рыбачить везде, где под настилом вода", function()
	local pier = workspace.Map.Pier.PierDeck
	local half = pier.Size.Z / 2
	local checked = 0
	for t = 0, 1, 0.05 do
		local point = pier.CFrame * Vector3.new(0, pier.Size.Y / 2 + 3, -half + t * half * 2)
		-- край пляжа острова: радиус 150 + 7
		if math.abs(point.Z) > 160 then
			checked += 1
			expect(MapService.zoneAt(point) == "Pier", `точка z={point.Z} пирса вне зоны рыбалки`)
		end
	end
	expect(checked >= 10, "проверено мало точек")
end)

test("ворота перекрывают дорогу целиком и стоят на ней", function()
	for zoneId, gate in MapService.Gates do
		expect(gate.Size.X >= 12, `{zoneId}: ворота уже настила`)
		expect(gate.CanCollide, `{zoneId}: ворота должны держать игрока`)
		expect(gate:FindFirstChild("UnlockPrompt"), `{zoneId}: нет кнопки открытия`)
		expect(MapService.zoneAt(gate.CFrame.Position) == nil, `{zoneId}: ворота внутри зоны рыбалки`)
	end
	expect(MapService.Gates.Lake and MapService.Gates.Reef, "ворота Озера и Рифа")
	expect(MapService.Gates.Pier == nil, "Пирс открыт сразу")
end)

test("лужи накрывают дорожку во всю ширину", function()
	expect(#MapService.Puddles >= 4, "фонтан + лужи на маршрутах")
	for _, puddle in MapService.Puddles do
		local radius = puddle:GetAttribute("Radius")
		expect(type(radius) == "number" and radius >= 6, `{puddle:GetFullName()}: радиус {radius}`)
	end
end)

test("медузы висят над настилом и атоллом", function()
	expect(#MapService.Jellyfish == 12, "12 медуз")
	for _, jelly in MapService.Jellyfish do
		for _, t in { 0, 0.7, 1.9, 3.3 } do
			local position = MapService.jellyPosition(jelly, t)
			expect(position.Z > MapService.HazardMinZ, "медузы только у рифа")
			expect(position.Y > 1 and position.Y < 8, "на высоте игрока")
		end
	end
end)

test("рынок и магазин в центре, с кнопками", function()
	expect(MapService.ShopPrompt and MapService.MarketPrompt, "кнопки прилавков")
	expect(MapService.ShopPosition.Magnitude < 50 and MapService.MarketPosition.Magnitude < 50, "прилавки в центре гавани")
	expect(#MapService.LeaderboardRows == Config.MaxPlayers, "строки доски лидеров")
end)

test("в шаблонном плейсе нет Baseplate поверх воды", function()
	expect(workspace:FindFirstChild("Baseplate") == nil)
	expect(workspace.Map.Harbor:FindFirstChild("PlazaSpawn"), "свой спавн в центре")
end)

-- Выгрузка карты для картинки сверху ------------------------------------------------------------

if dumpPath then
	local parts = {}
	for _, part in workspace.Map:GetDescendants() do
		if part:IsA("BasePart") then
			local cf = part.CFrame
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
			local shape = if part:IsA("Part") then part.Shape.Name else part.ClassName
			table.insert(parts, {
				name = part.Name,
				shape = shape,
				cf = { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 },
				size = { part.Size.X, part.Size.Y, part.Size.Z },
				color = { part.Color.R, part.Color.G, part.Color.B },
				transparency = part.Transparency,
				zone = part:GetAttribute("ZoneId"),
			})
		end
	end
	fs.writeFile(dumpPath, serde.encode("json", parts))
	print(`map dumped: {#parts} parts -> {dumpPath}`)
end

test("в рантайме не было ошибок и warn", function()
	expect(#rt.failures == 0, table.concat(rt.failures, "\n"))
end)

print(`{suite.passed} passed, {suite.failed} failed`)
process.exit(if suite.failed > 0 then 1 else 0)
