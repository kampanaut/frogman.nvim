-- "Keep the older one": the restore errors (M7, A1, A6-A8, A11, A13, I23).
-- IDs are the spec's (what-is-frogman.md, section 7). Every case here is
-- decided behaviour, built in step 3.
local Helpers = dofile('tests/helpers.lua')
local K = dofile('tests/helpers_keys.lua')
local eq, no_eq = Helpers.eq, Helpers.expect.no_equality
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = child.stop,
	},
})

-- Press a key that must not throw, with no hook failing; returns its messages.
local function clean(key)
	child.messages()
	local ok, err = child.step(key)
	eq({ ok, err }, { true, nil })
	local msgs = K.messages(child)
	eq(K.hook_failures(msgs), {})
	return msgs
end

-- T177's keys up to the restore: the round trip onto the secondary and back.
local ROUND_TRIP = { ':e a', ':e b', ':e c', '<M-f>', '<M-f>', '<M-f>' }

T['T177 [char] the round trip onto the secondary and back: <M-;><M-t> on c says "No secondary relationship found"'] = function()
	-- <M-f> (b graduates), <M-f> (to b), <M-f> (back to c).
	child.steps(ROUND_TRIP)
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	local msgs = clean('<M-;><M-t>')
	eq(K.has(msgs, 'No secondary relationship found'), true)
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	eq(K.dsm(child), 'dsm{b-swap>c b>a c-swap>b}')
end

