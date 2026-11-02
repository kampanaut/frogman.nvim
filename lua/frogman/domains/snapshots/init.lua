---Snapshots domain initialization and API layer.
---
---The snapshots domain keeps each window's snapshots: its setup as it was, taken on purpose, its files
---held by the snapshot's place. This module provides the API layer and the autocmds that let a
---window's snapshots go with it.

local data = require('frogman.domains.snapshots.data')
local routines = require('frogman.domains.snapshots.routines')

local M = {
	data = data,         -- Domain data structures
	routines = routines, -- Domain business logic
}

M.take = routines.take
M.list = require('frogman.domains.snapshots.list')
M.open_list = M.list.open

-- a load from idle starts from nothing, as at startup: no snapshot, before the handles go
local storageSM = require('frogman.domains.storage.sm')
local storageStates = require('frogman.domains.storage.states')
storageSM:on(storageStates.IDLE, storageStates.BARE, "snapshots_teardown", function()
	routines.teardown()
end, 2.6, true)

---Create the snapshots domain's autocmds in frogman's augroup.
---
---Called by setup(), so nothing runs at require. A window's snapshots go with the window, and the
---list's keys are mapped on its buffer.
---
---@param group integer The frogman augroup
---@return nil
function M.init_autocmds(group)
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			local winid = tonumber(args.file)
			if winid and data.by_window[winid] then
				routines.drop_window(winid)
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
