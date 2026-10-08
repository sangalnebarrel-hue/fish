--[[
	Доска лидеров в центре гавани: игроки сервера по доходу в секунду.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)

local MapService = require(script.Parent.MapService)

local LeaderboardService = {}

local MEDALS = { "🥇", "🥈", "🥉" }

local function refresh()
	local entries = {}
	for _, player in Players:GetPlayers() do
		table.insert(entries, { name = player.DisplayName, income = (player:GetAttribute("Income") :: number?) or 0 })
	end
	table.sort(entries, function(a, b)
		return a.income > b.income
	end)
	for index, row in MapService.LeaderboardRows do
		local entry = entries[index]
		if entry then
			row.Text = `{MEDALS[index] or `{index}.`} {entry.name} — {Format.perSecond(entry.income)}`
		else
			row.Text = ""
		end
	end
end

function LeaderboardService.start()
	task.spawn(function()
		while true do
			refresh()
			task.wait(5)
		end
	end)
end

return LeaderboardService
