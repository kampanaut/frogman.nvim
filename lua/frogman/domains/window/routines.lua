---Window domain core routines for buffer relationship management.
---
---This module contains the main business logic for managing triquetra buffer
---relationships within windows, including the complex reconciliation logic
---that was previously in sync_detached_history().

local data = require('frogman.domains.window.data')

local history = require('frogman.domains.history')
local loop_sm = require('frogman.domains.ui.sm').loop
local loop_states = require('frogman.domains.ui.states').LOOP

local M = {}

---Rewrite the arriving buffer's ternary note when it has gone stale.
---
---When a buffer becomes current by anything but plain navigation onto it (displacement_mangement
---checks that route itself), its plain ternary note can name the buffer now in the ternary, and
---restoring it would throw. The note is rewritten to the buffer from before, as navigation's check
---does it:
--- - the buffer left went into the ternary: the pre-jump stored ternary if the arriving buffer was
---   the ternary, otherwise the pre-jump ternary
--- - the ternary stayed put: the ternary's own plain note
---It's dropped when that would name the arriving buffer or the ternary itself.
---
---@param triquetra WindowTriquetra The window's triquetra
---@param arrived HandleId The handle of the buffer that became current
---@param left HandleId The handle of the buffer it replaced
---@param ternary_before HandleId|nil The ternary before the arrival
---@param ternary_after HandleId|nil The ternary after the arrival
---@return nil
function M.enforce_ternary_map_policy(triquetra, arrived, left, ternary_before, ternary_after)
	local dtm = triquetra.displacement_ternary_map
	if arrived == nil or ternary_after == nil or dtm[arrived] ~= ternary_after then
		return
	end
	local older
	if ternary_after == left then
		if arrived == ternary_before then older = dtm[left] else older = ternary_before end
	else
		older = dtm[ternary_before]
	end
	if older == arrived or older == ternary_after then
		older = nil
	end
	require('frogman.domains.ledger').note("ternary", arrived, dtm[arrived], older, "stale")
	dtm[arrived] = older
end

---Rewrite the current buffer's secondary note when it has gone stale.
---
---A plain secondary note that names the window's secondary would make the restore throw. It's
---rewritten to the buffer's swap note when that names another buffer, otherwise it's dropped.
---
---@param triquetra WindowTriquetra The window's triquetra
---@param current HandleId|nil The current buffer's handle
---@param secondary HandleId|nil The window's secondary
---@return nil
function M.enforce_secondary_map_policy(triquetra, current, secondary)
	local dsm = triquetra.displacement_secondary_map
	if current == nil or secondary == nil or dsm[current] ~= secondary then
		return
	end
	local older = dsm[current .. "-swap"]
	if older ~= nil and older ~= secondary and older ~= current then
		dsm[current] = older
	else
		dsm[current] = nil
	end
	require('frogman.domains.ledger').note("secondary", current, secondary, dsm[current], "stale")
end

---Write the notes of a swap onto the secondary.
---
---Every route onto the secondary writes them: <M-f>, its <M-;><M-f> fallback, and plain navigation
---onto the secondary. The buffer left gets swap notes for its secondary and its ternary. The
---secondary's own swap note becomes its plain note when it names another buffer, and a plain note
---naming the buffer left is cleared, so a round trip can't leave it stale.
---
---@param triquetra WindowTriquetra The window's triquetra, before the swap
---@return nil
function M.write_secondary_swap_notes(triquetra)
	local current, secondary, ternary = triquetra.current_slot, triquetra.secondary_slot, triquetra.ternary_slot
	local dsm = triquetra.displacement_secondary_map
	local older = dsm[secondary .. "-swap"]
	dsm[current .. "-swap"] = secondary
	if older ~= nil and older ~= current then
		dsm[secondary] = older
	elseif dsm[secondary] == current then
		dsm[secondary] = nil
	end
	if ternary then
		triquetra.displacement_ternary_map[current .. "-swap"] = ternary
	end
end

---Check the current buffer's notes after a slot changed under it.
---
---Runs where a slot changes with no buffer becoming current: the restores' exchanges, graduation,
---the history fill, and a cleanup pass that moved slots. A ternary note naming the ternary becomes
---the ternary's own plain note, or is dropped when that names the current buffer or the ternary. A
---secondary note naming the secondary is rewritten as `M.enforce_secondary_map_policy()` does it.
---
---@param triquetra WindowTriquetra The window's triquetra
---@return nil
function M.enforce_note_maps_policy(triquetra)
	local current, ternary = triquetra.current_slot, triquetra.ternary_slot
	if current == nil then
		return
	end
	local dtm = triquetra.displacement_ternary_map
	if ternary ~= nil and dtm[current] == ternary then
		local older = dtm[ternary]
		if older == current or older == ternary then
			older = nil
		end
		require('frogman.domains.ledger').note("ternary", current, ternary, older, "stale")
		dtm[current] = older
	end
	M.enforce_secondary_map_policy(triquetra, current, triquetra.secondary_slot)
end

---Remember a window's triquetra from just before a buffer arrives in it.
---
---Used by `M.undo_arrival()` to put the window back.
---
---@param winid WinId The window it arrives in
---@param triquetra WindowTriquetra The window's triquetra before the arrival
---@param id HandleId The arriving buffer's handle
---@return nil
function M.remember_arrival(winid, triquetra, id)
	data.arrivals[winid] = { id = id, before = vim.deepcopy(triquetra) }
end

---Remember a window's triquetra from just after a buffer arrived in it.
---
---An arrival is undone only while nothing else has changed the triquetra since.
---
---@param winid WinId The window it arrived in
---@param triquetra WindowTriquetra The window's triquetra after the arrival
---@return nil
function M.seal_arrival(winid, triquetra)
	local arrival = data.arrivals[winid]
	if arrival and arrival.id == triquetra.current_slot then
		arrival.after = vim.deepcopy(triquetra)
	end
end


---Resolve the next slot in line into a window's current slot, for a current slot that's gone.
---
---The next slot in line is the first open one of the ternary, the secondary, the primary and the
---most recent open buffer. A slot is open when its buffer is registered, valid and still tracked; a
---closed one keeps its place and isn't reopened. The ternary or the secondary it came from is
---emptied, and the primary queue stays.
---
---@param triquetra WindowTriquetra The window's triquetra
---@param except Bufnr|nil A buffer that doesn't count as open, the one going
---@return "ternary"|"secondary"|"primary"|"recent"|nil from Where it came from, nil when none is open
---@return Bufnr|nil bufnr The buffer it holds
local function resolve_next_slot(triquetra, except)
	local function open(id)
		local bufnr = id and history.get_buffer_from_handle(id)
		if bufnr and bufnr ~= except and vim.api.nvim_buf_is_valid(bufnr) and history.routines.is_trackable(bufnr) then
			return bufnr
		end
	end
	local bufnr = open(triquetra.ternary_slot)
	if bufnr then
		triquetra:update({ current_slot = triquetra.ternary_slot, ternary_slot = vim.NIL })
		return "ternary", bufnr
	end
	bufnr = open(triquetra.secondary_slot)
	if bufnr then
		triquetra:update({ current_slot = triquetra.secondary_slot, secondary_slot = vim.NIL })
		return "secondary", bufnr
	end
	bufnr = open(triquetra.primary_buffer[1])
	if bufnr then
		triquetra:set("current_slot", triquetra.primary_buffer[1])
		return "primary", bufnr
	end
	-- the most recent buffer, in the bufferline's order (it follows history_view).
	for _, item in ipairs(history.get_ordered_buffers()) do
		local id = history.get_handle_from_buffer(item.buf)
		if id and id ~= triquetra.current_slot and open(id) then
			triquetra:set("current_slot", id)
			return "recent", item.buf
		end
	end
