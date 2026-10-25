---@class CavediverKeymaps
---@field reopen_last_closed string Reopen last closed buffer
---@field toggle_secondary string Current ↔ Secondary toggle
---@field toggle_ternary string Current ↔ Ternary toggle
---@field jump_to_primary string Bring primary to current
---@field restore_ternary string Restore ternary relationship
---@field restore_secondary string Restore secondary relationship
---@field cycle_left string Cycle left during cycling mode
---@field cycle_right string Cycle right during cycling mode
---@field cycle_select string Select cycling buffer and attach history
---@field toggle_primary string Toggle current buffer as primary
---@field set_primary string Set current buffer as primary
---@field close_buffer string Unregister and delete current buffer
---@field toggle_window string Jump between previous windows
---@field open_primary_buffer_history string Open primary buffer history window
---@field open_closed_lists string Open the closed lists
---@field views CavediverViewKeymaps Keys inside cavediver's own views (the same keys in each)

---Keys inside cavediver's own views, the same in each. A key set to false isn't mapped.
---@class CavediverViewKeymaps
---@field leave string|false Write the view and leave it (the trail backs out of a search first)
---@field leave_too string|false Second key that writes and leaves the view (in the trail, even from a search)
---@field act string|false Run the view's main action on the line under the cursor, then leave
---@field act_and_stay string|false Run the view's main action, staying in the view
---@field fold string|false Fold or unfold what's under the cursor
---@field previous_section string|false Go to the previous section (the older day in the trail)
---@field next_section string|false Go to the next section (the newer day in the trail)
---@field pick string|false Add files through the picker, in the primary pop-up
---@field search string|false Search every page for a name, in the trail
---@field search_word string|false Search for the name under the cursor, in the trail

---@class CavediverGlyphs
---@field set "unicode"|"ascii" The glyph set (a glyph named here, outside the sets, replaces the set's own)
---@field list string|nil Glyph before a list's name
---@field closed string|nil Glyph before a closed entry
---@field tag string|nil Glyph before a missing file's tag

---A closed entry, as the closed lists draw it and hand it to a formatter
---@class CavediverClosedEntry
---@field name string The line's text (the file's path from the cwd, or `[No Name] "first line…"`)
---@field path string The file's full path, or its NONAME_ name
---@field time number|nil When it was closed, in seconds since the epoch
---@field filetype string|nil Filetype of a No Name text
---@field tag string|nil Label of where the file went missing, when it's gone from disk
---@field list string Name of the list it's under

---What the trail's header is drawn from, as its formatter gets it
---@class CavediverTrailHeader
---@field day string|nil The day shown, as `YYYY-MM-DD`
---@field date string The day as the header writes it (`%a %d %b %Y`)
---@field depth integer How many calendar days before today
---@field moves integer Number of the day's moves
---@field kinds table<string, integer> Number of the day's moves by kind (kind → count)

---@class CavediverFormatters
---@field closed_entry fun(entry: CavediverClosedEntry, glyphs: table): table[]|nil Virtual text after a closed entry, as {text, highlight} chunks (nil draws none)
---@field trail_step fun(step: CavediverLedgerStep, glyphs: table): table[]|nil A step's line in the trail, as {text, highlight} chunks (nil for cavediver's own)
---@field trail_move fun(move: CavediverLedgerMove, glyphs: table, step: CavediverLedgerStep): table[]|nil A move's line in the trail (nil for cavediver's own)
---@field trail_header fun(header: CavediverTrailHeader, glyphs: table): table[]|nil The trail's header line (nil for cavediver's own)

---The ledger's records, read by the ring, the trail and the formatters, so their shape stays stable

---A window's slots at one moment, with files as hashes (the step holding the row names them)
---@class CavediverLedgerRow
---@field c Filehash|nil The current slot
---@field s Filehash|nil The secondary slot
---@field t Filehash|nil The ternary slot
---@field p Filehash[] The primary queue
---@field on boolean Whether the primary is switched on
---@field dtm table<string, Filehash> Ternary notes (displacement_ternary_map), `-swap` keys included
---@field dsm table<string, Filehash> Secondary notes (displacement_secondary_map), `-swap` keys included
---@field shows Filehash|nil What the window shows, when cavediver tracks it (a replay plants it)

