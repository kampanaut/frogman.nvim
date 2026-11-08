---Snapshots domain routines.
---
---This module contains the snapshots' business logic: taking one of a window, holding its files by
---its place, finding and deleting one, holding a closed window's over, saving and loading them, and
---letting them all go.

local data = require('frogman.domains.snapshots.data')
local history = require('frogman.domains.history')

local M = {}

---Get the place a snapshot holds its files by.
---
---@param snapshot Snapshot
---@return string place Like "snap:<id>"
local function place_of(snapshot)
	return "snap:" .. snapshot.id
end

---Get the handle a snapshot keeps for a file now.
---
---A handle let go for a moved file that took its name is followed to the moved file's.
---
---@param id integer|nil
---@return FileHandle|nil handle
function M.handle(id)
	if id == nil then
		return nil
	end
	return history.handles.follow(id)
end

---Hold a snapshot's files by its place: its slots, its queue and its order.
---
---Its notes are weak, as a window's are, and hold nothing.
---
---@param snapshot Snapshot The snapshot whose files are held
---@return nil
local function hold(snapshot)
	local ids = {}
	local function add(id)
		local handle = M.handle(id)
		if handle then
			table.insert(ids, handle.id)
		end
	end
	add(snapshot.current)
	add(snapshot.secondary)
	add(snapshot.ternary)
	for _, id in ipairs(snapshot.queue) do
		add(id)
	end
	for _, id in ipairs(snapshot.order) do
		add(id)
	end
	history.handles.hold(place_of(snapshot), ids)
end

---Keep each file once in a snapshot, by the live slots' rule.
---
---The current slot keeps a file when it holds it; otherwise the slot given keeps it (at a move, the
---slot the moved file was in), or else the secondary over the ternary, as a load, which can't tell,
---reads it; any other slot holding it lets go. A repeat in its queue or its order keeps its first
---place. Each file is held by its live handle's number from then on.
---
---@param snapshot Snapshot The snapshot, rewritten in place
---@param keeper "secondary"|"ternary"|nil The slot keeping a file the current doesn't hold, when it's known
---@return string[] cleared The slots that let a file go
local function once(snapshot, keeper)
	local function live(id)
		local handle = M.handle(id)
		return handle and handle.id or nil
	end
	local c, s, t = live(snapshot.current), live(snapshot.secondary), live(snapshot.ternary)
	snapshot.current, snapshot.secondary, snapshot.ternary = c or snapshot.current, s or snapshot.secondary, t or snapshot.ternary
	local cleared = {}
	if s ~= nil and s == c then
		snapshot.secondary, s = nil, nil
		table.insert(cleared, "secondary")
	end
	if t ~= nil and t == c then
		snapshot.ternary, t = nil, nil
		table.insert(cleared, "ternary")
	end
	if s ~= nil and s == t then
		local goes = keeper == "ternary" and "secondary" or "ternary"
		snapshot[goes] = nil
		table.insert(cleared, goes)
	end
	for _, field in ipairs({ "queue", "order" }) do
		local seen, kept = {}, {}
		for _, id in ipairs(snapshot[field]) do
			local file = live(id)
			if file == nil or not seen[file] then
				if file then
					seen[file] = true
				end
				table.insert(kept, file or id)
			end
		end
		snapshot[field] = kept
	end
	return cleared
end

---Apply the live slots' rule to the snapshots a move left holding one file twice.
---
---The move gave the moved file a name another live file had, so a snapshot that held both holds one
---file twice: the current keeps it when it holds it, otherwise the slot the moved file was in. Every
---snapshot is looked at, a window's, a held-over one and one waiting a tick to be held over.
---
---@param other HandleId The handle the move let go, which leads to the moved file's now
---@param moved HandleId The moved file's handle
---@return table[] cleared Each snapshot that let a slot go: `{ time = when it was taken, slots = the slots }`
function M.take_over(other, moved)
	local out = {}
	local function names(id)
		return id ~= nil and (id == other or id == moved)
	end
	local function each(snapshot)
		local holds = names(snapshot.current) or names(snapshot.secondary) or names(snapshot.ternary)
		for _, id in ipairs(snapshot.queue) do
			holds = holds or names(id)
		end
		for _, id in ipairs(snapshot.order) do
			holds = holds or names(id)
		end
		if not holds then
			return
		end
		local keeper = snapshot.secondary == moved and "secondary" or (snapshot.ternary == moved and "ternary" or nil)
		local cleared = once(snapshot, keeper)
		hold(snapshot)
		if #cleared > 0 then
			table.insert(out, { time = snapshot.time, slots = cleared })
		end
	end
	for _, list in pairs(data.by_window) do
		for _, snapshot in ipairs(list) do
			each(snapshot)
		end
	end
	for _, list in pairs(data.held) do
		for _, snapshot in ipairs(list) do
			each(snapshot)
		end
	end
	for _, entry in ipairs(data.pending) do
		for _, snapshot in ipairs(entry.snapshots or {}) do
			each(snapshot)
		end
	end
	return out
