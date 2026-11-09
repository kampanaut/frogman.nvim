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
		-- the registry binds by hash; register_buffer gives the file's handle, whose hash it is
		local hash = H.get_hash_from_handle(H.register_buffer(older))
		vim.api.nvim_buf_set_name(older, _G.FRG_TEST.root .. '/moved.txt')
		local newer = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(newer, path)
		local hash2 = H.get_hash_from_handle(H.register_buffer(newer))
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

T['T936 [char] (M2 Handles, A20, DESK.md:832) a move onto a held name hands its notes, its snapshot notes and its visits over before its handle is let go'] = function()
	child.lua('_G.FRG_TEST.setup({ cleanup_interval = 3600000 })')
	child.steps({ ':e c', ':e b', ':e a', ':e d' })
	eq({ child.slots(), child.notes() }, { '⦉a⦊ [d] ⟦-⟧', 'dtm{a>b b>c} dsm{}' })
	child.steps({ '<M-;><M-s>' })
	local a, c = handle('a'), handle('c')
	local a_time = child.lua('return require("frogman.domains.history").data.crux_internals.global[...]', { a.id })
	child.cmd('bwipeout ' .. child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/a.txt")'))
	child.settle(300)
	-- c moved over a.txt on disk, and its buffer, shown nowhere, given a.txt's name
	child.lua([[
		local root = _G.FRG_TEST.root
		os.rename(root .. '/c.txt', root .. '/a.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/c.txt'), root .. '/a.txt')
	]])
	child.settle(300)
	local got = child.lua([[
		local H = require('frogman.domains.history')
		local S = require('frogman.domains.snapshots').routines
		local a, c, a_time = ...
		local snapshot_notes = 0
		for _, s in ipairs(S.of_window(vim.api.nvim_get_current_win())) do
			for _, note in ipairs(s.dtm) do
				local key = S.handle(note.key)
				if key and key.id == c then snapshot_notes = snapshot_notes + 1 end
			end
		end
		return { let_go = H.handles.get(a) == nil, visit = H.data.crux_internals.global[c] == a_time, snapshot_notes = snapshot_notes }
	]], { a.id, c.id, a_time })
	eq({ got = got, notes = child.notes() },
		{ got = { let_go = true, visit = true, snapshot_notes = 1 }, notes = 'dtm{a>b b>a} dsm{}' })
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
		for _, place in ipairs(h and H.handles.holders(h.id) or {}) do
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

-- The Pool class (M5, DESK.md:836): a change that would break one of a list's rules is refused,
-- the list as it was, and dumps, as T695's update is.
T['T923 [char] (M5, I22, DESK.md:836) a change that would put a file twice on a list is refused, and dumps'] = function()
	child.steps({ ':e c', ':e a', ':e b', ':bdelete c.txt' })
	eq(holders('c'), { 'pool:editor' })
	local dumps = child.dump_files()
	local got = child.lua([[
		local H = require('frogman.domains.history')
		local pool = H.routines.pools()['']
		local c = H.get_handle_from_filepath(_G.FRG_TEST.root .. '/c.txt')
		local before = vim.deepcopy(pool.closed)
		local method = type(pool.push_oldest) == 'function'
		local ok = pcall(function() pool:push_oldest(c) end)
		return { method = method, ok = ok, same = vim.deep_equal(before, pool.closed) }
	]])
	child.settle(100)
	eq({ got, child.dumped_since(dumps) ~= nil }, { { method = true, ok = false, same = true }, true })
end

T['T924 [char] (M5, I7, DESK.md:836) a change that would put an open file on a list is refused, and dumps'] = function()
	child.steps({ ':e c', ':e a', ':e b', ':bdelete c.txt' })
	local dumps = child.dump_files()
	local got = child.lua([[
		local H = require('frogman.domains.history')
		local pool = H.routines.pools()['']
		local b = H.get_handle_from_filepath(_G.FRG_TEST.root .. '/b.txt') -- open, the window's current
		local before = vim.deepcopy(pool.closed)
		local method = type(pool.push) == 'function'
		local ok = pcall(function() pool:push(b) end)
		return { method = method, ok = ok, same = vim.deep_equal(before, pool.closed) }
	]])
	child.settle(100)
	eq({ got, child.dumped_since(dumps) ~= nil }, { { method = true, ok = false, same = true }, true })
