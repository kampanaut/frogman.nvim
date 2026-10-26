-- Extra helpers for the negative cases (tests/test_negative.lua). They sit on
-- top of tests/helpers.lua's child and are candidates for it.

local Neg = {}

-- The shared child setup, with one more option: no_harpoon = true leaves the
-- harpoon stub out, so require('harpoon') fails as it would with harpoon not
-- installed. Otherwise it's child.setup(opts).
local SETUP = table.concat(vim.fn.readfile('tests/helpers.lua'), '\n'):match('local CHILD_SETUP = %[==%[\n(.-)%]==%]')
local n
SETUP, n = SETUP:gsub("(package%.preload%['harpoon'%] = function%(%)\n.-\nend\n)", 'if not opts.no_harpoon then\n%1end\n', 1)
assert(n == 1, 'tests/helpers.lua changed: the harpoon stub no longer matches')

Neg.start = function(child, opts)
	child.restart({ '-u', 'scripts/minimal_init.lua' })
	child.lua(SETUP, { opts or {} })
end

-- Everything a test may want to compare before and after something that
-- shouldn't change cavediver's state, for the current window.
Neg.snapshot = function(child, winid)
	return child.lua([[
		local w = ...
		local T = _G.CDV_TEST
		return {
			slots = T.slots(w), notes = T.notes(w), primary = T.primary(w),
			closed = T.closed(), ordered = T.ordered(), shown = T.shown(w),
		}
	]], { winid })
end

-- I23 for one window's current buffer: the note a restore would read (the
-- swap note when it's set and isn't the slot's occupant, else the plain note)
-- never names the occupant of the slot it restores into. Returns nil when it
-- holds, or which map breaks it.
Neg.i23 = function(child, winid)
	local v = child.lua([[
		local t = require('frogman.domains.window').data.crux[... or vim.api.nvim_get_current_win()]
		if not t then return 'no triquetra' end
		local x = t.current_slot
		for _, m in ipairs({
			{ 'dtm', t.displacement_ternary_map, t.ternary_slot },
			{ 'dsm', t.displacement_secondary_map, t.secondary_slot },
		}) do
			local note = m[2][x .. '-swap']
			if note == nil or note == m[3] then note = m[2][x] end
			if note ~= nil and note == m[3] then return m[1] end
		end
		return vim.NIL
	]], { winid })
	if v == vim.NIL then return nil end
	return v
end

-- Whether a hash is in the current, secondary or ternary slot of a window
-- (default: the current one).
Neg.in_slots = function(child, hash, winid)
	return child.lua([[
		local h, w = ...
		local t = require('frogman.domains.window').data.crux[w or vim.api.nvim_get_current_win()]
		return t ~= nil and (t.current_slot == h or t.secondary_slot == h or t.ternary_slot == h)
	]], { hash, winid })
end

-- Gaps in a window's primary queue: indexes up to its highest one that hold nil.
Neg.queue_holes = function(child, winid)
	return child.lua([[
		local q = require('frogman.domains.window').data.crux[...].primary_buffer
		local holes = 0
		for i = 1, table.maxn(q) do if q[i] == nil then holes = holes + 1 end end
		return holes
	]], { winid })
end

-- Active timers that repeat (cavediver's UI refresh and cleanup are two).
Neg.repeating_timers = function(child)
	return child.lua([[
		local n = 0
		vim.uv.walk(function(h)
			if h:get_type() == 'timer' and h:is_active() and h:get_repeat() > 0 then n = n + 1 end
		end)
		return n
	]])
end

-- Notes naming their own buffer, over seeded random walks. One walk runs in
-- the child from a fresh setup: `nkeys` actions drawn with a Park-Miller
-- generator from `seed`, the same mix as T190's walks. After every action,
-- every window's maps are checked for an entry X>X or X-swap>X. Stops at the
-- first one. Returns { steps, actions, brk = nil | { window, entry, slots, notes } }.
local SELF_WALK = [==[
local seed, nkeys, multi = ...
local H = require('frogman.domains.history')
local W = require('frogman.domains.window')
local state = seed % 2147483647
if state <= 0 then state = state + 2147483646 end
local function rnd(k)
	state = (state * 16807) % 2147483647
	return (state % k) + 1
end
local function name(hash)
	if hash == nil then return '-' end
	local path = H.get_filepath_from_hash((hash:gsub('%-swap$', '')))
	local n = path and vim.fn.fnamemodify(path, ':t:r') or ('?' .. hash:sub(1, 6))
	if hash:match('%-swap$') then n = n .. '-swap' end
	return n
end

local actions = {
	':e a', ':e b', ':e c', ':e d', ':e e',
	'<M-f>', '<M-S-f>', '<M-;><M-r>', '<M-;><M-t>', 'pick', '<M-;><M-c>', '<M-;><M-f>',
}
if multi then
	table.insert(actions, ':vsplit')
	table.insert(actions, '<C-w>w')
end

local res = { steps = 0, actions = {} }
local press = _G.CDV_TEST.press

local function run(a)
	if a:sub(1, 3) == ':e ' then
		pcall(vim.cmd, 'edit ' .. a:sub(4) .. '.txt')
		return a
	elseif a == ':vsplit' then
		if #vim.api.nvim_tabpage_list_wins(0) < 3 then vim.cmd('vsplit') end
		return a
	elseif a == '<C-w>w' then
		vim.cmd('wincmd w')
		return a
	elseif a == 'pick' then
		local key = rnd(2) == 1 and '<M-n>' or '<M-m>'
		local k = rnd(3)
		for _ = 1, k do press(key) end
		press('<M-v>')
		return string.format('%s x%d <M-v>', key, k)
	end
	press(a)
	return a
end

local function check()
	for i, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local t = W.data.crux[win]
		if t then
			for which, map in pairs({ dtm = t.displacement_ternary_map, dsm = t.displacement_secondary_map }) do
				for k, v in pairs(map or {}) do
					if (k:gsub('%-swap$', '')) == v then
						return {
							window = i,
							entry = which .. '{' .. name(k) .. '>' .. name(v) .. '}',
							slots = _G.CDV_TEST.slots(win),
							notes = _G.CDV_TEST.notes(win),
						}
					end
				end
			end
		end
	end
end

for _ = 1, nkeys do
	table.insert(res.actions, run(actions[rnd(#actions)]))
	res.steps = res.steps + 1
	local brk = check()
	if brk then
		res.brk = brk
		break
	end
end
_G.CDV_NOTES = {}
return res
]==]

Neg.self_walk = function(child, seed, nkeys, multi)
	local dumps = child.dump_files()
	local res = child.lua(SELF_WALK, { seed, nkeys, multi or false })
	-- its keys come back to back, so the queue is checked once, after the editor settles at the end
	child.settle(50)
	local queued = child.lua('return require("frogman.settle").pending()')
	if #queued > 0 then
		error(string.format('walk (seed %d) left the settle queue not empty once settled: %s\n  keys: %s', seed,
			table.concat(queued, ', '), table.concat(res.actions, ', ')), 0)
	end
	local fired = child.dumped_since(dumps)
	if fired then
		error(string.format('walk (seed %d) dumped: %s\n  keys: %s', seed, fired, table.concat(res.actions, ', ')), 0)
	end
	return res
end

return Neg
