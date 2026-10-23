-- Sessions (S1, S2). IDs are the spec's (what-is-cavediver.md, section 7).
--
-- A load can follow nothing else in one process, so a round trip saves in one
-- child and loads in a fresh one. Both start in a project the test runner
-- makes, with the same cwd (the session file is named after the directory
-- and the session's name), and with a session directory the test runner
-- makes, handed to setup() (Misc.start). The second child brings the buffers
-- back the way a session manager does (Misc.restore) before loading.
-- save_session and load_session get the cwd as the session's name, as the
-- README wires them.
local Helpers = dofile('tests/helpers.lua')
local Misc = dofile('tests/helpers_misc.lua')
local eq = Helpers.eq
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		post_once = child.stop,
	},
})

-- A project and a session directory that outlive the children.
local function shared()
	return { root = Misc.make_project(), session_dir = Misc.make_session_dir() }
end

-- A fresh child in the shared project (or in `root`, another project), with
-- the shared session directory.
local function start(s, root)
	Misc.start(child, { root = root or s.root, session_dir = s.session_dir })
end

-- The window entry's slots are hashes, and the paths behind them are in the
-- paths table, not in clear.
T['T134 [char] save_session writes paths, outsiders, buffers, windows, closed, noname_content; windows[i] = [c, s, p[], t, dtm, dsm, shows, on, history]'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	eq(Misc.save(child), { true })
	local got = child.lua([[
		local H = require('cavediver.domains.history')
		local f = vim.fn.glob(require('cavediver.configs').session_dir .. '*.json', true, true)
		local data = vim.json.decode(table.concat(vim.fn.readfile(f[1]), '\n'))
		local keys = vim.tbl_keys(data)
		table.sort(keys)
		local w = data.windows[1]
		local function path(file) return _G.CDV_TEST.root .. '/' .. file end
		local function hash(file) return H.get_hash_from_buffer(vim.fn.bufnr(path(file))) end
		return {
			keys = keys,
			windows = #data.windows,
			fields = #w,
			c = w[1] == hash('d.txt'),
			s = w[2] == hash('b.txt'),
			p = type(w[3]),
			t = w[4] == hash('c.txt'),
			dtm = type(w[5]),
			dsm = type(w[6]),
			shows = w[7] == hash('d.txt'),
			on = w[8],
			history = type(w[9]),
			path = type(data.paths[hash('d.txt')]) == 'string' and data.paths[hash('d.txt')] ~= path('d.txt'),
		}
	]])
	eq(got, {
		keys = { 'buffers', 'closed', 'noname_content', 'outsiders', 'paths', 'windows' },
		windows = 1, fields = 9,
		c = true, s = true, p = 'table', t = true, dtm = 'table', dsm = 'table',
		shows = true, on = false, history = 'table', path = true,
	})
end

T['T135 [char] a round trip with every slot buffer restored and loaded gives back the slots and maps'] = function()
	local s = shared()
	start(s)
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d', ':e e' })
	local slots, notes = child.slots(), child.notes()
	eq(slots, '⦉d⦊ [e] ⟦b⟧')
	eq(notes, 'dtm{b>a d>c} dsm{b>a}')
	eq(Misc.save(child), { true })

	start(s)
	Misc.restore(child, { 'a', 'b', 'c', 'd', 'e' }, 'e')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.slots(), slots)
	eq(child.notes(), notes)
end

T['T136 [char] primary_enabled = false survives a round trip'] = function()
	local s = shared()
	start(s)
	child.steps({ ':e a', ':e b', '<M-;><M-c>', '<M-;><M-x>' })
	eq(child.primary(), '[b]off')
	eq(Misc.save(child), { true })

	start(s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.primary(), '[b]off')
end

T['T137 [char] load_session after save_session in the same process goes through and ends idle'] = function()
	child.setup()
	child.steps({ ':e a' })
	eq(Misc.save(child), { true })
	eq(Misc.load(child), { true })
	eq(child.lua('return require("cavediver.domains.storage").sm:state()'), 'idle')
end

