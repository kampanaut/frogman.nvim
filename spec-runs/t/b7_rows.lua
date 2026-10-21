dofile(os.getenv("CDV_SPEC") .. "/t/fmt.lua")
local wins = {}
local function wname() local w = vim.api.nvim_get_current_win() for i, x in ipairs(wins) do if x == w then return "win" .. i end end table.insert(wins, w) return "win" .. #wins end
local function R(action, f) ROW(action, f) ROWS[#ROWS] = ROWS[#ROWS]:gsub("^(" .. string.rep(".", 34) .. ")", "%1" .. wname() .. "  ", 1) end
wname()
if PART == "fill" then
	R(":e a", function() vim.cmd('edit a.txt') end)
	R("<M-f>  (one buffer in history)", function() CDV.toggle_secondary() end)
	R(":e b", function() vim.cmd('edit b.txt') end)
	R(":vsplit  (a fresh window)", function() vim.cmd('vsplit') end)
	R("<M-f>  (nothing to graduate)", function() CDV.toggle_secondary() end)
	R("<M-f>  again", function() CDV.toggle_secondary() end)
else
	R(":e a", function() vim.cmd('edit a.txt') end)
	R(":e b", function() vim.cmd('edit b.txt') end)
	R(":vsplit  (a fresh window)", function() vim.cmd('vsplit') end)
	R("<C-w>p, :e c  (back in win1)", function() vim.cmd('wincmd p') vim.cmd('edit c.txt') end)
	R("<M-n>  (cycling: history frozen)", function() CDV.cycle_left() end)
	R("<C-w>p  (to the fresh window)", function() vim.cmd('wincmd p') end)
	R("<M-f>  (nothing to graduate)", function() CDV.toggle_secondary() end)
	R("<M-f>  again", function() CDV.toggle_secondary() end)
end
ROWS_DONE()