end
---Copy a No Name buffer's text, its lines, filetype and cursor, as it turns into something frogman
---doesn't track.
---
---@param bufnr Bufnr The buffer turning
---@return { lines: string[], filetype: string, cursor: integer[] }|nil text The copy, or nil when it isn't a registered No Name buffer
function M.copy_noname_text(bufnr)
	local filepath = history.get_filepath_from_buffer(bufnr)
	if not filepath or not filepath:match("^NONAME_") then
		return nil
	end
	local winid = vim.fn.bufwinid(bufnr)
	return {
		lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
		filetype = vim.bo[bufnr].filetype,
		cursor = winid ~= -1 and vim.api.nvim_win_get_cursor(winid) or { 1, 0 },
	}
end

---Close a buffer's file once the buffer turned into something frogman doesn't track.
---
---Runs when the buffer's buftype changed after it was slotted. Its file isn't open any more, and
---another buffer has taken its name, so it's closed as a delete closes it: onto its lists, with its
---history kept, and every slot, queue entry and note holding it keeps it. A window it just arrived in
---gets back the slots and notes it had before, and is visiting it. Any other window whose current
---slot it was keeps it there, closed, visiting the buffer that took its name.
---
---@param bufnr Bufnr The buffer that turned
---@param text { lines: string[], filetype: string, cursor: integer[] }|nil A No Name buffer's text, copied as it turned
---@return nil
function M.undo_arrival(bufnr, text)
	local id = history.get_handle_from_buffer(bufnr)
	if not id then
		return
	end
	local ledger = require('frogman.domains.ledger')
	for winid, triquetra in pairs(data.crux) do
		local arrival = data.arrivals[winid]
		if
			triquetra.current_slot == id and arrival and arrival.id == id and arrival.after and
			vim.deep_equal(arrival.after, triquetra)
		then
			local before = ledger.slots(winid)
			local restored = {}
			-- the copy keeps no file: one let go since left it as it went (`let_go_arrivals`)
			for _, key in ipairs({ "current_slot", "secondary_slot", "ternary_slot", "primary_buffer",
				"primary_enabled", "displacement_ternary_map", "displacement_secondary_map" }) do
				restored[key] = arrival.before[key] == nil and vim.NIL or arrival.before[key]
			end
			triquetra:update(restored)
			-- a current slot let go or closed since falls to the next open one, as a landing does; a closed
			-- one stays when there's none, and a window with nothing to come back to loses its triquetra
			if triquetra.current_slot == nil or history.get_buffer_from_handle(triquetra.current_slot) == nil then
				if not resolve_next_slot(triquetra, bufnr) and triquetra.current_slot == nil then
					data.unregister_triquetra(winid)
				end
			end
			if data.crux[winid] then
				ledger.slots_moved("undone", winid, before, { words = "its buffer turned into something untracked" })
				M.enforce_note_maps_policy(triquetra) -- a slot changed under the current buffer.
			else
				ledger.move("dropped", { subject = tostring(winid), name = ledger.window_name(winid),
					words = "its buffer turned into something untracked, with nothing to come back to" })
			end
		end
		if arrival and arrival.id == id then
			data.arrivals[winid] = nil
		end
	end
	-- a close: the file goes on its lists, and whatever holds it keeps it
	local close = history.routines.closing(bufnr, text)
	if close then
		history.routines.close(close)
	end
	loop_sm:to(loop_states.SELF)
end

---This will take in FILEPATHS and validates the input FILEPATHS, to be put as the
---new primary buffers history for the triquetra.
---
---The lines it would leave out are asked about first, in one prompt. No saves nothing, and a path
---typed in isn't registered either.
---
---@param primary_filepaths Filepath[] The filepaths to update in the primary buffer
---@param winid WinId The window ID to update the primary buffer for
---@return boolean saved False when the prompt was answered no
---@return integer|nil at The index in primary_filepaths of the first line left out, when not saved
function M.update_primary_buffer(primary_filepaths, winid)
	local triquetra = data.get_window_triquetra(winid)

	if not triquetra then
		error("No triquetra found for window " .. winid)
	end

	local error_lines = {}
	local first_error = nil -- where the first line left out is, for the cursor when it's not saved
	local to_register = {} -- registered, and put on the closed stack, only once it's saved
	local valid_filepaths = {}
	local seen = {}
	local queued = {} -- what the queue holds now: an entry gone from disk stays, as every pointer does
	for _, id in ipairs(triquetra.primary_buffer) do
		queued[id] = true
	end
	for index, filepath in ipairs(primary_filepaths) do
		local typed = filepath -- the messages name the line as it was typed
		local errors_before = #error_lines
		if not filepath:match("^NONAME_") and vim.trim(filepath) ~= "" then
			filepath = vim.fn.fnamemodify(filepath, ":p") -- a relative path, as :e takes it
		end
		local fbufnr = history.routines.find_buffer_by_filepath(filepath) or -1 -- by its exact name, not a pattern
		if vim.trim(filepath) == "" then
			goto continue
		elseif seen[filepath] then -- the queue holds a file once
			table.insert(error_lines, "- Repeated: " .. typed)
			goto continue
		elseif (vim.fn.filereadable(filepath) == 0) and (not filepath:match("^NONAME_")) and not queued[history.get_handle_from_filepath(filepath)] then -- If it's a file that doesn't exist in the filesystem.
			table.insert(error_lines, "- File does not exist: " .. typed)
			goto continue
		elseif fbufnr ~= -1 and vim.api.nvim_buf_is_loaded(fbufnr) and history.get_hash_from_buffer(fbufnr) == nil then -- THE USER CANNOT REGISTER A BUFFER EXPLICITLY. IT IS DONE AUTOMATICALLY. SO we throw error instead of automatically registering it.
			-- history.register_buffer(fbufnr)
			table.insert(error_lines,
				"- You cannot set the file buffer [" ..
				typed .. "] that isn't tracked by frogman to be a primary buffer.")
			goto continue
		elseif (fbufnr == -1 or not vim.api.nvim_buf_is_loaded(fbufnr)) and history.get_hash_from_filepath(filepath) == nil then -- If the filepath is not loaded by neovim and is not registered then register it.
			if filepath:match("^NONAME_") then                                 -- If the buffer_from_filepath query turned out to be nil and the filepath was just for NO NAME buffer then that means this NO_NAME buffer you have never existed, since the registry says so.
				table.insert(error_lines,
					" - [" ..
					filepath ..
					"] is not a registered no name buffer. You can only add registered no name buffers to the primary buffer.")
				goto continue
			else
				table.insert(to_register, filepath)
			end
		end
		table.insert(valid_filepaths, filepath)
		seen[filepath] = true
		::continue::
		if #error_lines > errors_before and not first_error then
			first_error = index
		end
	end

	if #error_lines > 0 and vim.fn.confirm("frogman: these lines would be left out:\n" .. table.concat(error_lines, "\n") ..
			"\nSave the rest?", "&Yes\n&No", 2) ~= 1 then
		return false, first_error
	end
	for _, filepath in ipairs(to_register) do
		history.register_filepath(filepath)
		local id = history.get_handle_from_filepath(filepath)
		if id then
			history.routines.track_closing_handle_force(id) -- It's fine, this line guarantees that the filepath is not NONAME_
		end
	end

	-- the primary switches on only when the first row changed; otherwise it stays as it was
	local first = valid_filepaths[1] and history.get_handle_from_filepath(valid_filepaths[1])
	if first and first ~= triquetra.primary_buffer[1] then
		triquetra.primary_enabled = true
	end
	triquetra:set_queue(vim.tbl_map(history.get_handle_from_filepath, valid_filepaths))

	loop_sm:to(loop_states.SELF)
	return true
