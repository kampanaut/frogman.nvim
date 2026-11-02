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

	-- Let scheduled callbacks and short timers run. With FRG_CHECK_HOLDERS set, it then checks the
	-- handles' holders (M2 Holders): the files held are the ones known, and each place holds what its
	-- window's slots and queue, its list or the registered buffers hold; it fails the case where they
	-- differ. Seven cases plant slots or list entries by hand, so they fail under it by design: T34,
	-- T275, T276, T589 (slots), T371, T372, T676 (list entries).
	child.settle = function(ms)
		child.lua('vim.wait(...)', { ms or 30 })
		if os.getenv('FRG_CHECK_HOLDERS') then
			local drift = child.lua([[
				if not package.loaded['frogman.domains.history'] then return nil end
				local H = require('frogman.domains.history')
				if not H.handles or not H.handles.holders then return nil end
				local known, held = H.routines.known_filehashes(), {}
				for _, h in pairs(H.handles.live()) do
					if next(h.holders) then held[h.hash] = true end
				end
				for hash in pairs(known) do
					if not held[hash] and H.handles.of_hash(hash) then return 'known, no holder: ' .. hash end
				end
				for hash in pairs(held) do
					if not known[hash] then return 'held, not known: ' .. hash .. ' by ' .. table.concat(H.handles.holders(hash), ', ') end
				end
				local W = require('frogman.domains.window')
				local function same(place, hashes)
					local want, seen = {}, {}
					for _, h in pairs(hashes) do
						if H.handles.of_hash(h) then want[h] = true end
					end
					for _, h in ipairs(H.handles.held_by(place)) do
						if not want[h] then return place .. ' holds ' .. h .. ', which it does not' end
						seen[h] = true
					end
					for h in pairs(want) do
						if not seen[h] then return place .. ' misses ' .. h end
					end
				end
				for winid, t in pairs(W.data.crux) do
					local p = 'win:' .. winid .. ':'
					local bad = same(p .. 'current', { t.current_slot }) or same(p .. 'secondary', { t.secondary_slot })
						or same(p .. 'ternary', { t.ternary_slot }) or same(p .. 'primary', t.primary_buffer or {})
					if bad then return bad end
				end
				for _, pool in pairs(H.routines.pools()) do
					local bad = same(H.routines.pool_place(pool), pool.closed)
					if bad then return bad end
				end
				-- each mark's place holds its file (M15)
				local Mk = package.loaded['frogman.domains.marks']
				for kind, scopes in pairs(Mk and Mk.data.scopes or {}) do
					for id, scope in pairs(scopes) do
						for position, group in ipairs(scope.groups) do
							for alias, hid in pairs(group.marks) do
								local handle = H.handles.get(H.handles.resolve(hid))
								local bad = same('mark:' .. kind .. ':' .. tostring(id) .. ':' .. position .. ':' .. alias, { handle and handle.hash })
								if bad then return bad end
							end
						end
					end
				end
				-- each snapshot's place holds its slots', its queue's and its order's files (M16)
				local Sn = package.loaded['frogman.domains.snapshots']
				for _, snaps in pairs(Sn and Sn.data.by_window or {}) do
					for _, sn in ipairs(snaps) do
						local hashes = {}
						for _, id in ipairs(vim.list_extend({ sn.current, sn.secondary or false, sn.ternary or false }, vim.list_extend(vim.deepcopy(sn.queue), sn.order))) do
							local h = id and H.handles.get(H.handles.resolve(id))
							if h then table.insert(hashes, h.hash) end
						end
						local bad = same('snap:' .. sn.id, hashes)
						if bad then return bad end
					end
				end
				local bufs = {}
				for h in pairs(H.data.hash_buffer_registry.buffers) do table.insert(bufs, h) end
				local bad = same('buffer', bufs)
				if bad then return bad end
			]])
			if drift ~= nil and drift ~= vim.NIL then
				error('holders drift: ' .. drift, 2)
			end
		end
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

	-- Answer every confirm() from now on with the choice whose label is `choice` ("Yes", "No"),
	-- and keep each prompt's text: an unanswered confirm() blocks a headless child.
	child.answer = function(choice)
		child.lua([[
			local choice = ...
			_G.FRG_PROMPTS = _G.FRG_PROMPTS or {}
			vim.fn.confirm = function(msg, choices)
				table.insert(_G.FRG_PROMPTS, msg)
				local i = 0
				for c in (choices or ''):gmatch('[^\n]+') do
					i = i + 1
					if c:gsub('&', '') == choice then return i end
				end
				return 0
			end
		]], { choice })
	end

	-- The prompts confirm() was given since the last call.
	child.prompts = function()
		return child.lua('local p = _G.FRG_PROMPTS or {}; _G.FRG_PROMPTS = {}; return p')
	end

	return child
end

return Helpers
