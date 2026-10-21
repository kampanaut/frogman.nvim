vim.cmd("e a.txt"); vim.cmd("e b.txt"); CDV.set_primary(); vim.cmd("e c.txt"); vim.cmd("e d.txt")
CDV.toggle_secondary()  -- s=c
vim.cmd("e e.txt") -- c=e s=c t=d p=b
FLUSH(); STATE("setup")
vim.cmd("bdelete " .. vim.fn.bufnr("d.txt")); STATE(":bdelete d (ternary)"); P("closed", CLOSED())
vim.cmd("bdelete " .. vim.fn.bufnr("b.txt")); STATE(":bdelete b (primary)"); P("closed", CLOSED())
vim.cmd("bdelete " .. vim.fn.bufnr("c.txt")); STATE(":bdelete c (secondary, ternary closed)"); P("closed", CLOSED())
TRY("M-S-f", function() CDV.toggle_ternary() end); STATE("M-S-f to closed ternary"); P("closed", CLOSED())
TRY("M-f", function() CDV.toggle_secondary() end); STATE("M-f to closed secondary"); P("closed", CLOSED())
TRY("jump", function() CDV.jump_to_primary() end); STATE("jump_to_primary to closed primary"); P("closed", CLOSED())
DONE()
