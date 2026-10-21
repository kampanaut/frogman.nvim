dofile(os.getenv("CDV_SPEC") .. "/t/fmt.lua")
local W = {}
local function both(label, f)
	local ok, err = true, nil
	if f then ok, err = pcall(f) end
	vim.wait(150)
	local note = ""
	for _, x in ipairs(NOTES) do note = note .. " «" .. x.msg:gsub("\n.*", ""):sub(1, 50) .. "»" end
	NOTES = {}
	if not ok then note = note .. " ERROR: " .. tostring(err):gsub("^.-:%d+: ", ""):sub(1, 60) end
	local cur = vim.api.nvim_get_current_win() == W[1] and "win1" or "win2"
	local function sh(w) return (vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)), ":t"):gsub("%.txt","")) end
	table.insert(ROWS, string.format("%-30s in %s | win1 %s shows %s | win2 %s shows %s | nav=%s%s", label, cur,
		TQ(W[1]):gsub("   dtm.*", ""), sh(W[1]), W[2] and TQ(W[2]):gsub("   dtm.*", "") or "-", W[2] and sh(W[2]) or "-", N.sm:state(), note))
end
W[1] = vim.api.nvim_get_current_win()
vim.cmd('edit a.txt') vim.cmd('edit b.txt')
vim.cmd('vsplit') W[2] = vim.api.nvim_get_current_win() vim.cmd('edit x.txt')
vim.cmd('wincmd p') vim.cmd('edit c.txt')
both("setup")
both("<M-n>  (win1 cycles)", function() CDV.cycle_left() end)
both("<C-w>p  (jump to win2)", function() vim.cmd('wincmd p') end)
both(":e d  (work in win2)", function() vim.cmd('edit d.txt') end)
table.insert(ROWS, "   ordered now: " .. ORD():gsub("%.txt",""))
both("<M-v>  (pressed in win2)", function() CDV.cycle_select() end)
both("<C-w>p  (back to win1)", function() vim.cmd('wincmd p') end)
ROWS_DONE()
