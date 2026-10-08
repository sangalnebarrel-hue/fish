--[[
	Строит мир при старте сервера: гавань с 8 базами вокруг, рынок, магазин, фонтан,
	зоны рыбалки (Пирс, Озеро, Коралловый риф), лужи-чекпоинты, ворота зон и медуз.
	Карта целиком процедурная, поэтому игра запускается в пустом плейсе без ассетов.

	Координаты: центр гавани в (0, 0, 0), вода на высоте 0, земля острова на высоте 1.
	Пирс на севере (-Z), Озеро на востоке (+X), Риф на юге (+Z), на западе — тизер будущих зон.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FishData = require(Shared.FishData)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)

local MapService = {}

export type Plot = {
	Index: number,
	Model: Model,
	CFrame: CFrame,
	HalfSize: number,
	SlotCFrames: { CFrame },
	FishFolder: Folder,
	Barrier: { BasePart },
	BarrierGroup: string,
	OwnerGroup: string,
	SignTitle: TextLabel,
	SignSubtitle: TextLabel,
	OwnerTag: TextLabel,
	SpawnCFrame: CFrame,
	LockPad: BasePart,
	LockPrompt: ProximityPrompt,
	AlarmSound: Sound,
	Color: Color3,
}

export type Jelly = {
	Part: BasePart,
	Origin: Vector3,
	Axis: Vector3,
	Amplitude: number,
	Period: number,
	Phase: number,
}

MapService.WaterLevel = 0
MapService.GroundLevel = 1
MapService.Plots = {} :: { Plot }
MapService.FishingAreas = {} :: { BasePart }
MapService.Puddles = {} :: { BasePart }
MapService.Gates = {} :: { [string]: BasePart }
MapService.Jellyfish = {} :: { Jelly }
MapService.ShoalEmitters = {} :: { ParticleEmitter }
MapService.LeaderboardRows = {} :: { TextLabel }
MapService.EventBoardLabel = nil :: TextLabel?
MapService.ShopPosition = Vector3.zero
MapService.MarketPosition = Vector3.zero
MapService.ShopPrompt = nil :: ProximityPrompt?
MapService.HazardMinZ = math.huge -- южнее этой линии начинаются медузы рифа
MapService.MarketPrompt = nil :: ProximityPrompt?

local ISLAND_RADIUS = 150
local PLAZA_RADIUS = 42
local BASE_RING_RADIUS = 92
local BASE_HALF = 20
local DECK_Y = 2.2

local BASE_COLORS = {
	Color3.fromRGB(235, 80, 80),
	Color3.fromRGB(70, 140, 240),
	Color3.fromRGB(90, 200, 100),
	Color3.fromRGB(245, 200, 60),
	Color3.fromRGB(170, 100, 230),
	Color3.fromRGB(250, 140, 50),
	Color3.fromRGB(240, 120, 190),
	Color3.fromRGB(60, 200, 200),
}

local WOOD = Color3.fromRGB(150, 105, 65)
local DARK_WOOD = Color3.fromRGB(105, 70, 45)
local SAND = Color3.fromRGB(235, 215, 160)
local STONE = Color3.fromRGB(165, 165, 170)
local WATER = Color3.fromRGB(70, 170, 230)

local root: Folder

type Box = { size: Vector3, offset: CFrame }

-- Хелперы -------------------------------------------------------------------

type PartProps = {
	Name: string?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Transparency: number?,
	CanCollide: boolean?,
	Parent: Instance?,
	ClassName: string?,
}

local function part(props: PartProps): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	p.Name = props.Name or "Part"
	p.Anchored = true
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or STONE
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape and p:IsA("Part") then
		p.Shape = props.Shape
	end
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	if props.CanCollide ~= nil then
		p.CanCollide = props.CanCollide
	end
	p.Parent = props.Parent or root
	return p
end

-- Вертикальный цилиндр: у Part ось цилиндра идёт по X, поворачиваем её вверх.
local function cylinder(
	name: string,
	center: Vector3,
	diameter: number,
	height: number,
	color: Color3,
	material: Enum.Material?,
	parent: Instance?
): BasePart
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
		Parent = parent,
	})
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.FredokaOne
	l.Text = text
	l.TextScaled = true
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
	l.Parent = parent
	return l
end

