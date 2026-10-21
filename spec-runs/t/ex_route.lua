-- EX: the ten-key route of t/i23_route.lua, then two more keys to show what follows (EX_MORE="R S" etc.).
dofile(os.getenv("CDV_SPEC") .. "/t/ex_fmt.lua")
local p = os.getenv("CDV_PLUGIN") or ""
table.insert(ROWS, "-- plugin: " .. (p:match("variants/([^/]+)$") or "today"))
ROW(":e a", function() vim.cmd('edit a.txt') end)
ROW(":e b", function() vim.cmd('edit b.txt') end)
ROW(":e c", function() vim.cmd('edit c.txt') end)
ROW("<M-f>  (b graduates)", function() CDV.toggle_secondary() end)
ROW("<M-f>", function() CDV.toggle_secondary() end)
ROW("<M-f>", function() CDV.toggle_secondary() end)
ROW(":e a", function() vim.cmd('edit a.txt') end)
ROW("<M-f>", function() CDV.toggle_secondary() end)
ROW("<M-;><M-t>", function() CDV.restore_secondary() end)
ROW("<M-;><M-r>", function() CDV.restore_ternary() end)
local more = { R = { "<M-;><M-r>", function() CDV.restore_ternary() end }, S = { "<M-;><M-t>", function() CDV.restore_secondary() end },
	F = { "<M-f>", function() CDV.toggle_secondary() end }, G = { "<M-S-f>", function() CDV.toggle_ternary() end } }
local extra = vim.split(os.getenv("EX_MORE") or "", " ", { trimempty = true })
if #extra > 0 then table.insert(ROWS, "-- then:") end
for _, k in ipairs(extra) do ROW(more[k][1], more[k][2]) end
ROWS_DONE()
