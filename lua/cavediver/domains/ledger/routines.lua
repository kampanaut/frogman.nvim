local data = require('cavediver.domains.ledger.data')

---Ledger domain routines: steps begin at what set them off, moves land on the step they follow
---from, and the messages a step queued are said once it closes.
local M = {}

-- How many settles a step stays open for. cavediver's own follow-ups run on vim.schedule, each
-- scheduled from the one before (an arrival's settle, the close key's deferred delete, the landing
-- after a delete): three deep at most, so their moves land on the step that set them off.
local SETTLES = 4

-- Steps kept whatever they did: an action asked for is worth seeing in the ring.
local ALWAYS = { keymap = true, load = true, save = true, restart = true, label = true }

-- Steps whose messages are said: what you did, or what happened around you. A load, a save or a
-- timer says nothing: what it closes or reopens isn't news to anyone.
local SAYS = { keymap = true, command = true, event = true }

---Now, to the microsecond.
---@return number
local function now()
	local seconds, microseconds = vim.uv.gettimeofday()
	return seconds + microseconds / 1e6
end

---A file's name as the trail shows it: its basename, or `[No Name]`.
---
---@param filehash Filehash|nil
---@return string|nil
function M.name_of(filehash)
	if filehash == nil then
		return nil
	end
	local path = require('cavediver.domains.history.data').hash_filepath_registry.filepaths[filehash]
	if path == nil then
		return nil
	end
	if path:match("^NONAME_") then
		return "[No Name]"
	end
	return vim.fs.basename(path)
end

---A buffer's name as an event names it.
---@param bufnr integer
---@return string
function M.buffer_label(bufnr)
	local name = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ""
	return name == "" and "[No Name]" or vim.fs.basename(name)
end

---A window's row as it stands, with the names of every file in it kept in `names`.
---
---@param winid integer|nil
---@param names table<Filehash, string>
---@return CavediverLedgerRow|nil
local function row_of(winid, names)
	local triquetra = winid and require('cavediver.domains.window.data').crux[winid]
	if not triquetra then
		return nil
	end
	local row = {
		c = triquetra.current_slot,
		s = triquetra.secondary_slot,
		t = triquetra.ternary_slot,
		p = vim.deepcopy(triquetra.primary_buffer or {}),
		on = triquetra.primary_enabled and true or false,
		dtm = vim.deepcopy(triquetra.displacement_ternary_map or {}),
		dsm = vim.deepcopy(triquetra.displacement_secondary_map or {}),
	}
	local function keep(filehash)
		if filehash then
			local base = filehash:gsub("%-swap$", "")
			names[base] = names[base] or M.name_of(base)
		end
	end
	keep(row.c)
	keep(row.s)
	keep(row.t)
	for _, filehash in ipairs(row.p) do
		keep(filehash)
	end
	for _, map in ipairs({ row.dtm, row.dsm }) do
		for key, value in pairs(map) do
			keep(key)
			keep(value)
		end
	end
	return row
end

---A window's slots as they stand, for a move's row: the slots, the primary queue and its switch.
---
---@param winid integer|nil
---@return CavediverLedgerRow|nil
function M.slots(winid)
	local triquetra = winid and require('cavediver.domains.window.data').crux[winid]
	if not triquetra then
		return nil
	end
	return {
		c = triquetra.current_slot,
		s = triquetra.secondary_slot,
		t = triquetra.ternary_slot,
		p = vim.deepcopy(triquetra.primary_buffer or {}),
		on = triquetra.primary_enabled and true or false,
	}
end

---A window as the trail names it: `win 2`, by its number in its tab.
---@param winid integer
---@return string
function M.window_name(winid)
	return "win " .. (vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_number(winid) or winid)
end

---@param a CavediverLedgerRow|nil
---@param b CavediverLedgerRow|nil
---@return boolean
local function same_row(a, b)
	return vim.deep_equal(a, b)
end

---@param cause string
---@param trigger string
---@param winid integer|nil
---@return CavediverLedgerStep
local function new_step(cause, trigger, winid)
	data.seq = data.seq + 1
	local step = {
		seq = data.seq,
		time = now(),
		cause = cause,
		trigger = trigger,
		win = winid,
		tab = winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_tabpage(winid) or nil,
		names = {},
		events = {},
		moves = {},
		told = {},
	}
	step.row_before = row_of(winid, step.names)
	return step
