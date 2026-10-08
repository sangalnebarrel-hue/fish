--[[
	Процедурные модели рыб из простых деталей: без загрузки мешей, работает в пустом плейсе.
	Рыба смотрит в -Z (LookVector), хвост в +Z. Тело — PrimaryPart, остальные детали приварены к нему,
	поэтому достаточно двигать тело (TweenService / PivotTo), и вся рыба едет следом.
]]

local FishData = require(script.Parent.FishData)

local FishModel = {}

local BLACK = Color3.fromRGB(25, 25, 30)
local WHITE = Color3.fromRGB(250, 250, 250)
local GOLD = Color3.fromRGB(255, 205, 40)

function FishModel.rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

export type BuildOptions = {
	scale: number?, -- дополнительный масштаб поверх размера рыбы
	anchored: boolean?, -- true для аквариума и земли, false для ведра
}

type Builder = {
	model: Model,
	body: BasePart,
	scale: number,
	anchored: boolean,
}

local function newPart(builder: Builder, name: string, className: string, size: Vector3, offset: CFrame, color: Color3): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Size = size * builder.scale
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Anchored = false
	local scaledOffset = CFrame.new(offset.Position * builder.scale) * offset.Rotation
	part.CFrame = builder.body.CFrame * scaledOffset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = builder.body
	weld.Part1 = part
	weld.Parent = part
	part.Parent = builder.model
	return part
end

local function ellipsoid(part: BasePart)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
end

local function ball(builder: Builder, name: string, size: Vector3, offset: CFrame, color: Color3): BasePart
	local part = newPart(builder, name, "Part", size, offset, color)
	ellipsoid(part)
	return part
end

local function block(builder: Builder, name: string, size: Vector3, offset: CFrame, color: Color3): BasePart
	return newPart(builder, name, "Part", size, offset, color)
end

local function cylinderUp(builder: Builder, name: string, height: number, diameter: number, offset: CFrame, color: Color3): BasePart
	local part = newPart(builder, name, "Part", Vector3.new(height, diameter, diameter), offset * CFrame.Angles(0, 0, math.rad(90)), color) :: Part
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Хвост из двух клиньев: острие к телу, широкая часть назад.
local function tail(builder: Builder, length: number, height: number, z: number, color: Color3)
	local size = Vector3.new(0.14, height / 2, length)
	newPart(builder, "TailTop", "WedgePart", size, CFrame.new(0, height / 4, z), color)
	newPart(builder, "TailBottom", "WedgePart", size, CFrame.new(0, -height / 4, z) * CFrame.Angles(0, 0, math.pi), color)
end

local function dorsal(builder: Builder, length: number, height: number, y: number, color: Color3)
	newPart(
		builder,
		"Dorsal",
		"WedgePart",
		Vector3.new(0.12, height, length),
		CFrame.new(0, y + height / 2, 0.1) * CFrame.Angles(0, math.pi, 0),
		color
	)
end

local function eyes(builder: Builder, x: number, y: number, z: number, size: number)
	for _, side in { -1, 1 } do
		ball(builder, "Eye", Vector3.one * size, CFrame.new(side * x, y, z), WHITE)
		ball(builder, "Pupil", Vector3.one * size * 0.5, CFrame.new(side * (x + size * 0.32), y, z - size * 0.12), BLACK)
	end
end

-- Аксессуары ------------------------------------------------------------------

type HeadInfo = { top: number, front: number, width: number, eyeY: number }

