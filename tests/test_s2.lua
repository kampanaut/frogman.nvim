-- The session file, S2 (what-is-cavediver.md, section 5, S2, and section 7,
-- "The session file, S2"). IDs are the spec's.
--
-- Most cases save in one child and load in a fresh one, both in a project and
-- with a session directory the test runner makes (tests/helpers_s2.lua). They
-- call save_session and load_session with the cwd, as the README wires them:
-- the cwd is then just the session's name, so these cases test their own rule
-- and not the API. The cases on the API and on tab sessions pass a name, no
-- argument, or { tab = … }.
local Helpers = dofile('tests/helpers.lua')
local Misc = dofile('tests/helpers_misc.lua')
local S2 = dofile('tests/helpers_s2.lua')
local eq, no_eq = Helpers.eq, Helpers.expect.no_equality
local child = Helpers.new_child()
-- A second editor on the same project (T317).
local other = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		post_once = function()
			child.stop()
			other.stop()
		end,
	},
})

local function session_dir()
	return child.lua('return require("cavediver.configs").session_dir')
end

-- Contract and API ----------------------------------------------------------------

T['T292 [char] (S2) save_session() and load_session() take no directory: the file is named after getcwd(-1, -1) and a fresh process loads it'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	eq(S2.save(child), { true })
	eq(S2.main_file(s.session_dir, S2.cwd(child)) ~= nil, true)

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b', 'c', 'd' }, 'd')
	eq(S2.load(child), { true })
	child.settle(300)
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
end

-- The second tab's local directory is sub/, inside the project.
T['T293 [char] (S2) a whole-editor save is keyed by the global directory, not by a tab-local :tcd'] = function()
	child.setup()
	child.steps({ ':e a' })
	child.lua('vim.fn.mkdir(_G.CDV_TEST.root .. "/sub", "p")')
	child.cmd('tabnew')
	child.cmd('tcd sub')
	child.settle()
	local global, tab = S2.cwd(child), child.lua('return vim.fn.getcwd(-1, 0)')
	no_eq(global, tab)
	eq(S2.save(child, 'work'), { true })
	local dir = session_dir()
	eq({ global = S2.main_file(dir, global, 'work') ~= nil, tab = S2.main_file(dir, tab, 'work') ~= nil },
		{ global = true, tab = false })
end

T['T294 [char] (S2) a tab session is keyed by its tab\'s directory'] = function()
	child.setup()
	child.steps({ ':e a' })
	child.lua('vim.fn.mkdir(_G.CDV_TEST.root .. "/sub", "p")')
	child.cmd('tabnew')
	child.cmd('tcd sub')
	child.cmd('edit ../b.txt')
	child.settle()
	local tab = child.lua('return vim.fn.getcwd(-1, 0)')
	eq(child.lua('return { pcall(require("cavediver").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'),
		{ true })
	eq(S2.main_file(session_dir(), tab, 't') ~= nil, true)
end

-- Loading -------------------------------------------------------------------------

T['T295 [char] (S2) a load from idle goes idle -> bare -> loading'] = function()
	child.setup()
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })
	local n = #child.lua('return require("cavediver.domains.storage").sm.history')
	Misc.load(child)
	local after = child.lua('return { unpack(require("cavediver.domains.storage").sm.history, ...) }', { n + 1 })
	local bare, loading
	for i, t in ipairs(after) do
		if t == 'idle->bare' and not bare then bare = i end
		if t == 'bare->loading' and bare and not loading then loading = i end
	end
	eq({ idle_bare = bare ~= nil, then_bare_loading = loading ~= nil }, { idle_bare = true, then_bare_loading = true })
end

-- After the save the editor moves on: d and x visited, d closed, a cycle left
-- open. The manager's restore puts the window back on c with no events.
T['T296 [char] (S2) every domain tears its own state down at idle -> bare'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	eq(Misc.save(child), { true })
	child.steps({ ':e d', ':e x' })
	child.cmd('bdelete d.txt')
	child.steps({ '<M-m>' })
	eq({ closed = child.closed(), states = S2.states(child), x = S2.registered(child, 'x') },
		{ closed = 'd', states = { nav = 'cycling', hist = 'detached' }, x = true })
	child.cmd('noautocmd edit c.txt')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ slots = child.slots(), closed = child.closed(), states = S2.states(child), x = S2.registered(child, 'x') },
		{ slots = '⦉b⦊ [c] ⟦-⟧', closed = '', states = { nav = 'normal', hist = 'attached' }, x = false })
end

