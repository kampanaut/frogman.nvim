local function step(label, fn) fn() vim.wait(150) print(string.format("  %-38s %s", label, T())) end
step(":e a.txt, then <M-;><M-c> (primary a)", function() vim.cmd('edit a.txt') CDV.set_primary() end)
step(":e c.txt, :e d.txt, :e e.txt", function() vim.cmd('edit c.txt') vim.cmd('edit d.txt') vim.cmd('edit e.txt') end)
step(":e f.txt  (leave e by navigation)", function() vim.cmd('edit f.txt') end)
step(":e e.txt  (back to e)", function() vim.cmd('edit e.txt') end)
step("<M-;><M-f>  (jump to primary a)", function() CDV.jump_to_primary() end)
step(":e e.txt  (back to e)", function() vim.cmd('edit e.txt') end)
step("<M-;><M-r>  (restore on e)", function() CDV.restore_ternary() end)
vim.cmd('qa!')