end

---Drop a file that's let go from every snapshot's notes.
---
---A snapshot's notes are weak, as a window's are: the notes about the file and the notes naming it go,
---in a window's snapshots, the held-over ones and those waiting a tick to be held over. A note keeps
---the number it was taken with, so one naming a file let go for a moved file names the moved file,
---and goes when that one does.
---
---@param id HandleId The handle let go
---@return nil
function M.let_go_notes(id)
	local function about(note)
		return history.handles.resolve(note.key) == id or history.handles.resolve(note.value) == id
	end
	local function each(snapshot)
		for _, field in ipairs({ "dtm", "dsm" }) do
			snapshot[field] = vim.tbl_filter(function(note) return not about(note) end, snapshot[field])
		end
	end
	for _, list in pairs(data.by_window) do
		for _, snapshot in ipairs(list) do
			each(snapshot)
		end
	end
	for _, list in pairs(data.held) do
		for _, snapshot in ipairs(list) do
			each(snapshot)
		end
	end
	for _, entry in ipairs(data.pending) do
		for _, snapshot in ipairs(entry.snapshots or {}) do
			each(snapshot)
		end
	end
end

---Get a file's handle id from its hash.
---@param filehash Filehash|nil
---@return integer|nil id
local function id_of(filehash)
	local handle = filehash and history.handles.of_hash(filehash)
	return handle and handle.id or nil
end

---Get a window's note map as a snapshot keeps it, each note by its two handles.
---
---A window's notes name only files that live: a file let go leaves them as it goes.
---
---@param map table<HandleId|string, HandleId>|nil The note map, as the window holds it
---@return SnapshotNote[] notes
local function notes_of(map)
	local window_data = require('frogman.domains.window').data
	local notes = {}
	for key, value in pairs(map or {}) do
		table.insert(notes, { key = window_data.note_owner(key), swap = window_data.is_swap_note(key), value = value })
	end
	return notes
end

---Get a fresh snapshot id, unique across editors: the time, the counter's digits and this editor's count.
---
---@return string id
local function new_id()
	data.taken = data.taken + 1
	return string.format("%d%04d%d", os.time(), vim.uv.hrtime() % 10000, data.taken)
end

---Take a snapshot of a window: its slots, its notes, its queue and switch, and the order its
---bufferline drew.
---
---A window with no triquetra, or one cycling, has nothing to take, and says so.
---
---@param winid WinId|nil The window (nil = the current one)
---@return Snapshot|nil snapshot
function M.take(winid)
	winid = winid or vim.api.nvim_get_current_win()
	local triquetra = require('frogman.domains.window').data.get_window_triquetra(winid)
	if not triquetra then
		vim.notify("Window with unregistered buffer.", vim.log.levels.WARN)
		return nil
	end
	if require('frogman.domains.navigation').is_cycling() then
		vim.notify("frogman: pick or cancel the cycle first.", vim.log.levels.WARN)
		return nil
	end
	local order = {}
	for _, item in ipairs(history.get_ordered_buffers()) do
		local id = history.get_handle_from_buffer(item.buf)
		if id then
			table.insert(order, id)
		end
	end
	local snapshot = {
		id = new_id(),
		time = os.time(),
		current = triquetra.current_slot,
		secondary = triquetra.secondary_slot,
		ternary = triquetra.ternary_slot,
		queue = vim.deepcopy(triquetra.primary_buffer or {}),
		primary_enabled = triquetra.primary_enabled == true,
		dtm = notes_of(triquetra.displacement_ternary_map),
		dsm = notes_of(triquetra.displacement_secondary_map),
		order = order,
	}
	data.by_window[winid] = data.by_window[winid] or {}
	table.insert(data.by_window[winid], snapshot)
	require('frogman.held').note_session(winid)
	hold(snapshot)
	vim.notify("frogman: snapshot taken: window " .. vim.api.nvim_win_get_number(winid) .. " has " ..
		#data.by_window[winid] .. ".", vim.log.levels.INFO)
	return snapshot
end

---Get a window's snapshots, oldest first.
---
---@param winid WinId
---@return Snapshot[] snapshots
function M.of_window(winid)
	return data.by_window[winid] or {}
end

---Get the session whose scope a window's snapshots are held over in: its tab's list's, a tab
---session's or a detached list's, as its marks are, or else the whole editor's.
---
---@param winid WinId
---@return string session_id The session's pool id ("" for the whole editor's)
function M.session_of(winid)
	local tabpage = vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_tabpage(winid)
	return tabpage and history.data.tab_pools[tabpage] or ""
