-- Decided and intended rules that no other case checks (what-is-cavediver.md,
-- section 7, "Decided rules not covered elsewhere"). Each case cites the rule
-- it comes from (P, M, A, I, D or Q, and the final section).
local Helpers = dofile('tests/helpers.lua')
local K = dofile('tests/helpers_keys.lua')
local Extra = dofile('tests/helpers_cycling.lua')
local Misc = dofile('tests/helpers_misc.lua')
local Neg = dofile('tests/helpers_negative.lua')
local Dec = dofile('tests/helpers_decisions.lua')
local eq = Helpers.eq
local child = Helpers.new_child()
Extra.attach(child)
-- For the cases about what runs at require: cavediver isn't loaded yet.
local bare = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = function()
			child.stop()
			bare.stop()
		end,
	},
})

local function errors() return Extra.at_least(child.messages()) end

-- Press a restore and return ok, err and the messages it gave.
local function press(key)
	child.messages()
	local ok, err = child.step(key)
	return ok, err, child.messages()
end

-- A project and a session directory that outlive the children (sessions).
local function shared()
	return { root = Misc.make_project(), session_dir = Misc.make_session_dir() }
end

local function start(s)
	Misc.start(child, { root = s.root, session_dir = s.session_dir })
end

-- Principles ------------------------------------------------------------------

