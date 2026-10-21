-- Extra helpers for the cleanup, UI, setup, invariant, session and doc tests.
-- They sit on top of tests/helpers.lua and are candidates for it.

local Misc = {}

-- Error level of a notification, as vim.log.levels.ERROR.
Misc.ERROR = 4

-- The notifications at ERROR level since the last read.
Misc.errors = function(child)
	local out = {}
	for _, m in ipairs(child.messages()) do
		if m.level == Misc.ERROR then table.insert(out, m.msg) end
	end
	return out
end

-- Sessions ------------------------------------------------------------------

-- The shared setup from tests/helpers.lua, with two more options: `root`, the
-- project to start in, and `session_dir`, cavediver's session directory. With
-- neither it's child.setup(). A candidate option for the shared child.setup.
local SETUP = table.concat(vim.fn.readfile('tests/helpers.lua'), '\n'):match('local CHILD_SETUP = %[==%[\n(.-)%]==%]')
local n_root, n_dir
SETUP, n_root = SETUP:gsub('local root = vim%.fn%.tempname%(%)', 'local root = opts.root or vim.fn.tempname()')
SETUP, n_dir = SETUP:gsub("session_dir = root %.%. '/state/sessions/',",
	"session_dir = opts.session_dir or (root .. '/state/sessions/'),")
assert(n_root == 1 and n_dir == 1, 'tests/helpers.lua changed: CHILD_SETUP no longer matches')

-- Restart the child with cavediver set up. opts: root, session_dir, plus
-- child.setup's (history_view, no_cokeline).
Misc.start = function(child, opts)
	child.restart({ '-u', 'scripts/minimal_init.lua' })
	child.lua(SETUP, { opts or {} })
end

-- A project made by the test runner itself, so it outlives the children: one
-- child saves, a fresh child loads. Files a..f, t, x.
Misc.make_project = function()
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, 'p')
	for _, f in ipairs({ 'a', 'b', 'c', 'd', 'e', 'f', 't', 'x' }) do
		vim.fn.writefile({ f }, root .. '/' .. f .. '.txt')
	end
	return root
end

-- A session directory made by the test runner, kept apart from the projects.
Misc.make_session_dir = function()
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, 'p')
	return dir .. '/'
end

-- The regular files in a directory (a session file, whatever its format);
-- none when the directory doesn't exist.
Misc.files_in = function(dir)
	local out = {}
	if vim.fn.isdirectory(dir) == 0 then return out end
	for _, name in ipairs(vim.fn.readdir(dir)) do
		if vim.fn.isdirectory(dir .. '/' .. name) == 0 then table.insert(out, name) end
	end
	return out
end

-- Bring buffers back the way a session manager does: `loaded` are added,
-- loaded and listed, `unloaded` are added with `noautocmd badd`, and `shown`
-- is edited in the current window with `noautocmd`. File letters as in a..f.
Misc.restore = function(child, loaded, shown, unloaded)
	child.lua([[
		local loaded, shown, unloaded = ...
		for _, f in ipairs(loaded) do
			local b = vim.fn.bufadd(f .. '.txt')
			vim.fn.bufload(b)
			vim.bo[b].buflisted = true
		end
		for _, f in ipairs(unloaded) do
			vim.cmd('noautocmd badd ' .. f .. '.txt')
		end
		if shown then
			vim.cmd('noautocmd edit ' .. shown .. '.txt')
		end
	]], { loaded or {}, shown, unloaded or {} })
end

-- save_session / load_session with the cwd, as the README wires them.
-- Returns { ok, err }.
Misc.save = function(child)
	return child.lua('return { pcall(require("cavediver").save_session, vim.fn.getcwd()) }')
end
Misc.load = function(child)
	return child.lua('return { pcall(require("cavediver").load_session, vim.fn.getcwd()) }')
end

-- The regular files in the child's session directory.
Misc.session_files = function(child)
	return Misc.files_in(child.lua([[return require('cavediver.configs').session_dir]]))
end

-- Random walks ----------------------------------------------------------------

