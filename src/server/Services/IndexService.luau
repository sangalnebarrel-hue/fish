--[[
	Индекс рыб: каждая новая рыба в аквариуме открывается в индексе,
	за каждые 5 открытых — награда (наживка).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FishData = require(Shared.FishData)
local Net = require(Shared.Net)
local ShopData = require(Shared.ShopData)

local DataService = require(script.Parent.DataService)
local Analytics = require(script.Parent.Analytics)

local IndexService = {}

local function discoveredCount(index: { [string]: boolean }): number
	local count = 0
	for _ in index do
		count += 1
	end
	return count
end

local function sortedMilestones(): { number }
	local milestones = {}
	for milestone in ShopData.IndexRewards do
		table.insert(milestones, milestone)
	end
	table.sort(milestones)
	return milestones
end

local MILESTONES = sortedMilestones()

function IndexService.discover(player: Player, fishId: string)
	local data = DataService.get(player)
	if not data or data.Index[fishId] then
		return
	end
	data.Index[fishId] = true
	local count = discoveredCount(data.Index)
	local notify = Net.event("Notify")
	notify:FireClient(player, `📖 Новая рыба в индексе: {FishData.displayName(fishId)} ({count})`, "good")
	Analytics.custom(player, "IndexDiscovered", count, { Fish = fishId })

	for _, milestone in MILESTONES do
		if count >= milestone and data.IndexRewards < milestone then
			local reward = ShopData.IndexRewards[milestone]
			data.Baits[reward.Bait] = (data.Baits[reward.Bait] or 0) + reward.Amount
			data.IndexRewards = milestone
			local bait = ShopData.Baits[reward.Bait]
			notify:FireClient(player, `🎁 Награда индекса за {milestone} рыб: {bait.Name} ×{reward.Amount}`, "good")
		end
	end
	DataService.markDirty(player)
end

return IndexService
