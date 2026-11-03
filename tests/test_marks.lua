-- Frogman's marks (M15). IDs are the spec's (what-is-frogman.md, section 7).
local Helpers = dofile('tests/helpers.lua')
local S2 = dofile('tests/helpers_s2.lua')
local Misc = dofile('tests/helpers_misc.lua')
local eq = Helpers.eq
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = child.stop,
	},
})

local ADD = "<M-'><M-'><M-"
local JUMP = "<M-'><M-"

-- The messages said since the last call, their text alone.
local function said()
	return vim.tbl_map(function(m) return m.msg end, child.messages())
end

-- A file's line deleted in the closed lists and written.
local function discard(name)
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, S2.line_of(lines, name))
	S2.write_picker(child, p, lines)
	child.cmd('close')
	child.settle(100)
end

-- The aliases a file has in the current mode's scope, by its name: the scope of the window you're
-- in, or, from the marks pop-up, of the window it was opened from.
local function label(name)
	return child.lua([[
		local H = require('frogman.domains.history')
		local popup = require('frogman.domains.marks').popup
		local win = popup.is_current() and popup.origin() or nil
		return require('frogman.domains.marks').label_of(H.routines.get_filehash(_G.FRG_TEST.root .. '/' .. ... .. '.txt'), win) or false
	]], { name })
end

T['T711 [char] (M15) harpoon is gone'] = function()
	child.lua([[_G.FRG_TEST.setup({ marks_provider = function() error('read') end })]])
	local warned = vim.tbl_filter(function(m) return m:find('marks_provider is gone', 1, true) ~= nil end, said())
	child.cmd('FrogmanIndicators harpoon off')
	local refused = vim.tbl_filter(function(m) return m:find('roles or marks', 1, true) ~= nil end, said())
	local colors = child.lua('local c = require("frogman.configs").colors; return { c.marked ~= nil, c.harpooned == nil }')
	local readme = table.concat(vim.fn.readfile('README.md'), '\n')
	eq({ warned = #warned, refused = #refused, colors = colors, readme = readme:find('- harpoon', 1, true) == nil },
		{ warned = 1, refused = 1, colors = { true, true }, readme = true })
end

T['T712 [char] (M15) the modes'] = function()
	child.steps({ ':e a' })
	local mode = 'return require("frogman.domains.marks").data.mode'
	local first = child.lua(mode)
	child.steps({ "<M-'><M-2>" })
	local tab = child.lua(mode)
	child.steps({ ADD .. 'a>' })
	local in_tab = child.lua('return vim.tbl_count(require("frogman.domains.marks").data.scopes.tab)')
	child.steps({ "<M-'><M-3>", ADD .. 's>' })
	local session = child.lua('local s = require("frogman.domains.marks").data.scopes.session[""]; return s and vim.tbl_count(s.groups[1].marks)')
	-- a tab session's tab: its tab mode is the session's
	child.lua('require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()] = "t\\n/x"')
	local kind = child.lua('return { require("frogman.domains.marks.routines").scope_key("tab") }')
	eq({ first, tab, in_tab, session, kind }, { 'window', 'tab', 1, 1, { 'session', 't\n/x' } })
end

T['T713 [char] (M15) the aliases are checked one to one'] = function()
	local ok, err = unpack(child.lua([[
		local ok, err = pcall(require('frogman').setup, { marks = { aliases = { a = 1, s = 1 } } })
		return { ok, tostring(err) }
	]]))
	child.lua('_G.FRG_TEST.setup({ marks = { aliases = { q = 1 } } })')
	local keys = child.lua([[return { vim.fn.maparg("<M-'><M-q>", 'n') ~= '', vim.fn.maparg("<M-'><M-a>", 'n') ~= '' }]])
	eq({ ok, err:find('a and s', 1, true) ~= nil, keys }, { false, true, { true, false } })
end

T['T714 [char] (M15, M2 Handles) a mark follows its file'] = function()
	child.steps({ ':e a', ':e b', ADD .. 'a>' })
	child.lua([[
		local root = _G.FRG_TEST.root
		os.rename(root .. '/b.txt', root .. '/g.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/b.txt'), root .. '/g.txt')
	]])
	child.settle(300)
	child.steps({ ':e a', JUMP .. 'a>' })
	eq(child.shown(), 'g')
end

T['T715 [char] (M15, M2 Holders) a marked file stays known'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e a' })
	child.cmd('bdelete b.txt')
	child.settle()
	discard('b.txt')
	local kept = child.lua([[
		local H = require('frogman.domains.history')
		local hash = H.routines.get_filehash(_G.FRG_TEST.root .. '/b.txt')
		return { H.get_filepath_from_hash(hash) ~= nil, H.handles.of_hash(hash) ~= nil }
	]])
	child.steps({ JUMP .. 'a>' })
	eq({ kept, child.shown() }, { { true, true }, 'b' })
end

T['T716 [char] (M15) holders keep it'] = function()
	child.steps({ ':e x', ADD .. 'a>', ':e a' })
	eq(child.slots(), '⦉x⦊ [a] ⟦-⟧')
	child.cmd('bdelete x.txt')
	child.settle()
	discard('x.txt')
	local slots = child.slots()
	child.steps({ '<M-S-f>' })
	eq({ slots, child.shown() }, { '⦉x⦊ [a] ⟦-⟧', 'x' })
end

T['T717 [char] (M15) the add'] = function()
	child.steps({ ':e a', ':e b', ADD .. 'a>' })
	local bar = child.lua('return vim.wo.winbar')
	child.steps({ ADD .. 's>' })
	local label_b = child.lua('return require("frogman.domains.marks").label_of(require("frogman.domains.history").get_hash_from_buffer(vim.api.nvim_get_current_buf()))')
	child.steps({ ':e c', ADD .. 'a>' })
	local conflict = child.lua([[
		local buf = vim.fn.bufnr('frogman://marks')
		return buf ~= -1 and vim.api.nvim_get_current_buf() == buf and vim.api.nvim_buf_get_lines(buf, 1, 3, false) or false
	]])
	local c_marked = label('c')
	child.lua('local b = vim.fn.bufnr("frogman://marks"); if b ~= -1 then vim.api.nvim_buf_delete(b, { force = true }) end')
	child.settle()
	child.cmd('help')
	child.settle()
	said()
	child.steps({ ADD .. 'd>' })
	local untracked = said()
	eq({ bar = bar:find('⟨a⟩ marked', 1, true) ~= nil, label = label_b, conflict = conflict, c_marked = c_marked, untracked = untracked },
		{ bar = true, label = 'a,s', conflict = { 'a -> c.txt', 'a -> b.txt' }, c_marked = false,
		untracked = { 'frogman: only files can be marked.' } })
end

T['T718 [char] (M15) the jump'] = function()
	child.steps({ ':e a', ADD .. 'a>', ':e c', ADD .. 's>', ':e b', JUMP .. 'a>' })
	local jumped = { child.shown(), child.slots(), child.notes() }
	child.cmd('bdelete c.txt')
	child.settle()
	child.steps({ JUMP .. 's>' })
	local reopened = child.shown()
	child.steps({ ':e a' })
	child.cmd('bdelete c.txt')
	child.settle()
	child.lua('os.remove(_G.FRG_TEST.root .. "/c.txt")')
	said()
	child.steps({ JUMP .. 's>' })
	local gone = said()
	child.steps({ '<M-m>' })
	said()
	child.steps({ JUMP .. 'a>' })
	local cycling = said()
	eq({ jumped = jumped[1], slots = jumped[2], reopened = reopened, gone = gone[1] and gone[1]:find("isn't on disk right now; the mark keeps it", 1, true) ~= nil,
		cycling = cycling },
		{ jumped = 'a', slots = '⦉b⦊ [a] ⟦-⟧', reopened = 'c', gone = true, cycling = { 'frogman: pick or cancel the cycle first.' } })
end

T['T719 [char] (M15) the bufferline shows a file\'s aliases in the mode\'s scope'] = function()
	child.steps({ ':e a', ':e b', ADD .. 'a>', ADD .. 's>', ':e c' })
	child.settle(300)
	local b = child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/b.txt")')
	local lookup = 'local bl = require("frogman").bufferline; return { bl.is_marked(...), bl.get_mark_labels(...) }'
	local window = child.lua(lookup, { b })
	child.steps({ "<M-'><M-2>" })
	child.settle(300)
	local tab = child.lua(lookup, { b })
	eq({ window, tab[1] }, { { true, 'a,s' }, false })
end

T['T720 [char] (M15, M5) a marked empty No Name text is kept'] = function()
	child.steps({ ':e a', ':enew' })
	local n = child.lua('return vim.api.nvim_get_current_buf()')
	local hash = child.lua('return require("frogman.domains.history").get_hash_from_buffer(...)', { n })
	child.steps({ ADD .. 'a>', ':e b' })
	child.cmd('bwipeout ' .. n)
	child.settle(100)
	local kept = child.lua([[
		local H = require('frogman.domains.history')
		local h = H.handles.of_hash(...)
		return { closed = H.routines.is_filehash_closed(...), state = h and h:state() or false }
	]], { hash })
	child.steps({ JUMP .. 'a>' })
	local back = child.lua('return { vim.api.nvim_buf_get_name(0), vim.api.nvim_buf_get_lines(0, 0, -1, false) }')
	eq({ kept, back }, { { closed = false, state = 'closed' }, { '', { '' } } })
end

T['T721 [char] (M15, A21) a visiting window keeps a closed current slot a mark holds'] = function()
	child.steps({ ':e a', ':e x', ADD .. 'a>' })
	child.lua('vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, true))')
	child.settle()
	child.cmd('bdelete x.txt')
	child.settle()
	discard('x.txt')
	child.lua('require("frogman.domains.history").routines.cleanup_system()')
	child.settle(100)
	eq(child.slots(), '⦉a⦊ [x] ⟦-⟧')
end

-- Saved and loaded (M15, 4b) ---------------------------------------------------------


-- A tab session t saved from a second tab at ⦉c⦊ [d] (S2.save_tab_session),
-- then a fresh editor with its first tab at ⦉x⦊ [t] loads t into a second tab
-- (T318's state). Returns t's window.
local function tab_session(s)
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(S2.load_tab_session(child, 't'), { true })
	return child.lua('return vim.api.nvim_get_current_win()')
end

-- t saved again from the tab it's in.
local function save_t()
	return child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }')
end

-- What a jump in the current window opens: its buffer's name's last part, or "[No Name]" with its lines.
local function opened()
	return child.lua([[
		local name = vim.api.nvim_buf_get_name(0)
		if name == '' then
			return { '[No Name]', vim.api.nvim_buf_get_lines(0, 0, -1, false) }
		end
		return { vim.fn.fnamemodify(name, ':t:r') }
	]])
end

T['T722 [char] (M15, S1) a session\'s own marks come back'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ "<M-'><M-3>", ':e a', ADD .. 'a>', ':e c', ADD .. 's>', ':e b' })
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b', 'c' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	child.steps({ "<M-'><M-3>" })
	local a = label('a')
	child.steps({ JUMP .. 's>' })
	eq({ a = a, jumped = child.shown() }, { a = 'a', jumped = 'c' })
