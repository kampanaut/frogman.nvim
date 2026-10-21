-- WV: rt_seq.lua for multi-window walks. Same letters, plus:
--   SP = :vsplit, WP = <C-w>p (falls back to <C-w>w when the previous window is gone), CL = :close (never the last window),
--   Y1/Y2 = <M-m> / <M-n> one step, then <C-w>p: a cycle left open across a window jump.
-- One JSON line per step. The current window's fields are as in rt_seq.lua; w = its label (win1, win2, ... in creation
-- order), nw = number of windows, wins = every window's triquetra, view = the active history view,
-- ordt = the ordered list with its access times.
local seq = vim.split(os.getenv("CDV_SEQ") or "", " ", { trimempty = true })
local WINS = {}
local function label(winid)
	for i, x in ipairs(WINS) do if x == winid then return "win" .. i end end
	table.insert(WINS, winid)
	return "win" .. #WINS
end
local function note_new_windows()
	local ids = vim.api.nvim_tabpage_list_wins(0)
	table.sort(ids)
	for _, w in ipairs(ids) do label(w) end
end
label(vim.api.nvim_get_current_win())
local function m(x)
	local o = {}
	for k, v in pairs(x or {}) do o[NAME(k)] = NAME(v) end
	return o
end
local function tq(winid)
	local t = W.data.crux[winid]
	if not t then return nil end
	return { c = NAME(t.current_slot), s = NAME(t.secondary_slot), t = NAME(t.ternary_slot),
		dtm = m(t.displacement_ternary_map), dsm = m(t.displacement_secondary_map), shown = SHOWN(winid) }
end
local function ordt()
	local o = {}
	for _, e in ipairs(H.data.ordered.crux) do table.insert(o, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(e.buf), ":t") .. "=" .. tostring(e.time)) end
	return table.concat(o, ",")
end
local function snap()
	local cw = vim.api.nvim_get_current_win()
	local t = W.data.crux[cw]
	local wins = {}
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do wins[label(w)] = tq(w) or { none = true } end
	local base = { w = label(cw), nw = #vim.api.nvim_tabpage_list_wins(0), wins = wins,
		view = require("cavediver.configs").bufferline.history_view,
		shown = SHOWN(), nav = N.sm:state(), hist = H.sm:state(), ord = ORD(), ordt = ordt(), closed = CLOSED() }
	if not t then base.none = true return base end
	local p = {}
	for _, h in ipairs(t.primary_buffer or {}) do table.insert(p, NAME(h)) end
	base.c = NAME(t.current_slot); base.s = NAME(t.secondary_slot); base.t = NAME(t.ternary_slot)
	base.dtm = m(t.displacement_ternary_map); base.dsm = m(t.displacement_secondary_map); base.pt = m(t.rt_partner)
	base.p = p; base.pe = t.primary_enabled
	return base
end
local function wp()
	local before = vim.api.nvim_get_current_win()
	pcall(vim.cmd, "wincmd p")
	if vim.api.nvim_get_current_win() == before then vim.cmd("wincmd w") end
end
local acts = {
	F = function() CDV.toggle_secondary() end,
	G = function() CDV.toggle_ternary() end,
	R = function() CDV.restore_ternary() end,
	S = function() CDV.restore_secondary() end,
	P = function() CDV.set_primary() end,
	J = function() CDV.jump_to_primary() end,
	X1 = function() CDV.cycle_right() CDV.cycle_select() end,
	X2 = function() CDV.cycle_left() CDV.cycle_select() end,
	X3 = function() CDV.cycle_right() CDV.cycle_right() CDV.cycle_select() end,
	SP = function() vim.cmd("vsplit") end,
	WP = wp,
	CL = function() if #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.cmd("close") end end,
	Y1 = function() CDV.cycle_right() wp() end,
	Y2 = function() CDV.cycle_left() wp() end,
}
local out = {}
local plugin = os.getenv("CDV_PLUGIN")
for i, a in ipairs(seq) do
	NOTES = {}
	local ok, err = pcall(function()
		if a:sub(1, 1) == "e" and #a == 2 then
			vim.cmd("edit " .. a:sub(2) .. ".txt")
		else
			acts[a]()
		end
	end)
	note_new_windows()
	local notes = {}
	for _, n in ipairs(NOTES) do table.insert(notes, { l = n.level, m = (n.msg:gsub(plugin, "<p>")):sub(1, 200) }) end
	table.insert(out, vim.json.encode({ i = i, a = a, ok = ok, err = (not ok) and (tostring(err):gsub(plugin, "<p>")):sub(1, 200) or nil, notes = notes, st = snap() }))
end
io.stdout:write(table.concat(out, "\n") .. "\n")
vim.cmd("qa!")
