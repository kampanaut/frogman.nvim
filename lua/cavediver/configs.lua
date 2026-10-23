---@class CavediverKeymaps
---@field reopen_last_closed string Reopen last closed buffer
---@field toggle_secondary string Current ↔ Secondary toggle
---@field toggle_ternary string Current ↔ Ternary toggle
---@field jump_to_primary string Bring primary to current
---@field restore_ternary string Restore ternary relationship
---@field restore_secondary string Restore secondary relationship
---@field cycle_left string Cycle left during cycling mode
---@field cycle_right string Cycle right during cycling mode
---@field cycle_select string Toggle current buffer as primary
---@field toggle_primary string Toggle current buffer as primary
---@field set_primary string Set current buffer as primary
---@field close_buffer string Unregister and delete current buffer
---@field toggle_window string Jump between previous windows
---@field open_primary_buffer_history string Open primary buffer history window
---@field open_closed_lists string Open the closed lists
---@field views CavediverViewKeymaps The keys inside cavediver's own views, the same in each

---@class CavediverViewKeymaps
---@field leave string Write, then leave the view
---@field act string The view's main action on the line under the cursor, then leave
---@field act_and_stay string The main action, staying in the view
---@field fold string Fold or unfold a section
---@field previous_section string Go to the previous section
---@field next_section string Go to the next section

---@class CavediverGlyphs
---@field set "unicode"|"ascii" The glyph set; any glyph named here replaces the set's own
---@field list string|nil Before a list's name
---@field closed string|nil Before a closed entry
---@field tag string|nil Before a missing file's tag

---A closed entry, as the closed lists draw it and hand it to a formatter.
---@class CavediverClosedEntry
---@field name string The line's text: the file's path, or `[No Name] "first line…"`
---@field path string The file's path, or its NONAME_ name
---@field time number|nil When it was closed, in seconds
---@field filetype string|nil A No Name text's filetype
---@field tag string|nil Where the file went missing, when it's gone from disk
---@field list string The list's name

---@class CavediverFormatters
---@field closed_entry fun(entry: CavediverClosedEntry, glyphs: table): table[]|nil The virtual text after an entry, as {text, highlight} chunks

---The ledger's records, which the ring and the trail read. Kept stable: formatters read them.

---A window's slots at one moment. Files are hashes; the step that holds the row names them.
---@class CavediverLedgerRow
---@field c Filehash|nil The current slot
---@field s Filehash|nil The secondary slot
---@field t Filehash|nil The ternary slot
---@field p Filehash[] The primary queue
---@field on boolean Whether the primary is switched on
---@field dtm table<string, Filehash> The ternary notes, `-swap` keys included
---@field dsm table<string, Filehash> The secondary notes, `-swap` keys included

---What set things off, and what cavediver did then.
---@class CavediverLedgerStep
---@field seq integer Its number, one more than the step before
---@field time number When it began, in seconds
---@field cause "keymap"|"command"|"event"|"timer"|"load"|"save"|"restart"|"label"
---@field trigger string What set it off, as written: `<M-f>`, `:bdelete c.txt`, `BufDelete c.txt`, `cleanup`
---@field win integer|nil The window it's about
---@field tab integer|nil That window's tab
---@field pool string|nil The id of that tab's list then: "" the editor's, or a session's
---@field row_before CavediverLedgerRow|nil The window's row as the step began
---@field row_after CavediverLedgerRow|nil The window's row as the step closed
---@field names table<Filehash, string> The name of every file in its rows and moves, as they were then
---@field events string[] The events it set off, `BufEnter b.txt`, listed under it
---@field moves CavediverLedgerMove[] What cavediver did in it
---@field torn boolean|nil A whole-editor load replaced what it did: the session manager's teardown

---Something cavediver did in a step.
---@class CavediverLedgerMove
---@field kind string What it was: closed, reopened, forgotten, repair, …
---@field subject Filehash|string|nil What it's about: a file's hash, a list, a window
---@field name string|nil The subject as shown
---@field words string|nil What happened, in words
---@field lists string[]|nil The lists it names, the tab's own first
---@field dim boolean|nil Bookkeeping: what the key's own result left, shown dim