end

-- Saved: the split (listed first, with 'splitright' off as the harness runs) on c, its mark a -> a,
-- and the first window on b, its mark a -> d. The windows come back the other way round.
T['T723 [char] (M15, S1) window marks ride on their window\'s entry'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e d', ADD .. 'a>', ':e b' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e a', ADD .. 'a>', ':e c' })
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b', 'c', 'd' }, 'c')
	child.cmd('noautocmd vsplit')
	child.cmd('noautocmd edit b.txt')
	local wins = child.lua('return vim.api.nvim_tabpage_list_wins(0)')
	eq({ child.shown(wins[1]), child.shown(wins[2]) }, { 'b', 'c' })
	eq(S2.load(child), { true })
	child.settle(300)
	local got = {}
	for _, win in ipairs(wins) do
		child.lua('vim.api.nvim_set_current_win(...)', { win })
		child.settle()
		child.steps({ JUMP .. 'a>' })
		table.insert(got, child.shown(win))
	end
	eq(got, { 'd', 'a' })
end

T['T724 [char] (M15, M5) a marked No Name text comes back for its mark'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':enew' })
	local n = child.lua('return vim.api.nvim_get_current_buf()')
	child.steps({ ADD .. 'a>' })
	child.cmd('buffer a.txt') -- :edit would take the empty buffer over for the file it opens
	child.settle()
	child.cmd('bwipeout ' .. n)
	child.settle(100)
	eq(child.shown(), 'a')
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a' }, 'a')
	eq(S2.load(child), { true })
	child.settle(300)
	local closed = child.closed()
	child.steps({ JUMP .. 'a>' })
	eq({ closed = closed, opened = opened() }, { closed = '', opened = { '[No Name]', { '' } } })
end

T['T725 [char] (M15, S1 Records) a records write keeps the texts a tab session\'s marks hold'] = function()
	local s = S2.shared()
	tab_session(s)
	child.steps({ "<M-'><M-3>", ':enew' })
	local n = child.lua('return vim.api.nvim_get_current_buf()')
	child.steps({ ADD .. 'a>', ':e d' })
	child.cmd('bwipeout ' .. n)
	child.settle(100)
	eq(save_t(), { true })
	child.cmd('bdelete c.txt')
	child.settle(1200) -- the records' second runs out, and they're written
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(S2.load_tab_session(child, 't'), { true })
	child.steps({ "<M-'><M-3>", JUMP .. 'a>' })
	eq(opened(), { '[No Name]', { '' } })
end

T['T726 [char] (M15, S1) a tab session keeps the path of a file only a mark holds'] = function()
	local s = S2.shared()
	tab_session(s)
	child.steps({ "<M-'><M-3>", ':e e', ADD .. 'a>', ':e d' })
	child.cmd('bdelete e.txt')
	child.settle()
	discard('e.txt')
	eq(save_t(), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(S2.load_tab_session(child, 't'), { true })
	child.steps({ "<M-'><M-3>", JUMP .. 'a>' })
	eq(child.shown(), 'e')
end

T['T727 [char] (M15, S1 Load) a fresh start drops the marks before their handles go'] = function()
	child.steps({ ':e a', ':e b', ADD .. 'a>' })
	eq(S2.load(child, 'nothing'), { true })
	child.settle(300)
	local left = child.lua([[
		local d = require('frogman.domains.marks').data
		return { next(d.scopes.window) == nil and next(d.scopes.tab) == nil and next(d.scopes.session) == nil, next(d.places) == nil }
	]])
	local before = child.dump_files()
	child.messages()
	child.steps({ JUMP .. 'a>' })
	eq({ left = left, errors = Misc.errors(child), dumped = child.dumped_since(before) },
		{ left = { true, true }, errors = {} })
end

T['T728 [char] (M15, S2 Closed-stack picker) the closed lists keep a text a mark holds'] = function()
	child.steps({ ':e a' })
	local n = S2.noname(child, { 'kept' })
	child.steps({ ADD .. 'a>', ':e b' })
	child.cmd('bdelete! ' .. n)
	child.settle()
	child.answer('Keep')
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, S2.line_of(lines, '[No Name]'))
	S2.write_picker(child, p, lines)
	child.cmd('close')
	child.settle(100)
	local asked, closed = #child.prompts(), child.closed()
	child.steps({ JUMP .. 'a>' })
	eq({ asked = asked, closed = closed, opened = opened() }, { asked = 0, closed = '', opened = { '[No Name]', { 'kept' } } })
end

-- The split's marks name the text; once the split closes and its held-over group is cleared, memory
-- lets the text go, and only the file's window entry names it when the records are written.
T['T734 [char] (M15, S1 Records) a records write carries a text only its file\'s window marks name'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e a' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':enew' })
	local n = child.lua('return vim.api.nvim_get_current_buf()')
	child.steps({ ADD .. 'a>' })
	child.cmd('buffer a.txt')
	child.settle()
	child.cmd('bwipeout ' .. n)
	child.settle(100)
	eq(S2.save(child), { true })
	child.cmd('close')
	child.settle(100)
	-- the split's marks are held over now: cleared, as deleting their rows in the pop-up clears them
	child.lua('require("frogman.domains.marks.routines").drop_scope("session", "")')
	child.settle(100)
	local known = child.lua('return require("frogman.domains.history").data.hash_filepath_registry.filepaths')
	local forgotten = true
	for _, path in pairs(known) do
		if path:match('^NONAME_') then forgotten = false end
	end
	child.cmd('bdelete b.txt')
	child.settle(1200) -- the records' second runs out, and they're written
	S2.start(child, s)
	Misc.restore(child, { 'a' }, 'a')
	child.cmd('noautocmd vsplit')
	local wins = child.lua('return vim.api.nvim_tabpage_list_wins(0)')
	eq(S2.load(child), { true })
	child.settle(300)
	child.lua('vim.api.nvim_set_current_win(...)', { wins[1] })
	child.settle()
	child.steps({ JUMP .. 'a>' })
	eq({ forgotten = forgotten, opened = opened() }, { forgotten = true, opened = { '[No Name]', { '' } } })
end

-- Saved: in tab mode, the first tab on a with b marked a, the second on c with d marked a. They
-- come back the other way round.
T['T729 [char] (M15, S1) tab marks find their tab by what it shows'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ "<M-'><M-2>", ':e b', ADD .. 'a>', ':e a' })
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e d', ADD .. 'a>', ':e c' })
	eq(S2.save(child), { true })
	S2.start(child, s)
	S2.restore_tabs(child, { { files = { 'c', 'd' }, shown = 'c' }, { files = { 'a', 'b' }, shown = 'a' } })
	eq(S2.load(child), { true })
	child.settle(300)
	child.steps({ "<M-'><M-2>" })
	local got = {}
	for _, n in ipairs({ 1, 2 }) do
		child.cmd('tabnext ' .. n)
		child.settle()
		local from = child.shown()
		child.steps({ JUMP .. 'a>' })
		got[from] = child.shown()
	end
	eq(got, { c = 'd', a = 'b' })