---A ledger step, with what set it off and what cavediver did then
---@class CavediverLedgerStep
---@field seq integer Step number, one more than the step before
---@field time number When it began, in seconds since the epoch
---@field cause "keymap"|"command"|"event"|"timer"|"load"|"save"|"restart"|"label" Kind of trigger that began it
---@field trigger string What set it off, as written (`<M-f>`, `:bdelete c.txt`, `BufDelete c.txt`, `cleanup`)
---@field win integer|nil The window it's about
---@field tab integer|nil That window's tabpage
---@field pool string|nil Id of that tab's list then ("" for the editor's, otherwise a session's)
---@field session string|nil The whole editor's session it was made under, whose file keeps it (in memory only)
---@field row_before CavediverLedgerRow|nil The window's row as the step began
---@field row_after CavediverLedgerRow|nil The window's row as the step closed
---@field names table<Filehash, string> Name of every file in its rows and moves, as it was then
---@field events string[] Events it set off, listed under it (`BufEnter b.txt`)
---@field moves CavediverLedgerMove[] What cavediver did in it
---@field told table[] Messages it queued, said as it closes (and emptied then)
---@field closed boolean|nil Whether it has closed
---@field torn boolean|nil Whether a whole-editor load replaced what it did (the session manager's teardown)
---@field dumped boolean|nil Whether the flight recorder dumped in it

---Something cavediver did in a step
---@class CavediverLedgerMove
---@field kind string Kind of move (closed, reopened, forgotten, repair, …)
---@field subject Filehash|string|nil What it's about (a file's hash, a list or a window)
---@field name string|nil The subject as shown
---@field words string|nil What happened, in words
---@field lists string[]|nil The lists it names, the tab's own first
---@field dim boolean|nil Whether it's bookkeeping of the key's own result, shown dim
---@field new boolean|nil For a reopen, whether the file was never written, so it came back as a new one
---@field state "open"|"closed"|nil Where it left its file, when its kind doesn't say (a repair's)


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
	trail_popup = {
		height = 0.8, -- can be a ratio or a whole number
		width = 0.8, -- can be a ratio or a whole number
	},
	-- the trail's header: its tally of the day's moves, its gauge of the days, its fill shaded by depth
	trail = {
		header = { tally = true, gauge = true, shade = true },
	},
	glyphs = {
		set = "unicode", -- "unicode" | "ascii"; a glyph named here, outside the sets, replaces the set's
		unicode = {
			list = "≡", closed = "↓", tag = "⎇", more = "…",
			-- the trail's: its title, fills by depth (and unshaded), gauge, marks, branches, folds, arrows, and a
			-- search's mark and life line
			title = "⦉ trail ⦊", shade0 = "≋", shade1 = "░", shade2 = "▒", shade3 = "▓", rule = "─",
			bars = "▁▂▃▄▅▆▇█", now_left = "❬", now_right = "❭", dot = " · ", older = "<<<", newer = ">>>",
			branch = "├ ", last = "└ ", stem = "│ ", folded = "▸", unfolded = "▾", arrow = " → ", ring = "┊",
			row_t = { "⦉", "⦊" }, row_c = { "[", "]" }, row_s = { "⟦", "⟧" }, search = "⌕", life = "┃", none = "—",
			-- what set a step off
			keymap = "⌨", command = "⌨", event = "⚡", timer = "⏲", load = "◆", save = "◇", restart = "↻", label = "⎇",
			-- a move's family
			reopened = "↑", forgotten = "∅", note_dropped = "⌫", gone = "✗", back = "✓", repair = "⚒", repointed = "⟲",
			landed = "⤳", undone = "↶", dropped = "⊘", cleared = "⊘", rewritten = "✎", cancelled = "⇤", loaded = "◆",
			fresh = "◆", saved = "◇", refreshed = "◇", tab_closed = "◇", copied = "⧉", moved = "⇢", detached = "≡",
			detached_left = "≡",
		},
		ascii = {
			list = "#", closed = "v", tag = "@", more = "...",
			title = "[ trail ]", shade0 = "~", shade1 = ".", shade2 = ":", shade3 = "#", rule = "-",
			bars = "_.-=+*#", now_left = "(", now_right = ")", dot = " - ", older = "<<<", newer = ">>>",
			branch = "|- ", last = "`- ", stem = "|  ", folded = "+", unfolded = "-", arrow = " -> ", ring = ":",
			row_t = { "<", ">" }, row_c = { "[", "]" }, row_s = { "{", "}" }, search = "?", life = "|", none = "-",
			keymap = "K", command = ":", event = "E", timer = "T", load = "L", save = "S", restart = "R", label = "@",
			reopened = "^", forgotten = "0", note_dropped = "x", gone = "X", back = "+", repair = "!", repointed = "~",
			landed = ">", undone = "<", dropped = "/", cleared = "/", rewritten = "*", cancelled = "|", loaded = "L",
			fresh = "L", saved = "S", refreshed = "S", tab_closed = "S", copied = "=", moved = ">", detached = "#",
			detached_left = "#",
		},
	},
	formatters = {}, -- closed_entry, trail_step, trail_move, trail_header: each gives {text, highlight} chunks, or nil for cavediver's own
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
			-- the trail's own
			wave = { "#4385BE", "#205EA6", "#1A4F8C", "#163B66" }, -- the fill: today, a week, a month, older
			title = "#879A39", -- green-400
			date = "#B7B5AC", -- base-300
			depth = "#DA702C", -- orange-400
			count = "#878580", -- base-500
			gauge = "#4385BE", -- blue-400
			gauge_now = "#FFAF00",
			key_on = "#8B7EC8", -- purple-400
			key_off = "#575653", -- base-700
			gutter = "#575653", -- base-700
			trigger = "#878580", -- base-500
			name = "#B7B5AC", -- base-300
			words = "#878580", -- base-500
			ring = "#6F6E69", -- base-600
			fold = "#8B7EC8", -- purple-400
			reopened = "#879A39", -- green-400
			forgot = "#6F6E69", -- base-600
			gone = "#D14D41", -- red-400
			back = "#879A39", -- green-400
			repair = "#D0A215", -- yellow-400
			slot = "#3AA99F", -- cyan-400
			note = "#CE5D97", -- magenta-400
			cycle = "#4385BE", -- blue-400
			session = "#4385BE", -- blue-400
			rename = "#4385BE", -- blue-400
			row_t = "#9F9D96", -- base-400
			row_c = "#879A39", -- green-400
			row_s = "#DA702C", -- orange-400
			-- a search's life line: the name open, closed, gone from disk
			life_open = "#879A39", -- green-400
			life_closed = "#DA702C", -- orange-400
			life_gone = "#D14D41", -- red-400
		},
		-- a window with no current slot: its visit alone
		visit_bar = {
			focused = "#3AA99F", -- cyan-400
			unfocused = "#575653", -- base-700
		},
		cokeline = {
			is_picking_close = "#D14D41", -- red-400
			is_picking_focus = "#4385BE", -- blue-400
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
			leave_too = "<C-c>",
			act = "<CR>",
			act_and_stay = "gf",
			fold = "za",
			previous_section = "H",
			next_section = "L",
			pick = "<M-e>", -- the primary pop-up's: add files through the picker
			search = "s", -- the trail's: search every page for a name
			search_word = "*", -- the trail's: search for the name under the cursor
		},
	},
	-- the ledger: `ring`, how many of the last steps are kept in memory, and `dump`, whether something
	-- that shouldn't happen writes them to a file under stdpath("state")/cavediver/ and a window
	ledger = {
		ring = 1000,
		dump = true,
	},
	-- label_provider: where you are, for tagging files that go missing: nil reads .git/HEAD, a
	-- function returning a string gives the label, false turns labels off (the tag is then the time).
	-- primary_picker: the primary pop-up's file picker, a function given a callback it calls with the
	-- picked files' paths: nil uses telescope's find_files when telescope is installed.
	-- marks_provider: the marked files, for the bufferline's marks: nil reads harpoon's list when it's
	-- installed, a function returning their paths in order gives them, false marks nothing.
	-- the winbar: `own`, whether cavediver writes it (otherwise `require('cavediver').winbar_segment()`
	-- gives its segment to place yourself); `skip_filetypes`, windows of these filetypes get none
	winbar = {
		own = true,
		skip_filetypes = {
			"neo-tree-popup",
			"neo-tree",
			"notify",
			"neominimap",
			"Avante",
			"AvanteInput",
			"dropbar_menu",
			"dropbar_menu_fzf",
			"DressingInput",
			"cmp_docs",
			"cmp_menu",
			"noice",
			"prompt",
			"TelescopePrompt",
			"blink_menu",
			"blink_docs",
		},
	},
	-- <M-,> (toggle_window) skips a previous window of these filetypes
	toggle_window = {
		skip_filetypes = { "minimap", "neominimap" },
	},
	cleanup_interval = 4000,              -- milliseconds
	winbar_refresh_interval = 140         -- milliseconds
}

return defaults
