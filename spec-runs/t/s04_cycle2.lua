local function setup()
  vim.cmd("e a.txt"); vim.cmd("e b.txt"); vim.cmd("e c.txt"); vim.cmd("e d.txt")
  CDV.toggle_secondary()
  vim.cmd("e e.txt")
end
setup(); FLUSH(); STATE("setup")
-- select an outside buffer: cycle right 3 times -> b
for i=1,3 do TRY("cr", function() CDV.cycle_right() end) end
STATE("cycled to")
TRY("cycle_select", function() CDV.cycle_select() end); STATE("select outside (b)")
-- select the secondary
for i=1,3 do TRY("cr", function() CDV.cycle_right() end) end
STATE("cycled to")
TRY("cycle_select", function() CDV.cycle_select() end); STATE("select")
-- M-f during cycling
TRY("cr", function() CDV.cycle_right() end); STATE("cycling")
TRY("M-f in cycling", function() CDV.toggle_secondary() end); STATE("M-f during cycling")
TRY("cr", function() CDV.cycle_right() end); TRY("cr", function() CDV.cycle_right() end); STATE("cycling more")
TRY("jump_to_primary in cycling", function() CDV.jump_to_primary() end); STATE("jump_to_primary during cycling")
TRY("M-S-f in cycling", function() CDV.toggle_ternary() end); STATE("M-S-f during cycling")
TRY("cycle_select", function() CDV.cycle_select() end); STATE("select")
TRY("cycle_select in normal", function() CDV.cycle_select() end); STATE("cycle_select while normal")
DONE()
