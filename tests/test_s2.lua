-- The session file, S2 (what-is-frogman.md, section 5, S2, and section 7,
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
	return child.lua('return require("frogman.configs").session_dir')
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
	child.lua('vim.fn.mkdir(_G.FRG_TEST.root .. "/sub", "p")')
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
	child.lua('vim.fn.mkdir(_G.FRG_TEST.root .. "/sub", "p")')
	child.cmd('tabnew')
	child.cmd('tcd sub')
	child.cmd('edit ../b.txt')
	child.settle()
	local tab = child.lua('return vim.fn.getcwd(-1, 0)')
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'),
		{ true })
	eq(S2.main_file(session_dir(), tab, 't') ~= nil, true)
end

-- Loading -------------------------------------------------------------------------

T['T295 [char] (S2) a load from idle goes idle -> bare -> loading'] = function()
	child.setup()
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })
	local n = #child.lua('return require("frogman.domains.storage").sm.history')
	Misc.load(child)
	local after = child.lua('return { unpack(require("frogman.domains.storage").sm.history, ...) }', { n + 1 })
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
-- Each session is saved under its own name in one editor; the fresh editor shows d, as B's window did.
T['T572 [char] (S2) a second session loaded in the same batch loads'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(S2.save(child, 'A'), { true })
	child.steps({ ':e c', ':e d' })
	eq(S2.save(child, 'B'), { true })
	S2.start(child, s)
	Misc.restore(child, { 'c', 'd' }, 'd')
	child.lua([[
		local cd = require('frogman')
		cd.load_session('A')
		cd.load_session('B')
		cd.load_session('B')
	]])
	child.settle(300)
	eq({ loads = S2.loads(child), slots = child.slots() }, { loads = 2, slots = '⦉c⦊ [d] ⟦-⟧' })
end

-- T572's route, the third call naming A again, as a native restore's repeat for A arriving after a load of B.
T['T613 [char] (S2) a call naming a session a load in the same batch was for is skipped, whichever came between'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(S2.save(child, 'A'), { true })
	child.steps({ ':e c', ':e d' })
	eq(S2.save(child, 'B'), { true })
	S2.start(child, s)
	Misc.restore(child, { 'c', 'd' }, 'd')
	child.lua([[
		local cd = require('frogman')
		cd.load_session('A')
		cd.load_session('B')
		cd.load_session('A')
	]])
	child.settle(300)
	eq({ loads = S2.loads(child), slots = child.slots() }, { loads = 2, slots = '⦉c⦊ [d] ⟦-⟧' })
end

T['T297 [char] (S2) the repeat flag is re-armed by vim.schedule: a call after the batch is a full load'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	local oks = child.lua([[
		local cwd, load = vim.fn.getcwd(), require('frogman').load_session
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
T['T298 [char] (S2) after Neovim\'s :restart session, frogman loads again by itself, ignoring the repeat flag'] = function()
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
		pcall(require('frogman').load_session, vim.fn.getcwd())
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
-- told frogman about it before the load. Timer handles are counted: the
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
		pcall(require('frogman').load_session, vim.fn.getcwd())
		return timers() - before
	]])
	child.settle(30)
	local current = child.lua(
		'return require("frogman.domains.window").data.last_valid_window == vim.api.nvim_get_current_win()')
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
		{ 'the project directory', child.lua('return _G.FRG_TEST.root') },
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
	_G.FRG_SHELL = 0
	local sys, popen, vsys = vim.fn.system, io.popen, vim.system
	vim.fn.system = function(...) _G.FRG_SHELL = _G.FRG_SHELL + 1; return sys(...) end
	io.popen = function(...) _G.FRG_SHELL = _G.FRG_SHELL + 1; return popen(...) end
	vim.system = function(...) _G.FRG_SHELL = _G.FRG_SHELL + 1; return vsys(...) end
]]
T['T303 [char] (S2) a save and a load run no shell command'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.lua(SHELL_SPY)
	eq(Misc.save(child), { true })
	local at_save = child.lua('return _G.FRG_SHELL')

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.lua(SHELL_SPY)
	eq(Misc.load(child), { true })
	child.settle(30)
	eq({ save = at_save, load = child.lua('return _G.FRG_SHELL') }, { save = 0, load = 0 })
end

-- Every name the loader tries is recorded, the real loader still doing the
-- loading. On macOS the bare name would load the system's own libcrypto.
T['T480 [char] (S2) libcrypto is loaded by its versioned name first'] = function()
	child.setup()
	child.steps({ ':e a' })
	child.lua([[
		local ffi = require('ffi')
		local real = ffi.load
		_G.FRG_TRIED = {}
		ffi.load = function(name, ...)
			table.insert(_G.FRG_TRIED, tostring(name))
			return real(name, ...)
		end
	]])
	eq(Misc.save(child), { true })
	eq(child.lua('return _G.FRG_TRIED[1]'), 'libcrypto.so.3')
end

-- libcrypto_path names a file that isn't there; every name the loader tries is recorded, the real
-- loader still doing the loading.
T['T548 [char] (S2) libcrypto_path is tried first, and one that won\'t load falls back with a WARN'] = function()
	child.setup()
	child.lua('_G.FRG_TEST.setup({ libcrypto_path = _G.FRG_TEST.root .. "/nowhere/libcrypto.so.3" })')
	child.steps({ ':e a' })
	child.lua([[
		local ffi = require('ffi')
		local real = ffi.load
		_G.FRG_TRIED = {}
		ffi.load = function(name, ...)
			table.insert(_G.FRG_TRIED, tostring(name))
			return real(name, ...)
		end
	]])
	child.messages()
	local saved = Misc.save(child)
	local warns = vim.tbl_filter(function(m)
		return m.msg:find('libcrypto_path (', 1, true) ~= nil and m.msg:find('/nowhere/', 1, true) ~= nil
	end, child.messages())
	eq({ saved = saved, first = child.lua('return _G.FRG_TRIED[1]'):find('/nowhere/libcrypto.so.3', 1, true) ~= nil, warns = #warns },
		{ saved = { true }, first = true, warns = 1 })
end

-- The loader hands back, for libcrypto_path, a library with no libcrypto in it: looking up any of
-- its functions fails, as a wrong library's lookup does.
T['T550 [char] (S2) a libcrypto_path that loads but isn\'t libcrypto counts as one that won\'t load'] = function()
	child.setup()
	child.lua('_G.FRG_TEST.setup({ libcrypto_path = _G.FRG_TEST.root .. "/wrong/libnotcrypto.so" })')
	child.steps({ ':e a' })
	child.lua([[
		local ffi = require('ffi')
		local real = ffi.load
		ffi.load = function(name, ...)
			if tostring(name):find('/wrong/', 1, true) then
				return setmetatable({}, { __index = function(_, key) error('undefined symbol: ' .. key) end })
			end
			return real(name, ...)
		end
	]])
	child.messages()
	local saved = Misc.save(child)
	local warns = vim.tbl_filter(function(m)
		return m.msg:find('libcrypto_path (', 1, true) ~= nil and m.msg:find("isn't libcrypto", 1, true) ~= nil
	end, child.messages())
	eq({ saved = saved, warns = #warns }, { saved = { true }, warns = 1 })
end

-- Every load fails; the second save fails the same way.
T['T549 [char] (S2) with no libcrypto loading, the error names what was tried, and the WARN comes once'] = function()
	child.setup()
	child.lua('_G.FRG_TEST.setup({ libcrypto_path = _G.FRG_TEST.root .. "/nowhere/libcrypto.so.3" })')
	child.steps({ ':e a' })
	child.lua([[
		_G.FRG_TRIED = {}
		require('ffi').load = function(name)
			table.insert(_G.FRG_TRIED, tostring(name))
			error('simulated: ' .. tostring(name) .. ' not found')
		end
	]])
	child.messages()
	local first, second = Misc.save(child), Misc.save(child)
	local tried = child.lua('return _G.FRG_TRIED')
	local err = tostring(first[2])
	local named = #tried > 0
	for _, name in ipairs(tried) do
		if not err:find(name, 1, true) then named = false end
	end
	local function at(name)
		for i, t in ipairs(tried) do
			if t == name then return i end
		end
	end
	local warns = vim.tbl_filter(function(m) return m.msg:find('libcrypto_path (', 1, true) ~= nil end, child.messages())
	eq({ first = first[1], second = second[1], named = named, option = err:find('libcrypto_path', 1, true) ~= nil,
		path_first = (tried[1] or ''):find('/nowhere/', 1, true) ~= nil,
		four_after_three = (at('libcrypto.so.4') or 0) > (at('libcrypto.so.3') or math.huge), warns = #warns },
		{ first = false, second = false, named = true, option = true, path_first = true, four_after_three = true, warns = 1 })
end

-- The FFI says macOS, and every name the loader tries is recorded, none loading.
T['T594 [char] (S2) on macOS no bare name is tried'] = function()
	child.setup()
	child.steps({ ':e a' })
	child.lua([[
		local ffi = require('ffi')
		_G.FRG_TRIED = {}
		ffi.os = 'OSX'
		ffi.load = function(name)
			table.insert(_G.FRG_TRIED, tostring(name))
			error('simulated: ' .. tostring(name) .. ' not found')
		end
	]])
	Misc.save(child)
	local bare = child.lua([[
		local out = {}
		for _, name in ipairs(_G.FRG_TRIED) do
			if not name:find('/', 1, true) then table.insert(out, name) end
		end
		return out
	]])
	eq({ tried = child.lua('return #_G.FRG_TRIED') > 0, bare = bare }, { tried = true, bare = {} })
end

T['T595 [char] (S2) libcrypto_path is expanded'] = function()
	child.setup()
	child.lua('_G.FRG_TEST.setup({ libcrypto_path = "$HOME/nowhere/libcrypto.so.3" })')
	child.steps({ ':e a' })
	child.lua([[
		local ffi = require('ffi')
		local real = ffi.load
		_G.FRG_TRIED = {}
		ffi.load = function(name, ...)
			table.insert(_G.FRG_TRIED, tostring(name))
			return real(name, ...)
		end
	]])
	eq(Misc.save(child), { true })
	eq(child.lua('return _G.FRG_TRIED[1] == vim.env.HOME .. "/nowhere/libcrypto.so.3"'), true)
end

T['T597 [char] (S2) a search that loaded nothing isn\'t made again until libcrypto_path changes'] = function()
	child.setup()
	child.lua('_G.FRG_TEST.setup({ libcrypto_path = _G.FRG_TEST.root .. "/nowhere/libcrypto.so.3" })')
	child.steps({ ':e a' })
	child.lua([[
		_G.FRG_TRIED = {}
		require('ffi').load = function(name)
			table.insert(_G.FRG_TRIED, tostring(name))
			error('simulated: ' .. tostring(name) .. ' not found')
		end
	]])
	Misc.save(child)
	local first = child.lua('return #_G.FRG_TRIED')
	Misc.save(child)
	local second = child.lua('return #_G.FRG_TRIED') - first
	child.lua('_G.FRG_TEST.setup({ libcrypto_path = _G.FRG_TEST.root .. "/elsewhere/libcrypto.so.3" })')
	Misc.save(child)
	local again = child.lua('return (_G.FRG_TRIED[...] or ""):find("/elsewhere/", 1, true) ~= nil', { first + 1 })
	eq({ first = first > 0, second = second, again = again }, { first = true, second = 0, again = true })
end

-- A libcrypto stood in for by the loader: enough to derive a key and make a nonce,
-- and no cipher context.
T['T598 [char] (S2) a cipher context libcrypto can\'t make fails the save'] = function()
	child.setup()
	child.steps({ ':e a' })
	child.lua([[
		require('ffi').load = function()
			return {
				frg_EVP_aes_256_gcm = function() return nil end,
				frg_EVP_sha256 = function() return nil end,
				frg_PKCS5_PBKDF2_HMAC = function() return 1 end,
				frg_RAND_bytes = function() return 1 end,
				frg_EVP_CIPHER_CTX_new = function() return nil end,
				frg_EVP_CIPHER_CTX_free = function() end,
			}
		end
	]])
	local saved = Misc.save(child)
	eq({ saved = saved[1], said = tostring(saved[2]):find('cipher context', 1, true) ~= nil }, { saved = false, said = true })
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

-- Two temporary files beside the main file, as another editor's writes leave them: one in flight,
-- one left by a crash two minutes ago.
T['T552 [char] (S2) a save leaves another editor\'s write in flight alone, and sweeps an old one'] = function()
	child.setup()
	child.steps({ ':e a' })
	eq(Misc.save(child), { true })
	local file = S2.only_file(session_dir())
	local fresh, old = file .. '.tmp1', file .. '.tmp2'
	vim.fn.writefile({ 'in flight' }, fresh)
	vim.fn.writefile({ 'left by a crash' }, old)
	local ago = os.time() - 120
	vim.uv.fs_utime(old, ago, ago)
	child.steps({ ':e b' })
	eq(Misc.save(child), { true })
	eq({ fresh = vim.uv.fs_stat(fresh) ~= nil, old = vim.uv.fs_stat(old) ~= nil }, { fresh = true, old = false })
end

-- Each save runs in one call, with io.open counted on its main file meanwhile.
T['T563 [char] (S2) a save reads its main file once'] = function()
	child.setup()
	child.steps({ ':e a' })
	child.lua('vim.fn.mkdir(_G.FRG_TEST.root .. "/sub", "p")')
	local reads_during = function(path, save)
		return child.lua([[
			local path, save = ...
			local open, n = io.open, 0
			io.open = function(p, mode)
				if p == path and mode == 'rb' then n = n + 1 end
				return open(p, mode)
			end
			local ok = pcall(loadstring(save))
			io.open = open
			return { ok, n }
		]], { path, save })
	end
	local dir = session_dir()
	eq(Misc.save(child), { true })
	local whole = dir .. S2.main_file(dir, S2.cwd(child), S2.cwd(child)) -- Misc.save names it after the cwd
	child.cmd('tabnew')
	child.cmd('tcd sub')
	child.cmd('edit ../b.txt')
	child.settle()
	local tab_save = 'require("frogman").save_session("t", { tab = vim.api.nvim_get_current_tabpage() })'
	eq(child.lua('return { pcall(loadstring(...)) }', { tab_save }), { true })
	local tab = dir .. S2.main_file(dir, child.lua('return vim.fn.getcwd(-1, 0)'), 't')
	child.cmd('tabprevious')
	eq(reads_during(whole, 'require("frogman").save_session(vim.fn.getcwd())'), { true, 1 })
	child.cmd('tabnext')
	eq(reads_during(tab, tab_save), { true, 1 })
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
-- still there; the next editor, which didn't write it, sweeps it once it's a minute old.
T['T307 [char] (S2) the main file is the commit point: leftovers of a crash after it are swept once a minute old'] = function()
	local s = S2.shared()
	local v = two_versions(s)
	pcall(child.lua, 'vim.uv.kill(vim.uv.os_getpid(), "sigkill")') -- the crash: no VimLeavePre
	S2.write(v.d .. v.v1, v.v1bytes)
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(Misc.load(child), { true })
	eq(Misc.save(child), { true })
	local fresh = vim.tbl_contains(S2.scratch_files(s.session_dir), v.v1)
	local ago = os.time() - 120
	vim.uv.fs_utime(v.d .. v.v1, ago, ago)
	eq(Misc.save(child), { true })
	eq({ fresh = fresh, aged = vim.tbl_contains(S2.scratch_files(s.session_dir), v.v1) }, { fresh = true, aged = false })
end

-- Another editor's text, written a moment ago, its main file not landed yet.
T['T573 [char] (S2) a save sweeps its own old text at once and leaves another editor\'s new one alone'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	local n = S2.noname(child, { 'v1 text' })
	child.steps({ ':e b' })
	eq(Misc.save(child), { true })
	local one, d = S2.scratch_files(s.session_dir)
	vim.fn.writefile({ 'another editor' }, d .. 'in-flight')
	child.lua('vim.api.nvim_buf_set_lines(..., 0, -1, false, { "v2 text" })', { n })
	eq(Misc.save(child), { true })
	local after = S2.scratch_files(s.session_dir)
	local ago = os.time() - 120
	vim.uv.fs_utime(d .. 'in-flight', ago, ago)
	eq(Misc.save(child), { true })
	eq({ own = vim.tbl_contains(after, one[1]), other = vim.tbl_contains(after, 'in-flight'),
		aged = vim.tbl_contains(S2.scratch_files(s.session_dir), 'in-flight') }, { own = false, other = true, aged = false })
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

-- Is a No Name text on any list in memory?
local NONAME_LISTED = [[
	local H = require('frogman.domains.history')
	for _, pool in pairs(H.routines.pools()) do
		for _, h in ipairs(pool.closed) do
			if (H.get_filepath_from_handle(h) or ''):match('^NONAME_') then return true end
		end
	end
	return false
]]

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

-- T473's route, with A's text files removed before B's first save, so the text, held unread from
-- A's file, can't be read when B's save needs it.
T['T556 [char] (S2) a held text that can\'t be read at a write is lost there, and said once'] = function()
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
	local a = S2.main_file(s.session_dir, S2.cwd(child), 'A')
	vim.fn.delete(s.session_dir .. a .. '.d', 'rf')
	child.messages()
	eq(S2.save(child, 'B'), { true })
	eq(S2.save(child, 'B'), { true })
	local warns = vim.tbl_filter(function(m) return m.msg:find('so that text is lost', 1, true) ~= nil end, child.messages())
	local listed = child.lua(NONAME_LISTED)
	eq({ warns = #warns, listed = listed }, { warns = 1, listed = false })
end

-- A closed No Name text saved under A, held unread in the next editor, which loaded A.
local function held_text(s)
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	S2.noname(child, { 'carried text' })
	child.steps({ '<M-.>' })
	eq(S2.save(child, 'A'), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child, 'A'), { true })
	child.settle(300)
	return s.session_dir .. S2.main_file(s.session_dir, S2.cwd(child), 'A') .. '.d/'
end

local function said(text)
	return #vim.tbl_filter(function(m) return m.msg:find(text, 1, true) ~= nil end, child.messages())
end

T['T607 [char] (S2, M5) a held text whose file is missing says it\'s missing'] = function()
	local s = S2.shared()
	vim.fn.delete(held_text(s), 'rf')
	child.messages()
	child.steps({ '<M-S-w>' })
	eq({ missing = said("a No Name text's file is missing, so that text is lost."), check = said('integrity check'),
		listed = child.lua(NONAME_LISTED) }, { missing = 1, check = 0, listed = false })
end

T['T608 [char] (S2 Closed-stack picker, M5) a lost text found by the closed lists\' draw leaves every list then, said once'] = function()
	local s = S2.shared()
	local dir = held_text(s)
	for _, name in ipairs(Misc.files_in(dir)) do
		if not name:match('%.trail$') then S2.flip_middle(dir .. name) end
	end
	child.messages()
	local first = S2.picker(child)
	child.type_keys('q')
	child.settle()
	local second = S2.picker(child)
	local function drawn(p)
		return #vim.tbl_filter(function(l) return l:find('[No Name]', 1, true) ~= nil end, p.lines)
	end
	eq({ warns = said('integrity check'), first = drawn(first), second = drawn(second), listed = child.lua(NONAME_LISTED) },
		{ warns = 1, first = 0, second = 0, listed = false })
end

T['T610 [char] (S2, S1 Save) a held text whose own session\'s file is gone leaves every list at the next write'] = function()
	local s = S2.shared()
	vim.fn.delete(held_text(s), 'rf')
	child.messages()
	eq(S2.save(child, 'A'), { true })
	eq({ listed = child.lua(NONAME_LISTED), lost = said('so that text is lost') }, { listed = false, lost = 0 })
end

T['T625 [char] (S1 Load) a load with a quickfix window focused leaves a window with a triquetra as the last one'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true }) -- the first load, so the next is from idle and tears down first
	child.settle(300)
	child.cmd('copen')
	child.settle()
	eq(S2.load(child), { true })
	child.settle(300)
	eq(child.lua([[
		local W = require('frogman.domains.window').data
		local w = W.last_valid_window
		return { valid = w ~= nil and vim.api.nvim_win_is_valid(w), tracked = w ~= nil and W.crux[w] ~= nil,
			focused = vim.bo.buftype }
	]]), { valid = true, tracked = true, focused = 'quickfix' })
end

-- B saved with c closed and in no slot; a fresh editor loads B, a tick's round left halfway through two thousand
-- paths no file holds, as a long-lived session's would be, then B loaded again from idle and c.txt
-- removed from disk.
T['T638 [char] (M14, S1) a whole-editor load starts the tick\'s round over on the new session\'s files'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e c', ':e a', ':e b' })
	child.cmd('bdelete ' .. child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/c.txt")'))
	child.settle()
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧') -- c on the closed list alone, in no slot
	eq(S2.save(child, 'B'), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child, 'B'), { true })
	child.settle(300)
	child.lua([[
		local H = require('frogman.domains.history')
		for n = 1, 2000 do
			H.data.hash_filepath_registry.filepaths[('%016x'):format(n)] = '/nowhere/' .. n
		end
		H.routines.cleanup_system(true)
	]])
	eq(S2.load(child, 'B'), { true })
	child.settle(300)
	local got = child.lua([[
		local H = require('frogman.domains.history')
		local path = _G.FRG_TEST.root .. '/c.txt'
		local c = H.get_handle_from_filepath(path)
		local closed = H.routines.is_handle_closed(c)
		os.remove(path)
		H.routines.cleanup_system(true)
		local handle = H.handles.get(c)
		return { closed = closed, missing = handle ~= nil and handle.tag ~= nil }
	]])
	eq(got, { closed = true, missing = true })
end

-- A thousand closed entries no file holds, as a long-lived editor's lists gather, and focus coming back.
T['T650 [char] (M14) a settle point checks the known files as a tick does'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.settle(300)
	local tagged = child.lua([[
		local H = require('frogman.domains.history')
		local pool = H.routines.pools()['']
		local closed = vim.list_slice(pool.closed, 1, #pool.closed)
		for n = 1, 1000 do
			local path = '/nowhere/' .. n
			H.register_filepath(path) -- known, so the list holds its handle
			table.insert(closed, H.get_handle_from_filepath(path))
		end
		pool:replace(closed, pool.times, true) -- held by their list, as a close holds them
		vim.api.nvim_exec_autocmds('FocusGained', {})
		local n = 0
		for _, h in pairs(H.handles.live()) do
			if h.tag and H.get_filepath_from_hash(h.hash):match('^/nowhere/') then n = n + 1 end
		end
		return n
	]])
	eq(tagged <= 500, true)
end

-- A project with no .git above it, and every upward look for one counted.
T['T651 [char] (M14) the label looks for .git once when there\'s none'] = function()
	local s = S2.shared()
	S2.start(child, s)
	eq(child.lua([[
		local find, n = vim.fs.find, 0
		vim.fs.find = function(names, opts)
			if names == '.git' then n = n + 1 end
			return find(names, opts)
		end
		require('frogman.domains.history').routines.refresh_label()
		vim.fs.find = find
		return n
	]]), 1)
end

T['T611 [char] (S2 The file) session_dir is read as a path: its variables expanded, with or without its trailing slash'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.lua('vim.env.FRG_T611 = ...; _G.FRG_TEST.setup({ session_dir = "$FRG_T611" })', { (s.session_dir:gsub('/$', '')) })
	child.steps({ ':e a', ':e b' })
	eq(S2.save(child), { true })
	eq({ inside = S2.main_file(s.session_dir, S2.cwd(child), nil) ~= nil, dir = child.lua('return require("frogman.configs").session_dir') },
		{ inside = true, dir = s.session_dir })
end

T['T612 [char] (S2 The file) a look for a session\'s file makes no folder, and the first write makes it'] = function()
	local s = S2.shared()
	S2.start(child, s)
	local later = s.session_dir .. 'later/'
	child.lua('_G.FRG_TEST.setup({ session_dir = ... })', { later })
	local looked = child.lua('return require("frogman.domains.storage").routines.session_exists(vim.fn.getcwd(-1, -1), "work")')
	eq(S2.load(child, 'work'), { true })
	local made = vim.fn.isdirectory(later) == 1
	child.steps({ ':e a' })
	eq(S2.save(child), { true })
	eq({ looked = looked, made = made, after = vim.fn.isdirectory(later) == 1 }, { looked = false, made = false, after = true })
end

-- A crash's leftover of the main file, two minutes old, and every listing of the session folder counted.
T['T614 [char] (S2 Save) a commit finds its leftovers without listing the session folder'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(S2.save(child), { true })
	local main = s.session_dir .. S2.main_file(s.session_dir, S2.cwd(child), nil)
	S2.write(main .. '.tmp1', 'left')
	vim.uv.fs_utime(main .. '.tmp1', os.time() - 120, os.time() - 120)
	child.lua([[
		_G.FRG_LISTED = 0
		local readdir, dir = vim.fn.readdir, require('frogman.configs').session_dir
		vim.fn.readdir = function(path, ...)
			if path == dir then _G.FRG_LISTED = _G.FRG_LISTED + 1 end
			return readdir(path, ...)
		end
	]])
	eq(S2.save(child), { true })
	eq({ listed = child.lua('return _G.FRG_LISTED'), swept = vim.uv.fs_stat(main .. '.tmp1') == nil }, { listed = 0, swept = true })
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
-- with :buffer, which doesn't list it: the window visits a buffer frogman
-- doesn't track, whose file it knows.
T['T475 [char] (S2) a closed file shown again through its unlisted buffer is not an outsider, and the load goes through'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	child.cmd('buffer ' .. child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/c.txt")'))
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

-- The text is held unread after the load; its file then goes, so <M-S-w> can't bring it back.
T['T537 [char] (A16, M5) a closed No Name text that can\'t be read is lost, not reopened'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	S2.noname(child, { 'lost text' })
	child.steps({ '<M-.>' })
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.closed():match('NONAME_') ~= nil, true)
	vim.fn.delete(S2.scratch_dir(s.session_dir) or '', 'rf')
	child.messages()
	child.step('<M-S-w>')
	child.settle(1500) -- the records are written on the next tick, and again a second later
	local lost = vim.tbl_filter(function(m) return m.msg:find('so that text is lost', 1, true) ~= nil end, child.messages())
	local reopened = child.lua([[
		for _, st in ipairs(require('frogman').ledger.steps()) do
			for _, m in ipairs(st.moves or {}) do
				if m.kind == 'reopened' then return true end
			end
		end
		return false
	]])
	eq({ lost = #lost, reopened = reopened, closed = child.closed():match('NONAME_') ~= nil,
		cached = child.lua('local n = 0; for _, h in pairs(require("frogman.domains.history").handles.live()) do if h.text then n = n + 1 end end; return n') },
		{ lost = 1, reopened = false, closed = false, cached = 0 })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.closed():match('NONAME_') ~= nil, false)
end

-- x.txt is first shown through a nofile buffer of that name, an outsider at the save; once it's a
-- file closed since, the records write puts it on the closed list.
T['T533 [char] (S1 Records, S2) a records write leaves out of the outsiders a file it puts on the closed list'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.cmd('enew | setlocal buftype=nofile | file x.txt')
	child.settle()
	eq(Misc.save(child), { true })
	child.cmd('bwipeout!')
	child.steps({ ':e x', ':e a', ':bdelete x.txt' })
	child.settle(1500) -- the records are written on the next tick, and again a second later
	eq(child.closed():find('x') ~= nil, true)

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'a')
	child.messages()
	local dumps = child.dump_files()
	eq(Misc.load(child), { true })
	child.settle(300)
	eq({ errors = Misc.errors(child), dump = child.dumped_since(dumps), closed = child.closed():find('x') ~= nil },
		{ errors = {}, dump = nil, closed = true })
	child.step('<M-S-w>')
	eq(child.shown(), 'x')
end

-- The file is sealed again by hand, the way only a writer's bug could leave it: x.txt's hash both
-- an outsider and closed, and a closed entry whose hash has no path.
T['T541 [char] (S1 Load, S2) a load fixes a session file that broke its own rules, and says so'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })

	-- planted in the fresh editor: the first one's quit writes its records over the file
	S2.start(child, s)
	child.lua([[
		local crypto = require('frogman.domains.storage.crypto')
		local dir, name = vim.fn.getcwd(-1, -1), vim.fn.getcwd()
		local path = require('frogman.configs').session_dir .. vim.fn.sha256(dir .. "\n" .. name)
		local fh = assert(io.open(path, 'rb')); local bytes = fh:read('*a'); fh:close()
		local salt = bytes:sub(5, 4 + crypto.salt_length)
		local data = require('frogman.domains.storage.routines').read_session(dir, name)
		local x = _G.FRG_TEST.root .. '/x.txt'
		local h = vim.fn.sha256(x .. "\n"):sub(1, 16)
		data.paths[h] = x
		data.outsiders = data.outsiders or {}
		table.insert(data.outsiders, h)
		table.insert(data.closed, h)
		table.insert(data.closed, 'deadbeefdeadbeef') -- a closed entry no path names
		local header = "CDV1" .. salt
		local out = header .. crypto.seal(crypto.derive_key(dir, salt), vim.json.encode(data), header)
		fh = assert(io.open(path, 'wb')); fh:write(out); fh:close()
	]])
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.messages()
	local dumps = child.dump_files()
	eq(Misc.load(child), { true })
	child.settle(300)
	local notes = child.messages()
	local warns = vim.tbl_filter(function(m) return m.msg:find("broke its own rules", 1, true) ~= nil end, notes)
	local errors = vim.tbl_map(function(m) return m.msg end, vim.tbl_filter(function(m) return m.level == Misc.ERROR end, notes))
	local trail = child.lua([[
		for _, st in ipairs(require('frogman').ledger.steps()) do
			for _, m in ipairs(st.moves or {}) do
				if m.kind == 'loaded' and (m.words or ''):find('broke its own rules', 1, true) then return true end
			end
		end
		return false
	]])
	eq({ errors = errors, dump = child.dumped_since(dumps), warns = #warns, trail = trail, x = child.closed():find('x') ~= nil,
		nopath = child.lua('for _, h in ipairs(require("frogman.domains.history").get_closed_buffers()) do if h == "deadbeefdeadbeef" then return true end end return false') },
		{ errors = {}, dump = nil, warns = 1, trail = true, x = true, nopath = false })
	child.step('<M-S-w>')
	eq(child.shown(), 'x')
end

-- A file another writer left holding a closed hash twice, as a hand edit could: the load places it once,
-- since a list holds a file once (I22), and nothing dumps.
T['T928 [char] (S1 Load, M5, I22, DESK.md:758) a session file holding a closed hash twice loads it once'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c', ':e b', ':bdelete c.txt' })
	eq(Misc.save(child), { true })

	-- planted in the fresh editor: the first one's quit writes its records over the file
	S2.start(child, s)
	child.lua([[
		local crypto = require('frogman.domains.storage.crypto')
		local dir, name = vim.fn.getcwd(-1, -1), vim.fn.getcwd()
		local path = require('frogman.configs').session_dir .. vim.fn.sha256(dir .. "\n" .. name)
		local fh = assert(io.open(path, 'rb')); local bytes = fh:read('*a'); fh:close()
		local salt = bytes:sub(5, 4 + crypto.salt_length)
		local data = require('frogman.domains.storage.routines').read_session(dir, name)
		table.insert(data.closed, 1, data.closed[#data.closed]) -- c's hash, twice
		local header = "CDV1" .. salt
		local out = header .. crypto.seal(crypto.derive_key(dir, salt), vim.json.encode(data), header)
		fh = assert(io.open(path, 'wb')); fh:write(out); fh:close()
	]])
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.messages()
	local dumps = child.dump_files()
	eq(Misc.load(child), { true })
	child.settle(300)
	local errors = vim.tbl_map(function(m) return m.msg end,
		vim.tbl_filter(function(m) return m.level == Misc.ERROR end, child.messages()))
	eq({ errors = errors, dump = child.dumped_since(dumps), closed = child.closed() }, { errors = {}, dump = nil, closed = 'c' })
end

-- The text is open in the ternary, the window on b, when the session is saved;
-- its buffer is then set to nofile, which takes it out of frogman's hands.
T['T476 [char] (S2, I10) a saved-open No Name text whose buffer turned nofile comes back closed, and the load goes through'] = function()
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
	eq({ errors = Misc.errors(child), dump = child.dumped_since(dumps), holding = S2.holding(child, 'turned text'),
		closed = child.closed():match('NONAME_%d+') ~= nil },
		{ errors = {}, dump = nil, holding = 1, closed = true })
	child.steps({ '<M-S-w>' })
	eq(S2.holding(child, 'turned text'), 2)
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
	eq({ failed = S2.has(msgs, 'failed during transition'), state = child.lua('return require("frogman.domains.storage").sm:state()') },
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
	-- the kill in the same call, so nothing scheduled between two requests repairs the file first
	local ran, err = pcall(child.lua, [[
		vim.cmd('write ' .. vim.fn.fnameescape(_G.FRG_TEST.root .. '/notes.txt'))
		vim.cmd('doautocmd VimLeavePre')
		vim.uv.kill(vim.uv.os_getpid(), 'sigkill')
	]])
	eq({ ran = ran, killed = tostring(err):find('was closed by the peer', 1, true) ~= nil }, { ran = false, killed = true })
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
	child.lua([[vim.cmd('bwipeout ' .. vim.fn.bufnr(_G.FRG_TEST.root .. '/x.txt')); require('frogman').load_session(vim.fn.getcwd())]])
	child.settle(300)
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
end

-- 150 more files in the project, each opened and closed. It held before the
-- encrypted format and holds with it.
T['T309 [char] (S2) no count limit: 150 closed files all come back'] = function()
	local s = S2.shared()
	for i = 1, 150 do vim.fn.writefile({ 'n' }, s.root .. '/n' .. i .. '.txt') end
	local function closed() return child.lua('return #require("frogman.domains.history").get_closed_buffers()') end
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
	local told = #vim.tbl_filter(function(m) return m.msg:find("isn't on disk right now; the secondary slot keeps it.", 1, true) ~= nil end, child.messages()) > 0
	eq({ ok = ok, err = err, told = told, slots = child.slots() },
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
	child.lua('require("frogman.domains.history").cleanup_system()')
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
	local old = child.lua('return require("frogman.domains.history").get_hash_from_buffer(...)', { n })
	eq(type(old), 'string')
	eq(child.lua('return require("frogman.domains.window").data.crux[vim.api.nvim_get_current_win()].ternary_slot == require("frogman.domains.history").get_handle_from_buffer(...)',
		{ n }), true)
	eq(Misc.save(child), { true })

	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(Misc.load(child), { true })
	child.settle(300)
	local back = S2.buffer_holding(child, 'ternary text')
	eq(back ~= nil, true)
	local got = child.lua([[
		local old, buf = ...
		local H = require('frogman.domains.history')
		local W = require('frogman.domains.window')
		local new = H.get_hash_from_buffer(buf)
		local stale = {}
		-- a consumer holding a handle that still has the old name's hash
		local function look(where, h)
			if h ~= nil and H.get_hash_from_handle(W.data.note_owner(h)) == old then table.insert(stale, where) end
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
		return { fresh = new ~= nil and new ~= old, in_ternary = t ~= nil and t.ternary_slot == H.get_handle_from_buffer(buf), stale = stale }
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
	local resession_dir = vim.fn.stdpath('data') .. '/frogman_test_sessions/'
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
			'--resession-dir', 'frogman_test_sessions', '--session-dir', s.session_dir, ... }
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
-- its frogman file after that cwd. The project's own old file, under the
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
	local resession_dir = vim.fn.stdpath('data') .. '/frogman_test_sessions/'
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
		local data = require('frogman.domains.storage.routines').read_session(tab, tab)
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
		{ code = 1, named = true, left = 1 })
end

T['T642 [char] (S2) the migration script takes libcrypto_path from --libcrypto-path'] = function()
	local s = S2.shared()
	local _, migrate = old_session(s)
	local run = migrate('--libcrypto-path', '/nowhere/libcrypto.so.3')
	local said = (run.stdout .. run.stderr):find('libcrypto_path (/nowhere/libcrypto.so.3) didn\'t load', 1, true) ~= nil
	eq({ code = run.code, said = said, converted = run.stdout:find('converted 1 session', 1, true) ~= nil },
		{ code = 0, said = true, converted = true })
end

T['T643 [char] (S2) the migration script stops at a flag whose value is missing'] = function()
	local s = S2.shared()
	local old_path = old_session(s)
	local function run(...)
		return vim.system({ vim.v.progpath, '--clean', '-l', 'scripts/migrate_sessions.lua', '--resession-dir', 'frogman_test_sessions', ... },
			{ text = true }):wait()
	end
	local last, flag = run('--session-dir'), run('--session-dir', '--dry-run')
	eq({ last = { last.code, last.stderr:find('--session-dir needs a value', 1, true) ~= nil },
		flag = { flag.code, flag.stderr:find('--session-dir needs a value', 1, true) ~= nil }, left = vim.fn.filereadable(old_path) },
		{ last = { 2, true }, flag = { 2, true }, left = 1 })
end

-- T338's old file, and a resession session under a name of its own instead of the project's.
T['T644 [char] (S2) the migration script counts an old file whose session name can\'t be told once'] = function()
	local s = S2.shared()
	local _, migrate = old_session(s)
	local root = S2.cwd(child)
	local dir = vim.fn.stdpath('data') .. '/frogman_test_sessions/'
	vim.fn.delete(dir .. root:gsub('/', '_'):gsub(':', '_') .. '.json')
	vim.fn.writefile({ vim.json.encode({ global = { cwd = root }, buffers = {}, tab_scoped = false, tabs = { {} } }) }, dir .. 'custom.json')
	local run = migrate()
	eq({ unnamed = run.stdout:find('1 with a name that can\'t be told', 1, true) ~= nil,
		leftover = run.stdout:find('0 old file(s) no resession session points to', 1, true) ~= nil }, { unnamed = true, leftover = true })
end

-- A project whose path holds a `$`, which the old editor's shell expanded before hashing it.
T['T645 [char] (S2) the migration script names a session whose directory the old shell hashed another way'] = function()
	local s = S2.shared()
	local _, migrate = old_session(s)
	local root = S2.cwd(child)
	local odd = root .. '/a$b'
	vim.fn.mkdir(odd, 'p')
	local dir = vim.fn.stdpath('data') .. '/frogman_test_sessions/'
	vim.fn.writefile({ vim.json.encode({ global = { cwd = odd }, buffers = {}, tab_scoped = false, tabs = { {} } }) },
		dir .. odd:gsub('/', '_'):gsub(':', '_') .. '.json')
	local run = migrate('--dry-run')
	eq({ named = run.stdout:find('a$b', 1, true) ~= nil and run.stdout:find('shell', 1, true) ~= nil,
		none = run.stdout:find('0 with no frogman file', 1, true) ~= nil }, { named = true, none = true })
end

-- T338's old file is also a tab session's: saved from a tab whose cwd is the project's, the
-- editor's own cwd elsewhere.
T['T646 [char] (S2) the migration script converts both sessions whose old file is one, a dry run counting alike'] = function()
	local s = S2.shared()
	local _, migrate = old_session(s)
	local root = S2.cwd(child)
	local elsewhere = root .. '/elsewhere'
	vim.fn.mkdir(elsewhere, 'p')
	local dir = vim.fn.stdpath('data') .. '/frogman_test_sessions/'
	vim.fn.writefile({ vim.json.encode({ global = { cwd = elsewhere }, buffers = {}, tab_scoped = true, tabs = { { cwd = root } } }) },
		dir .. elsewhere:gsub('/', '_'):gsub(':', '_') .. '.json')
	local dry = migrate('--dry-run')
	local real = migrate()
	local both = child.lua([[
		local root, elsewhere = ...
		local st = require('frogman.domains.storage.routines')
		return st.session_exists(root, root) and st.session_exists(root, elsewhere)
	]], { root, elsewhere })
	eq({ dry = dry.stdout:find('would convert 2 session', 1, true) ~= nil, real = real.stdout:find('converted 2 session', 1, true) ~= nil, both = both },
		{ dry = true, real = true, both = true })
end

-- cavediver's folders planted in the run's own data and state folders, checked first to sit inside
-- the test sandbox.
T['T652 [char] (S2) the migration script moves cavediver\'s files into frogman\'s folders'] = function()
	local sandbox = vim.env.FRG_TEST_SANDBOX
	local data, state = vim.fn.stdpath('data'), vim.fn.stdpath('state')
	eq({ data:sub(1, #sandbox + 1) == sandbox .. '/', state:sub(1, #sandbox + 1) == sandbox .. '/' }, { true, true })
	local old_sessions, old_state = data .. '/cavediver/sessions/', state .. '/cavediver/'
	local hash = vim.fn.sha256('planted for T652')
	vim.fn.mkdir(old_sessions .. hash .. '.d', 'p')
	vim.fn.writefile({ 'x' }, old_sessions .. hash)
	vim.fn.writefile({ 'x' }, old_sessions .. hash .. '.d/text')
	vim.fn.mkdir(old_state, 'p')
	vim.fn.writefile({ 'x' }, old_state .. 'dump-planted.txt')
	local function run(...)
		return vim.system({ vim.v.progpath, '--clean', '-l', 'scripts/migrate_sessions.lua',
			'--resession-dir', 'frogman_test_no_sessions', ... }, { text = true }):wait()
	end
	local dry = run('--dry-run')
	local before = vim.fn.filereadable(old_sessions .. hash)
	local real = run()
	local new = data .. '/frogman/sessions/' .. hash
	eq({ dry = dry.stdout:find('would move 3 of cavediver', 1, true) ~= nil, before = before,
		moved = real.stdout:find('moved 3 of cavediver', 1, true) ~= nil, code = real.code,
		main = vim.fn.filereadable(new), text = vim.fn.filereadable(new .. '.d/text'),
		dump = vim.fn.filereadable(state .. '/frogman/dump-planted.txt'),
		gone = vim.fn.isdirectory(data .. '/cavediver') + vim.fn.isdirectory(old_state) },
		{ dry = true, before = 1, moved = true, code = 0, main = 1, text = 1, dump = 1, gone = 0 })
	vim.fn.delete(new, 'rf')
	vim.fn.delete(new .. '.d', 'rf')
	vim.fn.delete(state .. '/frogman/dump-planted.txt')
end

-- The session's file planted in cavediver's sessions folder, inside the sandbox, and frogman's
-- session_dir left as it is.
T['T653 [char] (S2) a load whose file is still in cavediver\'s folder points to the migration script'] = function()
	local s = S2.shared()
	S2.start(child, s)
	eq(child.lua([[
		local sandbox = ...
		local data = vim.fn.stdpath('data')
		if data:sub(1, #sandbox + 1) ~= sandbox .. '/' then return 'outside the sandbox' end
		_G.FRG_TEST.setup({ session_dir = data .. '/frogman/sessions/' })
		local old = data .. '/cavediver/sessions/'
		vim.fn.mkdir(old, 'p')
		-- named as Misc.load's load reads it: the cwd is its session's name too
		vim.fn.writefile({ 'x' }, old .. vim.fn.sha256(vim.fn.getcwd(-1, -1) .. '\n' .. vim.fn.getcwd()))
		return 'planted'
	]], { vim.env.FRG_TEST_SANDBOX }), 'planted')
	child.messages()
	eq(Misc.load(child), { true })
	child.settle(300)
	local said = S2.has(child.messages(), "frogman: this session's file is still in cavediver's folder. Run the migration script to move it, nvim --clean -l ")
	child.lua('vim.fn.delete(vim.fn.stdpath("data") .. "/cavediver", "rf")')
	eq(said, true)
end

-- A file from before encryption planted in cavediver's sessions folder, inside the sandbox, and
-- frogman's session_dir left as it is.
T['T654 [char] (S2) a load whose file from before encryption is still in cavediver\'s folder points to the migration script'] = function()
	local s = S2.shared()
	S2.start(child, s)
	eq(child.lua([[
		local sandbox = ...
		local data = vim.fn.stdpath('data')
		if data:sub(1, #sandbox + 1) ~= sandbox .. '/' then return 'outside the sandbox' end
		_G.FRG_TEST.setup({ session_dir = data .. '/frogman/sessions/' })
		local old = data .. '/cavediver/sessions/'
		vim.fn.mkdir(old, 'p')
		vim.fn.writefile({ '{"buffers":{"window":[],"global":[]},"windows":[],"closed":[],"noname_content":[]}' },
			old .. vim.fn.sha256(vim.fn.getcwd(-1, -1) .. '\n'):sub(1, 32) .. '.json')
		return 'planted'
	]], { vim.env.FRG_TEST_SANDBOX }), 'planted')
	child.messages()
	eq(Misc.load(child), { true })
	child.settle(300)
	local got = child.lua([[
		local old = vim.fn.stdpath('data') .. '/cavediver/sessions/' .. vim.fn.sha256(vim.fn.getcwd(-1, -1) .. '\n'):sub(1, 32) .. '.json'
		return vim.fn.filereadable(old)
	]])
	local said = S2.has(child.messages(), "frogman: this session has a file from before encryption. Run the migration script to convert it, nvim --clean -l ")
	child.lua('vim.fn.delete(vim.fn.stdpath("data") .. "/cavediver", "rf")')
	eq({ said = said, left = got }, { said = true, left = 1 })
end

-- T338's old file and resession session, then plant(old_path, cavediver's sessions folder, the
-- project) puts what the case needs in that folder, inside the sandbox, and the script runs with
-- --session-dir left as it is, a dry run first. What the real run leaves in frogman's folder goes
-- afterwards, and so does cavediver's folder. Returns the two runs.
local function from_cavediver(s, plant)
	local sandbox = vim.env.FRG_TEST_SANDBOX
	local data = vim.fn.stdpath('data')
	eq(data:sub(1, #sandbox + 1) == sandbox .. '/', true)
	local old_path = old_session(s)
	local old_sessions, new_sessions = data .. '/cavediver/sessions/', data .. '/frogman/sessions/'
	vim.fn.mkdir(old_sessions, 'p')
	plant(old_path, old_sessions, S2.cwd(child))
	local before = {}
	for _, entry in ipairs(vim.fn.isdirectory(new_sessions) == 1 and vim.fn.readdir(new_sessions) or {}) do
		before[entry] = true
	end
	local function run(...)
		return vim.system({ vim.v.progpath, '--clean', '-l', 'scripts/migrate_sessions.lua',
			'--resession-dir', 'frogman_test_sessions', ... }, { text = true }):wait()
	end
	local dry = run('--dry-run')
	local real = run()
	for _, entry in ipairs(vim.fn.isdirectory(new_sessions) == 1 and vim.fn.readdir(new_sessions) or {}) do
		if not before[entry] then vim.fn.delete(new_sessions .. entry, 'rf') end
	end
	vim.fn.delete(data .. '/cavediver', 'rf')
	return dry, real
end

-- The old file in cavediver's folder, and one more old file there that no session points to.
T['T655 [char] (S2) a dry run counts what the real run converts when the old files are still in cavediver\'s folder'] = function()
	local dry, real = from_cavediver(S2.shared(), function(old_path, old_sessions)
		vim.fn.rename(old_path, old_sessions .. vim.fs.basename(old_path))
		vim.fn.writefile({ '{}' }, old_sessions .. string.rep('0', 32) .. '.json')
	end)
	eq({ dry = dry.stdout:find('would convert 1 session', 1, true) ~= nil,
		no_file = dry.stdout:find('; 0 with no frogman file', 1, true) ~= nil,
		leftover = dry.stdout:find('; 1 old file(s) no resession session points to', 1, true) ~= nil,
		real = real.stdout:find('converted 1 session', 1, true) ~= nil, code = real.code,
		real_leftover = real.stdout:find('; 1 old file(s) no resession session points to', 1, true) ~= nil },
		{ dry = true, no_file = true, leftover = true, real = true, code = 0, real_leftover = true })
end

-- Only the old file's .migrated mark in cavediver's folder.
T['T656 [char] (S2) a dry run counts an old file converted already whose mark is still in cavediver\'s folder'] = function()
	local dry, real = from_cavediver(S2.shared(), function(old_path, old_sessions)
		vim.fn.rename(old_path, old_sessions .. vim.fs.basename(old_path) .. '.migrated')
	end)
	eq({ dry = dry.stdout:find('; 1 already converted', 1, true) ~= nil,
		real = real.stdout:find('; 1 already converted', 1, true) ~= nil },
		{ dry = true, real = true })
end

-- The old file and a file under the session's new name in cavediver's folder; only whether that
-- file is there counts.
T['T657 [char] (S2) a dry run counts a session with a file in the new format already in cavediver\'s folder'] = function()
	local dry, real = from_cavediver(S2.shared(), function(old_path, old_sessions, root)
		vim.fn.rename(old_path, old_sessions .. vim.fs.basename(old_path))
		vim.fn.writefile({ 'x' }, old_sessions .. vim.fn.sha256(root .. '\n' .. root))
	end)
	eq({ dry = dry.stdout:find('would convert 0 session(s); 0 already converted; 1 with a file in the new format already', 1, true) ~= nil,
		real = real.stdout:find('converted 0 session(s); 0 already converted; 1 with a file in the new format already', 1, true) ~= nil },
		{ dry = true, real = true })
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

-- T340's old-named file, and the plugin's own directory, the test run's, on the child's runtimepath.
T['T648 [char] (S2) the WARN gives the migration script\'s command as it runs in this install'] = function()
	local s = S2.shared()
	S2.start(child, s)
	local root = S2.cwd(child)
	vim.fn.writefile({ '{"buffers":{"window":[],"global":[]},"windows":[],"closed":[],"noname_content":[]}' },
		s.session_dir .. vim.fn.sha256(root .. '\n'):sub(1, 32) .. '.json')
	S2.start(child, s)
	Misc.restore(child, { 'a' }, 'a')
	child.messages()
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(S2.has(child.messages(), 'nvim --clean -l ' .. vim.fn.getcwd() .. '/scripts/migrate_sessions.lua'), true)
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
			local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), nil)
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
	-- e and x are open again, and the file's list follows them
	local followed = in_file()

	-- a fresh process: e comes back under c, closed at load from the saved window's slot (T337)
	S2.start(child, s)
	Misc.restore(child, { 't' }, 't')
	eq(S2.load(child), { true })
	child.settle(300)
	local fresh = child.closed()
	child.steps({ '<M-S-w>' })
	eq({ saved = saved, live = live, followed = followed, fresh = fresh, after = child.shown() },
		{ saved = 'x,c,e', live = { 'e', 'x' }, followed = 'c', fresh = 'e,c', after = 'c' })
end

-- No TabClosedPre hook calls save_session here: frogman writes the session's
-- records itself as the tab closes. The load
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
		return { pcall(require('frogman').load_session, 't') }
	]])
	child.settle(300)
	child.steps({ '<M-S-w>' })
	eq({ notices = notices, got = got, reopened = child.shown() }, { notices = {}, got = { true }, reopened = 'c' })
end

-- The places holding anything, each as its name: t's list is `pool:t <its directory>`.
local function pool_places()
	return child.lua([[
		local seen = {}
		for _, h in pairs(require('frogman.domains.history').handles.live()) do
			for place in pairs(h.holders) do
				if place:match('^pool:') then seen[place:match('^pool:(%S+)')] = true end
			end
		end
		local out = vim.tbl_keys(seen)
		table.sort(out)
		return out
	]])
end

T['T697 [char] (M2 Holders, M5) a list leaving memory lets go of what it held'] = function()
	local s = S2.shared()
	tab_session(s)
	child.cmd('bdelete c.txt')
	child.settle()
	eq(vim.tbl_contains(pool_places(), 't'), true)
	child.cmd('tabclose')
	child.settle(300)
	eq(vim.tbl_contains(pool_places(), 't'), false)
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
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'),
		{ true })
	-- the whole editor's file, as the load reads it
	eq(child.lua([[
		local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), nil)
		local x = require('frogman.domains.history').get_hash_from_filepath(vim.fn.getcwd(-1, -1) .. '/x.txt')
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
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'),
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
			require('frogman').save_session('t', { tab = vim.api.nvim_get_current_tabpage() })
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
		return { pcall(require('frogman').load_session, 't') }
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
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'),
		{ true })

	S2.start(child, s)
	local got = child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd tcd sub')
		local b = vim.fn.bufadd(vim.fn.fnamemodify('../c.txt', ':p'))
		vim.fn.bufload(b)
		vim.bo[b].buflisted = true
		vim.cmd('noautocmd edit ../d.txt')
		return { pcall(require('frogman').load_session, 't') }
	]])
	child.settle(300)
	eq({ got = got, slots = child.slots() }, { got = { true }, slots = '⦉c⦊ [d] ⟦-⟧' })
end

-- One process: a save, then a load from idle, then a close and a reopen.
-- The window of tab 1 built the last history view before the load, so the load's
-- rebuild for it has to start afresh to rank the session's own visits.
-- The text's typing writes t's records with it open; its wipe's write waits for the
-- records' second, and the load comes before that.
T['T586 [char] (S2) a session loaded while it\'s open doesn\'t reopen a text it has closed since'] = function()
	local s = S2.shared()
	tab_session(s)
	local buf = S2.noname(child, { 'precious' })
	child.settle(100)
	child.steps({ ':e d' })
	child.cmd('bwipeout! ' .. buf)
	child.settle()
	eq(S2.load_tab_session(child, 't'), { true })
	local holding = S2.holding(child, 'precious')
	child.steps({ '<M-S-w>' })
	eq({ before = holding, after = S2.holding(child, 'precious') }, { before = 0, after = 1 })
end

T['T582 [char] (S2) a tab session loaded into the window that built the last view ranks the session\'s visits at once'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b', ':e c' })
	local tab1 = child.lua('return vim.api.nvim_get_current_tabpage()')
	child.cmd('tabnew')
	child.steps({ ':e d', ':e e' })
	eq(child.lua('return { pcall(require("frogman").save_session, "t1", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.cmd('tabclose')
	child.settle(300)
	child.steps({ ':e a' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t1", { tab = ... }) }', { tab1 }), { true })
	child.settle(300)
	local got = child.ordered()
	child.lua([[
		local routines = require('frogman.domains.history').routines
		routines.construct_crux(nil)
		routines.construct_crux(vim.api.nvim_get_current_win())
		routines.update_buffer_history_ordered()
	]])
	eq(got, child.ordered())
end

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

-- The session u has no frogman file; the hint says it's a tab session.
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
		return { pcall(require('frogman').load_session, 'u', { tab = vim.api.nvim_get_current_tabpage() }) }
	]])
	child.settle(300)
	local w2 = child.lua('return vim.api.nvim_get_current_win()')
	local state = { got = got, session_tab = child.slots(w2), first_tab = child.slots(w1), closed = child.closed() }
	child.messages()
	eq(child.lua('return { pcall(require("frogman").save_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
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
	local got = child.lua('return { pcall(require("frogman").load_session, vim.fn.getcwd(), { tab = vim.api.nvim_get_current_tabpage() }) }')
	child.settle(300)
	eq({ got = got, slots = child.slots(),
		editor = child.lua('return require("frogman.domains.history").routines.current_pool().id') },
		{ got = { true }, slots = '⦉c⦊ [d] ⟦-⟧', editor = '' })
end

-- The session directory is read-only, so the records can't be written: the
-- failure path of T322's write.
T['T356 [char] (S2) a tab session\'s records that can\'t be written as its tab closes keep its list, with a warning'] = function()
	local s = S2.shared()
	tab_session(s)
	vim.fn.setfperm(s.session_dir, 'r-xr-xr-x')
	MiniTest.finally(function() vim.fn.setfperm(s.session_dir, 'rwxr-xr-x') end) -- writable again, even when the case fails
	if vim.fn.filewritable(s.session_dir) == 2 then -- root writes through a read-only folder
		vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
		MiniTest.skip('a read-only folder is still writable: the suite runs as root')
	end
	child.cmd('bdelete c.txt')
	child.settle(300)
	child.messages()
	child.cmd('tabclose')
	child.settle(300)
	local warned = S2.has(child.messages(), "'s tab closed, and its closed files couldn't be written")
	local kept = child.lua([[
		local H = require('frogman.domains.history')
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
		return { pcall(require('frogman').load_session, 't') }
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
	local ran, err = pcall(child.lua, [[
		vim.cmd('bdelete e.txt')
		vim.cmd('tabclose')
		vim.api.nvim_exec_autocmds('VimLeavePre', {})
		vim.uv.kill(vim.uv.os_getpid(), 'sigkill')
	]])
	-- the batch reached the kill: an error before it would leave the child up, and the restart's quit
	-- would write the records the case is about
	eq({ ran = ran, killed = tostring(err):find('was closed by the peer', 1, true) ~= nil }, { ran = false, killed = true })
	S2.start(child, s)
	local got = child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		return { pcall(require('frogman').load_session, 't') }
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
		require('frogman').load_session('two')
	]])
	child.settle(1500)
	local closed = child.lua([[
		local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), 'one')
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
-- A session known but with no file, from a load that found none: its records are due at a close.
T['T361 [char] (S2) records never make a file'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(S2.load(child, 'u'), { true })
	child.settle(300)
	child.steps({ ':e a', ':e b' })
	child.cmd('bdelete a.txt')
	child.settle(1200)
	eq(vim.fn.readdir(s.session_dir), {})
end

-- t is loaded into a second tab after the whole editor's save; the No Name buffer is the first tab's alone.
T['T566 [char] (S2) a No Name edit marks only the sessions whose files hold its text'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(S2.save(child), { true })
	eq(S2.load_tab_session(child, 't'), { true })
	child.cmd('tabprevious')
	child.cmd('enew')
	child.settle(1500)
	local dir, cwd = s.session_dir, S2.cwd(child)
	local whole, tab = dir .. S2.main_file(dir, cwd, nil), dir .. S2.main_file(dir, cwd, 't')
	local before = { whole = S2.read(whole), tab = S2.read(tab) }
	child.type_keys('i', 'draft', '<Esc>')
	child.settle(1500)
	eq({ whole = S2.read(whole) ~= before.whole, tab = S2.read(tab) ~= before.tab }, { whole = true, tab = false })
end

T['T599 [char] (S2) a tab session keeps owning a No Name text its tab visited after the window that showed it closes'] = function()
	local s = S2.shared()
	tab_session(s)
	child.cmd('split')
	S2.noname(child, { 'draft' })
	child.steps({ ':e x' })
	local function texts()
		eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
		return child.lua([[
			local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), 't')
			local n = 0
			for _ in pairs(saved.noname_content or {}) do n = n + 1 end
			return n
		]])
	end
	local first = texts()
	child.cmd('close')
	child.settle()
	eq({ first = first, after = texts() }, { first = 1, after = 1 })
end

-- Unnamed mode: the whole editor saved, then t loaded into a second tab. The text
-- is typed in a split of the first tab, so closing the split takes it out of that
-- tab's histories.
T['T600 [char] (S2) a session whose last write held a No Name text no longer its own is written without it'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	local w1 = child.lua('return vim.api.nvim_get_current_win()')
	eq(S2.save(child), { true })
	eq(S2.load_tab_session(child, 't'), { true })
	local w2 = child.lua('return vim.api.nvim_get_current_win()')
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	child.cmd('split')
	local buf = S2.noname(child, { 'draft' })
	child.steps({ ':e x' })
	child.settle(1500)
	local function editor_texts()
		return child.lua([[
			local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), nil)
			local n = 0
			for _ in pairs(saved.noname_content or {}) do n = n + 1 end
			return n
		]])
	end
	local held = editor_texts()
	child.cmd('close')
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('buffer ' .. buf)
	child.settle()
	child.type_keys('i', 'more', '<Esc>')
	child.settle(1500)
	eq({ held = held, after = editor_texts() }, { held = 1, after = 0 })
end

T['T601 [char] (S2) an edited text\'s sessions are worked out once in a second of writes'] = function()
	local s = S2.shared()
	tab_session(s)
	S2.noname(child, { 'draft' })
	child.settle(1500)
	local asked = child.lua([[
		local H = require('frogman.domains.history').routines
		local real = H.tabs_that_visited
		local n = 0
		H.tabs_that_visited = function(...) n = n + 1 return real(...) end
		for i = 1, 20 do
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'draft ' .. i })
			vim.api.nvim_exec_autocmds('TextChanged', { buffer = 0 })
		end
		H.tabs_that_visited = real
		return n
	]])
	eq(asked <= 2, true)
end

T['T602 [char] (S2) steady typing writes the records once a second'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	eq(S2.save(child), { true })
	S2.noname(child, { 'draft' })
	child.settle(1500)
	child.lua([[
		local R = require('frogman.domains.storage').routines
		local real = R.write_records
		_G.FRG_WRITES = 0
		_G.FRG_AT = {}
		local t0 = vim.uv.hrtime()
		R.write_records = function(...) _G.FRG_WRITES = _G.FRG_WRITES + 1 table.insert(_G.FRG_AT, (vim.uv.hrtime() - t0) / 1e6) return real(...) end
		local n = 0
		local t = vim.uv.new_timer()
		t:start(0, 50, vim.schedule_wrap(function()
			n = n + 1
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'draft ' .. n })
			vim.api.nvim_exec_autocmds('TextChanged', { buffer = 0 })
			if n >= 80 then t:stop() t:close() end
		end))
	]])
	child.settle(5500)
	-- one a second: no two writes close together, as the first change after a second's write was
	local at = child.lua('return _G.FRG_AT')
	local closest = math.huge
	for i = 2, #at do closest = math.min(closest, at[i] - at[i - 1]) end
	eq({ some = #at > 0, apart = closest >= 500 }, { some = true, apart = true })
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
		require('frogman').disable()
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
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'),
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
		require('frogman').load_session('two')
	]])
	child.settle(1500)
	local closed = child.lua([[
		local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), 't')
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
	eq(child.lua('return { pcall(require("frogman").save_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'),
		{ true })
	child.settle(300)
	child.lua('require("frogman.domains.history").cleanup_system()')
	child.settle(300)
	local state = child.lua([[
		local H = require('frogman.domains.history')
		local tabless = 0
		for id, pool in pairs(H.routines.pools()) do
			if id ~= '' and next(pool.tabs) == nil then
				tabless = tabless + 1
			end
		end
		local u = {}
		for _, h in ipairs(H.routines.current_pool().closed) do
			table.insert(u, vim.fn.fnamemodify(H.get_filepath_from_handle(h) or tostring(h), ':t:r'))
		end
		return { pool = H.routines.current_pool().name, u = table.concat(u, ','), tabless = tabless }
	]])
	state.slots = child.slots(w2)
	local got = child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		return { pcall(require('frogman').load_session, 't') }
	]])
	child.settle(300)
	child.steps({ '<M-S-w>' })
	state.got, state.reopened = got, child.shown()
	eq(state, { pool = 'u', u = 'c', tabless = 0, slots = '⦉c⦊ [d] ⟦-⟧', got = { true }, reopened = 'c' })
end

-- The lists a closed file is on, by pool: the editor's as "", a tab session's
-- by its name, and whether each pool has a tab.
local LISTS = [[
	local H = require('frogman.domains.history')
	local h = H.get_handle_from_filepath(vim.fn.getcwd(-1, -1) .. '/' .. ... .. '.txt')
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
	eq(child.lua('return { pcall(require("frogman").save_session, "notes", { tab = vim.api.nvim_get_current_tabpage() }) }'),
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
	eq(child.lua('return { pcall(require("frogman").save_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'),
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
		return { pcall(require('frogman').load_session, 't') }
	]])
	child.settle(300)
	local lists = child.lua([[
		local H = require('frogman.domains.history')
		local function list(tabpage)
			local pool = H.routines.pool_of_tab(tabpage)
			local out = {}
			for _, h in ipairs(pool.closed) do
				table.insert(out, vim.fn.fnamemodify(H.get_filepath_from_handle(h) or tostring(h), ':t:r'))
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
		require('frogman').load_session('t')
	]])
	child.settle(300)
	return w2, child.lua('return vim.api.nvim_get_current_win()')
end

-- A tab's list, as its name and its entries.
local LIST_OF = [[
	local H = require('frogman.domains.history')
	local pool = H.routines.pool_of_tab(vim.api.nvim_win_get_tabpage(...))
	local out = {}
	for _, h in ipairs(pool.closed) do
		table.insert(out, vim.fn.fnamemodify(H.get_filepath_from_handle(h) or tostring(h), ':t:r'))
	end
	return (pool.name or '') .. ':' .. table.concat(out, ',')
]]

-- The whole editor's file, as names: its closed list, and each detached list.
local EDITOR_FILE = [[
	local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), nil)
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
		return { pcall(require('frogman').save_session, 't', { tab = vim.api.nvim_get_current_tabpage() }) }
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
		for _, pool in pairs(require('frogman.domains.history').routines.pools()) do
			if pool.name == 't_DETACHED' then return true end
		end
		return false
	]])
	local file = child.lua(EDITOR_FILE)
	local path = child.lua([[
		local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), nil)
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
		for _, pool in pairs(require('frogman.domains.history').routines.pools()) do
			if pool.name == 't_DETACHED' then return next(pool.tabs) == nil end
		end
		return false
	]])
	eq({ kept = kept, warned = S2.has(child.messages(), "'s tab is gone, and its closed files couldn't be written into the whole editor's session file") },
		{ kept = true, warned = true })
end

T['T383 [char] (S2) a second detach of a session is numbered'] = function()
	local s = S2.shared()
	local w2, w3 = detached_state(s)
	child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		require('frogman').load_session('t')
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
		require('frogman').load_session('t')
	]])
	child.settle(300)
	local w3 = child.lua('return vim.api.nvim_get_current_win()')
	child.lua([[
		vim.api.nvim_set_current_win(...)
		vim.cmd('noautocmd edit d.txt')
		require('frogman').load_session('t')
	]], { w2 })
	child.settle(300)
	return w2, w3
end

-- The closed lists' window, when it's open: { buf, win, lines, cursor_line }.
local OPEN_LISTS = [==[
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].filetype == 'frogman-closed-lists' then
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			return { buf = buf, win = win, lines = lines, cursor_line = lines[vim.api.nvim_win_get_cursor(win)[1]] }
		end
	end
	return vim.NIL
]==]

-- Whether a list of that name is in memory.
local IN_MEMORY = [[
	for _, pool in pairs(require('frogman.domains.history').routines.pools()) do
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
		require('frogman').load_session('t')
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

-- The trail's header, from its float, or '' with none open; every float is closed after.
local TRAIL_HEADER = [==[
local head = ''
for _, w in ipairs(vim.api.nvim_list_wins()) do
	local b = vim.api.nvim_win_get_buf(w)
	if vim.bo[b].filetype == 'frogman-trail' then head = vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] or '' end
end
for _, w in ipairs(vim.api.nvim_list_wins()) do
	if vim.api.nvim_win_get_config(w).relative ~= '' then vim.api.nvim_win_close(w, true) end
end
return head
]==]

-- How many moves a search's header counts.
local function moves_in(header)
	return tonumber(header:match('(%d+) moves? over')) or -1
end

-- File-only state, sub/e.txt closed in the first tab too, so e.txt names two files, and e taken off
-- t's list, so frogman lets e go and knows its path no longer: t_DETACHED's e line, in the file alone,
-- is followed by its hash and named by the path the file keeps.
T['T922 [char] (A27, S2 Closed-stack picker, DESK.md:1861) * on an entry of a list in the whole editor\'s file alone follows its file'] = function()
	local s = S2.shared()
	local w1 = file_only_state(s)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	child.lua([[
		vim.fn.mkdir(_G.FRG_TEST.root .. '/sub', 'p')
		vim.fn.writefile({ 'sub e' }, _G.FRG_TEST.root .. '/sub/e.txt')
	]])
	child.steps({ ':e sub/e.txt', ':e t' })
	child.cmd('bdelete sub/e.txt')
	child.settle()
	local p = S2.picker(child)
	local lines, section = {}, nil
	for _, l in ipairs(p.lines) do
		if l:sub(1, 3) == '≡' then section = l end
		if not (section == '≡t' and vim.trim(l) == 'e.txt') then table.insert(lines, l) end
	end
	eq(#lines, #p.lines - 1)
	S2.write_picker(child, p, lines)
	child.settle(300)
	local known = child.lua('return require("frogman.domains.history").get_handle_from_filepath(_G.FRG_TEST.root .. "/e.txt") ~= nil')
	local _, e = under_detached(child.lua('return vim.api.nvim_buf_get_lines(..., 0, -1, false)', { p.buf }))
	child.lua('local w, row = ...; vim.api.nvim_set_current_win(w); vim.api.nvim_win_set_cursor(w, { row, 0 })', { p.win, e or 1 })
	child.steps({ '*' })
	child.settle(100)
	local star = child.lua(TRAIL_HEADER)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	child.cmd('FrogmanTrail e.txt')
	child.settle(100)
	local typed = child.lua(TRAIL_HEADER)
	eq({ known = known, e = e ~= nil, named = star:find('⌕ e.txt', 1, true) ~= nil, fewer = moves_in(star) >= 1 and moves_in(star) < moves_in(typed) },
		{ known = false, e = true, named = true, fewer = true })
end

-- T574's route to t_DETACHED in the whole editor's file alone holding the text, then the text's file
-- there made to fail its check.
T['T609 [char] (S2 Closed-stack picker) a lost text on a list in the file alone is said once however often the lists are drawn'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s)
	eq(S2.save(child), { true })
	local buf = S2.noname(child, { 'precious' })
	child.steps({ ':e d' })
	child.cmd('bwipeout! ' .. buf)
	child.settle(1200)
	eq(S2.load_tab_session(child, 't'), { true })
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	local dir = s.session_dir .. S2.main_file(s.session_dir, S2.cwd(child), nil) .. '.d/'
	for _, name in ipairs(Misc.files_in(dir)) do
		if not name:match('%.trail$') then S2.flip_middle(dir .. name) end
	end
	child.messages()
	local lines = {}
	for i = 1, 2 do
		local p = S2.picker(child)
		local section
		for _, l in ipairs(p.lines) do
			if l:sub(1, 3) == '≡' then section = l end
			if section == '≡t_DETACHED' and l:find('[No Name]', 1, true) then lines[i] = l end
		end
		child.type_keys('q')
		child.settle()
	end
	local warns = #vim.tbl_filter(function(m) return m.msg:find('integrity check', 1, true) ~= nil end, child.messages())
	eq({ warns = warns, drawn = { lines[1] ~= nil, lines[2] ~= nil } }, { warns = 1, drawn = { true, true } })
end

-- T381's route with a No Name text in t's tab instead of e, so t_DETACHED in the
-- whole editor's file alone holds the text; t's own list held it too, until the
-- text was reopened from it in t's new tab.
T['T574 [char] (S2) a No Name text moved from a list in the file alone onto a tab session\'s list keeps its text'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s)
	eq(S2.save(child), { true })
	local buf = S2.noname(child, { 'precious' })
	child.steps({ ':e d' })
	child.cmd('bwipeout! ' .. buf)
	child.settle(1200) -- the records' second runs out, so t's file has the text closed
	eq(S2.load_tab_session(child, 't'), { true })
	local w3 = child.lua('return vim.api.nvim_get_current_win()')
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	child.lua('vim.api.nvim_set_current_win(...)', { w3 })
	child.steps({ '<M-S-w>' })
	eq(S2.holding(child, 'precious'), 1)
	local p = S2.picker(child)
	local t_header, text
	local section
	for i, l in ipairs(p.lines) do
		if l:sub(1, 3) == '≡' then section = l end
		if l == '≡t' then t_header = i end
		if section == '≡t_DETACHED' and l:find('precious', 1, true) then text = i end
	end
	eq({ t_header = t_header ~= nil, text = text ~= nil }, { t_header = true, text = true })
	local lines = vim.deepcopy(p.lines)
	local moved = table.remove(lines, text)
	table.insert(lines, t_header + 1, moved)
	child.messages()
	S2.write_picker(child, p, lines)
	child.lua('if vim.api.nvim_win_is_valid(...) then vim.api.nvim_win_close(..., true) end', { p.win })
	child.lua('vim.api.nvim_set_current_win(...)', { w3 })
	child.settle(600)
	local lost = S2.has(child.messages(), "so that text is lost")
	local in_file = child.lua([[
		local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), 't')
		for _, h in ipairs(saved and saved.closed or {}) do
			if (saved.noname_content or {})[h] then return true end
		end
		return false
	]])
	child.steps({ '<M-S-w>' })
	eq({ lost = lost, in_file = in_file, holding = S2.holding(child, 'precious') }, { lost = false, in_file = true, holding = 2 })
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
-- In a tab, a split with a window mark on d and a snapshot of it, closed: held over in the tab's list's scope.
local function held_in_split(win)
	child.lua('vim.api.nvim_set_current_win(...)', { win })
	child.settle()
	child.cmd('split')
	child.settle()
	child.steps({ ':e d', "<M-'><M-'><M-a>", '<M-;><M-s>' })
	child.cmd('close')
	child.settle(300)
end

-- The whole editor's held-over groups and snapshots, in memory and in its file.
local WHOLE_HELD = [[
	local scope = require('frogman.domains.marks').data.scopes.session['']
	local n = 0
	for _, g in ipairs(scope and scope.groups or {}) do if g.held then n = n + 1 end end
	local saved = require('frogman.domains.storage.routines').read_session(vim.fn.getcwd(-1, -1), nil)
	local f = 0
	for _, g in ipairs(saved and saved.marks or {}) do if g.held then f = f + 1 end end
	return { groups = n, snapshots = #require('frogman.domains.snapshots').routines.held_in(''),
		file_groups = f, file_snapshots = #(saved and saved.snapshots or {}) }
]]

T['T860 [char] (S2, M15, M16) a detached list merged away gives its held-over groups and snapshots to the whole editor\'s scope'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s)
	eq(S2.save(child), { true })
	child.steps({ ':e x', ':e c', ':e d' })
	child.cmd('bdelete x.txt')
	child.cmd('bdelete c.txt')
	child.settle()
	child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		require('frogman').load_session('t')
	]])
	child.settle(300)
	held_in_split(w2) -- in the second tab, now t_DETACHED's
	child.lua([[
		vim.api.nvim_set_current_win(...)
		vim.cmd('noautocmd edit d.txt')
		require('frogman').load_session('t')
	]], { w2 })
	child.settle(300)
	local p = child.lua(OPEN_LISTS)
	local lines, moved, under, section = {}, {}, nil, nil
	for _, l in ipairs(p.lines) do
		if l:sub(1, 3) == '≡' then section = l end
		if section == '≡t_DETACHED' and l ~= '≡t_DETACHED' then table.insert(moved, l) else table.insert(lines, l) end
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
	local got = child.lua(WHOLE_HELD)
	eq({ gone = child.lua(IN_MEMORY, { 't_DETACHED' }), groups = got.groups, snapshots = got.snapshots },
		{ gone = false, groups = 1, snapshots = 1 })
end

T['T890 [char] (S2, M16) a merged list\'s held-over snapshots keep headers of their own'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s)
	eq(S2.save(child), { true })
	child.steps({ ':e x', ':e c', ':e d' })
	child.cmd('bdelete x.txt')
	child.cmd('bdelete c.txt')
	child.settle()
	child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		require('frogman').load_session('t')
	]])
	child.settle(300)
	held_in_split(w2) -- in the second tab, now t_DETACHED's
	-- the whole editor's scope holds one under the same header
	child.lua([[
		local Sn = require('frogman.domains.snapshots').routines
		local list = require('frogman.domains.history').data.tab_pools[vim.api.nvim_win_get_tabpage(...)]
		local snap = Sn.held_in(list)[1]
		Sn.copy({ session = '', held = snap.held }, snap)
	]], { w2 })
	child.lua([[
		vim.api.nvim_set_current_win(...)
		vim.cmd('noautocmd edit d.txt')
		require('frogman').load_session('t')
	]], { w2 })
	child.settle(300)
	local p = child.lua(OPEN_LISTS)
	local lines, moved, under, section = {}, {}, nil, nil
	for _, l in ipairs(p.lines) do
		if l:sub(1, 3) == '≡' then section = l end
		if section == '≡t_DETACHED' and l ~= '≡t_DETACHED' then table.insert(moved, l) else table.insert(lines, l) end
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
	eq(child.lua([[
		local headers = {}
		for _, sn in ipairs(require('frogman.domains.snapshots').routines.held_in('')) do headers[sn.held] = true end
		return { n = #require('frogman.domains.snapshots').routines.held_in(''), headers = #vim.tbl_keys(headers) }
	]]), { n = 2, headers = 2 })
end

T['T861 [char] (S2, M15, M16) a list in the file alone emptied gives its held-over groups and snapshots to the whole editor\'s scope'] = function()
	local s = S2.shared()
	local w1, w2 = tab_session(s)
	eq(S2.save(child), { true })
	child.steps({ ':e e', ':e d' })
	child.cmd('bdelete e.txt')
	child.settle()
	eq(S2.load_tab_session(child, 't'), { true })
	held_in_split(w2)
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	local p = S2.picker(child)
	local _, e = under_detached(p.lines)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, e)
	S2.write_picker(child, p, lines)
	child.settle(300)
	eq(child.lua(WHOLE_HELD), { groups = 1, snapshots = 1, file_groups = 1, file_snapshots = 1 })
end

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
	MiniTest.finally(function() vim.fn.setfperm(s.session_dir, 'rwxr-xr-x') end) -- writable again, even when the case fails
	if vim.fn.filewritable(s.session_dir) == 2 then -- root writes through a read-only folder
		vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
		MiniTest.skip('a read-only folder is still writable: the suite runs as root')
	end
	child.messages()
	S2.write_picker(child, p, lines)
	local got = { warned = S2.has(child.messages(), "the closed lists' edits to the lists in the whole editor's file alone weren't written"),
		modified = child.lua('return vim.bo[...].modified', { p.buf }) }
	vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
	eq(got, { warned = true, modified = true })
end

-- T391's edit, left unwritten, and q: the file can't take it, so q leaves anyway and says so.
T['T542 [char] (S2) q leaves the closed lists when only the write into the whole editor\'s file fails'] = function()
	local s = S2.shared()
	local w1 = file_only_state(s)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	local p = S2.picker(child)
	local _, e = under_detached(p.lines)
	eq(e ~= nil, true)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, e)
	vim.fn.setfperm(s.session_dir, 'r-xr-xr-x')
	MiniTest.finally(function() vim.fn.setfperm(s.session_dir, 'rwxr-xr-x') end) -- writable again, even when the case fails
	if vim.fn.filewritable(s.session_dir) == 2 then -- root writes through a read-only folder
		vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
		MiniTest.skip('a read-only folder is still writable: the suite runs as root')
	end
	child.messages()
	child.lua('vim.api.nvim_buf_set_lines(...)', { p.buf, 0, -1, false, lines })
	child.lua('vim.api.nvim_set_current_win(...)', { p.win })
	child.type_keys('q')
	child.settle()
	local got = { warned = #S2.notices(child.messages()), open = child.lua('return vim.api.nvim_win_is_valid(...)', { p.win }) }
	vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
	eq(got, { warned = 1, open = false })
end

-- T542's edit, left unwritten, then <CR> on x, closed onto the editor's list, a list in memory.
T['T555 [char] (S2) <CR> in the closed lists reopens when only the write into the whole editor\'s file fails'] = function()
	local s = S2.shared()
	local w1 = file_only_state(s)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	child.cmd('bdelete x.txt')
	child.settle()
	local p = S2.picker(child)
	local _, e = under_detached(p.lines)
	eq(e ~= nil, true)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, e)
	local x
	for i, l in ipairs(lines) do
		if l:find('x.txt', 1, true) then x = i end
	end
	eq(x ~= nil, true)
	vim.fn.setfperm(s.session_dir, 'r-xr-xr-x')
	MiniTest.finally(function() vim.fn.setfperm(s.session_dir, 'rwxr-xr-x') end) -- writable again, even when the case fails
	if vim.fn.filewritable(s.session_dir) == 2 then -- root writes through a read-only folder
		vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
		MiniTest.skip('a read-only folder is still writable: the suite runs as root')
	end
	child.messages()
	child.lua('vim.api.nvim_buf_set_lines(...)', { p.buf, 0, -1, false, lines })
	child.lua('vim.api.nvim_set_current_win(...)', { p.win })
	child.lua('vim.api.nvim_win_set_cursor(0, { ..., 0 })', { x })
	child.type_keys('<CR>')
	child.settle()
	local got = { warned = #S2.notices(child.messages()), shown = child.shown(w1) }
	vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
	eq(got, { warned = 1, shown = 'x' })
end

T['T587 [char] (S2) gf says what\'s kept when only the write into the whole editor\'s file fails'] = function()
	local s = S2.shared()
	local w1 = file_only_state(s)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	child.cmd('bdelete x.txt')
	child.settle()
	local p = S2.picker(child)
	local _, e = under_detached(p.lines)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, e)
	local x = S2.line_of(lines, 'x.txt')
	eq(x ~= nil, true)
	vim.fn.setfperm(s.session_dir, 'r-xr-xr-x')
	MiniTest.finally(function() vim.fn.setfperm(s.session_dir, 'rwxr-xr-x') end) -- writable again, even when the case fails
	if vim.fn.filewritable(s.session_dir) == 2 then -- root writes through a read-only folder
		vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
		MiniTest.skip('a read-only folder is still writable: the suite runs as root')
	end
	child.messages()
	child.lua('vim.api.nvim_buf_set_lines(...)', { p.buf, 0, -1, false, lines })
	child.lua('vim.api.nvim_set_current_win(...)', { p.win })
	child.lua('vim.api.nvim_win_set_cursor(0, { ..., 0 })', { x })
	child.type_keys('gf')
	child.settle()
	local said = S2.notices(child.messages())
	local got = { shown = child.shown(w1), open = child.lua('return vim.api.nvim_win_is_valid(...)', { p.win }),
		kept = #said == 1 and said[1]:find('the lists in memory keep their edits', 1, true) ~= nil }
	vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
	eq(got, { shown = 'x', open = true, kept = true })
end

T['T588 [char] (S2) a No Name text discarded by a write that failed only on the file isn\'t asked about again'] = function()
	local s = S2.shared()
	local w1 = file_only_state(s)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	local buf = S2.noname(child, { 'scratch' })
	child.steps({ ':e t' })
	child.cmd('bwipeout! ' .. buf)
	child.settle()
	local p = S2.picker(child)
	local _, e = under_detached(p.lines)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, e)
	table.remove(lines, S2.line_of(lines, '[No Name]'))
	child.lua([[
		_G.FRG_ASKED = 0
		vim.fn.confirm = function() _G.FRG_ASKED = _G.FRG_ASKED + 1 return 1 end
	]])
	vim.fn.setfperm(s.session_dir, 'r-xr-xr-x')
	MiniTest.finally(function() vim.fn.setfperm(s.session_dir, 'rwxr-xr-x') end) -- writable again, even when the case fails
	if vim.fn.filewritable(s.session_dir) == 2 then -- root writes through a read-only folder
		vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
		MiniTest.skip('a read-only folder is still writable: the suite runs as root')
	end
	S2.write_picker(child, p, lines)
	child.lua('vim.api.nvim_set_current_win(...)', { p.win })
	child.type_keys('q')
	child.settle()
	local got = { asked = child.lua('return _G.FRG_ASKED'), open = child.lua('return vim.api.nvim_win_is_valid(...)', { p.win }) }
	vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
	eq(got, { asked = 1, open = false })
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
			local ok = pcall(require('frogman').load_session, ..., { tab = tab })
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
			original = vim.w.oil_original_buffer == vim.fn.bufnr(_G.FRG_TEST.root .. '/b.txt'),
			oil_registered = require('frogman.domains.history').get_hash_from_buffer(oil) ~= nil,
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

