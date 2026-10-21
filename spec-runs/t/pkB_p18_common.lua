-- Item 1: a swap on the cycle's start, then the same swap outside a cycle. MODE is set by the caller.
local function show(label) FLUSH() P(label, "shown=" .. SHOWN() .. " " .. T() .. " nav=" .. N.sm:state()) end
if MODE == "suppress" then
	-- Simulates "no map writes while cycling": every slot key's map writes are undone while navigation is cycling.
	for _, k in ipairs({ "toggle_ternary", "toggle_secondary", "restore_ternary", "restore_secondary" }) do
		local f = CDV[k]
		CDV[k] = function(...)
			if not N.is_cycling() then return f(...) end
			local t = W.data.crux[vim.api.nvim_get_current_win()]
			local dtm, dsm = vim.deepcopy(t.displacement_ternary_map), vim.deepcopy(t.displacement_secondary_map)
			f(...)
			t.displacement_ternary_map, t.displacement_secondary_map = dtm, dsm
		end
	end
end
vim.cmd('edit a.txt') vim.cmd('edit b.txt') vim.cmd('edit c.txt') vim.cmd('edit d.txt') vim.cmd('edit c.txt')
show("setup")
if MODE == "normal" then
	TRY("<M-S-f>", function() CDV.toggle_ternary() end); show("<M-S-f> (normal mode)")
else
	TRY("<M-n>", function() CDV.cycle_left() end)
	TRY("<M-S-f>", function() CDV.toggle_ternary() end); show("<M-n>, <M-S-f> (back to the start)")
	TRY("<M-S-f>", function() CDV.toggle_ternary() end); show("<M-S-f> (swap on the start, cycling)")
	TRY("<M-v>", function() CDV.cycle_select() end); show("<M-v>")
end
vim.cmd('edit e.txt'); show(":e e")
vim.cmd('edit c.txt'); show(":e c")
TRY("<M-;><M-r>", function() CDV.restore_ternary() end); show("<M-;><M-r> on c")
DONE()
