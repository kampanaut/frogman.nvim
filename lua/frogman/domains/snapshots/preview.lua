---A snapshot shown in its window, to take with <M-v> or to leave.
---
---While it shows, history is detached as a cycle detaches it, so nothing the window shows is recorded,
---and the winbar and the bufferline draw the snapshot's slots and its stored order. The cycle keys
---step through that order, <M-v> takes the snapshot onto the window, and opening the snapshot list or
---going to another window leaves it, the window back on what it showed. A closed file it shows is
---borrowed, still counted closed, and a file gone from disk shows as a placeholder.

local routines = require('frogman.domains.snapshots.routines')
local history = require('frogman.domains.history')

local M = {}

---The snapshot showing: its window, the snapshot, the buffer the window showed before it, and the
---buffers it made or borrowed to show closed files, by their hashes, each with what it was before.
---@type {window: WinId, snapshot: Snapshot, before: Bufnr, made: table<Filehash, {buf: Bufnr, was: "made"|"unloaded"|"loaded"|"placeholder", text: boolean|nil, tick: integer|nil}>}|nil
local showing = nil

---The words a placeholder holds
local GONE = "[This file has been deleted off the disk]"

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

---Get the buffers the preview made or borrowed in a window, by the hashes they show, for drawing them as
---the snapshot's slots. Another window's are none.
---
---@param winid WinId
---@return table<Filehash, Bufnr> buffers
function M.buffers(winid)
	local out = {}
	if showing and showing.window == winid then
		for filehash, made in pairs(showing.made) do
			if vim.api.nvim_buf_is_valid(made.buf) then
				out[filehash] = made.buf
			end
		end
	end
	return out
end

---Get the buffer the preview shows a snapshot's file in, making or borrowing one when it has to.
---
---An open file shows in its own buffer. A closed one is borrowed: loaded into an unlisted buffer that
---frogman doesn't take in, so it's still counted closed, a No Name text from its text, read first when
---a load left it unread. A file the slot keys call gone from disk shows as a placeholder. Each is made
---once while the snapshot shows. A file whose name another buffer has, one that turned untracked,
---can't be shown, and nor can a text that's lost.
---
---@param filehash Filehash
---@return Bufnr|nil bufnr
---@return string|nil why "taken" when another buffer has its name
local function buffer_for(filehash)
	local bufnr = history.get_buffer_from_hash(filehash)
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		return bufnr
	end
	local made = showing.made[filehash]
	if made and vim.api.nvim_buf_is_valid(made.buf) then
		return made.buf
	end
	local filepath = history.get_filepath_from_hash(filehash)
	if filepath == nil then
		return nil
	end
	if require('frogman.domains.window').routines.is_missing(filehash) then
		bufnr = vim.api.nvim_create_buf(false, true)
		pcall(vim.api.nvim_buf_set_name, bufnr, "frogman://gone/" .. vim.fs.basename(filepath))
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { GONE })
		vim.bo[bufnr].modifiable = false
		showing.made[filehash] = { buf = bufnr, was = "placeholder" }
		return bufnr
	end
	if filepath:match("^NONAME_") then
		local text = history.data.noname_content[filehash]
		if text and text.lines == nil and text.read then
			-- held unread from a session file: read now and kept read; one that's lost leaves every list,
			-- as a reopen that can't read it finds it
			text = text.read()
			history.data.noname_content[filehash] = text
			if text == nil then
				history.routines.discard_from_pools(filehash)
			end
		end
		if text == nil or text.lines == nil then
			return nil
		end
		bufnr = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, text.lines)
		vim.bo[bufnr].filetype = text.filetype or ""
		vim.bo[bufnr].modified = false -- setting its lines marked it
		showing.made[filehash] = { buf = bufnr, was = "made", text = true, tick = vim.b[bufnr].changedtick }
		return bufnr
	end
	local holder = history.routines.find_buffer_by_filepath(filepath)
	if holder and vim.bo[holder].buftype ~= "" and not history.routines.is_nowrite_file(holder) then
		return nil, "taken"
	end
	local was = holder == nil and "made" or (vim.api.nvim_buf_is_loaded(holder) and "loaded" or "unloaded")
	bufnr = holder or vim.fn.bufadd(filepath)
	if was ~= "loaded" then
		vim.fn.bufload(bufnr)
	end
	-- its changes counted from here, so one written since, no longer modified, is still edited
	showing.made[filehash] = { buf = bufnr, was = was, tick = vim.b[bufnr].changedtick }
	return bufnr
end

---Open a borrowed file for real: taken in and off the closed lists, as a reopen opens it. A No Name
---text comes back holding what its borrowed buffer holds, in a buffer of its own, which takes the
---borrowed one's place in any window showing it.
---
---@param filehash Filehash
---@param made table What the preview borrowed for it
---@param say boolean Whether to say so: it was edited, not landed on
---@return nil
local function open_for_real(filehash, made, say)
	local name = require('frogman.domains.ui').routines.get_smart_basename(filehash)
	if made.text then
		history.data.noname_content[filehash] = { lines = vim.api.nvim_buf_get_lines(made.buf, 0, -1, false),
			filetype = vim.bo[made.buf].filetype, cursor = { 1, 0 } }
		local bufnr = history.routines.reopen_filehash(filehash)
		if bufnr then
			for _, winid in ipairs(vim.fn.win_findbuf(made.buf)) do
				vim.api.nvim_win_set_buf(winid, bufnr)
			end
		end
		vim.api.nvim_buf_delete(made.buf, { force = true })
	elseif history.get_hash_from_buffer(made.buf) == nil then
		history.routines.reopen_filehash(filehash)
	else
		vim.bo[made.buf].buflisted = true -- written while it showed, so taken in already
	end
	if say then
		vim.notify("frogman: " .. name .. " was edited while the snapshot showed it, so it's open now, off the closed lists.",
			vim.log.levels.INFO)
	end
