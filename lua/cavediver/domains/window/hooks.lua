---Window domain hooks for extending the history state machine.
---
---The window domain extends the history state machine with hooks that manage
---per-window buffer relationships. These hooks run after the history domain
---hooks to ensure proper execution order.

local history = require('cavediver.domains.history')
local navigation = require("cavediver.domains.navigation")

local routines = require('cavediver.domains.window.routines')
local data = require('cavediver.domains.window.data')

-- a load from idle starts from nothing, as at startup: no window has a triquetra, nor its winbar.
local storageSM = require('cavediver.domains.storage.sm')
local storageStates = require('cavediver.domains.storage.states')
storageSM:on(storageStates.IDLE, storageStates.BARE, "window_teardown", function()
	for winid, _ in pairs(data.crux) do
		if vim.api.nvim_win_is_valid(winid) then
			require('cavediver.domains.ui.routines').remove_winbar_string(winid)
		end
	end
	data.crux = {}
	data.landing = {}
	data.arrivals = {}
	data.current_window = vim.api.nvim_get_current_win()
	data.last_valid_window = data.current_window
end, 2, true)

history.sm:on("*", "*", "ensure_curwin_crux", function(context, _, _)
	local winid = context.winid or vim.api.nvim_get_current_win()
	local triquetra = data.get_window_triquetra(winid) -- creates triquetra for us, or not will return nil instead. 
	if not triquetra then
		context.window = nil
	end
end, 1, true, history.states.mode.UPDATE)

history.sm:on("*", "*", "cleanup_triquetras", function(context, _, _)
	-- the filepath-hash registry is the source of truth. If it don't exist, then it shouldn't be in the triquetra.
	-- It's an close empty noname buffer. And We don't really want this to be tracked when it's closed.
	if (context.mode == history.states.mode.DELETE) and context.buf then
		routines.cleanup_triquetras(context.buf)
	else
		routines.cleanup_triquetras()
	end
end, 1.8, true)

history.sm:on(history.states.ATTACHED, history.states.ATTACHED, "displacement_mangement", function(context, _, _)
	if context.history_modified == nil then
		require('cavediver.domains.ledger').never("history_modified is nil in displacement_mangement hook")
	elseif context.history_modified == false then
		return -- skip if history didn't update anything.
	end
	local winid = vim.api.nvim_get_current_win()
	local new_bufnr = context.buf
	local new_filehash = history.get_hash_from_buffer(new_bufnr)

	if not new_filehash then return end -- Skip unregistered buffers

	local triquetra = data.crux[winid]
	if not triquetra then
		return
	end
	if triquetra.current_slot ~= new_filehash then
		routines.remember_arrival(winid, triquetra, new_filehash)
	end
	-- happens when you are dealing with an empty ternary slot and it's just an ordinary
	-- swap with the secondary slot.
	if triquetra.secondary_slot == new_filehash then
		-- plain navigation onto the secondary leaves the same notes as <M-f>, and runs the guard
		-- before the swap, so the ternary's memory gets the buffer being left.
		local left, ternary = triquetra.current_slot, triquetra.ternary_slot
		routines.write_secondary_swap_notes(triquetra)
		if triquetra.displacement_ternary_map[triquetra.ternary_slot] == new_filehash then
			triquetra.displacement_ternary_map[triquetra.ternary_slot] = triquetra.current_slot
			require('cavediver.domains.ledger').note("ternary", triquetra.ternary_slot, new_filehash, triquetra.current_slot, "guard")
			vim.notify("Avoided conflict of ternary's remembered relationship becoming current.", vim.log.levels.WARN)
		end
		triquetra.secondary_slot = triquetra.current_slot
		triquetra.current_slot = new_filehash
		routines.keep_older_ternary_note(triquetra, new_filehash, left, ternary, ternary)
	elseif triquetra.current_slot ~= new_filehash then
		-- Only create displacement mapping if NOT in cycling mode
		-- and the new bufnr is not the current alternative slot.
		if navigation.sm:state() == navigation.states.NORMAL then
			if
				triquetra.secondary_slot and
				triquetra.ternary_slot and
				triquetra.secondary_slot == triquetra.ternary_slot
			then
				require('cavediver.domains.ledger').never("Duplicates detected in current triquetra")
			end
			if triquetra.ternary_slot and new_filehash ~= triquetra.ternary_slot then
				triquetra.displacement_ternary_map[triquetra.current_slot.."-swap"] = nil
				triquetra.displacement_ternary_map[triquetra.current_slot] = triquetra.ternary_slot
			end

			if triquetra.current_slot == triquetra.displacement_ternary_map[new_filehash] then
				if triquetra.ternary_slot == new_filehash then
					vim.notify(
						"The stored ternary of the new buffer is already the ternary, switching with the pre-jump stored ternary.",
						vim.log.levels.WARN
					)
					triquetra.displacement_ternary_map[new_filehash] = triquetra.displacement_ternary_map[triquetra.current_slot]
					require('cavediver.domains.ledger').note("ternary", new_filehash, triquetra.current_slot,
						triquetra.displacement_ternary_map[new_filehash], "navigation")
				else
					vim.notify(
						"The stored ternary of the new buffer is already the ternary, switching with the pre-jump ternary.",
						vim.log.levels.WARN
					)
					triquetra.displacement_ternary_map[new_filehash] = triquetra.ternary_slot
					require('cavediver.domains.ledger').note("ternary", new_filehash, triquetra.current_slot, triquetra.ternary_slot, "navigation")
				end
			end
		end
		-- so that we don't update with bad information. This is bad information, 
		-- it doesn't provide anything outside the current ternary relationship.
		-- We are tracking for buffers outside, that were ternary slots.

		-- Always update slots
		triquetra.ternary_slot = triquetra.current_slot
		triquetra.current_slot = new_filehash
		routines.keep_older_secondary_note(triquetra, new_filehash, triquetra.secondary_slot)
	end
	routines.seal_arrival(winid, triquetra)
end, 2, true, history.states.mode.UPDATE)

