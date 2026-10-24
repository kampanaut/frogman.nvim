---Window domain core routines for buffer relationship management.
---
---This module contains the main business logic for managing triquetra buffer
---relationships within windows, including the complex reconciliation logic
---that was previously in sync_detached_history().

local data = require('cavediver.domains.window.data')

local history = require('cavediver.domains.history')
local loop_sm = require('cavediver.domains.ui.sm').loop
local loop_states = require('cavediver.domains.ui.states').LOOP

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
---@param triquetra WindowTriquetra
---@param arrived Filehash The buffer that became current
---@param left Filehash The buffer it replaced
---@param ternary_before Filehash|nil The ternary before the arrival
---@param ternary_after Filehash|nil The ternary after the arrival
---@return nil
function M.keep_older_ternary_note(triquetra, arrived, left, ternary_before, ternary_after)
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
	require('cavediver.domains.ledger').note("ternary", arrived, dtm[arrived], older, "stale")
	dtm[arrived] = older
end

---Rewrite the current buffer's secondary note when it has gone stale.
---
---A plain secondary note that names the window's secondary would make the restore throw. It's
---rewritten to the buffer's swap note when that names another buffer, otherwise it's dropped.
---
---@param triquetra WindowTriquetra
---@param current Filehash|nil The current buffer
---@param secondary Filehash|nil The window's secondary
---@return nil
function M.keep_older_secondary_note(triquetra, current, secondary)
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
	require('cavediver.domains.ledger').note("secondary", current, secondary, dsm[current], "stale")
end

---Write the notes of a swap onto the secondary.
---
---Every route onto the secondary writes them: <M-f>, its <M-;><M-f> fallback, and plain navigation
---onto the secondary. The buffer left gets swap notes for its secondary and its ternary. The
---secondary's own swap note becomes its plain note when it names another buffer, and a plain note
---naming the buffer left is cleared, so a round trip can't leave it stale.
---
---@param triquetra WindowTriquetra
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
---secondary note naming the secondary is rewritten as `M.keep_older_secondary_note()` does it.
---
---@param triquetra WindowTriquetra
---@return nil
function M.check_notes_under_current(triquetra)
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
		require('cavediver.domains.ledger').note("ternary", current, ternary, older, "stale")
		dtm[current] = older
	end
	M.keep_older_secondary_note(triquetra, current, triquetra.secondary_slot)
end

---Remember a window's triquetra from just before a buffer arrives in it.
---
---Used by `M.undo_arrival()` to put the window back.
---
---@param winid WinId
---@param triquetra WindowTriquetra
---@param filehash Filehash The arriving buffer
---@return nil
function M.remember_arrival(winid, triquetra, filehash)
	data.arrivals[winid] = { hash = filehash, before = vim.deepcopy(triquetra) }
end

---Remember a window's triquetra from just after a buffer arrived in it.
---
---An arrival is undone only while nothing else has changed the triquetra since.
---
---@param winid WinId
---@param triquetra WindowTriquetra
---@return nil
function M.seal_arrival(winid, triquetra)
	local arrival = data.arrivals[winid]
	if arrival and arrival.hash == triquetra.current_slot then
		arrival.after = vim.deepcopy(triquetra)
	end
end

---Undo a buffer's arrival once it turned into something cavediver doesn't track.
---
---Runs when the buffer's buftype changed after it was slotted. A window it just arrived in gets back
---the slots and notes it had before, and is visiting it. A window whose current slot it was otherwise
---takes the next slot in line, as a landing does. The buffer then leaves every other slot, and is no
---longer tracked.
---
---@param bufnr Bufnr
---@return nil
function M.undo_arrival(bufnr)
	local filehash = history.get_hash_from_buffer(bufnr)
	if not filehash then
		return
	end
	local ledger = require('cavediver.domains.ledger')
	for winid, triquetra in pairs(data.crux) do
		local arrival = data.arrivals[winid]
		if triquetra.current_slot == filehash then
			local before = ledger.slots(winid)
			if arrival and arrival.hash == filehash and arrival.after and vim.deep_equal(arrival.after, triquetra) then
				for _, key in ipairs({ "current_slot", "secondary_slot", "ternary_slot", "primary_buffer",
					"primary_enabled", "displacement_ternary_map", "displacement_secondary_map" }) do
					triquetra[key] = arrival.before[key]
				end
			elseif triquetra.ternary_slot then
				triquetra.current_slot, triquetra.ternary_slot = triquetra.ternary_slot, nil
			elseif triquetra.secondary_slot then
				triquetra.current_slot, triquetra.secondary_slot = triquetra.secondary_slot, nil
			elseif triquetra.primary_buffer[1] and triquetra.primary_buffer[1] ~= filehash then
				triquetra.current_slot = triquetra.primary_buffer[1]
			else
				data.unregister_triquetra(winid) -- nothing to come back to.
			end
			if data.crux[winid] then
				ledger.slots_moved("undone", winid, before, { words = "its buffer turned into something untracked" })
				M.check_notes_under_current(triquetra) -- a slot changed under the current buffer.
			else
				ledger.move("dropped", { subject = tostring(winid), name = ledger.window_name(winid),
					words = "its buffer turned into something untracked, with nothing to come back to" })
			end
		end
		if arrival and arrival.hash == filehash then
			data.arrivals[winid] = nil
		end
	end
	data.forget_hash_in_slots(filehash)

	local filepath = history.get_filepath_from_hash(filehash)
	history.routines.untrack_buffer(bufnr)
	history.routines.unregister_buffer(bufnr)
	if filepath then
		history.routines.unregister_filepath(filepath)
	end
	loop_sm:to(loop_states.SELF)
