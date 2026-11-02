---Marks domain initialization and API layer.
---
---The marks domain manages frogman's own marks: a window's, a tab's and a session's, each in groups,
---each mark an alias for a file's handle. This module provides the API layer and the autocmds that let
---a window's or a tab's marks go with it.

local data = require('frogman.domains.marks.data')
local routines = require('frogman.domains.marks.routines')

local M = {
	data = data,         -- Domain data structures
	routines = routines, -- Domain business logic
}

M.add = routines.add
M.jump = routines.jump
M.set_mode = routines.set_mode
M.label_of = routines.label_of
M.marked_paths = routines.marked_paths
M.flash_of = routines.flash_of
M.popup = require('frogman.domains.marks.popup')
M.open_popup = M.popup.open

-- a load from idle starts from nothing, as at startup: every scope empty
local storageSM = require('frogman.domains.storage.sm')
local storageStates = require('frogman.domains.storage.states')
storageSM:on(storageStates.IDLE, storageStates.BARE, "marks_teardown", function()
	routines.teardown()
end, 2.5, true)

---Create the marks domain's autocmds in frogman's augroup.
---
---Called by setup(), so nothing runs at require. A window's marks go with the window, and a tab's
---with the tab. The marks pop-up's keys are mapped on its buffer.
---
---@param group integer The frogman augroup
---@return nil
function M.init_autocmds(group)
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "frogman-marks",
		callback = function(args)
			M.popup.map_keys(args.buf)
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			local winid = tonumber(args.file)
			if winid and data.scopes.window[winid] then
				routines.drop_scope("window", winid)
			end
			data.flashes[winid or -1] = nil
		end,
	})
	vim.api.nvim_create_autocmd("TabClosed", {
		group = group,
		callback = function()
			local alive = {}
			for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
				alive[tabpage] = true
			end
			for tabpage, _ in pairs(data.scopes.tab) do
				if not alive[tabpage] then
					routines.drop_scope("tab", tabpage)
				end
			end
		end,
	})
end

return M
