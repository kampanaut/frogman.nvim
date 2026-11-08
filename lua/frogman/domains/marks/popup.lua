---The marks pop-up.
---
---One editable floating window on the marks of a scope: the scope the current mode reads for the
---window it's opened from. A group is a header line, `❖ main`, and its marks are rows under it,
---`a -> b.txt`, one for every alias the config has, then the group's unassigned ones. What the rows
---stand for is drawn around them as virtual text, in the trail's language. The lines are written
---back into the scope at `:w`, after the checks.

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

---The pop-up that's open: its buffer, its window, the window it was opened from, the scope it
---shows, what each drawn name stands for, the rows drawn as incoming or already set, each group
---drawn, by itself and by its key and rows, for the write to know it again, the drafts of the scopes
---a mode switch left with edits, and the lines the screen's scope was drawn as.
---@type {buf: Bufnr, win: WinId, origin: WinId, kind: string, id: any, names: table<string, HandleId>, paths: table<string, string>, states: table<string, string>, drawn: table<MarksGroup, true>, groups_drawn: {key: string, name: string, held: boolean|nil, default: boolean|nil, from: string|nil, rows: string[]}[], drafts: table[], drawn_lines: string[]|nil}|nil
local open = nil

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

---Check if the pop-up is open, its buffer still there.
---@return boolean
local function is_open()
	return open ~= nil and vim.api.nvim_buf_is_valid(open.buf)
end

---Check if the screen holds edits: the buffer modified, and its lines not the ones their scope was
---drawn as, a conflict waiting to be settled counting as edits.
---
---The modified flag counts as much as the lines: the flag reset by hand, `:set nomodified` or `:e!`,
---leaves nothing on the screen to write, `:w`, `:q` and `q` writing none of it until it's edited again.
---
---@return boolean edited
local function screen_edited()
	return vim.bo[open.buf].modified
		and (open.drawn_lines == nil or not vim.deep_equal(vim.api.nvim_buf_get_lines(open.buf, 0, -1, false), open.drawn_lines))
end

---Check if the pop-up holds anything not written: edits on its screen, or a draft.
---@return boolean holds
local function holds_edits()
	return screen_edited() or #open.drafts > 0
end

---Mark the pop-up modified while it holds anything not written, so `:q` refuses until it's written or
---dropped; lines typed back as they were drawn leave it unmodified.
---@return nil
local function set_modified()
	vim.bo[open.buf].modified = holds_edits()
end

---Put lines on the screen as frogman draws them, the undo history starting from them, so an undo takes
---back only what's typed since, never a draw: not a write's, not a scope's that changed, not another
---scope's lines a mode switch left.
---@param lines string[] The lines to draw
---@return nil
local function put_lines(lines)
	local levels = vim.bo[open.buf].undolevels
	vim.bo[open.buf].undolevels = -1
	local put, problem = pcall(vim.api.nvim_buf_set_lines, open.buf, 0, -1, false, lines)
	vim.bo[open.buf].undolevels = levels
	if not put then
		error(problem, 0)
	end
end

---Redraw the UI once marks or the mode changed.
---@return nil
local function repaint()
	require('frogman.domains.ui.sm').loop:to(require('frogman.domains.ui.states').LOOP.SELF)
end

---Check if the marks pop-up has edits not written yet: on its screen, or in a draft.
---@return boolean dirty
function M.dirty()
	return is_open() and holds_edits()
end

---Check if the marks pop-up is the window you're in.
---@return boolean current
function M.is_current()
	return is_open() and vim.api.nvim_get_current_buf() == open.buf
end

---The words the mark keys say while the pop-up has edits not written yet
local DIRTY = "frogman: the marks pop-up has edits not written yet: write them with :w, or leave them, first."

