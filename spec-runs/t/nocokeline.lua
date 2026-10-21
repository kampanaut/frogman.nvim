package.preload['cokeline.mappings'] = nil
package.loaded['cokeline.mappings'] = nil
local function step(label, fn)
	local ok, err = pcall(fn) vim.wait(150)
	print(string.format("  %-34s %s%s", label, T():gsub(" dtm=.*", ""), ok and "" or ("\n      ERROR " .. tostring(err):gsub(os.getenv("CDV_PLUGIN"), "<plugin>"):sub(1, 140))))
end
step(":e a, :e b, :e c", function() vim.cmd('edit a.txt') vim.cmd('edit b.txt') vim.cmd('edit c.txt') end)
step("<M-f>", function() CDV.toggle_secondary() end)
step("<M-;><M-c>, <M-;><M-f>", function() CDV.set_primary() CDV.jump_to_primary() end)
step("<M-n>  (cycle, no cokeline)", function() CDV.cycle_left() end)
print("  nav state after: " .. N.sm:state())
vim.cmd('qa!')
