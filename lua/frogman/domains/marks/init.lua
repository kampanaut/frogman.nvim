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
M.labels = routines.labels
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
			if scope and routines.unchanged_copy(winid) then
				-- a copy no one changed, its window still holding the same: nothing would be lost
				routines.drop_scope("window", winid)
			elseif scope then
				-- held over in its session's scope once the editor settles, unless a load comes first, or its
				-- tab's own TabClosed, a tab session's tab really closing, drops it (a refused close fires none)
				local tabpage = vim.api.nvim_win_get_tabpage(winid)
				routines.queue_hold_over(tabpage, require('frogman.domains.history').data.tab_pools[tabpage] or "", scope.groups,
					"window on " .. routines.shows(winid))
				routines.drop_scope("window", winid)
			end
			data.flashes[winid or -1] = nil
			data.copies[winid or -1] = nil
		end,
	})
	-- a split starts with a copy of its window's marks, when the config says so
	vim.api.nvim_create_autocmd("WinNew", {
		group = group,
		callback = function()
			if not require('frogman.configs').marks.split_copies then
				return
			end
			-- a split is the newest window and the current one, and the window it was split from the one before
			local new = vim.api.nvim_get_current_win()
			if new ~= math.max(unpack(vim.api.nvim_list_wins())) or vim.api.nvim_win_get_config(new).relative ~= "" then
				return
			end
			local from = vim.fn.win_getid(vim.fn.winnr('#'))
			if from ~= new and data.scopes.window[from] and data.scopes.window[new] == nil then
				routines.copy_scope("window", from, new)
				data.copies[new] = { from = from, given = routines.serialise("window", new) }
			end
		end,
	})
	-- what each tab showed and its session, read before it closes
	vim.api.nvim_create_autocmd("TabClosedPre", {
		group = group,
		callback = function()
			-- the tab closing is the current one; a tab session's, but a detached list's, ends there
			local closing = vim.api.nvim_get_current_tabpage()
			local pool = require('frogman.domains.history').data.pools[require('frogman.domains.history').data.tab_pools[closing] or ""]
			-- read anew at each close's start: a tab that outlived a refused close may be a detached list's now
			-- the last wait queued before the close began: what its windows queue after is dropped at TabClosed
			data.ending[closing] = (pool and pool.id ~= "" and not pool.detached) and require('frogman.held').last_wait() or nil
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
			for tabpage, began in pairs(data.ending) do
				if not alive[tabpage] then
					data.ending[tabpage] = nil
					-- a tab session's tab closing ends the session there, as a switch does: its windows' marks
					-- and snapshots live on their entries, and come back with them; what was waiting from before
					-- the close began is held over as at any close
					routines.drop_pending(tabpage, began)
					require('frogman.domains.snapshots').routines.drop_pending(tabpage, began)
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