-- Табличка с надписью на передней грани (-Z).
local function sign(name: string, cf: CFrame, size: Vector2, text: string, background: Color3, parent: Instance?): (BasePart, TextLabel)
	local board = part({
		Name = name,
		Size = Vector3.new(size.X, size.Y, 0.5),
		CFrame = cf,
		Color = background,
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local textLabel = label(gui, text, UDim2.fromScale(0.94, 0.86), UDim2.fromScale(0.03, 0.07))
	return board, textLabel
end

local function prompt(parent: Instance, actionText: string, objectText: string, holdDuration: number?, distance: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = actionText
	p.ObjectText = objectText
	p.HoldDuration = holdDuration or 0
	p.MaxActivationDistance = distance or 10
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

local function tree(position: Vector3, parent: Instance, palm: boolean?)
	local height = palm and 14 or 9
	cylinder("Trunk", position + Vector3.new(0, height / 2, 0), palm and 1.4 or 2, height, DARK_WOOD, Enum.Material.Wood, parent)
	if palm then
		for i = 0, 4 do
			local angle = i * math.pi * 2 / 5
			part({
				Name = "Leaf",
				Size = Vector3.new(1.5, 0.4, 8),
				CFrame = CFrame.new(position + Vector3.new(0, height, 0))
					* CFrame.Angles(0, angle, 0)
					* CFrame.new(0, -0.6, -3.5)
					* CFrame.Angles(math.rad(-15), 0, 0),
				Color = Color3.fromRGB(60, 160, 70),
				Material = Enum.Material.Grass,
				CanCollide = false,
				Parent = parent,
			})
		end
	else
		part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 9,
			CFrame = CFrame.new(position + Vector3.new(0, height + 2.5, 0)),
			Color = Color3.fromRGB(70, 150, 70),
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = parent,
		})
	end
end

-- barrelOffset: где поставить бочку с водой рядом с лужей (сбоку от дорожки, чтобы не мешала бегу).
local function puddle(position: Vector3, diameter: number, parent: Instance, barrelOffset: Vector3?): BasePart
	local water = cylinder("Puddle", position, diameter, 0.2, WATER, Enum.Material.SmoothPlastic, parent)
	water.CanCollide = false
	water.Transparency = 0.15
	water:SetAttribute("Radius", diameter / 2 + 1.5)
	water:SetAttribute("ReadyAt", 0)
	CollectionService:AddTag(water, "Puddle")
	table.insert(MapService.Puddles, water)
	if barrelOffset then
		local barrelBase = position + barrelOffset
		cylinder("Barrel", barrelBase + Vector3.new(0, 1.8, 0), 3, 3.6, DARK_WOOD, Enum.Material.Wood, parent)
		cylinder("BarrelWater", barrelBase + Vector3.new(0, 3.65, 0), 2.6, 0.1, WATER, nil, parent)
	end
	return water
end

local function fishingArea(zoneId: string, cf: CFrame, size: Vector3, parent: Instance): BasePart
	local area = part({
		Name = "FishingArea",
		Size = size,
		CFrame = cf,
		Transparency = 1,
		CanCollide = false,
		Parent = parent,
	})
	area.CanQuery = false
	area.CanTouch = false
	area:SetAttribute("ZoneId", zoneId)
	CollectionService:AddTag(area, "FishingArea")
	table.insert(MapService.FishingAreas, area)
	return area
end

-- Пузыри «косяка» в воде, включаются EventService во время ивента.
local function shoalSpot(position: Vector3, size: Vector3, parent: Instance)
	local spot = part({
		Name = "ShoalSpot",
		Size = size,
		CFrame = CFrame.new(position),
		Transparency = 1,
		CanCollide = false,
		Parent = parent,
	})
	spot.CanQuery = false
	spot.CanTouch = false
	local emitter = Instance.new("ParticleEmitter")
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 240, 255))
	emitter.Size = NumberSequence.new(0.6, 0.1)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.Rate = 25
	emitter.Enabled = false
	emitter.Parent = spot
	table.insert(MapService.ShoalEmitters, emitter)
end

local function gate(zoneId: string, cf: CFrame, width: number, parent: Instance)
	local zone = FishData.Zones[zoneId]
	local gatePart = part({
		Name = `Gate_{zoneId}`,
		Size = Vector3.new(width, 12, 1),
		CFrame = cf * CFrame.new(0, 6, 0),
		Color = Color3.fromRGB(255, 200, 60),
		Material = Enum.Material.ForceField,
		Parent = parent,
	})
	gatePart:SetAttribute("ZoneId", zoneId)
	CollectionService:AddTag(gatePart, "ZoneGate")
	for _, side in { -1, 1 } do
		part({
			Name = "GatePost",
			Size = Vector3.new(1.5, 14, 1.5),
			CFrame = cf * CFrame.new(side * (width / 2 + 0.75), 7, 0),
			Color = DARK_WOOD,
			Material = Enum.Material.Wood,
			Parent = parent,
		})
	end
	local price = Format.money(zone.UnlockPrice or 0)
	sign(`GateSign_{zoneId}`, cf * CFrame.new(0, 15, 0), Vector2.new(width + 3, 3), `{zone.Name} — {price}`, DARK_WOOD, parent)
	prompt(gatePart, `Открыть за {price}`, zone.Name, 0.5, 12).Name = "UnlockPrompt"
	MapService.Gates[zoneId] = gatePart
end

-- Медуза: сервер считает её положение формулой (см. HazardService), клиент рисует то же самое.
local function jelly(origin: Vector3, axis: Vector3, amplitude: number, period: number, phase: number, parent: Instance)
	local body = part({
		Name = "Jellyfish",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		CFrame = CFrame.new(origin),
		Color = Color3.fromRGB(255, 120, 200),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		Parent = parent,
	})
	body.CanQuery = false
	body.CanTouch = false
	body:SetAttribute("OriginX", origin.X)
	body:SetAttribute("OriginY", origin.Y)
	body:SetAttribute("OriginZ", origin.Z)
	body:SetAttribute("Axis", axis)
	body:SetAttribute("Amplitude", amplitude)
	body:SetAttribute("Period", period)
	body:SetAttribute("Phase", phase)
	CollectionService:AddTag(body, "Jellyfish")
	table.insert(MapService.Jellyfish, {
		Part = body,
		Origin = origin,
		Axis = axis,
		Amplitude = amplitude,
		Period = period,
		Phase = phase,
	})
end

-- Окружение -----------------------------------------------------------------

