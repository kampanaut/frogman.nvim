local historySM = require("cavediver.domains.history.sm")

local states = require('cavediver.domains.history.states')
local data = require('cavediver.domains.history.data')

local navigationSM = require('cavediver.domains.navigation.sm')
local navigationSMStates = require('cavediver.domains.navigation.states')


local routines = require("cavediver.domains.history.routines")

historySM:on("*", states.ATTACHED, "attach_history_update", function(context, _, _)
	-- Pure history domain logic - always attach core history tracking
	-- print("nandito ako")
	if not context.buf then
		error("context.buf is nil in attach_history hook")
	end

	if context.mode == states.mode.DELETE then
		routines.update_buffer_history_ordered()
		routines.update_buffer_history_ordered_nonharpooned()
	elseif context.mode == states.mode.UPDATE then
		local history_modified = routines.update_buffer_history(context.buf) -- the buffer where you currently at.
		if history_modified then
			routines.update_buffer_history_ordered()
			routines.update_buffer_history_ordered_nonharpooned()
		end
		context.history_modified = history_modified
	end
	-- print_table(data.hash_buffer_registry)
end, 1, true)
-- this runs regardless of mode, so we can track history in all modes.
-- It needs to update for deletes

historySM:on(states.ATTACHED, states.DETACHED, "detach_history", function(context, _, _)
	if context.window and context.window.current_crux then
		routines.snapshot_origin(context.window.current_crux)
	end
end, 2, true)


historySM:on("*", "*", "handle_deletion", function(context, from, to)
	-- Handle deletion immediately, regardless of state
	-- print("FUCK")
	if not context.buf then
		error("context.buf is nil in attach_history hook")
	end
	-- print("I'm fucking here. Delete ", context.buf)
	-- print("SHEEESH")
	local filehash = routines.get_hash_from_buffer(context.buf)
	if filehash then -- if it's registered, then we untrack it. Ignore the untegistered, because they are unrecongised by BufEnter.
		-- print("Deleting buffer: " .. context.buf .. " with filehash: " .. filehash .. "\n" .. debug.traceback())
		routines.track_closing_filehash(filehash)
		routines.untrack_buffer(context.buf)
		routines.unregister_buffer(context.buf)
	end
end, 0, true, states.mode.DELETE)

-- a load from idle starts from nothing, as at startup. a cycle left open ends with it, and nothing is picked.
local storageSM = require('cavediver.domains.storage.sm')
local storageStates = require('cavediver.domains.storage.states')
storageSM:on(storageStates.IDLE, storageStates.BARE, "history_teardown", function()
	routines.teardown()
	historySM.current_state = states.ATTACHED
end, 3, true)

navigationSM:on("*", "*", "winenter_update_history_view", function(context)
	routines.construct_crux(require("cavediver.domains.navigation").routines.find_most_recent_tracked_window())
end, 3, true, navigationSMStates.mode.WINENTER)

-- renames on their way: the old hash, kept from BufFilePre until the rename settles.
---@type table<Bufnr, { hash: Filehash, history: table|nil }>
local renames = {}

-- No Name buffers deleted in this batch of events. One that's written under a name in the same batch
-- (:w name) was renamed, not closed; anything else, like :e reusing an empty one, wasn't.
---@type table<Bufnr, { hash: Filehash, history: table }>
local noname_deleted = {}

---Settle a rename once the command that made it is over: the disk decides whether it was a copy or a
---move (routines.settle_rename), then the buffer is taken in under its new name, as an arrival in the
---window that shows it, or just registered when no window does.
---
---@param bufnr Bufnr
---@param rename { hash: Filehash, history: table }
local function settle_rename(bufnr, rename)
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.api.nvim_buf_get_name(bufnr) == "" then
		return -- deleted for good (a No Name buffer closed), not renamed.
	end
	local moved_from = routines.settle_rename(bufnr, rename.hash, rename.history)
	if not moved_from and routines.get_hash_from_buffer(bufnr) == rename.hash then
		-- a copy: the old name is still a file, and it's closed as a delete closes it.
		historySM:to(historySM:state(), { buf = bufnr }, states.mode.DELETE)
	end
	if routines.is_trackable(bufnr) and not routines.get_hash_from_buffer(bufnr) then
		routines.register_buffer(bufnr) -- known by its new name, whatever the history state (a cycle).
	end
	local winid = vim.fn.bufwinid(bufnr)
	if winid ~= -1 then
		vim.api.nvim_win_call(winid, function()
			historySM:to(historySM:state(), { buf = bufnr }, states.mode.UPDATE)
		end)
	end
	if moved_from then
		routines.unregister_filepath(moved_from)
	end
end

local M = {}

