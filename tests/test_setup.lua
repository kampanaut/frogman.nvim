-- Setup (A25): setup() and what runs at require. IDs are the spec's
-- (what-is-cavediver.md, section 7). These start a child with cavediver on the
-- runtimepath but not required, in an empty temporary directory.
local Helpers = dofile('tests/helpers.lua')
local eq = Helpers.eq
local child = MiniTest.new_child_neovim()

local function bare()
	child.restart({ '-u', 'scripts/minimal_init.lua' })
	child.lua([[
		package.preload['harpoon'] = function()
			return { list = function() return { display = function() return {} end } end }
		end
		local root = vim.fn.tempname()
		vim.fn.mkdir(root, 'p')
		vim.cmd('cd ' .. vim.fn.fnameescape(root))
		_G.CDV_ROOT = root
		_G.CDV_NOTES = {}
		vim.notify = function(msg, level) table.insert(_G.CDV_NOTES, { msg = tostring(msg), level = level }) end
	]])
end

-- Autocmds, and running timers that repeat (the UI refresh and the cleanup).
local function counts()
	return child.lua([[
		local timers = 0
		vim.uv.walk(function(h)
			if h:get_type() == 'timer' and h:is_active() and h:get_repeat() > 0 then timers = timers + 1 end
		end)
		return { autocmds = #vim.api.nvim_get_autocmds({}), timers = timers }
	]])
end

local T = MiniTest.new_set({
	hooks = {
		pre_case = bare,
		post_once = child.stop,
	},
})

T['T125 [char] setup() with no argument works and uses the defaults'] = function()
	local got = child.lua([[
		local ok, err = pcall(require('frogman').setup)
		local cfg = require('frogman.configs')
		return {
			ok = ok,
			err = err and tostring(err) or nil,
			key = vim.fn.maparg('<M-f>', 'n') ~= '',
			history_view = cfg.bufferline.history_view,
			cleanup_interval = cfg.cleanup_interval,
			session_dir = cfg.session_dir == vim.fn.stdpath('data') .. '/cavediver/sessions/',
		}
	]])
	eq(got, { ok = true, key = true, history_view = 'global', cleanup_interval = 4000, session_dir = true })
end

-- :colorscheme runs :hi clear, which removes every group the theme doesn't define.
T['T557 [char] the highlights outlive a theme change'] = function()
	local got = child.lua([[
		require('frogman').setup()
		vim.cmd.colorscheme('default')
		local cfg = require('frogman.configs')
		local function fg(name) return vim.api.nvim_get_hl(0, { name = name }).fg end
		return {
			base = fg('WinbarBase') == tonumber(cfg.colors.base.focused.fg:sub(2), 16),
			list = fg('CavediverTrailList') == tonumber(cfg.colors.trail.list:sub(2), 16),
		}
	]])
	eq(got, { base = true, list = true })
end

-- A ColorScheme autocmd made before setup() styles one of cavediver's groups, so it runs before cavediver's.
T['T627 [char] (A25) a group a colorscheme autocmd defines stays its own'] = function()
	local got = child.lua([[
		vim.api.nvim_create_autocmd('ColorScheme', { callback = function()
			vim.api.nvim_set_hl(0, 'CavediverTrailList', { fg = '#123456' })
		end })
		require('frogman').setup()
		vim.cmd.colorscheme('default')
		local cfg = require('frogman.configs')
		local function fg(name) return vim.api.nvim_get_hl(0, { name = name }).fg end
		return { own = fg('CavediverTrailList') == 0x123456, base = fg('WinbarBase') == tonumber(cfg.colors.base.focused.fg:sub(2), 16) }
	]])
	eq(got, { own = true, base = true })
end

T['T126 [char] require("frogman") without setup() creates no autocmds'] = function()
	local got = child.lua([[
		local before = #vim.api.nvim_get_autocmds({})
		require('frogman')
		return #vim.api.nvim_get_autocmds({}) - before
	]])
	eq(got, 0)
end

T['T127 [char] calling setup() twice leaves one set of autocmds and timers'] = function()
	local opts = 'local s = { session_dir = _G.CDV_ROOT .. "/sessions/" }; '
	child.lua(opts .. 'require("frogman").setup(s)')
	child.lua('vim.wait(300)')
	local once = counts()
	child.lua(opts .. 'require("frogman").setup(s)')
	child.lua('vim.wait(300)')
	eq(counts(), once)
end

-- What a key maps to: its description, or nil when it maps nothing.
local function maps(lhs)
	return child.lua('local m = vim.fn.maparg(..., "n", false, true); return m.desc or vim.NIL', { lhs })
end

T['T520 [char] (M13, A25) setup() again starts from the defaults'] = function()
	child.lua([[require('frogman').setup({ session_dir = _G.CDV_ROOT .. '/sessions/' })]])
	local first = { close = maps('<M-.>') }
	child.lua([[require('frogman').setup({ cleanup_interval = 123, keymaps = { close_buffer = '<M-q>' } })]])
	local moved = { q = maps('<M-q>'), close = maps('<M-.>'), interval = child.lua('return require("frogman.configs").cleanup_interval') }
	child.lua([[require('frogman').setup()]])
	local again = { q = maps('<M-q>'), close = maps('<M-.>'), interval = child.lua('return require("frogman.configs").cleanup_interval') }
	eq({ first = first, moved = moved, again = again }, {
		first = { close = 'Close the current buffer' },
		moved = { q = 'Close the current buffer', close = vim.NIL, interval = 123 },
		again = { q = vim.NIL, close = 'Close the current buffer', interval = 4000 },
	})
end

T['T521 [char] (M13) a bracket pair named at the top of glyphs is taken'] = function()
	local got = child.lua([[
		local ok, err = pcall(require('frogman').setup, { session_dir = _G.CDV_ROOT .. '/sessions/', glyphs = { row_t = { '<', '>' } } })
		return { ok = ok, err = err and tostring(err) or vim.NIL, row_t = ok and require('frogman.domains.ui.routines').glyphs().row_t or vim.NIL }
	]])
	eq(got, { ok = true, err = vim.NIL, row_t = { '<', '>' } })
end

-- ffi made unavailable before cavediver is required, as a Neovim built without
-- LuaJIT has it.
T['T593 [char] (S2) a Neovim without LuaJIT\'s FFI loads cavediver'] = function()
	local got = child.lua([[
		package.loaded.ffi = nil
		package.preload.ffi = function() error("module 'ffi' not found") end
		local ok, err = pcall(require('frogman').setup, { session_dir = _G.CDV_ROOT .. '/sessions/' })
		vim.fn.writefile({ 'a' }, _G.CDV_ROOT .. '/a.txt')
		vim.cmd('edit ' .. vim.fn.fnameescape(_G.CDV_ROOT .. '/a.txt'))
		vim.wait(50)
		local saved, why = pcall(require('frogman').save_session)
		return { setup = ok, err = err and tostring(err) or vim.NIL, saved = saved, luajit = tostring(why):find('LuaJIT', 1, true) ~= nil }
	]])
	eq(got, { setup = true, err = vim.NIL, saved = false, luajit = true })
end

-- Another plugin's declaration of RAND_bytes, with a parameter fewer, made first.
T['T596 [char] (S2) another plugin\'s different declaration of a libcrypto function doesn\'t stand in for cavediver\'s'] = function()
	local got = child.lua([[
		require('ffi').cdef('int RAND_bytes(unsigned char *buf);')
		require('frogman').setup({ session_dir = _G.CDV_ROOT .. '/sessions/' })
		vim.fn.writefile({ 'a' }, _G.CDV_ROOT .. '/a.txt')
		vim.cmd('edit ' .. vim.fn.fnameescape(_G.CDV_ROOT .. '/a.txt'))
		vim.wait(50)
		local ok, err = pcall(require('frogman').save_session)
		return { ok = ok, err = err and tostring(err) or vim.NIL }
	]])
	eq(got, { ok = true, err = vim.NIL })
end

-- Run from the test runner itself, not a child: an nvim started on the test init
-- with a clean environment, its XDG folders fresh and empty.
T['T591 [char] the test init refuses a run outside its sandbox'] = function()
	local function run(sandboxed)
		local root = vim.fn.tempname()
		local env = { PATH = vim.env.PATH, HOME = vim.env.HOME }
		for _, x in ipairs({ 'CONFIG', 'DATA', 'STATE', 'CACHE' }) do
			env['XDG_' .. x .. '_HOME'] = root .. '/' .. x:lower()
		end
		if sandboxed then
			env.CDV_TEST_SANDBOX = root
			env.XDG_DATA_HOME = vim.fn.tempname() -- one folder outside it
		end
		local r = vim.system({ vim.v.progpath, '--headless', '-u', 'scripts/minimal_init.lua', '-c', 'qa!' },
			{ env = env, clear_env = true, text = true }):wait(10000)
		local found = vim.fn.globpath(root, '**', true, true)
		if sandboxed then vim.list_extend(found, vim.fn.globpath(env.XDG_DATA_HOME, '**', true, true)) end
		-- files only, and not Neovim's own log, which it starts before any init runs
		local written = vim.tbl_filter(function(f)
			return vim.fn.isdirectory(f) == 0 and not f:match('/nvim/nvim%.log$')
		end, found)
		return { code = r.code, said = ((r.stdout or '') .. (r.stderr or '')):find('make test', 1, true) ~= nil, written = #written }
	end
	eq({ none = run(false), outside = run(true) },
		{ none = { code = 2, said = true, written = 0 }, outside = { code = 2, said = true, written = 0 } })
end

return T