end

---Names in one line: `a`, `a and b`, `a, b and c`.
---@param names string[]
---@return string
local function joined(names)
	if #names <= 1 then
		return names[1] or ""
	end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

---The messages a step queued, one line for each kind, the names and lists of all its moves of
---that kind together.
---@param step CavediverLedgerStep
local function say(step)
	local kinds, order = {}, {}
	for _, told in ipairs(step.told) do
		local kind = kinds[told.kind]
		if kind == nil then
			kind = { names = {}, lists = {}, seen = {} }
			kinds[told.kind] = kind
			table.insert(order, told.kind)
		end
		if not kind.seen[told.name] then
			kind.seen[told.name] = true
			table.insert(kind.names, told.name)
		end
		for _, list in ipairs(told.lists) do
			if not kind.seen["\0" .. list] then
				kind.seen["\0" .. list] = true
				table.insert(kind.lists, list)
			end
		end
	end
	for _, name in ipairs(order) do
		local kind = kinds[name]
		if name == "closed" then
			vim.notify(joined(kind.names) .. " closed here and in " .. joined(kind.lists), vim.log.levels.INFO)
		elseif name == "reopened" then
			vim.notify(joined(kind.names) .. " reopened and taken off " .. joined(kind.lists), vim.log.levels.INFO)
		end
	end
end

---Put a step in the ring, in order, and in its day's trail when it made moves.
---@param step CavediverLedgerStep
local function keep(step)
	local ring = data.ring
	local i = #ring
	while i > 0 and ring[i].seq > step.seq do
		i = i - 1
	end
	table.insert(ring, i + 1, step)
	local n = math.max(require('cavediver.configs').ledger.ring or 0, 0)
	while #ring > n do
		table.remove(ring, 1)
	end
	if #step.moves > 0 then
		local day = os.date("%Y-%m-%d", math.floor(step.time))
		data.days[day] = data.days[day] or {}
		local steps = data.days[day]
		local j = #steps
		while j > 0 and steps[j].seq > step.seq do
			j = j - 1
		end
		table.insert(steps, j + 1, step)
	end
end

---Close a step: its row after is read now, it's kept when it did anything, and what it queued is
---said.
---@param step CavediverLedgerStep
local function close(step)
	if step.closed then
		return
	end
	step.closed = true
	if data.open == step then
		data.open = nil
	end
	step.row_after = row_of(step.win, step.names)
	if ALWAYS[step.cause] or step.torn or #step.moves > 0 or not same_row(step.row_before, step.row_after) then
		keep(step)
	end
	if SAYS[step.cause] then
		say(step)
	end
	step.told = {}
end

---Keep a step open for a few settles, then close it.
---@param step CavediverLedgerStep
---@param left integer
local function hold_open(step, left)
	vim.schedule(function()
		if data.open ~= step then
			return -- closed already, by the next trigger
		end
		if left > 1 then
			hold_open(step, left - 1)
		else
			close(step)
		end
	end)
end

---Begin a step at what set it off. An event while a step is open is one of its own follow-ups:
---it's listed under that step, and begins none. A save or a load isn't followed by events of its
---own: a session manager saves the outgoing session, then tears it down in the same call, and that
---teardown is a step of its own.
---
---@param cause "keymap"|"command"|"event"|"load"|"save"|"restart"|"label"
---@param trigger string What set it off, as written: `<M-f>`, `:bdelete c.txt`, `BufDelete c.txt`
---@param winid integer|nil The window it's about
---@return CavediverLedgerStep
function M.begin(cause, trigger, winid)
	local open = data.open
	if cause == "event" and open and open.cause ~= "save" and open.cause ~= "load" then
		table.insert(open.events, trigger)
		return open
	end
	if open then
		close(open)
	end
	local step = new_step(cause, trigger, winid)
	data.open = step
	hold_open(step, SETTLES)
	return step
end