local function setupLighting()
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(110, 110, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
	Lighting.ClockTime = 13
	Lighting.GlobalShadows = true
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.28
		atmosphere.Haze = 0.8
		atmosphere.Color = Color3.fromRGB(200, 225, 255)
		atmosphere.Decay = Color3.fromRGB(110, 150, 200)
		atmosphere.Parent = Lighting
	end
	local terrain = Workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(40, 150, 200)
	terrain.WaterTransparency = 0.6
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8
	terrain.WaterReflectance = 0.5
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.45
		clouds.Density = 0.6
		clouds.Parent = terrain
	end
end

local function buildSea()
	local terrain = Workspace.Terrain
	terrain:FillBlock(CFrame.new(0, -11, 0), Vector3.new(2048, 22, 2048), Enum.Material.Water)
	terrain:FillBlock(CFrame.new(0, -24, 0), Vector3.new(2048, 4, 2048), Enum.Material.Sand)
end

local function removeTemplateParts()
	-- В шаблоне Baseplate есть плита и точка спавна поверх воды — убираем их.
	for _, name in { "Baseplate", "SpawnLocation" } do
		local existing = Workspace:FindFirstChild(name)
		if existing and existing:IsA("BasePart") then
			existing:Destroy()
		end
	end
end

-- Гавань ----------------------------------------------------------------------

local function buildHarbor()
	local harbor = folder("Harbor", root)
	cylinder("Beach", Vector3.new(0, -2.4, 0), ISLAND_RADIUS * 2 + 14, 6, SAND, Enum.Material.Sand, harbor)
	cylinder("Island", Vector3.new(0, -2, 0), ISLAND_RADIUS * 2, 6, Color3.fromRGB(95, 175, 85), Enum.Material.Grass, harbor)
	cylinder("Plaza", Vector3.new(0, 1.1, 0), PLAZA_RADIUS * 2, 0.4, Color3.fromRGB(200, 195, 185), Enum.Material.Cobblestone, harbor)

	-- Дорожки к зонам по четырём сторонам света
	for i = 0, 3 do
		local angle = i * math.pi / 2
		local length = ISLAND_RADIUS - PLAZA_RADIUS + 6
		part({
			Name = "Path",
			Size = Vector3.new(10, 0.3, length),
			CFrame = CFrame.Angles(0, angle, 0) * CFrame.new(0, 1.05, -(PLAZA_RADIUS + length / 2 - 4)),
			Color = Color3.fromRGB(215, 200, 165),
			Material = Enum.Material.Sand,
			Parent = harbor,
		})
	end

	-- Фонтан в центре — тоже лужа-чекпоинт для погонь между базами.
	cylinder("FountainBasin", Vector3.new(0, 2, 0), 16, 2, STONE, Enum.Material.Marble, harbor)
	local fountainWater = puddle(Vector3.new(0, 3.05, 0), 14, harbor)
	fountainWater.Name = "FountainWater"
	cylinder("FountainPillar", Vector3.new(0, 5, 0), 2, 6, STONE, Enum.Material.Marble, harbor)
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.fromRGB(180, 230, 255))
	spray.Size = NumberSequence.new(0.5, 0.2)
	spray.Transparency = NumberSequence.new(0.2, 1)
	spray.Lifetime = NumberRange.new(0.8, 1.2)
	spray.Speed = NumberRange.new(10, 14)
	spray.SpreadAngle = Vector2.new(20, 20)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.Rate = 40
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = cylinder("FountainTop", Vector3.new(0, 8.1, 0), 2.6, 0.3, STONE, Enum.Material.Marble, harbor)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlazaSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(0, 1.3, 30)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Color = Color3.fromRGB(240, 240, 240)
	spawn.Parent = harbor

	for i = 0, 11 do
		local angle = (i + 0.5) * math.pi / 6
		tree(Vector3.new(math.sin(angle) * 135, 1, math.cos(angle) * 135), harbor, i % 2 == 0)
	end
end

local function stall(name: string, cf: CFrame, title: string, colorA: Color3, colorB: Color3, parent: Instance): BasePart
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local counter = part({
		Name = "Counter",
		Size = Vector3.new(12, 3.5, 3),
		CFrame = cf * CFrame.new(0, 1.75, 0),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})
	for _, x in { -6, 6 } do
		for _, z in { 0, 5 } do
			part({
				Name = "Post",
				Size = Vector3.new(0.8, 9, 0.8),
				CFrame = cf * CFrame.new(x, 5.5, z),
				Color = DARK_WOOD,
				Material = Enum.Material.Wood,
				Parent = model,
			})
		end
	end
	for i = 0, 5 do
		part({
			Name = "Awning",
			Size = Vector3.new(13 / 6, 0.4, 7),
			CFrame = cf * CFrame.new(-6.5 + 13 / 12 + i * 13 / 6, 9.4, 2.5) * CFrame.Angles(math.rad(-12), 0, 0),
			Color = if i % 2 == 0 then colorA else colorB,
			Material = Enum.Material.Fabric,
			Parent = model,
		})
	end
	sign(`{name}Sign`, cf * CFrame.new(0, 11, -0.4), Vector2.new(13, 2.6), title, colorA, model)
	return counter
end

