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
	-- the session's last part, never a whole path (native wiring passes v:this_session); a tab
	-- session's save is its own step, kept in its own file
	local step = require('cavediver.domains.ledger').begin("save", vim.fn.fnamemodify(name or directory, ":t"))
	if tab then
		step.pool = require('cavediver.domains.history').routines.pool_id(name, directory)
	end
	storageSM:to(states.SAVING, { name = name, directory = directory, tab = tab })
	storageSM:to(states.IDLE, { name = name, directory = directory, tab = tab })
end

---Load a session, whether or not one is loaded already. From idle, every domain tears its own
---state down first (idle -> bare), so the load starts as it does at startup; a tab session's file
---loads into one tab instead, the hint's or the one you're in, with nothing torn down.
---
---@param name string|nil
---@param opts {tab: integer|nil}|nil `tab` says it's a tab session, for when its file can't say so
---@param restart boolean|nil It's the load run again after Neovim's :restart session
---@return nil
local function load(name, opts, restart)
	local hint = opts ~= nil and opts.tab ~= nil
	local directory = vim.fn.getcwd(-1, -1)
	-- a tab with a directory of its own: a tab session saved from it has its file there
	if hint then
		directory = vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(opts.tab))
	elseif vim.fn.haslocaldir(-1, 0) == 1 and routines.session_exists(vim.fn.getcwd(-1, 0), name) then
		directory = vim.fn.getcwd(-1, 0)
	end
	local session = { name = name, directory = directory }
	data.loading_batch = true
	data.last_loaded = { name = name, tab = hint }
	-- once the restore's batch is over: the next call is a full load again, and the window the
	-- restore left focused is taken in.
	vim.schedule(function()
		data.loading_batch = false
		routines.after_restore()
	end)
	-- the file is read first, since its scope decides whether anything is torn down
	local tab_session = routines.prepare_load(directory, name, hint and opts.tab or nil)
	local ledger = require('cavediver.domains.ledger')
	if not tab_session then
		-- the manager has torn the outgoing session down by now: a write still waiting would hold that,
		-- and so would the moves and the messages of the batch it happened in
		routines.drop_pending_records()
		ledger.drop_batch()
	end
	local step = ledger.begin(restart and "restart" or "load", vim.fn.fnamemodify(name or directory, ":t"))
	if tab_session then
		step.pool = require('cavediver.domains.history').routines.pool_id(name, directory) -- kept in its own file
	end
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
---@param opts {tab: integer|nil}|nil `tab` is the tabpage of a tab session, for when its file can't say so
---@return nil
function M.load_session(name, opts)
	if data.loading_batch then
		return
	end
	load(name, opts)
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
			local name, tab = data.last_loaded.name, data.last_loaded.tab
			vim.schedule(function()
				load(name, tab and { tab = vim.api.nvim_get_current_tabpage() } or nil, true)
			end)
		end,
	})

	-- A tab session's tab closed: its records go into its file, and its pool goes with the tab.
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
						routines.close_tab_pool(pool)
					end
				end
			end
		end,
	})

	-- Records cavediver writes itself: every known session's, as the editor quits (nothing scheduled
	-- runs after this), and an open No Name text's, as it's edited.
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			routines.write_records(true)
		end,
	})
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = group,
		callback = function(args)
			local history = require('cavediver.domains.history')
			if vim.api.nvim_buf_get_name(args.buf) == "" and history.get_hash_from_buffer(args.buf) then
				for id, _ in pairs(history.routines.pools()) do
					routines.records_changed(id)
				end
			end
		end,
	})
	routines.write_records_on(true)
end

return M