end

T['T730 [char] (M15) a mark whose alias is gone is kept, out of reach'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.lua('_G.FRG_TEST.setup({ marks = { aliases = { q = 1, a = 2 } } })')
	child.steps({ ':e b', "<M-'><M-'><M-q>", ':e c', ADD .. 'a>', ':e a' })
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b', 'c' }, 'a')
	eq(S2.load(child), { true })
	child.settle(300)
	local held = child.lua([[
		local H = require('frogman.domains.history')
		local h = H.handles.of_hash(H.routines.get_filehash(_G.FRG_TEST.root .. '/b.txt'))
		for place, _ in pairs(h and h.holders or {}) do
			if place:match('^mark:') then return true end
		end
		return false
	]])
	local labels = { b = label('b'), c = label('c') }
	child.steps({ JUMP .. 'a>' })
	eq({ held = held, labels = labels, jumped = child.shown() }, { held = true, labels = { b = false, c = 'a' }, jumped = 'c' })
end

-- The places t's marks hold by, as many as there are.
local function t_places()
	return child.lua([[
		local n = 0
		for key, _ in pairs(require('frogman.domains.marks').data.places) do
			if key:match('^session:t\n') then n = n + 1 end
		end
		return n
	]])
end

T['T731 [char] (M15, S1 Records) a tab session\'s marks go with its list'] = function()
	local s = S2.shared()
	tab_session(s)
	child.steps({ "<M-'><M-3>", ':e c', ADD .. 'a>', ':e d' })
	local before = t_places()
	child.cmd('tabclose')
	child.settle(300)
	local after = t_places()
	eq(S2.load_tab_session(child, 't'), { true })
	child.steps({ "<M-'><M-3>", JUMP .. 'a>' })
	eq({ before = before, after = after, jumped = child.shown() }, { before = 1, after = 0, jumped = 'c' })
end

T['T732 [char] (M15, M5) a detached list keeps a copy of its session\'s marks, and gets it back at a load'] = function()
	local s = S2.shared()
	tab_session(s)
	eq(S2.save(child), { true }) -- the whole editor's file, for the detached list's entry
	child.steps({ "<M-'><M-3>", ':e c', ADD .. 'a>', ':e d' })
	local second = child.lua('return vim.api.nvim_get_current_tabpage()')
	eq(S2.load_tab_session(child, 't'), { true })
	child.steps({ "<M-'><M-3>", JUMP .. 'a>' })
	local third = child.shown()
	child.lua('vim.api.nvim_set_current_tabpage(...)', { second })
	child.settle()
	local list = child.lua('return require("frogman.domains.history").routines.current_pool().name')
	child.steps({ JUMP .. 'a>' })
	local in_second = child.shown()
	child.steps({ ':e d', ADD .. 's>' })
	local d_in_third = child.lua([[
		local tab = vim.api.nvim_list_tabpages()[3]
		local win = vim.api.nvim_tabpage_get_win(tab)
		local H = require('frogman.domains.history')
		return require('frogman.domains.marks').label_of(H.routines.get_filehash(_G.FRG_TEST.root .. '/d.txt'), win) or false
	]])
	eq(S2.save(child), { true })
	local on_entry = child.lua([[
		local saved = require('frogman.domains.storage.routines').read_session(vim.fn.getcwd(-1, -1), nil)
		for _, l in ipairs(saved.detached or {}) do
			if l.label == 't_DETACHED' then return l.marks ~= nil and l.marks[1] ~= nil end
		end
		return false
	]])
	-- a fresh editor with the three tabs as they were: the detached list's tab gets its copy back
	S2.start(child, s)
	S2.restore_tabs(child, { { files = { 'x', 't' }, shown = 't' }, { files = { 'c', 'd' }, shown = 'd' },
		{ files = { 'c', 'd' }, shown = 'd' } })
	eq(S2.load(child), { true })
	child.settle(300)
	child.cmd('tabnext 2')
	child.settle()
	local back = child.lua('return require("frogman.domains.history").routines.current_pool().name')
	child.steps({ "<M-'><M-3>", JUMP .. 'a>' })
	eq({ third = third, list = list, in_second = in_second, d_in_third = d_in_third, on_entry = on_entry, back = back,
		back_jumped = child.shown() },
		{ third = 'c', list = 't_DETACHED', in_second = 'c', d_in_third = false, on_entry = true, back = 't_DETACHED',
		back_jumped = 'c' })
end

-- The file is sealed again by hand, as T541's is: a session mark naming a hash no path names.
T['T733 [char] (M15, S1 Load) a load leaves out a mark no path names'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ "<M-'><M-3>", ':e b', ADD .. 'a>', ':e a' })
	eq(Misc.save(child), { true })
	S2.start(child, s)
	child.lua([[
		local crypto = require('frogman.domains.storage.crypto')
		local dir, name = vim.fn.getcwd(-1, -1), vim.fn.getcwd()
		local path = require('frogman.configs').session_dir .. vim.fn.sha256(dir .. "\n" .. name)
		local fh = assert(io.open(path, 'rb')); local bytes = fh:read('*a'); fh:close()
		local salt = bytes:sub(5, 4 + crypto.salt_length)
		local data = require('frogman.domains.storage.routines').read_session(dir, name)
		data.marks[1].marks.s = 'deadbeefdeadbeef' -- a mark no path names
		local header = "CDV1" .. salt
		local out = header .. crypto.seal(crypto.derive_key(dir, salt), vim.json.encode(data), header)
		fh = assert(io.open(path, 'wb')); fh:write(out); fh:close()
	]])
	Misc.restore(child, { 'a', 'b' }, 'a')
	child.messages()
	eq(Misc.load(child), { true })
	child.settle(300)
	local warns = vim.tbl_filter(function(m) return m.msg:find("broke its own rules", 1, true) ~= nil end, child.messages())
	child.steps({ "<M-'><M-3>" })
	local marks = child.lua([[
		local g = require('frogman.domains.marks').data.scopes.session[""].groups[1]
		local out = {}
		for alias, _ in pairs(g.marks) do table.insert(out, alias) end
		table.sort(out)
		return out
	]])
	eq({ warned = #warns, marks = marks }, { warned = 1, marks = { 'a' } })
end

-- The marks pop-up (M15, 4c) -----------------------------------------------------------

local OPEN = "<M-'><M-e>"

-- The pop-up's buffer and its lines, once it's the current window; nil when it isn't open.
local function popup()
	return child.lua([[
		local buf = vim.fn.bufnr('frogman://marks')
		if buf == -1 then return vim.NIL end
		return { buf = buf, lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false), modified = vim.bo[buf].modified,
			ft = vim.bo[buf].filetype, bt = vim.bo[buf].buftype, current = vim.api.nvim_get_current_buf() == buf }
	]])
end

-- The pop-up's lines replaced, then written with :w.
local function write_lines(lines)
	child.lua('vim.api.nvim_buf_set_lines(vim.fn.bufnr("frogman://marks"), 0, -1, false, ...)', { lines })
	child.cmd('silent! write')
	child.settle(100)
end

-- The virtual text drawn on the pop-up's lines, joined line by line, with the mode line first.
local function decoration()
	return child.lua([[
		local buf = vim.fn.bufnr('frogman://marks')
		local ns = vim.api.nvim_get_namespaces()['frogman_marks_popup']
		local out = {}
		for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
			local d = m[4]
			local text = {}
			for _, chunk in ipairs(d.virt_text or {}) do table.insert(text, chunk[1]) end
			for _, l in ipairs(d.virt_lines or {}) do for _, chunk in ipairs(l) do table.insert(text, chunk[1]) end end
			out[m[2] + 1] = (out[m[2] + 1] or '') .. table.concat(text)
		end
		return out
	]])
end

-- The default rows for a group with only these marks, every other alias empty.
local function rows(marked)
	local out = {}
	for _, alias in ipairs({ 'a', 's', 'd', 'f', 'u', 'i', 'o', 'p' }) do
		table.insert(out, alias .. ' -> ' .. (marked[alias] or ''))
	end
	return out
end

T['T735 [char] (M15) the marks pop-up shows the scope\'s groups, a row for every alias'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', ADD .. 's>', ':e a', OPEN })
	local p = popup()
	local deco = decoration()
	child.lua('vim.cmd("redraw")')
	local drawn = tostring(child.get_screenshot()):find('marks · window', 1, true) ~= nil
	child.cmd('close')
	child.settle()
	child.cmd('FrogmanMarks')
	child.settle()
	local again = popup()
	eq({ lines = p.lines, ft = p.ft, bt = p.bt, current = p.current, mode = deco[1], drawn = drawn, again = again.lines },
		{ lines = vim.list_extend({ '❖ main' }, rows({ a = 'b.txt', s = 'c.txt' })), ft = 'frogman-marks', bt = 'acwrite',
		current = true, mode = 'marks · window', drawn = true, again = vim.list_extend({ '❖ main' }, rows({ a = 'b.txt', s = 'c.txt' })) })
end

T['T736 [char] (M15) a row typed and written marks its file, and a row emptied unmarks it'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	write_lines(vim.list_extend({ '❖ main' }, rows({ s = 'c.txt', d = 'd.txt' })))
	local p = popup()
	child.cmd('close')
	child.settle()
	eq({ modified = p.modified, b = label('b'), c = label('c'), d = label('d') }, { modified = false, b = false, c = 's', d = 'd' })
end

T['T737 [char] (M15) an alias holding two files refuses the write'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({ a = 'b.txt' }))
	table.insert(lines, 3, 'a -> c.txt')
	child.messages()
	write_lines(lines)
	local said = vim.tbl_map(function(m) return m.msg end, child.messages())
	local p = popup()
	eq({ said = said, modified = p.modified, b = label('b'), c = label('c') },
		{ said = { 'frogman: ⟨a⟩ holds two files in ❖ main: keep one.' }, modified = true, b = 'a', c = false })
end

T['T738 [char] (M15) a row naming no file is asked about, and No writes nothing'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.answer('No')
	write_lines(vim.list_extend({ '❖ main' }, rows({ a = 'b.txt', s = 'missing.txt', d = 'd.txt' })))
	local asked = child.prompts()
	local after_no = { modified = popup().modified, d = label('d') }
	child.answer('Yes')
	child.cmd('silent! write')
	child.settle(100)
	eq({ asked = #asked, names = asked[1] and asked[1]:find('s -> missing.txt  names no file', 1, true) ~= nil, after_no = after_no,
		d = label('d'), modified = popup().modified },
		{ asked = 1, names = true, after_no = { modified = true, d = false }, d = 'd', modified = false })
end

T['T739 [char] (M15) a header typed makes a group, and the first group drives the keys'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e e', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({ a = 'b.txt' }))
	table.insert(lines, '❖ feature')
	table.insert(lines, 'a -> c.txt')
	write_lines(lines)
	child.cmd('close')
	child.settle()
	local groups = child.lua([[
		local s = require('frogman.domains.marks').data.scopes.window[vim.api.nvim_get_current_win()]
		return vim.tbl_map(function(g) return g.name end, s.groups)
	]])
	child.steps({ JUMP .. 'a>' })
	eq({ groups = groups, jumped = child.shown(), c = label('c') }, { groups = { 'main', 'feature' }, jumped = 'b', c = false })
end

T['T740 [char] (M15) a header deleted moves its rows up; the first one deleted refuses'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e e', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({ a = 'b.txt' }))
	table.insert(lines, '❖ feature')
	table.insert(lines, 's -> c.txt')
	write_lines(lines)
	-- feature's header deleted: s -> c.txt joins main
	local now = popup().lines
	table.remove(now, vim.fn.index(now, '❖ feature') + 1)
	write_lines(now)
	local joined = { c = label('c'), groups = #child.lua('return require("frogman.domains.marks").data.scopes.window[vim.fn.win_getid(vim.fn.winnr("#"))].groups') }
	child.messages()
	now = popup().lines
	table.remove(now, 1)
	write_lines(now)
	local said = vim.tbl_map(function(m) return m.msg end, child.messages())
	eq({ joined = joined, said = said, modified = popup().modified },
		{ joined = { c = 's', groups = 1 },
		said = { "frogman: the marks above the first group's header have no group: put a header back above them, or delete them." },
		modified = true })
end

T['T741 [char] (M15) two groups of one name are asked about, and Yes keeps both'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e e', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({ a = 'b.txt' }))
	table.insert(lines, '❖ main')
	table.insert(lines, 'a -> c.txt')
	child.answer('Yes')
	write_lines(lines)
	local asked = child.prompts()
	child.cmd('close')
	child.settle()
	local groups = child.lua([[
		local s = require('frogman.domains.marks').data.scopes.window[vim.api.nvim_get_current_win()]
		return vim.tbl_map(function(g) return g.name end, s.groups)
	]])
	eq({ asked = #asked, second = asked[1] and asked[1]:find('is a second group of that name', 1, true) ~= nil, groups = groups },
		{ asked = 1, second = true, groups = { 'main', 'main' } })
end

-- Telescope stubbed as far as the pop-up uses it: each picker picks the next of _G.FRG_PICKS.
local function stub_pickers()
	child.lua([[
		for _, m in ipairs({ 'telescope.builtin', 'telescope.actions', 'telescope.actions.state', 'telescope.pickers', 'telescope.finders', 'telescope.config' }) do
			package.loaded[m] = nil
		end
		local chosen
		package.preload['telescope.actions'] = function()
			return { select_default = { replace = function(_, fn) chosen = fn end }, close = function() end }
		end
		package.preload['telescope.actions.state'] = function()
			return { get_selected_entry = function()
				local v = table.remove(_G.FRG_PICKS, 1)
				return v and { v, value = v, path = v } or nil
			end }
		end
		package.preload['telescope.finders'] = function() return { new_table = function(t) return t end } end
		package.preload['telescope.config'] = function() return { values = { generic_sorter = function() end } } end
		package.preload['telescope.pickers'] = function()
			return { new = function(_, opts) return { find = function() opts.attach_mappings(1); chosen() end } end }
		end
		package.preload['telescope.builtin'] = function()
			return { find_files = function(opts) opts.attach_mappings(1); chosen() end }
		end
	]])
end

T['T742 [char] (M15) a picks an alias and a file, and onto a taken alias shows both'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e e', OPEN })
	stub_pickers()
	child.lua('_G.FRG_PICKS = { "s", _G.FRG_TEST.root .. "/c.txt" }; vim.api.nvim_win_set_cursor(0, { 2, 0 })')
	child.step('a')
	child.settle()
	local free = popup().lines[3]
	child.lua('_G.FRG_PICKS = { "a", _G.FRG_TEST.root .. "/d.txt" }')
	child.step('a')
	child.settle()
	local p = popup()
	local deco = decoration()
	child.messages()
	child.cmd('silent! write')
	child.settle(100)
	local refused = #vim.tbl_filter(function(m) return m.msg:find('holds two files', 1, true) ~= nil end, child.messages())
	local i = vim.fn.index(p.lines, 'a -> b.txt') + 1
	eq({ free = free, rows = { p.lines[2], p.lines[3] }, deco = { deco[2], deco[3] }, refused = refused },
		{ free = 's -> c.txt', rows = { 'a -> b.txt', 'a -> d.txt' }, deco = { '  already set', '  incoming' }, refused = 1 })
	eq(i, 2)
end

T['T743 [char] (M15) the add onto a taken alias opens the pop-up on the conflict'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', ADD .. 'a>' })
	local p = popup()
	local deco = decoration()
	local cursor = child.lua('return vim.api.nvim_win_get_cursor(0)[1]')
	eq({ rows = { p.lines[2], p.lines[3] }, deco = { deco[2], deco[3] }, cursor = cursor, modified = p.modified },
		{ rows = { 'a -> c.txt', 'a -> b.txt' }, deco = { '  incoming', '  already set' }, cursor = 2, modified = true })
end

T['T744 [char] (M15) the primary key makes the line\'s file the opening window\'s primary'] = function()
	child.steps({ ':e c', '<M-;><M-c>', ':e b', ADD .. 'a>', ':e a' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ OPEN })
	child.lua('vim.api.nvim_win_set_cursor(0, { 2, 0 })')
	child.step('<M-c>')
	child.settle()
	local queue = child.lua([[
		local t = require('frogman.domains.window').data.crux[...]
		local H = require('frogman.domains.history')
		return { vim.tbl_map(function(h) return vim.fn.fnamemodify(H.get_filepath_from_hash(h), ':t:r') end, t.primary_buffer), t.primary_enabled }
	]], { win })
	eq(queue, { { 'b', 'c' }, true })
end

T['T745 [char] (M15) the mark keys refuse while the pop-up has unsaved edits'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.lua('vim.api.nvim_buf_set_lines(0, 2, 3, false, { "s -> d.txt" })')
	child.cmd('wincmd p')
	child.settle()
	child.messages()
	child.steps({ JUMP .. 'a>', ADD .. 's>', "<M-'><M-2>" })
	local said = vim.tbl_map(function(m) return m.msg end, child.messages())
	local dirty = 'frogman: the marks pop-up has edits not written yet: write them with :w, or leave them, first.'
	eq({ said = said, shown = child.shown(), mode = child.lua('return require("frogman.domains.marks").data.mode'), c = label('c') },
		{ said = { dirty, dirty, dirty }, shown = 'c', mode = 'window', c = false })
end

T['T746 [char] (M15) an unassigned mark shows as unassigned and keeps its file through a write'] = function()
	child.lua('_G.FRG_TEST.setup({ marks = { aliases = { q = 1, a = 2 } } })')
	child.steps({ ':e b', "<M-'><M-'><M-q>", ':e c' })
	child.lua('_G.FRG_TEST.setup({})')
	child.steps({ OPEN })
	local p = popup()
	local deco = decoration()
	child.lua('vim.api.nvim_buf_set_lines(0, 1, 2, false, { "a -> c.txt" })')
	child.cmd('silent! write')
	child.settle(100)
	local after = popup().lines
	local held = child.lua([[
		local H = require('frogman.domains.history')
		local h = H.handles.of_hash(H.routines.get_filehash(_G.FRG_TEST.root .. '/b.txt'))
		for place, _ in pairs(h and h.holders or {}) do
			if place:match('^mark:') then return true end
		end
		return false
	]])
	eq({ last = p.lines[#p.lines], deco = deco[#p.lines], kept = after[#after], held = held },
		{ last = 'q -> b.txt', deco = '  unassigned', kept = 'q -> b.txt', held = true })
end

T['T747 [char] (M15) q writes and leaves, :q refuses, and :q! discards'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.lua('vim.api.nvim_buf_set_lines(0, 2, 3, false, { "s -> c.txt" })')
	local ok = child.lua('return { pcall(vim.cmd, "quit") }')
	local still = popup() ~= vim.NIL
	child.cmd('quit!')
	child.settle()
	local discarded = label('c')
	child.steps({ OPEN })
	child.lua('vim.api.nvim_buf_set_lines(0, 2, 3, false, { "s -> c.txt" })')
	child.step('q')
	child.settle(100)
	eq({ e37 = (ok[2] or ''):find('E37', 1, true) ~= nil, still = still, discarded = discarded, gone = popup() == vim.NIL, c = label('c') },
		{ e37 = true, still = true, discarded = false, gone = true, c = 's' })
end

T['T748 [char] (M15) a mode key in the pop-up shows the new scope, writing the edits first'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.steps({ "<M-'><M-2>" })
	local tab = { lines = popup().lines, mode = decoration()[1] }
	child.lua('vim.api.nvim_buf_set_lines(0, 1, 2, false, { "a -> c.txt" })')
	child.steps({ "<M-'><M-1>" })
	local back = popup().lines
	child.cmd('close')
	child.settle()
	child.steps({ "<M-'><M-2>" })
	local in_tab = label('c')
	eq({ tab = tab, back = back[2], in_tab = in_tab },
		{ tab = { lines = vim.list_extend({ '❖ main' }, rows({})), mode = 'marks · tab' }, back = 'a -> b.txt', in_tab = 'a' })
end

T['T749 [char] (M15) <CR>, gf and a jump key act in the window the pop-up came from'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', ADD .. 's>', ':e d' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ OPEN })
	child.lua('vim.api.nvim_win_set_cursor(0, { 2, 0 })')
	child.step('<CR>')
	child.settle()
	local cr = { shown = child.shown(win), open = popup() ~= vim.NIL }
	child.steps({ ':e d', OPEN })
	child.lua('vim.api.nvim_win_set_cursor(0, { 3, 0 })')
	child.step('gf')
	child.settle()
	local gf = { shown = child.shown(win), open = popup() ~= vim.NIL, current = popup().current }
	child.cmd('close')
	child.settle()
	child.steps({ ':e d', OPEN, JUMP .. 's>' })
	local jump = { shown = child.shown(win), open = popup() ~= vim.NIL, here = child.lua('return vim.api.nvim_get_current_win()') == win }
	eq({ cr = cr, gf = gf, jump = jump }, {
		cr = { shown = 'b', open = false },
		gf = { shown = 'c', open = true, current = true },
		jump = { shown = 'c', open = false, here = true },
	})
end

T['T750 [char] (M15) the pop-up doesn\'t write the marks of a window that\'s gone'] = function()
	child.steps({ ':e b' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ADD .. 'a>' })
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ OPEN })
	child.lua('vim.api.nvim_win_close(..., true)', { split })
	child.settle()
	child.lua('vim.api.nvim_buf_set_lines(0, 2, 3, false, { "s -> c.txt" })')
	child.messages()
	child.cmd('silent! write')
	child.settle(100)
	local said = vim.tbl_map(function(m) return m.msg end, child.messages())
	local scope = child.lua('return require("frogman.domains.marks").data.scopes.window[...] ~= nil', { split })
	eq({ said = said, scope = scope, modified = popup().modified },
		{ said = { "frogman: the window these marks are for is gone, so they aren't written." }, scope = false, modified = true })
end

-- Review round 5's #3, #4, #6, #7 and #8 (M15, 2026-11-03) ----------------------------------

T['T839 [char] (M15) a group glyph of one\'s own is read back'] = function()
	child.lua('_G.FRG_TEST.setup({ glyphs = { group = "▸" } })')
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	local first = popup().lines[1]
	child.lua('vim.api.nvim_buf_set_lines(0, 2, 3, false, { "s -> c.txt" })')
	child.cmd('silent! write')
	child.settle(100)
	eq({ first = first, modified = popup().modified, c = label('c') }, { first = '▸ main', modified = false, c = 's' })
end

T['T840 [char] (M15) the primary key on a typed path writes first'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e a' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ OPEN })
	child.lua('vim.api.nvim_buf_set_lines(0, 2, 3, false, { "s -> x.txt" })')
	child.lua('vim.api.nvim_win_set_cursor(0, { 3, 0 })')
	child.step('<M-c>')
	child.settle(100)
	local got = child.lua([[
		local t = require('frogman.domains.window').data.crux[...]
		local H = require('frogman.domains.history')
		return { queue = vim.tbl_map(function(h) return vim.fn.fnamemodify(H.get_filepath_from_hash(h) or '?', ':t:r') end, t.primary_buffer),
			on = t.primary_enabled, x = H.get_hash_from_filepath(_G.FRG_TEST.root .. '/x.txt') ~= nil }
	]], { win })
	eq({ modified = popup().modified, got = got }, { modified = false, got = { queue = { 'x' }, on = true, x = true } })
end

T['T841 [char] (M15) <CR> after an edit acts on the row it was on'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', ADD .. 'd>', ':e e' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ OPEN })
	child.lua('vim.api.nvim_buf_set_lines(0, 2, 3, false, {})') -- the empty s row
	child.lua('vim.api.nvim_win_set_cursor(0, { 3, 0 })') -- d -> c.txt, now the third line
	child.step('<CR>')
	child.settle(100)
	eq(child.shown(win), 'c')
end

T['T842 [char] (M15) a mode key in the pop-up with its window gone refuses'] = function()
	child.steps({ ':e b' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ADD .. 'a>' })
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ OPEN })
	child.lua('vim.api.nvim_win_close(..., true)', { split })
	child.settle()
	child.messages()
	child.steps({ "<M-'><M-2>" })
	child.settle(100)
	local said = vim.tbl_map(function(m) return m.msg end, child.messages())
	eq({ said = said, mode = child.lua('return require("frogman.domains.marks").data.mode'), open = popup() ~= vim.NIL },
		{ said = { 'frogman: the window these marks are for is gone.' }, mode = 'window', open = true })
end

T['T843 [char] (M15) an alias that takes a fixed key is said once'] = function()
	child.messages()
	child.lua('_G.FRG_TEST.setup({ marks = { aliases = { e = 1, s = 2 } } })')
	local said = vim.tbl_filter(function(m) return m:find('marks.aliases', 1, true) ~= nil end,
		vim.tbl_map(function(m) return m.msg end, child.messages()))
	child.lua('_G.FRG_TEST.setup({ marks = { aliases = { e = 1, s = 2 } }, keymaps = { mark_popup = "<M-m>" } })')
	local quiet = vim.tbl_filter(function(m) return m:find('marks.aliases', 1, true) ~= nil end,
		vim.tbl_map(function(m) return m.msg end, child.messages()))
	child.steps({ ':e b', "<M-'><M-m>" })
	eq({ n = #said, names = said[1] ~= nil and said[1]:find("e", 1, true) ~= nil and said[1]:find("<M-'><M-e>", 1, true) ~= nil,
		quiet = #quiet, open = popup() ~= vim.NIL }, { n = 1, names = true, quiet = 0, open = true })
end

T['T849 [char] (M15) marks.split_copies copies a split\'s marks'] = function()
	child.lua('_G.FRG_TEST.setup({ marks = { split_copies = true } })')
	child.steps({ ':e b', ADD .. 'a>' })
	local first = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('split')
	child.settle()
	local copied = label('b')
	child.steps({ ':e c', ADD .. 's>' })
	child.lua('vim.api.nvim_set_current_win(...)', { first })
	child.settle()
	local first_c = label('c')
	child.lua('_G.FRG_TEST.setup({})')
	child.cmd('split')
	child.settle()
	local plain = child.lua('return require("frogman.domains.marks").data.scopes.window[vim.api.nvim_get_current_win()] == nil')
	eq({ copied = copied, first_c = first_c, plain = plain }, { copied = 'a', first_c = false, plain = true })
end

T['T850 [char] (M15) a mark\'s word in the winbar goes after its moment'] = function()
	child.steps({ ':e b', ADD .. 'a>' })
	local during = (child.lua('return vim.wo.winbar') or ''):find('marked', 1, true) ~= nil
	child.lua('vim.wait(2600)')
	child.settle(100)
	local after = (child.lua('return vim.wo.winbar') or ''):find('marked', 1, true) ~= nil
	eq({ during = during, after = after }, { during = true, after = false })
end

T['T851 [char] (M15) indices order numbers first, then the rest by text'] = function()
	child.lua([[_G.FRG_TEST.setup({ marks = { aliases = { a = 10, b = 9, c = '05' } } })]])
	child.steps({ ':e b', ADD .. 'a>', ADD .. 'b>', ADD .. 'c>' })
	local labelled = label('b')
	child.steps({ OPEN })
	local rows = vim.tbl_map(function(l) return l:match('^(%S+) %->') or false end, popup().lines)
	child.cmd('close')
	child.settle()
	eq({ label = labelled, rows = rows }, { label = 'b,a,c', rows = { false, 'b', 'a', 'c' } })
end

T['T853 [char] (M15, M16) a tab close Neovim refuses leaves the tab\'s windows held over as any'] = function()
	local s = S2.shared()
	tab_session(s)
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	child.lua('vim.o.hidden = false')
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>', '<M-;><M-s>' })
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('wincmd p')
	child.settle()
	child.cmd('enew')
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })')
	child.settle()
	local refused = not child.lua('return pcall(vim.cmd, "tabclose")') -- it closes the split, then refuses
	child.settle(300)
	local held = child.lua([[
		local id = ...
		local scope = require('frogman.domains.marks').data.scopes.session[id]
		local n = 0
		for _, g in ipairs(scope and scope.groups or {}) do if g.held then n = n + 1 end end
		return { groups = n, snapshots = #require('frogman.domains.snapshots').routines.held_in(id) }
	]], { id })
	local split_gone = not child.lua('return vim.api.nvim_win_is_valid(...)', { split })
	eq({ refused = refused, split_gone = split_gone, held = held }, { refused = true, split_gone = true, held = { groups = 1, snapshots = 1 } })
end

-- Held-over groups (M15, 4d) --------------------------------------------------------------

-- A session scope's groups: each one's name, whether it's held over, and its marks by file name.
local function session_groups(id)
	return child.lua([[
		local d = require('frogman.domains.marks').data
		local H = require('frogman.domains.history')
		local s = d.scopes.session[...]
		local out = {}
		for _, g in ipairs(s and s.groups or {}) do
			local marks = {}
			for alias, hid in pairs(g.marks) do
				local h = H.handles.get(H.handles.resolve(hid))
				marks[alias] = h and vim.fn.fnamemodify(H.get_filepath_from_hash(h.hash), ':t:r') or false
			end
			table.insert(out, { name = g.name, held = g.held == true, marks = marks })
		end
		return out
	]], { id })
end

local STAMP = ' · %d%d%-%d%d %d%d:%d%d'

-- The route T751 takes: a split on b with b marked a, closed.
local function window_held_over()
	child.steps({ ':e a', ':e b' })
	child.cmd('split')
	child.settle()
	child.steps({ ADD .. 'a>' })
	child.cmd('close')
	child.settle(100)
end

T['T751 [char] (M15) a window closed while you work leaves its marks held over'] = function()
	window_held_over()
	local groups = session_groups('')
	child.steps({ ':e a', "<M-'><M-3>", JUMP .. 'a>' })
	eq({ n = #groups, first = groups[1], held = groups[2] and groups[2].held, marks = groups[2] and groups[2].marks,
		name = groups[2] and groups[2].name:match('^held over · window on b%.txt' .. STAMP .. '$') ~= nil, jumped = child.shown() },
		{ n = 2, first = { name = 'main', held = false, marks = {} }, held = true, marks = { a = 'b' }, name = true, jumped = 'a' })
end

T['T752 [char] (M15) a closed tab leaves one group for its tab marks and one for each of its marked windows'] = function()
	child.steps({ ':e a' })
	child.cmd('tabnew')
	child.settle()
	child.steps({ "<M-'><M-2>", ':e c', ADD .. 'a>', "<M-'><M-1>", ':e d', ADD .. 'a>' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e e', ADD .. 'a>' })
	child.cmd('tabclose')
	child.settle(100)
	local names = {}
	for _, g in ipairs(session_groups('')) do
		if g.held then
			table.insert(names, (g.name:match('^held over · (%a+) on ')))
		end
	end
	table.sort(names)
	eq(names, { 'tab', 'window', 'window' })
end

T['T753 [char] (M15) a switch holds nothing over'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('split')
	child.settle()
	child.steps({ ADD .. 'a>' })
	eq(S2.save(child), { true })
	child.lua('vim.cmd("close"); require("frogman").load_session()')
	child.settle(300)
	local held = vim.tbl_filter(function(g) return g.held end, session_groups(''))
	eq(#held, 0)
end

T['T754 [char] (M15, S1) a window entry no window takes at a load leaves a held-over group naming the load'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e d', ADD .. 'a>', ':e c' })
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	local project = vim.fn.fnamemodify(s.root, ':t')
	local held = vim.tbl_filter(function(g) return g.held end, session_groups(''))
	eq({ n = #held, marks = held[1] and held[1].marks,
		name = held[1] and held[1].name:match('^held over · ' .. vim.pesc(project) .. ', loaded' .. STAMP .. '$') ~= nil },
		{ n = 1, marks = { a = 'd' }, name = true })
end

T['T755 [char] (M15) a held-over group drives the keys only once you move it first'] = function()
	window_held_over()
	child.steps({ ':e a', "<M-'><M-3>", OPEN })
	local lines = popup().lines
	lines[3] = 's -> c.txt'
	write_lines(lines)
	local still = session_groups('')[2].held
	lines = popup().lines
	local at = vim.fn.index(lines, '❖ ' .. session_groups('')[2].name) + 1
	local moved = vim.list_slice(lines, at)
	vim.list_extend(moved, vim.list_slice(lines, 1, at - 1))
	write_lines(moved)
	child.cmd('close')
	child.settle()
	local first = session_groups('')[1]
	child.steps({ JUMP .. 'a>' })
	eq({ still = still, first_held = first.held, jumped = child.shown() }, { still = true, first_held = false, jumped = 'b' })
end

T['T756 [char] (M15) a plain tab\'s tab marks are held over when it becomes a tab session\'s tab'] = function()
	child.steps({ ':e a' })
	child.cmd('tabnew')
	child.settle()
	child.steps({ "<M-'><M-2>", ':e c', ADD .. 'a>', ':e d' })
	local tab = child.lua('return vim.api.nvim_get_current_tabpage()')
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = ... }) }', { tab }), { true })
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[...]', { tab })
	local groups = session_groups(id)
	local tab_scope = child.lua('return require("frogman.domains.marks").data.scopes.tab[...] ~= nil', { tab })
	local held = vim.tbl_filter(function(g) return g.held end, groups)
	eq({ n = #held, marks = held[1] and held[1].marks, name = held[1] and held[1].name:match('^held over · tab on d%.txt' .. STAMP .. '$') ~= nil,
		tab_scope = tab_scope }, { n = 1, marks = { a = 'c' }, name = true, tab_scope = false })
end

T['T757 [char] (M15, S1 Load) a tab session loaded where it\'s open keeps memory\'s marks and holds the file\'s others over'] = function()
	local s = S2.shared()
	tab_session(s)
	child.steps({ "<M-'><M-3>", ':e c', ADD .. 'a>', ':e d' })
	eq(save_t(), { true })
	-- in memory, c moves to s and d takes a
	child.lua([[
		local M = require('frogman.domains.marks').routines
		local H = require('frogman.domains.history')
		local kind, id = M.scope_key('session')
		local g = M.first_group(M.scope(kind, id))
		local function h(f) return H.handles.of_hash(H.routines.get_filehash(_G.FRG_TEST.root .. '/' .. f .. '.txt')).id end
		g.marks = { a = h('d'), s = h('c') }
		M.hold_scope(kind, id)
	]])
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	eq(S2.load_tab_session(child, 't'), { true })
	local groups = session_groups(id)
	local tab = child.lua('return vim.api.nvim_tabpage_get_number(0)')
	eq({ n = #groups, first = groups[1] and groups[1].marks, held = groups[2] and groups[2].held, file = groups[2] and groups[2].marks,
		name = groups[2] and groups[2].name:match('^held over · t, loaded into tab ' .. tab .. STAMP .. '$') ~= nil },
		{ n = 2, first = { a = 'd', s = 'c' }, held = true, file = { a = 'c' }, name = true })
end

T['T758 [char] (M15) two held-over groups that would read the same are numbered'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('split')
	child.settle()
	child.steps({ ADD .. 'a>' })
	child.cmd('split')
	child.settle()
	child.steps({ ADD .. 'a>' })
	child.cmd('close')
	child.settle(100)
	child.cmd('close')
	child.settle(100)
	local held = vim.tbl_filter(function(g) return g.held end, session_groups(''))
	eq({ n = #held, numbered = held[2] and held[2].name:match(' #2$') ~= nil }, { n = 2, numbered = true })
end

T['T759 [char] (M15, S1) a held-over group is saved and loaded as one'] = function()
	local s = S2.shared()
	S2.start(child, s)
	window_held_over()
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	child.steps({ ':e a', "<M-'><M-3>", JUMP .. 'a>' })
	local held = vim.tbl_filter(function(g) return g.held end, session_groups(''))
	eq({ n = #held, marks = held[1] and held[1].marks, jumped = child.shown() }, { n = 1, marks = { a = 'b' }, jumped = 'a' })
end

T['T760 [char] (M15) a tab session\'s tab closing holds nothing over'] = function()
	local s = S2.shared()
	tab_session(s)
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	child.steps({ ':e c', ADD .. 'a>', ':e d' })
	eq(save_t(), { true })
	local rounds = {}
	for _ = 1, 2 do
		child.cmd('tabclose')
		child.settle(300)
		eq(S2.load_tab_session(child, 't'), { true })
		child.steps({ JUMP .. 'a>' })
		table.insert(rounds, { held = #vim.tbl_filter(function(g) return g.held end, session_groups(id)), jumped = child.shown() })
		child.steps({ ':e d' })
		eq(save_t(), { true })
	end
	eq(rounds, { { held = 0, jumped = 'c' }, { held = 0, jumped = 'c' } })
end

T['T870 [char] (M15, M16) a tab session\'s tab closed by its last window holds nothing over'] = function()
	local s = S2.shared()
	tab_session(s)
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	eq(child.lua('return #vim.api.nvim_tabpage_list_wins(0)'), 1)
	child.steps({ ':e c', ADD .. 'a>', '<M-;><M-s>', ':e d' })
	eq(save_t(), { true })
	local rounds = {}
	for _ = 1, 2 do
		child.cmd('q')
		child.settle(300)
		eq(S2.load_tab_session(child, 't'), { true })
		local snapshots = child.lua([[
			local R = require('frogman.domains.snapshots').routines
			return { own = #R.of_window(vim.api.nvim_get_current_win()), held = #R.held_in(...) }
		]], { id })
		child.steps({ JUMP .. 'a>' })
		table.insert(rounds, { held = #vim.tbl_filter(function(g) return g.held end, session_groups(id)), snapshots = snapshots, jumped = child.shown() })
		child.steps({ ':e d' })
		eq(save_t(), { true })
	end
	local once = { held = 0, snapshots = { own = 1, held = 0 }, jumped = 'c' }
	eq(rounds, { once, once })
end

T['T871 [char] (M15, M16) a tab session\'s save wired at TabClosedPre keeps what its last window held as `:q` closes it'] = function()
	local s = S2.shared()
	tab_session(s)
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	child.lua([[
		vim.api.nvim_create_autocmd('TabClosedPre', { callback = function()
			require('frogman').save_session('t', { tab = vim.api.nvim_get_current_tabpage() })
		end })
	]])
	child.steps({ ':e c', ADD .. 'a>', '<M-;><M-s>', ':e d' })
	child.cmd('q')
	child.settle(300)
	eq(S2.load_tab_session(child, 't'), { true })
	local snapshots = child.lua([[
		local R = require('frogman.domains.snapshots').routines
		return { own = #R.of_window(vim.api.nvim_get_current_win()), held = #R.held_in(...) }
	]], { id })
	child.steps({ JUMP .. 'a>' })
	eq({ snapshots = snapshots, jumped = child.shown() }, { snapshots = { own = 1, held = 0 }, jumped = 'c' })
end

T['T872 [char] (M15) the window a copy came from holds nothing over while its copy lives unchanged'] = function()
	child.lua('_G.FRG_TEST.setup({ marks = { split_copies = true } })')
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e b', ADD .. 'a>' })
	local first = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('split')
	child.settle()
	local copy = child.lua('return vim.api.nvim_get_current_win()')
	local function held() return #vim.tbl_filter(function(g) return g.held end, session_groups('')) end
	child.lua('vim.api.nvim_win_close(..., false)', { first })
	child.settle(300)
	local origin = held()
	child.lua('vim.api.nvim_win_close(..., false)', { copy })
	child.settle(300)
	eq({ origin = origin, copy = held() }, { origin = 0, copy = 1 })
end

T['T873 [char] (M15) a closed window\'s mark keeps its file through a move before its tick'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('split')
	child.settle()
	child.steps({ ADD .. 'a>' })
	child.lua([[
		local root = _G.FRG_TEST.root
		vim.cmd('close')
		os.rename(root .. '/b.txt', root .. '/b2.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/b.txt'), root .. '/b2.txt')
		require('frogman.settle').drain()
	]])
	child.settle(300)
	local held = vim.tbl_filter(function(g) return g.held end, session_groups(''))
	eq(vim.tbl_map(function(g) return g.marks end, held), { { a = 'b2' } })
end

T['T875 [char] (M15) the pop-up\'s write keeps what came in since it was drawn'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.lua([[
		local origin = require('frogman.domains.marks.popup').origin()
		vim.api.nvim_win_call(origin, function() require('frogman.domains.marks.routines').add('s') end)
	]])
	child.settle()
	local shown = vim.tbl_contains(popup().lines, 's -> c.txt')
	child.cmd('close')
	child.settle()
	child.cmd('split')
	child.settle()
	child.steps({ ':e d', ADD .. 'f>' })
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('wincmd p')
	child.settle()
	child.steps({ "<M-'><M-3>", OPEN })
	child.lua('vim.api.nvim_buf_set_lines(vim.fn.bufnr("frogman://marks"), 0, -1, false, { "❖ main", "d -> b.txt" })')
	child.lua('vim.api.nvim_win_close(..., false)', { split })
	child.settle(300)
	child.cmd('silent! write')
	child.settle(100)
	local held = vim.tbl_filter(function(g) return g.held end, session_groups(''))
	eq({ shown = shown, held = vim.tbl_map(function(g) return g.marks end, held) }, { shown = true, held = { { f = 'd' } } })
end

T['T866 [char] (M15) a pop-up whose drawing fails leaves no buffer behind'] = function()
	child.steps({ ':e b', ADD .. 'a>' })
	local got = child.lua([[
		local R = require('frogman.domains.marks.routines')
		local first_group = R.first_group
		R.first_group = function() error('drawing fails') end
		local ok = pcall(require('frogman.domains.marks.popup').open)
		R.first_group = first_group
		local left = vim.fn.bufnr('frogman://marks') ~= -1
		local again = pcall(require('frogman.domains.marks.popup').open)
		return { failed = not ok, left = left, again = again }
	]])
	eq(got, { failed = true, left = false, again = true })
end

T['T876 [char] (M15) a pop-up whose window can\'t open leaves no buffer behind'] = function()
	child.steps({ ':e b', ADD .. 'a>' })
	local got = child.lua([[
		local open_win = vim.api.nvim_open_win
		vim.api.nvim_open_win = function() error('no window here') end
		local ok = pcall(require('frogman.domains.marks.popup').open)
		vim.api.nvim_open_win = open_win
		local left = vim.fn.bufnr('frogman://marks') ~= -1
		local again = pcall(require('frogman.domains.marks.popup').open)
		return { failed = not ok, left = left, again = again }
	]])
	eq(got, { failed = true, left = false, again = true })
end

T['T867 [char] (M15) two of the marks\' keys that come out the same are said'] = function()
	child.messages()
	local function told(key)
		return #vim.tbl_filter(function(m) return m.msg:find(key, 1, true) ~= nil end, child.messages())
	end
	child.lua([[_G.FRG_TEST.setup({ keymaps = { mark_popup = "<M-'><M-a>" } })]])
	local first = told("<M-'><M-'><M-a>")
	child.lua([[_G.FRG_TEST.setup({ keymaps = { mark_modes = { window = "<M-e>" } } })]])
	local second = told("<M-'><M-e>")
	eq({ first = first, second = second }, { first = 1, second = 1 })
end

T['T858 [char] (M15) a copy no one changed holds nothing over'] = function()
	child.lua('_G.FRG_TEST.setup({ marks = { split_copies = true } })')
	child.steps({ ':e b', ADD .. 'a>' })
	child.cmd('help')
	child.settle()
	child.cmd('quit')
	child.settle(300)
	local help = #vim.tbl_filter(function(g) return g.held end, session_groups(''))
	child.cmd('split')
	child.settle()
	child.steps({ ADD .. 's>' })
	child.cmd('close')
	child.settle(300)
	eq({ help = help, changed = #vim.tbl_filter(function(g) return g.held end, session_groups('')) }, { help = 0, changed = 1 })
end

T['T862 [char] (M15, M16) a window closed ahead of its tab session\'s close is held over'] = function()
	local s = S2.shared()
	tab_session(s)
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>', '<M-;><M-s>' })
	child.cmd('wincmd p')
	child.settle()
	child.cmd('only | tabclose')
	child.settle(500)
	eq(child.lua([[
		local saved = require('frogman.domains.storage.routines').read_session(vim.fn.getcwd(-1, -1), 't')
		local n = 0
		for _, g in ipairs(saved and saved.marks or {}) do if g.held then n = n + 1 end end
		return { groups = n, snapshots = #(saved and saved.snapshots or {}) }
	]]), { groups = 1, snapshots = 1 })
end

T['T863 [char] (M15, S1 Load) two groups of one entry with the same marks are both held over'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e b', OPEN })
	write_lines({ '❖ main', 'a -> b.txt', '❖ backup', 'a -> b.txt' })
	child.cmd('close')
	child.settle()
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a' }, 'a')
	eq(S2.load(child), { true })
	child.settle(300)
	eq(#vim.tbl_filter(function(g) return g.held end, session_groups('')), 2)
end

T['T864 [char] (M15, S1 Records) an entry a list in the file alone names keeps its marks through the records'] = function()
	local s = S2.shared()
	tab_session(s)
	eq(S2.save(child), { true })
	child.steps({ ':e c', ADD .. 'a>', ':e d' }) -- a window mark in t's tab
	eq(S2.load_tab_session(child, 't'), { true }) -- that tab keeps t_DETACHED
	eq(S2.save(child), { true }) -- the whole editor's file, the list's window entry with its marks
	S2.start(child, s)
	S2.restore_tabs(child, { { files = { 'x', 't' }, shown = 't' } })
	eq(S2.load(child), { true })
	child.settle(300)
	S2.start(child, s) -- the quit writes the records
	S2.restore_tabs(child, { { files = { 'x', 't' }, shown = 't' }, { files = { 'c', 'd' }, shown = 'd' },
		{ files = { 'c', 'd' }, shown = 'd' } })
	eq(S2.load(child), { true })
	child.settle(300)
	child.cmd('tabnext 2')
	child.settle()
	child.steps({ JUMP .. 'a>' })
	eq(child.shown(), 'c')
end

T['T761 [char] (M15) a tab session\'s load drops what its own tab\'s closes queued and keeps the rest'] = function()
	child.steps({ ':e a' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e b', ADD .. 'a>' })
	local one = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e d', ADD .. 'a>' })
	local got = child.lua('return { vim.api.nvim_get_current_win(), vim.api.nvim_get_current_tabpage() }')
	child.lua([[
		local one, two, tab2 = ...
		vim.api.nvim_win_close(two, true)
		vim.api.nvim_win_close(one, true)
		require('frogman').load_session('u', { tab = tab2 })
	]], { one, got[1], got[2] })
	child.settle(300)
	local held = vim.tbl_filter(function(g) return g.held end, session_groups(''))
	eq({ n = #held, marks = held[1] and held[1].marks }, { n = 1, marks = { a = 'b' } })
end

-- Review round 5's storage findings, and the tab rule's count (M15, S1) ---------------------------

-- T369's state with a whole-editor save first: t in a third tab, the second keeping t_DETACHED, and
-- the second tab current.
local function detached(s)
	tab_session(s)
	eq(S2.save(child), { true }) -- the whole editor's file, for the detached list to go into
	eq(S2.load_tab_session(child, 't'), { true })
	child.cmd('tabnext 2')
	child.settle()
end

-- t_DETACHED's marks in the whole editor's saved file, alias -> file stem, or false when it isn't there.
local function detached_marks()
	return child.lua([[
		local saved = require('frogman.domains.storage.routines').read_session(vim.fn.getcwd(-1, -1), nil)
		for _, l in ipairs(saved.detached or {}) do
			if l.label == 't_DETACHED' then
				local out = {}
				for _, g in ipairs(l.marks or {}) do
					for alias, h in pairs(g.marks or {}) do out[alias] = vim.fn.fnamemodify(saved.paths[h] or '?', ':t:r') end
				end
				return out
			end
		end
		return false
	]])
end

-- T823's route: in t_DETACHED's tab, e marked in session mode and held by the mark alone; the tab closed.
local function detached_into_file(s)
	detached(s)
	child.steps({ "<M-'><M-3>", ':e e', ADD .. 'a>', ':e d' })
	child.cmd('bdelete e.txt')
	child.settle()
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, S2.line_of(lines, 'e.txt'))
	S2.write_picker(child, p, lines)
	child.cmd('close')
	child.settle(100)
	child.cmd('tabclose') -- t_DETACHED goes into the whole editor's file, its marks with it
	child.settle(300)
end

T['T823 [char] (M15, M5) a detached list that goes into the whole editor\'s file keeps its marks through the next save'] = function()
	local s = S2.shared()
	detached_into_file(s)
	local written = detached_marks()
	eq(S2.save(child), { true })
	eq({ written = written, saved = detached_marks() }, { written = { a = 'e' }, saved = { a = 'e' } })
end

T['T824 [char] (M15, M5, S1 Load) a list in the whole editor\'s file alone keeps its marks across a load and a save'] = function()
	local s = S2.shared()
	detached_into_file(s)
	S2.start(child, s)
	eq(S2.load(child), { true })
	child.settle(300)
	eq(S2.save(child), { true })
	eq(detached_marks(), { a = 'e' })
end

T['T825 [char] (M15, S1 Save) the tabs key carries no window count'] = function()
	child.steps({ "<M-'><M-2>", ':e b', ADD .. 'a>', ':e a' })
	eq(S2.save(child), { true })
	eq(child.lua([[
		local saved = require('frogman.domains.storage.routines').read_session(vim.fn.getcwd(-1, -1), nil)
		local keys = vim.tbl_keys((saved.tabs or {})[1] or {})
		table.sort(keys)
		return keys
	]]), { 'groups', 'position', 'shows' })
end

T['T826 [char] (M15, S1 Load) a window entry no window takes is held over once, however often it\'s loaded'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e d', ADD .. 'a>', ':e c' })
	eq(S2.save(child), { true })
	for _ = 1, 3 do
		S2.start(child, s) -- the child before quits, writing its records
		Misc.restore(child, { 'a', 'b' }, 'b')
		eq(S2.load(child), { true })
		child.settle(300)
	end
	local held = vim.tbl_filter(function(g) return g.held and vim.deep_equal(g.marks, { a = 'd' }) end, session_groups(''))
	eq(#held, 1)
end

T['T830 [char] (M15, S1 Records) a held-over group you clear stays cleared'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e d', ADD .. 'a>', ':e c' })
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	local before = #vim.tbl_filter(function(g) return g.held end, session_groups(''))
	-- cleared, as the marks pop-up's write clears it once its rows are deleted
	child.lua([[
		local M = require('frogman.domains.marks').routines
		local scope = M.scope('session', '')
		scope.groups = vim.tbl_filter(function(g) return not g.held end, scope.groups)
		M.hold_scope('session', '')
	]])
	S2.start(child, s) -- the quit writes the records
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	eq({ before = before, after = #vim.tbl_filter(function(g) return g.held end, session_groups('')) }, { before = 1, after = 0 })
end

-- The stranger stands in for another editor's save: a window on b, with its own mark s on e, put
-- where the split's unclaimed entry was.
T['T832 [char] (M15, S1 Records) the records write takes off only the entry the load left'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e d', ADD .. 'a>', ':e c' })
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	child.lua([[
		local crypto = require('frogman.domains.storage.crypto')
		local H = require('frogman.domains.history')
		local dir = vim.fn.getcwd(-1, -1)
		local path = require('frogman.configs').session_dir .. vim.fn.sha256(dir)
		local fh = assert(io.open(path, 'rb')); local bytes = fh:read('*a'); fh:close()
		local salt = bytes:sub(5, 4 + crypto.salt_length)
		local data = require('frogman.domains.storage.routines').read_session(dir, nil)
		local e = H.routines.get_filehash(_G.FRG_TEST.root .. '/e.txt')
		data.paths[e] = _G.FRG_TEST.root .. '/e.txt'
		local stranger = vim.deepcopy(data.windows[2])
		stranger[10] = { { name = 'main', marks = { s = e } } }
		table.insert(data.windows, 1, stranger)
		local header = "CDV1" .. salt
		local out = header .. crypto.seal(crypto.derive_key(dir, salt), vim.json.encode(data), header)
		fh = assert(io.open(path, 'wb')); fh:write(out); fh:close()
	]])
	S2.start(child, s) -- the quit writes the records
	local kept = child.lua([[
		local data = require('frogman.domains.storage.routines').read_session(vim.fn.getcwd(-1, -1), nil)
		local entry = data.windows[1]
		return type(entry[10]) == 'table' and entry[10][1] ~= nil
	]])
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	local held = vim.tbl_filter(function(g) return g.held and vim.deep_equal(g.marks, { a = 'd' }) end, session_groups(''))
	eq({ kept = kept, held = #held }, { kept = true, held = 1 })
end

return T
