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
	child.settle()
	child.steps({ '<M-m>' })
	eq({ closed = child.closed(), states = S2.states(child), x = S2.registered(child, 'x') },
		{ closed = 'd', states = { nav = 'cycling', hist = 'detached' }, x = true })
	child.cmd('noautocmd edit c.txt')
	eq(Misc.load(child), { true })
	child.settle(300)
	-- d's close was written into the file as it happened, so it comes back from there, once
	eq({ slots = child.slots(), closed = child.closed(), states = S2.states(child), x = S2.registered(child, 'x') },
		{ slots = '⦉b⦊ [c] ⟦-⟧', closed = 'd', states = { nav = 'normal', hist = 'attached' }, x = false })
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

-- Every name the loader tries is recorded, the real loader still doing the
-- loading. On macOS the bare name would load the system's own libcrypto.
T['T480 [char] (S2) libcrypto is loaded by its versioned name first'] = function()
	child.setup()
	child.steps({ ':e a' })
	child.lua([[
		local ffi = require('ffi')
		local real = ffi.load
		_G.CDV_TRIED = {}
		ffi.load = function(name, ...)
			table.insert(_G.CDV_TRIED, tostring(name))
			return real(name, ...)
		end
	]])
	eq(Misc.save(child), { true })
	eq(child.lua('return _G.CDV_TRIED[1]'), 'libcrypto.so.3')
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
	pcall(child.lua, 'vim.uv.kill(vim.uv.os_getpid(), "sigkill")') -- the crash: no VimLeavePre
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

-- A No Name text closed with <M-.> keeps its hash on the closed stack. Each
-- fresh editor is a new process, encoding JSON in its own key order; the
-- closed lists read the text, as drawing its first line does, and q leaves
-- them unedited.
T['T472 [char] (S2) an unchanged No Name text keeps its file in every editor'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	S2.noname(child, { 'same text' })
	child.steps({ '<M-.>' })
	eq(Misc.save(child), { true })
	local one = S2.scratch_files(s.session_dir)
	eq(#one, 1)
	for _ = 1, 5 do
		S2.start(child, s)
		Misc.restore(child, { 'a', 'b' }, 'b')
		eq(Misc.load(child), { true })
		child.settle(300)
		S2.picker(child)
		child.type_keys('q')
		child.settle()
		eq(Misc.save(child), { true })
		eq(S2.scratch_files(s.session_dir), one)
	end
end

-- A No Name text closed with <M-.> and saved under A is held unread in the
-- next editor, which saves B. A's files then go, as another editor's save of
-- A would sweep the text's file.
T['T473 [char] (S2) a closed No Name text read from another session\'s file is kept when that file goes'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	S2.noname(child, { 'carried text' })
	child.steps({ '<M-.>' })
	eq(S2.save(child, 'A'), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child, 'A'), { true })
	child.settle(300)
	eq(S2.save(child, 'B'), { true })
	local a = S2.main_file(s.session_dir, S2.cwd(child), 'A')
	vim.fn.delete(s.session_dir .. a)
	vim.fn.delete(s.session_dir .. a .. '.d', 'rf')
	child.messages()
	eq(S2.save(child, 'B'), { true })
	eq(S2.has(child.messages(), 'integrity check'), false)

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child, 'B'), { true })
	child.settle(300)
	child.steps({ '<M-S-w>' })
	eq(S2.holding(child, 'carried text'), 1)
end

-- The No Name text is in a second tab, its cursor on its third line; the
-- save runs from the first tab.
T['T474 [char] (S2) an open No Name text shown in another tab keeps its cursor'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('tabnew')
	S2.noname(child, { 'one', 'two', 'three' })
	child.lua('vim.api.nvim_win_set_cursor(0, { 3, 2 })')
	child.cmd('tabprevious')
	child.settle()
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a' }, 'a')
	eq(Misc.load(child), { true })
	child.settle(300)
	local b = S2.buffer_holding(child, 'three')
	eq(b ~= nil, true)
	child.cmd('buffer ' .. b)
	child.settle()
	eq(child.lua('return vim.api.nvim_win_get_cursor(0)'), { 3, 2 })
end

-- c is closed with <M-.>, and its buffer, unlisted after :bdelete, shown again
-- with :buffer, which doesn't list it: the window visits a buffer cavediver
-- doesn't track, whose file it knows.
T['T475 [char] (S2) a closed file shown again through its unlisted buffer is not an outsider, and the load goes through'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.cmd('buffer ' .. child.lua('return vim.fn.bufnr(_G.CDV_TEST.root .. "/c.txt")'))
	child.settle()
	eq(child.lua('return vim.bo.buflisted'), false)
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b', 'c' }, 'c')
	child.messages()
	local dumps = child.dump_files()
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ errors = Misc.errors(child), dump = child.dumped_since(dumps), triquetra = child.slots() ~= 'no triquetra' },
		{ errors = {}, dump = nil, triquetra = true })
end

-- The text is open in the ternary, the window on b, when the session is saved;
-- its buffer is then set to nofile, which takes it out of cavediver's hands.
T['T476 [char] (S2) a saved-open No Name text whose buffer turned nofile is reopened from its file, and the load goes through'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	local n = S2.noname(child, { 'turned text' })
	child.steps({ ':e b' })
	eq(Misc.save(child), { true })
	child.lua('vim.bo[...].buftype = "nofile"', { n })
	child.settle(300)
	child.messages()
	local dumps = child.dump_files()
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ errors = Misc.errors(child), dump = child.dumped_since(dumps), holding = S2.holding(child, 'turned text') },
		{ errors = {}, dump = nil, holding = 2 })
end

-- libcrypto made unloadable in the fresh editor before anything has needed it.
T['T477 [char] (S1) a load whose file can\'t be read for an environment reason fails inside its hook'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })

	S2.start(child, s)
	child.lua([[
		local ffi = require('ffi')
		local real = ffi.load
		ffi.load = function(name, ...)
			if tostring(name):match('crypto') then error('simulated: library not found') end
			return real(name, ...)
		end
	]])
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.messages()
	eq(Misc.load(child), { true })
	child.settle(300)
	local msgs = child.messages()
	eq({ failed = S2.has(msgs, 'failed during transition'), state = child.lua('return require("cavediver.domains.storage").sm:state()') },
		{ failed = true, state = 'idle' })
end

-- The No Name text is written as notes.txt and the quit's VimLeavePre runs in the same call, before
-- the write has settled; the process is then killed, so nothing else runs.
T['T508 [char] (S2) the quit\'s records come after the settle work'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })
	S2.noname(child, { 'note' })
	child.lua([[vim.cmd('write ' .. vim.fn.fnameescape(_G.CDV_TEST.root .. '/notes.txt')); vim.cmd('doautocmd VimLeavePre')]])
	pcall(child.lua, 'vim.uv.kill(vim.uv.os_getpid(), "sigkill")')
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.closed():match('NONAME') == nil, true)
end

