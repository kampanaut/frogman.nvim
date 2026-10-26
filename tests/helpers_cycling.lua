-- Extra helpers for the cycling, closing, windows and primary queue window
-- tests. Candidates for tests/helpers.lua.
--
--   local Extra = dofile('tests/helpers_cycling.lua')
--   Extra.attach(child)   -- once, after Helpers.new_child()
--
-- Every function runs after child.setup(); the child-side table is installed
-- lazily on first use in each fresh child.

local Extra = {}

local CHILD_EXTRA = [==[
local H = require('frogman.domains.history')
local W = require('frogman.domains.window')
local N = require('frogman.domains.navigation')

local function name(hash)
	if hash == nil then return '-' end
	local base = hash:gsub('%-swap$', '')
	local path = H.get_filepath_from_hash(base)
	local n = path and vim.fn.fnamemodify(path, ':t:r') or ('?' .. base:sub(1, 6))
	if hash:match('%-swap$') then n = n .. '-swap' end
	return n
end

local function triquetra(winid)
	return W.data.crux[winid or vim.api.nvim_get_current_win()]
end

_G.CDV_X = {
	name = name,
	state = function()
		return { nav = N.sm:state(), hist = H.sm:state() }
	end,
	-- One note, by its key's name ('b' or 'b-swap'), from 'dtm' or 'dsm'.
	-- Returns the value's name, or '-' when there's no such note.
	note = function(which, key, winid)
		local t = triquetra(winid)
		if not t then return 'no triquetra' end
		local map = which == 'dtm' and t.displacement_ternary_map or t.displacement_secondary_map
		for k, v in pairs(map or {}) do
			if name(k) == key then return name(v) end
		end
		return '-'
	end,
	-- The hash of a project file by its stem ('a' → <root>/a.txt).
	hash_of = function(stem)
		return H.get_hash_from_filepath(_G.CDV_TEST.root .. '/' .. stem .. '.txt')
	end,
	-- Floating windows open now.
	floats = function()
		local out = {}
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_config(w).relative ~= '' then table.insert(out, w) end
		end
		return out
	end,
	-- The primary queue window, or nil.
	popup = function()
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			local b = vim.api.nvim_win_get_buf(w)
			if vim.bo[b].filetype == 'cavediver-primary-buffer-history' then return w end
		end
		return nil
	end,
	-- Every place in cavediver's data that holds `hash`: slots, primary
	-- queues, map keys (plain or -swap) and values, history, closed stack.
	refs = function(hash)
		local out = {}
		local function hit(where) table.insert(out, where) end
		for winid, t in pairs(W.data.crux) do
			for _, slot in ipairs({ 'current_slot', 'secondary_slot', 'ternary_slot' }) do
				if t[slot] == hash then hit(winid .. '.' .. slot) end
			end
			for i, h in ipairs(t.primary_buffer or {}) do
				if h == hash then hit(winid .. '.primary[' .. i .. ']') end
			end
			for _, m in ipairs({ 'displacement_ternary_map', 'displacement_secondary_map' }) do
				for k, v in pairs(t[m] or {}) do
					if k == hash or k == hash .. '-swap' then hit(winid .. '.' .. m .. ' key') end
					if v == hash then hit(winid .. '.' .. m .. ' value') end
				end
			end
		end
		if H.data.crux[hash] then hit('history') end
		for _, h in ipairs(H.data.closed_buffers) do
			if h == hash then hit('closed') end
		end
		return out
	end,
	-- Files under stdpath('state')/cavediver/, recursively, sorted.
	dumps = function()
		local dir = vim.fn.stdpath('state') .. '/cavediver'
		local files = vim.fn.globpath(dir, '**/*', true, true)
		local out = {}
		for _, f in ipairs(files) do
			if vim.fn.isdirectory(f) == 0 then table.insert(out, f) end
		end
		table.sort(out)
		return out
	end,
}
]==]

Extra.attach = function(child)
	local function ensure()
		if not child.lua('return _G.CDV_X ~= nil') then
			child.lua(CHILD_EXTRA)
		end
	end
	local function call(fn, ...)
		ensure()
		return child.lua('return _G.CDV_X.' .. fn .. '(...)', { ... })
	end

	-- { nav = 'normal'|'cycling', hist = 'attached'|'detached' }
	child.state = function() return call('state') end
	child.note = function(which, key, winid) return call('note', which, key, winid) end
	child.hash_of = function(stem) return call('hash_of', stem) end
	child.floats = function() return call('floats') end
	child.popup = function()
		local w = call('popup')
		if w == vim.NIL then return nil end
		return w
	end
	child.refs = function(hash) return call('refs', hash) end
	child.dumps = function() return call('dumps') end
	child.win = function() return child.lua('return vim.api.nvim_get_current_win()') end

	-- The primary queue window's lines.
	child.popup_lines = function()
		local w = child.popup()
		if not w then return nil end
		return child.lua('return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(...), 0, -1, false)', { w })
	end
	-- Replace the primary queue window's lines (the window must be current).
	child.popup_set = function(lines)
		child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, ...)', { lines })
	end
end

-- Messages with level at or above `level` (default ERROR), as plain strings.
Extra.at_least = function(msgs, level)
	level = level or vim.log.levels.ERROR
	local out = {}
	for _, m in ipairs(msgs) do
		if m.level ~= nil and m.level ~= vim.NIL and m.level >= level then table.insert(out, m.msg) end
	end
	return out
end

-- True when some message contains `text` (plain).
Extra.has = function(msgs, text)
	for _, m in ipairs(msgs) do
		if m.msg:find(text, 1, true) then return true end
	end
	return false
end

-- Files in `after` that aren't in `before`.
Extra.new_files = function(before, after)
	local seen = {}
	for _, f in ipairs(before) do seen[f] = true end
	local out = {}
	for _, f in ipairs(after) do
		if not seen[f] then table.insert(out, f) end
	end
	return out
end

return Extra
