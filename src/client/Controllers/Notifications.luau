--[[
	Всплывающие уведомления, большой баннер улова, тревога «вор у аквариума» и окно офлайн-дохода.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Net = require(Shared.Net)

local UI = script.Parent.Parent:WaitForChild("UI")
local Gui = require(UI:WaitForChild("Gui"))
local Kit = require(UI:WaitForChild("Kit"))

local Notifications = {}

local KIND_COLORS: { [string]: Color3 } = {
	info = Color3.fromRGB(40, 60, 110),
	good = Color3.fromRGB(45, 150, 75),
	bad = Color3.fromRGB(190, 55, 55),
	event = Color3.fromRGB(200, 140, 20),
}

local MAX_TOASTS = 4
local toastOrder = 0
local container: Frame
local sounds: { [string]: Sound } = {}

local function getSound(name: string): Sound?
	local existing = sounds[name]
	if existing then
		return existing
	end
	local id = (Config.Sounds :: any)[name] :: string?
	if not id then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Parent = SoundService
	sounds[name] = sound
	return sound
end

function Notifications.playSound(name: string, volume: number?)
	local sound = getSound(name)
	if sound then
		sound.Volume = volume or 0.6
		SoundService:PlayLocalSound(sound)
	end
end

function Notifications.show(text: string, kind: string?)
	local color = KIND_COLORS[kind or "info"] or KIND_COLORS.info
	toastOrder -= 1
	local toast = Kit.make("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(540, 42),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.05,
		LayoutOrder = toastOrder,
		Parent = container,
	})
	Kit.corner(toast, 12)
	Kit.stroke(toast, Kit.Colors.Stroke, 2)
	local label = Kit.text({ Size = UDim2.new(1, -20, 1, -8), Position = UDim2.fromOffset(10, 4), Text = text, Parent = toast })
	label.TextXAlignment = Enum.TextXAlignment.Center

	local toasts = {}
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = MAX_TOASTS + 1, #toasts do
		toasts[index]:Destroy()
	end

	if kind == "bad" then
		Notifications.playSound("Fail", 0.3)
	elseif kind == "good" then
		Notifications.playSound("Coins", 0.4)
	end

	task.delay(3.5, function()
		if toast.Parent then
			local info = TweenInfo.new(0.35)
			TweenService:Create(toast, info, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(label, info, { TextTransparency = 1 }):Play()
			task.wait(0.35)
			toast:Destroy()
		end
	end)
end

-- Большой баннер по центру: «Поймал Мифическую!»
function Notifications.big(title: string, subtitle: string, color: Color3)
	local frame = Kit.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(520, 120),
		BackgroundTransparency = 1,
		Parent = Gui.overlay,
	})
	local scale = Kit.make("UIScale", { Scale = 0.3, Parent = frame })
	Kit.text({ Size = UDim2.new(1, 0, 0.62, 0), Text = title, TextColor3 = color, Parent = frame })
	Kit.text({ Size = UDim2.new(1, 0, 0.36, 0), Position = UDim2.fromScale(0, 0.64), Text = subtitle, Parent = frame })
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(2.2, function()
		TweenService:Create(scale, TweenInfo.new(0.25), { Scale = 0 }):Play()
		task.wait(0.25)
		frame:Destroy()
	end)
end

function Notifications.alarm(intruderName: string)
	local border = Kit.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = Gui.overlay,
	})
	local stroke = Kit.make("UIStroke", { Color = Kit.Colors.Red, Thickness = 18, Transparency = 0.2, Parent = border })
	local label = Kit.text({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 160),
		Size = UDim2.fromOffset(620, 54),
		Text = `⚠ ВОР У АКВАРИУМА: {intruderName}!`,
		TextColor3 = Color3.fromRGB(255, 90, 90),
		Parent = border,
	})
	Notifications.playSound("Alarm", 0.8)
	task.spawn(function()
		for _ = 1, 3 do
			TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 0.9 }):Play()
			task.wait(0.3)
			TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 0.2 }):Play()
			task.wait(0.3)
		end
		label:Destroy()
		border:Destroy()
	end)
end

function Notifications.offline(amount: number, seconds: number)
	local dim = Kit.make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Text = "",
		AutoButtonColor = false,
		Parent = Gui.overlay,
	})
	local panel = Kit.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 250),
		BackgroundColor3 = Kit.Colors.Panel,
		Parent = dim,
	})
	Kit.corner(panel, 20)
	Kit.stroke(panel, Kit.Colors.Stroke, 4)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	local away = if hours > 0 then `{hours} ч {minutes} мин` else `{minutes} мин`
	Kit.text({
		Position = UDim2.fromOffset(20, 18),
		Size = UDim2.new(1, -40, 0, 44),
		Text = "С возвращением! 🐟",
		Parent = panel,
	})
	Kit.text({
		Position = UDim2.fromOffset(20, 70),
		Size = UDim2.new(1, -40, 0, 34),
		Text = `Тебя не было {away}. Рыбки заработали:`,
		TextColor3 = Kit.Colors.Muted,
		Parent = panel,
	})
	Kit.text({
		Position = UDim2.fromOffset(20, 108),
		Size = UDim2.new(1, -40, 0, 54),
		Text = Format.money(amount),
		TextColor3 = Kit.Colors.Gold,
		Parent = panel,
	})
	Kit.button("Забрать", Kit.Colors.Green, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(200, 54),
		Parent = panel,
	}, function()
		dim:Destroy()
	end)
	Notifications.playSound("Coins", 0.6)
end

function Notifications.start()
	container = Kit.make("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 96),
		Size = UDim2.fromOffset(560, 220),
		BackgroundTransparency = 1,
		Parent = Gui.overlay,
	})
	Kit.list(container, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)

	Net.event("Notify").OnClientEvent:Connect(function(text, kind)
		if type(text) == "string" then
			Notifications.show(text, if type(kind) == "string" then kind else nil)
		end
	end)
	Net.event("Alarm").OnClientEvent:Connect(function(name)
		Notifications.alarm(tostring(name))
	end)
	Net.event("OfflineEarnings").OnClientEvent:Connect(function(amount, seconds)
		if type(amount) == "number" and type(seconds) == "number" then
			Notifications.offline(amount, seconds)
		end
	end)
end

return Notifications
