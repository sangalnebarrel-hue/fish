local Format = Shared.Format

test("Format.short сокращает большие числа", function()
	local cases = {
		{ 0, "0" },
		{ 0.5, "0.5" },
		{ 7, "7" },
		{ 950, "950" },
		{ 1000, "1K" },
		{ 1250, "1.25K" },
		{ 12500, "12.5K" },
		{ 999999, "999K" },
		{ 3400000, "3.4M" },
		{ 25000000, "25M" },
		{ 1.5e9, "1.5B" },
		{ -2000, "-2K" },
	}
	for _, case in cases do
		local got = Format.short(case[1])
		expect(got == case[2], tostring(case[1]) .. " -> " .. got .. ", ожидалось " .. case[2])
	end
end)

test("Format.money и Format.time", function()
	expect(Format.money(12500) == "$12.5K")
	expect(Format.perSecond(45) == "$45/с")
	expect(Format.time(75) == "1:15")
	expect(Format.time(0) == "0:00")
	expect(Format.time(299.2) == "5:00")
	expect(Format.hex({ 255, 0, 16 }) == "#FF0010")
end)