end

---Check if a slot's file isn't on disk right now.
---
---A No Name text has no file to look for, and a file never written isn't gone: it reopens as the
---new file it was.
---
---@param id HandleId|nil The slot's file
---@return boolean off True if the file isn't readable and was written once
local function is_off_disk(id)
	local handle = id and history.handles.get(id)
	local filepath = handle and history.get_filepath_from_hash(handle.hash)
	return filepath ~= nil and
		not filepath:match("^NONAME_") and
		vim.fn.filereadable(filepath) == 0 and
		not handle.unwritten
end

---Check if a slot's file is closed and gone from disk.
---
---Its pointer is kept, since the file may come back, and using it says so instead. A file never
---written isn't gone: it reopens as the new file it was.
---
---@param id HandleId|nil The slot's file
---@return boolean missing True if the file has no buffer, isn't readable and was written once
local function is_missing(id)
	return is_off_disk(id) and history.get_buffer_from_handle(id) == nil
end
M.is_missing = is_missing -- the snapshots' preview asks the slot keys' rule

---Check if a slot's file is one cleanup lets go of.
---
---It is when no path is known for it, or when it's a file with no buffer that nothing besides the
---windows' slots holds, no closed list and no mark: the slot couldn't bring it back. A No Name buffer's
---hash isn't let go this way, since its text is what holds it.
---
---@param id HandleId The slot's file
---@return boolean stale True if the slot lets it go
local function is_handle_stale(id)
	local filepath = history.get_filepath_from_handle(id)
	-- i.e. if the buffer is not registered (typically means that buffer is closed) and it is not
	-- registered as closed in the closed buffers list. something is wrong with the triquetra, so we
	-- just remove it.
	return not filepath or (not filepath:match("^NONAME_") and history.get_buffer_from_handle(id) == nil
		and not history.handles.held_beyond_windows(id))
end

---Say that a slot's file is gone from disk, and that the slot keeps it.
---@param id HandleId The slot's file
---@param slot string The slot's name, as the message says it ("secondary slot")
local function say_missing(id, slot)
	vim.notify(require('frogman.domains.ui').routines.get_smart_basename(id) ..
		" isn't on disk right now; the " .. slot .. " keeps it.", vim.log.levels.WARN)
end

---A function used to handle conflicts of slot allocations in the triquetra.
---@param winid WinId The window the buffer lands in
---@param new_bufnr Bufnr The buffer landing
---@param is_pick boolean|nil Whether a cycling pick (<M-v>) lands here, rather than a load or a cancel
function M.reconcile_triquetra(winid, new_bufnr, is_pick)
	local new_id = history.get_handle_from_buffer(new_bufnr)

	if not new_bufnr then require('frogman.domains.ledger').never("Bufnr must be provided.") end

	if not new_id then
		require('frogman.domains.ledger').never("What the fuck.")
	end -- Skip unregistered buffers

	local triquetra = data.crux[winid]
	local temp, proc
	if triquetra and triquetra.current_slot ~= new_id then
		M.remember_arrival(winid, triquetra, new_id)
		local left, ternary_before = triquetra.current_slot, triquetra.ternary_slot
		M.enforce_secondary_map_policy(
			triquetra,
			new_id,
			(triquetra.secondary_slot == new_id) and triquetra.current_slot or triquetra.secondary_slot
		)
		-- Reconcile the triquetra slots if we selected a buffer part of the relationship
		if triquetra.ternary_slot == new_id then
			triquetra.displacement_ternary_map[triquetra.current_slot .. "-swap"] = triquetra.ternary_slot
			temp = triquetra.current_slot
			triquetra:update({ current_slot = triquetra.ternary_slot, ternary_slot = temp })
			proc = true
		end
		if triquetra.secondary_slot == new_id then
			if proc then
				require('frogman.domains.ledger').never("Duplicates detected in triquetra slots")
			end
			-- the guard runs before the swap, so the ternary's memory gets the buffer being left.
			if triquetra.displacement_ternary_map[triquetra.ternary_slot] == new_id then
				triquetra.displacement_ternary_map[triquetra.ternary_slot] = triquetra.current_slot
				require('frogman.domains.ledger').note("ternary", triquetra.ternary_slot, new_id, triquetra.current_slot, "guard")
				vim.notify(
					"Avoided conflict of ternary's remembered relationship becoming current. Remembered relationship has been changed to remember pre-jump current buffer instead: ["
					.. (history.get_buffer_from_handle(triquetra.ternary_slot) or "")
					.. "] -> ["
					.. (history.get_buffer_from_handle(triquetra.current_slot) or "")
					.. "]", vim.log.levels.WARN)
			end
			temp = triquetra.current_slot
			triquetra:update({ current_slot = triquetra.secondary_slot, secondary_slot = temp })
			proc = true
		end

		if not proc then
			if triquetra.displacement_ternary_map[triquetra.ternary_slot] == new_id then
				triquetra.displacement_ternary_map[triquetra.ternary_slot] = triquetra.current_slot
				require('frogman.domains.ledger').note("ternary", triquetra.ternary_slot, new_id, triquetra.current_slot, "guard")
				vim.notify(
					"Avoided conflict of ternary's remembered relationship becoming current. Remembered relationship has been changed to remember pre-jump current buffer instead: ["
					.. (history.get_buffer_from_handle(triquetra.ternary_slot) or "")
					.. "] -> ["
					.. (history.get_buffer_from_handle(triquetra.current_slot) or "")
					.. "]", vim.log.levels.WARN)
			end
			triquetra:set("current_slot", new_id)
			-- a pick outside the slots notes where the cycle started, so a ternary restore brings it
			-- back; the picked buffer's older swap note would win the restore, so it goes.
			if is_pick and left ~= nil then
				triquetra.displacement_ternary_map[new_id] = left
				triquetra.displacement_ternary_map[new_id .. "-swap"] = nil
			end
		end
		M.enforce_ternary_map_policy(
			triquetra,
			new_id,
			left,
			ternary_before,
			(new_id == ternary_before) and left or ternary_before
		)
		M.seal_arrival(winid, triquetra)
	end
end

