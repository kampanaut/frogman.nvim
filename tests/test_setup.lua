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
		local ok, err = pcall(require('cavediver').setup)
		local cfg = require('cavediver.configs')
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

T['T126 [char] require("cavediver") without setup() creates no autocmds'] = function()
	local got = child.lua([[
		local before = #vim.api.nvim_get_autocmds({})
		require('cavediver')
		return #vim.api.nvim_get_autocmds({}) - before
	]])
	eq(got, 0)
end

T['T127 [char] calling setup() twice leaves one set of autocmds and timers'] = function()
	local opts = 'local s = { session_dir = _G.CDV_ROOT .. "/sessions/" }; '
	child.lua(opts .. 'require("cavediver").setup(s)')
	child.lua('vim.wait(300)')
	local once = counts()
	child.lua(opts .. 'require("cavediver").setup(s)')
	child.lua('vim.wait(300)')
	eq(counts(), once)
end

return T
