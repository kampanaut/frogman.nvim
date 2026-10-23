-- Negative cases: things that must not happen, and bad or impossible actions
-- that are refused or handled without harm. IDs are the spec's
-- (what-is-cavediver.md, section 7, "Negative cases").
local Helpers = dofile('tests/helpers.lua')
local K = dofile('tests/helpers_keys.lua')
local Extra = dofile('tests/helpers_cycling.lua')
local Misc = dofile('tests/helpers_misc.lua')
local Neg = dofile('tests/helpers_negative.lua')
local eq, no_eq = Helpers.eq, Helpers.expect.no_equality
local child = Helpers.new_child()
Extra.attach(child)

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = child.stop,
	},
})

local CYCLING = { nav = 'cycling', hist = 'detached' }
local NORMAL = { nav = 'normal', hist = 'attached' }

local function no_errors()
	eq(Extra.at_least(child.messages()), {})
end

-- Is buffer `buf` (default: the current one) registered?
local function registered(buf)
	return child.lua([[
		return require('cavediver.domains.history').get_hash_from_buffer(... or vim.api.nvim_get_current_buf()) ~= nil
	]], { buf })
end

local function bufnr(stem)
	return child.lua('return vim.fn.bufnr(_G.CDV_TEST.root .. "/" .. ... .. ".txt")', { stem })
end

-- {c=e s=c t=d}, with order e,d,c,b,a (as in test_cycling.lua).
local function ecd()
	child.steps({ ':e a', ':e b', ':e c', ':e d', '<M-f>', ':e e' })
	eq(child.slots(), '⦉d⦊ [e] ⟦c⟧')
	eq(child.ordered(), 'e,d,c,b,a')
end

-- Queue [b,a], switched on; returns the window it belongs to.
local function queue_ba()
	child.steps({ ':e a', '<M-;><M-c>', ':e b', '<M-;><M-c>' })
	eq(child.primary(), '[b,a]on')
	return child.win()
end

-- Open the primary queue window and check it's the one now focused.
local function open_popup()
	child.steps({ '<M-;>F' })
	local w = child.popup()
	eq(w ~= nil, true)
	eq(child.win(), w)
	return w
end

-- A project and a session directory that outlive the children (sessions).
local function shared()
	return { root = Misc.make_project(), session_dir = Misc.make_session_dir() }
end

local function start(s)
	Misc.start(child, { root = s.root, session_dir = s.session_dir })
end

-- Principles -----------------------------------------------------------------

T['T207 [char] (P5) a nofile scratch entered in a tracked window is not registered'] = function()
	child.steps({ ':e a', ':e b' })
	eq(registered(), true)
	child.lua('vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, true))')
	child.settle()
	eq(child.lua('return vim.bo.buftype'), 'nofile')
	eq(registered(), false)
end

