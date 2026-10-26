-- Shared helpers for frogman's tests.
--
-- Every test drives a child Neovim with frogman set up in a fresh temporary
-- project (files a.txt to f.txt, t.txt and x.txt), so no state leaks between
-- cases. Slots are read back in the winbar's order and brackets:
--   ⦉ternary⦊ [current] ⟦secondary⟧
-- and the notes as dtm{…} (restore ternary) and dsm{…} (restore secondary),
-- with file names shortened to their stem (a.txt → a) and swap keys as x-swap.

local Helpers = {}

Helpers.expect = vim.deepcopy(MiniTest.expect)
Helpers.eq = MiniTest.expect.equality

-- Code that runs inside the child once per case.
local CHILD_SETUP = [==[
local opts = ...
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/state', 'p')
for _, f in ipairs({ 'a', 'b', 'c', 'd', 'e', 'f', 't', 'x' }) do
	vim.fn.writefile({ f }, root .. '/' .. f .. '.txt')
end
vim.cmd('cd ' .. vim.fn.fnameescape(root))

-- harpoon: no marks.
package.preload['harpoon'] = function()
	return { list = function() return { display = function() return {} end } end }
end
-- cokeline: by_step("focus", step) walks frogman's ordered history
-- (index 1 = most recent), the order the bufferline shows.
if not opts.no_cokeline then
	package.preload['cokeline.mappings'] = function()
		return {
			by_step = function(_, step)
				local ord = require('frogman.domains.history').get_ordered_buffers()
				local cur = vim.api.nvim_get_current_buf()
				local idx = 1
				for i, e in ipairs(ord) do if e.buf == cur then idx = i end end
				vim.api.nvim_set_current_buf(ord[((idx - 1 + step) % #ord) + 1].buf)
			end,
			is_picking_focus = function() return false end,
			is_picking_close = function() return false end,
		}
	end
end

_G.FRG_NOTES = {}
vim.notify = function(msg, level) table.insert(_G.FRG_NOTES, { msg = tostring(msg), level = level }) end

-- what this child is set up with; every setup() starts from the defaults, so a case that sets up
-- again layers its own options over these (_G.FRG_TEST.setup)
_G.FRG_BASE = {
	session_dir = root .. '/state/sessions/',
	bufferline = { history_view = opts.history_view or 'global' },
}
require('frogman').setup(_G.FRG_BASE)

local H = require('frogman.domains.history')
local W = require('frogman.domains.window')

local function name(hash)
	if hash == nil then return '-' end
	local base = hash:gsub('%-swap$', '')
	local path = H.get_filepath_from_hash(base)
	local n = path and vim.fn.fnamemodify(path, ':t:r') or ('?' .. base:sub(1, 6))
	if hash:match('%-swap$') then n = n .. '-swap' end
	return n
end

local function map(m)
	local keys = {}
	for k, v in pairs(m or {}) do table.insert(keys, name(k) .. '>' .. name(v)) end
	table.sort(keys)
	return '{' .. table.concat(keys, ' ') .. '}'
end

_G.FRG_TEST = {
	root = root,
	-- set up again with the options given, layered over this child's own (_G.FRG_BASE)
	setup = function(options)
		require('frogman').setup(vim.tbl_deep_extend('force', vim.deepcopy(_G.FRG_BASE), options or {}))
	end,
	slots = function(winid)
		local t = W.data.crux[winid or vim.api.nvim_get_current_win()]
		if not t then return 'no triquetra' end
		return string.format('⦉%s⦊ [%s] ⟦%s⟧', name(t.ternary_slot), name(t.current_slot), name(t.secondary_slot))
	end,
	notes = function(winid)
		local t = W.data.crux[winid or vim.api.nvim_get_current_win()]
		if not t then return 'no triquetra' end
		return 'dtm' .. map(t.displacement_ternary_map) .. ' dsm' .. map(t.displacement_secondary_map)
	end,
	primary = function(winid)
		local t = W.data.crux[winid or vim.api.nvim_get_current_win()]
		if not t then return 'no triquetra' end
		local p = {}
		for _, h in ipairs(t.primary_buffer or {}) do table.insert(p, name(h)) end
		return '[' .. table.concat(p, ',') .. ']' .. (t.primary_enabled and 'on' or 'off')
	end,
	shown = function(winid)
		return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(winid or 0)), ':t:r')
	end,
	ordered = function()
		local out = {}
		for _, e in ipairs(H.data.ordered.crux) do
			table.insert(out, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(e.buf), ':t:r'))
		end
		return table.concat(out, ',')
	end,
	closed = function()
		local out = {}
		for _, h in ipairs(H.data.closed_buffers) do table.insert(out, name(h)) end
		return table.concat(out, ',')
	end,
	-- Press a mapped key by running its mapping, so errors come back instead of
	-- landing in :messages. Returns ok, err.
	press = function(lhs)
		local m = vim.fn.maparg(lhs, 'n', false, true)
		if not m or not m.callback then
			return false, 'no mapping for ' .. lhs
		end
		local ok, err = pcall(m.callback)
		return ok, err and tostring(err) or nil
	end,
}
]==]

