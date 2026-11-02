---A snapshot shown in its window, to take with <M-v> or to leave.
---
---While it shows, history is detached as a cycle detaches it, so nothing the window shows is recorded,
---and the winbar and the bufferline draw the snapshot's slots and its stored order. The cycle keys
---step through that order, <M-v> takes the snapshot onto the window, and opening the snapshot list or
---going to another window leaves it, the window back on what it showed.

local routines = require('frogman.domains.snapshots.routines')
local history = require('frogman.domains.history')

local M = {}

---The snapshot showing: its window, the snapshot, and the buffer the window showed before it.
---@type {window: WinId, snapshot: Snapshot, before: Bufnr}|nil
local showing = nil

---The words every other key says while a snapshot shows
M.REFUSED = "frogman: a snapshot is showing: <M-v> takes it, and opening the snapshot list or going to another window leaves it."

---Check if a snapshot is showing.
---@return boolean
function M.active()
	return showing ~= nil
end

---Get the window a snapshot shows in.
---@return WinId|nil winid
function M.window()
	return showing and showing.window
end

---Get the hashes of a snapshot's slots, by the live slots' rule.
---
---A file a rename left in two of its slots stays in the current, and the secondary keeps one the
---current doesn't hold over the ternary.
---
---@param snapshot Snapshot
---@return Filehash|nil current
---@return Filehash|nil secondary
---@return Filehash|nil ternary
local function slots_of(snapshot)
	local function hash(id)
		local handle = routines.handle(id)
		return handle and handle.hash or nil
	end
	local c, s, t = hash(snapshot.current), hash(snapshot.secondary), hash(snapshot.ternary)
	if s == c then
		s = nil
	end
	if t == c or t == s then
		t = nil
	end
	return c, s, t
end

---Get the hashes of a snapshot's notes, as a note map holds them.
---
---@param notes SnapshotNote[]
---@return table<string, Filehash> map
local function map_of(notes)
	local map = {}
	for _, note in ipairs(notes) do
		local key, value = routines.handle(note.key), routines.handle(note.value)
		if key and value and key.hash ~= value.hash then
			map[key.hash .. (note.swap and "-swap" or "")] = value.hash
		end
	end
	return map
end

---Get what the window's winbar is drawn from while a snapshot shows there: its slots, its queue and
---its notes, as a triquetra holds them.
---
---@param winid WinId
---@return table|nil triquetra Nil when no snapshot shows there
function M.triquetra_of(winid)
	if not showing or showing.window ~= winid then
		return nil
	end
	local snapshot = showing.snapshot
	local c, s, t = slots_of(snapshot)
	local queue = {}
	for _, id in ipairs(snapshot.queue) do
		local handle = routines.handle(id)
		if handle then
			table.insert(queue, handle.hash)
		end
	end
	return {
		current_slot = c, secondary_slot = s, ternary_slot = t, primary_buffer = queue,
		primary_enabled = snapshot.primary_enabled,
		displacement_ternary_map = map_of(snapshot.dtm), displacement_secondary_map = map_of(snapshot.dsm),
	}
end

---Get the open buffers of the snapshot's stored order, the first drawn first.
---@return Bufnr[] buffers
function M.order()
	local buffers = {}
	for _, id in ipairs(showing and showing.snapshot.order or {}) do
		local handle = routines.handle(id)
		local bufnr = handle and history.get_buffer_from_hash(handle.hash)
		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			table.insert(buffers, bufnr)
		end
	end
	return buffers
end

---Redraw the UI once what shows changed.
---@return nil
local function repaint()
	require('frogman.domains.ui.sm').loop:to(require('frogman.domains.ui.states').LOOP.SELF)
end

---Show a snapshot in its window.
---
---A cycle running, or a snapshot whose current file is closed, shows nothing yet, and says so.
---
---@param snapshot Snapshot
---@param winid WinId
---@return boolean shown
function M.start(snapshot, winid)
	if require('frogman.domains.navigation').is_cycling() then
		vim.notify("frogman: pick or cancel the cycle first.", vim.log.levels.WARN)
		return false
	end
	local c = slots_of(snapshot)
	local bufnr = c and history.get_buffer_from_hash(c)
	if not bufnr then
		local name = c and require('frogman.domains.ui').routines.get_smart_basename(c) or "its current file"
		vim.notify("frogman: " .. name .. " is closed; showing a closed file comes with borrowing.", vim.log.levels.WARN)
		return false
	end
	if showing then
		M.cancel()
	end
	vim.api.nvim_set_current_win(winid)
	showing = { window = winid, snapshot = snapshot, before = vim.api.nvim_win_get_buf(winid) }
	history.sm:to(history.states.DETACHED, {}, history.states.mode.UPDATE)
	vim.api.nvim_win_set_buf(winid, bufnr)
	repaint()
	return true