-- A BufEnter autocmd of the user's, made after setup(), runs inside the event:
-- under the settle rule cavediver hasn't slotted the arrival yet.
T['T250 [char] (P2, A1) the slotting happens after the event, not inside it'] = function()
	child.steps({ ':e a' })
	child.lua([[
		_G.CDV_SEEN = {}
		vim.api.nvim_create_autocmd('BufEnter', { callback = function()
			table.insert(_G.CDV_SEEN, _G.CDV_TEST.slots())
		end })
	]])
	child.steps({ ':e b' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	eq(child.lua('return _G.CDV_SEEN'), { '⦉-⦊ [a] ⟦-⟧' })
end

-- T250's purpose: what settling protects. A buffer that only becomes a terminal or help
-- after its BufEnter is never slotted or registered as a file (the author, 2026-10-21: "Both").
T['T250 [char] (P2, A1) a buffer that turns into a terminal or help after its BufEnter is never slotted as a file'] = function()
	child.steps({ ':e a', ':e b' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	child.lua('vim.o.shell = "sh"')
	child.cmd('terminal')
	child.settle(200)
	local term = child.lua('return { buf = vim.api.nvim_get_current_buf(), bt = vim.bo.buftype }')
	eq(term.bt, 'terminal')
	-- The terminal isn't registered and sits in no slot (whether the window keeps its slots
	-- while visiting is the visiting rule's test, T27).
	eq(child.lua('return require("cavediver.domains.history").get_hash_from_buffer(...) == nil', { term.buf }), true)
	eq(child.slots():find('NONAME', 1, true), nil)
	child.cmd('buffer b.txt')
	child.cmd('help')
	child.settle(200)
	local help = child.lua('return { buf = vim.api.nvim_get_current_buf(), bt = vim.bo.buftype, win = vim.api.nvim_get_current_win() }')
	eq(help.bt, 'help')
	eq(child.lua('return require("cavediver.domains.history").get_hash_from_buffer(...) == nil', { help.buf }), true)
	eq(child.slots(help.win), 'no triquetra')
end

-- Saved: the split (listed first) ⦉c⦊ [d], the first window ⦉a⦊ [b]. The
-- manager brings both back the other way round: the first-listed window on b.
T['T251 [char] (P3) the load matches windows by what they show, not by position'] = function()
	local s = shared()
	start(s)
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦-⟧')
	eq(Misc.save(child), { true })

	start(s)
	Misc.restore(child, { 'a', 'b', 'c', 'd' }, 'd')
	child.cmd('noautocmd vsplit')
	child.cmd('noautocmd edit b.txt')
	local wins = child.lua('return vim.api.nvim_tabpage_list_wins(0)')
	eq({ child.shown(wins[1]), child.shown(wins[2]) }, { 'b', 'd' })
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ child.slots(wins[1]), child.slots(wins[2]) }, { '⦉a⦊ [b] ⟦-⟧', '⦉c⦊ [d] ⟦-⟧' })
end

-- b is closed and stays known through the closed stack.
T['T252 [target] (P10, I17) a closed file still on the closed stack keeps its history entry'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	local h = child.hash_of('b')
	eq(child.lua('return require("cavediver.domains.history").data.crux_internals.global[...] ~= nil', { h }), true)
	child.cmd('bdelete b.txt')
	child.settle()
	eq(child.closed(), 'b')
	eq(child.lua('return require("cavediver.domains.history").data.crux_internals.global[...] ~= nil', { h }), true)
end

T['T253 [char] (P11) a failing hook is reported with a stack trace'] = function()
	child.messages()
	child.lua([[
		local sm = require('cavediver.engine'):create('t253')
		sm:register_state('a')
		sm:register_state('b')
		sm.current_state = 'a'
		sm:on('a', 'b', 'breaks', function() error('boom') end, 1, true)
		sm:to('b')
	]])
	local msgs = child.messages()
	eq(Extra.has(msgs, "Hook 'breaks' failed"), true)
	local traced = false
	for _, m in ipairs(msgs) do
		if m.msg:lower():find('stack traceback', 1, true) then traced = true end
	end
	eq(traced, true)
end

T['T254 [char] (P12, A25) require creates no user commands and starts no timers'] = function()
	Dec.bare(bare)
	local got = bare.lua(Dec.TIMERS .. [[
		local before = timers()
		require('cavediver')
		local cmds = {}
		for name in pairs(vim.api.nvim_get_commands({})) do
			if name:find('^Cavediver') then table.insert(cmds, name) end
		end
		return { commands = cmds, timers = timers() - before }
	]])
	eq(got, { commands = {}, timers = 0 })
end

T['T254 [char] (P12, A25) setup() puts every autocmd it makes in the cavediver augroup, and makes the commands'] = function()
	Dec.bare(bare)
	local got = bare.lua([[
		local function key(a) return table.concat({ tostring(a.id), a.event, tostring(a.group), tostring(a.pattern), tostring(a.buffer) }, '|') end
		local before = {}
		for _, a in ipairs(vim.api.nvim_get_autocmds({})) do before[key(a)] = true end
		require('cavediver').setup({ session_dir = _G.CDV_ROOT .. '/sessions/' })
		local made, outside = 0, 0
		for _, a in ipairs(vim.api.nvim_get_autocmds({})) do
			if not before[key(a)] then
				made = made + 1
				if a.group_name ~= 'cavediver' then outside = outside + 1 end
			end
		end
		return { made = made > 0, outside = outside, command = vim.fn.exists(':CavediverTriquetra') == 2 }
	]])
	eq(got, { made = true, outside = 0, command = true })
end

-- Model -----------------------------------------------------------------------

-- Decided 2026-10-21: a separator between directory and name, so "/proj" + "a" and
-- "/proja" + "" can't share a file.
T['T255 [char] (M1) the session file is named sha256(directory .. "\\n" .. name)'] = function()
	child.steps({ ':e a', ':e b' })
	local got = child.lua([[
		local dir = require('cavediver.configs').session_dir
		pcall(require('cavediver').save_session, 'work')
		local want = vim.fn.sha256(vim.fn.getcwd(-1, -1) .. '\n' .. 'work')
		local names = vim.fn.isdirectory(dir) == 1 and vim.fn.readdir(dir) or {}
		for _, f in ipairs(names) do
			if f:sub(1, #want) == want then return true end
		end
		return false
	]])
	eq(got, true)
end

T['T255 [char] (M1) a session "a" in /proj and a nameless save in /proja are two files'] = function()
	child.steps({ ':e a' })
	local got = child.lua([[
		local root = _G.CDV_TEST.root
		local dir = require('cavediver.configs').session_dir
		vim.fn.mkdir(root .. '/proj', 'p'); vim.fn.mkdir(root .. '/proja', 'p')
		local before = vim.fn.isdirectory(dir) == 1 and #vim.fn.readdir(dir) or 0
		vim.cmd('cd ' .. vim.fn.fnameescape(root .. '/proj'))
		pcall(require('cavediver').save_session, 'a')
		vim.cmd('cd ' .. vim.fn.fnameescape(root .. '/proja'))
		pcall(require('cavediver').save_session)
		local after = vim.fn.isdirectory(dir) == 1 and #vim.fn.readdir(dir) or 0
		return after - before
	]])
	eq(got, 2)
end

-- A listed buffer on c.txt, an existing regular file, with buftype nowrite.
T['T256 [char] (M3) a listed nowrite buffer on an existing regular file is tracked'] = function()
	child.steps({ ':e a' })
	child.lua([[
		local b = vim.fn.bufadd(_G.CDV_TEST.root .. '/c.txt')
		vim.bo[b].buftype = 'nowrite'
		vim.bo[b].buflisted = true
		vim.api.nvim_set_current_buf(b)
	]])
	child.settle()
	eq({ child.lua('return vim.bo.buftype'), child.lua('return vim.bo.buflisted') }, { 'nowrite', true })
	eq(Dec.registered(child), true)
	eq(child.slots(), '⦉a⦊ [c] ⟦-⟧')
end

-- b's secondary swap note is set directly; b isn't the current buffer, so no
-- check at the load touches it.
T['T257 [char] (M7) the secondary map\'s swap notes are saved and loaded with the rest of the map'] = function()
	local s = shared()
	start(s)
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	K.set_note(child, 'dsm', 'b-swap', 'c')
	local notes = K.notes_for(child, { 'b' })
	eq(notes, 'dtm{b>a} dsm{b-swap>c b>a}')
	eq(Misc.save(child), { true })

	start(s)
	Misc.restore(child, { 'a', 'b', 'c' }, 'c')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	eq(K.notes_for(child, { 'b' }), notes)
end

-- The primary a sits in the ternary, then the secondary, then the current slot.
T['T258 [char] (M8, Q16) the primary may share a slot\'s buffer: the queue stays and nothing reports an error'] = function()
	child.steps({ ':e a', '<M-;><M-c>', ':e b' })
	eq({ child.slots(), child.primary() }, { '⦉a⦊ [b] ⟦-⟧', '[a]on' })
	child.steps({ '<M-f>' })
	eq({ child.slots(), child.primary() }, { '⦉-⦊ [b] ⟦a⟧', '[a]on' })
	child.steps({ '<M-f>' })
	eq({ child.slots(), child.primary() }, { '⦉-⦊ [a] ⟦b⟧', '[a]on' })
	child.settle(500)
	eq(child.primary(), '[a]on')
	eq(errors(), {})
end

-- Keys ------------------------------------------------------------------------

-- From ⦉c⦊ [d] ⟦b⟧ with an empty queue, <M-;><M-f> acts as <M-f> (T191's notes).
T['T259 [char] (M7, A6, A8) the <M-;><M-f> fallback onto the secondary writes the swap notes, as <M-f> does'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq({ child.slots(), child.primary() }, { '⦉c⦊ [d] ⟦b⟧', '[]off' })
	child.steps({ '<M-;><M-f>' })
	eq(child.slots(), '⦉c⦊ [b] ⟦d⟧')
	eq({ dsm_d_swap = child.note('dsm', 'd-swap'), dtm_d_swap = child.note('dtm', 'd-swap'), dsm_d = child.note('dsm', 'd') },
		{ dsm_d_swap = 'b', dtm_d_swap = 'c', dsm_d = '-' })
end

-- T186's keys up to ⦉d⦊ [a] ⟦c⟧, where d's note d>a names a; then a pick of d,
-- the ternary, in place of <M-S-f>.
T['T260 [char] (A1, A13) a pick of the ternary: its stale note becomes the left buffer\'s own note, dropped when it has none'] = function()
	child.steps({ ':e a', ':e d', ':e c', '<M-;><M-f>', '<M-f>', ':e a' })
	eq(child.slots(), '⦉d⦊ [a] ⟦c⟧')
	eq(child.note('dtm', 'd'), 'a')
	K.cycle_to(child, 'd')
	child.steps({ '<M-v>' })
	eq(child.slots(), '⦉a⦊ [d] ⟦c⟧')
	eq(child.note('dtm', 'd'), '-')
	local ok, err, msgs = press('<M-;><M-r>')
	eq({ ok, err }, { true, nil })
	eq(Extra.has(msgs, 'No ternary relationship found'), true)
end

-- The same state with d as the primary, reached by a primary jump onto d, the ternary.
T['T261 [char] (A1, A8) a primary jump onto the ternary: its stale note becomes the left buffer\'s own note, dropped when it has none'] = function()
	child.steps({ ':e a', ':e d', '<M-;><M-c>', ':e c', '<M-f>', '<M-f>', ':e a' })
	eq({ child.slots(), child.primary() }, { '⦉d⦊ [a] ⟦c⟧', '[d]on' })
	eq(child.note('dtm', 'd'), 'a')
	child.steps({ '<M-;><M-f>' })
	eq(child.slots(), '⦉a⦊ [d] ⟦c⟧')
	eq(child.note('dtm', 'd'), '-')
	local ok, err, msgs = press('<M-;><M-r>')
	eq({ ok, err }, { true, nil })
	eq(Extra.has(msgs, 'No ternary relationship found'), true)
end

-- T185's keys up to ⦉c⦊ [b] ⟦e⟧, where e's note e>c names c; then a pick of e,
-- the secondary, in place of <M-f>. c stays put, so e's note becomes c's own, a.
T['T262 [char] (A1, A13) a pick of the secondary: a stale ternary note becomes the ternary\'s own note'] = function()
	child.steps({ ':e a', ':e c', ':e e', ':e b', '<M-f>', ':e c', '<M-S-f>' })
	eq(child.slots(), '⦉c⦊ [b] ⟦e⟧')
	eq(child.note('dtm', 'e'), 'c')
	K.cycle_to(child, 'e')
	child.steps({ '<M-v>' })
	eq(child.slots(), '⦉c⦊ [e] ⟦b⟧')
	eq(child.note('dtm', 'e'), 'a')
	local ok, err = child.step('<M-;><M-r>')
	eq({ ok, err }, { true, nil })
	eq(child.slots(), '⦉a⦊ [e] ⟦b⟧')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉c⦊ [e] ⟦b⟧')
end

-- The arriving buffer's plain secondary note names the window's secondary,
-- set by hand; it has no swap note, so the check drops it.
T['T263 [char] (A7, M7) <M-S-f> runs the secondary map\'s check on the buffer it brings in'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	K.set_note(child, 'dsm', 'c', 'b')
	child.steps({ '<M-S-f>' })
	eq(child.slots(), '⦉d⦊ [c] ⟦b⟧')
	eq(Neg.i23(child), nil)
	local ok, err, msgs = press('<M-;><M-t>')
	eq({ ok, err }, { true, nil })
	eq(Extra.has(msgs, 'No secondary relationship found'), true)
end

T['T263 [char] (A8, M7) a primary jump runs the secondary map\'s check on the primary'] = function()
	child.steps({ ':e x', '<M-;><M-c>', ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq({ child.slots(), child.primary() }, { '⦉c⦊ [d] ⟦b⟧', '[x]on' })
	K.set_note(child, 'dsm', 'x', 'b')
	child.steps({ '<M-;><M-f>' })
	eq(child.slots(), '⦉d⦊ [x] ⟦b⟧')
	eq(Neg.i23(child), nil)
	local ok, err, msgs = press('<M-;><M-t>')
	eq({ ok, err }, { true, nil })
	eq(Extra.has(msgs, 'No secondary relationship found'), true)
end

-- Restores --------------------------------------------------------------------

-- T62's exchange: b's note b>a names the secondary a, so <M-;><M-r> swaps the
-- ternary c up into the secondary. b's secondary note is set to name c by hand.
T['T264 [char] (A11, I23) the ternary restore\'s exchange is followed by the secondary map\'s check'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e a', ':e b' })
	eq(child.slots(), '⦉c⦊ [b] ⟦a⟧')
	eq(child.note('dtm', 'b'), 'a')
	K.set_note(child, 'dsm', 'b', 'c')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉a⦊ [b] ⟦c⟧')
	eq(Neg.i23(child), nil)
	local ok, err = child.step('<M-;><M-t>')
	eq({ ok, err }, { true, nil })
end

-- At ⦉c⦊ [d] ⟦b⟧, set by hand: d's secondary note names c (the ternary, so the
-- restore exchanges), d's ternary note names b (which the exchange moves into
-- the ternary), and b's own note names d, the current buffer.
T['T265 [char] (A11) at the secondary restore\'s exchange, a stale ternary note is dropped when the ternary\'s own note names the current buffer'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	K.set_note(child, 'dsm', 'd', 'c')
	K.set_note(child, 'dtm', 'd', 'b')
	K.set_note(child, 'dtm', 'b', 'd')
	child.steps({ '<M-;><M-t>' })
	eq(child.slots(), '⦉b⦊ [d] ⟦c⟧')
	eq(child.note('dtm', 'd'), '-')
	local ok, err, msgs = press('<M-;><M-r>')
	eq({ ok, err }, { true, nil })
	eq(Extra.has(msgs, 'No ternary relationship found'), true)
end

-- a ends up with the plain note a>b and the swap note a-swap>f, ternary d
-- (T173's state). f.txt is deleted on disk while f's buffer stays open.
T['T266 [char] (A11, D9) a restore onto an open buffer whose file is gone flip-flops and says the file isn\'t on disk'] = function()
	child.steps({ ':e b', ':e a', ':e c', ':e f', ':e a', '<M-S-f>', ':e d', ':e a' })
	eq(child.slots(), '⦉d⦊ [a] ⟦-⟧')
	eq(K.notes_for(child, { 'a' }), 'dtm{a-swap>f a>b} dsm{}')
	child.lua(K.rm_code('f'))
	eq(child.lua([[return vim.fn.bufloaded('f.txt')]]), 1)
	for _, want in ipairs({ '⦉f⦊ [a] ⟦-⟧', '⦉d⦊ [a] ⟦-⟧', '⦉f⦊ [a] ⟦-⟧' }) do
		local ok, err, msgs = press('<M-;><M-r>')
		eq({ ok, err }, { true, nil })
		eq(child.slots(), want)
		-- Each press that brings f back says so, in one WARN line (wording locked 2026-10-21).
		if want:find('⦉f⦊', 1, true) then
			local said = false
			for _, m in ipairs(msgs) do
				if m.level == vim.log.levels.WARN
					and m.msg:match('^Restored ternary slot to: %x+ %(f%.txt%), not on disk right now$') then
					said = true
				end
			end
			eq({ want, said }, { want, true })
		end
	end
end

T['T267 [char] (A11, D9) a note at a hash with no path is cleared when it\'s used'] = function()
	child.steps({ ':e a', ':e b' })
	K.set_note(child, 'dtm', 'b', '0123456789abcdef', true)
	local ok, err = child.step('<M-;><M-r>')
	eq({ ok, err }, { true, nil })
	eq(child.lua([[
		local t = require('cavediver.domains.window').data.crux[vim.api.nvim_get_current_win()]
		for _, v in pairs(t.displacement_ternary_map) do
			if v == '0123456789abcdef' then return true end
		end
		return false
	]]), false)
end

-- Visiting (the desk's visiting rule, A2) ------------------------------------

-- Help shown in a's own window: a visit.
T['T268 [char] (A2) the winbar shows the visit, like "a.txt ← [help]"'] = function()
	child.steps({ ':e a' })
	local aw = child.win()
	child.cmd('help')
	child.settle()
	local hb = child.lua('return vim.api.nvim_get_current_buf()')
	child.cmd('close')
	child.settle()
	eq(child.win(), aw)
	child.lua('vim.api.nvim_win_set_buf(0, ...)', { hb })
	child.settle(300)
	eq(child.lua('return vim.bo.buftype'), 'help')
	-- Format locked 2026-10-21: the current slot's piece becomes "[<bufnr>] a.txt ← [help]",
	-- the ternary and secondary pieces kept around it; the brackets hold the buftype.
	local text = Dec.winbar_text(child, aw)
	eq(text:match('%[%d+%] a%.txt ← %[help%]') ~= nil, true)
end

T['T269 [char] (A2, A6, A7) while visiting, <M-f> and <M-S-f> take the window back to its current slot first'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	for _, key in ipairs({ '<M-f>', '<M-S-f>' }) do
		Dec.visit_scratch(child)
		eq(child.lua('return vim.bo.buftype'), 'nofile')
		local ok, err = child.step(key)
		eq({ key, ok, err }, { key, true, nil })
		eq({ key, child.shown(), child.slots() }, { key, 'd', '⦉c⦊ [d] ⟦b⟧' })
	end
end

T['T270 [char] (A2) while visiting, the current slot may hold a closed buffer'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	child.cmd('terminal')
	child.settle()
	eq(child.lua('return vim.bo.buftype'), 'terminal')
	child.cmd('bdelete c.txt')
	child.settle()
	eq(child.closed(), 'c')
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
end

-- Deletes and renames (A19, A20, A22) -----------------------------------------

-- Neovim closes every other window that shows the deleted buffer, so each of
-- these is a window on its own (as in T111), on a route where Neovim's own
-- pick (the most recent buffer in the window's jumplist) isn't the landing.

-- ⦉-⦊ [b] ⟦a⟧: no ternary. The window came to b from c by <M-f>, so Neovim's
-- own pick is c; the secondary restore then made a the secondary.
T['T271 [char] (A19) a deleted buffer\'s window lands on the secondary when there\'s no ternary'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', '<M-f>', '<M-;><M-t>' })
	eq(child.slots(), '⦉-⦊ [b] ⟦a⟧')
	child.cmd('bdelete b.txt')
	child.settle()
	eq(child.shown(), 'a')
end

-- A split on c with empty slots, left on its own by :only after window 1
-- visited d and x. Neovim's pick there is b, from the jumplist the split
-- copied; the most recent buffer is x.
local function lone_split()
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('vsplit')
	child.settle()
	local w2 = child.win()
	child.cmd('wincmd p')
	child.settle()
	child.steps({ ':e d', ':e x' })
	child.cmd('wincmd p')
	child.settle()
	child.cmd('only')
	child.settle()
	eq(child.lua('return vim.api.nvim_list_wins()'), { w2 })
	eq({ child.shown(), child.slots(), child.primary() }, { 'c', '⦉-⦊ [c] ⟦-⟧', '[]off' })
	eq(child.ordered(), 'c,x,d,b,a')
	return w2
end

T['T271 [char] (A19) with no ternary or secondary, it lands on the primary'] = function()
	local w2 = lone_split()
	-- The queue set by hand: [a], switched on.
	child.lua([[
		local t = require('cavediver.domains.window').data.crux[...]
		t.primary_buffer = { require('cavediver.domains.history').get_hash_from_filepath(_G.CDV_TEST.root .. '/a.txt') }
		t.primary_enabled = true
	]], { w2 })
	eq(child.primary(), '[a]on')
	child.cmd('bdelete c.txt')
	child.settle()
	eq({ child.win(), child.shown() }, { w2, 'a' })
end

T['T271 [char] (A19) with no ternary, secondary or primary, it lands on the most recent buffer'] = function()
	local w2 = lone_split()
	child.cmd('bdelete c.txt')
	child.settle()
	eq({ child.win(), child.shown() }, { w2, 'x' })
end

-- "Most recent" follows history_view (decided 2026-10-21), as <M-.> already does: under the
-- window view it's the window's own history, so the window lands on what it showed, not on x.
T['T271 [char] (A19) under the window view, "most recent" is the window\'s own history'] = function()
	child.setup({ history_view = 'window' })
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('vsplit')
	child.settle()
	local w2 = child.win()
	-- keepjumps: cavediver records these visits, Neovim's jumplist doesn't, so Neovim's own
	-- pick on :bdelete (the jumplist, b) differs from the window's history (a): no pass by luck.
	child.cmd('keepjumps edit a.txt')
	child.settle()
	child.cmd('keepjumps edit c.txt')
	child.settle()
	child.cmd('wincmd p')
	child.settle()
	child.steps({ ':e d', ':e x' })
	child.cmd('wincmd p')
	child.settle()
	child.cmd('only')
	child.settle()
	-- Empty the window's slots by hand, so only "most recent" can decide the landing.
	child.lua('local t = require("cavediver.domains.window").data.crux[...]; t.ternary_slot = nil; t.secondary_slot = nil', { w2 })
	eq({ child.shown(), child.slots(w2) }, { 'c', '⦉-⦊ [c] ⟦-⟧' })
	child.cmd('bdelete c.txt')
	child.settle()
	eq({ child.win(), child.shown() }, { w2, 'a' })
end

-- Nothing to land on: a is the only tracked file. Neovim's pick is a listed
-- scratch buffer, something other than its empty buffer, so the window gets a new
-- empty buffer.
T['T271 [char] (A19) with nothing to land on and Neovim showing something else, the window gets a new empty buffer'] = function()
	child.steps({ ':e a' })
	local scratch = child.lua('return vim.api.nvim_create_buf(true, true)')
	child.cmd('bdelete a.txt')
	child.settle()
	local got = child.lua([[
		local b = vim.api.nvim_get_current_buf()
		return { b ~= ..., vim.api.nvim_buf_get_name(b), vim.bo[b].buftype, vim.api.nvim_buf_get_lines(b, 0, -1, false) }
	]], { scratch })
	eq(got, { true, '', '', { '' } })
end

-- :saveas writes g.txt and leaves b.txt on disk. What happens to the window
-- afterwards is T106's.
T['T272 [char] (A20) a rename whose old file still exists is a copy: the old name goes on the closed stack'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('saveas g.txt')
	child.settle(300)
	eq(child.lua('return vim.fn.filereadable(_G.CDV_TEST.root .. "/b.txt")'), 1)
	eq(vim.tbl_contains(vim.split(child.closed(), ','), 'b'), true)
end

-- T113's stale registration: b's buffer wiped without events, a copy of b.txt
-- loaded the same way, then the timer's pass.
T['T273 [char] (A22) the stale pass keeps the history of the file it re-points'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	local got = child.lua([[
		local H = require('cavediver.domains.history')
		local path = _G.CDV_TEST.root .. '/b.txt'
		local old = vim.fn.bufnr(path)
		local hash = H.get_hash_from_buffer(old)
		local had = H.data.crux_internals.global[hash] ~= nil
		vim.cmd('noautocmd bwipeout! ' .. old)
		local copy = vim.fn.bufadd(path)
		vim.cmd('noautocmd call bufload(' .. copy .. ')')
		vim.bo[copy].buflisted = true
		H.cleanup_system()
		return { had = had, kept = H.data.crux_internals.global[hash] ~= nil }
	]])
	eq(got, { had = true, kept = true })
end

-- Debug commands (A23) ----------------------------------------------------------

T['T274 [char] (A23) the triquetra commands print primary_buffer[1] as "Primary buffer"'] = function()
	child.steps({ ':e a', '<M-;><M-c>', ':e b' })
	local h = K.hash(child, 'a')
	local plain = child.lua('return vim.api.nvim_exec2("CavediverTriquetra", { output = true }).output')
	local verbose = child.lua('return vim.api.nvim_exec2("CavediverTriquetraVerbose", { output = true }).output')
	eq({ plain:find('Primary buffer:%s+' .. h) ~= nil, verbose:find('Primary buffer:%s+' .. h) ~= nil }, { true, true })
end

-- The flight recorder (A26) ----------------------------------------------------
-- Not built. Its dumps go under stdpath('state')/cavediver/, as in
-- test_cycling.lua.

local function dumps_after(fn)
	local before = child.dumps()
	fn()
	child.settle(200)
	return Extra.new_files(before, child.dumps())
end

T['T275 [target] (A26) the fill assertion dumps'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	-- The ordered list's first two entries swapped by hand, so its first entry
	-- isn't the window's current buffer (T176).
	local files = dumps_after(function()
		child.lua([[
			local ord = require('cavediver.domains.history').data.ordered.crux
			ord[1], ord[2] = ord[2], ord[1]
			_G.CDV_TEST.press('<M-f>')
		]])
	end)
	eq(#files > 0, true)
end

T['T275 [target] (A26) "Duplicates detected" dumps'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':e d' })
	-- s = t, set directly (T34).
	child.lua([[
		local H = require('cavediver.domains.history')
		local t = require('cavediver.domains.window').data.crux[vim.api.nvim_get_current_win()]
		local c = H.get_hash_from_filepath(_G.CDV_TEST.root .. '/c.txt')
		t.secondary_slot, t.ternary_slot = c, c
	]])
	eq(child.slots(), '⦉c⦊ [d] ⟦c⟧')
	child.messages()
	local files = dumps_after(function() child.steps({ ':e a' }) end)
	eq(Extra.has(child.messages(), 'Duplicates detected'), true)
	eq(#files > 0, true)
end

-- A failing hook bound by hand to the history machine's updates.
T['T275 [target] (A26) a hook failure dumps'] = function()
	child.steps({ ':e a' })
	child.lua([[
		require('cavediver.domains.history').sm:on('attached', 'attached', 't275_breaks', function() error('planted') end, 5, true)
	]])
	child.messages()
	local files = dumps_after(function() child.steps({ ':e b' }) end)
	eq(Extra.has(child.messages(), "Hook 't275_breaks' failed"), true)
	eq(#files > 0, true)
end

-- T203's layout, with a duplicate planted in the first window instead of a
-- stale note: c's secondary set to b, which is already its ternary.
T['T276 [target] (A26) a planted I1 break dumps at the next step'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	local win1 = child.win()
	eq(child.slots(win1), '⦉b⦊ [c] ⟦-⟧')
	child.cmd('vsplit')
	child.steps({ ':e d', ':e e' })
	child.lua('require("cavediver.domains.window").data.crux[...].secondary_slot = select(2, ...)', { win1, child.hash_of('b') })
	eq(child.slots(win1), '⦉b⦊ [c] ⟦b⟧')
	local files = dumps_after(function() child.steps({ ':e x' }) end)
	eq(#files, 1)
end

-- T200's route: the restore assertion, from a secondary note set by hand.
local function fire_restore_assertion()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	Dec.stale_secondary_note(child)
	local err
	local files = dumps_after(function()
		local ok
		ok, err = child.step('<M-;><M-t>')
		eq(ok, false)
	end)
	eq(err:find('Remembered secondary is the same as current secondary', 1, true) ~= nil, true)
	return files, err
end

T['T277 [target] (A26) the error says where the dump file is'] = function()
	local files, err = fire_restore_assertion()
	eq(#files > 0, true)
	local text = err
	for _, m in ipairs(child.messages()) do text = text .. '\n' .. m.msg end
	local named = false
	for _, f in ipairs(files) do
		if text:find(vim.fn.fnamemodify(f, ':t'), 1, true) then named = true end
	end
	eq(named, true)
end

T['T278 [target] (A26) steps from keymaps and from events are tagged keymap and event'] = function()
	local files = fire_restore_assertion()
	eq(#files > 0, true)
	local tagged = false
	for _, f in ipairs(files) do
		local text = table.concat(child.lua('return vim.fn.readfile(...)', { f }), '\n')
		if text:find('%f[%w]keymap%f[%W]') and text:find('%f[%w]event%f[%W]') then tagged = true end
	end
	eq(tagged, true)
end

-- Invariants (section 4) ---------------------------------------------------------
-- Walks as in tests/test_invariants.lua: each in a fresh child, a.txt then
-- the steps picked by a fixed seed, the invariant checked after every action.

local WALKS, STEPS = 30, 24
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
-- The spec's walk actions, weighted as in tests/test_invariants.lua.
local ACTS = join(rep(2, { 'e a', 'e b', 'e c', 'e d', 'e e' }), rep(4, { '<M-f>' }), rep(3, { '<M-S-f>' }),
	{ '<M-;><M-r>', '<M-;><M-t>', 'X1', 'X2', 'X3', '<M-;><M-c>', '<M-;><M-f>' })
local MW = join(ACTS, rep(2, { 'vsplit' }), rep(3, { 'wincmd p' }), { 'close' })
local MWY = join(MW, { 'Y1', 'Y2' })
local CLOSING = { 'enew', 'enew+text', '<M-.>', '<M-.>', '<M-S-w>' }

local function walk(check, actions, seed, walks)
	local broke = Dec.walks(child, { seed = seed, walks = walks or WALKS, steps = STEPS, actions = actions, check = check })
	if broke then error(broke, 0) end
end

T['T279 [char] (I5) the registry stays a bijection over random walks'] = function()
	walk('I5', join(MW, CLOSING), 11)
end

-- b, the ternary, wiped without events: no BufDelete, so the registry is
-- stale until the cleanup tick (4 s, first tick at once).
T['T280 [char] (I6) a buffer wiped without events leaves no stale registration after a cleanup tick'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	child.lua('vim.cmd("noautocmd bwipeout " .. vim.fn.bufnr(_G.CDV_TEST.root .. "/b.txt"))')
	child.settle(4600)
	eq(child.lua([[
		local r = require('cavediver.domains.history').data.hash_buffer_registry
		local bad = 0
		for _, b in pairs(r.buffers) do if not vim.api.nvim_buf_is_valid(b) then bad = bad + 1 end end
		for b in pairs(r.hashes) do if not vim.api.nvim_buf_is_valid(b) then bad = bad + 1 end end
		return bad
	]]), 0)
end

-- Checked after a cleanup pass forced after every action ("eventually").
T['T281 [char] (I7) after a cleanup pass, no closed hash has an open buffer, over random walks'] = function()
	walk('I7', join(MW, CLOSING), 12)
end

-- Cycles left open across a window jump (Y1, Y2), as in T128.
T['T282 [char] (I8) the current slot is the shown buffer outside cycling and visits, over random walks'] = function()
	walk('I8', MWY, 13)
end

T['T283 [char] (I9) every triquetra belongs to a valid, non-floating window, over random walks'] = function()
	walk('I9', join(MWY, CLOSING), 14)
end

T['T284 [char] (I9) :file onto a name not on disk in a split leaves no triquetra for a dead window'] = function()
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e b' })
	child.cmd('file new.txt')
	child.settle(200)
	eq(child.lua([[
		local dead = 0
		for w in pairs(require('cavediver.domains.window').data.crux) do
			if not vim.api.nvim_win_is_valid(w) then dead = dead + 1 end
		end
		return dead
	]]), 0)
end

-- A secondary set to a hash nothing knows, saved in the same call so no other
-- pass runs first.
T['T285 [char] (I14) a save with a slot holding a hash with no path succeeds'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	child.messages()
	local got = child.lua([[
		local t = require('cavediver.domains.window').data.crux[vim.api.nvim_get_current_win()]
		t.secondary_slot = '0123456789abcdef'
		return { pcall(require('cavediver').save_session, vim.fn.getcwd()) }
	]])
	eq(got, { true })
	eq(errors(), {})
end

-- T143's read-only session directory.
-- The transition is abandoned, so storage stays where it was: idle after a load or a save,
-- bare before either (as here, a fresh process's first save).
T['T286 [char] (I21) the critical save hook throws to the caller and leaves storage where it was'] = function()
	local s = shared()
	vim.fn.setfperm(s.session_dir, 'r-xr-xr-x')
	start(s)
	child.steps({ ':e a' })
	local before = child.lua('return require("cavediver").get_storage_state()')
	local got = Misc.save(child)
	local state = child.lua('return require("cavediver").get_storage_state()')
	vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
	eq({ got[1], state }, { false, before })
end

-- Final section ------------------------------------------------------------------

-- T163's re-point: the window put on d without a BufEnter, then a's buffer
-- wiped. d's secondary note names b, the window's secondary, set by hand; the
-- secondary stays b either way, so the note is stale once d is current.
T['T287 [char] (I23, A21) a cleanup re-point runs the check on the buffer it makes current'] = function()
	child.steps({ ':e d', ':e b', ':e c', '<M-f>', ':e a' })
	eq(child.slots(), '⦉c⦊ [a] ⟦b⟧')
	K.set_note(child, 'dsm', 'd', 'b')
	child.cmd('noautocmd buffer d.txt')
	child.cmd('bwipeout a.txt')
	child.settle()
	eq({ child.slots():match('%[(.-)%]'), child.slots():match('⟦(.-)⟧$') }, { 'd', 'b' })
	eq(Neg.i23(child), nil)
	local ok, err = child.step('<M-;><M-t>')
	eq({ ok, err }, { true, nil })
end

T['T288 [char] (D11) under the window view, :close leaves no tie: :e a after it ranks a first'] = function()
	child.setup({ history_view = 'window' })
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	child.cmd('close')
	child.settle()
	child.steps({ ':e a' })
	eq(Dec.leftmost(child), nil)
end

-- Doc checks ---------------------------------------------------------------------

local function read(path)
	if vim.fn.filereadable(path) == 0 then return '' end
	return Misc.read(path)
end

T['T289 [target] (D25) the window machine is gone: its file, its SHOWING_ constants and its require'] = function()
	local requires = false
	for _, f in ipairs(vim.fn.globpath('lua/cavediver', '**/*.lua', true, true)) do
		if Misc.has(read(f), "require('cavediver.domains.window.sm')") or Misc.has(read(f), 'require("cavediver.domains.window.sm")') then
			requires = true
		end
	end
	eq({
		sm = vim.fn.filereadable('lua/cavediver/domains/window/sm.lua'),
		showing = Misc.has(read('lua/cavediver/domains/window/states.lua'), 'SHOWING_'),
		requires = requires,
	}, { sm = 0, showing = false, requires = false })
end

T['T290 [char] (D18, D22, D24) STATUS and the old project CLAUDE.md live in archive/'] = function()
	eq({
		vim.fn.filereadable('archive/CURRENT_IMPLEMENTATION_STATUS.md'),
		vim.fn.filereadable('archive/CLAUDE.md'),
		vim.fn.filereadable('CURRENT_IMPLEMENTATION_STATUS.md'),
		vim.fn.filereadable('CLAUDE.md'),
	}, { 1, 1, 0, 0 })
end

T['T291 [char] (D8, D13) README:15 and README:355 stay as written'] = function()
	local r = read('README.md')
	eq({
		Misc.has(r, 'Closed buffers reopen when accessed through relationships'),
		Misc.has(r, 'Every time you jump to secondary the system also records the current buffers, secondary'),
	}, { true, true })
end

return T
