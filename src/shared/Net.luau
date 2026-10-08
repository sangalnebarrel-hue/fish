--[[
	Все RemoteEvent / RemoteFunction игры. Сервер создаёт их при первом require,
	клиент ждёт появления. Имена перечислены здесь, чтобы опечатка ломалась сразу.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	-- сервер -> клиент
	"DataSync", -- (snapshot) свои данные игрока
	"Notify", -- (text, kind)
	"FishingBite", -- (castId, rarityId, hookParams)
	"FishingEnded", -- (castId, result, info)
	"Alarm", -- (intruderName)
	"Knockback", -- (velocity: Vector3)
	"OpenUI", -- (panelName)
	"Effect", -- (effectName, ...)
	"OfflineEarnings", -- (amount, seconds)
	-- клиент -> сервер
	"Hook", -- (castId, success)
	"CancelCast", -- ()
	"Slap", -- ()
	"Lock", -- ()
	"SelectBait", -- (baitId)
}

local FUNCTIONS = {
	"Cast", -- () -> (ok, castIdOrMessage)
	"Purchase", -- (category, id) -> (ok, message)
	"Sell", -- (uid | "bucket") -> (ok, message)
	"SetSafe", -- (uid) -> (ok, message)
	"RequestSync", -- () -> snapshot
}

local Net = {}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Net.event(name: string): RemoteEvent
	assert(table.find(EVENTS, name), `Unknown remote event {name}`)
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	assert(table.find(FUNCTIONS, name), `Unknown remote function {name}`)
	return folder:WaitForChild(name) :: RemoteFunction
end

-- Общее состояние мира (ивенты, ночь). Сервер пишет атрибуты, клиент читает.
function Net.state(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("GameState")
		if existing then
			return existing :: Folder
		end
		local state = Instance.new("Folder")
		state.Name = "GameState"
		state.Parent = ReplicatedStorage
		return state
	end
	return ReplicatedStorage:WaitForChild("GameState") :: Folder
end

return Net
