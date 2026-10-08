--[[
	Мини-рантайм Roblox поверх Lune для смоук-тестов: грузит собранный плейс,
	исполняет ModuleScript'ы с настоящими script/game, а движковые методы и события,
	которых в Lune нет, заменяет заглушками. События можно «выстрелить» из теста.

	Lune сверяет имена и типы свойств с базой Roblox API, поэтому неверное свойство
	в коде игры падает здесь так же, как упало бы в Studio.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local realTask = require("@lune/task")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local Runtime = {}

export type Signal = {
	Connect: (Signal, (...any) -> ()) -> { Disconnect: () -> () },
	Once: (Signal, (...any) -> ()) -> { Disconnect: () -> () },
	Wait: (Signal) -> ...any,
	Fire: (Signal, ...any) -> (),
	handlers: { (...any) -> () },
}

function Runtime.load(placePath: string)
	local game = roblox.deserializePlace(fs.readFile(placePath))
	-- ProfileStore читает идентификаторы сервера; у загруженного плейса их нет
	game.PlaceId = 1
	game.JobId = "lune-smoke-test"
	local failures: { string } = {}
	local mode = { server = true, studio = true }

	local function fail(message: string)
		table.insert(failures, message)
		print(`[runtime error] {message}`)
	end

	local function guard(fn: (...any) -> ...any, label: string?)
		return function(...)
			local ok, err = pcall(fn, ...)
			if not ok then
				fail(`{label or "task"}: {err}`)
			end
		end
	end

	-- Сигналы ---------------------------------------------------------------------------

	local function newSignal(): Signal
		local signal = { handlers = {} }
		function signal.Connect(_, handler)
			table.insert(signal.handlers, handler)
			return {
				Disconnect = function()
					local index = table.find(signal.handlers, handler)
					if index then
						table.remove(signal.handlers, index)
					end
				end,
			}
		end
		function signal.Once(self, handler)
			local connection
			connection = self:Connect(function(...)
				connection.Disconnect()
				handler(...)
			end)
			return connection
		end
		function signal.Wait()
			return realTask.wait(0.05)
		end
		-- Как в Roblox: каждый обработчик в своём потоке (до первого yield — синхронно).
		function signal.Fire(_, ...)
			for _, handler in table.clone(signal.handlers) do
				realTask.spawn(guard(handler, "signal handler"), ...)
			end
		end
		return signal :: any
	end

	local registry: { [any]: { [string]: Signal } } = {}
	local attributeValues: { [any]: { [string]: any } } = {}
	local NIL = newproxy() -- в таблице нельзя хранить nil, а «атрибута нет» — тоже значение
	local function signalOf(owner: any, name: string): Signal
		registry[owner] = registry[owner] or {}
		local signal = registry[owner][name]
		if not signal then
			signal = newSignal()
			registry[owner][name] = signal
			local attribute = name:match("^attribute:(.+)$")
			if attribute and typeof(owner) == "Instance" then
				attributeValues[owner] = attributeValues[owner] or {}
				local value = owner:GetAttribute(attribute)
				attributeValues[owner][attribute] = if value == nil then NIL else value
			end
		end
		return signal
	end

	-- В Roblox SetAttribute сразу шлёт GetAttributeChangedSignal. Встроенный SetAttribute
	-- в Lune этого не делает, поэтому тест периодически вызывает flushAttributes().
	local function flushAttributes()
		for owner, values in attributeValues do
			for attribute, previous in values do
				local value = owner:GetAttribute(attribute)
				local current = if value == nil then NIL else value
				if current ~= previous then
					values[attribute] = current
					signalOf(owner, `attribute:{attribute}`):Fire()
				end
			end
		end
	end

	local EVENTS = {
		GuiButton = { "Activated", "MouseButton1Down", "MouseButton1Up", "MouseLeave", "MouseEnter" },
		RemoteEvent = { "OnClientEvent", "OnServerEvent" },
		RunService = { "RenderStepped", "Heartbeat", "Stepped" },
		UserInputService = { "InputBegan", "InputEnded", "InputChanged" },
		Players = { "PlayerAdded", "PlayerRemoving" },
		Player = { "CharacterAdded", "CharacterRemoving", "Chatted" },
		Humanoid = { "Died" },
		MarketplaceService = { "PromptGamePassPurchaseFinished" },
		ProximityPromptService = { "PromptTriggered", "PromptButtonHoldBegan" },
		Instance = { "Destroying", "DescendantAdded", "ChildAdded", "AncestryChanged" },
	}
	for className, names in EVENTS do
		for _, name in names do
			roblox.implementProperty(className, name, function(self)
				return signalOf(self, name)
			end)
		end
	end
	roblox.implementMethod("Instance", "GetAttributeChangedSignal", function(self, name)
		return signalOf(self, `attribute:{name}`)
	end)
	roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(self, name)
		return signalOf(self, `property:{name}`)
	end)

	-- Методы движка --------------------------------------------------------------------------

	roblox.implementMethod("Instance", "WaitForChild", function(self, name)
		local child = self:FindFirstChild(name)
		assert(child, `WaitForChild would hang: {self:GetFullName()}.{name}`)
		return child
	end)

	local collisionGroups = {}
	roblox.implementMethod("PhysicsService", "IsCollisionGroupRegistered", function(_, name)
		return collisionGroups[name] == true
	end)
	roblox.implementMethod("PhysicsService", "RegisterCollisionGroup", function(_, name)
		assert(not collisionGroups[name], `collision group {name} registered twice`)
		collisionGroups[name] = true
	end)
	roblox.implementMethod("PhysicsService", "CollisionGroupSetCollidable", function(_, a, b)
		assert(collisionGroups[a] and collisionGroups[b], "collision group must be registered first")
	end)

	local terrainFills = {}
	roblox.implementMethod("Terrain", "FillBlock", function(_, cf, size, material)
		table.insert(terrainFills, { cf = cf, size = size, material = material })
	end)

	roblox.implementMethod("RunService", "IsServer", function()
		return mode.server
	end)
	roblox.implementMethod("RunService", "IsClient", function()
		return not mode.server
	end)
	roblox.implementMethod("RunService", "IsStudio", function()
		return mode.studio
	end)

	local clockStart = os.time()
	roblox.implementMethod("Workspace", "GetServerTimeNow", function()
		return clockStart + os.clock()
	end)

	roblox.implementMethod("Players", "GetPlayers", function(self)
		local result = {}
		for _, child in self:GetChildren() do
			if child:IsA("Player") then
				table.insert(result, child)
			end
		end
		return result
	end)
	roblox.implementMethod("Players", "GetPlayerByUserId", function(self, userId)
		for _, child in self:GetChildren() do
			if child:IsA("Player") and child.UserId == userId then
				return child
			end
		end
		return nil
	end)

	-- Сервер: сохранения в режиме заглушки ProfileStore, сеть, аналитика ---------------------

	roblox.implementMethod("DataModel", "BindToClose", function() end)
	-- Ответ «403» переводит ProfileStore в mock-режим, как в Studio без доступа к API.
	roblox.implementMethod("DataStoreService", "GetDataStore", function()
		local function forbidden()
			error("403: Studio has no API access")
		end
		return { SetAsync = forbidden, GetAsync = forbidden, UpdateAsync = forbidden, RemoveAsync = forbidden }
	end)
	roblox.implementMethod("DataStoreOptions", "SetExperimentalFeatures", function() end)
	roblox.implementMethod("MessagingService", "SubscribeAsync", function()
		return { Disconnect = function() end }
	end)
	roblox.implementMethod("MessagingService", "PublishAsync", function() end)
	local guidCounter = 0
	roblox.implementMethod("HttpService", "GenerateGUID", function()
		guidCounter += 1
		return string.format("00000000-0000-0000-0000-%012d", guidCounter)
	end)
	for _, method in { "LogCustomEvent", "LogEconomyEvent", "LogOnboardingFunnelStepEvent", "LogProgressionEvent", "LogFunnelStepEvent" } do
		roblox.implementMethod("AnalyticsService", method, function() end)
	end
	roblox.implementMethod("MarketplaceService", "UserOwnsGamePassAsync", function()
		return false
	end)

	local kicked: { [any]: string } = {}
	roblox.implementMethod("Player", "Kick", function(self, message)
		kicked[self] = message or ""
	end)

	-- Сообщения сервера клиентам складываются в журнал, тест их читает.
	local clientEvents: { { any } } = {}
	roblox.implementMethod("RemoteEvent", "FireClient", function(self, player, ...)
		table.insert(clientEvents, { remote = self.Name, player = player, args = table.pack(...) })
	end)
	roblox.implementMethod("RemoteEvent", "FireAllClients", function(self, ...)
		table.insert(clientEvents, { remote = self.Name, player = nil, args = table.pack(...) })
	end)
	local callbacks: { [any]: any } = {}
	roblox.implementProperty("RemoteFunction", "OnServerInvoke", function(self)
		return callbacks[self]
	end, function(self, value)
		callbacks[self] = value
	end)

	-- Луч вниз: на острове — земля, за его краем — вода. Для смоук-теста этого достаточно.
	roblox.implementMethod("Workspace", "Raycast", function(_, origin, direction)
		if direction.Y >= 0 then
			return nil
		end
		local flat = Vector3.new(origin.X, 0, origin.Z).Magnitude
		if flat <= 150 then
			return {
				Position = Vector3.new(origin.X, 1, origin.Z),
				Material = roblox.Enum.Material.Grass,
				Instance = nil,
				Normal = Vector3.new(0, 1, 0),
			}
		end
		return { Position = Vector3.new(origin.X, 0, origin.Z), Material = roblox.Enum.Material.Water, Instance = nil, Normal = Vector3.new(0, 1, 0) }
	end)

	roblox.implementMethod("Humanoid", "ChangeState", function() end)
	roblox.implementMethod("SoundService", "PlayLocalSound", function() end)
	roblox.implementMethod("Sound", "Play", function() end)
	roblox.implementMethod("MarketplaceService", "PromptGamePassPurchase", function() end)
	roblox.implementMethod("Debris", "AddItem", function() end)

	-- Твины применяют цель сразу: так проверяются имена и типы анимируемых свойств.
	roblox.implementMethod("TweenService", "Create", function(_, instance, _info, goals)
		local tween = { Completed = newSignal() }
		function tween.Play()
			for key, value in goals do
				instance[key] = value
			end
			tween.Completed:Fire(roblox.Enum.PlaybackState.Completed)
		end
		function tween.Cancel() end
		function tween.Pause() end
		return tween
	end)

	local function modelParts(model)
		local parts = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
		return parts
	end

	roblox.implementMethod("Model", "PivotTo", function(self, target)
		local primary = self.PrimaryPart
		assert(primary, `PivotTo on {self:GetFullName()} without PrimaryPart`)
		local delta = target * primary.CFrame:Inverse()
		for _, part in modelParts(self) do
			part.CFrame = delta * part.CFrame
			part.Position = part.CFrame.Position -- в Lune Position не следует за CFrame
		end
	end)
	roblox.implementMethod("Model", "GetPivot", function(self)
		return if self.PrimaryPart then self.PrimaryPart.CFrame else CFrame.new()
	end)
	roblox.implementMethod("Model", "GetExtentsSize", function(self)
		local min = Vector3.new(math.huge, math.huge, math.huge)
		local max = -min
		for _, part in modelParts(self) do
			local half = part.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = part.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
						min = min:Min(corner)
						max = max:Max(corner)
					end
				end
			end
		end
		return max - min
	end)

	-- В Lune 0.10 CFrame.lookAt отражает ось Z. Подменяем на эталонную формулу Roblox.
	local function lookAt(at, target, up)
		local look = (target - at).Unit
		local right = look:Cross(up or Vector3.new(0, 1, 0)).Unit
		local trueUp = right:Cross(look)
		return CFrame.fromMatrix(at, right, trueUp, -look)
	end
	local CFrameProxy = setmetatable({ lookAt = lookAt }, { __index = CFrame })

	-- Сервисы-заглушки: у Lune есть встроенный Instance:AddTag, он перекрывает
	-- CollectionService:AddTag(instance, tag), а колбэки TextChatService не поддерживаются.
	local CollectionServiceProxy = {
		AddTag = function(_, instance, tag)
			instance:AddTag(tag)
		end,
		HasTag = function(_, instance, tag)
			return instance:HasTag(tag)
		end,
		GetTagged = function(_, tag)
			local result = {}
			for _, descendant in game:GetDescendants() do
				if descendant:HasTag(tag) then
					table.insert(result, descendant)
				end
			end
			return result
		end,
		GetInstanceAddedSignal = function(_, tag)
			return signalOf("CollectionService", `added:{tag}`)
		end,
		GetInstanceRemovedSignal = function(_, tag)
			return signalOf("CollectionService", `removed:{tag}`)
		end,
	}
	local TextChatServiceProxy = { OnIncomingMessage = nil }

	local gameProxy = setmetatable({
		GetService = function(_, name)
			if name == "CollectionService" then
				return CollectionServiceProxy
			elseif name == "TextChatService" then
				return TextChatServiceProxy
			end
			return game:GetService(name)
		end,
	}, {
		__index = function(_, key)
			return game[key]
		end,
	})

	local taskProxy = {
		spawn = function(fn, ...)
			if type(fn) == "thread" then
				return realTask.spawn(fn, ...)
			end
			return realTask.spawn(guard(fn, "task.spawn"), ...)
		end,
		defer = function(fn, ...)
			return realTask.defer(guard(fn, "task.defer"), ...)
		end,
		delay = function(seconds, fn, ...)
			return realTask.delay(seconds, guard(fn, "task.delay"), ...)
		end,
		wait = realTask.wait,
		cancel = realTask.cancel,
	}

	local TweenInfoStub = {
		new = function(...)
			return { ... }
		end,
	}

	-- Загрузчик ModuleScript / LocalScript / Script -------------------------------------------

	local cache = {}
	local function env(scriptInstance)
		return {
			script = scriptInstance,
			game = gameProxy,
			workspace = game:GetService("Workspace"),
			require = nil :: any,
			task = taskProxy,
			warn = function(...)
				local parts = {}
				for _, value in { ... } do
					table.insert(parts, tostring(value))
				end
				fail(`warn: {table.concat(parts, " ")}`)
			end,
			Instance = Instance,
			Vector3 = Vector3,
			Vector2 = roblox.Vector2,
			CFrame = CFrameProxy,
			Color3 = roblox.Color3,
			UDim = roblox.UDim,
			UDim2 = roblox.UDim2,
			Enum = roblox.Enum,
			NumberRange = roblox.NumberRange,
			NumberSequence = roblox.NumberSequence,
			ColorSequence = roblox.ColorSequence,
			TweenInfo = TweenInfoStub,
			RaycastParams = {
				new = function()
					return {}
				end,
			},
			Random = {
				new = function()
					return {
						NextNumber = function(_, min, max)
							min = min or 0
							max = max or 1
							return min + math.random() * (max - min)
						end,
						NextInteger = function(_, min, max)
							return math.random(min, max)
						end,
					}
				end,
			},
		}
	end

	local function requireModule(moduleScript)
		if cache[moduleScript] ~= nil then
			return cache[moduleScript]
		end
		assert(moduleScript:IsA("ModuleScript"), `require of non-module {moduleScript:GetFullName()}`)
		local scriptEnv = env(moduleScript)
		scriptEnv.require = requireModule
		local chunk = luau.load(moduleScript.Source, { debugName = moduleScript:GetFullName(), environment = scriptEnv })
		local result = chunk()
		cache[moduleScript] = result
		return result
	end

	local function runScript(scriptInstance)
		local scriptEnv = env(scriptInstance)
		scriptEnv.require = requireModule
		local chunk = luau.load(scriptInstance.Source, { debugName = scriptInstance:GetFullName(), environment = scriptEnv })
		guard(chunk, scriptInstance:GetFullName())()
	end

	-- В Lune BasePart.Position хранится отдельно от CFrame. В Roblox это одно и то же,
	-- поэтому после перемещения деталей тест копирует CFrame.Position в Position.
	local function syncPositions(root)
		local list = if root:IsA("BasePart") then { root } else {}
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(list, descendant)
			end
		end
		for _, part in list do
			part.Position = part.CFrame.Position
		end
	end

	-- Новый экземпляр с тегом: в Roblox клиент узнаёт о нём через GetInstanceAddedSignal.
	local function announceTags(root)
		for _, descendant in root:GetDescendants() do
			for _, tag in descendant:GetTags() do
				signalOf("CollectionService", `added:{tag}`):Fire(descendant)
			end
		end
	end

	return {
		game = game,
		gameProxy = gameProxy,
		mode = mode,
		failures = failures,
		terrainFills = terrainFills,
		textChatService = TextChatServiceProxy,
		require = requireModule,
		runScript = runScript,
		signalOf = signalOf,
		announceTags = announceTags,
		syncPositions = syncPositions,
		flushAttributes = flushAttributes,
		clientEvents = clientEvents,
		callbacks = callbacks,
		kicked = kicked,
		lookAt = lookAt,
		modelParts = modelParts,
	}
end

-- Простые проверки для тестов.
function Runtime.suite()
	local suite = { passed = 0, failed = 0 }
	function suite.test(name: string, fn: () -> ())
		local ok, err = pcall(fn)
		if ok then
			suite.passed += 1
		else
			suite.failed += 1
			print(`FAIL  {name}\n      {err}`)
		end
	end
	function suite.expect(condition: any, message: string?)
		if not condition then
			error(message or "expectation failed", 2)
		end
	end
	return suite
end

return Runtime
