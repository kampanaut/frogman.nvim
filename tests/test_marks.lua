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
		return require('frogman.domains.marks').label_of(H.get_handle_from_hash(H.routines.get_filehash(_G.FRG_TEST.root .. '/' .. ... .. '.txt')), win) or false
	]], { name })
end

T['T711 [char] (M15) harpoon is gone'] = function()
	child.lua([[_G.FRG_TEST.setup({ marks_provider = function() error('read') end })]])
	local warned = vim.tbl_filter(function(m) return m:find('marks_provider is gone', 1, true) ~= nil end, said())
	child.cmd('FrogmanIndicators harpoon off')
	local refused = vim.tbl_filter(function(m) return m:find('roles or marks', 1, true) ~= nil end, said())
	local colors = child.lua('local c = require("frogman.configs").colors; return { c.marked ~= nil, c.harpooned == nil }')
	local readme = table.concat(vim.fn.readfile('README.md'), '\n')
	-- a config that still sets it is ignored, nothing said (decided 2026-11-05, "Setup ignores it silently")
	eq({ warned = #warned, refused = #refused, colors = colors, readme = readme:find('- harpoon', 1, true) == nil },
		{ warned = 0, refused = 1, colors = { true, true }, readme = true })
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
	local label_b = child.lua('return require("frogman.domains.marks").label_of(require("frogman.domains.history").get_handle_from_buffer(vim.api.nvim_get_current_buf()))')
	child.steps({ ':e c', ADD .. 'a>' })
	local conflict = child.lua([[
		local buf = (require('frogman.domains.marks.popup').buffer() or -1)
		return buf ~= -1 and vim.api.nvim_get_current_buf() == buf and vim.api.nvim_buf_get_lines(buf, 1, 3, false) or false
	]])
	local c_marked = label('c')
	child.lua('local b = (require("frogman.domains.marks.popup").buffer() or -1); if b ~= -1 then vim.api.nvim_buf_delete(b, { force = true }) end')
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
	local before = child.slots()
	child.steps({ '<M-m>' })
	said()
	-- while a cycle runs, the jump cancels it as a cancel ends it, then jumps from its start
	child.steps({ JUMP .. 'a>' })
	local cycling = said()
	eq({ jumped = jumped[1], slots = jumped[2], reopened = reopened, gone = gone[1] and gone[1]:find("isn't on disk right now; the mark keeps it", 1, true) ~= nil,
		cancelled = #vim.tbl_filter(function(m) return m:find('Cycling cancelled.', 1, true) ~= nil end, cycling),
		refused = #vim.tbl_filter(function(m) return m:find('pick or cancel the cycle first', 1, true) ~= nil end, cycling),
		after = { child.shown(), child.lua('return require("frogman.domains.navigation").sm:state()'), child.slots() == before } },
		{ jumped = 'a', slots = '⦉b⦊ [a] ⟦-⟧', reopened = 'c', gone = true, cancelled = 1, refused = 0, after = { 'a', 'normal', true } })
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
		return { closed = H.routines.is_handle_closed(h and h.id), state = h and h:state() or false }
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

-- The groups of each window entry of a session's file that carries some, entry by entry, each group as its name
-- and its marks by file letter.
local ENTRY_GROUPS = [[
	local name = ...
	local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), name ~= '' and name or nil) or {}
	local out = {}
	for _, entry in ipairs(saved.windows or {}) do
		if type(entry) == 'table' and type(entry[10]) == 'table' then
			local groups = {}
			for _, g in ipairs(entry[10]) do
				local marks = {}
				for alias, h in pairs(type(g.marks) == 'table' and g.marks or {}) do
					table.insert(marks, alias .. '=' .. vim.fn.fnamemodify((saved.paths or {})[h] or h, ':t:r'))
				end
				table.sort(marks)
				table.insert(groups, g.name .. ' ' .. table.concat(marks, ','))
			end
			table.insert(out, groups)
		end
	end
	return out
]]

-- The groups of each tab entry of the whole editor's file, the same way.
local TAB_GROUPS = [[
	local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), nil) or {}
	local out = {}
	for _, tab in ipairs(saved.tabs or {}) do
		local groups = {}
		for _, g in ipairs(type(tab.groups) == 'table' and tab.groups or {}) do
			local marks = {}
			for alias, h in pairs(type(g.marks) == 'table' and g.marks or {}) do
				table.insert(marks, alias .. '=' .. vim.fn.fnamemodify((saved.paths or {})[h] or h, ':t:r'))
			end
			table.sort(marks)
			table.insert(groups, g.name .. ' ' .. table.concat(marks, ','))
		end
		table.insert(out, groups)
	end
	return out
]]

-- The current tab's pool id.
local function pool_here()
	return child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
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
	-- the split closed: its marks go onto its entry, which alone holds the text now, until the file's next save
	-- or load; nothing else names it
	child.cmd('close')
	child.settle(100)
	local holders = child.lua([[
		local H = require('frogman.domains.history')
		local Hd = require('frogman.domains.history.handles')
		local out = {}
		for hash, path in pairs(H.data.hash_filepath_registry.filepaths) do
			if path:match('^NONAME_') then
				for _, place in ipairs(Hd.holders(Hd.of_hash(hash).id)) do
					table.insert(out, (place:gsub('%d+$', 'N')))
				end
			end
		end
		return out
	]])
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
	eq({ holders = holders, opened = opened() }, { holders = { 'entry:closed:N' }, opened = { '[No Name]', { '' } } })
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
		return require('frogman.domains.marks').label_of(H.get_handle_from_hash(H.routines.get_filehash(_G.FRG_TEST.root .. '/d.txt')), win) or false
	]])
	eq(S2.save(child), { true })
	local on_entry = child.lua([[
		local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), nil)
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
		local path = _G.FRG_TEST.session_path(dir, name)
		local fh = assert(io.open(path, 'rb')); local bytes = fh:read('*a'); fh:close()
		local salt = bytes:sub(5, 4 + crypto.salt_length)
		local data = _G.FRG_TEST.read_session(dir, name)
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
		local buf = (require('frogman.domains.marks.popup').buffer() or -1)
		if buf == -1 then return vim.NIL end
		return { buf = buf, lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false), modified = vim.bo[buf].modified,
			ft = vim.bo[buf].filetype, bt = vim.bo[buf].buftype, current = vim.api.nvim_get_current_buf() == buf }
	]])
end

-- The pop-up's lines replaced, then written with :w.
local function write_lines(lines)
	child.lua('vim.api.nvim_buf_set_lines((require("frogman.domains.marks.popup").buffer() or -1), 0, -1, false, ...)', { lines })
	child.cmd('silent! write')
	child.settle(100)
end

-- The virtual text drawn on the pop-up's lines, joined line by line, with the mode line first.
local function decoration()
	return child.lua([[
		local buf = (require('frogman.domains.marks.popup').buffer() or -1)
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

T['T740 [char] (M15, DESK.md:1308) a header deleted is asked about, and its rows join the group above; the first one deleted refuses'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e e', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({ a = 'b.txt' }))
	table.insert(lines, '❖ feature')
	table.insert(lines, 's -> c.txt')
	write_lines(lines)
	-- feature's header deleted: the write asks first; No writes nothing, Yes joins s -> c.txt to main
	local now = popup().lines
	table.remove(now, vim.fn.index(now, '❖ feature') + 1)
	child.answer('No')
	write_lines(now)
	local asked = child.prompts()
	local kept = { c = label('c'), modified = popup().modified }
	child.answer('Yes')
	child.cmd('silent! write')
	child.settle(100)
	local joined = { c = label('c'), groups = #child.lua('return require("frogman.domains.marks").data.scopes.window[vim.fn.win_getid(vim.fn.winnr("#"))].groups') }
	child.messages()
	now = popup().lines
	table.remove(now, 1)
	write_lines(now)
	local said = vim.tbl_map(function(m) return m.msg end, child.messages())
	eq({ asked = #asked, gone = (asked[1] or ''):find("❖ feature's header is gone: its rows join ❖ main", 1, true) ~= nil,
		kept = kept, joined = joined, said = said, modified = popup().modified },
		{ asked = 1, gone = true, kept = { c = false, modified = true }, joined = { c = 's', groups = 1 },
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

-- Telescope stubbed as far as the pop-up uses it: each picker picks the next of _G.FRG_PICKS, and its
-- attach_mappings gets a map that maps nothing, as telescope's own gives it one.
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
			return { new = function(_, opts) return { find = function() opts.attach_mappings(1, function() end); chosen() end } end }
		end
		package.preload['telescope.builtin'] = function()
			return { find_files = function(opts) opts.attach_mappings(1, function() end); chosen() end }
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
		return { vim.tbl_map(function(h) return vim.fn.fnamemodify(H.get_filepath_from_handle(h), ':t:r') end, t.primary_buffer), t.primary_enabled }
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

T['T748 [char] (M15, DESK.md:1304) a mode key in the pop-up keeps the edits as a draft, :w writes the screen\'s scope, q every draft'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	-- the window's scope edited, then the tab's shown: nothing written yet
	child.lua('vim.api.nvim_buf_set_lines(0, 2, 3, false, { "s -> c.txt" })')
	child.steps({ "<M-'><M-2>" })
	local tab = { lines = popup().lines, mode = decoration()[1], modified = popup().modified }
	-- the tab's edited too, then the window's draft back as it was left
	child.lua('vim.api.nvim_buf_set_lines(0, 1, 2, false, { "a -> d.txt" })')
	child.steps({ "<M-'><M-1>" })
	local back = { s = popup().lines[3], mode = decoration()[1], c = label('c') }
	-- :w writes the window's scope alone, the tab's draft still held
	child.cmd('silent! write')
	child.settle(100)
	local written = { c = label('c'), modified = popup().modified, mode = decoration()[1] }
	-- q writes the tab's draft and leaves
	child.step('q')
	child.settle(100)
	local gone = popup() == vim.NIL
	child.steps({ "<M-'><M-2>" })
	eq({ tab = tab, back = back, written = written, gone = gone, d = label('d') }, {
		tab = { lines = vim.list_extend({ '❖ main' }, rows({})), mode = 'marks · tab · draft: window', modified = true },
		back = { s = 's -> c.txt', mode = 'marks · window · draft: tab', c = false },
		written = { c = 's', modified = true, mode = 'marks · window · draft: tab' },
		gone = true, d = 'a',
	})
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
		return { queue = vim.tbl_map(function(h) return vim.fn.fnamemodify(H.get_filepath_from_handle(h) or '?', ':t:r') end, t.primary_buffer),
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

T['T885 [char] (M15, M16, M11) a close\'s hold-over is settle work'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('split')
	child.settle()
	child.steps({ ADD .. 'a>', '<M-;><M-s>' })
	local in_batch = child.lua([[
		vim.cmd('close')
		require('frogman').mark_mode('window')
		local n = 0
		for _, g in ipairs((require('frogman.domains.marks').data.scopes.session[''] or { groups = {} }).groups) do
			if g.held then n = n + 1 end
		end
		return n
	]])
	eq(S2.save(child), { true })
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', ADD .. 's>', '<M-;><M-s>' })
	child.lua([[
		vim.cmd('close')
		vim.api.nvim_exec_autocmds('VimLeavePre', {})
	]])
	local saved = child.lua([[
		local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), nil)
		local c = require('frogman.domains.history').routines.get_filehash(_G.FRG_TEST.root .. '/c.txt')
		local groups, snapshots = 0, 0
		for _, g in ipairs(saved and saved.marks or {}) do
			if g.held and g.marks and g.marks.s == c then groups = groups + 1 end
		end
		for _, sn in ipairs(saved and saved.snapshots or {}) do
			if sn.current == c then snapshots = snapshots + 1 end
		end
		return { groups = groups, snapshots = snapshots }
	]])
	eq({ in_batch = in_batch, saved = saved }, { in_batch = 1, saved = { groups = 1, snapshots = 1 } })
end

T['T886 [char] (S1 Records, M15, M16) a session\'s marks and held-over snapshots are written as they change'] = function()
	child.steps({ ':e a', ':e b' })
	eq(S2.save(child), { true })
	child.steps({ "<M-'><M-3>", ADD .. 'a>', "<M-'><M-1>" })
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', '<M-;><M-s>' })
	child.cmd('close')
	child.settle(1500)
	eq(child.lua([[
		local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), nil)
		local H = require('frogman.domains.history')
		local b = H.routines.get_filehash(_G.FRG_TEST.root .. '/b.txt')
		local c = H.routines.get_filehash(_G.FRG_TEST.root .. '/c.txt')
		local marked, held = false, 0
		for _, g in ipairs(saved and saved.marks or {}) do
			if not g.held and g.marks and g.marks.a == b then marked = true end
		end
		for _, sn in ipairs(saved and saved.snapshots or {}) do
			if sn.current == c then held = held + 1 end
		end
		return { marked = marked, held = held }
	]]), { marked = true, held = 1 })
end

T['T887 [char] (A5, M15, M16) a tab another window keeps open lets the closed window\'s data go'] = function()
	child.steps({ ':e a' })
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>', '<M-;><M-s>' })
	local w = child.lua('return vim.api.nvim_get_current_win()')
	child.lua([[
		local w = ...
		vim.api.nvim_create_autocmd('WinClosed', { pattern = tostring(w), once = true, callback = function()
			vim.api.nvim_open_win(0, false, { split = 'right', win = w })
		end })
	]], { w })
	child.cmd('q')
	child.settle(300)
	eq(child.lua([[
		local w = ...
		local Wd = require('frogman.domains.window').data
		local H = require('frogman.domains.history')
		local Mk, Sn = require('frogman.domains.marks'), require('frogman.domains.snapshots')
		local held = 0
		for _, g in ipairs((Mk.data.scopes.session[''] or { groups = {} }).groups) do if g.held then held = held + 1 end end
		return { tabs = #vim.api.nvim_list_tabpages(), triquetra = Wd.crux[w] ~= nil, history = H.data.crux_internals.window[w] ~= nil,
			marks = Mk.data.scopes.window[w] ~= nil, snapshots = Sn.data.by_window[w] ~= nil, held = held,
			held_snapshots = #Sn.routines.held_in('') }
	]], { w }), { tabs = 2, triquetra = false, history = false, marks = false, snapshots = false, held = 1, held_snapshots = 1 })
end

-- A window of a tab session's tab closed while another window keeps the tab open: its marks and its snapshot
-- go onto its entry in t's file, nothing held over.
T['T892 [char] (M15, M16, DESK.md:1313, :2065) a tab session\'s window closed while another keeps its tab open puts its marks and snapshots onto its entry in t\'s file'] = function()
	local s = S2.shared()
	tab_session(s)
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	eq(child.lua('return #vim.api.nvim_tabpage_list_wins(0)'), 1)
	child.steps({ ':e c', ADD .. 'a>', '<M-;><M-s>' })
	local w = child.lua('return vim.api.nvim_get_current_win()')
	child.lua([[
		local w = ...
		vim.api.nvim_create_autocmd('WinClosed', { pattern = tostring(w), once = true, callback = function()
			vim.api.nvim_open_win(0, false, { split = 'right', win = w })
		end })
	]], { w })
	child.cmd('q')
	child.settle(1500) -- the close's write lands with the records
	eq(child.lua([[
		local id = ...
		local Mk, Sn = require('frogman.domains.marks'), require('frogman.domains.snapshots')
		local held = 0
		for _, g in ipairs((Mk.data.scopes.session[id] or { groups = {} }).groups) do if g.held then held = held + 1 end end
		local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), 't') or {}
		local filed = 0
		for _, entry in ipairs(saved.windows or {}) do
			if type(entry) == 'table' and type(entry[11]) == 'table' then filed = filed + #entry[11] end
		end
		return { held = held, snapshots = #Sn.routines.held_in(id), filed_snapshots = filed }
	]], { id }), { held = 0, snapshots = 0, filed_snapshots = 1 })
	eq(child.lua(ENTRY_GROUPS, { 't' }), { { 'main a=c' } })
end

T['T751 [char] (M15) a window closed while you work with no saved entry leaves its marks held over'] = function()
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

T['T753 [char] (M15, DESK.md:1315) a reload in the same call as a close holds nothing over'] = function()
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

T['T882 [char] (M15) a row the pop-up drew follows its file'] = function()
	child.steps({ ':e a', ':e b', ADD .. 'a>', ':e c', OPEN })
	child.lua('vim.api.nvim_buf_set_lines((require("frogman.domains.marks.popup").buffer() or -1), 0, -1, false, { "❖ main", "a -> b.txt", "s -> c.txt" })')
	child.lua([[
		local root = _G.FRG_TEST.root
		os.rename(root .. '/b.txt', root .. '/g.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/b.txt'), root .. '/g.txt')
		require('frogman.settle').drain()
	]])
	child.settle(300)
	child.lua('vim.api.nvim_set_current_win((require("frogman.domains.marks.popup").window() or -1))')
	child.cmd('silent! write')
	child.settle(100)
	child.cmd('close')
	child.settle()
	eq({ g = label('g'), c = label('c') }, { g = 'a', c = 's' })
end

T['T891 [char] (M15) a row\'s closed glyph sits at its name however it\'s spaced'] = function()
	child.steps({ ':e a', ':e b', ADD .. 'a>', ':e c' })
	child.cmd('bdelete b.txt')
	child.settle()
	child.steps({ OPEN })
	local col = child.lua([[
		local buf = (require('frogman.domains.marks.popup').buffer() or -1)
		vim.api.nvim_buf_set_lines(buf, 1, 2, false, { 'a->b.txt' })
		vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf })
		local ns = vim.api.nvim_get_namespaces()['frogman_marks_popup']
		for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { 1, 0 }, { 1, -1 }, { details = true })) do
			if m[4].virt_text and m[4].virt_text_pos == 'inline' then return m[3] end
		end
		return false
	]])
	eq({ line = child.lua('return vim.api.nvim_buf_get_lines((require("frogman.domains.marks.popup").buffer() or -1), 1, 2, false)[1]'), col = col },
		{ line = 'a->b.txt', col = 3 })
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
	child.lua('vim.api.nvim_buf_set_lines((require("frogman.domains.marks.popup").buffer() or -1), 0, -1, false, { "❖ main", "d -> b.txt" })')
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
		local left = #vim.tbl_filter(function(b) return vim.api.nvim_buf_get_name(b):find('frogman://marks', 1, true) ~= nil end, vim.api.nvim_list_bufs()) > 0
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
		local left = #vim.tbl_filter(function(b) return vim.api.nvim_buf_get_name(b):find('frogman://marks', 1, true) ~= nil end, vim.api.nvim_list_bufs()) > 0
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
		local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), 't')
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

T['T883 [char] (M15, M16, S1 Load) a copy held over of an entry a detached list waits on goes when its tab comes back unchanged'] = function()
	local s = S2.shared()
	tab_session(s)
	eq(S2.save(child), { true })
	child.steps({ ':e c', ADD .. 'a>', '<M-;><M-s>', ':e d' }) -- a window mark and a snapshot in t's tab
	eq(S2.load_tab_session(child, 't'), { true }) -- that tab keeps t_DETACHED
	eq(S2.save(child), { true })
	S2.start(child, s)
	S2.restore_tabs(child, { { files = { 'x', 't' }, shown = 't' } })
	eq(S2.load(child), { true }) -- the list's tab stays away: its window's marks and snapshot held over
	child.settle(300)
	S2.start(child, s) -- the quit writes the records, no save
	S2.restore_tabs(child, { { files = { 'x', 't' }, shown = 't' }, { files = { 'c', 'd' }, shown = 'd' },
		{ files = { 'c', 'd' }, shown = 'd' } })
	eq(S2.load(child), { true })
	child.settle(300)
	child.cmd('tabnext 2')
	child.settle()
	local own = child.lua('return #require("frogman.domains.snapshots").routines.of_window(vim.api.nvim_get_current_win())')
	local left = child.lua([[
		local H = require('frogman.domains.history')
		local Sn = require('frogman.domains.snapshots').routines
		local c = H.routines.get_filehash(_G.FRG_TEST.root .. '/c.txt')
		local groups, snapshots = 0, 0
		for _, g in ipairs((require('frogman.domains.marks').data.scopes.session[''] or { groups = {} }).groups) do
			local h = g.held and g.marks.a and H.handles.get(H.handles.resolve(g.marks.a))
			if h and h.hash == c then groups = groups + 1 end
		end
		for _, snap in ipairs(Sn.held_in('')) do
			local h = Sn.handle(snap.current)
			if h and h.hash == c then snapshots = snapshots + 1 end
		end
		return { groups = groups, snapshots = snapshots }
	]])
	child.steps({ JUMP .. 'a>' })
	eq({ shown = child.shown(), own = own, left = left }, { shown = 'c', own = 1, left = { groups = 0, snapshots = 0 } })
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

T['T761 [char] (M15, DESK.md:1315) a tab session\'s load keeps what its own tab\'s closes queued, held over as the rest are'] = function()
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
	local marked = vim.tbl_map(function(g) return g.marks.a end, held)
	table.sort(marked)
	eq({ n = #held, marked = marked }, { n = 2, marked = { 'b', 'd' } })
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
		local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), nil)
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

-- The whole editor's held-over groups in memory, each by its header without the time and its marks by file
-- letter, and its file's held-over marks.
local function editor_held()
	return child.lua([[
		local function what(name) return (name:gsub('^held over · ', ''):gsub(' · %d%d%-%d%d %d%d:%d%d.*$', '')) end
		local H = require('frogman.domains.history')
		local memory = {}
		for _, g in ipairs((require('frogman.domains.marks').data.scopes.session[''] or { groups = {} }).groups) do
			if g.held then
				local marks = {}
				for alias, id in pairs(g.marks) do
					table.insert(marks, alias .. '=' .. vim.fn.fnamemodify(H.get_filepath_from_handle(H.handles.resolve(id)) or '?', ':t:r'))
				end
				table.sort(marks)
				table.insert(memory, what(g.name) .. ' ' .. table.concat(marks, ','))
			end
		end
		local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), nil) or {}
		local file = {}
		for _, g in ipairs(saved.marks or {}) do
			if g.held then
				for alias, h in pairs(g.marks or {}) do table.insert(file, alias .. '=' .. vim.fn.fnamemodify((saved.paths or {})[h] or h, ':t:r')) end
			end
		end
		table.sort(file)
		return { memory = memory, file = file }
	]])
