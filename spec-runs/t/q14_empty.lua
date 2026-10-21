local function step(label, fn) fn() vim.wait(150) print(string.format("  %-46s %s  shown=%s", label, T():gsub(" dtm=.*", ""), SHOWN())) end
step(":e a.txt, :e b.txt, <M-;><M-c> (primary b)", function() vim.cmd('edit a.txt') vim.cmd('edit b.txt') CDV.set_primary() end)
step(":e c.txt", function() vim.cmd('edit c.txt') end)
assert(vim.startswith(vim.fn.getcwd(), os.getenv("CDV_SPEC")))
step("b.txt deleted on disk, then :e d.txt", function() os.remove('b.txt') vim.cmd('edit d.txt') end)
step("<M-;><M-x>  (switch the primary on, 1st press)", function() CDV.toggle_primary() end)
step("<M-;><M-x>  (2nd press)", function() CDV.toggle_primary() end)
step("<M-;><M-f>", function() CDV.jump_to_primary() end)
vim.cmd('qa!')
