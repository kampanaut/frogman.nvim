dofile(os.getenv("CDV_SPEC") .. "/t/fmt.lua")
local function n(h) return (NAME(h):gsub("%.txt","")) end
local function whist(w)
	local t = {}
	for h, v in pairs(H.data.crux_internals.window[w] or {}) do table.insert(t, {h=h, v=v}) end
	table.sort(t, function(x, y) return x.v > y.v end)
	local o = {} for _, e in ipairs(t) do table.insert(o, n(e.h)) end
	return "{" .. table.concat(o, ",") .. "}"
end
local W1 = vim.api.nvim_get_current_win()
vim.cmd('edit a.txt') vim.cmd('edit b.txt')
vim.cmd('vsplit'); local W2 = vim.api.nvim_get_current_win()
table.insert(ROWS, "after :vsplit          win2 window history " .. whist(W2) .. "   ordered " .. ORD():gsub("%.txt",""))
vim.cmd('wincmd p') vim.cmd('edit c.txt')
CDV.cycle_left()
vim.cmd('wincmd p') vim.wait(150)
table.insert(ROWS, "back in win2 (cycling) win2 window history " .. whist(W2) .. "   ordered " .. ORD():gsub("%.txt","") .. "   ← <M-f> takes ordered[2]")
ROWS_DONE()