-- x is wiped, so its window lands after the delete, and the session loads in the same call.
T['T509 [char] (A19, S1) a landing queued before a whole-editor load doesn\'t move the loaded window'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	eq(Misc.save(child), { true })
	child.steps({ ':e x' })
	child.lua([[vim.cmd('bwipeout ' .. vim.fn.bufnr(_G.CDV_TEST.root .. '/x.txt')); require('cavediver').load_session(vim.fn.getcwd())]])
	child.settle(300)
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
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

-- A tab session saved from a tab whose directory is aaa/: the old wiring named
-- its cavediver file after that cwd. The project's own old file, under the
-- global cwd, belongs to another session, so the script mustn't take it.
T['T478 [char] (S2) the migration script finds a tab session\'s old file under its tab\'s directory, and writes it as a tab session'] = function()
	local s = S2.shared()
	local _, migrate = old_session(s)
	local root = S2.cwd(child)
	local tab = root .. '/aaa'
	vim.fn.mkdir(tab, 'p')
	local function xor(text, key)
		local out = {}
		for n = 1, #text do
			out[n] = string.char(bit.bxor(text:byte(n), key:byte(((n - 1) % #key) + 1)))
		end
		return vim.base64.encode(table.concat(out))
	end
	local function hash(path) return vim.fn.sha256(path .. '\n'):sub(1, 16) end
	local old = {
		buffers = { window = {}, global = { [hash(root .. '/d.txt')] = 4 } },
		windows = { { hash(root .. '/d.txt'), vim.NIL, {}, vim.NIL, {}, {} } },
		closed = { xor(root .. '/e.txt', tab) },
		noname_content = {},
	}
	vim.fn.writefile({ vim.json.encode(old) }, s.session_dir .. vim.fn.sha256(tab .. '\n'):sub(1, 32) .. '.json')
	local resession_dir = vim.fn.stdpath('data') .. '/cavediver_test_sessions/'
	vim.fn.delete(resession_dir, 'rf')
	vim.fn.mkdir(resession_dir, 'p')
	local session = {
		global = { cwd = root },
		buffers = { { name = root .. '/d.txt' } },
		tab_scoped = true,
		tabs = { { cwd = tab } },
	}
	vim.fn.writefile({ vim.json.encode(session) }, resession_dir .. tab:gsub('/', '_'):gsub(':', '_') .. '.json')

	local run = migrate()
	eq({ code = run.code, converted = run.stdout:find('converted 1 session', 1, true) ~= nil }, { code = 0, converted = true })
	local project_old = s.session_dir .. vim.fn.sha256(root .. '\n'):sub(1, 32) .. '.json'
	eq({ left = vim.fn.filereadable(project_old), marked = vim.fn.filereadable(project_old .. '.migrated') }, { left = 1, marked = 0 })
	local got = child.lua([[
		local tab, e, b = ...
		local data = require('cavediver.domains.storage.routines').read_session(tab, tab)
		return { scope = data and data.scope, e = data ~= nil and vim.tbl_contains(data.closed, e), b = data ~= nil and vim.tbl_contains(data.closed, b) }
	]], { tab, hash(root .. '/e.txt'), hash(root .. '/b.txt') })
	eq(got, { scope = 'tab', e = true, b = false })
end

-- The old file found through resession's session list isn't JSON.
T['T479 [char] (S2) the migration script names an old file it can\'t read, and leaves it'] = function()
	local s = S2.shared()
	local old_path, migrate = old_session(s)
	vim.fn.writefile({ 'not json' }, old_path)
	local run = migrate()
	eq({ code = run.code, named = run.stdout:find("can't be read", 1, true) ~= nil, left = vim.fn.filereadable(old_path) },
		{ code = 0, named = true, left = 1 })
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
	local function in_file()
		return child.lua([[
			local saved = require('cavediver.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), nil)
			local out = {}
			for _, h in ipairs(saved.closed or {}) do
				table.insert(out, vim.fn.fnamemodify(saved.paths[h] or h, ':t:r'))
			end
			return table.concat(out, ',')
		]])
	end
	local saved = in_file()
	local live = {}
	for _ = 1, 2 do
		child.steps({ '<M-S-w>' })
		table.insert(live, child.shown(w1))
	end
	child.settle(1200)

	-- e and x are open again, and the file follows them
	S2.start(child, s)
	Misc.restore(child, { 't' }, 't')
	eq(S2.load(child), { true })
	child.settle(300)
	child.steps({ '<M-S-w>' })
	eq({ saved = saved, live = live, after = child.shown() }, { saved = 'x,c,e', live = { 'e', 'x' }, after = 'c' })
end

-- No TabClosedPre hook calls save_session here: cavediver writes the session's
-- records itself as the tab closes (the author, 2026-10-23). The load
-- afterwards brings d back and not c, as a manager would after c was closed.
T['T322 [char] (S2) a tab session\'s tab closed with nothing wired writes its records, and gives no notice'] = function()
	local s = S2.shared()
	tab_session(s)
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

-- The session u has no cavediver file; the hint says it's a tab session.
T['T354 [char] (S2) a tab session with no file, loaded with the hint, starts only its tab fresh'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e x', ':e t' })
	child.cmd('bdelete a.txt')
	child.settle()
	local w1 = child.lua('return vim.api.nvim_get_current_win()')
	eq(S2.save(child), { true })
	local got = child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		return { pcall(require('cavediver').load_session, 'u', { tab = vim.api.nvim_get_current_tabpage() }) }
	]])
	child.settle(300)
	local w2 = child.lua('return vim.api.nvim_get_current_win()')
	local state = { got = got, session_tab = child.slots(w2), first_tab = child.slots(w1), closed = child.closed() }
	child.messages()
	eq(child.lua('return { pcall(require("cavediver").save_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	state.notices = S2.notices(child.messages())
	eq(state, { got = { true }, session_tab = '⦉-⦊ [d] ⟦-⟧', first_tab = '⦉x⦊ [t] ⟦-⟧', closed = 'a', notices = {} })
end

-- The hint is read (T354, T367); a usable file's scope wins over it.
T['T355 [char] (S2) a file\'s scope wins over the hint'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e c', ':e d' })
	eq(Misc.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'c', 'd' }, 'd')
	local got = child.lua('return { pcall(require("cavediver").load_session, vim.fn.getcwd(), { tab = vim.api.nvim_get_current_tabpage() }) }')
	child.settle(300)
	eq({ got = got, slots = child.slots(),
		editor = child.lua('return require("cavediver.domains.history").routines.current_pool().id') },
		{ got = { true }, slots = '⦉c⦊ [d] ⟦-⟧', editor = '' })
end

-- The session directory is read-only, so the records can't be written: the
-- failure path of T322's write.
T['T356 [char] (S2) a tab session\'s records that can\'t be written as its tab closes keep its list, with a warning'] = function()
	local s = S2.shared()
	tab_session(s)
	vim.fn.setfperm(s.session_dir, 'r-xr-xr-x')
	child.cmd('bdelete c.txt')
	child.settle(300)
	child.messages()
	child.cmd('tabclose')
	child.settle(300)
	local warned = #S2.notices(child.messages()) > 0
	local kept = child.lua([[
		local H = require('cavediver.domains.history')
		for id, pool in pairs(H.routines.pools()) do
			if id ~= '' and next(pool.tabs) == nil then
				return #pool.closed
			end
		end
		return 0
	]])
	vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
	eq({ warned = warned, kept = kept }, { warned = true, kept = 1 })
end

-- t is open in a second tab, where e is visited and closed; e isn't in t's
-- saved slots, so only t's list brings it back. A third tab loads t too.
T['T357 [char] (S2) a session loaded into another tab while open takes its list along'] = function()
	local s = S2.shared()
	tab_session(s)
	child.steps({ ':e e', ':e d' })
	child.cmd('bdelete e.txt')
	child.settle()
	local got = child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		return { pcall(require('cavediver').load_session, 't') }
	]])
	child.settle(300)
	child.steps({ '<M-S-w>' })
	eq({ got = got, reopened = child.shown() }, { got = { true }, reopened = 'e' })
end

-- The whole editor saved, then a tab session loaded (so resession would leave
-- the whole editor's session unsaved at quit), its tab closed, and work in the
-- first tab; then a quit with nothing saved.
T['T358 [char] (S2) quitting writes every known session\'s records'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(S2.save(child), { true })
	eq(S2.load_tab_session(child, 't'), { true })
	child.cmd('tabclose')
	child.settle(300)
	S2.noname(child, { 'note' })
	child.steps({ ':e t' })

	S2.start(child, s)
	Misc.restore(child, { 't' }, 't')
	eq(S2.load(child), { true })
	child.settle(300)
	eq(S2.holding(child, 'note'), 1)
end

-- e is visited in t's tab; then e is closed, the tab closes, the quit's
-- VimLeavePre runs and the process is killed, all in one call, so no write
-- gets its tick, as at a real quit. e isn't in t's saved slots, so only t's
-- list brings it back; the load afterwards brings d back and not e.
T['T358 [char] (S2) a quit in the same batch as a tab close writes that tab session\'s records'] = function()
	local s = S2.shared()
	tab_session(s)
	child.steps({ ':e e', ':e d' })
	pcall(child.lua, [[
		vim.cmd('bdelete e.txt')
		vim.cmd('tabclose')
		vim.api.nvim_exec_autocmds('VimLeavePre', {})
		vim.uv.kill(vim.uv.os_getpid(), 'sigkill')
	]])
	S2.start(child, s)
	local got = child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		return { pcall(require('cavediver').load_session, 't') }
	]])
	child.settle(300)
	child.steps({ '<M-S-w>' })
	eq({ got = got, reopened = child.shown() }, { got = { true }, reopened = 'e' })
end

-- a is closed after the save and sits in no slot, so only a write after the
-- close can bring it back; the process is then killed, with no VimLeavePre.
T['T359 [char] (S2) a crash loses no close'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c' })
	eq(Misc.save(child), { true })
	child.cmd('bdelete a.txt')
	child.settle(1200)
	pcall(child.lua, 'vim.uv.kill(vim.uv.os_getpid(), "sigkill")')
	S2.start(child, s)
	Misc.restore(child, { 'b', 'c' }, 'c')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.closed(), 'a')
end

-- a is closed, and its write lands; then, in one go, the manager's teardown
-- closes b and c with events on, and the load of another session follows.
T['T360 [char] (S2) a load cancels a write still pending, so the teardown\'s closes stay out of the old file'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c' })
	eq(S2.save(child, 'one'), { true })
	child.cmd('bdelete a.txt')
	child.settle()
	child.lua([[
		vim.cmd('enew')
		vim.cmd('bdelete b.txt')
		vim.cmd('bdelete c.txt')
		require('cavediver').load_session('two')
	]])
	child.settle(1500)
	local closed = child.lua([[
		local saved = require('cavediver.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), 'one')
		local out = {}
		for _, h in ipairs(saved.closed or {}) do
			table.insert(out, vim.fn.fnamemodify(saved.paths[h] or h, ':t:r'))
		end
		table.sort(out)
		return table.concat(out, ',')
	]])
	eq(closed, 'a')
end

-- Closes are written on every change; the write never makes a file.
T['T361 [char] (S2) records never make a file'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.cmd('bdelete a.txt')
	child.settle(1200)
	eq(Misc.files_in(s.session_dir), {})
end

-- The global directory moves to another project with no load, as a switch
-- with post_load unwired leaves it.
T['T362 [char] (S2) records aren\'t written into a session the editor has moved away from'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c' })
	eq(S2.save(child), { true })
	local file = S2.main_file(s.session_dir, S2.cwd(child), nil)
	local before = S2.read(s.session_dir .. file)
	child.cmd('cd ' .. Misc.make_project())
	child.cmd('bdelete a.txt')
	child.settle(1200)
	eq(S2.read(s.session_dir .. file) == before, true)
end

-- The other editor saves after the file was removed, so with a new salt; this
-- editor then closes a, and its write has to use the new salt's key.
T['T363 [char] (S2) a session\'s key is kept by its directory and salt'] = function()
	local s = S2.shared()
	S2.start(child, s)
	S2.start(other, s)
	child.steps({ ':e a', ':e b', ':e c' })
	eq(S2.save(child), { true })
	local file = s.session_dir .. S2.main_file(s.session_dir, S2.cwd(child), nil)
	os.remove(file)
	other.steps({ ':e b', ':e c' })
	eq(S2.save(other), { true })
	other.stop()
	child.cmd('bdelete a.txt')
	child.settle(1200)

	S2.start(child, s)
	Misc.restore(child, { 'b', 'c' }, 'c')
	child.messages()
	eq(S2.load(child), { true })
	child.settle(300)
	eq({ integrity = S2.has(child.messages(), 'integrity'), closed = child.closed() }, { integrity = false, closed = 'a' })
end

-- A close, then disable() at once: the write it set off never lands.
T['T364 [char] (S2) disable() stops the writes'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c' })
	eq(S2.save(child), { true })
	local file = s.session_dir .. S2.main_file(s.session_dir, S2.cwd(child), nil)
	local before = S2.read(file)
	child.lua([[
		vim.cmd('bdelete a.txt')
		require('cavediver').disable()
	]])
	child.settle(1200)
	eq(S2.read(file) == before, true)
end

-- The whole editor is saved at ⦉a⦊ [b], and t from a second tab at ⦉c⦊ [d],
-- in one process, so c's buffer comes before d's. Back in the first tab, in
-- one go, as resession switches: a scratch buffer in the window, every listed
-- buffer deleted with events on, in buffer order (c goes on t's list, then
-- deleting d closes t's tab), the other tabs closed, and the load of another
-- session, which has no file.
T['T365 [char] (S2) a whole-editor switch keeps the manager\'s teardown out of an open tab session\'s file'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(S2.save(child, 'main'), { true })
	child.cmd('tabnew')
	child.steps({ ':e c', ':e d' })
	eq(child.lua('return { pcall(require("cavediver").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'),
		{ true })
	child.cmd('tabprevious')
	child.settle()
	child.lua([[
		local scratch = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_win_set_buf(0, scratch)
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.bo[b].buflisted then
				vim.api.nvim_buf_delete(b, { force = true })
			end
		end
		vim.cmd('silent! tabonly')
		require('cavediver').load_session('two')
	]])
	child.settle(1500)
	local closed = child.lua([[
		local saved = require('cavediver.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), 't')
		local out = {}
		for _, h in ipairs(saved.closed or {}) do
			table.insert(out, vim.fn.fnamemodify(saved.paths[h] or h, ':t:r'))
		end
		return table.concat(out, ',')
	]])
	eq(closed, '')
end

-- In T318's state, c is closed in the session's tab and stays in its ternary;
-- that tab is then saved as u ("save as"), so t has no tab left. The load of t
-- afterwards brings d back and not c, as a manager would after c was closed.
T['T366 [char] (S2) a tab saved as another session writes the one it leaves, and carries the closed files its slots hold'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s)
	child.cmd('bdelete c.txt')
	child.settle()
	eq(child.slots(w2), '⦉c⦊ [d] ⟦-⟧')
	eq(child.lua('return { pcall(require("cavediver").save_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'),
		{ true })
	child.settle(300)
	child.lua('require("cavediver.domains.history").cleanup_system()')
	child.settle(300)
	local state = child.lua([[
		local H = require('cavediver.domains.history')
		local tabless = 0
		for id, pool in pairs(H.routines.pools()) do
			if id ~= '' and next(pool.tabs) == nil then
				tabless = tabless + 1
			end
		end
		local u = {}
		for _, h in ipairs(H.routines.current_pool().closed) do
			table.insert(u, vim.fn.fnamemodify(H.get_filepath_from_hash(h) or h, ':t:r'))
		end
		return { pool = H.routines.current_pool().name, u = table.concat(u, ','), tabless = tabless }
	]])
	state.slots = child.slots(w2)
	local got = child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		return { pcall(require('cavediver').load_session, 't') }
	]])
	child.settle(300)
	child.steps({ '<M-S-w>' })
	state.got, state.reopened = got, child.shown()
	eq(state, { pool = 'u', u = 'c', tabless = 0, slots = '⦉c⦊ [d] ⟦-⟧', got = { true }, reopened = 'c' })
end

-- The lists a closed file is on, by pool: the editor's as "", a tab session's
-- by its name, and whether each pool has a tab.
local LISTS = [[
	local H = require('cavediver.domains.history')
	local h = H.get_hash_from_filepath(vim.fn.getcwd(-1, -1) .. '/' .. ... .. '.txt')
	local out = {}
	for id, pool in pairs(H.routines.pools()) do
		if vim.tbl_contains(pool.closed, h) then
			table.insert(out, (id == '' and 'editor' or pool.name) .. (next(pool.tabs) == nil and id ~= '' and ' (no tab)' or ''))
		end
	end
	table.sort(out)
	return table.concat(out, ',')
]]

-- Case A: the first tab is in no session, so b is closed on the editor's list;
-- the tab is then saved as notes.
T['T368 [char] (S2) a tab saved as a session for the first time carries the closed files its slots hold'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('bdelete b.txt')
	child.settle()
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	eq(child.lua('return { pcall(require("cavediver").save_session, "notes", { tab = vim.api.nvim_get_current_tabpage() }) }'),
		{ true })
	child.settle(300)
	local lists = child.lua(LISTS, { 'b' })
	child.steps({ '<M-S-w>' })
	eq({ lists = lists, reopened = child.shown() }, { lists = 'editor,notes', reopened = 'b' })
end

-- Case B: t is open in the second tab and, loaded again, into a third, which
-- takes it (T369), so the second holds t_DETACHED; c is closed in the second,
-- which is then saved as u. No whole-editor save ran, so the detached list,
-- left with no tab, stays in memory (T382).
T['T368 [char] (S2) a tab whose session another tab took, saved as a new session, carries the closed files its slots hold'] = function()
	local s = S2.shared()
	tab_session(s)
	eq(S2.load_tab_session(child, 't'), { true })
	child.cmd('tabprevious')
	child.cmd('bdelete c.txt')
	child.settle()
	eq(child.lua('return { pcall(require("cavediver").save_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'),
		{ true })
	child.settle(300)
	local lists = child.lua(LISTS, { 'c' })
	child.steps({ '<M-S-w>' })
	eq({ lists = lists, reopened = child.shown() }, { lists = 't,t_DETACHED (no tab),u', reopened = 'c' })
end

-- In t's tab, x is closed after it has left the slots, and c from the
-- ternary; then t is loaded into a third tab, with d restored and not c.
T['T369 [char] (S2) a tab session is in one tab at a time, and the tab it leaves keeps a detached list'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s)
	child.steps({ ':e x', ':e c', ':e d' })
	child.cmd('bdelete x.txt')
	child.cmd('bdelete c.txt')
	child.settle()
	eq(child.slots(w2), '⦉c⦊ [d] ⟦-⟧')
	local got = child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		return { pcall(require('cavediver').load_session, 't') }
	]])
	child.settle(300)
	local lists = child.lua([[
		local H = require('cavediver.domains.history')
		local function list(tabpage)
			local pool = H.routines.pool_of_tab(tabpage)
			local out = {}
			for _, h in ipairs(pool.closed) do
				table.insert(out, vim.fn.fnamemodify(H.get_filepath_from_hash(h) or h, ':t:r'))
			end
			return (pool.name or '') .. ':' .. table.concat(out, ',')
		end
		return { second = list(vim.api.nvim_win_get_tabpage(...)), third = list(vim.api.nvim_get_current_tabpage()) }
	]], { w2 })
	eq({ got = got, lists = lists }, { got = { true }, lists = { second = 't_DETACHED:x,c', third = 't:x,c' } })
end

-- T369's state: in t's tab (the second), x closed after it has left the slots
-- and c from the ternary; then t loaded into a third tab, with d restored and
-- not c. Returns the second tab's window and the third's.
local function detached_state(s)
	local _, w2 = tab_session(s)
	child.steps({ ':e x', ':e c', ':e d' })
	child.cmd('bdelete x.txt')
	child.cmd('bdelete c.txt')
	child.settle()
	child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		require('cavediver').load_session('t')
	]])
	child.settle(300)
	return w2, child.lua('return vim.api.nvim_get_current_win()')
end

-- A tab's list, as its name and its entries.
local LIST_OF = [[
	local H = require('cavediver.domains.history')
	local pool = H.routines.pool_of_tab(vim.api.nvim_win_get_tabpage(...))
	local out = {}
	for _, h in ipairs(pool.closed) do
		table.insert(out, vim.fn.fnamemodify(H.get_filepath_from_hash(h) or h, ':t:r'))
	end
	return (pool.name or '') .. ':' .. table.concat(out, ',')
]]

-- The whole editor's file, as names: its closed list, and each detached list.
local EDITOR_FILE = [[
	local saved = require('cavediver.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), nil)
	local function names(hashes)
		local out = {}
		for _, h in ipairs(hashes or {}) do
			table.insert(out, vim.fn.fnamemodify(saved.paths[h] or h, ':t:r'))
		end
		table.sort(out)
		return table.concat(out, ',')
	end
	local detached = {}
	for _, list in ipairs(saved.detached or {}) do
		detached[list.label] = { closed = names(list.closed), windows = #(list.windows or {}) }
	end
	return { closed = names(saved.closed), detached = detached }
]]

-- t is open in the second tab, c closed there; a third tab, opened on d, is
-- saved as t.
T['T378 [char] (S2) a save of a tab as a session open in another tab takes it from that tab'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s)
	child.cmd('bdelete c.txt')
	child.settle()
	local got = child.lua([[
		vim.cmd('tabnew')
		vim.cmd('edit d.txt')
		return { pcall(require('cavediver').save_session, 't', { tab = vim.api.nvim_get_current_tabpage() }) }
	]])
	child.settle(300)
	local w3 = child.lua('return vim.api.nvim_get_current_win()')
	eq({ got = got, second = child.lua(LIST_OF, { w2 }), third = child.lua(LIST_OF, { w3 }):match('^[^:]*') },
		{ got = { true }, second = 't_DETACHED:c', third = 't' })
end

T['T379 [char] (S2) a detached tab\'s closes and <M-S-w> use its own list'] = function()
	local s = S2.shared()
	local w2, w3 = detached_state(s)
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.steps({ ':e e', ':e d' })
	child.cmd('bdelete e.txt')
	child.settle()
	local lists = { second = child.lua(LIST_OF, { w2 }), third = child.lua(LIST_OF, { w3 }) }
	child.steps({ '<M-S-w>' })
	eq({ lists = lists, reopened = child.shown(w2) },
		{ lists = { second = 't_DETACHED:x,c,e', third = 't:x,c' }, reopened = 'e' })
end

-- A fresh process restores the three tabs as they were (e not restored) and
-- loads the whole editor.
T['T380 [char] (S2) a whole-editor save writes a detached list apart, and a whole-editor load brings it back to its tab'] = function()
	local s = S2.shared()
	local w2 = detached_state(s)
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.steps({ ':e e', ':e d' })
	child.cmd('bdelete e.txt')
	child.settle()
	eq(S2.save(child), { true })
	local file = child.lua(EDITOR_FILE)

	S2.start(child, s)
	S2.restore_tabs(child, { { files = { 'x', 't' }, shown = 't' }, { files = { 'c', 'd' }, shown = 'd' }, { files = { 'c', 'd' }, shown = 'd' } })
	eq(S2.load(child), { true })
	child.settle(300)
	child.cmd('tabnext 2')
	child.settle()
	local second = child.lua(LIST_OF, { child.lua('return vim.api.nvim_get_current_win()') })
	child.steps({ '<M-S-w>' })
	eq({ e_in_closed = file.closed:find('e') ~= nil, detached = file.detached.t_DETACHED and file.detached.t_DETACHED.closed,
		second = second:match('^[^:]*'), reopened = child.shown() },
		{ e_in_closed = false, detached = 'c,e,x', second = 't_DETACHED', reopened = 'e' })
end

-- The whole editor is saved right after T318's load, so it has a file.
T['T381 [char] (S2) a detached list left with no tab goes into the whole editor\'s file and stays there'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s)
	eq(S2.save(child), { true })
	child.steps({ ':e e', ':e d' })
	child.cmd('bdelete e.txt')
	child.settle()
	eq(S2.load_tab_session(child, 't'), { true })
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	local in_memory = child.lua([[
		for _, pool in pairs(require('cavediver.domains.history').routines.pools()) do
			if pool.name == 't_DETACHED' then return true end
		end
		return false
	]])
	local file = child.lua(EDITOR_FILE)
	local path = child.lua([[
		local saved = require('cavediver.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), nil)
		for _, list in ipairs(saved.detached or {}) do
			for _, h in ipairs(list.closed) do
				if (saved.paths[h] or ''):match('e%.txt$') then return true end
			end
		end
		return false
	]])
	eq(S2.save(child), { true })
	local again = child.lua(EDITOR_FILE)
	eq({ in_memory = in_memory, file = file.detached.t_DETACHED, path = path, again = again.detached.t_DETACHED },
		{ in_memory = false, file = { closed = 'e', windows = 0 }, path = true, again = { closed = 'e', windows = 0 } })
end

T['T382 [char] (S2) with no whole-editor file, a detached list left with no tab stays in memory, with a warning'] = function()
	local s = S2.shared()
	local w2 = detached_state(s)
	child.messages()
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	local kept = child.lua([[
		for _, pool in pairs(require('cavediver.domains.history').routines.pools()) do
			if pool.name == 't_DETACHED' then return next(pool.tabs) == nil end
		end
		return false
	]])
	eq({ kept = kept, warned = #S2.notices(child.messages()) > 0 }, { kept = true, warned = true })
end

T['T383 [char] (S2) a second detach of a session is numbered'] = function()
	local s = S2.shared()
	local w2, w3 = detached_state(s)
	child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		require('cavediver').load_session('t')
	]])
	child.settle(300)
	eq({ second = child.lua(LIST_OF, { w2 }):match('^[^:]*'), third = child.lua(LIST_OF, { w3 }):match('^[^:]*') },
		{ second = 't_DETACHED', third = 't_DETACHED_2' })
end

-- Keys typed into a window as a user would, so its own mappings run.
local function type_into(win, keys)
	child.lua([[
		local win, keys = ...
		vim.api.nvim_set_current_win(win)
		vim.api.nvim_feedkeys(vim.keycode(keys), 'mx', false)
	]], { win, keys })
	child.settle()
end

-- Case 8: T369's state, optionally with a whole-editor save right after T318's
-- load, then t loaded back into the second tab, which holds t_DETACHED, with d
-- restored there. Returns the second tab's window and the third's.
local function case8(s, saved)
	local _, w2 = tab_session(s)
	if saved then
		eq(S2.save(child), { true })
	end
	child.steps({ ':e x', ':e c', ':e d' })
	child.cmd('bdelete x.txt')
	child.cmd('bdelete c.txt')
	child.settle()
	child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		require('cavediver').load_session('t')
	]])
	child.settle(300)
	local w3 = child.lua('return vim.api.nvim_get_current_win()')
	child.lua([[
		vim.api.nvim_set_current_win(...)
		vim.cmd('noautocmd edit d.txt')
		require('cavediver').load_session('t')
	]], { w2 })
	child.settle(300)
	return w2, w3
end

-- The closed lists' window, when it's open: { buf, win, lines, cursor_line }.
local OPEN_LISTS = [==[
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].filetype == 'cavediver-closed-lists' then
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			return { buf = buf, win = win, lines = lines, cursor_line = lines[vim.api.nvim_win_get_cursor(win)[1]] }
		end
	end
	return vim.NIL
]==]

