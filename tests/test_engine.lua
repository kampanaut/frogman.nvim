-- Engine (M11). IDs are the spec's (what-is-frogman.md, section 7).
-- Each case builds its own machines in the child through the factory.
local Helpers = dofile('tests/helpers.lua')
local eq = Helpers.eq
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = child.stop,
	},
})

T['T1 [char] to() on a transition with no bound hook throws from to() itself'] = function()
	child.messages()
	local got = child.lua([[
		local sm = require('frogman.engine'):create('t1')
		sm:register_state('a')
		sm:register_state('b')
		sm.current_state = 'a'
		-- a hook on b->a only: a->b stays unregistered
		sm:on('b', 'a', 'back', function() end, 1, true)
		local ok, err = pcall(sm.to, sm, 'b')
		return { ok = ok, err = tostring(err), state = sm:state() }
	]])
	eq(got.ok, false)
	Helpers.expect.no_equality(got.err:find("Transition 'a->b' is not registered", 1, true), nil)
	Helpers.expect.no_equality(got.err:find('engine/state-machine.lua:', 1, true), nil)
	eq(got.state, 'a')
	eq(child.messages(), {})
end

T['T2 [char] a failing hook is reported, later hooks still run, and the state still changes'] = function()
	child.messages()
	local got = child.lua([[
		local sm = require('frogman.engine'):create('t2')
		sm:register_state('a')
		sm:register_state('b')
		sm.current_state = 'a'
		local ran = {}
		sm:on('a', 'b', 'breaks', function() error('boom') end, 1, true)
		sm:on('a', 'b', 'after', function() table.insert(ran, 'after') end, 2, true)
		sm:to('b')
		return { ran = ran, state = sm:state() }
	]])
	eq(got.ran, { 'after' })
	eq(got.state, 'b')
	-- the flight recorder's notice of its dump is a message of its own (A26)
	local msgs = vim.tbl_filter(function(m)
		return not m.msg:find("frogman: something that shouldn't happen did", 1, true)
	end, child.messages())
	eq(#msgs, 1)
	eq(msgs[1].level, vim.log.levels.ERROR)
	Helpers.expect.no_equality(msgs[1].msg:find("Hook 'breaks' failed during transition a->b", 1, true), nil)
end

T['T3 [char] sm:state() inside a hook returns the state being left'] = function()
	local got = child.lua([[
		local sm = require('frogman.engine'):create('t3')
		sm:register_state('a')
		sm:register_state('b')
		sm.current_state = 'a'
		local seen
		sm:on('a', 'b', 'look', function() seen = sm:state() end, 1, true)
		sm:to('b')
		return { inside = seen, after = sm:state() }
	]])
	eq(got, { inside = 'a', after = 'b' })
end

T['T4 [char] hooks run in class order; no mode runs only "*" hooks, a mode adds its own'] = function()
	local got = child.lua([[
		local sm = require('frogman.engine'):create('t4')
		sm:register_state('a')
		sm.current_state = 'a'
		sm:register_mode('t4_m1')
		sm:register_mode('t4_m2')
		local ran = {}
		local function hook(name) return function() table.insert(ran, name) end end
		-- registered out of class order, with distinct classes
		sm:on('a', 'a', 'star3', hook('star3'), 3, true)
		sm:on('a', 'a', 'star1', hook('star1'), 1, true)
		sm:on('a', 'a', 'm1_2', hook('m1_2'), 2, true, 't4_m1')
		sm:on('a', 'a', 'm2_0', hook('m2_0'), 0, true, 't4_m2')
		local out = {}
		sm:to('a')
		out.none = ran
		ran = {}
		sm:to('a', {}, 't4_m1')
		out.m1 = ran
		ran = {}
		sm:to('a', {}, 't4_m2')
		out.m2 = ran
		return out
	]])
	eq(got.none, { 'star1', 'star3' })
	eq(got.m1, { 'star1', 'm1_2', 'star3' })
	eq(got.m2, { 'm2_0', 'star1', 'star3' })
end

T['T5 [char] off(from, to, name) removes that hook from that transition and nothing else'] = function()
	local got = child.lua([[
		local sm = require('frogman.engine'):create('t5')
		sm:register_state('a')
		sm:register_state('b')
		sm.current_state = 'a'
		local ran = {}
		local function hook(name) return function(_, _, from, to) table.insert(ran, name .. ':' .. from .. '->' .. to) end end
		sm:on('a', 'b', 'h', hook('h'), 1, true)
		sm:on('b', 'a', 'h', nil, nil, nil)
		sm:on('a', 'b', 'g', hook('g'), 2, true)
		sm:off('a', 'b', 'h')
		sm:to('b')
		sm:to('a')
		return ran
	]])
	eq(got, { 'g:a->b', 'h:b->a' })
end

T['T6 [char] transition modes are shared: a mode registered on one machine works on another (Q20)'] = function()
	local got = child.lua([[
		local E = require('frogman.engine')
		local one = E:create('t6_one')
		local two = E:create('t6_two')
		one:register_state('x')
		one.current_state = 'x'
		two:register_state('y')
		two.current_state = 'y'
		one:register_mode('t6_only_on_one')
		local ran = {}
		local ok_on, err_on = pcall(two.on, two, 'y', 'y', 'named', function() table.insert(ran, 'named') end, 1, true, 't6_only_on_one')
		local ok_to, err_to = pcall(two.to, two, 'y', {}, 't6_only_on_one')
		return {
			ok_on = ok_on, err_on = (not ok_on) and tostring(err_on) or nil,
			ok_to = ok_to, err_to = (not ok_to) and tostring(err_to) or nil,
			ran = ran,
		}
	]])
	eq(got, { ok_on = true, ok_to = true, ran = { 'named' } })
end

T['T7 [char] sm.history keeps every transition: 1,000 transitions, 1,000 entries (Q21)'] = function()
	local got = child.lua([[
		local sm = require('frogman.engine'):create('t7')
		sm:register_state('a')
		sm.current_state = 'a'
		sm:on('a', 'a', 'noop', function() end, 1, true)
		for _ = 1, 1000 do sm:to('a') end
		local all_same = true
		for _, t in ipairs(sm.history) do if t ~= 'a->a' then all_same = false end end
		return { n = #sm.history, all_same = all_same }
	]])
	eq(got, { n = 1000, all_same = true })
end

-- Machine models and instances (M11, decided 2026-10-27) -------------------

-- a model with states a, b and c in the child, under a name of the case's own
local function model_with(name)
	return ([[
		local E = require('frogman.engine')
		local m = E:create('%s')
		m:register_state('a')
		m:register_state('b')
		m:register_state('c')
	]]):format(name)
end

T['T658 [char] two instances of one model move apart, and its hooks run for both'] = function()
	local got = child.lua(model_with('t658') .. [[
		local ran = 0
		m:on('a', 'b', 'count', function() ran = ran + 1 end, 1, true)
		local one, two = m:instantiate('a'), m:instantiate('a')
		one:to('b')
		local names = E:list()
		return { one = one:state(), two = two:state(), ran = ran, listed = vim.tbl_contains(names, 't658'), n = #vim.tbl_filter(function(n) return n:find('t658', 1, true) end, names) }
	]])
	eq(got, { one = 'b', two = 'a', ran = 1, listed = true, n = 1 })
end

T['T659 [char] a hook gets the instance second, then the states'] = function()
	local got = child.lua(model_with('t659') .. [[
		local seen = {}
		m:on('a', 'b', 'look', function(_, instance, from, to) table.insert(seen, { instance = instance, from = from, to = to }) end, 1, true)
		local one = m:instantiate('a')
		one:to('b')
		m.current_state = 'a'
		m:to('b')
		return { first = seen[1].instance == one, states = { seen[1].from, seen[1].to }, built_in = seen[2].instance == m }
	]])
	eq(got, { first = true, states = { 'a', 'b' }, built_in = true })
end

T['T660 [char] an instance\'s first state must be registered'] = function()
	local got = child.lua(model_with('t660') .. [[
		local ok, err = pcall(m.instantiate, m, 'nowhere')
		return { ok = ok, names = tostring(err):find('nowhere', 1, true) ~= nil }
	]])
	eq(got, { ok = false, names = true })
end

T['T661 [char] a transition asked for inside its own instance\'s hooks runs after, linked'] = function()
	local got = child.lua(model_with('t661') .. [[
		m:on('b', 'c', 'noop', function() end, 1, true)
		local inside
		m:on('a', 'b', 'ask', function(_, instance) instance:to('c'); inside = instance:state() end, 1, true)
		local one = m:instantiate('a')
		one:to('b')
		return { inside = inside, after = one:state(), history = one.history }
	]])
	eq(got, { inside = 'a', after = 'c', history = { 'a->b', 'b->c <- a->b' } })
end

T['T662 [char] an abandoned transition drops what it asked for'] = function()
	local got = child.lua(model_with('t662') .. [[
		m:on('b', 'c', 'noop', function() end, 1, true)
		m:on('a', 'b', 'ask', function(_, instance) instance:to('c'); error('boom') end, 1, true)
		m:make_hook_critical('ask')
		local one = m:instantiate('a')
		local ok = pcall(one.to, one, 'b')
		return { ok = ok, state = one:state(), history = one.history }
	]])
	eq(got, { ok = false, state = 'a', history = { 'a->b' } })
end

T['T663 [char] nested transitions stop at a depth of 16, naming the parent and the label'] = function()
	local got = child.lua(model_with('t663') .. [[
		m:set_labeler(function() return 'x.txt' end)
		m:on('a', 'b', 'there', function(_, instance) instance:to('a') end, 1, true)
		m:on('b', 'a', 'back', function(_, instance) instance:to('b') end, 1, true)
		local one = m:instantiate('a')
		local ok, err = pcall(one.to, one, 'b')
		err = tostring(err)
		return { ok = ok, label = err:find('x.txt', 1, true) ~= nil, depth = err:find('16', 1, true) ~= nil }
	]])
	eq(got, { ok = false, label = true, depth = true })
end

T['T664 [char] a failing hook\'s notification names the instance by the labeler'] = function()
	child.messages()
	local got = child.lua(model_with('t664') .. [[
		m:set_labeler(function() return 'x.txt' end)
		m:on('a', 'b', 'breaks', function() error('boom') end, 1, true)
		m:instantiate('a'):to('b')
	]])
	-- the notification itself: the dump's WARN quotes it too
	local said = vim.tbl_filter(function(msg)
		return msg.level == vim.log.levels.ERROR and msg.msg:find("Hook 'breaks' failed during transition a->b of x.txt", 1, true)
	end, child.messages())
	eq(#said, 1)
end

T['T665 [char] an instance\'s switch stops that instance alone, the model\'s every one'] = function()
	local got = child.lua(model_with('t665') .. [[
		m:on('a', 'b', 'noop', function() end, 1, true)
		local one, two = m:instantiate('a'), m:instantiate('a')
		one:disable_transition('a', 'b')
		local ok_one = pcall(one.to, one, 'b')
		two:to('b')
		local three = m:instantiate('a')
		m:disable_transition('a', 'b')
		local ok_three = pcall(three.to, three, 'b')
		return { ok_one = ok_one, one = one:state(), two = two:state(), ok_three = ok_three }
	]])
	eq(got, { ok_one = false, one = 'a', two = 'b', ok_three = false })
end

T['T666 [char] an instance nothing holds isn\'t kept alive by its model'] = function()
	local got = child.lua(model_with('t666') .. [[
		m:instantiate('a')
		collectgarbage(); collectgarbage()
		return next(m.members.a) == nil
	]])
	eq(got, true)
end

T['T667 [char] unregister_state refuses while an instance is in the state'] = function()
	local got = child.lua(model_with('t667') .. [[
		m:on('a', 'b', 'there', function() end, 1, true)
		m:on('b', 'a', 'back', function() end, 1, true)
		local one = m:instantiate('a')
		one:to('b')
		local refused = not pcall(m.unregister_state, m, 'b')
		local kept = m:is_state_registered('b')
		one:to('a')
		local ok = pcall(m.unregister_state, m, 'b')
		return { refused = refused, kept = kept, ok = ok, gone = not m:is_state_registered('b') }
	]])
	eq(got, { refused = true, kept = true, ok = true, gone = true })
end

T['T668 [char] force_state runs no hook, is recorded as forced, and keeps the sets'] = function()
	local got = child.lua(model_with('t668') .. [[
		local ran = false
		m:on('a', 'b', 'would', function() ran = true end, 1, true)
		local one = m:instantiate('a')
		one:force_state('b')
		return { ran = ran, state = one:state(), last = one.history[#one.history], refused = not pcall(m.unregister_state, m, 'b') }
	]])
	eq(got, { ran = false, state = 'b', last = 'a->b (forced)', refused = true })
end

T['T669 [char] an unregistered instance refuses transitions'] = function()
	local got = child.lua(model_with('t669') .. [[
		m:set_labeler(function() return 'x.txt' end)
		m:on('a', 'b', 'noop', function() end, 1, true)
		local one = m:instantiate('a')
		one:unregister()
		local ok, err = pcall(one.to, one, 'b')
		return { ok = ok, label = tostring(err):find('x.txt', 1, true) ~= nil, free = pcall(m.unregister_state, m, 'a') }
	]])
	eq(got, { ok = false, label = true, free = true })
end

T['T844 [char] an instance unregistered inside its own transition stays unregistered'] = function()
	local got = child.lua(model_with('t844') .. [[
		m:on('a', 'b', 'leave', function(_, inst) inst:to('c'); inst:unregister() end, 1, true)
		m:on('b', 'c', 'noop', function() end, 1, true)
		local one = m:instantiate('a')
		local ok = pcall(one.to, one, 'b')
		local member = false
		for _, set in pairs(m.members) do member = member or set[one] == true end
		return { ok = ok, member = member, freed = pcall(m.unregister_state, m, 'b') }
	]])
	eq(got, { ok = true, member = false, freed = true })
end

T['T845 [char] an instance\'s switch reaches a general hook'] = function()
	local got = child.lua(model_with('t845') .. [[
		local ran = 0
		m:on('a', 'b', 'noop', function() end, 1, true)
		table.insert(m.general_hooks, { name = 'audit', func = function() ran = ran + 1 end, enabled = true, type = 'before', class = 0 })
		local one = m:instantiate('a')
		one:disable_hook('audit')
		one:to('b')
		local after_one = ran
		m:instantiate('a'):to('b')
		return { after_one, ran }
	]])
	eq(got, { 0, 1 })
end

T['T846 [char] the labeler is called only for a message'] = function()
	child.messages()
	local got = child.lua(model_with('t846') .. [[
		local calls = 0
		m:set_labeler(function() calls = calls + 1; return 'x.txt' end)
		m:on('a', 'b', 'noop', function() end, 1, true)
		m:on('b', 'c', 'breaks', function() error('boom') end, 1, true)
		local one = m:instantiate('a')
		one:to('b')
		local through = calls
		one:to('c')
		return { through, calls }
	]])
	eq(got, { 0, 1 })
end

-- R13: a hook on a->b asks for c, which isn't registered (or is disabled), then for a. The failed ask
-- drops the one queued after it, so a later to('a') runs b->a alone, once a->a is registered for a
-- stale ask to have something to run.
T['T941 [char] (M11, DESK.md:1047, repro R13) a nested ask that fails drops the asks queued after it'] = function()
	local got = child.lua([[
		local E = require('frogman.engine')
		local out = {}
		for _, kind in ipairs({ 'unregistered', 'disabled' }) do
			local m = E:create('t941_' .. kind)
			m:register_state('a'); m:register_state('b'); m:register_state('c')
			m:on('b', 'a', 'back', function() end, 1, true)
			if kind == 'disabled' then
				m:on('b', 'c', 'over', function() end, 1, true)
				m:disable_transition('b', 'c')
			end
			m:on('a', 'b', 'ask', function(_, inst) inst:to('c'); inst:to('a') end, 1, true)
			local one = m:instantiate('a')
			local ok = pcall(one.to, one, 'b')
			local queued = #one.pending
			m:on('a', 'a', 'stale', function() end, 1, true)
			one:to('a')
			out[kind] = { ok = ok, queued = queued, history = one.history, state = one:state() }
		end
		return out
	]])
	local want = { ok = false, queued = 0, history = { 'a->b', 'b->a' }, state = 'a' }
	eq(got, { unregistered = want, disabled = want })
end

-- R14: twelve hooks of one class, registered in an order no sort by name gives, and two general
-- hooks that run before the rest.
T['T942 [char] (M11, DESK.md:1047, repro R14) hooks of one class run in the order they were registered'] = function()
	local got = child.lua(model_with('t942') .. [[
		local names = { 'k', 'c', 'h', 'a', 'l', 'e', 'j', 'b', 'g', 'd', 'i', 'f' }
		local ran = {}
		for _, n in ipairs(names) do
			m:on('a', 'b', n, function() table.insert(ran, n) end, 1, true)
		end
		for _, n in ipairs({ 'first', 'second' }) do
			table.insert(m.general_hooks, { name = n, func = function() table.insert(ran, n) end, enabled = true, type = 'before', class = 0 })
		end
		m:instantiate('a'):to('b')
		return ran
	]])
	eq(got, { 'first', 'second', 'k', 'c', 'h', 'a', 'l', 'e', 'j', 'b', 'g', 'd', 'i', 'f' })
end

-- The ties DESK.md:1047 lists, each in the order what its hooks read and write needs: the history
-- registered before the window looks for its triquetra, the window kept before the jump's cancels, and
-- the save before the hook that only registers the way back to idle.
T['T943 [char] (M11, DESK.md:1047, repro R14) each tie of the built-in machines runs in its given order'] = function()
	local got = child.lua([[
		local helpers = require('frogman.engine.helpers')
		local history = require('frogman.domains.history')
		local navigation = require('frogman.domains.navigation')
		local storage = require('frogman.domains.storage')
		local function pipeline(from, to, mode, sm, names)
			local order, classes, shared = {}, {}, false
			for _, hook in ipairs(helpers.compute_transition_pipeline(from, to, mode, sm, sm)) do
				if classes[hook.class] then shared = true end
				classes[hook.class] = true
				if vim.tbl_contains(names, hook.name) then table.insert(order, hook.name) end
			end
			return { order = order, shared = shared }
		end
		local h = { 'attach_history_update', 'ensure_curwin_crux' }
		local w = { 'winenter_track_current_window', 'cancel_cycle_on_window_jump', 'cancel_preview_on_window_jump' }
		local s = { 'save_history_on_save', 'back_to_idle' }
		return {
			pipeline('attached', 'attached', history.states.mode.UPDATE, history.sm, h),
			pipeline('detached', 'attached', history.states.mode.UPDATE, history.sm, h),
			pipeline('normal', 'normal', navigation.states.mode.WINENTER, navigation.sm, w),
			pipeline('cycling', 'cycling', navigation.states.mode.WINENTER, navigation.sm, w),
			pipeline('bare', 'saving', '*', storage.sm, s),
		}
	]])
	local h = { order = { 'attach_history_update', 'ensure_curwin_crux' }, shared = false }
	local s = { order = { 'save_history_on_save', 'back_to_idle' }, shared = false }
	eq(got, {
		h, h,
		{ order = { 'winenter_track_current_window', 'cancel_preview_on_window_jump' }, shared = false },
		{ order = { 'winenter_track_current_window', 'cancel_cycle_on_window_jump', 'cancel_preview_on_window_jump' }, shared = false },
		s,
	})
end

T['T944 [char] (M11, DESK.md:1047) enable_transition switches a disabled transition back on'] = function()
	local got = child.lua(model_with('t944') .. [[
		m:on('a', 'b', 'noop', function() end, 1, true)
		local one = m:instantiate('a')
		m:disable_transition('a', 'b')
		local off = pcall(one.to, one, 'b')
		m:enable_transition('a', 'b')
		local on = pcall(one.to, one, 'b')
		return { off = off, on = on, state = one:state() }
	]])
	eq(got, { off = false, on = true, state = 'b' })
end

-- A machine the factory makes starts on an empty table, no state, so the entry for its first state
-- has nothing before the arrow.
T['T945 [char] (M11, DESK.md:1047) a factory machine\'s first force_state leaves its forced entry'] = function()
	local got = child.lua([[
		local E = require('frogman.engine')
		local m = E:create('t945')
		m:register_state('a'); m:register_state('b')
		m:force_state('a')
		m:force_state('b')
		local first = {}
		for _, name in ipairs(E:list()) do
			if not name:find('^t945') and E:get(name).history then first[name] = E:get(name).history[1] end
		end
		return { made = m.history, first = first }
	]])
	eq(got.made, { '->a (forced)', 'a->b (forced)' })
	eq({ history = got.first.history, navigation = got.first.navigation, storage = got.first.storage, loop = got.first.ui_loop },
		{ history = '->attached (forced)', navigation = '->normal (forced)', storage = '->bare (forced)', loop = '->self (forced)' })
	for name, entry in pairs(got.first) do
		eq({ name, entry:match('^%->[%w_]+ %(forced%)$') ~= nil }, { name, true })
	end
end

T['T946 [char] (M11, DESK.md:1047) a hook\'s failure names its transition with its link'] = function()
	child.messages()
	child.lua(model_with('t946') .. [[
		m:set_labeler(function() return 'x.txt' end)
		m:on('b', 'c', 'breaks', function() error('boom') end, 1, true)
		m:on('a', 'b', 'ask', function(_, inst) inst:to('c') end, 1, true)
		m:instantiate('a'):to('b')
	]])
	local said = vim.tbl_filter(function(msg)
		return msg.level == vim.log.levels.ERROR and msg.msg:find("Hook 'breaks' failed during transition b->c <- a->b of x.txt", 1, true)
	end, child.messages())
	eq(#said, 1)
end

T['T947 [char] (M11, A26, DESK.md:1049) a hook\'s failure hands on its instance, and the dump names the handle'] = function()
	local got = child.lua(model_with('t947') .. [[
		m:set_labeler(function() return 'x.txt' end)
		m:on('a', 'b', 'breaks', function() error('boom') end, 1, true)
		local helpers = require('frogman.engine.helpers')
		local before, seen = helpers.on_failure, nil
		helpers.on_failure = function(...) seen = { ... } end
		local one = m:instantiate('a')
		one:to('b')
		helpers.on_failure = before
		return { name = seen[1], instance = seen[3] == one,
			message = (seen[4] or ''):find("Hook 'breaks' failed during transition a->b of x.txt: ", 1, true) ~= nil }
	]])
	eq(got, { name = 'breaks', instance = true, message = true })
	-- a hook bound by hand to the handle model's close, failing as b.txt closes: the dump says it's b.txt's
	child.steps({ ':e a', ':e b' })
	local dumps = child.dump_files()
	child.lua([[require('frogman.domains.history').handles.model:on('open', 'closed', 't947_breaks', function() error('boom') end, 20, true)]])
	child.cmd('bdelete b.txt')
	child.settle(100)
	local fired = child.dumped_since(dumps) or ''
	eq(fired:find("Hook 't947_breaks' failed during transition open->closed of b.txt: ", 1, true) ~= nil, true)
end

T['T670 [char] no state is written directly outside the engine'] = function()
	local found = {}
	for _, path in ipairs(vim.fn.globpath('lua/frogman/domains', '**/*.lua', false, true)) do
		for n, line in ipairs(vim.fn.readfile(path)) do
			if line:find('current_state%s*=') then table.insert(found, path .. ':' .. n) end
		end
	end
	eq(found, {})
end

return T