local function buildPlaza()
	local plaza = folder("Plaza", root)

	local marketCf = CFrame.lookAt(Vector3.new(-26, 1.3, -26), Vector3.new(0, 1.3, 0))
	local market = stall("FishMarket", marketCf, "РЫБНЫЙ РЫНОК", Color3.fromRGB(70, 140, 230), Color3.fromRGB(245, 245, 245), plaza)
	MapService.MarketPosition = market.CFrame.Position
	MapService.MarketPrompt = prompt(market, "Продать рыбу", "Рыбный рынок", 0, 12)
	CollectionService:AddTag(market, "Market")

	local shopCf = CFrame.lookAt(Vector3.new(26, 1.3, -26), Vector3.new(0, 1.3, 0))
	local shop = stall("GearShop", shopCf, "СНАРЯЖЕНИЕ", Color3.fromRGB(240, 120, 50), Color3.fromRGB(250, 220, 90), plaza)
	MapService.ShopPosition = shop.CFrame.Position
	MapService.ShopPrompt = prompt(shop, "Открыть магазин", "Снаряжение", 0, 12)
	CollectionService:AddTag(shop, "Shop")

	-- Доска лидеров
	local boardCf = CFrame.lookAt(Vector3.new(-26, 8, 26), Vector3.new(0, 8, 0))
	local board = part({
		Name = "Leaderboard",
		Size = Vector3.new(14, 12, 0.6),
		CFrame = boardCf,
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
		Parent = plaza,
	})
	for _, x in { -6, 6 } do
		part({
			Name = "Leg",
			Size = Vector3.new(0.8, 8, 0.8),
			CFrame = boardCf * CFrame.new(x, -6, 0.2),
			Color = DARK_WOOD,
			Parent = plaza,
		})
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = board
	label(gui, "🏆 ЛУЧШИЕ НА СЕРВЕРЕ", UDim2.fromScale(0.9, 0.12), UDim2.fromScale(0.05, 0.03), Color3.fromRGB(255, 215, 80))
	for i = 1, Config.MaxPlayers do
		local row = label(gui, "", UDim2.fromScale(0.9, 0.09), UDim2.fromScale(0.05, 0.17 + (i - 1) * 0.1))
		row.TextXAlignment = Enum.TextXAlignment.Left
		table.insert(MapService.LeaderboardRows, row)
	end

	-- Табло ивентов
	local eventsCf = CFrame.lookAt(Vector3.new(26, 7, 26), Vector3.new(0, 7, 0))
	local _, eventLabel = sign("EventBoard", eventsCf, Vector2.new(14, 8), "", Color3.fromRGB(40, 60, 110), plaza)
	eventLabel.TextScaled = true
	eventLabel.RichText = true
	MapService.EventBoardLabel = eventLabel
	for _, x in { -6, 6 } do
		part({
			Name = "Leg",
			Size = Vector3.new(0.8, 6, 0.8),
			CFrame = eventsCf * CFrame.new(x, -5, 0.2),
			Color = DARK_WOOD,
			Parent = plaza,
		})
	end
end

-- Базы ----------------------------------------------------------------------

