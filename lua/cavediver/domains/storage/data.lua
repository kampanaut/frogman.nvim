---Storage domain data structures for session persistence.
---
---This module contains the data structures for managing session persistence,
---including file paths, session metadata, and serialization formats.

local M = {}

---@class StorageData
---@field session_file string Default session file path
---@field auto_save_interval number Auto-save interval in milliseconds
---@field last_save_time number Timestamp of last save operation
---@field session_metadata table Session metadata including version and timestamp
---@field serialization_format string Format for data serialization (json, lua, etc.)

---Auto-save interval in milliseconds (5 minutes default)
---@type number
M.auto_save_interval = 300000

---Timestamp of last save operation
---@type number
M.last_save_time = 0

---Session metadata including version and creation info
---@type table
M.session_metadata = {
    version = "1.0.0",
    created_at = nil,
    last_modified = nil,
    domains = {},
}

---Serialization format for session data
---@type string
M.serialization_format = "json"

---Session data structure template
---@type table
M.session_template = {
    metadata = {
        version = "1.0.0",
        created_at = nil,
        last_modified = nil,
        nvim_version = nil,
    },
    domains = {
        history = {},
        navigation = {},
        window = {},
        ui = {},
    },
}

---The session a load in the current batch of events was for, cleared by a vim.schedule once the
---batch is over (a native restore calls load_session once per loaded buffer, and only the first
---loads; a call naming another session loads)
---@type {name: string|nil, directory: string}|false
M.loading_batch = false

---What the last load in this startup loaded, so cavediver can load it again after Neovim's own
---:restart session (`name` is nil for a nameless load, `tab` is true when the load had the hint)
---@type {name: string|nil, tab: boolean}|nil
M.last_loaded = nil

---Whether this editor replayed a flight recorder's dump (its state is then no session's, and
---isn't saved)
---@type boolean
M.replayed = false

---The last whole-editor session loaded or saved
---@type {name: string|nil, directory: string}|nil
M.editor_session = nil
---The unnamed session, the whole-editor session in effect when tab sessions started (each
---tab-session save refreshes its records in its file)
---@type {name: string|nil, directory: string}|nil
M.unnamed = nil

---Error state information
---@type table
M.error_state = {
    last_error = nil,
    error_count = 0,
    last_error_time = nil,
}

return M
