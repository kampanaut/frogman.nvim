-- Invariants (section 4) as property tests over random walks. IDs are the
-- spec's (what-is-cavediver.md, section 7).
--
-- Each walk starts a fresh child, opens a.txt and takes `steps` actions picked
-- by a fixed seed, checking the invariant after every action (Misc.walks).
-- Each test's actions come from the routes the spec names for its invariant.
-- A break fails the case with the walk's seed, step and route.
local Helpers = dofile('tests/helpers.lua')
local Misc = dofile('tests/helpers_misc.lua')
local eq = Helpers.eq
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		post_once = child.stop,
	},
})

-- 30 walks of 25 actions (a.txt, then 24 picked), like the spec's walks.
local WALKS, STEPS = 30, 24

-- The spec's walk actions (spec-runs/all/all_walk.py): :e on five files, <M-f>,
-- <M-S-f>, both restores, cycling picks (X1-X3: one step right, one left, two
-- right, then <M-v>), <M-;><M-c> and <M-;><M-f>, weighted as there.
local function rep(n, list)
	local out = {}
	for _ = 1, n do vim.list_extend(out, list) end
	return out
end
local function join(...)
	local out = {}
	for _, l in ipairs({ ... }) do vim.list_extend(out, l) end
	return out
end
local ACTS = join(rep(2, { 'e a', 'e b', 'e c', 'e d', 'e e' }), rep(4, { '<M-f>' }), rep(3, { '<M-S-f>' }),
	{ '<M-;><M-r>', '<M-;><M-t>', 'X1', 'X2', 'X3', '<M-;><M-c>', '<M-;><M-f>' })
-- Several windows: :vsplit, the previous window, :close.
local MW = join(ACTS, rep(2, { 'vsplit' }), rep(3, { 'wincmd p' }), { 'close' })
-- And cycles left open across a window jump (Y1, Y2).
local MWY = join(MW, { 'Y1', 'Y2' })

local function walk(check, actions, seed, walks)
	local broke = Misc.walks(child, { seed = seed, walks = walks or WALKS, steps = STEPS, actions = actions, check = check })
	if broke then error(broke, 0) end
end

-- I1. Route: <M-f>'s history fill while a cycle in another window holds the
-- history (T198), so several windows and cycles left open across a jump.
-- About 3% of these walks break I1 today (4 of 120, 2 of 60 measured), so
-- this one takes 100 walks.
T['T128 [target] I1: no duplicate among a triquetra\'s current, secondary and ternary'] = function()
	walk('I1', MWY, 1, 100)
end

-- I2. Routes: an empty No Name buffer closed while notes or slots name it, a
-- reopened No Name buffer. :enew and <M-.> are doubled: with them single,
-- about 5% of walks break I2 today (3 of 60 measured), doubled about 12%.
T['T129 [char] I2: every hash referenced anywhere has a path'] = function()
	walk('I2', join(ACTS, rep(2, { 'enew', '<M-.>' }), { 'enew+text', '<M-S-w>' }), 2)
end

-- I3. Route: :vsplit.
T['T130 [char] I3: every triquetra has a history entry'] = function()
	walk('I3', MW, 3)
end

-- I12. Route: a new file, not on disk yet, with a typed line. Cavediver's
-- vim.cmd and nvim_buf_delete calls are checked.
T['T131 [char] I12: no buffer with unsaved changes is wiped by cavediver'] = function()
	walk('I12', join(ACTS, rep(2, { 'new file' }), { '<M-.>', '<M-S-w>' }), 4)
end

-- I13. Routes: healing after a file goes missing switches or closes windows,
-- so several windows and files deleted (and written back) on disk.
T['T132 [char] I13: a slot action switches only the target window\'s buffer'] = function()
	walk('I13', join(MWY, rep(2, { 'rm/mk' }), { '<M-;><M-x>' }), 5)
end

-- Checked after every action that isn't a cycling key or pick, while
-- navigation is normal (the list is frozen on purpose while cycling).
T['T133 [char] I11: ordered.crux is newest first and holds only registered open buffers'] = function()
	walk('I11', join(MWY, { '<M-n>', '<M-m>', '<M-v>', 'enew', '<M-.>', '<M-S-w>', '<M-;><M-x>' }), 6)
end

-- I14. A save after every action, over the one-window, several-window and closing
-- mixes: the save hook is critical, so any throw on cavediver's own data would
-- reach the session manager's save.
T['T334 [char] I14: a save never throws on cavediver\'s own data, over random walks'] = function()
	walk('save', ACTS, 8, 10)
	walk('save', MWY, 9, 10)
	walk('save', join(ACTS, rep(2, { 'enew', '<M-.>' }), { 'enew+text', '<M-S-w>', 'new file' }), 10, 10)
end

-- The spec's single-window walks.
T['T154 [target] no restore throws "Remembered … is the same as current …" (Q13)'] = function()
	walk('restores', ACTS, 7)
end

-- The empty, switched-on queue is set directly (the spec's route to it, a
-- primary file deleted on disk, stops working once missing files stay tracked).
T['T157 [target] I19: <M-;><M-x> on an empty queue that is switched on gives p=[A]on (Q14)'] = function()
	child.setup()
	child.steps({ ':e a' })
	child.lua([[
		local t = require('cavediver.domains.window').data.crux[vim.api.nvim_get_current_win()]
		t.primary_buffer = {}
		t.primary_enabled = true
	]])
	eq(child.primary(), '[]on')
	child.steps({ '<M-;><M-x>' })
	eq(child.primary(), '[a]on')
end

return T