---Land a window whose buffer got deleted, once the delete is over.
---
---It goes to the ternary, then the secondary, then the primary, then the most recent buffer. With
---nothing to land on it keeps the empty buffer Neovim gave it, and only makes one if Neovim showed
---something else. Neovim's own pick in between isn't recorded as a visit (see `M.is_landing_pick()`).
---A window that moved on in the same batch doesn't land: from Neovim's pick, or from a buffer that was
---renamed rather than deleted and is still listed.
---
---@param winid WinId The window that was showing the deleted buffer
---@param deleted_bufnr Bufnr The buffer being deleted
---@return nil
function M.land_after_delete(winid, deleted_bufnr)
	local landing = { deleted = deleted_bufnr, pick = nil }
	data.landing[winid] = landing
	local loads = history.data.loads
	require('frogman.settle').later("landing", function()
		if data.landing[winid] == landing then
			data.landing[winid] = nil
		end
		if history.data.loads ~= loads then
			return -- a session loaded since: the load laid its windows out
		end
		local triquetra = data.crux[winid]
		if not triquetra or not vim.api.nvim_win_is_valid(winid) then
			return -- neovim closed the window, nothing to land.
		end
		-- still shown: it wasn't deleted, it was renamed, or an :edit reused it for a new name, listed or
		-- not, as an oil listing unlists its own; the window now visits what it is, as cleanup takes it.
		if vim.api.nvim_buf_is_valid(deleted_bufnr) and vim.api.nvim_win_get_buf(winid) == deleted_bufnr then
			if history.get_buffer_from_handle(triquetra.current_slot) == nil then
				M.enforce_editor_policy()
			end
			return
		end
		-- the window moved on since neovim's pick (another :e in the same batch), so that's where it is.
		if landing.pick and vim.api.nvim_win_get_buf(winid) ~= landing.pick then
			return
		end
		-- still listed, it wasn't deleted but renamed, a No Name buffer written under a name, and Neovim made
		-- no pick: the window moved on from it in the same batch (another :e), and its arrival settles it.
		if vim.api.nvim_buf_is_valid(deleted_bufnr) and vim.bo[deleted_bufnr].buflisted then
			return
		end

		local ledger = require('frogman.domains.ledger')
		local before = ledger.slots(winid)
		local from, landing_bufnr = resolve_next_slot(triquetra, deleted_bufnr)

		if landing_bufnr then
			ledger.slots_moved("landed", winid, before, { from = from })
			M.enforce_note_maps_policy(triquetra) -- a buffer became current under the slots, its notes may be stale.
		else
			ledger.slots_moved("landed", winid, before, { from = "empty" })
		end

		vim.api.nvim_win_call(winid, function()
			if landing_bufnr then
				vim.api.nvim_set_current_buf(landing_bufnr)
				return
			end
			local shown = vim.api.nvim_get_current_buf()
			local is_empty = vim.api.nvim_buf_get_name(shown) == "" and
				vim.bo[shown].buftype == "" and
				not vim.bo[shown].modified and
				vim.api.nvim_buf_line_count(shown) == 1 and
				vim.api.nvim_buf_get_lines(shown, 0, 1, false)[1] == ""
			if not is_empty then
				-- a new buffer, not :enew, which would reuse an empty scratch and change it.
				vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
			else
				-- neovim's pick wasn't recorded, so record it now.
				history.sm:to(history.sm:state(), { buf = shown }, history.states.mode.UPDATE)
			end
		end)
	end)
end

---Note the windows a buffer being deleted makes land, at its delete's event.
---
---A window that shows it lands once the delete is over (`M.land_after_delete()`) when its current slot
---is the buffer's file, or has no buffer, the window visiting the buffer; Neovim's own pick meanwhile
---isn't a visit. It's read at the event, since the close runs once the editor settles, by when the
---window shows Neovim's pick.
---
---@param bufnr Bufnr The buffer being deleted
---@param id HandleId|nil Its file's handle, nil for a buffer frogman doesn't track
---@return nil
function M.note_landings(bufnr, id)
	for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
		local triquetra = data.crux[winid]
		if triquetra and (triquetra.current_slot == id or history.get_buffer_from_handle(triquetra.current_slot) == nil) then
			M.land_after_delete(winid, bufnr)
		end
	end
end

---Check if this BufEnter is Neovim's own pick for a window whose buffer is being deleted.
---
---Only the first one counts, and only once the buffer has left the buffer list (a rename keeps it).
---
---@param winid WinId The window the buffer is entered in
---@param bufnr Bufnr The buffer being entered
---@return boolean pick True if it's Neovim's pick, which isn't recorded as a visit
function M.is_landing_pick(winid, bufnr)
	local landing = data.landing[winid]
	if
		not landing or
		landing.pick or
		bufnr == landing.deleted or -- the buffer reused for a new name, not a pick
		(vim.api.nvim_buf_is_valid(landing.deleted) and vim.bo[landing.deleted].buflisted)
	then
		return false
	end
	landing.pick = bufnr
	return true
end

