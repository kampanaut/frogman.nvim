---Marks domain data structures.
---
---@class MarksGroup A named set of marks inside a scope
---@field name string The group's name
---@field marks table<string, integer> Alias → the handle number of the file it marks
---
---@class MarksScope A window's, a tab's or a session's marks
---@field groups MarksGroup[] Its groups, in order; the first drives the keys
---
---@class MarksState
---@field mode "window"|"tab"|"session" The editor's current mode
---@field scopes table<string, table<any, MarksScope>> Scope kind → id → scope: windows by their id, tabs by their tab page, sessions by their pool id ("" for the whole editor's)
---@field places table<string, table<string, boolean>> Scope ("<kind>:<id>") → the holder places its marks hold now
---@field flashes table<WinId, { text: string, till: number }> Window → what its winbar says for a moment, and until when

---@type MarksState
local corpus = {
	mode = "window",
	scopes = { window = {}, tab = {}, session = {} },
	places = {},
	flashes = {},
}

return corpus