T['T325 [char] (S2) :FrogmanClosed opens an editable buffer listing the closed entries, newest first, and no open buffer'] = function()
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
	local H = require('frogman.domains.history')
	local out = {}
	for id, pool in pairs(H.routines.pools()) do
		local entries = {}
		for _, h in ipairs(pool.closed) do
			table.insert(entries, vim.fn.fnamemodify(H.get_filepath_from_handle(h) or tostring(h), ':t:r') .. '@' .. tostring(pool.times[h]))
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
		local H = require('frogman.domains.history')
		local w2 = ...
		local x = H.get_handle_from_filepath(vim.fn.getcwd(-1, -1) .. '/x.txt')
		local editor = H.routines.pools()['']
		local session = H.routines.pool_of_tab(vim.api.nvim_win_get_tabpage(w2))
		session:push(x, editor.times[x] + 60, true)
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
		os.remove(_G.FRG_TEST.root .. '/b.txt')
		local H = require('frogman.domains.history')
		H.handles.set_tag(H.get_handle_from_filepath(_G.FRG_TEST.root .. '/b.txt'), 'feature')
	]])
	child.settle()
	local p = S2.picker(child)
	local b = S2.line_of(p.lines, 'b.txt')
	eq(b ~= nil and S2.shown_line(child, p.buf, b):find('⎇feature', 1, true) ~= nil, true)