end

---Get the snapshots held over in a session's scope, oldest first.
---
---@param session_id string The session's pool id ("" for the whole editor's)
---@return Snapshot[] snapshots
function M.held_in(session_id)
	return data.held[session_id] or {}
end

---Find a snapshot by its id, with the window it belongs to, or the session it's held over in.
---
---@param id string
---@return Snapshot|nil snapshot
---@return WinId|nil winid Its window, when it's a window's
---@return string|nil session_id The session it's held over in, when it's held over
function M.find(id)
	for winid, snapshots in pairs(data.by_window) do
		for _, snapshot in ipairs(snapshots) do
			if snapshot.id == id then
				return snapshot, winid, nil
			end
		end
	end
	for session_id, snapshots in pairs(data.held) do
		for _, snapshot in ipairs(snapshots) do
			if snapshot.id == id then
				return snapshot, nil, session_id
			end
		end
	end
	return nil, nil, nil
end

---Delete a snapshot, a window's or a held-over one, letting its files go once nothing else holds them.
---
---@param id string
---@return nil
function M.delete(id)
	local snapshot, winid, session_id = M.find(id)
	if not snapshot then
		return
	end
	local list = winid and data.by_window[winid] or data.held[session_id]
	for i, other in ipairs(list) do
		if other == snapshot then
			table.remove(list, i)
			break
		end
	end
	if #list == 0 and winid then
		data.by_window[winid] = nil
	elseif #list == 0 then
		data.held[session_id] = nil
	end
	history.handles.drop_place(place_of(snapshot))
	if not winid then
		require('frogman.held').records_changed(session_id) -- held-over snapshots are records
	end
end

---Let the snapshots held over in a session's scope go, as its list goes once they're in its file.
---
---@param session_id string The session's pool id
---@return nil
function M.drop_held(session_id)
	for _, snapshot in ipairs(data.held[session_id] or {}) do
		history.handles.drop_place(place_of(snapshot))
	end
	data.held[session_id] = nil
end

---Get a held-over header: what the window was and when, numbered on when the scope has that one.
---
---@param session_id string The session's pool id ("" for the whole editor's)
---@param what string What it was, like "window on api.lua" or "proj, loaded into tab 2"
---@return string header Like "held over · window on api.lua · 11-03 07:50"
local function held_name(session_id, what)
	local taken = {}
	for _, snapshot in ipairs(M.held_in(session_id)) do
		taken[snapshot.held] = true
	end
	return require('frogman.held').held_header(what, taken)
end

---Hold snapshots over in a session's scope, under one header, after the ones held there already.
---
---They keep holding their files by their places. Committing one doesn't make it a window's.
---
---@param session_id string The session's pool id ("" for the whole editor's)
---@param snapshots Snapshot[]
---@param what string What they were, like "window on api.lua"
---@return nil
function M.hold_over(session_id, snapshots, what)
	if #snapshots == 0 then
		return
	end
	local header = held_name(session_id, what)
	data.held[session_id] = data.held[session_id] or {}
	for _, snapshot in ipairs(snapshots) do
		snapshot.held = header
		table.insert(data.held[session_id], snapshot)
	end
	require('frogman.held').records_changed(session_id)
end