end

---This will take in FILEPATHS and validates the input FILEPATHS, to be put as the
---new primary buffers history for the triquetra.
---
---@param primary_filepaths Filepath[] The filepaths to update in the primary buffer
---@param winid WinId The window ID to update the primary buffer for
---@return nil
function M.update_primary_buffer(primary_filepaths, winid)
	local triquetra = data.get_window_triquetra(winid)

	if not triquetra then
		error("No triquetra found for window " .. winid)
	end

	local error_lines = {}
	local valid_filepaths = {}
	local seen = {}
	local queued = {} -- what the queue holds now: an entry gone from disk stays, as every pointer does
	for _, filehash in ipairs(triquetra.primary_buffer) do
		queued[filehash] = true
	end
	for _, filepath in ipairs(primary_filepaths) do
		local typed = filepath -- the messages name the line as it was typed
		if not filepath:match("^NONAME_") and vim.trim(filepath) ~= "" then
			filepath = vim.fn.fnamemodify(filepath, ":p") -- a relative path, as :e takes it
		end
		local fbufnr = history.routines.find_buffer_by_filepath(filepath) or -1 -- by its exact name, not a pattern
		if vim.trim(filepath) == "" then
			goto continue
		elseif seen[filepath] then -- the queue holds a file once
			table.insert(error_lines, "- Repeated: " .. typed)
			goto continue
		elseif (vim.fn.filereadable(filepath) == 0) and (not filepath:match("^NONAME_")) and not queued[history.get_hash_from_filepath(filepath)] then -- If it's a file that doesn't exist in the filesystem.
			table.insert(error_lines, "- File does not exist: " .. typed)
			goto continue
		elseif fbufnr ~= -1 and vim.api.nvim_buf_is_loaded(fbufnr) and history.get_hash_from_buffer(fbufnr) == nil then -- THE USER CANNOT REGISTER A BUFFER EXPLICITLY. IT IS DONE AUTOMATICALLY. SO we throw error instead of automatically registering it.
			-- history.register_buffer(fbufnr)
			table.insert(error_lines,
				"- You cannot set the file buffer [" ..
				typed .. "] that isn't tracked by cavediver to be a primary buffer.")
			goto continue
		elseif (fbufnr == -1 or not vim.api.nvim_buf_is_loaded(fbufnr)) and history.get_hash_from_filepath(filepath) == nil then -- If the filepath is not loaded by neovim and is not registered then register it.
			if filepath:match("^NONAME_") then                                 -- If the buffer_from_filepath query turned out to be nil and the filepath was just for NO NAME buffer then that means this NO_NAME buffer you have never existed, since the registry says so.
				table.insert(error_lines,
					" - [" ..
					filepath ..
					"] is not a registered no name buffer. You can only add registered no name buffers to the primary buffer.")
				goto continue
			else
				history.register_filepath(filepath)
				local filehash = history.get_hash_from_filepath(filepath)
				if filehash then
					history.routines.track_closing_filehash_force(filehash) -- It's fine, this line guarantees that the filepath is not NONAME_
				end
			end
		end
		table.insert(valid_filepaths, filepath)
		seen[filepath] = true
		::continue::
	end

	if #error_lines > 0 then
		vim.notify(
			"Error updating primary buffer for window " .. winid .. ":\n" .. table.concat(error_lines, "\n"),
			vim.log.levels.ERROR
		)
	end

	-- the primary switches on only when the first row changed; otherwise it stays as it was
	local first = valid_filepaths[1] and history.get_hash_from_filepath(valid_filepaths[1])
	if first and first ~= triquetra.primary_buffer[1] then
		triquetra.primary_enabled = true
	end
	triquetra.primary_buffer = vim.tbl_map(history.get_hash_from_filepath, valid_filepaths)

	loop_sm:to(loop_states.SELF)
end

---Remove buffer from closed buffers list by filehash.
---@param filehash Filehash The filehash to remove from closed buffers
local function remove_from_closed_buffers(filehash)
	history.routines.open_out_of_pools(filehash) -- open again, it's closed nowhere
end

---Check if a slot's file is closed and gone from disk.
---
---Its pointer is kept, since the file may come back, and using it says so instead.
---
---@param filehash Filehash|nil
---@return boolean missing True if the file has no buffer and isn't readable
local function is_missing(filehash)
	local filepath = filehash and history.get_filepath_from_hash(filehash)
	return filepath ~= nil and
		history.get_buffer_from_hash(filehash) == nil and
		not filepath:match("^NONAME_") and
		vim.fn.filereadable(filepath) == 0
