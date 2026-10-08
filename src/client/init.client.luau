--[[
	Точка входа клиента. Клиент только рисует картинку и шлёт нажатия:
	всё, что стоит денег, считает сервер.
]]

local Controllers = script:WaitForChild("Controllers")

local ORDER = {
	"State",
	"Notifications",
	"ShopPanel",
	"AquariumPanel",
	"IndexPanel",
	"Hud",
	"Fishing",
	"World",
	"Effects",
	"ChatTags",
}

for _, name in ORDER do
	local controller = require(Controllers:WaitForChild(name) :: ModuleScript) :: any
	if controller.start then
		local ok, err = pcall(controller.start)
		if not ok then
			warn(`[Client] {name} failed to start: {err}`)
		end
	end
end