-- Three calls in one batch, then a 30 ms wait (scheduled callbacks run, no
-- timer anywhere near), then a fourth call. With T145 (three calls, one load),
-- two loads in all tells vim.schedule apart from a timer and from no flag.
T['T297 [char] (S2) the repeat flag is re-armed by vim.schedule: a call after the batch is a full load'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	local oks = child.lua([[
		local cwd, load = vim.fn.getcwd(), require('cavediver').load_session
		local oks = {}
		for i = 1, 3 do oks[i] = pcall(load, cwd) end
		return oks
	]])
	child.settle(30)
	table.insert(oks, Misc.load(child)[1])
	child.settle(300)
	eq({ oks = oks, loads = S2.loads(child) }, { oks = { true, true, true, true }, loads = 2 })
end

-- :restart can't run inside a child. The second child is started the way
-- :restart starts its new server (v:startreason "restart", S2.start_restarted),
-- and Neovim's restart session is a real :mksession! file, named the way
-- :restart names it. It's sourced in the same batch as the startup load, as in
-- the desk's tmux run, and rebuilds the windows with events on.
T['T298 [char] (S2) after Neovim\'s :restart session, cavediver loads again by itself, ignoring the repeat flag'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.steps({ ':e c', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦-⟧')
	eq(Misc.save(child), { true })
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, 'p')
	local session = dir .. '/restart_session_T298xy'
	child.cmd('mksession! ' .. vim.fn.fnameescape(session))

	S2.start_restarted(child, s)
	eq(child.lua('return vim.v.startreason'), 'restart')
	Misc.restore(child, { 'a', 'b', 'c', 'd' }, 'b')
	child.cmd('noautocmd vsplit')
	child.cmd('noautocmd edit d.txt')
	child.lua([[
		pcall(require('cavediver').load_session, vim.fn.getcwd())
		vim.cmd('source ' .. vim.fn.fnameescape(...))
	]], { session })
	child.settle(300)
	local slots = {}
	for _, w in ipairs(child.lua('return vim.api.nvim_tabpage_list_wins(0)')) do
		slots[child.shown(w)] = child.slots(w)
	end
	eq({ loads = S2.loads(child), slots = slots },
		{ loads = 2, slots = { b = '⦉a⦊ [b] ⟦-⟧', d = '⦉c⦊ [d] ⟦-⟧' } })
end

-- The current window is a split on c, made with no events, so nothing has
-- told cavediver about it before the load. Timer handles are counted: the
-- decided load uses vim.schedule, and a fixed delay needs a timer.
T['T299 [char] (S2) one post-restore callback replaces the load\'s 210 ms delay'] = function()
	local s = S2.shared()
	S2.start(child, s, { history_view = 'window' })
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.steps({ ':e c' })
	eq(Misc.save(child), { true })

	S2.start(child, s, { history_view = 'window' })
	Misc.restore(child, { 'a', 'b', 'c' }, 'b')
	child.cmd('noautocmd vsplit')
	child.cmd('noautocmd edit c.txt')
	local made = child.lua([[
		local function timers()
			local n = 0
			vim.uv.walk(function(h) if h:get_type() == 'timer' then n = n + 1 end end)
			return n
		end
		local before = timers()
		pcall(require('cavediver').load_session, vim.fn.getcwd())
		return timers() - before
	]])
	child.settle(30)
	local current = child.lua(
		'return require("cavediver.domains.window").data.last_valid_window == vim.api.nvim_get_current_win()')
	local order = child.ordered()
	child.settle(300)
	eq({ new_timers = made, last_valid_window = current, order = order },
		{ new_timers = 0, last_valid_window = true, order = child.ordered() })
end

-- The window shows the No Name text when it's saved, and a load follows in the
-- same process, as a native session's reload does: the buffer is still there.
T['T339 [char] (S2) a reload in the same process keeps the slots of a window showing an open No Name text'] = function()
	child.setup()
	child.steps({ ':e a', ':e b' })
	S2.noname(child, { 'shown text' })
	local before = child.slots()
	eq(before:match('^⦉b⦊ %[NONAME_%d+%] ⟦%-⟧$') ~= nil, true)
	eq(Misc.save(child), { true })
	child.messages()
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ slots = child.slots(), holding = S2.holding(child, 'shown text'), errors = Misc.errors(child) },
		{ slots = before, holding = 1, errors = {} })
end

-- The same with the No Name buffer empty, in a split that isn't focused: an
-- empty one has no text to reopen, so the load knows it by its id alone.
T['T339 [char] (S2) a reload in the same process keeps the slots of a window that isn\'t focused, on an empty No Name buffer'] = function()
	child.setup()
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c', ':enew' })
	local split = child.lua('return vim.api.nvim_get_current_win()')
	local before = child.slots(split)
	eq(before:match('^⦉c⦊ %[NONAME_%d+%] ⟦%-⟧$') ~= nil, true)
	child.cmd('wincmd p')
	child.settle()
	eq(Misc.save(child), { true })
	child.messages()
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ split = child.slots(split), focused = child.slots(), errors = Misc.errors(child) },
		{ split = before, focused = '⦉a⦊ [b] ⟦-⟧', errors = {} })
end

-- The No Name text is open in the ternary at save, so the first load reopens it.
T['T300 [char] (S2) a later reload brings no No Name text back twice'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	S2.noname(child, { 'reload text' })
	child.steps({ ':e b' })
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(Misc.load(child), { true })
	child.settle(300)
	local first = S2.holding(child, 'reload text')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ first = first, second = S2.holding(child, 'reload text') }, { first = 1, second = 1 })
end

-- The file -----------------------------------------------------------------------

T['T301 [char] (S2) the main file starts with the clear version header CDV1'] = function()
	child.setup()
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })
	local file = S2.only_file(session_dir())
	eq(file ~= nil, true)
	eq(S2.read(file):sub(1, 4), 'CDV1')
end

