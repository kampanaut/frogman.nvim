-- The ledger (what-is-cavediver.md, A27 and A26, and section 7, "The ledger").
-- IDs are the spec's.
--
-- The records are read through require('cavediver').ledger: steps(), the ring,
-- oldest first, and trail(), today's steps that made moves. Each step comes
-- back as plain fields, its rows written ⦉t⦊ [c] ⟦s⟧ with the names the step
-- captured.
local Helpers = dofile('tests/helpers.lua')
local S2 = dofile('tests/helpers_s2.lua')
local eq = Helpers.eq
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		post_once = function()
			child.stop()
		end,
	},
})

local READ = [==[
local which = ...
local ledger = require('cavediver').ledger
local function row(r, names)
	if r == nil then return nil end
	local function n(h) return h and (names[h] or '?') or '-' end
	return '⦉' .. n(r.t) .. '⦊ [' .. n(r.c) .. '] ⟦' .. n(r.s) .. '⟧'
end
local out = {}
for _, step in ipairs(which == 'trail' and ledger.trail() or ledger.steps()) do
	local moves = {}
	for _, m in ipairs(step.moves) do
		table.insert(moves, { kind = m.kind, name = m.name, lists = m.lists, dim = m.dim or false })
	end
	table.insert(out, {
		seq = step.seq, cause = step.cause, trigger = step.trigger, win = step.win,
		before = row(step.row_before, step.names), after = row(step.row_after, step.names),
		events = step.events, moves = moves,
	})
end
return out
]==]

-- The ring, or today's trail ('trail').
local function steps(which)
	return child.lua(READ, { which or 'ring' })
end

