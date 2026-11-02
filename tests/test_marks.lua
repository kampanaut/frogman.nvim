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
	local label = child.lua('return require("frogman.domains.marks").label_of(require("frogman.domains.history").get_hash_from_buffer(vim.api.nvim_get_current_buf()))')
	said()
	child.steps({ ':e c', ADD .. 'a>' })
	local taken = said()
	child.cmd('help')
	child.settle()
	child.steps({ ADD .. 'd>' })
	local untracked = said()
	eq({ bar = bar:find('⟨a⟩ marked', 1, true) ~= nil, label = label, taken = #taken == 1 and taken[1]:find('holds b.txt', 1, true) ~= nil,
		untracked = untracked },
		{ bar = true, label = 'a,s', taken = true, untracked = { 'frogman: only files can be marked.' } })
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
	local lookup = 'local bl = require("frogman").bufferline; return { bl.is_harpooned(...), bl.get_harpoon_index(...) }'
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

-- The aliases a file has in the current mode's scope, by its name.
local function label(name)
	return child.lua([[
		local H = require('frogman.domains.history')
		return require('frogman.domains.marks').label_of(H.routines.get_filehash(_G.FRG_TEST.root .. '/' .. ... .. '.txt')) or false
	]], { name })
end

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

-- The split's marks name the text; once the split closes, memory lets the text go, and only the
-- file's window entry names it when the records are written.
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

return T
