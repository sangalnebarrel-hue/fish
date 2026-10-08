--[[
	Рыбалка на клиенте: кнопка «Закинуть» у воды и мини-игра подсечки.
	Маркер бегает по полоске, нужно нажать, когда он в зелёной зоне.
	Чем реже рыба, тем быстрее маркер и уже зона; хорошая удочка расширяет зону.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FishData = require(Shared.FishData)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)

local UI = script.Parent.Parent:WaitForChild("UI")
local Gui = require(UI:WaitForChild("Gui"))
local Kit = require(UI:WaitForChild("Kit"))

local State = require(script.Parent.State)
local Notifications = require(script.Parent.Notifications)
local Hud = require(script.Parent.Hud)

local Fishing = {}

type HookParams = { zoneCenter: number, zoneWidth: number, speed: number, window: number, autoHook: boolean }

local phase = "idle" -- idle | casting | waiting | bite | hooked
local castId: number? = nil
local params: HookParams? = nil
local biteStarted = 0

local overlay: TextButton
local titleLabel: TextLabel
local zoneFrame: Frame
local marker: Frame
local timerFill: Frame

local function zoneAtPlayer(): string?
	local root = State.root()
	if not root then
		return nil
	end
	for _, area in CollectionService:GetTagged("FishingArea") do
		if area:IsA("BasePart") then
			local localPos = area.CFrame:PointToObjectSpace(root.Position)
			local half = area.Size / 2
			if math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z then
				local zoneId = area:GetAttribute("ZoneId") :: string?
				if zoneId and Config.EnabledZones[zoneId] then
					return zoneId
				end
			end
		end
	end
	return nil
end

-- Мини-игра ---------------------------------------------------------------------------

local function buildOverlay()
	overlay = Kit.make("TextButton", {
		Name = "HookGame",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -64),
		Size = UDim2.fromOffset(520, 170),
		BackgroundColor3 = Kit.Colors.Panel,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		Parent = Gui.overlay,
	})
	Kit.corner(overlay, 20)
	Kit.stroke(overlay, Kit.Colors.Stroke, 4)
	titleLabel = Kit.text({
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -32, 0, 40),
		Text = "",
		Parent = overlay,
	})
	local bar = Kit.make("Frame", {
		Position = UDim2.fromOffset(20, 58),
		Size = UDim2.new(1, -40, 0, 44),
		BackgroundColor3 = Color3.fromRGB(20, 25, 40),
		Parent = overlay,
	})
	Kit.corner(bar, 10)
	zoneFrame = Kit.make("Frame", {
		BackgroundColor3 = Kit.Colors.Green,
		Size = UDim2.fromScale(0.2, 1),
		Parent = bar,
	})
	Kit.corner(zoneFrame, 8)
	marker = Kit.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 10, 1, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
		Parent = bar,
	})
	Kit.corner(marker, 4)
	Kit.stroke(marker, Kit.Colors.Stroke, 2)
	local timer = Kit.make("Frame", {
		Position = UDim2.fromOffset(20, 112),
		Size = UDim2.new(1, -40, 0, 8),
		BackgroundColor3 = Color3.fromRGB(20, 25, 40),
		Parent = overlay,
	})
	Kit.corner(timer, 4)
	timerFill = Kit.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.Colors.Orange,
		Parent = timer,
	})
	Kit.corner(timerFill, 4)
	Kit.text({
		Position = UDim2.fromOffset(16, 126),
		Size = UDim2.new(1, -32, 0, 34),
		Text = if Gui.isTouch
			then "Жми, когда маркер в зелёной зоне!"
			else "Жми [C] или кликни, когда маркер в зелёной зоне!",
		TextColor3 = Kit.Colors.Muted,
		Parent = overlay,
	})
end

local function showMinigame(rarityId: string, hookParams: HookParams)
	local rarity = FishData.Rarities[rarityId]
	local excitement = string.rep("!", math.clamp(rarity.Order, 1, 4))
	titleLabel.Text = `{excitement} Клюёт: <font color="{Format.hex(rarity.Color)}">{rarity.Name}</font> {excitement}`
	zoneFrame.Size = UDim2.fromScale(hookParams.zoneWidth, 1)
	zoneFrame.Position = UDim2.fromScale(hookParams.zoneCenter - hookParams.zoneWidth / 2, 0)
	zoneFrame.BackgroundColor3 = Kit.Colors.Green
	overlay.Visible = true
end

local function hideMinigame()
	overlay.Visible = false
end

-- Заброс и подсечка ---------------------------------------------------------------------

local function cast()
	phase = "casting"
	local ok, success, result = pcall(function()
		return Net.func("Cast"):InvokeServer()
	end)
	if not ok then
		phase = "idle"
		Notifications.show("Сервер не ответил, попробуй ещё раз", "bad")
		return
	end
	if success and type(result) == "table" then
		castId = result.castId
		phase = "waiting"
		Notifications.playSound("Splash", 0.5)
	else
		phase = "idle"
		if type(result) == "string" then
			Notifications.show(result, "info")
		end
	end
