-- Extra helpers for the decided-rule cases (tests/test_decisions.lua). They sit
-- on top of tests/helpers.lua's child and the other helper files, which they
-- use unchanged, and are candidates for the shared helpers.

local Dec = {}

-- Random walks with four more invariant checks ------------------------------

-- The walker of tests/helpers_misc.lua (its actions, its run loop and its
-- checks), read from that file, with the checks below appended to the same
-- chunk so they join its `checks` table.
local MISC = table.concat(vim.fn.readfile('tests/helpers_misc.lua'), '\n')
local WALKER = MISC:match('local WALKER = %[==%[\n(.-)%]==%]')
assert(WALKER and WALKER:find('local checks = {}', 1, true), 'tests/helpers_misc.lua changed: WALKER no longer matches')

local EXTRA_CHECKS = [==[
local function base(path) return path and vim.fn.fnamemodify(path, ':t') or '?' end

-- I5: the registry is a bijection, for buffers and for paths.
checks.I5 = { post = function()
	local r = H.data.hash_buffer_registry
	for h, b in pairs(r.buffers) do
		if r.hashes[b] ~= h then
			return string.format('buffers[%s] = %d, but hashes[%d] = %s', name(h), b, b, r.hashes[b] and name(r.hashes[b]) or 'nil')
		end
	end
	for b, h in pairs(r.hashes) do
		if r.buffers[h] ~= b then
			return string.format('hashes[%d] = %s, but buffers[%s] = %s', b, name(h), name(h), tostring(r.buffers[h]))
		end
	end
	local p = H.data.hash_filepath_registry
	for h, path in pairs(p.filepaths) do
		if p.hashes[path] ~= h then return string.format('filepaths[%s] = %s has no matching reverse entry', name(h), base(path)) end
	end
	for path, h in pairs(p.hashes) do
		if p.filepaths[h] ~= path then return string.format('hashes[%s] = %s has no matching forward entry', base(path), name(h)) end
	end
end }

-- I7: after a cleanup pass, no hash on the closed stack has an open buffer.
checks.I7 = { post = function()
	H.cleanup_system()
	for _, h in ipairs(H.data.closed_buffers) do
		local b = H.data.hash_buffer_registry.buffers[h]
		if b and vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_is_loaded(b) then
			return string.format('closed %s still has open buffer %d', name(h), b)
		end
		local path = H.get_filepath_from_hash(h)
		local nb = path and vim.fn.bufnr(path) or -1
		if nb ~= -1 and vim.api.nvim_buf_is_loaded(nb) and vim.bo[nb].buflisted then
			return string.format('closed %s is open as buffer %d', name(h), nb)
		end
	end
end }

-- I8: a window's current slot is the hash of the buffer it shows, outside
-- the window a cycle runs in and outside visits (a shown buffer that isn't
-- registered). The cycle's window is the one a cycling key started it from.
local cycle_win
checks.I8 = {
	pre = function()
		return { nav = N.sm:state(), win = vim.api.nvim_get_current_win() }
	end,
	post = function(snap, action)
		local nav = N.sm:state()
		if nav == 'cycling' then
			if snap.nav ~= 'cycling' then cycle_win = snap.win end
		else
			cycle_win = nil
		end
		for winid, t in pairs(W.data.crux) do
			if winid ~= cycle_win and vim.api.nvim_win_is_valid(winid)
				and vim.api.nvim_win_get_config(winid).relative == '' then
				local buf = vim.api.nvim_win_get_buf(winid)
				local h = H.get_hash_from_buffer(buf)
				if h and t.current_slot ~= h then
					return string.format('window %d shows %s, its current slot is %s (navigation %s)',
						winid, stem(buf), name(t.current_slot), nav)
				end
			end
		end
	end,
}

-- Handles (M2 Handles): after a cleanup pass, every path has one live handle,
-- every live handle a path, each open exactly while its hash has a buffer, and
-- gone exactly while its file has a tag.
checks.HANDLES = { post = function()
	H.cleanup_system()
	local handles = H.handles
	local paths, buffers = H.data.hash_filepath_registry.filepaths, H.data.hash_buffer_registry.buffers
	for hash, path in pairs(paths) do
		local h = handles.of_hash(hash)
		if not h then return string.format('%s has a path and no handle', base(path)) end
		if handles.get(h.id) ~= h then return string.format('%s has handle %d, not live', base(path), h.id) end
		if h.hash ~= hash then return string.format('%s has handle %d, which names another hash', base(path), h.id) end
		if (h:state() == 'open') ~= (buffers[hash] ~= nil) then
			return string.format('%s handle %d is %s, its buffer %s', base(path), h.id, h:state(), tostring(buffers[hash]))
		end
		if h.gone ~= (H.data.missing[hash] ~= nil) then
			return string.format('%s handle %d gone %s, its tag %s', base(path), h.id, tostring(h.gone), tostring(H.data.missing[hash]))
		end
	end
	for id, h in pairs(handles.live()) do
		if paths[h.hash] == nil then return string.format('handle %d names no path', id) end
		if handles.of_hash(h.hash) ~= h then return string.format('handle %d shares its hash with another', id) end
	end
	for hash in pairs(buffers) do
		if not handles.of_hash(hash) then return string.format('buffer %d is registered with no handle', buffers[hash]) end
	end
end }

-- Holders (M2 Holders): the hashes whose handles have a holder are exactly what follow-along calls
-- known, and each place holds what its own writes say; the one copy of the check, which child.settle
-- runs too under FRG_CHECK_HOLDERS (tests/holders_check.lua).
checks.HOLDERS = { post = function()
	local file = vim.api.nvim_get_runtime_file('tests/holders_check.lua', false)[1]
	if not file then
		error('tests/holders_check.lua is not on the runtimepath, so the holders go unchecked')
	end
	return dofile(file)(name)
end }

-- I9: every triquetra belongs to a valid, non-floating window.
checks.I9 = { post = function()
	for winid in pairs(W.data.crux) do
		if not vim.api.nvim_win_is_valid(winid) then return string.format('triquetra for closed window %d', winid) end
		if vim.api.nvim_win_get_config(winid).relative ~= '' then return string.format('triquetra for float %d', winid) end
	end
end }
]==]

