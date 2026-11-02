-- Identity, registry and tracking (M1-M3). IDs are the spec's
-- (what-is-frogman.md, section 7).
local Helpers = dofile('tests/helpers.lua')
local eq = Helpers.eq
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = child.stop,
	},
})

-- Is the current buffer registered?
local function registered()
	return child.lua([[
		return require('frogman.domains.history').get_hash_from_buffer(vim.api.nvim_get_current_buf()) ~= nil
	]])
end

T['T8 [char] the hash of a plain path is the first 16 hex characters of sha256(path .. "\\n")'] = function()
	child.steps({ ':e a' })
	local got = child.lua([[
		local H = require('frogman.domains.history')
		local path = vim.api.nvim_buf_get_name(0)
		return { H.get_hash_from_buffer(vim.api.nvim_get_current_buf()), vim.fn.sha256(path .. '\n'):sub(1, 16) }
	]])
	eq(got[1], got[2])
end

T['T9 [char] a path with ", $HOME or a backslash hashes to sha256(path .. "\\n")'] = function()
	child.steps({ ':e a' })
	-- Only hashes come back, keyed by a label, never the paths. The backslash
	-- name has two in a row, which the shell's double quotes fold into one.
	local got = child.lua([[
		local H = require('frogman.domains.history')
		local names = { quote = 'q"uote.txt', dollar_home = '$HOME.txt', backslash = 'back\\\\slash.txt' }
		local got, want = {}, {}
		for label, n in pairs(names) do
			local path = _G.FRG_TEST.root .. '/' .. n
			vim.fn.writefile({ label }, path)
			vim.cmd('edit ' .. vim.fn.fnameescape(path))
			vim.wait(10) -- the arrival is slotted once the editor settles
			got[label] = H.get_hash_from_buffer(vim.api.nvim_get_current_buf()) or 'not registered'
			want[label] = vim.fn.sha256(vim.api.nvim_buf_get_name(0) .. '\n'):sub(1, 16)
		end
		return { got = got, want = want }
	]])
	eq(got.got, got.want)
end

T['T10 [char] :e registers a file; help, terminal, scheme:// and otter\'s unlisted buffers are not registered'] = function()
	child.lua([[vim.o.shell = 'sh']])
	local got = {}
	child.steps({ ':e a' })
	got.file = registered()

	child.cmd('help')
	child.settle()
	got.help = registered()
	child.cmd('close')

	child.cmd('terminal')
	child.settle(100)
	got.terminal = registered()
	child.steps({ ':e a' })

	child.cmd('edit scheme://some/thing')
	child.settle()
	got.scheme = registered()

	-- otter makes its buffers with vim.uri_to_bufnr, which leaves them unlisted; listed-only
	-- tracking is what keeps them out, not their name.
	child.lua([[
		local b = vim.uri_to_bufnr(vim.uri_from_fname(vim.fn.getcwd() .. '/sub/otter.lua'))
		vim.api.nvim_set_current_buf(b)
	]])
	child.settle()
	got.otter = registered()

	eq(got, { file = true, help = false, terminal = false, scheme = false, otter = false })
end

T['T11 [char] an entered No Name buffer is registered as NONAME_<id>, its id kept on the buffer (I16)'] = function()
	child.steps({ ':e a', ':enew' })
	local got = child.lua([[
		local H = require('frogman.domains.history')
		local buf = vim.api.nvim_get_current_buf()
		local hash = H.get_hash_from_buffer(buf)
		return { path = hash and H.get_filepath_from_hash(hash), want = 'NONAME_' .. tostring(vim.b[buf].frogman_noname) }
	]])
	eq(got.path, got.want)
	eq(got.path ~= 'NONAME_' .. child.lua('return vim.api.nvim_get_current_buf()'), true)
end

T['T12 [char] registering a second buffer under the same hash binds it to the newer one'] = function()
	child.steps({ ':e a' })
	-- Names change with autocmds off, so only register_buffer touches the registry.
	local got = child.lua([[
		local H = require('frogman.domains.history')
		local reg = H.data.hash_buffer_registry
		local path = _G.FRG_TEST.root .. '/same.txt'
		vim.o.eventignore = 'all'
		local older = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(older, path)
		local hash = H.register_buffer(older)
		vim.api.nvim_buf_set_name(older, _G.FRG_TEST.root .. '/moved.txt')
		local newer = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(newer, path)
		local hash2 = H.register_buffer(newer)
		vim.o.eventignore = ''
		return {
			distinct = older ~= newer,
			same_hash = hash == hash2,
			bound_to_newer = reg.buffers[hash] == newer,
			newer_reverse = reg.hashes[newer] == hash,
			older_reverse = reg.hashes[older] or 'dropped',
		}
	]])
	eq(got, { distinct = true, same_hash = true, bound_to_newer = true, newer_reverse = true, older_reverse = 'dropped' })
