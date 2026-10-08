--[[
	Локальная копия данных игрока. Сервер присылает снимок при каждом изменении.
	Деньги и доход меняются каждую секунду, поэтому приходят атрибутами игрока.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Signal)

local State = {}

local player = Players.LocalPlayer

State.data = nil :: { [string]: any }?
State.Changed = Signal.new()

local function apply(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	State.data = snapshot
	State.Changed:Fire(snapshot)
end

function State.money(): number
	return (player:GetAttribute("Money") :: number?) or 0
end

function State.income(): number
	return (player:GetAttribute("Income") :: number?) or 0
end

function State.isCarrying(): boolean
	return player:GetAttribute("CarryFish") ~= nil
end

function State.hasPass(passId: string): boolean
	return player:GetAttribute(`Pass_{passId}`) == true
end

function State.root(): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Модель своей базы (Map/Bases/BaseN).
function State.myBase(): Model?
	for _, base in CollectionService:GetTagged("Base") do
		if base:GetAttribute("OwnerUserId") == player.UserId then
			return base :: Model
		end
	end
	return nil
end

function State.start()
	Net.event("DataSync").OnClientEvent:Connect(apply)
	task.spawn(function()
		local snapshot = Net.func("RequestSync"):InvokeServer()
		if State.data == nil then
			apply(snapshot)
		end
	end)
end

return State