local ACCESSORIES: { [string]: (Builder, HeadInfo, Color3) -> () } = {
	Shades = function(builder, head)
		block(builder, "Shades", Vector3.new(head.width + 0.25, 0.26, 0.55), CFrame.new(0, head.eyeY, head.front + 0.35), BLACK)
	end,
	Cap = function(builder, head, accent)
		block(builder, "Cap", Vector3.new(head.width * 0.95, 0.3, head.width * 0.95), CFrame.new(0, head.top + 0.05, head.front + 0.55), accent)
		block(builder, "Visor", Vector3.new(head.width * 0.8, 0.08, 0.55), CFrame.new(0, head.top - 0.05, head.front + 0.05), accent)
	end,
	ChefHat = function(builder, head)
		cylinderUp(builder, "Hat", 0.8, head.width * 0.9, CFrame.new(0, head.top + 0.4, head.front + 0.6), WHITE)
		ball(builder, "HatTop", Vector3.new(head.width * 1.15, 0.6, head.width * 1.15), CFrame.new(0, head.top + 0.9, head.front + 0.6), WHITE)
	end,
	Headband = function(builder, head, accent)
		block(builder, "Headband", Vector3.new(head.width + 0.12, 0.2, 0.7), CFrame.new(0, head.eyeY + 0.22, head.front + 0.55), accent)
		block(
			builder,
			"Knot",
			Vector3.new(0.1, 0.15, 0.6),
			CFrame.new(0, head.eyeY + 0.22, head.front + 1.1) * CFrame.Angles(math.rad(25), 0, 0),
			accent
		)
	end,
	Headphones = function(builder, head)
		block(builder, "Band", Vector3.new(head.width + 0.3, 0.12, 0.22), CFrame.new(0, head.top + 0.08, head.front + 0.75), BLACK)
		for _, side in { -1, 1 } do
			local cup = newPart(
				builder,
				"Cup",
				"Part",
				Vector3.new(0.18, 0.5, 0.5),
				CFrame.new(side * (head.width / 2 + 0.12), head.eyeY, head.front + 0.75),
				Color3.fromRGB(255, 60, 160)
			) :: Part
			cup.Shape = Enum.PartType.Cylinder
		end
	end,
	Crown = function(builder, head)
		cylinderUp(builder, "Crown", 0.35, head.width * 0.75, CFrame.new(0, head.top + 0.15, head.front + 0.7), GOLD)
		for i = 0, 3 do
			local angle = i * math.pi / 2 + math.pi / 4
			local radius = head.width * 0.3
			block(
				builder,
				"Spike",
				Vector3.new(0.12, 0.3, 0.12),
				CFrame.new(math.cos(angle) * radius, head.top + 0.45, head.front + 0.7 + math.sin(angle) * radius),
				GOLD
			)
		end
	end,
	Brows = function(builder, head)
		for _, side in { -1, 1 } do
			block(
				builder,
				"Brow",
				Vector3.new(0.1, 0.09, 0.42),
				CFrame.new(side * (head.width / 2 - 0.02), head.eyeY + 0.25, head.front + 0.5) * CFrame.Angles(math.rad(-22), 0, 0),
				BLACK
			)
		end
	end,
	Horns = function(builder, head)
		for _, side in { -1, 1 } do
			newPart(
				builder,
				"Horn",
				"WedgePart",
				Vector3.new(0.14, 0.55, 0.4),
				CFrame.new(side * head.width * 0.25, head.top + 0.2, head.front + 0.8),
				GOLD
			)
		end
	end,
	Fedora = function(builder, head)
		cylinderUp(builder, "Brim", 0.08, head.width * 1.5, CFrame.new(0, head.top, head.front + 0.7), BLACK)
		cylinderUp(builder, "Crown", 0.45, head.width * 0.9, CFrame.new(0, head.top + 0.25, head.front + 0.7), BLACK)
		cylinderUp(builder, "Ribbon", 0.1, head.width * 0.92, CFrame.new(0, head.top + 0.1, head.front + 0.7), Color3.fromRGB(200, 30, 40))
	end,
}

-- Формы тела ------------------------------------------------------------------

local SHAPES: { [string]: (Builder, Color3, Color3) -> HeadInfo } = {}

SHAPES.Fish = function(builder, _main, accent)
	local body = builder.body
	body.Size = Vector3.new(0.9, 1.4, 2.4) * builder.scale
	tail(builder, 1, 1.3, 1.55, accent)
	dorsal(builder, 1, 0.5, 0.55, accent)
	eyes(builder, 0.33, 0.2, -0.75, 0.32)
	return { top = 0.6, front = -1.15, width = 0.9, eyeY = 0.2 }
end

SHAPES.Long = function(builder, _main, accent)
	builder.body.Size = Vector3.new(0.7, 0.9, 3.2) * builder.scale
	tail(builder, 0.8, 0.9, 1.9, accent)
	dorsal(builder, 1.6, 0.3, 0.35, accent)
	eyes(builder, 0.25, 0.12, -1.1, 0.26)
	return { top = 0.38, front = -1.5, width = 0.7, eyeY = 0.12 }
end

SHAPES.Flat = function(builder, _main, accent)
	builder.body.Size = Vector3.new(2.6, 0.45, 2.2) * builder.scale
	block(builder, "Tail", Vector3.new(0.12, 0.12, 2), CFrame.new(0, 0, 2), accent)
	-- «пепперони» на спине
	for i, pos in
		{
			Vector3.new(-0.5, 0.2, -0.2),
			Vector3.new(0.45, 0.2, 0.15),
			Vector3.new(0, 0.2, 0.55),
			Vector3.new(0.1, 0.2, -0.6),
		}
	do
		cylinderUp(builder, `Spot{i}`, 0.06, 0.4, CFrame.new(pos), accent)
	end
	eyes(builder, 0.35, 0.25, -0.7, 0.24)
	return { top = 0.25, front = -1, width = 1, eyeY = 0.25 }
end

SHAPES.Round = function(builder, _main, accent)
	builder.body.Size = Vector3.new(1.7, 1.7, 1.8) * builder.scale
	tail(builder, 0.7, 1, 1.15, accent)
	block(builder, "Stripe", Vector3.new(1.75, 0.25, 1.85), CFrame.new(0, 0, 0), accent)
	eyes(builder, 0.62, 0.3, -0.55, 0.36)
	return { top = 0.8, front = -0.85, width = 1.5, eyeY = 0.3 }
end

