--[[
	Базы игроков: аквариумы, кража, замок, тревога, сейф и защита новичка.

	Рыба принадлежит игроку, пока лежит в его Profile.Data.Fish. Когда её крадут, она остаётся
	у владельца с пометкой «в пути» (transit). Владение меняется одним действием только в момент,
	когда вор доносит рыбу до своего аквариума (transfer). Если вор не успел, пометка просто снимается.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local FishData = require(Shared.FishData)
local FishModel = require(Shared.FishModel)
local Format = require(Shared.Format)
local Formulas = require(Shared.Formulas)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local MapService = require(script.Parent.MapService)
local MonetizationService = require(script.Parent.MonetizationService)
local AntiCheatService = require(script.Parent.AntiCheatService)
local IndexService = require(script.Parent.IndexService)
local Analytics = require(script.Parent.Analytics)

type Plot = MapService.Plot
type FishRecord = DataService.FishRecord

local BaseService = {}

-- Устанавливает BucketService: может ли вор взять рыбу (свободно ли ведро, влезет ли размер).
BaseService.stealHandler = nil :: ((thief: Player, owner: Player, record: FishRecord) -> (boolean, string?))?

local plotOf: { [Player]: Plot } = {}
local ownerOf: { [number]: Player } = {}
local transit: { [string]: { thief: Player, owner: Player } } = {}
local lockedUntil: { [number]: number } = {}
local lockCooldownUntil: { [Player]: number } = {}
local holdBegan: { [Player]: number } = {}
local alarmCooldown: { [Player]: { [Player]: number } } = {}
local characterConnections: { [Player]: { RBXScriptConnection } } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function notify(player: Player, text: string, kind: string?)
	Net.event("Notify"):FireClient(player, text, kind or "info")
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Публичные запросы -----------------------------------------------------------

function BaseService.plotOf(player: Player): Plot?
	return plotOf[player]
end

function BaseService.ownerOfPlot(plot: Plot): Player?
	return ownerOf[plot.Index]
end

function BaseService.maxSlots(player: Player): number
	local data = DataService.get(player)
	local tier = if data then data.AquariumTier else 1
	return math.min(Formulas.aquariumSlots(tier, MonetizationService.passes(player)), Formulas.maxPossibleSlots())
end

function BaseService.isFull(player: Player): boolean
	local data = DataService.get(player)
	return data == nil or #data.Fish >= BaseService.maxSlots(player)
end

function BaseService.findFish(player: Player, uid: string): (number?, FishRecord?)
	local data = DataService.get(player)
	if not data then
		return nil, nil
	end
	for index, record in data.Fish do
		if record.Uid == uid then
			return index, record
		end
	end
	return nil, nil
end

function BaseService.isInTransit(uid: string): boolean
	return transit[uid] ~= nil
end

-- Рыбы, которые сейчас в аквариуме и приносят доход (украденные «в пути» не считаются).
function BaseService.activeFish(player: Player): { FishRecord }
	local data = DataService.get(player)
	local result = {}
	if data then
		for _, record in data.Fish do
			if not transit[record.Uid] then
				table.insert(result, record)
			end
		end
	end
	return result
end

function BaseService.isLocked(plot: Plot): boolean
	local untilTime = lockedUntil[plot.Index]
	return untilTime ~= nil and untilTime > now()
end

function BaseService.isInsideOwnBase(player: Player, margin: number?): boolean
	local plot = plotOf[player]
	local root = rootOf(player)
	return plot ~= nil and root ~= nil and MapService.isInsidePlot(plot, root.Position, margin)
end

-- Отрисовка аквариума ------------------------------------------------------------

local function fishLabel(record: FishRecord, isSafe: boolean, inTransit: boolean, scale: number): BillboardGui
	local fish = FishData.Fish[record.Id]
	local rarity = FishData.Rarities[fish.Rarity]
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(170, 48)
	billboard.StudsOffset = Vector3.new(0, 1.2 * scale + 1, 0)
	billboard.MaxDistance = 45
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.RichText = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.3
	local status = if inTransit
		then `<font color="#FF5050">УКРАДЕНА!</font>`
		elseif isSafe then `🔒 сейф · {Format.perSecond(Formulas.fishIncome(record))}`
		else Format.perSecond(Formulas.fishIncome(record))
	text.Text = `<font color="{Format.hex(rarity.Color)}">{FishData.fullName(record)}</font>\n{status}`
	text.Parent = billboard
	return billboard
end

local function renderNow(player: Player)
	local plot = plotOf[player]
	local data = DataService.get(player)
	if not plot or not data then
		return
	end
	plot.FishFolder:ClearAllChildren()
	for index, record in data.Fish do
		local slotCf = plot.SlotCFrames[index]
		if not slotCf or not FishData.Fish[record.Id] then
			continue
		end
		local inTransit = transit[record.Uid] ~= nil
		local isSafe = data.SafeUid == record.Uid
		local model = FishModel.build(record, { anchored = true })
		model.Name = record.Uid
		model:PivotTo(slotCf)
		model:SetAttribute("Uid", record.Uid)
		model:SetAttribute("OwnerUserId", player.UserId)
		model:SetAttribute("Slot", index)

		local body = model.PrimaryPart :: BasePart
		local scale = (model:GetAttribute("Scale") :: number?) or 1
		fishLabel(record, isSafe, inTransit, scale).Parent = body

		if inTransit then
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					part.Transparency = math.max(part.Transparency, 0.8)
				end
			end
		else
			model:AddTag("AquariumFish")
			if not isSafe then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "StealPrompt"
				prompt.ActionText = "Украсть"
				prompt.ObjectText = FishData.fullName(record)
				prompt.HoldDuration = Config.Steal.HoldDuration
				prompt.MaxActivationDistance = Config.Steal.MaxDistance
				prompt.RequiresLineOfSight = false
				prompt:SetAttribute("Uid", record.Uid)
				prompt:SetAttribute("OwnerUserId", player.UserId)
				prompt.Parent = body
			end
		end
		model.Parent = plot.FishFolder
	end
end

local renderPending: { [Player]: boolean } = {}

-- Перерисовать аквариум. Несколько изменений за кадр (кража, перенос рыбы между игроками)
-- склеиваются в одну перерисовку в конце кадра.
function BaseService.render(player: Player)
	if renderPending[player] then
		return
	end
	renderPending[player] = true
	task.defer(function()
		renderPending[player] = nil
		if player.Parent == Players then
			renderNow(player)
		end
	end)
end

-- Изменение аквариума -----------------------------------------------------------

function BaseService.addFish(player: Player, record: FishRecord): boolean
	local data = DataService.get(player)
	if not data or BaseService.isFull(player) then
		return false
	end
	table.insert(data.Fish, record)
	IndexService.discover(player, record.Id)
	BaseService.render(player)
	DataService.markDirty(player)
	return true
end

function BaseService.removeFish(player: Player, uid: string): FishRecord?
	local data = DataService.get(player)
	local index, record = BaseService.findFish(player, uid)
	if not data or not index or not record then
		return nil
	end
	table.remove(data.Fish, index)
	if data.SafeUid == uid then
		data.SafeUid = ""
	end
	transit[uid] = nil
	BaseService.render(player)
	DataService.markDirty(player)
	return record
end

function BaseService.setSafe(player: Player, uid: string): (boolean, string?)
	local data = DataService.get(player)
	local _, record = BaseService.findFish(player, uid)
	if not data or not record then
		return false, "Рыба не найдена"
	end
	if transit[uid] then
		return false, "Эту рыбу сейчас крадут!"
	end
	data.SafeUid = if data.SafeUid == uid then "" else uid
	BaseService.render(player)
	DataService.markDirty(player)
	return true, if data.SafeUid == uid then `🔒 {FishData.fullName(record)} в сейфе` else "Сейф освобождён"
end

function BaseService.setTransit(uid: string, owner: Player, thief: Player)
	transit[uid] = { thief = thief, owner = owner }
	BaseService.render(owner)
	DataService.markDirty(owner)
end

-- Кража не удалась: рыба «уплывает домой» (просто снимаем пометку).
function BaseService.clearTransit(uid: string)
	local entry = transit[uid]
	if not entry then
		return
	end
	transit[uid] = nil
	if entry.owner.Parent == Players then
		BaseService.render(entry.owner)
		DataService.markDirty(entry.owner)
	end
end

-- Вор донёс рыбу до своего аквариума — меняем владельца.
function BaseService.transfer(owner: Player, uid: string, thief: Player): (boolean, string?)
	if BaseService.isFull(thief) then
		return false, "Аквариум полон! Продай рыбу на рынке."
	end
	local record = BaseService.removeFish(owner, uid)
	if not record then
		return false, "Рыба исчезла"
	end
	BaseService.addFish(thief, record)
	local ownerData = DataService.get(owner)
	local thiefData = DataService.get(thief)
	if ownerData then
		ownerData.Stats.LostToThieves = (ownerData.Stats.LostToThieves or 0) + 1
	end
	if thiefData then
		thiefData.Stats.Stolen = (thiefData.Stats.Stolen or 0) + 1
		Analytics.onboarding(thief, thiefData, "FirstSteal")
	end
	-- сохраняем обоих сразу, чтобы при падении сервера рыба не задвоилась
	DataService.save(owner)
	DataService.save(thief)
	return true, nil
end

-- Замок -------------------------------------------------------------------------

local function setBarrier(plot: Plot, on: boolean)
	for _, wall in plot.Barrier do
		wall.Transparency = if on then 0.55 else 1
		wall.CanCollide = on
	end
end

local function pushOutIntruders(plot: Plot)
	local owner = ownerOf[plot.Index]
	for _, player in Players:GetPlayers() do
		if player ~= owner then
			local root = rootOf(player)
			if root and MapService.isInsidePlot(plot, root.Position, 1) then
				local character = player.Character :: Model
				AntiCheatService.grace(player, 2)
				character:PivotTo(MapService.outsideFront(plot) * CFrame.new((math.random() - 0.5) * 16, 0, 0))
				notify(player, "🔒 База закрыта — тебя вытолкнуло барьером", "bad")
			end
		end
	end
end

local function setLock(plot: Plot, untilTime: number, reason: string)
	lockedUntil[plot.Index] = untilTime
	plot.Model:SetAttribute("LockedUntil", untilTime)
	plot.Model:SetAttribute("LockReason", reason)
	setBarrier(plot, true)
	pushOutIntruders(plot)
end

local function unlock(plot: Plot)
	lockedUntil[plot.Index] = nil
	plot.Model:SetAttribute("LockedUntil", 0)
	plot.Model:SetAttribute("LockReason", "")
	setBarrier(plot, false)
end

function BaseService.lock(player: Player): (boolean, string?)
	local plot = plotOf[player]
	if not plot then
		return false, "У тебя нет базы"
	end
	if BaseService.isLocked(plot) then
		return false, "База уже закрыта"
	end
	local t = now()
	local cooldown = lockCooldownUntil[player]
	if cooldown and cooldown > t then
		return false, `Замок перезаряжается: {Format.time(cooldown - t)}`
	end
	if not BaseService.isInsideOwnBase(player, 4) then
		return false, "Замок включается только на своей базе"
	end
	setLock(plot, t + Config.Lock.Duration, "lock")
	lockCooldownUntil[player] = t + Config.Lock.Cooldown
	player:SetAttribute("LockCooldownUntil", t + Config.Lock.Cooldown)
	return true, `🔒 База закрыта на {Config.Lock.Duration} сек`
end

-- Кража -------------------------------------------------------------------------

local function alarm(owner: Player, intruder: Player)
	local plot = plotOf[owner]
	alarmCooldown[owner] = alarmCooldown[owner] or {}
	local last = alarmCooldown[owner][intruder]
	local t = os.clock()
	if last and t - last < 8 then
		return
	end
	alarmCooldown[owner][intruder] = t
	Net.event("Alarm"):FireClient(owner, intruder.DisplayName)
	if plot then
		plot.AlarmSound:Play()
	end
end

local function handleSteal(thief: Player, prompt: ProximityPrompt)
	local uid = prompt:GetAttribute("Uid") :: string?
	local ownerId = prompt:GetAttribute("OwnerUserId") :: number?
	if not uid or not ownerId then
		return
	end
	local owner = Players:GetPlayerByUserId(ownerId)
	local plot = owner and plotOf[owner]
	if not owner or not plot or owner == thief then
		return
	end
	if not DataService.isLoaded(thief) or not plotOf[thief] then
		return
	end
	if BaseService.isLocked(plot) then
		notify(thief, "🔒 База закрыта", "bad")
		return
	end
	local began = holdBegan[thief]
	if not began or os.clock() - began < Config.Steal.HoldDuration - 0.35 then
		return
	end
	local index, record = BaseService.findFish(owner, uid)
	local ownerData = DataService.get(owner)
	if not index or not record or not ownerData then
		return
	end
	if transit[uid] then
		notify(thief, "Эту рыбу уже кто-то несёт", "bad")
		return
	end
	if ownerData.SafeUid == uid then
		notify(thief, "🔒 Эта рыба в сейфе", "bad")
		return
	end
	local root = rootOf(thief)
	local slotCf = plot.SlotCFrames[index]
	if not root or not slotCf or (root.Position - slotCf.Position).Magnitude > Config.Steal.MaxDistance + Config.Steal.DistanceTolerance then
		return
	end

	local handler = BaseService.stealHandler
	if not handler then
		return
	end
	local ok, message = handler(thief, owner, record)
	if not ok then
		if message then
			notify(thief, message, "bad")
		end
		return
	end
	BaseService.setTransit(uid, owner, thief)
	alarm(owner, thief)
	notify(owner, `⚠ {thief.DisplayName} крадёт твою рыбу: {FishData.fullName(record)}! Шлёпни вора!`, "bad")
	Analytics.custom(thief, "FishStealStarted", FishData.Rarities[FishData.Fish[record.Id].Rarity].Order)
end

-- Назначение баз --------------------------------------------------------------------

local function applyOwnerCollision(player: Player, character: Model)
	local plot = plotOf[player]
	if not plot then
		return
	end
	local function apply(descendant: Instance)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = plot.OwnerGroup
		end
	end
	for _, descendant in character:GetDescendants() do
		apply(descendant)
	end
	table.insert(characterConnections[player], character.DescendantAdded:Connect(apply))
end

local function spawnAtBase(player: Player, character: Model)
	local plot = plotOf[player]
	if not plot then
		return
	end
	character:WaitForChild("HumanoidRootPart", 10)
	if character.Parent then
		AntiCheatService.grace(player, 3)
		character:PivotTo(plot.SpawnCFrame)
	end
end

local function assign(player: Player)
	local plot: Plot? = nil
	for _, candidate in MapService.Plots do
		if not ownerOf[candidate.Index] then
			plot = candidate
			break
		end
	end
	if not plot then
		player:Kick("Сервер полон, зайди на другой.")
		return
	end
	plotOf[player] = plot
	ownerOf[plot.Index] = player
	alarmCooldown[player] = {}
	characterConnections[player] = {}
	plot.Model:SetAttribute("OwnerUserId", player.UserId)
	plot.Model:SetAttribute("OwnerName", player.DisplayName)
	player:SetAttribute("BaseIndex", plot.Index)
	plot.SignTitle.Text = player.DisplayName
	plot.OwnerTag.Text = player.DisplayName

	-- Новичку 5 минут защиты базы после входа на сервер
	setLock(plot, now() + Config.NewbieProtection, "newbie")
	BaseService.render(player)

	table.insert(
		characterConnections[player],
		player.CharacterAdded:Connect(function(character)
			applyOwnerCollision(player, character)
			spawnAtBase(player, character)
		end)
	)
	local character = player.Character
	if character then
		applyOwnerCollision(player, character)
		task.spawn(spawnAtBase, player, character)
	end
end

local function release(player: Player)
	local plot = plotOf[player]
	for uid, entry in transit do
		if entry.owner == player then
			transit[uid] = nil
		end
	end
	local connections: { RBXScriptConnection } = characterConnections[player] or {}
	for _, connection in connections do
		connection:Disconnect()
	end
	characterConnections[player] = nil
	alarmCooldown[player] = nil
	lockCooldownUntil[player] = nil
	holdBegan[player] = nil
	if not plot then
		return
	end
	plot.FishFolder:ClearAllChildren()
	unlock(plot)
	plot.Model:SetAttribute("OwnerUserId", 0)
	plot.Model:SetAttribute("OwnerName", "")
	plot.SignTitle.Text = "Свободно"
	plot.SignSubtitle.Text = ""
	plot.OwnerTag.Text = ""
	plotOf[player] = nil
	ownerOf[plot.Index] = nil
end

-- Циклы ---------------------------------------------------------------------------

local function securityTick()
	local t = now()
	for _, plot in MapService.Plots do
		local owner = ownerOf[plot.Index]
		local untilTime = lockedUntil[plot.Index]
		if untilTime and untilTime <= t then
			unlock(plot)
			if owner then
				notify(owner, "🔓 Замок базы выключился", "info")
			end
		elseif untilTime then
			pushOutIntruders(plot)
		end
		if owner then
			for _, player in Players:GetPlayers() do
				if player ~= owner then
					local root = rootOf(player)
					if root and MapService.isInsidePlot(plot, root.Position) then
						alarm(owner, player)
					end
				end
			end
		end
	end
end

local function signTick()
	local t = now()
	for _, plot in MapService.Plots do
		local owner = ownerOf[plot.Index]
		if owner then
			local income = (owner:GetAttribute("Income") :: number?) or 0
			local untilTime = lockedUntil[plot.Index]
			local lockText = ""
			if untilTime and untilTime > t then
				local reason = plot.Model:GetAttribute("LockReason")
				lockText = if reason == "newbie" then ` · 🛡 {Format.time(untilTime - t)}` else ` · 🔒 {Format.time(untilTime - t)}`
			end
			plot.SignSubtitle.Text = `{Format.perSecond(income)}{lockText}`
		end
	end
end

function BaseService.start()
	DataService.onLoaded(assign)
	DataService.onRemoving(release)
	DataService.addSnapshotDecorator(function(player, snapshot)
		local inTransit = {}
		local data = DataService.get(player)
		if data then
			for _, record in data.Fish do
				if transit[record.Uid] then
					table.insert(inTransit, record.Uid)
				end
			end
		end
		snapshot.Transit = inTransit
		snapshot.MaxSlots = BaseService.maxSlots(player)
	end)

	MonetizationService.PassGranted:Connect(function(player: Player, passId: string)
		if passId == "VIP" or passId == "SecondFloor" then
			BaseService.render(player)
			DataService.markDirty(player)
		end
	end)

	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name == "StealPrompt" then
			holdBegan[player] = os.clock()
			local ownerId = prompt:GetAttribute("OwnerUserId") :: number?
			local owner = if ownerId then Players:GetPlayerByUserId(ownerId) else nil
			if owner and owner ~= player then
				alarm(owner, player)
			end
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name == "StealPrompt" then
			handleSteal(player, prompt)
		elseif prompt.Name == "LockPrompt" then
			local plot = plotOf[player]
			if plot and plot.LockPrompt == prompt then
				local _, message = BaseService.lock(player)
				if message then
					notify(player, message)
				end
			end
		end
	end)

	Net.event("Lock").OnServerEvent:Connect(function(player)
		local _, message = BaseService.lock(player)
		if message then
			notify(player, message)
		end
	end)
	Net.func("SetSafe").OnServerInvoke = function(player, uid)
		if type(uid) ~= "string" then
			return false, "Неверный запрос"
		end
		return BaseService.setSafe(player, uid)
	end

	task.spawn(function()
		local tick = 0
		while true do
			task.wait(0.25)
			securityTick()
			tick += 1
			if tick % 4 == 0 then
				signTick()
			end
		end
	end)
end

return BaseService
