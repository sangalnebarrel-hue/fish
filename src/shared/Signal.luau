--[[
	Минимальный сигнал для связи между сервисами.
	Обработчики вызываются через task.spawn: до первого yield они выполняются синхронно.
]]

export type Connection = { Disconnect: () -> () }

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
}

local Signal = {}

function Signal.new(): Signal
	local handlers: { (...any) -> () } = {}

	local function connect(_self: Signal, handler: (...any) -> ()): Connection
		table.insert(handlers, handler)
		return {
			Disconnect = function()
				local index = table.find(handlers, handler)
				if index then
					table.remove(handlers, index)
				end
			end,
		}
	end

	local function fire(_self: Signal, ...: any)
		for _, handler in table.clone(handlers) do
			task.spawn(handler, ...)
		end
	end

	return { Connect = connect, Fire = fire }
end

return Signal