---Cleanup all the triquetras. Remove any triquetra that references
---to unregistered buffers.
---
---A window a snapshot shows in, or a snapshot's commit lands in, is left alone: what it shows isn't
---its slots' yet, and the preview's end or the commit's pick settles them.
---
---@param bufnr_ondelete nil | Bufnr The buffer being deleted, whose windows land once the delete is over
---@param committing WinId|nil The window a snapshot's commit lands in
---@return nil
function M.enforce_editor_policy(bufnr_ondelete, committing)
	-- a buffer the screen shows deleted already is judged gone: its close, still to settle, runs first
	history.routines.run_closes()
	local set_cache_from_window_triquetra = require("frogman").ui.routines.set_cache_from_window_triquetra
	local ledger = require('frogman.domains.ledger')
	local preview = package.loaded['frogman.domains.snapshots.preview']
	local slots_before, rows_before = {}, {}
	for winid, triquetra in pairs(data.crux) do
		slots_before[winid] = { triquetra.current_slot, triquetra.secondary_slot, triquetra.ternary_slot }
		rows_before[winid] = ledger.slots(winid)
	end
	for winid, triquetra in pairs(data.crux) do
		if not vim.api.nvim_win_is_valid(winid) then
			-- a window gone without its WinClosed: closed while frogman was off, or with noautocmd
			data.unregister_triquetra(winid)
			goto continue
		end
		if data.landing[winid] then
			goto continue -- its buffer is being deleted: it lands by itself once the delete is over
		end
		if winid == committing or (preview and preview.window() == winid) then
			goto continue -- a snapshot showing leaves its slots as they are, and a commit's pick slots them
		end
		local current_bufnr = history.get_buffer_from_handle(triquetra.current_slot)
		local filepath, bufnr
		if not current_bufnr then -- this is a special case. we can't have an unregistered
			-- hash in the current slot. doesn't make sense.
			local current_slot_candidate = history.get_handle_from_buffer(vim.api.nvim_win_get_buf(winid))
			if current_slot_candidate then
				-- an old current No Name buffer that isn't closed, an empty one whose delete took it out of
				-- every other slot, goes into none, and the window lost nothing to say so
				local old_path = history.get_filepath_from_handle(triquetra.current_slot)
				local gone = old_path ~= nil and old_path:match("^NONAME_") ~= nil
					and not history.handles.kept_closed(triquetra.current_slot)
				if not gone then
					vim.notify("Healed the triquetra of window " ..
						winid .. " with current slot: " .. vim.api.nvim_win_get_buf(winid))
				end
				-- like navigation: the old current goes into the ternary, or trades places with the
				-- secondary when that's what the window shows now, with the notes navigation writes.
				local healed = { current_slot = current_slot_candidate }
				if gone then
					if current_slot_candidate == triquetra.secondary_slot then
						healed.secondary_slot = vim.NIL
					elseif current_slot_candidate == triquetra.ternary_slot then
						healed.ternary_slot = vim.NIL
					end
				elseif current_slot_candidate == triquetra.secondary_slot then
					M.write_secondary_swap_notes(triquetra)
					healed.secondary_slot = triquetra.current_slot
				else
					if triquetra.ternary_slot and current_slot_candidate ~= triquetra.ternary_slot then
						triquetra.displacement_ternary_map[triquetra.current_slot .. "-swap"] = nil
						triquetra.displacement_ternary_map[triquetra.current_slot] = triquetra.ternary_slot
					end
					healed.ternary_slot = triquetra.current_slot
				end
				triquetra:update(healed)
			else
				-- print("Running enforce_editor_policy [" .. winid .. "] with unregistered current slot: " .. (history.get_filepath_from_hash(triquetra.current_slot) or "nil"))
				-- yes if the noname buffer turns evolved into a terminal, we don't want to track it.
				--
				-- but there is a catch, what if the buffer's file was just deleted along the way? Then
				-- we just remove that current slot from the triquetra, and replace it with ternary, then
				-- secondary, then primary, then most recent buffer, if the tracked is more than 1.
				-- print("(2) Deleted window triquetra of bufnr: " .. index)
				local cbufnr, cbufhash, cbufname
				-- the hash the current slot's file has now, which a buffer showing it under that name hashes to
				local current_hash = history.get_hash_from_handle(triquetra.current_slot)
				if vim.api.nvim_win_is_valid(winid) then
					cbufnr = vim.api.nvim_win_get_buf(winid)
					cbufname = vim.api.nvim_buf_get_name(cbufnr)
					if cbufname == "" and vim.b[cbufnr].frogman_noname ~= nil then -- one with no id was never tracked
						cbufname = history.routines.noname_name(cbufnr)
					end
					cbufhash = history.routines.get_filehash(cbufname)
				else
					-- yes, this line of code appears three times in this condition branch.
					-- we delete triquetras associated to windows that are not "regular" windows.
					data.unregister_triquetra(winid)
					goto continue
				end

				if cbufnr == bufnr_ondelete then
					-- print("skipped because it's the buffer being deleted: ".. (cbufnr or "nil"))
					-- we can't switch buffers inside the delete, so the window lands after it's over.
					M.land_after_delete(winid, cbufnr)
					goto continue
				end
				if cbufhash == current_hash and vim.bo[cbufnr].buftype == "" and history.routines.is_trackable(cbufnr) then
					-- the window still shows the current slot's file, it's only unregistered for the moment
					-- (a reload without events). there's nothing to heal. one no longer trackable, an empty
					-- No Name buffer unlisted, isn't taken in again: the window visits it, as below.
					goto continue
				end
				if history.handles.kept_closed(triquetra.current_slot) then
					-- the window is visiting something we don't track and keeps its triquetra: a closed
					-- current slot stays, it's the file the window was last on.
					goto continue
				end
				if cbufhash == current_hash or vim.bo[cbufnr].buftype == "acwrite" then -- it means that the buffer didn't evolved to anything new. it was still deleted, so we fallback.
					-- Part 1: Try Heal triquetra with self
					---Whether a slot took the current slot's place
					---@type boolean
					local resolved = resolve_next_slot(triquetra) ~= nil -- no visit: the window doesn't go to it

					if resolved then -- I know this is fucking stupid, but I don't want to change the structure of this function.
						history.routines.update_buffer_history_ordered()
						-- print("#4")
						goto continue -- the window keeps showing what it shows: cleanup never touches a window.
					end

					-- Part 2: This is when we can't heal it straightforward anymore.
					if history.get_filepath_from_handle(triquetra.current_slot) ~= nil then
						-- if it has a filepath mapping then it was registered before. If it was registered
						-- before and we ended up at this point, it means that this buffer is stale. Something
						-- must have went wrong. Otherwise, if it's not registered, i.e. empty filepath
						-- output then that means that we should never consider this in the first place, so
						-- no errors thrown. [edit: no errors thrown as well for the stale window triquetra.]

						-- this comes before healing with ordered history or creating a new NO_NAME buffer since
						-- it is quite destructive to the triquetra tracking to replace a window triquetra's current slot,
						-- which the triquetra itself is now considered stale, with a heuristic replacement buffer.
						-- The implication of this is the stale triquetra SHOULD be removed, as the window it is associated
						-- with is not a "regular" buffer anymore.
						--
						-- This is now an unregular window, because we can't heal it properly anymore and turns out the
						-- tracked current_slot buffer was unloaded. So unloaded buffer and no possible healing, that is
						-- what we proved in this condition branch. So we just need to nuke this triquetra, since there
						-- is no appropriate buffer to set it to without destructively replacing the current slot, since
						-- this window is not a "regular" window anymore.

						-- error("Impossible: current_slot is nil and no buffer is available to set it. " ..
						-- 	(triquetra.current_slot or "") .. " - " .. winid .. " - " .. vim.api.nvim_get_current_buf() .. " - " .. vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()))
						vim.notify("Cleaning up triquetra of now unregular window" .. winid ..
							" with current slot: " .. triquetra.current_slot .. " - " ..
							vim.api.nvim_win_get_buf(winid) ..
							" - (" .. vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(winid)) .. ")",
							vim.log.levels.INFO)
						data.unregister_triquetra(winid)
						goto continue
					elseif #history.get_ordered_buffers() > 0 then
						-- print("#5")
						local candidate = history.get_handle_from_buffer(history.get_ordered_buffers()[1].buf)
						if candidate then
							triquetra:set("current_slot", candidate)
						else
							require('frogman.domains.ledger').never(
								"This is impossible. Ordered history buffers should always have a hash associated with it.")
						end
					else
						-- nothing to put in the current slot, and cleanup doesn't touch the window to make
						-- something: the window is left with no triquetra, as one born untracked.
						data.unregister_triquetra(winid)
						goto continue
					end
				else -- it's visiting, and its current slot names nothing open or closed any more: the next slot
					-- in line takes its place, or there's nothing to come back to.
					-- print all the variables
					--
					-- print(vim.inspect({
					-- 	current_buf_bufnr = (cbufnr or "nil"),
					-- 	current_buf_bufname = (cbufname or "nil"),
					-- 	current_buf_filehash = (cbufhash or "nil"),
					-- 	current_buf_filepath = (history.get_filepath_from_hash(cbufhash) or "nil"),
					-- 	triquetra_current_slot_bufnr = (current_bufnr or "nil"),
					-- 	triquetra_current_slot_filehash = (triquetra.current_slot or "nil"),
					-- 	triquetra_current_slot_filepath = (history.get_filepath_from_hash(triquetra.current_slot) or "nil"),
					-- }))
					if history.routines.is_trackable(cbufnr) and history.get_hash_from_buffer(cbufnr) == nil then
						-- it was switched to a buffer still to be taken in, as a delete helper switches the window
						-- before the delete: that buffer's arrival re-points the window, like navigation.
					elseif not resolve_next_slot(triquetra) then -- the next slot in line, the window still visiting
						data.unregister_triquetra(winid)
					end
				end
				goto continue
			end
		end

		bufnr = history.get_buffer_from_handle(triquetra.secondary_slot)
		if triquetra.secondary_slot ~= nil and is_handle_stale(triquetra.secondary_slot) then
			if bufnr then
				-- quiet: the trail has the slot cleared, from the pass's own rows, and no close of the file
				history.routines.unregister_buffer(bufnr, { quiet = true })
			end
			triquetra:set("secondary_slot", nil)
		end

		bufnr = history.get_buffer_from_handle(triquetra.ternary_slot)
		if triquetra.ternary_slot ~= nil and is_handle_stale(triquetra.ternary_slot) then
			if bufnr then
				history.routines.unregister_buffer(bufnr, { quiet = true })
			end
			triquetra:set("ternary_slot", nil)
		end

		local pid
		for index = #(triquetra.primary_buffer or {}), 1, -1 do
			pid = triquetra.primary_buffer[index]
			bufnr = history.get_buffer_from_handle(pid)
			if is_handle_stale(pid) then
				if bufnr then
					history.routines.unregister_buffer(bufnr, { quiet = true })
				end
				triquetra:queue_remove(index)
			end
		end


		filepath = history.get_filepath_from_handle(triquetra.current_slot)
		if not filepath then
			bufnr = history.get_buffer_from_handle(triquetra.current_slot)
			if bufnr then
				history.routines.unregister_buffer(bufnr, { quiet = true })
			end
		end

		set_cache_from_window_triquetra(winid)
		::continue::
	end
	-- what the pass did by itself goes into the trail: a triquetra dropped from a window still open, a
	-- current slot moved, or a slot or a queue entry cleared.
	for winid, before in pairs(rows_before) do
		local after = ledger.slots(winid)
		if after == nil then
			if vim.api.nvim_win_is_valid(winid) then
				ledger.move("dropped", { subject = tostring(winid), name = ledger.window_name(winid), row = { before = before, after = {} },
					words = "nothing it can be on any more" })
			end
		elseif after.c ~= before.c then
			ledger.slots_moved("repointed", winid, before)
		elseif after.s ~= before.s or after.t ~= before.t or not vim.deep_equal(after.p, before.p) then
			ledger.slots_moved("cleared", winid, before, { words = "what it named is gone" })
		end
	end
	-- a slot that changed under the current buffer can leave its notes naming it.
	for winid, triquetra in pairs(data.crux) do
		local before = slots_before[winid]
		if
			before and (
				before[1] ~= triquetra.current_slot or
				before[2] ~= triquetra.secondary_slot or
				before[3] ~= triquetra.ternary_slot
			)
		then
			M.enforce_note_maps_policy(triquetra)
		end
	end
