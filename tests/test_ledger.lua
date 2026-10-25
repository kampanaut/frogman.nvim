-- The ledger (what-is-cavediver.md, A27 and A26, and section 7, "The ledger").
-- IDs are the spec's.
--
-- The records are read through require('cavediver').ledger: steps(), the ring,
-- oldest first, and trail(), today's steps that made moves. Each step comes
-- back as plain fields, its rows written ⦉t⦊ [c] ⟦s⟧ with the names the step
-- captured.
local Helpers = dofile('tests/helpers.lua')
local S2 = dofile('tests/helpers_s2.lua')
local Misc = dofile('tests/helpers_misc.lua')
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
	if which == 'full' then
		moves = {}
		for _, m in ipairs(step.moves) do
			local function n(h) return h and (step.names[h] or '?') or '-' end
			local note
			if m.note then
				note = n(m.subject) .. '>' .. n(m.note.before) .. ' → ' .. n(m.subject) .. '>' .. n(m.note.after)
			end
			table.insert(moves, {
				kind = m.kind, name = m.name, words = m.words, from = m.from, by = m.by, notes = m.notes,
				row = m.row and (row(m.row.before, step.names) or '-') .. ' → ' .. (row(m.row.after, step.names) or '-') or nil,
				note = note, lists = m.lists,
			})
		end
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
		if s.trigger == ':bdelete c.txt' then found = { cause = s.cause, first = s.moves[1] } end
	end
	eq(found, { cause = 'command', first = { kind = 'closed', name = 'c.txt', lists = { 'editor' }, dim = true } })
end

T['T396 [char] (A27) a path typed on the command line is kept as its last part'] = function()
	child.setup()
	child.steps({ ':e a' })
	local root = child.lua('return _G.CDV_TEST.root')
	child.type_keys(':e ' .. root .. '/b.txt<CR>')
	child.settle(100)
	local triggers = {}
	for _, s in ipairs(steps()) do table.insert(triggers, s.trigger) end
	eq({ cut = vim.tbl_contains(triggers, ':e b.txt'), whole = vim.tbl_contains(triggers, ':e ' .. root .. '/b.txt') },
		{ cut = true, whole = false })
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
	local one = said(vim.log.levels.WARN)
	-- three on t's list: a and b visited in t's tab and closed there, not shown
	child.cmd('tabnext')
	child.steps({ ':e a', ':e b', ':e d' })
	child.cmd('bdelete a.txt')
	child.cmd('bdelete b.txt')
	child.settle()
	child.cmd('tabprevious')
	child.settle()
	child.messages()
	child.steps({ '<M-S-w>' })
	local three = said(vim.log.levels.WARN)
	eq({ one = one, three = three }, {
		one = { "No closed buffers to reopen in this tab.\n1 is on another tab's list: :CavediverClosed" },
		three = { "No closed buffers to reopen in this tab.\n3 are on other tabs' lists: :CavediverClosed" },
	})
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

-- The move of a kind on a file in today's trail, or nil; `but` leaves out the
-- steps of that cause.
local function move_on(kind, name, but)
	for _, s in ipairs(steps('trail')) do
		for _, m in ipairs(s.moves) do
			if m.kind == kind and m.name == name and s.cause ~= but then return m end
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
	eq({ got = got, told = told, move = move_on('closed', 'a.txt', 'load') }, { got = { true }, told = {}, move = nil })
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
	eq({ got = got, saves = saves, teardown = teardown, torn = torn, move = move_on('closed', 'a.txt', 'load') },
		{ got = { true }, saves = { {} }, teardown = { 'BufDelete a.txt' }, torn = true, move = nil })
end

-- L1b: the other moves --------------------------------------------------------

-- The first move of a kind on a name in the ring, with its step's cause and
-- trigger; name nil matches any.
local function found(kind, name)
	for _, st in ipairs(steps('full')) do
		for _, m in ipairs(st.moves) do
			if m.kind == kind and (name == nil or m.name == name) then
				m.cause, m.trigger = st.cause, st.trigger
				return m
			end
		end
	end
