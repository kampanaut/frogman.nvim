-- Item 6 (D9 b): a swap note pointing at a closed file that's gone from disk, with a valid plain note behind it.
local function show(label) FLUSH() P(label, "shown=" .. SHOWN() .. " " .. T() .. " closed=[" .. CLOSED() .. "]") end
vim.cmd('edit b.txt') vim.cmd('edit a.txt') vim.cmd('edit c.txt'); show(":e b, :e a, :e c  (plain note dtm[a] := b)")
vim.cmd('edit f.txt') vim.cmd('edit a.txt')
TRY("<M-S-f>", function() CDV.toggle_ternary() end); show(":e f, :e a, <M-S-f>  (swap note dtm[a-swap] := f)")
vim.cmd('edit d.txt') vim.cmd('edit a.txt'); show(":e d, :e a")
assert(vim.startswith(vim.fn.getcwd(), os.getenv("CDV_SPEC")))
TRY(":bdelete f", function() vim.cmd('bdelete f.txt') end) os.remove('f.txt'); show(":bdelete f, f.txt deleted on disk")
TRY("<M-;><M-r>", function() CDV.restore_ternary() end); show("<M-;><M-r> on a")
TRY("<M-;><M-r>", function() CDV.restore_ternary() end); show("<M-;><M-r> on a again")
DONE()
