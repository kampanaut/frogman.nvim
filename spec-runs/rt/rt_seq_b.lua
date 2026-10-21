-- WV copy of rt_seq.lua: the same, plus the active history view in every snapshot.
-- Runs the action sequence in $CDV_SEQ (space separated) and prints one JSON line per step.
-- Actions: e<letter> = :edit <letter>.txt, F = <M-f>, G = <M-S-f>, R = restore ternary,
-- S = restore secondary, L/Rt = cycle left/right one step, V = cycle select, P = set primary, J = jump to primary
local seq = vim.split(os.getenv("CDV_SEQ") or "", " ", { trimempty = true })
local function snap()
	local t = W.data.crux[vim.api.nvim_get_current_win()]
	if not t then return { none = true } end
	local function m(x)
		local o = {}
		for k, v in pairs(x or {}) do o[NAME(k)] = NAME(v) end
		return o
	end
	local p = {}
	for _, h in ipairs(t.primary_buffer or {}) do table.insert(p, NAME(h)) end
	return { c = NAME(t.current_slot), s = NAME(t.secondary_slot), t = NAME(t.ternary_slot),
		dtm = m(t.displacement_ternary_map), dsm = m(t.displacement_secondary_map), pt = m(t.rt_partner), p = p, pe = t.primary_enabled,
		shown = SHOWN(), nav = N.sm:state(), hist = H.sm:state(), ord = ORD(), closed = CLOSED(),
		view = require("cavediver.configs").bufferline.history_view }
end
local acts = {
	F = function() CDV.toggle_secondary() end,
	G = function() CDV.toggle_ternary() end,
	R = function() CDV.restore_ternary() end,
	S = function() CDV.restore_secondary() end,
	L = function() CDV.cycle_left() end,
	Rt = function() CDV.cycle_right() end,
	V = function() CDV.cycle_select() end,
	P = function() CDV.set_primary() end,
	J = function() CDV.jump_to_primary() end,
	X1 = function() CDV.cycle_right() CDV.cycle_select() end, -- cycle one step right, pick
	X2 = function() CDV.cycle_left() CDV.cycle_select() end,  -- cycle one step left, pick
	X3 = function() CDV.cycle_right() CDV.cycle_right() CDV.cycle_select() end,
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
	local notes = {}
	for _, n in ipairs(NOTES) do table.insert(notes, { l = n.level, m = (n.msg:gsub(plugin, "<p>")):sub(1, 200) }) end
	table.insert(out, vim.json.encode({ i = i, a = a, ok = ok, err = (not ok) and (tostring(err):gsub(plugin, "<p>")):sub(1, 200) or nil, notes = notes, st = snap() }))
end
io.stdout:write(table.concat(out, "\n") .. "\n")
vim.cmd("qa!")