-- Code that runs inside the child: the walk's actions, the invariant checks,
-- and the walk itself. A walk is deterministic for its seed.
local WALKER = [==[
local H = require('cavediver.domains.history')
local W = require('cavediver.domains.window')
local N = require('cavediver.domains.navigation')
local raw_cmd = vim.cmd
local root = _G.CDV_TEST.root
local newfile = 0

local function stem(buf)
	if not vim.api.nvim_buf_is_valid(buf) then return 'buffer ' .. buf .. ' (gone)' end
	local n = vim.api.nvim_buf_get_name(buf)
	if n == '' then return 'NONAME_' .. buf end
	return vim.fn.fnamemodify(n, ':t:r')
end

local function press(lhs) return _G.CDV_TEST.press(lhs) end

local actions = {}
for _, f in ipairs({ 'a', 'b', 'c', 'd', 'e' }) do
	actions['e ' .. f] = function() raw_cmd('edit ' .. f .. '.txt') end
end
for _, k in ipairs({ '<M-f>', '<M-S-f>', '<M-;><M-r>', '<M-;><M-t>', '<M-n>', '<M-m>', '<M-v>',
	'<M-;><M-c>', '<M-;><M-f>', '<M-;><M-x>', '<M-.>', '<M-S-w>', '<M-,>' }) do
	actions[k] = function()
		local ok, err = press(k)
		if not ok then error(err, 0) end
	end
end
-- Cycling picks: cycle one step right or left, or two right, then <M-v>.
local function keys(list)
	return function()
		for _, k in ipairs(list) do
			local ok, err = press(k)
			if not ok then error(err, 0) end
		end
	end
end
actions['X1'] = keys({ '<M-m>', '<M-v>' })
actions['X2'] = keys({ '<M-n>', '<M-v>' })
actions['X3'] = keys({ '<M-m>', '<M-m>', '<M-v>' })
actions['vsplit'] = function() if #vim.api.nvim_tabpage_list_wins(0) < 3 then raw_cmd('vsplit') end end
actions['wincmd w'] = function() raw_cmd('wincmd w') end
-- The previous window, or the next one when there's none.
local function wincmd_p()
	local before = vim.api.nvim_get_current_win()
	pcall(raw_cmd, 'wincmd p')
	if vim.api.nvim_get_current_win() == before then raw_cmd('wincmd w') end
end
actions['wincmd p'] = wincmd_p
-- A cycle left open across a window jump.
actions['Y1'] = function() press('<M-m>'); wincmd_p() end
actions['Y2'] = function() press('<M-n>'); wincmd_p() end
actions['close'] = function() if #vim.api.nvim_tabpage_list_wins(0) > 1 then raw_cmd('close') end end
actions['enew'] = function() raw_cmd('enew') end
actions['enew+text'] = function()
	raw_cmd('enew')
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'scratch' })
end
-- A file that isn't on disk yet, with a typed line.
actions['new file'] = function()
	newfile = newfile + 1
	raw_cmd('edit n' .. newfile .. '.txt')
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'typed' })
end
-- Delete the next of the five files on disk (a, b, ... in turn), or write it
-- back if it's gone. Only inside the child's temporary project.
local rm_turn = 0
actions['rm/mk'] = function()
	rm_turn = rm_turn % 5 + 1
	local path = root .. '/' .. ({ 'a', 'b', 'c', 'd', 'e' })[rm_turn] .. '.txt'
	if vim.fn.filereadable(path) == 1 then os.remove(path) else vim.fn.writefile({ 'back' }, path) end
end

local slot_keys = {
	['<M-f>'] = true, ['<M-S-f>'] = true, ['<M-;><M-r>'] = true, ['<M-;><M-t>'] = true,
	['<M-;><M-f>'] = true, ['<M-;><M-c>'] = true, ['<M-;><M-x>'] = true,
	['<M-n>'] = true, ['<M-m>'] = true, ['<M-v>'] = true, X1 = true, X2 = true, X3 = true,
}
local cycling_keys = { ['<M-n>'] = true, ['<M-m>'] = true, ['<M-v>'] = true, X1 = true, X2 = true, X3 = true }

local function name(hash)
	if hash == nil then return '-' end
	local p = H.get_filepath_from_hash((hash:gsub('%-swap$', '')))
	return p and vim.fn.fnamemodify(p, ':t:r') or ('?' .. hash:sub(1, 6))
end