-- Start a new child; `child.setup(opts)` restarts it with frogman ready.
-- opts: history_view = 'global' | 'window' (default 'global'),
--       no_cokeline = true to leave cokeline out.
Helpers.new_child = function()
	local child = MiniTest.new_child_neovim()

	child.setup = function(opts)
		child.restart({ '-u', 'scripts/minimal_init.lua' })
		child.lua(CHILD_SETUP, { opts or {} })
	end

	-- The dumps under stdpath('state')/frogman/.
	child.dump_files = function()
		return child.lua([[return vim.fn.globpath(vim.fn.stdpath('state') .. '/frogman', 'dump-*.txt', true, true)]])
	end

	-- What fired in the first dump written since `before` (a child.dump_files() list), read in this
	-- child's project, where it was sealed; nil when none was written. Walks fail on one.
	child.dumped_since = function(before)
		local fired = child.lua([[
			local seen = {}
			for _, f in ipairs(...) do seen[f] = true end
			for _, f in ipairs(vim.fn.globpath(vim.fn.stdpath('state') .. '/frogman', 'dump-*.txt', true, true)) do
				if not seen[f] then
					local text = require('frogman.domains.ledger.dump').read(f)
					return text and text:match('\n([^\n]*)') or ('a dump that does not open: ' .. vim.fn.fnamemodify(f, ':t'))
				end
			end
		]], { before })
		if fired == vim.NIL then return nil end
		return fired
	end

	-- Let scheduled callbacks and short timers run.
	child.settle = function(ms)
		child.lua('vim.wait(...)', { ms or 30 })
	end

	-- One step. A string starting with ':' is an Ex command, with a bare file
	-- letter expanded (':e a' → ':e a.txt'); anything else is a mapped key.
	-- Returns ok, err for keys; Ex commands raise on error.
	child.step = function(action)
		local ok, err = true, nil
		if action:sub(1, 1) == ':' then
			local cmd = action:sub(2):gsub('^(e%s+)(%a)$', '%1%2.txt')
			child.cmd(cmd)
		else
			local res = child.lua('return { _G.FRG_TEST.press(...) }', { action })
			ok, err = res[1], res[2]
		end
		child.settle()
		return ok, err
	end

	-- Several steps; fails the case on the first key that errors.
	child.steps = function(actions)
		for _, a in ipairs(actions) do
			local ok, err = child.step(a)
			if not ok then
				error(string.format('%s raised: %s', a, err), 2)
			end
		end
	end

	child.slots = function(winid) return child.lua('return _G.FRG_TEST.slots(...)', { winid }) end
	child.notes = function(winid) return child.lua('return _G.FRG_TEST.notes(...)', { winid }) end
	child.primary = function(winid) return child.lua('return _G.FRG_TEST.primary(...)', { winid }) end
	child.shown = function(winid) return child.lua('return _G.FRG_TEST.shown(...)', { winid }) end
	child.ordered = function() return child.lua('return _G.FRG_TEST.ordered()') end
	child.closed = function() return child.lua('return _G.FRG_TEST.closed()') end
	child.messages = function()
		local m = child.lua('local n = _G.FRG_NOTES; _G.FRG_NOTES = {}; return n')
		return m
	end

	return child
end

return Helpers
