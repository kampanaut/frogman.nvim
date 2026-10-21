-- Item 5: today's <M-f> round trip, then the secondary restore.
local function show(label) FLUSH() P(label, "shown=" .. SHOWN() .. " " .. T()) end
vim.cmd('edit a.txt') vim.cmd('edit b.txt') vim.cmd('edit c.txt')
TRY("<M-f>", function() CDV.toggle_secondary() end); show(":e a, :e b, :e c, <M-f> (graduation)")
TRY("<M-f>", function() CDV.toggle_secondary() end); show("<M-f>")
TRY("<M-f>", function() CDV.toggle_secondary() end); show("<M-f>")
TRY("<M-;><M-t>", function() CDV.restore_secondary() end); show("<M-;><M-t>")
DONE()
