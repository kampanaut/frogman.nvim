-- WV: under the window view, the first buffer recorded after entering a window can tie with that window's newest one.
local v = os.getenv("CDV_VIEW"); if v and v ~= "" then require("cavediver.configs").bufferline.history_view = v end
dofile(os.getenv("CDV_SPEC") .. "/t/fmt.lua")
local function times()
	local o = {}
	for _, e in ipairs(H.data.ordered.crux) do table.insert(o, (vim.fn.fnamemodify(vim.api.nvim_buf_get_name(e.buf), ":t"):gsub("%.txt", "")) .. "=" .. e.time) end
	return table.concat(o, " ")
end
local function o(l) table.insert(ROWS, string.format("%-26s shows %s  ordered %s   next index %d", l, SHOWN():gsub("%.txt",""), times(), H.data.history_index)) end
table.insert(ROWS, "view = " .. require("cavediver.configs").bufferline.history_view)
vim.cmd('edit a.txt') o(":e a (win1)")
vim.cmd('edit b.txt') o(":e b (win1)")
vim.cmd('vsplit') o(":vsplit (win2)")
vim.cmd('edit c.txt') o(":e c (win2)")
vim.cmd('edit d.txt') o(":e d (win2)")
vim.cmd('wincmd p') o("<C-w>p (win1)")
vim.cmd('wincmd p') o("<C-w>p (win2)")
vim.cmd('edit e.txt') o(":e e (win2)")
ROWS_DONE()