---Queue a closed window's snapshots to be held over once the editor settles, but for a window whose close
---put them onto its saved entry, and a window frogman never took in, which keeps none (DESK.md:1694): their
---snapshots let their files go.
---
---A session manager's switch closes windows inside its teardown, and the load it ends with drops
---what's queued, so a switch holds nothing over. A tab session's load drops what came from the tab it
---loads into. While they wait, the snapshots keep holding their files.
---
---A tab session's last window keeps its snapshots until the close is over, for a save at the tab's
---TabClosedPre; a tab session's last tab closing holds what its windows queued over as its records are
---written.
---
---@param winid WinId The window closing
---@param onto boolean|nil Whether its close put its snapshots onto its saved entry
---@return nil
function M.queue_hold_over(winid, onto)
	local snapshots = data.by_window[winid]
	local held = require('frogman.held')
	held.after_close(winid, function() data.by_window[winid] = nil end)
	if snapshots == nil or #snapshots == 0 then
		return
	end
	if onto or held.never_taken_in(winid) then
		for _, snapshot in ipairs(snapshots) do
			history.handles.drop_place(place_of(snapshot))
		end
		return
	end
	local session, what = held.closing_in(winid)
	local entry = { tab = vim.api.nvim_win_get_tabpage(winid), session = session, snapshots = snapshots, what = what }
	held.wait_a_tick(function() return data.pending end, entry, function()
		M.hold_over(entry.session, entry.snapshots, entry.what)
	end)
end

---Hold over at once what closes in a session queued, as its last tab closes and its records are written
---with its closed list, so they take it.
---
---@param session_id string The session's pool id
---@return nil
function M.flush_pending(session_id)
	local due = {}
	for i = #data.pending, 1, -1 do
		if data.pending[i].session == session_id then
			table.insert(due, 1, table.remove(data.pending, i))
		end
	end
	for _, entry in ipairs(due) do
		M.hold_over(entry.session, entry.snapshots, entry.what)
	end
end

---Hold over the snapshots of the windows that closed without their WinClosed, by noautocmd or while
---frogman was off: in the scope of the session a window was last seen in, or the whole editor's, under
---what it showed then.
---
---@return nil
function M.hold_over_gone()
	local held = require('frogman.held')
	for winid, snapshots in pairs(data.by_window) do
		if not vim.api.nvim_win_is_valid(winid) and not held.closing(winid) then
			-- onto its saved entry in the session it was last seen in, when it has one there; else held over
			local session, what = held.last_session(winid) or "", held.last_seen_as("window", winid)
			local onto = require('frogman.domains.storage').routines.close_onto_entry("window", winid, session, what)
			data.by_window[winid] = nil
			if onto or held.never_taken_in(winid) then
				for _, snapshot in ipairs(snapshots) do
					history.handles.drop_place(place_of(snapshot))
				end
			else
				M.hold_over(session, snapshots, what)
			end
		end
	end
end

---Drop the snapshots still queued to be held over from a tab, as a tab session's load into it starts.
---
---@param tabpage integer The tab whose queued snapshots go
---@return nil
function M.drop_pending(tabpage)
	require('frogman.held').drop_waiting(data.pending, tabpage, function(entry)
		for _, snapshot in ipairs(entry.snapshots) do
			history.handles.drop_place(place_of(snapshot))
		end
	end)
end

---Move the snapshots held over in one session's scope into another's, each keeping its header,
---numbered on when the scope it goes to has it, as a detached list that goes leaves them to the
---whole editor's.
---
---@param from_id string
---@param to_id string
---@return nil
function M.move_held(from_id, to_id)
	if data.held[from_id] == nil then
		return
	end
	local taken, renamed = {}, {}
	for _, snapshot in ipairs(data.held[to_id] or {}) do
		taken[snapshot.held] = true
	end
	for _, snapshot in ipairs(data.held[from_id]) do
		if renamed[snapshot.held] == nil then
			local name, n = snapshot.held, 1
			while taken[name] do
				n = n + 1
				name = snapshot.held .. " #" .. n
			end
			renamed[snapshot.held] = name
			taken[name] = true
		end
	end
	data.held[to_id] = data.held[to_id] or {}
	for _, snapshot in ipairs(data.held[from_id]) do
		snapshot.held = renamed[snapshot.held]
		table.insert(data.held[to_id], snapshot)
	end
	data.held[from_id] = nil
	require('frogman.held').records_changed(to_id)
end

