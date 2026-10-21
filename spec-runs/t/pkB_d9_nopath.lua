-- Item 6 (D9 a): a remembered value whose path was forgotten (a No Name buffer, emptied, then closed).
local function show(label) FLUSH() P(label, "shown=" .. (SHOWN() == "" and "[No Name]" or SHOWN()) .. " " .. T()) end
vim.cmd('edit a.txt') vim.cmd('enew'); local n = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(n, 0, -1, false, { "scratch" }); show(":e a, :enew, type a line (No Name N)")
vim.cmd('edit b.txt') vim.cmd('edit c.txt'); show(":e b, :e c  (dtm[b] := N)")
vim.api.nvim_buf_set_lines(n, 0, -1, false, {}); vim.bo[n].modified = false
TRY(":bdelete N", function() vim.cmd('bdelete ' .. n) end); show("N emptied, :bdelete N")
P("  path of N still registered", tostring(H.get_filepath_from_hash(W.data.crux[vim.api.nvim_get_current_win()].displacement_ternary_map[H.get_hash_from_buffer(vim.fn.bufnr('b.txt'))]) ~= nil))
vim.cmd('edit b.txt'); show(":e b")
TRY("<M-;><M-r>", function() CDV.restore_ternary() end); show("<M-;><M-r> on b")
DONE()
