---Snapshots domain data structures.
---
---@class SnapshotNote A note a snapshot keeps: its buffer's handle, the handle it names, and its kind
---@field key integer The handle of the buffer the note is on
---@field swap boolean Whether it's a swap note (`-swap`)
---@field value integer The handle the note names
---
---@class Snapshot A window's setup as it was, taken on purpose
---@field id string Its id, kept from when it was taken
---@field time integer When it was taken, in seconds since the epoch
---@field current integer The current slot's handle
---@field secondary integer|nil The secondary's handle
---@field ternary integer|nil The ternary's handle
---@field queue integer[] The primary queue's handles, the primary first
---@field primary_enabled boolean Whether the primary was on
---@field dtm SnapshotNote[] The ternary notes
---@field dsm SnapshotNote[] The secondary notes
---@field order integer[] The order the bufferline drew, its handles, the first drawn first
---@field held string|nil Its held-over header, once its window is gone: what that window was and when
---
---@class SnapshotsState
---@field by_window table<WinId, Snapshot[]> Window → its snapshots, oldest first
---@field held table<string, Snapshot[]> Session's pool id ("" for the whole editor's) → the snapshots held over in its scope, oldest first
---@field pending table[] The closed windows' snapshots waiting a tick to be held over
---@field taken integer Counts the snapshots taken in this editor, for their ids

---@type SnapshotsState
local corpus = {
	by_window = {},
	held = {},
	pending = {},
	taken = 0,
}

return corpus
