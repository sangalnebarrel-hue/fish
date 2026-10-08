--[[
	Тег [VIP] в чате для владельцев геймпасса.
]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ChatTags = {}

function ChatTags.start()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local source = message.TextSource
		local speaker = source and Players:GetPlayerByUserId(source.UserId)
		if speaker and speaker:GetAttribute("VIP") then
			local properties = Instance.new("TextChatMessageProperties")
			properties.PrefixText = `<font color="#FFD54A">[VIP]</font> {message.PrefixText}`
			return properties
		end
		return nil :: any
	end
end

return ChatTags
