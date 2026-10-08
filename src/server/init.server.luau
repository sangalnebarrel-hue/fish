--[[
	Точка входа сервера. Сервисы подключаются в порядке зависимостей:
	сначала у всех вызывается init(), потом start(). Порядок start() важен:
	в нём же регистрируются обработчики DataService.onLoaded, и они вызываются по очереди
	(сначала геймпассы, потом база, потом доход и офлайн-заработок).
]]

local Services = script:WaitForChild("Services")

local ORDER = {
	"Analytics",
	"DataService",
	"MapService",
	"MonetizationService",
	"MovementService",
	"AntiCheatService",
	"EventService",
	"IndexService",
	"BaseService",
	"EconomyService",
	"BucketService",
	"FishingService",
	"SlapService",
	"HazardService",
	"ShopService",
	"LeaderboardService",
	"AdminService",
}

type Service = { init: (() -> ())?, start: (() -> ())? }

local modules: { [string]: Service } = {}
for _, name in ORDER do
	modules[name] = require(Services:WaitForChild(name) :: ModuleScript) :: any
end

for _, name in ORDER do
	local init = modules[name].init
	if init then
		init()
	end
end

for _, name in ORDER do
	local start = modules[name].start
	if start then
		start()
	end
end

-- Игроков начинаем загружать только теперь, когда все подписались на DataService.onLoaded.
(modules.DataService :: any).listen()

print(`[Server] {#ORDER} services started`)