---Default configuration
---@class CavediverConfig
local defaults = {
	session_dir = vim.fn.stdpath("data") .. "/cavediver/sessions/",
	bufferline = {
		history_view = "global" -- "global" | "window"
	},
	primary_buffer_history_popup = {
		height = 0.2, -- can be a ratio or a whole number
		width = 0.7, -- can be a ratio or a whole number
	},
	closed_lists_popup = {
		height = 0.5, -- can be a ratio or a whole number
		width = 0.7, -- can be a ratio or a whole number
	},
	glyphs = {
		set = "unicode", -- "unicode" | "ascii"; a glyph named here (list, closed, tag) replaces the set's
	},
	formatters = {}, -- closed_entry: a function of the entry and the glyphs, giving the text after it
	colors = {
		base = {
			focused = {
				fg = "#B7B5AC", -- base-300
				bg = "#151515", -- your bg
			},
			unfocused = {
				fg = "#575653", -- base-700
				bg = "#151515"
			},
		},
		current = {
			focused = {
				filename = "#879A39", -- green-400
				bufnr = "#879A39",
			},
			unfocused = {
				filename = "#575653",
				bufnr = "#575653",
			}
		},
		secondary = {
			focused = {
				filename = "#879A39",
				bufnr = "#DA702C" -- orange-400
			},
			unfocused = {
				filename = "#575653",
				bufnr = "#575653",
			},
		},
		ternary = {
			focused = {
				filename = "#9F9D96", -- base-400
				bufnr = "#9F9D96"
			},
			unfocused = {
				filename = "#575653",
				bufnr = "#575653",
			},
		},
		primary = {
			active = "#FFAF00",
			inactive = "#575653",
			unfocused = "#575653"
		},
		harpooned = {
			unfocused = {
				fg = "#8B7EC8", -- purple-400
			}
		},
		both_way_arrow = {
			focused = "#4385BE", -- blue-400
			unfocused = "#4385BE"
		},
		trail = {
			list = "#8B7EC8", -- purple-400
			closed = "#DA702C", -- orange-400
			time = "#878580", -- base-500
			tag = "#6F6E69", -- base-600
			dim = "#575653", -- base-700
		},
		cokeline = {
			is_picking_close = "#D14D41", -- red-400
			active = "#FFAF00",
			bg = {
				detached = {
					focused = "#282726", -- base-900
					unfocused = "#100F0F", -- black
				},
				attached = "#151515"
			},
			fg = {
				focused = "#878580", -- base-500
				unfocused = "#6F6E69" -- base-600
			},
			diagnostics = {
				error = "#D14D41", -- red-400
				warning = "#D0A215", -- yellow-400
				info = "#3AA99F", -- cyan-400
				hint = "#879A39" -- green-400
			}
		}
	},
	keymaps = {
		-- Buffer lifecycle
		reopen_last_closed = "<M-S-w>",

		-- Core triquetra operations
		toggle_secondary = "<M-f>", -- Current ↔ Secondary toggle
		toggle_ternary = "<M-S-f>", -- Current ↔ Ternary toggle
		jump_to_primary = "<M-;><M-f>", -- Bring primary to current
		restore_ternary = "<M-;><M-r>", -- Restore ternary relationship
		restore_secondary = "<M-;><M-t>", -- Restore secondary relationship

		-- Window navigation
		toggle_window = "<M-,>", -- Toggle between current and previous window

		-- Cycling mode navigation
		cycle_left = "<M-n>", -- During cycling mode
		cycle_right = "<M-m>", -- During cycling mode
		cycle_select = "<M-v>", -- Quit cycling mode and attach history with cycling buffer

		-- Primary buffer management
		toggle_primary = "<M-;><M-x>", -- Toggle current buffer as primary
		set_primary = "<M-;><M-c>",
		close_buffer = "<M-.>",

		open_primary_buffer_history = "<M-;>F", -- Open primary buffer history
		open_closed_lists = "<M-;>W", -- Open the closed lists

		-- Inside cavediver's own views
		views = {
			leave = "q",
			act = "<CR>",
			act_and_stay = "gf",
			fold = "za",
			previous_section = "H",
			next_section = "L",
		},
	},
	-- the ledger: `ring`, how many of the last steps are kept in memory
	ledger = {
		ring = 1000,
	},
	-- label_provider: where you are, for tagging files that go missing: nil reads .git/HEAD, a
	-- function returning a string gives the label, false turns labels off (the tag is then the time).
	cleanup_interval = 4000,              -- seconds
	winbar_refresh_interval = 140         -- milliseconds
}

return defaults