---Let every snapshot go, as a whole-editor load from idle starts from nothing.
---
---The ones held over and the ones still waiting to be go too.
---
---@return nil
function M.teardown()
	local function drop(snapshots)
		for _, snapshot in ipairs(snapshots) do
			history.handles.drop_place(place_of(snapshot))
		end
	end
	for _, snapshots in pairs(data.by_window) do
		drop(snapshots)
	end
	for _, snapshots in pairs(data.held) do
		drop(snapshots)
	end
	for _, entry in ipairs(data.pending) do
		drop(entry.snapshots)
	end
	data.by_window, data.held, data.pending = {}, {}, {}
	local preview = package.loaded['frogman.domains.snapshots.preview']
	if preview then
		preview.teardown()
	end
end

---Saving and loading --------------------------------------------------------------------

---Get a snapshot as a session file holds it: each file by its hash, a note by its two.
---
---@param snapshot Snapshot
---@return table saved Its `{ id, time, current, secondary, ternary, queue, on, dtm, dsm, order }`, and `held` when it's held over
local function saved_of(snapshot)
	local function hash(id)
		local handle = M.handle(id)
		return handle and handle.hash or nil
	end
	local function hashes(ids)
		local out = {}
		for _, id in ipairs(ids) do
			local filehash = hash(id)
			if filehash then
				table.insert(out, filehash)
			end
		end
		return out
	end
	local function map(notes)
		local out = {}
		for _, note in ipairs(notes) do
			local key, value = hash(note.key), hash(note.value)
			if key and value then
				out[key .. (note.swap and "-swap" or "")] = value
			end
		end
		return out
	end
	return {
		id = snapshot.id, time = snapshot.time, held = snapshot.held,
		current = hash(snapshot.current), secondary = hash(snapshot.secondary), ternary = hash(snapshot.ternary),
		queue = hashes(snapshot.queue), on = snapshot.primary_enabled == true,
		dtm = map(snapshot.dtm), dsm = map(snapshot.dsm), order = hashes(snapshot.order),
	}
end

---Get a window's snapshots as its session file entry holds them.
---
---@param winid WinId
---@return table[]|nil saved Each snapshot as `saved_of` gives it, oldest first, or nil with none
function M.serialise_window(winid)
	local saved = vim.tbl_map(saved_of, data.by_window[winid] or {})
	return #saved > 0 and saved or nil
end

---Get the snapshots held over in a session's scope as its session file holds them.
---
---@param session_id string The session's pool id ("" for the whole editor's)
---@return table[]|nil saved Each snapshot as `saved_of` gives it, its header with it, or nil with none
function M.serialise_held(session_id)
	local saved = vim.tbl_map(saved_of, M.held_in(session_id))
	return #saved > 0 and saved or nil
end

---Make a snapshot from a session file's, each file taking its handle, and hold its files.
---
---One whose current file the registry doesn't know is left out, and so is any other file of it the
---registry doesn't know. An id memory holds already, another window's copy of it, gets a fresh one,
---the two going their own ways after.
---
---@param saved table
---@return Snapshot|nil snapshot
local function from_saved(saved)
	if type(saved) ~= "table" then
		return nil
	end
	local function id(filehash)
		return type(filehash) == "string" and id_of(filehash) or nil
	end
	local function ids(list)
		local out = {}
		for _, filehash in ipairs(type(list) == "table" and list or {}) do
			local i = id(filehash)
			if i then
				table.insert(out, i)
			end
		end
		return out
	end
	local function notes(map)
		local out = {}
		for key, value in pairs(type(map) == "table" and map or {}) do
			local k, v = id((tostring(key):gsub("%-swap$", ""))), id(value)
			if k and v then
				table.insert(out, { key = k, swap = tostring(key):match("%-swap$") ~= nil, value = v })
			end
		end
		return out
	end
	local current = id(saved.current)
	if current == nil then
		return nil
	end
	local snapshot = {
		id = (type(saved.id) == "string" and M.find(saved.id) == nil) and saved.id or new_id(),
		time = type(saved.time) == "number" and saved.time or os.time(),
		current = current, secondary = id(saved.secondary), ternary = id(saved.ternary),
		queue = ids(saved.queue), primary_enabled = saved.on == true,
		dtm = notes(saved.dtm), dsm = notes(saved.dsm), order = ids(saved.order),
	}
	once(snapshot) -- a file saved twice, by a move before the rule held at moves, is kept once
	hold(snapshot)
	return snapshot
end

