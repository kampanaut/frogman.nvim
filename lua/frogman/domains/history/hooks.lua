local historySM = require("frogman.domains.history.sm")

local states = require('frogman.domains.history.states')
local data = require('frogman.domains.history.data')

local navigationSM = require('frogman.domains.navigation.sm')
local navigationSMStates = require('frogman.domains.navigation.states')


local routines = require("frogman.domains.history.routines")

historySM:on("*", states.ATTACHED, "attach_history_update", function(context, _, _)
	-- Pure history domain logic - always attach core history tracking
	-- print("nandito ako")
	if not context.buf then
		error("context.buf is nil in attach_history hook")
	end

	if context.mode == states.mode.DELETE then
		routines.update_buffer_history_ordered()
	elseif context.mode == states.mode.UPDATE then
		local history_modified = routines.update_buffer_history(context.buf) -- the buffer where you currently at.
		if history_modified then
			routines.update_buffer_history_ordered()
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


-- No Name buffers deleted in this batch of events, each with its close as read at its delete. One
-- that's written under a name in the same batch (:w name) was renamed, not closed: the write claims it,
-- and it's never closed. Anything else, like :e reusing an empty one, wasn't, and its close runs once the
-- batch is over.
---@type table<Bufnr, FrogmanClose>
local noname_deleted = {}

historySM:on("*", "*", "handle_deletion", function(context, _, from, to)
	-- Handle deletion immediately, regardless of state
	-- print("FUCK")
	if not context.buf then
		error("context.buf is nil in attach_history hook")
	end
	-- print("I'm fucking here. Delete ", context.buf)
	-- print("SHEEESH")
	-- a delete's close was read at its event, while the buffer was there; a copy's old name is read here
	local close = context.close or routines.closing(context.buf)
	if close then -- if it's registered, then we untrack it. Ignore the untegistered, because they are unrecongised by BufEnter.
		-- print("Deleting buffer: " .. context.buf .. " with handle: " .. id .. "\n" .. debug.traceback())
		routines.close(close)
	end
end, 0, true, states.mode.DELETE)

-- What reacts on a file's handle, each in a class of its own, whoever needs the "before" first; the
-- trail's hook, the ledger's, runs last and reads what these found in the context.
local handles = require('frogman.domains.history.handles')
local handle_states = handles.states

-- a file open again is closed nowhere: it leaves every list, which remembers it for its next close, and
-- the lists' names go to the trail
handles.model:on(handle_states.CLOSED, handle_states.OPEN, "off_the_lists", function(context, handle)
	context.left, context.others = routines.open_out_of_pools(handle.id)
	-- a file never written comes back as a new one, which the trail says
	local filepath = routines.get_filepath_from_hash(context.hash)
	context.new = handle.unwritten ~= nil and filepath ~= nil and not filepath:match("^NONAME_")
		and vim.fn.filereadable(filepath) == 0 or nil
end, 2, true)

-- a No Name text reopened is its buffer's now
handles.model:on(handle_states.CLOSED, handle_states.OPEN, "text_into_buffer", function(_, handle)
	handle.text = nil
end, 3, true)

-- a move onto a name a live handle had: that handle comes off every list, nothing remembered, the buffer
-- holding the name open now
handles.model:on("*", "*", "replaced_off_the_lists", function(context)
	if context.other then
		routines.discard_from_pools(context.other)
	end
end, 2, true, handle_states.mode.RENAME)

-- and of the two names' visits the newer stays, overall, in each window and in each pool
handles.model:on("*", "*", "visits_merge", function(context, handle)
	if context.other then
		routines.merge_history(context.other, handle.id)
	end
end, 4, true, handle_states.mode.RENAME)

-- a load from idle starts from nothing, as at startup. a cycle left open ends with it, and nothing is picked.
local storageSM = require('frogman.domains.storage.sm')
local storageStates = require('frogman.domains.storage.states')
storageSM:on(storageStates.IDLE, storageStates.BARE, "history_teardown", function()
	routines.teardown()
	historySM:force_state(states.ATTACHED)
end, 3, true)

navigationSM:on("*", "*", "winenter_update_history_view", function(context)
	routines.construct_crux(require("frogman.domains.navigation").routines.find_most_recent_tracked_window())
end, 3, true, navigationSMStates.mode.WINENTER)

-- renames on their way: the file's handle, which keeps the old name's hash from BufFilePre until the
-- rename settles.
---@type table<Bufnr, { id: HandleId, history: table|nil }>
local renames = {}

---Settle a rename once the command that made it is over.
---
---The disk decides whether it was a copy or a move (see `routines.settle_rename()`), and the
---trail records which. A copy closes the old name. The buffer is then taken in under its new
---name, as an arrival in the window that shows it, or just registered when no window does. A
---new name that isn't on disk yet is marked as unwritten. No name at all (`:0file`) is a new name
---too, a No Name buffer's. A buffer that's gone was deleted rather than renamed, and one given its
---own name again wasn't renamed: both are left alone.
---
---@param bufnr Bufnr The renamed buffer
---@param rename { id: HandleId, history: table } Its file's handle, and its history if kept
---@return nil
local function settle_rename(bufnr, rename)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return -- deleted for good (a No Name buffer closed), not renamed.
	end
	-- the hash its file had, kept before the move gives its handle the new one
	local old_hash = routines.get_hash_from_handle(rename.id)
	local new_name = vim.api.nvim_buf_get_name(bufnr)
	if routines.get_filehash(new_name ~= "" and new_name or routines.noname_name(bufnr)) == old_hash then
		return -- its own name again: nothing was renamed
	end
	if new_name ~= "" and vim.fn.filereadable(new_name) == 0 then
		vim.b[bufnr].frogman_unwritten = true -- a name that isn't on disk yet: its handle takes the mark as it's registered
	end
	-- a move: the handle's rename, which the trail gets
	local moved_from = routines.settle_rename(bufnr, rename.id)
	if not moved_from and old_hash and routines.get_hash_from_buffer(bufnr) == old_hash then
		-- a copy: the old name is still a file, and it's closed as a delete closes it. A copy frogman tracks
		-- is linked to the file it came from first, its handle made for its name, so the trail has the copy
		-- ahead of the old name's close; a new name frogman doesn't track is no copy, and its close says so
		if routines.is_trackable(bufnr) then
			local ledger = require('frogman.domains.ledger')
			local old_name = ledger.name_of(old_hash)
			local new_path = new_name ~= "" and new_name or routines.noname_name(bufnr) -- no name: a No Name buffer's
			routines.register_filepath(new_path)
			require('frogman.domains.history.handles').copied(routines.get_filehash(new_path), old_hash, {
				words = "renamed to " .. (new_name ~= "" and vim.fs.basename(new_name) or "[No Name]") .. ": a copy, "
					.. (old_name or "the old name") .. " is still on disk",
			})
		end
		historySM:to(historySM:state(), { buf = bufnr }, states.mode.DELETE)
	end
	if routines.is_trackable(bufnr) and not routines.get_hash_from_buffer(bufnr) then
		routines.register_buffer(bufnr) -- known by its new name, whatever the history state (a cycle).
	end
	-- the window that shows it, the current tab's first, then any tab's
	local winid = vim.fn.bufwinid(bufnr)
	winid = winid ~= -1 and winid or (vim.fn.win_findbuf(bufnr)[1] or -1)
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

---Create the history domain's autocmds in frogman's augroup.
---
---Called by setup(), so nothing runs at require. Calling it again after the group is cleared
---replaces them cleanly.
---
---@param group integer The frogman augroup
---@return nil
function M.init_autocmds(group)
	-- where you are can change without frogman seeing it: the label is read again at these
	-- settle points, and the files gone from disk are marked with it, checked as a tick checks them,
	-- once the editor settles, as every change to what frogman knows.
	vim.api.nvim_create_autocmd({ "FocusGained", "ShellCmdPost", "TermLeave", "DirChanged" }, {
		group = group,
		callback = function()
			require('frogman.settle').later("disk check", function()
				if not routines.refresh_label() then
					routines.mark_missing(data.last_label, true)
				end
			end)
		end,
	})

	-- a file that doesn't exist yet isn't missing: it hasn't been written.
	vim.api.nvim_create_autocmd("BufNewFile", {
		group = group,
		callback = function(args)
			if vim.api.nvim_buf_get_name(args.buf) ~= "" then
				local id = routines.get_handle_from_buffer(args.buf)
				if id then
					-- taken in already, as a deleted file's buffer Neovim reloads as a new one: its handle takes the mark now
					require('frogman.domains.history.handles').get(id).unwritten = args.buf
				else
					vim.b[args.buf].frogman_unwritten = true -- kept on its buffer until its handle takes it in
				end
			end
		end,
	})

	-- What happens when a buffer is deleted?
	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		callback = function(args)
			-- print("HOOOY")
			-- print_table(args)
			-- print("BufUnload"..args.buf .. " - "..vim.api.nvim_buf_get_name(args.buf))
			-- print("I was ran!" .. args.buf)
			-- the settle rule: the close runs once the editor settles, as everything does. What needs the
			-- buffer is read now, while it's there: its file, the lists it goes on, and a No Name text.
			local settle = require('frogman.settle')
			local close = routines.closing(args.buf)
			local label = require('frogman.domains.ledger.routines').buffer_label(args.buf)
			local function delete()
				historySM:to(historySM:state(), { buf = args.buf, close = close }, states.mode.DELETE)
			end
			if close and close.text then
				-- a No Name buffer written under a name is deleted and made again under it: a rename, if the
				-- write follows in this batch (BufWritePost claims it); otherwise it's closed once it settles.
				noname_deleted[args.buf] = close
				local function drop_note()
					if vim.fn.state("x") ~= "" then
						-- still inside an autocommand, a write's own BufWritePre waiting among them: the
						-- batch isn't over, so the write may yet claim the note. Asked again a moment later,
						-- by a timer: queued again at once, it would run at once, inside the same wait.
						vim.defer_fn(function() settle.later("No Name note", drop_note) end, 10)
						return
					end
					if noname_deleted[args.buf] == close then
						noname_deleted[args.buf] = nil
						delete() -- no write claimed it: a close after all
					end
				end
				settle.later("No Name note", drop_note)
			else
				settle.later("close " .. label, delete)
			end
			-- a window that showed it lands once the delete is over; Neovim's own pick meanwhile isn't a visit
			require('frogman.domains.window.routines').note_landings(args.buf, close and close.id)
		end,
	})

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function(args)
			local rename = noname_deleted[args.buf]
			noname_deleted[args.buf] = nil
			if rename and data.closing[args.buf] == rename then
				data.closing[args.buf] = nil -- claimed: a rename, so it's never closed
			end
			-- once the write is over: a No Name buffer written under a name settles as a rename.
			require('frogman.settle').later("write " .. require('frogman.domains.ledger.routines').buffer_label(args.buf), function()
				if rename then
					settle_rename(args.buf, rename)
					return
				end
				-- Skip if already registered
				if not vim.api.nvim_buf_is_valid(args.buf) or routines.get_hash_from_buffer(args.buf) then
					return
				end

				-- Only process normal file buffers with valid filenames: an arrival in the window that shows
				-- it, or just registered when none does, so a write of buffers never entered moves no slots
				local winid = vim.fn.bufwinid(args.buf)
				winid = winid ~= -1 and winid or (vim.fn.win_findbuf(args.buf)[1] or -1) -- or one in another tab
				if winid ~= -1 then
					vim.api.nvim_win_call(winid, function()
						historySM:to(historySM:state(), { buf = args.buf }, states.mode.UPDATE)
					end)
				elseif routines.is_trackable(args.buf) then
					routines.register_buffer(args.buf)
				end
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
			if require("frogman.domains.window.routines").is_landing_pick(winid, args.buf) then
				return
			end
			-- the settle rule: the arrival is slotted once the event is over, against the window it
			-- happened in (not the focused one), and only if that window still shows the buffer then.
			local cycling_step = historySM:state() == states.DETACHED
			local loads = data.loads
			require('frogman.settle').later("arrival " .. require('frogman.domains.ledger.routines').buffer_label(args.buf), function()
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
			local id = routines.get_handle_from_buffer(args.buf)
			renames[args.buf] = id and { id = id } or nil
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
			require('frogman.settle').later("rename " .. require('frogman.domains.ledger.routines').buffer_label(args.buf), function()
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
			-- kept until the close is over, so the TabClosedPre of a tab it takes with it may save its history
			require('frogman.held').after_close(winid, function() data.crux_internals.window[winid] = nil end)
		end
	})
end

return M
