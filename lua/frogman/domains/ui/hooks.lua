---UI domain hooks for extending other domains' state machines.
---
---The UI domain extends navigation and history state machines with hooks that manage
---visual component state. These hooks ensure UI components adapt appropriately to
---different coordination modes and buffer state changes.

local uiMachines = require('frogman.domains.ui.sm')
local history = require('frogman.domains.history')
local states = require('frogman.domains.ui.states')
local data = require('frogman.domains.ui.data')
local routines = require('frogman.domains.ui.routines')
local navigation = require('frogman.domains.navigation')

-- a load from idle starts from nothing, as at startup: the display caches go with what they showed.
local storageSM = require('frogman.domains.storage.sm')
local storageStates = require('frogman.domains.storage.states')
storageSM:on(storageStates.IDLE, storageStates.BARE, "ui_teardown", function()
	for winid, _ in pairs(data.window_display_cache) do
		data.clear_window_display_cache(winid)
	end
	data.clear_display_name_cache()
	data.clear_bufferline_cache()
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
	local navigation = require('frogman.domains.navigation')
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

---Map a view key on a view's buffer.
---
---A key set to false isn't mapped, as in every view. A job is a step of its own, through
---`run_key`, about the window `origin` gives when the key is pressed; a string is mapped as it is.
---
---@param buf Bufnr The view's buffer
---@param lhs string|false|nil The key
---@param fn function|string The key's job, or the keys it stands for
---@param desc string What the key does
---@param origin fun(): WinId|nil The window the key's step is about, nil for the current one
---@return nil
local function map_view_key(buf, lhs, fn, desc, origin)
	if not lhs then
		return
	end
	local act = fn
	if type(fn) == "function" then
		act = function()
			require('frogman.domains.ledger').run_key(lhs, origin(), fn)
		end
	end
	vim.keymap.set("n", lhs, act, { buffer = buf, desc = desc })
end

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

	-- a colorscheme's :hi clear removes every group it doesn't define, so they're defined again; one the
	-- colorscheme defines, or a ColorScheme autocmd made before this one, stays theirs
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = function()
			local ui = require('frogman.domains.ui')
			local defined = vim.api.nvim_get_hl(0, {})
			ui.init_winbar_highlights()
			ui.init_trail_highlights()
			for name, spec in pairs(defined) do
				if next(spec) ~= nil and not vim.deep_equal(spec, vim.api.nvim_get_hl(0, { name = name })) then
					vim.api.nvim_set_hl(0, name, spec)
				end
			end
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

				vim.api.nvim_win_close(dwin, true) -- its WinClosed deletes the buffer
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

			local keys = require('frogman.configs').keymaps.views or {}
			-- each key's step is about the window the queue is for
			local function origin()
				local winid = vim.b[args.buf].origin_window
				return winid and vim.api.nvim_win_is_valid(winid) and winid or nil
			end

			-- Quick save
			map_view_key(args.buf, keys.write, function() vim.cmd("write") end, "Save queue", origin)
			-- Save and close
			map_view_key(args.buf, keys.leave_too, close_window, "Save and close", origin)
			map_view_key(args.buf, keys.leave, close_window, "Save and close", origin)
			map_view_key(args.buf, keys.act, function() promote_to_primary_and_quit(false) end, "Promote file under cursor and quit floating window", origin)
			map_view_key(args.buf, keys.act_and_stay, function() promote_to_primary_and_quit(true) end, "Promote file under cursor and stay", origin)
			map_view_key(args.buf, keys.pick, function() routines.pick_into_primary_popup(args.buf) end, "Add files through the picker", origin)
			map_view_key(args.buf, keys.search_word, function() routines.search_primary_popup(args.buf) end, "Search the trail for the file under the cursor", origin)
		end
	})

	-- The closed lists' keys, the same as every view's (keymaps.views)
	vim.api.nvim_create_autocmd("Filetype", {
		group = group,
		pattern = "cavediver-closed-lists",
		callback = function(args)
			local keys = require('frogman.configs').keymaps.views or {}
			local buf = args.buf
			-- the step is about the window the lists act on, the one they were opened from
			local function map(lhs, fn, desc)
				map_view_key(buf, lhs, fn, desc, function() return routines.closed_lists_origin(buf) end)
			end
			map(keys.leave, function() routines.leave_closed_lists(buf) end, "Write and leave the closed lists")
			map(keys.leave_too, function() routines.leave_closed_lists(buf) end, "Write and leave the closed lists")
			map(keys.act, function() routines.reopen_from_closed_lists(buf, false) end, "Reopen the file under the cursor and leave")
			map(keys.act_and_stay, function() routines.reopen_from_closed_lists(buf, true) end, "Reopen the file under the cursor and stay")
			map(keys.fold, "za", "Fold or unfold the list")
			map(keys.previous_section, function() routines.closed_lists_section(buf, -1) end, "Go to the previous list")
			map(keys.next_section, function() routines.closed_lists_section(buf, 1) end, "Go to the next list")
			map(keys.write, function() vim.cmd("write") end, "Write the closed lists")
			map(keys.search_word, function() routines.search_closed_entry(buf) end, "Search the trail for the file under the cursor")
		end
	})

end

return M