end

local function told(text)
	for _, m in ipairs(child.messages()) do
		if m.msg:find(text, 1, true) then return true end
	end
	return false
end

T['T403 [char] (A27, A21) cleanup\'s re-point is a move, and its pop-up stays'] = function()
	child.setup()
	child.steps({ ':e d', ':e b', ':e c', '<M-f>', ':e a' })
	eq(child.slots(), '⦉c⦊ [a] ⟦b⟧')
	child.messages()
	child.cmd('noautocmd buffer d.txt')
	child.cmd('bwipeout a.txt')
	child.settle(100)
	local healed = told('Healed the triquetra')
	local m = found('repointed')
	eq({ healed = healed, trigger = m and m.trigger, row = m and m.row },
		{ healed = true, trigger = 'BufDelete a.txt', row = '⦉c.txt⦊ [a.txt] ⟦b.txt⟧ → ⦉a.txt⦊ [d.txt] ⟦b.txt⟧' })
end

T['T404 [char] (A27, A19) the landing after a delete is a move on the delete\'s step'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', ':e d', ':e c', '<M-;><M-r>' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	child.cmd('bdelete c.txt')
	child.settle(300)
	local got
	for _, st in ipairs(steps('full')) do
		if st.trigger == 'BufDelete c.txt' then
			local kinds = {}
			for _, m in ipairs(st.moves) do table.insert(kinds, m.kind) end
			local landed = found('landed')
			got = { kinds = kinds, from = landed and landed.from, row = landed and landed.row }
		end
	end
	eq(got, { kinds = { 'closed', 'landed' }, from = 'ternary', row = '⦉b.txt⦊ [c.txt] ⟦-⟧ → ⦉-⦊ [b.txt] ⟦-⟧' })
end

T['T405 [char] (A27, I10) an arrival undone is a move'] = function()
	child.setup()
	child.steps({ ':e a', ':enew' })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "plugin text" })')
	child.cmd('setlocal buftype=nofile')
	child.settle(100)
	local m = found('undone')
	eq({ trigger = m and m.trigger, row = m and m.row },
		{ trigger = 'OptionSet buftype', row = '⦉a.txt⦊ [[No Name]] ⟦-⟧ → ⦉-⦊ [a.txt] ⟦-⟧' })
end

T['T406 [char] (A27, A21) a triquetra dropped is a move'] = function()
	child.setup()
	child.steps({ ':e a', ':enew' })
	local n = child.lua('return vim.api.nvim_get_current_buf()')
	-- a scratch shown in the window: it's visiting, with the empty No Name buffer hidden as its current slot
	child.lua('vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(false, true))')
	child.settle(100)
	child.cmd('bwipeout ' .. n)
	child.settle(100)
	local m = found('dropped')
	eq({ dropped = m ~= nil, triquetra = child.lua('return require("cavediver.domains.window").data.crux[vim.api.nvim_get_current_win()] ~= nil') },
		{ dropped = true, triquetra = false })
end

T['T407 [char] (A27, M7) keep the older one\'s rewrite is a move'] = function()
	child.setup()
	child.steps({ ':e a', ':e c', ':e e', ':e b', '<M-f>', ':e c', '<M-S-f>', '<M-f>' })
	eq(child.slots(), '⦉c⦊ [e] ⟦b⟧')
	local m = found('rewritten', 'e.txt')
	eq({ trigger = m and m.trigger, note = m and m.note },
		{ trigger = '<M-f>', note = 'e.txt>c.txt → e.txt>a.txt' })
end