-- b is closed; a No Name text is open in the ternary.
T['T302 [char] (S2) no session file is JSON or holds the directory, a file name or No Name text in clear'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('bdelete b.txt')
	S2.noname(child, { 'private words' })
	child.steps({ ':e d' })
	eq(Misc.save(child), { true })
	local pieces = {
		{ 'the project directory', child.lua('return _G.CDV_TEST.root') },
		{ 'a.txt', 'a.txt' }, { 'b.txt', 'b.txt' }, { 'c.txt', 'c.txt' }, { 'd.txt', 'd.txt' },
		{ 'the No Name text', 'private words' },
	}
	local files = S2.all_files(session_dir())
	eq(#files > 0, true)
	local found = {}
	for i, f in ipairs(files) do
		local bytes = S2.read(f)
		local ok, data = pcall(vim.json.decode, bytes)
		if ok and type(data) == 'table' then table.insert(found, 'file ' .. i .. ' is JSON') end
		for _, p in ipairs(pieces) do
			if bytes:find(p[2], 1, true) then table.insert(found, 'file ' .. i .. ' holds ' .. p[1]) end
		end
	end
	eq(found, {})
end

-- Every way to a shell is counted, at the save and, in a fresh process, at the
-- load. Hashing on :e is T222.
local SHELL_SPY = [[
	_G.CDV_SHELL = 0
	local sys, popen, vsys = vim.fn.system, io.popen, vim.system
	vim.fn.system = function(...) _G.CDV_SHELL = _G.CDV_SHELL + 1; return sys(...) end
	io.popen = function(...) _G.CDV_SHELL = _G.CDV_SHELL + 1; return popen(...) end
	vim.system = function(...) _G.CDV_SHELL = _G.CDV_SHELL + 1; return vsys(...) end
]]
T['T303 [char] (S2) a save and a load run no shell command'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.lua(SHELL_SPY)
	eq(Misc.save(child), { true })
	local at_save = child.lua('return _G.CDV_SHELL')

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.lua(SHELL_SPY)
	eq(Misc.load(child), { true })
	child.settle(30)
	eq({ save = at_save, load = child.lua('return _G.CDV_SHELL') }, { save = 0, load = 0 })
end

T['T304 [char] (S2) every write is atomic: a new file is renamed over the old one, and nothing else is left'] = function()
	child.setup()
	child.steps({ ':e a' })
	eq(Misc.save(child), { true })
	local dir = session_dir()
	local file = S2.only_file(dir)
	eq(file ~= nil, true)
	local first = vim.uv.fs_stat(file).ino
	child.steps({ ':e b' })
	eq(Misc.save(child), { true })
	eq({ regular_files = #Misc.files_in(dir), same_inode = vim.uv.fs_stat(file).ino == first },
		{ regular_files = 1, same_inode = false })
end

-- A No Name text closed with <M-.>, another open, and an empty one shown.
T['T305 [char] (S2) one scratch file per No Name text in <main>.d/, each in mode 0600'] = function()
	child.setup()
	S2.umask022(child)
	child.steps({ ':e a' })
	S2.noname(child, { 'first text' })
	child.steps({ '<M-.>' })
	eq(child.shown(), 'a')
	S2.noname(child, { 'second text' })
	child.cmd('enew')
	child.settle()
	eq(Misc.save(child), { true })
	local files, d = S2.scratch_files(session_dir())
	local perms = {}
	for _, f in ipairs(files) do table.insert(perms, vim.fn.getfperm(d .. f)) end
	eq(perms, { 'rw-------', 'rw-------' })
end

-- The No Name text is open in the ternary, the window on b.
T['T306 [char] (S2) scratch files are named per version, rewritten only when they change, and swept when unreferenced'] = function()
	child.setup()
	child.steps({ ':e a' })
	local n = S2.noname(child, { 'v1 text' })
	child.steps({ ':e b' })
	local dir = session_dir()
	eq(Misc.save(child), { true })
	local one, d = S2.scratch_files(dir)
	eq(#one, 1)
	local bytes = S2.read(d .. one[1])
	eq(Misc.save(child), { true })
	eq({ files = S2.scratch_files(dir), bytes = S2.read(d .. one[1]) }, { files = one, bytes = bytes })
	child.lua('vim.api.nvim_buf_set_lines(..., 0, -1, false, { "v2 text" })', { n })
	eq(Misc.save(child), { true })
	local three = S2.scratch_files(dir)
	eq(#three, 1)
	no_eq(three[1], one[1])
end

-- T306's two saves, v1 then v2. Returns the main file, its first bytes, the
-- scratch directory and both scratch files.
local function two_versions(s)
	S2.start(child, s)
	child.steps({ ':e a' })
	local n = S2.noname(child, { 'v1 text' })
	child.steps({ ':e b' })
	eq(Misc.save(child), { true })
	local main = S2.only_file(s.session_dir)
	local one, d = S2.scratch_files(s.session_dir)
	eq({ main = main ~= nil, scratches = #one }, { main = true, scratches = 1 })
	local v = { main = main, main1 = S2.read(main), d = d, v1 = one[1], v1bytes = S2.read(d .. one[1]) }
	child.lua('vim.api.nvim_buf_set_lines(..., 0, -1, false, { "v2 text" })', { n })
	eq(Misc.save(child), { true })
	local two = S2.scratch_files(s.session_dir)
	eq(#two, 1)
	v.v2 = two[1]
	return v
end

-- The crash: v2's scratch written, the main file not replaced yet, nothing
-- swept. Put together from the files of the two saves.
T['T307 [char] (S2) the main file is the commit point: a crash before it lands leaves the old session whole'] = function()
	local s = S2.shared()
	local v = two_versions(s)
	S2.write(v.main, v.main1)
	S2.write(v.d .. v.v1, v.v1bytes)

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ v1 = S2.holding(child, 'v1 text'), v2 = S2.holding(child, 'v2 text') }, { v1 = 1, v2 = 0 })
end

-- The crash: the main file landed, the sweep didn't run, so v1's scratch is
-- still there.
T['T307 [char] (S2) the main file is the commit point: leftovers of a crash after it are swept by the next save'] = function()
	local s = S2.shared()
	local v = two_versions(s)
	S2.write(v.d .. v.v1, v.v1bytes)
	local both = { v.v1, v.v2 }
	table.sort(both)
	eq(S2.scratch_files(s.session_dir), both)
	eq(Misc.save(child), { true })
	eq(S2.scratch_files(s.session_dir), { v.v2 })
end

-- Two No Name texts made in a split, which is then closed: both stay open and
-- hidden, and the first window keeps ⦉a⦊ [b].
T['T308 [char] (S2) a damaged scratch file loses one scratch, not the session'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	S2.noname(child, { 'one text' })
	S2.noname(child, { 'two text' })
	child.cmd('close')
	child.settle()
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	eq(Misc.save(child), { true })
	local files, d = S2.scratch_files(s.session_dir)
	eq(#files, 2)
	S2.flip_middle(d .. files[1])

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ slots = child.slots(), texts_back = S2.holding(child, 'one text') + S2.holding(child, 'two text') },
		{ slots = '⦉a⦊ [b] ⟦-⟧', texts_back = 1 })
end

-- A No Name text closed with <M-.> is held unread after a load. The session's
-- files are then removed, so the next save makes a new key and can't read the
-- text: it's lost, and it leaves the closed stack in the file too, so the load
-- after that doesn't stop on a closed No Name entry without its text.
T['T341 [char] (S2) a closed No Name text that can\'t be read at a save leaves the closed stack, and the next load goes through'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	S2.noname(child, { 'closed text' })
	child.steps({ '<M-.>' })
	eq(child.closed():match('NONAME_') ~= nil, true)
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.closed():match('NONAME_') ~= nil, true)
	for _, f in ipairs(Misc.files_in(s.session_dir)) do
		vim.fn.delete(s.session_dir .. f)
	end
	vim.fn.delete(S2.scratch_dir(s.session_dir) or '', 'rf')
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.messages()
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ errors = Misc.errors(child), noname_closed = child.closed():match('NONAME_') ~= nil },
		{ errors = {}, noname_closed = false })
end

-- 150 more files in the project, each opened and closed. It held before the
-- encrypted format and holds with it.
T['T309 [char] (S2) no count limit: 150 closed files all come back'] = function()
	local s = S2.shared()
	for i = 1, 150 do vim.fn.writefile({ 'n' }, s.root .. '/n' .. i .. '.txt') end
	local function closed() return child.lua('return #require("cavediver.domains.history").data.closed_buffers') end
	S2.start(child, s)
	child.steps({ ':e a' })
	child.lua([[
		for i = 1, 150 do
			vim.cmd('edit n' .. i .. '.txt')
			vim.wait(10) -- the visit settles before the close, as when it's typed
			vim.cmd('bdelete n' .. i .. '.txt')
		end
	]])
	child.settle()
	eq(closed(), 150)
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a' }, 'a')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(closed(), 150)
end

-- Checks --------------------------------------------------------------------------

-- The file saved as `work` in one project is copied to the name the same
-- session takes in a second project (its sha256(directory .. "\n" .. name) prefix
-- changed, the rest of the name kept).
T['T310 [char] (S2) a file only decrypts in its own directory'] = function()
	local s = S2.shared()
	local two = Misc.make_project()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(S2.save(child, 'work'), { true })
	local name = S2.main_file(s.session_dir, S2.cwd(child), 'work')
	eq(name ~= nil, true)

	S2.start(child, s, { root = two })
	local copy = S2.session_names(S2.cwd(child), 'work')[1] .. name:sub(65)
	S2.write(s.session_dir .. copy, S2.read(s.session_dir .. name))
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.messages()
	eq(S2.load(child, 'work'), { true })
	child.settle(300)
	eq({ told = S2.has(child.messages(), 'integrity check'), slots = child.slots(), closed = child.closed() },
		{ told = true, slots = '⦉-⦊ [b] ⟦-⟧', closed = '' })
end

T['T311 [char] (S2) a cut-off file gives the integrity notification and a fresh start'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })
	local file = S2.only_file(s.session_dir)
	eq(file ~= nil, true)
	local bytes = S2.read(file)
	S2.write(file, bytes:sub(1, math.floor(#bytes / 2)))

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.messages()
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ told = S2.has(child.messages(), 'integrity check'), slots = child.slots(), closed = child.closed() },
		{ told = true, slots = '⦉-⦊ [b] ⟦-⟧', closed = '' })
end

-- The main file's bytes replaced by a file in the format from before encryption:
-- plain JSON, no header.
T['T312 [char] (S2) a file with no header points to the migration script'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })
	local file = S2.only_file(s.session_dir)
	eq(file ~= nil, true)
	S2.write(file, vim.json.encode({
		buffers = { window = {}, global = vim.empty_dict() },
		windows = {}, closed = {}, noname_content = vim.empty_dict(),
	}))

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.messages()
	Misc.load(child)
	child.settle(300)
	eq(S2.has(child.messages(), 'migration script'), true)
end

-- b.txt is deleted from disk after the save and isn't brought back.
T['T313 [char] (S2) a reference that resolves to nothing is kept, says so when used, and works again when its file is back'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	eq(Misc.save(child), { true })

	S2.start(child, s)
	-- after the start: a child's setup writes the project's files again
	os.remove(s.root .. '/b.txt')
	Misc.restore(child, { 'a', 'c', 'd' }, 'd')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	child.messages()
	local ok, err = child.step('<M-f>')
	eq({ ok = ok, err = err, told = #child.messages() > 0, slots = child.slots() },
		{ ok = true, told = true, slots = '⦉c⦊ [d] ⟦b⟧' })
	vim.fn.writefile({ 'b' }, s.root .. '/b.txt')
	child.steps({ '<M-f>' })
	eq(child.slots(), '⦉c⦊ [b] ⟦d⟧')
end

-- Contents ------------------------------------------------------------------------

-- x is loaded and hidden when the load runs, and the saved file never knew it.
T['T314 [char] (S2) a restored buffer the file doesn\'t know waits for BufEnter'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b', 'x' }, 'b')
	eq(Misc.load(child), { true })
	child.settle(300)
	local at_load = S2.registered(child, 'x')
	child.steps({ ':e x' })
	eq({ at_load = at_load, entered = S2.registered(child, 'x') }, { at_load = false, entered = true })
end

-- b.txt stays on disk, but the manager doesn't bring b back. A cleanup pass
-- after the load leaves the reference alone.
T['T337 [char] (S2) a reference whose buffer the manager doesn\'t restore is kept, and reopens when used'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'c', 'd' }, 'd')
	eq(Misc.load(child), { true })
	child.settle(300)
	child.lua('require("cavediver.domains.history").cleanup_system()')
	eq({ slots = child.slots(), b = S2.registered(child, 'b') }, { slots = '⦉c⦊ [d] ⟦b⟧', b = false })
	child.steps({ '<M-f>' })
	eq({ slots = child.slots(), shown = child.shown() }, { slots = '⦉c⦊ [b] ⟦d⟧', shown = 'b' })
end

-- Saved: the split (listed first) ⦉c⦊ [b], the first window ⦉a⦊ [b]. The
-- manager brings both back, behind a new first-listed window on e.
T['T315 [char] (S2) windows on the same file keep their saved order, and a window that matches nothing starts fresh'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c', ':e b' })
	eq(child.slots(), '⦉c⦊ [b] ⟦-⟧')
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b', 'c', 'e' }, 'b')
	child.cmd('noautocmd vsplit')
	child.cmd('noautocmd vsplit')
	child.cmd('noautocmd edit e.txt')
	local wins = child.lua('return vim.api.nvim_tabpage_list_wins(0)')
	eq({ child.shown(wins[1]), child.shown(wins[2]), child.shown(wins[3]) }, { 'e', 'b', 'b' })
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ child.slots(wins[1]), child.slots(wins[2]), child.slots(wins[3]) },
		{ '⦉-⦊ [e] ⟦-⟧', '⦉c⦊ [b] ⟦-⟧', '⦉a⦊ [b] ⟦-⟧' })
end

-- The No Name text sits in the ternary at save.
T['T316 [char] (S2) a No Name buffer reopened at load gets a fresh id, and every reference to the old one is renamed'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	local n = S2.noname(child, { 'ternary text' })
	child.steps({ ':e b' })
	local old = child.lua('return require("cavediver.domains.history").get_hash_from_buffer(...)', { n })
	eq(type(old), 'string')
	eq(child.lua('return require("cavediver.domains.window").data.crux[vim.api.nvim_get_current_win()].ternary_slot == ...',
		{ old }), true)
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(Misc.load(child), { true })
	child.settle(300)
	local back = S2.buffer_holding(child, 'ternary text')
	eq(back ~= nil, true)
	local got = child.lua([[
		local old, buf = ...
		local H = require('cavediver.domains.history')
		local W = require('cavediver.domains.window')
		local new = H.get_hash_from_buffer(buf)
		local stale = {}
		local function look(where, h)
			if type(h) == 'string' and (h:gsub('%-swap$', '')) == old then table.insert(stale, where) end
		end
		for _, t in pairs(W.data.crux) do
			look('current slot', t.current_slot)
			look('secondary slot', t.secondary_slot)
			look('ternary slot', t.ternary_slot)
			for _, p in ipairs(t.primary_buffer or {}) do look('primary queue', p) end
			for k, v in pairs(t.displacement_ternary_map or {}) do look('dtm key', k); look('dtm value', v) end
			for k, v in pairs(t.displacement_secondary_map or {}) do look('dsm key', k); look('dsm value', v) end
		end
		for h in pairs(H.data.crux_internals.global) do look('global history', h) end
		for _, hist in pairs(H.data.crux_internals.window) do
			for h in pairs(hist) do look('window history', h) end
		end
		local t = W.data.crux[vim.api.nvim_get_current_win()]
		return { fresh = new ~= nil and new ~= old, in_ternary = t ~= nil and t.ternary_slot == new, stale = stale }
	]], { old, back })
	eq(got, { fresh = true, in_ternary = true, stale = {} })
end

-- The old file is made by hand in the format from before encryption: paths
-- XOR'd with the cwd and base64-encoded, raw hashes for open buffers, the
-- six-field window entry. So is the resession session that names the project,
-- in the test run's own data directory. The directory is the one the child
-- sees, symlinks resolved. Returns the old file's path and a function that runs
-- the script with extra arguments.
local function old_session(s)
	S2.start(child, s)
	local root = S2.cwd(child)
	local function xor(text)
		local out = {}
		for n = 1, #text do
			out[n] = string.char(bit.bxor(text:byte(n), root:byte(((n - 1) % #root) + 1)))
		end
		return vim.base64.encode(table.concat(out))
	end
	local function hash(file) return vim.fn.sha256(root .. '/' .. file .. '\n'):sub(1, 16) end
	local old = {
		buffers = { window = {}, global = { [hash('a.txt')] = 1, [hash('c.txt')] = 3, [hash('d.txt')] = 4 } },
		windows = { { hash('d.txt'), xor(root .. '/b.txt'), {}, hash('c.txt'), {}, {} } },
		closed = { xor(root .. '/b.txt') },
		noname_content = {},
	}
	local old_path = s.session_dir .. vim.fn.sha256(root .. '\n'):sub(1, 32) .. '.json'
	vim.fn.writefile({ vim.json.encode(old) }, old_path)
	local resession_dir = vim.fn.stdpath('data') .. '/cavediver_test_sessions/'
	vim.fn.delete(resession_dir, 'rf')
	vim.fn.mkdir(resession_dir, 'p')
	local session = {
		global = { cwd = root },
		buffers = { { name = root .. '/a.txt' }, { name = root .. '/c.txt' }, { name = root .. '/d.txt' } },
		tab_scoped = false,
		tabs = { {} },
	}
	vim.fn.writefile({ vim.json.encode(session) }, resession_dir .. root:gsub('/', '_'):gsub(':', '_') .. '.json')
	local function migrate(...)
		local cmd = { vim.v.progpath, '--clean', '-l', 'scripts/migrate_sessions.lua',
			'--resession-dir', 'cavediver_test_sessions', '--session-dir', s.session_dir, ... }
		return vim.system(cmd, { text = true }):wait()
	end
	return old_path, migrate
end

T['T338 [char] (S2) the migration script converts an old file found through resession\'s session list, and a load reads it'] = function()
	local s = S2.shared()
	local old_path, migrate = old_session(s)

	local first = migrate()
	eq({ code = first.code, converted = first.stdout:find('converted 1 session', 1, true) ~= nil },
		{ code = 0, converted = true })
	eq({ old = vim.fn.filereadable(old_path), marked = vim.fn.filereadable(old_path .. '.migrated') }, { old = 0, marked = 1 })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'c', 'd' }, 'd')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ slots = child.slots(), closed = child.closed() }, { slots = '⦉c⦊ [d] ⟦b⟧', closed = 'b' })

	local second = migrate()
	eq({ code = second.code, already = second.stdout:find('1 already converted', 1, true) ~= nil },
		{ code = 0, already = true })
end

-- The new code runs a session before the script: its load starts fresh and its
-- save writes a file in the new format. The script doesn't take that for a
-- conversion: it reports the conflict, and --replace converts over it.
T['T342 [char] (S2) the migration script reports a session saved fresh before it ran, and --replace converts over it'] = function()
	local s = S2.shared()
	local _, migrate = old_session(s)
	S2.start(child, s)
	Misc.restore(child, { 'a', 'c', 'd' }, 'd')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.slots(), '⦉-⦊ [d] ⟦-⟧')
	eq(Misc.save(child), { true })

	local first = migrate()
	eq({ code = first.code, conflict = first.stdout:find('1 with a file in the new format already', 1, true) ~= nil },
		{ code = 0, conflict = true })
	local replaced = migrate('--replace')
	eq({ code = replaced.code, converted = replaced.stdout:find('converted 1 session', 1, true) ~= nil },
		{ code = 0, converted = true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'c', 'd' }, 'd')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
end

-- Only a file named the old way is there: the first 32 hex characters of
-- sha256(cwd .. "\n"), plus .json, in the format from before encryption.
T['T340 [char] (S2) a load that finds only a file named the old way points to the migration script'] = function()
	local s = S2.shared()
	S2.start(child, s)
	local root = S2.cwd(child)
	local old = s.session_dir .. vim.fn.sha256(root .. '\n'):sub(1, 32) .. '.json'
	vim.fn.writefile({ '{"buffers":{"window":[],"global":[]},"windows":[],"closed":[],"noname_content":[]}' }, old)

	S2.start(child, s)
	Misc.restore(child, { 'a' }, 'a')
	child.messages()
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ told = S2.has(child.messages(), 'migration script'), slots = child.slots(), left = vim.fn.filereadable(old) },
		{ told = true, slots = '⦉-⦊ [a] ⟦-⟧', left = 1 })
end

-- Errors and drift ----------------------------------------------------------------

-- Two editors on one project and one session directory save in turn. It held
-- before the encrypted format and holds with it.
T['T317 [char] (S2) with two editors on one project, the last writer wins'] = function()
	local s = S2.shared()
	S2.start(child, s)
	S2.start(other, s)
	child.steps({ ':e a', ':e b' })
	other.steps({ ':e c', ':e d' })
	eq(Misc.save(child), { true })
	eq(Misc.save(other), { true })
	other.stop()

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b', 'c', 'd' }, 'd')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.slots(), '⦉c⦊ [d] ⟦-⟧')
end

-- Tab sessions --------------------------------------------------------------------

-- A tab session t saved from a second tab at ⦉c⦊ [d] (S2.save_tab_session),
-- then a fresh process with its first tab at ⦉x⦊ [t] loads t into a second
-- tab. Returns both windows.
local function tab_session(s)
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	local w1 = child.lua('return vim.api.nvim_get_current_win()')
	eq(child.slots(w1), '⦉x⦊ [t] ⟦-⟧')
	eq(S2.load_tab_session(child, 't'), { true })
	return w1, child.lua('return vim.api.nvim_get_current_win()')
end

T['T318 [char] (S2) a tab session\'s file says its scope, and its load works on the current tab only'] = function()
	local s = S2.shared()
	local w1, w2 = tab_session(s)
	eq({ session_tab = child.slots(w2), first_tab = child.slots(w1) },
		{ session_tab = '⦉c⦊ [d] ⟦-⟧', first_tab = '⦉x⦊ [t] ⟦-⟧' })
end

-- The same, from idle: a whole-editor save in that process first.
T['T318 [char] (S2) a tab session\'s load from idle works on the current tab only too'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	local w1 = child.lua('return vim.api.nvim_get_current_win()')
	eq(S2.save(child), { true })
	eq(S2.load_tab_session(child, 't'), { true })
	local w2 = child.lua('return vim.api.nvim_get_current_win()')
	eq({ session_tab = child.slots(w2), first_tab = child.slots(w1) },
		{ session_tab = '⦉c⦊ [d] ⟦-⟧', first_tab = '⦉x⦊ [t] ⟦-⟧' })
end

T['T319 [char] (S2) closes go to the pool of the tab they happen in, and <M-S-w> reopens from the current tab\'s'] = function()
	local s = S2.shared()
	local w1, w2 = tab_session(s)
	child.cmd('tabprevious')
	child.cmd('bdelete x.txt')
	child.cmd('tabnext')
	child.cmd('bdelete c.txt')
	child.cmd('tabprevious')
	child.settle()
	child.steps({ '<M-S-w>' })
	local first_tab = child.shown(w1)
	child.cmd('tabnext')
	child.settle()
	child.steps({ '<M-S-w>' })
	eq({ first_tab = first_tab, session_tab = child.shown(w2) }, { first_tab = 'x', session_tab = 'c' })
end

-- Only membership is checked: the spec doesn't fix the order inside the overlay.
T['T320 [char] (S2) a tab session\'s tab ranks its own visits first, a buffer visited from both tabs included'] = function()
	local s = S2.shared()
	tab_session(s)
	child.cmd('tabprevious')
	child.steps({ ':e a', ':e b' })
	child.cmd('tabnext')
	child.steps({ ':e a' })
	child.settle(300)
	local first = vim.list_slice(vim.split(child.ordered(), ','), 1, 3)
	table.sort(first)
	eq(first, { 'a', 'c', 'd' })
end

-- x closed in the first tab, c in the session's tab, then e in the first tab,
-- a second apart so their close times differ whatever the clock's grain. The
-- window goes back to t before e is closed: :bdelete of what the only window
-- of a tab shows closes that tab.
T['T321 [char] (S2) saves are snapshots: a whole-editor save merges the pools by close time in the file only'] = function()
	local s = S2.shared()
	local w1 = tab_session(s)
	child.cmd('tabprevious')
	child.cmd('bdelete x.txt')
	child.settle(1100)
	child.cmd('tabnext')
	child.cmd('bdelete c.txt')
	child.settle(1100)
	child.cmd('tabprevious')
	child.steps({ ':e e', ':e t' })
	child.cmd('bdelete e.txt')
	child.settle()
	eq(S2.save(child), { true })
	local live = {}
	for _ = 1, 2 do
		child.steps({ '<M-S-w>' })
		table.insert(live, child.shown(w1))
	end

	S2.start(child, s)
	Misc.restore(child, { 't' }, 't')
	eq(S2.load(child), { true })
	child.settle(300)
	local merged = {}
	for _ = 1, 3 do
		child.steps({ '<M-S-w>' })
		table.insert(merged, child.shown())
	end
	eq({ live = live, merged = merged }, { live = { 'e', 'x' }, merged = { 'e', 'c', 'x' } })
end

-- No TabClosedPre hook calls save_session here. The notice's wording isn't
-- fixed, so any notification that isn't a hook failure counts.
T['T322 [char] (S2) a tab session\'s tab closed with no save wired gives a notice'] = function()
	local s = S2.shared()
	tab_session(s)
	child.messages()
	child.cmd('tabclose')
	child.settle(300)
	eq(#S2.notices(child.messages()) > 0, true)
end

-- c is closed in the session's tab before the tab goes; its pool is kept with
-- no tab, so the picker still lists it.
T['T322 [target] (S2) a tab session\'s tab closed with no save wired keeps its pool, still in the picker'] = function()
	local s = S2.shared()
	tab_session(s)
	child.cmd('bdelete c.txt')
	child.cmd('tabclose')
	child.settle(300)
	local p = S2.picker(child)
	eq(S2.line_of(p.lines, 'c.txt') ~= nil, true)
end

-- The whole editor is saved (the unnamed session) at ⦉x⦊ [t]; then t is loaded
-- into a second tab, x is closed and e visited in the first tab, and t is saved.
T['T323 [char] (S2) a tab-session save refreshes the unnamed session\'s records and leaves its references'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(child.slots(), '⦉x⦊ [t] ⟦-⟧')
	eq(S2.save(child), { true })
	eq(S2.load_tab_session(child, 't'), { true })
	child.cmd('tabprevious')
	child.cmd('bdelete x.txt')
	child.steps({ ':e e' })
	child.cmd('tabnext')
	child.settle()
	eq(child.lua('return { pcall(require("cavediver").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'),
		{ true })
	-- the whole editor's file, as the load reads it
	eq(child.lua([[
		local saved = require('cavediver.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), nil)
		local x = require('cavediver.domains.history').get_hash_from_filepath(vim.fn.getcwd(-1, -1) .. '/x.txt')
		return vim.tbl_contains(saved.closed or {}, x)
	]]), true)

	S2.start(child, s)
	Misc.restore(child, { 't' }, 't')
	eq(S2.load(child), { true })
	child.settle(300)
	eq({ closed = child.closed(), slots = child.slots() }, { closed = 'x', slots = '⦉x⦊ [t] ⟦-⟧' })
end

-- In T318's state, a No Name text made in the session's tab and left there
-- (the window goes back to d), and another made in the first tab and left
-- there (back to t). Only the tab session is saved; a fresh process loads it
-- into a second tab.
T['T332 [char] (S2) a tab session\'s file holds the No Name texts its own tab owns, and not another tab\'s'] = function()
	local s = S2.shared()
	tab_session(s)
	S2.noname(child, { 'session text' })
	child.steps({ ':e d' })
	child.cmd('tabprevious')
	S2.noname(child, { 'first text' })
	child.steps({ ':e t' })
	child.cmd('tabnext')
	child.settle()
	eq(child.lua('return { pcall(require("cavediver").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'),
		{ true })

	S2.start(child, s)
	child.steps({ ':e x' })
	eq(S2.load_tab_session(child, 't'), { true })
	eq({ session_text = S2.holding(child, 'session text'), first_text = S2.holding(child, 'first text') },
		{ session_text = 1, first_text = 0 })
end

-- a is visited in both tabs and closed in the first; x is visited and closed
-- in the first tab only. The answer to Q15 (2026-10-23): "Both".
T['T349 [char] (S2) a close goes back on the pool of every tab that visited the file'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s)
	child.steps({ ':e a', ':e d' })
	child.cmd('tabprevious')
	child.cmd('bdelete x.txt')
	child.steps({ ':e a' })
	child.cmd('bdelete a.txt')
	child.cmd('tabnext')
	child.settle()
	child.steps({ '<M-S-w>' })
	local first = child.shown(w2)
	child.steps({ '<M-S-w>' })
	eq({ first = first, second = child.shown(w2) }, { first = 'a', second = 'a' })
end

-- e is closed into the session's pool from a split that's gone by then, so no
-- window of the session's tab has it in its history; reopened and closed in the
-- first tab, it goes back on the pool it came out of.
T['T350 [char] (S2) a file reopened from one pool goes back on the pools it came out of when it is closed again'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s)
	child.cmd('vsplit')
	child.steps({ ':e e' })
	child.cmd('close')
	child.cmd('bdelete e.txt')
	child.cmd('tabprevious')
	child.cmd('bdelete x.txt')
	child.steps({ ':e e' })
	child.cmd('bdelete e.txt')
	child.cmd('tabnext')
	child.settle()
	child.steps({ '<M-S-w>' })
	local first = child.shown(w2)
	child.steps({ '<M-S-w>' })
	eq({ first = first, second = child.shown(w2) }, { first = 'e', second = 'e' })
end

-- The contract's TabClosedPre save is wired here. The load afterwards brings d
-- back and not c, as a manager would after c was closed.
T['T351 [char] (S2) a tab session\'s tab closed with its save wired gives no notice'] = function()
	local s = S2.shared()
	tab_session(s)
	child.lua([[
		vim.api.nvim_create_autocmd('TabClosedPre', { callback = function()
			require('cavediver').save_session('t', { tab = vim.api.nvim_get_current_tabpage() })
		end })
	]])
	child.cmd('bdelete c.txt')
	child.settle()
	child.messages()
	child.cmd('tabclose')
	child.settle(300)
	local notices = S2.notices(child.messages())
	local got = child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		return { pcall(require('cavediver').load_session, 't') }
	]])
	child.settle(300)
	child.steps({ '<M-S-w>' })
	eq({ notices = notices, got = got, reopened = child.shown() }, { notices = {}, got = { true }, reopened = 'c' })
end

-- The tab's own directory is sub, in the save and in the load, as the manager
-- restores it.
T['T352 [char] (S2) a tab session saved from a tab with a :tcd of its own is found at load in that tab'] = function()
	local s = S2.shared()
	vim.fn.mkdir(s.root .. '/sub', 'p')
	S2.start(child, s)
	child.cmd('tabnew')
	child.cmd('tcd sub')
	child.steps({ ':e ../c.txt', ':e ../d.txt' })
	eq(child.slots(), '⦉c⦊ [d] ⟦-⟧')
	eq(child.lua('return { pcall(require("cavediver").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'),
		{ true })

	S2.start(child, s)
	local got = child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd tcd sub')
		local b = vim.fn.bufadd(vim.fn.fnamemodify('../c.txt', ':p'))
		vim.fn.bufload(b)
		vim.bo[b].buflisted = true
		vim.cmd('noautocmd edit ../d.txt')
		return { pcall(require('cavediver').load_session, 't') }
	]])
	child.settle(300)
	eq({ got = got, slots = child.slots() }, { got = { true }, slots = '⦉c⦊ [d] ⟦-⟧' })
end

-- One process: a save, then a load from idle, then a close and a reopen.
T['T353 [char] (S1) after a load from idle, closes and <M-S-w> use one closed stack'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e b', ':e c' })
	eq(Misc.save(child), { true })
	eq(Misc.load(child), { true })
	child.settle(300)
	child.steps({ ':e a' })
	child.cmd('bdelete c.txt')
	child.settle()
	child.steps({ '<M-S-w>' })
	eq(child.shown(), 'c')
end

-- Oil -----------------------------------------------------------------------------

-- Oil is stood in for by an acwrite buffer named oil://<project>/ with
-- filetype oil. The manager brings the files back, then the oil buffer into
-- the window, with no events.
local OIL = [[
	local b = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(b, 'oil://' .. vim.fn.getcwd() .. '/')
	vim.bo[b].buftype = 'acwrite'
	vim.bo[b].filetype = 'oil'
]]
T['T324 [char] (S2) an oil window comes back as oil, with oil_original_buffer set from its current slot'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.lua(OIL .. 'vim.api.nvim_win_set_buf(0, b)')
	child.settle()
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	local oil = child.lua(OIL .. [[
		local ei = vim.o.eventignore
		vim.o.eventignore = 'all'
		vim.api.nvim_win_set_buf(0, b)
		vim.o.eventignore = ei
		return b
	]])
	eq(Misc.load(child), { true })
	child.settle(300)
	local got = child.lua([[
		local oil = ...
		return {
			shows_oil = vim.api.nvim_get_current_buf() == oil,
			original = vim.w.oil_original_buffer == vim.fn.bufnr(_G.CDV_TEST.root .. '/b.txt'),
			oil_registered = require('cavediver.domains.history').get_hash_from_buffer(oil) ~= nil,
		}
	]], { oil })
	eq({ got = got, slots = child.slots() },
		{ got = { shows_oil = true, original = true, oil_registered = false }, slots = '⦉a⦊ [b] ⟦-⟧' })
end

-- The closed-stack picker ---------------------------------------------------------
--
-- Entry lines are found by the file name they hold: the spec gives the line
-- format only for No Name entries, and only as an example.

-- b closed, then c; a and d stay open.
local function two_closed()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', ':e d' })
	child.cmd('bdelete b.txt')
	child.cmd('bdelete c.txt')
	child.settle()
	eq(child.closed(), 'b,c')
end

T['T325 [target] (S2) :CavediverClosed opens an editable buffer listing the closed entries, newest first, and no open buffer'] = function()
	two_closed()
	local p = S2.picker(child)
	local c, b = S2.line_of(p.lines, 'c.txt'), S2.line_of(p.lines, 'b.txt')
	eq({
		modifiable = p.modifiable,
		c_above_b = c ~= nil and b ~= nil and c < b,
		a_listed = S2.line_of(p.lines, 'a.txt') ~= nil,
		d_listed = S2.line_of(p.lines, 'd.txt') ~= nil,
	}, { modifiable = true, c_above_b = true, a_listed = false, d_listed = false })
end

-- The format is given as an example (`[No Name] "TODO: fix the…"  lua`), so the
-- pieces are matched on their own; a digit stands for the close time.
T['T326 [target] (S2) a No Name entry shows its first line in quotes, its filetype and its close time'] = function()
	child.setup()
	child.steps({ ':e a' })
	S2.noname(child, { 'TODO: fix the thing', 'more' }, 'lua')
	child.steps({ '<M-.>' })
	eq(child.shown(), 'a')
	local p = S2.picker(child)
	local i = S2.line_of(p.lines, '[No Name]')
	local line = i and p.lines[i] or ''
	eq({ listed = i ~= nil, quoted = line:find('"TODO: fix the', 1, true) ~= nil,
		filetype = line:find('lua', 1, true) ~= nil, time = line:find('%d') ~= nil },
		{ listed = true, quoted = true, filetype = true, time = true })
end

T['T327 [target] (S2) reordering the picker\'s lines and :w reorders the stack'] = function()
	two_closed()
	local p = S2.picker(child)
	local c, b = S2.line_of(p.lines, 'c.txt'), S2.line_of(p.lines, 'b.txt')
	eq(c ~= nil and b ~= nil, true)
	local lines = vim.deepcopy(p.lines)
	lines[c], lines[b] = p.lines[b], p.lines[c]
	S2.write_picker(child, p, lines)
	child.lua('vim.api.nvim_set_current_win(...)', { p.came_from })
	child.settle()
	child.steps({ '<M-S-w>' })
	eq(child.shown(p.came_from), 'b')
end

-- <CR> is typed into the picker, since its own mapping isn't known in advance.
T['T328 [target] (S2) <CR> in the picker reopens the entry under the cursor in the window you came from'] = function()
	two_closed()
	local p = S2.picker(child)
	local b = S2.line_of(p.lines, 'b.txt')
	eq(b ~= nil, true)
	child.lua([[
		local win, line = ...
		vim.api.nvim_win_set_cursor(win, { line, 0 })
		vim.api.nvim_feedkeys(vim.keycode('<CR>'), 'mx', false)
	]], { p.win, b })
	child.settle()
	eq({ shown = child.shown(p.came_from), closed = child.closed() }, { shown = 'b', closed = 'c' })
end

T['T329 [target] (S2) deleting a file\'s line in the picker and :w discards it'] = function()
	two_closed()
	local p = S2.picker(child)
	local c = S2.line_of(p.lines, 'c.txt')
	eq(c ~= nil, true)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, c)
	S2.write_picker(child, p, lines)
	eq(child.closed(), 'b')
end

-- T318's state, with x closed in the first tab and c in the session's tab;
-- the first tab is current.
local function two_pools(s)
	local w1, w2 = tab_session(s)
	child.cmd('tabprevious')
	child.cmd('bdelete x.txt')
	child.cmd('tabnext')
	child.cmd('bdelete c.txt')
	child.cmd('tabprevious')
	child.settle()
	return w1, w2
end

-- A header is a line that isn't empty and names neither entry.
T['T330 [target] (S2) the picker shows each pool as a header with its closed entries under it'] = function()
	local s = S2.shared()
	two_pools(s)
	local p = S2.picker(child)
	local x, c = S2.line_of(p.lines, 'x.txt'), S2.line_of(p.lines, 'c.txt')
	eq(x ~= nil and c ~= nil, true)
	local function header(i)
		local l = p.lines[i] or ''
		return vim.trim(l) ~= '' and not l:find('x.txt', 1, true) and not l:find('c.txt', 1, true)
	end
	local between = false
	for i = math.min(x, c) + 1, math.max(x, c) - 1 do
		if header(i) then between = true end
	end
	eq({ first_line_is_header = header(1), header_between_pools = between },
		{ first_line_is_header = true, header_between_pools = true })
end

-- c's line is cut from the session's pool and pasted right under x's line.
T['T331 [target] (S2) pools merge by moving a line under another pool\'s header'] = function()
	local s = S2.shared()
	local w1, w2 = two_pools(s)
	local p = S2.picker(child)
	local c = S2.line_of(p.lines, 'c.txt')
	eq(c ~= nil and S2.line_of(p.lines, 'x.txt') ~= nil, true)
	local lines = vim.deepcopy(p.lines)
	local moved = table.remove(lines, c)
	table.insert(lines, S2.line_of(lines, 'x.txt') + 1, moved)
	S2.write_picker(child, p, lines)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	child.settle()
	local first_tab = {}
	for _ = 1, 2 do
		child.steps({ '<M-S-w>' })
		table.insert(first_tab, child.shown(w1))
	end
	child.cmd('tabnext')
	child.settle()
	child.steps({ '<M-S-w>' })
	eq({ first_tab = first_tab, session_tab = child.shown(w2) }, { first_tab = { 'x', 'c' }, session_tab = 'd' })
end

return T
