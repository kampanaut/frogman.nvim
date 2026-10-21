-- WV: does history_view bite? Ordered list seen from each window, under the view given by $CDV_VIEW.
local v = os.getenv("CDV_VIEW"); if v and v ~= "" then require("cavediver.configs").bufferline.history_view = v end
dofile(os.getenv("CDV_SPEC") .. "/t/fmt.lua")
local function o(l) table.insert(ROWS, string.format("%-34s win%d  ordered %s   bufenter=%d", l, vim.fn.winnr(), ORD():gsub("%.txt",""), BE)) BE = 0 end
BE = 0
vim.api.nvim_create_autocmd("BufEnter", { callback = function() BE = BE + 1 end })
table.insert(ROWS, "view = " .. require("cavediver.configs").bufferline.history_view)
vim.cmd('edit a.txt') o(":e a")
vim.cmd('edit b.txt') o(":e b")
vim.cmd('vsplit') o(":vsplit")
vim.cmd('edit c.txt') o(":e c (win2)")
vim.cmd('edit d.txt') o(":e d (win2)")
vim.cmd('wincmd p') o("<C-w>p (to win1)")
vim.cmd('wincmd p') o("<C-w>p (to win2)")
vim.cmd('wincmd p') o("<C-w>p (to win1)")
vim.cmd('edit e.txt') o(":e e (win1)")
vim.cmd('wincmd p') o("<C-w>p (to win2)")
vim.cmd('close') o(":close (win2)")
ROWS_DONE()
