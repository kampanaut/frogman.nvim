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

---What the preview made or borrowed for one file: its buffer, what that buffer was before (made by the
---preview, there unloaded, there loaded, or a placeholder), whether it was listed then, whether it holds
---a No Name text, and whether it was written while borrowed.
---@alias Borrowed {buf: Bufnr, was: "made"|"unloaded"|"loaded"|"placeholder", listed: boolean|nil, text: boolean|nil, written: boolean|nil}

---The snapshot showing: its window, the snapshot, the buffer the window showed before it, every buffer
---there as it began, loaded or not and listed or not, and the buffers it made or borrowed, by their
---files' handles, or by `new:<bufnr>` for a file frogman doesn't know.
---@type {window: WinId, snapshot: Snapshot, before: Bufnr, known: table<Bufnr, {loaded: boolean, listed: boolean}>, made: table<HandleId|string, Borrowed>}|nil
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

---Note that the buffer a snapshot shows is being deleted, so the preview ends once the editor settles, as
---a cancel ends it, saying why.
---
---@param bufnr Bufnr The buffer being deleted
---@return nil
function M.deleted(bufnr)
	if not showing or showing.ending or not vim.api.nvim_win_is_valid(showing.window)
		or vim.api.nvim_win_get_buf(showing.window) ~= bufnr then
		return
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	showing.ending = name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":t")
	local was = showing
	require('frogman.settle').later("preview ended", function()
		if showing == was then
			M.cancel()
			vim.notify("frogman: " .. was.ending .. " was deleted while the snapshot showed it, so the preview ended.",
				vim.log.levels.INFO)
		end
	end)
end

---Get the handles of a snapshot's slots, by the live slots' rule.
---
---A file a rename left in two of its slots stays in the current, and the secondary keeps one the
---current doesn't hold over the ternary.
---
---@param snapshot Snapshot The snapshot showing
---@return HandleId|nil current
---@return HandleId|nil secondary
---@return HandleId|nil ternary
local function slots_of(snapshot)
	local function live(id)
		local handle = routines.handle(id)
		return handle and handle.id or nil
	end
	local c, s, t = live(snapshot.current), live(snapshot.secondary), live(snapshot.ternary)
	if s == c then
		s = nil
	end
	if t == c or t == s then
		t = nil
	end
	return c, s, t
end

---Get a snapshot's notes as a note map holds them, by handle.
---
---@param notes SnapshotNote[] The snapshot's notes on one map
---@return table<HandleId|string, HandleId> map
local function map_of(notes)
	local map = {}
	for _, note in ipairs(notes) do
		local key, value = routines.handle(note.key), routines.handle(note.value)
		if key and value and key ~= value then
			map[note.swap and key.id .. "-swap" or key.id] = value.id
		end
	end
	return map
end

---Get what the window's winbar is drawn from while a snapshot shows there: its slots, its queue and
---its notes, as a triquetra holds them.
---
---@param winid WinId The window
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
			table.insert(queue, handle.id)
		end
	end
	return {
		current_slot = c, secondary_slot = s, ternary_slot = t, primary_buffer = queue,
		primary_enabled = snapshot.primary_enabled,
		displacement_ternary_map = map_of(snapshot.dtm), displacement_secondary_map = map_of(snapshot.dsm),
	}
end

---Get the buffers the preview made or borrowed in a window, by the handles of the files they show, for
---drawing them as the snapshot's slots. Another window's are none.
---
---@param winid WinId The window
---@return table<HandleId, Bufnr> buffers
function M.buffers(winid)
	local out = {}
	if showing and showing.window == winid then
		for id, made in pairs(showing.made) do
			if vim.api.nvim_buf_is_valid(made.buf) then
				out[id] = made.buf
			end
		end
	end
	return out
end

