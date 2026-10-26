---Storage domain data for session persistence.
---
---This module holds what the storage domain keeps between calls: the loads of the current batch
---of events, the last load, and the whole editor's session and the unnamed one.

local M = {}

---The sessions the loads in the current batch of events were for, cleared by a vim.schedule once
---the batch is over (a native restore calls load_session once per loaded buffer, and only the first
---loads; a call naming another session loads, and one naming any of these again doesn't)
---@type {name: string|nil, directory: string}[]|false
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

return M
