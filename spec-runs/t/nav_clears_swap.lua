local function show(label) FLUSH() P(label, T():gsub(" p=%[%]off", ""):gsub(" dsm=.*", "")) end
vim.cmd('edit a.txt') vim.cmd('edit b.txt'); show(":e a, :e b")
TRY("<M-S-f>", function() CDV.toggle_ternary() end); show("<M-S-f>  (leave b by a swap)")
vim.cmd('edit b.txt'); show(":e b     (back on b)")
vim.cmd('edit c.txt'); show(":e c     (leave b by navigation)")
DONE()
