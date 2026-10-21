vim.cmd('edit d.txt') vim.cmd('edit e.txt') vim.cmd('edit x.txt') CDV.toggle_ternary() CDV.restore_ternary() CDV.toggle_ternary() CDV.toggle_ternary() vim.wait(150)
local ok, err = pcall(CDV.restore_ternary) vim.wait(100)
print("  last restore: ok=" .. tostring(ok) .. " " .. tostring(err):gsub("\n.*", ""):sub(1, 160) .. "   " .. T():gsub(" p=.*", ""))
for _, n in ipairs(NOTES) do if n.level and n.level >= 3 then print("  notify: " .. n.msg:sub(1, 140)) end end
vim.cmd('qa!')