-- Whether a list of that name is in memory.
local IN_MEMORY = [[
	for _, pool in pairs(require('cavediver.domains.history').routines.pools()) do
		if pool.name == ... then return true end
	end
	return false
]]

T['T384 [char] (S2) t loaded back into its detached tab opens the closed lists, on t_DETACHED, and pushes the other tab out'] = function()
	local s = S2.shared()
	local w2, w3 = case8(s)
	local lists = child.lua(OPEN_LISTS)
	eq({ open = lists ~= vim.NIL, cursor = lists ~= vim.NIL and lists.cursor_line or nil,
		second = child.lua(LIST_OF, { w2 }):match('^[^:]*'), third = child.lua(LIST_OF, { w3 }):match('^[^:]*') },
		{ open = true, cursor = '≡t_DETACHED', second = 't', third = 't_DETACHED_2' })
end

-- t_DETACHED's entry lines go under t's header.
T['T385 [char] (S2) merging t_DETACHED in case 8\'s picker ends it'] = function()
	local s = S2.shared()
	case8(s, true)
	local p = child.lua(OPEN_LISTS)
	eq(p ~= vim.NIL, true)
	local lines, moved, under = {}, {}, nil
	local section
	for _, l in ipairs(p.lines) do
		if l:sub(1, 3) == '≡' then section = l end
		if section == '≡t_DETACHED' and l ~= '≡t_DETACHED' then
			table.insert(moved, l)
		else
			table.insert(lines, l)
		end
	end
	for i, l in ipairs(lines) do
		if l == '≡t' then under = i end
	end
	for k, l in ipairs(moved) do
		table.insert(lines, under + k, l)
	end
	S2.write_picker(child, p, lines)
	type_into(p.win, 'q')
	child.settle(300)
	eq({ in_memory = child.lua(IN_MEMORY, { 't_DETACHED' }), in_file = child.lua(EDITOR_FILE).detached.t_DETACHED ~= nil },
		{ in_memory = false, in_file = false })