end

T['T374 [char] (S2) with the ASCII glyph set the picker draws nothing outside ASCII'] = function()
	local s = S2.shared()
	two_pools(s)
	child.lua([[_G.FRG_TEST.setup({ session_dir = require('frogman.configs').session_dir, glyphs = { set = 'ascii' } })]])
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
		local H = require('frogman.domains.history')
		local out = {}
		for _, pool in pairs(H.routines.pools()) do
			if pool.directory then
				local names = {}
				for _, h in ipairs(pool.closed) do table.insert(names, vim.fs.basename(H.get_filepath_from_handle(h) or tostring(h))) end
				out[vim.fn.fnamemodify(pool.directory, ':h:t') .. '/' .. vim.fn.fnamemodify(pool.directory, ':t')] = table.concat(names, ',')
			end
		end
		return out
	]])
end

-- Two nameless tab sessions, in w/app and p/app: one name, one last part.
T['T504 [char] (S2) two lists of one name and one last part get headers of their own'] = function()
	child.setup()
	child.lua('for _, d in ipairs({ "w/app", "p/app" }) do vim.fn.mkdir(_G.FRG_TEST.root .. "/" .. d, "p") end')
	child.steps({ ':e a' })
	child.cmd('tcd w/app')
	child.cmd('edit ../../b.txt')
	child.cmd('edit ../../c.txt')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").save_session, nil, { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.cmd('bdelete ' .. child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/b.txt")'))
	child.cmd('tabnew')
	child.cmd('tcd ' .. child.lua('return _G.FRG_TEST.root') .. '/p/app')
	child.cmd('edit ../../d.txt')
	child.cmd('edit ../../e.txt')
	child.settle()
	eq(child.lua('return { pcall(require("frogman").save_session, nil, { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.cmd('bdelete ' .. child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/d.txt")'))
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
	child.cmd('FrogmanClosed')
	child.settle()
	local got = child.lua([[
		local buf = vim.fn.bufnr('frogman://closed-lists')
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
		local steps = require('frogman').ledger.steps()
		for i = #steps, 1, -1 do
			if steps[i].trigger == '<CR>' then return { win = steps[i].win, after = steps[i].row_after ~= nil } end
		end
		return vim.NIL
	]])
	eq(step, { win = source, after = true })