---Get the buffer the preview shows a snapshot's file in, making or borrowing one when it has to.
---
---An open file shows in its own buffer. A closed one is borrowed: loaded into a buffer frogman doesn't
---take in, so it's still counted closed, a No Name text from its text, read first when a load left it
---unread; it's listed while it's borrowed, so the bufferline gives it a tab. A file the slot keys call
---gone from disk shows as a placeholder, unlisted. Each is made once while the snapshot shows. A file
---whose name another buffer has, one that turned untracked, can't be shown, and nor can a text that's
---lost.
---
---@param id HandleId The file's handle
---@return Bufnr|nil bufnr
---@return string|nil why "taken" when another buffer has its name, "lost" when it's a text that's lost
local function buffer_for(id)
	local bufnr = history.get_buffer_from_handle(id)
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		return bufnr
	end
	local made = showing.made[id]
	if made and vim.api.nvim_buf_is_valid(made.buf) then
		return made.buf
	end
	local handle = history.handles.get(id)
	local filepath = history.get_filepath_from_handle(id)
	if filepath == nil then
		return nil
	end
	if require('frogman.domains.window').routines.is_missing(id) then
		bufnr = vim.api.nvim_create_buf(false, true)
		pcall(vim.api.nvim_buf_set_name, bufnr, "frogman://gone/" .. vim.fs.basename(filepath))
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { GONE })
		vim.bo[bufnr].modifiable = false
		showing.made[id] = { buf = bufnr, was = "placeholder" }
		return bufnr
	end
	if filepath:match("^NONAME_") then
		local text = handle.text
		if text and text.lines == nil and text.read then
			-- held unread from a session file: read now and kept read; one that's lost stays as it is, the
			-- preview writing nothing, and leaves the lists when a reopen can't read it
			text = text.read()
			if text ~= nil then
				handle.text = text
			end
		end
		if text == nil or text.lines == nil then
			return nil, "lost"
		end
		bufnr = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, text.lines)
		vim.bo[bufnr].filetype = text.filetype or ""
		vim.bo[bufnr].modified = false -- setting its lines marked it
		showing.made[id] = { buf = bufnr, was = "made", text = true }
		return bufnr
	end
	local holder = history.routines.find_buffer_by_filepath(filepath)
	if holder and vim.bo[holder].buftype ~= "" and not history.routines.is_nowrite_file(holder) then
		return nil, "taken"
	end
	local was = holder == nil and "made" or (vim.api.nvim_buf_is_loaded(holder) and "loaded" or "unloaded")
	bufnr = holder or vim.fn.bufadd(filepath)
	local listed = vim.bo[bufnr].buflisted
	if was ~= "loaded" then
		vim.fn.bufload(bufnr)
	end
	vim.bo[bufnr].buflisted = true -- its tab while it's borrowed
	showing.made[id] = { buf = bufnr, was = was, listed = listed }
	return bufnr
end

---Open a borrowed file for real: taken in and off the closed lists, as a reopen opens it. A No Name
---text comes back holding what its borrowed buffer holds, in a buffer of its own, which takes the
---borrowed one's place in any window showing it, and a file frogman didn't know is taken in as an
---arrival takes one in.
---
---@param id HandleId|string The file's handle, or `new:<bufnr>` for a file frogman didn't know
---@param made Borrowed What the preview borrowed for it
---@param say boolean Whether to say so: it was edited, not landed on
---@return nil
local function open_for_real(id, made, say)
	if type(id) == "string" then
		vim.bo[made.buf].buflisted = true
		if history.get_hash_from_buffer(made.buf) == nil and history.routines.is_trackable(made.buf) then
			history.routines.register_buffer(made.buf)
		end
		if say then
			vim.notify("frogman: " .. vim.fs.basename(vim.api.nvim_buf_get_name(made.buf)) ..
				" was edited while the snapshot showed it, so it's open now.", vim.log.levels.INFO)
		end
		return
	end
	local name = require('frogman.domains.ui').routines.get_smart_basename(id)
	if made.text then
		history.handles.get(id).text = { lines = vim.api.nvim_buf_get_lines(made.buf, 0, -1, false),
			filetype = vim.bo[made.buf].filetype, cursor = { 1, 0 } }
		local bufnr = history.routines.reopen_handle(id)
		if bufnr then
			for _, winid in ipairs(vim.fn.win_findbuf(made.buf)) do
				vim.api.nvim_win_set_buf(winid, bufnr)
			end
		end
		vim.api.nvim_buf_delete(made.buf, { force = true })
	elseif history.get_hash_from_buffer(made.buf) == nil then
		history.routines.reopen_handle(id)
	else
		vim.bo[made.buf].buflisted = true -- written while it showed, so taken in already
	end
	if say then
		vim.notify("frogman: " .. name .. " was edited while the snapshot showed it, so it's open now, off the closed lists.",
			vim.log.levels.INFO)
	end
end