end

T['T386 [char] (S2) leaving case 8\'s picker with t_DETACHED as it was sends it into the whole editor\'s file'] = function()
	local s = S2.shared()
	case8(s, true)
	local p = child.lua(OPEN_LISTS)
	eq(p ~= vim.NIL, true)
	type_into(p.win, 'q')
	child.settle(300)
	local file = child.lua(EDITOR_FILE).detached.t_DETACHED
	eq({ in_memory = child.lua(IN_MEMORY, { 't_DETACHED' }), in_file = file and file.closed },
		{ in_memory = false, in_file = 'c,x' })
end

T['T387 [char] (S2) t loaded into a tab other than its detached one opens no closed lists'] = function()
	local s = S2.shared()
	detached_state(s)
	child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		require('cavediver').load_session('t')
	]])
	child.settle(300)
	eq(child.lua(OPEN_LISTS), vim.NIL)
end

-- T381's state: t_DETACHED in the whole editor's file alone, holding e.
-- Returns the first tab's window.
local function file_only_state(s)
	local w1, w2 = tab_session(s)
	eq(S2.save(child), { true })
	child.steps({ ':e e', ':e d' })
	child.cmd('bdelete e.txt')
	child.settle()
	eq(S2.load_tab_session(child, 't'), { true })
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	eq(child.lua(EDITOR_FILE).detached.t_DETACHED, { closed = 'e', windows = 0 })
	return w1
