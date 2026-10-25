---UI domain hooks for extending other domains' state machines.
---
---The UI domain extends navigation and history state machines with hooks that manage
---visual component state. These hooks ensure UI components adapt appropriately to
---different coordination modes and buffer state changes.

local uiMachines = require('cavediver.domains.ui.sm')
local history = require('cavediver.domains.history')
local states = require('cavediver.domains.ui.states')
local data = require('cavediver.domains.ui.data')
local routines = require('cavediver.domains.ui.routines')
local navigation = require('cavediver.domains.navigation')

-- a load from idle starts from nothing, as at startup: the display caches go with what they showed.
local storageSM = require('cavediver.domains.storage.sm')
local storageStates = require('cavediver.domains.storage.states')
storageSM:on(storageStates.IDLE, storageStates.BARE, "ui_teardown", function()
	for winid, _ in pairs(data.window_display_cache) do
		data.clear_window_display_cache(winid)
	end
	data.clear_display_name_cache()
	local cache = data.bufferline_state
	cache.harpooned_buffers, cache.harpooned_lookup = {}, {}
	cache.recent_buffers, cache.buffer_ranking = {}, {}
	cache.current_buf, cache.current_window_triquetra = nil, nil
	cache.initialized, cache.history_detached = false, false
end, 4, true)

-- The toggles: the winbar, the indicators and the bufferline, each drawn again once its new state is set
for _, machine in ipairs({ uiMachines.winbar, uiMachines.indicators, uiMachines.bufferline }) do
	machine:on("*", "*", "redraw_toggled", function()
		vim.schedule(function()
			uiMachines.loop:to(states.LOOP.SELF)
			vim.cmd("redrawtabline")
		end)
	end, 1, true)
end

uiMachines.loop:on("*", states.LOOP.SELF, "update_ui_state", function()
	local navigation = require('cavediver.domains.navigation')
	local tracked_winid = navigation.routines.find_most_recent_tracked_window()

	if tracked_winid then
		routines.refresh_ui(tracked_winid) -- Use tracked window as fake current
		routines.show_ui()           -- This still uses real current window for display
	end
end, 1, true)

history.sm:on("*", history.states.ATTACHED, "refresh_ui_attached", function(context, from_state, to_state)
	if context.history_modified == nil then
		error("history_modified is nil in refresh_ui_attached hook")
	elseif context.history_modified == false then
		return -- skip if history didn't update anything.
	end
	uiMachines.loop:to(states.LOOP.SELF)
end, 3, true, history.states.mode.UPDATE)

history.sm:on(history.states.DETACHED, history.states.DETACHED, "refresh_ui_detached", function(context, _, _)
	uiMachines.loop:to(states.LOOP.SELF)
end, 3, true, history.states.mode.UPDATE)

navigation.sm:on("*", "*", "winenter_update_ui", function(context)
	uiMachines.loop:to(states.LOOP.SELF)
end, 4, true, navigation.states.mode.WINENTER)


local M = {}