end

---Step through the snapshot's stored order: toward its front (1) or toward its end (2).
---
---@param direction 1|2
---@return nil
function M.step(direction)
	if not showing or not vim.api.nvim_win_is_valid(showing.window) then
		return
	end
	local order = M.order()
	if #order == 0 then
		return
	end
	local shown, index = vim.api.nvim_win_get_buf(showing.window), 0
	for i, bufnr in ipairs(order) do
		if bufnr == shown then
			index = i
		end
	end
	local at = index == 0 and 1 or ((index - 1 + (direction == 1 and -1 or 1)) % #order) + 1
	vim.api.nvim_win_set_buf(showing.window, order[at])
	repaint()
end

---Leave the snapshot: its window goes back to what it showed, its slots untouched, and history
---attaches again on the window you're in, as a cycle's cancel attaches it (`attach_on_landing`).
---
---@return nil
function M.cancel()
	if not showing then
		return
	end
	local was = showing
	showing = nil
	if vim.api.nvim_win_is_valid(was.window) and vim.api.nvim_buf_is_valid(was.before) then
		vim.api.nvim_win_set_buf(was.window, was.before)
	end
	require('frogman.domains.navigation.routines').attach_on_landing()
	repaint()
end

---Take the snapshot onto its window, landing on the buffer it shows.
---
---One update writes the snapshot's slots, its notes laid over the window's, its queue first and the
---window's other entries after, and its switch; the buffer the preview left gets swap notes for its old
---ternary and secondary. In the window view the stored order goes into the window's history with fresh
---times, the first drawn the newest. Then history attaches on the buffer shown with a pick's rules, and
---that landing is a visit.
---
---@return nil
function M.commit()
	if not showing or not vim.api.nvim_win_is_valid(showing.window) then
		return
	end
	local winid, snapshot = showing.window, showing.snapshot
	local window = require('frogman.domains.window')
	local triquetra = window.data.get_window_triquetra(winid)
	if not triquetra then
		M.cancel()
		return
	end
	local left, old_s, old_t = triquetra.current_slot, triquetra.secondary_slot, triquetra.ternary_slot
	local c, s, t = slots_of(snapshot)
	triquetra:update({ current_slot = c, secondary_slot = s or vim.NIL, ternary_slot = t or vim.NIL })
	for key, value in pairs(map_of(snapshot.dtm)) do
		triquetra.displacement_ternary_map[key] = value
	end
	for key, value in pairs(map_of(snapshot.dsm)) do
		triquetra.displacement_secondary_map[key] = value
	end
	if left and left ~= c then
		-- the way back: the arrangement the preview replaced, as swap notes on the buffer it left
		if old_t and old_t ~= left then
			triquetra.displacement_ternary_map[left .. "-swap"] = old_t
		end
		if old_s and old_s ~= left then
			triquetra.displacement_secondary_map[left .. "-swap"] = old_s
		end
	end
	local queue, seen = {}, {}
	for _, id in ipairs(snapshot.queue) do
		local handle = routines.handle(id)
		if handle and not seen[handle.hash] then
			seen[handle.hash] = true
			table.insert(queue, handle.hash)
		end
	end
	for _, filehash in ipairs(triquetra.primary_buffer or {}) do
		if not seen[filehash] then
			seen[filehash] = true
			table.insert(queue, filehash)
		end
	end
	triquetra:set_queue(queue)
	triquetra.primary_enabled = snapshot.primary_enabled
	if require('frogman.configs').bufferline.history_view == "window" then
		-- the stored order into the window's own history, the first drawn the newest
		local own = history.data.crux_internals.window[winid] or {}
		history.data.crux_internals.window[winid] = own
		local order = {}
		for _, id in ipairs(snapshot.order) do
			local handle = routines.handle(id)
			if handle then
				table.insert(order, handle.hash)
			end
		end
		for i = #order, 1, -1 do
			own[order[i]] = history.data.history_index
			history.data.history_index = history.data.history_index + 1
		end
	end
	showing = nil
	vim.api.nvim_set_current_win(winid)
	history.sm:to(history.states.ATTACHED, { buf = vim.api.nvim_win_get_buf(winid), pick = true }, history.states.mode.UPDATE)
	window.routines.enforce_note_maps_policy(triquetra)
	repaint()
end

---Forget a snapshot showing, with no window switched, as a whole-editor load starts from nothing.
---@return nil
function M.teardown()
	showing = nil
end

return M