end

-- The line of e under t_DETACHED's header, and that header's line.
local function under_detached(lines)
	local section, header, e
	for i, l in ipairs(lines) do
		if l:sub(1, 3) == '≡' then section = l end
		if l == '≡t_DETACHED' then header = i end
		if section == '≡t_DETACHED' and l:find('e.txt', 1, true) then e = i end
	end
	return header, e
end

T['T388 [char] (S2) a list in the whole editor\'s file alone shows in the picker, marked in the file, and is edited there'] = function()
	local s = S2.shared()
	local w1 = file_only_state(s)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	local p = S2.picker(child)
	local header, e = under_detached(p.lines)
	eq({ header = header ~= nil, e = e ~= nil }, { header = true, e = true })
	local marked = S2.shown_line(child, p.buf, header):find('in the file', 1, true) ~= nil
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, e)
	S2.write_picker(child, p, lines)
	child.settle(300)
	eq({ marked = marked, in_file = child.lua(EDITOR_FILE).detached.t_DETACHED ~= nil }, { marked = true, in_file = false })
end

T['T389 [char] (S2) a line moved out of a list in the file alone lands on the list it\'s moved under'] = function()
	local s = S2.shared()
	local w1 = file_only_state(s)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	local p = S2.picker(child)
	local _, e = under_detached(p.lines)
	eq(e ~= nil, true)
	local lines = vim.deepcopy(p.lines)
	local moved = table.remove(lines, e)
	table.insert(lines, 2, moved) -- under ≡editor, the first header
	S2.write_picker(child, p, lines)
	child.lua('if vim.api.nvim_win_is_valid(...) then vim.api.nvim_win_close(..., true) end', { p.win })
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	child.settle(300)
	child.steps({ '<M-S-w>' })
	eq({ in_file = child.lua(EDITOR_FILE).detached.t_DETACHED ~= nil, reopened = child.shown(w1) }, { in_file = false, reopened = 'e' })