end

---Swap with secondary buffer in the target window. It actually just jumps to the secondary buffer.
---
---The BufEnter autocmd does the swapping dynamically, so this function is just a jump.
---
---@param winid WinId The target window ID
---@return nil
function M.swap_with_secondary(winid)
	local triquetra = data.get_window_triquetra(winid)

	if not triquetra then
		vim.notify("Window with unregistered buffer.", vim.log.levels.WARN)
		return
	end

	local cbufnr = history.get_buffer_from_handle(triquetra.current_slot)
	if cbufnr == nil and history.get_hash_from_buffer(vim.api.nvim_win_get_buf(winid)) == nil then
		-- visiting, with the current slot closed: going back to it reopens it.
		if is_missing(triquetra.current_slot) then
			say_missing(triquetra.current_slot, "current slot")
			return
		end
		local basename = require('frogman.domains.ui').routines.get_smart_basename(triquetra.current_slot)
		local reason
		cbufnr, reason = history.reopen_handle(triquetra.current_slot)
		if cbufnr == nil then
			-- it can't come back (a No Name text that's lost): no swap is made from a window off its current slot
			if reason ~= "taken" then -- another buffer has its name: the reopen said so
				vim.notify(basename .. " can't be reopened, so the window stays where it is.", vim.log.levels.WARN)
			end
			return
		end
	end

	-- check if the current buffer of the window is the triquetra current. If not,
	-- then we just jump to the triquetra current window.
	if cbufnr and cbufnr ~= vim.api.nvim_win_get_buf(winid) then
		vim.notify("Jumped back to windows current buffer.", vim.log.levels.INFO)
		vim.api.nvim_set_current_buf(cbufnr)
		return -- we just jump.
	end

	if triquetra.secondary_slot == nil then
		cbufnr = history.get_buffer_from_handle(triquetra.current_slot)
		if triquetra.ternary_slot ~= nil then
			triquetra:update({ secondary_slot = triquetra.ternary_slot, ternary_slot = vim.NIL })
			triquetra.displacement_secondary_map[triquetra.secondary_slot] =
				triquetra.displacement_ternary_map[triquetra.secondary_slot]
			triquetra.displacement_secondary_map[triquetra.secondary_slot .. "-swap"] = nil
			M.enforce_note_maps_policy(triquetra)
			vim.notify("Secondary buffer set to ternary slot. Ternary slot graduated.", vim.log.levels.INFO)
		elseif #history.data.ordered.crux >= 2 then
			-- the newest buffer that isn't the current one: a visit in another window, made without
			-- the focus, can rank above the window's own current buffer.
			for _, entry in ipairs(history.data.ordered.crux) do
				local id = history.get_handle_from_buffer(entry.buf)
				if id and id ~= triquetra.current_slot then
					triquetra:set("secondary_slot", id)
					break
				end
			end
			if triquetra.secondary_slot then
				M.enforce_note_maps_policy(triquetra)
				vim.notify("Secondary buffer populated from history.", vim.log.levels.INFO)
			else
				-- no entry but the current one names a file: a history just made stale
				vim.notify("Cannot populate secondary slot - insufficent history.", vim.log.levels.WARN)
			end
		else
			vim.notify("Cannot populate secondary slot - insufficent history.", vim.log.levels.WARN)
		end
	else
		if is_missing(triquetra.secondary_slot) then
			say_missing(triquetra.secondary_slot, "secondary slot")
			return
		end
		if not triquetra.current_slot then
			require('frogman.domains.ledger').never("It's not okay to have a secondary slot without a current slot.")
		end
		-- the secondary comes back before any note is written, so a reopen that fails leaves none of a
		-- swap that didn't happen
		cbufnr = history.get_buffer_from_handle(triquetra.secondary_slot)
		if cbufnr == nil then
			local old_basename = require('frogman.domains.ui').routines.get_smart_basename(triquetra.secondary_slot)
			local old_secondary_filehash = history.get_hash_from_handle(triquetra.secondary_slot) or "-"
			local reason
			cbufnr, reason = history.reopen_handle(triquetra.secondary_slot)
			if cbufnr == nil and reason == "taken" then
				return -- another buffer has its name: the reopen said so, and the slot keeps it
			elseif cbufnr == nil then
				vim.notify(
					"Removed secondary file not found in filesystem: " .. old_basename,
					vim.log.levels.WARN)
				triquetra:set("secondary_slot", nil)
				loop_sm:to(loop_states.SELF)
				return
			else
				vim.notify("File reopened for secondary slot: " .. old_basename .. " - old: " .. old_secondary_filehash,
					vim.log.levels.INFO)
			end
		end
		if not history.get_handle_from_buffer(cbufnr) then
			require('frogman.domains.ledger').never("This is impossible. Ternary slot should always have a buffer associated with it.")
		end

		-- the switch goes first, so one Vim refuses (E37, E1513) raises before any slot or note is written
		vim.api.nvim_set_current_buf(cbufnr)
		M.write_secondary_swap_notes(triquetra)
		M.reconcile_triquetra(winid, cbufnr)
	end

	loop_sm:to(loop_states.SELF)
end

