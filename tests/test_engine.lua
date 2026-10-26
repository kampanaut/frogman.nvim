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
		local function hook(name) return function(_, from, to) table.insert(ran, name .. ':' .. from .. '->' .. to) end end
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

return T
