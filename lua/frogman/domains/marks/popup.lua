---The marks pop-up.
---
---One editable floating window on the marks of a scope: the scope the current mode reads for the
---window it's opened from. Each scope has a buffer of its own, the window's, the tab's and the
---session's, kept with its whole undo history as long as its scope is there, the float showing one at
---a time. A group is a header line, `❖ main`, and its marks are rows under it, `a -> b.txt`, one for
---every alias the config has, then the group's unassigned ones. What the rows stand for is drawn around
---them as virtual text, in the trail's language. The lines are written back into the scope at `:w`,
---after the checks.

local data = require('frogman.domains.marks.data')
local history = require('frogman.domains.history')

local M = {}

local NAME = "frogman://marks"
local ns = vim.api.nvim_create_namespace("frogman_marks_popup")

---The marks domain's routines, required when first used, since they require this module.
---@return table routines
local function routines()
	return require('frogman.domains.marks.routines')
end

---@class MarksPopupBuffer A scope's buffer in the pop-up, and what its lines were drawn from
---@field buf Bufnr Its buffer
---@field kind "window"|"tab"|"session" Its scope's kind
---@field id any Its window, tab or session's pool id
---@field key string What it's kept by (`key_of`)
---@field mode string The mode it was last shown in
---@field flag boolean|nil The modified flag frogman last set on it while shown
---@field names table<string, HandleId> Drawn name → the file's handle
---@field paths table<string, string> Drawn name → the file's path
---@field states table<string, string> Row (alias and the file's handle) → "incoming" or "already set"
---@field drawn table<MarksGroup, true>|nil The scope's groups as it was drawn, so a group that came in since stays
---@field groups_drawn {key: string, name: string, held: boolean|nil, default: boolean|nil, from: string|nil, rows: string[]}[]|nil Each group drawn, by its key and rows, for the write to know it again
---@field drawn_lines string[]|nil The lines it was drawn as, none while a conflict waits to be settled

---Each scope's buffer, by its key.
---@type table<string, MarksPopupBuffer>
local bufs = {}

---The float that's open: its window, the window it was opened from, and the buffer it shows.
---@type {win: WinId|nil, origin: WinId, shown: MarksPopupBuffer}|nil
local open = nil

---What a scope's buffer held as Neovim threw it away, by its key: its lines and the file its undo history
---was written to, read back when that scope's buffer is made again.
---@type table<string, {lines: string[], undo: string|nil, kind: string, id: any}>
local kept = {}

-- set while frogman sets a buffer's modified flag itself
local setting = false
-- set once Neovim exits: a buffer it throws away then keeps nothing
local exiting = false
-- the buffers frogman wipes itself, their scope gone: nothing kept of them
local wiping = {}

---Get the glyph a group's header opens with, in the glyph set in use.
---@return string glyph
local function group_glyph()
	return require('frogman.domains.ui').routines.glyphs().group or "❖"
end

---Get the aliases the config has, in their order.
---@return string[] aliases
local function aliases()
	local index = require('frogman.configs').marks.aliases or {}
	local out = vim.tbl_keys(index)
	table.sort(out, function(a, b)
		return routines().alias_before(index, a, b)
	end)
	return out
end

---Check if the pop-up's float is open.
---@return boolean
local function is_open()
	return open ~= nil and open.win ~= nil and vim.api.nvim_win_is_valid(open.win)
end

---Get the whole editor's session's part of a key: its directory and name, nothing before it has one.
---@param session {name: string|nil, directory: string}|nil The whole editor's session
---@return string part
local function editor_part(session)
	return session and (session.directory .. "\0" .. (session.name or "")) or ""
end

---Get what a scope's buffer is kept by: its kind and id, and for the whole editor's session its directory and
---name too, so another session gets a buffer of its own.
---@param kind "window"|"tab"|"session" The scope's kind
---@param id any Its window, tab or session's pool id
---@return string key
local function key_of(kind, id)
	if kind == "session" and id == "" then
		return "session\0\0" .. editor_part(require('frogman.domains.storage.data').editor_session)
	end
	return kind .. "\0" .. tostring(id)
end

---Check if a scope's window or tab is gone; a session's scope never is.
---@param kind "window"|"tab"|"session" The scope's kind
---@param id any Its window, tab or session's pool id
---@return boolean gone
local function scope_gone(kind, id)
	return (kind == "window" and not vim.api.nvim_win_is_valid(id)) or (kind == "tab" and not vim.api.nvim_tabpage_is_valid(id))
end

---Check if a scope's buffer holds edits: its lines not the ones its scope was drawn as, a conflict waiting
---to be settled counting as edits.
---@param record MarksPopupBuffer The scope's buffer
---@return boolean edited
local function edited(record)
	if not vim.api.nvim_buf_is_loaded(record.buf) then
		return false
	end
	return record.drawn_lines == nil or not vim.deep_equal(vim.api.nvim_buf_get_lines(record.buf, 0, -1, false), record.drawn_lines)
end

---Get the drafts: the scopes' buffers holding edits that the float doesn't show, the window's first, then the
---tab's, then the sessions'.
---@return MarksPopupBuffer[] drafts
local function drafts()
	local out = {}
	for _, record in pairs(bufs) do
		if (open == nil or record ~= open.shown) and edited(record) then
			table.insert(out, record)
		end
	end
	local rank = { window = 1, tab = 2, session = 3 }
	table.sort(out, function(a, b)
		return rank[a.kind] < rank[b.kind] or (rank[a.kind] == rank[b.kind] and a.buf < b.buf)
	end)
	return out
end

---Check if the pop-up holds anything not written: edits on its screen, or a draft.
---@return boolean holds
local function holds_edits()
	return (open ~= nil and edited(open.shown)) or #drafts() > 0
end

---Mark each scope's buffer modified while it holds edits, and the shown one while any does, so `:q` refuses
---until they're written or dropped. The shown one modified is wiped by a `:q!`, its history kept as it goes
---(`keep`); otherwise a buffer is hidden as the float leaves it, its history with it. Lines typed back as they
---were drawn hold nothing.
---@return nil
local function set_modified()
	local held = #drafts() > 0
	setting = true
	for _, record in pairs(bufs) do
		if vim.api.nvim_buf_is_loaded(record.buf) then
			local shown = open ~= nil and record == open.shown
			local modified = edited(record) or (shown and held)
			vim.bo[record.buf].modified = modified
			vim.bo[record.buf].bufhidden = (shown and modified) and "wipe" or "hide"
			if shown then
				record.flag = modified
			end
		end
	end
	setting = false
end

---Put lines in a scope's buffer as frogman draws them: its first draw starts its undo history, and every draw
---after it is one undo step, so an undo takes back a redraw as it takes back a change.
---@param record MarksPopupBuffer The scope's buffer to draw into
---@param lines string[] The lines to draw
---@param first boolean|nil Whether it's the buffer's first draw
---@return nil
local function put_lines(record, lines, first)
	if first then
		local levels = vim.bo[record.buf].undolevels
		vim.bo[record.buf].undolevels = -1
		local put, problem = pcall(vim.api.nvim_buf_set_lines, record.buf, 0, -1, false, lines)
		vim.bo[record.buf].undolevels = levels
		if not put then
			error(problem, 0)
		end
		return
	end
	if vim.deep_equal(vim.api.nvim_buf_get_lines(record.buf, 0, -1, false), lines) then
		return -- nothing to take back
	end
	vim.api.nvim_buf_call(record.buf, function()
		vim.o.undolevels = vim.o.undolevels -- what was typed before stays a step of its own
		vim.api.nvim_buf_set_lines(record.buf, 0, -1, false, lines)
	end)
end

---Redraw the UI once marks or the mode changed.
---@return nil
local function repaint()
	require('frogman.domains.ui.sm').loop:to(require('frogman.domains.ui.states').LOOP.SELF)
end

---Check if the marks pop-up is the window you're in.
---@return boolean current
function M.is_current()
	return is_open() and vim.api.nvim_get_current_buf() == open.shown.buf
end

---The words the mark keys say while the pop-up has edits not written yet
local DIRTY = "frogman: the marks pop-up has edits not written yet: write them with :w, or leave them, first."
---The words they say while it holds a draft of another scope, which `:w` doesn't write
local DRAFTS = "frogman: the marks pop-up holds drafts not written yet: write them with q, or drop them with :q!, first."

---Get what a refusal says while the pop-up has edits not written yet: the drafts' words while one is held.
---@return string words
local function refusal()
	return #drafts() > 0 and DRAFTS or DIRTY
end

---Refuse a mark key while the pop-up has edits not written yet, saying so.
---@return boolean refused
function M.refuse_if_dirty()
	if M.dirty() then
		vim.notify(refusal(), vim.log.levels.WARN)
		return true
	end
	return false
end

---Get the name a file is drawn by, and keep what it stands for.
---
---A file goes by its shortest unique name, and by its path from here when another drawn file goes
---by that name already; a No Name text by `[No Name]` and its first line.
---
---@param id HandleId The file's handle
---@param names table<string, HandleId> Drawn name → the file's handle, added to in place
---@param paths table<string, string> Drawn name → the file's path, added to in place
---@return string name
local function name_of(id, names, paths)
	local handle = history.handles.get(id)
	local filepath = history.get_filepath_from_handle(id) or tostring(id)
	local name
	if filepath:match("^NONAME_") then
		local bufnr = history.get_buffer_from_handle(id)
		local lines = bufnr and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
			or (handle and handle.text or {}).lines or {}
		local first = vim.trim(lines[1] or "")
		name = first ~= "" and ('[No Name] "' .. first:sub(1, 24) .. '"') or "[No Name]"
		local n = 1
		while names[name] and names[name] ~= id do
			n = n + 1
			name = name:gsub(" #%d+$", "") .. " #" .. n
		end
	else
		name = require('frogman.domains.ui').routines.get_smart_basename(id)
		if names[name] and names[name] ~= id then
			name = vim.fn.fnamemodify(filepath, ":.")
		end
	end
	-- each name drawn by its file's handle, so a row follows its file through a move, and by its path, for
	-- a file let go and known again under a handle of its own
	names[name], paths[name] = id, filepath
	return name
end

---Draw a scope's groups as the pop-up's lines.
---
---A scope with no group yet is drawn with its default one. With a conflict, the alias the add was
---for holds two rows in the first group: the incoming file and the one already set.
---
---@param kind string The scope's kind: "window", "tab" or "session"
---@param id any Its window, tab or session's pool id
---@param conflict {alias: string, id: HandleId}|nil The alias an add found taken and the incoming file's handle, or nil
---@return string[] lines
---@return table<string, HandleId> names
---@return table<string, string> states Row (alias and the file's handle) → "incoming" or "already set"
---@return {key: string, name: string, held: boolean|nil, default: boolean|nil, from: string|nil, rows: string[]}[] drawn Each group drawn, in order: its key, its flags, the name a held-over one with no marks came from, and its marks, each by its alias and its file
---@return table<string, string> paths Drawn name → the file's path
local function draw(kind, id, conflict)
	local scope = data.scopes[kind][id]
	local groups = scope and scope.groups or {}
	if routines().first_group(scope) == nil then
		-- the keys' group first, the default one, ahead of anything held over
		groups = vim.list_extend({ { name = require('frogman.configs').marks.default_group, marks = {}, default = true } },
			vim.list_slice(groups))
	end
	local keys_group = routines().first_group({ groups = groups })
	local lines, names, states, drawn, paths = {}, {}, {}, {}, {}
	local glyph = group_glyph()
	local known = {}
	for _, alias in ipairs(aliases()) do
		known[alias] = true
	end
	for g, group in ipairs(groups) do
		table.insert(lines, glyph .. " " .. group.name)
		local info = {
			key = routines().group_key(groups, g), name = group.name, held = group.held, default = group.default, from = group.from, rows = {},
		}
		table.insert(drawn, info)
		local function row(alias, id)
			table.insert(lines, alias .. " -> " .. (id and name_of(id, names, paths) or ""))
			if id then
				table.insert(info.rows, alias .. "\0" .. id) -- a mark, by its alias and its file
			end
		end
		for _, alias in ipairs(aliases()) do
			local handle = routines().handle_of(group, alias)
			if group == keys_group and conflict and conflict.alias == alias and (handle == nil or handle.id ~= conflict.id) then
				row(alias, conflict.id)
				states[alias .. "\0" .. conflict.id] = "incoming"
				if handle then
					row(alias, handle.id)
					states[alias .. "\0" .. handle.id] = "already set"
				end
			else
				row(alias, handle and handle.id)
			end
		end
		local unassigned = {}
		for alias, _ in pairs(group.marks) do
			if not known[alias] then
				table.insert(unassigned, alias)
			end
		end
		table.sort(unassigned)
		for _, alias in ipairs(unassigned) do
			local handle = routines().handle_of(group, alias)
			if handle then
				row(alias, handle.id)
			end
		end
	end
	return lines, names, states, drawn, paths
end

---Read one of the pop-up's lines.
---
---@param line string The line as the buffer holds it
---@return "blank"|"header"|"row"|"other" kind
---@return string|nil a The header's name, or the row's alias
---@return string|nil b The row's file as written
local function read_line(line)
	local text = vim.trim(line)
	if text == "" then
		return "blank"
	end
	-- a header opens with the glyph the set in use draws, one of one's own too, or with either set's
	for _, glyph in ipairs({ group_glyph(), "❖", "*" }) do
		if glyph ~= "" and text:sub(1, #glyph) == glyph then
			local name = text:sub(#glyph + 1):match("^%s+(.-)%s*$")
			if name and name ~= "" then
				return "header", name
			end
		end
	end
	local alias, file = text:match("^(%S+)%s*%->%s*(.-)%s*$")
	if alias then
		return "row", alias, file
	end
	return "other"
end

---Find the file a row names: a name the pop-up drew, or a path, from here, to a file.
---
---A file the registry knows is given by its handle, and so is an open file the path is another name of,
---a symlink to it; one it doesn't know yet, by its path's hash, until the write registers the path.
---
---@param record MarksPopupBuffer The buffer the row is in
---@param file string The row's file as written
---@return HandleId|Filehash|nil ref The file's handle, or its hash while the registry doesn't know it
---@return string|nil path A path to register as the write goes through, when the registry has none
local function resolve(record, file)
	-- a row it drew follows its file, by the file's handle, through a move since
	local drawn = record.names[file]
	if drawn then
		-- a file let go since and known again has a handle of its own, which the row finds by its path
		local handle = history.handles.follow(drawn)
			or history.handles.get(history.get_handle_from_filepath(record.paths and record.paths[file]))
		return handle and handle.id or drawn, nil
	end
	local path = vim.fn.fnamemodify(file, ":p")
	local id = history.get_handle_from_filepath(path)
	if id then
		return id, nil
	end
	-- another name of an open file, a symlink to it, is that file, as :e goes to its buffer
	local real = vim.uv.fs_realpath(path)
	if real then
		for _, bufnr in pairs(history.data.hash_buffer_registry.buffers) do
			local name = vim.api.nvim_buf_get_name(bufnr)
			if name ~= "" and vim.uv.fs_realpath(name) == real then
				return history.get_handle_from_buffer(bufnr), nil
			end
		end
	end
	if vim.fn.filereadable(path) == 1 and vim.fn.isdirectory(path) == 0 then
		return history.routines.get_filehash(path), path
	end
	return nil, nil
end

---Draw the pop-up's decoration again: the mode line above it, its lines coloured in the trail's
---language, and around each row its file's state.
---
---A header takes the lists' colour; a row's alias a key's, dim when the config has none for it, its
---arrow dim, and its file the trail's name colour, dim while the file is closed or gone from disk and
---for a row naming no file.
---
---@return nil
local function decorate()
	if not is_open() then
		return
	end
	local record = open.shown
	local buf = record.buf
	local glyphs = require('frogman.domains.ui').routines.glyphs()
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local mode_line = "marks" .. glyphs.dot .. record.kind
	local held = drafts()
	if #held > 0 then
		-- the scopes a mode switch left with edits, still to be written
		mode_line = mode_line .. glyphs.dot .. (#held == 1 and "draft: " or "drafts: ") ..
			table.concat(vim.tbl_map(function(draft) return draft.kind end, held), ", ")
	end
	vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
		virt_lines = { { { mode_line, "FrogmanTrailDim" } } }, virt_lines_above = true,
	})
	local known = {}
	for _, alias in ipairs(aliases()) do
		known[alias] = true
	end
	for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		local kind, alias, file = read_line(line)
		if kind == "header" then
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = #line, hl_group = "FrogmanTrailList" })
		elseif kind == "row" then
			local start = line:find("%S")
			local arrow = line:find("->", start + #alias, true)
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, start - 1, {
				end_col = start - 1 + #alias, hl_group = known[alias] and "FrogmanTrailKeyOn" or "FrogmanTrailKeyOff",
			})
			if arrow then
				vim.api.nvim_buf_set_extmark(buf, ns, i - 1, arrow - 1, { end_col = arrow + 1, hl_group = "FrogmanTrailDim" })
			end
		end
		if kind == "row" and file ~= "" then
			local ref = resolve(record, file)
			local handle = type(ref) == "number" and history.handles.get(ref) or nil
			local arrow = line:find("->", 1, true)
			local col = arrow and line:find("%S", arrow + 2) -- the name's first character, however it's spaced
			if col then
				-- the file in the trail's name colour, dim while it's closed or gone from disk, and for a row naming
				-- no file; a path to a file the registry knows only at the write names one
				local named = handle ~= nil or type(ref) == "string"
				local dim = not named or (handle ~= nil and (history.handles.kept_closed(handle.id) or handle.tag ~= nil))
				vim.api.nvim_buf_set_extmark(buf, ns, i - 1, col - 1, {
					end_col = col - 1 + #file, hl_group = dim and "FrogmanTrailDim" or "FrogmanTrailName",
				})
			end
			if handle and history.handles.kept_closed(handle.id) and col then
				vim.api.nvim_buf_set_extmark(buf, ns, i - 1, col - 1, {
					virt_text = { { glyphs.closed .. " ", "FrogmanTrailClosed" } }, virt_text_pos = "inline",
				})
			end
			local after = {}
			local state = ref and record.states[alias .. "\0" .. ref]
			if state then
				table.insert(after, { "  " .. state, "FrogmanTrailDim" })
			end
			if not known[alias] then
				table.insert(after, { "  unassigned", "FrogmanTrailDim" })
			end
			if handle and handle.tag then
				table.insert(after, { "  " .. glyphs.tag .. handle.tag, "FrogmanTrailTag" })
			end
			if #after > 0 then
				vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { virt_text = after, virt_text_pos = "eol" })
			end
		end
	end
end

---Show the mode line above the first line: a window shows a line above its top one only when told to.
---@return nil
local function show_mode_line()
	require('frogman.domains.ui.view').show_top(open and open.win)
end

---Put a scope's marks in its buffer, as they are now: its first draw, or an undo step.
---@param record MarksPopupBuffer The scope's buffer
---@param conflict {alias: string, id: HandleId}|nil The alias an add found taken and the incoming file's handle, or nil
---@param first boolean|nil Whether it's the buffer's first draw
---@return nil
local function draw_into(record, conflict, first)
	local lines, names, states, drawn, paths = draw(record.kind, record.id, conflict)
	record.names, record.states, record.groups_drawn, record.paths = names, states, drawn, paths
	-- what the write rebuilds from the lines: a group that comes in after stays
	local scope = data.scopes[record.kind][record.id]
	record.drawn = {}
	for _, group in ipairs(scope and scope.groups or {}) do
		record.drawn[group] = true
	end
	put_lines(record, lines, first)
	record.drawn_lines = conflict == nil and lines or nil -- a conflict waits to be settled and written, as edits do
	set_modified()
	if is_open() and open.shown == record then
		decorate()
		show_mode_line()
	end
end

---Draw a scope's buffer again when its scope changed and it holds no edits, shown or not, so it shows what's
---there, the draw an undo step.
---
---@param kind "window"|"tab"|"session" The kind of the scope that changed
---@param id any Its window, tab or session's pool id
---@return nil
function M.scope_changed(kind, id)
	local record = bufs[key_of(kind, id)]
	if record and vim.api.nvim_buf_is_loaded(record.buf) and not edited(record) then
		draw_into(record, nil)
	end
end

---Draw every scope's buffer again that holds nothing unwritten, as when every scope changed at once: a
---whole-editor load's teardown lets every scope go.
---
---@return nil
function M.every_scope_changed()
	for _, record in pairs(bufs) do
		if vim.api.nvim_buf_is_loaded(record.buf) and not edited(record) then
			draw_into(record, nil)
		end
	end
end

---Match each group written to the one the pop-up drew, and find each drawn group whose header was
---deleted with some of its marks left under another group's.
---
---A mark is known by its alias and its file, each counted once, and a group by its name and place: a
---drawn group whose name and place another written group still holds is that one's alone. A group
---written is first the drawn one of its name that kept marks of it: the one of its name and place when
---that one did, otherwise the one whose mark comes first under it, since a deleted header's rows join
---the group above below its own. Else, renamed, it's the drawn one whose mark comes first under it,
---unless a drawn group of its own name and place is still there to be it. Else it's the one of its name
---and place. Else, empty, with no mark to follow, it's by position the unclaimed empty drawn group between
---the drawn groups its nearest matched neighbours have; where more empty headers stand between them than
---empty groups were drawn there, which header stands for which can't be told, and each one taken is named
---for the write's prompt to ask about. One renamed with every mark changed, or typed in under a new name,
---matches none. A drawn group none matched had its header deleted, and its marks still there, beyond
---another group's own, joined that group.
---
---@param groups {name: string, row: integer, rows: {key: string, row: integer}[]}[] The groups written, in order, each with its header's line and each mark by its key and its line
---@param drawn {key: string, name: string, held: boolean|nil, rows: string[]}[] The groups drawn, in order
---@return table<integer, integer> match A written group's place → the drawn group's
---@return {name: string, into: string, row: integer}[] joined Each drawn group whose header is gone with marks left: its name, the group they joined and the first one's line, a name with its place, `x/2`, when another group has it
---@return {row: integer, text: string}[] guessed Each empty header taken by its place for a drawn group where more empty headers stand than empty groups were drawn, at its header's line
local function match_groups(groups, drawn)
	local match, claimed = {}, {}
	local function claim(g, d)
		match[g], claimed[d] = d, true
	end
	local keys = {}
	for g, _ in ipairs(groups) do
		keys[g] = routines().group_key(groups, g)
	end
	-- the unclaimed drawn group of a key
	local function keyed(key)
		for d, info in ipairs(drawn) do
			if not claimed[d] and info.key == key then
				return d
			end
		end
		return nil
	end
	-- how many of a drawn group's marks a written group holds
	local function kept(group, info)
		local have, n = {}, 0
		for _, mark in ipairs(group.rows) do
			have[mark.key] = (have[mark.key] or 0) + 1
		end
		for _, key in ipairs(info.rows) do
			if (have[key] or 0) > 0 then
				have[key], n = have[key] - 1, n + 1
			end
		end
		return n
	end
	-- whether another written group, still unmatched, holds a drawn group's name and place
	local function held_by_another(g, info)
		for other, _ in ipairs(groups) do
			if other ~= g and not match[other] and keys[other] == info.key then
				return true
			end
		end
		return false
	end
	-- the unclaimed drawn group, among those that pass and that no other written group's name and place
	-- holds, that owns the written group's first mark
	local function owner(g, passes)
		for _, mark in ipairs(groups[g].rows) do
			for d, info in ipairs(drawn) do
				if not claimed[d] and passes(info) and not held_by_another(g, info) and vim.tbl_contains(info.rows, mark.key) then
					return d
				end
			end
		end
		return nil
	end
	-- its name, with marks of it kept: the one whose header stands, else the one of its first mark
	for g, group in ipairs(groups) do
		local own = keyed(keys[g])
		if own and kept(group, drawn[own]) > 0 then
			claim(g, own)
		else
			local d = owner(g, function(info) return info.name == group.name end)
			if d then
				claim(g, d)
			end
		end
	end
	-- renamed: the one of its first mark, unless its own name and place is still drawn
	for g, _ in ipairs(groups) do
		if not match[g] and keyed(keys[g]) == nil then
			local d = owner(g, function() return true end)
			if d then
				claim(g, d)
			end
		end
	end
	-- its name and place, for a group whose marks say nothing
	for g, _ in ipairs(groups) do
		local d = not match[g] and keyed(keys[g]) or nil
		if d then
			claim(g, d)
		end
	end
	-- an empty group renamed has no mark to follow, so it follows by position: it's the unclaimed empty drawn
	-- group standing between the drawn groups its nearest matched neighbours have. each one's neighbours are
	-- read before any is taken, so the empty headers of one gap are counted against its empty drawn groups
	local gaps, gap_of = {}, {}
	for g, group in ipairs(groups) do
		if not match[g] and #group.rows == 0 then
			local low, high = 0, #drawn + 1
			for p = g - 1, 1, -1 do
				if match[p] then
					low = match[p]
					break
				end
			end
			for n = g + 1, #groups do
				if match[n] then
					high = match[n]
					break
				end
			end
			local key = low .. ":" .. high
			if not gaps[key] then
				local empty = 0
				for d = low + 1, high - 1 do
					if not claimed[d] and #drawn[d].rows == 0 then
						empty = empty + 1
					end
				end
				gaps[key] = { low = low, high = high, headers = 0, empty = empty }
			end
			gaps[key].headers = gaps[key].headers + 1
			gap_of[g] = gaps[key]
		end
	end
	local guessed = {}
	for g, group in ipairs(groups) do
		local gap = gap_of[g]
		if gap then
			for d = gap.low + 1, gap.high - 1 do
				if not claimed[d] and #drawn[d].rows == 0 then
					claim(g, d)
					if gap.headers > gap.empty then
						table.insert(guessed, { row = group.row, text = group_glyph() .. " " .. group.name .. "  stands for " ..
							group_glyph() .. " " .. drawn[d].name .. (drawn[d].held and ", the held-over group" or ", the group") ..
							" drawn here: more empty headers stand here than empty groups were drawn" })
					end
					break
				end
			end
		end
	end
	-- the marks each group holds beyond those of the group it matched
	local beyond = {}
	for g, group in ipairs(groups) do
		local own = {}
		for _, key in ipairs(match[g] and drawn[match[g]].rows or {}) do
			own[key] = (own[key] or 0) + 1
		end
		beyond[g] = {}
		for _, mark in ipairs(group.rows) do
			if (own[mark.key] or 0) > 0 then
				own[mark.key] = own[mark.key] - 1
			else
				table.insert(beyond[g], mark)
			end
		end
	end
	-- a mark beyond a group's own, taken by the drawn group it came from
	local function take(key)
		for g, _ in ipairs(groups) do
			for i, mark in ipairs(beyond[g]) do
				if mark.key == key then
					table.remove(beyond[g], i)
					return g, mark.row
				end
			end
		end
		return nil
	end
	-- a group's name in the prompt, or its name and place when another group has that name
	local function named(list, at, key)
		for i, other in ipairs(list) do
			if i ~= at and other.name == list[at].name then
				return key
			end
		end
		return list[at].name
	end
	local joined = {}
	for d, info in ipairs(drawn) do
		if not claimed[d] then
			local into, first
			for _, key in ipairs(info.rows) do
				local g, row = take(key)
				if g and (first == nil or row < first) then
					into, first = g, row
				end
			end
			if into then
				table.insert(joined, { name = named(drawn, d, info.key), into = named(groups, into, keys[into]), row = first })
			end
		end
	end
	return match, joined, guessed
end

---Read the pop-up's lines into the groups they'd write.
---
---A header starts a group, and the rows under it are its marks, each by its alias and its file. A
---line naming nothing, a row naming no file and a second group of one name are noted with why, to ask
---about. A line naming something above the first header and an alias that holds two files in one group
---are noted at the first of each, for the write to refuse; an empty row there names nothing, and goes.
---
---@param record MarksPopupBuffer The buffer the lines are in
---@param lines string[] The pop-up's lines
---@return {groups: table[], items: {row: integer, text: string}[], fresh: table<Filehash, string>, orphan: integer|nil, two: {row: integer, words: string}|nil} read
local function read_groups(record, lines)
	local read = { groups = {}, items = {}, fresh = {} }
	local current
	local named = {}
	for row, line in ipairs(lines) do
		local kind, a, b = read_line(line)
		if kind == "header" then
			current = { name = a, marks = {}, rows = {}, row = row }
			if named[a] then
				table.insert(read.items, { row = row, text = line .. "  is a second group of that name" })
			end
			named[a] = true
			table.insert(read.groups, current)
		elseif kind == "row" and current == nil then
			-- an empty row there names nothing, so nothing is lost with it
			if b ~= "" then
				read.orphan = read.orphan or row
			end
		elseif kind == "other" and current == nil then
			read.orphan = read.orphan or row
		elseif kind == "row" and b ~= "" then
			local ref, path = resolve(record, b)
			if path then
				read.fresh[ref] = path
			end
			if ref == nil then
				table.insert(read.items, { row = row, text = line .. "  names no file" })
			elseif current.marks[a] and current.marks[a] ~= ref then
				read.two = read.two or {
					row = row, words = "frogman: ⟨" .. a .. "⟩ holds two files in " .. group_glyph() .. " " .. current.name .. ": keep one.",
				}
			else
				current.marks[a] = ref
				table.insert(current.rows, { key = a .. "\0" .. tostring(ref), row = row })
			end
		elseif kind == "other" then
			table.insert(read.items, { row = row, text = line .. "  names nothing" })
		end
	end
	return read
end

---Find the groups written that moved: each matched to a drawn group, and outside some longest run of them that keeps
---the drawn order. A group in every such run stayed where it was drawn; groups swapped are each outside one.
---
---@param match table<integer, integer> A written group's place → the drawn group's (`match_groups`)
---@param count integer How many groups were written
---@return table<integer, true> moved The written groups' places that moved
local function moved_groups(match, count)
	local order = {}
	for g = 1, count do
		if match[g] then
			table.insert(order, { g = g, d = match[g] })
		end
	end
	local ending, starting, longest = {}, {}, 0
	for i = 1, #order do
		ending[i] = 1
		for j = 1, i - 1 do
			if order[j].d < order[i].d then
				ending[i] = math.max(ending[i], ending[j] + 1)
			end
		end
		longest = math.max(longest, ending[i])
	end
	for i = #order, 1, -1 do
		starting[i] = 1
		for j = i + 1, #order do
			if order[i].d < order[j].d then
				starting[i] = math.max(starting[i], starting[j] + 1)
			end
		end
	end
	-- on a longest run, and the only one there at its length, so on every one
	local on, at = {}, {}
	for i = 1, #order do
		if ending[i] + starting[i] - 1 == longest then
			on[i] = true
			at[ending[i]] = (at[ending[i]] or 0) + 1
		end
	end
	local moved = {}
	for i, item in ipairs(order) do
		if not (on[i] and at[ending[i]] == 1) then
			moved[item.g] = true
		end
	end
	return moved
end

---Check if a group the pop-up drew has this group's name and its marks, alias for alias, already.
---
---@param record MarksPopupBuffer The buffer the pop-up drew
---@param group MarksGroup A group that came into the scope since the draw
---@return boolean drawn
local function drawn_already(record, group)
	local rows = {}
	for alias, _ in pairs(group.marks) do
		local handle = routines().handle_of(group, alias)
		if handle then
			rows[alias .. "\0" .. handle.id] = true
		end
	end
	for _, drawn in ipairs(record.groups_drawn or {}) do
		local same = drawn.name == group.name and vim.tbl_count(rows) == #drawn.rows
		for _, row in ipairs(same and drawn.rows or {}) do
			same = same and rows[row] == true
		end
		if same then
			return true
		end
	end
	return false
end

---Find where a buffer's lines go when the scope its mode reads for its tab moved since they were drawn, and
---the words that say so: a tab's own marks, the tab having joined a tab session since, go into the session's
---marks, under what the join held the tab's own over as; a session's marks, the session having moved to
---another tab since and this tab kept a copy of its list, go into that copy, the marks this tab reads now.
---Held over either way.
---
---@param record MarksPopupBuffer The buffer being written
---@return {session: string, what: string, words: string}|nil moved Nil when its scope is still the one read
local function moved_to(record)
	local function name_of(pool)
		return pool and (pool.name or vim.fn.fnamemodify(pool.directory or "", ":t")) or "?"
	end
	if record.kind == "tab" then
		local join = history.data.tab_pools[record.id] and routines().join_of(record.id)
		if not join then
			return nil
		end
		local name = name_of(history.data.pools[join.session])
		return {
			session = join.session,
			what = join.what or ("tab on " .. routines().shows(vim.api.nvim_tabpage_get_win(record.id))),
			words = "frogman: tab " .. vim.api.nvim_tabpage_get_number(record.id) .. " joined the session " .. name ..
				" since these marks were drawn: they're held over in " .. name .. "'s marks, as the tab's own were.",
		}
	end
	local origin = M.origin()
	if record.kind ~= "session" or record.id == "" or not origin then
		return nil
	end
	local kind, id = routines().scope_key(record.mode or data.mode, origin)
	local copy = kind == "session" and id ~= record.id and history.data.pools[id] or nil
	if not (copy and copy.detached and copy.of == record.id) then
		return nil
	end
	local session = history.data.pools[record.id]
	local name = name_of(session)
	local there = session and next(session.tabs)
	local where = there and vim.api.nvim_tabpage_is_valid(there) and (" to tab " .. vim.api.nvim_tabpage_get_number(there)) or ""
	local here = vim.api.nvim_tabpage_get_number(vim.api.nvim_win_get_tabpage(origin))
	return {
		session = id,
		what = name .. ", written after it moved" .. where,
		words = "frogman: " .. name .. " moved" .. where .. " since these marks were drawn: they're held over in tab " ..
			here .. "'s copy, " .. copy.name .. ", the marks this tab reads now.",
	}
end

---Write a scope's buffer's lines into the scope.
---
---Lines that hold no edits write nothing. A row naming a file above the first header, or an alias that
---holds two files in one group, refuses the write, and so does a window or a tab the scope was for
---that's gone; an empty row above the first header names nothing, and goes.
---A line naming nothing, a row naming no file, a second group of one name, and a header deleted with
---some of its rows left under another group's are asked about in one prompt, in the lines' order, and
---No writes nothing, the cursor on the first of them. The lines are the scope's groups from then on, in
---order, and what came in since the pop-up was drawn stays below them, with marks or none: a group held
---over meanwhile, and a load's, held over under its header, but for one a group the pop-up drew has
---already, by its name and its marks. A row it drew follows its file through a move.
---Each group written keeps what the drawn group it matches was (`match_groups`): held over, unless it's
---first or moved (`moved_groups`), and the default group while its name stands.
---
---@param record MarksPopupBuffer The buffer to write
---@return boolean written
local function write(record)
	if not edited(record) then
		set_modified() -- lines typed back as they were drawn leave the drafts alone to keep it modified
		return true -- the drafts are written by leaving
	end
	if scope_gone(record.kind, record.id) then
		vim.notify("frogman: the " .. record.kind .. " these marks are for is gone, so they aren't written.", vim.log.levels.WARN)
		return false
	end
	local read = read_groups(record, vim.api.nvim_buf_get_lines(record.buf, 0, -1, false))
	local refused = read.orphan and (read.two == nil or read.orphan < read.two.row) and {
		row = read.orphan, words = "frogman: the marks above the first group's header have no group: put a header back above them, or delete them.",
	} or read.two
	if refused then
		vim.notify(refused.words, vim.log.levels.WARN)
		if is_open() and open.shown == record then
			vim.api.nvim_win_set_cursor(open.win, { refused.row, 0 })
		end
		return false
	end
	local groups, items, fresh = read.groups, read.items, read.fresh
	local drawn_groups = record.groups_drawn or {}
	local match, joined, guessed = match_groups(groups, drawn_groups)
	local moved = moved_groups(match, #groups)
	for _, gone in ipairs(joined) do
		table.insert(items, { row = gone.row,
			text = group_glyph() .. " " .. gone.name .. "'s header is gone: its rows join " .. group_glyph() .. " " .. gone.into })
	end
	vim.list_extend(items, guessed)
	table.sort(items, function(x, y) return x.row < y.row end)
	if #items > 0 and vim.fn.confirm("frogman: before writing the marks:\n" ..
			table.concat(vim.tbl_map(function(item) return item.text end, items), "\n") ..
			"\nWrite as it stands?", "&Yes\n&No", 2) ~= 1 then
		if is_open() and open.shown == record then
			vim.api.nvim_win_set_cursor(open.win, { items[1].row, 0 })
		end
		return false
	end
	for _, path in pairs(fresh) do
		history.register_filepath(path) -- a file typed by its path, known from now on
	end
	local elsewhere = moved_to(record)
	if elsewhere then
		-- the scope its mode reads for its tab moved since the marks were drawn: the lines are held over where
		-- the mode reads now, and it says so
		local held = {}
		for _, group in ipairs(groups) do
			local marks = {}
			for alias, ref in pairs(group.marks) do
				local handle = type(ref) == "number" and history.handles.get(ref) or history.handles.of_hash(ref)
				if handle then
					marks[alias] = handle.id
				end
			end
			table.insert(held, { name = group.name, marks = marks })
		end
		routines().hold_over(elsewhere.session, held, elsewhere.what)
		vim.notify(elsewhere.words, vim.log.levels.INFO)
		draw_into(record, nil)
		M.rescope()
		return true
	end
	local scope = routines().scope(record.kind, record.id, true)
	-- what came in since the draw: a group held over, or a load's, with marks or none, but for one the
	-- pop-up drew already and the default with none, which goes as a load's does
	local arrived = vim.tbl_filter(function(group)
		return not record.drawn[group] and (group.held or group.loaded ~= nil) and not drawn_already(record, group)
			and not (group.default and next(group.marks) == nil)
	end, scope.groups)
	scope.groups = {}
	for g, group in ipairs(groups) do
		local marks = {}
		for alias, ref in pairs(group.marks) do
			-- a path typed there is known by now, under the hash it was read by
			local handle = type(ref) == "number" and history.handles.get(ref) or history.handles.of_hash(ref)
			if handle then
				marks[alias] = handle.id
			end
		end
		-- a held-over group stays held over, renamed or not, unless it's first or you moved it, up or down,
		-- keeping the name an empty one came from; the default group stays the default while its name stands,
		-- and is one typed in once it's renamed
		local was = match[g] and drawn_groups[match[g]] or {}
		local held = (g > 1 and was.held and not moved[g]) or nil
		table.insert(scope.groups, {
			name = group.name, marks = marks, held = held, default = (was.default and was.name == group.name) or nil,
			from = held and was.from or nil,
		})
	end
	-- what came in since the draw stays below: a load's marks held over under its header, as a load
	-- holds over what it replaces
	for _, group in ipairs(arrived) do
		if not group.held then
			local taken = {}
			for _, other in ipairs(scope.groups) do
				taken[other.name] = true
			end
			group.from = next(group.marks) == nil and group.name or nil -- what an empty one is known by
			group.name = require('frogman.held').held_header(group.loaded or "loaded", taken)
			group.held = true
		end
		group.default, group.loaded = nil, nil -- held over, it's no default
		table.insert(scope.groups, group)
	end
	routines().hold_scope(record.kind, record.id)
	draw_into(record, nil)
	repaint()
	return true
end

---Let a scope's buffer go, frogman wiping it itself, its scope gone: nothing is kept of it. One Neovim won't delete
---just then stays its scope's, for the next let-go.
---@param record MarksPopupBuffer The buffer to let go
---@return nil
local function wipe(record)
	if vim.api.nvim_buf_is_valid(record.buf) then
		wiping[record.buf] = true
		pcall(vim.api.nvim_buf_delete, record.buf, { force = true })
		wiping[record.buf] = nil
	end
	if not vim.api.nvim_buf_is_valid(record.buf) and bufs[record.key] == record then
		bufs[record.key] = nil
	end
end

---Keep what a scope's buffer holds as Neovim throws it away, by a `:q!`, `:e!` or a forced close: its lines and
---its undo history, written to a file of Neovim's own, for when that scope's buffer is made again; the buffer
---itself goes once Neovim is done with it, unless it's loaded again, as `:e!` reads it back. Not while Neovim
---exits, nor for one frogman wipes itself.
---@param record MarksPopupBuffer The scope's buffer Neovim throws away
---@param buf Bufnr The buffer being thrown away
---@return nil
local function keep(record, buf)
	if exiting or wiping[buf] or bufs[record.key] ~= record then
		return
	end
	bufs[record.key] = nil
	if kept[record.key] and kept[record.key].undo then
		os.remove(kept[record.key].undo) -- an earlier keep not given back, a draw having raised: this one replaces it
	end
	local undo = vim.fn.tempname()
	local written = pcall(vim.api.nvim_buf_call, buf, function()
		vim.cmd("silent wundo! " .. vim.fn.fnameescape(undo))
	end)
	kept[record.key] = { lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false), undo = written and undo or nil,
		kind = record.kind, id = record.id }
	vim.schedule(function()
		if vim.api.nvim_buf_is_valid(buf) and not vim.api.nvim_buf_is_loaded(buf) then
			wiping[buf] = true
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
			wiping[buf] = nil
		end
	end)
end

---Give a scope's buffer back what was kept of it as Neovim threw it away, its lines and its undo history, then
---draw its scope as it stands, the edits it held dropped as one undo step; or draw it for the first time.
---@param record MarksPopupBuffer The scope's buffer, made again
---@param conflict {alias: string, id: HandleId}|nil The alias an add found taken and the incoming file's handle, or nil
---@return nil
local function restore(record, conflict)
	local back = kept[record.key]
	bufs[record.key] = record
	if back == nil then
		draw_into(record, conflict, true)
		return
	end
	put_lines(record, back.lines, true)
	if back.undo then
		pcall(vim.api.nvim_buf_call, record.buf, function()
			vim.cmd("silent rundo " .. vim.fn.fnameescape(back.undo))
		end)
	end
	draw_into(record, conflict)
	kept[record.key] = nil -- given back once drawn: a draw that raises leaves it kept for the next make
	if back.undo then
		os.remove(back.undo)
	end
end

---Make a scope's buffer: drawn as its scope stands, or given back what was kept of an earlier one first.
---A draw that raises takes the buffer with it, so nothing half made stays.
---@param kind "window"|"tab"|"session" The scope's kind
---@param id any Its window, tab or session's pool id
---@param conflict {alias: string, id: HandleId}|nil The alias an add found taken and the incoming file's handle, or nil
---@return MarksPopupBuffer record
local function make(kind, id, conflict)
	local buf = vim.api.nvim_create_buf(false, false)
	vim.bo[buf].modifiable = true -- an editable view: on, whatever a new buffer takes from a global nomodifiable
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].swapfile = false
	vim.bo[buf].bufhidden = "hide"
	vim.api.nvim_buf_set_name(buf, NAME .. "/" .. kind .. "/" .. buf)
	---@type MarksPopupBuffer
	local record = { buf = buf, kind = kind, id = id, key = key_of(kind, id), mode = data.mode, names = {}, paths = {}, states = {} }
	local drawn, problem = pcall(restore, record, conflict)
	if not drawn then
		wipe(record)
		error(problem, 0)
	end
	vim.bo[buf].filetype = "frogman-marks" -- once drawn, so the keys its filetype maps find it drawn
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = "frogman",
		buffer = buf,
		callback = function()
			set_modified() -- lines typed back as they were drawn hold nothing
			decorate()
		end,
		desc = "Draw the marks again",
	})
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = "frogman",
		buffer = buf,
		callback = function()
			write(record)
		end,
		desc = "Write the marks",
	})
	vim.api.nvim_create_autocmd("BufUnload", {
		group = "frogman",
		buffer = buf,
		callback = function(args)
			keep(record, args.buf)
		end,
		desc = "Keep what the marks pop-up held",
	})
	-- `:e!`: Neovim threw its text away first (its BufUnload kept it); it comes back, and the scope is drawn
	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = "frogman",
		buffer = buf,
		callback = function()
			restore(record, nil)
		end,
		desc = "Draw the marks again",
	})
	return record