---Get the snapshots a session file's list makes.
---
---@param list table[]|nil
---@return Snapshot[] snapshots
local function from_list(list)
	local snapshots = {}
	for _, saved in ipairs(type(list) == "table" and list or {}) do
		local snapshot = from_saved(saved)
		if snapshot then
			table.insert(snapshots, snapshot)
		end
	end
	return snapshots
end

---Give a window the snapshots its session file entry holds.
---
---The ones it had are held over under the load's header, but for one the entry brings back by its id,
---the same snapshot, which the entry's takes the place of.
---
---@param winid WinId
---@param list table[]|nil The entry's snapshots
---@param session_id string The session's pool id ("" for the whole editor's)
---@param what string The load, like "proj, loaded into tab 2"
---@return nil
function M.restore_window(winid, list, session_id, what)
	local incoming, kept = {}, {}
	for _, saved in ipairs(type(list) == "table" and list or {}) do
		if type(saved) == "table" and type(saved.id) == "string" then
			incoming[saved.id] = true
		end
	end
	for _, snapshot in ipairs(vim.list_slice(data.by_window[winid] or {})) do
		if incoming[snapshot.id] then
			M.delete(snapshot.id)
		else
			table.insert(kept, snapshot)
		end
	end
	data.by_window[winid] = nil
	M.hold_over(session_id, kept, what)
	local snapshots = from_list(list)
	data.by_window[winid] = #snapshots > 0 and snapshots or nil
	require('frogman.held').note_session(winid)
end

---Hold a session file's snapshots over under the load's header: an entry's no window took.
---
---@param session_id string The session's pool id ("" for the whole editor's)
---@param list table[]|nil The entry's snapshots
---@param what string The load, like "proj, loaded into tab 2"
---@return nil
function M.hold_saved(session_id, list, what)
	M.hold_over(session_id, from_list(list), what)
end

---Give a session's scope the held-over snapshots its session file holds, each under its own header.
---
---@param session_id string The session's pool id ("" for the whole editor's)
---@param list table[]|nil The file's `snapshots`
---@return nil
function M.restore_held(session_id, list)
	for _, saved in ipairs(type(list) == "table" and list or {}) do
		local snapshot = from_saved(saved)
		if snapshot then
			snapshot.held = type(saved.held) == "string" and saved.held or "held over"
			data.held[session_id] = data.held[session_id] or {}
			table.insert(data.held[session_id], snapshot)
		end
	end
end

---Get the snapshots of a session file's list whose id memory doesn't hold.
---
---A session loaded while it's open keeps memory's: the file's it holds already are skipped.
---
---@param list table[]|nil
---@return table[] left
function M.not_held(list)
	return vim.tbl_filter(function(saved)
		return type(saved) == "table" and not (type(saved.id) == "string" and M.find(saved.id))
	end, type(list) == "table" and list or {})
end

---Get the snapshot held over in a session's scope under an id, a close's copy or a load's.
---
---@param session_id string The session's pool id ("" for the whole editor's)
---@param id string The snapshot's id
---@return Snapshot|nil snapshot
function M.held_copy(session_id, id)
	for _, snapshot in ipairs(data.held[session_id] or {}) do
		if snapshot.id == id then
			return snapshot
		end
	end
	return nil
end

---Let go of the copy held over of a snapshot its window's entry brings back unchanged, the window taking
---it: a close's copy or a load's, by its id, while it's still what was held over.
---
---@param session_id string The session's pool id ("" for the whole editor's)
---@param saved table The entry's snapshot, as its session file holds it
---@return boolean dropped Whether the copy went; one that changed since stays held over
function M.drop_copy(session_id, saved)
	local copy = M.held_copy(session_id, saved.id)
	if copy == nil then
		return false
	end
	local held, brought = saved_of(copy), vim.deepcopy(saved)
	held.held, brought.held = nil, nil
	if not vim.deep_equal(held, brought) then
		return false
	end
	M.delete(saved.id)
	return true
end

---Copying between windows ----------------------------------------------------------------

---Get this editor's mark, the ledger's, which a list line's handle numbers are read against.
---@return string epoch
local function this_editor()
	require('frogman.domains.ledger.routines') -- it sets the mark as it loads
	return require('frogman.domains.ledger.data').epoch
end