local function buildBase(index: number, parent: Instance): Plot
	local angle = math.rad(22.5 + (index - 1) * 45)
	local position = Vector3.new(math.sin(angle) * BASE_RING_RADIUS, MapService.GroundLevel, -math.cos(angle) * BASE_RING_RADIUS)
	-- LookVector базы смотрит в центр гавани: это «перед», откуда заходят гости.
	local cf = CFrame.lookAt(position, Vector3.new(0, MapService.GroundLevel, 0))
	local color = BASE_COLORS[(index - 1) % #BASE_COLORS + 1]

	local model = Instance.new("Model")
	model.Name = `Base{index}`
	model.Parent = parent

	part({
		Name = "Floor",
		Size = Vector3.new(BASE_HALF * 2, 0.6, BASE_HALF * 2),
		CFrame = cf * CFrame.new(0, 0.3, 0),
		Color = color,
		Material = Enum.Material.WoodPlanks,
		Parent = model,
	})

	-- Низкий заборчик по бокам и сзади
	local fences: { Box } = {
		{ size = Vector3.new(BASE_HALF * 2, 2.5, 0.8), offset = CFrame.new(0, 1.85, BASE_HALF - 0.4) },
		{ size = Vector3.new(0.8, 2.5, BASE_HALF * 2), offset = CFrame.new(-BASE_HALF + 0.4, 1.85, 0) },
		{ size = Vector3.new(0.8, 2.5, BASE_HALF * 2), offset = CFrame.new(BASE_HALF - 0.4, 1.85, 0) },
	}
	for _, wall in fences do
		part({
			Name = "Fence",
			Size = wall.size,
			CFrame = cf * wall.offset,
			Color = Color3.fromRGB(245, 245, 245),
			Material = Enum.Material.WoodPlanks,
			Parent = model,
		})
	end

	-- Аквариум у задней стены. Места: ряды по 6, ряды растут вверх.
	local maxSlots = Formulas.maxPossibleSlots()
	local columns = 6
	local rows = math.ceil(maxSlots / columns)
	local rowHeight = 3.4
	local tankWidth = 32
	local tankDepth = 6
	local tankHeight = rows * rowHeight + 1.6
	local tankZ = 13
	local pedestalTop = 2.6
	local tankCf = cf * CFrame.new(0, 0, tankZ)

	part({
		Name = "Pedestal",
		Size = Vector3.new(tankWidth + 1, 2, tankDepth + 1),
		CFrame = tankCf * CFrame.new(0, pedestalTop - 1, 0),
		Color = STONE,
		Material = Enum.Material.Marble,
		Parent = model,
	})
	part({
		Name = "TankSand",
		Size = Vector3.new(tankWidth, 0.4, tankDepth),
		CFrame = tankCf * CFrame.new(0, pedestalTop + 0.2, 0),
		Color = SAND,
		Material = Enum.Material.Sand,
		Parent = model,
	})
	local water = part({
		Name = "TankWater",
		Size = Vector3.new(tankWidth - 0.4, tankHeight - 0.8, tankDepth - 0.4),
		CFrame = tankCf * CFrame.new(0, pedestalTop + 0.4 + (tankHeight - 0.8) / 2, 0),
		Color = Color3.fromRGB(90, 190, 240),
		Transparency = 0.8,
		CanCollide = false,
		Parent = model,
	})
	water.CanQuery = false
	water.CastShadow = false
	local glassY = pedestalTop + tankHeight / 2
	local glasses: { Box } = {
		{ size = Vector3.new(tankWidth, tankHeight, 0.3), offset = CFrame.new(0, glassY, -tankDepth / 2) },
		{ size = Vector3.new(tankWidth, tankHeight, 0.3), offset = CFrame.new(0, glassY, tankDepth / 2) },
		{ size = Vector3.new(0.3, tankHeight, tankDepth), offset = CFrame.new(-tankWidth / 2, glassY, 0) },
		{ size = Vector3.new(0.3, tankHeight, tankDepth), offset = CFrame.new(tankWidth / 2, glassY, 0) },
	}
	for _, glass in glasses do
		local g = part({
			Name = "Glass",
			Size = glass.size,
			CFrame = tankCf * glass.offset,
			Color = Color3.fromRGB(200, 240, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.75,
			Parent = model,
		})
		g.CastShadow = false
	end
	part({
		Name = "Rim",
		Size = Vector3.new(tankWidth + 0.8, 0.6, tankDepth + 0.8),
		CFrame = tankCf * CFrame.new(0, pedestalTop + tankHeight + 0.3, 0),
		Color = DARK_WOOD,
		Material = Enum.Material.Wood,
		Parent = model,
	})
	for i = 1, 5 do
		local x = -tankWidth / 2 + i * tankWidth / 6
		local weed = part({
			Name = "Seaweed",
			Size = Vector3.new(0.4, 2.5 + (i % 3), 0.4),
			CFrame = tankCf * CFrame.new(x, pedestalTop + 1.6, 2.2),
			Color = Color3.fromRGB(60, 170, 90),
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = model,
		})
		weed.CastShadow = false
	end

	local slotCFrames = {}
	for slot = 1, maxSlots do
		local column = (slot - 1) % columns
		local row = (slot - 1) // columns
		local x = -tankWidth / 2 + (column + 0.5) * tankWidth / columns
		local y = pedestalTop + 0.4 + rowHeight * (row + 0.55)
		-- рыба плывёт вдоль стекла (смотрит в -X базы)
		table.insert(slotCFrames, tankCf * CFrame.new(x, y, 0) * CFrame.Angles(0, math.rad(90), 0))
	end

	local fishFolder = Instance.new("Folder")
	fishFolder.Name = "Fish"
	fishFolder.Parent = model

	-- Табличка с именем владельца у входа
	local signBoard, signTitle = sign("Sign", cf * CFrame.new(-13, 6.5, -BASE_HALF + 0.5), Vector2.new(12, 4), "Свободно", color, model)
	signTitle.Size = UDim2.fromScale(0.94, 0.55)
	local signGui = signBoard:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui
	local signSubtitle = label(signGui, "", UDim2.fromScale(0.94, 0.35), UDim2.fromScale(0.03, 0.6), Color3.fromRGB(255, 240, 150))
	for _, x in { -18, -8 } do
		part({
			Name = "SignPost",
			Size = Vector3.new(0.6, 6, 0.6),
			CFrame = cf * CFrame.new(x, 3.6, -BASE_HALF + 0.8),
			Color = DARK_WOOD,
			Parent = model,
		})
	end

	-- Имя владельца над базой, видно издалека
	local tagAnchor = part({
		Name = "TagAnchor",
		Size = Vector3.one,
		CFrame = cf * CFrame.new(0, 20, 5),
		Transparency = 1,
		CanCollide = false,
		Parent = model,
	})
	tagAnchor.CanQuery = false
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 50)
	billboard.MaxDistance = 400
	billboard.LightInfluence = 0
	billboard.Parent = tagAnchor
	local ownerTag = label(billboard, "", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), color)
	ownerTag.TextStrokeTransparency = 0

	-- Кнопка замка
	local lockPad = cylinder("LockPad", (cf * CFrame.new(12, 0.75, -12)).Position, 5, 0.4, Color3.fromRGB(150, 90, 255), Enum.Material.Neon, model)
	local lockPrompt = prompt(lockPad, "Закрыть базу", "Замок", 0, 8)
	lockPrompt.Name = "LockPrompt"

	-- Барьер замка: включается на 60 секунд. Хозяин проходит сквозь (группы столкновений).
	local barrierGroup = `Barrier{index}`
	local ownerGroup = `Owner{index}`
	for _, group in { barrierGroup, ownerGroup } do
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(barrierGroup, ownerGroup, false)
	local barrier = {}
	local walls: { Box } = {
		{ size = Vector3.new(BASE_HALF * 2, 16, 0.6), offset = CFrame.new(0, 8, -BASE_HALF) },
		{ size = Vector3.new(BASE_HALF * 2, 16, 0.6), offset = CFrame.new(0, 8, BASE_HALF) },
		{ size = Vector3.new(0.6, 16, BASE_HALF * 2), offset = CFrame.new(-BASE_HALF, 8, 0) },
		{ size = Vector3.new(0.6, 16, BASE_HALF * 2), offset = CFrame.new(BASE_HALF, 8, 0) },
	}
	for _, wall in walls do
		local b = part({
			Name = "Barrier",
			Size = wall.size,
			CFrame = cf * wall.offset,
			Color = Color3.fromRGB(160, 110, 255),
			Material = Enum.Material.ForceField,
			Transparency = 1,
			CanCollide = false,
			Parent = model,
		})
		b.CollisionGroup = barrierGroup
		b.CastShadow = false
		table.insert(barrier, b)
	end

	local alarm = Instance.new("Sound")
	alarm.Name = "Alarm"
	alarm.SoundId = Config.Sounds.Alarm
	alarm.Volume = 0.8
	alarm.PlaybackSpeed = 0.8
	alarm.RollOffMaxDistance = 120
	alarm.Parent = model:FindFirstChild("Floor")

	model:SetAttribute("BaseIndex", index)
	model:SetAttribute("LockedUntil", 0)
	model:SetAttribute("OwnerUserId", 0)
	CollectionService:AddTag(model, "Base")

	return {
		Index = index,
		Model = model,
		CFrame = cf,
		HalfSize = BASE_HALF,
		SlotCFrames = slotCFrames,
		FishFolder = fishFolder,
		Barrier = barrier,
		BarrierGroup = barrierGroup,
		OwnerGroup = ownerGroup,
		SignTitle = signTitle,
		SignSubtitle = signSubtitle,
		OwnerTag = ownerTag,
		SpawnCFrame = cf * CFrame.new(0, 4, -6),
		LockPad = lockPad,
		LockPrompt = lockPrompt,
		AlarmSound = alarm,
		Color = color,
	}
