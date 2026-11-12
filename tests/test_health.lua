-- The health check (M17), :checkhealth frogman. IDs are the spec's (what-is-frogman.md, section 7).
-- Every case but the first reads the report through vim.health's own calls, collected in the child,
-- each line as its section, its level and its words.
local Helpers = dofile('tests/helpers.lua')
local eq = Helpers.eq
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = child.stop,
	},
})

-- The report, as { section, level, msg, advice } rows, from a fresh copy of the health module and of
-- crypto (so a case can change what crypto finds without the rest of the child seeing it), run after
-- `before`, a chunk of Lua run in the child first.
local function report(before)
	return child.lua([[
		local before = ...
		if type(before) == 'string' then assert(loadstring(before))() end
		local got, section = {}, nil
		local h = vim.health
		local saved = { start = h.start, ok = h.ok, warn = h.warn, error = h.error, info = h.info }
		h.start = function(name) section = name end
		for _, level in ipairs({ 'ok', 'warn', 'error', 'info' }) do
			h[level] = function(msg, advice)
				table.insert(got, { section = section, level = level, msg = msg, advice = advice and table.concat(advice, ' ') or '' })
			end
		end
		package.loaded['frogman.health'] = nil
		local ok, err = pcall(require('frogman.health').check)
		for k, v in pairs(saved) do h[k] = v end
		if not ok then error(err) end
		return got
	]], { before or vim.NIL })
end

-- The rows of one section.
local function section(rows, name)
	return vim.tbl_filter(function(r) return r.section == name end, rows)
end

-- Each row of a section as "level: msg".
local function lines(rows, name)
	return vim.tbl_map(function(r) return r.level .. ': ' .. r.msg end, section(rows, name))
end

-- A fresh crypto, as a new editor has before its first save.
local FRESH_CRYPTO = [[package.loaded['frogman.domains.storage.crypto'] = nil]]

T['T1294 [char] (M17; the user, 2026-11-12: "go", "All seven (Recommended)") :checkhealth frogman finds the check and reports each part, in order'] = function()
	local got = child.lua([[
		vim.cmd('checkhealth frogman')
		local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
		local order = {}
		for _, heading in ipairs({ 'Neovim ~', 'Encryption ~', 'Folders ~', 'Setup ~', 'Plugins frogman uses ~', 'Keys ~' }) do
			table.insert(order, (text:find(heading, 1, true)))
		end
		local sorted = vim.deepcopy(order)
		table.sort(sorted)
		return {
			found = not vim.tbl_contains(order, vim.NIL) and #order == 6,
			in_order = vim.deep_equal(order, sorted),
			loaded = text:find('libcrypto loaded', 1, true) ~= nil,
			round_trip = text:find('encrypted and decrypted again', 1, true) ~= nil,
			failed = text:find('the check failed', 1, true) ~= nil,
		}
	]])
	eq(got, { found = true, in_order = true, loaded = true, round_trip = true, failed = false })
end