end

---Get a scope's buffer, making it when there's none.
---@param kind "window"|"tab"|"session" The scope's kind
---@param id any Its window, tab or session's pool id
---@param conflict {alias: string, id: HandleId}|nil The alias an add found taken and the incoming file's handle, or nil
---@return MarksPopupBuffer record
---@return boolean made Whether it was made now
local function buffer_for(kind, id, conflict)
	local record = bufs[key_of(kind, id)]
	if record and vim.api.nvim_buf_is_loaded(record.buf) then
		return record, false
	end
	if record then
		wipe(record) -- unloaded, its text gone
	end
	return make(kind, id, conflict), true
end

---Show a scope's buffer in the float, the one it showed hidden, its history with it.
---@param record MarksPopupBuffer The scope's buffer to show
---@return nil
local function show(record)
	local was = open.shown
	if was ~= record and vim.api.nvim_buf_is_loaded(was.buf) then
		vim.bo[was.buf].bufhidden = "hide"
	end
	open.shown = record
	vim.api.nvim_win_set_buf(open.win, record.buf)
	set_modified()
	decorate()
	show_mode_line()
end

---Write the shown buffer when it holds edits, then every draft, each shown in turn in its mode and checked.
---
---One that's refused or answered No stays shown, in its mode, and the drafts after it wait. With
---every one written, the mode is the one the screen was in.
---
---@return boolean written
local function write_all()
	local mode = data.mode
	if not write(open.shown) then
		return false
	end
	for _, record in ipairs(drafts()) do
		data.mode = record.mode
		show(record)
		if not write(record) then
			repaint() -- its mode shows
			return false
		end
	end
	if data.mode ~= mode then
		data.mode = mode
		repaint() -- the mode the screen was in shows again
	end
	return true
