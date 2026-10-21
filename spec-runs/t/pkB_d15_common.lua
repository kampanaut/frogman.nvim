-- Item 4 (D15): the cycle's checkpoint as today's live triquetra, or as a copy taken at the cycle's start.
-- MODE "live": today. "copy": right after the cycle starts, cycling_origins[win] is replaced with vim.deepcopy of itself.
-- CASE "swap": <M-S-f> on the start mid-cycle, cycle away, <M-;><M-f>. CASE "close": :bdelete the start mid-cycle, <M-;><M-f>.
local function show(label) FLUSH() P(label, "shown=" .. SHOWN() .. " " .. T() .. " nav=" .. N.sm:state()) end
local win = vim.api.nvim_get_current_win()
local function origin() local o = H.data.cycling_origins[win]; return o and (NAME(o.current_slot) .. (o == W.data.crux[win] and " (live table)" or " (copy)")) or "-" end
vim.cmd('edit a.txt') vim.cmd('edit b.txt') vim.cmd('edit c.txt')
CDV.toggle_secondary()
vim.cmd('edit d.txt') vim.cmd('edit c.txt')
show("setup")
TRY("<M-n>", function() CDV.cycle_left() end)
if MODE == "copy" then H.data.cycling_origins[win] = vim.deepcopy(H.data.cycling_origins[win]) end
show("<M-n>"); P("  origin", origin())
if CASE == "swap" then
	TRY("<M-S-f>", function() CDV.toggle_ternary() end)
	TRY("<M-S-f>", function() CDV.toggle_ternary() end); show("<M-S-f> (back), <M-S-f> (swap on the start)"); P("  origin", origin())
	TRY("<M-n>", function() CDV.cycle_left() end); show("<M-n>")
else
	TRY(":bdelete c", function() vim.cmd('bdelete c.txt') end); show(":bdelete c (the start)"); P("  origin", origin())
end
TRY("<M-;><M-f>", function() CDV.jump_to_primary() end); show("<M-;><M-f>")
TRY("<M-S-f>", function() CDV.toggle_ternary() end); show("<M-S-f>")
TRY("<M-v>", function() CDV.cycle_select() end); show("<M-v>")
DONE()
