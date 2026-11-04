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
end, 2, true, navigation.states.mode.WINENTER)

-- a load from idle starts from nothing, as at startup: no snapshot, before the handles go
local storageSM = require('frogman.domains.storage.sm')
local storageStates = require('frogman.domains.storage.states')
storageSM:on(storageStates.IDLE, storageStates.BARE, "snapshots_teardown", function()
	routines.teardown()
end, 2.6, true)

---Create the snapshots domain's autocmds in frogman's augroup.
---
---Called by setup(), so nothing runs at require. A closed window's snapshots are held over in its
---session's scope once the editor settles, and the list's keys are mapped on its buffer.
---
---@param group integer The frogman augroup
---@return nil
function M.init_autocmds(group)
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			local winid = tonumber(args.file)
			if winid and data.by_window[winid] then
				-- held over in its session's scope once the editor settles, unless a load comes first, or its
				-- tab's own TabClosed, a tab session's tab really closing, drops it (a refused close fires none)
				routines.queue_hold_over(winid)
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
