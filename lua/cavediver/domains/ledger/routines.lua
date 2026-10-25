local data = require('cavediver.domains.ledger.data')

---Ledger domain core routines for recording steps and moves.
---
---This module begins a step at whatever set it off, lands each move cavediver makes on the
---step it follows from, and says the messages a step queued once it closes. A kept step goes
---in the ring and, when it made moves, in its day's trail.
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

---Get the time now, to the microsecond.
---@return number seconds Seconds since the epoch
local function now()
	local seconds, microseconds = vim.uv.gettimeofday()
	return seconds + microseconds / 1e6
end

---Get a file's name as the trail shows it.
---
---Returns its basename, or `[No Name]` for a No Name buffer.
---
---@param filehash Filehash|nil The file's hash
---@return string|nil name The file's name, or nil when cavediver knows no path for it
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

---Get a buffer's name as an event names it.
---
---Returns its basename, or `[No Name]` when it has none or isn't valid.
---
---@param bufnr integer Buffer number
---@return string label The buffer's name
function M.buffer_label(bufnr)
	local name = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ""
	return name == "" and "[No Name]" or vim.fs.basename(name)
end

---Read a window's row as it stands.
---
---Copies its slots, its primary queue and switch, its notes, and what the window shows. The
---name of every file in the row goes in `names`, unless it's there already.
---
---@param winid integer|nil The window to read
---@param names table<Filehash, string> The names to fill in, a step's own
---@return CavediverLedgerRow|nil row The window's row, or nil if there's no triquetra for it
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
		shows = vim.api.nvim_win_is_valid(winid)
			and require('cavediver.domains.history').get_hash_from_buffer(vim.api.nvim_win_get_buf(winid)) or nil,
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
	keep(row.shows)
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
M.row_of = row_of

---Read a window's slots as they stand, for a move's row.
---
---Copies its slots, primary queue and switch, without the notes or what the window shows.
---
---@param winid integer|nil The window to read
---@return CavediverLedgerRow|nil row The window's slots, or nil if there's no triquetra for it
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

---Get a window's name as the trail shows it.
---
---Returns `win 2`, by its number in its tab, or by its id once the window is gone.
---
---@param winid integer The window
---@return string name The window's name
function M.window_name(winid)
	return "win " .. (vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_number(winid) or winid)
end

---Check if two rows hold the same slots, queue, switch and notes.
---
---What the window shows is left out, so a visit alone doesn't keep a step.
---
---@param a CavediverLedgerRow|nil The first row
---@param b CavediverLedgerRow|nil The second row
---@return boolean same True if only what the windows show differs, if anything
local function same_row(a, b)
	local function bare(row)
		if row == nil then
			return nil
		end
		local copy = vim.deepcopy(row)
		copy.shows = nil
		return copy
	end
	return vim.deep_equal(bare(a), bare(b))
end
M.same_row = same_row

---Make a new step, numbered one past the last.
---
---Reads the window's row as the step begins and notes the id of its tab's list. Then tells the
---dump the step began, which takes a snapshot when one is due.
---
---@param cause string The kind of trigger
---@param trigger string What set it off, as written
---@param winid integer|nil The window it's about
---@return CavediverLedgerStep step The new step
local function new_step(cause, trigger, winid)
	data.seq = data.seq + 1
	local step = {
		seq = data.seq,
		time = now(),
		cause = cause,
		trigger = trigger,
		win = winid,
		tab = winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_tabpage(winid) or nil,
		-- numbered as they stand now, which is where a replay finds them
		win_nr = winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_number(winid) or nil,
		tab_nr = winid and vim.api.nvim_win_is_valid(winid)
			and vim.api.nvim_tabpage_get_number(vim.api.nvim_win_get_tabpage(winid)) or nil,
		pool = nil,
		session = data.session, -- the whole editor's session then, whose file keeps it
		names = {},
		events = {},
		moves = {},
		told = {},
	}
	step.row_before = row_of(winid, step.names)
	-- the list of its tab, so each session's file keeps its own steps
	if step.tab then
		step.pool = require('cavediver.domains.history').routines.pool_of_tab(step.tab).id
	end
	require('cavediver.domains.ledger.dump').began(step)
	return step
end

---Join names into one line.
---
---Returns `a`, `a and b` or `a, b and c`, and an empty string for no names.
---
---@param names string[] The names to join
---@return string line The names in one line
local function joined(names)
	if #names <= 1 then
		return names[1] or ""
	end
	return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

---Say the messages a step queued.
---
---Says one line for each kind, with the names and lists of all its messages of that kind
---together, each named once.
---
---@param step CavediverLedgerStep The step closing
---@return nil
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

