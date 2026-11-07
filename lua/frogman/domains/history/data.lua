---History domain data structures and state management.
---@alias Filehash string -- File hash type alias
---@alias Bufnr number -- Buffer number type alias
---@alias Filepath string -- File path type alias
---
---@class HistoryState
---@field crux table<HandleId, integer> File's handle to access time mapping (handle → timestamp)
---@field crux_internals BufferCruxInternals Internal data structures for crux construction.
---@field ordered OrderedHistory Ordered buffer lists for recency-based operations
---@field history_index number Next available timestamp for buffer access tracking
---@field hash_buffer_registry BuffersRegistry Bidirectional file hash ↔ buffer number mappings
---@field hash_filepath_registry FilepathRegistry Bidirectional file hash ↔ file path mappings
---@field cycling_origins table<number, WindowSnapshot> Window states before cycling began (winid → snapshot)

---@class BufferCruxInternals
---@field window table<WinId, table<HandleId, integer>> -- Window-specific crux: winid → file's handle → access_time. Can be partial
---@field global table<HandleId, integer> -- the fallback global crux: file's handle → access_time
---
---@class BufferCruxInternalsSerialised
---@field window table<string, table<Filehash, integer>> -- Window-specific crux, as a file holds it: winid → file_hash → access_time
---@field global table<Filehash, integer> -- the fallback global crux, as a file holds it: file_hash → access_time

---@class NoNameBufferContent [No Name] buffer content and metadata for restoration
---@field lines string[] Buffer content as array of lines
---@field filetype string Buffer filetype for syntax highlighting
---@field cursor {[1]:number, [2]:number} Cursor position as {row, col} tuple

---@class BufferHistoryItem Array element: {buf=number, time=number}
---@field buf number Buffer number
---@field time number Access timestamp from history_index

---@class OrderedHistory
---@field crux BufferHistoryItem[] Buffers ordered by recency (most recent first)

---@class BuffersRegistry
---@field buffers table<Filehash, Bufnr> File hash → buffer number lookup
---@field hashes table<Bufnr, Filehash> Buffer number → file hash lookup

---@class FilepathRegistry
---@field filepaths table<Filehash, Filepath> File hash → file paths lookup
---@field hashes table<Filepath, Filehash> File path → file hash lookup

---@alias WindowSnapshot WindowTriquetra Captured window state before cycling for restoration

local HistorySM = require('frogman.domains.history.sm')
local states = require("frogman.domains.history.states")

---@type HistoryState
local corpus = {
	-- Function to check if history tracking is detached (legacy compatibility)
	history_detached = function()
		return HistorySM:state() == states.DETACHED
	end,
	-- Core buffer access history: file's handle → access_time
	crux = {},
	crux_internals = {
		window = {},
		global = {},
	},
	-- Ordered buffer lists for recency-based operations
	ordered = {
		crux = {}, -- All buffers ordered by recency
	},
	-- Monotonic timestamp counter for buffer access ordering
	history_index = 1,
	-- Bidirectional file hash ↔ buffer number mappings
	hash_buffer_registry = {
		buffers = {}, -- hash → buffer
		hashes = {}   -- buffer → hash
	},
	hash_filepath_registry = {
		filepaths = {},
		hashes = {}
	},
	-- Window states captured before cycling for restoration
	cycling_origins = {}, -- cycling_origins
	-- How many session loads have run: an arrival queued before one is the restore's own, and dropped
	loads = 0,
	-- The last label seen (a git branch, say), and whether one was looked for yet
	last_label = nil,
	label_seen = false,
	-- Each session's pool (id → pool), a `Pool` (history/pool.lua): the editor's, id "", and a tab session's,
	-- keyed by its name and directory
	pools = {},
	-- The tab session each tab belongs to (tabpage → pool id); a tab in none belongs to the editor's pool
	tab_pools = {},
	-- The pools a file came out of when it was opened again (file's handle → pool id → true), for its next close
	came_from = {},
	-- The closes read at a delete's event and waiting for the editor to settle (buffer → its close); the
	-- cleanup and the UI leave such a buffer to its close
	closing = {},
}
return corpus
