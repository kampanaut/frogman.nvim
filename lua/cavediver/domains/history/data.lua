---History domain data structures and state management.
---@alias Filehash string -- File hash type alias
---@alias Bufnr number -- Buffer number type alias
---@alias Filepath string -- File path type alias
---
---@class HistoryState
---@field crux table<Filehash, integer> File hash to access time mapping (hash → timestamp)
---@field crux_internals BufferCruxInternals Internal data structures for crux construction.
---@field ordered OrderedHistory Ordered buffer lists for recency-based operations
---@field history_index number Next available timestamp for buffer access tracking
---@field hash_buffer_registry BuffersRegistry Bidirectional file hash ↔ buffer number mappings
---@field hash_filepath_registry FilepathRegistry Bidirectional file hash ↔ file path mappings
---@field cycling_origins table<number, WindowSnapshot> Window states before cycling began (winid → snapshot)
---@field closed_buffers Filehash[] Stack of closed buffer filehashes that can be reopened via hash_filepath_registry
---@field noname_content table<Filepath, NoNameBufferContent> Content storage for [No Name] buffers

---@class Pool A session's own closed stack, close times and visits
---@field id string Pool id: "" for the editor's, or the tab session's name and directory
---@field name string|nil The tab session's name
---@field directory string|nil The tab session's directory
---@field closed Filehash[] Closed buffer filehashes, newest last
---@field times table<Filehash, number> File hash → close time, in seconds to the microsecond
---@field visits table<Filehash, integer> Its own visits, ranked above the editor's in its tab
---@field tabs table<integer, boolean> Tabs it's in (tabpage → true), none if its last tab closed unsaved
---@field detached boolean|nil Whether it's a detached list: a tab's own once its session moved to another tab
---@field of string|nil For a detached list, the id of the session it was detached from
---@field merging boolean|nil Whether a detached list waits in memory for the closed lists opened on it to close

---@class BufferCruxInternals
---@field window table<WinId, table<Filehash, integer>> -- Window-specific crux: winid → file_hash → access_time. Can be partial
---@field global table<Filehash, integer> -- the fallback global crux: file_hash → access_time
---
---@class BufferCruxInternalsSerialised
---@field window table<string, table<Filehash, integer>> -- Window-specific crux: winid → file_hash → access_time. Can be partial
---@field global table<Filehash, integer> -- the fallback global crux: file_hash → access_time

---@class NoNameBufferContent [No Name] buffer content and metadata for restoration
---@field lines string[] Buffer content as array of lines
---@field filetype string Buffer filetype for syntax highlighting
---@field cursor {[1]:number, [2]:number} Cursor position as {row, col} tuple

---@class BufferHistoryItem Array element: {buf=number, time=number}
---@field buf number Buffer number
---@field time number Access timestamp from history_index

---@class OrderedHistory
---@field crux BufferHistoryItem[] Buffers ordered by recency (most recent first)
---@field nonharpooned BufferHistoryItem[] Non-harpooned buffers ordered by recency

---@class BuffersRegistry
---@field buffers table<Filehash, Bufnr> File hash → buffer number lookup
---@field hashes table<Bufnr, Filehash> Buffer number → file hash lookup

---@class FilepathRegistry
---@field filepaths table<Filehash, Filepath> File hash → file paths lookup
---@field hashes table<Filepath, Filehash> File path → file hash lookup

---@alias WindowSnapshot WindowTriquetra Captured window state before cycling for restoration

local HistorySM = require('cavediver.domains.history.sm')
local states = require("cavediver.domains.history.states")

---@type HistoryState
local corpus = {
	-- Function to check if history tracking is detached (legacy compatibility)
	history_detached = function()
		return HistorySM:state() == states.DETACHED
	end,
	-- Core buffer access history: file_hash → access_time
	crux = {},
	crux_internals = {
		window = {},
		global = {},
	},
	-- Ordered buffer lists for recency-based operations
	ordered = {
		crux = {},        -- All buffers ordered by recency
		nonharpooned = {} -- Non-harpooned buffers ordered by recency
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
	-- Stack of closed buffer filehashes that can be reopened
	closed_buffers = {},
	-- Content storage for [No Name] buffers (identifier → content)
	noname_content = {},
	-- How many session loads have run: an arrival queued before one is the restore's own, and dropped
	loads = 0,
	-- Files gone from disk (filehash → tag): where you were when each went missing, or the time
	missing = {},
	-- Files never written (filehash → the buffer it was marked with, or true from a session file): a new
	-- file isn't missing, it hasn't been written yet
	unwritten = {},
	-- The last label seen (a git branch, say), and whether one was looked for yet
	last_label = nil,
	label_seen = false,
	-- Each session's pool (id → pool): the editor's, id "", holds closed_buffers itself; a tab session's is
	-- keyed by its name and directory
	pools = {},
	-- The tab session each tab belongs to (tabpage → pool id); a tab in none belongs to the editor's pool
	tab_pools = {},
	-- The pools a file came out of when it was opened again (filehash → pool id → true), for its next close
	came_from = {},
}
corpus.pools[""] = { id = "", closed = corpus.closed_buffers, times = {}, visits = {}, tabs = {} }
return corpus
