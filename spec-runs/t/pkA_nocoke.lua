-- Item 0: <M-n> with cokeline not installed. Prints slot strings, navigation and history states, and what <M-n> printed.
package.preload['cokeline.mappings'] = nil
package.loaded['cokeline.mappings'] = nil
local printed = {}
local oprint = print
print = function(...) table.insert(printed, table.concat(vim.tbl_map(tostring, { ... }), " ")) end
local function st(label) P(label, T():gsub(" dtm=.*", "") .. "  nav=" .. N.sm:state() .. " hist=" .. H.sm:state() .. "  shown=" .. SHOWN()) end
vim.cmd("e a.txt"); vim.cmd("e b.txt"); vim.cmd("e c.txt"); FLUSH(); st(":e a, :e b, :e c")
TRY("M-n", function() CDV.cycle_left() end); st("<M-n>")
for _, s in ipairs(printed) do P("  printed", s) end; printed = {}
vim.cmd("e a.txt"); st(":e a while stuck")
P("  ordered history", ORD())
TRY("M-v", function() CDV.cycle_select() end); st("<M-v>")
P("  ordered history", ORD())
print = oprint
DONE()