end

T['T13 [char] an unlisted buftype "" buffer that a plugin creates and enters is not registered'] = function()
	child.steps({ ':e a' })
	child.lua([[
		local buf = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_set_current_buf(buf)
	]])
	child.settle()
	eq(child.lua('return vim.bo.buflisted'), false)
	eq(child.lua('return vim.bo.buftype'), '')
	eq(registered(), false)
end

T['T14 [char] a buffer whose file is not written yet stays registered after it is left and re-entered'] = function()
	child.steps({ ':e a', ':e brandnew.txt' })
	local first = child.lua([[
		local H = require('frogman.domains.history')
		local buf = vim.api.nvim_get_current_buf()
		return { buf = buf, hash = H.get_hash_from_buffer(buf) }
	]])
	Helpers.expect.no_equality(first.hash, nil)
	local bound = function()
		return child.lua('return require("frogman.domains.history").data.hash_buffer_registry.buffers[...]', { first.hash })
	end

	child.steps({ ':e a' })
	eq(bound(), first.buf)

	child.steps({ ':e brandnew.txt' })
	eq(child.lua('return vim.api.nvim_get_current_buf()'), first.buf)
	eq(bound(), first.buf)
end

-- Handles (M2 Handles) -------------------------------------------------------

-- A handle as the case reads it: its number, state, gone flag and copy link,
-- and whether it's live. `of` is a file's stem in the project, or a buffer
-- number for the buffer's own handle; false when there's none.
local function handle(of)
	return child.lua([[
		local H = require('frogman.domains.history')
		local of = ...
		local hash
		if type(of) == 'number' then
			hash = H.get_hash_from_buffer(of)
		else
			hash = H.routines.get_filehash(_G.FRG_TEST.root .. '/' .. of .. '.txt')
		end
		local h = hash and H.handles.of_hash(hash)
		if not h then return false end
		return { id = h.id, hash = h.hash, state = h:state(), gone = h.gone, copy_of = h.copy_of or false,
			live = H.handles.get(h.id) == h }
	]], { of })
end

-- Every live handle as `<stem>:<state>`, sorted, a No Name text as NONAME.
local function live_handles()
	return child.lua([[
		local H = require('frogman.domains.history')
		local out = {}
		for _, h in pairs(H.handles.live()) do
			local path = H.get_filepath_from_hash(h.hash) or '?'
			local stem = path:match('^NONAME_') and 'NONAME' or vim.fn.fnamemodify(path, ':t:r')
			table.insert(out, stem .. ':' .. h:state())
		end
		table.sort(out)
		return out
	]])
end

T['T682 [char] (M2 Handles) a name that comes back while its handle lives gets it back'] = function()
	child.steps({ ':e a', ':e b', ':bdelete a.txt' })
	local a, b = handle('a'), handle('b')
	eq({ a.state, a.live, child.closed() }, { 'closed', true, 'a' })
	child.steps({ ':e a' })
	local again = handle('a')
	eq({ again.id, again.state, again.live }, { a.id, 'open', true })
	eq(b.id ~= a.id, true)
end

T['T683 [char] (M2 Handles) a file forgotten gets a fresh handle, above every handle before it'] = function()
	local S2 = dofile('tests/helpers_s2.lua')
	child.steps({ ':e a', ':e b', ':e c', ':e d', ':bdelete a.txt' })
	local a = handle('a')
	local top = child.lua('local m = 0; for id in pairs(require("frogman.domains.history").handles.live()) do m = math.max(m, id) end; return m')
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, S2.line_of(lines, 'a.txt'))
	S2.write_picker(child, p, lines)
	child.cmd('close')
	child.lua('require("frogman.domains.history").routines.cleanup_system()')
	eq({ handle('a'), child.lua('return require("frogman.domains.history").handles.get(...) == nil', { a.id }) }, { false, true })
	child.steps({ ':e a' })
	local fresh = handle('a')
	eq({ fresh.state, fresh.id > top }, { 'open', true })
end

T['T684 [char] (M2 Handles, A20) a move keeps the handle'] = function()
	child.steps({ ':e a', ':e b' })
	local b = handle('b')
	child.lua([[
		local root = _G.FRG_TEST.root
		os.rename(root .. '/b.txt', root .. '/g.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/b.txt'), root .. '/g.txt')
	]])
	child.settle(300)
	local g = handle('g')
	eq({ g.id, g.state, g.hash ~= b.hash, handle('b') }, { b.id, 'open', true, false })
