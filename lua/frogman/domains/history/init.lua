---History domain initialization, extension hooks, and API layer.
---
---The history domain manages global buffer access history and tracking state.
---This module provides the API layer and loads extension hooks that integrate
---with other domains' state machines.

local states = require('frogman.domains.history.states')
local data = require('frogman.domains.history.data')
local routines = require('frogman.domains.history.routines')

local configs = require('frogman.configs')

-- Load hooks to extend other domains' state machines
local hooks = require('frogman.domains.history.hooks')

-- Get history state machine for domain coordination
local HistorySM = require('frogman.domains.history.sm')

local M = {
	sm = HistorySM,      -- The history state machine
	states = states,     -- State constants
	data = data,         -- Domain data structures
	routines = routines, -- Domain business logic (sync functions)
	handles = require('frogman.domains.history.handles'), -- Each known file's handle
}

M.register_buffer = routines.register_buffer

M.register_filepath = routines.register_filepath

M.track_buffer = routines.track_buffer

M.reopen_last_closed = routines.reopen_last_closed

M.init_autocmds = hooks.init_autocmds

local cleanup_timer = nil

---Stop the history cleanup timer, if it's running.
---@return nil
function M.stop_cleanup_timer()
	if cleanup_timer then
		cleanup_timer:stop()
		cleanup_timer:close()
		cleanup_timer = nil
	end
end

---Run one cleanup tick.
---
---What's still queued to settle runs first, so the tick acts on the editor as it stands once the batch
---is over, as a key does. Each repair goes into the trail, as a move of the tick's own step, and
---nothing is said.
---
---@return nil
function M.tick()
	require('frogman.settle').drain()
	require('frogman.domains.ledger').within("timer", "cleanup", routines.cleanup_system, true)
end

---Initiate the history cleanup timer.
---
---It runs a tick (`M.tick()`) right away, then every `configs.cleanup_interval`.
---Calling it again restarts it.
---
---@return nil
function M.init_cleanup_timer()
	M.stop_cleanup_timer()
	cleanup_timer = vim.loop:new_timer()
	if cleanup_timer then
		cleanup_timer:start(0, configs.cleanup_interval, vim.schedule_wrap(function()
			M.tick()
		end))
	end
end

---Check if history tracking is currently detached.
---
---@return boolean detached True if history tracking is detached
function M.is_detached()
	return HistorySM:state() == states.DETACHED
end

---Get current buffer access history.
---
---@return table<HandleId, number> history File's handle to access time mapping
function M.get_buffer_history()
	return data.crux
end

---Get the stack of closed buffer handles.
---
---This is the editor's own stack. Each tab session's pool keeps a stack of its own.
---
---@return HandleId[] closed_buffers Stack of closed buffer handles that can be reopened
function M.get_closed_buffers()
	return data.closed_buffers
end

---Get ordered buffer list by recency.
---
---@return BufferHistoryItem[] ordered Buffers ordered by recency
function M.get_ordered_buffers()
	return data.ordered.crux
end

M.get_buffer_from_hash = routines.get_buffer_from_hash
M.get_hash_from_buffer = routines.get_hash_from_buffer
M.get_filepath_from_hash = routines.get_filepath_from_hash
M.get_filepath_from_buffer = routines.get_filepath_from_buffer
M.get_hash_from_filepath = routines.get_hash_from_filepath
M.get_handle_from_buffer = routines.get_handle_from_buffer
M.get_handle_from_filepath = routines.get_handle_from_filepath
M.get_handle_from_hash = routines.get_handle_from_hash
M.keyed_by_hash = routines.keyed_by_hash
M.keyed_by_handle = routines.keyed_by_handle
M.hashes_of = routines.hashes_of
M.handles_of = routines.handles_of
M.tags_by_hash = routines.tags_by_hash
M.get_hash_from_handle = routines.get_hash_from_handle
M.get_filepath_from_handle = routines.get_filepath_from_handle
M.get_buffer_from_handle = routines.get_buffer_from_handle

M.repopulate_history = routines.repopulate_history

---Check if a file is on any closed list.
---
---@param id HandleId The file's handle
---@return boolean closed True if the file is on a closed list
function M.handle_is_closed(id)
	return routines.is_handle_closed(id)
end

function M.clear_closed_buffers()
	data.closed_buffers = {}
end

M.reopen_handle = routines.reopen_handle

---Get the triquetra (window snapshot) for a specific window.
---@param winid WinId
---@return WindowTriquetra
function M.get_cycling_origins(winid)
	return data.cycling_origins[winid] or nil
end

M.delete_buffer = routines.delete_buffer

-- Cleanup functions
M.cleanup_system = routines.cleanup_system

return M