end

-- Every line of the code but the class's own module that writes a list's closed files or close times,
-- or the editor's old field: the session file's own fields, a step's flag and the closed lists' own
-- record of what they drew aren't a list's.
local LIST_WRITES = {
	'%.closed%s*%[[^%]]*%]%s*=[^=]', 'table%.insert%(%s*[^,]-%.closed%s*,', 'table%.remove%(%s*[^,]-%.closed%s*[,)]',
	'list_extend%(%s*[^,]-%.closed%s*,', '%.times%s*%[[^%]]*%]%s*=[^=]',
	'data%.closed_buffers', 'corpus%.closed_buffers', '^%s*closed_buffers%s*=',
}
local NOT_A_LIST = {
	['lua/frogman/domains/storage/routines.lua'] = {
		'storage.closed = vim.tbl_filter(keeps, storage.closed or {})', -- the session file's policy
		'list.closed = vim.tbl_filter(keeps, list.closed or {})', -- the same, a detached list in the file
		'saved.closed, saved.closed_times = serialise_closed_buffers(session.pools)', -- a records write's file
		'list.closed, list.closed_times = change.closed, change.times', -- a list in that file alone
		'list.closed, list.closed_times = was.closed, was.closed_times', -- the switch's write, a detached list as its file has it
	},
	['lua/frogman/domains/ledger/routines.lua'] = { 'step.closed = true' }, -- a step closed, no list
	['lua/frogman/domains/ui/routines.lua'] = {
		'picker.refs, picker.filetypes, picker.times, picker.drawn = refs, filetypes, times, drawn', -- what it drew
	},
}

-- Whether a line assigns a list's closed files or close times: one of its targets, before its first
-- `=`, is a field named `closed` or `times`.
local function assigns(code)
	local targets = code:match('^%s*([%w_%.%[%]%s,]-)%s*=[^=]')
	for target in (targets or ''):gmatch('[^,]+') do
		if vim.trim(target):match('%.closed$') or vim.trim(target):match('%.times$') then
			return true
		end
	end
	return false
end

T['T925 [char] (M5, DESK.md:836) every write to a list goes through the Pool class'] = function()
	local found = {}
	for _, path in ipairs(vim.fs.find(function(name) return name:match('%.lua$') ~= nil end,
			{ path = 'lua/frogman', type = 'file', limit = math.huge })) do
		local rel = path:match('(lua/frogman/.*)$')
		if not rel:match('domains/history/pool%.lua$') then
			local n = 0
			for line in io.lines(path) do
				n = n + 1
				local code = line:gsub('%-%-.*$', '')
				local named = false
				for _, ok in ipairs(NOT_A_LIST[rel] or {}) do
					if vim.trim(code) == ok then named = true end
				end
				if not named then
					local hit = assigns(code)
					for _, pattern in ipairs(LIST_WRITES) do
						hit = hit or code:match(pattern) ~= nil
					end
					if hit then
						table.insert(found, rel .. ':' .. n)
					end
				end
			end
		end
	end
	table.sort(found)
	eq({ module = vim.uv.fs_stat('lua/frogman/domains/history/pool.lua') ~= nil, writes = found }, { module = true, writes = {} })
end

