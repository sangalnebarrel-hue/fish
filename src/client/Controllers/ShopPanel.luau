--[[
	Магазин снаряжения (открывается у прилавка) и панель геймпассов (кнопка VIP в HUD).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)
local ShopData = require(Shared.ShopData)

local UI = script.Parent.Parent:WaitForChild("UI")
local Kit = require(UI:WaitForChild("Kit"))
local Panel = require(UI:WaitForChild("Panel"))

local State = require(script.Parent.State)
local Notifications = require(script.Parent.Notifications)

local ShopPanel = {}

local player = Players.LocalPlayer

local TABS = { "Удочки", "Вёдра", "Наживка", "Ласты", "Аквариум" }

local shop: Panel.Panel
local passes: Panel.Panel
local shopList: ScrollingFrame
local passList: ScrollingFrame
local currentTab = TABS[1]
-- кнопки «Купить»: перекрашиваются, когда меняются деньги, без пересборки списка
local priceButtons: { { button: TextButton, price: number } } = {}

local function purchase(category: string, id: string?)
	local ok, success, message = pcall(function()
		return Net.func("Purchase"):InvokeServer(category, id)
	end)
	if not ok then
		Notifications.show("Магазин не ответил, попробуй ещё раз", "bad")
		return
	end
	if type(message) == "string" then
		Notifications.show(message, if success then "good" else "bad")
	end
	Notifications.playSound("Click", 0.5)
end

type Action = { text: string, color: Color3, onClick: (() -> ())?, price: number? }

-- Карточка товара: название, описание и кнопка справа.
local function card(parent: Instance, order: number, title: string, description: string, action: Action)
	local frame = Kit.make("Frame", {
		Size = UDim2.new(1, 0, 0, 82),
		BackgroundColor3 = Kit.Colors.PanelLight,
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.corner(frame, 14)
	Kit.text({
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -260, 0, 34),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	Kit.text({
		Position = UDim2.fromOffset(16, 44),
		Size = UDim2.new(1, -260, 0, 26),
		Text = description,
		TextColor3 = Kit.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local button = Kit.button(action.text, action.color, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(220, 58),
		Parent = frame,
	}, action.onClick)
	button.Active = action.onClick ~= nil
	if action.price then
		table.insert(priceButtons, { button = button, price = action.price })
	end
end

local function buyAction(price: number, category: string, id: string?, label: string?): Action
	local affordable = State.money() >= price
	return {
		text = `{label or "Купить"} {Format.money(price)}`,
		color = if affordable then Kit.Colors.Green else Kit.Colors.Grey,
		price = price,
		onClick = function()
			purchase(category, id)
		end,
	}
end

local function renderRods(data: { [string]: any })
	for index, rod in ShopData.RodList do
		local action: Action
		if data.Rod == rod.Id then
			action = { text = "Надето ✓", color = Kit.Colors.Grey }
		elseif data.OwnedRods[rod.Id] then
			action = {
				text = "Надеть",
				color = Kit.Colors.Blue,
				onClick = function()
					purchase("Rod", rod.Id)
				end,
			}
		else
			action = buyAction(rod.Price, "Rod", rod.Id)
		end
		local description = `Удача ×{rod.Luck}` .. (if rod.Perk then ` · {rod.Perk}` else "")
		card(shopList, index, `🎣 {rod.Name}`, description, action)
	end
end

local function renderBuckets(data: { [string]: any })
	for index, bucket in ShopData.BucketList do
		local action: Action
		if data.Bucket == bucket.Id then
			action = { text = "Надето ✓", color = Kit.Colors.Grey }
		elseif data.OwnedBuckets[bucket.Id] then
			action = {
				text = "Взять",
				color = Kit.Colors.Blue,
				onClick = function()
					purchase("Bucket", bucket.Id)
				end,
			}
		else
			action = buyAction(bucket.Price, "Bucket", bucket.Id)
		end
		local description = `Кислород ×{bucket.Oxygen}` .. (if bucket.Perk then ` · {bucket.Perk}` else "")
		card(shopList, index, `🪣 {bucket.Name}`, description, action)
	end
end

local function renderBaits(data: { [string]: any })
	for index, bait in ShopData.BaitList do
		local count = if bait.Infinite then "∞" else tostring(data.Baits[bait.Id] or 0)
		local description = `{bait.Description} · у тебя: {count}`
		local action: Action
		if bait.Infinite then
			action = { text = "Бесплатно", color = Kit.Colors.Grey }
		elseif not bait.Price then
			action = { text = "Только в ивентах", color = Kit.Colors.Grey }
		else
			action = buyAction(bait.Price, "Bait", bait.Id, `×{bait.Pack} за`)
		end
		card(shopList, index, `🪱 {bait.Name}`, description, action)
	end
end

local function renderFins(data: { [string]: any })
	local level = data.FinsLevel :: number
	local bonus = math.floor(level * Config.Movement.FinsBonusPerLevel * 100 + 0.5)
	local description =
		`Уровень {level}/{Config.Movement.MaxFinsLevel} · +{bonus}% к бегу. Быстрее бегаешь — дальше уносишь рыбу`
	local action: Action
	if level >= Config.Movement.MaxFinsLevel then
		action = { text = "Максимум", color = Kit.Colors.Grey }
	else
		action = buyAction(Formulas.finsPrice(level + 1), "Fins", nil, "Улучшить")
	end
	card(shopList, 1, "🩴 Ласты", description, action)
end

local function renderAquarium(data: { [string]: any })
	for index, tier in ShopData.AquariumTiers do
		local action: Action
		if index <= data.AquariumTier then
			action = { text = "Есть ✓", color = Kit.Colors.Grey }
		elseif index > Config.MaxAquariumTier then
			action = { text = "Скоро", color = Kit.Colors.Grey }
		elseif index == data.AquariumTier + 1 then
			action = buyAction(tier.Price, "Aquarium", nil, "Расширить")
		else
			action = { text = "Сначала прошлое", color = Kit.Colors.Grey }
		end
		card(
			shopList,
			index,
			`🐠 Аквариум на {tier.Slots} мест`,
			"Больше рыб — больше дохода в секунду",
			action
		)
	end
end

local RENDERERS: { [string]: ({ [string]: any }) -> () } = {
	["Удочки"] = renderRods,
	["Вёдра"] = renderBuckets,
	["Наживка"] = renderBaits,
	["Ласты"] = renderFins,
	["Аквариум"] = renderAquarium,
}

local function renderShop()
	local data = State.data
	if not data or not shop.isOpen() then
		return
	end
	Panel.clear(shopList)
	table.clear(priceButtons)
	RENDERERS[currentTab](data)
end

local function recolorPrices()
	local money = State.money()
	for _, entry in priceButtons do
		entry.button.BackgroundColor3 = if money >= entry.price then Kit.Colors.Green else Kit.Colors.Grey
	end
end

local function renderPasses()
	if not passes.isOpen() then
		return
	end
	Panel.clear(passList)
	local ids: { [string]: number } = Config.GamePassIds
	local enabled: { [string]: boolean } = Config.EnabledPasses
	local order = 0
	for _, pass in ShopData.PassList do
		if enabled[pass.Id] then
			order += 1
			local action: Action
			if State.hasPass(pass.Id) then
				action = { text = "Куплено ✓", color = Kit.Colors.Grey }
			else
				action = {
					text = `R$ {pass.Robux}`,
					color = Kit.Colors.Green,
					onClick = function()
						local assetId = ids[pass.Id]
						if assetId and assetId ~= 0 then
							MarketplaceService:PromptGamePassPurchase(player, assetId)
						else
							Notifications.show("Этот геймпасс ещё не настроен", "info")
						end
					end,
				}
			end
			card(passList, order, `⭐ {pass.Name}`, pass.Description, action)
		end
	end
end

function ShopPanel.openShop()
	shop.open()
end

function ShopPanel.openPasses()
	passes.open()
end

function ShopPanel.start()
	shop = Panel.create("Shop", "🛒 Снаряжение", Kit.Colors.Orange, Vector2.new(820, 520))
	local body, selectTab = Panel.tabs(shop, TABS, function(tab)
		currentTab = tab
		renderShop()
	end)
	shopList = Panel.scroll(body)
	shop.onOpen = function()
		selectTab(currentTab)
	end

	passes = Panel.create("Passes", "⭐ VIP и бонусы", Kit.Colors.Gold, Vector2.new(760, 460))
	passList = Panel.scroll(passes.content)
	passes.onOpen = renderPasses

	State.Changed:Connect(renderShop)
	player:GetAttributeChangedSignal("Money"):Connect(recolorPrices)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function()
		task.wait(1)
		renderPasses()
	end)
	Net.event("OpenUI").OnClientEvent:Connect(function(name)
		if name == "Shop" then
			shop.open()
		end
	end)
end

return ShopPanel