end

T['T503 [char] (S2) a closed_entry formatter that gives nothing leaves frogman\'s own text'] = function()
	local s = S2.shared()
	two_pools(s)
	child.lua([[_G.FRG_TEST.setup({ session_dir = require('frogman.configs').session_dir,
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
			named = require('frogman.configs').keymaps.open_closed_lists,
		}
	]], { came_from })
	eq({ moved = got.moved, modifiable = got.modifiable, c = got.lines:find('c.txt', 1, true) ~= nil, named = got.named },
		{ moved = true, modifiable = true, c = true, named = '<M-;>W' })
end

-- vim.fn.confirm is answered by hand: the choice named No, then Yes, in the write's one prompt.
T['T376 [char] (S2, DESK.md:1733) discarding a No Name entry in the picker asks first, in the write\'s one prompt'] = function()
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
			local H = require('frogman.domains.history')
			for _, h in ipairs(H.get_closed_buffers()) do
				if (H.get_filepath_from_handle(h) or ''):match('^NONAME_') then return H.handles.get(h).text ~= nil end
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
	answer('No')
	delete_and_write()
	local kept = noname_listed()
	answer('Yes')
	delete_and_write()
	eq({ kept = kept, discarded = not noname_listed() }, { kept = true, discarded = true })
end

T['T377 [char] (S2) a typed header that names no list is asked about'] = function()
	two_closed()
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	table.insert(lines, '≡nowhere')
	child.answer('No')
	S2.write_picker(child, p, lines)
	local no = {
		named = (child.prompts()[1] or ''):find('≡nowhere', 1, true) ~= nil,
		closed = child.closed(),
		modified = child.lua('return vim.bo[...].modified', { p.buf }),
	}
	child.answer('Yes')
	child.lua('vim.api.nvim_buf_call(..., function() vim.cmd("write") end)', { p.buf })
	child.settle()
	eq({ no, { closed = child.closed(), modified = child.lua('return vim.bo[...].modified', { p.buf }) } },
		{ { named = true, closed = 'b,c', modified = true }, { closed = 'b,c', modified = false } })
end

-- The guard's cases type keys one group at a time, letting the editor settle between, as
-- typing does: a burst typed at once fires the events differently.
local function keys(...)
	for _, k in ipairs({ ... }) do
		child.type_keys(k)
		child.settle()
	end
end

local function picker_lines()
	return child.lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)')
