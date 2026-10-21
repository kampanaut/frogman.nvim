local function step(label, fn) local ok, e = pcall(fn) vim.wait(150) print(string.format("  %-30s %s%s", label, T():gsub(" p=%[%]off", ""), ok and "" or ("   ERROR " .. tostring(e):sub(1, 80)))) end
step(":e a, :e b, :e c", function() vim.cmd('edit a.txt') vim.cmd('edit b.txt') vim.cmd('edit c.txt') end)
step("<M-f>  (graduation)", function() CDV.toggle_secondary() end)
step("<M-f>  (swap to b)", function() CDV.toggle_secondary() end)
step("<M-;><M-t>  (restore secondary)", function() CDV.restore_secondary() end)
vim.cmd('qa!')