T["T178 [char] T177's keys, then <M-f> back to b: <M-;><M-t> on b brings back a, then c"] = function()
	child.steps(ROUND_TRIP)
	child.steps({ '<M-;><M-t>', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [b] ⟦c⟧')
	clean('<M-;><M-t>')
	eq(child.slots(), '⦉-⦊ [b] ⟦a⟧')
	clean('<M-;><M-t>')
	eq(child.slots(), '⦉-⦊ [b] ⟦c⟧')
end

-- T179's route: the same round trip by plain navigation.
local NAV_ROUND = { ':e a', ':e b', ':e c', '<M-f>', ':e d', ':e b', ':e d' }

-- The round trip leaves d no secondary note to restore.
T['T179 [char] the round trip by plain navigation: <M-;><M-t> on d says "No secondary relationship found"'] = function()
	child.steps(NAV_ROUND)
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	local msgs = clean('<M-;><M-t>')
	eq(K.has(msgs, 'No secondary relationship found'), true)
end

T["T179 [char] the round trip by plain navigation writes D8's notes along the way (A1's example)"] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	child.steps({ ':e b' })
	eq(child.slots(), '⦉c⦊ [b] ⟦d⟧')
	eq(K.dsm(child), 'dsm{b>a d-swap>b}')
	child.steps({ ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	eq(K.dsm(child), 'dsm{b-swap>d b>a d-swap>b}')
end

T["T180 [char] after a round trip, the buffer's older secondary comes back"] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d', ':e b', ':e e', '<M-f>', '<M-f>', '<M-f>' })
	eq(child.slots(), '⦉b⦊ [d] ⟦e⟧')
	local msgs = clean('<M-;><M-t>')
	eq(child.slots(), '⦉e⦊ [d] ⟦b⟧')
	eq(K.has(msgs, 'Restored secondary slot to'), true)
	eq(K.has(msgs, '(b.txt)'), true)
	clean('<M-;><M-t>')
	eq(child.slots(), '⦉b⦊ [d] ⟦e⟧')
end

T['T181 [char] with nothing older on record, a stale secondary note is dropped'] = function()
	-- <M-f> (d graduates, dsm{d→a}), :e a, <M-f> (to d, whose secondary is now a).
	child.steps({ ':e a', ':e d', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦d⟧')
	eq(K.note(child, 'dsm', 'd'), 'a')
	child.steps({ ':e a', '<M-f>' })
	eq(child.slots(), '⦉c⦊ [d] ⟦a⟧')
	eq(K.note(child, 'dsm', 'd'), nil)
	local msgs = clean('<M-;><M-t>')
	eq(K.has(msgs, 'No secondary relationship found'), true)
end

T['T182 [char] the check on other arrivals, secondary map: at the last :e c the stale note is dropped'] = function()
	-- The primary queue is empty, so <M-;><M-f> acts as <M-f>.
	child.steps({
		':e a', ':e c', '<M-S-f>', '<M-S-f>', ':e d', '<M-f>', '<M-;><M-f>', '<M-;><M-r>',
		'<M-S-f>', '<M-;><M-f>', ':e c',
	})
	eq(child.slots(), '⦉d⦊ [c] ⟦a⟧')
	eq(K.note(child, 'dsm', 'c'), nil)
	local msgs = clean('<M-;><M-t>')
	eq(K.has(msgs, 'No secondary relationship found'), true)
end

T["T183 [char] a stale secondary note is rewritten to the buffer's swap note when that names another buffer"] = function()
	child.steps({ ':e a', ':e e', '<M-f>', ':e d', '<M-;><M-f>', '<M-S-f>', '<M-;><M-f>', '<M-f>' })
	eq(child.slots(), '⦉a⦊ [e] ⟦d⟧')
	-- Pick a (the ternary), then d (the secondary).
	K.cycle_to(child, 'a')
	child.steps({ '<M-v>' })
	K.cycle_to(child, 'd')
	child.steps({ '<M-v>' })
	eq(child.slots(), '⦉e⦊ [d] ⟦a⟧')
	-- d's note d>a named the secondary a; it becomes d's swap note, e.
	eq(K.note(child, 'dsm', 'd'), 'e')
	child.steps({ '<M-f>' })
	K.cycle_to(child, 'd')
	child.steps({ '<M-v>' })
	clean('<M-;><M-t>')
	eq(child.slots(), '⦉a⦊ [d] ⟦e⟧')
	clean('<M-;><M-t>')
	eq(child.slots(), '⦉e⦊ [d] ⟦a⟧')
end

T["T184 [char] graduation clears the graduated buffer's old swap note, so <M-;><M-t> brings back dtm[b]'s buffer (Q3)"] = function()
	-- Secondary empty, ternary b with dtm[b] = a; b's old swap note dsm[b-swap] = d is set directly.
	child.steps({ ':e d', ':e a', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	eq(K.note(child, 'dtm', 'b'), 'a')
	K.set_note(child, 'dsm', 'b-swap', 'd')
	child.steps({ '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	eq(K.note(child, 'dsm', 'b'), 'a')
	eq(K.note(child, 'dsm', 'b-swap'), nil)
	child.steps({ '<M-f>' })
	eq(child.slots(), '⦉-⦊ [b] ⟦c⟧')
	clean('<M-;><M-t>')
	eq(child.slots(), '⦉-⦊ [b] ⟦a⟧')
end

T["T185 [char] where the ternary stays put, a stale ternary note becomes the ternary's own note"] = function()
	child.steps({ ':e a', ':e c', ':e e', ':e b', '<M-f>', ':e c', '<M-S-f>', '<M-f>' })
	eq(child.slots(), '⦉c⦊ [e] ⟦b⟧')
	-- e's note e>c named the ternary c; it becomes c's own note, a.
	eq(K.note(child, 'dtm', 'e'), 'a')
	clean('<M-;><M-r>')
	eq(child.slots(), '⦉a⦊ [e] ⟦b⟧')
	clean('<M-;><M-r>')
	eq(child.slots(), '⦉c⦊ [e] ⟦b⟧')
end

T['T186 [char] where the ternary changes, a stale note with nothing older is dropped (by <M-S-f>)'] = function()
	-- <M-;><M-f> on an empty queue: d graduates.
	child.steps({ ':e a', ':e d', ':e c', '<M-;><M-f>', '<M-f>', ':e a', '<M-S-f>' })
	eq(child.slots(), '⦉a⦊ [d] ⟦c⟧')
	eq(K.note(child, 'dtm', 'd'), nil)
	local msgs = clean('<M-;><M-r>')
	eq(K.has(msgs, 'No ternary relationship found'), true)
end

-- This route goes through navigation's own stale-note check.
T["T186 [char] where the ternary changes, a stale note with nothing older is dropped (by :e d, navigation's own check)"] = function()
	child.steps({ ':e a', ':e d', ':e c', '<M-;><M-f>', '<M-f>', ':e a', ':e d' })
	eq(child.slots(), '⦉a⦊ [d] ⟦c⟧')
	eq(K.note(child, 'dtm', 'd'), nil)
	local msgs = clean('<M-;><M-r>')
	eq(K.has(msgs, 'No ternary relationship found'), true)
end

T["T187 [char] a primary jump uses navigation's second case: b's stale note becomes e, the pre-jump ternary"] = function()
	child.steps({ ':e a', ':e b', '<M-;><M-c>', ':e e', ':e a', '<M-;><M-f>' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	eq(child.primary(), '[b]on')
	eq(K.note(child, 'dtm', 'b'), 'e')
	clean('<M-;><M-r>')
	eq(child.slots(), '⦉e⦊ [b] ⟦-⟧')
	clean('<M-;><M-r>')
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
end

T["T188 [char] where the ternary's own note is the window's secondary, the restore exchanges the ternary and the secondary"] = function()
	child.steps({ ':e a', ':e b', ':e e', '<M-f>', '<M-f>', ':e a', ':e d', ':e e', ':e b', '<M-;><M-t>', ':e e' })
	eq(child.slots(), '⦉b⦊ [e] ⟦a⟧')
	eq(K.notes_for(child, { 'a', 'b' }):match('^dtm%b{}'), 'dtm{a>b b>a}')
	-- Plain navigation onto the secondary: Q6's guard rewrites b's note to e,
	-- and a's note a>b, naming the ternary, becomes the ternary's own note, e.
	child.steps({ ':e a' })
	eq(child.slots(), '⦉b⦊ [a] ⟦e⟧')
	eq(K.note(child, 'dtm', 'b'), 'e')
	eq(K.note(child, 'dtm', 'a'), 'e')
	clean('<M-;><M-r>')
	eq(child.slots(), '⦉e⦊ [a] ⟦b⟧')
	clean('<M-;><M-r>')
	eq(child.slots(), '⦉b⦊ [a] ⟦e⟧')
end

T["T189 [char] (Q13) the slot exchange: b's stale note is dropped and <M-;><M-r> says \"No ternary relationship found\""] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', '<M-f>', '<M-f>', ':e a', '<M-f>' })
	eq(child.slots(), '⦉c⦊ [b] ⟦a⟧')
	eq(K.note(child, 'dtm', 'b'), 'a')
	eq(K.note(child, 'dsm', 'b-swap'), 'c')
	-- c is the ternary, so the two slots exchange.
	clean('<M-;><M-t>')
	eq(child.slots(), '⦉a⦊ [b] ⟦c⟧')
	local msgs = clean('<M-;><M-r>')
	eq(K.has(msgs, 'No ternary relationship found'), true)
end

-- T190: I23 after every action of seeded random walks (see K.walk).
local WALKS, KEYS = 30, 20
-- each walk set's key errors, as T190's walks counted them, for T335 to read (view .. multi → { errors, keys })
local key_errors = {}

local function walks(view, multi, seed0)
	local errors, hook_failures, steps = 0, 0, 0
	local first_keys
	for i = 1, WALKS do
		child.setup({ history_view = view })
		local r = K.walk(child, seed0 + i, KEYS, multi)
		steps = steps + r.steps
		errors, hook_failures = errors + r.errors, hook_failures + r.hook_failures
		if r.errors > 0 and not first_keys then
			first_keys = { walk = i, keys = table.concat(r.actions, ', ') }
		end
		if r.brk then
			local b = r.brk
			error(string.format(
				'I23 broke in walk %d at step %d (window %d): %s holds %s, whose %s note names it\n  keys: %s\n  %s   %s',
				i, r.steps, b.window, b.map == 'dtm' and 'the ternary' or 'the secondary', b.occupant, b.current,
				table.concat(r.actions, ', '), b.slots, b.notes), 0)
		end
	end
	MiniTest.add_note(string.format('%d steps, %d key errors, %d hook failures', steps, errors, hook_failures))
	key_errors[view .. tostring(multi)] = { errors = errors, first = first_keys }
end

T['T190 [char] I23 over random walks: one window, global view'] = function() walks('global', false, 7000) end
T['T190 [char] I23 over random walks: one window, window view'] = function() walks('window', false, 7000) end
T['T190 [char] I23 over random walks: several windows, global view'] = function() walks('global', true, 11000) end
T['T190 [char] I23 over random walks: several windows, window view'] = function() walks('window', true, 11000) end

-- T335: the same walks, and no key raises anything: any route that reaches a throw is a bug (Q13).
local function no_key_errors(view, multi, seed0)
	-- T190's walks are the same walks: their count is read, and they're walked here only when T335 runs alone
	if not key_errors[view .. tostring(multi)] then
		walks(view, multi, seed0)
	end
	local found = key_errors[view .. tostring(multi)]
	if found.errors > 0 then
		error(string.format('%d key error(s), the first in walk %d\n  keys: %s', found.errors, found.first.walk, found.first.keys), 0)
	end
end

T['T335 [char] no key raises over random walks: one window, both views'] = function()
	no_key_errors('global', false, 7000)
	no_key_errors('window', false, 7000)
end
T['T335 [char] no key raises over random walks: several windows, both views'] = function()
	no_key_errors('global', true, 11000)
	no_key_errors('window', true, 11000)
end

T["T192 [char] rename_hash_in_triquetras(old, new) moves dsm[old-swap] to dsm[new-swap] and renames values in both maps"] = function()
	-- Set up directly: a is renamed to x.
	child.steps({ ':e x', ':e b', ':e c', ':e d', ':e a' })
	child.lua([[
		local t = require('frogman.domains.window').data.crux[vim.api.nvim_get_current_win()]
		t.displacement_ternary_map = {}
		t.displacement_secondary_map = {}
	]])
	K.set_note(child, 'dtm', 'c', 'a')
	K.set_note(child, 'dtm', 'a-swap', 'b')
	K.set_note(child, 'dsm', 'a-swap', 'b')
	K.set_note(child, 'dsm', 'a', 'c')
	K.set_note(child, 'dsm', 'd', 'a')
	eq(child.notes(), 'dtm{a-swap>b c>a} dsm{a-swap>b a>c d>a}')
	child.lua('require("frogman.domains.window.data").rename_hash_in_triquetras(...)',
		{ K.hash(child, 'a'), K.hash(child, 'x') })
	eq(child.notes(), 'dtm{c>x x-swap>b} dsm{d>x x-swap>b x>c}')
end

T['T193 [char] (D9) the missing-file rule on the secondary map: <M-;><M-t> says the file is missing, changes no slot, keeps both notes'] = function()
	-- <M-f> (f graduates), <M-f> (to f), :e e, <M-f> (to b).
	child.steps({ ':e f', ':e b', '<M-f>', '<M-f>', ':e e', '<M-f>' })
	eq(child.slots(), '⦉f⦊ [b] ⟦e⟧')
	eq(K.notes_for(child, { 'b' }):match('dsm%b{}'), 'dsm{b-swap>f b>f}')
	child.messages()
	-- :bdelete f, delete f.txt on disk, and press, in one go.
	local ok, err = K.press_after(child, "vim.cmd('bdelete f.txt'); " .. K.rm_code('f'), '<M-;><M-t>')
	eq({ ok, err }, { true, nil })
	local msgs = K.messages(child)
	eq(K.hook_failures(msgs), {})
	no_eq(K.warnings(msgs), {})
	eq(child.slots(), '⦉f⦊ [b] ⟦e⟧')
	eq(K.notes_for(child, { 'b' }):match('dsm%b{}'), 'dsm{b-swap>f b>f}')
end

return T