---Create the ui domain's autocmds in cavediver's augroup.
---
---Called by setup(), so nothing runs at require. Calling it again after the group is cleared
---replaces them cleanly.
---
---@param group integer The cavediver augroup
---@return nil
function M.init_autocmds(group)
	-- Clear display name cache on buffer changes for accurate basename display
	vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufFilePost", "BufWritePost" }, {
		group = group,
		callback = function()
			data.clear_display_name_cache()
		end,
	})

	vim.api.nvim_create_autocmd({ "VimResized" }, {
		group = group,
		callback = function()
			routines.debounced_update()
		end,
	})

	vim.api.nvim_create_autocmd({ "BufModifiedSet" }, {
		group = group,
		callback = function()
			uiMachines.loop:to(states.LOOP.SELF)
		end
	})

	vim.api.nvim_create_autocmd("Filetype", {
		group = group,
		pattern = "cavediver-primary-buffer-history",
		callback = function(args)
			local function close_window()
				vim.cmd("write!")
				local dwin = vim.b[args.buf].display_window

				vim.api.nvim_win_close(dwin, true)
				vim.defer_fn(function()
					if vim.api.nvim_buf_is_loaded(args.buf) then
						vim.api.nvim_buf_delete(args.buf, { force = true })
					end
				end, 100)
			end

			local function promote_to_primary_and_quit(stay)
				local dwin = vim.b[args.buf].display_window
				local dbuf = args.buf
				local cursor_line = vim.api.nvim_win_get_cursor(dwin)[1]
				local lines = vim.api.nvim_buf_get_lines(dbuf, 0, -1, false)

				if cursor_line > #lines then return end

				local selected_filepath = vim.trim(lines[cursor_line])

				if selected_filepath == "" then
					vim.notify("No filepath selected", vim.log.levels.WARN)
					return
				end

				table.remove(lines, cursor_line)
				table.insert(lines, 1, selected_filepath)

				vim.api.nvim_buf_set_lines(dbuf, 0, -1, false, lines)

				if stay then
					vim.cmd("write!")
					vim.api.nvim_win_set_cursor(dwin, { 1, 0 })
				else
					close_window()
				end
			end

			local keys = require('cavediver.configs').keymaps.views or {}


			-- Quick save
			vim.keymap.set("n", "<C-s>", "<cmd>write<cr>", { buffer = args.buf, desc = "Save queue" })

			-- a view key set to false isn't mapped, as in every view
			-- Save and close
			if keys.leave_too then
				vim.keymap.set("n", keys.leave_too, close_window, { buffer = args.buf, desc = "Save and close" })
			end

			if keys.leave then
				vim.keymap.set("n", keys.leave, close_window, { buffer = args.buf, desc = "Save and close" })
			end

			if keys.act then
				vim.keymap.set("n", keys.act, function() promote_to_primary_and_quit(false) end, { buffer = args.buf, desc = "Promote file under cursor and quit floating window"})
			end

			if keys.act_and_stay then
				vim.keymap.set("n", keys.act_and_stay, function() promote_to_primary_and_quit(true) end, { buffer = args.buf, desc = "Promote file under cursor and stay" })
			end

			if keys.pick then
				vim.keymap.set("n", keys.pick, function() routines.pick_into_primary_popup(args.buf) end, { buffer = args.buf, desc = "Add files through the picker" })
			end
		end
	})

	-- The closed lists' keys, the same as every view's (keymaps.views)
	vim.api.nvim_create_autocmd("Filetype", {
		group = group,
		pattern = "cavediver-closed-lists",
		callback = function(args)
			local keys = require('cavediver.configs').keymaps.views or {}
			local buf = args.buf
			local function map(lhs, fn, desc)
				if lhs then
					local act = fn
					if type(fn) == "function" then
						act = function()
							local settle = require('cavediver.settle')
							settle.drain()
							-- the step is about the window the lists act on, the one they were opened from
							require('cavediver.domains.ledger').begin("keymap", lhs, routines.closed_lists_origin(buf) or vim.api.nvim_get_current_win())
							settle.now(function()
								require('cavediver.domains.navigation').cancel_cycle_elsewhere()
								fn()
							end)
						end
					end
					vim.keymap.set("n", lhs, act, { buffer = buf, desc = desc })
				end
			end
			map(keys.leave, function() routines.leave_closed_lists(buf) end, "Write and leave the closed lists")
			map(keys.leave_too, function() routines.leave_closed_lists(buf) end, "Write and leave the closed lists")
			map(keys.act, function() routines.reopen_from_closed_lists(buf, false) end, "Reopen the file under the cursor and leave")
			map(keys.act_and_stay, function() routines.reopen_from_closed_lists(buf, true) end, "Reopen the file under the cursor and stay")
			map(keys.fold, "za", "Fold or unfold the list")
			map(keys.previous_section, function() routines.closed_lists_section(buf, -1) end, "Go to the previous list")
			map(keys.next_section, function() routines.closed_lists_section(buf, 1) end, "Go to the next list")
		end
	})

	-- WinClosed: the primary pop-up's buffer goes with its window, however it closes
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			if not args.file then
				return
			end
			local winid = tonumber(args.file)
			if not winid then
				return
			end
			local bufnr = vim.api.nvim_win_get_buf(winid)

			if vim.bo[bufnr].filetype ~= "cavediver-primary-buffer-history" then
				return
			end

			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
	})
end

return M
