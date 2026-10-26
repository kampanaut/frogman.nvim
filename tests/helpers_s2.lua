-- Extra helpers for the cases on the decided session file, S2
-- (tests/test_s2.lua). They sit on top of tests/helpers.lua's child and
-- tests/helpers_misc.lua, which they use unchanged, and are candidates for the
-- shared helpers.

local Misc = dofile('tests/helpers_misc.lua')

local S2 = {}

-- Projects and children ---------------------------------------------------------

-- A project and a session directory that outlive the children.
S2.shared = function()
	return { root = Misc.make_project(), session_dir = Misc.make_session_dir() }
end

-- A fresh child in the shared project (or opts.root), with the shared session
-- directory. opts also takes child.setup's (history_view, no_cokeline).
S2.start = function(child, s, opts)
	opts = vim.deepcopy(opts or {})
	opts.root = opts.root or s.root
	opts.session_dir = s.session_dir
	Misc.start(child, opts)
end

-- A fresh child started as Neovim's :restart starts one: v:startreason is
-- "restart". Neovim 0.12 passes that to the new server through the
-- __NVIM_STARTREASON environment variable (an undocumented internal), which
-- the child inherits from the test runner here.
S2.start_restarted = function(child, s, opts)
	vim.env.__NVIM_STARTREASON = 'restart'
	local ok, err = pcall(S2.start, child, s, opts)
	vim.env.__NVIM_STARTREASON = nil
	if not ok then error(err, 0) end
end

-- save_session / load_session with exactly these arguments; { ok, err }.
S2.save = function(child, ...)
	return child.lua('return { pcall(require("frogman").save_session, ...) }', { ... })
end
S2.load = function(child, ...)
	return child.lua('return { pcall(require("frogman").load_session, ...) }', { ... })
end

-- The whole editor's directory, as the child sees it.
S2.cwd = function(child)
	return child.lua('return vim.fn.getcwd(-1, -1)')
end

-- How many loads the storage machine has run.
S2.loads = function(child)
	return child.lua([[
		local n = 0
		for _, t in ipairs(require('frogman.domains.storage').sm.history) do
			if tostring(t):match('%->loading$') then n = n + 1 end
		end
		return n
	]])
end

-- { nav = navigation state, hist = history state }.
S2.states = function(child)
	return child.lua([[return {
		nav = require('frogman.domains.navigation').sm:state(),
		hist = require('frogman.domains.history').sm:state(),
	}]])
end

-- Is the buffer on `stem`.txt registered?
S2.registered = function(child, stem)
	return child.lua([[
		local b = vim.fn.bufnr(_G.CDV_TEST.root .. '/' .. ... .. '.txt')
		return b ~= -1 and require('frogman.domains.history').get_hash_from_buffer(b) ~= nil
	]], { stem })
end

-- :enew, then `lines` (and the filetype `ft`) in the new No Name buffer.
-- Returns its buffer number.
S2.noname = function(child, lines, ft)
	child.cmd('enew')
	local buf = child.lua([[
		local lines, ft = ...
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
		if ft then vim.bo.filetype = ft end
		return vim.api.nvim_get_current_buf()
	]], { lines, ft })
	child.settle()
	return buf
end

-- How many buffers hold a line that reads exactly `text`.
S2.holding = function(child, text)
	return child.lua([[
		local n = 0
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(b) and vim.tbl_contains(vim.api.nvim_buf_get_lines(b, 0, -1, false), ...) then
				n = n + 1
			end
		end
		return n
	]], { text })
end

-- The first buffer holding a line that reads exactly `text`, or nil.
S2.buffer_holding = function(child, text)
	local b = child.lua([[
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(b) and vim.tbl_contains(vim.api.nvim_buf_get_lines(b, 0, -1, false), ...) then
				return b
			end
		end
		return vim.NIL
	]], { text })
	if b == vim.NIL then return nil end
	return b
end

-- The child's umask set to 022, so a file written with default permissions shows.
S2.umask022 = function(child)
	child.lua([[
		local ffi = require('ffi')
		pcall(ffi.cdef, 'unsigned int umask(unsigned int mask);')
		ffi.C.umask(18)
	]])
end

-- Messages ------------------------------------------------------------------------

-- True when some message contains `text` (plain).
S2.has = function(msgs, text)
	for _, m in ipairs(msgs) do
		if m.msg:find(text, 1, true) then return true end
	end
	return false
end

-- The messages that aren't a hook failure.
S2.notices = function(msgs)
	local out = {}
	for _, m in ipairs(msgs) do
		if not m.msg:find('failed during transition', 1, true) then table.insert(out, m.msg) end
	end
	return out
end

-- Files ---------------------------------------------------------------------------

-- The prefixes a session's main file name may start with:
-- sha256(directory .. "\n" .. name) for a named session (the separator
-- decided 2026-10-21, T255). A nameless save is sha256(directory) alone
-- (decided 2026-10-21, T292).
S2.session_names = function(directory, name)
	if name then return { vim.fn.sha256(directory .. '\n' .. name) } end
	return { vim.fn.sha256(directory) } -- a nameless save: sha256(directory) alone (decided 2026-10-21)
end