end

local function buildBases()
	local bases = folder("Bases", root)
	for index = 1, Config.MaxPlayers do
		table.insert(MapService.Plots, buildBase(index, bases))
	end
end

-- Зоны рыбалки ----------------------------------------------------------------

local function deck(name: string, from: Vector3, to: Vector3, width: number, parent: Instance)
	local length = (to - from).Magnitude
	local cf = CFrame.lookAt((from + to) / 2, to)
	part({
		Name = name,
		Size = Vector3.new(width, 1, length),
		CFrame = cf * CFrame.new(0, DECK_Y - 0.5 - cf.Position.Y, 0),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})
	local posts = math.floor(length / 14)
	for i = 0, posts do
		for _, side in { -1, 1 } do
			local post = (cf * CFrame.new(side * (width / 2 - 0.5), 0, -length / 2 + i * length / math.max(posts, 1))).Position
			cylinder("Post", Vector3.new(post.X, -4, post.Z), 1.2, 12, DARK_WOOD, Enum.Material.Wood, parent)
		end
	end
end

local function buildPier()
	local zone = folder("Pier", root)
	local startZ = -(ISLAND_RADIUS - 12)
	local endZ = -232
	deck("PierDeck", Vector3.new(0, 0, startZ), Vector3.new(0, 0, endZ), 16, zone)
	part({
		Name = "PierEnd",
		Size = Vector3.new(26, 1, 14),
		CFrame = CFrame.new(0, DECK_Y - 0.5, endZ - 4),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		Parent = zone,
	})
	sign("PierSign", CFrame.lookAt(Vector3.new(0, 11, startZ - 4), Vector3.new(0, 11, 0)), Vector2.new(14, 3), "🎣 ПИРС", DARK_WOOD, zone)
	for _, x in { -7.5, 7.5 } do
		part({
			Name = "ArchPost",
			Size = Vector3.new(1, 10, 1),
			CFrame = CFrame.new(x, DECK_Y + 5, startZ - 4),
			Color = DARK_WOOD,
			Parent = zone,
		})
	end
	fishingArea("Pier", CFrame.new(0, DECK_Y + 5, (startZ - 22 + endZ - 11) / 2), Vector3.new(30, 12, math.abs(endZ - 11 - (startZ - 22))), zone)
	shoalSpot(Vector3.new(-14, -1, -195), Vector3.new(8, 1, 60), zone)
	shoalSpot(Vector3.new(14, -1, -195), Vector3.new(8, 1, 60), zone)
	for i = 0, 3 do
		cylinder("Crate", Vector3.new(-6 + (i % 2) * 12, DECK_Y + 1, startZ - 30 - i * 18), 2.5, 2, DARK_WOOD, Enum.Material.Wood, zone)
	end
end