---Refuse a mark key while the pop-up has edits not written yet, saying so.
---@return boolean refused
function M.refuse_if_dirty()
	if M.dirty() then
		vim.notify(DIRTY, vim.log.levels.WARN)
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
---@param conflict {alias: string, id: HandleId}|nil
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
---@param line string
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
---A file the registry knows is given by its handle; one it doesn't yet, by its path's hash, until the
---write registers the path.
---
---@param file string The row's file as written
---@return HandleId|Filehash|nil ref The file's handle, or its hash while the registry doesn't know it
---@return string|nil path A path to register as the write goes through, when the registry has none
local function resolve(file)
	-- a row it drew follows its file, by the file's handle, through a move since
	local drawn = open.names[file]
	if drawn then
		-- a file let go since and known again has a handle of its own, which the row finds by its path
		local handle = history.handles.follow(drawn)
			or history.handles.get(history.get_handle_from_filepath(open.paths and open.paths[file]))
		return handle and handle.id or drawn, nil
	end
	local path = vim.fn.fnamemodify(file, ":p")
	local id = history.get_handle_from_filepath(path)
	if id then
		return id, nil
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
	local buf = open.buf
	local glyphs = require('frogman.domains.ui').routines.glyphs()
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local mode_line = "marks" .. glyphs.dot .. open.kind
	if #open.drafts > 0 then
		-- the scopes a mode switch left with edits, still to be written
		mode_line = mode_line .. glyphs.dot .. (#open.drafts == 1 and "draft: " or "drafts: ") ..
			table.concat(vim.tbl_map(function(draft) return draft.kind end, open.drafts), ", ")
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
			local ref = resolve(file)
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
			local state = ref and open.states[alias .. "\0" .. ref]
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

---Put the scope's marks in the pop-up's lines, as they are now, the undo history starting there.
---@param conflict {alias: string, id: HandleId}|nil
---@return nil
local function redraw(conflict)
	local lines, names, states, drawn, paths = draw(open.kind, open.id, conflict)
	open.names, open.states, open.groups_drawn, open.paths = names, states, drawn, paths
	-- what the write rebuilds from the lines: a group that comes in after stays
	local scope = data.scopes[open.kind][open.id]
	open.drawn = {}
	for _, group in ipairs(scope and scope.groups or {}) do
		open.drawn[group] = true
	end
	put_lines(lines)
	open.drawn_lines = conflict == nil and lines or nil -- a conflict waits to be settled and written, as edits do
	set_modified()
	decorate()
	show_mode_line()
end

---Draw the pop-up again when its scope changed and the screen holds no edits, so it shows what's there.
---
---@param kind "window"|"tab"|"session" The kind of the scope that changed
---@param id any Its window, tab or session's pool id
---@return nil
function M.scope_changed(kind, id)
	if is_open() and open.kind == kind and open.id == id and not screen_edited() then
		redraw(nil)
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
---and place. One renamed with every mark changed, or typed in under a new name, matches none. A drawn
---group none matched had its header deleted, and its marks still there, beyond another group's own,
---joined that group.
---
---@param groups {name: string, rows: {key: string, row: integer}[]}[] The groups written, in order, each mark by its key and its line
---@param drawn {key: string, name: string, rows: string[]}[] The groups drawn, in order
---@return table<integer, integer> match A written group's place → the drawn group's
---@return {name: string, into: string, row: integer}[] joined Each drawn group whose header is gone with marks left: its name, the group they joined and the first one's line, a name with its place, `x/2`, when another group has it
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
	return match, joined
end

---Read the pop-up's lines into the groups they'd write.
---
---A header starts a group, and the rows under it are its marks, each by its alias and its file. A
---line naming nothing, a row naming no file and a second group of one name are noted with why, to ask
---about. A line naming something above the first header and an alias that holds two files in one group
---are noted at the first of each, for the write to refuse; an empty row there names nothing, and goes.
---
---@param lines string[] The pop-up's lines
---@return {groups: table[], items: {row: integer, text: string}[], fresh: table<Filehash, string>, orphan: integer|nil, two: {row: integer, words: string}|nil} read
local function read_groups(lines)
	local read = { groups = {}, items = {}, fresh = {} }
	local current
	local named = {}
	for row, line in ipairs(lines) do
		local kind, a, b = read_line(line)
		if kind == "header" then
			current = { name = a, marks = {}, rows = {} }
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
			local ref, path = resolve(b)
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

---Check if a group the pop-up drew has this group's name and its marks, alias for alias, already.
---
---@param group MarksGroup A group that came into the scope since the draw
---@return boolean drawn
local function drawn_already(group)
	local rows = {}
	for alias, _ in pairs(group.marks) do
		local handle = routines().handle_of(group, alias)
		if handle then
			rows[alias .. "\0" .. handle.id] = true
		end
	end
	for _, drawn in ipairs(open.groups_drawn or {}) do
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

---Write the pop-up's lines into the scope.
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
---Each group written keeps what the drawn group it matches was (`match_groups`): held over, unless it
---was moved first, and the default group while its name stands.
---
---@return boolean written
local function write()
	if not screen_edited() then
		set_modified() -- lines typed back as they were drawn leave the drafts alone to keep it modified
		return true -- the drafts are written by leaving
	end
	if (open.kind == "window" and not vim.api.nvim_win_is_valid(open.id))
		or (open.kind == "tab" and not vim.api.nvim_tabpage_is_valid(open.id)) then
		vim.notify("frogman: the " .. open.kind .. " these marks are for is gone, so they aren't written.", vim.log.levels.WARN)
		return false
	end
	local read = read_groups(vim.api.nvim_buf_get_lines(open.buf, 0, -1, false))
	local refused = read.orphan and (read.two == nil or read.orphan < read.two.row) and {
		row = read.orphan, words = "frogman: the marks above the first group's header have no group: put a header back above them, or delete them.",
	} or read.two
	if refused then
		vim.notify(refused.words, vim.log.levels.WARN)
		if open.win and vim.api.nvim_win_is_valid(open.win) then
			vim.api.nvim_win_set_cursor(open.win, { refused.row, 0 })
		end
		return false
	end
	local groups, items, fresh = read.groups, read.items, read.fresh
	local drawn_groups = open.groups_drawn or {}
	local match, joined = match_groups(groups, drawn_groups)
	for _, gone in ipairs(joined) do
		table.insert(items, { row = gone.row,
			text = group_glyph() .. " " .. gone.name .. "'s header is gone: its rows join " .. group_glyph() .. " " .. gone.into })
	end
	table.sort(items, function(x, y) return x.row < y.row end)
	if #items > 0 and vim.fn.confirm("frogman: before writing the marks:\n" ..
			table.concat(vim.tbl_map(function(item) return item.text end, items), "\n") ..
			"\nWrite as it stands?", "&Yes\n&No", 2) ~= 1 then
		if open.win and vim.api.nvim_win_is_valid(open.win) then
			vim.api.nvim_win_set_cursor(open.win, { items[1].row, 0 })
		end
		return false
	end
	for _, path in pairs(fresh) do
		history.register_filepath(path) -- a file typed by its path, known from now on
	end
	local scope = routines().scope(open.kind, open.id, true)
	-- what came in since the draw: a group held over, or a load's, with marks or none, but for one the
	-- pop-up drew already and the default with none, which goes as a load's does
	local arrived = vim.tbl_filter(function(group)
		return not open.drawn[group] and (group.held or group.loaded ~= nil) and not drawn_already(group)
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
		-- a held-over group stays held over, renamed or not, unless you moved it first, keeping the name an
		-- empty one came from; the default group stays the default while its name stands, and is one typed in
		-- once it's renamed
		local was = match[g] and drawn_groups[match[g]] or {}
		local held = (g > 1 and was.held) or nil
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
	routines().hold_scope(open.kind, open.id)
	redraw(nil)
	repaint()
	return true
end

---Take a scope's draft out of the drafts held.
---@param kind string The scope's kind
---@param id any Its window, tab or session's pool id
---@return table|nil draft
local function take_draft(kind, id)
	for i, draft in ipairs(open.drafts) do
		if draft.kind == kind and draft.id == id then
			return table.remove(open.drafts, i)
		end
	end
	return nil
end

---Show a draft as the screen: its lines as they were left, and what they were drawn from, the undo
---history starting there.
---@param draft table A scope's lines as a mode switch left them, with its mode and what they were drawn from
---@return nil
local function show_draft(draft)
	open.names, open.paths, open.states = draft.names, draft.paths, draft.states
	open.groups_drawn, open.drawn, open.drawn_lines = draft.groups_drawn, draft.drawn, draft.drawn_lines
	put_lines(draft.lines)
	set_modified()
	decorate()
	show_mode_line()
end

---Write the screen when it holds edits, then every draft, each shown in turn in its mode and checked.
---
---One that's refused or answered No stays shown, in its mode, and the drafts after it wait. With
---every one written, the mode is the one the screen was in.
---
---@return boolean written
local function write_all()
	local mode = data.mode
	if not write() then
		return false
	end
	while #open.drafts > 0 do
		local draft = table.remove(open.drafts, 1)
		data.mode, open.kind, open.id = draft.mode, draft.kind, draft.id
		show_draft(draft)
		if not write() then
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

---Close the pop-up's window; its buffer goes with it.
---@return nil
local function close()
	if is_open() and open.win and vim.api.nvim_win_is_valid(open.win) then
		vim.api.nvim_win_close(open.win, true)
	end
end

---Get the window the pop-up acts on: the one it was opened from, or the last tracked one.
---@return WinId|nil winid
function M.origin()
	if is_open() and vim.api.nvim_win_is_valid(open.origin) then
		return open.origin
	end
	return nil
end

---Open the marks pop-up on the scope the current mode reads for the window you're in.
---
---With edits not written yet, the pop-up stays as it is, focused, and says so. With a conflict, the
---alias the add was for shows the incoming file and the one already set, to settle and write.
---
---@param opts {conflict: {alias: string, id: HandleId}|nil}|nil
---@return nil
function M.open(opts)
	opts = opts or {}
	local view = require('frogman.domains.ui.view')
	if is_open() then
		if view.keep_if_dirty(open.buf, open.win, DIRTY) then
			return
		end
		close()
	end
	local origin = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_config(origin).relative ~= "" then
		origin = require('frogman.domains.navigation.routines').find_most_recent_tracked_window() or origin
	end
	local kind, id = routines().scope_key(data.mode, origin)
	local buf, win = view.open({
		name = NAME, filetype = "frogman-marks", title = "Marks", size = require('frogman.configs').marks_popup,
		fill = function(buf)
			open = { buf = buf, origin = origin, kind = kind, id = id, names = {}, states = {}, drafts = {} }
			redraw(opts.conflict)
		end,
		write = write,
		changed = function()
			set_modified() -- lines typed back as they were drawn hold nothing
			decorate()
		end,
		closed = function(buf)
			if open and open.buf == buf then
				open = nil
			end
		end,
	})
	open.win = win
	show_mode_line()
	if opts.conflict then
		for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
			local kind_of, alias = read_line(line)
			if kind_of == "row" and alias == opts.conflict.alias then
				vim.api.nvim_win_set_cursor(win, { i, 0 })
				break
			end
		end
	end
end

---Write the pop-up's lines when they were edited, and every draft, then leave it.
---
---A write that's refused or answered No leaves it open, showing the lines it refused.
---
---@return nil
function M.leave()
	if not is_open() then
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
	return resolve(file)
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
	local ref = (kind == "row" and file ~= "") and (resolve(file)) or nil
	if vim.bo[open.buf].modified and not write() then
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
---@param title string
---@param items string[]
---@param done fun(item: string)
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
---@param done fun(path: string)
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
	local buf, row = open.buf, vim.api.nvim_win_get_cursor(0)[1]
	pick_one("Alias", aliases(), function(alias)
		pick_file(function(path)
			if not is_open() or open.buf ~= buf then
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
			if open.names[text] and open.names[text] ~= ref then
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
					local held = resolve(file)
					if held then
						open.states[alias .. "\0" .. held] = "already set"
					end
					at = i
					break
				end
			end
			open.states[alias .. "\0" .. ref] = "incoming"
			vim.api.nvim_buf_set_lines(buf, at, at, false, { alias .. " -> " .. text })
			decorate()
		end)
	end)
end

---Switch the mode from inside the pop-up, and show the new mode's scope.
---
---The scope it leaves stays a draft when the screen holds edits, and the new scope's draft comes back
---with its lines as they were left, or the scope is drawn as it is.
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
	if kind == open.kind and id == open.id then
		data.mode = mode -- a tab session's tab and session modes read one scope
		decorate()
		return true
	end
	if screen_edited() then
		-- the lines kept as a draft can't hold two files for an alias
		local two = read_groups(vim.api.nvim_buf_get_lines(open.buf, 0, -1, false)).two
		if two then
			vim.notify(two.words, vim.log.levels.WARN)
			if open.win and vim.api.nvim_win_is_valid(open.win) then
				vim.api.nvim_win_set_cursor(open.win, { two.row, 0 })
			end
			return false
		end
		table.insert(open.drafts, {
			mode = data.mode, kind = open.kind, id = open.id, lines = vim.api.nvim_buf_get_lines(open.buf, 0, -1, false),
			names = open.names, paths = open.paths, states = open.states, groups_drawn = open.groups_drawn, drawn = open.drawn,
			drawn_lines = open.drawn_lines,
		})
	end
	data.mode, open.kind, open.id = mode, kind, id
	local draft = take_draft(kind, id)
	if draft then
		show_draft(draft)
	else
		redraw(nil)
	end
	return true
end

---Map the pop-up's keys on its buffer, from `keymaps.views`.
---
---Each key that acts begins a step of its own, about the window the pop-up was opened from. A key set
---to false isn't mapped.
---
---@param buf Bufnr
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

return M