SHAPES.Octo = function(builder, main, _accent)
	builder.body.Size = Vector3.new(1.7, 1.6, 1.7) * builder.scale
	for i = 0, 5 do
		local angle = i * math.pi / 3
		local tentacle = newPart(
			builder,
			"Tentacle",
			"Part",
			Vector3.new(1.3, 0.32, 0.32),
			CFrame.new(math.cos(angle) * 0.55, -0.95, math.sin(angle) * 0.55) * CFrame.Angles(0, 0, math.rad(90)),
			main
		) :: Part
		tentacle.Shape = Enum.PartType.Cylinder
	end
	eyes(builder, 0.5, 0.2, -0.6, 0.38)
	return { top = 0.75, front = -0.8, width = 1.5, eyeY = 0.2 }
end

SHAPES.Shark = function(builder, main, _accent)
	builder.body.Size = Vector3.new(1, 1.2, 3.4) * builder.scale
	tail(builder, 1.1, 1.6, 2.1, main)
	dorsal(builder, 1, 1, 0.5, main)
	block(builder, "Belly", Vector3.new(0.9, 0.3, 2.6), CFrame.new(0, -0.45, -0.1), WHITE)
	eyes(builder, 0.38, 0.2, -1.2, 0.26)
	return { top = 0.55, front = -1.6, width = 1, eyeY = 0.2 }
end

SHAPES.Jelly = function(builder, _main, accent)
	builder.body.Size = Vector3.new(1.8, 1.3, 1.8) * builder.scale
	builder.body.Transparency = 0.25
	for i = 0, 5 do
		local angle = i * math.pi / 3
		local strand = newPart(
			builder,
			"Strand",
			"Part",
			Vector3.new(1.6, 0.14, 0.14),
			CFrame.new(math.cos(angle) * 0.5, -1.1, math.sin(angle) * 0.5) * CFrame.Angles(0, 0, math.rad(90)),
			accent
		) :: Part
		strand.Shape = Enum.PartType.Cylinder
		strand.Material = Enum.Material.Neon
	end
	eyes(builder, 0.55, 0.05, -0.55, 0.3)
	return { top = 0.6, front = -0.85, width = 1.5, eyeY = 0.05 }
end

-- Мутации -------------------------------------------------------------------

local function applyMutation(model: Model, body: BasePart, mutationId: string?)
	if not mutationId then
		return
	end
	local mutation = FishData.Mutations[mutationId]
	if not mutation then
		return
	end
	local color = FishModel.rgb(mutation.Color)
	local function eachSkin(fn: (BasePart) -> ())
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "Eye" and part.Name ~= "Pupil" then
				fn(part)
			end
		end
	end

	if mutationId == "Golden" then
		eachSkin(function(part)
			part.Color = color
			part.Material = Enum.Material.Metal
			part.Reflectance = 0.25
		end)
	elseif mutationId == "Diamond" then
		eachSkin(function(part)
			part.Color = color
			part.Material = Enum.Material.Glass
			part.Reflectance = 0.3
		end)
	elseif mutationId == "Electric" then
		eachSkin(function(part)
			if part ~= body then
				part.Color = color
				part.Material = Enum.Material.Neon
			end
		end)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 8
		light.Brightness = 2
		light.Parent = body
		local sparks = Instance.new("ParticleEmitter")
		sparks.Color = ColorSequence.new(color)
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new(0.15)
		sparks.Lifetime = NumberRange.new(0.2, 0.4)
		sparks.Rate = 6
		sparks.Speed = NumberRange.new(2, 4)
		sparks.SpreadAngle = Vector2.new(180, 180)
		sparks.Parent = body
	elseif mutationId == "Ghost" then
		eachSkin(function(part)
			part.Color = color
			part.Material = Enum.Material.ForceField
		end)
	elseif mutationId == "Ice" then
		eachSkin(function(part)
			part.Color = color
			part.Material = Enum.Material.Ice
		end)
	elseif mutationId == "Rainbow" then
		model:AddTag("RainbowFish")
	end
end

-- Сборка --------------------------------------------------------------------

function FishModel.build(record: { Id: string, Size: string?, Mutation: string? }, options: BuildOptions?): Model
	local opts: BuildOptions = options or {}
	local fish = FishData.Fish[record.Id]
	assert(fish, `Unknown fish {record.Id}`)
	local size = FishData.Sizes[record.Size or "Normal"] or FishData.Sizes.Normal
	local scale = size.Scale * (opts.scale or 1)
	local main = FishModel.rgb(fish.Color)
	local accent = FishModel.rgb(fish.Color2)

	local model = Instance.new("Model")
	model.Name = fish.Id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Color = main
	body.Material = Enum.Material.SmoothPlastic
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CastShadow = false
	body.Massless = true
	body.Anchored = opts.anchored ~= false
	body.CFrame = CFrame.new()
	ellipsoid(body)
	body.Parent = model
	model.PrimaryPart = body

	local builder: Builder = { model = model, body = body, scale = scale, anchored = body.Anchored }
	local shape = SHAPES[fish.Shape] or SHAPES.Fish
	local head = shape(builder, main, accent)

	if fish.Accessory and ACCESSORIES[fish.Accessory] then
		ACCESSORIES[fish.Accessory](builder, head, accent)
	end
	applyMutation(model, body, record.Mutation)

	model:SetAttribute("FishId", record.Id)
	model:SetAttribute("Size", record.Size or "Normal")
	model:SetAttribute("Scale", scale)
	return model
end

return FishModel
