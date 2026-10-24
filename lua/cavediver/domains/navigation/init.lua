---Navigation domain initialization, extension hooks, and API layer.
---
---The navigation domain manages buffer navigation modes and coordination context.
---This module provides the API layer and loads extension hooks that coordinate
---with other domains' state machines.

local states = require('cavediver.domains.navigation.states')
local data = require('cavediver.domains.navigation.data')
local routines = require('cavediver.domains.navigation.routines')

-- Load hooks to coordinate with other domains' state machines
local hooks = require('cavediver.domains.navigation.hooks')

-- Get navigation state machine for domain coordination
local NavigationSM = require('cavediver.domains.navigation.sm')

local M = {
    sm = NavigationSM,      -- The navigation state machine
    states = states,        -- State constants
    data = data,            -- Domain data structures
    routines = routines,    -- Domain business logic
}

---Get current navigation mode.
---
---@return string mode Current navigation mode ("normal", "cycling", "file_picker")
function M.get_mode()
    return NavigationSM:state()
end

---Check if currently in cycling mode.
---
---@return boolean cycling True if in cycling mode
function M.is_cycling()
    return NavigationSM:state() == states.CYCLING
end

---End a cycle still running in another window that no window jump queued a cancel for.
---
---A window jump queues the cycle's cancel as settle work, which a key runs first. This is the
---fallback for a jump that queued nothing, one made without autocmds. Cavediver's exported key
---functions call it once the settle queue has run, and so do the closed lists' keys and the
---trail's act_and_stay.
---
---@return nil
function M.cancel_cycle_elsewhere()
    local cycling_window = data.cycling_window
    if M.is_cycling() and cycling_window and cycling_window ~= vim.api.nvim_get_current_win() then
        routines.cancel_cycle(cycling_window)
    end
end

---Check if currently in file picker mode.
---
---@return boolean file_picker True if in file picker mode
function M.is_file_picker()
    return NavigationSM:state() == states.FILE_PICKER
end

---Check if currently in normal mode.
---
---@return boolean normal True if in normal mode
function M.is_normal()
    return NavigationSM:state() == states.NORMAL
end

---Check if a cycle can't start in the current window, saying so when it can't.
---
---A window with no triquetra (help, a quickfix list) has no start to hold, as the slot keys find.
---
---@return boolean refused True if the window has no triquetra and no cycle is running
local function refused()
	if M.is_normal() and not require('cavediver.domains.window').get_triquetra(vim.api.nvim_get_current_win()) then
		vim.notify("Window with unregistered buffer.", vim.log.levels.WARN)
		return true
	end
	return false
end

function M.cycle_left()
	if refused() then
		return
	end
	NavigationSM:to(states.CYCLING, {
		direction = 1,
		window = {
			current_crux = vim.api.nvim_get_current_win()
		}
	}, states.mode.CYCLE)
end

function M.cycle_right()
	if refused() then
		return
	end
	NavigationSM:to(states.CYCLING, {
		direction = 2,
		window = {
			current_crux = vim.api.nvim_get_current_win()
		}
	}, states.mode.CYCLE)
end

function M.select_buffer()
	NavigationSM:to(states.NORMAL, {
		history = {
			cbufnr = vim.api.nvim_get_current_buf()
		}
	}, states.mode.CYCLE)
end

M.toggle_window = routines.toggle_window


M.init_autocmds = hooks.init_autocmds

return M
