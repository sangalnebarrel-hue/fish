--[[
	Мой аквариум: список рыб, доход, сейф и продажа (продавать можно только у рыбного рынка).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FishData = require(Shared.FishData)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)

local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Panel = require(UI:WaitForChild("Panel"))

local State = require(script.Parent.State)
local Notifications = require(script.Parent.Notifications)

local AquariumPanel = {}

local MARKET_RADIUS = 24

local panel: Panel.Panel
local summary: TextLabel
local list: ScrollingFrame
local wasNearMarket = false

function AquariumPanel.isNearMarket(): boolean
	local root = State.root()
	if not root then
		return false
	end
	for _, market in CollectionService:GetTagged("Market") do
		if market:IsA("BasePart") and (market.Position - root.Position).Magnitude <= MARKET_RADIUS then
			return true
		end
	end
	return false
end

local function invoke(name: string, uid: string)
	local ok, success, message = pcall(function()
		return Net.func(name):InvokeServer(uid)
	end)
	if not ok then
		Notifications.show("Сервер не ответил, попробуй ещё раз", "bad")
	elseif type(message) == "string" then
		Notifications.show(message, if success then "good" else "bad")
	end
end

local function row(order: number, record: { [string]: any }, isSafe: boolean, inTransit: boolean, nearMarket: boolean)
	local fish = FishData.Fish[record.Id]
	if not fish then
		return
	end
	local rarity = FishData.Rarities[fish.Rarity]
	local frame = Kit.make("Frame", {
		Size = UDim2.new(1, 0, 0, 74),
		BackgroundColor3 = Kit.Colors.PanelLight,
		LayoutOrder = order,
		Parent = list,
	})
	Kit.corner(frame, 14)
	local stripe = Kit.make("Frame", {
		Size = UDim2.new(0, 10, 1, -16),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Kit.rgb(rarity.Color),
		Parent = frame,
	})
	Kit.corner(stripe, 5)
	Kit.text({
		Position = UDim2.fromOffset(28, 6),
		Size = UDim2.new(1, -380, 0, 34),
		Text = FishData.fullName(record :: any),
		TextColor3 = Kit.rgb(rarity.Color),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local income = Formulas.fishIncome(record :: any)
	local status = if inTransit then "⚠ Сейчас крадут!" elseif isSafe then "🔒 В сейфе — не украсть" else rarity.Name
	Kit.text({
		Position = UDim2.fromOffset(28, 42),
		Size = UDim2.new(1, -380, 0, 24),
		Text = `{Format.perSecond(income)} · {status}`,
		TextColor3 = if inTransit then Kit.Colors.Red else Kit.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	if inTransit then
		return
	end

	Kit.button(if isSafe then "Сейф ✓" else "🔒 В сейф", if isSafe then Kit.Colors.Gold else Kit.Colors.Purple, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -226, 0.5, 0),
		Size = UDim2.fromOffset(130, 54),
		Parent = frame,
	}, function()
		invoke("SetSafe", record.Uid)
	end)

	local price = Formulas.sellPrice(record :: any)
	local sellText = if not price
		then "Не продаётся"
		elseif nearMarket then `Продать {Format.money(price)}`
		else "Продажа у рынка"
	local sell = Kit.button(sellText, if price and nearMarket then Kit.Colors.Green else Kit.Colors.Grey, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(204, 54),
		Parent = frame,
	}, function()
		if price and AquariumPanel.isNearMarket() then
			invoke("Sell", record.Uid)
		elseif price then
			Notifications.show("Подойди к 💰 рыбному рынку в центре гавани", "info")
		end
	end)
	sell.Active = price ~= nil
end

local function render()
	local data = State.data
	if not data or not panel.isOpen() then
		return
	end
	local nearMarket = AquariumPanel.isNearMarket()
	wasNearMarket = nearMarket
	Panel.clear(list)
	local transit: { string } = data.Transit or {}
	local fishList: { { [string]: any } } = data.Fish
	summary.Text = `Рыб: {#fishList}/{data.MaxSlots or "?"} · Доход: {Format.perSecond(State.income())}`
		.. (if nearMarket then " · 💰 ты у рынка" else "")
	if #fishList == 0 then
		Kit.text({
			Size = UDim2.new(1, 0, 0, 40),
			Text = "Пока пусто. Поймай рыбу на пирсе и донеси её до базы!",
			TextColor3 = Kit.Colors.Muted,
			Parent = list,
		})
		return
	end
	for index, record in fishList do
		row(index, record, data.SafeUid == record.Uid, table.find(transit, record.Uid) ~= nil, nearMarket)
	end
end

function AquariumPanel.open()
	panel.open()
end

function AquariumPanel.start()
	panel = Panel.create("Aquarium", "🐠 Мой аквариум", Kit.Colors.Blue, Vector2.new(820, 520))
	summary = Kit.text({
		Size = UDim2.new(1, 0, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel.content,
	})
	local holder = Kit.make("Frame", {
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		BackgroundTransparency = 1,
		Parent = panel.content,
	})
	list = Panel.scroll(holder)
	panel.onOpen = render

	State.Changed:Connect(render)
	Net.event("OpenUI").OnClientEvent:Connect(function(name)
		if name == "Market" or name == "Aquarium" then
			panel.open()
		end
	end)
	-- кнопки «Продать» включаются, когда подходишь к рынку
	task.spawn(function()
		while true do
			task.wait(0.5)
			if panel.isOpen() and AquariumPanel.isNearMarket() ~= wasNearMarket then
				render()
			end
		end
	end)
end

return AquariumPanel
