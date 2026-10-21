-- EX rows for a walk's action sequence in $CDV_SEQ (the walk letters, multi-window ones included), under $EX_VIEW.
local view = os.getenv("EX_VIEW")
if view and view ~= "" then require("cavediver.configs").bufferline.history_view = view end
dofile(os.getenv("CDV_SPEC") .. "/t/ex_fmt.lua")
local p = os.getenv("CDV_PLUGIN") or ""
table.insert(ROWS, "-- plugin: " .. (p:match("variants/([^/]+)$") or "today") .. ", history_view = " .. (view or "global"))
local WINS = {}
local function label(w)
	for i, x in ipairs(WINS) do if x == w then return "win" .. i end end
	table.insert(WINS, w); return "win" .. #WINS
end
label(vim.api.nvim_get_current_win())
local function wp()
	local before = vim.api.nvim_get_current_win()
	pcall(vim.cmd, "wincmd p")
	if vim.api.nvim_get_current_win() == before then vim.cmd("wincmd w") end
end
local names = { F = "<M-f>", G = "<M-S-f>", R = "<M-;><M-r>", S = "<M-;><M-t>", P = "<M-;><M-c>", J = "<M-;><M-f>",
	X1 = "<M-m> <M-v>", X2 = "<M-n> <M-v>", X3 = "<M-m> <M-m> <M-v>", SP = ":vsplit", WP = "<C-w>p", CL = ":close",
	Y1 = "<M-m> <C-w>p", Y2 = "<M-n> <C-w>p" }
local acts = {
	F = function() CDV.toggle_secondary() end, G = function() CDV.toggle_ternary() end,
	R = function() CDV.restore_ternary() end, S = function() CDV.restore_secondary() end,
	P = function() CDV.set_primary() end, J = function() CDV.jump_to_primary() end,
	X1 = function() CDV.cycle_right() CDV.cycle_select() end, X2 = function() CDV.cycle_left() CDV.cycle_select() end,
	X3 = function() CDV.cycle_right() CDV.cycle_right() CDV.cycle_select() end,
	SP = function() vim.cmd("vsplit") end, WP = wp,
	CL = function() if #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.cmd("close") end end,
	Y1 = function() CDV.cycle_right() wp() end, Y2 = function() CDV.cycle_left() wp() end,
}
local multi = false
for _, a in ipairs(vim.split(os.getenv("CDV_SEQ") or "", " ", { trimempty = true })) do
	if a == "SP" then multi = true end
	local lab = (a:sub(1, 1) == "e" and #a == 2) and (":e " .. a:sub(2)) or (names[a] or a)
	local f = (a:sub(1, 1) == "e" and #a == 2) and function() vim.cmd("edit " .. a:sub(2) .. ".txt") end or acts[a]
	ROW(lab, f)
	if multi then
		for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do label(w) end
		ROWS[#ROWS] = ROWS[#ROWS]:gsub("^(.-%s%s+)", "%1" .. label(vim.api.nvim_get_current_win()) .. " ", 1)
	end
end
ROWS_DONE()
