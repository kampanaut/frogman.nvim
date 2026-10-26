-- Extra helpers for the slot-key, primary-key and restore tests.
-- They work on top of tests/helpers.lua's child (Helpers.new_child()).
--
-- Notes are named the way the shared helpers name them: a file's stem, with
-- '-swap' for a swap note ('b', 'b-swap'). Maps are 'dtm' (restore ternary)
-- and 'dsm' (restore secondary).

local K = {}

-- Code shared by the child-side helpers: name(hash) and the window's triquetra.
local PRELUDE = [==[
local H = require('frogman.domains.history')
local W = require('frogman.domains.window')
local function name(hash)
	if hash == nil then return nil end
	local base = hash:gsub('%-swap$', '')
	local path = H.get_filepath_from_hash(base)
	local n = path and vim.fn.fnamemodify(path, ':t:r') or ('?' .. base:sub(1, 6))
	if hash:match('%-swap$') then n = n .. '-swap' end
	return n
end
local function hash(stem)
	local buf = vim.fn.bufnr(stem .. '.txt')
	if buf ~= -1 and H.get_hash_from_buffer(buf) then return H.get_hash_from_buffer(buf) end
	for h, path in pairs(H.data.hash_filepath_registry.filepaths) do
		if vim.fn.fnamemodify(path, ':t:r') == stem then return h end
	end
	return nil
end
local function map_of(t, which)
	return which == 'dtm' and t.displacement_ternary_map or t.displacement_secondary_map
end
]==]

-- The stem one note names, or nil: K.note(child, 'dtm', 'b-swap').
K.note = function(child, which, key)
	local v = child.lua(PRELUDE .. [[
		local which, key = ...
		local t = W.data.crux[vim.api.nvim_get_current_win()]
		if not t then return vim.NIL end
		for k, v in pairs(map_of(t, which)) do
			if name(k) == key then return name(v) end
		end
		return vim.NIL
	]], { which, key })
	if v == vim.NIL then return nil end
	return v
end

-- The notes kept under the given stems (plain and swap), in the shared
-- helpers' format: K.notes_for(child, { 'a', 'b' }) → 'dtm{a>b b>a} dsm{}'.
K.notes_for = function(child, stems)
	return child.lua(PRELUDE .. [[
		local stems = ...
		local want = {}
		for _, s in ipairs(stems) do want[s] = true; want[s .. '-swap'] = true end
		local t = W.data.crux[vim.api.nvim_get_current_win()]
		if not t then return 'no triquetra' end
		local function fmt(m)
			local out = {}
			for k, v in pairs(m) do
				if want[name(k)] then table.insert(out, name(k) .. '>' .. name(v)) end
			end
			table.sort(out)
			return '{' .. table.concat(out, ' ') .. '}'
		end
		return 'dtm' .. fmt(t.displacement_ternary_map) .. ' dsm' .. fmt(t.displacement_secondary_map)
	]], { stems })
end

-- Only the secondary map, in the shared helpers' format: 'dsm{b>a c-swap>b}'.
K.dsm = function(child)
	return child.notes():match('(dsm%b{})')
end

-- Set one note directly. The value is a stem, or a raw hash when raw is true.
K.set_note = function(child, which, key, value, raw)
	child.lua(PRELUDE .. [[
		local which, key, value, raw = ...
		local t = W.data.crux[vim.api.nvim_get_current_win()]
		local base, swap = key:match('^(.-)(%-swap)$')
		local k = base and (hash(base) .. swap) or hash(key)
		map_of(t, which)[k] = raw and value or hash(value)
	]], { which, key, value, raw or false })
end

-- The hash frogman holds for a stem.
K.hash = function(child, stem)
	return child.lua(PRELUDE .. 'return hash(...)', { stem })
end

-- Whether current and secondary (or ternary) hold the same buffer.
K.duplicate = function(child)
	return child.lua([[
		local t = require('frogman.domains.window').data.crux[vim.api.nvim_get_current_win()]
		if not t then return false end
		local c, s, r = t.current_slot, t.secondary_slot, t.ternary_slot
		return (s ~= nil and s == c) or (r ~= nil and r == c) or (s ~= nil and s == r)
	]])
end

K.nav = function(child)
	return child.lua('return require("frogman").get_navigation_state()')
end

