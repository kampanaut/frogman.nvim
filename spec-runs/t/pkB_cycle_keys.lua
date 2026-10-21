-- Items 1 and 2: what the slot keys and the primary key write while cycling.
local function show(label) FLUSH() P(label, "shown=" .. SHOWN() .. " " .. T() .. " nav=" .. N.sm:state()) end
vim.cmd('edit e.txt') CDV.set_primary()
vim.cmd('edit a.txt') vim.cmd('edit b.txt') vim.cmd('edit c.txt')
CDV.toggle_secondary()          -- graduation: s := b
vim.cmd('edit d.txt') vim.cmd('edit c.txt')   -- back to c by its ternary: {c=c s=b t=d}
show("setup")
TRY("<M-n>", function() CDV.cycle_left() end); show("<M-n> (cycled away)")
TRY("<M-;><M-f>", function() CDV.jump_to_primary() end); show("<M-;><M-f> (away: back to the start)")
TRY("<M-;><M-f>", function() CDV.jump_to_primary() end); show("<M-;><M-f> (on the start)")
TRY("<M-S-f>", function() CDV.toggle_ternary() end); show("<M-S-f> (on the start)")
TRY("<M-S-f>", function() CDV.toggle_ternary() end); show("<M-S-f> (on the start again)")
TRY("<M-f>", function() CDV.toggle_secondary() end); show("<M-f> (on the start)")
TRY("<M-;><M-r>", function() CDV.restore_ternary() end); show("<M-;><M-r>")
local R = require('cavediver.domains.window.routines')
local orig = R.reconcile_triquetra
R.reconcile_triquetra = function(w, b) P("  navigation state read inside the pick's reconcile_triquetra", N.sm:state()) return orig(w, b) end
TRY("<M-v>", function() CDV.cycle_select() end); show("<M-v> (pick the start)")
R.reconcile_triquetra = orig
TRY("<M-;><M-f>", function() CDV.jump_to_primary() end); show("<M-;><M-f> (normal mode)")
DONE()
