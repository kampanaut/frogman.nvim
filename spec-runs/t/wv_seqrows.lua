-- WV rows for a walk's action sequence in $CDV_SEQ, under the view in $CDV_VIEW, with the window each row is in.
-- Same letters as the walks (t/rt_seqrows.lua), plus SP = :vsplit, WP = <C-w>p, CL = :close, Y1/Y2 = a cycle step then <C-w>p.
-- No wait between rows, like the walks (rt/rt_seq_mw.lua), so the rows reach the walk's states.
local v = os.getenv("CDV_VIEW"); if v and v ~= "" then require("cavediver.configs").bufferline.history_view = v end
dofile(os.getenv("CDV_SPEC") .. "/t/rt_fmt.lua")
ROWS[#ROWS] = ROWS[#ROWS] .. ", " .. require("cavediver.configs").bufferline.history_view .. " view"
local WINS = {}
local function label(w) for i, x in ipairs(WINS) do if x == w then return "win" .. i end end table.insert(WINS, w) return "win" .. #WINS end
label(vim.api.nvim_get_current_win())
local function newwins() local ids = vim.api.nvim_tabpage_list_wins(0) table.sort(ids) for _, w in ipairs(ids) do label(w) end end
local function nm(x) return (x:gsub("%.txt", "")) end
local function note(m)
	local k, case, a, b = m:match("^KT%-t (%S+) (%S+) (%S+) => (%S+)")
	if k then return b == "-" and ("rewrite: " .. a .. ", no older note, so dropped") or ("rewrite: " .. a .. " becomes " .. a:match("^[^>]+") .. ">" .. b) end
	local st = m:match("^WV%-cancel: cycle cancelled, start (%S+)")
	if st then return "cycle cancelled, its window back on " .. st end
	return (m:gsub("\n.*", ""):gsub("%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x", ""):gsub("%s%s+", " "):sub(1, 70))
end
local function R(action, f)
	local ok, err = true, nil
	if f then ok, err = pcall(f) end
	newwins()
	local n = ""
	for _, x in ipairs(NOTES) do n = n .. "  «" .. note(x.msg) .. "»" end
	NOTES = {}
	if not ok then
		local e = tostring(err):gsub("^.-:%d+: ", ""):gsub("This is impossible%. ", ""):gsub(" It should be different for flip flop%.", "")
		n = n .. "  ERROR: " .. e:sub(1, 90)
	end
	if N.sm:state() ~= "normal" then n = n .. "  (still " .. N.sm:state() .. ")" end
	if os.getenv("CDV_TIMES") == "1" then -- the ordered list with its access times, after the action
		local o = {}
		for _, e in ipairs(H.data.ordered.crux) do table.insert(o, (vim.fn.fnamemodify(vim.api.nvim_buf_get_name(e.buf), ":t"):gsub("%.txt", "")) .. "=" .. e.time) end
		n = "   ordered " .. table.concat(o, " ") .. n
	end
	table.insert(ROWS, string.format("%-26s %-5s %s%s", action, label(vim.api.nvim_get_current_win()), TQ(), n))
end
local function wp()
	local before = vim.api.nvim_get_current_win()
	pcall(vim.cmd, "wincmd p")
	if vim.api.nvim_get_current_win() == before then vim.cmd("wincmd w") end
end
local names = { F = "<M-f>", G = "<M-S-f>", R = "<M-;><M-r>", S = "<M-;><M-t>", P = "<M-;><M-c>", J = "<M-;><M-f>",
	X1 = "<M-m> <M-v>", X2 = "<M-n> <M-v>", X3 = "<M-m> <M-m> <M-v>", SP = ":vsplit", WP = "<C-w>p", CL = ":close",
	Y1 = "<M-m> <C-w>p", Y2 = "<M-n> <C-w>p" }
local acts = {
	F = F, G = G, R = RT, S = RS, J = J,
	P = function() CDV.set_primary() end,
	X1 = function() CDV.cycle_right() CDV.cycle_select() end,
	X2 = function() CDV.cycle_left() CDV.cycle_select() end,
	X3 = function() CDV.cycle_right() CDV.cycle_right() CDV.cycle_select() end,
	SP = function() vim.cmd("vsplit") end,
	WP = wp,
	CL = function() if #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.cmd("close") end end,
	Y1 = function() CDV.cycle_right() wp() end,
	Y2 = function() CDV.cycle_left() wp() end,
}
for _, a in ipairs(vim.split(os.getenv("CDV_SEQ") or "", " ", { trimempty = true })) do
	if a:sub(1, 1) == "e" and #a == 2 then R(":e " .. a:sub(2), E(a:sub(2))) else R(names[a] or a, acts[a]) end
end
ROWS_DONE()