-- N is an empty No Name buffer that ends up only in the notes: a key (N>c) and
-- a value (b>N). Wiping it pushes nothing (M5); its path stays only because the
-- notes still name it (I2), so once the notes follow along, nothing names it.
T['T208 [char] (P10, I17) the notes about an empty No Name buffer go once it is wiped'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':enew' })
	local n = child.lua('return vim.api.nvim_get_current_buf()')
	local h = child.lua('return require("cavediver.domains.history").get_hash_from_buffer(...)', { n })
	eq(type(h), 'string')
	child.steps({ ':e b', ':e d' })
	eq(child.slots(), '⦉b⦊ [d] ⟦-⟧')
	eq(#child.refs(h) > 0, true)
	child.cmd('bwipeout ' .. n)
	child.settle()
	eq(child.closed(), '')
	eq(child.refs(h), {})
end

T['T209 [char] (P14) the secondary changes only when you act: navigation elsewhere, cycle steps, a split and a window jump leave it'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	local w1 = child.win()
	local function secondary(w) return child.slots(w):match('⟦(.-)⟧') end
	for _, step in ipairs({ ':e d', ':e e', ':e a' }) do
		child.steps({ step })
		eq(secondary(), 'b')
	end
	-- Steps only, then back to the start and pick it: no slot moves.
	child.steps({ '<M-m>', '<M-m>' })
	eq(child.state(), CYCLING)
	eq(secondary(), 'b')
	child.steps({ '<M-;><M-f>', '<M-v>' })
	eq(child.state(), NORMAL)
	eq(child.slots(), '⦉e⦊ [a] ⟦b⟧')
	child.cmd('vsplit')
	child.settle()
	child.cmd('wincmd p')
	child.settle(300)
	eq(child.win(), w1)
	eq(child.slots(w1), '⦉e⦊ [a] ⟦b⟧')
end

T['T210 [char] (P17) navigation and slot keys in one window leave another window\'s triquetra alone'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d', '<M-;><M-c>' })
	local w1 = child.win()
	eq(child.slots(w1), '⦉c⦊ [d] ⟦b⟧')
	local before = { child.slots(w1), child.notes(w1), child.primary(w1) }
	child.cmd('vsplit')
	child.settle()
	local w2 = child.win()
	child.steps({ ':e e', ':e a', '<M-f>', '<M-f>', '<M-S-f>', ':e b', '<M-;><M-c>', '<M-;><M-r>' })
	no_eq(child.slots(w2), '⦉-⦊ [d] ⟦-⟧')
	eq({ child.slots(w1), child.notes(w1), child.primary(w1) }, before)
	child.cmd('wincmd p')
	child.settle(300)
	eq(child.win(), w1)
	eq({ child.slots(w1), child.notes(w1), child.primary(w1) }, before)
end

-- c's note c>b is on record while c's ternary is empty (graduation took d).
T['T211 [char] (P20) restoring is only ever explicit: an empty ternary stays empty until <M-;><M-r>'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':e d', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦d⟧')
	eq(K.note(child, 'dtm', 'c'), 'b')
	child.settle(300)
	eq(child.slots(), '⦉-⦊ [c] ⟦d⟧')
	child.messages()
	child.steps({ '<M-S-f>' })
	eq(Extra.has(child.messages(), 'No ternary buffer to swap with.'), true)
	eq(child.slots(), '⦉-⦊ [c] ⟦d⟧')
	eq(child.shown(), 'c')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉b⦊ [c] ⟦d⟧')
end

T['T212 [char] (P22, S2) the session file is written with mode 0600'] = function()
	child.steps({ ':e a', ':e b' })
	-- The usual umask, so a file written with default permissions shows.
	child.lua([[
		local ffi = require('ffi')
		pcall(ffi.cdef, 'unsigned int umask(unsigned int mask);')
		ffi.C.umask(18)
	]])
	eq(Misc.save(child), { true })
	local dir = child.lua('return require("cavediver.configs").session_dir')
	local files = Misc.files_in(dir)
	eq(#files, 1)
	eq(child.lua('return vim.fn.getfperm(...)', { dir .. files[1] }), 'rw-------')
end

T['T213 [char] (P24, M6) a save with a No Name current slot leaves the live triquetra as it was'] = function()
	child.steps({ ':e a', ':e b', ':enew' })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "scratch" })')
	child.settle()
	local before = Neg.snapshot(child)
	eq(before.slots:match('^⦉b⦊ %[NONAME_%d+%] ⟦%-⟧$') ~= nil, true)
	eq(Misc.save(child), { true })
	eq(Neg.snapshot(child), before)
	child.settle(300)
	eq(Neg.snapshot(child), before)
end

-- b is closed and outside the slots; its file goes, then the save, in one call
-- so no other pass runs in between.
T['T214 [char] (P24) a save leaves the closed stack as it was, a closed file gone from disk included'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦-⟧')
	child.cmd('bdelete b.txt')
	child.settle()
	eq(child.closed(), 'b')
	local got = child.lua([[
		local T = _G.CDV_TEST
		local function snap() return { slots = T.slots(), notes = T.notes(), closed = T.closed(), ordered = T.ordered() } end
		local before = snap()
		os.remove(T.root .. '/b.txt')
		local ok = pcall(require('cavediver').save_session, vim.fn.getcwd())
		return { ok = ok, before = before, after = snap() }
	]])
	eq(got.ok, true)
	eq(got.after, got.before)
end

T['T215 [target] (P26) with harpoon not installed, navigation, the slot keys and the UI raise nothing'] = function()
	Neg.start(child, { no_harpoon = true })
	eq(child.lua('return (pcall(require, "harpoon"))'), false)
	child.messages()
	local raised = {}
	for _, step in ipairs({ ':e a', ':e b', ':e c', '<M-f>', ':e d', '<M-S-f>', '<M-;><M-c>', '<M-;><M-r>' }) do
		-- Ex commands raise; keys return ok, err.
		local ran, key_ok = pcall(child.step, step)
		if not ran or key_ok == false then table.insert(raised, step) end
	end
	child.settle(400)
	eq(raised, {})
	eq(Extra.at_least(child.messages()), {})
	eq(child.slots(), '⦉d⦊ [c] ⟦b⟧')
end

-- Decisions behind the invariants ----------------------------------------------

-- Two fresh processes, the same steps, so the No Name buffer gets the same
-- buffer number in both.
T['T216 [char] (I16) a No Name id is not reused across sessions'] = function()
	local function noname()
		child.setup()
		child.steps({ ':e a', ':enew' })
		return child.lua([[
			local b = vim.api.nvim_get_current_buf()
			return { buf = b, hash = require('cavediver.domains.history').get_hash_from_buffer(b) }
		]])
	end
	local one, two = noname(), noname()
	eq(one.buf, two.buf)
	eq(type(one.hash), 'string')
	eq(type(two.hash), 'string')
	no_eq(one.hash, two.hash)
end

-- A buffer a plugin makes: entered as buftype "", then turned nofile. It has
-- text, so the next :e doesn't reuse it.
T['T217 [char] (I10, A1) a buffer whose buftype turns nofile after it is entered is not left registered or in a slot'] = function()
	child.steps({ ':e a', ':enew' })
	local n = child.lua('return vim.api.nvim_get_current_buf()')
	local h = child.lua('return require("cavediver.domains.history").get_hash_from_buffer(...)', { n })
	eq(type(h), 'string')
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "plugin text" })')
	child.cmd('setlocal buftype=nofile')
	child.settle()
	child.steps({ ':e b' })
	eq(child.lua('return vim.api.nvim_buf_is_valid(...)', { n }), true)
	eq(registered(n), false)
	eq(Neg.in_slots(child, h), false)
end

-- :copen enters the new quickfix buffer before its buftype is set (DESK:2453).
T['T217 [char] (I10, A2) a :copen quickfix buffer is not left registered, and its window gets no triquetra'] = function()
	child.steps({ ':e a', ':e b' })
	child.lua('vim.fn.setqflist({ { filename = "a.txt", lnum = 1, text = "x" } })')
	child.cmd('copen')
	child.settle(300)
	eq(child.lua('return vim.bo.buftype'), 'quickfix')
	eq(registered(), false)
	eq(child.slots(), 'no triquetra')
end

-- Decided 2026-10-21: a repeated file is refused loudly, like a typo'd path (Q11's partial save).
T['T218 [target] (I18) a repeated file in the primary queue window is refused with an error, and saved once'] = function()
	local w = queue_ba()
	open_popup()
	child.messages()
	child.popup_set({ 'a.txt', 'b.txt', 'a.txt' })
	child.cmd('write')
	child.settle()
	local errors = 0
	for _, m in ipairs(child.messages()) do
		if (m.level or 0) >= vim.log.levels.ERROR then errors = errors + 1 end
	end
	eq(errors >= 1, true)
	eq(child.primary(w), '[a,b]on')
end

T['T219 [char] (I19, Q14) an empty queue that is switched on stays on: navigation, slot keys and UI ticks leave it'] = function()
	child.steps({ ':e a', ':e b' })
	child.lua([[
		local t = require('cavediver.domains.window').data.crux[vim.api.nvim_get_current_win()]
		t.primary_buffer = {}
		t.primary_enabled = true
	]])
	eq(child.primary(), '[]on')
	for _, step in ipairs({ ':e c', '<M-f>', '<M-;><M-f>', ':e a', '<M-S-f>' }) do
		child.steps({ step })
		eq(child.primary(), '[]on')
	end
	child.settle(300)
	eq(child.primary(), '[]on')
end

-- Engine and model -------------------------------------------------------------

-- Decided 2026-10-21: the toggles are built (how they're exposed, key or command, comes later).
T['T220 [target] (M11, D23) the winbar and indicator toggles work at runtime'] = function()
	child.steps({ ':e a', ':e b' })
	child.settle(300)
	eq(child.lua('return vim.wo.winbar ~= ""'), true)
	local got = child.lua([[
		local ui = require('cavediver').ui
		local out = {}
		for _, f in ipairs({ 'hide_winbar', 'show_winbar', 'hide_indicators', 'show_indicators' }) do
			out[f] = pcall(ui[f])
		end
		return out
	]])
	eq(got, { hide_winbar = true, show_winbar = true, hide_indicators = true, show_indicators = true })
	-- Hidden stays hidden through the refresh, and shown comes back.
	child.lua('require("cavediver").ui.hide_winbar()')
	child.settle(300)
	eq(child.lua('return vim.wo.winbar'), '')
	child.lua('require("cavediver").ui.show_winbar()')
	child.settle(300)
	eq(child.lua('return vim.wo.winbar ~= ""'), true)
	child.lua('require("cavediver").ui.hide_indicators()')
	eq(child.lua('return require("cavediver").ui.is_hidden("indicators")'), true)
	child.lua('require("cavediver").ui.show_indicators()')
	eq(child.lua('return require("cavediver").ui.is_hidden("indicators")'), false)
end

T['T221 [char] (M11) unregister_hook(name) removes that hook from its machine, and nothing else, without throwing'] = function()
	local got = child.lua([[
		local E = require('cavediver.engine')
		local one = E:create('t221_one')
		local two = E:create('t221_two')
		local ran = {}
		for _, sm in ipairs({ one, two }) do
			sm:register_state('a')
			sm:register_state('b')
			sm.current_state = 'a'
		end
		local function hook(tag) return function() table.insert(ran, tag) end end
		one:on('a', 'b', 'h', hook('one.h'), 1, true)
		one:on('a', 'b', 'g', hook('one.g'), 2, true)
		two:on('a', 'b', 'h', hook('two.h'), 1, true)
		local ok = pcall(one.unregister_hook, one, 'h')
		one:to('b')
		two:to('b')
		return { ok = ok, ran = ran, reusable = (pcall(one.on, one, 'b', 'a', 'h', hook('one.h2'), 1, true)) }
	]])
	eq(got, { ok = true, ran = { 'one.g', 'two.h' }, reusable = true })
end

T['T222 [char] (M1, D4) hashing a file name runs no shell'] = function()
	local calls = child.lua([[
		local n = 0
		local sys, popen, vsys = vim.fn.system, io.popen, vim.system
		vim.fn.system = function(...) n = n + 1; return sys(...) end
		io.popen = function(...) n = n + 1; return popen(...) end
		vim.system = function(...) n = n + 1; return vsys(...) end
		vim.cmd('edit a.txt')
		vim.cmd('edit b.txt')
		vim.fn.system, io.popen, vim.system = sys, popen, vsys
		return n
	]])
	eq(registered(), true)
	eq(calls, 0)
end

-- Actions --------------------------------------------------------------------------

T['T223 [char] (A1, A3) going back into a window onto its current slot changes no slot and writes no note'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	local w1 = child.win()
	eq(child.slots(w1), '⦉c⦊ [d] ⟦b⟧')
	child.cmd('vsplit')
	child.steps({ ':e e' })
	local w2 = child.win()
	eq(child.slots(w2), '⦉d⦊ [e] ⟦-⟧')
	local before = { child.slots(w1), child.notes(w1), child.slots(w2), child.notes(w2) }
	for _, want in ipairs({ w1, w2, w1 }) do
		child.cmd('wincmd p')
		child.settle()
		eq(child.win(), want)
		eq({ child.slots(w1), child.notes(w1), child.slots(w2), child.notes(w2) }, before)
	end
end

T['T224 [char] (A1) a visit made in another window with win_execute moves that window\'s slots, not the focused one\'s'] = function()
	child.steps({ ':e a', ':e b' })
	local w1 = child.win()
	child.cmd('vsplit')
	child.steps({ ':e c' })
	local w2 = child.win()
	eq(child.slots(w2), '⦉b⦊ [c] ⟦-⟧')
	child.cmd('wincmd p')
	child.settle()
	eq(child.win(), w1)
	eq(child.slots(w1), '⦉a⦊ [b] ⟦-⟧')
	child.lua('vim.fn.win_execute(..., "edit d.txt")', { w2 })
	child.settle()
	eq(child.win(), w1)
	eq(child.shown(w1), 'b')
	eq(child.slots(w1), '⦉a⦊ [b] ⟦-⟧')
	eq(child.slots(w2), '⦉c⦊ [d] ⟦-⟧')
end

T['T225 [char] (A2, M6) windows born untracked (:help, :split | terminal) never get a triquetra'] = function()
	child.lua('vim.o.shell = "sh"')
	child.steps({ ':e a', ':e b' })
	local function check(open, close)
		child.cmd(open)
		child.settle(300)
		local w = child.win()
		eq(child.slots(w), 'no triquetra')
		-- A jump out and back in, and UI ticks.
		child.cmd('wincmd p')
		child.settle()
		child.cmd('wincmd p')
		child.settle(300)
		eq(child.win(), w)
		eq(child.slots(w), 'no triquetra')
		if close then child.cmd(close) end
		child.settle()
	end
	check('help', 'close')
	check('split | terminal', nil)
end

T['T226 [char] (A6, A7, A8) with no triquetra, <M-f>, <M-S-f> and <M-;><M-f> warn "Window with unregistered buffer." and change nothing'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	local w1 = child.win()
	eq(child.slots(w1), '⦉-⦊ [c] ⟦b⟧')
	child.cmd('help')
	child.settle()
	local hw = child.win()
	local hb = child.lua('return vim.api.nvim_get_current_buf()')
	eq(child.slots(hw), 'no triquetra')
	for _, key in ipairs({ '<M-f>', '<M-S-f>', '<M-;><M-f>' }) do
		child.messages()
		local ok, err = child.step(key)
		eq({ key, ok, err }, { key, true, nil })
		eq({ key, Extra.has(child.messages(), 'Window with unregistered buffer.') }, { key, true })
		eq(child.win(), hw)
		eq(child.lua('return vim.api.nvim_get_current_buf()'), hb)
		eq(child.slots(hw), 'no triquetra')
		eq(child.slots(w1), '⦉-⦊ [c] ⟦b⟧')
	end
end

-- b is closed and stays in the ternary (T102); its file is deleted in the same
-- call as the key, before any other pass.
T['T227 [char] (A7, P9) <M-S-f> on a closed ternary whose file is gone says so and keeps the pointer'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('bdelete b.txt')
	child.settle()
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	eq(child.closed(), 'b')
	child.messages()
	local ok, err = K.press_after(child, K.rm_code('b'), '<M-S-f>')
	eq({ ok, err }, { true, nil })
	local msgs = K.messages(child)
	eq(K.hook_failures(msgs), {})
	no_eq(K.warnings(msgs), {})
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
end

T['T228 [char] (A11, D9) a restore switches no buffer and reopens nothing: a closed hash waits in the slot until <M-S-f> uses it'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':e d', ':e b' })
	eq(child.slots(), '⦉d⦊ [b] ⟦-⟧')
	eq(K.note(child, 'dtm', 'b'), 'a')
	child.cmd('bdelete a.txt')
	child.settle()
	eq(child.closed(), 'a')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	eq(child.shown(), 'b')
	eq(child.lua('return vim.fn.bufloaded(_G.CDV_TEST.root .. "/a.txt")'), 0)
	eq(child.closed(), 'a')
	child.settle(300)
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	child.steps({ '<M-S-f>' })
	eq(child.shown(), 'a')
	eq(child.slots(), '⦉b⦊ [a] ⟦-⟧')
	eq(child.closed(), '')
end

-- Cycling in the only window, then a jump into a float or into :help.
local function cycle_then(enter)
	child.steps({ ':e a', ':e b', ':e c' })
	local w1 = child.win()
	eq(child.slots(w1), '⦉b⦊ [c] ⟦-⟧')
	eq(child.ordered(), 'c,b,a')
	child.steps({ '<M-m>' })
	eq(child.shown(w1), 'b')
	eq(child.state(), CYCLING)
	enter()
	child.settle(200)
	no_eq(child.win(), w1)
	eq(child.shown(w1), 'c')
	eq(child.slots(w1), '⦉b⦊ [c] ⟦-⟧')
	eq(child.state(), NORMAL)
	eq(child.ordered(), 'c,b,a')
end

T['T229 [char] (A12) a jump into a float cancels the cycle, and nothing is recorded'] = function()
	cycle_then(function()
		child.lua([[
			local b = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_open_win(b, true, { relative = 'editor', row = 1, col = 1, width = 30, height = 5 })
		]])
	end)
end

T['T229 [char] (A12) a jump into :help cancels the cycle, and nothing is recorded'] = function()
	cycle_then(function() child.cmd('help') end)
end

T['T230 [char] (A13) a pick of an outside buffer or of the ternary writes no secondary note'] = function()
	ecd()
	local dsm = K.dsm(child)
	child.steps({ '<M-n>', '<M-n>' })
	eq(child.shown(), 'b')
	child.steps({ '<M-v>' })
	eq(child.slots(), '⦉d⦊ [b] ⟦c⟧')
	eq(K.dsm(child), dsm)
	K.cycle_to(child, 'd')
	child.steps({ '<M-v>' })
	eq(child.slots(), '⦉b⦊ [d] ⟦c⟧')
	eq(K.dsm(child), dsm)
end

T['T231 [char] (A14, Q7) <M-;><M-f> while cycling on the start announces the origin again and changes nothing'] = function()
	ecd()
	child.steps({ '<M-m>', '<M-n>' })
	eq(child.shown(), 'e')
	eq(child.state(), CYCLING)
	local before = { child.slots(), child.notes(), child.shown(), child.ordered() }
	for _ = 1, 2 do
		child.messages()
		child.steps({ '<M-;><M-f>' })
		eq(Extra.has(child.messages(), 'Returned to cycling origin buffer'), true)
		eq({ child.slots(), child.notes(), child.shown(), child.ordered() }, before)
		eq(child.state(), CYCLING)
	end
end

T['T232 [target] (A17) <M-,> skips a previous window whose filetype is neominimap'] = function()
	child.steps({ ':e a' })
	local w1 = child.win()
	child.cmd('vsplit')
	child.steps({ ':e b' })
	local w2 = child.win()
	child.lua('vim.bo[vim.api.nvim_win_get_buf(...)].filetype = "neominimap"', { w1 })
	child.messages()
	child.steps({ '<M-,>' })
	eq(child.win(), w2)
	eq(Extra.has(child.messages(), 'No valid previous window to toggle to.'), true)
end

T['T233 [char] (A18) with no triquetra, <M-;>F says "No triquetra found for current window." and opens no window'] = function()
	child.steps({ ':e a', '<M-;><M-c>' })
	eq(child.primary(), '[a]on')
	child.cmd('help')
	child.settle()
	eq(child.slots(), 'no triquetra')
	child.messages()
	child.steps({ '<M-;>F' })
	eq(Extra.has(child.messages(), 'No triquetra found for current window.'), true)
	eq(child.popup(), nil)
	eq(child.floats(), {})
end

-- The help file is loaded, readable and untracked; NONAME_999 was never a
-- No Name buffer cavediver knew.
T['T234 [char] (A18, Q11) the pop-up rejects an untracked buffer and an unknown No Name, drops a blank line, and keeps the good lines'] = function()
	local w = queue_ba()
	child.cmd('help')
	child.settle()
	local help = child.lua('return vim.api.nvim_buf_get_name(0)')
	eq(child.lua('return vim.fn.filereadable(...)', { help }), 1)
	child.cmd('wincmd p')
	child.settle()
	eq(child.win(), w)
	open_popup()
	child.messages()
	child.popup_set({ 'a.txt', '', help, 'NONAME_999', 'b.txt' })
	child.cmd('write')
	child.settle()
	eq(child.primary(w), '[a,b]on')
	local errors = Extra.at_least(child.messages())
	eq(#errors, 1)
	eq(errors[1]:find(help, 1, true) ~= nil, true)
	eq(errors[1]:find('NONAME_999', 1, true) ~= nil, true)
end

-- Decided 2026-10-21: a relative path is resolved against the current directory, as :e does.
T['T235 [target] (A18) a relative path in the primary queue window is resolved: ./b.txt becomes b, shown as b.txt'] = function()
	local w = queue_ba()
	open_popup()
	child.popup_set({ './b.txt', 'a.txt' })
	local wrote = pcall(child.cmd, 'write')
	child.settle()
	eq(wrote, true)
	eq(Neg.queue_holes(child, w), 0)
	eq(child.primary(w), '[b,a]on')
	-- The pop-up redraws each entry by its shortest unique name.
	eq(child.popup_lines(), { 'b.txt', 'a.txt' })
end

T['T236 [target] (A5) closing another window first does not stop the pop-up\'s buffer going when the pop-up closes, and it opens again'] = function()
	child.steps({ ':e a', '<M-;><M-c>' })
	child.cmd('vsplit')
	child.settle()
	child.cmd('close')
	child.settle()
	open_popup()
	local buf = child.lua('return vim.api.nvim_get_current_buf()')
	eq(child.lua('return vim.bo.filetype'), 'cavediver-primary-buffer-history')
	child.cmd('close')
	child.settle(300)
	eq(child.popup(), nil)
	eq(child.lua('return vim.api.nvim_buf_is_valid(...)', { buf }), false)
	-- And the pop-up opens again (today: E95, a buffer with this name already exists).
	local ok, err = child.step('<M-;>F')
	eq({ ok, err }, { true, nil })
	eq(child.lua('return vim.bo.filetype'), 'cavediver-primary-buffer-history')
end

-- One tracked buffer only, so nothing is left to land on: Neovim puts an empty
-- buffer in the window, read in the same call as the delete.
-- The rest of A19's landing order is T111's.
T['T237 [char] (A19) with nothing left to land on, the window keeps Neovim\'s empty buffer and no :enew runs'] = function()
	child.steps({ ':e a' })
	local got = child.lua([[
		vim.cmd('bdelete a.txt')
		return { buf = vim.api.nvim_get_current_buf(), n = #vim.api.nvim_list_bufs() }
	]])
	child.settle(300)
	eq(child.lua('return vim.api.nvim_get_current_buf()'), got.buf)
	eq(#child.lua('return vim.api.nvim_list_bufs()'), got.n)
end

-- The decided move (DESK:1924): no ghost on the closed stack, and the No Name's notes follow to the new name.
T['T238 [char] (A20) :w name on a No Name buffer is a move: no ghost on the closed stack, and its notes follow'] = function()
	child.steps({ ':e a', ':enew' })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "draft" })')
	child.steps({ ':e b', ':buffer #' })
	child.settle()
	eq(child.closed(), '')
	-- The No Name buffer now carries a note: its ternary was a.
	eq(child.notes():find('NONAME_%d+>a') ~= nil, true)
	child.cmd('write new.txt')
	child.settle(300)
	eq(child.lua('return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")'), 'new.txt')
	eq(child.closed(), '')
	eq(child.notes():find('new>a', 1, true) ~= nil, true)
	eq(child.notes():find('?', 1, true), nil)
end

-- b (the secondary) and c (the ternary) are open but hidden; their files go.
T['T239 [char] (A21) a secondary and a ternary whose files are deleted while their buffers are open stay in their slots'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	child.lua(K.rm_code('b') .. '; ' .. K.rm_code('c'))
	child.settle(300)
	child.lua('require("cavediver.domains.history").cleanup_system()')
	child.settle(300)
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	eq({ registered(bufnr('b')), registered(bufnr('c')) }, { true, true })
end

T['T240 [char] (A25) disable() clears the cavediver augroup and stops the timers, and nothing is tracked after'] = function()
	child.steps({ ':e a', ':e b' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	local got = child.lua([[
		local cd = require('cavediver')
		if type(cd.disable) ~= 'function' then return { disable = type(cd.disable) } end
		local ok = pcall(cd.disable)
		local okg, aus = pcall(vim.api.nvim_get_autocmds, { group = 'cavediver' })
		return { disable = 'function', ok = ok, autocmds = okg and #aus or 0 }
	]])
	if got.disable == 'function' then got.timers = Neg.repeating_timers(child) end
	eq(got, { disable = 'function', ok = true, autocmds = 0, timers = 0 })
	child.steps({ ':e c' })
	child.settle(300)
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	eq(child.ordered(), 'b,a')
end

-- Text typed in insert mode, then the restore assertion (c's secondary note set
-- to name the secondary by hand, as T200 does). Whatever the dump looks like,
-- the typed keys aren't steps in it.
T['T241 [target] (A26) the flight recorder records keymap actions and events, never raw keystrokes'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	child.lua([[vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('iQZQZQZ<Esc>', true, false, true), 'xt', false)]])
	child.settle()
	child.lua([[
		local t = require('cavediver.domains.window').data.crux[vim.api.nvim_get_current_win()]
		t.displacement_secondary_map[t.current_slot .. '-swap'] = nil
		t.displacement_secondary_map[t.current_slot] = t.secondary_slot
	]])
	local files_before = child.dumps()
	local bufs_before = child.lua('return vim.api.nvim_list_bufs()')
	local ok = child.step('<M-;><M-t>')
	eq(ok, false)
	child.settle(200)
	local texts = {}
	for _, f in ipairs(Extra.new_files(files_before, child.dumps())) do
		table.insert(texts, table.concat(child.lua('return vim.fn.readfile(...)', { f }), '\n'))
	end
	local seen = {}
	for _, b in ipairs(bufs_before) do seen[b] = true end
	for _, b in ipairs(child.lua('return vim.api.nvim_list_bufs()')) do
		if not seen[b] then
			table.insert(texts, table.concat(child.lua('return vim.api.nvim_buf_get_lines(..., 0, -1, false)', { b }), '\n'))
		end
	end
	eq(#texts > 0, true)
	for _, text in ipairs(texts) do
		eq(text:find('Q.-Z.-Q.-Z.-Q.-Z') == nil, true)
	end
end

-- A bug found while porting: a tracked buffer wiped with noautocmd, here the
-- window's current buffer.
T['T242 [char] a tracked buffer wiped with noautocmd is repaired within one refresh, with no UI errors'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	child.messages()
	child.lua('vim.cmd("noautocmd bwipeout " .. vim.fn.bufnr(_G.CDV_TEST.root .. "/c.txt"))')
	-- Decided 2026-10-21: the UI repairs it on the spot, within one refresh, as cleanup's
	-- re-point would (like navigation, Q18): the window shows b, so b is current and c the ternary.
	child.settle(300)
	eq(child.shown(), 'b')
	eq(child.slots(), '⦉c⦊ [b] ⟦-⟧')
	child.settle(300)
	eq(Extra.at_least(child.messages()), {})
end

-- The I23 check wherever a slot changes under the current buffer (decided
-- 2026-10-21). Each stale note is planted by hand: no route is known that
-- reaches these states with the other fixes in.
T['T243 [char] (I23) the check runs at graduation: a stale secondary note naming the graduated buffer is dropped'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	K.set_note(child, 'dsm', 'c', 'b')
	child.steps({ '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	eq(Neg.i23(child), nil)
	local ok, err = child.step('<M-;><M-t>')
	eq({ ok, err }, { true, nil })
end

T['T243 [char] (I23) the check runs at the history fill: a stale secondary note naming the filled buffer is dropped'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	eq(child.slots(), '⦉-⦊ [b] ⟦-⟧')
	eq(child.ordered(), 'b,a')
	K.set_note(child, 'dsm', 'b', 'a')
	child.steps({ '<M-f>' })
	eq(child.slots(), '⦉-⦊ [b] ⟦a⟧')
	eq(Neg.i23(child), nil)
	local ok, err = child.step('<M-;><M-t>')
	eq({ ok, err }, { true, nil })
end

T['T243 [char] (I23) the check runs at a session load: a stale note from the file is dropped'] = function()
	local s = shared()
	start(s)
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	K.set_note(child, 'dsm', 'c', 'b')
	eq(Neg.i23(child), 'dsm')
	eq(Misc.save(child), { true })

	start(s)
	Misc.restore(child, { 'a', 'b', 'c' }, 'c')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	eq(Neg.i23(child), nil)
end

-- Sessions (S2) ----------------------------------------------------------------------

-- Saved: the split (listed first) ⦉c⦊ [d], the first window ⦉a⦊ [b]. The
-- manager brings back one window, on b.
T['T244 [char] (S2) a load into fewer windows matches by what they show and drops the unmatched entry, without an error'] = function()
	local s = shared()
	start(s)
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.steps({ ':e c', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦-⟧')
	eq(Misc.save(child), { true })

	start(s)
	Misc.restore(child, { 'a', 'b', 'c', 'd' }, 'b')
	child.messages()
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(Misc.errors(child), {})
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
end

T['T245 [char] (S2) a session file with a newer header says it was made by a newer cavediver and is left alone'] = function()
	local s = shared()
	start(s)
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })
	local saved = Misc.files_in(s.session_dir)
	eq(#saved, 1)
	local file = s.session_dir .. saved[1]
	local fh = io.open(file, 'wb')
	fh:write('CDV9\nfrom a later version\n')
	fh:close()

	start(s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.messages()
	Misc.load(child)
	child.settle(300)
	eq(Extra.has(child.messages(), 'newer cavediver'), true)
	fh = io.open(file, 'rb')
	local bytes = fh:read('*a')
	fh:close()
	eq(bytes, 'CDV9\nfrom a later version\n')
end

-- It held before the encrypted format and holds with it.
T['T246 [char] (S2) a No Name buffer closed with <M-.> stays on the closed stack across a save and a load'] = function()
	local s = shared()
	start(s)
	child.steps({ ':e a', ':enew' })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "kept text" })')
	child.steps({ '<M-.>' })
	eq(child.shown(), 'a')
	eq(#child.lua('return require("cavediver.domains.history").data.closed_buffers'), 1)
	eq(Misc.save(child), { true })

	start(s)
	Misc.restore(child, { 'a' }, 'a')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(#child.lua('return require("cavediver.domains.history").data.closed_buffers'), 1)
	child.steps({ '<M-S-w>' })
	eq(child.lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'kept text' })
end

-- Cleanup and the focused window ---------------------------------------------------------

-- The split shows an oil-like buffer (acwrite) and keeps its triquetra; its
-- current slot's file is then closed from the first window, which has the
-- focus (A21's healing branch, DESK:2447).
T['T247 [char] (I13, A21) a cleanup heal in another window does not switch the focused window or wipe what that window shows'] = function()
	child.steps({ ':e a', ':e b' })
	local w1 = child.win()
	child.cmd('vsplit')
	child.steps({ ':e x', ':e c' })
	local w2 = child.win()
	local acw = child.lua([[
		local buf = vim.api.nvim_create_buf(true, false)
		vim.bo[buf].buftype = 'acwrite'
		vim.api.nvim_buf_set_name(buf, 'acw://scratch')
		vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = buf, callback = function() end })
		vim.api.nvim_set_current_buf(buf)
		return buf
	]])
	child.settle(200)
	eq(child.slots(w2), '⦉x⦊ [c] ⟦-⟧')
	child.cmd('wincmd p')
	child.settle()
	eq(child.win(), w1)
	eq(child.shown(w1), 'b')
	child.cmd('bdelete c.txt')
	child.settle(300)
	eq(child.win(), w1)
	eq(child.shown(w1), 'b')
	eq(child.lua('return vim.api.nvim_win_is_valid(...)', { w2 }), true)
	eq(child.lua('return vim.api.nvim_win_get_buf(...)', { w2 }), acw)
	eq(child.lua('return vim.api.nvim_buf_is_valid(...)', { acw }), true)
end

T['T248 [char] (A12) with no cokeline, a cycle step raises nothing and <M-v> still ends the cycle'] = function()
	child.setup({ no_cokeline = true })
	eq(child.lua('return (pcall(require, "cokeline.mappings"))'), false)
	child.steps({ ':e a', ':e b' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	local ok, err = child.step('<M-n>')
	eq({ ok, err }, { true, nil })
	eq(child.state(), CYCLING)
	-- the step goes through cavediver's own order, onto a (T171)
	eq(child.shown(), 'a')
	ok, err = child.step('<M-v>')
	eq({ ok, err }, { true, nil })
	eq(child.state(), NORMAL)
	eq(child.slots(), '⦉b⦊ [a] ⟦-⟧')
end

-- T249: no note names its own buffer, after every action of seeded random walks.
local WALKS, KEYS = 30, 20
local function self_walks(multi, seed0)
	for i = 1, WALKS do
		child.setup()
		local r = Neg.self_walk(child, seed0 + i, KEYS, multi)
		if r.brk then
			local b = r.brk
			error(string.format('a note names its own buffer in walk %d at step %d (window %d): %s\n  keys: %s\n  %s   %s',
				i, r.steps, b.window, b.entry, table.concat(r.actions, ', '), b.slots, b.notes), 0)
		end
	end
end

-- It guards the decided check's order: after Q6's guard, never naming the current buffer.
T['T249 [char] (A1, A11) no note names its own buffer, over random walks: one window'] = function() self_walks(false, 7000) end
T['T249 [char] (A1, A11) no note names its own buffer, over random walks: several windows'] = function() self_walks(true, 11000) end

return T