T['T935 [char] (M2 Holders, A22, DESK.md:832, :846) the scan is gone: nothing names follow_along or is_handle_referenced, and the cleanup pass forgets nothing'] = function()
	local found = {}
	for _, path in ipairs(vim.fs.find(function(name) return name:match('%.lua$') ~= nil end,
			{ path = 'lua/frogman', type = 'file', limit = math.huge })) do
		local rel = path:match('(lua/frogman/.*)$')
		local n = 0
		for line in io.lines(path) do
			n = n + 1
			local code = line:gsub('%-%-.*$', '')
			for _, name in ipairs({ 'follow_along', 'is_handle_referenced' }) do
				if code:find(name, 1, true) then table.insert(found, rel .. ':' .. n .. ' ' .. name) end
			end
		end
	end
	-- the cleanup pass forgets nothing: a file is forgotten by its let-go alone
	local routines = table.concat(vim.fn.readfile('lua/frogman/domains/history/routines.lua'), '\n')
	local cleanup = routines:match('\nfunction M%.cleanup_system%(.-\nend\n') or ''
	for _, name in ipairs({ 'unregister_filepath', 'let_go', 'orphaned' }) do
		if cleanup:gsub('%-%-[^\n]*', ''):find(name, 1, true) then table.insert(found, 'cleanup_system ' .. name) end
	end
	table.sort(found)
	eq({ cleanup = cleanup ~= '', found = found }, { cleanup = true, found = {} })
end

T['T927 [char] (M5, DESK.md:836) clear_closed_buffers() empties the editor\'s list in place'] = function()
	child.steps({ ':e c', ':e a', ':e b', ':bdelete c.txt' })
	local got = child.lua([[
		local H = require('frogman.domains.history')
		local before = H.routines.pools()['']
		H.clear_closed_buffers()
		local after = H.routines.pools()['']
		return { same = rawequal(before, after), empty = #after.closed == 0, field = H.data.closed_buffers == nil,
			read = #H.get_closed_buffers() }
	]])
	eq(got, { same = true, empty = true, field = true, read = 0 })
end

T['T932 [char] (M5, DESK.md:832) a file let go takes what it remembers of its lists with it'] = function()
	child.lua('_G.FRG_TEST.setup({ cleanup_interval = 3600000 })')
	child.steps({ ':e a' })
	child.cmd('enew')
	local n = child.lua('return vim.api.nvim_get_current_buf()')
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "draft" })')
	child.settle()
	child.steps({ ':e b' })
	-- the text closed onto the editor's list, then reopened off it, which remembers the list for its next close
	child.cmd('bdelete! ' .. n)
	child.settle(100)
	child.steps({ '<M-S-w>' })
	local id = child.lua('return require("frogman.domains.history").get_handle_from_buffer(vim.api.nvim_get_current_buf())')
	local remembered = child.lua('return require("frogman.domains.history").data.came_from[...] ~= nil', { id })
	-- emptied and closed: an empty text goes on no list, so no close clears what it remembers, and nothing holds it
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, {})')
	child.cmd('bdelete!')
	child.settle(300)
	local got = child.lua([[
		local H = require('frogman.domains.history')
		return { live = H.handles.get(...) ~= nil, remembers = H.data.came_from[...] ~= nil }
	]], { id })
	eq({ remembered = remembered, got = got }, { remembered = true, got = { live = false, remembers = false } })
end

