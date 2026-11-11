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

-- a load done: an open pop-up shows the scope its mode reads now, another session's when it was another's,
-- once the load's own settle work has run
storageSM:on(storageStates.LOADING, storageStates.IDLE, "marks_popup_rescope", function()
	require('frogman.settle').later("marks pop-up after a load", function()
		M.popup.rescope()
	end)
end, 4, true)

---Create the marks domain's autocmds in frogman's augroup.
---
---Called by setup(), so nothing runs at require. A closed window's marks, and a closed tab's, are held
---over in its session's scope once the editor settles. The marks pop-up's keys are mapped on its buffer,
---and its own autocmds are made first (`popup.init_autocmds`).
---
---@param group integer The frogman augroup
---@return nil
function M.init_autocmds(group)
	M.popup.init_autocmds(group)
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
			local held = require('frogman.held')
			if winid then
				-- onto its saved entry in its session's file, as it stands, when it has one there; else held over
				-- in its session's scope once the editor settles, or as a load begins, a tab session's last tab
				-- closing holding it over as its records are written
				routines.window_going(winid, held.closing_in(winid))
			end
			if scope then
				-- kept until the close is over, so a save at its tab's TabClosedPre still reads them
				held.after_close(winid, function() routines.drop_scope("window", winid) end)
			end
			data.flashes[winid or -1] = nil
			data.copies[winid or -1] = nil
		end,
	})
	-- the session each window is seen in and what it shows, for one that closes without its WinClosed
	vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
		group = group,
		callback = function()
			require('frogman.held').note_session(vim.api.nvim_get_current_win())
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
			for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
				if data.scopes.tab[tabpage] then
					local session, what = require('frogman.held').tab_closing_in(tabpage)
					data.tab_shows[tabpage] = { session = session, what = what }
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
			for tabpage, scope in pairs(data.scopes.tab) do
				if not alive[tabpage] then
					local shown = data.tab_shows[tabpage] or { session = "", what = "tab" }
					routines.tab_going(tabpage, shown.session, shown.what) -- onto its saved tab entry, or held over
					routines.drop_scope("tab", tabpage)
					data.tab_shows[tabpage] = nil
				end
			end
		end,
	})
end

return M