-- After the save the window moves on to d; the manager's restore puts it back
-- on c (noautocmd edit) before the load.
T['T138 [char] load_session from idle tears down and loads'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	eq(Misc.save(child), { true })
	child.steps({ ':e d' })
	child.cmd('noautocmd edit c.txt')
	local got = Misc.load(child)
	child.settle(300)
	eq({ got[1], child.lua('return require("cavediver").get_storage_state()'), child.slots() },
		{ true, 'idle', '⦉b⦊ [c] ⟦-⟧' })
end

T['T139 [char] a slot whose buffer comes back unloaded keeps its value after load'] = function()
	local s = shared()
	start(s)
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	eq(Misc.save(child), { true })

	start(s)
	Misc.restore(child, { 'd' }, 'd', { 'a', 'b', 'c' })
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
end

T['T140 [char] a save with a No Name current slot succeeds and the load reopens it, hidden and modified'] = function()
	local s = shared()
	start(s)
	child.steps({ ':e a', ':enew' })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "scratch text" })')
	child.messages()
	eq(Misc.save(child), { true })
	eq(Misc.errors(child), {})

	start(s)
	Misc.restore(child, { 'a' }, 'a')
	eq(Misc.load(child), { true })
	child.settle(300)
	local got = child.lua([[
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
			if #lines == 1 and lines[1] == 'scratch text' then
				return { found = true, modified = vim.bo[b].modified, hidden = #vim.fn.win_findbuf(b) == 0 }
			end
		end
		return { found = false }
	]])
	eq(got, { found = true, modified = true, hidden = true })
end

T['T141 [char] a save with a :vsplit window that has no visits succeeds'] = function()
	child.setup()
	child.steps({ ':e a', ':vsplit' })
	child.messages()
	eq(Misc.save(child), { true })
	eq(Misc.errors(child), {})
end

-- The first window has ⦉a⦊ [b]; the split (listed first) visits c, then a No
-- Name buffer. A session manager brings back only the window showing b.
T['T142 [char] two windows, one on a No Name buffer: after save and load each window gets its own entry'] = function()
	local s = shared()
	start(s)
	child.steps({ ':e a', ':e b', ':vsplit', ':e c', ':enew' })
	eq(child.slots(), '⦉c⦊ [NONAME_' .. child.lua('return vim.b.cavediver_noname') .. '] ⟦-⟧')
	child.cmd('wincmd p')
	child.settle()
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	eq(Misc.save(child), { true })

	start(s)
	Misc.restore(child, { 'a', 'b', 'c' }, 'b')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
end

-- The session directory is made read-only before the child starts.
T['T143 [char] a save into a read-only directory throws to the caller'] = function()
	local s = shared()
	vim.fn.setfperm(s.session_dir, 'r-xr-xr-x')
	start(s)
	child.steps({ ':e a' })
	local got = Misc.save(child)
	vim.fn.setfperm(s.session_dir, 'rwxr-xr-x')
	eq(got[1], false)
end

-- One byte in the middle of the saved file (the one regular file in the
-- session directory) is flipped.
T['T144 [target] a file that fails the integrity check gives the notification and a fresh start'] = function()
	local s = shared()
	start(s)
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })
	local saved = Misc.files_in(s.session_dir)
	eq(#saved, 1)
	local file = s.session_dir .. saved[1]
	local fh = io.open(file, 'rb')
	local bytes = fh:read('*a')
	fh:close()
	local mid = math.floor(#bytes / 2)
	fh = io.open(file, 'wb')
	fh:write(bytes:sub(1, mid - 1) .. string.char(bit.bxor(bytes:byte(mid), 1)) .. bytes:sub(mid + 1))
	fh:close()

	start(s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	child.messages()
	eq(Misc.load(child), { true })
	child.settle(300)
	local told = false
	for _, m in ipairs(child.messages()) do
		if m.msg:find('integrity check', 1, true) then told = true end
	end
	eq({ told, child.slots(), child.closed() }, { true, '⦉-⦊ [b] ⟦-⟧', '' })
end

T['T145 [char] three load_session calls in one batch load once'] = function()
	local s = shared()
	start(s)
	child.steps({ ':e a', ':e b' })
	eq(Misc.save(child), { true })

	start(s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	local got = child.lua([[
		local cwd = vim.fn.getcwd()
		local load = require('cavediver').load_session
		local oks = {}
		for i = 1, 3 do oks[i] = pcall(load, cwd) end
		local loads = 0
		for _, t in ipairs(require('cavediver.domains.storage').sm.history) do
			if t:match('%->loading$') then loads = loads + 1 end
		end
		return { oks = oks, loads = loads }
	]])
	eq(got, { oks = { true, true, true }, loads = 1 })
end

-- Every window's buffer, and every loaded buffer.
local function snapshot()
	return child.lua([[
		local wins, bufs = {}, {}
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			wins[tostring(w)] = vim.api.nvim_win_get_buf(w)
		end
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(b) then table.insert(bufs, b) end
		end
		return { wins = wins, bufs = bufs }
	]])
end

-- The window shows b, whose file is deleted on disk just before the save.
T['T146 [char] a save never wipes a buffer or changes what a window shows'] = function()
	child.setup()
	child.steps({ ':e a', ':vsplit', ':e b' })
	local before = snapshot()
	local got = child.lua([[
		os.remove(_G.CDV_TEST.root .. '/b.txt')
		return { pcall(require('cavediver').save_session, vim.fn.getcwd()) }
	]])
	eq(got, { true })
	child.settle(300)
	eq(snapshot(), before)
end

-- The split visits c, then shows an oil-like buffer (acwrite, oil://) and keeps
-- its triquetra.
T['T146 [target] a save leaves an oil window on its oil buffer'] = function()
	child.setup()
	child.steps({ ':e a', ':e b', ':vsplit', ':e c' })
	child.lua([[
		local b = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(b, 'oil://' .. _G.CDV_TEST.root .. '/')
		vim.bo[b].buftype = 'acwrite'
		vim.bo[b].filetype = 'oil'
		vim.api.nvim_win_set_buf(0, b)
	]])
	child.settle()
	eq(child.lua('return require("cavediver.domains.window").data.crux[vim.api.nvim_get_current_win()] ~= nil'), true)
	local before = snapshot()
	eq(Misc.save(child), { true })
	child.settle(300)
	eq(snapshot(), before)
end

T['T147 [char] with no file, a load gives every window {c=<shown>} and an empty closed stack'] = function()
	child.setup()
	child.cmd('noautocmd edit a.txt')
	child.cmd('noautocmd vsplit')
	child.cmd('noautocmd edit b.txt')
	eq(Misc.session_files(child), {})
	eq(Misc.load(child), { true })
	child.settle(300)
	local got = {}
	for _, w in ipairs(child.lua('return vim.api.nvim_list_wins()')) do
		table.insert(got, child.slots(w))
	end
	table.sort(got)
	eq(got, { '⦉-⦊ [a] ⟦-⟧', '⦉-⦊ [b] ⟦-⟧' })
	eq(child.closed(), '')
end

-- Project one has a No Name buffer with text, closed with <M-.> (its text is
-- kept for reopening). Then the editor switches to project two: save, cd, the
-- manager's restore, load, and later a save there. Both share one session
-- directory. A fresh child loads project two's file and looks for the text.
T['T148 [char] after switching sessions, the outgoing No Name text is not in the incoming file'] = function()
	local s = shared()
	local two = Misc.make_project()
	start(s)
	child.steps({ ':e a', ':enew' })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "outgoing text" })')
	child.steps({ '<M-.>' })
	eq(child.shown(), 'a')
	eq(Misc.save(child), { true })
	child.cmd('cd ' .. vim.fn.fnameescape(two))
	child.cmd('noautocmd edit ' .. vim.fn.fnameescape(two .. '/a.txt'))
	Misc.load(child)
	child.settle(300)
	eq(Misc.save(child), { true })

	start(s, two)
	Misc.restore(child, { 'a' }, 'a')
	eq(Misc.load(child), { true })
	child.settle(300)
	local found = child.lua([[
		local function has(lines) return vim.tbl_contains(lines, 'outgoing text') end
		for _, c in pairs(require('cavediver.domains.history').data.noname_content) do
			if has(c.lines) then return true end
		end
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if has(vim.api.nvim_buf_get_lines(b, 0, -1, false)) then return true end
		end
		return false
	]])
	eq(found, false)
end

return T
