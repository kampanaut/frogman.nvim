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

navigationSM:on("*", "*", "winenter_update_history_view", function(context)
	routines.construct_crux(require("cavediver.domains.navigation").routines.find_most_recent_tracked_window())
end, 3, true, navigationSMStates.mode.WINENTER)

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
				historySM:to(historySM:state(), { buf = args.buf }, states.mode.DELETE)
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function(args)
			local bufname = vim.api.nvim_buf_get_name(args.buf)

			-- Skip if already registered
			if routines.get_hash_from_buffer(args.buf) then
				return
			end

			-- Only process normal file buffers with valid filenames
			historySM:to(historySM:state(), { buf = args.buf }, states.mode.UPDATE)
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
			vim.b[args.buf].cavediver_renaming = routines.get_hash_from_buffer(args.buf) ~= nil
			historySM:to(historySM:state(), { buf = args.buf }, states.mode.DELETE)
		end
	})

	-- BufFilePost: Re-register new identity
	vim.api.nvim_create_autocmd("BufFilePost", {
		group = group,
		callback = function(args)
			-- print("rename post")
			-- print(vim.bo[args.buf].buftype)
			-- print(args.file)
			if not vim.b[args.buf].cavediver_renaming then
				return
			end
			vim.b[args.buf].cavediver_renaming = nil
			historySM:to(historySM:state(), { buf = args.buf }, states.mode.UPDATE)
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
