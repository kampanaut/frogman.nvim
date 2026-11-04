---Marks domain data structures.
---
---@class MarksGroup A named set of marks inside a scope
---@field name string The group's name
---@field marks table<string, integer> Alias → the handle number of the file it marks
---@field held boolean|nil Whether it's held over: a closed window's or tab's, or a load's, until you move it first
---@field loaded string|nil The load that gave it, as a held-over group would name it, for a marks pop-up with edits not written
---
---@class MarksScope A window's, a tab's or a session's marks
---@field groups MarksGroup[] Its groups, in order; the first that isn't held over drives the keys
---
---@class MarksState
---@field mode "window"|"tab"|"session" The editor's current mode
---@field scopes table<string, table<any, MarksScope>> Scope kind → id → scope: windows by their id, tabs by their tab page, sessions by their pool id ("" for the whole editor's)
---@field places table<string, table<string, boolean>> Scope ("<kind>:<id>") → the holder places its marks hold now
---@field flashes table<WinId, { text: string, till: number }> Window → what its winbar says for a moment, and until when
---@field pending table[] The closed windows' and tabs' groups waiting a tick to be held over
---@field waited integer Counts the groups that waited, naming the place each one's files wait in
---@field tab_shows table<integer, { session: string, what: string }> Each tab's session and what it showed, read as tabs close
---@field ending table<integer, integer> The tab sessions' tabs closing now, each with the last wait queued before its close began: what its windows queue after is dropped at its TabClosed
---@field copies table<WinId, { from: WinId, given: table|nil }> The splits that started with a copy of a window's marks: the window, and the marks given, serialised

---@type MarksState
local corpus = {
	mode = "window",
	scopes = { window = {}, tab = {}, session = {} },
	places = {},
	flashes = {},
	pending = {},
	waited = 0,
	tab_shows = {},
	ending = {},
	copies = {},
}

return corpus