end

local function hook()
	if phase ~= "bite" or not params or not castId then
		return
	end
	local position = Formulas.markerPosition(os.clock() - biteStarted, params.speed)
	local success = math.abs(position - params.zoneCenter) <= params.zoneWidth / 2
	zoneFrame.BackgroundColor3 = if success then Kit.Colors.Gold else Kit.Colors.Red
	phase = "hooked"
	Net.event("Hook"):FireServer(castId, success)
end

local function press()
	if phase == "idle" then
		local data = State.data
		local zoneId = zoneAtPlayer()
		if data and zoneId and not data.UnlockedZones[zoneId] then
			Notifications.show(`Сначала открой «{FishData.Zones[zoneId].Name}» у ворот`, "info")
			return
		end
		cast()
	elseif phase == "waiting" then
		Net.event("CancelCast"):FireServer()
	elseif phase == "bite" then
		hook()
	end
end

local function onBite(id: number, rarityId: string, hookParams: HookParams)
	if id ~= castId then
		return
	end
	params = hookParams
	biteStarted = os.clock()
	phase = "bite"
	Notifications.playSound("Bite", 0.8)
	showMinigame(rarityId, hookParams)
	if hookParams.autoHook then
		titleLabel.Text ..= "\nУдочка Нептуна подсекает сама!"
		phase = "hooked"
		Net.event("Hook"):FireServer(castId, true)
	end
end

local END_MESSAGES: { [string]: { string } } = {
	escaped = { "Сорвалась! 🐟💨", "bad" },
	timeout = { "Не успел подсечь", "bad" },
	moved = { "Ты отошёл от воды — заброс отменён", "info" },
}

local function onEnded(id: number, reason: string, record: any)
	if id ~= castId then
		return
	end
	castId = nil
	params = nil
	phase = "idle"
	task.delay(0.35, hideMinigame)
	if reason == "caught" and type(record) == "table" then
		local fish = FishData.Fish[record.Id]
		if fish then
			local rarity = FishData.Rarities[fish.Rarity]
			Notifications.big(
				`🐟 {FishData.fullName(record)}`,
				`{rarity.Name} · {Format.perSecond(Formulas.fishIncome(record))} · неси домой!`,
				Kit.rgb(rarity.Color)
			)
			Notifications.playSound("Coins", 0.7)
		end
	else
		local message = END_MESSAGES[reason]
		if message then
			Notifications.show(message[1], message[2])
		end
	end
end

-- Кнопка ------------------------------------------------------------------------------

local function updateButton()
	local button = Hud.castButton
	local bait = Hud.baitButton
	if not button or not bait then
		return
	end
	local zoneId = zoneAtPlayer()
	local visible = phase ~= "idle" or (zoneId ~= nil and not State.isCarrying())
	button.Visible = visible
	bait.Visible = visible and phase == "idle"
	if not visible then
		return
	end
	local keyHint = if Gui.isTouch then "" else " [C]"
	local data = State.data
	if phase == "idle" then
		if data and zoneId and not data.UnlockedZones[zoneId] then
			button.Text = "🔒 Зона закрыта"
			button.BackgroundColor3 = Kit.Colors.Grey
		else
			button.Text = `🎣 ЗАКИНУТЬ{keyHint}`
			button.BackgroundColor3 = Kit.Colors.Blue
		end
	elseif phase == "casting" or phase == "waiting" then
		button.Text = "⏳ Ждём поклёвку…"
		button.BackgroundColor3 = Kit.Colors.PanelLight
	elseif phase == "bite" then
		button.Text = `‼ ПОДСЕКАЙ!{keyHint}`
		button.BackgroundColor3 = Kit.Colors.Green
	else
		button.Text = "…"
		button.BackgroundColor3 = Kit.Colors.PanelLight
	end
end

function Fishing.start()
	buildOverlay()
	local button = Hud.castButton
	if button then
		button.Activated:Connect(press)
	end
	overlay.Activated:Connect(hook)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.C then
			press()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 and phase == "bite" then
			hook()
		end
	end)

	Net.event("FishingBite").OnClientEvent:Connect(onBite)
	Net.event("FishingEnded").OnClientEvent:Connect(onEnded)

	RunService.RenderStepped:Connect(function()
		if phase == "bite" and params then
			local elapsed = os.clock() - biteStarted
			marker.Position = UDim2.fromScale(Formulas.markerPosition(elapsed, params.speed), 0.5)
			timerFill.Size = UDim2.fromScale(math.clamp(1 - elapsed / params.window, 0, 1), 1)
			if elapsed > params.window then
				-- окно закончилось: ждём ответа сервера (timeout)
				phase = "hooked"
			end
		end
	end)

	task.spawn(function()
		while true do
			updateButton()
			task.wait(0.15)
		end
	end)
end

return Fishing
