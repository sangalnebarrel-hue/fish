--[[
	Эффекты на клиенте: отбрасывание от шлепка и молнии, вспышка молнии,
	надпись «ШЛЁП!», дождь во время Шторма.
]]

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))

local Effects = {}

local player = Players.LocalPlayer

local function knockback(velocity: Vector3)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	humanoid:ChangeState(Enum.HumanoidStateType.FallingDown)
	root.AssemblyLinearVelocity = velocity
	task.delay(0.7, function()
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

local flash: ColorCorrectionEffect

local function lightningFlash()
	flash.Brightness = 0.6
	TweenService:Create(flash, TweenInfo.new(0.35), { Brightness = 0 }):Play()
end

local function popupText(position: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position + Vector3.new(0, 3, 0)
	anchor.Parent = Workspace
	local billboard = Kit.make("BillboardGui", {
		Size = UDim2.fromOffset(180, 60),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Parent = anchor,
	})
	local label = Kit.text({ Size = UDim2.fromScale(1, 1), Text = text, TextColor3 = color, Parent = billboard })
	TweenService:Create(anchor, TweenInfo.new(0.7), { Position = anchor.Position + Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.7), { TextTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.8)
end

-- Дождь: облако частиц над камерой, пока идёт Шторм.
local rainPart: BasePart
local rainEmitter: ParticleEmitter

local function buildRain()
	rainPart = Instance.new("Part")
	rainPart.Name = "LocalRain"
	rainPart.Anchored = true
	rainPart.CanCollide = false
	rainPart.CanQuery = false
	rainPart.CanTouch = false
	rainPart.Transparency = 1
	rainPart.Size = Vector3.new(90, 1, 90)
	rainPart.Parent = Workspace
	rainEmitter = Instance.new("ParticleEmitter")
	rainEmitter.Shape = Enum.ParticleEmitterShape.Box
	rainEmitter.EmissionDirection = Enum.NormalId.Bottom
	rainEmitter.Color = ColorSequence.new(Color3.fromRGB(180, 200, 230))
	rainEmitter.Transparency = NumberSequence.new(0.4)
	rainEmitter.Size = NumberSequence.new(0.12)
	rainEmitter.Lifetime = NumberRange.new(0.8, 1)
	rainEmitter.Speed = NumberRange.new(70, 80)
	rainEmitter.Rate = 400
	rainEmitter.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	rainEmitter.Squash = NumberSequence.new(3)
	rainEmitter.Enabled = false
	rainEmitter.Parent = rainPart
end

local function updateRain()
	local state = ReplicatedStorage:FindFirstChild("GameState")
	local endsAt = if state then (state:GetAttribute("Storm_EndsAt") :: number?) or 0 else 0
	local storming = endsAt > Workspace:GetServerTimeNow()
	rainEmitter.Enabled = storming
	local camera = Workspace.CurrentCamera
	if storming and camera then
		rainPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 45, 0))
	end
end

function Effects.start()
	flash = Instance.new("ColorCorrectionEffect")
	flash.Name = "LightningFlash"
	flash.Parent = Lighting
	buildRain()

	Net.event("Knockback").OnClientEvent:Connect(function(velocity)
		if typeof(velocity) == "Vector3" then
			knockback(velocity)
		end
	end)
	Net.event("Effect").OnClientEvent:Connect(function(name, position)
		if name == "Lightning" then
			lightningFlash()
		elseif name == "Slap" and typeof(position) == "Vector3" then
			popupText(position, "ШЛЁП!", Color3.fromRGB(255, 170, 60))
		end
	end)
	RunService.RenderStepped:Connect(updateRain)
end

return Effects