local function buildLake()
	local zone = folder("Lake", root)
	-- центр озера подобран так, чтобы до ближайшего берега было ~15 сек бега (диздок)
	local center = Vector3.new(380, 0, 0)
	local outer, inner = 170, 90
	local band = (outer - inner) / 2
	local landY = MapService.GroundLevel - 3
	local grass = Color3.fromRGB(90, 170, 80)
	-- Земля вокруг пруда из четырёх плит
	part({
		Name = "LandN",
		Size = Vector3.new(outer, 6, band),
		CFrame = CFrame.new(center + Vector3.new(0, landY, -(inner + band) / 2)),
		Color = grass,
		Material = Enum.Material.Grass,
		Parent = zone,
	})
	part({
		Name = "LandS",
		Size = Vector3.new(outer, 6, band),
		CFrame = CFrame.new(center + Vector3.new(0, landY, (inner + band) / 2)),
		Color = grass,
		Material = Enum.Material.Grass,
		Parent = zone,
	})
	part({
		Name = "LandW",
		Size = Vector3.new(band, 6, inner),
		CFrame = CFrame.new(center + Vector3.new(-(inner + band) / 2, landY, 0)),
		Color = grass,
		Material = Enum.Material.Grass,
		Parent = zone,
	})
	part({
		Name = "LandE",
		Size = Vector3.new(band, 6, inner),
		CFrame = CFrame.new(center + Vector3.new((inner + band) / 2, landY, 0)),
		Color = grass,
		Material = Enum.Material.Grass,
		Parent = zone,
	})

	-- Мост от гавани с воротами
	local bridgeStart = Vector3.new(ISLAND_RADIUS - 10, 0, 0)
	local bridgeEnd = Vector3.new(center.X - outer / 2 + 6, 0, 0)
	deck("LakeBridge", bridgeStart, bridgeEnd, 12, zone)
	gate("Lake", CFrame.lookAt(Vector3.new(ISLAND_RADIUS + 6, DECK_Y, 0), Vector3.new(0, DECK_Y, 0)), 12, zone)
	puddle(Vector3.new((bridgeStart.X + bridgeEnd.X) / 2 + 8, DECK_Y + 0.05, 0), 9, zone, Vector3.new(0, 0, 4.5))

	-- Рыбачить можно по берегу пруда
	local shore = 14
	local edge = inner / 2
	fishingArea("Lake", CFrame.new(center + Vector3.new(-edge - shore / 2 + 4, 6, 0)), Vector3.new(shore, 12, inner + shore), zone)
	fishingArea("Lake", CFrame.new(center + Vector3.new(edge + shore / 2 - 4, 6, 0)), Vector3.new(shore, 12, inner + shore), zone)
	fishingArea("Lake", CFrame.new(center + Vector3.new(0, 6, -edge - shore / 2 + 4)), Vector3.new(inner + shore, 12, shore), zone)
	fishingArea("Lake", CFrame.new(center + Vector3.new(0, 6, edge + shore / 2 - 4)), Vector3.new(inner + shore, 12, shore), zone)
	shoalSpot(center + Vector3.new(0, -1, 0), Vector3.new(70, 1, 70), zone)

	-- Маленький причал в пруд и деревья
	local dockCenter = center + Vector3.new(0, DECK_Y - 0.5, -edge + 6)
	part({
		Name = "Dock",
		Size = Vector3.new(6, 1, 16),
		CFrame = CFrame.new(dockCenter),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		Parent = zone,
	})
	fishingArea("Lake", CFrame.new(dockCenter + Vector3.new(0, 5, 0)), Vector3.new(12, 12, 18), zone)
	for i = 0, 9 do
		local angle = i * math.pi / 5
		tree(center + Vector3.new(math.cos(angle) * 72, MapService.GroundLevel, math.sin(angle) * 72), zone, false)
	end
	sign(
		"LakeSign",
		CFrame.lookAt(center + Vector3.new(-outer / 2 + 2, 9, 14), center + Vector3.new(-200, 9, 14)),
		Vector2.new(14, 3),
		"🌿 ОЗЕРО",
		DARK_WOOD,
		zone
	)
end