-- A note map as `x>y` lines, sorted, with the step's names.
local NOTES = [==[
local field, which = ...
local all = require('cavediver').ledger.steps()
local step = all[#all]
local map = step[field][which] or {}
local out = {}
for k, v in pairs(map) do
	local base, swap = k:gsub('%-swap$', '')
	table.insert(out, (step.names[base] or '?') .. (swap > 0 and '-swap' or '') .. '>' .. (step.names[v] or '?'))
end
table.sort(out)
return out
]==]

-- In a fresh child: the tab session t saved from a tab at ⦉c⦊ [d], then the
-- first tab at ⦉x⦊ [t] and t loaded into a second tab (T318's state). Returns
-- the two windows; the second tab is current.
local function tab_session(s)
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	local w1 = child.lua('return vim.api.nvim_get_current_win()')
	eq(child.slots(w1), '⦉x⦊ [t] ⟦-⟧')
	eq(S2.load_tab_session(child, 't'), { true })
	return w1, child.lua('return vim.api.nvim_get_current_win()')
end

-- The notifications since the last read, at one level.
local function said(level)
	local out = {}
	for _, m in ipairs(child.messages()) do
		if m.level == level then table.insert(out, m.msg) end
	end
	return out
end

T['T392 [char] (A27, A26) the ring keeps the last N steps, N from ledger.ring, 1,000 by default'] = function()
	child.setup()
	eq(child.lua('return require("cavediver.configs").ledger.ring'), 1000)
	child.lua('require("cavediver").setup({ ledger = { ring = 5 } })')
	child.steps({ ':e a', ':e b' })
	for _ = 1, 8 do
		child.steps({ '<M-f>' })
	end
	local got = steps()
	local triggers, ordered = {}, true
	for i, s in ipairs(got) do
		table.insert(triggers, s.trigger)
		if i > 1 and s.seq <= got[i - 1].seq then ordered = false end
	end
	eq({ triggers = triggers, ordered = ordered },
		{ triggers = { '<M-f>', '<M-f>', '<M-f>', '<M-f>', '<M-f>' }, ordered = true })
end

T['T393 [char] (A27) a keymap step holds its cause, trigger, window, and rows before and after with the queue and notes'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	local all = steps()
	local last = all[#all]
	local queue = child.lua([[
		local all = require('cavediver').ledger.steps()
		local step = all[#all]
		return { before = step.row_before.p, after = step.row_after.p, on = step.row_after.on }
	]])
	eq({
		cause = last.cause, trigger = last.trigger, win = last.win, before = last.before, after = last.after,
		before_dtm = child.lua(NOTES, { 'row_before', 'dtm' }), after_dsm = child.lua(NOTES, { 'row_after', 'dsm' }),
		queue = queue,
	}, {
		cause = 'keymap', trigger = '<M-f>', win = win,
		before = '⦉b.txt⦊ [c.txt] ⟦-⟧', after = '⦉-⦊ [c.txt] ⟦b.txt⟧',
		before_dtm = { 'b.txt>a.txt' }, after_dsm = { 'b.txt>a.txt' },
		queue = { before = {}, after = {}, on = false },
	})
end

T['T394 [char] (A27) a key\'s follow-ups land on its step, the events it set off listed under it'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c' })
	local n = #steps()
	child.steps({ '<M-.>' })
	child.settle(100)
	local new = vim.list_slice(steps(), n + 1)
	eq(#new, 1)
	eq({ cause = new[1].cause, trigger = new[1].trigger, events = new[1].events, moves = new[1].moves }, {
		cause = 'keymap', trigger = '<M-.>',
		events = { 'BufEnter b.txt', 'BufDelete c.txt' },
		moves = { { kind = 'closed', name = 'c.txt', lists = { 'editor' }, dim = true } },
	})
end

T['T395 [char] (A27) an event with no step open begins its own'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
	child.steps({ ':e d' })
	local all = steps()
	local last = all[#all]
	eq({ cause = last.cause, trigger = last.trigger, before = last.before, after = last.after },
		{ cause = 'event', trigger = 'BufEnter d.txt', before = '⦉c.txt⦊ [b.txt] ⟦-⟧', after = '⦉b.txt⦊ [d.txt] ⟦-⟧' })
end

T['T396 [char] (A27) a command typed on the command line is a step under its text'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c' })
	child.type_keys(':bdelete c.txt<CR>')
	child.settle(100)
	local found
	for _, s in ipairs(steps()) do
		if s.trigger == ':bdelete c.txt' then found = { cause = s.cause, moves = s.moves } end
	end
	eq(found, { cause = 'command', moves = { { kind = 'closed', name = 'c.txt', lists = { 'editor' }, dim = true } } })
end

T['T397 [char] (A27) a step that changes no row and makes no move is not kept'] = function()
	child.setup()
	child.lua('require("cavediver").setup({ cleanup_interval = 100 })')
	child.steps({ ':e a', ':e b' })
	local n = #steps()
	child.settle(500)
	child.cmd('help')
	child.settle()
	child.cmd('close')
	child.settle(100)
	eq(#steps(), n)
end

-- b is in the ternary, so wiping it without events raises nothing (T242); the
-- timer's tick or the UI's refresh repairs it, whichever comes first.
T['T398 [char] (A27, A22) the cleanup says nothing, and its repair is a move'] = function()
	child.setup()
	child.lua('require("cavediver").setup({ cleanup_interval = 100 })')
	child.steps({ ':e a', ':e b', ':e c' })
	child.messages()
	child.lua('vim.cmd("noautocmd bwipeout " .. vim.fn.bufnr("b.txt"))')
	child.settle(500)
	local report = false
	for _, m in ipairs(child.messages()) do
		if m.msg:find('CAVEDIVER CLEANUP REPORT', 1, true) then report = true end
	end
	local found
	for _, s in ipairs(steps('trail')) do
		for _, m in ipairs(s.moves) do
			if m.kind == 'repair' and m.name == 'b.txt' then
				found = { cause = s.cause, trigger = s.trigger, lists = m.lists }
			end
		end
	end
	eq({ report = report, found = found },
		{ report = false, found = { cause = 'timer', trigger = 'cleanup', lists = { 'editor' } } })
end

T['T399 [char] (A27, A16) <M-S-w> on an empty list while other lists hold closed files says so'] = function()
	local s = S2.shared()
	tab_session(s)
	child.cmd('bdelete c.txt')
	child.settle()
	child.cmd('tabprevious')
	child.settle()
	child.messages()
	child.steps({ '<M-S-w>' })
	local warns = said(vim.log.levels.WARN)
	local one = warns[1] or ''
	eq({
		count = #warns,
		empty = one:find('empty', 1, true) ~= nil,
		counted = one:find('1 closed file', 1, true) ~= nil,
		points = one:find(':CavediverClosed', 1, true) ~= nil,
		old = one:find('No closed buffers to reopen.', 1, true) ~= nil,
	}, { count = 1, empty = true, counted = true, points = true, old = false })
end

-- a is visited in the session's tab, then closed with <M-.> in the first tab,
-- which keeps its window: it goes on the first tab's list and on t's.
local function close_in_both(s)
	tab_session(s)
	child.steps({ ':e a', ':e d' })
	child.cmd('tabprevious')
	child.settle()
	child.steps({ ':e a' })
	child.messages()
	child.steps({ '<M-.>' })
	child.settle(100)
end

-- The move of a kind on a file in today's trail, or nil.
local function move_on(kind, name)
	for _, s in ipairs(steps('trail')) do
		for _, m in ipairs(s.moves) do
			if m.kind == kind and m.name == name then return m end
		end
	end
end

T['T400 [char] (A27) a close that also lands on another list says so, once the batch settles'] = function()
	local s = S2.shared()
	close_in_both(s)
	eq({ told = said(vim.log.levels.INFO), move = move_on('closed', 'a.txt') }, {
		told = { 'a.txt closed here and in t' },
		move = { kind = 'closed', name = 'a.txt', lists = { 'editor', 't' }, dim = false },
	})
end

T['T401 [char] (A27) a reopen that takes the file off another list says so'] = function()
	local s = S2.shared()
	close_in_both(s)
	child.messages()
	child.steps({ '<M-S-w>' })
	child.settle(100)
	eq({ shown = child.shown(), told = said(vim.log.levels.INFO), move = move_on('reopened', 'a.txt') }, {
		shown = 'a',
		told = { 'a.txt reopened and taken off t' },
		move = { kind = 'reopened', name = 'a.txt', lists = { 'editor', 't' }, dim = false },
	})
end

-- The first tab keeps a window on b, so :bdelete of a doesn't close the tab.
T['T402 [char] (A27) a whole-editor load drops what its batch did'] = function()
	local s = S2.shared()
	tab_session(s)
	child.steps({ ':e a', ':e d' })
	child.cmd('tabprevious')
	child.settle()
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.steps({ ':e b' })
	eq(S2.save(child), { true })
	child.messages()
	local got = child.lua([[
		vim.cmd('bdelete a.txt')
		return { pcall(require('cavediver').load_session) }
	]])
	child.settle(300)
	local told = {}
	for _, m in ipairs(child.messages()) do
		if m.msg:find('closed here', 1, true) or m.msg:find('taken off', 1, true) then table.insert(told, m.msg) end
	end
	eq({ got = got, told = told, move = move_on('closed', 'a.txt') }, { got = { true }, told = {}, move = nil })
end

-- The contract's outgoing save (resession's pre_load) runs in the same call as the
-- teardown and the load: the teardown is a step of its own, not the save's.
T['T402 [char] (A27) the outgoing save before a switch keeps the teardown out of its step'] = function()
	local s = S2.shared()
	tab_session(s)
	child.steps({ ':e a', ':e d' })
	child.cmd('tabprevious')
	child.settle()
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.steps({ ':e b' })
	eq(S2.save(child), { true })
	child.messages()
	local n = #steps()
	local got = child.lua([[
		require('cavediver').save_session()
		vim.cmd('bdelete a.txt')
		return { pcall(require('cavediver').load_session) }
	]])
	child.settle(300)
	local saves, teardown = {}, {}
	for _, st in ipairs(vim.list_slice(steps(), n + 1)) do
		if st.cause == 'save' then table.insert(saves, st.events) end
		if st.cause == 'event' and vim.tbl_contains(st.events, 'BufDelete a.txt') or st.trigger == 'BufDelete a.txt' then
			table.insert(teardown, st.trigger)
		end
	end
	local torn = child.lua([[
		for _, st in ipairs(require('cavediver').ledger.steps()) do
			if st.trigger == 'BufDelete a.txt' then return st.torn == true end
		end
		return false
	]])
	eq({ got = got, saves = saves, teardown = teardown, torn = torn, move = move_on('closed', 'a.txt') },
		{ got = { true }, saves = { {} }, teardown = { 'BufDelete a.txt' }, torn = true, move = nil })
end

return T
