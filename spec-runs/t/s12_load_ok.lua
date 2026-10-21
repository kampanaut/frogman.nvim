for _, f in ipairs({"b.txt","c.txt","e.txt"}) do local b = vim.fn.bufadd(f); vim.fn.bufload(b); vim.bo[b].buflisted = true end
vim.cmd("noautocmd edit d.txt")
TRY("load", function() CDV.load_session(vim.fn.getcwd()) end)
STATE("after load"); P("closed", CLOSED()); P("storage", CDV.get_storage_state())
TRY("M-S-f", function() CDV.toggle_ternary() end); STATE("M-S-f")
DONE()
