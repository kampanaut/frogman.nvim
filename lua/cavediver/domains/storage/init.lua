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

---Save current session to file. The session's directory is read here: the global one for the
---whole editor, or the tab's for a tab session.
---
---@param name string|nil The session's name, as the session manager passes it; nil for a nameless save
---@param opts {tab: integer|nil}|nil `tab` is the tabpage of a tab session
---@return nil
function M.save_session(name, opts)
	local directory = vim.fn.getcwd(-1, -1)
	if opts and opts.tab then
		directory = vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(opts.tab))
	end
	local tab = opts and opts.tab
	storageSM:to(states.SAVING, { name = name, directory = directory, tab = tab })
	storageSM:to(states.IDLE, { name = name, directory = directory, tab = tab })
end

---Load a session, whether or not one is loaded already. From idle, every domain tears its own
---state down first (idle -> bare), so the load starts as it does at startup; a tab session's file
---loads into the tab you're in instead, with nothing torn down.
---
---@param name string|nil
---@return nil
local function load(name)
	local directory = vim.fn.getcwd(-1, -1)
	-- a tab with a directory of its own: a tab session saved from it has its file there
	if vim.fn.haslocaldir(-1, 0) == 1 and routines.session_exists(vim.fn.getcwd(-1, 0), name) then
		directory = vim.fn.getcwd(-1, 0)
	end
	local session = { name = name, directory = directory }
	data.loading_batch = true
	data.last_loaded = { name = name }
	-- once the restore's batch is over: the next call is a full load again, and the window the
	-- restore left focused is taken in.
	vim.schedule(function()
		data.loading_batch = false
		routines.after_restore()
	end)
	-- the file is read first, since its scope decides whether anything is torn down
	local tab_session = routines.prepare_load(directory, name)
	if storageSM:state() == states.IDLE and not tab_session then
		storageSM:to(states.BARE, session)
	end
	storageSM:to(states.LOADING, session)
	storageSM:to(states.IDLE, session)
end

---Load session from file. A repeat inside one restore (a native session calls this once per
---loaded buffer) is skipped.
---
---@param name string|nil The session's name, as the session manager passes it; nil for a nameless save
---@return nil
function M.load_session(name)
	if data.loading_batch then
		return
	end
	load(name)
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
			local name = data.last_loaded.name
			vim.schedule(function()
				load(name)
			end)
		end,
	})

	-- A tab session's tab closed: its pool goes with it when its session was saved since it last
	-- changed (the contract saves it on TabClosedPre); otherwise the pool stays, with no tab, and you're
	-- told.
	vim.api.nvim_create_autocmd("TabClosed", {
		group = group,
		callback = function()
			local history = require('cavediver.domains.history')
			for tabpage, id in pairs(history.data.tab_pools) do
				local pool = history.data.pools[id]
				if not vim.api.nvim_tabpage_is_valid(tabpage) then
					history.data.tab_pools[tabpage] = nil
					if pool then
						pool.tabs[tabpage] = nil
					end
					if pool and next(pool.tabs) == nil then
						if pool.saved_at and pool.saved_at >= (pool.changed_at or 0) then
							history.data.pools[id] = nil -- its file has everything
						else
							vim.notify("cavediver: the tab session " .. (pool.name or vim.fn.fnamemodify(pool.directory or "", ":t")) .. "'s tab closed without being saved; its closed files stay, with no tab, in :CavediverClosed until you merge or discard them.", vim.log.levels.WARN)
						end
					end
				end
			end
		end,
	})
end

return M
