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

return T
