local F = require('cavediver.engine')
vim.cmd('edit a.txt'); vim.cmd('edit b.txt')
local function counts()
	local t = {}
	for _, n in ipairs(F:list()) do t[n] = #F:get(n).history end
	return t
end
vim.wait(500, function() return false end)
local before = counts()
vim.wait(10000, function() return false end)
local after = counts()
local lines = {}
for n, c in pairs(after) do table.insert(lines, string.format("  %-14s +%d in 10 s idle", n, c - (before[n] or 0))) end
table.sort(lines)
print("Q21: transitions added while idle, per machine")
print(table.concat(lines, "\n"))
-- Q20: does each machine own its mode table?
local seen = {}
for _, n in ipairs(F:list()) do
	local m = F:get(n)
	print(string.format("Q20: %-14s own table=%s  modes it sees: %s", n, tostring(rawget(m, "transition_modes") ~= nil),
		table.concat(vim.tbl_keys(m.transition_modes), ",")))
end
-- memory cost of history entries
collectgarbage("collect"); local k0 = collectgarbage("count")
local h = {}
for i = 1, 600000 do h[i] = "self->self" end
collectgarbage("collect"); local k1 = collectgarbage("count")
print(string.format("Q21: 600,000 entries cost %.1f MB", (k1 - k0) / 1024))
vim.cmd('qa!')
