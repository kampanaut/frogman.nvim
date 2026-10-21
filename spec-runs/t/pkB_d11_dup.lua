-- Item 7 (D11): the history fill while history is frozen by a cycle in another window.
local function show(label, w) FLUSH() P(label, "win" .. (w == W1 and "1" or "2") .. " shown=" .. SHOWN(w) .. " " .. T(w) .. " nav=" .. N.sm:state() .. " ordered=" .. ORD()) end
W1 = vim.api.nvim_get_current_win()
vim.cmd('edit a.txt') vim.cmd('edit b.txt')
vim.cmd('vsplit'); W2 = vim.api.nvim_get_current_win(); vim.wait(100); show(":e a, :e b, :vsplit", W2)
vim.cmd('wincmd p'); vim.cmd('edit c.txt'); show("<C-w>p, :e c", W1)
TRY("<M-n>", function() CDV.cycle_left() end); show("<M-n> (cycling, history frozen)", W1)
vim.cmd('wincmd p'); vim.wait(100); show("<C-w>p (to the fresh window)", W2)
TRY("<M-f>", function() CDV.toggle_secondary() end); show("<M-f>", W2)
TRY("<M-f>", function() CDV.toggle_secondary() end); show("<M-f> again", W2)
DONE()