end

T['T685 [char] (M2 Handles, M14) gone from disk flips the handle\'s field'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':bdelete b.txt' })
	local b = handle('b')
	eq(b.gone, false)
	child.lua([[
		os.remove(_G.FRG_TEST.root .. '/b.txt')
		require('frogman.domains.history').routines.cleanup_system()
	]])
	local gone = handle('b')
	eq({ gone.id, gone.state, gone.gone }, { b.id, 'closed', true })
	child.lua([[
		vim.fn.writefile({ 'b' }, _G.FRG_TEST.root .. '/b.txt')
		require('frogman.domains.history').routines.cleanup_system()
	]])
	local back = handle('b')
	eq({ back.id, back.state, back.gone }, { b.id, 'closed', false })
end

T['T686 [char] (M2 Handles) every path has one live handle, and every live handle a path'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':bdelete b.txt', ':e brandnew.txt' })
	local paths = child.lua([[
		local out = {}
		for _, path in pairs(require('frogman.domains.history').data.hash_filepath_registry.filepaths) do
			table.insert(out, vim.fn.fnamemodify(path, ':t:r'))
		end
		table.sort(out)
		return out
	]])
	eq(paths, { 'a', 'b', 'brandnew', 'c' })
	eq(live_handles(), { 'a:open', 'b:closed', 'brandnew:open', 'c:open' })
end

T['T687 [char] (M2 Handles, M5) a No Name text reopened keeps its handle'] = function()
	child.steps({ ':e a', ':enew' })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "draft" })')
	local n = handle(child.lua('return vim.api.nvim_get_current_buf()'))
	child.steps({ '<M-.>' })
	eq(handle(child.lua('return vim.api.nvim_get_current_buf()')).state, 'open') -- landed on a
	child.steps({ '<M-S-w>' })
	eq(child.lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'draft' })
	local back = handle(child.lua('return vim.api.nvim_get_current_buf()'))
	eq({ back.id, back.state, back.hash ~= n.hash }, { n.id, 'open', true })
end

T['T688 [char] (M2 Handles, A20) a move onto a name a live handle has: the moved file wins'] = function()
	child.steps({ ':e a', ':e b' })
	local a, b = handle('a'), handle('b')
	child.cmd('bwipeout ' .. child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/a.txt")'))
	child.settle(300)
	eq(handle('a').state, 'closed')
	child.lua([[
		local root = _G.FRG_TEST.root
		os.rename(root .. '/b.txt', root .. '/a.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/b.txt'), root .. '/a.txt')
	]])
	child.settle(300)
	local now = handle('a')
	eq({ now.id, now.state }, { b.id, 'open' })
	eq(child.lua('return require("frogman.domains.history").handles.get(...) == nil', { a.id }), true)
end

T['T689 [char] (M2 Handles, A20) a copy makes a new handle linked to the old'] = function()
	child.steps({ ':e a', ':e b' })
	local b = handle('b')
	child.cmd('saveas g.txt')
	child.settle(300)
	local g = handle('g')
	eq({ g.id > b.id, g.copy_of, g.state, handle('b').state, handle('b').id }, { true, b.id, 'open', 'closed', b.id })
end

T['T690 [char] (M2 Handles) what isn\'t registered gets no handle'] = function()
	child.steps({ ':e a' })
	child.lua([[
		local win = vim.api.nvim_get_current_win()
		vim.cmd('help')
		vim.api.nvim_set_current_win(win)
		vim.cmd('copen')
		vim.api.nvim_set_current_win(win)
		local buf = vim.api.nvim_create_buf(true, false)
		vim.bo[buf].buftype = 'acwrite'
		vim.api.nvim_buf_set_name(buf, 'oil://' .. _G.FRG_TEST.root .. '/')
		vim.api.nvim_win_set_buf(win, buf)
	]])
	child.settle(100)
	eq(live_handles(), { 'a:open' })
end

