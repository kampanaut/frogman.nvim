-- Frogman's marks (M15). IDs are the spec's (what-is-frogman.md, section 7).
local Helpers = dofile('tests/helpers.lua')
local S2 = dofile('tests/helpers_s2.lua')
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

return T