end

---Close the pop-up's float; the buffer it shows is hidden, its history with it.
---@return nil
local function close()
	if is_open() then
		vim.api.nvim_win_close(open.win, false)
	end
end

---Let go the buffers whose window or tab is gone, and the history kept of one, once the float is closed: while
---it's open they wait, so leaving can say whose edits it drops (`leave_gone`), and its close lets them go.
---@return nil
local function let_go_gone()
	if is_open() then
		return
	end
	for _, record in pairs(vim.tbl_values(bufs)) do
		if scope_gone(record.kind, record.id) then
			wipe(record)
		end
	end
	for key, back in pairs(kept) do
		if scope_gone(back.kind, back.id) then
			if back.undo then
				os.remove(back.undo)
			end
			kept[key] = nil
		end
	end
end

---Once the float has closed: the edits the drafts still hold are dropped, each as an undo step, and the
---buffers whose scope is gone go. The buffer it showed went with it when it held edits, its history kept.
---@return nil
local function closed()
	open = nil
	for _, record in pairs(vim.tbl_values(bufs)) do
		if scope_gone(record.kind, record.id) then
			wipe(record)
		elseif edited(record) then
			draw_into(record, nil)
		end
	end
	set_modified()
end

---Do what the float's close would have when it closed without its events, by `noautocmd` or while frogman was
---off: the edits the drafts still hold dropped, each as an undo step. A float still opening, its window not yet
---known, isn't one.
---@return nil
local function closed_unseen()
	if open ~= nil and open.win ~= nil and not is_open() then
		closed()
	end
