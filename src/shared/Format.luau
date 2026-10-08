--[[
	Форматирование чисел и времени для интерфейса.
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 950 -> "950", 12500 -> "12.5K", 3400000 -> "3.4M"
function Format.short(value: number): string
	local negative = value < 0
	value = math.abs(value)
	local index = 1
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	local text
	if index == 1 then
		text = if value < 10 and value % 1 ~= 0 then string.format("%.1f", value) else tostring(math.floor(value))
	elseif value < 10 then
		text = string.format("%.2f", math.floor(value * 100) / 100)
	elseif value < 100 then
		text = string.format("%.1f", math.floor(value * 10) / 10)
	else
		text = tostring(math.floor(value))
	end
	if text:find(".", 1, true) then
		-- 1.50 -> 1.5, 2.00 -> 2
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return (if negative then "-" else "") .. text .. SUFFIXES[index]
end

function Format.money(value: number): string
	return "$" .. Format.short(value)
end

function Format.perSecond(value: number): string
	return "$" .. Format.short(value) .. "/с"
end

-- 75 -> "1:15"
function Format.time(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	local minutes = seconds // 60
	return string.format("%d:%02d", minutes, seconds % 60)
end

function Format.seconds(seconds: number): string
	return string.format("%d с", math.max(0, math.ceil(seconds)))
end

-- {r, g, b} из данных -> "#RRGGBB" для RichText
function Format.hex(rgb: { number }): string
	return string.format("#%02X%02X%02X", rgb[1], rgb[2], rgb[3])
end

return Format