---Get a snapshot as a list line carries it: every file once, by its path and its handle's number, and
---the slots, the queue, the order and the notes by those files. A No Name text goes by its name alone.
---
---@param snapshot Snapshot
---@return table carried The `{ v, id, time, editor, files, c, s, t, queue, on, order, dtm, dsm }` a line encodes
function M.carried(snapshot)
	local files, index = {}, {}
	local function at(id)
		local handle = id and M.handle(id)
		local filepath = handle and history.get_filepath_from_hash(handle.hash)
		if not filepath then
			return nil
		end
		if index[handle.id] == nil then
			table.insert(files, { path = filepath, handle = handle.id })
			index[handle.id] = #files
		end
		return index[handle.id]
	end
	local function list(ids)
		local out = {}
		for _, id in ipairs(ids) do
			local i = at(id)
			if i then
				table.insert(out, i)
			end
		end
		return out
	end
	local function notes(each)
		local out = {}
		for _, note in ipairs(each) do
			local k, v = at(note.key), at(note.value)
			if k and v then
				table.insert(out, { k, v, note.swap and 1 or 0 })
			end
		end
		return out
	end
	return {
		v = 1, id = snapshot.id, time = snapshot.time, editor = this_editor(),
		c = at(snapshot.current), s = at(snapshot.secondary), t = at(snapshot.ternary),
		queue = list(snapshot.queue), on = snapshot.primary_enabled == true, order = list(snapshot.order),
		dtm = notes(snapshot.dtm), dsm = notes(snapshot.dsm), files = files,
	}
end

---Where a list line puts the snapshot it makes: a window's own, or held over in a session's scope under
---a header.
---@alias SnapshotPlace {winid: WinId}|{session: string, held: string}

---Put a snapshot where a list line sits: a window's own, with no header, or held over under the header.
---
---@param into SnapshotPlace
---@param snapshot Snapshot
---@return nil
local function put(into, snapshot)
	if into.held then
		snapshot.held = into.held
		data.held[into.session] = data.held[into.session] or {}
		table.insert(data.held[into.session], snapshot)
		require('frogman.held').records_changed(into.session)
	else
		snapshot.held = nil
		data.by_window[into.winid] = data.by_window[into.winid] or {}
		table.insert(data.by_window[into.winid], snapshot)
		require('frogman.held').note_session(into.winid)
	end
end

---Copy a snapshot to where a list line sits, with an id of its own, the two going their own ways after.
---
---@param into SnapshotPlace
---@param snapshot Snapshot
---@return Snapshot copy
function M.copy(into, snapshot)
	local copy = vim.deepcopy(snapshot)
	copy.id = new_id()
	hold(copy)
	put(into, copy)
	return copy
end

---Copy the snapshots held over in one session's scope into another's, each with an id of its own and
---its header, the two going their own ways after, as a detached list takes its session's.
---
---@param session_id string The session's pool id
---@param to_id string The pool id they're copied into
---@return nil
function M.copy_held(session_id, to_id)
	for _, snapshot in ipairs(vim.list_slice(M.held_in(session_id))) do
		M.copy({ session = to_id, held = snapshot.held }, snapshot)
	end
end

---Get the hash a carried file names in this editor: its handle's while that handle lives here, otherwise
---its path's, registered when the registry doesn't know it. A No Name text goes by its handle alone, and
---a name frogman doesn't track, a `://` one or a directory, names none.
---
---@param file table
---@param here boolean Whether this editor drew the line, so its handle numbers are this editor's
---@param register boolean Whether to register a path the registry doesn't know, or only to tell
---@return Filehash|nil filehash
local function carried_hash(file, here, register)
	if type(file) ~= "table" then
		return nil
	end
	if here and type(file.handle) == "number" then
		local handle = history.handles.follow(file.handle)
		if handle then
			return handle.hash
		end
	end
	local path = file.path
	if type(path) ~= "string" or path == "" or path:match("^NONAME_") or path:find("://", 1, true)
		or vim.fn.isdirectory(path) == 1 then
		return nil
	end
	local filehash = history.routines.get_filehash(path)
	if register and not history.handles.of_hash(filehash) then
		history.routines.register_filepath(path)
	end
	return filehash
end