end

---Check if the marks pop-up has edits not written yet: on its screen, or in a draft.
---@return boolean dirty
function M.dirty()
	closed_unseen()
	return holds_edits()
end

---Get the window the pop-up acts on: the one it was opened from, while it's there.
---@return WinId|nil winid
function M.origin()
	if open and vim.api.nvim_win_is_valid(open.origin) then
		return open.origin
	end
	return nil
end

---Show the scope the pop-up's mode reads for its window now, when that's another than the one it shows: a load
---of another-named session, or the window's tab joining or leaving a tab session, changes it. Unedited, the
---pop-up shows that scope's buffer, drawn as the scope stands; edited, it stays as it is, and its write goes
---where the mode reads, a join's held over (`write`).
---
---@return nil
function M.rescope()
	closed_unseen()
	if not is_open() or not M.origin() then
		return
	end
	local kind, id = routines().scope_key(data.mode, open.origin)
	local record = open.shown
	if key_of(kind, id) == record.key or edited(record) then
		return
	end
	local target, made = buffer_for(kind, id)
	if not made and not edited(target) then
		draw_into(target, nil) -- as its scope stands now
	end
	target.mode = data.mode
	show(target)
end

---Open the marks pop-up on the scope the current mode reads for the window you're in, showing that scope's
---buffer, its lines and history as they were left.
---
---With edits not written yet, the pop-up stays as it is, focused, and says so. With a conflict, the
---alias the add was for shows the incoming file and the one already set, to settle and write.
---
---@param opts {conflict: {alias: string, id: HandleId}|nil}|nil Options: `conflict`, the alias an add found taken and the incoming file's handle
---@return nil
function M.open(opts)
	opts = opts or {}
	closed_unseen()
	if is_open() then
		if holds_edits() then
			vim.api.nvim_set_current_win(open.win)
			vim.notify(refusal(), vim.log.levels.WARN)
			return
		end
		close()
	end
	local origin = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_config(origin).relative ~= "" then
		origin = require('frogman.domains.navigation.routines').find_most_recent_tracked_window() or origin
	end
	local kind, id = routines().scope_key(data.mode, origin)
	local record, made = buffer_for(kind, id, opts.conflict)
	record.mode = data.mode
	if not made and (opts.conflict or not edited(record)) then
		draw_into(record, opts.conflict) -- as its scope stands now: a step when it changed while hidden
	end
	open = { origin = origin, shown = record }
	local opened, win = pcall(require('frogman.domains.ui.view').float, record.buf, {
		title = "Marks", size = require('frogman.configs').marks_popup, closed = closed,
	})
	if not opened then
		open = nil
		if made then
			keep(record, record.buf) -- its lines and history kept, as a throw-away keeps them, for the next open
			wipe(record) -- and the buffer made for it goes with it
		end
		error(win, 0)
	end
	open.win = win
	set_modified()
	decorate()
	show_mode_line()
	if opts.conflict then
		for i, line in ipairs(vim.api.nvim_buf_get_lines(record.buf, 0, -1, false)) do
			local kind_of, alias = read_line(line)
			if kind_of == "row" and alias == opts.conflict.alias then
				vim.api.nvim_win_set_cursor(win, { i, 0 })
				break
			end
		end
	end