---Keep a step in the ring, and in its day's trail when it made moves.
---
---Both stay in the order of the steps' numbers. The step is counted for the dump's snapshots,
---and the ring then drops its oldest steps past `ledger.ring`.
---
---@param step CavediverLedgerStep The step to keep
---@return nil
local function keep(step)
	local ring = data.ring
	local i = #ring
	while i > 0 and ring[i].seq > step.seq do
		i = i - 1
	end
	table.insert(ring, i + 1, step)
	require('cavediver.domains.ledger.dump').kept()
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

---Close a step.
---
---Reads its row after, and keeps the step when it did anything, or always for a key, a load,
---a save, `:restart`'s reload or a change of label. A step set off by a key, a command or an
---event then says what it queued. Only a step held open its full time has the slot rules
---checked, since one the next trigger closed early may still have follow-ups to land.
---
---@param step CavediverLedgerStep The step to close
---@param held boolean|nil True when the step was held open its full time
---@return nil
local function close(step, held)
	if step.closed then
		return
	end
	step.closed = true
	if data.open == step then
		data.open = nil
	end
	step.row_after = row_of(step.win, step.names)
	-- a command a replay drives is kept too, so a split reaches the dump
	local driven = step.cause == "command" and require('cavediver.domains.ledger.replay').drives(step.trigger)
	if ALWAYS[step.cause] or step.torn or driven or #step.moves > 0 or not same_row(step.row_before, step.row_after) then
		keep(step)
	end
	if SAYS[step.cause] then
		say(step)
	end
	step.told = {}
	if held then
		require('cavediver.domains.ledger.dump').closed(step)
	end
end

---Hold a step open for a few settles, then close it.
---
---Each settle is one `vim.schedule` turn. A step the next trigger has closed is left alone.
---
---@param step CavediverLedgerStep The step to hold open
---@param left integer Settles still to wait
---@return nil
local function hold_open(step, left)
	vim.schedule(function()
		if data.open ~= step then
			return -- closed already, by the next trigger
		end
		if left > 1 then
			hold_open(step, left - 1)
		else
			close(step, true)
		end
	end)
end

---Begin a step at what set it off.
---
---An event while a step is open is one of that step's follow-ups, so it's listed under it and
---begins none. A save or a load, `:restart`'s reload included, takes no events, since what
---follows one in the same call is a step of its own. Anything else closes the open step and begins a new one, held open for a
---few settles.
---
---@param cause "keymap"|"command"|"event"|"load"|"save"|"restart"|"label" The kind of trigger
---@param trigger string What set it off, as written (`<M-f>`, `:bdelete c.txt`, `BufDelete c.txt`)
---@param winid integer|nil The window it's about
---@return CavediverLedgerStep step The step begun, or the open one an event went under
function M.begin(cause, trigger, winid)
	local open = data.open
	if cause == "event" and open and open.cause ~= "save" and open.cause ~= "load" and open.cause ~= "restart" then
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

---Run a call as a step of its own, such as a timer's tick.
---
---Every move the call makes lands on that step, which is kept only when it made one. The step
---closes either way, and an error in the call is then raised again with its traceback.
---
---@param cause "timer" The kind of trigger
---@param trigger string What set it off, as written
---@param fn function The call to run
---@param ... any The call's arguments
---@return any ... The call's results
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

---Get the step a move lands on.
---
---Returns the running call's own step, else the open step, else a new one begun for the
---current window.
---
---@return CavediverLedgerStep step The step to land on
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
---The step keeps the name of every file the move names, as it is now.
---
---@param kind string What the move was (closed, reopened, forgotten, repair, …)
---@param fields table The move's other fields (CavediverLedgerMove)
---@return CavediverLedgerMove move The move recorded
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

---Put fields on the step a move would be recorded on.
---
---It keeps what a step's trigger was made of, besides its text, such as the labels a label step
---went from and to. The step is kept or not by its moves, as before.
---
---@param fields table The step's fields to set (CavediverLedgerStep)
---@return nil
function M.step_fields(fields)
	local step = current()
	for key, value in pairs(fields) do
		step[key] = value
	end
end