T['T691 [char] (M2 Handles, S1) a load mints fresh handles, above every handle before it'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	local ids = 'local out = {}; for id in pairs(require("frogman.domains.history").handles.live()) do table.insert(out, id) end; table.sort(out); return out'
	local before = child.lua(ids)
	eq(#before, 3)
	child.lua('require("frogman").save_session("t691")')
	child.settle()
	child.lua('require("frogman").load_session("t691")')
	child.settle(100)
	local after = child.lua(ids)
	eq(#after >= 3, true)
	eq(after[1] > before[#before], true)
end

-- Holders (M2 Holders, M6 Triquetra) ------------------------------------------

-- The places holding a file, by its stem, sorted, the window's id written <w>.
local function holders(stem)
	return child.lua([[
		local H = require('frogman.domains.history')
		local h = H.handles.of_hash(H.routines.get_filehash(_G.FRG_TEST.root .. '/' .. ... .. '.txt'))
		local w = tostring(vim.api.nvim_get_current_win())
		local out = {}
		for _, place in ipairs(h and H.handles.holders(h.hash) or {}) do
			table.insert(out, (place:gsub(':' .. w .. ':', ':<w>:')))
		end
		table.sort(out)
		return out
	]], { stem })
end

T['T693 [char] (M2 Holders) strong holders hold by place'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':bdelete a.txt' })
	eq(holders('a'), { 'pool:editor' })
	eq(holders('b'), { 'buffer', 'win:<w>:ternary' })
	eq(holders('c'), { 'buffer', 'win:<w>:current' })
	child.steps({ '<M-;><M-c>' })
	eq(holders('c'), { 'buffer', 'win:<w>:current', 'win:<w>:primary' })
end

T['T695 [char] (M6 Triquetra) an update that would leave a file in two slots is refused, and dumps'] = function()
	child.steps({ ':e a', ':e b' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	local dumps = child.dump_files()
	local ok = child.lua([[
		local t = require('frogman.domains.window').data.crux[vim.api.nvim_get_current_win()]
		return (pcall(t.update, t, { secondary_slot = t.current_slot }))
	]])
	child.settle(100)
	eq({ ok, child.slots(), child.dumped_since(dumps) ~= nil }, { false, '⦉a⦊ [b] ⟦-⟧', true })
end

T['T696 [char] (M6 Triquetra) a copy of a triquetra holds nothing'] = function()
	child.steps({ ':e c', ':e a', ':e b', ':bdelete c.txt' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	eq(holders('c'), { 'pool:editor' })
	child.lua([[
		local H = require('frogman.domains.history')
		local t = require('frogman.domains.window').data.crux[vim.api.nvim_get_current_win()]
		local copy = vim.deepcopy(t)
		copy:set('ternary_slot', H.routines.get_filehash(_G.FRG_TEST.root .. '/c.txt'))
	]])
	eq({ holders('c'), child.slots() }, { { 'pool:editor' }, '⦉a⦊ [b] ⟦-⟧' })
end

-- With the cleanup timer at an hour, its first tick ran at the setup, and none comes after.
T['T698 [char] (M2 Holders, P10) a file no holder holds is forgotten once the editor settles, with no cleanup pass'] = function()
	local S2 = dofile('tests/helpers_s2.lua')
	child.lua('_G.FRG_TEST.setup({ cleanup_interval = 3600000 })')
	child.steps({ ':e a', ':e b', ':e c', ':e d', ':bdelete a.txt' })
	local a = handle('a')
	eq(child.notes(), 'dtm{b>a c>b} dsm{}')
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, S2.line_of(lines, 'a.txt'))
	-- written through the picker's own write key, which begins a step of its own
	child.lua('vim.api.nvim_buf_set_lines(..., 0, -1, false, select(2, ...))', { p.buf, lines })
	child.step('<C-s>')
	child.settle(100)
	child.cmd('close')
	local got = child.lua([[
		local H = require('frogman.domains.history')
		local forgotten = false
		for _, st in ipairs(require('frogman').ledger.trail()) do
			for _, m in ipairs(st.moves) do
				if m.kind == 'forgotten' and m.subject == ... then forgotten = st.trigger end
			end
		end
		return {
			path = H.get_filepath_from_hash(...) ~= nil,
			live = H.handles.get(select(2, ...)) ~= nil,
			forgotten = forgotten,
		}
	]], { a.hash, a.id })
	eq({ got = got, notes = child.notes() }, { got = { path = false, live = false, forgotten = '<C-s>' }, notes = 'dtm{c>b} dsm{}' })
end

T['T699 [char] (M2 Holders) a file let go and held again in one batch is kept'] = function()
	child.steps({ ':e a' })
	local got = child.lua([[
		local H = require('frogman.domains.history')
		local path = _G.FRG_TEST.root .. '/x.txt'
		H.register_filepath(path)
		local x = H.get_hash_from_filepath(path)
		H.routines.track_closing_filehash_force(x)
		vim.wait(50)
		local id = H.handles.of_hash(x).id
		H.routines.discard_from_pools(x)
		H.routines.track_closing_filehash_force(x)
		return { x = x, id = id }
	]])
	child.settle(100)
	local after = child.lua([[
		local H = require('frogman.domains.history')
		local h = H.handles.of_hash(...)
		return { path = H.get_filepath_from_hash(...) ~= nil, id = h and h.id or false }
	]], { got.x })
	eq(after, { path = true, id = got.id })
end

return T
