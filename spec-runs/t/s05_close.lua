vim.cmd("e a.txt"); vim.cmd("e b.txt"); vim.cmd("e c.txt"); vim.cmd("e d.txt")
CDV.toggle_secondary()  -- s=c
vim.cmd("e e.txt") -- c=e s=c t=d
FLUSH(); STATE("setup"); P("ord", ORD())
-- close the secondary's buffer from elsewhere (bdelete c)
local cb = vim.fn.bufnr("c.txt")
vim.cmd("bdelete " .. cb); STATE(":bdelete c (secondary)"); P("closed", CLOSED()); P("ord", ORD())
vim.cmd("e f.txt"); STATE(":e f (next transition)"); P("closed", CLOSED())
-- now close via the close key
TRY("delete_buffer", function() CDV.delete_buffer() end); STATE("<M-.> on f"); P("closed", CLOSED()); P("ord", ORD())
TRY("reopen_last_closed", function() CDV.reopen_last_closed() end); STATE("reopen_last_closed"); P("closed", CLOSED()); P("ord", ORD())
-- delete a non-most-recent buffer via close key: go to ternary
TRY("M-S-f", function() CDV.toggle_ternary() end); STATE("M-S-f"); P("ord", ORD())
TRY("delete_buffer", function() CDV.delete_buffer() end); STATE("<M-.>"); P("closed", CLOSED()); P("ord", ORD())
DONE()
