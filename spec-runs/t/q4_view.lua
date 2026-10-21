require('cavediver.configs').bufferline.history_view = "window"
local Hd = require('cavediver.domains.history').data
local function ordered()
  local t = {}
  for _, e in ipairs(H.get_ordered_buffers()) do t[#t+1] = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(e.buf), ":t"):gsub("%.txt$","") .. "=" .. tostring(Hd.crux[H.get_hash_from_buffer(e.buf)]) end
  return table.concat(t, " ")
end
local A = vim.api.nvim_get_current_win()
vim.cmd('edit a.txt') vim.cmd('edit b.txt') vim.wait(100)
vim.cmd('vsplit') local B = vim.api.nvim_get_current_win()
vim.cmd('edit c.txt') vim.cmd('edit d.txt') vim.wait(100)
vim.api.nvim_set_current_win(A) vim.wait(300)
print("  back in window A (shows b):  " .. ordered())
vim.cmd('edit e.txt') vim.wait(300)
print("  then :e e.txt in window A:   " .. ordered())
vim.cmd('qa!')
