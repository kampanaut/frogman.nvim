---Storage domain initialization and API.
---
---The storage domain manages session persistence across all domains,
---providing save/load functionality and automatic state preservation.

local states = require('cavediver.domains.storage.states')
local data = require('cavediver.domains.storage.data')
local routines = require('cavediver.domains.storage.routines')
local storageSM = require('cavediver.domains.storage.sm')

require('cavediver.domains.storage.hooks')

local M = {
	states = states,
	data = data,
	routines = routines,
	sm = storageSM,
}

---Save current session to file.
---
---@param cwd string|nil
---@return nil
function M.save_session(cwd)
	if cwd then
		storageSM:to(states.SAVING, { cwd = cwd })
		storageSM:to(states.IDLE, { cwd = cwd })
	else
		error("CWD is required to save session")
	end
end

---Load a session, whether or not one is loaded already. From idle, every domain tears its own
---state down first (idle -> bare), so the load starts as it does at startup.
---
---@param cwd string
---@return nil
local function load(cwd)
	data.loading_batch = true
	data.last_loaded = cwd
	-- once the restore's batch is over: the next call is a full load again, and the window the
	-- restore left focused is taken in.
	vim.schedule(function()
		data.loading_batch = false
		routines.after_restore()
	end)
	if storageSM:state() == states.IDLE then
		storageSM:to(states.BARE, { cwd = cwd })
	end
	storageSM:to(states.LOADING, { cwd = cwd })
	storageSM:to(states.IDLE, { cwd = cwd })
end

---Load session from file. A repeat inside one restore (a native session calls this once per
---loaded buffer) is skipped.
---
---@param cwd string|nil
---@return nil
function M.load_session(cwd)
	if cwd then
		if data.loading_batch then
			return
		end
		load(cwd)
	else
		error("CWD is required to save session")
	end
end

---Create the storage domain's autocmds in cavediver's augroup. setup() calls this, so nothing
---runs at require.
---
---@param group integer The cavediver augroup
function M.init_autocmds(group)
	-- Neovim's :restart restores its own session after the startup's, and rebuilds the windows, so
	-- whatever was loaded in this startup is loaded again once that settles, repeat or not.
	vim.api.nvim_create_autocmd("SourcePost", {
		group = group,
		callback = function(args)
			if
				vim.v.startreason ~= "restart" or
				data.last_loaded == nil or
				not vim.fn.fnamemodify(args.file or "", ":t"):match("^restart_session_")
			then
				return
			end
			local cwd = data.last_loaded
			vim.schedule(function()
				load(cwd)
			end)
		end,
	})
end

return M