end

-- T823's route: in t_DETACHED's tab, e marked in session mode and closed, and, unless kept, its line deleted from
-- the list, so the mark alone holds it; the tab closed.
local function detached_into_file(s, kept)
	detached(s)
	child.steps({ "<M-'><M-3>", ':e e', ADD .. 'a>', ':e d' })
	child.cmd('bdelete e.txt')
	child.settle()
	if not kept then
		local p = S2.picker(child)
		local lines = vim.deepcopy(p.lines)
		table.remove(lines, S2.line_of(lines, 'e.txt'))
		S2.write_picker(child, p, lines)
		child.cmd('close')
		child.settle(100)
	end
	child.cmd('tabclose')
	child.settle(300)
end

-- T823's route, the list emptied before its tab closes: it goes as an emptied list does, the mark that alone holds
-- e held over in the whole editor's scope under the list's name, which the next save keeps.
T['T823 [char] (M15, M5, DESK.md:1322) a detached list whose tab closes with only a mark holding its file gives the mark to the whole editor\'s scope through the next save'] = function()
	local s = S2.shared()
	detached_into_file(s)
	local written = detached_marks()
	eq(S2.save(child), { true })
	eq({ written = written, saved = detached_marks(), held = editor_held() },
		{ written = false, saved = false, held = { memory = { 't_DETACHED a=e' }, file = { 'a=e' } } })
end