---Run a call as a step of its own, a timer's tick: what it does lands on it, and it's kept only
---when it made a move. Errors go on as they came.
---
---@param cause "timer"
---@param trigger string
---@param fn function
---@param ... any fn's arguments
---@return any fn's results
function M.within(cause, trigger, fn, ...)
	local step = new_step(cause, trigger, nil)
	table.insert(data.scopes, step)
	local results = { xpcall(fn, debug.traceback, ...) }
	for i = #data.scopes, 1, -1 do
		if data.scopes[i] == step then
			table.remove(data.scopes, i)
		end
	end
	close(step)
	if not results[1] then
		error(results[2], 0)
	end
	return unpack(results, 2, table.maxn(results))
end

---The step a move lands on: the call's own, the one open, or else a new one.
---@return CavediverLedgerStep
local function current()
	local scope = data.scopes[#data.scopes]
	if scope then
		return scope
	end
	if data.open then
		return data.open
	end
	return M.begin("event", "—", vim.api.nvim_get_current_win())
end

---Record a move on the step it follows from.
---
---@param kind string closed, reopened, forgotten, repair, …
---@param fields table The move's other fields (CavediverLedgerMove)
---@return CavediverLedgerMove
function M.move(kind, fields)
	local move = { kind = kind }
	for key, value in pairs(fields or {}) do
		move[key] = value
	end
	local step = current()
	-- the names of the files it names, as they are now
	local function name(filehash)
		if type(filehash) == "string" and #filehash == 16 and filehash:match("^%x+$") then
			step.names[filehash] = step.names[filehash] or M.name_of(filehash)
		end
	end
	name(move.subject)
	for _, row in ipairs(move.row and { move.row.before, move.row.after } or {}) do
		name(row.c)
		name(row.s)
		name(row.t)
		for _, filehash in ipairs(row.p or {}) do
			name(filehash)
		end
	end
	if move.note then
		name(move.note.before)
		name(move.note.after)
	end
	table.insert(step.moves, move)
	return move
end

---A note cavediver changed by itself: rewritten to an older one, or dropped.
---
---@param map "ternary"|"secondary" The map it's on
---@param owner Filehash The buffer whose note it is
---@param before Filehash|nil What it named
---@param after Filehash|nil What it names now
---@param by string What changed it: "stale" (keep the older one), "guard" (Q6), "navigation", "no path"
function M.note(map, owner, before, after, by)
	if before == after then
		return
	end
	M.move(after and "rewritten" or "note_dropped", {
		subject = owner, name = M.name_of(owner), note = { map = map, before = before, after = after }, by = by,
	})
end

---A window's slots that cavediver moved by itself, from a row taken before the change.
---
---@param kind string repointed, landed, undone, cleared
---@param winid integer
---@param before CavediverLedgerRow|nil
---@param fields table|nil The move's other fields
function M.slots_moved(kind, winid, before, fields)
	local move = { subject = tostring(winid), name = M.window_name(winid), row = { before = before or {}, after = M.slots(winid) or {} } }
	for key, value in pairs(fields or {}) do
		move[key] = value
	end
	M.move(kind, move)
end

---The step still open, if any.
---@return CavediverLedgerStep|nil
function M.open_step()
	return data.open
end

---Queue a message on the step it follows from, said once the step closes, with the others of
---its kind.
---
---@param kind "closed"|"reopened"
---@param name string The file's name
---@param lists string[] The other lists, by name
function M.tell(kind, name, lists)
	table.insert(current().told, { kind = kind, name = name, lists = lists })
end

---A whole-editor load replaces what its batch did: the session manager's teardown closed every
---buffer with events on. The step still open loses its moves and its messages, unless it's a
---session's own step (a save before the switch, `:restart`'s reload), which the teardown isn't.
function M.drop_batch()
	local open = data.open
	if open and (open.cause == "event" or open.cause == "command" or open.cause == "keymap") then
		open.moves = {}
		open.told = {}
		open.torn = true
		close(open)
	end
end

---The ring's steps, oldest first.
---@return CavediverLedgerStep[]
function M.steps()
	return data.ring
end

---A day's steps that made moves, oldest first.
---
---@param day string|nil `YYYY-MM-DD`; today when nil
---@return CavediverLedgerStep[]
function M.trail(day)
	return data.days[day or os.date("%Y-%m-%d")] or {}
end

return M
