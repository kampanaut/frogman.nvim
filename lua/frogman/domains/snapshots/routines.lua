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

---Hold over the snapshots of the windows that closed without their WinClosed, by noautocmd or while
---frogman was off: in the whole editor's scope, the session they were in no longer known.
---
---@return nil
function M.hold_over_gone()
	for winid, snapshots in pairs(data.by_window) do
		if not vim.api.nvim_win_is_valid(winid) then
			data.by_window[winid] = nil
			M.hold_over("", snapshots, "window")
		end
	end
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

---Copy a snapshot into a window's own, with an id of its own and no held-over header, the two going
---their own ways after.
---
---@param winid WinId
---@param snapshot Snapshot
---@return Snapshot copy
function M.copy(winid, snapshot)
	local copy = vim.deepcopy(snapshot)
	copy.id, copy.held = new_id(), nil
	hold(copy)
	data.by_window[winid] = data.by_window[winid] or {}
	table.insert(data.by_window[winid], copy)
	return copy
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
		local handle = history.handles.get(history.handles.resolve(file.handle))
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

---Rebuild a snapshot a list line carries, as a window's own.
---
---Each file comes back by its handle while that lives in this editor, otherwise by its path. Repeats in
---its order keep their first place, and a current that's dropped falls to the ternary, then the
---secondary, then the first of the order. With `dry`, nothing is registered or made: it only tells
---whether the snapshot would have a current.
---
---@param winid WinId
---@param carried table The line's decoded JSON
---@param dry boolean|nil
---@return Snapshot|boolean|nil snapshot The snapshot made, or with `dry` whether one would be
function M.rebuild(winid, carried, dry)
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
		data.by_window[winid] = data.by_window[winid] or {}
		table.insert(data.by_window[winid], snapshot)
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
