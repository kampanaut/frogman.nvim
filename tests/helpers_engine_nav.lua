-- Extra helpers for the engine, identity, history, lifecycle and navigation
-- tests. They work on a child from tests/helpers.lua after child.setup().
--
-- Files are named by their stem (a for a.txt), as in the shared helpers.

local X = {}

-- Code run in the child: name <-> handle for the temp project's files.
local CHILD_LIB = [==[
_G.FRG_X = _G.FRG_X or {}
local H = require('frogman.domains.history')
local W = require('frogman.domains.window')

-- a slot's file, or a note's key, by its handle (a note's key the handle, or the handle and -swap)
local function name(id)
	if id == nil then return nil end
	local path = H.get_filepath_from_handle(W.data.note_owner(id))
	local n = path and vim.fn.fnamemodify(path, ':t:r') or ('?' .. tostring(W.data.note_owner(id)))
	if W.data.is_swap_note(id) then n = n .. '-swap' end
	return n
end

-- The hash a file of the temp project has, whether or not it's open.
local function hash(stem)
	return H.routines.get_filehash(_G.FRG_TEST.root .. '/' .. stem .. '.txt')
end

-- The handle a file of the temp project has, nil while frogman doesn't know it.
local function handle(stem)
	return H.get_handle_from_hash(hash(stem))
end

local function key(k)
	local stem, swap = k:match('^(.-)(%-swap)$')
	if stem then return handle(stem) .. swap end
	return handle(k)
end

_G.FRG_X.name = name
_G.FRG_X.hash = hash
_G.FRG_X.handle = handle

-- Both maps of a window as tables of names, swap keys included.
_G.FRG_X.maps = function(winid)
	local t = W.data.crux[winid or vim.api.nvim_get_current_win()]
	if not t then return nil end
	local out = { dtm = {}, dsm = {} }
	for k, v in pairs(t.displacement_ternary_map or {}) do out.dtm[name(k)] = name(v) end
	for k, v in pairs(t.displacement_secondary_map or {}) do out.dsm[name(k)] = name(v) end
	return out
end

-- Set slots and maps of a window directly, by file stem. Fields left out are
-- kept; `false` empties a slot.
_G.FRG_X.set = function(spec, winid)
	local t = W.data.crux[winid or vim.api.nvim_get_current_win()]
	for _, slot in ipairs({ 'current', 'secondary', 'ternary' }) do
		if spec[slot] == false then
			t[slot .. '_slot'] = nil
		elseif spec[slot] then
			t[slot .. '_slot'] = handle(spec[slot])
		end
	end
	for _, m in ipairs({ { 'dtm', 'displacement_ternary_map' }, { 'dsm', 'displacement_secondary_map' } }) do
		if spec[m[1]] then
			local map = {}
			for k, v in pairs(spec[m[1]]) do map[key(k)] = handle(v) end
			t[m[2]] = map
		end
	end
end

-- Is the current buffer strictly first in the bufferline order? Compares it
-- with every other tracked buffer (the bufferline shows them all, Q5) through
-- compare_buffers, so a tie counts as not leftmost. Returns nil when it is,
-- or a short reason.
_G.FRG_X.leftmost = function()
	local bl = require('frogman.domains.ui').bufferline
	local cur = vim.api.nvim_get_current_buf()
	if not H.get_hash_from_buffer(cur) then return 'current buffer not tracked' end
	for _, e in ipairs(H.get_ordered_buffers()) do
		if e.buf ~= cur and not bl.compare_buffers(cur, e.buf) then
			local stem = function(b) return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ':t:r') end
			return string.format('%s not ahead of %s', stem(cur), stem(e.buf))
		end
	end
	return nil
end

-- The history view's times for the tracked buffers, as "e=7 b=6 ...",
-- newest first.
_G.FRG_X.times = function()
	local out = {}
	for _, e in ipairs(H.get_ordered_buffers()) do
		local id = H.get_handle_from_buffer(e.buf)
		table.insert(out, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(e.buf), ':t:r') .. '=' .. tostring(H.data.crux[id]))
	end
	return table.concat(out, ' ')
end
]==]

-- Load the child-side library. Call after child.setup().
X.load = function(child)
	child.lua(CHILD_LIB)
end

-- A nil returned by the child comes back as vim.NIL; turn it back into nil.
X.unnil = function(v)
	if v == vim.NIL then return nil end
	return v
end

X.hash = function(child, stem) return child.lua('return _G.FRG_X.hash(...)', { stem }) end
X.handle = function(child, stem) return X.unnil(child.lua('return _G.FRG_X.handle(...)', { stem })) end
X.maps = function(child, winid) return X.unnil(child.lua('return _G.FRG_X.maps(...)', { winid })) end
X.set = function(child, spec, winid) child.lua('_G.FRG_X.set(...)', { spec, winid }) end
X.leftmost = function(child) return X.unnil(child.lua('return _G.FRG_X.leftmost()')) end
X.times = function(child) return child.lua('return _G.FRG_X.times()') end
X.win = function(child) return child.lua('return vim.api.nvim_get_current_win()') end

-- Messages collected since the last read whose text contains `needle`.
X.messages_with = function(child, needle)
	local out = {}
	for _, m in ipairs(child.messages()) do
		if m.msg:find(needle, 1, true) then table.insert(out, m) end
	end
	return out
end

-- A small deterministic generator (Park-Miller), so walks repeat exactly.
-- Its products stay below 2^53, so plain Lua numbers hold them exactly.
-- rnd(n) gives 1..n.
X.rng = function(seed)
	local state = seed % 2147483646 + 1
	return function(n)
		state = (state * 16807) % 2147483647
		return math.floor(state / 2147483647 * n) + 1
	end
end

return X
