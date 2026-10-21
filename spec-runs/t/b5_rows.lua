dofile(os.getenv("CDV_SPEC") .. "/t/fmt.lua")
local h = function(f) return H.get_hash_from_buffer(vim.fn.bufnr(f)) end
local function plain_to_secondary(f)
	local t = W.data.crux[vim.api.nvim_get_current_win()]
	local left = t.current_slot
	vim.cmd('edit ' .. f)
	if MODE == "write" then t.displacement_secondary_map[left] = h(f) end
end
ROW(":e a", function() vim.cmd('edit a.txt') end)
ROW(":e b", function() vim.cmd('edit b.txt') end)
ROW(":e c", function() vim.cmd('edit c.txt') end)
ROW("<M-f>  (b graduates to secondary)", function() CDV.toggle_secondary() end)
ROW(":e d", function() vim.cmd('edit d.txt') end)
if PART == "use" then
	ROW(":e b  (plain, onto the secondary)" .. (MODE == "write" and " +note" or ""), function() plain_to_secondary('b.txt') end)
	ROW(":e e", function() vim.cmd('edit e.txt') end)
	ROW("<M-f>  (back to d)", function() CDV.toggle_secondary() end)
	ROW("<M-;><M-t>  (on d)", function() CDV.restore_secondary() end)
else
	ROW(":e b  (plain, onto the secondary)" .. (MODE == "write" and " +note" or ""), function() plain_to_secondary('b.txt') end)
	ROW(":e d  (plain, onto the secondary)" .. (MODE == "write" and " +note" or ""), function() plain_to_secondary('d.txt') end)
	ROW("<M-;><M-t>  (on d)", function() CDV.restore_secondary() end)
end
ROWS_DONE()
