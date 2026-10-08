--[[
	Индекс рыб: все рыбы, которых можно поймать. Неоткрытые — чёрные силуэты.
	Каждые 5 открытых рыб дают награду (выдаёт сервер).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FishData = require(Shared.FishData)
local FishModel = require(Shared.FishModel)
local Format = require(Shared.Format)
local ShopData = require(Shared.ShopData)

local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Panel = require(UI:WaitForChild("Panel"))

local State = require(script.Parent.State)

local IndexPanel = {}

type Card = {
	frame: Frame,
	viewport: ViewportFrame,
	model: Model,
	name: TextLabel,
	info: TextLabel,
	discovered: boolean?,
}

local panel: Panel.Panel
local progress: TextLabel
local grid: ScrollingFrame
local cards: { [string]: Card } = {}

local function sortedFish(): { string }
	local list = FishData.obtainableFish(Config.EnabledZones)
	table.sort(list, function(a, b)
		local fa, fb = FishData.Fish[a], FishData.Fish[b]
		local ra, rb = FishData.Rarities[fa.Rarity].Order, FishData.Rarities[fb.Rarity].Order
		if ra ~= rb then
			return ra < rb
		end
		return fa.Income < fb.Income
	end)
	return list
end

local function zoneNames(fishId: string): string
	local names = {}
	for _, zoneId in FishData.Fish[fishId].Zones do
		local zone = FishData.Zones[zoneId]
		if zone and Config.EnabledZones[zoneId] then
			table.insert(names, zone.Name)
		end
	end
	return table.concat(names, ", ")
end

local function setSilhouette(model: Model, silhouette: boolean)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if part:GetAttribute("OriginalColor") == nil then
				part:SetAttribute("OriginalColor", part.Color)
			end
			part.Color = if silhouette then Color3.new(0.05, 0.05, 0.08) else part:GetAttribute("OriginalColor") :: Color3
		end
	end
end

local function buildCard(order: number, fishId: string): Card
	local fish = FishData.Fish[fishId]
	local rarity = FishData.Rarities[fish.Rarity]
	local frame = Kit.make("Frame", {
		BackgroundColor3 = Kit.Colors.PanelLight,
		LayoutOrder = order,
		Parent = grid,
	})
	Kit.corner(frame, 14)
	Kit.make("UIStroke", { Color = Kit.rgb(rarity.Color), Thickness = 3, Parent = frame })

	local viewport = Kit.make("ViewportFrame", {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 0, 104),
		BackgroundColor3 = Color3.fromRGB(70, 140, 200),
		Ambient = Color3.fromRGB(200, 200, 200),
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = frame,
	})
	Kit.corner(viewport, 10)
	local model = FishModel.build({ Id = fishId, Size = "Normal" }, { anchored = true })
	model:PivotTo(CFrame.new())
	model.Parent = viewport
	local camera = Instance.new("Camera")
	local extents = model:GetExtentsSize()
	local distance = math.max(extents.X, extents.Y, extents.Z) * 1.25 + 1
	camera.CFrame = CFrame.lookAt(Vector3.new(distance, distance * 0.25, -distance * 0.35), Vector3.zero)
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local name = Kit.text({
		Position = UDim2.fromOffset(6, 116),
		Size = UDim2.new(1, -12, 0, 28),
		Text = "???",
		Parent = frame,
	})
	local info = Kit.text({
		Position = UDim2.fromOffset(6, 146),
		Size = UDim2.new(1, -12, 0, 36),
		Text = "",
		TextColor3 = Kit.Colors.Muted,
		TextWrapped = true,
		Parent = frame,
	})
	return { frame = frame, viewport = viewport, model = model, name = name, info = info, discovered = nil }
end

local function nextReward(count: number): string
	local best: number? = nil
	for milestone in ShopData.IndexRewards do
		if milestone > count and (best == nil or milestone < best) then
			best = milestone
		end
	end
	if not best then
		return "Все награды получены!"
	end
	local reward = ShopData.IndexRewards[best]
	local bait = ShopData.Baits[reward.Bait]
	return `Ещё {best - count} до награды: {bait.Name} ×{reward.Amount}`
end

local function render()
	local data = State.data
	if not data or not panel.isOpen() then
		return
	end
	local index: { [string]: boolean } = data.Index
	local list = sortedFish()
	local discovered = 0
	for order, fishId in list do
		local card = cards[fishId]
		if not card then
			card = buildCard(order, fishId)
			cards[fishId] = card
		end
		local fish = FishData.Fish[fishId]
		local rarity = FishData.Rarities[fish.Rarity]
		local isOpen = index[fishId] == true
		if isOpen then
			discovered += 1
		end
		if card.discovered ~= isOpen then
			card.discovered = isOpen
			setSilhouette(card.model, not isOpen)
		end
		card.name.Text = if isOpen then fish.NameRu else "???"
		card.name.TextColor3 = if isOpen then Kit.rgb(rarity.Color) else Kit.Colors.Muted
		card.info.Text = if isOpen then `{rarity.Name} · {Format.perSecond(fish.Income)}` else `{rarity.Name} · {zoneNames(fishId)}`
	end
	progress.Text = `Открыто {discovered}/{#list} · {nextReward(discovered)}`
end

function IndexPanel.open()
	panel.open()
end

function IndexPanel.start()
	panel = Panel.create("Index", "📖 Индекс рыб", Kit.Colors.Purple, Vector2.new(860, 540))
	progress = Kit.text({
		Size = UDim2.new(1, 0, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel.content,
	})
	local holder = Kit.make("Frame", {
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 1, -42),
		BackgroundTransparency = 1,
		Parent = panel.content,
	})
	grid = Panel.scroll(holder, Vector2.new(184, 190))
	panel.onOpen = render
	State.Changed:Connect(render)
end

return IndexPanel