end

---Give back what the preview made or borrowed, as the snapshot stops showing.
---
---A placeholder is wiped. A borrowed buffer goes back to what it was: one the borrow made is wiped, one
---that was there unloaded is unloaded again, as a file closed with :bdelete leaves its buffer, and one
---already loaded is left; one a window still shows stays. One you edited since it was borrowed, written
---or not, stays open instead, and so does the one a commit lands on: both are opened for real, a
---reopen's visit recorded in the window the snapshot showed in.
---
---@param was table The preview that showed
---@param keep Filehash|nil The file a commit lands on
---@return nil
local function release(was, keep)
	for filehash, made in pairs(was.made) do
		local buf = made.buf
		if vim.api.nvim_buf_is_valid(buf) then
			local edited = vim.bo[buf].modified or vim.b[buf].changedtick ~= made.tick or history.get_hash_from_buffer(buf) ~= nil
			if made.was == "placeholder" then
				vim.api.nvim_buf_delete(buf, { force = true })
			elseif filehash == keep or edited then
				if vim.api.nvim_win_is_valid(was.window) then
					vim.api.nvim_win_call(was.window, function()
						open_for_real(filehash, made, filehash ~= keep)
					end)
				else
					open_for_real(filehash, made, filehash ~= keep)
				end
			elseif made.was == "made" and #vim.fn.win_findbuf(buf) == 0 then
				vim.api.nvim_buf_delete(buf, { force = true })
			elseif made.was == "unloaded" and #vim.fn.win_findbuf(buf) == 0 then
				vim.api.nvim_buf_delete(buf, { unload = true })
			end
		end
	end
	was.made = {}
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

---Show a snapshot in its window, its current file borrowed when it's closed, or its placeholder.
---
---A cycle running shows nothing, and says so, and so does a current file whose name another buffer
---has; a text that's lost shows nothing, its reader having said so.
---
---@param snapshot Snapshot
---@param winid WinId
---@return boolean shown
function M.start(snapshot, winid)
	if require('frogman.domains.navigation').is_cycling() then
		vim.notify("frogman: pick or cancel the cycle first.", vim.log.levels.WARN)
		return false
	end
	if showing then
		M.cancel()
	end
	local c = slots_of(snapshot)
	showing = { window = winid, snapshot = snapshot, before = vim.api.nvim_win_get_buf(winid), made = {} }
	local bufnr, why = nil, nil
	if c then
		bufnr, why = buffer_for(c)
	end
	if not bufnr then
		showing = nil
		if why == "taken" then
			vim.notify("frogman: " .. require('frogman.domains.ui').routines.get_smart_basename(c) ..
				" can't be shown while another buffer has its name.", vim.log.levels.WARN)
		end
		return false
	end
	vim.api.nvim_set_current_win(winid)
	history.sm:to(history.states.DETACHED, {}, history.states.mode.UPDATE)
	vim.api.nvim_win_set_buf(winid, bufnr)
	repaint()
	return true
end

---Step through the snapshot's stored order: toward its front (1) or toward its end (2).
---
---A closed file is borrowed and a file gone from disk shows its placeholder; one that can't be shown,
---its name another buffer's or its text lost, is stepped over.
---
---@param direction 1|2
---@return nil
function M.step(direction)
	if not showing or not vim.api.nvim_win_is_valid(showing.window) then
		return
	end
	local order = showing.snapshot.order
	if #order == 0 then
		return
	end
	local shown, index = vim.api.nvim_win_get_buf(showing.window), 0
	local own = M.buffers(showing.window)
	for i, id in ipairs(order) do
		local handle = routines.handle(id)
		if handle and (history.get_buffer_from_hash(handle.hash) == shown or own[handle.hash] == shown) then
			index = i
		end
	end
	for n = 1, #order do
		local at = index == 0 and n or ((index - 1 + n * (direction == 1 and -1 or 1)) % #order) + 1
		local handle = routines.handle(order[at])
		local bufnr = handle and buffer_for(handle.hash)
		if bufnr then
			vim.api.nvim_win_set_buf(showing.window, bufnr)
			repaint()
			return
		end
	end
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
	release(was, nil)
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
	local shown, landing = vim.api.nvim_win_get_buf(winid), nil
	for filehash, made in pairs(showing.made) do
		if made.buf == shown and made.was == "placeholder" then
			vim.notify("frogman: " .. require('frogman.domains.ui').routines.get_smart_basename(filehash) ..
				" isn't on disk; step onto another file to take the snapshot.", vim.log.levels.WARN)
			return
		elseif made.buf == shown then
			landing = filehash
		end
	end
	-- the file it lands on opened for real, before its slots are read, and the rest given back
	release(showing, landing)
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
---
---What it made or borrowed and no window shows goes back as a release gives it back, but one you
---edited, which keeps its buffer.
---
---@return nil
function M.teardown()
	local was = showing
	showing = nil
	for _, made in pairs(was and was.made or {}) do
		local buf = made.buf
		if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) == 0 and not vim.bo[buf].modified then
			if made.was == "unloaded" then
				vim.api.nvim_buf_delete(buf, { unload = true })
			elseif made.was ~= "loaded" then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
	end
end

return M
