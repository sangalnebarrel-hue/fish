--[[
	Обёртка над AnalyticsService: улов, кражи, покупки и где новички бросают игру.
	Ошибки аналитики никогда не ломают геймплей.
]]

local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

-- Воронка новичка: на каком шаге игроки выходят из игры.
Analytics.OnboardingSteps = {
	"Joined",
	"FirstCast",
	"FirstCatch",
	"FirstDeposit",
	"FirstPurchase",
	"FirstSteal",
}

local function safe(fn: () -> ())
	local result = table.pack(pcall(fn))
	if not result[1] then
		warn(`[Analytics] {result[2]}`)
	end
end

function Analytics.custom(player: Player, eventName: string, value: number?, fields: { [string]: any }?)
	safe(function()
		AnalyticsService:LogCustomEvent(player, eventName, value, fields)
	end)
end

function Analytics.spend(player: Player, amount: number, balance: number, sku: string)
	safe(function()
		AnalyticsService:LogEconomyEvent(
			player,
			Enum.AnalyticsEconomyFlowType.Sink,
			"Money",
			amount,
			balance,
			Enum.AnalyticsEconomyTransactionType.Shop.Name,
			sku
		)
	end)
end

function Analytics.earn(player: Player, amount: number, balance: number, transactionType: string, sku: string?)
	safe(function()
		AnalyticsService:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Source, "Money", amount, balance, transactionType, sku)
	end)
end

-- Шаг воронки засчитывается один раз и только по порядку.
function Analytics.onboarding(player: Player, data: { Onboarding: number }, stepName: string)
	local step = table.find(Analytics.OnboardingSteps, stepName)
	if not step or step ~= data.Onboarding + 1 then
		return
	end
	data.Onboarding = step
	safe(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
	end)
end

return Analytics