end

-- The cursor on t's header, the line above c's, its only entry.
local function on_t_header(lines)
	local c = S2.line_of(lines, 'c.txt')
	child.lua('vim.api.nvim_win_set_cursor(0, { ..., 0 })', { c - 1 })
end

T['T671 [char] (S2) a header deleted outside insert mode comes back, and <C-r> can\'t take it again'] = function()
	local s = S2.shared()
	two_pools(s)
	local p = S2.picker(child)
	on_t_header(p.lines)
	keys('dd')
	local after_dd = picker_lines()
	keys('<C-r>')
	local after_redo = picker_lines()
	child.lua('vim.cmd("write")')
	child.settle()
	eq({ after_dd, after_redo, S2.picker(child).lines }, { p.lines, p.lines, p.lines })
end

T['T672 [char] (S2) a header can\'t be changed in insert mode, keystroke by keystroke'] = function()
	local s = S2.shared()
	two_pools(s)
	local p = S2.picker(child)
	local got = {}
	for name, seq in pairs({
		clear = { 'S', '<Esc>' },
		type_over = { 'A', 'x', 'y', 'z', '<Esc>' },
		join = { 'I', '<BS>', '<Esc>' },
		split = { 'A', '<Left>', '<CR>', '<Esc>' },
	}) do
		on_t_header(p.lines)
		keys(unpack(seq))
		got[name] = picker_lines()
	end
	child.lua('vim.cmd("write")')
	child.settle()
	eq({ got, S2.picker(child).lines },
		{ { clear = p.lines, type_over = p.lines, join = p.lines, split = p.lines }, p.lines })
end