-- Each check: pre() takes a snapshot before the action, post(snap, action, ok, err)
-- returns a description of the break, or nil.
local checks = {}

-- I1: current, secondary and ternary are three different hashes, or empty.
checks.I1 = { post = function()
	for winid, t in pairs(W.data.crux) do
		local c, s, tt = t.current_slot, t.secondary_slot, t.ternary_slot
		if (s and s == c) or (tt and tt == c) or (s and tt and s == tt) then
			return string.format('window %d holds ⦉%s⦊ [%s] ⟦%s⟧', winid, name(tt), name(c), name(s))
		end
	end
end }

-- I2: every hash held anywhere has a path.
checks.I2 = { post = function()
	local function known(h)
		return h == nil or H.get_filepath_from_hash((h:gsub('%-swap$', ''))) ~= nil
	end
	for winid, t in pairs(W.data.crux) do
		for _, slot in ipairs({ 'current_slot', 'secondary_slot', 'ternary_slot' }) do
			if not known(t[slot]) then return string.format('window %d %s has no path', winid, slot) end
		end
		for _, h in ipairs(t.primary_buffer or {}) do
			if not known(h) then return string.format('window %d primary entry has no path', winid) end
		end
		for mapname, m in pairs({ dtm = t.displacement_ternary_map, dsm = t.displacement_secondary_map }) do
			for k, v in pairs(m or {}) do
				if not known(k) or not known(v) then
					return string.format('window %d %s entry %s>%s has no path', winid, mapname, name(k), name(v))
				end
			end
		end
	end
	for h in pairs(H.data.crux) do if not known(h) then return 'history view entry has no path' end end
	for h in pairs(H.data.crux_internals.global) do if not known(h) then return 'global history entry has no path' end end
	for winid, hist in pairs(H.data.crux_internals.window) do
		for h in pairs(hist) do
			if not known(h) then return string.format('window %d history entry has no path', winid) end
		end
	end
	for _, h in ipairs(H.data.closed_buffers) do if not known(h) then return 'closed stack entry has no path' end end
end }

-- I3: every triquetra has its window's history entry.
checks.I3 = { post = function()
	for winid in pairs(W.data.crux) do
		if H.data.crux_internals.window[winid] == nil then
			return string.format('window %d has a triquetra and no history entry', winid)
		end
	end
end }

-- I11: after a non-cycling action, ordered.crux is newest first and holds only
-- registered, open buffers.
checks.I11 = { post = function(_, action)
	if cycling_keys[action] or N.sm:state() ~= 'normal' then return nil end
	local prev
	for i, e in ipairs(H.data.ordered.crux) do
		if not vim.api.nvim_buf_is_valid(e.buf) or not vim.api.nvim_buf_is_loaded(e.buf) then
			return string.format('entry %d (buffer %d) is not open', i, e.buf)
		end
		if H.get_hash_from_buffer(e.buf) == nil then
			return string.format('entry %d (%s) is not registered', i, stem(e.buf))
		end
		if prev and not (prev > e.time) then
			return string.format('entry %d (%s) is not older than the one before it', i, stem(e.buf))
		end
		prev = e.time
	end
end }

-- I12: no buffer with unsaved changes is wiped by cavediver. The walk runs its
-- own commands through the original vim.cmd, so only cavediver's calls are
-- checked. No Name buffers are left out: closing one caches its text (T83).
_G.CDV_WIPED = {}
local function check_wipe(buf)
	if buf and buf ~= 0 and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified
		and vim.api.nvim_buf_get_name(buf) ~= '' then
		table.insert(_G.CDV_WIPED, stem(buf))
	end
end
checks.I12 = {
	install = function()
		vim.cmd = setmetatable({}, {
			__call = function(_, c, ...)
				if type(c) == 'string' then
					local n = c:match('^%s*bw%a*!?%s+(%d+)') or c:match('^%s*bd%a*!?%s+(%d+)')
					if n then check_wipe(tonumber(n)) end
				end
				return raw_cmd(c, ...)
			end,
			__index = raw_cmd,
		})
		local raw_del = vim.api.nvim_buf_delete
		vim.api.nvim_buf_delete = function(buf, opts)
			check_wipe(buf == 0 and vim.api.nvim_get_current_buf() or buf)
			return raw_del(buf, opts)
		end
	end,
	post = function()
		if #_G.CDV_WIPED > 0 then
			return 'wiped with unsaved changes: ' .. table.concat(_G.CDV_WIPED, ',')
		end
	end,
}