---Give one buffer the preview made or borrowed back to what it was: a placeholder or one the borrow
---made is wiped, one that was there unloaded is unloaded again, as a file closed with :bdelete leaves
---its buffer, unless it's been unloaded since, and one already loaded is left; one the borrow listed is
---unlisted again, and one unlisted since, as :bdelete leaves it, stays so. One a window still shows stays.
---
---@param made Borrowed What the preview made or borrowed
---@return nil
local function give_back(made)
	local buf = made.buf
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	if made.was == "placeholder" then
		vim.api.nvim_buf_delete(buf, { force = true })
		return
	end
	if vim.bo[buf].buflisted and not made.listed then
		-- quietly: unlisting fires BufDelete, which would land a window still showing it elsewhere
		vim.api.nvim_buf_call(buf, function()
			vim.cmd("noautocmd setlocal nobuflisted")
		end)
	end
	if #vim.fn.win_findbuf(buf) > 0 then
		return
	end
	if made.was == "made" then
		vim.api.nvim_buf_delete(buf, { force = true })
	elseif made.was == "unloaded" and vim.api.nvim_buf_is_loaded(buf) then
		vim.api.nvim_buf_delete(buf, { unload = true })
	end
end

---Check if a buffer the preview borrowed was edited while it showed: unsaved changes in it, or a write
---made since it was borrowed. A rewrite that leaves it unmodified, or a reload, is no edit.
---
---@param made Borrowed What the preview borrowed
---@return boolean edited
local function edited(made)
	return vim.bo[made.buf].modified or made.written == true or history.get_hash_from_buffer(made.buf) ~= nil
end

---Give back what the preview made or borrowed, as the snapshot stops showing.
---
---Each goes back to what it was (`give_back`). One you edited since it was borrowed stays open
---instead, and so does the one a commit lands on: both are opened for real, a reopen's visit recorded
---in the window the snapshot showed in.
---
---@param was table The preview that showed
---@param keep HandleId|string|nil The key of the file a commit lands on
---@return nil
local function release(was, keep)
	for id, made in pairs(was.made) do
		if vim.api.nvim_buf_is_valid(made.buf) then
			if made.was ~= "placeholder" and (id == keep or edited(made)) then
				if vim.api.nvim_win_is_valid(was.window) then
					vim.api.nvim_win_call(was.window, function()
						open_for_real(id, made, id ~= keep)
					end)
				else
					open_for_real(id, made, id ~= keep)
				end
			else
				give_back(made)
			end
		end
	end
	was.made = {}
end

---Get the buffers the bufferline draws while a snapshot shows: the open and borrowed ones of its stored
---order, the first drawn first, then the ones `:e` borrowed outside it. A closed file not stepped onto
---yet has no buffer, and a placeholder no tab.
---@return Bufnr[] buffers
function M.order()
	local buffers, seen = {}, {}
	if not showing then
		return buffers
	end
	local function add(bufnr)
		if bufnr and vim.api.nvim_buf_is_valid(bufnr) and not seen[bufnr] then
			seen[bufnr] = true
			table.insert(buffers, bufnr)
		end
	end
	for _, id in ipairs(showing.snapshot.order) do
		local handle = routines.handle(id)
		local made = handle and showing.made[handle.id]
		add(handle and (history.get_buffer_from_handle(handle.id) or (made and made.was ~= "placeholder" and made.buf or nil)))
	end
	local outside = {}
	for _, made in pairs(showing.made) do
		if made.was ~= "placeholder" and not seen[made.buf] then
			table.insert(outside, made.buf)
		end
	end
	table.sort(outside)
	for _, bufnr in ipairs(outside) do
		add(bufnr)
	end
	return buffers
end