T['T673 [char] (S2, DESK.md:1730) a pasted copy of a header stays where it\'s put'] = function()
	local s = S2.shared()
	two_pools(s)
	local p = S2.picker(child)
	on_t_header(p.lines)
	keys('yy', 'p')
	local lines = vim.deepcopy(p.lines)
	local t = S2.line_of(p.lines, 'c.txt') - 1
	table.insert(lines, t + 1, lines[t])
	eq(picker_lines(), lines)
end

T['T674 [char] (S2) a redraw of frogman\'s own is the state the guard takes back to'] = function()
	local s = S2.shared()
	two_pools(s)
	local p = S2.picker(child)
	child.lua('vim.api.nvim_win_set_cursor(0, { ..., 0 })', { S2.line_of(p.lines, 'x.txt') })
	keys('gf')
	child.lua('vim.api.nvim_set_current_win(...)', { p.win })
	child.settle()
	local redrawn = picker_lines()
	on_t_header(redrawn)
	keys('dd')
	eq({ x_gone = S2.line_of(redrawn, 'x.txt') == nil, lines = picker_lines() }, { x_gone = true, lines = redrawn })
end

T['T675 [char] (S2) the write asks first about the lines it would leave out'] = function()
	two_closed()
	local p = S2.picker(child)
	local b = S2.line_of(p.lines, 'b.txt')
	local lines = vim.deepcopy(p.lines)
	table.insert(lines, b + 1, lines[b]) -- a pasted copy, under the list that drew it
	table.insert(lines, 'typo.txt')
	child.answer('No')
	S2.write_picker(child, p, lines)
	local prompt = child.prompts()
	local no = {
		prompts = #prompt,
		named = (prompt[1] or ''):find('typo.txt', 1, true) ~= nil and (prompt[1] or ''):find('twice under', 1, true) ~= nil,
		closed = child.closed(),
		lines = child.lua('return vim.api.nvim_buf_get_lines(..., 0, -1, false)', { p.buf }),
		modified = child.lua('return vim.bo[...].modified', { p.buf }),
		cursor = child.lua('return vim.api.nvim_win_get_cursor(...)[1]', { p.win }),
	}
	child.answer('Yes')
	child.lua('vim.api.nvim_buf_call(..., function() vim.cmd("write") end)', { p.buf })
	child.settle()
	local yes = { closed = child.closed(), modified = child.lua('return vim.bo[...].modified', { p.buf }) }
	eq({ no, yes }, {
		{ prompts = 1, named = true, closed = 'b,c', lines = lines, modified = true, cursor = b + 1 },
		{ closed = 'b,c', modified = false },
	})
end

T['T676 [char] (S2) a merge\'s duplicate isn\'t asked about'] = function()
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
	child.answer('No')
	S2.write_picker(child, p, lines)
	local after = child.lua(LISTS_STATE)
	eq({ prompts = #child.prompts(), editor = after[''] }, { prompts = 0, editor = 'x@' .. before.t:match('x@([%d%.]+)') })
end

T['T677 [char] (S2) q stays open when the prompt is answered No'] = function()
	two_closed()
	local p = S2.picker(child)
	child.lua('vim.api.nvim_buf_set_lines(..., -1, -1, false, { "typo.txt" })', { p.buf })
	child.answer('No')
	child.type_keys('q')
	child.settle()
	local no = {
		open = child.lua('return vim.api.nvim_win_is_valid(...)', { p.win }),
		modified = child.lua('return vim.api.nvim_buf_is_valid(...) and vim.bo[...].modified', { p.buf }),
	}
	child.answer('Yes')
	child.type_keys('q')
	child.settle()
	eq({ no, { open = child.lua('return vim.api.nvim_win_is_valid(...)', { p.win }), closed = child.closed() } },
		{ { open = true, modified = true }, { open = false, closed = 'b,c' } })
end

-- b and c closed, the lists open with an edit not written (their lines swapped), then c reopened in the
-- window they came from, as from another window: c's line, drawn closed, is open by the write. The
-- cleanup tick waits an hour, so nothing else takes c off a list between.
T['T926 [char] (S2 Closed-stack picker, I7, DESK.md:758) the write asks about a line whose file is open now, and Yes leaves it off'] = function()
	two_closed()
	child.lua('_G.FRG_TEST.setup({ cleanup_interval = 3600000 })')
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	local c, b = S2.line_of(lines, 'c.txt'), S2.line_of(lines, 'b.txt')
	lines[c], lines[b] = lines[b], lines[c]
	child.lua('vim.api.nvim_buf_set_lines(..., 0, -1, false, select(2, ...))', { p.buf, lines })
	child.lua([[
		local from = ...
		vim.api.nvim_win_call(from, function() vim.cmd('edit c.txt') end)
	]], { p.came_from })
	child.settle()
	child.prompts()
	child.answer('Yes')
	child.lua('vim.api.nvim_buf_call(..., function() vim.cmd("write") end)', { p.buf })
	child.settle()
	local asked = child.prompts()
	local open_now = #asked == 1 and asked[1]:find('c.txt', 1, true) ~= nil and asked[1]:find('open now', 1, true) ~= nil
	eq({ asked = open_now, closed = child.closed() }, { asked = true, closed = 'b' })
end

-- b and c closed, the lists open with a line no list names added, so :w asks. c is opened in the window the
-- lists came from in the same call as the :w, its arrival queued, and that arrival runs while the prompt
-- waits, as queued work can under a typed :w: the write leaves c's line off, and says so once it's done.
T['T929 [char] (S2 Closed-stack picker, I7) a line whose file opened while the write was asking is left off, and said'] = function()
	two_closed()
	child.lua('_G.FRG_TEST.setup({ cleanup_interval = 3600000 })')
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	table.insert(lines, 'typo.txt')
	child.lua('vim.api.nvim_buf_set_lines(..., 0, -1, false, select(2, ...))', { p.buf, lines })
	child.messages()
	local dumps = child.dump_files()
	child.lua([[
		vim.fn.confirm = function()
			require('frogman.settle').drain() -- what was queued runs while the prompt waits: c's arrival
			return 1
		end
	]])
	child.lua([[
		local from, buf = ...
		vim.api.nvim_win_call(from, function() vim.cmd('edit c.txt') end) -- its arrival queued, not run yet
		vim.api.nvim_buf_call(buf, function() vim.cmd('write') end)
	]], { p.came_from, p.buf })
	child.settle()
	local said = vim.tbl_filter(function(m) return m.msg:find('c.txt', 1, true) ~= nil and m.msg:find('open', 1, true) ~= nil end,
		child.messages())
	eq({ closed = child.closed(), said = #said, dump = child.dumped_since(dumps) }, { closed = 'b', said = 1, dump = nil })
end

-- T929's race with two files: c opened in the window the lists came from, b in a split of it, both arrivals
-- queued, both running while the prompt waits: one message names both, joined as natural English.
T['T930 [char] (S2 Closed-stack picker, I7) two lines whose files opened while the write was asking are said in one message'] = function()
	two_closed()
	child.lua('_G.FRG_TEST.setup({ cleanup_interval = 3600000 })')
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	table.insert(lines, 'typo.txt')
	child.lua('vim.api.nvim_buf_set_lines(..., 0, -1, false, select(2, ...))', { p.buf, lines })
	child.messages()
	local dumps = child.dump_files()
	child.lua([[
		vim.fn.confirm = function()
			require('frogman.settle').drain() -- what was queued runs while the prompt waits: b's and c's arrivals
			return 1
		end
	]])
	child.lua([[
		local from, buf = ...
		vim.api.nvim_win_call(from, function()
			vim.cmd('edit c.txt')
			vim.cmd('split b.txt') -- b in a window of its own, its arrival queued beside c's
		end)
		vim.api.nvim_buf_call(buf, function() vim.cmd('write') end)
	]], { p.came_from, p.buf })
	child.settle()
	local said = vim.tbl_map(function(m) return m.msg end, vim.tbl_filter(function(m)
		return m.msg:find('opened while the write was asking', 1, true) ~= nil end, child.messages()))
	eq({ closed = child.closed(), said = said, dump = child.dumped_since(dumps) },
		{ closed = '', said = { "frogman: b.txt and c.txt opened while the write was asking, so they're open now, off the closed lists." } })
end

T['T525 [char] (S1 Load) a window entry whose maps are saved as null loads with empty ones'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(S2.save(child), { true })
	-- the saved maps set to null by hand, as a file written elsewhere may hold them
	child.lua([[
		local st = require('frogman.domains.storage').routines
		local dir = vim.fn.getcwd(-1, -1)
		local saved = st.read_session(dir, nil)
		for _, w in ipairs(saved.windows) do
			w[5], w[6] = vim.NIL, vim.NIL
		end
		st.write_session(dir, nil, saved, {})
	]])
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.messages()
	eq(S2.load(child), { true })
	child.settle(300)
	local failed = false
	for _, m in ipairs(child.messages()) do
		if m.msg:find('failed', 1, true) then failed = true end
	end
	local maps = child.lua([[
		local t = require('frogman.domains.window').data.crux[vim.api.nvim_get_current_win()]
		return { t = t and type(t.displacement_ternary_map), s = t and type(t.displacement_secondary_map) }
	]])
	eq({ failed = failed, maps = maps, slots = child.slots() },
		{ failed = false, maps = { t = 'table', s = 'table' }, slots = '⦉a⦊ [b] ⟦-⟧' })
end

-- A split in t_DETACHED's tab with only an empty typed group, closed: held over, empty, in the list's scope.
local function empty_held_in_split(win)
	child.lua('vim.api.nvim_set_current_win(...)', { win })
	child.settle()
	child.cmd('split')
	child.settle()
	child.steps({ ':e d', "<M-'><M-e>" })
	local buf = child.lua('return (require("frogman.domains.marks.popup").buffer() or -1)')
	local lines = child.lua('return vim.api.nvim_buf_get_lines(..., 0, -1, false)', { buf })
	lines[1] = '❖ todo'
	child.lua('local b, l = ...; vim.api.nvim_buf_set_lines(b, 0, -1, false, l)', { buf, lines })
	child.cmd('silent! write')
	child.settle(100)
	child.cmd('close')
	child.settle()
	child.cmd('close')
	child.settle(300)
end

T['T1043 [char] (S2, M15, DESK.md:1214) a list in the file alone emptied gives its empty held-over group to the whole editor\'s scope'] = function()
	local s = S2.shared()
	local w1, w2 = tab_session(s)
	eq(S2.save(child), { true })
	child.steps({ ':e e', ':e d' })
	child.cmd('bdelete e.txt')
	child.settle()
	eq(S2.load_tab_session(child, 't'), { true })
	empty_held_in_split(w2)
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	local p = S2.picker(child)
	local _, e = under_detached(p.lines)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, e)
	S2.write_picker(child, p, lines)
	child.settle(300)
	eq(child.lua(WHOLE_HELD), { groups = 1, snapshots = 0, file_groups = 1, file_snapshots = 0 })
end

-- T860's route with the split holding only an empty typed group: the list merged away gives the group to the
-- whole editor's scope, empty, still known by the name it was held over from.
T['T1047 [char] (S2, M15, DESK.md:1214, :1211) a detached list merged away gives its empty held-over group to the whole editor\'s scope, known as before'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s)
	eq(S2.save(child), { true })
	child.steps({ ':e x', ':e c', ':e d' })
	child.cmd('bdelete x.txt')
	child.cmd('bdelete c.txt')
	child.settle()
	child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		require('frogman').load_session('t')
	]])
	child.settle(300)
	empty_held_in_split(w2) -- in the second tab, now t_DETACHED's
	child.lua([[
		vim.api.nvim_set_current_win(...)
		vim.cmd('noautocmd edit d.txt')
		require('frogman').load_session('t')
	]], { w2 })
	child.settle(300)
	local p = child.lua(OPEN_LISTS)
	local lines, moved, under, section = {}, {}, nil, nil
	for _, l in ipairs(p.lines) do
		if l:sub(1, 3) == '≡' then section = l end
		if section == '≡t_DETACHED' and l ~= '≡t_DETACHED' then table.insert(moved, l) else table.insert(lines, l) end
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
	eq(child.lua([[
		local out = {}
		for _, g in ipairs((require('frogman.domains.marks').data.scopes.session[''] or { groups = {} }).groups) do
			if g.held then table.insert(out, { empty = next(g.marks) == nil, from = g.from or false }) end
		end
		return out
	]]), { { empty = true, from = 'todo' } })
end


-- A detached list's copy of its session's marks as the whole editor's file holds it: its closed files' count and
-- its own groups' marks by file letter; nil when the file holds no such list.
local DETACHED_MARKS = [[
	local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), nil)
	for _, list in ipairs(saved and saved.detached or {}) do
		if list.label == ... then
			local marks = {}
			for _, g in ipairs(list.marks or {}) do
				if not g.held then
					for alias, h in pairs(g.marks or {}) do
						marks[alias] = vim.fn.fnamemodify((saved.paths or {})[h] or h, ':t:r')
					end
				end
			end
			return { closed = #(list.closed or {}), marks = marks }
		end
	end
	return vim.NIL
]]

-- The whole editor's held-over groups, in memory and in its file: each by its header without the time and its
-- marks by file letter.
local EDITOR_HELD = [[
	local H = require('frogman.domains.history')
	local function what(name)
		return (name:gsub('^held over · ', ''):gsub(' · %d%d%-%d%d %d%d:%d%d.*$', ''))
	end
	local memory = {}
	for _, g in ipairs((require('frogman.domains.marks').data.scopes.session[''] or { groups = {} }).groups) do
		if g.held then
			local marks = {}
			for alias, id in pairs(g.marks) do
				local h = H.handles.get(H.handles.resolve(id))
				table.insert(marks, alias .. '=' .. (h and vim.fn.fnamemodify(H.get_filepath_from_hash(h.hash), ':t:r') or '?'))
			end
			table.sort(marks)
			table.insert(memory, what(g.name) .. ' ' .. table.concat(marks, ','))
		end
	end
	local saved = require('frogman.domains.storage.routines').read_session(vim.fn.getcwd(-1, -1), nil) or {}
	local file = {}
	for _, g in ipairs(saved.marks or {}) do
		if g.held then
			local marks = {}
			for alias, h in pairs(g.marks or {}) do
				table.insert(marks, alias .. '=' .. vim.fn.fnamemodify((saved.paths or {})[h] or h, ':t:r'))
			end
			table.sort(marks)
			table.insert(file, what(g.name) .. ' ' .. table.concat(marks, ','))
		end
	end
	return { memory = memory, file = file }
]]

-- T318's state, a whole-editor save, then t's session mark a on c made in t's tab, and t loaded into a third tab,
-- so the second keeps t_DETACHED with a copy of t's list, empty, and of its marks. Returns the second tab's window.
local function detached_with_copy(s, marked)
	local _, w2 = tab_session(s)
	eq(S2.save(child), { true })
	if marked then
		child.steps({ "<M-'><M-3>", ':e c', "<M-'><M-'><M-a>", ':e d', "<M-'><M-1>" })
	end
	eq(S2.load_tab_session(child, 't'), { true })
	return w2
end

-- A list in the whole editor's file alone, emptied in the closed lists: its copy of its session's marks goes to
-- the whole editor's scope, held over under the list's name, and the list leaves the file.
T['T1095 [char] (S2, M15, DESK.md:1214) a list in the file alone emptied in the closed lists gives its copy of the session\'s marks to the whole editor\'s scope'] = function()
	local s = S2.shared()
	local w1, w2 = tab_session(s)
	child.steps({ "<M-'><M-3>", ':e c', "<M-'><M-'><M-a>", ':e d', "<M-'><M-1>" }) -- t's session mark, made in t's tab
	eq(S2.save(child), { true })
	child.steps({ ':e e', ':e d' })
	child.cmd('bdelete e.txt')
	child.settle()
	eq(S2.load_tab_session(child, 't'), { true })
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	local before = child.lua(DETACHED_MARKS, { 't_DETACHED' })
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	local p = S2.picker(child)
	local _, e = under_detached(p.lines)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, e)
	S2.write_picker(child, p, lines)
	child.settle(300)
	eq({ before = before, after = child.lua(DETACHED_MARKS, { 't_DETACHED' }), held = child.lua(EDITOR_HELD) },
		{ before = { closed = 1, marks = { a = 'c' } }, after = vim.NIL,
			held = { memory = { 't_DETACHED a=c' }, file = { 't_DETACHED a=c' } } })
end

-- A detached list merged away in the closed lists: it leaves memory and the file, and its copy of its session's
-- marks goes to the whole editor's scope, held over under its name.
T['T1096 [char] (S2, M15, DESK.md:1214) a detached list merged away gives its copy of the session\'s marks to the whole editor\'s scope'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s)
	child.steps({ "<M-'><M-3>", ':e c', "<M-'><M-'><M-a>", ':e d', "<M-'><M-1>" })
	eq(S2.save(child), { true })
	child.steps({ ':e x', ':e c', ':e d' })
	child.cmd('bdelete x.txt')
	child.cmd('bdelete c.txt')
	child.settle()
	child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		require('frogman').load_session('t')
	]])
	child.settle(300)
	child.lua([[
		vim.api.nvim_set_current_win(...)
		vim.cmd('noautocmd edit d.txt')
		require('frogman').load_session('t')
	]], { w2 })
	child.settle(300)
	local p = child.lua(OPEN_LISTS)
	eq(p ~= vim.NIL, true)
	local lines, moved, under, section = {}, {}, nil, nil
	for _, l in ipairs(p.lines) do
		if l:sub(1, 3) == '≡' then section = l end
		if section == '≡t_DETACHED' and l ~= '≡t_DETACHED' then table.insert(moved, l) else table.insert(lines, l) end
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
	eq({ in_memory = child.lua(IN_MEMORY, { 't_DETACHED' }), file = child.lua(DETACHED_MARKS, { 't_DETACHED' }), held = child.lua(EDITOR_HELD) },
		{ in_memory = false, file = vim.NIL, held = { memory = { 't_DETACHED a=c' }, file = { 't_DETACHED a=c' } } })
end

-- A detached list whose last tab closes with nothing in its closed list goes as an emptied one does: its copy of
-- its session's marks goes to the whole editor's scope, held over under its name, and the list leaves the file.
T['T1097 [char] (S2, M15, DESK.md:1214) a detached list whose tab closes with nothing in its list gives its copy of the session\'s marks to the whole editor\'s scope'] = function()
	local s = S2.shared()
	local w2 = detached_with_copy(s, true)
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	eq({ after = child.lua(DETACHED_MARKS, { 't_DETACHED' }), in_memory = child.lua(IN_MEMORY, { 't_DETACHED' }), held = child.lua(EDITOR_HELD) },
		{ after = vim.NIL, in_memory = false, held = { memory = { 't_DETACHED a=c' }, file = { 't_DETACHED a=c' } } })