T['T408 [char] (A27, Q6) Q6\'s guard is a move, and its pop-up stays'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', ':e b', '<M-f>', ':e a', '<M-f>' })
	child.messages()
	child.steps({ '<M-f>' })
	local warned = told('Avoided conflict')
	local m = found('rewritten', 'b.txt')
	eq({ warned = warned, trigger = m and m.trigger, by = m and m.by, note = m and m.note },
		{ warned = true, trigger = '<M-f>', by = 'guard', note = 'b.txt>a.txt → b.txt>c.txt' })
end

T['T409 [char] (A27, A1) navigation\'s own check is a move, and its pop-up stays'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', ':e a' })
	child.messages()
	child.steps({ ':e b' })
	local warned = told('switching with the pre-jump ternary.')
	local m = found('rewritten', 'b.txt')
	eq({ warned = warned, trigger = m and m.trigger, by = m and m.by, note = m and m.note },
		{ warned = true, trigger = 'BufEnter b.txt', by = 'navigation', note = 'b.txt>a.txt → b.txt>c.txt' })
end

T['T410 [char] (A27, P10) a file forgotten by follow along is a move, with the notes that went'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', ':enew' })
	local n = child.lua('return vim.api.nvim_get_current_buf()')
	child.steps({ ':e b', ':e d' })
	child.cmd('bwipeout ' .. n)
	child.settle(100)
	local m = found('forgotten', '[No Name]')
	eq({ notes = m and m.notes, trigger = m and m.trigger }, { notes = 2, trigger = 'BufDelete [No Name]' })
end

T['T411 [char] (A27, A12) the cancel on a window jump is a move on the jump\'s step'] = function()
	child.setup()
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.steps({ ':e x' })
	child.cmd('wincmd p')
	child.steps({ ':e c', '<M-n>' })
	child.cmd('wincmd p')
	child.settle(200)
	local m = found('cancelled')
	eq({ trigger = m and m.trigger, words = m and m.words }, { trigger = 'WinEnter win 1', words = 'cycle cancelled; back on c.txt' })
end

T['T412 [char] (A27, S1) a load\'s moves: windows matched, references closed'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'c', 'd' }, 'd')
	eq(S2.load(child), { true })
	child.settle(300)
	local loaded, closed = found('loaded'), found('closed', 'b.txt')
	eq({ loaded = loaded and loaded.words, loaded_by = loaded and loaded.cause, closed = closed and closed.cause },
		{ loaded = '1 window matched', loaded_by = 'load', closed = 'load' })
end

T['T413 [char] (A27, S1) a load with no file is a fresh start'] = function()
	child.setup()
	child.steps({ ':e a' })
	child.lua('require("cavediver").load_session("nothing")')
	child.settle(100)
	local m = found('fresh')
	eq({ cause = m and m.cause, trigger = m and m.trigger }, { cause = 'load', trigger = 'nothing' })
end

T['T414 [char] (A27, S1) a tab-session save\'s moves: saved, and the whole editor\'s records refreshed'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(S2.save(child), { true })
	eq(S2.load_tab_session(child, 't'), { true })
	child.cmd('tabprevious')
	child.cmd('bdelete x.txt')
	child.steps({ ':e e' })
	child.cmd('tabnext')
	child.settle()
	child.lua('require("cavediver").save_session("t", { tab = vim.api.nvim_get_current_tabpage() })')
	child.settle(100)
	-- the save's own move on its step; the whole editor's records refreshed on a step of their own
	local kinds = {}
	for _, st in ipairs(steps('full')) do
		if st.cause == 'save' then
			local here = {}
			for _, m in ipairs(st.moves) do table.insert(here, m.kind) end
			kinds[st.trigger == 't' and 't' or 'editor'] = here
		end
	end
	eq(kinds, { t = { 'saved' }, editor = { 'refreshed' } })
end

T['T415 [char] (A27, S1) :restart\'s reload is a step of its own'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, 'p')
	local session = dir .. '/restart_session_T415xy'
	child.cmd('mksession! ' .. vim.fn.fnameescape(session))
	S2.start_restarted(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.lua([[
		pcall(require('cavediver').load_session, vim.fn.getcwd())
		vim.cmd('source ' .. vim.fn.fnameescape(...))
	]], { session })
	child.settle(300)
	local causes = {}
	for _, st in ipairs(steps()) do
		if st.cause == 'load' or st.cause == 'restart' then table.insert(causes, st.cause) end
	end
	-- the restart session's own events, sourced with events on, are a step the rerun's load tears down
	local before = child.lua([[
		local all = require('cavediver').ledger.steps()
		for i, st in ipairs(all) do
			if st.cause == 'restart' then
				local prev = all[i - 1]
				return prev and { cause = prev.cause, torn = prev.torn == true, moves = #prev.moves } or vim.NIL
			end
		end
		return vim.NIL
	]])
	eq({ causes = causes, before = before }, { causes = { 'load', 'restart' }, before = { cause = 'event', torn = true, moves = 0 } })
end

T['T416 [char] (A27) a tab session\'s tab closed is a move'] = function()
	local s = S2.shared()
	tab_session(s)
	child.cmd('bdelete c.txt')
	child.settle()
	child.cmd('tabclose')
	child.settle(300)
	local m = found('tab_closed', 't')
	eq(m ~= nil, true)
end

T['T417 [char] (A27, A20) renames are moves: a copy, and a No Name buffer written under a name'] = function()
	child.setup()
	child.steps({ ':e a', ':e b' })
	child.cmd('saveas g.txt')
	child.settle(300)
	local copy = found('copied', 'b.txt')
	child.steps({ ':enew' })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "draft" })')
	child.cmd('write new.txt')
	child.settle(300)
	local move = found('moved', '[No Name]')
	eq({ copy = copy and copy.words, move = move and move.words },
		{ copy = 'renamed to g.txt: a copy, b.txt is still on disk', move = 'written as new.txt: a move' })
end

T['T418 [char] (A27, M14) a change of label is a step, and tags are moves'] = function()
	child.setup()
	child.lua([[
		vim.fn.mkdir(_G.CDV_TEST.root .. '/.git', 'p')
		vim.fn.writefile({ 'ref: refs/heads/feature' }, _G.CDV_TEST.root .. '/.git/HEAD')
	]])
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	child.cmd('bdelete b.txt')
	child.settle()
	child.cmd('doautocmd FocusGained')
	child.settle()
	child.lua('os.remove(_G.CDV_TEST.root .. "/b.txt")')
	child.lua('vim.fn.writefile({ "ref: refs/heads/main" }, _G.CDV_TEST.root .. "/.git/HEAD")')
	child.settle(300)
	local gone = found('gone', 'b.txt')
	child.lua('vim.fn.writefile({ "b" }, _G.CDV_TEST.root .. "/b.txt")')
	child.lua('require("cavediver.domains.history").cleanup_system()')
	child.settle(100)
	local back = found('back', 'b.txt')
	eq({ cause = gone and gone.cause, trigger = gone and gone.trigger, tag = gone and gone.words, back = back ~= nil },
		{ cause = 'label', trigger = 'feature → main', tag = 'gone from disk ⎇feature', back = true })
end

T['T419 [char] (A27, M5) detached lists are moves: made, and left into the whole editor\'s file'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s)
	eq(S2.save(child), { true })
	child.steps({ ':e e', ':e d' })
	child.cmd('bdelete e.txt')
	child.settle()
	eq(S2.load_tab_session(child, 't'), { true })
	local made = found('detached', 't_DETACHED')
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	local left = found('detached_left', 't_DETACHED')
	eq({ made = made and made.cause, left = left and left.words },
		{ made = 'load', left = 'into the whole editor\'s file' })
end

-- L2: the trail's pages ---------------------------------------------------------

-- A day's page of a session's trail (today's by default), as a fresh read finds
-- it: each step's trigger and its moves, `kind name`. nil when there's none.
local PAGE = [==[
local name, day = ...
if name == vim.NIL then name = nil end
if day == vim.NIL then day = nil end
local steps = require('cavediver.domains.storage').routines.read_trail(vim.fn.getcwd(-1, -1), name, day or os.date('%Y-%m-%d'))
if steps == nil then return vim.NIL end
local out = {}
for _, step in ipairs(steps) do
	local moves = {}
	for _, m in ipairs(step.moves or {}) do table.insert(moves, m.kind .. ' ' .. (m.name or '?')) end
	table.insert(out, { trigger = step.trigger, moves = moves })
end
return out
]==]
local function page(name, day)
	return child.lua(PAGE, { name or vim.NIL, day or vim.NIL })
end

-- The `closed …` moves of a page, in order.
local function closes(steps)
	local out = {}
	for _, st in ipairs(type(steps) == 'table' and steps or {}) do
		for _, m in ipairs(st.moves) do
			if m:match('^closed ') then table.insert(out, m) end
		end
	end
	return out
end

-- Today's page file of the nameless session, by its path.
local PAGE_FILE = [==[
local st = require('cavediver.domains.storage').routines
local dir = vim.fn.getcwd(-1, -1)
local saved = st.read_session(dir, nil)
local name = saved and saved.trail and saved.trail[os.date('%Y-%m-%d')]
if not name then return vim.NIL end
for _, entry in ipairs(vim.fn.readdir(require('cavediver.configs').session_dir)) do
	local path = require('cavediver.configs').session_dir .. entry .. '/' .. name
	if entry:match('%.d$') and vim.uv.fs_stat(path) then return path end
end
return vim.NIL
]==]

T['T420 [char] (A27) a save writes today\'s page, sealed, and a fresh process reads it back'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
	eq(S2.save(child), { true })
	local path = child.lua(PAGE_FILE)
	local clear = path ~= vim.NIL and table.concat(vim.fn.readfile(path, 'b'), '\n'):find('c.txt', 1, true) ~= nil
	S2.start(child, s)
	local held = false
	for _, st in ipairs(page() ~= vim.NIL and page() or {}) do
		if st.trigger == '<M-.>' and vim.tbl_contains(st.moves, 'closed c.txt') then held = true end
	end
	eq({ file = path ~= vim.NIL, clear = clear, held = held }, { file = true, clear = false, held = true })
end

T['T421 [char] (A27) today\'s page rides with the records'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c' })
	eq(S2.save(child), { true })
	child.cmd('bdelete b.txt')
	child.settle(1500)
	eq(vim.tbl_contains(closes(page()), 'closed b.txt'), true)
end

T['T422 [char] (A27) a load reads no page'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
	eq(S2.save(child), { true })
	S2.start(child, s) -- the first editor's quit writes the page again, so it's damaged after
	local path = child.lua(PAGE_FILE)
	eq(path ~= vim.NIL, true)
	-- one byte of the page flipped
	local bytes = table.concat(vim.fn.readfile(path, 'b'), '\n')
	local i = math.floor(#bytes / 2)
	bytes = bytes:sub(1, i - 1) .. string.char((bytes:byte(i) + 1) % 256) .. bytes:sub(i + 1)
	local f = assert(io.open(path, 'wb'))
	f:write(bytes)
	f:close()
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.messages()
	eq(S2.load(child), { true })
	child.settle(300)
	local warned = {}
	for _, m in ipairs(child.messages()) do
		if m.level == vim.log.levels.WARN then table.insert(warned, m.msg) end
	end
	eq({ warned = warned, page = page() }, { warned = {}, page = vim.NIL })
end

T['T423 [char] (A27) pages outlive the editor that wrote them'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
	-- a step the first editor kept on an earlier day
	child.lua([[
		require('cavediver').ledger.data.days['2026-10-20'] = { {
			seq = 0, time = os.time({ year = 2026, month = 10, day = 20, hour = 9 }), cause = 'keymap',
			trigger = '<M-.>', names = {}, events = {}, moves = { { kind = 'closed', name = 'old.txt' } },
		} }
	]])
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	child.steps({ ':e a', ':e b', '<M-.>' })
	child.settle(100)
	eq(S2.save(child), { true })
	local days = child.lua('return require("cavediver.domains.storage").routines.trail_days(vim.fn.getcwd(-1, -1), nil)')
	eq({ closes = closes(page()), earlier = vim.tbl_contains(days, '2026-10-20') },
		{ closes = { 'closed c.txt', 'closed b.txt' }, earlier = true })
end

T['T424 [char] (A27) each file keeps its own moves'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(S2.save(child), { true })
	eq(S2.load_tab_session(child, 't'), { true })
	child.cmd('tabprevious')
	child.cmd('bdelete x.txt')
	child.settle()
	child.cmd('tabnext')
	child.cmd('bdelete c.txt')
	child.settle(1500)
	-- t's own steps, its save (in the first editor) and its load, are in its file and not the whole editor's
	local function own(steps)
		local out = {}
		for _, st in ipairs(type(steps) == 'table' and steps or {}) do
			for _, m in ipairs(st.moves) do
				if m == 'saved t' or m == 'loaded t' then out[m] = true end
			end
		end
		return out
	end
	local t_page, editor_page = page('t'), page()
	eq({ t = closes(t_page), editor = closes(editor_page), t_own = own(t_page), editor_own = own(editor_page) },
		{ t = { 'closed c.txt' }, editor = { 'closed x.txt' }, t_own = { ['saved t'] = true, ['loaded t'] = true }, editor_own = {} })
end

-- The current tab's trail today, as its reader gives it: each step's trigger and
-- its moves, `kind name`.
local READER = [==[
local out = {}
for _, step in ipairs(require('cavediver.domains.storage').routines.trail_reader().steps(os.date('%Y-%m-%d'))) do
	local moves = {}
	for _, m in ipairs(step.moves or {}) do table.insert(moves, m.kind .. ' ' .. (m.name or '?')) end
	table.insert(out, { trigger = step.trigger, moves = moves })
end
return out
]==]

-- Whether any step of a page holds the move `kind name`.
local function holds(steps, move)
	for _, st in ipairs(type(steps) == 'table' and steps or {}) do
		if vim.tbl_contains(st.moves, move) then return true end
	end
	return false
end

T['T516 [char] (A27, S1) each whole-editor session\'s file keeps the moves made under it'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' }) -- before any session: c's close goes to the first one
	child.settle(100)
	eq(S2.save(child, 'B'), { true })
	eq(S2.load(child, 'A'), { true }) -- no file: a fresh start, and A is the whole editor's session
	child.settle(300)
	child.steps({ ':e d', ':e e', '<M-.>' })
	child.settle(100)
	eq(S2.save(child, 'A'), { true })
	eq(S2.load(child, 'B'), { true })
	child.settle(300)
	local trail = child.lua(READER)
	eq(S2.save(child, 'B'), { true })
	local b_page, a_page = page('B'), page('A')
	-- a save under another name: its moves from then on are its own
	eq(S2.save(child, 'C'), { true })
	child.cmd('bdelete d.txt')
	child.settle(1500)
	local c_page = page('C')
	-- C's own save is on C's page, and on no other
	local saved = { c = holds(c_page, 'saved C'), elsewhere = holds(page('B'), 'saved C') or holds(page('A'), 'saved C') }
	eq({
		trail = { c = holds(trail, 'closed c.txt'), e = holds(trail, 'closed e.txt') },
		b = { c = holds(b_page, 'closed c.txt'), e = holds(b_page, 'closed e.txt'), loaded = holds(b_page, 'loaded B') },
		a = { c = holds(a_page, 'closed c.txt'), e = holds(a_page, 'closed e.txt') },
		c = closes(c_page),
		saved = saved,
	}, {
		trail = { c = true, e = false },
		b = { c = true, e = false, loaded = true },
		a = { c = false, e = true },
		c = { 'closed d.txt' },
		saved = { c = true, elsewhere = false },
	})
end

return T