T['T696 [char] (M6 Triquetra) a copy of a triquetra holds nothing'] = function()
	child.steps({ ':e c', ':e a', ':e b', ':bdelete c.txt' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	eq(holders('c'), { 'pool:editor' })
	child.lua([[
		local H = require('frogman.domains.history')
		local t = require('frogman.domains.window').data.crux[vim.api.nvim_get_current_win()]
		local copy = vim.deepcopy(t)
		copy:set('ternary_slot', H.get_handle_from_filepath(_G.FRG_TEST.root .. '/c.txt'))
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

T['T877 [char] (M2 Holders) two lists whose ids read alike with the newline a space hold apart'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':bdelete a.txt', ':bdelete b.txt' })
	local held = child.lua([[
		local H = require('frogman.domains.history')
		local Pool = require('frogman.domains.history.pool')
		local root = _G.FRG_TEST.root
		local a, b = H.get_handle_from_filepath(root .. '/a.txt'), H.get_handle_from_filepath(root .. '/b.txt')
		Pool.new({ id = 'x /a\n/b' }):push(a, nil, true) -- closed, so a list can hold them
		Pool.new({ id = 'x\n/a /b' }):push(b, nil, true)
		local function lists(id)
			local n = 0
			for _, place in ipairs(H.handles.holders(id)) do if place:match('^pool:x') then n = n + 1 end end
			return n
		end
		return { a = lists(a), b = lists(b) }
	]])
	eq(held, { a = 1, b = 1 })
end

T['T878 [char] (M2 Handles) a teardown forgets the moves'] = function()
	child.steps({ ':e a', ':e b' })
	local a, b = handle('a'), handle('b')
	child.cmd('bwipeout ' .. child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/a.txt")'))
	child.settle(300)
	child.lua([[
		local root = _G.FRG_TEST.root
		os.rename(root .. '/b.txt', root .. '/a.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/b.txt'), root .. '/a.txt')
	]])
	child.settle(300)
	local function resolved() return child.lua('return require("frogman.domains.history").handles.resolve(...)', { a.id }) end
	local before = resolved()
	child.lua('pcall(require("frogman").load_session, "nothing")')
	child.settle(300)
	eq({ before = before, after = resolved() }, { before = b.id, after = a.id })
end

T['T880 [char] (M6 Triquetra) a slot\'s write holds its own place alone'] = function()
	child.steps({ ':e c', ':e a', ':e b' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	local writes = child.lua([[
		local H = require('frogman.domains.history')
		local hold, places = H.handles.hold, {}
		H.handles.hold = function(place, ...) table.insert(places, place); return hold(place, ...) end
		local t = require('frogman.domains.window').data.crux[vim.api.nvim_get_current_win()]
		t:set('ternary_slot', H.get_handle_from_filepath(_G.FRG_TEST.root .. '/c.txt'))
		H.handles.hold = hold
		return #places
	]])
	eq(writes, 1)
end

T['T937 [char] (M2 Holders, DESK.md:832) a handle held by nothing is let go even when its path is gone already'] = function()
	child.lua('_G.FRG_TEST.setup({ cleanup_interval = 3600000 })')
	child.steps({ ':e b', ':e a' })
	local b = handle('b')
	-- b's path pair dropped by hand, as only a bug drops it, its buffer still registered: the window pass
	-- empties its slot and unregisters its buffer, so nothing holds it any more (T910's route)
	child.lua([=[
		local reg = require('frogman.domains.history').data.hash_filepath_registry
		reg.hashes[reg.filepaths[...]] = nil
		reg.filepaths[...] = nil
		require('frogman.domains.window.routines').enforce_editor_policy()
	]=], { b.hash })
	child.settle(100)
	eq(child.lua('return require("frogman.domains.history").handles.get(...) == nil', { b.id }), true)
end

T['T699 [char] (M2 Holders) a file let go and held again in one batch is kept'] = function()
	child.steps({ ':e a' })
	local got = child.lua([[
		local H = require('frogman.domains.history')
		local path = _G.FRG_TEST.root .. '/x.txt'
		H.register_filepath(path)
		local x = H.get_hash_from_filepath(path)
		H.routines.track_closing_handle_force(H.get_handle_from_hash(x))
		vim.wait(50)
		local id = H.handles.of_hash(x).id
		H.routines.discard_from_pools(id)
		H.routines.track_closing_handle_force(id)
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

T['T895 [char] (M2 Handles, DESK.md:830) a move and a No Name text\'s reopen leave every consumer holding what it held'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	local a, b = handle('a'), handle('b')
	child.lua([[
		local root = _G.FRG_TEST.root
		os.rename(root .. '/a.txt', root .. '/g.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/a.txt'), root .. '/g.txt')
	]])
	child.settle(300)
	local held = child.lua([[
		local H = require('frogman.domains.history')
		local t = require('frogman.domains.window').data.crux[vim.api.nvim_get_current_win()]
		local b, a = ...
		return { note = t.displacement_ternary_map[b] or false, global = H.data.crux_internals.global[a] ~= nil,
			slots = { type(t.current_slot), type(t.ternary_slot) } }
	]], { b.id, a.id })
	eq({ held, handle('g').id }, { { note = a.id, global = true, slots = { 'number', 'number' } }, a.id })
	-- a No Name text closed and reopened keeps its handle, and the split holding it holds it still
	child.cmd('vsplit')
	child.steps({ ':enew' })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "n" })')
	child.settle()
	local n = handle(child.lua('return vim.api.nvim_get_current_buf()'))
	child.steps({ '<M-.>', '<M-S-w>' })
	local after = child.lua([[
		local H = require('frogman.domains.history')
		local t = require('frogman.domains.window').data.crux[vim.api.nvim_get_current_win()]
		return { current = t.current_slot, hash = H.get_hash_from_buffer(vim.api.nvim_get_current_buf()) }
	]])
	eq({ after.current, after.hash ~= n.hash }, { n.id, true })
end

T['T900 [char] (M2 Handles, M11, DESK.md:844, :847) every handle transition runs the ledger\'s hook last, and no two of its hooks share a class'] = function()
	local got = child.lua([[
		local helpers = require('frogman.engine.helpers')
		local model = require('frogman.domains.history.handles').model
		local cases = { { 'open', 'closed' }, { 'closed', 'open' } }
		for _, mode in ipairs({ 'rename', 'vanish', 'return', 'copy', 'forget' }) do
			table.insert(cases, { 'open', 'open', mode })
			table.insert(cases, { 'closed', 'closed', mode })
		end
		local out = {}
		for _, c in ipairs(cases) do
			local ok, pipeline = pcall(helpers.compute_transition_pipeline, c[1], c[2], c[3] or '*', model)
			local last, classes, shared = 'none', {}, false
			for _, hook in ipairs(ok and pipeline or {}) do
				last = hook.name
				shared = shared or classes[hook.class] ~= nil
				classes[hook.class] = true
			end
			table.insert(out, c[1] .. '->' .. c[2] .. ' ' .. (c[3] or '') .. ': ' .. last .. (shared and ', a shared class' or ''))
		end
		return out
	]])
	local want = vim.tbl_map(function(line) return (line:gsub(': .*$', ': trail_move')) end, got)
	eq(got, want)
end

T['T931 [char] (M2 Holders, M11, DESK.md:832) a let-go runs one hook for each weak holder, each in a class of its own, between the fields and the trail'] = function()
	local got = child.lua([[
		local helpers = require('frogman.engine.helpers')
		local model = require('frogman.domains.history.handles').model
		local out = {}
		for _, state in ipairs({ 'open', 'closed' }) do
			out[state] = {}
			for _, hook in ipairs(helpers.compute_transition_pipeline(state, state, 'forget', model)) do
				table.insert(out[state], hook.name .. ':' .. hook.class)
			end
		end
		return out
	]])
	local weak = { 'notes_let_go:2', 'arrivals_let_go:3', 'history_let_go:4', 'visits_let_go:5', 'came_from_let_go:6',
		'snapshot_notes_let_go:7', 'display_name_let_go:8', 'trail_move:9' }
	eq(got, {
		open = vim.list_extend({ 'keep_fields_while_open:1' }, vim.deepcopy(weak)),
		closed = vim.list_extend({ 'keep_fields_while_closed:1' }, vim.deepcopy(weak)),
	})
end

T['T901 [char] (M11, DESK.md:849) a handle goes by its file\'s unique name in a message'] = function()
	child.lua([[
		local root = _G.FRG_TEST.root
		for _, d in ipairs({ 'sub1', 'sub2' }) do
			vim.fn.mkdir(root .. '/' .. d, 'p')
			vim.fn.writefile({ d }, root .. '/' .. d .. '/init.lua')
		end
	]])
	child.steps({ ':e sub1/init.lua', ':e sub2/init.lua', ':e a' })
	child.lua([[
		require('frogman.domains.history.handles').model:on('open', 'closed', 'fails_on_close', function() error('planted') end, 50, true)
	]])
	child.messages()
	child.cmd('bdelete sub1/init.lua')
	child.settle(100)
	local said
	for _, m in ipairs(child.messages()) do
		if m.msg:find('fails_on_close', 1, true) then said = said or m.msg end
	end
	eq(said ~= nil and said:find('of sub1/init.lua', 1, true) ~= nil, true)
end

return T
