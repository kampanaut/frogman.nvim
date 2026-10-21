-- D13: which closed slots survive cleanup, and whether the slot keys reopen them.
local function st(label) P(label, T():gsub(" dtm=.*", "") .. "  closed=[" .. CLOSED() .. "]") end
local function bd(name) vim.cmd("bdelete " .. vim.fn.bufnr(name)) end
-- Part 1: close the secondary while the ternary is open
vim.cmd("e a.txt"); vim.cmd("e b.txt"); vim.cmd("e c.txt")
CDV.toggle_secondary(); vim.cmd("e d.txt"); FLUSH()
st("1 setup")
bd("b.txt"); st("1 :bdelete b (the secondary; ternary c open)")
-- Part 2: close a primary entry while the ternary is open
vim.cmd("e e.txt"); CDV.set_primary(); vim.cmd("e f.txt"); vim.cmd("e a.txt"); FLUSH()
st("2 setup")
bd("e.txt"); st("2 :bdelete e (the primary; ternary f open)")
-- Part 3: the same closes while the ternary is itself closed
CDV.toggle_secondary(); vim.cmd("e c.txt"); FLUSH()
st("3 setup")
bd("a.txt"); st("3 :bdelete a (the ternary)")
bd("f.txt"); st("3 :bdelete f (the secondary; ternary a closed)")
TRY("M-f", function() CDV.toggle_secondary() end); vim.wait(100)
st("3 <M-f>"); P("  shown", SHOWN())
-- Part 4: a closed primary entry, kept only because the ternary is closed, then <M-;><M-f>
vim.cmd("e d.txt"); CDV.set_primary(); vim.cmd("e e.txt"); vim.cmd("e b.txt"); FLUSH()
st("4 setup")
bd("e.txt"); st("4 :bdelete e (the ternary)")
bd("d.txt"); st("4 :bdelete d (the primary; ternary e closed)")
TRY("jump", function() CDV.jump_to_primary() end); vim.wait(100)
st("4 <M-;><M-f>"); P("  shown", SHOWN())
DONE()
