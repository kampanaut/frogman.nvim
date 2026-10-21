-- Item 7 (D11): <M-f> with an empty secondary and no ternary.
local function show(label, w) FLUSH() P(label, "win" .. (w == W1 and "1" or "2") .. " shown=" .. SHOWN(w) .. " " .. T(w) .. " ordered=" .. ORD()) end
W1 = vim.api.nvim_get_current_win()
vim.cmd('edit a.txt')
TRY("<M-f>", function() CDV.toggle_secondary() end); show(":e a, <M-f>  (one buffer in history)", W1)
vim.cmd('edit b.txt'); show(":e b", W1)
vim.cmd('vsplit'); W2 = vim.api.nvim_get_current_win(); vim.wait(100); show(":vsplit (fresh window)", W2)
TRY("<M-f>", function() CDV.toggle_secondary() end); show("<M-f> in the fresh window", W2)
TRY("<M-f>", function() CDV.toggle_secondary() end); show("<M-f> again", W2)
DONE()
