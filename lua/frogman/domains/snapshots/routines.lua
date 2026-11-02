---Snapshots domain routines.
---
---This module contains the snapshots' business logic: taking one of a window, holding its files by
---its place, finding and deleting one, and letting them all go.

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
	data.taken = data.taken + 1
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
		-- unique across editors: the time, the counter's digits and this editor's count
		id = string.format("%d%04d%d", os.time(), vim.uv.hrtime() % 10000, data.taken),
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

---Find a snapshot by its id, with the window it belongs to.
---
---@param id string
---@return Snapshot|nil snapshot
---@return WinId|nil winid
function M.find(id)
	for winid, snapshots in pairs(data.by_window) do
		for _, snapshot in ipairs(snapshots) do
			if snapshot.id == id then
				return snapshot, winid
			end
		end
	end
	return nil, nil
end

---Delete a snapshot, letting its files go once nothing else holds them.
---
---@param id string
---@return nil
function M.delete(id)
	local snapshot, winid = M.find(id)
	if not snapshot then
		return
	end
	for i, other in ipairs(data.by_window[winid]) do
		if other == snapshot then
			table.remove(data.by_window[winid], i)
			break
		end
	end
	if #data.by_window[winid] == 0 then
		data.by_window[winid] = nil
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

---Let every snapshot go, as a whole-editor load from idle starts from nothing.
---
---@return nil
function M.teardown()
	for _, snapshots in pairs(data.by_window) do
		for _, snapshot in ipairs(snapshots) do
			history.handles.drop_place(place_of(snapshot))
		end
	end
	data.by_window = {}
end

return M