---Swap with ternary buffer in the target window. It actually just jumps to the ternary buffer.
---
---The BufEnter autocmd does the swapping dynamically, so this function is just a jump.
---
---@param winid WinId The target window ID
---@return nil
function M.swap_with_ternary(winid)
	local triquetra = data.get_window_triquetra(winid)

	if not triquetra then
		vim.notify("Window with unregistered buffer.", vim.log.levels.WARN)
		return
	end

	local cbufnr = history.get_buffer_from_handle(triquetra.current_slot)
	if cbufnr == nil and history.get_hash_from_buffer(vim.api.nvim_win_get_buf(winid)) == nil then
		-- visiting, with the current slot closed: going back to it reopens it.
		if is_missing(triquetra.current_slot) then
			say_missing(triquetra.current_slot, "current slot")
			return
		end
		local basename = require('frogman.domains.ui').routines.get_smart_basename(triquetra.current_slot)
		local reason
		cbufnr, reason = history.reopen_handle(triquetra.current_slot)
		if cbufnr == nil then
			-- it can't come back (a No Name text that's lost): no swap is made from a window off its current slot
			if reason ~= "taken" then -- another buffer has its name: the reopen said so
				vim.notify(basename .. " can't be reopened, so the window stays where it is.", vim.log.levels.WARN)
			end
			return
		end
	end

	-- check if the current buffer of the window is the triquetra current. If not,
	-- then we just jump to the triquetra current window.
	if cbufnr and cbufnr ~= vim.api.nvim_win_get_buf(winid) then
		vim.notify("Jumped back to windows current buffer.", vim.log.levels.INFO)
		vim.api.nvim_set_current_buf(cbufnr)
		return -- we just jump.
	end


	if triquetra.ternary_slot == nil then
		vim.notify("No ternary buffer to swap with.", vim.log.levels.WARN)
		return
	end
	if is_missing(triquetra.ternary_slot) then
		say_missing(triquetra.ternary_slot, "ternary slot")
		return
	end

	cbufnr = history.get_buffer_from_handle(triquetra.ternary_slot)
	if cbufnr == nil then
		local old_basename = require('frogman.domains.ui').routines.get_smart_basename(triquetra.ternary_slot)
		local old_ternary_filehash = history.get_hash_from_handle(triquetra.ternary_slot) or "-"
		local reason
		cbufnr, reason = history.reopen_handle(triquetra.ternary_slot)
		if cbufnr == nil and reason == "taken" then
			return -- another buffer has its name: the reopen said so, and the slot keeps it
		elseif cbufnr == nil then
			vim.notify("Removed ternary file not found in filesystem: " .. old_basename,
				vim.log.levels.WARN)
			triquetra:set("ternary_slot", nil)
			loop_sm:to(loop_states.SELF)
			return
		else
			vim.notify("File reopened for ternary slot: " .. old_basename .. " - old: " .. old_ternary_filehash,
				vim.log.levels
				.INFO)
		end
	end
	if not history.get_handle_from_buffer(cbufnr) then
		require('frogman.domains.ledger').never("This is impossible. Ternary slot should always have a buffer associated with it.")
	end
	-- the switch goes first, so one Vim refuses (E37, E1513) raises before any slot or note is written
	vim.api.nvim_set_current_buf(cbufnr)
	M.reconcile_triquetra(winid, cbufnr)

	loop_sm:to(loop_states.SELF)
end

---Jump to a marked file in the target window, as a primary jump goes to the primary.
---
---The current buffer goes into the ternary with its swap note, and the file becomes current. A
---file that's the window's secondary is a swap with it, as <M-f> makes one. A closed file is
---reopened, a file only a mark holds included; one gone from disk is said instead, and nothing
---changes.
---
---@param winid WinId The target window ID
---@param id HandleId The marked file's handle
---@param label string How the mark is named in messages, like "⟨a⟩"
---@return nil
function M.jump_to_mark(winid, id, label)
	local triquetra = data.get_window_triquetra(winid)
	if not triquetra then
		vim.notify("Window with unregistered buffer.", vim.log.levels.WARN)
		return
	end
	if triquetra.secondary_slot == id then
		M.swap_with_secondary(winid)
		return
	end
	if is_missing(id) then
		say_missing(id, "mark")
		return
	end
	local cbufnr = history.get_buffer_from_handle(id)
	if cbufnr == nil then
		local basename = require('frogman.domains.ui').routines.get_smart_basename(id)
		local reason
		cbufnr, reason = history.reopen_handle(id)
		if cbufnr == nil then
			if reason ~= "taken" then -- another buffer has its name: the reopen said so
				vim.notify(basename .. " can't be reopened, so " .. label .. " goes nowhere.", vim.log.levels.WARN)
			end
			return
		end
	end
	-- the switch goes first, so one Vim refuses (E37, E1513) raises before any slot or note is written
	if vim.api.nvim_win_get_buf(winid) ~= cbufnr then
		vim.api.nvim_win_set_buf(winid, cbufnr)
	end
	if triquetra.current_slot ~= id then
		local left, ternary_before = triquetra.current_slot, triquetra.ternary_slot
		triquetra.displacement_ternary_map[left .. "-swap"] = ternary_before
		triquetra:update({ ternary_slot = left, current_slot = id })
		M.enforce_secondary_map_policy(triquetra, id, triquetra.secondary_slot)
		M.enforce_ternary_map_policy(triquetra, id, left, ternary_before, left)
	end
	loop_sm:to(loop_states.SELF)
end

---Jump to the target window's primary buffer.
---
---@param winid WinId The target window ID
---@return nil
function M.jump_to_primary(winid)
	local navigation = require("frogman.domains.navigation")
	local triquetra = data.get_window_triquetra(winid)
	if not triquetra then
		vim.notify("Window with unregistered buffer.", vim.log.levels.WARN)
		return
	end
	if navigation.is_cycling() then
		local cycling_origins = history.get_cycling_origins(winid)
		local ui_get_basename = require('frogman.domains.ui').routines.get_smart_basename

		if not cycling_origins then
			require('frogman.domains.ledger').never("This should not happen. Cycling origins not found for window: " .. winid)
		end

		local origin_bufnr = history.get_buffer_from_handle(cycling_origins.current_slot)
		if not origin_bufnr and history.handles.kept_closed(cycling_origins.current_slot) then
			-- the start closed while the window cycled through something untracked: going back to it
			-- reopens it, as <M-f> does.
			if is_missing(cycling_origins.current_slot) then
				say_missing(cycling_origins.current_slot, "current slot")
				return
			end
			origin_bufnr = history.reopen_handle(cycling_origins.current_slot)
			if not origin_bufnr then
				return -- a No Name text that couldn't be read: its reader said so
			end
		end

		if not origin_bufnr then
			-- the start has no buffer and nothing keeps it closed, as an empty No Name buffer Neovim took for the
			-- next :e: it can't come back, so the key says so and changes nothing, as for a start gone from disk
			vim.notify(ui_get_basename(cycling_origins.current_slot) ..
				" was the cycle's start and can't be reopened, so the window stays as it is.", vim.log.levels.WARN)
			return
		end

		vim.api.nvim_set_current_buf(origin_bufnr)
		triquetra:set("current_slot", cycling_origins.current_slot)
		vim.notify("Returned to cycling origin buffer: " .. ui_get_basename(cycling_origins.current_slot),
			vim.log.levels.INFO)
		return
	end
	if (triquetra.primary_buffer[1] == nil) or (not triquetra.primary_enabled) or triquetra.secondary_slot == triquetra.primary_buffer[1] then
		M.swap_with_secondary(winid)
		return
	end

	if is_missing(triquetra.primary_buffer[1]) then
		say_missing(triquetra.primary_buffer[1], "primary queue")
		return
	end
	local cbufnr = history.get_buffer_from_handle(triquetra.primary_buffer[1])
	if cbufnr == nil then
		local reason
		cbufnr, reason = history.reopen_handle(triquetra.primary_buffer[1])
		if cbufnr == nil and reason == "taken" then
			return -- another buffer has its name: the reopen said so, and the queue keeps it
		end
		if cbufnr == nil then
			-- a No Name text that's lost can't come back, so it leaves the queue
			vim.notify("Removed primary file not found in filesystem: " ..
				require('frogman.domains.ui').routines.get_smart_basename(triquetra.primary_buffer[1]),
				vim.log.levels.WARN)
			triquetra:queue_remove(1)
			loop_sm:to(loop_states.SELF)
			return
		end
	end
	-- the switch goes first, so one Vim refuses (E37, E1513) raises before any slot or note is written
	vim.api.nvim_set_current_buf(cbufnr)
	if triquetra.current_slot ~= triquetra.primary_buffer[1] then -- We only do displacment if we are not already in the primary buffer.
		local left, ternary_before = triquetra.current_slot, triquetra.ternary_slot
		triquetra.displacement_ternary_map[triquetra.current_slot .. "-swap"] = triquetra.ternary_slot
		triquetra:update({ ternary_slot = triquetra.current_slot, current_slot = triquetra.primary_buffer[1] })
		M.enforce_secondary_map_policy(triquetra, triquetra.current_slot, triquetra.secondary_slot)
		M.enforce_ternary_map_policy(triquetra, triquetra.current_slot, left, ternary_before, left)
	else
		vim.notify("Already in primary buffer, no displacement performed.", vim.log.levels.INFO)
	end

	M.reconcile_triquetra(winid, cbufnr)
