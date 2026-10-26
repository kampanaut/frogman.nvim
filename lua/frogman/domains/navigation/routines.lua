---Navigation domain core routines for coordination mode management.
---
---This module contains the main business logic for managing navigation modes
---that provide coordination context for other domains.

local data = require('frogman.domains.navigation.data')
local history = require('frogman.domains.history')

local M = {}

function M.cycle_buffer(direction)
	if #history.get_ordered_buffers() <= 1 then
		return
	end

	local ok, _ = pcall(require, 'cokeline.mappings')
	if not ok then
		-- without cokeline, the cycle steps through frogman's own order, in the same directions:
		-- left (1) toward newer buffers, right (2) toward older ones.
		if direction ~= 1 and direction ~= 2 then
			error("Invalid direction for cycling mode, must be 1 (left) or 2 (right).")
		end
		local ordered = history.get_ordered_buffers()
		local cbufnr = vim.api.nvim_get_current_buf()
		local index = 1
		for i, item in ipairs(ordered) do
			if item.buf == cbufnr then
				index = i
			end
		end
		local step = direction == 1 and -1 or 1
		vim.api.nvim_set_current_buf(ordered[((index - 1 + step) % #ordered) + 1].buf)
		return
	end

	if direction == 1 then
		require('cokeline.mappings').by_step("focus", -1)
	elseif direction == 2 then
		require('cokeline.mappings').by_step("focus", 1)
	else
		error("Invalid direction for cycling mode, must be 1 (left) or 2 (right).")
	end
end

local function skippable_window(winid)
	local buf = vim.api.nvim_win_get_buf(winid)
	local filetype = vim.bo[buf].filetype

	return vim.tbl_contains(require('frogman.configs').toggle_window.skip_filetypes or {}, filetype)
end

function M.record_window_jump(from_win, to_win)
	if vim.api.nvim_win_is_valid(from_win) and not skippable_window(from_win) then -- a window gone has nothing to skip
		data.window_jump_history[to_win] = from_win
	end
end

function M.toggle_window()
	local cwin = vim.api.nvim_get_current_win()

	local previous_win = data.window_jump_history[cwin]

	if
		previous_win and
		vim.api.nvim_win_is_valid(previous_win) and
		not (skippable_window(previous_win))
	then
		M.record_window_jump(cwin, previous_win)
		vim.api.nvim_set_current_win(previous_win)
	else
		vim.notify("No valid previous window to toggle to.", vim.log.levels.WARN)
	end
end

function M.get_the_previous_window_traverse_chain(cwin)
	local window = require('frogman.domains.window')
	if not cwin then
		vim.notify("No current window to trace.", vim.log.levels.WARN)
		return
	end

	local visited = {}
	local check_win = cwin

	while check_win and not visited[check_win] do
		visited[check_win] = true
		local previous_win = data.window_jump_history[check_win]
		if previous_win and vim.api.nvim_win_is_valid(previous_win) then
			-- a window with a triquetra: a float, or a window never taken in, is passed over
			if window.data.crux[previous_win] then
				window.data.last_valid_window = previous_win
				return previous_win  -- Found tracked window
			end
			check_win = previous_win
		else
			break
		end
	end
	return nil
end

function M.find_most_recent_tracked_window()
	local window = require('frogman.domains.window')
	local cwin = window.data.current_window

	if cwin == window.data.last_valid_window and vim.api.nvim_win_is_valid(cwin) then
		return window.data.last_valid_window
	elseif vim.api.nvim_win_is_valid(cwin) and window.get_triquetra(cwin) then
		window.data.last_valid_window = cwin
		return cwin
	elseif window.get_triquetra(window.data.last_valid_window) then
		return window.data.last_valid_window
	end

	return M.get_the_previous_window_traverse_chain(cwin)
end

---Cancel a cycle running in a window, and send that window back to the cycle's start.
---
---The start is the window's current slot, read live, since a swap made mid-cycle moves it. A start
---closed meanwhile is reopened, and one that can't come back leaves the window as it is.
---Navigation goes back to normal with no mode, so nothing is picked. History then attaches on
---the current window's own current slot, so no slot moves there, and what that window shows
---counts as an ordinary visit; a window visiting something untracked gets none. Says so in one
---message, and records the cancel in the ledger. Does nothing when the cycle was picked or
---cancelled already.
---
---@param cycling_window WinId The window the cycle runs in
---@return nil
function M.cancel_cycle(cycling_window)
	local navigationSM = require('frogman.domains.navigation.sm')
	local states = require('frogman.domains.navigation.states')
	if navigationSM:state() ~= states.CYCLING or data.cycling_window ~= cycling_window then
		return -- picked or cancelled already
	end
	-- the start is the cycling window's current slot, live: a swap made mid-cycle moves it.
	local triquetra = require('frogman.domains.window.data').crux[cycling_window]
	local returned = false
	if triquetra and vim.api.nvim_win_is_valid(cycling_window) then
		local start_bufnr = history.get_buffer_from_hash(triquetra.current_slot)
		if start_bufnr == nil and history.routines.is_filehash_closed(triquetra.current_slot) then
			start_bufnr = history.reopen_filehash(triquetra.current_slot) -- a start closed meanwhile comes back, as a pick's would
		end
		if start_bufnr and vim.api.nvim_win_get_buf(cycling_window) ~= start_bufnr then
			vim.api.nvim_win_set_buf(cycling_window, start_bufnr)
		end
		returned = start_bufnr ~= nil
	end
	history.data.cycling_origins[cycling_window] = nil
	data.cycling_window = nil
	local ledger = require('frogman.domains.ledger')
	ledger.move("cancelled", { subject = tostring(cycling_window), name = ledger.window_name(cycling_window),
		words = returned and ("cycle cancelled; back on " .. ledger.name_of(triquetra.current_slot)) or "cycle cancelled" })
	local named, name = false, nil
	if triquetra then
		named, name = pcall(require('frogman.domains.ui').routines.get_smart_basename, triquetra.current_slot)
	end
	if returned and named then
		vim.notify("Cycling cancelled. Window " .. vim.api.nvim_win_get_number(cycling_window)
			.. " returned to cycling origin buffer: " .. name, vim.log.levels.INFO)
	else
		vim.notify("Cycling cancelled.", vim.log.levels.INFO)
	end
	navigationSM:to(states.NORMAL) -- no mode, so this isn't a pick
	-- history attaches on the landed window's own current slot, so no slot moves; what the window
	-- shows, if that's something else, is then an ordinary visit.
	local landed = require('frogman.domains.window.data').crux[vim.api.nvim_get_current_win()]
	local shown_bufnr = vim.api.nvim_get_current_buf()
	-- a window visiting something untracked gets no visit: its current slot's file isn't what it shows
	local visiting = history.get_hash_from_buffer(shown_bufnr) == nil
	local current_bufnr = landed and not visiting and history.get_buffer_from_hash(landed.current_slot)
	history.sm:to(history.states.ATTACHED, { buf = current_bufnr or shown_bufnr }, history.states.mode.UPDATE)
	if current_bufnr and current_bufnr ~= shown_bufnr then
		history.sm:to(history.states.ATTACHED, { buf = shown_bufnr }, history.states.mode.UPDATE)
	end
	local ui = require('frogman.domains.ui')
	ui.sm.loop:to(ui.states.LOOP.SELF)
end

return M
