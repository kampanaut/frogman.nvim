dofile(os.getenv("CDV_SPEC") .. "/t/fmt.lua")
ROW(":e a", function() vim.cmd('edit a.txt') end)
ROW(":e b", function() vim.cmd('edit b.txt') end)
ROW(":e c", function() vim.cmd('edit c.txt') end)
ROW("<M-f>  (b graduates to secondary)", function() CDV.toggle_secondary() end)
ROW(":e d", function() vim.cmd('edit d.txt') end)
if PART == "use" then
	ROW(":e b  under A  (= <M-f>)", function() CDV.toggle_secondary() end)
	ROW(":e e", function() vim.cmd('edit e.txt') end)
	ROW("<M-f>  (back to d)", function() CDV.toggle_secondary() end)
	ROW("<M-;><M-t>  (on d)", function() CDV.restore_secondary() end)
	ROW("<M-;><M-t>  (again)", function() CDV.restore_secondary() end)
else
	ROW(":e b  under A  (= <M-f>)", function() CDV.toggle_secondary() end)
	ROW(":e d  under A  (= <M-f>)", function() CDV.toggle_secondary() end)
	ROW("<M-;><M-t>  (on d)", function() CDV.restore_secondary() end)
end
ROWS_DONE()