end

---Toggle the primary buffer in the target window.
---
---@param winid WinId The target window ID
---@return nil
function M.toggle_primary_buffer(winid)
	local triquetra = data.get_window_triquetra(winid)

	if not triquetra then
		return
	end

	if #triquetra.primary_buffer == 0 then
		-- an empty queue takes the current buffer and switches on, in one press.
		triquetra:queue_set(1, triquetra.current_slot)
		triquetra.primary_enabled = true
	else
		triquetra.primary_enabled = not triquetra.primary_enabled
	end
	loop_sm:to(loop_states.SELF)
	vim.cmd("redrawstatus!")
	vim.cmd("redrawtabline")
end

---Overwrite the primary buffer in the target window with the current slot.
---
---@param winid WinId The target window ID
---@return nil
function M.set_primary_buffer(winid)
	local triquetra = data.get_window_triquetra(winid)

	if not triquetra then
		return
	end

	if triquetra.primary_buffer[1] == nil then
		triquetra:queue_set(1, triquetra.current_slot)
		triquetra.primary_enabled = true
	elseif triquetra.primary_buffer[1] ~= triquetra.current_slot then
		local existing_index = vim.fn.index(triquetra.primary_buffer, triquetra.current_slot)
		if existing_index ~= -1 then
			triquetra:queue_remove(existing_index + 1)
		end
		triquetra:queue_insert(1, triquetra.current_slot)
		triquetra.primary_enabled = true
	else
		triquetra.primary_enabled = not triquetra.primary_enabled
	end
	loop_sm:to(loop_states.SELF)
	vim.cmd("redrawstatus!")
	vim.cmd("redrawtabline")
end

---A general function to restore from a displacement map.
---
---@param type "ternary"|"secondary" The type of displacement map to restore from
---@param triquetra WindowTriquetra The window's triquetra
local function restore_from_displacement_map(type, triquetra)
	local current_relationship = triquetra[type .. "_slot"]
	local remembered_mapping = triquetra["displacement_" .. type .. "_map"]

	-- a note at a file nothing knows any more is cleared when it's used.
	for _, key in ipairs({ triquetra.current_slot .. "-swap", triquetra.current_slot }) do
		if remembered_mapping[key] ~= nil and history.get_filepath_from_handle(remembered_mapping[key]) == nil then
			require('frogman.domains.ledger').note(type, triquetra.current_slot, remembered_mapping[key], nil, "no path")
			remembered_mapping[key] = nil
		end
	end

	-- a closed buffer whose file is gone from disk can't come back now. its note stays, it may come back.
	local remembered_relationship = remembered_mapping[triquetra.current_slot .. "-swap"]

	if
		remembered_relationship == nil or
		remembered_relationship == current_relationship or
		is_missing(remembered_relationship)
	then
		remembered_relationship = remembered_mapping[triquetra.current_slot]
	end

	if not remembered_relationship then
		vim.notify(
			"No " ..
			type ..
			" relationship found for restoration. It means you hadn't displaced a current buffer yet to the " ..
			type .. " slot.", vim.log.levels.WARN)
	elseif is_missing(remembered_relationship) then
		local ui_get_basename = require('frogman.domains.ui').routines.get_smart_basename
		vim.notify("Remembered " .. type .. " isn't on disk right now: " .. ui_get_basename(remembered_relationship) .. ". Nothing changed.", vim.log.levels.WARN)
	elseif remembered_relationship == current_relationship then
		require('frogman.domains.ledger').never("This is impossible. Remembered " ..
			type .. " is the same as current " .. type .. ". It should be different for flip flop.")
	else
		local ui_get_basename = require('frogman.domains.ui').routines.get_smart_basename
		if type == "ternary" then
			if remembered_relationship == triquetra.secondary_slot then
				triquetra:update({ secondary_slot = triquetra.ternary_slot or vim.NIL, ternary_slot = remembered_relationship })
			else
				triquetra:set("ternary_slot", remembered_relationship)
			end
		elseif type == "secondary" then
			if remembered_relationship == triquetra.ternary_slot then
				triquetra:update({ ternary_slot = triquetra.secondary_slot or vim.NIL, secondary_slot = remembered_relationship })
			else
				triquetra:set("secondary_slot", remembered_relationship)
			end
		end
		local restored = "Restored " .. type .. " slot to: " .. history.get_hash_from_handle(remembered_relationship) .. " (" .. ui_get_basename(remembered_relationship) .. ")"
		if is_off_disk(remembered_relationship) then
			-- its buffer is still open, so it comes back; the file just isn't on disk right now. One never
			-- written isn't gone.
			vim.notify(restored .. ", not on disk right now", vim.log.levels.WARN)
		else
			vim.notify(restored, vim.log.levels.INFO)
		end
		triquetra["displacement_" .. type .. "_map"][triquetra.current_slot] = current_relationship
		-- a slot changed under the current buffer (both, at an exchange), so its notes may name them now.
		M.enforce_note_maps_policy(triquetra)
	end
	loop_sm:to(loop_states.SELF)
end


---Restore to the ternary of the current buffer before being displaced into ternary slot.
---
---@param winid WinId The target window ID
---@return nil
function M.restore_triquetra_ternary(winid)
	local triquetra = data.get_window_triquetra(winid)
	if triquetra then
		restore_from_displacement_map("ternary", triquetra)
	end
end

---Restore to the secondary of the current buffer before being displaced into ternary slot.
---
---@param winid WinId The target window ID
---@return nil
function M.restore_triquetra_secondary(winid)
	local triquetra = data.get_window_triquetra(winid)
	if triquetra then
		restore_from_displacement_map("secondary", triquetra)
	end
end

function M.repopulate_window_relationships()
	local set_cache_from_window_triquetra = require("frogman.domains.ui").set_cache_from_window_triquetra
	for winid, _ in pairs(data.crux) do
		-- a window closed while frogman was off too: what the UI kept of it goes, its winbar only if it's there
		require('frogman.domains.ui.routines').remove_winbar_string(winid)
	end
	data.drop_all_triquetras()
	data.last_valid_window = vim.api.nvim_get_current_win()

	for _, winid in pairs(vim.api.nvim_list_wins()) do
		local current_slot = history.get_handle_from_buffer(vim.api.nvim_win_get_buf(winid))
		if current_slot == nil then
			vim.notify("skipping window " .. winid .. " because it has no registered buffer.", vim.log.levels.INFO)
			goto continue
		end
		if vim.api.nvim_win_get_config(winid).relative ~= "" then
			goto continue -- a float gets no triquetra, as the getter makes none for one
		end

		history.routines.ensure_window_entry(winid) -- every triquetra comes with its window's history entry.
		data.make_triquetra(winid, {
			current_slot = current_slot,
			secondary_slot = nil,
			ternary_slot = nil,
			primary_buffer = {},
			displacement_secondary_map = {},
			displacement_ternary_map = {},
			primary_enabled = false,
		})
		set_cache_from_window_triquetra(winid)
		::continue::
	end
	if not data.crux[data.last_valid_window] then
		-- the last window with a triquetra: the current one has none (a help window), so one that has
		for _, winid in ipairs(vim.api.nvim_list_wins()) do
			if data.crux[winid] then
				data.last_valid_window = winid
				break
			end
		end
	end
end

return M