-- Run some Lua in the child and press a key in the same call, so no timer
-- tick (the UI's cleanup) can run in between. Returns ok, err.
K.press_after = function(child, code, lhs)
	local res = child.lua('(function() ' .. code .. ' end)(); return { _G.FRG_TEST.press(...) }', { lhs })
	child.settle()
	return res[1], res[2]
end

-- Delete a project file on disk (it stays open if its buffer is).
K.rm_code = function(stem)
	return string.format("os.remove(_G.FRG_TEST.root .. '/%s.txt')", stem)
end

-- Press a cycle key until the window shows the stem, then stop (no pick).
K.cycle_to = function(child, stem, key)
	key = key or '<M-m>'
	for _ = 1, 12 do
		child.steps({ key })
		if child.shown() == stem then return end
	end
	error('cycling never reached ' .. stem, 2)
end

-- Messages since the last read, as plain strings.
K.messages = function(child)
	local out = {}
	for _, m in ipairs(child.messages()) do
		table.insert(out, { msg = m.msg, level = m.level })
	end
	return out
end

-- Whether any message contains the text (plain match).
K.has = function(msgs, text)
	for _, m in ipairs(msgs) do
		if m.msg:find(text, 1, true) then return true end
	end
	return false
end

-- Messages at WARN or above.
K.warnings = function(msgs)
	local out = {}
	for _, m in ipairs(msgs) do
		if (m.level or 0) >= vim.log.levels.WARN then table.insert(out, m.msg) end
	end
	return out
end

-- Hook failures, which the engine catches and only reports through notify.
K.hook_failures = function(msgs)
	local out = {}
	for _, m in ipairs(msgs) do
		if m.msg:match("^Hook '") then table.insert(out, m.msg) end
	end
	return out
end

-- A message with hashes and paths taken out, so two runs can be compared.
K.plain = function(msg)
	return (msg:gsub('%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x', '<hash>'):gsub('/%S+', '<path>'))
end

-- Everything a slot key can change, for comparing two runs.
K.state = function(child)
	local msgs = {}
	for _, m in ipairs(child.messages()) do table.insert(msgs, K.plain(m.msg)) end
	return {
		slots = child.slots(),
		notes = child.notes(),
		shown = child.shown(),
		primary = child.primary(),
		closed = child.closed(),
		messages = msgs,
	}
end

-- I23 over random walks (T190). One walk runs inside the child, from a fresh
-- setup: `nkeys` actions drawn with a Park-Miller generator from `seed`.
-- After every action, each window's current buffer is checked: the note a
-- restore would read (the swap note when set and not the slot's occupant,
-- else the plain note) never names the occupant of the slot it restores into
-- (the ternary for dtm, the secondary for dsm). Stops at the first break.
-- Returns { steps, errors, hook_failures, actions, brk = nil | {...} }.
local WALK = [==[
local seed, nkeys, multi = ...
local H = require('frogman.domains.history')
local W = require('frogman.domains.window')
local state = seed % 2147483647
if state <= 0 then state = state + 2147483646 end
local function rnd(n)
	state = (state * 16807) % 2147483647
	return (state % n) + 1
end
local function name(hash)
	if hash == nil then return '-' end
	local path = H.get_filepath_from_hash(hash)
	return path and vim.fn.fnamemodify(path, ':t:r') or ('?' .. hash:sub(1, 6))
end

local actions = {
	':e a', ':e b', ':e c', ':e d', ':e e',
	'<M-f>', '<M-S-f>', '<M-;><M-r>', '<M-;><M-t>', 'pick', '<M-;><M-c>', '<M-;><M-f>',
}
if multi then
	table.insert(actions, ':vsplit')
	table.insert(actions, '<C-w>w')
end

local res = { steps = 0, errors = 0, hook_failures = 0, actions = {} }

local function press(lhs)
	local ok, err = _G.FRG_TEST.press(lhs)
	if not ok then res.errors = res.errors + 1 end
	return ok, err
end

local function run(a)
	if a:sub(1, 3) == ':e ' then
		local ok = pcall(vim.cmd, 'edit ' .. a:sub(4) .. '.txt')
		if not ok then res.errors = res.errors + 1 end
		return a
	elseif a == ':vsplit' then
		if #vim.api.nvim_tabpage_list_wins(0) < 3 then vim.cmd('vsplit') end
		return a
	elseif a == '<C-w>w' then
		vim.cmd('wincmd w')
		return a
	elseif a == 'pick' then
		local key = rnd(2) == 1 and '<M-n>' or '<M-m>'
		local n = rnd(3)
		for _ = 1, n do
			press(key)
			vim.wait(10)
		end
		press('<M-v>')
		return string.format('%s x%d <M-v>', key, n)
	else
		press(a)
		return a
	end
end

local function check()
	for i, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local t = W.data.crux[win]
		if t and t.current_slot then
			local x = t.current_slot
			for _, m in ipairs({
				{ 'dtm', t.displacement_ternary_map, t.ternary_slot },
				{ 'dsm', t.displacement_secondary_map, t.secondary_slot },
			}) do
				local which, map, occupant = m[1], m[2], m[3]
				local note = map[x .. '-swap']
				if note == nil or note == occupant then note = map[x] end
				if note ~= nil and note == occupant then
					return {
						window = i,
						map = which,
						current = name(x),
						occupant = name(occupant),
						slots = _G.FRG_TEST.slots(win),
						notes = _G.FRG_TEST.notes(win),
					}
				end
			end
		end
	end
end

for _ = 1, nkeys do
	_G.FRG_NOTES = {}
	local label = run(actions[rnd(#actions)])
	vim.wait(10) -- the editor settles between keys, as when they're typed
	table.insert(res.actions, label)
	res.steps = res.steps + 1
	-- once the editor has settled, nothing is left on the settle queue
	local queued = require('frogman.settle').pending()
	if #queued > 0 then
		res.queued = table.concat(queued, ', ')
		return res
	end
	for _, n in ipairs(_G.FRG_NOTES) do
		if n.msg:match("^Hook '") then res.hook_failures = res.hook_failures + 1 end
	end
	local brk = check()
	if brk then
		res.brk = brk
		return res
	end
end
_G.FRG_NOTES = {}
return res
]==]

K.walk = function(child, seed, nkeys, multi)
	local dumps = child.dump_files()
	local res = child.lua(WALK, { seed, nkeys, multi or false })
	local fired = child.dumped_since(dumps)
	if fired then
		error(string.format('walk (seed %d) dumped: %s\n  keys: %s', seed, fired, table.concat(res.actions, ', ')), 0)
	end
	if res.queued then
		error(string.format('walk (seed %d) left the settle queue not empty once settled: %s\n  keys: %s', seed, res.queued,
			table.concat(res.actions, ', ')), 0)
	end
	return res
end

return K
