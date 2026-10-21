local orig = vim.cmd
vim.cmd = setmetatable({}, { __call = function(_, c)
  if type(c) == "string" and c:match("^bw") then
    local tb = debug.traceback("", 2)
    local where = {}
    for l in tb:gmatch("cavediver/lua/cavediver/([%w/%-_]+%.lua:%d+)") do table.insert(where, l) end
    P("vim.cmd " .. c, table.concat(where, " <- "))
  end
  return orig(c)
end, __index = orig })
vim.cmd("e a.txt"); vim.cmd("e b.txt")
vim.cmd("e brandnew.txt"); vim.api.nvim_buf_set_lines(0, 0, -1, false, {"typed text"})
STATE("brandnew typed")
vim.cmd("e a.txt"); STATE(":e a")
-- second variant: stay on the new file, re-enter it
vim.cmd("e new2.txt"); vim.api.nvim_buf_set_lines(0, 0, -1, false, {"more"})
local nb = vim.api.nvim_get_current_buf()
vim.cmd("split"); STATE("split on new2"); P("new2 valid", tostring(vim.api.nvim_buf_is_valid(nb)))
DONE()
