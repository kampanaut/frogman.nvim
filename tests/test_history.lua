-- History (M4). IDs are the spec's (what-is-cavediver.md, section 7).
local Helpers = dofile('tests/helpers.lua')
local X = dofile('tests/helpers_engine_nav.lua')
local eq = Helpers.eq
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.setup()
			X.load(child)
		end,
		post_once = child.stop,
	},
})

-- Restart the child with the window view.
local function window_view()
	child.setup({ history_view = 'window' })
	X.load(child)
end

local function enter(win)
	child.lua('vim.api.nvim_set_current_win(...)', { win })
	child.settle()
end

-- The window's own history entry, as a set of file stems, or nil.
local function window_history(win)
	return X.unnil(child.lua([[
		local H = require('cavediver.domains.history')
		local entry = H.data.crux_internals.window[...]
		if entry == nil then return nil end
		local out = {}
		for hash in pairs(entry) do out[_G.CDV_X.name(hash)] = true end
		return out
	]], { win }))
end

T['T15 [char] after visiting a, b, c, ordered.crux is c,b,a'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.ordered(), 'c,b,a')
end

T['T16 [char] with history_view = "window", window 2 ranks its own visits first (s17)'] = function()
	window_view()
	child.steps({ ':e a', ':e b', ':e c' })
	local w1 = X.win(child)
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e d', ':e e' })
	eq(child.ordered(), 'e,d,c,b,a')
	-- the rest of run s17 (M4)
	enter(w1)
	eq(child.ordered(), 'c,b,a,e,d')
	child.steps({ ':e a' })
	eq(child.ordered(), 'a,c,b,e,d')
end

T['T17 [char] closing a window removes its crux_internals.window entry'] = function()
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.steps({ ':e b' })
	local w2 = X.win(child)
	eq(window_history(w2), { b = true })
	child.cmd('close')
	child.settle()
	eq(window_history(w2), nil)
end

-- Under the default (global) view, as in run s16. The window view would give
-- the new window an empty entry on WinEnter for another reason (construct_crux).
T['T18 [char] :vsplit creates the new window\'s history entry along with its triquetra (I3)'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	local w2 = X.win(child)
	eq(child.slots(w2), '⦉-⦊ [b] ⟦-⟧')
	Helpers.expect.no_equality(window_history(w2), nil)
end

T['T19 [target] a visit is recorded in the history of the window that shows the buffer, not the focused one'] = function()
	child.steps({ ':e a' })
	local w1 = X.win(child)
	child.cmd('vsplit')
	child.steps({ ':e b' })
	local w2 = X.win(child)
	-- :e c runs in w1 while w2 keeps the focus
	child.lua('vim.fn.win_execute(..., "edit c.txt")', { w1 })
	child.settle()
	eq(X.win(child), w2)
	eq(child.shown(w1), 'c')
	eq({ w1_has_c = (window_history(w1) or {}).c, w2_has_c = (window_history(w2) or {}).c }, { w1_has_c = true })
end

T['T20 [target] track_buffer(h, t) stores t in the global history'] = function()
	child.steps({ ':e a' })
	local got = child.lua([[
		local H = require('cavediver.domains.history')
		local h = _G.CDV_X.hash('b')
		H.track_buffer(h, 1000)
		return { stored = H.data.crux_internals.global[h], index = H.data.history_index }
	]])
	eq(got.stored, 1000)
end

-- T149: random visits across windows. After every :e, the visited buffer must
-- be strictly first by compare_buffers (a tie counts as a failure).
local WALKS, STEPS, FILES = 30, 20, { 'a', 'b', 'c', 'd', 'e' }

local function walk(view, seed)
	child.setup({ history_view = view })
	X.load(child)
	local rnd = X.rng(seed)
	local keys = { ':e a' }
	child.steps({ ':e a' })
	for _ = 1, STEPS do
		local wins = child.lua('return #vim.api.nvim_tabpage_list_wins(0)')
		local pick = rnd(8)
		local key
		if pick <= 5 then
			key = ':e ' .. FILES[rnd(#FILES)]
		elseif pick == 6 and wins < 3 then
			key = ':vsplit'
		elseif pick == 8 and wins > 1 then
			key = ':close'
		elseif wins > 1 then
			key = ':' .. rnd(wins) .. 'wincmd w'
		else
			key = ':e ' .. FILES[rnd(#FILES)]
		end
		table.insert(keys, key)
		child.step(key)
		if key:match('^:e ') then
			local why = X.leftmost(child)
			if why ~= nil then
				return string.format('seed %d, step %d: %s after %s', seed, #keys, why, table.concat(keys, ', '))
			end
		end
	end
	return nil
end

local function walks(view)
	for seed = 1, WALKS do
		local failure = walk(view, seed)
		if failure then return failure end
	end
	return nil
end

T['T149 [char] random visits across windows, global view: the visited buffer is leftmost'] = function()
	eq(walks('global'), nil)
end

-- Under the window view this half fails today: the view's rebuild ties two buffers
-- (history/routines.lua:191, :194; T197), on a window jump and on :close alike, e.g.
-- :e a, :e b, :vsplit, :close, :e a gives a=4 b=4. It passes once that tie is fixed.
T['T149 [target] random visits across windows, window view: the visited buffer is leftmost'] = function()
	eq(walks('window'), nil)
end

T['T149 [char] the author\'s check (Q4): back into window A, :e e gives e=7 b=6 a=5 d=4 c=3'] = function()
	window_view()
	child.steps({ ':e a', ':e b' })
	local A = X.win(child)
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c', ':e d' })
	enter(A)
	child.steps({ ':e e' })
	eq(X.times(child), 'e=7 b=6 a=5 d=4 c=3')
	eq(X.leftmost(child), nil)
end

return T