---Check if a buffer is one the preview borrowed, which the bufferline draws dimmed, as a closed file.
---
---@param bufnr Bufnr The buffer
---@return boolean borrowed
function M.borrowed(bufnr)
	for _, made in pairs(showing and showing.made or {}) do
		if made.buf == bufnr and made.was ~= "placeholder" then
			return true
		end
	end
	return false
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
---@param snapshot Snapshot The snapshot to show
---@param winid WinId The window to show it in
---@return boolean shown
function M.start(snapshot, winid)
	if require('frogman.domains.navigation').is_cycling() then
		vim.notify("frogman: pick or cancel the cycle first.", vim.log.levels.WARN)
		return false
	end
	if vim.wo[winid].winfixbuf then
		vim.notify("frogman: window " .. vim.api.nvim_win_get_number(winid) ..
			" keeps its buffer ('winfixbuf'), so a snapshot can't show there.", vim.log.levels.WARN)
		return false
	end
	if showing then
		M.cancel()
	end
	local c = slots_of(snapshot)
	local known = {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		known[bufnr] = { loaded = vim.api.nvim_buf_is_loaded(bufnr), listed = vim.bo[bufnr].buflisted }
	end
	showing = { window = winid, snapshot = snapshot, before = vim.api.nvim_win_get_buf(winid), made = {}, known = known,
		tracked = require('frogman.domains.window').data.crux[winid] ~= nil }
	local found, bufnr, why = true, nil, nil
	if c then
		found, bufnr, why = pcall(buffer_for, c)
	end
	if found and not bufnr and why == "lost" then
		-- its current gone, the snapshot falls back, keeping its place
		local shown = nil
		routines.fall_back(snapshot, function(id)
			local ok, made = pcall(buffer_for, id)
			shown = ok and made or nil
			return shown ~= nil
		end)
		bufnr = shown
	end
	if not found then
		-- the world's: a swap file's prompt answered Abort, an autocmd of the user's raising
		local problem = bufnr
		release(showing, nil)
		showing = nil
		vim.notify("frogman: " .. require('frogman.domains.ui').routines.get_smart_basename(c) ..
			" couldn't be loaded to show it: " .. tostring(problem), vim.log.levels.WARN)
		return false
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
---@param direction 1|2 Toward the order's front (1) or toward its end (2)
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
		if handle and (history.get_buffer_from_handle(handle.id) == shown or own[handle.id] == shown) then
			index = i
		end
	end
	for n = 1, #order do
		local at = index == 0 and n or ((index - 1 + n * (direction == 1 and -1 or 1)) % #order) + 1
		local handle = routines.handle(order[at])
		local bufnr = handle and buffer_for(handle.id)
		if bufnr then
			vim.api.nvim_win_set_buf(showing.window, bufnr)
			repaint()
			return
		end
	end
end

---Borrow a buffer `:e` opened in the snapshot's window, as a step borrows a closed file: a file frogman
---knows by its handle, one it doesn't know by its buffer, and a file the slot keys call gone from disk as
---its placeholder while the window still shows it, the buffer `:e` opened going back. An open file, one
---the preview made or borrowed already, and something frogman doesn't track are left as they are.
---
---@param bufnr Bufnr The buffer `:e` opened there, which a later `:e` in the same batch may have replaced
---@return nil
function M.borrow(bufnr)
	if not showing or not vim.api.nvim_win_is_valid(showing.window) or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	for _, made in pairs(showing.made) do
		if made.buf == bufnr then
			return
		end
	end
	if history.get_hash_from_buffer(bufnr) ~= nil or not history.routines.is_trackable(bufnr) then
		return
	end
	local before = showing.known[bufnr]
	local made = { buf = bufnr, was = before == nil and "made" or (before.loaded and "loaded" or "unloaded"),
		listed = before ~= nil and before.listed }
	local name = vim.api.nvim_buf_get_name(bufnr)
	local id = name ~= "" and history.get_handle_from_filepath(name) or nil
	if id and require('frogman.domains.window').routines.is_missing(id) then
		if vim.api.nvim_win_get_buf(showing.window) == bufnr then
			vim.api.nvim_win_set_buf(showing.window, buffer_for(id))
		end
		vim.b[bufnr].frogman_unwritten = nil -- :e's new-file mark, which an unloaded buffer would keep for its reopen
		give_back(made)
	else
		showing.made[id or ("new:" .. bufnr)] = made -- listed by the :e, its tab while it's borrowed
	end
	repaint()
end

---Note a write of a buffer the preview borrowed, which counts as an edit once the preview ends.
---
---@param bufnr Bufnr The buffer written
---@return nil
function M.written(bufnr)
	for _, made in pairs(showing and showing.made or {}) do
		if made.buf == bufnr then
			made.written = true
		end
	end
end

---Put the snapshot's window back on what it showed before it. When that buffer can't come back, wiped
---or deleted since, the window shows its current slot, the file reopened when it's closed, its visit in
---that window, or, with none, an empty buffer. A borrowed file it reopens is opened for real, as a
---commit opens the one it lands on.
---
---@param was table The preview that showed
---@return nil
local function show_earlier(was)
	if not vim.api.nvim_win_is_valid(was.window) then
		return
	end
	local before = was.known[was.before]
	if vim.api.nvim_buf_is_valid(was.before) and (vim.api.nvim_buf_is_loaded(was.before) or not (before and before.loaded)) then
		vim.api.nvim_win_set_buf(was.window, was.before)
		return
	end
	-- a window frogman never took in has only what the preview showed it, which the cancel takes back
	local triquetra = was.tracked and require('frogman.domains.window').data.crux[was.window] or nil
	local id = triquetra and triquetra.current_slot
	local bufnr = id and history.get_buffer_from_handle(id)
	if id and bufnr == nil then
		local made = was.made[id]
		if made and made.was ~= "placeholder" and vim.api.nvim_buf_is_valid(made.buf) then
			was.made[id] = nil
			vim.api.nvim_win_call(was.window, function()
				open_for_real(id, made, edited(made))
			end)
			bufnr = history.get_buffer_from_handle(id)
		else
			vim.api.nvim_win_call(was.window, function()
				bufnr = history.routines.reopen_handle(id)
			end)
		end
	end
	if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then
		bufnr = vim.api.nvim_create_buf(true, false) -- a new buffer, as :enew shows one
	end
	vim.api.nvim_win_set_buf(was.window, bufnr)
end

---Leave the snapshot: its window goes back to what it showed (`show_earlier`), its slots untouched,
---and history attaches again on the window you're in, as a cycle's cancel attaches it
---(`attach_on_landing`).
---
---@return nil
function M.cancel()
	if not showing then
		return
	end
	local was = showing
	showing = nil
	show_earlier(was)
	release(was, nil) -- before history attaches, so a window still showing a borrow doesn't take it in
	require('frogman.domains.navigation.routines').attach_on_landing()
	-- a window frogman never took in got a triquetra from what the preview showed it; the cancel takes it back
	local window = require('frogman.domains.window')
	if not was.tracked and vim.api.nvim_win_is_valid(was.window) and window.data.crux[was.window] then
		window.data.unregister_triquetra(was.window)
	end
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
	local ledger = require('frogman.domains.ledger')
	local before = ledger.slots(winid)
	local shown, landing = vim.api.nvim_win_get_buf(winid), nil
	for id, made in pairs(showing.made) do
		if made.buf == shown and made.was == "placeholder" then
			vim.notify("frogman: " .. require('frogman.domains.ui').routines.get_smart_basename(id) ..
				" isn't on disk; step onto another file to take the snapshot.", vim.log.levels.WARN)
			return
		elseif made.buf == shown then
			landing = id
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
	if left then
		-- the way back: the arrangement the preview replaced, as swap notes on the buffer it left, the
		-- snapshot's own current too
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
		if handle and not seen[handle.id] then
			seen[handle.id] = true
			table.insert(queue, handle.id)
		end
	end
	for _, id in ipairs(triquetra.primary_buffer or {}) do
		if not seen[id] then
			seen[id] = true
			table.insert(queue, id)
		end
	end
	triquetra:set_queue(queue)
	triquetra.primary_enabled = snapshot.primary_enabled
	if require('frogman.configs').bufferline.history_view == "window" then
		-- the stored order into the window's own history, the first drawn the newest
		local order = {}
		for _, id in ipairs(snapshot.order) do
			local handle = routines.handle(id)
			if handle then
				table.insert(order, handle.id)
			end
		end
		history.routines.lay_in_order(winid, order)
	end
	showing = nil
	vim.api.nvim_set_current_win(winid)
	history.sm:to(history.states.ATTACHED, { buf = vim.api.nvim_win_get_buf(winid), pick = true, commit = true },
		history.states.mode.UPDATE)
	window.routines.enforce_note_maps_policy(triquetra)
	ledger.slots_moved("committed", winid, before, { words = "snapshot committed" })
	repaint()
end

---End a snapshot showing as a load starts over: what it made or borrowed goes back, and what you
---edited is opened for real, as a cancel releases them. At a whole-editor load its window goes back to
---what it showed, as a cancel puts it back (`show_earlier`), history attaching with the load; at a tab
---session's load into its tab, the window is the load's to lay out.
---
---@param whole boolean Whether it's a whole-editor load, before the windows' own teardown
---@return nil
function M.teardown(whole)
	local was = showing
	showing = nil
	if not was then
		return
	end
	if whole then
		show_earlier(was)
	end
	release(was, nil)
end

return M