---Create the history domain's autocmds in cavediver's augroup. setup() calls this, so nothing
---runs at require, and calling it again after the group is cleared replaces them cleanly.
---
---@param group integer The cavediver augroup
function M.init_autocmds(group)
	-- What happens when a buffer is deleted?
	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		callback = function(args)
			-- print("HOOOY")
			-- print_table(args)
			-- print("BufUnload"..args.buf .. " - "..vim.api.nvim_buf_get_name(args.buf))
			if vim.b[args.buf].skip_bufdelete ~= true then
				-- print("I was ran!" .. args.buf)
				-- a No Name buffer written under a name is deleted and made again under it: a rename, if the
				-- write follows in this batch (BufWritePost claims it); otherwise it's dropped once it settles.
				local hash = routines.get_hash_from_buffer(args.buf)
				local path = hash and routines.get_filepath_from_hash(hash)
				if path and path:match("^NONAME_") then
					noname_deleted[args.buf] = { hash = hash, history = routines.history_of(hash) }
					vim.schedule(function()
						noname_deleted[args.buf] = nil
					end)
				end
				historySM:to(historySM:state(), { buf = args.buf }, states.mode.DELETE)
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function(args)
			local rename = noname_deleted[args.buf]
			noname_deleted[args.buf] = nil
			-- once the write is over: a No Name buffer written under a name settles as a rename.
			vim.schedule(function()
				if rename then
					settle_rename(args.buf, rename)
					return
				end
				-- Skip if already registered
				if not vim.api.nvim_buf_is_valid(args.buf) or routines.get_hash_from_buffer(args.buf) then
					return
				end

				-- Only process normal file buffers with valid filenames
				historySM:to(historySM:state(), { buf = args.buf }, states.mode.UPDATE)
			end)
		end
	})

	-- What happens when we enter a buffer?
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(args)
			-- print("BufEnter "..args.buf .. " - "..vim.api.nvim_buf_get_name(args.buf) .. " - buftype: [" .. vim.bo[args.buf].buftype .. "]")
			-- neovim's pick for a window whose buffer got deleted isn't a visit, the window lands
			-- by itself once the delete is over.
			local winid = vim.api.nvim_get_current_win()
			if require("cavediver.domains.window.routines").is_landing_pick(winid, args.buf) then
				return
			end
			-- the settle rule: the arrival is slotted once the event is over, against the window it
			-- happened in (not the focused one), and only if that window still shows the buffer then.
			local cycling_step = historySM:state() == states.DETACHED
			local loads = data.loads
			vim.schedule(function()
				if
					not vim.api.nvim_win_is_valid(winid) or
					not vim.api.nvim_buf_is_valid(args.buf) or
					vim.api.nvim_win_get_buf(winid) ~= args.buf
				then
					return -- the window moved on, so its own BufEnter has the arrival.
				end
				if cycling_step and historySM:state() ~= states.DETACHED then
					return -- a cycle's step, and the cycle ended since: the pick or the cancel settled the window.
				end
				if data.loads ~= loads then
					return -- a session loaded since: this was the restore's own arrival, which the load replaced.
				end
				vim.api.nvim_win_call(winid, function()
					historySM:to(historySM:state(), { buf = args.buf }, states.mode.UPDATE)
				end)
			end)
		end,
	})

	-- BufFilePre: Clean up old identity
	vim.api.nvim_create_autocmd("BufFilePre", {
		group = group,
		callback = function(args)
			-- print("rename pre")
			-- print(vim.bo[args.buf].buftype)
			-- print(args.file)
			-- only a buffer we track gets its new identity at BufFilePost. the buffer :saveas makes for
			-- the old name isn't one, it's like a :badd buffer until it's entered.
			-- the old name stays registered until the rename settles (BufFilePost), so nothing prunes what
			-- a move carries over; a copy closes it then.
			local old_hash = routines.get_hash_from_buffer(args.buf)
			renames[args.buf] = old_hash and { hash = old_hash } or nil
		end
	})

	-- BufFilePost: Re-register new identity
	vim.api.nvim_create_autocmd("BufFilePost", {
		group = group,
		callback = function(args)
			-- print("rename post")
			-- print(vim.bo[args.buf].buftype)
			-- print(args.file)
			local rename = renames[args.buf]
			renames[args.buf] = nil
			if not rename then
				return
			end
			-- the disk decides once the rename is over (the settle rule).
			vim.schedule(function()
				settle_rename(args.buf, rename)
			end)
		end
	})

	-- BufFilePost: Re-register new identity
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			local winid = tonumber(args.file)
			if not winid then
				return
			end
			data.crux_internals.window[winid] = nil
		end
	})
end

return M
