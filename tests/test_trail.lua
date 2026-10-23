-- The trail's view, :CavediverTrail (what-is-cavediver.md, A27, and section 7,
-- "The ledger"). IDs are the spec's.
--
-- The view is a float on a buffer of its own; its keys are buffer-local, so
-- they're typed into it. Colours are read from the extmarks the view draws with,
-- never from the text.
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

-- The trail's float: { buf, win }, or vim.NIL.
local FIND = [==[
for _, w in ipairs(vim.api.nvim_list_wins()) do
	local b = vim.api.nvim_win_get_buf(w)
	if vim.bo[b].filetype == 'cavediver-trail' then return { buf = b, win = w } end
end
return vim.NIL
]==]
local function view()
	return child.lua(FIND)
end

local function lines()
	local v = view()
	if v == vim.NIL then return {} end
	return child.lua('return vim.api.nvim_buf_get_lines(..., 0, -1, false)', { v.buf })
end

-- The highlight groups drawn on a line (1-based), each with the text it covers.
local GROUPS = [==[
local buf, row = ...
local ns = vim.api.nvim_create_namespace('cavediver_trail')
local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ''
local out = {}
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { row - 1, 0 }, { row - 1, -1 }, { details = true })) do
	local d = m[4]
	if d.hl_group then
		table.insert(out, { group = d.hl_group, text = line:sub(m[3] + 1, d.end_col or #line) })
	end
end
return out
]==]
local function groups(row)
	return child.lua(GROUPS, { view().buf, row })
end

-- The group drawn on a piece of a line, or nil.
local function group_of(row, text)
	for _, g in ipairs(groups(row)) do
		if g.text == text then return g.group end
	end
end

-- The first line (1-based) holding all the pieces, or nil.
local function line_with(...)
	local pieces = { ... }
	for i, l in ipairs(lines()) do
		local all = true
		for _, p in ipairs(pieces) do
			if not l:find(p, 1, true) then all = false end
		end
		if all then return i end
	end
end

local function open_trail()
	child.cmd('CavediverTrail')
	child.settle(100)
end

-- Type keys into the trail.
local function type_in(keys)
	child.type_keys(keys)
	child.settle(100)
end

-- The tab session t saved from a tab at ⦉c⦊ [d], the first tab at ⦉x⦊ [t], and t
-- loaded into a second tab, which is current (T318's state).
local function tab_session(s)
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(S2.load_tab_session(child, 't'), { true })
end

T['T425 [char] (A27) :CavediverTrail opens the trail, untracked, on today\'s page'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
	local from = child.lua('return vim.api.nvim_get_current_win()')
	local slots = child.slots(from)
	open_trail()
	local v = view()
	local props = child.lua([[
		local b, w = ...
		return {
			buftype = vim.bo[b].buftype, listed = vim.bo[b].buflisted, hidden = vim.bo[b].bufhidden,
			float = vim.api.nvim_win_get_config(w).relative ~= '',
			hash = require('cavediver.domains.history').get_hash_from_buffer(b) ~= nil,
			triquetra = require('cavediver.domains.window').data.crux[w] ~= nil,
		}
	]], { v.buf, v.win })
	local L = lines()
	local step = line_with('⌨', '<M-.>')
	eq({
		props = props, slots = child.slots(from),
		header = L[1]:find('⦉ trail ⦊', 1, true) ~= nil and L[1]:find('today', 1, true) ~= nil and L[1]:find('1 move', 1, true) ~= nil,
		time = step and L[step]:match('^%d%d:%d%d ') ~= nil,
		move = step and L[step + 1]:find('↓ c.txt', 1, true) ~= nil and L[step + 1]:find('≡editor', 1, true) ~= nil,
	}, {
		props = { buftype = 'nofile', listed = false, hidden = 'wipe', float = true, hash = false, triquetra = false },
		slots = slots, header = true, time = true, move = true,
	})
end

T['T426 [char] (A27) H and L go to the older and the newer page'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
	child.lua([[
		local t = os.time() - 3 * 86400
		require('cavediver').ledger.data.days[os.date('%Y-%m-%d', t)] = { {
			seq = 0, time = t, cause = 'keymap', trigger = '<M-.>', names = {}, events = {},
			moves = { { kind = 'closed', name = 'old.txt', lists = { 'editor' } } },
		} }
	]])
	open_trail()
	type_in('H')
	local older = lines()[1]
	local h_dim = group_of(1, '<<< H')
	type_in('L')
	local newer = lines()[1]
	eq({ older = older:find('3 days down', 1, true) ~= nil, h_dim = h_dim, newer = newer:find('today', 1, true) ~= nil },
		{ older = true, h_dim = 'CavediverTrailKeyOff', newer = true })
end

T['T427 [char] (A27) brightness by surprise: a close onto other lists bright, the tab\'s own dim'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
	open_trail()
	local own = group_of(line_with('↓ c.txt'), '↓ ')
	type_in('q')

	local s = S2.shared()
	tab_session(s)
	child.steps({ ':e a', ':e d' })
	child.cmd('tabprevious')
	child.settle()
	child.steps({ ':e a', '<M-.>' })
	child.settle(100)
	open_trail()
	local other = group_of(line_with('↓ a.txt'), '↓ ')
	eq({ own = own, other = other }, { own = 'CavediverTrailDim', other = 'CavediverTrailClosed' })
end

T['T428 [char] (A27) more than three of a kind under one step fold to a count'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', ':e d', ':e e', ':e f' })
	child.cmd('bdelete a.txt b.txt c.txt d.txt')
	child.settle(100)
	open_trail()
	local fold = line_with('4 closed', '▸')
	local folded = line_with('↓ b.txt') == nil
	child.lua('vim.api.nvim_win_set_cursor(0, { ..., 0 })', { fold or 1 })
	type_in('za')
	local opened = {}
	for _, name in ipairs({ 'a.txt', 'b.txt', 'c.txt', 'd.txt' }) do
		if line_with('↓ ' .. name) then table.insert(opened, name) end
	end
	type_in('q')

	child.setup()
	child.steps({ ':e a', ':e b', ':e c', ':e d', ':e e' })
	child.cmd('bdelete a.txt b.txt c.txt')
	child.settle(100)
	open_trail()
	local three = { count = line_with('3 closed') ~= nil, each = line_with('↓ b.txt') ~= nil }
	eq({ fold = fold ~= nil, folded = folded, opened = opened, three = three },
		{ fold = true, folded = true, opened = { 'a.txt', 'b.txt', 'c.txt', 'd.txt' }, three = { count = false, each = true } })
end

-- The float's width set in cells.
local function at_width(cols)
	child.setup()
	child.lua('require("cavediver").setup({ trail_popup = { width = ... } })', { cols })
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
	open_trail()
	local header = lines()[1]
	type_in('q')
	return { tally = header:find('↓1', 1, true) ~= nil, gauge = header:find('❬', 1, true) ~= nil }
end

T['T429 [char] (A27) a narrow window drops the tally first, then the gauge'] = function()
	eq({ wide = at_width(120), middle = at_width(73), narrow = at_width(50) }, {
		wide = { tally = true, gauge = true }, middle = { tally = false, gauge = true }, narrow = { tally = false, gauge = false },
	})
end

T['T430 [char] (A27) the header\'s pieces can be turned off'] = function()
	child.setup()
	child.lua('require("cavediver").setup({ trail = { header = { tally = false, gauge = false, shade = false } } })')
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
	open_trail()
	local header = lines()[1]
	eq({ tally = header:find('↓1', 1, true) ~= nil, gauge = header:find('❬', 1, true) ~= nil,
		shade = header:find('≋', 1, true) ~= nil or header:find('░', 1, true) ~= nil },
		{ tally = false, gauge = false, shade = false })
end

T['T431 [char] (A27) with the ascii set, the trail draws no character outside ASCII'] = function()
	child.setup()
	child.lua('require("cavediver").setup({ glyphs = { set = "ascii" } })')
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
	open_trail()
	local wide = {}
	for i, l in ipairs(lines()) do
		if l:find('[\128-\255]') then table.insert(wide, i) end
	end
	eq({ lines = #lines() > 2, wide = wide }, { lines = true, wide = {} })
end

T['T432 [char] (A27) q and <C-c> leave, back in the window the trail came from'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
	local from = child.lua('return vim.api.nvim_get_current_win()')
	local left = {}
	for _, key in ipairs({ 'q', '<C-c>' }) do
		open_trail()
		local buf = view().buf
		type_in(key)
		table.insert(left, {
			view = view() == vim.NIL,
			buf = child.lua('return vim.api.nvim_buf_is_valid(...)', { buf }),
			back = child.lua('return vim.api.nvim_get_current_win()') == from,
		})
	end
	eq(left, { { view = true, buf = false, back = true }, { view = true, buf = false, back = true } })
end

-- Steps kept on earlier days: each `n` days ago, with `count` closes under one step.
local function plant_days(days, count)
	child.lua([[
		local days, count = ...
		local L = require('cavediver').ledger
		for _, n in ipairs(days) do
			local t = os.time() - n * 86400
			local moves = {}
			for i = 1, count do
				table.insert(moves, { kind = 'closed', name = 'old' .. i .. '.txt', lists = { 'editor' } })
			end
			L.data.days[os.date('%Y-%m-%d', t)] = { {
				seq = 0, time = t, cause = 'keymap', trigger = '<M-.>', names = {}, events = {}, moves = moves,
			} }
		end
	]], { days, count })
end

T['T433 [char] (A27) opening the trail reads only what it shows'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
	local days = {}
	for n = 1, 20 do table.insert(days, n) end
	plant_days(days, 1)
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	local listed = #child.lua('return require("cavediver.domains.storage").routines.trail_days(vim.fn.getcwd(-1, -1), nil)')
	child.lua('require("cavediver.domains.storage").routines.page_reads = 0')
	open_trail()
	local reads = child.lua('return require("cavediver.domains.storage").routines.page_reads')
	eq({ listed = listed >= 21, opened = view() ~= vim.NIL, few = reads <= 15 }, { listed = true, opened = true, few = true })
end

T['T434 [char] (A27) a fold opened on one day stays that day\'s'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', ':e d', ':e e', ':e f' })
	child.cmd('bdelete a.txt b.txt c.txt d.txt')
	child.settle(100)
	plant_days({ 2 }, 4)
	open_trail()
	local fold = line_with('4 closed', '▸')
	child.lua('vim.api.nvim_win_set_cursor(0, { ..., 0 })', { fold or 1 })
	type_in('za')
	local open_today = line_with('4 closed', '▾') ~= nil
	type_in('H')
	eq({ open_today = open_today, older = line_with('4 closed', '▸') ~= nil, older_open = line_with('4 closed', '▾') ~= nil },
		{ open_today = true, older = true, older_open = false })
end

-- L3b ------------------------------------------------------------------------------

local function cursor_to(row, col)
	child.lua('local r, c = ...; vim.api.nvim_win_set_cursor(0, { r, c })', { row, col or 0 })
end

-- Lines holding a piece.
local function count_with(piece)
	local n = 0
	for _, l in ipairs(lines()) do
		if l:find(piece, 1, true) then n = n + 1 end
	end
	return n
end

T['T435 [char] (A27) za on a step opens the ring\'s steps since the trail\'s line before'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', '<M-.>' })
	child.settle(100)
	open_trail()
	local step = line_with('<M-.>', '▸')
	cursor_to(step or 1)
	type_in('za')
	local opened = line_with('<M-f>', '⦉b⦊ [c] ⟦-⟧', '⦉-⦊ [c] ⟦b⟧') ~= nil
	cursor_to(line_with('<M-.>') or 1)
	type_in('za')
	eq({ step = step ~= nil, opened = opened, closed = line_with('<M-f>') == nil }, { step = true, opened = true, closed = true })
end

T['T436 [char] (A27) the ring\'s steps open 20 at a time'] = function()
	child.setup()
	local keys = { ':e a' }
	for i = 1, 24 do table.insert(keys, i % 2 == 1 and ':e b' or ':e a') end
	child.steps(keys)
	child.steps({ '<M-.>' })
	child.settle(100)
	open_trail()
	cursor_to(line_with('<M-.>', '▸') or 1)
	type_in('za')
	local first = { shown = count_with('BufEnter'), earlier = line_with('5 earlier steps') ~= nil }
	cursor_to(line_with('5 earlier steps') or 1)
	type_in('za')
	eq({ first = first, all = count_with('BufEnter'), earlier = line_with('earlier steps') == nil },
		{ first = { shown = 20, earlier = true }, all = 25, earlier = true })
end

T['T437 [char] (A27) a line from before this editor doesn\'t expand'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	child.steps({ ':e a', ':e b', ':e a', ':e b', ':e a' })
	child.cmd('bdelete b.txt') -- this editor's own line, which does expand
	child.settle(100)
	open_trail()
	local row = line_with('<M-.>')
	local own = line_with('BufDelete b.txt', '▸') ~= nil
	local before = #lines()
	cursor_to(row or 1)
	type_in('za')
	eq({ row = row ~= nil, mark = row and lines()[row]:find('▸', 1, true) == nil, same = #lines() == before, own = own },
		{ row = true, mark = true, same = true, own = true })
end

-- c.txt closed three days ago (a step kept then) and today.
local function closed_twice()
	child.setup()
	child.lua([[
		local t = os.time() - 3 * 86400
		require('cavediver').ledger.data.days[os.date('%Y-%m-%d', t)] = { {
			seq = 0, time = t, cause = 'keymap', trigger = '<M-.>', names = {}, events = {},
			moves = { { kind = 'closed', name = 'c.txt', lists = { 'editor' } } },
		} }
		vim.ui.input = function(_, on_confirm) on_confirm('c.txt') end
	]])
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
end

T['T438 [char] (A27) a search is a name\'s life line across every page, oldest first'] = function()
	closed_twice()
	open_trail()
	type_in('s')
	local header = lines()[1]
	local results = {}
	for i, l in ipairs(lines()) do
		if l:find('┃', 1, true) then table.insert(results, i) end
	end
	local older = child.lua('return os.date("%a %d", os.time() - 3 * 86400)')
	local first = results[1] and lines()[results[1]] or ''
	local bar = results[1] and group_of(results[1], '┃ ')
	type_in('q')
	type_in('q')
	child.cmd('CavediverTrail c.txt')
	child.settle(100)
	local again = lines()[1]
	eq({
		named = header:find('c.txt', 1, true) ~= nil, counted = header:find('2 moves over 2 days', 1, true) ~= nil,
		results = #results, oldest = first:find(older, 1, true) ~= nil, bar = bar,
		command = again:find('c.txt', 1, true) ~= nil and again:find('2 moves over 2 days', 1, true) ~= nil,
	}, { named = true, counted = true, results = 2, oldest = true, bar = 'CavediverTrailLifeClosed', command = true })
end

T['T439 [char] (A27) <CR> on a result opens its day on its step, and q goes back'] = function()
	closed_twice()
	open_trail()
	type_in('s')
	local results = {}
	for i, l in ipairs(lines()) do
		if l:find('┃', 1, true) then table.insert(results, i) end
	end
	cursor_to(results[1] or 1)
	type_in('<CR>')
	local header = lines()[1]
	local at = child.lua('return vim.api.nvim_get_current_line()')
	type_in('L')
	type_in('s')
	type_in('q')
	eq({ day = header:find('3 days down', 1, true) ~= nil, step = at:find('<M-.>', 1, true) ~= nil, back = lines()[1]:find('today', 1, true) ~= nil },
		{ day = true, step = true, back = true })
end

T['T440 [char] (A27) * searches the name under the cursor'] = function()
	closed_twice()
	open_trail()
	cursor_to(line_with('↓ c.txt') or 1, 12)
	type_in('*')
	local header = lines()[1]
	eq({ search = header:find('⌕', 1, true) ~= nil, named = header:find('c.txt', 1, true) ~= nil }, { search = true, named = true })
end

T['T441 [char] (A27) gf acts on the name under the cursor and stays'] = function()
	-- a file
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.settle(100)
	local from = child.lua('return vim.api.nvim_get_current_win()')
	open_trail()
	cursor_to(line_with('↓ c.txt') or 1, 12)
	type_in('gf')
	local file = { opened = child.shown(from), stays = view() ~= vim.NIL }
	type_in('q')

	-- a window: T411's cancel, a move on the window that cycled, the trail opened from the split
	child.setup()
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.steps({ ':e x' })
	child.cmd('wincmd p')
	local first = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', '<M-n>' })
	child.cmd('wincmd p')
	child.settle(200)
	open_trail()
	cursor_to(line_with('⇤') or 1, 12)
	type_in('gf')
	local window = child.lua('return vim.api.nvim_get_current_win()') == first

	-- a list
	local s = S2.shared()
	tab_session(s)
	child.steps({ ':e a', ':e d' })
	child.cmd('tabprevious')
	child.settle()
	child.steps({ ':e a', '<M-.>' })
	child.settle(100)
	open_trail()
	local row = line_with('↓ a.txt', '≡t')
	local col = row and lines()[row]:find('≡t', 1, true) - 1
	cursor_to(row or 1, col or 0)
	type_in('gf')
	local list = child.lua([[
		local ft = vim.bo.filetype
		return { ft = ft, line = vim.api.nvim_get_current_line() }
	]])
	eq({ file = file, window = window, list = list.ft == 'cavediver-closed-lists' and list.line:find('t', 1, true) ~= nil },
		{ file = { opened = 'c', stays = true }, window = true, list = true })
end

T['T442 [char] (A27) the formatters replace a line\'s look'] = function()
	child.setup()
	child.lua([[
		require('cavediver').setup({ formatters = {
			trail_move = function(move) if move.kind == 'closed' then return { { 'MOVE ' .. move.kind, 'Normal' } } end end,
			trail_step = function(step) return { { 'STEP ' .. step.trigger, 'Normal' } } end,
			trail_header = function() return { { 'HEADER', 'Normal' } } end,
		} })
	]])
	child.steps({ ':e a', ':e b', ':e c', ':e d', ':e c', '<M-;><M-r>' })
	child.cmd('bdelete c.txt')
	child.settle(300)
	open_trail()
	eq({ header = lines()[1], step = line_with('STEP BufDelete c.txt') ~= nil, move = line_with('MOVE closed') ~= nil,
		own = line_with('⤳') ~= nil }, { header = 'HEADER', step = true, move = true, own = true })
end

T['T443 [char] (A27) za opens a step in a search too'] = function()
	child.setup()
	child.lua([[
		local t = os.time() - 3 * 86400
		require('cavediver').ledger.data.days[os.date('%Y-%m-%d', t)] = { {
			seq = 0, time = t, cause = 'keymap', trigger = '<M-.>', names = {}, events = {},
			moves = { { kind = 'closed', name = 'c.txt', lists = { 'editor' } } },
		} }
	]])
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', '<M-.>' })
	child.settle(100)
	child.cmd('CavediverTrail c.txt')
	child.settle(100)
	local older = child.lua('return os.date("%a %d", os.time() - 3 * 86400)')
	local old_row = line_with(older, '┃')
	local today = line_with('┃', '<M-.>', '▸')
	cursor_to(today or 1)
	type_in('za')
	local opened = line_with('<M-f>', '⦉b⦊ [c] ⟦-⟧', '⦉-⦊ [c] ⟦b⟧') ~= nil
	type_in('<CR>')
	eq({ today = today ~= nil, old = old_row and lines()[old_row]:find('▸', 1, true) == nil, opened = opened,
		day = line_with('<M-.>', '▾') ~= nil and line_with('<M-f>', '⦉b⦊ [c] ⟦-⟧', '⦉-⦊ [c] ⟦b⟧') ~= nil },
		{ today = true, old = true, opened = true, day = true })
end

-- The rows of a search's results, each a line with the bar.
local function results()
	local out = {}
	for i, l in ipairs(lines()) do
		if l:find('┃', 1, true) then table.insert(out, i) end
	end
	return out
end

T['T444 [char] (A27) * on a file follows that file, and a typed name every file of that name'] = function()
	child.setup()
	child.lua([[
		vim.fn.mkdir(_G.CDV_TEST.root .. '/sub', 'p')
		vim.fn.writefile({ 'sub c' }, _G.CDV_TEST.root .. '/sub/c.txt')
		vim.ui.input = function(_, on_confirm) on_confirm('c.txt') end
	]])
	child.steps({ ':e a', ':e sub/c.txt', '<M-.>', ':e c', '<M-.>' })
	child.settle(100)
	open_trail()
	local closes = {}
	for i, l in ipairs(lines()) do
		if l:find('↓ c.txt', 1, true) then table.insert(closes, i) end
	end
	cursor_to(closes[#closes] or 1, 12)
	type_in('*')
	local star = lines()[1]
	type_in('q')
	type_in('s')
	local typed = lines()[1]
	eq({ closes = #closes, star = star:find('1 move over 1 day', 1, true) ~= nil, typed = typed:find('2 moves over 1 day', 1, true) ~= nil },
		{ closes = 2, star = true, typed = true })
end

T['T445 [char] (A27) a close by a rename or a repair turns the life line closed'] = function()
	-- the rename: b.txt copied to g.txt, b.txt closed
	child.setup()
	child.steps({ ':e a', ':e b' })
	child.cmd('saveas g.txt')
	child.settle(300)
	child.cmd('CavediverTrail b.txt')
	child.settle(100)
	local copy
	for _, row in ipairs(results()) do
		if lines()[row]:find('⧉', 1, true) then copy = group_of(row, '┃ ') end
	end
	type_in('q')
	type_in('q')

	-- the repair: b's buffer wiped without events, b kept on the editor's list
	child.setup()
	child.lua('require("cavediver").setup({ cleanup_interval = 100 })')
	child.steps({ ':e a', ':e b', ':e c' })
	child.lua('vim.cmd("noautocmd bwipeout " .. vim.fn.bufnr("b.txt"))')
	child.settle(500)
	child.cmd('CavediverTrail b.txt')
	child.settle(100)
	local repair
	for _, row in ipairs(results()) do
		if lines()[row]:find('⚒', 1, true) then repair = group_of(row, '┃ ') end
	end
	eq({ copy = copy, repair = repair }, { copy = 'CavediverTrailLifeClosed', repair = 'CavediverTrailLifeClosed' })
end

return T