end

-- T381's state with b closed too, so t_DETACHED in the file alone holds e and b.
-- Returns the first tab's window.
local function file_only_two(s)
	local w1, w2 = tab_session(s)
	eq(S2.save(child), { true })
	child.steps({ ':e e', ':e b', ':e d' })
	child.cmd('bdelete e.txt')
	child.cmd('bdelete b.txt')
	child.settle()
	eq(S2.load_tab_session(child, 't'), { true })
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	eq(child.lua(EDITOR_FILE).detached.t_DETACHED, { closed = 'b,e', windows = 0 })
	return w1
end

-- b's line is deleted, unsaved; then <CR> on e's line, both under t_DETACHED.
T['T390 [char] (S2) an edit to a list in the file alone survives <CR> on another of its entries'] = function()
	local s = S2.shared()
	local w1 = file_only_two(s)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	local p = S2.picker(child)
	local section, b, e
	for i, l in ipairs(p.lines) do
		if l:sub(1, 3) == '≡' then section = l end
		if section == '≡t_DETACHED' and l:find('b.txt', 1, true) then b = i end
		if section == '≡t_DETACHED' and l:find('e.txt', 1, true) then e = i end
	end
	eq(b ~= nil and e ~= nil, true)
	child.lua('local buf, i = ...; vim.api.nvim_buf_set_lines(buf, i - 1, i, false, {})', { p.buf, b })
	type_into(p.win, '') -- focus the picker
	child.lua('vim.api.nvim_win_set_cursor(..., { ' .. (e < b and e or e - 1) .. ', 0 })', { p.win })
	type_into(p.win, '<CR>')
	child.settle(300)
	eq({ in_file = child.lua(EDITOR_FILE).detached.t_DETACHED, reopened = child.shown(w1) }, { in_file = nil, reopened = 'e' })
end