-- Run `walks` deterministic random walks of `steps` actions, each in a fresh
-- child, and return the first break as a message, or nil. opts as in
-- Misc.walks (tests/helpers_misc.lua), with check one of I5, I7, I8, I9 (or
-- any of the walker's own).
Dec.walks = function(child, opts)
	for w = 1, opts.walks do
		child.setup(opts.setup)
		child.lua(WALKER .. '\n' .. EXTRA_CHECKS)
		local seed = opts.seed * 1000 + w
		local dumps = child.dump_files()
		local broke = child.lua('return _G.FRG_WALK(...)', { seed, opts.steps, opts.actions, opts.check })
		if broke ~= vim.NIL and broke ~= nil then
			return string.format('%s broke in walk %d (seed %d), step %d: %s\n  route: %s',
				opts.check, w, seed, broke.step, broke.detail, broke.trail)
		end
		local fired = child.dumped_since(dumps)
		if fired then
			return string.format('walk %d (seed %d) dumped: %s', w, seed, fired)
		end
	end
	return nil
end

-- Small readers -------------------------------------------------------------

-- Is buffer `buf` (default: the current one) registered?
Dec.registered = function(child, buf)
	return child.lua([[
		return require('frogman.domains.history').get_hash_from_buffer(... or vim.api.nvim_get_current_buf()) ~= nil
	]], { buf })
end

-- A window's winbar as text: highlight groups and other %-items taken out.
Dec.winbar_text = function(child, winid)
	child.settle(300)
	local s = child.lua('return vim.wo[... or 0].winbar', { winid or 0 })
	return (s:gsub('%%#[^#]*#', ''):gsub('%%%*', ''):gsub('%%=', ''))
end

-- Whether `pieces` appear in `s` in that order, each taken literally.
Dec.in_order = function(s, pieces)
	local from = 1
	for _, p in ipairs(pieces) do
		local i, j = s:find(p, from, true)
		if not i then return false end
		from = j + 1
	end
	return true
end

-- Is the current buffer strictly first in the bufferline order, against
-- every other tracked buffer (a tie isn't)? Returns nil, or a short reason.
Dec.leftmost = function(child)
	local v = child.lua([[
		local H = require('frogman.domains.history')
		local bl = require('frogman.domains.ui').bufferline
		local cur = vim.api.nvim_get_current_buf()
		local stem = function(b) return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ':t:r') end
		if not H.get_hash_from_buffer(cur) then return 'current buffer not tracked' end
		for _, e in ipairs(H.get_ordered_buffers()) do
			if e.buf ~= cur and not bl.compare_buffers(cur, e.buf) then
				return string.format('%s not ahead of %s', stem(cur), stem(e.buf))
			end
		end
		return vim.NIL
	]])
	if v == vim.NIL then return nil end
	return v
end

-- Writers -------------------------------------------------------------------

-- Make the current buffer's secondary note name the window's secondary, so
-- the next <M-;><M-t> fires the restore assertion (as test_cycling.lua does
-- for the flight recorder).
Dec.stale_secondary_note = function(child)
	child.lua([[
		local t = require('frogman.domains.window').data.crux[vim.api.nvim_get_current_win()]
		t.displacement_secondary_map[t.current_slot .. '-swap'] = nil
		t.displacement_secondary_map[t.current_slot] = t.secondary_slot
	]])
end

-- Show a fresh nofile scratch in the current window (a visit); returns it.
Dec.visit_scratch = function(child)
	local buf = child.lua([[
		local buf = vim.api.nvim_create_buf(true, true)
		vim.api.nvim_win_set_buf(0, buf)
		return buf
	]])
	child.settle()
	return buf
end

-- Child-side code: timers(), the number of active timers in the child.
Dec.TIMERS = [[
local function timers()
	local n = 0
	vim.uv.walk(function(h) if h:get_type() == 'timer' and h:is_active() then n = n + 1 end end)
	return n
end
]]

-- A child with frogman on the runtimepath but not required, in an empty
-- temporary directory, notifications collected (as tests/test_setup.lua does).
Dec.bare = function(child)
	child.restart({ '-u', 'scripts/minimal_init.lua' })
	child.lua([[
		local root = vim.fn.tempname()
		vim.fn.mkdir(root, 'p')
		vim.cmd('cd ' .. vim.fn.fnameescape(root))
		_G.FRG_ROOT = root
		_G.FRG_NOTES = {}
		vim.notify = function(msg, level) table.insert(_G.FRG_NOTES, { msg = tostring(msg), level = level }) end
	]])
end

return Dec
