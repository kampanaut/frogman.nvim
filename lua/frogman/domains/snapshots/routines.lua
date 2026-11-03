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
	return history.handles.get(history.handles.resolve(id))
end

---Hold a snapshot's files by its place: its slots, its queue and its order.
---
---Its notes are weak, as a window's are, and hold nothing.
---
---@param snapshot Snapshot
---@return nil
local function hold(snapshot)
	local hashes = {}
	local function add(id)
		local handle = M.handle(id)
		if handle then
			table.insert(hashes, handle.hash)
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
	history.handles.hold(place_of(snapshot), hashes)
end

---Get a file's handle id from its hash.
---@param filehash Filehash|nil
---@return integer|nil id
local function id_of(filehash)
	local handle = filehash and history.handles.of_hash(filehash)
	return handle and handle.id or nil
end

---Get a note map as a snapshot keeps it, each note by its two handles.
---
---@param map table<string, Filehash>|nil
---@return SnapshotNote[] notes
local function notes_of(map)
	local notes = {}
	for key, value in pairs(map or {}) do
		local swap = key:match("%-swap$") ~= nil
		local k, v = id_of((key:gsub("%-swap$", ""))), id_of(value)
		if k and v then
			table.insert(notes, { key = k, swap = swap, value = v })
		end
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
		local id = id_of(history.get_hash_from_buffer(item.buf))
		if id then
			table.insert(order, id)
		end
	end
	local queue = {}
	for _, filehash in ipairs(triquetra.primary_buffer or {}) do
		table.insert(queue, id_of(filehash))
	end
	local snapshot = {
		id = new_id(),
		time = os.time(),
		current = id_of(triquetra.current_slot),
		secondary = id_of(triquetra.secondary_slot),
		ternary = id_of(triquetra.ternary_slot),
		queue = queue,
		primary_enabled = triquetra.primary_enabled == true,
		dtm = notes_of(triquetra.displacement_ternary_map),
		dsm = notes_of(triquetra.displacement_secondary_map),
		order = order,
	}
	data.by_window[winid] = data.by_window[winid] or {}
	table.insert(data.by_window[winid], snapshot)
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

---Get the session whose scope a window's snapshots are held over in: its tab session's, or the whole
---editor's. A detached list has no file of its own, so its tab's are the whole editor's.
---
---@param winid WinId
---@return string session_id The session's pool id ("" for the whole editor's)
function M.session_of(winid)
	local tabpage = vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_tabpage(winid)
	local id = tabpage and history.data.tab_pools[tabpage]
	local pool = id and history.data.pools[id]
	return (pool and not pool.detached) and id or ""
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
end

---Let a window's snapshots go with it.
---
---@param winid WinId
---@return nil
function M.drop_window(winid)
	for _, snapshot in ipairs(vim.deepcopy(data.by_window[winid] or {})) do
		M.delete(snapshot.id)
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
	local base = "held over · " .. what .. " · " .. os.date("%m-%d %H:%M")
	local taken = {}
	for _, snapshot in ipairs(M.held_in(session_id)) do
		taken[snapshot.held] = true
	end
	local name, n = base, 1
	while taken[name] do
		n = n + 1
		name = base .. " #" .. n
	end
	return name
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
end

---Queue a closed window's snapshots to be held over once the editor settles.
---
---A session manager's switch closes windows inside its teardown, and the load it ends with drops
---what's queued, so a switch holds nothing over. A tab session's load drops what came from the tab it
---loads into. While they wait, the snapshots keep holding their files.
---
---@param winid WinId The window closing
---@return nil
function M.queue_hold_over(winid)
	local snapshots = data.by_window[winid]
	data.by_window[winid] = nil
	if snapshots == nil or #snapshots == 0 then
		return
	end
	local tabpage = vim.api.nvim_win_get_tabpage(winid)
	local entry = { tab = tabpage, session = M.session_of(winid), snapshots = snapshots,
		what = "window on " .. require('frogman.domains.marks').routines.shows(winid) }
	table.insert(data.pending, entry)
	vim.schedule(function()
		-- one a teardown or a load dropped meanwhile isn't there any more
		for i, waiting in ipairs(data.pending) do
			if waiting == entry then
				table.remove(data.pending, i)
				M.hold_over(entry.session, entry.snapshots, entry.what)
				return
			end
		end
	end)
end

---Drop the snapshots still queued to be held over from a tab, as a tab session's load into it starts.
---
---@param tabpage integer
---@return nil
function M.drop_pending(tabpage)
	for i = #data.pending, 1, -1 do
		local entry = data.pending[i]
		if entry.tab == tabpage then
			table.remove(data.pending, i)
			for _, snapshot in ipairs(entry.snapshots) do
				history.handles.drop_place(place_of(snapshot))
			end
		end
	end
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

---Give a window the snapshots its session file entry holds, in place of any it had.
---
---@param winid WinId
---@param list table[]|nil The entry's snapshots
---@return nil
function M.restore_window(winid, list)
	M.drop_window(winid)
	local snapshots = from_list(list)
	data.by_window[winid] = #snapshots > 0 and snapshots or nil
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
---in its scope.
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
	for winid, snapshots in pairs(data.by_window) do
		local tabpage = vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_tabpage(winid)
		if owner == nil or (tabpage and history.routines.pool_of_tab(tabpage) == owner) then
			for _, snapshot in ipairs(snapshots) do
				take(snapshot)
			end
		end
	end
	for session_id, snapshots in pairs(data.held) do
		if owner == nil or session_id == owner.id then
			for _, snapshot in ipairs(snapshots) do
				take(snapshot)
			end
		end
	end
	return held
end

return M
