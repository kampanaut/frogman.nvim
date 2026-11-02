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
---Called by setup(), so nothing runs at require. A closed window's marks, and a closed tab's, are held
---over in its session's scope once the editor settles. The marks pop-up's keys are mapped on its buffer.
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
			local scope = winid and data.scopes.window[winid]
			-- a tab session's tab closing ends the session there, as a switch does: its windows' marks live
			-- on their entries, and come back with them
			if scope and data.ending[vim.api.nvim_win_get_tabpage(winid)] then
				routines.drop_scope("window", winid)
			elseif scope then
				-- held over in its session's scope once the editor settles, unless a load comes first
				local tabpage = vim.api.nvim_win_get_tabpage(winid)
				routines.queue_hold_over(tabpage, require('frogman.domains.history').data.tab_pools[tabpage] or "", scope.groups,
					"window on " .. routines.shows(winid))
				routines.drop_scope("window", winid)
			end
			data.flashes[winid or -1] = nil
		end,
	})
	-- what each tab showed and its session, read before it closes
	vim.api.nvim_create_autocmd("TabClosedPre", {
		group = group,
		callback = function()
			-- the tab closing is the current one; a tab session's, but a detached list's, ends there
			local closing = vim.api.nvim_get_current_tabpage()
			local pool = require('frogman.domains.history').data.pools[require('frogman.domains.history').data.tab_pools[closing] or ""]
			if pool and pool.id ~= "" and not pool.detached then
				data.ending[closing] = true
			end
			for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
				if data.scopes.tab[tabpage] then
					data.tab_shows[tabpage] = { session = require('frogman.domains.history').data.tab_pools[tabpage] or "",
						what = "tab on " .. routines.shows(vim.api.nvim_tabpage_get_win(tabpage)) }
				end
			end
		end,
	})
	vim.api.nvim_create_autocmd("TabClosed", {
		group = group,
		callback = function()
			local alive = {}
			for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
				alive[tabpage] = true
			end
			for tabpage, _ in pairs(data.ending) do
				if not alive[tabpage] then
					data.ending[tabpage] = nil
				end
			end
			for tabpage, scope in pairs(data.scopes.tab) do
				if not alive[tabpage] then
					local shown = data.tab_shows[tabpage] or { session = "", what = "tab" }
					routines.queue_hold_over(tabpage, shown.session, scope.groups, shown.what)
					routines.drop_scope("tab", tabpage)
					data.tab_shows[tabpage] = nil
				end
			end
		end,
	})
end

return M
