---Snapshots domain initialization and API layer.
---
---The snapshots domain keeps each window's snapshots: its setup as it was, taken on purpose, its files
---held by the snapshot's place. This module provides the API layer and the autocmds that hold a
---closed window's snapshots over.

local data = require('frogman.domains.snapshots.data')
local routines = require('frogman.domains.snapshots.routines')

local M = {
	data = data,         -- Domain data structures
	routines = routines, -- Domain business logic
}

M.take = routines.take
M.list = require('frogman.domains.snapshots.list')
M.open_list = M.list.open
M.preview = require('frogman.domains.snapshots.preview')

-- going to another window leaves a snapshot showing, once the editor settles, as it cancels a cycle
local navigation = require('frogman.domains.navigation')
navigation.sm:on("*", "*", "cancel_preview_on_window_jump", function()
	local shown_in = M.preview.window()
	if shown_in == nil or shown_in == vim.api.nvim_get_current_win() or vim.fn.getcmdwintype() ~= "" then
		return
	end
	require('frogman.settle').later("preview cancel", function()
		if M.preview.window() and M.preview.window() ~= vim.api.nvim_get_current_win() then
			M.preview.cancel()
		end
	end)
-- after the window's own (2) and a cycle's cancel (2.1)
end, 2.2, true, navigation.states.mode.WINENTER)

-- a move onto a name a snapshot holds: the snapshot keeps the file once, by the live slots' rule, as the
-- move settles, and the trail says which slots let it go
local history = require('frogman.domains.history')
history.handles.model:on("*", "*", "snapshots_take_over", function(context, handle)
	if context.other then
		context.cleared = routines.take_over(context.other, handle.id)
	end
end, 5, true, history.handles.states.mode.RENAME)

-- a file let go leaves every snapshot's notes; one let go for a moved file isn't gone, its notes naming
-- the moved file now
history.handles.model:on("*", "*", "snapshot_notes_let_go", function(_, handle)
	if history.handles.resolve(handle.id) == handle.id then
		routines.let_go_notes(handle.id)
	end
end, 7, true, history.handles.states.mode.FORGET)

-- a load from idle starts from nothing, as at startup: no snapshot, before the handles go
local storageSM = require('frogman.domains.storage.sm')
local storageStates = require('frogman.domains.storage.states')
-- a snapshot showing ends first, while the windows still have their slots for its window to go back by
storageSM:on(storageStates.IDLE, storageStates.BARE, "preview_teardown", function()
	M.preview.teardown(true)
end, 1.5, true)
storageSM:on(storageStates.IDLE, storageStates.BARE, "snapshots_teardown", function()
	routines.teardown()
end, 2.6, true)

---Create the snapshots domain's autocmds in frogman's augroup.
---
---Called by setup(), so nothing runs at require. A closed window's snapshots are held over in its
---session's scope once the editor settles, the list's keys are mapped on its buffer, and while a
---snapshot shows, what `:e` opens in its window is borrowed and a write of a borrowed buffer noted.
---
---@param group integer The frogman augroup
---@return nil
function M.init_autocmds(group)
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			local winid = tonumber(args.file)
			if winid == nil then
				return
			end
			-- onto its saved entry in its session's file, as they stand, when it has one there; else held over
			-- in its session's scope once the editor settles, unless a load comes first
			local session, what = require('frogman.held').closing_in(winid)
			local onto = require('frogman.domains.storage').routines.close_onto_entry("window", winid, session, what)
			if data.by_window[winid] then
				routines.queue_hold_over(winid, onto)
			end
		end,
	})
	-- :e in the window a snapshot shows in is a step: what it opens is borrowed once the editor settles
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(args)
			if M.preview.window() == vim.api.nvim_get_current_win() then
				require('frogman.settle').later("preview borrow", function()
					M.preview.borrow(args.buf)
				end)
			end
		end,
	})
	-- a write of a borrowed buffer is an edit, kept open when the preview ends
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function(args)
			if M.preview.active() then
				M.preview.written(args.buf)
			end
		end,
	})
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "frogman-snapshots",
		callback = function(args)
			M.list.map_keys(args.buf)
		end,
	})
end

return M