---Record a note cavediver changed by itself.
---
---It's recorded as rewritten when it names another buffer now, otherwise as dropped. A note
---that didn't change isn't recorded. `by` says what changed it:
--- - "stale": a stale note, rewritten to the older one or dropped
--- - "guard": the guard (Q6) that keeps the ternary's note off the buffer becoming current
--- - "navigation": navigation's own check on a plain move onto a buffer
--- - "no path": a note dropped for naming a file nothing knows any more
---
---@param map "ternary"|"secondary" The map it's on
---@param owner Filehash The buffer whose note it is
---@param before Filehash|nil What it named
---@param after Filehash|nil What it names now
---@param by string What changed it ("stale", "guard", "navigation" or "no path")
---@return nil
function M.note(map, owner, before, after, by)
	if before == after then
		return
	end
	M.move(after and "rewritten" or "note_dropped", {
		subject = owner, name = M.name_of(owner), note = { map = map, before = before, after = after }, by = by,
	})
end

---Record a window's slots that cavediver moved by itself.
---
---The move's row runs from the slots taken before the change to the window's slots now.
---
---@param kind string What the move was (repointed, landed, undone, cleared)
---@param winid integer The window whose slots moved
---@param before CavediverLedgerRow|nil The slots before the change
---@param fields table|nil The move's other fields
---@return nil
function M.slots_moved(kind, winid, before, fields)
	local move = { subject = tostring(winid), name = M.window_name(winid), row = { before = before or {}, after = M.slots(winid) or {} } }
	for key, value in pairs(fields or {}) do
		move[key] = value
	end
	M.move(kind, move)
end

---Get the key a whole-editor session's steps are marked with.
---
---@param name string|nil The session's name (nil for a nameless one)
---@param directory string The session's directory
---@return string key The session's key
function M.session_of(name, directory)
	return (name or "\0") .. "\n" .. directory
end

---Give a whole-editor session the steps made before any.
---
---Those on the trail, the one still open and a running call's go to it, the first saved or
---loaded. A step made under a session keeps it.
---
---@param name string|nil The session's name (nil for a nameless one)
---@param directory string The session's directory
---@return nil
function M.claim(name, directory)
	local session = M.session_of(name, directory)
	local unclaimed = vim.list_extend({ data.open }, data.scopes)
	for _, steps in pairs(data.days) do
		vim.list_extend(unclaimed, steps)
	end
	for _, step in pairs(unclaimed) do
		if step.session == nil then
			step.session = session
		end
	end
end

---Mark the steps from now on as the whole editor's session's.
---
---It also claims the steps made before any (`claim`).
---
---@param name string|nil The session's name (nil for a nameless one)
---@param directory string The session's directory
---@return nil
function M.set_session(name, directory)
	data.session = M.session_of(name, directory)
	M.claim(name, directory)
end

---Get the step still open.
---@return CavediverLedgerStep|nil step The open step, or nil if none is open
function M.open_step()
	return data.open
end

---Queue a message on the step it follows from.
---
---It's said once the step closes, in one line with the others of its kind, when the step was
---set off by a key, a command or an event.
---
---@param kind "closed"|"reopened" The message's kind
---@param name string The file's name
---@param lists string[] The other lists, by name
---@return nil
function M.tell(kind, name, lists)
	table.insert(current().told, { kind = kind, name = name, lists = lists })
end

---Drop what the open step did, once a whole-editor load replaces it.
---
---By then the session manager has torn the outgoing session down in the same batch, closing
---every buffer with events on. The open step loses those moves and messages, is marked torn
---and closes. Only a step set off by a key, a command or an event is dropped, since a
---session's own steps aren't the teardown.
---
---@return nil
function M.drop_batch()
	local open = data.open
	if open and (open.cause == "event" or open.cause == "command" or open.cause == "keymap") then
		open.moves = {}
		open.told = {}
		open.torn = true
		close(open)
	end
end

---Get the ring's steps.
---@return CavediverLedgerStep[] steps The steps kept, oldest first
function M.steps()
	return data.ring
end

---Get a day's steps that made moves, oldest first.
---
---The open step is included when it began that day and has made moves.
---
---@param day string|nil The day as `YYYY-MM-DD` (the current day when nil)
---@return CavediverLedgerStep[] steps The day's steps with moves
function M.trail(day)
	day = day or os.date("%Y-%m-%d")
	local steps = data.days[day] or {}
	local open = data.open
	if open and #open.moves > 0 and os.date("%Y-%m-%d", math.floor(open.time)) == day then
		steps = vim.list_extend(vim.list_slice(steps, 1, #steps), { open })
	end
	return steps
end

---Get the days the trail holds steps for.
---
---The day the open step began counts when that step has made moves.
---
---@return string[] days The days as `YYYY-MM-DD`, in no set order
function M.trail_days()
	local days = vim.tbl_keys(data.days)
	local open = data.open
	if open and #open.moves > 0 then
		local day = os.date("%Y-%m-%d", math.floor(open.time))
		if not data.days[day] then
			table.insert(days, day)
		end
	end
	return days
end

return M