end

-- A detached list whose last tab closes with nothing left in it at all, no closed file, no mark, no held-over
-- snapshot, leaves the whole editor's file.
T['T1098 [char] (S2, M15, DESK.md:1214) a detached list whose tab closes with nothing left in it leaves the whole editor\'s file'] = function()
	local s = S2.shared()
	local w2 = detached_with_copy(s, false)
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	eq({ after = child.lua(DETACHED_MARKS, { 't_DETACHED' }), held = child.lua(EDITOR_HELD) },
		{ after = vim.NIL, held = { memory = {}, file = {} } })
end

-- T1097's list with a second group typed into its copy: each group is held over under the list's name and its own.
T['T1099 [char] (S2, M15, DESK.md:1214, :1208) a detached list leaving with two groups names each group after the list'] = function()
	local s = S2.shared()
	local w2 = detached_with_copy(s, true)
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.settle()
	child.steps({ "<M-'><M-3>", "<M-'><M-e>" }) -- the list's copy, in its tab's session mode
	local buf = child.lua('return (require("frogman.domains.marks.popup").buffer() or -1)')
	child.lua('local b = ...; vim.api.nvim_buf_set_lines(b, 0, -1, false, { "❖ main", "a -> c.txt", "❖ two", "s -> d.txt" })', { buf })
	child.cmd('silent! write')
	child.settle(100)
	child.cmd('close')
	child.settle()
	child.steps({ "<M-'><M-1>" })
	local copy = child.lua([[
		local H = require('frogman.domains.history')
		local id = H.data.tab_pools[vim.api.nvim_win_get_tabpage(...)]
		local out = {}
		for _, g in ipairs((require('frogman.domains.marks').data.scopes.session[id] or { groups = {} }).groups) do
			local marks = {}
			for alias, hid in pairs(g.marks) do
				local h = H.handles.get(H.handles.resolve(hid))
				table.insert(marks, alias .. '=' .. (h and vim.fn.fnamemodify(H.get_filepath_from_hash(h.hash), ':t:r') or '?'))
			end
			table.sort(marks)
			table.insert(out, g.name .. ' ' .. table.concat(marks, ','))
		end
		return out
	]], { w2 })
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	eq({ copy = copy, held = child.lua(EDITOR_HELD) }, { copy = { 'main a=c', 'two s=d' },
		held = { memory = { 't_DETACHED, main a=c', 't_DETACHED, two s=d' }, file = { 't_DETACHED, main a=c', 't_DETACHED, two s=d' } } })
end

-- A detached list whose tab is still open stays in the whole editor's file, nothing in its closed list and no
-- marks: its tab keeps it, and the next load finds the tab by it.
T['T1100 [char] (S2, DESK.md:1214) a detached list whose tab is open stays in the whole editor\'s file, empty'] = function()
	local s = S2.shared()
	detached_with_copy(s, false)
	eq(S2.save(child), { true })
	eq(child.lua(DETACHED_MARKS, { 't_DETACHED' }), { closed = 0, marks = {} })
end



-- A detached list whose tab closes with nothing in its closed list gives what its tab's windows left held over, a
-- group and a snapshot, to the whole editor's scope, and leaves the file.
T['T1102 [char] (S2, M15, M16, DESK.md:1214) a detached list whose tab closes with nothing in its list gives its held-over group and snapshot to the whole editor\'s scope'] = function()
	local s = S2.shared()
	local w2 = detached_with_copy(s, false)
	held_in_split(w2) -- in the second tab, now t_DETACHED's
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	eq({ after = child.lua(DETACHED_MARKS, { 't_DETACHED' }), held = child.lua(WHOLE_HELD) },
		{ after = vim.NIL, held = { groups = 1, snapshots = 1, file_groups = 1, file_snapshots = 1 } })
end

-- T1095's write failing once, the session directory read-only, then written again: the list's copy is held over
-- once in the whole editor's scope, the retried write not moving it a second time.
T['T1103 [char] (S2, M15, DESK.md:1214) a list in the file alone emptied by a write that fails and is retried gives its copy once'] = function()
	local s = S2.shared()
	local w1, w2 = tab_session(s)
	child.steps({ "<M-'><M-3>", ':e c', "<M-'><M-'><M-a>", ':e d', "<M-'><M-1>" }) -- t's session mark, made in t's tab
	eq(S2.save(child), { true })
	child.steps({ ':e e', ':e d' })
	child.cmd('bdelete e.txt')
	child.settle()
	eq(S2.load_tab_session(child, 't'), { true })
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	local p = S2.picker(child)
	local _, e = under_detached(p.lines)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, e)
	vim.fn.setfperm(s.session_dir, 'r-xr-xr-x')
	MiniTest.finally(function() vim.fn.setfperm(s.session_dir, 'rwxr-xr-x') end) -- writable again, even when the case fails
	if vim.fn.filewritable(s.session_dir) == 2 then -- root writes through a read-only folder
		vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
		MiniTest.skip('a read-only folder is still writable: the suite runs as root')
	end
	S2.write_picker(child, p, lines) -- the file can't take it: the edit stays on screen
	vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
	child.lua('local b = ...; vim.api.nvim_buf_call(b, function() vim.cmd("write") end)', { p.buf })
	child.settle(300)
	eq({ after = child.lua(DETACHED_MARKS, { 't_DETACHED' }), held = child.lua(EDITOR_HELD) },
		{ after = vim.NIL, held = { memory = { 't_DETACHED a=c' }, file = { 't_DETACHED a=c' } } })
end


-- A detached list whose tab closes with nothing in its list while the whole editor's file, which holds the list,
-- can't be written: the list stays in memory with no tab and nothing in it, so the next records write, once the
-- file can be written, leaves it out rather than taking the file's own entry for it, and lets it go from memory;
-- its copy is held over once.
T['T1104 [char] (S2, M15, DESK.md:1214) a detached list whose tab closes empty while the whole editor\'s file can\'t be written leaves it at the next write'] = function()
	local s = S2.shared()
	local w2 = detached_with_copy(s, true)
	eq(S2.save(child), { true }) -- the whole editor's file holds t_DETACHED with its copy
	local before = child.lua(DETACHED_MARKS, { 't_DETACHED' })
	vim.fn.setfperm(s.session_dir, 'r-xr-xr-x')
	MiniTest.finally(function() vim.fn.setfperm(s.session_dir, 'rwxr-xr-x') end) -- writable again, even when the case fails
	if vim.fn.filewritable(s.session_dir) == 2 then -- root writes through a read-only folder
		vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
		MiniTest.skip('a read-only folder is still writable: the suite runs as root')
	end
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.cmd('tabclose')
	child.settle(300)
	local kept = child.lua(IN_MEMORY, { 't_DETACHED' })
	vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
	child.lua('require("frogman.domains.storage").routines.write_records()') -- the records waiting, written now
	child.settle(300)
	eq({ before = before, kept = kept, after = child.lua(DETACHED_MARKS, { 't_DETACHED' }), in_memory = child.lua(IN_MEMORY, { 't_DETACHED' }),
		held = child.lua(EDITOR_HELD) },
		{ before = { closed = 0, marks = { a = 'c' } }, kept = true, after = vim.NIL, in_memory = false,
			held = { memory = { 't_DETACHED a=c' }, file = { 't_DETACHED a=c' } } })
end

-- T1096's merge, the whole editor's file holding the list, settled while that file can't be written: the list stays
-- in memory with no tab and nothing in it, so the next write, a save, leaves it out of the file and lets it go from
-- memory; its copy is held over once.
T['T1105 [char] (S2, M15, DESK.md:1214) a detached list merged away while the whole editor\'s file can\'t be written leaves it at the next write'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s)
	child.steps({ "<M-'><M-3>", ':e c', "<M-'><M-'><M-a>", ':e d', "<M-'><M-1>" })
	eq(S2.save(child), { true })
	child.steps({ ':e x', ':e c', ':e d' })
	child.cmd('bdelete x.txt')
	child.cmd('bdelete c.txt')
	child.settle()
	child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		require('frogman').load_session('t')
	]])
	child.settle(300)
	eq(S2.save(child), { true }) -- the whole editor's file holds t_DETACHED
	child.lua([[
		vim.api.nvim_set_current_win(...)
		vim.cmd('noautocmd edit d.txt')
		require('frogman').load_session('t')
	]], { w2 })
	child.settle(300)
	local p = child.lua(OPEN_LISTS)
	eq(p ~= vim.NIL, true)
	local lines, moved, under, section = {}, {}, nil, nil
	for _, l in ipairs(p.lines) do
		if l:sub(1, 3) == '≡' then section = l end
		if section == '≡t_DETACHED' and l ~= '≡t_DETACHED' then table.insert(moved, l) else table.insert(lines, l) end
	end
	for i, l in ipairs(lines) do
		if l == '≡t' then under = i end
	end
	for k, l in ipairs(moved) do
		table.insert(lines, under + k, l)
	end
	S2.write_picker(child, p, lines)
	vim.fn.setfperm(s.session_dir, 'r-xr-xr-x')
	MiniTest.finally(function() vim.fn.setfperm(s.session_dir, 'rwxr-xr-x') end) -- writable again, even when the case fails
	if vim.fn.filewritable(s.session_dir) == 2 then -- root writes through a read-only folder
		vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
		MiniTest.skip('a read-only folder is still writable: the suite runs as root')
	end
	type_into(p.win, 'q')
	child.settle(300)
	local kept = child.lua(IN_MEMORY, { 't_DETACHED' })
	vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
	eq(S2.save(child), { true })
	eq({ kept = kept, after = child.lua(DETACHED_MARKS, { 't_DETACHED' }), in_memory = child.lua(IN_MEMORY, { 't_DETACHED' }),
		held = child.lua(EDITOR_HELD) },
		{ kept = true, after = vim.NIL, in_memory = false, held = { memory = { 't_DETACHED a=c' }, file = { 't_DETACHED a=c' } } })
end


-- T1102's list, its tab's last window a split with a window mark on d, the tab closed while a records write queued
-- before the close waits: the write doesn't let the list go ahead of its close, so the window's group still reaches
-- the whole editor's scope as T1102's does.
T['T1106 [char] (S2, M15, DESK.md:1214) a detached list whose tab closes empty while a records write waits still gives its last window\'s group to the whole editor\'s scope'] = function()
	local s = S2.shared()
	local w2 = detached_with_copy(s, false)
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.settle()
	child.cmd('split')
	child.settle()
	child.lua('vim.api.nvim_win_close(..., false)', { w2 }) -- the split is t_DETACHED's tab's last window
	child.settle(300)
	child.steps({ ':e d', "<M-'><M-'><M-a>" })
	child.lua([[
		local storage = require('frogman.domains.storage').routines
		storage.records_changed('')
		vim.schedule(function() storage.write_records() end) -- a write queued ahead of the close's own work
		vim.cmd('tabclose')
	]])
	child.settle(300)
	eq({ after = child.lua(DETACHED_MARKS, { 't_DETACHED' }), in_memory = child.lua(IN_MEMORY, { 't_DETACHED' }),
		held = child.lua(EDITOR_HELD) },
		{ after = vim.NIL, in_memory = false, held = { memory = { 'window on d.txt a=d' }, file = { 'window on d.txt a=d' } } })
end


-- T1104's list with e on it: its tab closed while the whole editor's file can't be written, so it's kept in memory
-- with no tab, e on it, then the file made writable again. Returns once it's kept.
local function kept_with_e(s)
	local w2 = detached_with_copy(s, true)
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.settle()
	child.steps({ ':e e', ':e d' })
	child.cmd('bdelete e.txt') -- e on t_DETACHED's list
	child.settle()
	eq(S2.save(child), { true }) -- the whole editor's file holds t_DETACHED, e on it, and its copy
	vim.fn.setfperm(s.session_dir, 'r-xr-xr-x')
	MiniTest.finally(function() vim.fn.setfperm(s.session_dir, 'rwxr-xr-x') end) -- writable again, even when the case fails
	if vim.fn.filewritable(s.session_dir) == 2 then -- root writes through a read-only folder
		vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
		MiniTest.skip('a read-only folder is still writable: the suite runs as root')
	end
	child.cmd('tabclose') -- the close's write fails: the list stays in memory with no tab
	child.settle(300)
	vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
	return child.lua(IN_MEMORY, { 't_DETACHED' })
end

-- A detached list kept with no tab after a failed write, its last line deleted in the closed lists once the file can
-- be written: it goes as an emptied list does, its copy held over in the whole editor's scope, and it leaves
-- memory and the file.
T['T1107 [char] (S2, M15, DESK.md:1214) a detached list kept with no tab after a failed write, emptied in the closed lists, gives its copy to the whole editor\'s scope and leaves'] = function()
	local s = S2.shared()
	local kept = kept_with_e(s)
	local p = S2.picker(child)
	local _, e = under_detached(p.lines)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, e)
	S2.write_picker(child, p, lines)
	child.cmd('close')
	child.settle(300)
	eq({ kept = kept, after = child.lua(DETACHED_MARKS, { 't_DETACHED' }), in_memory = child.lua(IN_MEMORY, { 't_DETACHED' }),
		held = child.lua(EDITOR_HELD) },
		{ kept = true, after = vim.NIL, in_memory = false, held = { memory = { 't_DETACHED a=c' }, file = { 't_DETACHED a=c' } } })
end

-- The same list emptied by opening its last file again: it goes the same way.
T['T1108 [char] (S2, M15, DESK.md:1214) a detached list kept with no tab after a failed write, emptied by opening its file, gives its copy to the whole editor\'s scope and leaves'] = function()
	local s = S2.shared()
	local kept = kept_with_e(s)
	child.steps({ ':e e' }) -- e off every list
	child.settle(300)
	eq({ kept = kept, after = child.lua(DETACHED_MARKS, { 't_DETACHED' }), in_memory = child.lua(IN_MEMORY, { 't_DETACHED' }),
		held = child.lua(EDITOR_HELD) },
		{ kept = true, after = vim.NIL, in_memory = false, held = { memory = { 't_DETACHED a=c' }, file = { 't_DETACHED a=c' } } })
end


-- The same list emptied by opening its file and the whole editor saved at once, before any records write: the save
-- leaves the list out and holds its copy over in the whole editor's scope.
T['T1109 [char] (S2, M15, DESK.md:1214) a detached list kept with no tab after a failed write, emptied and saved at once, leaves the file through the save'] = function()
	local s = S2.shared()
	local kept = kept_with_e(s)
	local saved = child.lua([[
		vim.cmd('edit e.txt') -- e off every list; the records write waits for the next tick
		local ok = pcall(require('frogman').save_session)
		local file = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), nil) or {}
		local listed, held = false, 0
		for _, list in ipairs(file.detached or {}) do
			if list.label == 't_DETACHED' then listed = true end
		end
		for _, g in ipairs(file.marks or {}) do
			if g.held then held = held + 1 end
		end
		return { ok = ok, listed = listed, held = held }
	]])
	child.settle(300)
	eq({ kept = kept, saved = saved, in_memory = child.lua(IN_MEMORY, { 't_DETACHED' }) },
		{ kept = true, saved = { ok = true, listed = false, held = 1 }, in_memory = false })
end


-- A session file's closed list, its files by letter, sorted: the named session's.
local FILE_CLOSED = [[
	local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), ...) or {}
	local out = {}
	for _, h in ipairs(saved.closed or {}) do
		table.insert(out, vim.fn.fnamemodify((saved.paths or {})[h] or h, ':t:r'))
	end
	table.sort(out)
	return out
]]

-- Today's closes the trail records on a load's steps, the open one included, each as "<file letter> onto <lists>",
-- sorted.
local LOAD_CLOSES = [[
	local out = {}
	for _, step in ipairs(require('frogman.domains.ledger.routines').trail()) do
		if step.cause == 'load' then
			for _, move in ipairs(step.moves or {}) do
				if move.kind == 'closed' then
					table.insert(out, vim.fn.fnamemodify(move.name or '?', ':t:r') .. ' onto ' .. table.concat(move.lists or {}, ','))
				end
			end
		end
	end
	table.sort(out)
	return out
]]

-- A tab session's load into another tab session's tab, the teardown deleting that tab's buffers in the same call:
-- the session left keeps its closed list as its file had it, as at a whole-editor switch, while the trail still
-- records the closes onto its list.
T['T1101 [char] (S2, M5, DESK.md:1205) a tab session\'s load into a tab session\'s tab leaves the teardown\'s closes off the session left\'s closed list'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 'u'), { true })
	tab_session(s) -- t in the second tab, on d, c in its history
	local before = child.lua(FILE_CLOSED, { 't' })
	local got = child.lua([[
		vim.cmd('enew') -- the teardown keeps the tab: its window on an empty buffer, then the tab's buffers deleted
		vim.cmd('bdelete c.txt')
		vim.cmd('bdelete d.txt')
		return { pcall(require('frogman').load_session, 'u', { tab = vim.api.nvim_get_current_tabpage() }) }
	]])
	child.settle(300)
	eq({ before = before, got = got, after = child.lua(FILE_CLOSED, { 't' }), trail = child.lua(LOAD_CLOSES) },
		{ before = {}, got = { true }, after = {}, trail = { 'c onto t', 'd onto t' } })
end

