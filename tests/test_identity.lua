-- Identity, registry and tracking (M1-M3). IDs are the spec's
-- (what-is-cavediver.md, section 7).
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
			local path = _G.CDV_TEST.root .. '/' .. n
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
		return { path = hash and H.get_filepath_from_hash(hash), want = 'NONAME_' .. tostring(vim.b[buf].cavediver_noname) }
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
		local path = _G.CDV_TEST.root .. '/same.txt'
		vim.o.eventignore = 'all'
		local older = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(older, path)
		local hash = H.register_buffer(older)
		vim.api.nvim_buf_set_name(older, _G.CDV_TEST.root .. '/moved.txt')
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

return T
