-- Item 5 (D8): reaching the secondary by plain navigation. MODE "today", or "write": after each plain :e onto
-- the secondary, simulate <M-f>'s secondary note dsm[left] := arrived (window/routines.lua:496).
local function show(label) FLUSH() P(label, "shown=" .. SHOWN() .. " " .. T()) end
local h = function(f) return H.get_hash_from_buffer(vim.fn.bufnr(f)) end
local function nav_to_secondary(f)
	local t = W.data.crux[vim.api.nvim_get_current_win()]
	local left = t.current_slot
	vim.cmd('edit ' .. f)
	if MODE == "write" then t.displacement_secondary_map[left] = h(f) end
end
vim.cmd('edit a.txt') vim.cmd('edit b.txt') vim.cmd('edit c.txt')
CDV.toggle_secondary()
vim.cmd('edit d.txt'); show("setup")
if PART == "use" then
	nav_to_secondary('b.txt'); show(":e b (the secondary)" .. (MODE == "write" and " + simulated dsm[d] := b" or ""))
	vim.cmd('edit e.txt'); show(":e e")
	TRY("<M-f>", function() CDV.toggle_secondary() end); show("<M-f> (back to d, whose secondary is now e)")
	TRY("<M-;><M-t>", function() CDV.restore_secondary() end); show("<M-;><M-t> on d")
else
	nav_to_secondary('b.txt'); show(":e b (the secondary)" .. (MODE == "write" and " + simulated dsm[d] := b" or ""))
	nav_to_secondary('d.txt'); show(":e d (the secondary)" .. (MODE == "write" and " + simulated dsm[b] := d" or ""))
	TRY("<M-;><M-t>", function() CDV.restore_secondary() end); show("<M-;><M-t> on d")
end
DONE()
