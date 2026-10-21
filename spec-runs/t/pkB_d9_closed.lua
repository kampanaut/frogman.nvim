-- Item 6 (D9 c): a remembered value whose buffer is closed but whose file is on disk.
local function show(label) FLUSH() P(label, "shown=" .. SHOWN() .. " " .. T() .. " closed=[" .. CLOSED() .. "]") end
vim.cmd('edit a.txt') vim.cmd('edit b.txt') vim.cmd('edit c.txt') vim.cmd('edit b.txt'); show(":e a, :e b, :e c, :e b")
TRY(":bdelete a", function() vim.cmd('bdelete a.txt') end); show(":bdelete a")
TRY("<M-;><M-r>", function() CDV.restore_ternary() end); show("<M-;><M-r> on b")
TRY("<M-S-f>", function() CDV.toggle_ternary() end); show("<M-S-f>")
DONE()