end

---Leave the pop-up once the window it was opened from is gone: the buffers whose scope is still there are
---written, each checked as usual, then the edits of those whose scope is gone are dropped with them, and one
---WARN says what happened. A write that's refused or answered No leaves it open, showing the lines it refused,
---nothing dropped yet.
---@return nil
local function leave_gone()
	local mode = data.mode
	local records = edited(open.shown) and { open.shown } or {}
	vim.list_extend(records, drafts())
	local dropped, written = {}, {}
	for _, record in ipairs(records) do
		if not scope_gone(record.kind, record.id) then
			data.mode = record.mode
			if open.shown ~= record then
				show(record)
			end
			if not write(record) then
				repaint() -- its mode shows
				return
			end
			written[record.kind] = true
		end
	end
	if data.mode ~= mode then
		data.mode = mode
		repaint() -- the mode the screen was in shows again
	end
	for _, record in ipairs(records) do
		if scope_gone(record.kind, record.id) then
			dropped[record.kind] = true
			if record ~= open.shown then
				wipe(record) -- its edits go with it, so nothing holds the shown buffer modified
			end
		end
	end
	local gone = vim.tbl_filter(function(kind)
		return kind == "window" or (kind == "tab" and dropped.tab)
	end, { "window", "tab" })
	local parts = {}
	if dropped.window or dropped.tab then
		table.insert(parts, #gone == 1 and "its edits are dropped" or "their edits are dropped")
	end
	local names = vim.tbl_filter(function(name) return name end, {
		written.window and "the window's" or false, written.tab and "the tab's" or false, written.session and "the session's" or false,
	})
	if #names > 0 then
		table.insert(parts, require('frogman.domains.ledger').routines.joined(names) .. " are written")
	end
	if #parts > 0 then
		vim.notify("frogman: the " .. table.concat(gone, " and the ") .. " these marks were for " .. (#gone == 1 and "is" or "are") ..
			" gone: " .. table.concat(parts, "; ") .. ".", vim.log.levels.WARN)
	end
	if scope_gone(open.shown.kind, open.shown.id) then
		wipe(open.shown) -- the float goes with the buffer it shows
	else
		set_modified()
	end
	close()
end

---Write the pop-up's lines when they were edited, and every draft, then leave it; once the window it was
---opened from is gone, write what still has its scope and drop the rest (`leave_gone`).
---
---A write that's refused or answered No leaves it open, showing the lines it refused.
---
---@return nil
function M.leave()
	if not is_open() then
		return
	end
	if M.origin() == nil then
		leave_gone()
		return
	end
	if write_all() then
		close()
	end
end

---Get the file the row under the cursor names.
---@return HandleId|Filehash|nil ref The file's handle, or its hash while the registry doesn't know it
---@return Filepath|nil filepath Its path, when the registry doesn't know it
local function row_file()
	local kind, _, file = read_line(vim.api.nvim_get_current_line())
	if kind ~= "row" or file == "" then
		return nil
	end
	return resolve(open.shown, file)
end

---Get the row under the cursor, its alias and its file, writing the pop-up first when it was edited.
---
---The row is read before the write, which draws the lines again in the aliases' order, so what's acted
---on is the row you were on, and a path typed there is registered by the write.
---
---@return string|nil alias
---@return HandleId|nil id The file's handle, nil when the write was refused or answered No, or the row names no file
local function written_row()
	local kind, alias, file = read_line(vim.api.nvim_get_current_line())
	local ref = (kind == "row" and file ~= "") and (resolve(open.shown, file)) or nil
	if edited(open.shown) and not write(open.shown) then
		return nil, nil
	end
	-- a path typed there has its handle once the write registered it; a row the write left out has none
	local handle = type(ref) == "number" and history.handles.get(ref) or (ref and history.handles.of_hash(ref))
	return alias, handle and handle.id or nil
end

---Jump to the row's file in the window the pop-up was opened from, as a mark's jump goes.
---
---The pop-up is written first when it was edited, and stays when that's refused. With `stay`, the
---pop-up stays open, its drafts held; leaving, every draft is written first, as `q` writes them.
---
---@param stay boolean|nil Whether the pop-up stays open once the jump is made
---@return nil
function M.act(stay)
	if not is_open() then
		return
	end
	local alias, id = written_row()
	local origin = M.origin()
	if id == nil or origin == nil or (not stay and not write_all()) then
		return
	end
	local here = vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(origin)
	require('frogman.domains.window').routines.jump_to_mark(origin, id, "⟨" .. alias .. "⟩")
	if stay and open and open.win and vim.api.nvim_win_is_valid(open.win) then
		vim.api.nvim_set_current_win(here)
	elseif not stay then
		close()
	end
end

---Make the row's file the primary of the window the pop-up was opened from, at the front of its
---queue, and switch the primary on.
---
---The pop-up is written first when it was edited, and stays when that's refused.
---
---@return nil
function M.make_primary()
	if not is_open() then
		return
	end
	local _, id = written_row()
	local origin = M.origin()
	local triquetra = origin and require('frogman.domains.window').data.get_window_triquetra(origin)
	if id == nil or triquetra == nil then
		return
	end
	local at = vim.fn.index(triquetra.primary_buffer, id)
	if at ~= -1 then
		triquetra:queue_remove(at + 1)
	end
	triquetra:queue_insert(1, id)
	triquetra.primary_enabled = true
	require('frogman.domains.ui.sm').loop:to(require('frogman.domains.ui.states').LOOP.SELF)
	vim.cmd("redrawstatus!")
	vim.cmd("redrawtabline")
	vim.notify("frogman: " .. require('frogman.domains.ui').routines.get_smart_basename(id) ..
		" is the primary of window " .. vim.api.nvim_win_get_number(origin) .. ".", vim.log.levels.INFO)
end

---Pick one entry through telescope.
---
---@param title string The picker's prompt title
---@param items string[] The entries to pick from
---@param done fun(item: string) Called with the entry picked
---@return boolean picking False when telescope isn't installed
local function pick_one(title, items, done)
	local ok, pickers = pcall(require, "telescope.pickers")
	if not ok then
		vim.notify("frogman: the marks pop-up picks through telescope, and telescope.nvim isn't installed.", vim.log.levels.WARN)
		return false
	end
	local finders = require("telescope.finders")
	local sorters = require("telescope.config").values
	local actions = require("telescope.actions")
	local state = require("telescope.actions.state")
	pickers.new({}, {
		prompt_title = title,
		finder = finders.new_table({ results = items }),
		sorter = sorters.generic_sorter({}),
		attach_mappings = function(prompt_bufnr, map)
			require('frogman.domains.ui').routines.pick_one_only(map) -- one alias, single-select
			actions.select_default:replace(function()
				local entry = state.get_selected_entry()
				actions.close(prompt_bufnr)
				if entry then
					done(entry[1] or entry.value)
				end
			end)
			return true
		end,
	}):find()
	return true
end

---Pick a file through telescope's find_files, one file.
---@param done fun(path: string) Called with the path of the file picked
---@return nil
local function pick_file(done)
	require('frogman.domains.ui').routines.pick_files(false, function(paths)
		if paths[1] then
			done(paths[1])
		end
	end)
end

---Add a mark through telescope: an alias, then a file, as a row of the cursor's group.
---
---The row goes after the alias's own when the group has one, which then shows as already set and the
---new one as incoming, until one is deleted and the pop-up written.
---
---@return nil
function M.add_row()
	if not is_open() then
		return
	end
	local record, row = open.shown, vim.api.nvim_win_get_cursor(0)[1]
	local buf = record.buf
	pick_one("Alias", aliases(), function(alias)
		pick_file(function(path)
			if not is_open() or open.shown ~= record then
				return
			end
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			-- the cursor's group: from its header, or the first one
			local top, bottom = 1, #lines
			for i = row, 1, -1 do
				if read_line(lines[i]) == "header" then
					top = i
					break
				end
			end
			for i = top + 1, #lines do
				if read_line(lines[i]) == "header" then
					bottom = i - 1
					break
				end
			end
			-- the picked file by its handle, or by its hash while the registry doesn't know it
			local filehash = history.routines.get_filehash(vim.fn.fnamemodify(path, ":p"))
			local ref = history.get_handle_from_hash(filehash) or filehash
			local text = vim.fn.fnamemodify(path, ":.")
			if record.names[text] and record.names[text] ~= ref then
				text = "./" .. text
			end
			local at = bottom
			for i = top + 1, bottom do
				local kind, a, file = read_line(lines[i])
				if kind == "row" and a == alias then
					if file == "" then
						vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { alias .. " -> " .. text })
						return
					end
					local held = resolve(record, file)
					if held then
						record.states[alias .. "\0" .. held] = "already set"
					end
					at = i
					break
				end
			end
			record.states[alias .. "\0" .. ref] = "incoming"
			vim.api.nvim_buf_set_lines(buf, at, at, false, { alias .. " -> " .. text })
			decorate()
		end)
	end)
end

---Switch the mode from inside the pop-up, and show the new mode's scope's buffer.
---
---The buffer it leaves stays a draft when it holds edits, and the new scope's comes back with its lines and
---history as they were left, or is made.
---A switch is refused while an alias holds two files in the edits it would keep, and with the window
---it was opened from gone; each says so.
---
---@param mode "window"|"tab"|"session" The mode to switch to
---@return boolean switched
function M.switch_mode(mode)
	if not M.origin() then
		vim.notify("frogman: the window these marks are for is gone.", vim.log.levels.WARN)
		return false
	end
	local kind, id = routines().scope_key(mode, open.origin)
	local record = open.shown
	if kind == record.kind and id == record.id then
		data.mode, record.mode = mode, mode -- a tab session's tab and session modes read one scope
		decorate()
		return true
	end
	if edited(record) then
		-- the lines kept as a draft can't hold two files for an alias
		local two = read_groups(record, vim.api.nvim_buf_get_lines(record.buf, 0, -1, false)).two
		if two then
			vim.notify(two.words, vim.log.levels.WARN)
			vim.api.nvim_win_set_cursor(open.win, { two.row, 0 })
			return false
		end
	end
	local target, made = buffer_for(kind, id)
	if not made and not edited(target) then
		draw_into(target, nil) -- as its scope stands now: a step when it changed while hidden
	end
	data.mode, target.mode = mode, mode
	show(target)
	return true
end

---Map the pop-up's keys on its buffer, from `keymaps.views`.
---
---Each key that acts begins a step of its own, about the window the pop-up was opened from. A key set
---to false isn't mapped.
---
---@param buf Bufnr The scope's buffer to map the keys on
---@return nil
function M.map_keys(buf)
	local keys = require('frogman.configs').keymaps.views or {}
	local function map(lhs, fn, desc)
		if not lhs then
			return
		end
		vim.keymap.set("n", lhs, function()
			require('frogman.domains.ledger').run_key(lhs, M.origin(), fn)
		end, { buffer = buf, desc = desc })
	end
	map(keys.write, function() vim.cmd("write") end, "Write the marks")
	map(keys.leave, M.leave, "Write the marks and leave")
	map(keys.leave_too, M.leave, "Write the marks and leave")
	map(keys.act, function() M.act(false) end, "Jump to the line's mark and leave")
	map(keys.act_and_stay, function() M.act(true) end, "Jump to the line's mark and stay")
	map(keys.add, M.add_row, "Add a mark through the picker")
	map(keys.make_primary, M.make_primary, "Make the line's file the primary")
	map(keys.search_word, function()
		-- the row's file by its hash, a No Name text's too, across its moves and reopens; a row drawn for
		-- a file let go since names nothing
		local ref, filepath = row_file()
		local filehash = ref
		if type(ref) == "number" then
			filehash = history.get_hash_from_handle(ref)
		end
		if filehash then
			require('frogman.domains.ui.trail').follow(filehash, filepath)
		end
	end, "Search the trail for the line's file")
end

---Keep the whole editor's session's buffer with its scope as a whole-editor save names the session anew, its first
---save or a save as another: the marks it shows are the same, so its lines and its history go on under the name
---saved, and a buffer kept under that name before goes, the save writing over that session's file. A load starts
---the scope over instead: the buffer of the session it leaves stays under that session's name.
---@param before {name: string|nil, directory: string}|nil The whole editor's session before the save
---@return nil
function M.renamed(before)
	local from, to = "session\0\0" .. editor_part(before), key_of("session", "")
	if from == to then
		return
	end
	if bufs[to] then
		wipe(bufs[to])
	end
	if kept[to] and kept[to].undo then
		os.remove(kept[to].undo)
	end
	kept[to], kept[from] = kept[from], nil
	local record = bufs[from]
	if record then
		bufs[from], bufs[to], record.key = nil, record, to
	end
end

---Let go, once the editor is past what closed them, the buffers whose window or tab is gone, and the history kept
---of one: at the events of their close, and at the cleanup pass that finds one closed without its events.
---@return nil
function M.let_go_gone()
	vim.schedule(let_go_gone)
end

---Get the buffer the float shows, while it's open.
---@return Bufnr|nil buf
function M.buffer()
	return is_open() and open.shown.buf or nil
end

---Get the float's window, while it's open.
---@return WinId|nil win
function M.window()
	return is_open() and open.win or nil
end

---Create the pop-up's autocmds in frogman's augroup: a window's or tab's buffer goes with it once the float is
---closed; `:set nomodified` on the shown buffer, which fires no event of its own, draws its scope again
---once Neovim settles, the flag set again while a draft is held; and nothing is kept while Neovim exits.
---
---@param group integer The frogman augroup
---@return nil
function M.init_autocmds(group)
	vim.api.nvim_create_autocmd({ "WinClosed", "TabClosed" }, {
		group = group,
		callback = function()
			M.let_go_gone()
		end,
	})
	vim.api.nvim_create_autocmd("SafeState", {
		group = group,
		callback = function()
			local record = is_open() and open.shown or nil
			if record and record.flag and vim.api.nvim_buf_is_loaded(record.buf) and not vim.bo[record.buf].modified then
				draw_into(record, nil) -- a reset by hand: the screen drawn again, a step
			end
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			exiting = true
		end,
	})
end

return M
