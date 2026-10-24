---Navigation domain hooks for coordination with other domains.
---
---The navigation domain provides coordination context through its state changes.
---These hooks coordinate with other domains when navigation mode changes.

local history = require('cavediver.domains.history')
local routines = require('cavediver.domains.navigation.routines')
local states = require('cavediver.domains.navigation.states')
local data = require('cavediver.domains.navigation.data')
local navigationSM = require('cavediver.domains.navigation.sm')

-- a load from idle starts from nothing, as at startup: a cycle left open ends, picking nothing, and
-- the window jumps of the windows that were there go.
local storageSM = require('cavediver.domains.storage.sm')
local storageStates = require('cavediver.domains.storage.states')
storageSM:on(storageStates.IDLE, storageStates.BARE, "navigation_teardown", function()
	navigationSM.current_state = states.NORMAL
	data.cycling_window = nil
	data.window_jump_history = {}
end, 1, true)

navigationSM:on(states.NORMAL, states.CYCLING, "start_cycling", function(context)
	-- When transitioning to cycling mode, notify history domain
	---@cast context transitionContextArg
	history.sm:to(history.states.DETACHED, context or {}, history.states.mode.UPDATE)
	data.cycling_window = (context.window and context.window.current_crux) or vim.api.nvim_get_current_win()
	routines.cycle_buffer(context.direction)
end, 1, true, states.mode.CYCLE)

navigationSM:on(states.CYCLING, states.CYCLING, "keep_cycling", function(context)
	routines.cycle_buffer(context.direction)
end, 1, true, states.mode.CYCLE)

navigationSM:on(states.CYCLING, states.NORMAL, "stop_cycling", function(context)
	local ui = require('cavediver.domains.ui')
	---@cast context transitionContextArg
	history.sm:to(history.states.ATTACHED, { buf = context.history.cbufnr, pick = true }, history.states.mode.UPDATE)
	data.cycling_window = nil
	ui.sm.loop:to(ui.states.LOOP.SELF)
end, 1, true, states.mode.CYCLE)

-- jumping to another window while cycling cancels the cycle, once the editor settles: the cycling
-- window goes back to its start, nothing is recorded for the cycle's steps, and the window jumped to
-- counts as an ordinary visit (even when neovim fires no BufEnter there).
navigationSM:on(states.CYCLING, states.CYCLING, "cancel_cycle_on_window_jump", function()
	local cycling_window = data.cycling_window
	if cycling_window == nil or cycling_window == vim.api.nvim_get_current_win() then
		return
	end
	require('cavediver.settle').later("cycle cancel", function()
		routines.cancel_cycle(cycling_window)
	end)
end, 2, true, states.mode.WINENTER)

navigationSM:on("*", "*", "winenter_record_window", function(context)
	local current_win = vim.api.nvim_get_current_win()
	local previous_win = context.previous_win or vim.fn.win_getid(vim.fn.winnr("#"))

	if previous_win == 0 then
		local window = require('cavediver.domains.window.data')
		previous_win = window.last_valid_window
	end

	if previous_win and previous_win ~= current_win then
		routines.record_window_jump(previous_win, current_win)
	end
end, 1, true, states.mode.WINENTER)

local M = {}

---Create the navigation domain's autocmds in cavediver's augroup. setup() calls this, so nothing
---runs at require, and calling it again after the group is cleared replaces them cleanly.
---
---@param group integer The cavediver augroup
function M.init_autocmds(group)
	vim.api.nvim_create_autocmd("WinEnter", {
		group = group,
		callback = function(_)
			-- the settle rule: a new window doesn't show its own buffer yet (a :help or :copen split
			-- still shows the old file), so the window is taken in once the event is over.
			local winid = vim.api.nvim_get_current_win()
			-- where the jump came from is only known now.
			local previous_win = vim.fn.win_getid(vim.fn.winnr("#"))
			if previous_win == 0 then
				previous_win = require('cavediver.domains.window.data').last_valid_window
			end
			require('cavediver.settle').later("window entry win " .. vim.api.nvim_win_get_number(winid), function()
				if vim.api.nvim_get_current_win() ~= winid then
					return -- moved on already, the later WinEnter takes it from here.
				end
				navigationSM:to(navigationSM:state(), { previous_win = previous_win }, states.mode.WINENTER)
			end)
		end
	})
end

return M
