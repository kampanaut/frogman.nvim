vim.cmd("e a.txt"); vim.cmd("e b.txt"); vim.cmd("e c.txt"); vim.cmd("e d.txt")
local w = vim.api.nvim_get_current_win()
local t = W.data.crux[w]
local h = function(f) return H.get_hash_from_buffer(vim.fn.bufnr(f)) end
-- Q6: {c=d s=b t=c} with dtm{c->b}; <M-f>
t.secondary_slot = h("b.txt"); t.ternary_slot = h("c.txt"); t.displacement_ternary_map = { [h("c.txt")] = h("b.txt") }; t.displacement_secondary_map = {}
FLUSH(); STATE("Q6 before")
TRY("M-f", function() CDV.toggle_secondary() end); STATE("Q6 after <M-f>")
-- Guard 2: at A=b with ternary T=d (t), dtm[X=a] = b; :e a
t.secondary_slot = nil; t.ternary_slot = h("d.txt"); t.displacement_ternary_map = { [h("a.txt")] = h("b.txt") }; t.displacement_secondary_map = {}
FLUSH(); STATE("guard2 before")
vim.cmd("e a.txt"); FLUSH(); STATE("guard2 after :e a")
-- Guard 1: s == t
t.secondary_slot = h("c.txt"); t.ternary_slot = h("c.txt")
FLUSH(); STATE("guard1 before")
vim.cmd("e d.txt"); FLUSH(); STATE("guard1 after :e d")
DONE()
