--[[
	Всё, что клиент рисует в мире сам:
	- полоски кислорода над головами (по атрибутам от сервера, плавно каждый кадр);
	- рыбы в аквариумах плавают по точкам через TweenService (на телефонах — простое покачивание);
	- медузы двигаются по той же формуле, что и на сервере;
	- свои рыбы не показывают кнопку «Украсть», открытые ворота зон становятся проходимыми;
	- метка «ДОМОЙ» и лужи с кислородом, пока несёшь рыбу.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UI = script.Parent.Parent:WaitForChild("UI")
local Gui = require(UI:WaitForChild("Gui"))
local Kit = require(UI:WaitForChild("Kit"))

local State = require(script.Parent.State)

local World = {}

local player = Players.LocalPlayer

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function onTag(tag: string, handler: (Instance) -> ())
	CollectionService:GetInstanceAddedSignal(tag):Connect(handler)
	for _, instance in CollectionService:GetTagged(tag) do
		task.spawn(handler, instance)
	end
end

-- Полоски кислорода ---------------------------------------------------------------------

local GREEN = Color3.fromRGB(80, 220, 120)
local YELLOW = Color3.fromRGB(250, 210, 60)
local RED = Color3.fromRGB(240, 70, 70)

local function updateOxygenBars()
	local t = serverNow()
	for _, gui in CollectionService:GetTagged("OxygenBar") do
		local oxygen = gui:GetAttribute("Oxygen") :: number?
		local maxOxygen = gui:GetAttribute("OxygenMax") :: number?
		local rate = (gui:GetAttribute("Rate") :: number?) or 1
		local stamp = (gui:GetAttribute("Stamp") :: number?) or t
		local back = gui:FindFirstChild("Back")
		local fill = back and back:FindFirstChild("Fill") :: Frame?
		local label = back and back:FindFirstChild("Time") :: TextLabel?
		if oxygen and maxOxygen and maxOxygen > 0 and fill and label then
			local current = math.max(0, oxygen - (t - stamp) * rate)
			local fraction = math.clamp(current / maxOxygen, 0, 1)
			fill.Size = UDim2.fromScale(fraction, 1)
			fill.BackgroundColor3 = if fraction > 0.5 then YELLOW:Lerp(GREEN, (fraction - 0.5) * 2) else RED:Lerp(YELLOW, fraction * 2)
			label.Text = `{math.ceil(current)} с`
		end
	end
end

-- Рыбы в аквариуме ----------------------------------------------------------------------

local function swim(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local body = model.PrimaryPart
	if not body then
		return
	end
	local home = body.CFrame
	local phase = math.random() * 2
	task.wait(phase)
	if not body.Parent then
		return
	end

	if Gui.isTouch then
		-- телефон: одно бесконечное покачивание вместо цепочки твинов
		TweenService:Create(
			body,
			TweenInfo.new(1.8 + math.random(), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ CFrame = home * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, math.rad(10), 0) }
		):Play()
		return
	end

	-- ПК: плывёт вперёд, разворачивается, плывёт обратно
	local points = {
		{ cf = home * CFrame.new(0, 0.25, -1.3), time = 1.8 },
		{ cf = home * CFrame.new(0, 0.25, -1.3) * CFrame.Angles(0, math.pi, 0), time = 0.5 },
		{ cf = home * CFrame.new(0, -0.15, 1.3) * CFrame.Angles(0, math.pi, 0), time = 1.8 },
		{ cf = home * CFrame.new(0, -0.15, 1.3), time = 0.5 },
	}
	local index = 0
	while body.Parent do
		index = index % #points + 1
		local point = points[index]
		TweenService:Create(body, TweenInfo.new(point.time, Enum.EasingStyle.Sine), { CFrame = point.cf }):Play()
		task.wait(point.time)
	end
end

-- Скрываем «Украсть» на своих рыбах и чужие кнопки замка.
local function setupStealPrompt(model: Instance)
	if model:GetAttribute("OwnerUserId") == player.UserId then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("ProximityPrompt") then
				descendant.Enabled = false
			end
		end
	end
end

local function setupBase(base: Instance)
	local function refresh()
		local isMine = base:GetAttribute("OwnerUserId") == player.UserId
		local pad = base:FindFirstChild("LockPad")
		local prompt = pad and pad:FindFirstChild("LockPrompt") :: ProximityPrompt?
		if prompt then
			prompt.Enabled = isMine
		end
		local anchor = base:FindFirstChild("TagAnchor")
		local billboard = anchor and anchor:FindFirstChildOfClass("BillboardGui")
		local tag = billboard and billboard:FindFirstChildOfClass("TextLabel")
		if tag and isMine then
			tag.Text = "⭐ ТВОЯ БАЗА"
		end
	end
	base:GetAttributeChangedSignal("OwnerUserId"):Connect(refresh)
	refresh()
end

-- Ворота зон: если зона открыта, ворота для тебя проходимы (только на твоём клиенте).
local function refreshGates()
	local data = State.data
	if not data then
		return
	end
	for _, gate in CollectionService:GetTagged("ZoneGate") do
		if gate:IsA("BasePart") then
			local zoneId = gate:GetAttribute("ZoneId") :: string?
			local unlocked = zoneId ~= nil and data.UnlockedZones[zoneId] == true
			gate.CanCollide = not unlocked
			gate.Transparency = if unlocked then 0.9 else 0
			local prompt = gate:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt.Enabled = not unlocked
			end
		end
	end
end

-- Медузы --------------------------------------------------------------------------------

local function updateJellyfish()
	local t = serverNow()
	for _, jelly in CollectionService:GetTagged("Jellyfish") do
		if jelly:IsA("BasePart") then
			local origin = Vector3.new(
				(jelly:GetAttribute("OriginX") :: number?) or 0,
				(jelly:GetAttribute("OriginY") :: number?) or 0,
				(jelly:GetAttribute("OriginZ") :: number?) or 0
			)
			local axis = (jelly:GetAttribute("Axis") :: Vector3?) or Vector3.xAxis
			local amplitude = (jelly:GetAttribute("Amplitude") :: number?) or 0
			local period = (jelly:GetAttribute("Period") :: number?) or 1
			local phase = (jelly:GetAttribute("Phase") :: number?) or 0
			local offset = math.sin(2 * math.pi * t / period + phase) * amplitude
			local bob = math.sin(t * 2.5 + phase) * 0.4
			jelly.CFrame = CFrame.new(origin + axis * offset + Vector3.new(0, bob, 0))
		end
	end
end

-- Радужные рыбы переливаются цветами.
local function updateRainbow()
	local hue = (os.clock() * 0.25) % 1
	for _, model in CollectionService:GetTagged("RainbowFish") do
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name ~= "Eye" and part.Name ~= "Pupil" then
				part.Color = Color3.fromHSV(hue, 0.7, 1)
			end
		end
	end
end

-- Метки «ДОМОЙ» и луж, пока несёшь рыбу -------------------------------------------------------

local homeMarker: BillboardGui
local homeLabel: TextLabel
local puddleMarkers: { [BasePart]: BillboardGui } = {}

local function marker(text: string, color: Color3, size: Vector2): (BillboardGui, TextLabel)
	local billboard = Kit.make("BillboardGui", {
		Size = UDim2.fromOffset(size.X, size.Y),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		MaxDistance = 600,
		-- BillboardGui рисуется только прямо в PlayerGui, не внутри ScreenGui
		Parent = player:WaitForChild("PlayerGui"),
	})
	local label = Kit.text({ Size = UDim2.fromScale(1, 1), Text = text, TextColor3 = color, Parent = billboard })
	return billboard, label
end

local function updateMarkers()
	local carrying = State.isCarrying()
	local root = State.root()
	local base = State.myBase()
	local anchor = base and base:FindFirstChild("TagAnchor") :: BasePart?
	if anchor then
		homeMarker.Adornee = anchor
	end
	homeMarker.Enabled = carrying and anchor ~= nil
	if carrying and anchor and root then
		local distance = (anchor.Position - root.Position).Magnitude
		homeLabel.Text = `🏠 ДОМОЙ · {math.floor(distance)}`
	end
	local t = serverNow()
	for puddle, billboard in puddleMarkers do
		local ready = ((puddle:GetAttribute("ReadyAt") :: number?) or 0) <= t
		local near = root ~= nil and (puddle.Position - root.Position).Magnitude < 260
		billboard.Enabled = carrying and ready and near
	end
end

function World.start()
	onTag("AquariumFish", function(model)
		setupStealPrompt(model)
		swim(model)
	end)
	onTag("Base", setupBase)
	onTag("ZoneGate", function()
		refreshGates()
	end)
	State.Changed:Connect(refreshGates)

	homeMarker, homeLabel = marker("🏠 ДОМОЙ", Color3.fromRGB(255, 230, 120), Vector2.new(200, 44))
	onTag("Puddle", function(puddle)
		if puddle:IsA("BasePart") then
			local billboard = marker("💧", Color3.fromRGB(120, 200, 255), Vector2.new(48, 48))
			billboard.Adornee = puddle
			billboard.StudsOffset = Vector3.new(0, 4, 0)
			billboard.MaxDistance = 260
			puddleMarkers[puddle] = billboard
		end
	end)

	RunService.RenderStepped:Connect(function()
		updateOxygenBars()
		updateJellyfish()
		updateRainbow()
	end)
	task.spawn(function()
		while true do
			updateMarkers()
			task.wait(0.2)
		end
	end)
end

return World