end

---Say that a slot's file is gone from disk, and that the slot keeps it.
---@param filehash Filehash
---@param slot string The slot's name, as the message says it ("secondary slot")
local function say_missing(filehash, slot)
	vim.notify(require('cavediver.domains.ui').routines.get_smart_basename(filehash) ..
		" isn't on disk right now; the " .. slot .. " keeps it.", vim.log.levels.WARN)
end

---A function used to handle conflicts of slot allocations in the triquetra.
---@param winid WinId
---@param new_bufnr Bufnr
---@param is_pick boolean|nil Whether a cycling pick (<M-v>) lands here, rather than a load or a cancel
function M.reconcile_triquetra(winid, new_bufnr, is_pick)
	local new_filehash = history.get_hash_from_buffer(new_bufnr)

	if not new_bufnr then require('cavediver.domains.ledger').never("Bufnr must be provided.") end

	if not new_filehash then
		require('cavediver.domains.ledger').never("What the fuck.")
	end -- Skip unregistered buffers

	local triquetra = data.crux[winid]
	local temp, proc
	if triquetra and triquetra.current_slot ~= new_filehash then
		M.remember_arrival(winid, triquetra, new_filehash)
		local left, ternary_before = triquetra.current_slot, triquetra.ternary_slot
		M.keep_older_secondary_note(
			triquetra,
			new_filehash,
			(triquetra.secondary_slot == new_filehash) and triquetra.current_slot or triquetra.secondary_slot
		)
		-- Reconcile the triquetra slots if we selected a buffer part of the relationship
		if triquetra.ternary_slot == new_filehash then
			triquetra.displacement_ternary_map[triquetra.current_slot .. "-swap"] = triquetra.ternary_slot
			temp = triquetra.current_slot
			triquetra.current_slot = triquetra.ternary_slot
			triquetra.ternary_slot = temp
			proc = true
		end
		if triquetra.secondary_slot == new_filehash then
			if proc then
				require('cavediver.domains.ledger').never("Duplicates detected in triquetra slots")
			end
			-- the guard runs before the swap, so the ternary's memory gets the buffer being left.
			if triquetra.displacement_ternary_map[triquetra.ternary_slot] == new_filehash then
				triquetra.displacement_ternary_map[triquetra.ternary_slot] = triquetra.current_slot
				require('cavediver.domains.ledger').note("ternary", triquetra.ternary_slot, new_filehash, triquetra.current_slot, "guard")
				vim.notify(
					"Avoided conflict of ternary's remembered relationship becoming current. Remembered relationship has been changed to remember pre-jump current buffer instead: ["
					.. (history.get_buffer_from_hash(triquetra.ternary_slot) or "")
					.. "] -> ["
					.. (history.get_buffer_from_hash(triquetra.current_slot) or "")
					.. "]", vim.log.levels.WARN)
			end
			temp = triquetra.current_slot
			triquetra.current_slot = triquetra.secondary_slot
			triquetra.secondary_slot = temp
			proc = true
		end

		if not proc then
			if triquetra.displacement_ternary_map[triquetra.ternary_slot] == new_filehash then
				triquetra.displacement_ternary_map[triquetra.ternary_slot] = triquetra.current_slot
				require('cavediver.domains.ledger').note("ternary", triquetra.ternary_slot, new_filehash, triquetra.current_slot, "guard")
				vim.notify(
					"Avoided conflict of ternary's remembered relationship becoming current. Remembered relationship has been changed to remember pre-jump current buffer instead: ["
					.. (history.get_buffer_from_hash(triquetra.ternary_slot) or "")
					.. "] -> ["
					.. (history.get_buffer_from_hash(triquetra.current_slot) or "")
					.. "]", vim.log.levels.WARN)
			end
			triquetra.current_slot = new_filehash
			-- a pick outside the slots notes where the cycle started, so a ternary restore brings it
			-- back; the picked buffer's older swap note would win the restore, so it goes.
			if is_pick and left ~= nil then
				triquetra.displacement_ternary_map[new_filehash] = left
				triquetra.displacement_ternary_map[new_filehash .. "-swap"] = nil
			end
		end
		M.keep_older_ternary_note(
			triquetra,
			new_filehash,
			left,
			ternary_before,
			(new_filehash == ternary_before) and left or ternary_before
		)
		M.seal_arrival(winid, triquetra)
	end
end