history.sm:on(history.states.DETACHED, history.states.ATTACHED, "reconcile_triquetra", function(context, _, _)
	if context.history_modified == nil then
		require('cavediver.domains.ledger').never("history_modified is nil in reconcile_triquetra hook")
	elseif context.history_modified == false then
		return -- skip if history didn't update anything.
	end
	if context.buf == nil then
		require('cavediver.domains.ledger').never("context.buf is nil in reconcile_triquetra hook")
	end
	routines.reconcile_triquetra(vim.api.nvim_get_current_win(), context.buf, context.pick)
end, 2, true, history.states.mode.UPDATE)

-- no displacement
history.sm:on(history.states.DETACHED, history.states.DETACHED, "nondisplacement_management", function(context)
	local winid = context.winid
	local new_filehash = history.get_hash_from_buffer(context.buf)

	if winid == nil or new_filehash == nil then
		return
	end

	local triquetra = data.crux[winid]
	if triquetra and triquetra.current_slot ~= new_filehash then
		triquetra.current_slot = new_filehash
	end

end, 2, true, history.states.mode.UPDATE)

navigation.sm:on("*", "*", "winenter_track_current_window", function(context)
	local current_window = vim.api.nvim_get_current_win()
	data.current_window = current_window
end, 2, true, navigation.states.mode.WINENTER)

local M = {}

---Create the window domain's autocmds in cavediver's augroup. setup() calls this, so nothing
---runs at require, and calling it again after the group is cleared replaces them cleanly.
---
---@param group integer The cavediver augroup
function M.init_autocmds(group)
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			local winid = tonumber(args.file)
			data.unregister_triquetra(winid)
		end,
	})

	-- a buffer whose buftype changes after it was slotted (a plugin's scratch, entered as a plain buffer)
	-- has its arrival undone, once the editor settles.
	vim.api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = "buftype",
		callback = function()
			local bufnr = vim.api.nvim_get_current_buf()
			require('cavediver.settle').later("buftype undo", function()
				if
					vim.api.nvim_buf_is_valid(bufnr) and
					history.get_hash_from_buffer(bufnr) and
					not history.routines.is_trackable(bufnr)
				then
					routines.undo_arrival(bufnr)
				end
			end)
		end,
	})
end

return M