T['T824 [char] (M15, M5, S1 Load) a list in the whole editor\'s file alone keeps its marks across a load and a save'] = function()
	local s = S2.shared()
	detached_into_file(s, true) -- e kept on the list, so the list goes into the file with its mark
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
		local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), nil)
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
		local data = _G.FRG_TEST.read_session(dir, nil)
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
		local data = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), nil)
		local entry = data.windows[1]
		return type(entry[10]) == 'table' and entry[10][1] ~= nil
	]])
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	local held = vim.tbl_filter(function(g) return g.held and vim.deep_equal(g.marks, { a = 'd' }) end, session_groups(''))
	eq({ kept = kept, held = #held }, { kept = true, held = 1 })
end

-- An index can be a number or a string, and 1 and "1" are two (DESK.md:1297).
T['T950 [char] (M15, DESK.md:1297) 1 and "1" are two indices'] = function()
	local ok = child.lua([[return (pcall(_G.FRG_TEST.setup, { marks = { aliases = { a = 1, s = '1' } } }))]])
	child.steps({ ':e b', ADD .. 'a>', ':e c', ADD .. 's>', ':e d', JUMP .. 'a>' })
	local a = child.shown()
	child.steps({ JUMP .. 's>' })
	local s = child.shown()
	eq({ ok = ok, a = a, s = s }, { ok = true, a = 'b', s = 'c' })
end

-- A row "* -> b.txt" would read as a header named "-> b.txt": the glyphs a header opens with, either
-- set's and one of one's own, can't be aliases.
T['T951 [char] (M15, DESK.md:1297) an alias that\'s a group header\'s glyph is refused at setup'] = function()
	local got = child.lua([[
		local out = {}
		for _, case in ipairs({ { alias = '*' }, { alias = '❖' }, { alias = '▸', glyphs = { group = '▸' } } }) do
			local ok, err = pcall(require('frogman').setup, { marks = { aliases = { [case.alias] = 9, a = 1 } }, glyphs = case.glyphs })
			table.insert(out, { ok, tostring(err):find(case.alias, 1, true) ~= nil and tostring(err):find('header', 1, true) ~= nil })
		end
		return out
	]])
	eq(got, { { false, true }, { false, true }, { false, true } })
end

-- A copy no one changed holds nothing over when its window goes without its WinClosed either.
T['T952 [char] (M15, DESK.md:1300) a split\'s copy no one changed, closed without its events, holds nothing over'] = function()
	child.lua('_G.FRG_TEST.setup({ marks = { split_copies = true } })')
	local held = [[
		local groups = (require('frogman.domains.marks').data.scopes.session[''] or { groups = {} }).groups
		return #vim.tbl_filter(function(g) return g.held end, groups)
	]]
	local function gone()
		child.cmd('noautocmd close')
		child.settle()
		child.lua('require("frogman.domains.history").routines.cleanup_system()')
		child.settle(100)
		return child.lua(held)
	end
	child.steps({ ':e b', ADD .. 'a>' })
	local first = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('split')
	child.settle()
	local copy = gone() -- the copy, unchanged
	child.cmd('split')
	child.settle()
	child.lua('vim.api.nvim_set_current_win(...)', { first })
	child.settle()
	local original = gone() -- the window the copy came from, the copy alive and unchanged
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', ADD .. 's>' })
	local changed = gone() -- a copy changed since: held over
	eq({ copy = copy, original = original, changed = changed }, { copy = 0, original = 0, changed = 1 })
end

-- Telescope stubbed, each map() an attach_mappings makes recorded: the marks' two pickers switch
-- <Tab> and <S-Tab> off, in insert and normal mode, so one entry is picked; the primary pop-up's keeps
-- them, picking several.
T['T953 [char] (M15, DESK.md:1304, :1335) the marks\' pickers pick one entry, the primary pop-up\'s several'] = function()
	child.steps({ ':e b', ':e e', OPEN })
	stub_pickers()
	child.lua([[
		-- the primary pop-up's picker reads the selection, which the stub keeps empty
		require('telescope.actions.state').get_current_picker = function() return { get_multi_selection = function() return {} end } end
		_G.FRG_MAPPED = {}
		local pickers, builtin = require('telescope.pickers'), require('telescope.builtin')
		local function recording(attach)
			return function(prompt) return attach(prompt, function(modes, key, fn)
				for _, mode in ipairs(type(modes) == 'table' and modes or { modes }) do
					table.insert(_G.FRG_MAPPED, { picker = _G.FRG_PICKER, mode = mode, key = key, off = fn == false })
				end
			end) end
		end
		local new, find_files = pickers.new, builtin.find_files
		pickers.new = function(a, opts) opts.attach_mappings = recording(opts.attach_mappings); return new(a, opts) end
		builtin.find_files = function(opts) opts.attach_mappings = recording(opts.attach_mappings); return find_files(opts) end
		_G.FRG_PICKS = { 's', _G.FRG_TEST.root .. '/c.txt' }
		vim.api.nvim_win_set_cursor(0, { 2, 0 })
		_G.FRG_PICKER = 'marks'
	]])
	child.step('a')
	child.settle()
	child.lua([[
		_G.FRG_PICKER = 'primary'
		_G.FRG_PICKS = { _G.FRG_TEST.root .. '/d.txt' }
		require('frogman.domains.ui').routines.pick_files(true, function() end)
	]])
	local mapped = child.lua('return _G.FRG_MAPPED')
	local off = {}
	for _, m in ipairs(mapped) do
		if m.off then table.insert(off, m.picker .. ' ' .. m.mode .. ' ' .. m.key) end
	end
	table.sort(off)
	-- (the README's telescope line naming the marks pop-up is D27's to pin, in tests/test_docs.lua)
	eq(off, { 'marks i <S-Tab>', 'marks i <S-Tab>', 'marks i <Tab>', 'marks i <Tab>', 'marks n <S-Tab>', 'marks n <S-Tab>', 'marks n <Tab>', 'marks n <Tab>' })
end

-- A jump the unwritten pop-up refuses changes nothing: the cycle running in its window goes on.
T['T954 [char] (M15, DESK.md:1299, :1325) a jump refused for the pop-up\'s unwritten edits leaves a cycle running'] = function()
	child.steps({ ':e a', ':e b', ADD .. 'a>', ':e c', OPEN })
	child.lua('vim.api.nvim_buf_set_lines(0, 2, 3, false, { "s -> d.txt" })')
	child.cmd('wincmd p')
	child.settle()
	child.steps({ '<M-m>' })
	local stepped = child.shown()
	child.messages()
	child.steps({ JUMP .. 'a>' })
	local said = vim.tbl_map(function(m) return m.msg end, child.messages())
	local dirty = 'frogman: the marks pop-up has edits not written yet: write them with :w, or leave them, first.'
	eq({ said = said, shown = child.shown(), nav = child.lua('return require("frogman.domains.navigation").sm:state()') },
		{ said = { dirty }, shown = stepped, nav = 'cycling' })
end

-- A split's marks held over in the whole editor's scope as it closes, then the session's pop-up.
local function held_session_popup()
	child.steps({ ':e a' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e b', ADD .. 'a>' })
	child.cmd('close')
	child.settle(100)
	child.steps({ "<M-'><M-3>", OPEN })
	local lines = popup().lines
	local held
	for i, line in ipairs(lines) do
		if line:find('^❖ held over') then held = i end
	end
	return lines, held
end

local SESSION_FLAGS = [[
	local s = require('frogman.domains.marks').data.scopes.session['']
	return vim.tbl_map(function(g) return { name = g.name:match('^held over') and 'held over' or g.name, held = g.held == true } end, s.groups)
]]

-- A group typed under a held-over group's name, below it: each keeps its own flag, by its place among
-- the groups of that name, not by the name alone.
T['T955 [char] (M15, DESK.md:1303) two groups of one name keep their own held flags, by their place'] = function()
	local lines, held = held_session_popup()
	table.insert(lines, lines[held])
	table.insert(lines, 's -> c.txt')
	child.answer('Yes')
	write_lines(lines)
	eq(child.lua(SESSION_FLAGS), {
		{ name = 'main', held = false }, { name = 'held over', held = true }, { name = 'held over', held = false },
	})
end

-- Renaming a held-over group's header leaves it held over: it's the same group, in its place.
T['T956 [char] (M15, DESK.md:1318) a held-over group whose header is renamed stays held over'] = function()
	local lines, held = held_session_popup()
	lines[held] = '❖ kept'
	write_lines(lines)
	eq(child.lua(SESSION_FLAGS), { { name = 'main', held = false }, { name = 'kept', held = true } })
end

-- The default group's header renamed in place makes a typed group: saved, empty, it stays first across
-- a restart.
T['T957 [char] (M15, DESK.md:1307, :1301) a typed group is saved even while it\'s empty'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e b', OPEN })
	local lines = popup().lines
	lines[1] = '❖ feature'
	write_lines(lines)
	child.cmd('close')
	child.settle()
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	eq(child.lua([[
		local s = require('frogman.domains.marks').data.scopes.window[vim.api.nvim_get_current_win()]
		return s and vim.tbl_map(function(g) return g.name end, s.groups) or {}
	]]), { 'feature' })
end

-- The default group a mark's add made, emptied again: saved, it comes back empty.
T['T958 [char] (M15, DESK.md:1301) the default group emptied again is saved, and comes back empty'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e b', ADD .. 'a>', OPEN })
	write_lines(vim.list_extend({ '❖ main' }, rows({})))
	child.cmd('close')
	child.settle()
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	eq(child.lua([[
		local s = require('frogman.domains.marks').data.scopes.window[vim.api.nvim_get_current_win()]
		return s and vim.tbl_map(function(g) return { name = g.name, marked = next(g.marks) ~= nil } end, s.groups) or {}
	]]), { { name = 'main', marked = false } })
end

-- The current window's groups, each with its marks by file letter.
local WINDOW_GROUPS = [[
	local d = require('frogman.domains.marks').data
	local H = require('frogman.domains.history')
	local s = d.scopes.window[vim.api.nvim_get_current_win()]
	return vim.tbl_map(function(g)
		local marks = {}
		for alias, hid in pairs(g.marks) do
			local h = H.handles.get(hid)
			marks[alias] = h and vim.fn.fnamemodify(H.get_filepath_from_hash(h.hash), ':t:r') or false
		end
		return { name = g.name, marks = marks }
	end, s and s.groups or {})
]]

-- A tab session's window entry bringing a typed group with no marks: a window with marks of its own
-- keeps them and takes the group below them, nothing held over, and a window with none takes the group.
T['T959 [char] (M15, S1 Load, DESK.md:1333, :1307) an entry bringing only an empty typed group leaves a window\'s own marks, the group below them, and gives a window with none the group'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', OPEN })
	local lines = popup().lines
	lines[1] = '❖ feature'
	write_lines(lines)
	child.cmd('close')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e b', ADD .. 'a>', ':e a' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local own = child.lua(WINDOW_GROUPS)
	local held = child.lua([[
		local id = require('frogman.domains.history').data.tab_pools[vim.api.nvim_get_current_tabpage()]
		local scope = require('frogman.domains.marks').data.scopes.session[id]
		return #vim.tbl_filter(function(g) return g.held == true end, scope and scope.groups or {})
	]])
	S2.start(child, s)
	child.steps({ ':e a' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	eq({ own = own, held = held, typed = child.lua(WINDOW_GROUPS) },
		{ own = { { name = 'main', marks = { a = 'b' } }, { name = 'feature', marks = {} } }, held = 0,
			typed = { { name = 'feature', marks = {} } } })
end

-- Deleting a held-over group's header and rows, the way to clear it, asks nothing: no row of it is left
-- to join another group.
T['T960 [char] (M15, DESK.md:1308, :1318) a held-over group deleted with its rows is cleared with nothing asked'] = function()
	local lines, held = held_session_popup()
	local kept = {}
	for i, line in ipairs(lines) do
		if i < held then
			table.insert(kept, line)
		end
	end
	child.answer('No')
	write_lines(kept)
	eq({ asked = #child.prompts(), flags = child.lua(SESSION_FLAGS), modified = popup().modified },
		{ asked = 0, flags = { { name = 'main', held = false } }, modified = false })
end

-- The first of two groups of one name deleted, its rows under the group above: that group is asked
-- about, and the second keeps its own.
T['T961 [char] (M15, DESK.md:1303, :1308) the first of two groups of one name deleted is asked about as the one gone'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e e', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({ a = 'b.txt' }))
	vim.list_extend(lines, { '❖ x', 's -> c.txt', '❖ x', 'd -> d.txt' })
	child.answer('Yes')
	write_lines(lines)
	child.prompts()
	local now = popup().lines
	table.remove(now, vim.fn.index(now, '❖ x') + 1)
	child.answer('Yes')
	write_lines(now)
	local asked = child.prompts()
	eq({ asked = #asked, gone = (asked[1] or ''):find("❖ x/1's header is gone: its rows join ❖ main", 1, true) ~= nil,
		groups = #child.lua('return require("frogman.domains.marks").data.scopes.window[vim.fn.win_getid(vim.fn.winnr("#"))].groups'),
		c = label('c'), d = label('d') },
		{ asked = 1, gone = true, groups = 2, c = 's', d = false })
end

-- A header deleted, its rows under the group above, and a group typed where it was: the deleted one is
-- still asked about, and the typed one is a group of its own.
T['T962 [char] (M15, DESK.md:1308) a header deleted is asked about though a group is typed in its place'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e e', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({ a = 'b.txt' }))
	vim.list_extend(lines, { '❖ feature', 's -> c.txt' })
	write_lines(lines)
	local now = popup().lines
	table.remove(now, vim.fn.index(now, '❖ feature') + 1)
	table.insert(now, '❖ new')
	child.answer('Yes')
	write_lines(now)
	local asked = child.prompts()
	eq({ asked = #asked, gone = (asked[1] or ''):find("❖ feature's header is gone: its rows join ❖ main", 1, true) ~= nil,
		c = label('c') }, { asked = 1, gone = true, c = 's' })
end

-- A held-over group deleted whole asks nothing, though the first group holds the same mark.
T['T963 [char] (M15, DESK.md:1308, :1318) a held-over group deleted whole asks nothing though the first group holds the same mark'] = function()
	child.steps({ ':e a', "<M-'><M-3>", ':e b', ADD .. 'a>', "<M-'><M-1>" })
	child.cmd('split')
	child.settle()
	child.steps({ ADD .. 'a>' })
	child.cmd('close')
	child.settle(100)
	child.steps({ "<M-'><M-3>", OPEN })
	local lines = popup().lines
	local held
	for i, line in ipairs(lines) do
		if line:find('^❖ held over') then held = i end
	end
	child.answer('No')
	write_lines(vim.list_slice(lines, 1, held - 1))
	eq({ asked = #child.prompts(), flags = child.lua(SESSION_FLAGS), b = label('b') },
		{ asked = 0, flags = { { name = 'main', held = false } }, b = 'a' })
end

-- The current window's groups, from the pop-up opened on it, with their default flags.
local DEFAULTS = [[
	local s = require("frogman.domains.marks").data.scopes.window[vim.fn.win_getid(vim.fn.winnr("#"))]
	return vim.tbl_map(function(g) return { name = g.name, default = g.default == true } end, s.groups)
]]

-- A header deleted under an empty default group: asked about, and the default group stays the default.
T['T964 [char] (M15, DESK.md:1308, :1301) a header deleted under an empty default group is asked about, and the default stays'] = function()
	child.steps({ ':e e', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({}))
	vim.list_extend(lines, { '❖ dev', 'a -> b.txt' })
	write_lines(lines)
	local now = popup().lines
	table.remove(now, vim.fn.index(now, '❖ dev') + 1)
	child.answer('Yes')
	write_lines(now)
	local asked = child.prompts()
	eq({ asked = #asked, gone = (asked[1] or ''):find("❖ dev's header is gone: its rows join ❖ main", 1, true) ~= nil,
		groups = child.lua(DEFAULTS), b = label('b') },
		{ asked = 1, gone = true, groups = { { name = 'main', default = true } }, b = 'a' })
end

-- A group typed where a held-over group was deleted whole is a group of its own, not held over.
T['T965 [char] (M15, DESK.md:1308, :1318) a group typed where a held-over group was deleted whole isn\'t held over'] = function()
	local lines, held = held_session_popup()
	local kept = vim.list_slice(lines, 1, held - 1)
	vim.list_extend(kept, { '❖ new', 's -> c.txt' })
	child.answer('No')
	write_lines(kept)
	eq({ asked = #child.prompts(), flags = child.lua(SESSION_FLAGS) },
		{ asked = 0, flags = { { name = 'main', held = false }, { name = 'new', held = false } } })
end

-- Of two groups of one name, the second's header deleted: the first, whose header stands, keeps what it
-- was, though the second had more marks.
T['T966 [char] (M15, DESK.md:1303, :1308) of two groups of one name, the one whose header stands keeps what it was'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e e', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({ a = 'b.txt' }))
	vim.list_extend(lines, { '❖ main', 's -> c.txt', 'd -> d.txt' })
	child.answer('Yes')
	write_lines(lines)
	child.prompts()
	local now = popup().lines
	local second
	for i, line in ipairs(now) do
		if line == '❖ main' and i > 1 then second = i end
	end
	table.remove(now, second)
	child.answer('Yes')
	write_lines(now)
	local asked = child.prompts()
	eq({ asked = #asked, gone = (asked[1] or ''):find("❖ main/2's header is gone: its rows join ❖ main", 1, true) ~= nil,
		groups = child.lua(DEFAULTS) },
		{ asked = 1, gone = true, groups = { { name = 'main', default = true } } })
end

-- A held-over group whose header is renamed and every mark changed is a group of its own: what it was
-- is known by its marks, and none is left (mine).
T['T967 [char] (M15, DESK.md:1308, :1318) a held-over group renamed with every mark changed is a group of its own'] = function()
	local lines, held = held_session_popup()
	lines[held] = '❖ kept'
	for i = held + 1, #lines do
		if lines[i] == 'a -> b.txt' then lines[i] = 's -> c.txt' end
	end
	write_lines(lines)
	eq(child.lua(SESSION_FLAGS), { { name = 'main', held = false }, { name = 'kept', held = false } })
end

-- The first group's header deleted while it has no marks: its empty rows name nothing, so the write goes
-- through and the next group is the first.
T['T971 [char] (M15, DESK.md:1308) the first group\'s header deleted while it has no marks writes, the next group first'] = function()
	child.steps({ ':e e', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({}))
	vim.list_extend(lines, { '❖ dev', 'a -> b.txt' })
	write_lines(lines)
	local now = popup().lines
	table.remove(now, 1)
	child.answer('No')
	child.messages()
	write_lines(now)
	eq({ asked = #child.prompts(), said = said(), groups = child.lua(DEFAULTS), b = label('b'), modified = popup().modified },
		{ asked = 0, said = {}, groups = { { name = 'dev', default = false } }, b = 'a', modified = false })
end

-- A header renamed and the next one deleted in one write: the deleted one is asked about, though it had
-- more marks than the renamed one.
T['T972 [char] (M15, DESK.md:1308) a header renamed and the next one deleted: the deleted one is asked about'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e e', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({ a = 'b.txt' }))
	vim.list_extend(lines, { '❖ feature', 's -> c.txt', 'd -> d.txt', 'f -> f.txt' })
	write_lines(lines)
	local now = popup().lines
	now[1] = '❖ work'
	table.remove(now, vim.fn.index(now, '❖ feature') + 1)
	child.answer('Yes')
	write_lines(now)
	local asked = child.prompts()
	eq({ asked = #asked, gone = (asked[1] or ''):find("❖ feature's header is gone: its rows join ❖ work", 1, true) ~= nil,
		groups = child.lua(DEFAULTS) },
		{ asked = 1, gone = true, groups = { { name = 'work', default = false } } })
end

-- A header renamed with another group's rows moved under it, that group's header standing: nothing is
-- asked, and each group is the one it was.
T['T973 [char] (M15, DESK.md:1308) a header renamed with another group\'s rows moved under it asks nothing'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e e', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({ a = 'b.txt' }))
	vim.list_extend(lines, { '❖ feature', 's -> c.txt', 'd -> d.txt' })
	write_lines(lines)
	child.answer('No')
	write_lines({ '❖ work', 'a -> b.txt', 's -> c.txt', 'd -> d.txt', '❖ feature' })
	eq({ asked = #child.prompts(), groups = child.lua(DEFAULTS), c = label('c') },
		{ asked = 0, groups = { { name = 'work', default = false }, { name = 'feature', default = false } }, c = 's' })
end

-- A header renamed with another group's row pasted first under it, that group's header standing:
-- nothing is asked, and each group is the one it was.
T['T974 [char] (M15, DESK.md:1303, :1308) a renamed group with another group\'s row pasted first under it asks nothing'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e e', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({ a = 'b.txt' }))
	vim.list_extend(lines, { '❖ feature', 's -> c.txt' })
	write_lines(lines)
	child.answer('No')
	write_lines({ '❖ work', 's -> c.txt', 'a -> b.txt', '❖ feature' })
	eq({ asked = #child.prompts(), groups = child.lua(DEFAULTS) },
		{ asked = 0, groups = { { name = 'work', default = false }, { name = 'feature', default = false } } })
end

-- Two groups of one name whose rows swap places: each group is the one at its place, so the first stays
-- the default ("we distinguish them by which comes first").
T['T975 [char] (M15, DESK.md:1303) two groups of one name keep their places when their rows swap'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e e', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({ a = 'b.txt' }))
	vim.list_extend(lines, { '❖ main', 's -> c.txt' })
	child.answer('Yes')
	write_lines(lines)
	child.prompts()
	child.answer('Yes')
	write_lines({ '❖ main', 's -> c.txt', '❖ main', 'a -> b.txt' })
	local asked = child.prompts()
	eq({ asked = #asked, second = (asked[1] or ''):find('is a second group of that name', 1, true) ~= nil,
		gone = (asked[1] or ''):find('header is gone', 1, true) ~= nil, groups = child.lua(DEFAULTS) },
		{ asked = 1, second = true, gone = false, groups = { { name = 'main', default = true }, { name = 'main', default = false } } })
end

-- A mode switch with an alias holding two files on the screen is refused.
T['T968 [char] (M15, DESK.md:1304) a mode switch is refused while an alias holds two files on the screen'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	local lines = popup().lines
	table.insert(lines, 3, 'a -> c.txt')
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, ...)', { lines })
	child.messages()
	child.steps({ "<M-'><M-2>" })
	eq({ said = said(), mode = decoration()[1], lines = popup().lines, modified = popup().modified }, {
		said = { 'frogman: ⟨a⟩ holds two files in ❖ main: keep one.' }, mode = 'marks · window', lines = lines, modified = true,
	})
end

-- :q refuses while another scope holds a draft, the mark keys refuse too, and :q! drops every draft.
T['T969 [char] (M15, DESK.md:1304, :1325) :q refuses while a draft is held, the mark keys refuse, and :q! drops every draft'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.lua('vim.api.nvim_buf_set_lines(0, 2, 3, false, { "s -> c.txt" })')
	child.steps({ "<M-'><M-2>" })
	local quit = child.lua('return { pcall(vim.cmd, "quit") }')
	local still = popup() ~= vim.NIL
	child.cmd('wincmd p')
	child.settle()
	child.messages()
	child.steps({ JUMP .. 'a>' })
	local refused = said()
	child.lua('vim.api.nvim_set_current_win((require("frogman.domains.marks.popup").window() or -1))')
	child.cmd('quit!')
	child.settle(100)
	child.steps({ "<M-'><M-1>" })
	eq({ e37 = (quit[2] or ''):find('E37', 1, true) ~= nil, still = still, refused = refused, gone = popup() == vim.NIL,
		b = label('b'), c = label('c') }, {
		e37 = true, still = true,
		refused = { 'frogman: the marks pop-up holds drafts not written yet: write them with q, or drop them with :q!, first.' },
		gone = true, b = 'a', c = false,
	})
end

-- q stops at a draft its checks refuse, showing that draft.
T['T970 [char] (M15, DESK.md:1304) q stops at a draft its checks refuse, and shows it'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	-- the window's header deleted: its rows have no group
	child.lua('vim.api.nvim_buf_set_lines(0, 0, 1, false, {})')
	child.messages()
	child.steps({ "<M-'><M-2>" })
	-- the switch checks nothing but an alias holding two files: the window's lines go as a draft
	local switched = { said = said(), mode = decoration()[1] }
	child.step('q')
	child.settle(100)
	eq({ switched = switched, said = said(), open = popup() ~= vim.NIL, mode = decoration()[1], first = popup().lines[1],
		modified = popup().modified }, {
		switched = { said = {}, mode = 'marks · tab · draft: window' },
		said = { "frogman: the marks above the first group's header have no group: put a header back above them, or delete them." },
		open = true, mode = 'marks · window', first = 'a -> b.txt', modified = true,
	})
end

-- A draft held keeps the pop-up modified through an undo on the screen, so :q still refuses.
T['T982 [char] (M15, DESK.md:1304) a draft held keeps the pop-up modified through an undo on the screen'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.lua('vim.api.nvim_buf_set_lines(0, 2, 3, false, { "s -> c.txt" })')
	child.steps({ "<M-'><M-2>" })
	child.lua('vim.api.nvim_buf_set_lines(0, 1, 2, false, { "a -> d.txt" })')
	child.cmd('silent! undo')
	child.settle(50)
	local quit = child.lua('return { pcall(vim.cmd, "quit") }')
	eq({ e37 = (quit[2] or ''):find('E37', 1, true) ~= nil, open = popup() ~= vim.NIL, modified = popup().modified },
		{ e37 = true, open = true, modified = true })
end

-- An edit undone leaves the screen holding none: the pop-up follows its scope again, and q writes
-- nothing over a mark added meanwhile.
T['T983 [char] (M15, DESK.md:1304) an edit undone leaves the pop-up following its scope, and q writes nothing over it'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>', 'u')
	local undone = popup().modified
	child.cmd('wincmd p')
	child.settle()
	child.steps({ ADD .. 'd>' })
	local shown = popup().lines[4]
	child.lua('vim.api.nvim_set_current_win((require("frogman.domains.marks.popup").window() or -1))')
	child.step('q')
	child.settle(100)
	eq({ undone = undone, shown = shown, gone = popup() == vim.NIL, c = label('c') },
		{ undone = false, shown = 'd -> c.txt', gone = true, c = 'd' })
end

-- Each scope's screen is a buffer of its own, with its own undo history: on the tab's, which a mode switch drew
-- for the first time, an undo takes back what was typed there and goes no further; back on the window's, its
-- history is still there, an undo going back past the switch to before what was typed.
T['T984 [char] (M15, DESK.md:1305) each scope\'s screen keeps its own undo history across a mode switch'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	local drawn = popup().lines
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	local typed = popup().lines
	child.steps({ "<M-'><M-2>" })
	local tab = popup().lines
	child.type_keys('2G', 'cc', 'a -> d.txt', '<Esc>', 'u')
	local once = popup().lines
	child.type_keys('u')
	local twice = popup().lines
	child.steps({ "<M-'><M-1>" })
	local back = popup().lines
	child.type_keys('4G', 'cc', 'd -> b.txt', '<Esc>', 'u', 'u')
	eq({ once = once, twice = twice, back = back, back_undone = popup().lines },
		{ once = tab, twice = tab, back = typed, back_undone = drawn })
end

-- A row typed back as it was drawn holds nothing: the pop-up is unmodified at once, :q closes it, and the
-- mark keys work.
T['T985 [char] (M15, DESK.md:1304, :1325) a row typed back as it was drawn leaves the pop-up unmodified at once'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	local typed = popup().modified
	child.type_keys('cc', 's -> ', '<Esc>')
	local typed_back = popup()
	local quit = child.lua('return { pcall(vim.cmd, "quit") }')
	child.settle()
	child.messages()
	child.steps({ JUMP .. 'a>' })
	eq({ typed = typed, back = typed_back.lines[3], modified = typed_back.modified, quit = quit[1], gone = popup() == vim.NIL,
		said = said(), shown = child.shown() },
		{ typed = true, back = 's -> ', modified = false, quit = true, gone = true, said = {}, shown = 'b' })
end

-- An undo right after the pop-up opens takes nothing back: its draw starts the undo history, so the lines
-- stay as drawn, unmodified, and q writes nothing.
T['T986 [char] (M15, DESK.md:1304) an undo right after the pop-up opens takes nothing back'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', ADD .. 's>', OPEN })
	local drawn = popup().lines
	child.type_keys('u')
	local undone = popup()
	child.step('q')
	child.settle(100)
	eq({ lines = undone.lines, modified = undone.modified, gone = popup() == vim.NIL, b = label('b'), c = label('c') },
		{ lines = drawn, modified = false, gone = true, b = 'a', c = 's' })
end

-- The flag set by hand over lines as drawn: :w finds nothing to write and clears it, and :q then closes.
T['T988 [char] (M15, DESK.md:1304) :w over lines as drawn clears a flag set by hand, and :q then closes the pop-up'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.cmd('set modified')
	child.cmd('silent! write')
	child.settle(100)
	local modified = popup().modified
	local quit = child.lua('return { pcall(vim.cmd, "quit") }')
	child.settle()
	eq({ modified = modified, quit = quit[1], gone = popup() == vim.NIL, b = label('b') },
		{ modified = false, quit = true, gone = true, b = 'a' })
end

-- :set nomodified draws the screen again, its edits dropped, so q writes none of them; a draft held keeps the
-- mark keys refusing all the same, and q writes it.
T['T989 [char] (M15, DESK.md:1305, :1325) :set nomodified drops the screen\'s edits, and a draft held still keeps the mark keys refusing'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	-- a draft of the window's marks: s -> c.txt typed, then the tab's screen
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.steps({ "<M-'><M-2>" })
	-- on the tab's screen, an edit thrown away
	child.type_keys('2G', 'cc', 'a -> d.txt', '<Esc>')
	child.cmd('set nomodified')
	child.cmd('wincmd p')
	child.settle()
	child.messages()
	child.steps({ JUMP .. 'a>' })
	local refused = said()
	child.lua('vim.api.nvim_set_current_win((require("frogman.domains.marks.popup").window() or -1))')
	child.step('q')
	child.settle(100)
	local d_in_tab = label('d')
	child.steps({ "<M-'><M-1>" })
	eq({ refused = refused, gone = popup() == vim.NIL, d_in_tab = d_in_tab, c = label('c') }, {
		refused = { 'frogman: the marks pop-up holds drafts not written yet: write them with q, or drop them with :q!, first.' },
		gone = true, d_in_tab = false, c = 's',
	})
end

-- q writing a draft of another mode leaves the editor in the mode the screen was in, and repaints it
-- then, not at the UI's next timed refresh.
T['T990 [char] (M15, DESK.md:1304) q writing a draft of another mode repaints once the mode is back'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.steps({ "<M-'><M-2>" })
	child.lua([[
		local loop = require('frogman.domains.ui.sm').loop
		local to = loop.to
		_G.REPAINTED = {}
		loop.to = function(self, ...)
			table.insert(_G.REPAINTED, require('frogman.domains.marks').data.mode)
			return to(self, ...)
		end
	]])
	-- q and the read in one call, so the UI's own timed refresh can't run between them
	local state = child.lua([[
		_G.FRG_TEST.press('q')
		return { mode = require('frogman.domains.marks').data.mode, last = _G.REPAINTED[#_G.REPAINTED] }
	]])
	child.settle(100)
	child.steps({ "<M-'><M-1>" })
	eq({ state = state, c = label('c') }, { state = { mode = 'tab', last = 'tab' }, c = 's' })
end

-- :e! throws the pop-up's edits away, the screen drawn again as its scope is and unmodified: q writes nothing.
T['T991 [char] (M15, DESK.md:1304) :e! throws the pop-up\'s edits away, and q writes nothing'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.cmd('edit!')
	child.settle(50)
	local thrown = popup()
	child.step('q')
	child.settle(100)
	eq({ modified = thrown.modified, gone = popup() == vim.NIL, b = label('b'), c = label('c') },
		{ modified = false, gone = true, b = 'a', c = false })
end

-- :wq with a draft held writes the screen's scope and leaves the pop-up open: Vim takes a write that
-- leaves the buffer modified as not done, so the draft stays for q.
T['T992 [char] (M15, DESK.md:1304) :wq with a draft held writes the screen\'s scope and leaves the pop-up open'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.steps({ "<M-'><M-2>" })
	child.type_keys('2G', 'cc', 'a -> d.txt', '<Esc>')
	child.cmd('silent! wq')
	child.settle(100)
	local after = { open = popup() ~= vim.NIL, mode = decoration()[1], d_in_tab = label('d') }
	child.step('q')
	child.settle(100)
	child.steps({ "<M-'><M-1>" })
	eq({ after = after, gone = popup() == vim.NIL, c = label('c') }, {
		after = { open = true, mode = 'marks · tab · draft: window', d_in_tab = 'a' }, gone = true, c = 's',
	})
end

-- The flag reset by hand over an alias holding two files: the screen is drawn again, holding nothing a draft
-- would keep, so a mode key switches, saying nothing.
T['T993 [char] (M15, DESK.md:1304) a mode key after :set nomodified switches over an alias holding two files, keeping no draft'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	local lines = popup().lines
	table.insert(lines, 3, 'a -> c.txt')
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, ...)', { lines })
	child.cmd('set nomodified')
	child.messages()
	child.steps({ "<M-'><M-2>" })
	eq({ said = said(), mode = decoration()[1], modified = popup().modified }, { said = {}, mode = 'marks · tab', modified = false })
end

-- :e! with a draft held draws the screen again as its scope is, the draft keeping the flag on: q writes the draft,
-- and the screen's scope keeps its marks.
T['T994 [char] (M15, DESK.md:1305) :e! with a draft held draws the screen again, the draft keeping the flag on: q writes the draft'] = function()
	child.steps({ ':e b', ADD .. 'a>', "<M-'><M-2>", ':e c', ADD .. 's>', "<M-'><M-1>", OPEN })
	child.type_keys('4G', 'cc', 'd -> b.txt', '<Esc>')
	child.steps({ "<M-'><M-2>" })
	local tab = popup().lines
	child.cmd('edit!')
	child.settle(100)
	local thrown = popup()
	child.step('q')
	child.settle(100)
	child.steps({ "<M-'><M-2>" })
	local c_in_tab = label('c')
	child.steps({ "<M-'><M-1>" })
	eq({ lines = thrown.lines, modified = thrown.modified, gone = popup() == vim.NIL, c_in_tab = c_in_tab, b = label('b') },
		{ lines = tab, modified = true, gone = true, c_in_tab = 's', b = 'a,d' })
end

-- An undo after :w takes back what was typed before it, the history kept through the write: the screen holds that
-- undo as an edit, and a later write writes the screen as it stands.
T['T995 [char] (M15, DESK.md:1305) an undo after :w takes back what was typed before it, and a later write writes the screen as it stands'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	local drawn = popup().lines
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.cmd('silent! write')
	child.settle(100)
	local written = label('c')
	child.type_keys('u', 'u')
	local undone = popup()
	child.type_keys('4G', 'cc', 'd -> b.txt', '<Esc>')
	child.cmd('silent! write')
	child.settle(100)
	eq({ written = written, lines = undone.lines, modified = undone.modified, c = label('c'), b = label('b') },
		{ written = 's', lines = drawn, modified = true, c = false, b = 'a,d' })
end

-- A pop-up drawn again for a mark added from the window it came from: the redraw is an undo step, so an undo takes
-- it back and a redo brings it again, and a later write keeps the mark.
T['T996 [char] (M15, DESK.md:1305) a redraw for a change made outside the pop-up is an undo step, and a later write keeps the mark'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	local before = popup().lines
	child.cmd('wincmd p')
	child.settle()
	child.steps({ ADD .. 'd>' })
	child.lua('vim.api.nvim_set_current_win(require("frogman.domains.marks.popup").window())')
	local shown = popup().lines
	child.type_keys('u')
	local undone = popup().lines
	child.type_keys('<C-r>')
	local redone = popup().lines
	child.type_keys('3G', 'cc', 's -> b.txt', '<Esc>')
	child.cmd('silent! write')
	child.settle(100)
	eq({ shown = shown[4], undone = undone, redone = redone, c = label('c') },
		{ shown = 'd -> c.txt', undone = before, redone = shown, c = 'd' })
end

-- An empty typed group above a marked one: saved, it comes back first, and the keys then do nothing.
T['T979 [char] (M15, DESK.md:1307) an empty typed group first is saved, comes back first, and the keys then do nothing'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e b', ADD .. 'a>', ':e e', OPEN })
	write_lines(vim.list_extend(vim.list_extend({ '❖ feature' }, rows({})), { '❖ main', 'a -> b.txt' }))
	child.cmd('close')
	child.settle()
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'b', 'e' }, 'e')
	eq(S2.load(child), { true })
	child.settle(300)
	local names = child.lua([[
		local s = require('frogman.domains.marks').data.scopes.window[vim.api.nvim_get_current_win()]
		return s and vim.tbl_map(function(g) return g.name end, s.groups) or {}
	]])
	child.steps({ JUMP .. 'a>' })
	eq({ names = names, shown = child.shown() }, { names = { 'feature', 'main' }, shown = 'e' })
end

-- A scope's groups, each with its marks by file letter, its held flag and whether its name is a load's.
local SCOPE_GROUPS = [[
	local kind, id = ...
	if kind == 'tab' then id = vim.api.nvim_get_current_tabpage() end
	local d = require('frogman.domains.marks').data
	local H = require('frogman.domains.history')
	local scope = d.scopes[kind][id]
	return vim.tbl_map(function(g)
		local marks = {}
		for alias, hid in pairs(g.marks) do
			local h = H.handles.get(H.handles.resolve(hid))
			marks[alias] = h and vim.fn.fnamemodify(H.get_filepath_from_hash(h.hash), ':t:r') or false
		end
		return { marks = marks, held = g.held == true, load = g.name:find(', loaded', 1, true) ~= nil }
	end, scope and scope.groups or {})
]]

-- A whole-editor load under the pop-up's unwritten edits for the session's own marks, the load bringing
-- marks other than the scope's: the write makes the lines the session's marks, and what the load brought
-- stays below, held over under the load's header. The scope's own marks are made in a fresh editor, where
-- the session isn't known yet, so they aren't written into its file as they change.
T['T976 [char] (M15, S1 Load, DESK.md:1325) a load under the pop-up\'s edits for the session\'s marks keeps both'] = function()
	local shared = S2.shared()
	S2.start(child, shared)
	child.steps({ ':e b', ':e c', "<M-'><M-3>", ':e b', ADD .. 'a>', ':e e' })
	eq(child.lua('return { pcall(require("frogman").save_session) }'), { true })
	S2.start(child, shared)
	Misc.restore(child, { 'b', 'c', 'e' }, 'e')
	child.steps({ "<M-'><M-3>", ':e c', ADD .. 's>', ':e e', OPEN })
	child.lua('vim.api.nvim_buf_set_lines(0, 3, 4, false, { "d -> d.txt" })')
	child.cmd('wincmd p')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").load_session) }'), { true })
	child.settle(300)
	child.lua('vim.api.nvim_set_current_win((require("frogman.domains.marks.popup").window() or -1))')
	child.cmd('silent! write')
	child.settle(100)
	eq(child.lua(SCOPE_GROUPS, { 'session', '' }), {
		{ marks = { s = 'c', d = 'd' }, held = false, load = false }, { marks = { a = 'b' }, held = true, load = true },
	})
end

-- The same for a plain tab's marks: the tab's own made in a fresh editor, as T976's are, so the load brings
-- the file's tab marks in their place.
T['T977 [char] (M15, S1 Load, DESK.md:1325) a load under the pop-up\'s edits for a tab\'s marks keeps both'] = function()
	local shared = S2.shared()
	S2.start(child, shared)
	child.steps({ ':e b', "<M-'><M-2>", ADD .. 'a>', ':e c', ':e e' })
	eq(child.lua('return { pcall(require("frogman").save_session) }'), { true })
	S2.start(child, shared)
	Misc.restore(child, { 'b', 'c', 'e' }, 'e')
	child.steps({ "<M-'><M-2>", ':e c', ADD .. 's>', ':e e', OPEN })
	child.lua('vim.api.nvim_buf_set_lines(0, 3, 4, false, { "d -> d.txt" })')
	child.cmd('wincmd p')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").load_session) }'), { true })
	child.settle(300)
	child.lua('vim.api.nvim_set_current_win((require("frogman.domains.marks.popup").window() or -1))')
	child.cmd('silent! write')
	child.settle(100)
	child.cmd('wincmd p')
	eq(child.lua(SCOPE_GROUPS, { 'tab' }), {
		{ marks = { s = 'c', d = 'd' }, held = false, load = false }, { marks = { a = 'b' }, held = true, load = true },
	})
end

-- The pop-up's lines are coloured in the trail's language: a header in the lists' colour, an alias in a
-- key's, dim when the config has none for it, the arrow dim, a file in the trail's name colour, a path to a
-- file the registry doesn't know yet too, and dim while closed or for a row naming no file.
T['T978 [char] (M15, DESK.md:1304) the pop-up\'s lines are coloured in the trail\'s language'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', ADD .. 's>', ':e e' })
	child.cmd('bdelete c.txt')
	child.settle()
	child.steps({ OPEN })
	-- typed: a path to a file the registry doesn't know yet, a name naming no file, an alias the config hasn't
	child.lua('vim.api.nvim_buf_set_lines(0, 3, 6, false, { "d -> d.txt", "f -> nothere.txt", "z -> e.txt" })')
	child.settle(50)
	local colours = child.lua([[
		local buf = (require('frogman.domains.marks.popup').buffer() or -1)
		local ns = vim.api.nvim_get_namespaces()['frogman_marks_popup']
		local out = {}
		for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
			local d = m[4]
			if d.hl_group and d.end_col then
				local line = vim.api.nvim_buf_get_lines(buf, m[2], m[2] + 1, false)[1]
				out[m[2] + 1 .. ':' .. line:sub(m[3] + 1, d.end_col)] = d.hl_group
			end
		end
		return out
	]])
	eq({ header = colours['1:❖ main'], alias = colours['2:a'], arrow = colours['2:->'], open = colours['2:b.txt'],
		closed = colours['3:c.txt'], typed = colours['4:d.txt'], nothing = colours['5:nothere.txt'], unassigned = colours['6:z'],
		empty_alias = colours['7:i'] }, {
		header = 'FrogmanTrailList', alias = 'FrogmanTrailKeyOn', arrow = 'FrogmanTrailDim', open = 'FrogmanTrailName',
		closed = 'FrogmanTrailDim', typed = 'FrogmanTrailName', nothing = 'FrogmanTrailDim', unassigned = 'FrogmanTrailKeyOff',
		empty_alias = 'FrogmanTrailKeyOn',
	})
end

-- A load that changes the tab's marks while the pop-up holds the tab's draft, the screen on the window's: q
-- writes the draft as the tab's marks, and what the load brought stays below, held over under the load's
-- header. The tab's own marks are made in a fresh editor, as T977's are.
T['T987 [char] (M15, S1 Load, DESK.md:1325, :1304) a load under a draft for the tab\'s marks keeps both'] = function()
	local shared = S2.shared()
	S2.start(child, shared)
	child.steps({ ':e b', "<M-'><M-2>", ADD .. 'a>', ':e c', ':e e' })
	eq(child.lua('return { pcall(require("frogman").save_session) }'), { true })
	S2.start(child, shared)
	Misc.restore(child, { 'b', 'c', 'e' }, 'e')
	child.steps({ "<M-'><M-2>", ':e c', ADD .. 's>', ':e e', OPEN })
	child.lua('vim.api.nvim_buf_set_lines(0, 3, 4, false, { "d -> d.txt" })')
	child.steps({ "<M-'><M-1>" })
	child.cmd('wincmd p')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").load_session) }'), { true })
	child.settle(300)
	child.lua('vim.api.nvim_set_current_win((require("frogman.domains.marks.popup").window() or -1))')
	child.step('q')
	child.settle(100)
	eq({ gone = popup() == vim.NIL, groups = child.lua(SCOPE_GROUPS, { 'tab' }) }, {
		gone = true,
		groups = { { marks = { s = 'c', d = 'd' }, held = false, load = false }, { marks = { a = 'b' }, held = true, load = true } },
	})
end

-- The held-over groups and snapshots in a session's scope that hold c, and what the window holds of it.
local C_HELD = [[
	local session_id, win = ...
	local H = require('frogman.domains.history')
	local Sn = require('frogman.domains.snapshots').routines
	local c = H.routines.get_filehash(_G.FRG_TEST.root .. '/c.txt')
	local function is_c(id)
		local h = id and H.handles.get(H.handles.resolve(id))
		return h ~= nil and h.hash == c
	end
	local held, snaps = 0, 0
	for _, g in ipairs((require('frogman.domains.marks').data.scopes.session[session_id] or { groups = {} }).groups) do
		if g.held and is_c(g.marks.a) then held = held + 1 end
	end
	for _, snap in ipairs(Sn.held_in(session_id)) do
		if is_c(snap.current) then snaps = snaps + 1 end
	end
	local own = 0
	for _, g in ipairs((require('frogman.domains.marks').data.scopes.window[win] or { groups = {} }).groups) do
		if is_c(g.marks.a) then own = own + 1 end
	end
	return { held = held, held_snapshots = snaps, window = own, window_snapshots = #Sn.of_window(win) }
]]

-- P1: a tab session loaded twice, first into a tab its entries don't match, then into one they do: the
-- window takes its mark and its snapshot back, and the copies the first load held over go.
T['T997 [char] (M15, M16, S1 Load, DESK.md:1320) a tab session loaded twice, first where no entry matches, gives the window its mark and snapshot once'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>', '<M-;><M-s>', ':e d' })
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local first = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	eq(S2.load_tab_session(child, 't'), { true })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	local pool = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	eq({ same = pool == first, got = child.lua(C_HELD, { pool, win }) },
		{ same = true, got = { held = 0, held_snapshots = 0, window = 1, window_snapshots = 1 } })
end

-- P2: a plain tab closed after the whole editor's save, its window's mark and snapshot held over and written
-- with the records; a fresh editor restores both tabs and loads: the window takes them back from its entry,
-- and the copies the close held over go.
T['T998 [char] (M15, M16, S1 Load, DESK.md:1320) a plain tab restored before any save takes its window\'s mark and snapshot back once'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e x' })
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>', '<M-;><M-s>' })
	eq(S2.save(child), { true })
	child.cmd('tabclose')
	child.settle(1500) -- held over, and the records written within the second
	S2.start(child, s)
	S2.restore_tabs(child, { { files = { 'x' }, shown = 'x' }, { files = { 'c' }, shown = 'c' } })
	eq(S2.load(child), { true })
	child.settle(300)
	child.cmd('tabnext 2')
	child.settle()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	eq(child.lua(C_HELD, { '', win }), { held = 0, held_snapshots = 0, window = 1, window_snapshots = 1 })
end

-- A copy the first load held over that you edited stays at the second load, beside the window's own mark.
T['T999 [char] (M15, S1 Load, DESK.md:1320) a held-over copy you edited stays when the window takes its entry back'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>', ':e d' })
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	-- the held copy edited: e marked under s beside a -> c
	local first = child.lua([[
		local pool = require('frogman.domains.history').data.tab_pools[vim.api.nvim_get_current_tabpage()]
		local H = require('frogman.domains.history')
		local e = H.get_handle_from_filepath(_G.FRG_TEST.root .. '/x.txt')
		for _, g in ipairs(require('frogman.domains.marks').data.scopes.session[pool].groups) do
			if g.held then g.marks.s = e end
		end
		return pool
	]])
	eq(S2.load_tab_session(child, 't'), { true })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	eq(child.lua(C_HELD, { first, win }), { held = 1, held_snapshots = 0, window = 1, window_snapshots = 0 })
end

-- A copy the first load held over that you moved up first is a group of your own, as the pop-up's write
-- leaves a held-over group it finds first, so it stays at the second load, beside the window's own mark.
T['T1000 [char] (M15, S1 Load, DESK.md:1320, :1318) a held-over copy you moved up first stays when the window takes its entry back'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>', ':e d' })
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	-- the copy first, as the pop-up writes it there: held over no more (marks/popup.lua, held only below the first)
	local first = child.lua([[
		local pool = require('frogman.domains.history').data.tab_pools[vim.api.nvim_get_current_tabpage()]
		for _, g in ipairs(require('frogman.domains.marks').data.scopes.session[pool].groups) do g.held = nil end
		return pool
	]])
	eq(S2.load_tab_session(child, 't'), { true })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	local own = child.lua([[
		local H = require('frogman.domains.history')
		local c = H.routines.get_filehash(_G.FRG_TEST.root .. '/c.txt')
		local n = 0
		for _, g in ipairs(require('frogman.domains.marks').data.scopes.session[...].groups) do
			local h = not g.held and g.marks.a and H.handles.get(H.handles.resolve(g.marks.a))
			if h and h.hash == c then n = n + 1 end
		end
		return n
	]], { first })
	eq({ kept = own, got = child.lua(C_HELD, { first, win }) },
		{ kept = 1, got = { held = 0, held_snapshots = 0, window = 1, window_snapshots = 0 } })
end

-- A group of your own typed below a copy the first load held over doesn't keep it: the copy goes at the
-- second load all the same.
T['T1001 [char] (M15, S1 Load, DESK.md:1320) a group typed below a held-over copy doesn\'t keep it when the window takes its entry back'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>', ':e d' })
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local first = child.lua([[
		local pool = require('frogman.domains.history').data.tab_pools[vim.api.nvim_get_current_tabpage()]
		local x = require('frogman.domains.history').get_handle_from_filepath(_G.FRG_TEST.root .. '/x.txt')
		table.insert(require('frogman.domains.marks').data.scopes.session[pool].groups, { name = 'feature', marks = { s = x } })
		return pool
	]])
	eq(S2.load_tab_session(child, 't'), { true })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	eq(child.lua(C_HELD, { first, win }), { held = 0, held_snapshots = 0, window = 1, window_snapshots = 0 })
end

-- Two windows marking c under a, one entry no window takes and one a window takes, the untaken first:
-- what this load holds over of the untaken entry stays, though the other window brings the same marks back.
T['T1002 [char] (M15, S1 Load, DESK.md:1320) what a load holds over of an entry no window takes stays, though another window brings the same marks back'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e c', ADD .. 'a>', ':e d' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>' }) -- the split, first in the saved order, on c
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'c', 'd' }, 'd')
	eq(S2.load(child), { true })
	child.settle(300)
	local win = child.lua('return vim.api.nvim_get_current_win()')
	eq(child.lua(C_HELD, { '', win }), { held = 1, held_snapshots = 0, window = 1, window_snapshots = 0 })
end

-- The names of the held-over groups in a session's scope.
local HELD_NAMES = [[
	local out = {}
	for _, g in ipairs((require('frogman.domains.marks').data.scopes.session[...] or { groups = {} }).groups) do
		if g.held then table.insert(out, g.name) end
	end
	return out
]]

-- A plain tab's own tab marks held over as a tab session loads into it name the load, not what the tab
-- showed.
T['T1005 [char] (M15, S1 Load, DESK.md:1318) a plain tab\'s marks held over as a tab session loads into it name the load'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e b', "<M-'><M-2>", ADD .. 'a>', ':e e', "<M-'><M-1>" })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local pool = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local names = child.lua(HELD_NAMES, { pool })
	eq({ n = #names, load = (names[1] or ''):find('^held over · t, loaded into tab 1 · ') ~= nil,
		tab = (names[1] or ''):find('tab on ', 1, true) ~= nil }, { n = 1, load = true, tab = false })
end

-- A window entry no window takes, holding one marked group and a group typed in with none: both held over
-- at the load, each under the load's header with its group's name.
T['T1006 [char] (M15, S1 Load, DESK.md:1318, :1313) an entry with one marked group and an empty one has both held over, each named'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e c', ADD .. 'a>', ':e d', OPEN })
	write_lines(vim.list_extend({ '❖ main', 'a -> c.txt', '❖ feature' }, rows({})))
	child.cmd('close')
	child.settle()
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'x' }, 'x')
	eq(S2.load(child), { true })
	child.settle(300)
	local names = child.lua(HELD_NAMES, { '' })
	table.sort(names)
	eq({ n = #names, feature = (names[1] or ''):find(', loaded, feature · ', 1, true) ~= nil,
		main = (names[2] or ''):find(', loaded, main · ', 1, true) ~= nil }, { n = 2, feature = true, main = true })
end

-- A window with two marked groups closed while you work leaves one held-over group for each, its group's
-- name after what the window showed.
T['T1007 [char] (M15, DESK.md:1318) a window closed with two marked groups leaves one held-over group per group, each named'] = function()
	child.steps({ ':e a' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>', ':e d', OPEN })
	write_lines(vim.list_extend({ '❖ main', 'a -> c.txt', '❖ feature', 's -> e.txt' }, {}))
	child.cmd('close')
	child.settle()
	child.cmd('close')
	child.settle(300)
	local names = child.lua(HELD_NAMES, { '' })
	table.sort(names)
	eq({ n = #names, main = (names[2] or ''):find('^held over · window on d%.txt, main · ') ~= nil,
		feature = (names[1] or ''):find('^held over · window on d%.txt, feature · ') ~= nil }, { n = 2, main = true, feature = true })
end

-- A plain tab's own tab marks held over as the hint load starts a tab session fresh there name the load too,
-- the session having no file yet.
T['T1008 [char] (M15, S1 Load, DESK.md:1318) a plain tab\'s marks held over as the hint load starts a tab session fresh there name the load'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e b', "<M-'><M-2>", ADD .. 'a>', ':e e', "<M-'><M-1>" })
	eq(child.lua('return { pcall(require("frogman").load_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local pool = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local names = child.lua(HELD_NAMES, { pool })
	eq({ n = #names, load = (names[1] or ''):find('^held over · u, loaded into tab 1 · ') ~= nil,
		tab = (names[1] or ''):find('tab on ', 1, true) ~= nil }, { n = 1, load = true, tab = false })
end

-- What each held-over group and snapshot in a session's scope was, its header without the time.
local HELD_WHAT = [[
	local session_id = ...
	local function what(header)
		local s = header:gsub('^held over · ', '')
		s = s:gsub(' · %d%d%-%d%d %d%d:%d%d.*$', '')
		return s
	end
	local out = { marks = {}, snapshots = {} }
	for _, g in ipairs((require('frogman.domains.marks').data.scopes.session[session_id] or { groups = {} }).groups) do
		if g.held then table.insert(out.marks, what(g.name)) end
	end
	for _, snap in ipairs(require('frogman.domains.snapshots').routines.held_in(session_id)) do
		table.insert(out.snapshots, what(snap.held))
	end
	return out
]]

-- Close a window by noautocmd, then run a cleanup pass, as a window gone without its events meets one.
local function gone(win)
	child.lua('vim.cmd("noautocmd call nvim_win_close(" .. ... .. ", v:true)")', { win })
	child.lua('require("frogman.domains.history").routines.cleanup_system()')
	child.settle(100)
end

-- A window closed without its events: its marks and its snapshot held over under what it showed when frogman
-- last saw it, its buffer changed since the mark and the snapshot were made.
T['T1009 [char] (M15, M16, DESK.md:1313, :1318, :2065) a window closed without its events is headed by what it showed last, marks and snapshots alike'] = function()
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>', '<M-;><M-s>', ':e d' })
	child.cmd('wincmd p')
	child.settle()
	gone(split)
	eq(child.lua(HELD_WHAT, { '' }), { marks = { 'window on d.txt' }, snapshots = { 'window on d.txt' } })
end

-- A plain tab closed without its events: its tab marks held over under what its window showed when frogman
-- last saw it.
T['T1010 [char] (M15, DESK.md:1318) a tab closed without its events is headed by what it showed'] = function()
	child.steps({ ':e a' })
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', "<M-'><M-2>", ADD .. 'a>', ':e d', "<M-'><M-1>" })
	child.cmd('tabprevious')
	child.settle()
	child.lua('vim.cmd("noautocmd tabclose 2")')
	child.lua('require("frogman.domains.history").routines.cleanup_system()')
	child.settle(100)
	eq(child.lua(HELD_WHAT, { '' }), { marks = { 'tab on d.txt' }, snapshots = {} })
end

-- A split marked, and given a snapshot, before its tab starts the tab session u by the hint load, and never
-- entered after; u has no file, so the split has no saved entry: closed without its events, it's held over in
-- u's scope, where its tab went.
T['T1011 [char] (M15, M16, DESK.md:1313, :2065) a window last seen before its tab started a tab session is held over in that session\'s scope'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e x' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>', '<M-;><M-s>' })
	child.cmd('wincmd p')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").load_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local u = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	gone(split)
	eq({ u = child.lua(HELD_WHAT, { u }), editor = child.lua(HELD_WHAT, { '' }) },
		{ u = { marks = { 'window on c.txt' }, snapshots = { 'window on c.txt' } }, editor = { marks = {}, snapshots = {} } })
end

-- A split made in t's tab, marked and given a snapshot, then t loaded into a new tab, so the first tab keeps a
-- detached list; the split, never entered after and with no saved entry, closed without its events: held over
-- in the detached list's scope, where its tab went, not t's.
T['T1012 [char] (M15, M16, DESK.md:1313, :2065) a window last seen before its tab session moved to another tab is held over in the detached list\'s scope'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local first = child.lua('return vim.api.nvim_get_current_tabpage()')
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e e', ADD .. 'a>', '<M-;><M-s>' })
	child.cmd('wincmd p')
	child.settle()
	eq(S2.load_tab_session(child, 't'), { true })
	local detached = child.lua('return require("frogman.domains.history").data.tab_pools[...]', { first })
	local t = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	gone(split)
	eq({ apart = detached ~= t, detached = child.lua(HELD_WHAT, { detached }), t = child.lua(HELD_WHAT, { t }) },
		{ apart = true, detached = { marks = { 'window on e.txt' }, snapshots = { 'window on e.txt' } }, t = { marks = {}, snapshots = {} } })
end

-- A tab session's mark on a No Name text held over at one load, its entry taken back at the next: the copy goes,
-- known by the text, not by the hash the file had for it.
T['T1224 [char] (M15, DESK.md:1320) a copy of a No Name text\'s mark goes when its window takes the entry back, the text reopened under a new hash'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.cmd('tabnew')
	child.steps({ ':e c' })
	S2.noname(child, { 'draft' })
	child.steps({ ADD .. 'a>', ':e d' })
	eq(save_t(), { true })
	S2.start(child, s)
	child.steps({ ':e x' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local t = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local held_before = #child.lua(HELD_WHAT, { t }).marks
	eq(S2.load_tab_session(child, 't'), { true }) -- a tab whose window shows d takes the entry back
	eq({ before = held_before, after = #child.lua(HELD_WHAT, { t }).marks,
		own = child.lua([[
			local g = (require('frogman.domains.marks').data.scopes.window[vim.api.nvim_get_current_win()] or { groups = {} }).groups[1]
			local h = g and require('frogman.domains.marks').routines.handle_of(g, 'a')
			local path = h and require('frogman.domains.history').get_filepath_from_handle(h.id)
			return path and path:match('^NONAME_') ~= nil
		]]) },
		{ before = 1, after = 0, own = true })
end

-- T883's route, the copies the first load held over moved, in the whole editor's file, from its own scope into
-- the detached list's, as a window closed in the list's tab holds them: they go when the list's tab comes back.
T['T1226 [char] (M15, M16, DESK.md:1320) a copy held in a detached list\'s own scope goes when the list\'s tab comes back with the window taking its entry'] = function()
	local s = S2.shared()
	tab_session(s)
	eq(S2.save(child), { true })
	child.steps({ ':e c', ADD .. 'a>', '<M-;><M-s>', ':e d' }) -- a window mark and a snapshot in t's tab
	eq(S2.load_tab_session(child, 't'), { true }) -- that tab keeps t_DETACHED
	eq(S2.save(child), { true })
	S2.start(child, s)
	S2.restore_tabs(child, { { files = { 'x', 't' }, shown = 't' } })
	eq(S2.load(child), { true }) -- the list's tab stays away: its window's marks and snapshot held over
	child.settle(300)
	S2.start(child, s) -- the quit writes the records, no save
	-- sealed again by hand: the held-over group and snapshot moved into the detached list's own scope
	child.lua([[
		local crypto = require('frogman.domains.storage.crypto')
		local dir = vim.fn.getcwd(-1, -1)
		local path = require('frogman.configs').session_dir .. vim.fn.sha256(dir)
		local fh = assert(io.open(path, 'rb')); local bytes = fh:read('*a'); fh:close()
		local salt = bytes:sub(5, 4 + crypto.salt_length)
		local data = require('frogman.domains.storage.routines').read_session(dir, nil)
		local list = data.detached[1]
		list.marks, list.snapshots = list.marks or {}, list.snapshots or {}
		local kept = {}
		for _, g in ipairs(data.marks or {}) do
			table.insert(g.held and list.marks or kept, g)
		end
		data.marks = kept
		vim.list_extend(list.snapshots, data.snapshots or {})
		data.snapshots = {}
		local header = "CDV1" .. salt
		local out = header .. crypto.seal(crypto.derive_key(dir, salt), vim.json.encode(data), header)
		fh = assert(io.open(path, 'wb')); fh:write(out); fh:close()
	]])
	S2.restore_tabs(child, { { files = { 'x', 't' }, shown = 't' }, { files = { 'c', 'd' }, shown = 'd' },
		{ files = { 'c', 'd' }, shown = 'd' } })
	eq(S2.load(child), { true })
	child.settle(300)
	child.cmd('tabnext 2')
	child.settle()
	local list = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local own = child.lua('return #require("frogman.domains.snapshots").routines.of_window(vim.api.nvim_get_current_win())')
	local left = child.lua(HELD_WHAT, { list })
	eq({ detached = list:match('DETACHED') ~= nil, own = own, left = { marks = #left.marks, snapshots = #left.snapshots } },
		{ detached = true, own = 1, left = { marks = 0, snapshots = 0 } })
end

-- A tab whose window is never entered with its events, its tab marks restored by a whole-editor load, then
-- closed without its events: its marks go onto its tab entry, and a save that writes the tabs anew without it
-- holds them over, headed by what it showed, noted as its marks came back.
T['T1013 [char] (M15, S1 Load, DESK.md:1318) a tab whose marks a load restored, closed without its events, is headed by what it showed'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', "<M-'><M-2>", ADD .. 'a>', "<M-'><M-1>" })
	child.cmd('tabprevious')
	child.settle()
	eq(S2.save(child), { true })
	S2.start(child, s)
	S2.restore_tabs(child, { { files = { 'a' }, shown = 'a' }, { files = { 'c' }, shown = 'c' } })
	eq(S2.load(child), { true })
	child.settle(300)
	child.lua('vim.cmd("noautocmd tabclose 2")')
	child.lua('require("frogman.domains.history").routines.cleanup_system()')
	child.settle(100)
	local at_close = child.lua(HELD_WHAT, { '' })
	eq(S2.save(child), { true })
	eq({ at_close = at_close, saved = child.lua(HELD_WHAT, { '' }) },
		{ at_close = { marks = {}, snapshots = {} }, saved = { marks = { 'tab on c.txt' }, snapshots = {} } })
end

-- A note whose name can't be looked up keeps what was noted before, and fails neither the event that takes it
-- nor a save: the lookup made to raise, then `:e d` in a split last noted on c, and the tab saved as t, whose
-- join notes every window of the tab.
T['T1014 [char] (M15, DESK.md:1313, :1318) a note whose name can\'t be looked up fails no event or save, and keeps what was seen before'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>' })
	child.lua([[
		local R = require('frogman.domains.marks').routines
		_G.FRG_T1014 = R.name_of
		R.name_of = function() error('T1014: no name') end
		vim.v.errmsg = ''
	]])
	child.steps({ ':e d' })
	local saved = child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }')
	local during = child.lua('return { errmsg = vim.v.errmsg:find("T1014", 1, true) ~= nil, seen = require("frogman.held").last_seen_as("window", ...) }', { split })
	child.lua('require("frogman.domains.marks").routines.name_of = _G.FRG_T1014')
	child.steps({ ':e e' })
	eq({ saved = saved, during = during, after = child.lua('return require("frogman.held").last_seen_as("window", ...)', { split }) },
		{ saved = { true }, during = { errmsg = false, seen = 'window on c.txt' }, after = 'window on e.txt' })
end

-- A window closed without its events is named as a close names it, by its file's unique name: a split on
-- c, then on sub/c.txt, which frogman takes in only once its arrival settles, after the note its BufEnter
-- took; with c.txt open too, a close would name it sub/c.txt.
T['T1015 [char] (M15, DESK.md:1318) a window closed without its events is named by its file\'s unique name, as a close names it'] = function()
	child.lua([[
		vim.fn.mkdir(_G.FRG_TEST.root .. '/sub', 'p')
		vim.fn.writefile({ 'sub c' }, _G.FRG_TEST.root .. '/sub/c.txt')
	]])
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>', ':e sub/c.txt' })
	child.cmd('wincmd p')
	child.settle()
	gone(split)
	eq(child.lua(HELD_WHAT, { '' }), { marks = { 'window on sub/c.txt' }, snapshots = {} })
end

-- A window a load gives its marks, never entered with its events, closed without them: its marks go onto its
-- entry, and a save that writes the windows anew without it holds them over, headed by what it showed, noted
-- as its marks came back.
T['T1016 [char] (M15, S1 Load, DESK.md:1313, :1318) a window noted as a load gives it its marks is headed by what it showed'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>' })
	child.cmd('wincmd p')
	child.settle()
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'c' }, 'a')
	local split = child.lua([[
		vim.cmd('noautocmd vsplit')
		vim.cmd('noautocmd edit c.txt')
		return vim.api.nvim_get_current_win()
	]])
	eq(S2.load(child), { true })
	child.settle(300)
	gone(split)
	local at_close = child.lua(HELD_WHAT, { '' })
	eq(S2.save(child), { true })
	eq({ at_close = at_close, saved = child.lua(HELD_WHAT, { '' }) },
		{ at_close = { marks = {}, snapshots = {} }, saved = { marks = { 'window on c.txt' }, snapshots = {} } })
end

-- The same for a window a load gives its snapshot, and no marks.
T['T1017 [char] (M16, S1 Load, DESK.md:2065, :1318) a window noted as a load gives it its snapshot is headed by what it showed'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c', '<M-;><M-s>' })
	child.cmd('wincmd p')
	child.settle()
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'c' }, 'a')
	local split = child.lua([[
		vim.cmd('noautocmd vsplit')
		vim.cmd('noautocmd edit c.txt')
		return vim.api.nvim_get_current_win()
	]])
	eq(S2.load(child), { true })
	child.settle(300)
	gone(split)
	local at_close = child.lua(HELD_WHAT, { '' })
	eq(S2.save(child), { true })
	eq({ at_close = at_close, saved = child.lua(HELD_WHAT, { '' }) },
		{ at_close = { marks = {}, snapshots = {} }, saved = { marks = {}, snapshots = { 'window on c.txt' } } })
end

-- A session file's own marks and held-over snapshots, by file and header: { marks = { "a=c" ... }, held = { ... } }
local FILE_MARKS = [[
	local name = ...
	local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), name) or {}
	local out = { marks = {}, held = {}, snapshots = #(saved.snapshots or {}) }
	for _, g in ipairs(saved.marks or {}) do
		for alias, h in pairs(g.marks or {}) do
			table.insert(g.held and out.held or out.marks, alias .. '=' .. vim.fn.fnamemodify((saved.paths or {})[h] or h, ':t:r'))
		end
	end
	table.sort(out.marks)
	table.sort(out.held)
	return out
]]

-- A session's scope in memory, the same way: its marks, its held-over groups' marks, and how many held-over
-- snapshots it has with the ids they carry.
local SCOPE_MARKS = [[
	local id = ...
	local H = require('frogman.domains.history')
	local out = { marks = {}, held = {}, snapshots = {} }
	for _, g in ipairs((require('frogman.domains.marks').data.scopes.session[id] or { groups = {} }).groups) do
		for alias, handle in pairs(g.marks) do
			local path = H.get_filepath_from_handle(H.handles.resolve(handle))
			table.insert(g.held and out.held or out.marks, alias .. '=' .. vim.fn.fnamemodify(path or '?', ':t:r'))
		end
	end
	for _, snap in ipairs(require('frogman.domains.snapshots').routines.held_in(id)) do
		table.insert(out.snapshots, snap.id)
	end
	table.sort(out.marks)
	table.sort(out.held)
	return out
]]

-- P3: a tab session saved as another carries a copy of its session's marks; the old keeps its own, in its file.
T['T1018 [char] (M15, S1 Save, DESK.md:1311, repro P3) a tab session saved as another carries a copy of its session\'s marks'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	child.steps({ "<M-'><M-3>", ':e c', ADD .. 'a>', "<M-'><M-1>" })
	child.settle(1200) -- t's records written, its mark in t's file
	eq(child.lua('return { pcall(require("frogman").save_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local u = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	eq({ u = child.lua(SCOPE_MARKS, { u }), u_file = child.lua(FILE_MARKS, { 'u' }).marks, t_file = child.lua(FILE_MARKS, { 't' }).marks },
		{ u = { marks = { 'a=c' }, held = {}, snapshots = {} }, u_file = { 'a=c' }, t_file = { 'a=c' } })
end

-- A tab session saved as another carries a copy of its held-over groups and held-over snapshots too: a split in
-- t's tab, with no saved entry, marking c under `a` and with a snapshot, closed, so both are held over in t's
-- scope; the tab saved as u: u's scope holds the held-over group and a copy of the snapshot, under another id,
-- and t's file keeps its own.
T['T1019 [char] (M15, M16, S1 Save, DESK.md:1311, :2065) a tab session saved as another carries a copy of its held-over groups and snapshots'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local t = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>', '<M-;><M-s>' })
	child.cmd('close')
	child.settle(1200) -- held over in t's scope, and written into t's file
	local before = child.lua(SCOPE_MARKS, { t })
	eq(child.lua('return { pcall(require("frogman").save_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local u = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local got = child.lua(SCOPE_MARKS, { u })
	local t_file = child.lua(FILE_MARKS, { 't' })
	local u_file = child.lua(FILE_MARKS, { 'u' })
	eq({ before = { held = before.held, snapshots = #before.snapshots }, held = got.held, snapshots = #got.snapshots,
		new_id = got.snapshots[1] ~= before.snapshots[1], t_file = { held = t_file.held, snapshots = t_file.snapshots },
		u_file = { held = u_file.held, snapshots = u_file.snapshots } },
		{ before = { held = { 'a=c' }, snapshots = 1 }, held = { 'a=c' }, snapshots = 1, new_id = true, t_file = { held = { 'a=c' }, snapshots = 1 },
			u_file = { held = { 'a=c' }, snapshots = 1 } })
end

-- A session's groups in order, each as its name and its marks: { "main a=x", ... }.
local GROUPS_IN_ORDER = [[
	local id = ...
	local H = require('frogman.domains.history')
	local out = {}
	for _, g in ipairs((require('frogman.domains.marks').data.scopes.session[id] or { groups = {} }).groups) do
		local marks = {}
		for alias, handle in pairs(g.marks) do
			local path = H.get_filepath_from_handle(H.handles.resolve(handle))
			table.insert(marks, alias .. '=' .. vim.fn.fnamemodify(path or '?', ':t:r'))
		end
		table.sort(marks)
		table.insert(out, (g.held and 'held ' or '') .. g.name .. ' ' .. table.concat(marks, ','))
	end
	return out
]]

-- A tab session saved as a session that's in memory with marks of its own: what it carries goes below that
-- session's own, as it is, so its first group still drives the keys; and the tab that held it keeps its own.
T['T1020 [char] (M15, S1 Save, DESK.md:1311) a tab session saved as a session with marks of its own carries its marks below them'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	child.steps({ "<M-'><M-3>", ':e c', ADD .. 'a>', "<M-'><M-1>" })
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e e' })
	eq(child.lua('return { pcall(require("frogman").save_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	child.steps({ "<M-'><M-3>", ':e x', ADD .. 'a>', "<M-'><M-1>" })
	child.cmd('tabprevious')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").save_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local u = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local pushed = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_list_tabpages()[2]]')
	eq({ u = child.lua(GROUPS_IN_ORDER, { u }), pushed = child.lua(GROUPS_IN_ORDER, { pushed }) },
		{ u = { 'main a=x', 'main a=c' }, pushed = { 'main a=x' } })
end

-- A detached list's tab saved as another session carries its copy of the marks, as its closed files are.
T['T1021 [char] (M15, S1 Save, DESK.md:1311) a detached list\'s tab saved as another session carries its copy of the marks'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	child.steps({ "<M-'><M-3>", ':e c', ADD .. 'a>', "<M-'><M-1>" })
	eq(S2.load_tab_session(child, 't'), { true })
	child.cmd('tabnext 1')
	child.settle()
	local detached = child.lua('return require("frogman.domains.history").data.pools[require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]].detached == true')
	eq(child.lua('return { pcall(require("frogman").save_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local u = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local kept = child.lua([[
		for id, pool in pairs(require('frogman.domains.history').data.pools) do
			if pool.detached then return id end
		end
	]])
	-- the old list, its tab taken with nothing in its closed list, goes as an emptied one does: its copy held over
	-- in the whole editor's scope under its name
	eq({ detached = detached, u = child.lua(GROUPS_IN_ORDER, { u }), kept = kept ~= nil and kept ~= vim.NIL, editor = editor_held().memory },
		{ detached = true, u = { 'main a=c' }, kept = false, editor = { 't_DETACHED a=c' } })
end

-- A plain tab saved as a tab session carries none of the whole editor's marks, and a tab session's tab saved
-- under its own name again carries nothing twice: the carry is a tab session's, saved as another.
T['T1022 [char] (M15, S1 Save, DESK.md:1311) only a tab session saved as another carries: a plain tab saved as one carries none of the whole editor\'s marks, and a save under its own name carries nothing twice'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', "<M-'><M-3>", ADD .. 'a>', "<M-'><M-1>" })
	eq(child.lua('return { pcall(require("frogman").save_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local u = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	child.steps({ "<M-'><M-3>", ':e c', ADD .. 's>', "<M-'><M-1>" })
	eq(child.lua('return { pcall(require("frogman").save_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	eq({ editor = child.lua(GROUPS_IN_ORDER, { '' }), u = child.lua(GROUPS_IN_ORDER, { u }) },
		{ editor = { 'main a=a' }, u = { 'main s=c' } })
end

-- A list of group lines with the times taken out of held-over headers.
local function untimed(list)
	return vim.tbl_map(function(line) return (line:gsub(' · %d%d%-%d%d %d%d:%d%d', '')) end, list)
end

-- A window's groups, each by its name and its marks by file letter.
local WIN_GROUPS = [[
	local win = ...
	local H = require('frogman.domains.history')
	local s = require('frogman.domains.marks').data.scopes.window[win]
	return vim.tbl_map(function(g)
		local marks = {}
		for alias, hid in pairs(g.marks) do
			local h = H.handles.get(H.handles.resolve(hid))
			marks[alias] = h and vim.fn.fnamemodify(H.get_filepath_from_hash(h.hash), ':t:r') or false
		end
		return { name = g.name, held = g.held == true, marks = marks }
	end, s and s.groups or {})
]]

-- A held-over group whose rows are all emptied, its header kept, is saved and loaded back empty, and so is
-- the empty default group the hold-over made ahead of it.
T['T1023 [char] (M15, DESK.md:1318, :1301) a held-over group emptied in the pop-up is saved and loaded back'] = function()
	local s = S2.shared()
	S2.start(child, s)
	local lines, held = held_session_popup()
	local name = lines[held]:gsub('^❖ ', '')
	lines[held + 1] = 'a -> '
	write_lines(lines)
	child.cmd('close')
	child.settle()
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a' }, 'a')
	eq(S2.load(child), { true })
	child.settle(300)
	eq(child.lua(GROUPS_IN_ORDER, { '' }), { 'main ', 'held ' .. name .. ' ' })
end

-- An empty default group beside a typed one is saved, and comes back first.
T['T1024 [char] (M15, DESK.md:1301, :1307) an empty default group beside a typed one is saved and comes back first'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e b', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({}))
	vim.list_extend(lines, vim.list_extend({ '❖ dev' }, rows({ a = 'b.txt' })))
	write_lines(lines)
	child.cmd('close')
	child.settle()
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	eq(child.lua(WIN_GROUPS, { child.lua('return vim.api.nvim_get_current_win()') }),
		{ { name = 'main', held = false, marks = {} }, { name = 'dev', held = false, marks = { a = 'b' } } })
end

-- A window closed with a marked group and an empty typed one leaves both held over, each named.
T['T1025 [char] (M15, DESK.md:1313, :1318) a window closed with a marked group and an empty typed one leaves both held over, each named'] = function()
	child.steps({ ':e a' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>', ':e d', OPEN })
	write_lines(vim.list_extend({ '❖ main', 'a -> c.txt', '❖ todo' }, rows({})))
	child.cmd('close')
	child.settle()
	child.cmd('close')
	child.settle(300)
	eq(untimed(child.lua(GROUPS_IN_ORDER, { '' })),
		{ 'main ', 'held held over · window on d.txt, main a=c', 'held held over · window on d.txt, todo ' })
end

-- A window whose only group is a typed one with no marks holds it over, empty, as it closes.
T['T1026 [char] (M15, DESK.md:1313) a window closed with only an empty typed group holds it over, empty'] = function()
	child.steps({ ':e a' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e d', OPEN })
	local lines = popup().lines
	lines[1] = '❖ todo'
	write_lines(lines)
	child.cmd('close')
	child.settle()
	child.cmd('close')
	child.settle(300)
	eq(untimed(child.lua(GROUPS_IN_ORDER, { '' })), { 'main ', 'held held over · window on d.txt ' })
end

-- The same window closed without its events: the cleanup pass holds its empty group over too.
T['T1027 [char] (M15, DESK.md:1313) a window closed without its events holds its empty typed group over'] = function()
	child.steps({ ':e a' })
	child.cmd('split')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e d', OPEN })
	local lines = popup().lines
	lines[1] = '❖ todo'
	write_lines(lines)
	child.cmd('close')
	child.settle()
	child.cmd('wincmd p')
	child.settle()
	gone(split)
	eq(untimed(child.lua(GROUPS_IN_ORDER, { '' })), { 'main ', 'held held over · window on d.txt ' })
end

-- A plain tab whose only tab group is a typed one with no marks holds it over, empty, as it closes.
T['T1028 [char] (M15, DESK.md:1313) a plain tab closed with only an empty typed group holds it over, empty'] = function()
	child.steps({ ':e a' })
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e d', "<M-'><M-2>", OPEN })
	local lines = popup().lines
	lines[1] = '❖ todo'
	write_lines(lines)
	child.cmd('close')
	child.settle()
	child.steps({ "<M-'><M-1>" })
	child.cmd('tabclose')
	child.settle(300)
	eq(untimed(child.lua(GROUPS_IN_ORDER, { '' })), { 'main ', 'held held over · tab on d.txt ' })
end

-- A window entry no window takes, holding only a typed group with no marks: held over at the load, empty, and
-- the entry gives it up at the records write, as one with marks does.
T['T1029 [char] (M15, S1 Load, DESK.md:1313, :1318) an entry no window takes holds its empty typed group over, and gives it up in the file'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e d', OPEN })
	local lines = popup().lines
	lines[1] = '❖ todo'
	write_lines(lines)
	child.cmd('close')
	child.settle()
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'x' }, 'x')
	eq(S2.load(child), { true })
	child.settle(300)
	local held = untimed(child.lua(GROUPS_IN_ORDER, { '' }))
	S2.start(child, s) -- the quit writes the records
	local carrying = child.lua([[
		local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), nil) or {}
		local n = 0
		for _, entry in ipairs(saved.windows or {}) do
			if type(entry) == 'table' and entry[10] ~= nil then n = n + 1 end
		end
		return n
	]])
	eq({ held = #held, typed = (held[2] or ''):find('^held held over · .*, loaded $') ~= nil, carrying = carrying },
		{ held = 2, typed = true, carrying = 0 })
end

-- A load's clearing of held-over copies leaves an empty held-over group alone: two empty groups carry
-- nothing to tell them apart by.
T['T1030 [char] (M15, S1 Load, DESK.md:1320) a load\'s clearing leaves an empty held-over group alone'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', OPEN })
	local lines = popup().lines
	lines[1] = '❖ other'
	write_lines(lines)
	child.cmd('close')
	child.settle()
	eq(S2.save(child), { true })
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', OPEN })
	lines = popup().lines
	lines[1] = '❖ todo'
	write_lines(lines)
	child.cmd('close')
	child.settle()
	child.cmd('close')
	child.settle(1200) -- held over, and written into the file with the records
	eq(S2.load(child), { true })
	child.settle(300)
	eq(untimed(child.lua(GROUPS_IN_ORDER, { '' })), { 'main ', 'held held over · window on c.txt ' })
end

-- The pop-up's write keeps an empty group held over while it held edits, below its lines.
T['T1031 [char] (M15, DESK.md:1325, :1313) the marks pop-up keeps an empty group held over meanwhile below its lines'] = function()
	child.steps({ ':e a' })
	child.cmd('split')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e d', OPEN })
	local lines = popup().lines
	lines[1] = '❖ todo'
	write_lines(lines)
	child.cmd('close')
	child.settle()
	child.cmd('wincmd p')
	child.settle()
	child.steps({ "<M-'><M-3>", OPEN })
	lines = popup().lines
	lines[1] = '❖ mine'
	child.lua('vim.api.nvim_buf_set_lines((require("frogman.domains.marks.popup").buffer() or -1), 0, -1, false, ...)', { lines })
	child.lua('vim.api.nvim_win_close(..., false)', { split })
	child.settle(300)
	child.cmd('silent! write')
	child.settle(100)
	eq(untimed(child.lua(GROUPS_IN_ORDER, { '' })), { 'mine ', 'held held over · window on d.txt ' })
end

-- A load bringing a window the marks it has already, under the pop-up's edits: the write keeps nothing of it
-- below, a drawn group having the same name and marks.
T['T1032 [char] (M15, S1 Load, DESK.md:1325) an unchanged load under the pop-up\'s edits leaves nothing below'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e b', ADD .. 'a>', ':e a' })
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e b', ADD .. 'a>', ':e a' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ OPEN })
	child.lua('vim.api.nvim_buf_set_lines((require("frogman.domains.marks.popup").buffer() or -1), 0, -1, false, { "❖ main", "a -> b.txt", "d -> d.txt" })')
	child.lua('vim.api.nvim_set_current_win(...)', { win })
	child.settle()
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	child.lua('vim.api.nvim_set_current_win((require("frogman.domains.marks.popup").window() or -1))')
	child.cmd('silent! write')
	child.settle(100)
	eq(child.lua(WIN_GROUPS, { win }), { { name = 'main', held = false, marks = { a = 'b', d = 'd' } } })
end

-- A load that holds a matched window's own groups over leaves out an empty one its entry brings back, by
-- its name, having no marks to be known by, and holds over an empty one the entry doesn't name.
T['T1033 [char] (M15, S1 Load, DESK.md:1333, :1313) a load holding a window\'s own groups over knows an empty one by its name'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e c', ADD .. 'a>', ':e a', OPEN })
	write_lines(vim.list_extend({ '❖ main', 'a -> c.txt', '❖ todo' }, rows({})))
	child.cmd('close')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e b', ADD .. 'a>', ':e a', OPEN })
	local lines = vim.list_extend({ '❖ main', 'a -> b.txt', '❖ todo' }, rows({}))
	vim.list_extend(lines, vim.list_extend({ '❖ extra' }, rows({})))
	write_lines(lines)
	child.cmd('close')
	child.settle()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	eq({ window = child.lua(WIN_GROUPS, { win }), held = untimed(child.lua(GROUPS_IN_ORDER, { id })) },
		{ window = { { name = 'main', held = false, marks = { a = 'c' } }, { name = 'todo', held = false, marks = {} } },
			held = { 'main ', 'held held over · t, loaded into tab 1, main a=b', 'held held over · t, loaded into tab 1, extra ' } })
end

-- A saved plain tab no tab takes at a load, holding only a typed tab group with no marks: held over, empty,
-- and the tab leaves the file at the records write.
T['T1034 [char] (M15, S1 Load, DESK.md:1313, :1318) a saved tab no tab takes holds its empty typed group over, and leaves the file'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e d', "<M-'><M-2>", OPEN })
	local lines = popup().lines
	lines[1] = '❖ todo'
	write_lines(lines)
	child.cmd('close')
	child.settle()
	child.steps({ "<M-'><M-1>" })
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'x' }, 'x')
	eq(S2.load(child), { true })
	child.settle(300)
	local held = untimed(child.lua(GROUPS_IN_ORDER, { '' }))
	S2.start(child, s) -- the quit writes the records
	local tabs = child.lua([[
		local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), nil) or {}
		return #(saved.tabs or {})
	]])
	eq({ n = #held, first = held[1], typed = (held[2] or ''):find('^held held over · .+, loaded $') ~= nil, tabs = tabs },
		{ n = 2, first = 'main ', typed = true, tabs = 0 })
end

-- A window closed with an empty default group and a marked typed one: the default goes with the window,
-- the typed one is held over alone, unnamed.
T['T1035 [char] (M15, DESK.md:1313, :1301) a window closed with an empty default group holds over only its other groups'] = function()
	child.steps({ ':e a' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e d', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({}))
	vim.list_extend(lines, vim.list_extend({ '❖ feature' }, rows({ a = 'c.txt' })))
	write_lines(lines)
	child.cmd('close')
	child.settle()
	child.cmd('close')
	child.settle(300)
	eq(untimed(child.lua(GROUPS_IN_ORDER, { '' })), { 'main ', 'held held over · window on d.txt a=c' })
end

-- A window entry no window takes, holding an empty default group and a marked typed one: the load holds the
-- typed one over alone, the default going.
T['T1036 [char] (M15, S1 Load, DESK.md:1313, :1301) an entry no window takes holds over only its groups but an empty default'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e d', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({}))
	vim.list_extend(lines, vim.list_extend({ '❖ feature' }, rows({ a = 'c.txt' })))
	write_lines(lines)
	child.cmd('close')
	child.settle()
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'x' }, 'x')
	eq(S2.load(child), { true })
	child.settle(300)
	local held = untimed(child.lua(GROUPS_IN_ORDER, { '' }))
	eq({ n = #held, first = held[1], feature = (held[2] or ''):find('^held held over · .+, loaded a=c$') ~= nil },
		{ n = 2, first = 'main ', feature = true })
end

-- A tab session's load replacing a matched window's own groups: its empty default isn't held over.
T['T1037 [char] (M15, S1 Load, DESK.md:1333, :1301) a load replacing a window\'s own groups holds over none of its empty default'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e c', ADD .. 'a>', ':e a' })
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e a', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({}))
	vim.list_extend(lines, vim.list_extend({ '❖ mine' }, rows({ s = 'e.txt' })))
	write_lines(lines)
	child.cmd('close')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	eq(untimed(child.lua(GROUPS_IN_ORDER, { id })), { 'main ', 'held held over · t, loaded into tab 1 s=e' })
end

-- A window keeping its own marks at a tab session's load, its entry bringing an empty default group and an
-- empty typed one: it takes the typed one below its own, not the default.
T['T1038 [char] (M15, S1 Load, DESK.md:1333, :1301) a window keeping its own marks takes its entry\'s empty typed group, not its empty default'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({}))
	vim.list_extend(lines, vim.list_extend({ '❖ feature' }, rows({})))
	write_lines(lines)
	child.cmd('close')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e b', ADD .. 'a>', OPEN })
	lines = popup().lines
	lines[1] = '❖ work'
	write_lines(lines)
	child.cmd('close')
	child.settle()
	child.steps({ ':e a' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	eq(child.lua(WIN_GROUPS, { win }), { { name = 'work', held = false, marks = { a = 'b' } }, { name = 'feature', held = false, marks = {} } })
end

-- P1 with an empty group: a tab session loaded twice, first into a tab its entries don't match, then into one
-- they do: the window takes its empty group back, and the empty copy the first load held over goes, known by
-- the name of the group it came from.
T['T1039 [char] (M15, S1 Load, DESK.md:1320) a tab session loaded twice, first where no entry matches, gives the window its empty group once'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>', ':e d', OPEN })
	write_lines(vim.list_extend({ '❖ main', 'a -> c.txt', '❖ todo' }, rows({})))
	child.cmd('close')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local first = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local held_first = #child.lua(HELD_NAMES, { first })
	eq(S2.load_tab_session(child, 't'), { true })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	local pool = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	eq({ same = pool == first, held_first = held_first, held = child.lua(HELD_NAMES, { pool }), window = child.lua(WIN_GROUPS, { win }) },
		{ same = true, held_first = 2, held = {},
			window = { { name = 'main', held = false, marks = { a = 'c' } }, { name = 'todo', held = false, marks = {} } } })
end

-- A tab session loaded again where it's open, before any records write: an entry no window takes holds its
-- empty group over once, not again.
T['T1040 [char] (M15, S1 Load, DESK.md:1313, :1332) a tab session loaded again holds no repeat of an untaken entry\'s empty group over'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e d' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c', OPEN })
	local lines = popup().lines
	lines[1] = '❖ todo'
	write_lines(lines)
	child.cmd('close')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e d' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local pool = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local once = #child.lua(HELD_NAMES, { pool })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	eq({ once = once, again = #child.lua(HELD_NAMES, { pool }) }, { once = 1, again = 1 })
end

-- Two entries no window takes in one load, each with an empty group of one name: both are held over.
T['T1041 [char] (M15, S1 Load, DESK.md:1313) two entries no window takes, each with an empty group of one name, have both held over'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e d' })
	for _, f in ipairs({ 'c', 'e' }) do
		child.cmd('vsplit')
		child.settle()
		child.steps({ ':e ' .. f, OPEN })
		local lines = popup().lines
		lines[1] = '❖ todo'
		write_lines(lines)
		child.cmd('close')
		child.settle()
	end
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e d' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local pool = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	eq(#child.lua(HELD_NAMES, { pool }), 2)
end

-- Another editor's save stands in: t's file gains an empty group of its own, notes, that memory doesn't have.
-- Loaded again where it's open, memory winning: notes is held over, once, and not again at the next load.
T['T1042 [char] (M15, S1 Load, DESK.md:1332) a load where the session is open holds an empty group only its file has over, once'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e d' })
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e d' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	child.lua([[
		local crypto = require('frogman.domains.storage.crypto')
		local dir = vim.fn.getcwd(-1, -1)
		local path = _G.FRG_TEST.session_path(dir, 't')
		local fh = assert(io.open(path, 'rb')); local bytes = fh:read('*a'); fh:close()
		local salt = bytes:sub(5, 4 + crypto.salt_length)
		local data = _G.FRG_TEST.read_session(dir, 't')
		data.marks = data.marks or {}
		table.insert(data.marks, { name = 'notes', marks = {} })
		local header = "CDV1" .. salt
		local out = header .. crypto.seal(crypto.derive_key(dir, salt), vim.json.encode(data), header)
		fh = assert(io.open(path, 'wb')); fh:write(out); fh:close()
	]])
	local pool = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local once = untimed(child.lua(HELD_NAMES, { pool }))
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	eq({ once = once, again = #child.lua(HELD_NAMES, { pool }) }, { once = { 'held over · t, loaded into tab 1' }, again = 1 })
end

-- A load bringing a window its entry under the pop-up's edits, the entry holding an empty default group: the
-- write keeps nothing of the default below its lines, it going as a load's empty default goes.
T['T1044 [char] (M15, S1 Load, DESK.md:1325, :1301) an empty default a load brings under the pop-up\'s edits isn\'t kept below them'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', OPEN })
	local lines = vim.list_extend({ '❖ main' }, rows({}))
	vim.list_extend(lines, vim.list_extend({ '❖ feature' }, rows({ a = 'c.txt' })))
	write_lines(lines)
	child.cmd('close')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e b', ADD .. 'a>', ':e a' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ OPEN })
	child.lua('vim.api.nvim_buf_set_lines((require("frogman.domains.marks.popup").buffer() or -1), 0, -1, false, { "❖ main", "a -> b.txt", "d -> d.txt" })')
	child.lua('vim.api.nvim_set_current_win(...)', { win })
	child.settle()
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	child.lua('vim.api.nvim_set_current_win((require("frogman.domains.marks.popup").window() or -1))')
	child.cmd('silent! write')
	child.settle(100)
	local groups = child.lua(WIN_GROUPS, { win })
	eq({ n = #groups, first = groups[1] and groups[1].marks, second = groups[2] and groups[2].marks,
		held = groups[2] and groups[2].held, default = child.lua([[
			local s = require('frogman.domains.marks').data.scopes.window[...]
			local n = 0
			for _, g in ipairs(s and s.groups or {}) do if g.default and g.held then n = n + 1 end end
			return n
		]], { win }) },
		{ n = 2, first = { a = 'b', d = 'd' }, second = { a = 'c' }, held = true, default = 0 })
end

-- P2 with an empty group: a plain tab closed after the whole editor's save, its window's empty group held over
-- and written with the records; a fresh editor restores both tabs and loads: the window takes the group back
-- from its entry, and the copy the close held over goes, known by the name it came from, read from the file.
T['T1045 [char] (M15, S1 Load, DESK.md:1320) a plain tab restored before any save takes its window\'s empty group back once'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e x' })
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', OPEN })
	local lines = popup().lines
	lines[1] = '❖ todo'
	write_lines(lines)
	child.cmd('close')
	child.settle()
	eq(S2.save(child), { true })
	child.cmd('tabclose')
	child.settle(1500) -- held over, and the records written within the second
	S2.start(child, s)
	S2.restore_tabs(child, { { files = { 'x' }, shown = 'x' }, { files = { 'c' }, shown = 'c' } })
	eq(S2.load(child), { true })
	child.settle(300)
	child.cmd('tabnext 2')
	child.settle()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	eq({ held = child.lua(HELD_NAMES, { '' }), window = child.lua(WIN_GROUPS, { win }) },
		{ held = {}, window = { { name = 'todo', held = false, marks = {} } } })
end

-- A default group with marks a load brings under the pop-up's edits: kept below them, held over, as no
-- default; the pop-up's own first group stays the default.
T['T1046 [char] (M15, S1 Load, DESK.md:1325, :1301) a default group a load brings under the pop-up\'s edits is held over below them as no default'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e c', ADD .. 'a>', ':e a' })
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e b', ADD .. 'a>', ':e a' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ OPEN })
	child.lua('vim.api.nvim_buf_set_lines((require("frogman.domains.marks.popup").buffer() or -1), 0, -1, false, { "❖ main", "a -> b.txt", "d -> d.txt" })')
	child.lua('vim.api.nvim_set_current_win(...)', { win })
	child.settle()
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	child.lua('vim.api.nvim_set_current_win((require("frogman.domains.marks.popup").window() or -1))')
	child.cmd('silent! write')
	child.settle(100)
	eq(child.lua([[
		local s = require('frogman.domains.marks').data.scopes.window[...]
		return vim.tbl_map(function(g) return { held = g.held == true, default = g.default == true } end, s and s.groups or {})
	]], { win }), { { held = false, default = true }, { held = true, default = false } })
end

-- A load whose taken entry clears an empty copy holds over another entry's empty group of the same name: the
-- copy cleared isn't there to be it.
T['T1048 [char] (M15, S1 Load, DESK.md:1320, :1313) a copy a load clears doesn\'t keep another entry\'s same-named empty group from being held over'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.cmd('tabnew')
	child.settle()
	for i, f in ipairs({ 'c', 'e' }) do
		if i > 1 then
			child.cmd('vsplit')
			child.settle()
		end
		child.steps({ ':e ' .. f, OPEN })
		local lines = popup().lines
		lines[1] = '❖ todo'
		write_lines(lines)
		child.cmd('close')
		child.settle()
	end
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local pool = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local first = #child.lua(HELD_NAMES, { pool })
	eq(child.lua([[
		vim.cmd('noautocmd tabnew')
		local b = vim.fn.bufadd('e.txt')
		vim.fn.bufload(b)
		vim.cmd('noautocmd edit c.txt')
		return { pcall(require('frogman').load_session, 't', { tab = vim.api.nvim_get_current_tabpage() }) }
	]]), { true })
	child.settle(300)
	local win = child.lua('return vim.api.nvim_get_current_win()')
	pool = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	eq({ first = first, held = #child.lua(HELD_NAMES, { pool }), window = child.lua(WIN_GROUPS, { win }) },
		{ first = 2, held = 1, window = { { name = 'todo', held = false, marks = {} } } })
end

-- A tab session's first load into a tab on e holds the c window's empty group over; its second, into a tab on c
-- alone, gives the c window its group back, clearing that copy, and holds the e window's empty group of the same
-- name over: the cleared copy isn't there to be it, whatever order the file keeps the two windows in.
T['T1049 [char] (M15, S1 Load, DESK.md:1320, :1313) a window taking its empty group back leaves another window\'s same-named empty group to be held over'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.cmd('tabnew')
	child.settle()
	for i, f in ipairs({ 'c', 'e' }) do
		if i > 1 then
			child.cmd('vsplit')
			child.settle()
		end
		child.steps({ ':e ' .. f, OPEN })
		local lines = popup().lines
		lines[1] = '❖ todo'
		write_lines(lines)
		child.cmd('close')
		child.settle()
	end
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e e' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local pool = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local first = #child.lua(HELD_NAMES, { pool })
	eq(child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit c.txt')
		return { pcall(require('frogman').load_session, 't', { tab = vim.api.nvim_get_current_tabpage() }) }
	]]), { true })
	child.settle(300)
	local win = child.lua('return vim.api.nvim_get_current_win()')
	pool = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	eq({ first = first, held = #child.lua(HELD_NAMES, { pool }), window = child.lua(WIN_GROUPS, { win }) },
		{ first = 1, held = 1, window = { { name = 'todo', held = false, marks = {} } } })
end

-- Two windows with no saved entry, each with an empty todo, closed: two copies held over. A window whose entry
-- brings an empty todo takes it back at a load: one copy goes, the other window's stays.
T['T1050 [char] (M15, S1 Load, DESK.md:1320) a window taking its empty group back clears one copy of it, another window\'s staying'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e d', OPEN })
	local lines = popup().lines
	lines[1] = '❖ todo'
	write_lines(lines)
	child.cmd('close')
	child.settle()
	eq(S2.save(child), { true })
	for _, f in ipairs({ 'c', 'e' }) do
		child.cmd('split')
		child.settle()
		child.steps({ ':e ' .. f, OPEN })
		lines = popup().lines
		lines[1] = '❖ todo'
		write_lines(lines)
		child.cmd('close')
		child.settle()
		child.cmd('close')
		child.settle(300)
	end
	child.settle(1200) -- the two copies written with the records
	local before = #child.lua(HELD_NAMES, { '' })
	eq(S2.load(child), { true })
	child.settle(300)
	eq({ before = before, after = #child.lua(HELD_NAMES, { '' }), window = child.lua(WIN_GROUPS, { child.lua('return vim.api.nvim_get_current_win()') }) },
		{ before = 2, after = 1, window = { { name = 'todo', held = false, marks = {} } } })
end

-- A window closed with a saved entry: its groups go onto the entry as they stand, a group deleted since the
-- save gone from it and an empty one typed since on it, nothing held over; the next load gives them back once.
T['T1051 [char] (M15, DESK.md:1313) a window closed with a saved entry puts its groups onto it as they stand, nothing held over'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>', OPEN })
	write_lines({ '❖ main', 'a -> c.txt', '❖ feature', 's -> e.txt' })
	child.cmd('close')
	child.settle()
	eq(S2.save(child), { true })
	child.steps({ OPEN })
	write_lines(vim.list_extend({ '❖ main', 'a -> c.txt', '❖ todo' }, rows({})))
	child.cmd('close')
	child.settle()
	child.cmd('close')
	child.settle(1500) -- the close's write lands with the records
	local held, filed = child.lua(HELD_NAMES, { '' }), child.lua(ENTRY_GROUPS, { '' })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'c' }, 'a')
	child.lua('vim.cmd("noautocmd vsplit"); vim.cmd("noautocmd edit c.txt")')
	eq(S2.load(child), { true })
	child.settle(300)
	eq({ held = held, filed = filed, window = child.lua(WIN_GROUPS, { child.lua('return vim.api.nvim_get_current_win()') }),
		held_after = child.lua(HELD_NAMES, { '' }) },
		{ held = {}, filed = { { 'main a=c', 'todo ' } },
			window = { { name = 'main', held = false, marks = { a = 'c' } }, { name = 'todo', held = false, marks = {} } }, held_after = {} })
end

-- A save after a close, the windows written anew without the closed one: what the close put onto its entry
-- is held over then, once, under what the window showed; the next load: once.
T['T1052 [char] (M15, DESK.md:1313) a save after a close holds what the close put onto its entry over, once'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>' })
	eq(S2.save(child), { true })
	child.cmd('close')
	child.settle(1500)
	eq(S2.save(child), { true })
	local saved = untimed(child.lua(HELD_NAMES, { '' }))
	S2.start(child, s)
	Misc.restore(child, { 'a' }, 'a')
	eq(S2.load(child), { true })
	child.settle(300)
	eq({ saved = saved, loaded = untimed(child.lua(GROUPS_IN_ORDER, { '' })) },
		{ saved = { 'held over · window on c.txt' }, loaded = { 'main ', 'held held over · window on c.txt a=c' } })
end

-- The README's save at TabClosedPre, `:q` closing a tab session's last window: the save writes that window,
-- still in its tab, so nothing is held over, t's file holding no held-over group, and the load gives the mark
-- back once.
T['T1053 [char] (M15, DESK.md:1313) a save at TabClosedPre writes the window its last close closes, and holds nothing over'] = function()
	local s = S2.shared()
	tab_session(s)
	local id = pool_here()
	child.lua([[
		vim.api.nvim_create_autocmd('TabClosedPre', { callback = function()
			require('frogman').save_session('t', { tab = vim.api.nvim_get_current_tabpage() })
		end })
	]])
	child.steps({ ':e c', ADD .. 'a>', ':e d' })
	child.cmd('q')
	child.settle(300)
	local filed = child.lua(FILE_MARKS, { 't' }).held
	eq(S2.load_tab_session(child, 't'), { true })
	child.steps({ JUMP .. 'a>' })
	eq({ filed = filed, held = child.lua(HELD_NAMES, { id }), jumped = child.shown() }, { filed = {}, held = {}, jumped = 'c' })
end

-- Another editor's save rewrites the entry between the close and frogman's records write: the close's groups
-- are held over instead, and the file keeps the other editor's entry.
T['T1054 [char] (M15, S1 Records, DESK.md:1313) a close whose entry another editor rewrote meanwhile is held over instead'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>' })
	eq(S2.save(child), { true })
	child.lua([[
		local crypto = require('frogman.domains.storage.crypto')
		local H = require('frogman.domains.history')
		local dir = vim.fn.getcwd(-1, -1)
		local path = require('frogman.configs').session_dir .. vim.fn.sha256(dir)
		local fh = assert(io.open(path, 'rb')); local bytes = fh:read('*a'); fh:close()
		local salt = bytes:sub(5, 4 + crypto.salt_length)
		local data = _G.FRG_TEST.read_session(dir, nil)
		local e = H.routines.get_filehash(_G.FRG_TEST.root .. '/e.txt')
		data.paths[e] = _G.FRG_TEST.root .. '/e.txt'
		for _, entry in ipairs(data.windows) do
			if type(entry[10]) == 'table' then entry[10] = { { name = 'main', marks = { s = e } } } end
		end
		local header = "CDV1" .. salt
		local out = header .. crypto.seal(crypto.derive_key(dir, salt), vim.json.encode(data), header)
		fh = assert(io.open(path, 'wb')); fh:write(out); fh:close()
	]])
	child.cmd('close')
	child.settle(1500)
	eq({ held = untimed(child.lua(GROUPS_IN_ORDER, { '' })), filed = child.lua(ENTRY_GROUPS, { '' }) },
		{ held = { 'main ', 'held held over · window on c.txt a=c' }, filed = { { 'main s=e' } } })
end

-- A plain tab closed with a saved tab entry: its groups go onto it as they stand, nothing held over.
T['T1055 [char] (M15, DESK.md:1313) a plain tab closed with a saved tab entry puts its groups onto it'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', "<M-'><M-2>", ADD .. 'a>' })
	eq(S2.save(child), { true })
	child.steps({ OPEN })
	write_lines({ '❖ main', 'a -> c.txt', 's -> e.txt' })
	child.cmd('close')
	child.settle()
	child.steps({ "<M-'><M-1>" })
	child.cmd('tabclose')
	child.settle(1500)
	eq({ held = child.lua(HELD_NAMES, { '' }), tabs = child.lua(TAB_GROUPS) }, { held = {}, tabs = { { 'main a=c,s=e' } } })
end

-- A plain tab whose groups are all gone, closed: its tab entry comes off the file, nothing held over.
T['T1056 [char] (M15, DESK.md:1313) a plain tab closed with no groups left takes its tab entry off'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', "<M-'><M-2>", ADD .. 'a>' })
	eq(S2.save(child), { true })
	child.steps({ OPEN })
	write_lines({})
	child.cmd('close')
	child.settle()
	child.steps({ "<M-'><M-1>" })
	child.cmd('tabclose')
	child.settle(1500)
	eq({ held = child.lua(HELD_NAMES, { '' }), tabs = child.lua(TAB_GROUPS) }, { held = {}, tabs = {} })
end

-- R9: a mark made after a tab session's last save, its tab closed with nothing saving at the close: the mark
-- goes onto its window's entry in t's file, and the next load gives it back.
T['T1057 [char] (M15, DESK.md:1313, repro R9) a mark made after a tab session\'s last save comes back after its tab closes'] = function()
	local s = S2.shared()
	tab_session(s)
	local id = pool_here()
	eq(save_t(), { true })
	child.steps({ ':e c', ADD .. 'a>', ':e d' })
	child.cmd('tabclose')
	child.settle(300)
	eq(S2.load_tab_session(child, 't'), { true })
	child.steps({ JUMP .. 'a>' })
	eq({ jumped = child.shown(), held = child.lua(HELD_NAMES, { id }) }, { jumped = 'c', held = {} })
end

-- R9c: two marked windows in the tab, both marks made after t's last save, the tab closed: both come back.
T['T1058 [char] (M15, DESK.md:1313, repro R9c) the marks of two windows made after a tab session\'s last save come back after its tab closes'] = function()
	local s = S2.shared()
	tab_session(s)
	local id = pool_here()
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e e' })
	eq(save_t(), { true })
	child.steps({ ADD .. 'a>' })
	child.cmd('wincmd p')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>', ':e d' })
	child.cmd('tabclose')
	child.settle(300)
	local got = child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		vim.cmd('noautocmd vsplit')
		vim.cmd('noautocmd edit e.txt')
		return { pcall(require('frogman').load_session, 't', { tab = vim.api.nvim_get_current_tabpage() }) }
	]])
	child.settle(300)
	local marks = child.lua([[
		local out = {}
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			local H = require('frogman.domains.history')
			local s = require('frogman.domains.marks').data.scopes.window[win]
			local g = s and s.groups[1]
			local h = g and g.marks.a and H.handles.get(H.handles.resolve(g.marks.a))
			out[vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)), ':t:r')] =
				h and vim.fn.fnamemodify(H.get_filepath_from_hash(h.hash), ':t:r') or false
		end
		return out
	]])
	eq({ got = got, marks = marks, held = child.lua(HELD_NAMES, { pool_here() }) }, { got = { true }, marks = { d = 'c', e = 'e' }, held = {} })
end

-- P2: a plain tab closed after the whole editor's save: the close puts its window's mark onto its entry,
-- nothing held over.
T['T1060 [char] (M15, DESK.md:1313, repro P2) a plain tab closed after a save puts its window\'s mark onto its entry, nothing held over'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e x' })
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>' })
	eq(S2.save(child), { true })
	child.cmd('tabclose')
	child.settle(1500)
	eq({ held = child.lua(HELD_NAMES, { '' }), filed = child.lua(ENTRY_GROUPS, { '' }) }, { held = {}, filed = { { 'main a=c' } } })
end

-- P6: a window with a saved entry in t's file, closed without its events: the cleanup pass puts its mark onto
-- that entry, nothing held over anywhere.
T['T1061 [char] (M15, DESK.md:1313, repro P6) a window closed without its events puts its mark onto its entry in its session\'s file'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e x' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>' })
	child.cmd('wincmd p')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	local id = pool_here()
	child.steps({ ':e d' })
	child.lua('vim.cmd("noautocmd call nvim_win_close(" .. ... .. ", v:true)")', { split })
	child.lua('require("frogman.domains.history").routines.cleanup_system()')
	child.settle(1500)
	eq({ held_t = child.lua(HELD_NAMES, { id }), held_e = child.lua(HELD_NAMES, { '' }), filed = child.lua(ENTRY_GROUPS, { 't' }) },
		{ held_t = {}, held_e = {}, filed = { { 'main a=c' } } })
end

-- A tab session's tab closed while its file can't be written: the pool is kept with no tab, and its window's
-- close, its mark among it, is kept in memory with it, not written and not lost.
T['T1062 [char] (M15, DESK.md:1313) a tab session\'s close whose write fails keeps its window\'s close in memory with the list'] = function()
	local s = S2.shared()
	tab_session(s)
	eq(save_t(), { true })
	child.steps({ ':e c', ADD .. 'a>', ':e d' })
	vim.fn.setfperm(s.session_dir, 'r-xr-xr-x')
	MiniTest.finally(function() vim.fn.setfperm(s.session_dir, 'rwxr-xr-x') end)
	if vim.fn.filewritable(s.session_dir) == 2 then
		vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
		MiniTest.skip('a read-only folder is still writable: the suite runs as root')
	end
	child.cmd('tabclose')
	child.settle(300)
	local kept = child.lua([[
		local H = require('frogman.domains.history')
		local kept_pool = false
		for id, pool in pairs(H.data.pools) do
			if id ~= '' and not pool.detached and next(pool.tabs) == nil then kept_pool = true end
		end
		local file = _G.FRG_TEST.session_path(vim.fn.getcwd(-1, -1), 't')
		local known = require('frogman.domains.storage.data').entries[file]
		local closes = {}
		for _, slot in pairs(known and known.windows or {}) do
			if slot.close then
				for _, g in ipairs(slot.close.groups or {}) do
					for alias, h in pairs(g.marks) do
						table.insert(closes, alias .. '=' .. vim.fn.fnamemodify(H.get_filepath_from_hash(h) or h, ':t:r'))
					end
				end
				table.insert(closes, 'written=' .. tostring(slot.close.state ~= nil))
			end
		end
		return { pool = kept_pool, closes = closes }
	]])
	vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
	eq(kept, { pool = true, closes = { 'a=c', 'written=false' } })
end

-- A window with no saved entry in t's file, at t's tab's close: its mark is held over in t's scope and written
-- into t's file with its closed list, and comes back held over at the next load.
T['T1064 [char] (M15, DESK.md:1313) a window with no entry at a tab session\'s close is held over in its scope and written into its file'] = function()
	local s = S2.shared()
	tab_session(s)
	eq(save_t(), { true })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e e', ADD .. 'a>' })
	child.cmd('tabclose')
	child.settle(300)
	eq(S2.load_tab_session(child, 't'), { true })
	eq(untimed(child.lua(GROUPS_IN_ORDER, { pool_here() })), { 'main ', 'held held over · window on e.txt a=e' })
end

-- P6 at a save: a window with a saved entry closed without its events, then a save, whose cleanup pass puts
-- the mark onto the entry and whose windows, written anew without it, hold it over: once.
T['T1065 [char] (M15, DESK.md:1313, repro P6) a window closed without its events, then a save, is held over once'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>' })
	child.cmd('wincmd p')
	child.settle()
	eq(S2.save(child), { true })
	child.lua('vim.cmd("noautocmd call nvim_win_close(" .. ... .. ", v:true)")', { split })
	eq(S2.save(child), { true })
	child.settle(1500)
	eq(untimed(child.lua(GROUPS_IN_ORDER, { '' })), { 'main ', 'held held over · window on c.txt a=c' })
end

-- A tab session's last close while a key's job waits, as it does at a prompt: the event loop runs the close's
-- write before the hold-over its entry-less split queued, so the close holds that over into t's scope first,
-- and t's file takes it, its mark and its snapshot.
T['T1067 [char] (M15, M16, DESK.md:1313, :2065) a tab session\'s last close holds over what its windows still have queued as its records are written'] = function()
	local s = S2.shared()
	tab_session(s)
	eq(save_t(), { true })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e e', ADD .. 'a>', '<M-;><M-s>' })
	child.lua([[
		require('frogman.settle').now(function()
			vim.cmd('tabclose')
			vim.wait(200) -- the event loop runs while the job waits
		end)
	]])
	child.settle(300)
	local file = child.lua(FILE_MARKS, { 't' })
	eq({ held = file.held, snapshots = file.snapshots }, { held = { 'a=e' }, snapshots = 1 })
end

-- A window closing while its name can't be looked up: the close fails nothing, and what it holds over is headed
-- by what was noted of it before.
T['T1068 [char] (M15, DESK.md:1313, :1318) a close whose name can\'t be looked up fails nothing and names what was seen before'] = function()
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c', ADD .. 'a>' })
	child.lua([[
		local R = require('frogman.domains.marks').routines
		_G.FRG_T1068 = R.name_of
		R.name_of = function() error('T1068: no name') end
		vim.v.errmsg = ''
	]])
	local closed = child.lua('return (pcall(vim.cmd, "close"))')
	local errmsg = child.lua('return vim.v.errmsg:find("T1068", 1, true) ~= nil')
	child.lua('require("frogman.domains.marks").routines.name_of = _G.FRG_T1068')
	child.settle(300)
	eq({ closed = closed, errmsg = errmsg, held = child.lua(HELD_WHAT, { '' }) },
		{ closed = true, errmsg = false, held = { marks = { 'window on c.txt' }, snapshots = {} } })
end


-- A session manager's switch, in one call as a manager runs it: its teardown closes the windows given and
-- deletes the buffers given, then it loads the session it switches to.
local function switch(wins, bufs, name)
	return child.lua([[
		local wins, bufs, name = ...
		for _, w in ipairs(wins) do
			if vim.api.nvim_win_is_valid(w) then vim.api.nvim_win_close(w, true) end
		end
		for _, b in ipairs(bufs) do vim.cmd('bdelete ' .. b) end
		return { pcall(require('frogman').load_session, name) }
	]], { wins, bufs, name })
end

-- A session file's closed list, each entry by its file's letter.
local CLOSED_IN = [[
	local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), ...) or {}
	local out = {}
	for _, h in ipairs(saved.closed or {}) do
		table.insert(out, vim.fn.fnamemodify((saved.paths or {})[h] or h, ':t:r'))
	end
	return out
]]

-- The trail pages a session file names, each there on disk: true when every one is.
local PAGES_THERE = [[
	local name = ...
	local dir = vim.fn.getcwd(-1, -1)
	local saved = _G.FRG_TEST.read_session(dir, name) or {}
	local main = _G.FRG_TEST.session_path(dir, name)
	local n, there = 0, 0
	for _, page in pairs(saved.trail or {}) do
		n = n + 1
		if vim.uv.fs_stat(main .. ".d/" .. page) then there = there + 1 end
	end
	return { pages = n > 0, there = there == n }
]]

-- A switch with nothing wired to save at it: a mark made since the session's last save, its window closed by
-- the switch's teardown with the load in the same call: the session left's file holds it on the window's
-- entry, nothing held over.
T['T1069 [char] (M15, DESK.md:1315) a switch keeps a window\'s mark made since the last save on its entry in the session left\'s file'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>' })
	eq(S2.save(child, 'left'), { true })
	child.steps({ ':e e', ADD .. 's>' })
	eq(switch({ split }, {}, 'next'), { true })
	child.settle(300)
	eq({ filed = child.lua(ENTRY_GROUPS, { 'left' }), held = child.lua(FILE_MARKS, { 'left' }).held },
		{ filed = { { 'main a=c,s=e' } }, held = {} })
end

-- A window with no saved entry at a switch: its mark is held over in the session left's scope and written
-- into its file, and none of it reaches the session loaded next.
T['T1071 [char] (M15, DESK.md:1315) a window with no saved entry at a switch is held over in the session left\'s file, not in the next'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	eq(S2.save(child, 'left'), { true })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e e', ADD .. 'a>' })
	eq(switch({ split }, {}, 'next'), { true })
	child.settle(300)
	eq({ filed = child.lua(FILE_MARKS, { 'left' }).held, next = child.lua(HELD_NAMES, { '' }) }, { filed = { 'a=e' }, next = {} })
end

-- The switch's write leaves the session left's closed list as its file has it: a close settled into the list
-- in the same call as the switch, so no records write runs before it; the switch's write doesn't write the
-- close, which goes with the pending write the load drops.
T['T1072 [char] (M5, M15, DESK.md:1315) the switch\'s write leaves the session left\'s closed list as its file has it'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e a' }) -- b hidden, so deleting it closes no window
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>' })
	eq(S2.save(child, 'left'), { true })
	local before = child.lua(CLOSED_IN, { 'left' })
	local got = child.lua([[
		vim.cmd('bdelete b.txt')
		require('frogman.settle').drain() -- the close on the list now
		local on_list = vim.tbl_contains(vim.tbl_map(function(id)
			local h = require('frogman.domains.history').handles.get(id)
			return h and vim.fn.fnamemodify(require('frogman.domains.history').get_filepath_from_hash(h.hash) or '', ':t:r')
		end, require('frogman.domains.history').routines.pools()[''].closed), 'b')
		vim.api.nvim_win_close(..., true)
		return { on_list = on_list, loaded = { pcall(require('frogman').load_session, 'next') } }
	]], { split })
	child.settle(300)
	eq({ before = before, got = got, after = child.lua(CLOSED_IN, { 'left' }), filed = child.lua(ENTRY_GROUPS, { 'left' }) },
		{ before = {}, got = { on_list = true, loaded = { true } }, after = {}, filed = { { 'main a=c' } } })
end

-- A tab session's tab torn down at a whole-editor switch: its window's mark made since t's last save goes onto
-- its entry in t's file, and t's closed list stays as the file had it.
T['T1073 [char] (M15, DESK.md:1315) a tab session\'s tab torn down at a switch keeps its window\'s mark on t\'s entry, t\'s list as it was'] = function()
	local s = S2.shared()
	tab_session(s)
	eq(save_t(), { true })
	child.steps({ ':e c', ADD .. 'a>', ':e d' })
	local before = child.lua(CLOSED_IN, { 't' })
	local got = child.lua([[
		vim.cmd('tabclose')
		vim.cmd('bdelete c.txt')
		return { pcall(require('frogman').load_session, 'next') }
	]])
	child.settle(300)
	eq({ got = got, filed = child.lua(ENTRY_GROUPS, { 't' }), list = child.lua(CLOSED_IN, { 't' }) },
		{ got = { true }, filed = { { 'main a=c' } }, list = before })
end

-- A load of the same session right after a close, before the close's write lands: the window restored as
-- the load runs takes its entry with the close's groups on it.
T['T1074 [char] (M15, DESK.md:1313, :1315) a load of the same session right after a close gives the restored window the close\'s groups'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>' })
	eq(S2.save(child), { true })
	child.steps({ ADD .. 's>' })
	local got = child.lua([[
		vim.api.nvim_win_close(..., true)
		vim.cmd('noautocmd vsplit')
		vim.cmd('noautocmd edit c.txt')
		return { pcall(require('frogman').load_session) }
	]], { split })
	child.settle(300)
	eq({ got = got, window = child.lua(WIN_GROUPS, { child.lua('return vim.api.nvim_get_current_win()') }), held = child.lua(HELD_NAMES, { '' }) },
		{ got = { true }, window = { { name = 'main', held = false, marks = { a = 'c', s = 'c' } } }, held = {} })
end

-- After a switch, a save under the session left's name, from the session loaded next, holds none of the session
-- left's closes over: the switch wrote them, and the load let its entries go.
T['T1075 [char] (M15, DESK.md:1315, :1313) a save under the session left\'s name after a switch holds none of its closes over'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>' })
	eq(S2.save(child, 'left'), { true })
	eq(switch({ split }, {}, 'next'), { true })
	child.settle(300)
	eq(S2.save(child, 'left'), { true })
	eq(child.lua(HELD_NAMES, { '' }), {})
end

-- An open No Name text the session left's last save wrote, no mark naming it: the switch's write keeps its
-- text, and the session loaded back reopens it.
T['T1076 [char] (M15, S1 Records, DESK.md:1315) an open No Name text of the session left survives the switch\'s write'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	S2.noname(child, { 'kept text' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>' })
	eq(S2.save(child, 'left'), { true })
	eq(switch({ split }, {}, 'next'), { true })
	child.settle(300)
	S2.start(child, s)
	eq(S2.load(child, 'left'), { true })
	child.settle(300)
	eq(S2.holding(child, 'kept text'), 1)
end

-- A No Name text made and marked in a split, the split closed by the switch's teardown and the load, all in one
-- batch, so no records write has written the text: the switch's write takes it from its buffer, open still,
-- its window gone, and the window restored at the next load opens it from its mark.
T['T1077 [char] (M15, S1 Records, DESK.md:1315, :1310) a marked No Name text made in the switch\'s batch survives it, its mark opening it'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c' })
	eq(S2.save(child, 'left'), { true })
	local got = child.lua([[
		local split = ...
		vim.api.nvim_set_current_win(split)
		vim.cmd('enew')
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'marked text' })
		require('frogman').mark_add('a')
		vim.api.nvim_win_close(split, true)
		return { pcall(require('frogman').load_session, 'next') }
	]], { split })
	child.settle(300)
	S2.start(child, s)
	Misc.restore(child, { 'a', 'c' }, 'a')
	child.lua('vim.cmd("noautocmd vsplit"); vim.cmd("noautocmd edit c.txt")')
	eq(S2.load(child, 'left'), { true })
	child.settle(300)
	child.steps({ JUMP .. 'a>' })
	eq({ got = got, opened = opened() }, { got = { true }, opened = { '[No Name]', { 'marked text' } } })
end

-- A split closed in a detached list's tab by the switch's teardown: the switch's write carries the list's
-- held-over group onto the list in the whole editor's file.
T['T1078 [char] (M15, S2, DESK.md:1315, :1322) a switch writes a detached list\'s held-over group onto the list in the whole editor\'s file'] = function()
	local s = S2.shared()
	tab_session(s)
	eq(S2.save(child), { true }) -- the whole editor's file, before t moves
	eq(S2.load_tab_session(child, 't'), { true }) -- the second tab keeps t_DETACHED
	eq(S2.save(child), { true })
	child.cmd('tabnext 2')
	child.settle()
	child.cmd('split')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e e', ADD .. 'a>' })
	eq(switch({ split }, {}, 'next'), { true })
	child.settle(300)
	eq(child.lua([[
		local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), nil) or {}
		for _, l in ipairs(saved.detached or {}) do
			if l.label == 't_DETACHED' then
				local held = {}
				for _, g in ipairs(l.marks or {}) do
					if g.held then
						for alias, h in pairs(g.marks or {}) do
							table.insert(held, alias .. '=' .. vim.fn.fnamemodify((saved.paths or {})[h] or h, ':t:r'))
						end
					end
				end
				return held
			end
		end
		return false
	]]), { 'a=e' })
end

-- The switch's write keeps the session left's trail pages: its file names today's page, written by the save
-- after a close, and the page is still on disk after the switch.
T['T1079 [char] (A27, M15, DESK.md:1315) the switch\'s write keeps the session left\'s trail pages'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e d', ADD .. 'a>' })
	eq(S2.save(child, 'left'), { true })
	local before = child.lua(PAGES_THERE, { 'left' })
	eq(switch({ split }, {}, 'next'), { true })
	child.settle(300)
	eq({ before = before, after = child.lua(PAGES_THERE, { 'left' }) },
		{ before = { pages = true, there = true }, after = { pages = true, there = true } })
end

-- A tab session loaded into its own tab right after a close there, before the close's write lands: the window
-- restored as the load runs takes its entry with the close's groups.
T['T1080 [char] (M15, DESK.md:1313, :1315) a tab session loaded into its own tab right after a close gives the restored window the close\'s groups'] = function()
	local s = S2.shared()
	tab_session(s)
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>' })
	eq(save_t(), { true })
	child.steps({ ADD .. 's>' })
	local got = child.lua([[
		vim.api.nvim_win_close(..., true)
		vim.cmd('noautocmd vsplit')
		vim.cmd('noautocmd edit c.txt')
		return { pcall(require('frogman').load_session, 't', { tab = vim.api.nvim_get_current_tabpage() }) }
	]], { split })
	child.settle(300)
	eq({ got = got, window = child.lua(WIN_GROUPS, { child.lua('return vim.api.nvim_get_current_win()') }) },
		{ got = { true }, window = { { name = 'main', held = false, marks = { a = 'c', s = 'c' } } } })
end

-- A No Name text marked since the session's last save, its records written, then edited and the window that
-- marked it closed by the switch in one call, the text still open in another window: the switch's write takes
-- the text from the buffer over the file's copy, and the restored window's mark opens it as edited.
T['T1081 [char] (M15, S1 Records, DESK.md:1315, :1310) a marked No Name text edited since its last write keeps its edits at the switch'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c' })
	eq(S2.save(child, 'left'), { true })
	local buf = S2.noname(child, { 'open text' })
	child.steps({ ADD .. 'a>' })
	child.lua('vim.cmd("wincmd p"); vim.api.nvim_win_set_buf(0, ...)', { buf })
	child.settle(1500) -- the records written, the text among them
	local got = child.lua([[
		local buf, split = ...
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'edited text' })
		vim.api.nvim_win_close(split, true)
		return { pcall(require('frogman').load_session, 'next') }
	]], { buf, split })
	child.settle(300)
	S2.start(child, s)
	Misc.restore(child, { 'a', 'c' }, 'a')
	child.lua('vim.cmd("noautocmd vsplit"); vim.cmd("noautocmd edit c.txt")')
	eq(S2.load(child, 'left'), { true })
	child.settle(300)
	child.steps({ JUMP .. 'a>' })
	eq({ got = got, opened = opened() }, { got = { true }, opened = { '[No Name]', { 'edited text' } } })
end

-- A window the switch's teardown leaves standing: its mark made since the session's last save goes onto its
-- entry in the session left's file as it stands, as a closed window's does.
T['T1082 [char] (M15, DESK.md:1315) a window the switch leaves standing keeps its mark made since the last save on its entry'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>' })
	child.cmd('wincmd p')
	child.settle()
	eq(S2.save(child, 'left'), { true })
	child.steps({ ADD .. 's>' })
	eq(switch({ split }, {}, 'next'), { true })
	child.settle(300)
	local filed = vim.tbl_map(function(groups) return table.concat(groups, '|') end, child.lua(ENTRY_GROUPS, { 'left' }))
	table.sort(filed)
	eq(filed, { 'main a=c', 'main s=a' })
end

-- A plain tab the switch leaves standing: its tab marks made since the session's last save go onto its tab entry.
T['T1083 [char] (M15, DESK.md:1315) a plain tab the switch leaves standing keeps its tab marks made since the last save on its tab entry'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e x' })
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', "<M-'><M-2>", ADD .. 'a>' })
	eq(S2.save(child), { true })
	child.steps({ ':e d', ADD .. 's>' })
	eq(switch({}, {}, 'next'), { true })
	child.settle(300)
	eq(child.lua(TAB_GROUPS), { { 'main a=c,s=d' } })
end

-- An open No Name text the session left's last save wrote, edited since, in a window the switch leaves standing:
-- the switch's write takes its lines from the buffer, open as the file has it, and the session loaded back
-- reopens it as edited.
T['T1084 [char] (M15, S1 Records, DESK.md:1315, :650) an open No Name text edited since the last write keeps its edits at the switch'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	local buf = S2.noname(child, { 'first text' })
	eq(S2.save(child, 'left'), { true })
	local got = child.lua([[
		vim.api.nvim_buf_set_lines(..., 0, -1, false, { 'edited text' })
		return { pcall(require('frogman').load_session, 'next') }
	]], { buf })
	child.settle(300)
	S2.start(child, s)
	eq(S2.load(child, 'left'), { true })
	child.settle(300)
	eq({ got = got, edited = S2.holding(child, 'edited text'), first = S2.holding(child, 'first text') },
		{ got = { true }, edited = 1, first = 0 })
end

-- Today's trail page of a session, read back: whether a move of each kind given is on it, by kind and name.
local PAGE_HAS = [[
	local name, kinds = ...
	local steps = require('frogman.domains.storage').routines.read_trail(vim.fn.getcwd(-1, -1), name, os.date('%Y-%m-%d')) or {}
	local out = {}
	for _, want in ipairs(kinds) do
		out[want] = false
		for _, step in ipairs(steps) do
			for _, m in ipairs(step.moves or {}) do
				if (m.kind .. ' ' .. (m.name or '?')):find(want, 1, true) == 1 then out[want] = true end
			end
		end
	end
	return out
]]

-- The switch writes today's trail page with the session left's own steps: a cycle cancelled by a window jump since
-- the last save is on the session left's page, and a close made in the switch's own batch, the teardown's, isn't.
T['T1085 [char] (A27, DESK.md:1315, :650) the switch writes the session left\'s trail page, its teardown\'s moves left out'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e a' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e x' })
	child.cmd('wincmd p')
	child.settle()
	eq(S2.save(child, 'left'), { true })
	child.steps({ ':e c', '<M-n>' })
	child.cmd('wincmd p')
	child.settle(200)
	local got = child.lua([[
		vim.cmd('bdelete b.txt')
		require('frogman.settle').drain()
		return { pcall(require('frogman').load_session, 'next') }
	]])
	child.settle(300)
	eq({ got = got, page = child.lua(PAGE_HAS, { 'left', { 'cancelled', 'closed b.txt' } }) },
		{ got = { true }, page = { cancelled = true, ['closed b.txt'] = false } })
end

-- A switch whose teardown closes a window without its events (noautocmd), the load in the same call: the window's
-- mark made since the session's last save goes onto its entry in the session left's file as a closed window's
-- does, nothing held over.
T['T1087 [char] (M15, DESK.md:1315, :1313) a window the switch closes without its events keeps its mark made since the last save on its entry'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>' })
	eq(S2.save(child, 'left'), { true })
	child.steps({ ':e e', ADD .. 's>' })
	local got = child.lua([[
		local split = ...
		vim.cmd('noautocmd call nvim_win_close(' .. split .. ', v:true)')
		return { pcall(require('frogman').load_session, 'next') }
	]], { split })
	child.settle(300)
	eq({ got = got, filed = child.lua(ENTRY_GROUPS, { 'left' }), held = child.lua(FILE_MARKS, { 'left' }).held },
		{ got = { true }, filed = { { 'main a=c,s=e' } }, held = {} })
end

-- A window with no saved entry closed without its events by the switch's teardown: its mark is held over in the
-- session left's scope and written into its file, and none of it reaches the session loaded next, a cleanup
-- tick after the load included.
T['T1088 [char] (M15, DESK.md:1315, :1313) a window with no saved entry the switch closes without its events is held over in the session left\'s file'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	eq(S2.save(child, 'left'), { true })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e e', ADD .. 'a>' })
	local got = child.lua([[
		local split = ...
		vim.cmd('noautocmd call nvim_win_close(' .. split .. ', v:true)')
		return { pcall(require('frogman').load_session, 'next') }
	]], { split })
	child.settle(300)
	child.lua('require("frogman.domains.history").routines.cleanup_system()') -- the pass a cleanup tick runs
	child.settle(100)
	eq({ got = got, filed = child.lua(FILE_MARKS, { 'left' }).held, next = child.lua(HELD_NAMES, { '' }) },
		{ got = { true }, filed = { 'a=e' }, next = {} })
end

-- A tab session loaded into its own tab right after a split there closed without its events, before any cleanup
-- tick: the window restored as the load runs takes its entry with what the split held, and nothing is held
-- over, a cleanup tick after the load included.
T['T1089 [char] (M15, DESK.md:1313, :1315) a tab session loaded into its own tab right after a split there closed without its events gives the restored window its groups'] = function()
	local s = S2.shared()
	tab_session(s)
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>' })
	eq(save_t(), { true })
	child.steps({ ADD .. 's>' })
	local got = child.lua([[
		local split = ...
		vim.cmd('noautocmd call nvim_win_close(' .. split .. ', v:true)')
		vim.cmd('noautocmd vsplit')
		vim.cmd('noautocmd edit c.txt')
		return { pcall(require('frogman').load_session, 't', { tab = vim.api.nvim_get_current_tabpage() }) }
	]], { split })
	child.settle(300)
	child.lua('require("frogman.domains.history").routines.cleanup_system()') -- the pass a cleanup tick runs
	child.settle(100)
	eq({ got = got, window = child.lua(WIN_GROUPS, { child.lua('return vim.api.nvim_get_current_win()') }), held = child.lua(HELD_NAMES, { pool_here() }) },
		{ got = { true }, window = { { name = 'main', held = false, marks = { a = 'c', s = 'c' } } }, held = {} })
end

-- A marked No Name text open at the session left's last write, wiped by the switch's teardown, its close settled
-- before the load: the switch's write keeps it open in the file, as the file has it, and the session loaded back
-- reopens it with no mark jump.
T['T1092 [char] (M15, S1 Records, DESK.md:1315, :650) a marked No Name text the switch\'s teardown wipes stays open in the session left\'s file'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	local buf = S2.noname(child, { 'kept text' })
	child.steps({ ADD .. 'a>' })
	eq(S2.save(child, 'left'), { true })
	local got = child.lua([[
		local buf = ...
		local hash = require('frogman.domains.history').get_hash_from_buffer(buf)
		vim.cmd('bwipeout! ' .. buf)
		require('frogman.settle').drain() -- the close settled before the load
		return { hash = hash, loaded = { pcall(require('frogman').load_session, 'next') } }
	]], { buf })
	child.settle(300)
	local reopen = child.lua([[
		local saved = _G.FRG_TEST.read_session(vim.fn.getcwd(-1, -1), 'left') or {}
		local entry = (saved.noname_content or {})[...]
		return entry ~= nil and entry.reopen == true
	]], { got.hash })
	S2.start(child, s)
	eq(S2.load(child, 'left'), { true })
	child.settle(300)
	eq({ loaded = got.loaded, reopen = reopen, open = S2.holding(child, 'kept text') }, { loaded = { true }, reopen = true, open = 1 })
end

-- A plain tab with no saved entry closed with its events in the switch's own call: its tab marks are held over
-- once in the session left's file, the pass for tabs gone without their events not taking them again.
T['T1093 [char] (M15, DESK.md:1315, :1313) a plain tab the switch closes with its events is held over once in the session left\'s file'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e x' })
	eq(S2.save(child, 'left'), { true })
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', "<M-'><M-2>", ADD .. 'a>' })
	local got = child.lua([[
		vim.cmd('tabclose')
		return { pcall(require('frogman').load_session, 'next') }
	]])
	child.settle(300)
	eq({ got = got, held = child.lua(FILE_MARKS, { 'left' }).held }, { got = { true }, held = { 'a=c' } })
end

-- A tab session loaded into another tab session's only tab right after a split there closed without its events:
-- the session left, let go as its last tab becomes the other's, keeps the split's mark made since its last save
-- on its entry in its file, nothing held over in the whole editor's scope, a cleanup tick after the load
-- included.
T['T1094 [char] (M15, DESK.md:1315, :1313) a tab session loaded into another\'s only tab keeps a split closed there without its events on its entry'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 'u'), { true })
	tab_session(s)
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', ADD .. 'a>' })
	eq(save_t(), { true })
	child.steps({ ADD .. 's>' })
	local got = child.lua([[
		local split = ...
		vim.cmd('noautocmd call nvim_win_close(' .. split .. ', v:true)')
		return { pcall(require('frogman').load_session, 'u', { tab = vim.api.nvim_get_current_tabpage() }) }
	]], { split })
	child.settle(300)
	child.lua('require("frogman.domains.history").routines.cleanup_system()') -- the pass a cleanup tick runs
	child.settle(100)
	eq({ got = got, filed = child.lua(ENTRY_GROUPS, { 't' }), held = child.lua(HELD_NAMES, { '' }) },
		{ got = { true }, filed = { { 'main a=c,s=c' } }, held = {} })
end


-- Held over in the whole editor's scope, one group per split closed: each file shown in a split of its own, marked under
-- its alias there, and the split closed. Takes { alias, file } pairs, in order.
local function held_overs(pairs_)
	child.steps({ ':e a' })
	for _, pair in ipairs(pairs_) do
		child.cmd('split')
		child.settle()
		child.steps({ ':e ' .. pair[2], ADD .. pair[1] .. '>' })
		child.cmd('close')
		child.settle(100)
	end
end

-- The session's pop-up lines cut into its groups, each group's header and rows.
local function groups_of(lines)
	local out = {}
	for _, line in ipairs(lines) do
		if line:sub(1, #'❖') == '❖' then
			table.insert(out, { line })
		elseif #out > 0 then
			table.insert(out[#out], line)
		end
	end
	return out
end

-- Two held-over groups swapped in the pop-up: both moved, so both are yours from that write, keeping their names.
T['T1114 [char] (M15, DESK.md:1318) two held-over groups swapped in the pop-up are both yours from that write'] = function()
	held_overs({ { 'a', 'b' }, { 's', 'c' } })
	child.steps({ "<M-'><M-3>", OPEN })
	local g = groups_of(popup().lines) -- ❖ main, then b's and c's held over
	local lines = vim.list_extend(vim.list_extend(vim.deepcopy(g[1]), g[3]), g[2])
	write_lines(lines)
	local after = vim.tbl_map(function(group) return { held = group.held, marks = group.marks } end, session_groups(''))
	eq(after, { { held = false, marks = {} }, { held = false, marks = { s = 'c' } }, { held = false, marks = { a = 'b' } } })
end

-- Three held-over groups, the first moved below the others: it moved, so it's yours; the two kept in their drawn order
-- stay held over.
T['T1115 [char] (M15, DESK.md:1318) a held-over group moved down is yours, the ones kept in order stay held over'] = function()
	held_overs({ { 'a', 'b' }, { 's', 'c' }, { 'd', 'd' } })
	child.steps({ "<M-'><M-3>", OPEN })
	local g = groups_of(popup().lines) -- ❖ main, then b's, c's and d's held over
	local lines = vim.deepcopy(g[1])
	for _, k in ipairs({ 3, 4, 2 }) do
		vim.list_extend(lines, g[k])
	end
	write_lines(lines)
	local after = vim.tbl_map(function(group) return { held = group.held, marks = group.marks } end, session_groups(''))
	eq(after, { { held = false, marks = {} }, { held = true, marks = { s = 'c' } }, { held = true, marks = { d = 'd' } },
		{ held = false, marks = { a = 'b' } } })
end


-- :set nomodified on the tab's screen, a draft of the window's held: the screen is drawn again, the line typed there
-- gone as one undo step, and the draft keeps the flag on.
T['T1116 [char] (M15, DESK.md:1305) :set nomodified draws the screen again as an undo step, a held draft keeping the flag on'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.steps({ "<M-'><M-2>" })
	child.type_keys('2G', 'cc', 'a -> d.txt', '<Esc>')
	child.cmd('set nomodified')
	child.settle(50)
	local reset = popup()
	child.type_keys('u')
	eq({ line = reset.lines[2], modified = reset.modified, undone = popup().lines[2] },
		{ line = 'a -> ', modified = true, undone = 'a -> d.txt' })
end

-- :e! draws the screen again as one undo step, its undo history kept, so u brings the line back.
T['T1117 [char] (M15, DESK.md:1305) :e! draws the screen again as an undo step, its history kept'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.cmd('edit!')
	child.settle(50)
	local reset = popup()
	child.type_keys('u')
	eq({ line = reset.lines[3], modified = reset.modified, undone = popup().lines[3], c = label('c') },
		{ line = 's -> ', modified = false, undone = 's -> c.txt', c = false })
end

-- :q! drops what's typed, nothing written; opened again, the screen is as its scope is, and u brings the typing back.
T['T1118 [char] (M15, DESK.md:1305) :q! drops the edits, and u brings them back once the pop-up opens again'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.cmd('quit!')
	child.settle(100)
	local after = { c = label('c'), gone = popup() == vim.NIL }
	child.steps({ OPEN })
	local reopened = popup().lines[3]
	child.type_keys('u')
	eq({ after = after, reopened = reopened, undone = popup().lines[3] },
		{ after = { c = false, gone = true }, reopened = 's -> ', undone = 's -> c.txt' })
end

-- :q! from another scope's screen drops a draft's edits too, as an undo step of its buffer: back in its mode, the
-- pop-up shows its scope, and u brings the draft back.
T['T1119 [char] (M15, DESK.md:1305) :q! drops a draft\'s edits as an undo step of its buffer'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.steps({ "<M-'><M-2>" })
	child.cmd('quit!')
	child.settle(100)
	local after = { c = label('c'), gone = popup() == vim.NIL }
	child.steps({ "<M-'><M-1>", OPEN })
	local reopened = popup().lines[3]
	child.type_keys('u')
	eq({ after = after, reopened = reopened, undone = popup().lines[3] },
		{ after = { c = false, gone = true }, reopened = 's -> ', undone = 's -> c.txt' })
end

-- A window's buffer stays while its window is there, the pop-up closed, and goes once the window closes.
T['T1120 [char] (M15, DESK.md:1305) a window\'s buffer goes once its window closes'] = function()
	child.steps({ ':e a' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e b', OPEN })
	local buf = child.lua('return require("frogman.domains.marks.popup").buffer()')
	child.step('q')
	child.settle(100)
	local kept = child.lua('return vim.api.nvim_buf_is_valid(...)', { buf })
	child.cmd('close')
	child.settle(100)
	eq({ kept = kept, gone = not child.lua('return vim.api.nvim_buf_is_valid(...)', { buf }) }, { kept = true, gone = true })
end

-- The split the pop-up was opened from closed while the pop-up holds a draft of the split's marks and edits of the
-- session's: q drops the window's, writes the session's, says so, and leaves.
T['T1121 [char] (M15, DESK.md:1860) q with the window it was opened from gone writes the session\'s edits, drops the window\'s, and says so'] = function()
	child.steps({ ':e a' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e b' })
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ OPEN })
	child.type_keys('2G', 'cc', 'a -> b.txt', '<Esc>')
	child.steps({ "<M-'><M-3>" })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.lua('vim.api.nvim_win_close(..., true)', { split })
	child.settle(100)
	child.messages()
	child.step('q')
	child.settle(100)
	eq({ said = said(), b = label('b'), c = label('c'), gone = popup() == vim.NIL }, {
		said = { "frogman: the window these marks were for is gone: its edits are dropped; the session's are written." },
		b = false, c = 's', gone = true,
	})
end


-- A scope's buffer is kept with its undo history when the pop-up closes: opened again, an undo takes back what was
-- typed before the write.
T['T1122 [char] (M15, DESK.md:1305) a scope\'s buffer keeps its undo history through q and a reopen'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.step('q')
	child.settle(100)
	local written = { c = label('c'), gone = popup() == vim.NIL }
	child.steps({ OPEN })
	local reopened = popup().lines[3]
	child.type_keys('u')
	local undone = popup()
	eq({ written = written, reopened = reopened, undone = undone.lines[3], modified = undone.modified },
		{ written = { c = 's', gone = true }, reopened = 's -> c.txt', undone = 's -> ', modified = true })
end

-- The whole editor's session's buffer is kept with its history across a switch to another session and back: back in
-- the first, the pop-up opened again on its session's marks, an undo takes back what was typed before the switch.
T['T1123 [char] (M15, DESK.md:1305) the whole editor\'s session buffer keeps its history across a switch and back'] = function()
	child.steps({ "<M-'><M-3>", ':e b', ADD .. 'a>', ':e c' })
	eq(child.lua('return { pcall(require("frogman").save_session, "A") }'), { true })
	child.steps({ OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.step('q')
	child.settle(100)
	eq(child.lua('return { pcall(require("frogman").save_session, "A") }'), { true })
	eq(child.lua('return { pcall(require("frogman").load_session, "B") }'), { true })
	child.settle(300)
	local switched = label('c')
	eq(child.lua('return { pcall(require("frogman").load_session, "A") }'), { true })
	child.settle(300)
	child.steps({ "<M-'><M-3>", OPEN })
	local back = popup().lines[3]
	child.type_keys('u')
	eq({ switched = switched, back = back, undone = popup().lines[3] },
		{ switched = false, back = 's -> c.txt', undone = 's -> ' })
end

-- A whole-editor save that names the session anew, its first save or a save as another, keeps the session's buffer
-- and its history: the pop-up opened again, an undo takes back what was typed before the save.
T['T1124 [char] (M15, DESK.md:1305) a whole-editor save naming the session anew keeps the session\'s buffer and its history'] = function()
	child.steps({ "<M-'><M-3>", ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.step('q')
	child.settle(100)
	eq(child.lua('return { pcall(require("frogman").save_session, "A") }'), { true })
	child.steps({ OPEN })
	child.type_keys('u')
	local first = popup().lines[3]
	child.type_keys('<C-r>')
	child.step('q')
	child.settle(100)
	eq(child.lua('return { pcall(require("frogman").save_session, "B") }'), { true })
	child.steps({ OPEN })
	child.type_keys('u')
	eq({ first = first, again = popup().lines[3] }, { first = 's -> ', again = 's -> ' })
end

-- A window's buffer goes once its window closes without its events too, at the cleanup pass that finds it gone.
T['T1125 [char] (M15, DESK.md:1305) a window\'s buffer goes once its window closes without its events'] = function()
	child.steps({ ':e a' })
	child.cmd('split')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e b', OPEN })
	local buf = child.lua('return require("frogman.domains.marks.popup").buffer()')
	child.step('q')
	child.settle(100)
	local kept = child.lua('return vim.api.nvim_buf_is_valid(...)', { buf })
	gone(split)
	eq({ kept = kept, gone = not child.lua('return vim.api.nvim_buf_is_valid(...)', { buf }) }, { kept = true, gone = true })
end


-- A mode key shows a scope's buffer as its scope stands: the tab's buffer, left hidden with no edits, its scope
-- emptied by a load that drew nothing into it, is drawn again as it's shown.
T['T1126 [char] (M15, DESK.md:1305) a mode key draws a hidden buffer again when its scope changed meanwhile'] = function()
	child.steps({ ':e b' })
	eq(child.lua('return { pcall(require("frogman").save_session) }'), { true })
	child.steps({ "<M-'><M-2>", ADD .. 'a>', OPEN, "<M-'><M-1>" })
	child.step('q')
	child.settle(100)
	eq(child.lua('return { pcall(require("frogman").load_session) }'), { true })
	child.settle(300)
	child.steps({ OPEN, "<M-'><M-2>" })
	eq(popup().lines[2], 'a -> ')
end

-- The float closed without its events, by noautocmd: the next mark key does what its close would have, the draft's
-- edits dropped as an undo step, so the key isn't refused; opened again, an undo brings them back.
T['T1127 [char] (M15, DESK.md:1305) a float closed without its events lets its drafts go as its close would'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.steps({ "<M-'><M-2>" })
	child.cmd('noautocmd close!')
	child.settle(100)
	child.messages()
	child.steps({ "<M-'><M-1>", JUMP .. 'a>' })
	local refused = vim.tbl_filter(function(m) return m:find('pop-up', 1, true) ~= nil end, said())
	local shows = child.lua('return vim.fn.expand("%:t")')
	child.steps({ OPEN })
	local reopened = popup().lines[3]
	child.type_keys('u')
	eq({ refused = refused, shows = shows, reopened = reopened, undone = popup().lines[3] },
		{ refused = {}, shows = 'b.txt', reopened = 's -> ', undone = 's -> c.txt' })
end

-- A float that can't open keeps the scope's buffer as Neovim throwing it away would, its lines and undo history,
-- so the next open gives them back.
T['T1128 [char] (M15, DESK.md:1305) a float that can\'t open keeps the scope\'s undo history for the next open'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.cmd('quit!')
	child.settle(100)
	local failed = child.lua([[
		local open_win = vim.api.nvim_open_win
		vim.api.nvim_open_win = function() error('no window here') end
		local ok = pcall(require('frogman.domains.marks.popup').open)
		vim.api.nvim_open_win = open_win
		return not ok
	]])
	child.settle(100)
	child.steps({ OPEN })
	local reopened = popup().lines[3]
	child.type_keys('u')
	eq({ failed = failed, reopened = reopened, undone = popup().lines[3] },
		{ failed = true, reopened = 's -> ', undone = 's -> c.txt' })
end

-- :q! leaves no buffer behind: what Neovim threw away is kept as lines and history, and the buffer goes.
T['T1129 [char] (M15, DESK.md:1305) :q! leaves no unloaded buffer of the pop-up\'s behind'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.cmd('quit!')
	child.settle(100)
	eq(child.lua([[return #vim.tbl_filter(function(b)
		return vim.api.nvim_buf_get_name(b):find('frogman://marks', 1, true) ~= nil
	end, vim.api.nvim_list_bufs())]]), 0)
end


-- A draw that raises as a scope's buffer is made again leaves what was kept of it kept: the next open gives back
-- its lines and undo history.
T['T1130 [char] (M15, DESK.md:1305) a draw that raises as a buffer is made again keeps its history for the next open'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	child.cmd('quit!')
	child.settle(100)
	local failed = child.lua([[
		local R = require('frogman.domains.marks.routines')
		local first_group = R.first_group
		R.first_group = function() error('drawing fails') end
		local ok = pcall(require('frogman.domains.marks.popup').open)
		R.first_group = first_group
		return not ok
	]])
	child.settle(100)
	child.steps({ OPEN })
	local reopened = popup().lines[3]
	child.type_keys('u')
	eq({ failed = failed, reopened = reopened, undone = popup().lines[3] },
		{ failed = true, reopened = 's -> ', undone = 's -> c.txt' })
end


-- Something that asks whether the pop-up holds edits while its float is opening, a WinEnter of the user's, finds it
-- opening, not closed without its events: the open goes through.
T['T1131 [char] (M15, DESK.md:1305) a check of the pop-up while its float opens leaves the open alone'] = function()
	child.steps({ ':e b', ADD .. 'a>', ':e c' })
	child.lua([[vim.api.nvim_create_autocmd("WinEnter", { once = true, callback = function()
		require("frogman.domains.marks.popup").dirty()
	end })]])
	local opened = child.lua('return { pcall(require("frogman.domains.marks.popup").open) }')
	eq({ ok = opened[1], shown = popup() ~= vim.NIL }, { ok = true, shown = true })
end

-- A scope's buffer kept twice, the first given back by an :e! whose draw raised, then thrown away by :q!, leaves no
-- undo file behind once it's made again.
T['T1132 [char] (M15, DESK.md:1305) a scope kept twice leaves no undo file behind'] = function()
	local count = 'return #vim.fn.readdir(vim.fn.fnamemodify(vim.fn.tempname(), ":h"))'
	child.steps({ ':e b', ADD .. 'a>', ':e c', OPEN })
	child.type_keys('3G', 'cc', 's -> c.txt', '<Esc>')
	local before = child.lua(count)
	child.lua([[
		local R = require('frogman.domains.marks.routines')
		local first_group = R.first_group
		R.first_group = function() error('drawing fails') end
		pcall(vim.cmd, 'edit!')
		R.first_group = first_group
	]])
	child.settle(50)
	child.cmd('quit!')
	child.settle(100)
	child.steps({ OPEN })
	child.settle(50)
	eq(child.lua(count), before)
end


-- Review round 9 ------------------------------------------------------------------------------------------

T['T1227 [char] (M15, review round 9) :tabclose typed in the marks pop-up holding edits refuses with E445, the pop-up kept, focused'] = function()
	-- Neovim 0.12.6 loops inside :tabclose with a current float on a modified buffer that can't be hidden, so
	-- the case runs in an editor of its own, killed past ten seconds
	local r = Helpers.spawn_editor([[
vim.cmd('edit a.txt')
vim.cmd('tabnew f.txt')
require('frogman').mark_add('o')
vim.cmd('edit d.txt')
require('frogman').mark_add('o')
require('frogman.settle').drain()
vim.wait(100)

local float = vim.api.nvim_get_current_win()
local before = { float = vim.api.nvim_win_get_config(float).relative ~= '', modified = vim.bo.modified }
local ok, err = pcall(vim.cmd, 'tabclose')
vim.wait(50)
io.stdout:write(vim.json.encode({ before = before, ok = ok, err = tostring(err):match('E%d+') or '',
	tabs = #vim.api.nvim_list_tabpages(), back = vim.api.nvim_get_current_win() == float,
	modified = vim.bo[vim.api.nvim_win_get_buf(float)].modified }) .. '\n')
vim.cmd('qa!')
]])
	local decoded = (r.out ~= '' and pcall(vim.json.decode, r.out)) and vim.json.decode(r.out) or r.out
	eq({ code = r.code, out = decoded }, { code = 0, out = { before = { float = true, modified = true }, ok = false, err = 'E445', tabs = 2, back = true, modified = true } })
end

return T