---Land a window whose buffer got deleted, once the delete is over.
---
---It goes to the ternary, then the secondary, then the primary, then the most recent buffer. With
---nothing to land on it keeps the empty buffer Neovim gave it, and only makes one if Neovim showed
---something else. Neovim's own pick in between isn't recorded as a visit (see `M.is_landing_pick()`).
---
---@param winid WinId The window that was showing the deleted buffer
---@param deleted_bufnr Bufnr The buffer being deleted
---@return nil
function M.land_after_delete(winid, deleted_bufnr)
	local landing = { deleted = deleted_bufnr, pick = nil }
	data.landing[winid] = landing
	require('cavediver.settle').later("landing", function()
		if data.landing[winid] == landing then
			data.landing[winid] = nil
		end
		local triquetra = data.crux[winid]
		if not triquetra or not vim.api.nvim_win_is_valid(winid) then
			return -- neovim closed the window, nothing to land.
		end
		-- still listed and still shown: it wasn't deleted, it was renamed.
		if
			vim.api.nvim_buf_is_valid(deleted_bufnr) and
			vim.bo[deleted_bufnr].buflisted and
			vim.api.nvim_win_get_buf(winid) == deleted_bufnr
		then
			return
		end
		-- the window moved on since neovim's pick (another :e in the same batch), so that's where it is.
		if landing.pick and vim.api.nvim_win_get_buf(winid) ~= landing.pick then
			return
		end

		local function open(filehash)
			local bufnr = history.get_buffer_from_hash(filehash)
			if bufnr and bufnr ~= deleted_bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				return bufnr
			end
		end

		local ledger = require('cavediver.domains.ledger')
		local before, from = ledger.slots(winid), "recent"
		local landing_bufnr
		if triquetra.ternary_slot and open(triquetra.ternary_slot) then
			landing_bufnr = open(triquetra.ternary_slot)
			triquetra.current_slot = triquetra.ternary_slot
			triquetra.ternary_slot = nil
			from = "ternary"
		elseif triquetra.secondary_slot and open(triquetra.secondary_slot) then
			landing_bufnr = open(triquetra.secondary_slot)
			triquetra.current_slot = triquetra.secondary_slot
			triquetra.secondary_slot = nil
			from = "secondary"
		elseif triquetra.primary_buffer[1] and open(triquetra.primary_buffer[1]) then
			landing_bufnr = open(triquetra.primary_buffer[1])
			triquetra.current_slot = triquetra.primary_buffer[1]
			from = "primary"
		else
			-- the most recent buffer, in the bufferline's order (it follows history_view).
			for _, item in ipairs(history.get_ordered_buffers()) do
				local filehash = history.get_hash_from_buffer(item.buf)
				if filehash and open(filehash) then
					landing_bufnr = item.buf
					triquetra.current_slot = filehash
					break
				end
			end
		end

		if landing_bufnr then
			ledger.slots_moved("landed", winid, before, { from = from })
			M.check_notes_under_current(triquetra) -- a buffer became current under the slots, its notes may be stale.
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

---Check if this BufEnter is Neovim's own pick for a window whose buffer is being deleted.
---
---Only the first one counts, and only once the buffer has left the buffer list (a rename keeps it).
---
---@param winid WinId
---@param bufnr Bufnr The buffer being entered
---@return boolean pick True if it's Neovim's pick, which isn't recorded as a visit
function M.is_landing_pick(winid, bufnr)
	local landing = data.landing[winid]
	if
		not landing or
		landing.pick or
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
---@param bufnr_ondelete nil | Bufnr
---@return nil
function M.cleanup_triquetras(bufnr_ondelete)
	local set_cache_from_window_triquetra = require("cavediver").ui.routines.set_cache_from_window_triquetra
	local ledger = require('cavediver.domains.ledger')
	local slots_before, rows_before = {}, {}
	for winid, triquetra in pairs(data.crux) do
		slots_before[winid] = { triquetra.current_slot, triquetra.secondary_slot, triquetra.ternary_slot }
		rows_before[winid] = ledger.slots(winid)
	end
	for winid, triquetra in pairs(data.crux) do
		if not vim.api.nvim_win_is_valid(winid) then
			-- a window gone without its WinClosed: closed while cavediver was off, or with noautocmd
			data.unregister_triquetra(winid)
			goto continue
		end
		local current_bufnr = history.get_buffer_from_hash(triquetra.current_slot)
		local filepath, bufnr
		if not current_bufnr then -- this is a special case. we can't have an unregistered
			-- hash in the current slot. doesn't make sense.
			local current_slot_candidate = history.get_hash_from_buffer(vim.api.nvim_win_get_buf(winid))
			if current_slot_candidate then
				vim.notify("Healed the triquetra of window " ..
					winid .. " with current slot: " .. vim.api.nvim_win_get_buf(winid))
				-- like navigation: the old current goes into the ternary, or trades places with the
				-- secondary when that's what the window shows now, with the notes navigation writes.
				if current_slot_candidate == triquetra.secondary_slot then
					M.write_secondary_swap_notes(triquetra)
					triquetra.secondary_slot = triquetra.current_slot
				else
					if triquetra.ternary_slot and current_slot_candidate ~= triquetra.ternary_slot then
						triquetra.displacement_ternary_map[triquetra.current_slot .. "-swap"] = nil
						triquetra.displacement_ternary_map[triquetra.current_slot] = triquetra.ternary_slot
					end
					triquetra.ternary_slot = triquetra.current_slot
				end
				triquetra.current_slot = current_slot_candidate
			else
				-- print("Running cleanup_triquetras [" .. winid .. "] with unregistered current slot: " .. (history.get_filepath_from_hash(triquetra.current_slot) or "nil"))
				-- yes if the noname buffer turns evolved into a terminal, we don't want to track it.
				--
				-- but there is a catch, what if the buffer's file was just deleted along the way? Then
				-- we just remove that current slot from the triquetra, and replace it with ternary, then
				-- secondary, then primary, then most recent buffer, if the tracked is more than 1.
				-- print("(2) Deleted window triquetra of bufnr: " .. index)
				local cbufnr, cbufhash, cbufname
				if vim.api.nvim_win_is_valid(winid) then
					cbufnr = vim.api.nvim_win_get_buf(winid)
					cbufname = vim.api.nvim_buf_get_name(cbufnr)
					if cbufname == "" then
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
				if cbufhash == triquetra.current_slot and vim.bo[cbufnr].buftype == "" then
					-- the window still shows the current slot's file, it's only unregistered for the moment
					-- (a reload without events). there's nothing to heal.
					goto continue
				end
				if history.routines.is_filehash_closed(triquetra.current_slot) then
					-- the window is visiting something we don't track and keeps its triquetra: a closed
					-- current slot stays, it's the file the window was last on.
					goto continue
				end
				if cbufhash == triquetra.current_slot or vim.bo[cbufnr].buftype == "acwrite" then -- it means that the buffer didn't evolved to anything new. it was still deleted, so we fallback.
					-- Part 1: Try Heal triquetra with self
					---Whether a slot took the current slot's place
					---@type boolean
					local resolved = false
					local bufnr
					if triquetra.ternary_slot and history.get_buffer_from_hash(triquetra.ternary_slot) then
						triquetra.current_slot = triquetra.ternary_slot
						triquetra.ternary_slot = nil
						bufnr = history.get_buffer_from_hash(triquetra.current_slot)
						resolved = history.routines.update_buffer_history(bufnr)
						-- print("#1")
					end
					if not resolved and triquetra.secondary_slot and history.get_buffer_from_hash(triquetra.secondary_slot) then
						triquetra.current_slot = triquetra.secondary_slot
						triquetra.secondary_slot = nil
						bufnr = history.get_buffer_from_hash(triquetra.current_slot)
						resolved = history.routines.update_buffer_history(bufnr)
						-- print("#2")
					end
					if not resolved and triquetra.primary_buffer[1] and history.get_buffer_from_hash(triquetra.primary_buffer[1]) then
						triquetra.current_slot = triquetra.primary_buffer[1]
						bufnr = history.get_buffer_from_hash(triquetra.current_slot)
						resolved = history.routines.update_buffer_history(bufnr)
						-- print("#3")
					end

					if resolved then -- I know this is fucking stupid, but I don't want to change the structure of this function.
						history.routines.update_buffer_history_ordered()
						history.routines.update_buffer_history_ordered_nonharpooned()
						-- print("#4")
						goto continue -- the window keeps showing what it shows: cleanup never touches a window.
					end

					-- Part 2: This is when we can't heal it straightforward anymore.
					if history.get_filepath_from_hash(triquetra.current_slot) ~= nil then
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
						local candidate_hash = history.get_hash_from_buffer(history.get_ordered_buffers()[1].buf)
						if candidate_hash then
							triquetra.current_slot = candidate_hash
						else
							require('cavediver.domains.ledger').never(
								"This is impossible. Ordered history buffers should always have a hash associated with it.")
						end
					else
						-- nothing to put in the current slot, and cleanup doesn't touch the window to make
						-- something: the window is left with no triquetra, as one born untracked.
						data.unregister_triquetra(winid)
						goto continue
					end
				else -- it's visiting, and its current slot names nothing open or closed any more: there's nothing
					-- to come back to.
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
					data.unregister_triquetra(winid)
				end
				goto continue
			end
		end

		filepath = history.get_filepath_from_hash(triquetra.secondary_slot)
		bufnr = history.get_buffer_from_hash(triquetra.secondary_slot)
		if
			triquetra.secondary_slot ~= nil and
			(
				not filepath or
				(
					not filepath:match("^NONAME_") and
					(
						(
							bufnr == nil and
							not history.routines.is_filehash_closed(triquetra.secondary_slot)
						-- i.e. if the buffer is not registered (typically means that buffer is closed) and
						-- it is not registered as closed in the closed buffers list. something is wrong
						-- with the triquetra, so we just remove it.
						)
					)
				)
			)
		then
			if bufnr then
				history.routines.unregister_buffer(bufnr)
			end
			triquetra.secondary_slot = nil
		end

		filepath = history.get_filepath_from_hash(triquetra.ternary_slot)
		bufnr = history.get_buffer_from_hash(triquetra.ternary_slot)
		if
			triquetra.ternary_slot ~= nil and
			(
				not filepath or
				(
					not filepath:match("^NONAME_") and
					(
						(
							bufnr == nil and
							not history.routines.is_filehash_closed(triquetra.ternary_slot)
						-- i.e. if the buffer is not registered (typically means that buffer is closed) and
						-- it is not registered as closed in the closed buffers list. something is wrong
						-- with the triquetra, so we just remove it.
						)
					)
				)
			)
		then
			if bufnr then
				history.routines.unregister_buffer(bufnr)
			end
			triquetra.ternary_slot = nil
		end

		local pfilehash
		for index = #(triquetra.primary_buffer or {}), 1, -1 do
			pfilehash = triquetra.primary_buffer[index]
			bufnr = history.get_buffer_from_hash(pfilehash)
			filepath = history.get_filepath_from_hash(pfilehash)

			if
				not filepath or
				(
					not filepath:match("^NONAME_") and
					(
						(
							bufnr == nil and
							not history.routines.is_filehash_closed(pfilehash)
						-- i.e. if the buffer is not registered (typically means that buffer is closed) and
						-- it is not registered as closed in the closed buffers list. something is wrong
						-- with the triquetra, so we just remove it.
						)
					)
				)
			then
				if bufnr then
					history.routines.unregister_buffer(bufnr)
				end
				table.remove(triquetra.primary_buffer, index)
			end
		end


		filepath = history.get_filepath_from_hash(triquetra.current_slot)
		if not filepath then
			bufnr = history.get_buffer_from_hash(triquetra.current_slot)
			if bufnr then
				history.routines.unregister_buffer(bufnr)
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
			M.check_notes_under_current(triquetra)
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

	local cbufnr = history.get_buffer_from_hash(triquetra.current_slot)
	if cbufnr == nil and history.get_hash_from_buffer(vim.api.nvim_win_get_buf(winid)) == nil then
		-- visiting, with the current slot closed: going back to it reopens it.
		if is_missing(triquetra.current_slot) then
			say_missing(triquetra.current_slot, "current slot")
			return
		end
		cbufnr = history.reopen_filehash(triquetra.current_slot)
	end

	-- check if the current buffer of the window is the triquetra current. If not,
	-- then we just jump to the triquetra current window.
	if cbufnr and cbufnr ~= vim.api.nvim_win_get_buf(winid) then
		vim.notify("Jumped back to windows current buffer.", vim.log.levels.INFO)
		vim.api.nvim_set_current_buf(cbufnr)
		return -- we just jump.
	end

	if triquetra.secondary_slot == nil then
		cbufnr = history.get_buffer_from_hash(triquetra.current_slot)
		if triquetra.ternary_slot ~= nil then
			triquetra.secondary_slot = triquetra.ternary_slot
			triquetra.displacement_secondary_map[triquetra.secondary_slot] =
				triquetra.displacement_ternary_map[triquetra.secondary_slot]
			triquetra.displacement_secondary_map[triquetra.secondary_slot .. "-swap"] = nil
			triquetra.ternary_slot = nil
			M.check_notes_under_current(triquetra)
			vim.notify("Secondary buffer set to ternary slot. Ternary slot graduated.", vim.log.levels.INFO)
		elseif #history.data.ordered.crux >= 2 then
			-- the ordered list's first entry is the window's current buffer, or the second one could be it too.
			if history.get_hash_from_buffer(history.data.ordered.crux[1].buf) ~= triquetra.current_slot then
				require('cavediver.domains.ledger').never("This is impossible. The most recent buffer in the history must be the window's current buffer.")
			end
			triquetra.secondary_slot = history.get_hash_from_buffer(history.data.ordered.crux[2].buf)
			M.check_notes_under_current(triquetra)
			vim.notify("Secondary buffer populated from history.", vim.log.levels.INFO)
		else
			vim.notify("Cannot populate secondary slot - insufficent history.", vim.log.levels.WARN)
		end
	else
		if is_missing(triquetra.secondary_slot) then
			say_missing(triquetra.secondary_slot, "secondary slot")
			return
		end
		if triquetra.current_slot then
			M.write_secondary_swap_notes(triquetra)
		else
			require('cavediver.domains.ledger').never("It's not okay to have a secondary slot without a current slot.")
		end
		cbufnr = history.get_buffer_from_hash(triquetra.secondary_slot)
		if cbufnr == nil then
			local old_basename = require('cavediver.domains.ui').routines.get_smart_basename(triquetra.secondary_slot)
			local old_secondary_filehash = triquetra.secondary_slot
			cbufnr = history.reopen_filehash(triquetra.secondary_slot)
			if cbufnr == nil then
				vim.notify(
					"Removed secondary file not found in filesystem: " .. old_basename,
					vim.log.levels.WARN)
				triquetra.secondary_slot = nil
				loop_sm:to(loop_states.SELF)
				return
			else
				remove_from_closed_buffers(triquetra.secondary_slot)
				vim.notify("File reopened for secondary slot: " .. old_basename .. " - old: " .. old_secondary_filehash,
					vim.log.levels.INFO)
			end
		end
		local cfilehash = history.get_hash_from_buffer(cbufnr)
		if not cfilehash then
			require('cavediver.domains.ledger').never("This is impossible. Ternary slot should always have a buffer associated with it.")
		end

		local filepath = history.get_filepath_from_hash(cfilehash)

		if filepath and filepath:match("^NONAME_") then
			data.rename_hash_in_triquetras(triquetra.secondary_slot, cfilehash)
		end

		M.reconcile_triquetra(winid, cbufnr)

		vim.api.nvim_set_current_buf(cbufnr)
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

	local cbufnr = history.get_buffer_from_hash(triquetra.current_slot)
	if cbufnr == nil and history.get_hash_from_buffer(vim.api.nvim_win_get_buf(winid)) == nil then
		-- visiting, with the current slot closed: going back to it reopens it.
		if is_missing(triquetra.current_slot) then
			say_missing(triquetra.current_slot, "current slot")
			return
		end
		cbufnr = history.reopen_filehash(triquetra.current_slot)
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

	cbufnr = history.get_buffer_from_hash(triquetra.ternary_slot)
	if cbufnr == nil then
		local old_basename = require('cavediver.domains.ui').routines.get_smart_basename(triquetra.ternary_slot)
		local old_ternary_filehash = triquetra.ternary_slot
		cbufnr = history.reopen_filehash(triquetra.ternary_slot)
		if cbufnr == nil then
			vim.notify("Removed ternary file not found in filesystem: " .. old_basename,
				vim.log.levels.WARN)
			triquetra.ternary_slot = nil
			loop_sm:to(loop_states.SELF)
			return
		else
			remove_from_closed_buffers(triquetra.ternary_slot)
			vim.notify("File reopened for ternary slot: " .. old_basename .. " - old: " .. old_ternary_filehash,
				vim.log.levels
				.INFO)
		end
	end
	local cfilehash = history.get_hash_from_buffer(cbufnr)
	if cfilehash then
		data.rename_hash_in_triquetras(triquetra.ternary_slot, cfilehash)
	else
		require('cavediver.domains.ledger').never("This is impossible. Ternary slot should always have a buffer associated with it.")
	end
	M.reconcile_triquetra(winid, cbufnr)

	vim.api.nvim_set_current_buf(cbufnr)

	loop_sm:to(loop_states.SELF)
end

---Jump to the target window's primary buffer.
---
---@param winid WinId The target window ID
---@return nil
function M.jump_to_primary(winid)
	local navigation = require("cavediver.domains.navigation")
	local triquetra = data.get_window_triquetra(winid)
	if not triquetra then
		vim.notify("Window with unregistered buffer.", vim.log.levels.WARN)
		return
	end
	if navigation.is_cycling() then
		local cycling_origins = history.get_cycling_origins(winid)
		local ui_get_basename = require('cavediver.domains.ui').routines.get_smart_basename

		if not cycling_origins then
			require('cavediver.domains.ledger').never("This should not happen. Cycling origins not found for window: " .. winid)
		end

		local origin_bufnr = history.get_buffer_from_hash(cycling_origins.current_slot)

		if not origin_bufnr then
			require('cavediver.domains.ledger').never("This should not happen. Origin buffer not found for current slot: " .. cycling_origins.current_slot)
		end

		vim.api.nvim_set_current_buf(origin_bufnr)
		triquetra.current_slot = cycling_origins.current_slot
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
	local cbufnr = history.get_buffer_from_hash(triquetra.primary_buffer[1])
	if cbufnr == nil then
		cbufnr = history.reopen_filehash(triquetra.primary_buffer[1])
		if cbufnr and history.get_filepath_from_buffer(cbufnr):match("^NONAME_") then
			table.remove(triquetra.primary_buffer, 1)
			table.insert(triquetra.primary_buffer, 1, history.get_hash_from_buffer(cbufnr))
		end
		if cbufnr == nil then
			-- a No Name text that's lost can't come back, so it leaves the queue
			vim.notify("Removed primary file not found in filesystem: " ..
				require('cavediver.domains.ui').routines.get_smart_basename(triquetra.primary_buffer[1]),
				vim.log.levels.WARN)
			table.remove(triquetra.primary_buffer, 1)
			loop_sm:to(loop_states.SELF)
			return
		else
			remove_from_closed_buffers(triquetra.primary_buffer[1])
		end
	end
	if triquetra.current_slot ~= triquetra.primary_buffer[1] then -- We only do displacment if we are not already in the primary buffer.
		local left, ternary_before = triquetra.current_slot, triquetra.ternary_slot
		triquetra.displacement_ternary_map[triquetra.current_slot .. "-swap"] = triquetra.ternary_slot
		triquetra.ternary_slot = triquetra.current_slot
		triquetra.current_slot = triquetra.primary_buffer[1]
		M.keep_older_secondary_note(triquetra, triquetra.current_slot, triquetra.secondary_slot)
		M.keep_older_ternary_note(triquetra, triquetra.current_slot, left, ternary_before, left)
	else
		vim.notify("Already in primary buffer, no displacement performed.", vim.log.levels.INFO)
	end

	M.reconcile_triquetra(winid, cbufnr)
	vim.api.nvim_set_current_buf(cbufnr)
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
		triquetra.primary_buffer[1] = triquetra.current_slot
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
		triquetra.primary_buffer[1] = triquetra.current_slot
		triquetra.primary_enabled = true
	elseif triquetra.primary_buffer[1] ~= triquetra.current_slot then
		local existing_index = vim.fn.index(triquetra.primary_buffer, triquetra.current_slot)
		if existing_index ~= -1 then
			table.remove(triquetra.primary_buffer, existing_index + 1)
		end
		table.insert(triquetra.primary_buffer, 1, triquetra.current_slot)
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
---@param triquetra WindowTriquetra
local function restore_from_displacement_map(type, triquetra)
	local current_relationship = triquetra[type .. "_slot"]
	local remembered_mapping = triquetra["displacement_" .. type .. "_map"]

	-- a note at a hash nothing knows any more is cleared when it's used.
	for _, key in ipairs({ triquetra.current_slot .. "-swap", triquetra.current_slot }) do
		if remembered_mapping[key] ~= nil and history.get_filepath_from_hash(remembered_mapping[key]) == nil then
			require('cavediver.domains.ledger').note(type, triquetra.current_slot, remembered_mapping[key], nil, "no path")
			remembered_mapping[key] = nil
		end
	end

	-- a closed buffer whose file is gone from disk can't come back now. its note stays, it may come back.
	local function missing_and_closed(filehash)
		local filepath = history.get_filepath_from_hash(filehash)
		return filepath ~= nil and
			not filepath:match("^NONAME_") and
			vim.fn.filereadable(filepath) == 0 and
			history.get_buffer_from_hash(filehash) == nil
	end

	local remembered_relationship = remembered_mapping[triquetra.current_slot .. "-swap"]

	if
		remembered_relationship == nil or
		remembered_relationship == current_relationship or
		missing_and_closed(remembered_relationship)
	then
		remembered_relationship = remembered_mapping[triquetra.current_slot]
	end

	local filepath = history.get_filepath_from_hash(remembered_relationship)

	if not remembered_relationship then
		vim.notify(
			"No " ..
			type ..
			" relationship found for restoration. It means you hadn't displaced a current buffer yet to the " ..
			type .. " slot.", vim.log.levels.WARN)
	elseif missing_and_closed(remembered_relationship) then
		local ui_get_basename = require('cavediver.domains.ui').routines.get_smart_basename
		vim.notify("Remembered " .. type .. " isn't on disk right now: " .. ui_get_basename(remembered_relationship) .. ". Nothing changed.", vim.log.levels.WARN)
	elseif remembered_relationship == current_relationship then
		require('cavediver.domains.ledger').never("This is impossible. Remembered " ..
			type .. " is the same as current " .. type .. ". It should be different for flip flop.")
	else
		local ui_get_basename = require('cavediver.domains.ui').routines.get_smart_basename
		if type == "ternary" then
			if remembered_relationship == triquetra.secondary_slot then
				triquetra.secondary_slot = triquetra.ternary_slot
				triquetra.ternary_slot = remembered_relationship
			else
				triquetra.ternary_slot = remembered_relationship
			end
		elseif type == "secondary" then
			if remembered_relationship == triquetra.ternary_slot then
				triquetra.ternary_slot = triquetra.secondary_slot
				triquetra.secondary_slot = remembered_relationship
			else
				triquetra.secondary_slot = remembered_relationship
			end
		end
		local restored = "Restored " .. type .. " slot to: " .. remembered_relationship .. " (" .. ui_get_basename(remembered_relationship) .. ")"
		if not filepath:match("^NONAME_") and vim.fn.filereadable(filepath) == 0 then
			-- its buffer is still open, so it comes back; the file just isn't on disk right now.
			vim.notify(restored .. ", not on disk right now", vim.log.levels.WARN)
		else
			vim.notify(restored, vim.log.levels.INFO)
		end
		triquetra["displacement_" .. type .. "_map"][triquetra.current_slot] = current_relationship
		-- a slot changed under the current buffer (both, at an exchange), so its notes may name them now.
		M.check_notes_under_current(triquetra)
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
	local set_cache_from_window_triquetra = require("cavediver.domains.ui").set_cache_from_window_triquetra
	data.crux = {}
	data.last_valid_window = vim.api.nvim_get_current_buf()

	for _, winid in pairs(vim.api.nvim_list_wins()) do
		local current_slot = history.get_hash_from_buffer(vim.api.nvim_win_get_buf(winid))
		if current_slot == nil then
			vim.notify("skipping window " .. winid .. " because it has no registered buffer.", vim.log.levels.INFO)
			goto continue
		end

		history.routines.ensure_window_entry(winid) -- every triquetra comes with its window's history entry.
		data.crux[winid] = {
			current_slot = current_slot,
			secondary_slot = nil,
			ternary_slot = nil,
			primary_buffer = {},
			displacement_secondary_map = {},
			displacement_ternary_map = {},
			primary_enabled = false,
		}
		set_cache_from_window_triquetra(winid)
		::continue::
	end
end

return M