T['T1295 [char] (M17; the user, 2026-11-12: "All seven (Recommended)") Neovim older than 0.12 is an error'] = function()
	local rows = report([[
		local has = vim.fn.has
		vim.fn.has = function(what) if what == 'nvim-0.12' then return 0 end return has(what) end
	]])
	local neovim = section(rows, 'Neovim')
	eq({ #neovim, neovim[1].level, neovim[1].msg:find('needs 0.12 or newer', 1, true) ~= nil },
		{ 1, 'error', true })
end

T['T1296 [char] (M17; the user, 2026-11-12: "All seven (Recommended)") no LuaJIT FFI is an error, and nothing else is tried'] = function()
	local rows = report(FRESH_CRYPTO .. [[
		package.loaded.ffi = nil
		package.preload.ffi = function() error("module 'ffi' not found") end
	]])
	eq(lines(rows, 'Encryption'), { "error: this Neovim has no LuaJIT FFI, which encrypts the session files" })
end

T['T1297 [char] (M17; the user, 2026-11-12: "All seven (Recommended)") libcrypto not found is an error naming what the save\'s own search tried'] = function()
	local rows = report(FRESH_CRYPTO .. [[
		_G.FRG_TRIED = {}
		require('ffi').load = function(name)
			table.insert(_G.FRG_TRIED, tostring(name))
			error('simulated: ' .. tostring(name) .. ' not found')
		end
	]])
	local encryption = section(rows, 'Encryption')
	local tried = child.lua('return _G.FRG_TRIED')
	local last = encryption[#encryption]
	local named = #tried > 0
	for _, name in ipairs(tried) do
		if not last.msg:find(name, 1, true) then named = false end
	end
	eq({ levels = vim.tbl_map(function(r) return r.level end, encryption), named = named,
		prefix = last.msg:find('frogman: ', 1, true) ~= nil, option = last.msg:find('libcrypto_path', 1, true) ~= nil },
		{ levels = { 'ok', 'error' }, named = true, prefix = false, option = true })
end

T['T1298 [char] (M17; the user, 2026-11-12: "All seven (Recommended)") a libcrypto_path that doesn\'t load is a warning when frogman\'s own list finds one'] = function()
	local rows = report(FRESH_CRYPTO .. [[
		_G.FRG_TEST.setup({ libcrypto_path = _G.FRG_TEST.root .. '/nowhere/libcrypto.so.3' })
	]])
	local encryption = section(rows, 'Encryption')
	eq({ levels = vim.tbl_map(function(r) return r.level end, encryption),
		names = encryption[2].msg:find('/nowhere/libcrypto.so.3', 1, true) ~= nil },
		{ levels = { 'ok', 'warn', 'ok', 'ok' }, names = true })
end

T['T1299 [char] (M17; the user, 2026-11-12: "All seven (Recommended)") a test text that doesn\'t come back through AES-256-GCM is an error'] = function()
	local rows = report([[
		require('frogman.domains.storage.crypto').open = function() return nil end
	]])
	local encryption = section(rows, 'Encryption')
	eq({ encryption[#encryption].level, encryption[#encryption].msg }, { 'error', "a test text didn't come back through AES-256-GCM" })
end

T['T1300 [char] (M17; the user, 2026-11-12: "All seven (Recommended)") a session folder not made yet is fine when its parent is writable, and the check makes nothing'] = function()
	local rows = report()
	local folders = section(rows, 'Folders')
	local made = child.lua('return vim.uv.fs_stat(require("frogman.configs").session_dir) ~= nil')
	eq({ levels = vim.tbl_map(function(r) return r.level end, folders),
		sessions = folders[1].msg:find('made at the first write', 1, true) ~= nil, made = made },
		{ levels = { 'ok', 'ok' }, sessions = true, made = false })
end

T['T1301 [char] (M17; the user, 2026-11-12: "All seven (Recommended)") a session folder that\'s a file, or can\'t be written, is an error, and so is a dumps folder that can\'t be'] = function()
	local file = report([[
		vim.fn.writefile({ 'x' }, _G.FRG_TEST.root .. '/state/blocked')
		_G.FRG_TEST.setup({ session_dir = _G.FRG_TEST.root .. '/state/blocked/sessions/' })
	]])
	local locked = child.lua([[
		local dir = _G.FRG_TEST.root .. '/locked'
		vim.fn.mkdir(dir, 'p')
		vim.uv.fs_chmod(dir, tonumber('500', 8))
		_G.FRG_TEST.setup({ session_dir = dir .. '/sessions/' })
		return vim.uv.fs_access(dir, 'W') and 'root' or 'locked'
	]])
	local rows = report()
	child.lua('vim.uv.fs_chmod(_G.FRG_TEST.root .. "/locked", tonumber("700", 8))')
	local dumps = report([[
		local state = vim.fn.stdpath('state')
		vim.fn.mkdir(state, 'p')
		vim.fn.delete(state .. '/frogman', 'rf')
		vim.uv.fs_chmod(state, tonumber('500', 8))
	]])
	child.lua('vim.uv.fs_chmod(vim.fn.stdpath("state"), tonumber("700", 8))')
	local first = section(file, 'Folders')[1]
	eq({ first.level, first.msg:find('isn\'t a folder', 1, true) ~= nil }, { 'error', true })
	if locked == 'root' then
		MiniTest.skip('running as root, the folders are still writable')
	end
	local sessions = section(rows, 'Folders')[1]
	local dump = section(dumps, 'Folders')[2]
	eq({ locked = { sessions.level, sessions.msg:find("can't be written", 1, true) ~= nil, sessions.advice:find('session_dir', 1, true) ~= nil },
		dumps = { dump.level, dump.msg:find("can't be written", 1, true) ~= nil, dump.msg:find('dumps', 1, true) == 1 } },
		{ locked = { 'error', true, true }, dumps = { 'error', true, true } })
end

T['T1302 [char] (M17; the user, 2026-11-12: "All seven (Recommended)") setup() not run, and disable(), are warnings; setup() again is fine'] = function()
	child.restart({ '-u', 'scripts/minimal_init.lua' })
	local never = report()
	child.setup()
	child.lua('require("frogman").disable()')
	local off = report()
	child.lua('_G.FRG_TEST.setup()')
	local again = report()
	eq({ never = lines(never, 'Setup'), keys = lines(never, 'Keys'), off = section(off, 'Setup')[1].level, again = lines(again, 'Setup') },
		{ never = { "warn: setup() hasn't run, so nothing is tracked" }, keys = { "info: no keys mapped yet: setup() hasn't run" },
			off = 'warn', again = { 'ok: setup() has run, and frogman is on' } })
end

T['T1303 [char] (M17; the user, 2026-11-12: "Required two as errors (Recommended)") telescope and nvim-window-picker missing are errors, cokeline missing a warning'] = function()
	local missing = report()
	local stubbed = report([[
		package.preload['telescope.builtin'] = function() return {} end
		package.preload['telescope.pickers'] = function() return {} end
		package.preload['window-picker'] = function() return { pick_window = function() end } end
		package.preload['cokeline.mappings'] = function() error('not installed') end
		package.loaded['cokeline.mappings'] = nil
	]])
	local half = report([[
		package.preload['telescope.builtin'] = function() return {} end
		package.preload['telescope.pickers'], package.loaded['telescope.pickers'] = nil, nil
	]])
	local function levels(rows)
		return vim.tbl_map(function(r) return r.level .. ' ' .. (r.msg:match('^(%S+)') or '') end, section(rows, 'Plugins frogman uses'))
	end
	eq({ levels(missing), levels(stubbed), levels(half)[1] },
		{ { 'error telescope.nvim', 'error nvim-window-picker', 'ok nvim-cokeline' },
			{ 'ok telescope.nvim', 'ok nvim-window-picker', 'warn nvim-cokeline' }, 'error telescope.nvim' })
end

T['T1304 [char] (M17; the user, 2026-11-12: "All three (Recommended)") a key another mapping had before setup() took it is a warning, and stays one through another setup(), however that one spells it'] = function()
	local rows = report([[
		vim.keymap.set('n', '<M-z>', ':echo "mine"<CR>', { desc = 'my own thing' })
		_G.FRG_TEST.setup({ keymaps = { toggle_secondary = '<M-z>' } })
	]])
	local again = report([[_G.FRG_TEST.setup({ keymaps = { toggle_secondary = '<m-z>' } })]])
	local moved = report([[_G.FRG_TEST.setup()]])
	local said = 'warn: <M-z> was mapped to my own thing before setup() mapped it to toggle current ↔ secondary buffer'
	eq({ first = lines(rows, 'Keys'), second = lines(again, 'Keys')[1] == said:gsub('<M%-z>', '<m-z>'), moved = section(moved, 'Keys')[1].level,
		advice = section(rows, 'Keys')[1].advice },
		{ first = { said }, second = true, moved = 'ok',
			advice = 'Set keymaps.toggle_secondary to another key, or to false to leave it unmapped.' })
end

T['T1305 [char] (M17; the user, 2026-11-12: "All three (Recommended)") a frogman key mapped over or unmapped after setup() is a warning'] = function()
	local rows = report([[
		vim.keymap.set('n', '<M-f>', ':echo "mine"<CR>', { desc = 'my own thing' })
		vim.keymap.del('n', '<M-S-f>')
	]])
	eq(lines(rows, 'Keys'), {
		"warn: <M-f>, frogman's key to toggle current ↔ secondary buffer, was mapped over after setup(): it's mapped to my own thing now",
		"warn: <M-S-f>, frogman's key to toggle current ↔ ternary buffer, isn't mapped any more",
	})
end

T['T1306 [char] (M17; the user, 2026-11-12: "All three (Recommended)") a main key that\'s the same as one of the marks\' keys is a warning, spelled alike or not'] = function()
	local apart = report([[_G.FRG_TEST.setup({ keymaps = { toggle_secondary = "<m-'><M-1>" } })]])
	local alike = report([[_G.FRG_TEST.setup({ keymaps = { toggle_secondary = "<M-'><M-1>" } })]])
	eq({ lines(apart, 'Keys'), lines(alike, 'Keys') }, {
		{ "warn: <m-'><M-1> is frogman's key to both toggle current ↔ secondary buffer and use the window's marks; the marks' key took it" },
		{ "warn: <M-'><M-1> is frogman's key to both toggle current ↔ secondary buffer and use the window's marks; the marks' key took it" },
	})
end

T['T1307 [char] (M17) with nothing clashing the keys are fine, a buffer\'s own mapping of a key included, and another setup() takes frogman\'s keys back'] = function()
	local rows = report([[
		vim.keymap.set('n', '<M-f>', ':echo "here only"<CR>', { buffer = 0 })
		_G.FRG_TEST.setup()
	]])
	local mine = child.lua([[
		local m = require('frogman.state').global_mapping('<M-f>')
		return m ~= nil and m.callback == require('frogman.state').mapped['<M-f>']
	]])
	local keys = section(rows, 'Keys')
	eq({ #keys, keys[1].level, keys[1].msg:find("^each of frogman's %d+ keys is its own") ~= nil, mine },
		{ 1, 'ok', true, true })
end

T['T1308 [char] (M17) with every key off in the config, the Keys part says frogman maps none'] = function()
	local rows = report([[
		local off = {}
		for name, lhs in pairs(require('frogman.configs').keymaps) do
			if type(lhs) == 'string' then off[name] = false end
		end
		_G.FRG_TEST.setup({ keymaps = off })
	]])
	eq(lines(rows, 'Keys'), { 'info: frogman maps no keys: every one is off in the config' })
end

return T
