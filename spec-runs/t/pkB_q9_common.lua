-- Item 3: a cycling pick of b, an outside buffer that already has a swap note.
-- MODE "today": the code as it is. "note": Q9's write dtm[b] := start, simulated right after the pick.
-- "note_clear": the same write, also clearing dtm[b-swap] as plain navigation does for its own key (A1).
local function show(label) FLUSH() P(label, "shown=" .. SHOWN() .. " " .. T() .. " nav=" .. N.sm:state()) end
local h = function(f) return H.get_hash_from_buffer(vim.fn.bufnr(f)) end
vim.cmd('edit a.txt') vim.cmd('edit b.txt')
TRY("<M-S-f>", function() CDV.toggle_ternary() end); show(":e a, :e b, <M-S-f> (b left by a swap)")
vim.cmd('edit c.txt') vim.cmd('edit d.txt') vim.cmd('edit e.txt'); show(":e c, :e d, :e e")
P("ordered", ORD())
TRY("<M-n>", function() CDV.cycle_left() end); show("<M-n> (to b, outside the slots)")
local start = W.data.crux[vim.api.nvim_get_current_win()].current_slot
TRY("<M-v>", function() CDV.cycle_select() end)
local t = W.data.crux[vim.api.nvim_get_current_win()]
if MODE == "swapnote" then
	t.displacement_ternary_map[h("b.txt") .. "-swap"] = start
elseif MODE ~= "today" then
	t.displacement_ternary_map[h("b.txt")] = start
	if MODE == "note_clear" then t.displacement_ternary_map[h("b.txt") .. "-swap"] = nil end
end
show("<M-v> (pick b)" .. (MODE == "today" and "" or (MODE == "note" and " + simulated dtm[b] := e" or (MODE == "swapnote" and " + simulated dtm[b-swap] := e" or " + simulated dtm[b] := e, dtm[b-swap] := nil"))))
if TOGGLE then
	TRY("<M-S-f>", function() CDV.toggle_ternary() end); show("<M-S-f>")
	TRY("<M-S-f>", function() CDV.toggle_ternary() end); show("<M-S-f> (back on b)")
end
TRY("<M-;><M-r>", function() CDV.restore_ternary() end); show("<M-;><M-r> on b")
TRY("<M-;><M-r>", function() CDV.restore_ternary() end); show("<M-;><M-r> on b again")
DONE()
