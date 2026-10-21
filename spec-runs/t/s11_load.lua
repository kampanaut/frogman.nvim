-- simulate a manager restore with events off
vim.cmd("noautocmd edit e.txt"); vim.cmd("noautocmd badd b.txt"); vim.cmd("noautocmd badd c.txt"); vim.cmd("noautocmd badd d.txt")
P("loaded bufs", vim.inspect(vim.tbl_map(function(b) return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t") .. (vim.api.nvim_buf_is_loaded(b) and "(L)" or "(U)") end, vim.api.nvim_list_bufs())):gsub("%s+"," "))
TRY("load", function() CDV.load_session(vim.fn.getcwd()) end)
STATE("after load"); P("closed", CLOSED()); P("storage", CDV.get_storage_state())
DONE()