-- The file in `dir` whose name starts with one of S2.session_names, or nil.
S2.main_file = function(dir, directory, name)
	for _, want in ipairs(S2.session_names(directory, name)) do
		for _, f in ipairs(Misc.files_in(dir)) do
			if f:sub(1, #want) == want then return f end
		end
	end
	return nil
end

-- The path of the one regular file in `dir`, or nil when there isn't exactly one.
S2.only_file = function(dir)
	local f = Misc.files_in(dir)
	if #f == 1 then return dir .. f[1] end
	return nil
end

S2.read = function(path)
	local fh = assert(io.open(path, 'rb'))
	local bytes = fh:read('*a')
	fh:close()
	return bytes
end

S2.write = function(path, bytes)
	local fh = assert(io.open(path, 'wb'))
	fh:write(bytes)
	fh:close()
end

-- Flip one bit of the byte in the middle of a file.
S2.flip_middle = function(path)
	local bytes = S2.read(path)
	local mid = math.floor(#bytes / 2)
	S2.write(path, bytes:sub(1, mid - 1) .. string.char(bit.bxor(bytes:byte(mid), 1)) .. bytes:sub(mid + 1))
end

-- The scratch directory next to the main file: the one directory in `dir`
-- whose name ends in `.d` (the spec's `<main>.d/`), or nil.
S2.scratch_dir = function(dir)
	if vim.fn.isdirectory(dir) == 0 then return nil end
	local out = {}
	for _, n in ipairs(vim.fn.readdir(dir)) do
		if n:match('%.d$') and vim.fn.isdirectory(dir .. n) == 1 then table.insert(out, dir .. n .. '/') end
	end
	if #out == 1 then return out[1] end
	return nil
end

-- The names of the files in the scratch directory, sorted, and the directory.
S2.scratch_files = function(dir)
	local d = S2.scratch_dir(dir)
	if not d then return {}, nil end
	-- the trail's pages (A27) sit beside the texts' files, marked `.trail`
	local f = vim.tbl_filter(function(name) return not name:match('%.trail$') end, Misc.files_in(d))
	table.sort(f)
	return f, d
end

-- Every regular file under `dir`, as paths.
S2.all_files = function(dir)
	return vim.fs.find(function() return true end, { path = dir, type = 'file', limit = math.huge })
end

-- Tab sessions --------------------------------------------------------------------

-- In a fresh child: a second tab visits c then d (⦉c⦊ [d]), and that tab is
-- saved as the tab session `name`. Returns save_session's { ok, err }.
S2.save_tab_session = function(child, s, name)
	S2.start(child, s)
	child.cmd('tabnew')
	child.steps({ ':e c', ':e d' })
	return child.lua([[
		return { pcall(require('frogman').save_session, ..., { tab = vim.api.nvim_get_current_tabpage() }) }
	]], { name })
end

-- In the current child, the way resession loads a tab session: a new tab and
-- c and d brought back into it with no events, then load_session(name).
-- Returns { ok, err }.
S2.load_tab_session = function(child, name)
	local got = child.lua([[
		vim.cmd('noautocmd tabnew')
		local b = vim.fn.bufadd('c.txt')
		vim.fn.bufload(b)
		vim.bo[b].buflisted = true
		vim.cmd('noautocmd edit d.txt')
		return { pcall(require('frogman').load_session, ...) }
	]], { name })
	child.settle(300)
	return got
end

-- In the current child, the way a manager restores several tabs with no events:
-- the first tab is the current one, each other a new tab; each tab's files are
-- brought back (listed and loaded) and its window shows `shown`. tabs is a list
-- of { files = { 'x', 't' }, shown = 't' }, file letters as in the steps.
S2.restore_tabs = function(child, tabs)
	child.lua([[
		for i, tab in ipairs(...) do
			if i > 1 then vim.cmd('noautocmd tabnew') end
			for _, f in ipairs(tab.files) do
				local b = vim.fn.bufadd(f .. '.txt')
				vim.fn.bufload(b)
				vim.bo[b].buflisted = true
			end
			vim.cmd('noautocmd edit ' .. tab.shown .. '.txt')
		end
		vim.cmd('noautocmd tabnext 1')
	]], { tabs })
end

-- The closed-stack picker ---------------------------------------------------------

-- Run :CavediverClosed and find its buffer: the current one if the command
-- moved the focus, otherwise the buffer it made. Returns
-- { buf, win, came_from, lines, modifiable }; the picker's window is focused.
S2.picker = function(child)
	local got = child.lua([[
		local came_from = vim.api.nvim_get_current_win()
		local before = {}
		for _, b in ipairs(vim.api.nvim_list_bufs()) do before[b] = true end
		vim.cmd('CavediverClosed')
		local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
		if win == came_from then
			for _, b in ipairs(vim.api.nvim_list_bufs()) do
				if not before[b] then buf = b; break end
			end
			local wins = vim.fn.win_findbuf(buf)
			if #wins > 0 then win = wins[1]; vim.api.nvim_set_current_win(win) end
		end
		return { buf = buf, win = win, came_from = came_from }
	]])
	child.settle()
	got.lines = child.lua('return vim.api.nvim_buf_get_lines(..., 0, -1, false)', { got.buf })
	got.modifiable = child.lua('return vim.bo[...].modifiable', { got.buf })
	return got
end

-- The index of the first line holding `text`, or nil.
S2.line_of = function(lines, text)
	for i, l in ipairs(lines) do
		if l:find(text, 1, true) then return i end
	end
	return nil
end

-- Line i of buffer buf as it shows: its text, then the text of every piece of
-- virtual text drawn on it, from any namespace, joined with spaces.
S2.shown_line = function(child, buf, i)
	return child.lua([[
		local buf, i = ...
		local out = { vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or '' }
		for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, { i - 1, 0 }, { i - 1, -1 }, { details = true })) do
			for _, chunk in ipairs(m[4].virt_text or {}) do
				table.insert(out, chunk[1])
			end
		end
		return table.concat(out, ' ')
	]], { buf, i })
end

-- Set the picker's lines and write it.
S2.write_picker = function(child, p, lines)
	child.lua([[
		local buf, lines = ...
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_buf_call(buf, function() vim.cmd('write') end)
	]], { p.buf, lines })
	child.settle()
end

return S2
