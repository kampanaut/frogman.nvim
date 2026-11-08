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

---The loads this startup made that still stand, in order, so frogman can run each again after Neovim's
---own :restart session: the last whole-editor load and the tab sessions' loads after it (`name` is nil for
---a nameless load, `tab` the number of the tab a tab session went into)
---@type {name: string|nil, tab: integer|nil}[]
M.loads = {}

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

---@class EntryClose What a closing window or plain tab put onto its entry, for the records to write
---@field groups table[]|nil Its groups as the file holds them, nil with none
---@field snapshots table[]|nil A window's snapshots as the file holds them, nil with none
---@field what string What it was, as a held-over header names it, should the entry not take them
---@field session string The pool id of the session it closed in ("" for the whole editor's)
---@field place string The holder place its files wait in, so none is let go before they land
---@field state "landed"|"held"|nil Written onto the entry, or held over instead; nil while it waits

---@class EntrySlot A window or tab entry of a session's file, as this editor knows it
---@field win WinId|nil The window that wrote it or took it at a load
---@field tab integer|nil The tab that wrote it or took it at a load
---@field entry table The entry as the file holds it, for a write to know it again
---@field take_off true|nil An entry no window or tab took at the last load, its marks and snapshots held over since, to come off the file
---@field close EntryClose|nil What its window's or tab's close put onto it

---Each session file's window and tab entries this editor knows, by file and index: which window or
---tab each is, and what the next records write does to it, while it's still the entry this editor
---knows. A save of the file sets them anew, as does a load of it.
---@type table<string, {windows: table<integer, EntrySlot>, tabs: table<integer, EntrySlot>}>
M.entries = {}

return M