---Rebuild a snapshot a list line carries, where the line sits.
---
---Each file comes back by its handle while that lives in this editor, otherwise by its path. Repeats in
---its order keep their first place, and a current that's dropped falls to the ternary, then the
---secondary, then the first of the order. With `dry`, nothing is registered or made: it only tells
---whether the snapshot would have a current.
---
---@param into SnapshotPlace
---@param carried table The line's decoded JSON
---@param dry boolean|nil
---@return Snapshot|boolean|nil snapshot The snapshot made, or with `dry` whether one would be
function M.rebuild(into, carried, dry)
	local here = carried.editor == this_editor()
	local hashes = {}
	for i, file in ipairs(type(carried.files) == "table" and carried.files or {}) do
		hashes[i] = carried_hash(file, here, not dry)
	end
	local function hash(i)
		return type(i) == "number" and hashes[i] or nil
	end
	local saved = { id = carried.id, time = carried.time, on = carried.on == true,
		current = hash(carried.c), secondary = hash(carried.s), ternary = hash(carried.t),
		queue = {}, order = {}, dtm = {}, dsm = {} }
	for _, i in ipairs(type(carried.queue) == "table" and carried.queue or {}) do
		if hash(i) then
			table.insert(saved.queue, hash(i))
		end
	end
	local seen = {}
	for _, i in ipairs(type(carried.order) == "table" and carried.order or {}) do
		local filehash = hash(i)
		if filehash and not seen[filehash] then
			seen[filehash] = true
			table.insert(saved.order, filehash)
		end
	end
	for _, key in ipairs({ "dtm", "dsm" }) do
		for _, note in ipairs(type(carried[key]) == "table" and carried[key] or {}) do
			local k, v = type(note) == "table" and hash(note[1]), type(note) == "table" and hash(note[2])
			if k and v then
				saved[key][k .. (note[3] == 1 and "-swap" or "")] = v
			end
		end
	end
	if saved.current == nil then
		if saved.ternary then
			saved.current, saved.ternary = saved.ternary, nil
		elseif saved.secondary then
			saved.current, saved.secondary = saved.secondary, nil
		else
			saved.current = saved.order[1]
		end
	end
	if dry then
		return saved.current ~= nil
	end
	local snapshot = from_saved(saved)
	if snapshot then
		put(into, snapshot)
	end
	return snapshot
end

---Get the hashes a session file's snapshots name: their slots, queues, orders and notes.
---
---@param list table[]|nil
---@param into table<Filehash, boolean>|nil Added to in place, when given
---@return table<Filehash, boolean> named
function M.named_by(list, into)
	into = into or {}
	local function add(filehash)
		if type(filehash) == "string" then
			into[(filehash:gsub("%-swap$", ""))] = true
		end
	end
	for _, saved in ipairs(type(list) == "table" and list or {}) do
		if type(saved) == "table" then
			add(saved.current)
			add(saved.secondary)
			add(saved.ternary)
			for _, key in ipairs({ "queue", "order" }) do
				for _, filehash in ipairs(type(saved[key]) == "table" and saved[key] or {}) do
					add(filehash)
				end
			end
			for _, key in ipairs({ "dtm", "dsm" }) do
				for k, v in pairs(type(saved[key]) == "table" and saved[key] or {}) do
					add(k)
					add(v)
				end
			end
		end
	end
	return into
end

---Get the hashes of the files a session's snapshots hold.
---
---With no pool, every snapshot's. With a pool, those of the windows in its tabs and those held over
---in its scope; the editor's pool takes the detached lists' too.
---
---@param owner Pool|nil
---@return table<Filehash, boolean> held
function M.held_by(owner)
	local held = {}
	local function take(snapshot)
		for _, id in ipairs({ snapshot.current, snapshot.secondary or false, snapshot.ternary or false }) do
			local handle = id and M.handle(id)
			if handle then
				held[handle.hash] = true
			end
		end
		for _, key in ipairs({ "queue", "order" }) do
			for _, id in ipairs(snapshot[key]) do
				local handle = M.handle(id)
				if handle then
					held[handle.hash] = true
				end
			end
		end
	end
	local owns = require('frogman.held').owns
	for winid, snapshots in pairs(data.by_window) do
		if owns(owner, "window", winid) then
			for _, snapshot in ipairs(snapshots) do
				take(snapshot)
			end
		end
	end
	for session_id, snapshots in pairs(data.held) do
		if owns(owner, "session", session_id) then
			for _, snapshot in ipairs(snapshots) do
				take(snapshot)
			end
		end
	end
	return held
end

return M
