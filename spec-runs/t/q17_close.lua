local function try(label, setup)
  setup() vim.wait(150)
  local before = vim.fn.expand('%:t') .. " [" .. vim.bo.buftype .. "]"
  local ok, err = pcall(CDV.delete_buffer) vim.wait(200)
  print(string.format("  %-26s on %-22s → ok=%s now on %s %s", label, before, tostring(ok), vim.fn.expand('%:t'), ok and "" or tostring(err):gsub("\n.*",""):sub(1, 90)))
end
vim.cmd('edit a.txt') vim.cmd('edit b.txt')
try(":help, then <M-.>", function() vim.cmd('help help') vim.cmd('only') end)
try(":terminal, then <M-.>", function() vim.cmd('edit b.txt') vim.cmd('terminal') end)
for _, n in ipairs(NOTES) do if n.level and n.level >= 3 then print("    notify: " .. n.msg:sub(1, 100)) end end
vim.cmd('qa!')