-- The same teardown in a plain tab: the files it closes go onto the whole editor's list, which its file takes.
T['T1110 [char] (S2, M5, DESK.md:1205) a tab session\'s load into a plain tab puts the teardown\'s closes onto the whole editor\'s list'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 'u'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(S2.save(child), { true }) -- the whole editor's file, nothing on its list
	child.cmd('tabnew')
	child.steps({ ':e e', ':e f' })
	local got = child.lua([[
		vim.cmd('enew')
		vim.cmd('bdelete e.txt')
		vim.cmd('bdelete f.txt')
		return { pcall(require('frogman').load_session, 'u', { tab = vim.api.nvim_get_current_tabpage() }) }
	]])
	child.settle(300)
	child.lua('require("frogman.domains.storage").routines.write_records()') -- the records waiting, written now
	child.settle(300)
	eq({ got = got, closed = child.lua(EDITOR_FILE).closed }, { got = { true }, closed = 'e,f' })
end

-- The same teardown in a detached list's tab: the files it closes go onto that list, which goes into the whole
-- editor's file with them as its tab goes.
T['T1111 [char] (S2, M5, DESK.md:1205) a tab session\'s load into a detached list\'s tab puts the teardown\'s closes onto that list in the whole editor\'s file'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 'u'), { true })
	local w2 = detached_with_copy(s, false) -- the second tab keeps t_DETACHED, after a whole-editor save
	child.lua('vim.api.nvim_set_current_win(...)', { w2 })
	child.settle()
	child.steps({ ':e e', ':e f' })
	local got = child.lua([[
		vim.cmd('enew')
		vim.cmd('bdelete e.txt')
		vim.cmd('bdelete f.txt')
		return { pcall(require('frogman').load_session, 'u', { tab = vim.api.nvim_get_current_tabpage() }) }
	]])
	child.settle(300)
	eq({ got = got, list = child.lua(EDITOR_FILE).detached.t_DETACHED, in_memory = child.lua(IN_MEMORY, { 't_DETACHED' }) },
		{ got = { true }, list = { closed = 'e,f', windows = 0 }, in_memory = false })
end

-- t reloaded into its own tab, the teardown closing a file opened there since t's save in the same call: the file
-- stays off t's list, as t's file has it, while the trail records its close onto t.
T['T1112 [char] (S2, M5, DESK.md:1205) a tab session reloaded into its own tab leaves the teardown\'s closes off its closed list'] = function()
	local s = S2.shared()
	local _, w2 = tab_session(s) -- t in the second tab, its file with nothing closed
	child.steps({ ':e e', ':e d' }) -- e opened in t's tab since t's save
	local got = child.lua([[
		vim.cmd('enew') -- the teardown keeps the tab: its window on an empty buffer, then e deleted
		vim.cmd('bdelete e.txt')
		return { pcall(require('frogman').load_session, 't', { tab = vim.api.nvim_get_current_tabpage() }) }
	]])
	child.settle(300)
	child.lua('require("frogman.domains.storage").routines.write_records()') -- the records waiting, written now
	child.settle(300)
	local e_known = child.lua([==[
		local H = require('frogman.domains.history')
		for _, handle in pairs(H.handles.live()) do
			if (H.get_filepath_from_hash(handle.hash) or ''):match('/e%.txt$') then return true end
		end
		return false
	]==])
	eq({ got = got, memory = child.lua(LIST_OF, { w2 }), after = child.lua(FILE_CLOSED, { 't' }), trail = child.lua(LOAD_CLOSES),
		e_known = e_known },
		{ got = { true }, memory = 't:', after = {}, trail = { 'e onto t' }, e_known = false })
end

-- A file t's tab visited, closed from the first tab in the same call as u's load into t's tab: a close made in
-- another tab isn't the teardown's, so it goes onto t's list as a visitor's does, and into t's file as t goes.
T['T1113 [char] (S2, M5, DESK.md:1205) a close made in another tab just before a tab session\'s load still goes onto the session left\'s list'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 'u'), { true })
	local w1, w2 = tab_session(s) -- t in the second tab, c in its history
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	child.settle()
	child.steps({ ':e c', ':e t' }) -- the first tab visits c too
	local got = child.lua([[
		local into = vim.api.nvim_win_get_tabpage(...)
		vim.cmd('bdelete c.txt') -- in the first tab
		return { pcall(require('frogman').load_session, 'u', { tab = into }) }
	]], { w2 })
	child.settle(300)
	eq({ got = got, after = child.lua(FILE_CLOSED, { 't' }) }, { got = { true }, after = { 'c' } })
end


-- The guards (DESK.md:1730, :1733): a header the lists drew that's missing at the write refuses it, a pasted
-- copy of one stays and is asked about, and the No Name texts the write would discard are in its one prompt.

-- The write run on one command line with a line of the lists, before the guard can take the change back; the
-- cursor and the flag as the write left them.
local function on_one_line(command)
	return child.lua([[
		vim.cmd(...)
		return { cursor = vim.api.nvim_win_get_cursor(0)[1], modified = vim.bo.modified }
	]], { command })
end

T['T1133 [char] (S2 Closed-stack picker, DESK.md:1730, repro R10) a header deleted and written on one command line refuses the write, the cursor on its first entry'] = function()
	local s = S2.shared()
	two_pools(s)
	local before = child.lua(LISTS_STATE)
	local p = S2.picker(child)
	local t = S2.line_of(p.lines, 'c.txt') - 1
	child.messages()
	local got = on_one_line(t .. 'd|w')
	child.settle()
	eq({ got = got, told = said("frogman: ≡t's header is missing: put it back, or :q! to discard."), lists = child.lua(LISTS_STATE),
		lines = picker_lines() }, { got = { cursor = t, modified = true }, told = 1, lists = before, lines = p.lines })
end

T['T1134 [char] (S2 Closed-stack picker, DESK.md:1730, repro R10) a header deleted and written by a macro refuses the write'] = function()
	local s = S2.shared()
	two_pools(s)
	local before = child.lua(LISTS_STATE)
	local p = S2.picker(child)
	on_t_header(p.lines)
	child.lua('vim.fn.setreg("q", "dd:w\\r")')
	child.messages()
	-- played as typeahead, as a macro runs in a UI (repro R11): typed key by key into the child, TextChanged
	-- would fire between its keys
	child.lua('vim.api.nvim_feedkeys("@q", "tx", false)')
	child.settle()
	eq({ told = said("frogman: ≡t's header is missing: put it back, or :q! to discard."), lists = child.lua(LISTS_STATE),
		modified = child.lua('return vim.bo[...].modified', { p.buf }), lines = picker_lines() },
		{ told = 1, lists = before, modified = false, lines = p.lines }) -- the guard's undo, once the macro ends, takes it back as drawn
end

-- ≡t's header yanked and put under ≡editor's, above x's line: x stays with the list above the copy.
local function copy_over_x(p)
	on_t_header(p.lines)
	keys('yy', 'gg', 'p')
	local lines = vim.deepcopy(p.lines)
	table.insert(lines, 2, lines[S2.line_of(p.lines, 'c.txt') - 1])
	return lines
end

T['T1135 [char] (S2 Closed-stack picker, DESK.md:1730, :1733) a pasted copy of a header is asked about at the write, and Yes leaves it out, the lines under it with the list above'] = function()
	local s = S2.shared()
	two_pools(s)
	local before = child.lua(LISTS_STATE)
	local p = S2.picker(child)
	local pasted = copy_over_x(p)
	local kept = picker_lines()
	child.answer('No')
	child.lua('vim.cmd("write")')
	child.settle()
	local prompt = child.prompts()
	local no = { prompts = #prompt, named = (prompt[1] or ''):find('≡t  (a copy of a header)', 1, true) ~= nil,
		lists = child.lua(LISTS_STATE), modified = child.lua('return vim.bo[...].modified', { p.buf }),
		cursor = child.lua('return vim.api.nvim_win_get_cursor(...)[1]', { p.win }) }
	child.answer('Yes')
	child.lua('vim.cmd("write")')
	child.settle()
	eq({ kept = kept, no = no, yes = { lists = child.lua(LISTS_STATE), modified = child.lua('return vim.bo[...].modified', { p.buf }),
		lines = picker_lines() } },
		{ kept = pasted, no = { prompts = 1, named = true, lists = before, modified = true, cursor = 2 },
			yes = { lists = before, modified = false, lines = p.lines } })
end

T['T1136 [char] (S2 Closed-stack picker, DESK.md:1730, :1738) the header a guard took a change back on is still told from a pasted copy'] = function()
	local s = S2.shared()
	two_pools(s)
	local before = child.lua(LISTS_STATE)
	local p = S2.picker(child)
	on_t_header(p.lines)
	keys('dd') -- taken back by an undo
	on_t_header(p.lines)
	keys('A', 'z', '<Esc>') -- put back as it last stood
	local guarded = picker_lines()
	local pasted = copy_over_x(p)
	child.answer('Yes')
	child.lua('vim.cmd("write")')
	child.settle()
	eq({ guarded = guarded, pasted = #child.prompts(), lists = child.lua(LISTS_STATE) },
		{ guarded = p.lines, pasted = 1, lists = before })
	eq(pasted[2], pasted[S2.line_of(pasted, 'c.txt') - 1])
end

T['T1137 [char] (S2 Closed-stack picker, DESK.md:1733) the No Name texts a write would discard are asked about in its one prompt'] = function()
	child.setup()
	child.steps({ ':e a', ':e b' })
	S2.noname(child, { 'draft' })
	child.steps({ '<M-.>' })
	child.cmd('bdelete b.txt')
	child.settle()
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, S2.line_of(lines, '[No Name]'))
	table.insert(lines, 'typo.txt')
	child.answer('No')
	S2.write_picker(child, p, lines)
	local prompt = child.prompts()
	local closed = child.closed()
	local no = { prompts = #prompt, typo = (prompt[1] or ''):find('typo.txt', 1, true) ~= nil,
		text = (prompt[1] or ''):find('"draft"', 1, true) ~= nil, kept = closed:match('^NONAME_[%d]+,b$') ~= nil }
	child.answer('Yes')
	child.lua('vim.api.nvim_buf_call(..., function() vim.cmd("write") end)', { p.buf })
	child.settle()
	eq({ no = no, yes = { prompts = #child.prompts(), closed = child.closed() } },
		{ no = { prompts = 1, typo = true, text = true, kept = true }, yes = { prompts = 1, closed = 'b' } })
end

T['T1142 [char] (S2 Closed-stack picker, DESK.md:1730) <CR> under a pasted copy of another list\'s header reopens from the list the line is under'] = function()
	local s = S2.shared()
	local w1 = file_only_state(s)
	child.lua('vim.api.nvim_set_current_win(...)', { w1 })
	local p = S2.picker(child)
	local header = under_detached(p.lines)
	-- ≡editor's header yanked and put under ≡t_DETACHED's, above e's line
	child.lua('vim.api.nvim_set_current_win(...)', { p.win })
	child.lua('vim.api.nvim_win_set_cursor(0, { 1, 0 })')
	keys('yy')
	child.lua('vim.api.nvim_win_set_cursor(0, { ..., 0 })', { header })
	keys('p')
	-- e's line under ≡t_DETACHED's header, below the copy now, which a section read by text takes for ≡editor
	local e
	for i, l in ipairs(picker_lines()) do
		if i > header and not e and l:find('e.txt', 1, true) then e = i end
	end
	child.answer('Yes')
	child.lua('vim.api.nvim_win_set_cursor(0, { ..., 0 })', { e })
	type_into(p.win, '<CR>')
	child.settle(300)
	eq({ in_file = child.lua(EDITOR_FILE).detached.t_DETACHED, reopened = child.shown(w1) }, { in_file = nil, reopened = 'e' })
end

T['T1143 [char] (S2 Closed-stack picker, DESK.md:1730) a header deleted with a copy of it below is taken back'] = function()
	local s = S2.shared()
	two_pools(s)
	local before = child.lua(LISTS_STATE)
	local p = S2.picker(child)
	on_t_header(p.lines)
	keys('yy', 'G', 'p') -- ≡t's copy below c's line
	local copied = picker_lines()
	on_t_header(p.lines) -- the header ≡t was drawn on
	keys('dd')
	local after = picker_lines()
	child.answer('Yes')
	child.lua('vim.cmd("write")')
	child.settle()
	local lines = vim.deepcopy(p.lines)
	table.insert(lines, lines[S2.line_of(p.lines, 'c.txt') - 1])
	eq({ copied = copied, after = after, lists = child.lua(LISTS_STATE) }, { copied = lines, after = lines, lists = before })
end

T['T1144 [char] (S2 Closed-stack picker, DESK.md:1730) after every line is written over, the headers are told from a copy pasted later'] = function()
	local s = S2.shared()
	two_pools(s)
	local before = child.lua(LISTS_STATE)
	local p = S2.picker(child)
	child.lua('local buf, lines = ...; vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)', { p.buf, p.lines })
	child.settle() -- the guard takes the rewrite in
	copy_over_x(p)
	child.answer('Yes')
	child.lua('vim.cmd("write")')
	child.settle()
	eq({ prompts = #child.prompts(), lists = child.lua(LISTS_STATE) }, { prompts = 1, lists = before })
end

T['T1145 [char] (S2 Closed-stack picker, DESK.md:1730) the refusal puts the cursor on the list\'s own first entry, a file on two lists'] = function()
	local s = S2.shared()
	x_on_both(s)
	local p = S2.picker(child)
	local t = S2.line_of(p.lines, '≡t')
	local got = on_one_line(t .. 'd|w')
	child.settle()
	eq({ first = p.lines[t + 1], cursor = got.cursor }, { first = 'x.txt', cursor = t })
end

T['T1147 [char] (S2 Closed-stack picker, DESK.md:1730) keys typed ahead with the lists\' open key meet the headers it drew: a header deleted past its copy refuses'] = function()
	local s = S2.shared()
	two_pools(s)
	local before = child.lua(LISTS_STATE)
	child.messages()
	-- in one batch: the lists opened, ≡t's header (line 3) yanked and put below c's line, the header deleted, the write
	child.lua('vim.api.nvim_feedkeys(vim.keycode("<M-;>W3Gyy4Gp3Gdd:w<CR>"), "tx", false)')
	child.settle()
	eq({ told = said("frogman: ≡t's header is missing: put it back, or :q! to discard."), lists = child.lua(LISTS_STATE) },
		{ told = 1, lists = before })
end

T['T1149 [char] (S2 Closed-stack picker, DESK.md:1738) an edit typed ahead with a header change the guard undoes stays through a later put-back'] = function()
	local s = S2.shared()
	two_pools(s)
	local p = S2.picker(child)
	-- in one batch: x's line deleted, then the header that comes up to its row: the guard's undo takes back the header's
	child.lua('vim.api.nvim_feedkeys("2Gdd2Gdd", "tx", false)')
	child.settle()
	local undone = picker_lines()
	child.lua('vim.api.nvim_win_set_cursor(0, { 2, 0 })')
	keys('A', 'z', '<Esc>') -- on ≡t's header, put back as it last stood
	eq({ undone = undone, put_back = picker_lines() }, { undone = { '≡editor', '≡t', 'c.txt' }, put_back = { '≡editor', '≡t', 'c.txt' } })
end

T['T1150 [char] (S2 Closed-stack picker, DESK.md:1730, :1738) a line opened above a header is kept'] = function()
	local s = S2.shared()
	two_pools(s)
	local p = S2.picker(child)
	on_t_header(p.lines)
	keys('O', 'b', '.', 't', 'x', 't', '<Esc>')
	local lines = vim.deepcopy(p.lines)
	table.insert(lines, S2.line_of(p.lines, 'c.txt') - 1, 'b.txt')
	eq(picker_lines(), lines)
end

T['T1151 [char] (S2 Closed-stack picker, DESK.md:1730, :1733) a header\'s copy put above it is the copy the write asks about'] = function()
	local s = S2.shared()
	two_pools(s)
	local p = S2.picker(child)
	local t = S2.line_of(p.lines, 'c.txt') - 1
	on_t_header(p.lines)
	keys('yy', 'P')
	child.answer('No')
	child.lua('vim.cmd("write")')
	child.settle()
	eq({ prompts = #child.prompts(), cursor = child.lua('return vim.api.nvim_win_get_cursor(0)[1]') }, { prompts = 1, cursor = t })
end

T['T1194 [char] (M5, S1, DESK.md:2391, :2392) the lists a file came off when it was opened again are saved with the session'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.cmd('bdelete a.txt')
	child.settle()
	child.steps({ ':e a' })
	local before = child.lua([[
		local H = require('frogman.domains.history')
		return vim.tbl_keys(H.data.came_from[H.get_handle_from_filepath(_G.FRG_TEST.root .. '/a.txt')] or {})
	]])
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'a')
	eq(S2.load(child), { true })
	child.settle(300)
	eq({ before = before, after = child.lua([[
		local H = require('frogman.domains.history')
		return vim.tbl_keys(H.data.came_from[H.get_handle_from_filepath(_G.FRG_TEST.root .. '/a.txt')] or {})
	]]) }, { before = { '' }, after = { '' } })
end

T['T1196 [char] (S2, DESK.md:2391, :2392) after Neovim\'s :restart session, frogman runs every load of the startup again, each tab session into its own tab'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })
	child.cmd('tabnew')
	child.steps({ ':e c', ':e d' })
	eq(child.lua('return { pcall(require("frogman").save_session, "u", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, 'p')
	local session = dir .. '/restart_session_T1196xy'
	child.cmd('mksession! ' .. vim.fn.fnameescape(session))

	S2.start_restarted(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.lua('pcall(require("frogman").load_session, vim.fn.getcwd())')
	child.cmd('noautocmd tabnew')
	child.cmd('noautocmd edit d.txt')
	child.lua([[
		pcall(require('frogman').load_session, 'u', { tab = vim.api.nvim_get_current_tabpage() })
		vim.cmd('source ' .. vim.fn.fnameescape(...))
	]], { session })
	child.settle(300)
	local tabs = child.lua('return vim.api.nvim_list_tabpages()')
	local second = child.lua('return vim.api.nvim_tabpage_get_win(...)', { tabs[2] })
	eq({ loads = S2.loads(child), tabs = #tabs, slots = child.slots(second) }, { loads = 4, tabs = 2, slots = '⦉c⦊ [d] ⟦-⟧' })
end

T['T1200 [char] (S2, DESK.md:2391, :2392) after Neovim\'s :restart session, a whole-editor load the startup made before another isn\'t run again'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(S2.save(child, 'one'), { true })
	child.steps({ ':e c', ':e d' })
	eq(S2.save(child, 'two'), { true })
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, 'p')
	local session = dir .. '/restart_session_T1200xy'
	child.cmd('mksession! ' .. vim.fn.fnameescape(session))

	S2.start_restarted(child, s)
	Misc.restore(child, { 'a', 'b', 'c', 'd' }, 'd')
	child.lua([[
		pcall(require('frogman').load_session, 'one')
		pcall(require('frogman').load_session, 'two')
		vim.cmd('source ' .. vim.fn.fnameescape(...))
	]], { session })
	child.settle(300)
	eq({ loads = S2.loads(child), session = child.lua('local s = require("frogman.domains.storage").data.editor_session; return s and s.name') },
		{ loads = 3, session = 'two' })
end

return T