-- I13: a slot action changes no window but its own.
checks.I13 = {
	pre = function()
		local cur = vim.api.nvim_get_current_win()
		local snap = {}
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			if w ~= cur and vim.api.nvim_win_get_config(w).relative == '' then
				snap[w] = vim.api.nvim_win_get_buf(w)
			end
		end
		return snap
	end,
	post = function(snap, action)
		if not slot_keys[action] then return nil end
		for w, buf in pairs(snap) do
			if not vim.api.nvim_win_is_valid(w) then
				return string.format('window %d (on %s) was closed', w, stem(buf))
			end
			local now = vim.api.nvim_win_get_buf(w)
			if now ~= buf then
				return string.format('window %d went from %s to %s', w, stem(buf), stem(now))
			end
		end
	end,
}

-- T154: no restore throws "Remembered … is the same as current …".
checks.restores = { post = function(_, action, ok, err)
	if (action == '<M-;><M-r>' or action == '<M-;><M-t>') and not ok
		and tostring(err):find('Remembered %a+ is the same as current') then
		return action .. ' threw: ' .. tostring(err):gsub('^.-: ', '')
	end
end }

-- One action and its check.
local function run_step(c, a)
	local snap = c.pre and c.pre() or nil
	local ok, err = pcall(actions[a])
	vim.wait(10)
	return c.post(snap, a, ok, err)
end

-- A fixed route, checked after every action; for replaying a walk's report.
_G.CDV_ROUTE = function(names, check)
	local c = checks[check]
	if c.install then c.install() end
	for i, a in ipairs(names) do
		local broke = run_step(c, a)
		if broke then return { step = i, detail = broke } end
	end
	return nil
end

_G.CDV_WALK = function(seed, nsteps, names, check)
	local c = checks[check]
	if c.install then c.install() end
	-- Park-Miller's generator: exact in doubles, the same walk on every run.
	local state = seed % 2147483646 + 1
	local function rand(k)
		state = (state * 16807) % 2147483647
		return state % k + 1
	end
	local trail = { 'e a' }
	raw_cmd('edit a.txt')
	vim.wait(10)
	for step = 1, nsteps do
		local a = names[rand(#names)]
		table.insert(trail, a)
		local broke = run_step(c, a)
		if broke then
			return { step = step, detail = broke, trail = table.concat(trail, ', ') }
		end
	end
	return nil
end
]==]

-- Run `walks` deterministic random walks of `steps` actions each, every walk in
-- a fresh child, and return the first break as a message, or nil.
-- opts: seed, walks, steps, actions (names from the walker), check
-- (I1, I2, I3, I11, I12, I13, restores), setup (child.setup's opts).
Misc.walks = function(child, opts)
	for w = 1, opts.walks do
		child.setup(opts.setup)
		child.lua(WALKER)
		local seed = opts.seed * 1000 + w
		local broke = child.lua('return _G.CDV_WALK(...)', { seed, opts.steps, opts.actions, opts.check })
		if broke ~= vim.NIL and broke ~= nil then
			return string.format('%s broke in walk %d (seed %d), step %d: %s\n  route: %s',
				opts.check, w, seed, broke.step, broke.detail, broke.trail)
		end
	end
	return nil
end

-- Run a fixed list of walker actions in a fresh child, checking after each;
-- returns the break as { step, detail }, or nil. For replaying a reported route.
Misc.route = function(child, names, check, setup)
	child.setup(setup)
	child.lua(WALKER)
	local broke = child.lua('return _G.CDV_ROUTE(...)', { names, check })
	if broke == vim.NIL then return nil end
	return broke
end

-- Doc checks ------------------------------------------------------------------

-- A file of the repository as one string.
Misc.read = function(path)
	return table.concat(vim.fn.readfile(path), '\n')
end

-- Whether `text` contains `piece`, taken literally.
Misc.has = function(text, piece)
	return text:find(piece, 1, true) ~= nil
end

return Misc