local function buildReef()
	local zone = folder("Reef", root)
	-- атолл так далеко, что Эпика с Дырявым ведром без луж не донести (~30 сек бега)
	local center = Vector3.new(0, 0, 630)
	local outerRadius, innerRadius = 85, 50
	local ringRadius = (outerRadius + innerRadius) / 2
	local ringWidth = outerRadius - innerRadius
	local segments = 20
	local segmentLength = 2 * math.pi * outerRadius / segments + 2

	-- Длинный настил до атолла: 30 секунд бега, по пути две лужи с бочками
	local walkStart = Vector3.new(0, 0, ISLAND_RADIUS - 10)
	local walkEnd = Vector3.new(0, 0, center.Z - outerRadius + 6)
	deck("Boardwalk", walkStart, walkEnd, 12, zone)
	gate("Reef", CFrame.lookAt(Vector3.new(0, DECK_Y, ISLAND_RADIUS + 6), Vector3.new(0, DECK_Y, 0)), 12, zone)
	local walkLength = walkEnd.Z - walkStart.Z
	puddle(Vector3.new(0, DECK_Y + 0.05, walkStart.Z + walkLength * 0.36), 10, zone, Vector3.new(4.5, 0, 0))
	puddle(Vector3.new(0, DECK_Y + 0.05, walkStart.Z + walkLength * 0.7), 10, zone, Vector3.new(-4.5, 0, 0))

	for i = 0, segments - 1 do
		local angle = i * 2 * math.pi / segments
		local cf = CFrame.new(center) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -ringRadius)
		part({
			Name = "Atoll",
			Size = Vector3.new(segmentLength, 4, ringWidth),
			CFrame = cf * CFrame.new(0, MapService.GroundLevel - 1.6, 0),
			Color = SAND,
			Material = Enum.Material.Sand,
			Parent = zone,
		})
		fishingArea("Reef", cf * CFrame.new(0, 6, 0), Vector3.new(segmentLength, 12, ringWidth + 10), zone)
		-- кораллы
		local coralColors = {
			Color3.fromRGB(255, 110, 120),
			Color3.fromRGB(255, 180, 60),
			Color3.fromRGB(180, 90, 255),
			Color3.fromRGB(60, 210, 200),
		}
		local coralColor = coralColors[i % #coralColors + 1]
		if i % 2 == 0 then
			part({
				Name = "BrainCoral",
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 3.5,
				CFrame = cf * CFrame.new(4, MapService.GroundLevel + 0.9, 8),
				Color = coralColor,
				Material = Enum.Material.Slate,
				Parent = zone,
			})
		else
			for b = 0, 2 do
				part({
					Name = "Coral",
					Size = Vector3.new(0.8, 4 - b, 0.8),
					CFrame = cf * CFrame.new(-4 + b, MapService.GroundLevel + 1.8, -8) * CFrame.Angles(0, 0, math.rad(-25 + b * 25)),
					Color = coralColor,
					Material = Enum.Material.SmoothPlastic,
					CanCollide = false,
					Parent = zone,
				})
			end
		end
		if i % 5 == 2 then
			tree((cf * CFrame.new(0, MapService.GroundLevel + 0.4, 0)).Position, zone, true)
		end
	end
	shoalSpot(center + Vector3.new(0, -1, 0), Vector3.new(80, 1, 80), zone)

	-- Медузы: шесть поперёк настила перед рифом и шесть на кольце атолла
	MapService.HazardMinZ = walkEnd.Z - 90
	local jellyFolder = folder("Jellyfish", zone)
	for i = 0, 5 do
		local z = walkEnd.Z - 76 + i * 11
		jelly(Vector3.new(0, DECK_Y + 2.5, z), Vector3.new(1, 0, 0), 7, 2.6 + (i % 3) * 0.6, i * 1.3, jellyFolder)
	end
	for i = 0, 5 do
		local angle = i * math.pi / 3 + math.pi / 6
		local position = center + Vector3.new(math.sin(angle) * ringRadius, MapService.GroundLevel + 3, -math.cos(angle) * ringRadius)
		local tangent = Vector3.new(math.cos(angle), 0, math.sin(angle))
		jelly(position, tangent, 10, 4 + (i % 2), i * 0.9, jellyFolder)
	end
	sign(
		"ReefSign",
		CFrame.lookAt(Vector3.new(0, 11, walkEnd.Z - 2), Vector3.new(0, 11, 0)),
		Vector2.new(16, 3),
		"🪸 КОРАЛЛОВЫЙ РИФ",
		DARK_WOOD,
		zone
	)
end

local function buildComingSoon()
	local zone = folder("ComingSoon", root)
	deck("BrokenBridge", Vector3.new(-(ISLAND_RADIUS - 10), 0, 0), Vector3.new(-(ISLAND_RADIUS + 34), 0, 0), 12, zone)
	part({
		Name = "Barricade",
		Size = Vector3.new(12, 4, 1),
		CFrame = CFrame.lookAt(Vector3.new(-(ISLAND_RADIUS + 30), DECK_Y + 2, 0), Vector3.new(0, DECK_Y + 2, 0)),
		Color = Color3.fromRGB(240, 200, 40),
		Material = Enum.Material.SmoothPlastic,
		Parent = zone,
	})
	sign(
		"SoonSign",
		CFrame.lookAt(Vector3.new(-(ISLAND_RADIUS + 26), 9, 0), Vector3.new(0, 9, 0)),
		Vector2.new(16, 5),
		"⛈ Штормовое море и 🦈 Акулья бухта — скоро!",
		Color3.fromRGB(60, 70, 110),
		zone
	)
end

-- Публичные запросы ---------------------------------------------------------

local function insideBox(boxCf: CFrame, size: Vector3, position: Vector3, margin: number): boolean
	local localPos = boxCf:PointToObjectSpace(position)
	return math.abs(localPos.X) <= size.X / 2 + margin and math.abs(localPos.Y) <= size.Y / 2 + margin and math.abs(localPos.Z) <= size.Z / 2 + margin
end

-- В какой зоне рыбалки стоит игрок (nil — не у воды или зона выключена).
function MapService.zoneAt(position: Vector3, margin: number?): string?
	for _, area in MapService.FishingAreas do
		if insideBox(area.CFrame, area.Size, position, margin or 0) then
			local zoneId = area:GetAttribute("ZoneId") :: string
			if Config.EnabledZones[zoneId] then
				return zoneId
			end
		end
	end
	return nil
end

function MapService.isInsidePlot(plot: Plot, position: Vector3, margin: number?): boolean
	local localPos = plot.CFrame:PointToObjectSpace(position)
	local half = plot.HalfSize + (margin or 0)
	return math.abs(localPos.X) <= half and math.abs(localPos.Z) <= half and localPos.Y > -6 and localPos.Y < 30
end

function MapService.plotAt(position: Vector3): Plot?
	for _, plot in MapService.Plots do
		if MapService.isInsidePlot(plot, position) then
			return plot
		end
	end
	return nil
end

-- Точка перед входом в базу (куда выталкивает барьер).
function MapService.outsideFront(plot: Plot): CFrame
	return plot.CFrame * CFrame.new(0, 4, -plot.HalfSize - 6)
end

-- Где медуза в момент t (серверное время). Ту же формулу использует клиент.
function MapService.jellyPosition(jellyfish: Jelly, t: number): Vector3
	local offset = math.sin(2 * math.pi * t / jellyfish.Period + jellyfish.Phase) * jellyfish.Amplitude
	return jellyfish.Origin + jellyfish.Axis * offset
end

function MapService.init()
	removeTemplateParts()
	local existing = Workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	root = Instance.new("Folder")
	root.Name = "Map"
	root.Parent = Workspace

	setupLighting()
	buildSea()
	buildHarbor()
	buildPlaza()
	buildBases()
	buildPier()
	buildLake()
	buildReef()
	buildComingSoon()
end

return MapService