-- The session directory is made read-only after the picker draws.
T['T391 [char] (S2) an edit to a list in the file alone that can\'t be written says so and stays on screen'] = function()
	local s = S2.shared()
	local w1 = file_only_state(s)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	local p = S2.picker(child)
	local _, e = under_detached(p.lines)
	eq(e ~= nil, true)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, e)
	vim.fn.setfperm(s.session_dir, 'r-xr-xr-x')
	child.messages()
	S2.write_picker(child, p, lines)
	local got = { warned = #S2.notices(child.messages()) > 0, modified = child.lua('return vim.bo[...].modified', { p.buf }) }
	vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
	eq(got, { warned = true, modified = true })
end

-- From the first tab, the hint names another tab: u has no file, so the tab
-- it names starts fresh; t's file loads into the tab it names.
T['T367 [char] (S2) the hint\'s tab is the tab the load works on, wherever the focus is'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e a', ':e x', ':e t' })
	child.cmd('bdelete a.txt')
	child.settle()
	local w1 = child.lua('return vim.api.nvim_get_current_win()')
	eq(S2.save(child), { true })
	local function load_into_new_tab(name)
		return child.lua([[
			local first = vim.api.nvim_get_current_tabpage()
			vim.cmd('noautocmd tabnew')
			local b = vim.fn.bufadd('c.txt')
			vim.fn.bufload(b)
			vim.bo[b].buflisted = true
			vim.cmd('noautocmd edit d.txt')
			local tab, win = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
			vim.cmd('noautocmd tabnext ' .. vim.api.nvim_tabpage_get_number(first))
			local ok = pcall(require('cavediver').load_session, ..., { tab = tab })
			return { ok = ok, win = win }
		]], { name })
	end
	local u = load_into_new_tab('u')
	child.settle(300)
	local t = load_into_new_tab('t')
	child.settle(300)
	eq({ u = u.ok, t = t.ok, u_tab = child.slots(u.win), t_tab = child.slots(t.win), first_tab = child.slots(w1), closed = child.closed() },
		{ u = true, t = true, u_tab = '⦉-⦊ [d] ⟦-⟧', t_tab = '⦉c⦊ [d] ⟦-⟧', first_tab = '⦉x⦊ [t] ⟦-⟧', closed = 'a' })
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

T['T325 [char] (S2) :CavediverClosed opens an editable buffer listing the closed entries, newest first, and no open buffer'] = function()
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
-- pieces are matched on their own; a digit stands for the close time. The line
-- is read as it shows, virtual text included (the decoration is virtual text).
T['T326 [char] (S2) a No Name entry shows its first line in quotes, its filetype and its close time'] = function()
	child.setup()
	child.steps({ ':e a' })
	S2.noname(child, { 'TODO: fix the thing', 'more' }, 'lua')
	child.steps({ '<M-.>' })
	eq(child.shown(), 'a')
	local p = S2.picker(child)
	local i = S2.line_of(p.lines, '[No Name]')
	local line = i and S2.shown_line(child, p.buf, i) or ''
	eq({ listed = i ~= nil, quoted = line:find('"TODO: fix the', 1, true) ~= nil,
		filetype = line:find('lua', 1, true) ~= nil, time = line:find('%d') ~= nil },
		{ listed = true, quoted = true, filetype = true, time = true })
end

T['T327 [char] (S2) reordering the picker\'s lines and :w reorders the stack'] = function()
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
T['T328 [char] (S2) <CR> in the picker reopens the entry under the cursor in the window you came from'] = function()
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

T['T329 [char] (S2) deleting a file\'s line in the picker and :w discards it'] = function()
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
T['T330 [char] (S2) the picker shows each pool as a header with its closed entries under it'] = function()
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
T['T331 [char] (S2) pools merge by moving a line under another pool\'s header'] = function()
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

-- Each list's entries and close times, by the list's name ("" for the editor's),
-- as file names and times.
local LISTS_STATE = [[
	local H = require('cavediver.domains.history')
	local out = {}
	for id, pool in pairs(H.routines.pools()) do
		local entries = {}
		for _, h in ipairs(pool.closed) do
			table.insert(entries, vim.fn.fnamemodify(H.get_filepath_from_hash(h) or h, ':t:r') .. '@' .. tostring(pool.times[h]))
		end
		out[pool.name or id] = table.concat(entries, ',')
	end
	return out
]]

-- In T330's state, x also goes on the session's list, closed a minute after
-- the first tab's x (set by hand).
local function x_on_both(s)
	local w1, w2 = two_pools(s)
	child.lua([[
		local H = require('cavediver.domains.history')
		local w2 = ...
		local x = H.get_hash_from_filepath(vim.fn.getcwd(-1, -1) .. '/x.txt')
		local editor = H.routines.pools()['']
		local session = H.routines.pool_of_tab(vim.api.nvim_win_get_tabpage(w2))
		table.insert(session.closed, x)
		session.times[x] = editor.times[x] + 60
	]], { w2 })
	return w1, w2
end

-- Keys are typed into the picker as a user would, so its own mappings run;
-- line 0 leaves the cursor where it is.
local function press(win, line, keys)
	child.lua([[
		local win, line, keys = ...
		vim.api.nvim_set_current_win(win)
		if line > 0 then vim.api.nvim_win_set_cursor(win, { line, 0 }) end
		vim.api.nvim_feedkeys(vim.keycode(keys), 'mx', false)
	]], { win, line, keys })
	child.settle()
end

T['T370 [char] (S2) the picker\'s keys: gf acts and stays, za folds, H and L go between lists, q writes and leaves'] = function()
	local s = S2.shared()
	two_pools(s)
	local p = S2.picker(child)
	local x, c = S2.line_of(p.lines, 'x.txt'), S2.line_of(p.lines, 'c.txt')
	eq(x ~= nil and c ~= nil, true)
	local second
	for i = 2, #p.lines do
		if not p.lines[i]:find('.txt', 1, true) and vim.trim(p.lines[i]) ~= '' then second = second or i end
	end
	local got = {}
	press(p.win, 1, 'L')
	got.next = child.lua('return vim.api.nvim_win_get_cursor(...)[1]', { p.win }) == second
	press(p.win, 0, 'H')
	got.previous = child.lua('return vim.api.nvim_win_get_cursor(...)[1]', { p.win }) == 1
	press(p.win, 1, 'za')
	got.folded = child.lua('return vim.fn.foldclosed(...) ~= -1', { x })
	press(p.win, 1, 'za')
	press(p.win, x, 'gf')
	got.reopened = child.shown(p.came_from) == 'x'
	got.stays = child.lua('return vim.api.nvim_win_is_valid(...)', { p.win })
	local lines = child.lua('return vim.api.nvim_buf_get_lines(..., 0, -1, false)', { p.buf })
	got.c_listed = S2.line_of(lines, 'c.txt') ~= nil
	-- q writes, then leaves: c's line deleted first
	local ci = S2.line_of(lines, 'c.txt')
	child.lua('local buf, i = ...; vim.api.nvim_buf_set_lines(buf, i - 1, i, false, {})', { p.buf, ci })
	press(p.win, 1, 'q')
	got.left = not child.lua('return vim.api.nvim_win_is_valid(...)', { p.win })
	got.c_closed = child.lua(LISTS_STATE).t or ''
	eq(got, { next = true, previous = true, folded = true, reopened = true, stays = true, c_listed = true, left = true, c_closed = '' })
end

-- The session's x line is moved under the first tab's header, beside its own.
T['T371 [char] (S2) the picker\'s merge keeps one copy of a file, the newer'] = function()
	local s = S2.shared()
	x_on_both(s)
	local before = child.lua(LISTS_STATE)
	local p = S2.picker(child)
	local xs = {}
	for i, l in ipairs(p.lines) do
		if l:find('x.txt', 1, true) then table.insert(xs, i) end
	end
	eq(#xs, 2)
	local lines = vim.deepcopy(p.lines)
	local moved = table.remove(lines, xs[2])
	table.insert(lines, xs[1] + 1, moved)
	S2.write_picker(child, p, lines)
	local after = child.lua(LISTS_STATE)
	local newer = before.t:match('x@([%d%.]+)')
	eq({ editor = after[''], session = after.t }, { editor = 'x@' .. newer, session = 'c@' .. before.t:match('c@([%d%.]+)') })
end

T['T372 [char] (S2) a :w in the picker with no edits changes nothing'] = function()
	local s = S2.shared()
	x_on_both(s)
	local before = child.lua(LISTS_STATE)
	local p = S2.picker(child)
	S2.write_picker(child, p, p.lines)
	eq(child.lua(LISTS_STATE), before)
end

-- b is deleted on disk, so no check clears its tag, and tagged by hand.
T['T373 [char] (S2) the picker shows a missing file\'s tag'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('bdelete b.txt')
	child.lua([[
		os.remove(_G.CDV_TEST.root .. '/b.txt')
		local H = require('cavediver.domains.history')
		H.data.missing[H.get_hash_from_filepath(_G.CDV_TEST.root .. '/b.txt')] = 'feature'
	]])
	child.settle()
	local p = S2.picker(child)
	local b = S2.line_of(p.lines, 'b.txt')
	eq(b ~= nil and S2.shown_line(child, p.buf, b):find('⎇feature', 1, true) ~= nil, true)
end

T['T374 [char] (S2) with the ASCII glyph set the picker draws nothing outside ASCII'] = function()
	local s = S2.shared()
	two_pools(s)
	child.lua([[_G.CDV_TEST.setup({ session_dir = require('cavediver.configs').session_dir, glyphs = { set = 'ascii' } })]])
	local p = S2.picker(child)
	local ascii = true
	for i = 1, #p.lines do
		if S2.shown_line(child, p.buf, i):find('[\128-\255]') then ascii = false end
	end
	eq({ lines = #p.lines > 0, ascii = ascii }, { lines = true, ascii = true })
end

-- Each list's closed files, by basename, keyed by its directory's last two parts.
local function lists_by_dir()
	return child.lua([[
		local H = require('cavediver.domains.history')
		local out = {}
		for _, pool in pairs(H.routines.pools()) do
			if pool.directory then
				local names = {}
				for _, h in ipairs(pool.closed) do table.insert(names, vim.fs.basename(H.get_filepath_from_hash(h) or h)) end
				out[vim.fn.fnamemodify(pool.directory, ':h:t') .. '/' .. vim.fn.fnamemodify(pool.directory, ':t')] = table.concat(names, ',')
			end
		end
		return out
	]])
end

-- Two nameless tab sessions, in w/app and p/app: one name, one last part.
T['T504 [char] (S2) two lists of one name and one last part get headers of their own'] = function()
	child.setup()
	child.lua('for _, d in ipairs({ "w/app", "p/app" }) do vim.fn.mkdir(_G.CDV_TEST.root .. "/" .. d, "p") end')
	child.steps({ ':e a' })
	child.cmd('tcd w/app')
	child.cmd('edit ../../b.txt')
	child.cmd('edit ../../c.txt')
	child.settle()
	eq(child.lua('return { pcall(require("cavediver").save_session, nil, { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.cmd('bdelete ' .. child.lua('return vim.fn.bufnr(_G.CDV_TEST.root .. "/b.txt")'))
	child.cmd('tabnew')
	child.cmd('tcd ' .. child.lua('return _G.CDV_TEST.root') .. '/p/app')
	child.cmd('edit ../../d.txt')
	child.cmd('edit ../../e.txt')
	child.settle()
	eq(child.lua('return { pcall(require("cavediver").save_session, nil, { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.cmd('bdelete ' .. child.lua('return vim.fn.bufnr(_G.CDV_TEST.root .. "/d.txt")'))
	child.settle()
	local before = lists_by_dir()
	local p = S2.picker(child)
	local headers = vim.tbl_filter(function(l) return l:match('^\226\137\161app') ~= nil end, p.lines)
	child.cmd('write')
	child.settle()
	eq({ distinct = #headers == 2 and headers[1] ~= headers[2], lists = lists_by_dir() }, { distinct = true, lists = before })
end

T['T505 [char] (S2) opening the closed lists again keeps an edit not written yet'] = function()
	two_closed()
	local p = S2.picker(child)
	local b = S2.line_of(p.lines, 'b.txt')
	child.lua('vim.api.nvim_buf_set_lines(..., ' .. (b - 1) .. ', ' .. b .. ', false, {})', { p.buf })
	child.messages()
	child.cmd('CavediverClosed')
	child.settle()
	local got = child.lua([[
		local buf = vim.fn.bufnr('cavediver://closed-lists')
		return { modified = buf ~= -1 and vim.bo[buf].modified, b = buf ~= -1 and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('b.txt', 1, true) ~= nil }
	]])
	eq({ got = got, closed = child.closed(), told = S2.has(child.messages(), 'not written') }, { got = { modified = true, b = false }, closed = 'b,c', told = true })
end

-- <CR> on c reopens it in the window the lists were opened from.
T['T506 [char] (S2, A27) a closed lists key\'s step is about the window it acts on'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('bdelete c.txt')
	child.settle()
	local source = child.lua('return vim.api.nvim_get_current_win()')
	local p = S2.picker(child)
	child.lua('vim.api.nvim_win_set_cursor(0, { ' .. S2.line_of(p.lines, 'c.txt') .. ', 0 })')
	child.type_keys('<CR>')
	child.settle(300)
	local step = child.lua([[
		local steps = require('cavediver').ledger.steps()
		for i = #steps, 1, -1 do
			if steps[i].trigger == '<CR>' then return { win = steps[i].win, after = steps[i].row_after ~= nil } end
		end
		return vim.NIL
	]])
	eq(step, { win = source, after = true })
end

T['T503 [char] (S2) a closed_entry formatter that gives nothing leaves cavediver\'s own text'] = function()
	local s = S2.shared()
	two_pools(s)
	child.lua([[_G.CDV_TEST.setup({ session_dir = require('cavediver.configs').session_dir,
		formatters = { closed_entry = function() return nil end } })]])
	local p = S2.picker(child)
	local timed = false
	for i = 1, #p.lines do
		if not p.lines[i]:match('^\226\137\161') and S2.shown_line(child, p.buf, i):find('%d%d:%d%d') then timed = true end
	end
	eq(timed, true)
end

T['T375 [char] (S2) <M-;>W opens the picker, named keymaps.open_closed_lists'] = function()
	two_closed()
	local came_from = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ '<M-;>W' })
	child.settle()
	local got = child.lua([[
		local buf = vim.api.nvim_get_current_buf()
		return {
			moved = vim.api.nvim_get_current_win() ~= ...,
			modifiable = vim.bo[buf].modifiable,
			lines = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'),
			named = require('cavediver.configs').keymaps.open_closed_lists,
		}
	]], { came_from })
	eq({ moved = got.moved, modifiable = got.modifiable, c = got.lines:find('c.txt', 1, true) ~= nil, named = got.named },
		{ moved = true, modifiable = true, c = true, named = '<M-;>W' })
end

-- vim.fn.confirm is answered by hand: the choice named Keep, then Discard.
T['T376 [char] (S2) discarding a No Name entry in the picker asks first'] = function()
	child.setup()
	child.steps({ ':e a' })
	S2.noname(child, { 'draft' })
	child.steps({ '<M-.>' })
	local function answer(choice)
		child.lua([[
			local choice = ...
			vim.fn.confirm = function(_, choices)
				local i = 0
				for c in (choices or ''):gmatch('[^\n]+') do
					i = i + 1
					if c:gsub('&', '') == choice then return i end
				end
				return 0
			end
		]], { choice })
	end
	local function noname_listed()
		return child.lua([[
			local H = require('cavediver.domains.history')
			for _, h in ipairs(H.data.closed_buffers) do
				if (H.get_filepath_from_hash(h) or ''):match('^NONAME_') then return H.data.noname_content[h] ~= nil end
			end
			return false
		]])
	end
	local function delete_and_write()
		local p = S2.picker(child)
		local i = S2.line_of(p.lines, '[No Name]')
		local lines = vim.deepcopy(p.lines)
		if i then table.remove(lines, i) end
		S2.write_picker(child, p, lines)
		child.lua('if vim.api.nvim_win_is_valid(...) then vim.api.nvim_win_close(..., true) end', { p.win })
		child.settle()
	end
	answer('Keep')
	delete_and_write()
	local kept = noname_listed()
	answer('Discard')
	delete_and_write()
	eq({ kept = kept, discarded = not noname_listed() }, { kept = true, discarded = true })
end

T['T377 [char] (S2) a typed header that names no list refuses the write'] = function()
	two_closed()
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	table.insert(lines, '≡nowhere')
	child.messages()
	S2.write_picker(child, p, lines)
	eq({ named = S2.has(child.messages(), 'nowhere'), closed = child.closed() }, { named = true, closed = 'b,c' })
end

return T
