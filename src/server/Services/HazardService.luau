--[[
	Опасности зон. В MVP — медузы Кораллового рифа: жалят и замедляют на 2 секунды.
	Положение медуз считается формулой от серверного времени (клиент рисует ту же формулу),
	поэтому сеть не гоняет их координаты каждый кадр.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local MapService = require(script.Parent.MapService)
local MovementService = require(script.Parent.MovementService)

local HazardService = {}

local JELLY_HIT_RADIUS = 3.6
local JELLY_SLOW = 0.5
local JELLY_DURATION = 2

local function checkJellyfish()
	local t = Workspace:GetServerTimeNow()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		-- медузы живут только у рифа, остальных игроков не проверяем
		if root and root.Position.Z > MapService.HazardMinZ and not MovementService.isDebuffed(player, "Jelly") then
			for _, jelly in MapService.Jellyfish do
				if (root.Position - MapService.jellyPosition(jelly, t)).Magnitude <= JELLY_HIT_RADIUS then
					MovementService.debuff(player, "Jelly", JELLY_SLOW, JELLY_DURATION)
					Net.event("Notify"):FireClient(player, "🪼 Медуза ужалила! Замедление на 2 сек", "bad")
					break
				end
			end
		end
	end
end

function HazardService.start()
	task.spawn(function()
		while true do
			task.wait(0.1)
			checkJellyfish()
		end
	end)
end

return HazardService
