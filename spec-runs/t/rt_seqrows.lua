-- Rows for a walk's action sequence in $CDV_SEQ (same letters as the walks: e<x> = :e x, F, G, R, S, X1-3, P, J).
dofile(os.getenv("CDV_SPEC") .. "/t/rt_fmt.lua")
local names = { F = "<M-f>", G = "<M-S-f>", R = "<M-;><M-r>", S = "<M-;><M-t>", P = "<M-;><M-c>", J = "<M-;><M-f>",
	X1 = "<M-m> <M-v>", X2 = "<M-n> <M-v>", X3 = "<M-m> <M-m> <M-v>" }
local acts = {
	F = F, G = G, R = RT, S = RS, J = J,
	P = function() CDV.set_primary() end,
	X1 = function() CDV.cycle_right() CDV.cycle_select() end,
	X2 = function() CDV.cycle_left() CDV.cycle_select() end,
	X3 = function() CDV.cycle_right() CDV.cycle_right() CDV.cycle_select() end,
}
for _, a in ipairs(vim.split(os.getenv("CDV_SEQ") or "", " ", { trimempty = true })) do
	if a:sub(1, 1) == "e" and #a == 2 then ROW(":e " .. a:sub(2), E(a:sub(2))) else ROW(names[a] or a, acts[a]) end
end
ROWS_DONE()
