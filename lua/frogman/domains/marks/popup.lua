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
---shows, what each drawn name stands for, and the rows drawn as incoming or already set.
---@type {buf: Bufnr, win: WinId, origin: WinId, kind: string, id: any, names: table<string, Filehash>, states: table<string, string>}|nil
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

---Check if the marks pop-up has edits not written yet.
---@return boolean dirty
function M.dirty()
	return is_open() and vim.bo[open.buf].modified
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
---@param filehash Filehash
---@param names table<string, Filehash> Drawn name → hash, added to in place
---@return string name
local function name_of(filehash, names)
	local filepath = history.get_filepath_from_hash(filehash) or filehash
	local name
	if filepath:match("^NONAME_") then
		local bufnr = history.get_buffer_from_hash(filehash)
		local lines = bufnr and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
			or (history.data.noname_content[filehash] or {}).lines or {}
		local first = vim.trim(lines[1] or "")
		name = first ~= "" and ('[No Name] "' .. first:sub(1, 24) .. '"') or "[No Name]"
		local n = 1
		while names[name] and names[name] ~= filehash do
			n = n + 1
			name = name:gsub(" #%d+$", "") .. " #" .. n
		end
	else
		name = require('frogman.domains.ui').routines.get_smart_basename(filehash)
		if names[name] and names[name] ~= filehash then
			name = vim.fn.fnamemodify(filepath, ":.")
		end
	end
	names[name] = filehash
	return name
end

---Draw a scope's groups as the pop-up's lines.
---
---A scope with no group yet is drawn with its default one. With a conflict, the alias the add was
---for holds two rows in the first group: the incoming file and the one already set.
---
---@param kind string
---@param id any
---@param conflict {alias: string, hash: Filehash}|nil
---@return string[] lines
---@return table<string, Filehash> names
---@return table<string, string> states Row (alias and hash) → "incoming" or "already set"
---@return table<string, boolean> held The names of the groups held over
local function draw(kind, id, conflict)
	local scope = data.scopes[kind][id]
	local groups = scope and scope.groups or {}
	if routines().first_group(scope) == nil then
		-- the keys' group first, the default one, ahead of anything held over
		groups = vim.list_extend({ { name = require('frogman.configs').marks.default_group, marks = {} } }, vim.list_slice(groups))
	end
	local keys_group = routines().first_group({ groups = groups })
	local lines, names, states, held = {}, {}, {}, {}
	local glyph = group_glyph()
	local known = {}
	for _, alias in ipairs(aliases()) do
		known[alias] = true
	end
	for _, group in ipairs(groups) do
		table.insert(lines, glyph .. " " .. group.name)
		if group.held then
			held[group.name] = true
		end
		local function row(alias, filehash)
			table.insert(lines, alias .. " -> " .. (filehash and name_of(filehash, names) or ""))
		end
		for _, alias in ipairs(aliases()) do
			local handle = routines().handle_of(group, alias)
			if group == keys_group and conflict and conflict.alias == alias and (handle == nil or handle.hash ~= conflict.hash) then
				row(alias, conflict.hash)
				states[alias .. "\0" .. conflict.hash] = "incoming"
				if handle then
					row(alias, handle.hash)
					states[alias .. "\0" .. handle.hash] = "already set"
				end
			else
				row(alias, handle and handle.hash)
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
				row(alias, handle.hash)
			end
		end
	end
	return lines, names, states, held
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
---@param file string The row's file as written
---@return Filehash|nil filehash
---@return string|nil path A path to register as the write goes through, when the registry has none
local function resolve(file)
	-- a row it drew follows its file, by the file's handle, through a move since
	local drawn = open.handles and open.handles[file]
	local handle = drawn and history.handles.follow(drawn)
	if handle then
		return handle.hash, nil
	end
	if open.names[file] then
		return open.names[file], nil
	end
	local path = vim.fn.fnamemodify(file, ":p")
	local filehash = history.get_hash_from_filepath(path)
	if filehash then
		return filehash, nil
	end
	if vim.fn.filereadable(path) == 1 and vim.fn.isdirectory(path) == 0 then
		return history.routines.get_filehash(path), path
	end
	return nil, nil
end

---Draw the pop-up's decoration again: the mode line above it, and around each row its file's state.
---
---@return nil
local function decorate()
	if not is_open() then
		return
	end
	local buf = open.buf
	local glyphs = require('frogman.domains.ui').routines.glyphs()
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
		virt_lines = { { { "marks" .. glyphs.dot .. open.kind, "FrogmanTrailDim" } } }, virt_lines_above = true,
	})
	local known = {}
	for _, alias in ipairs(aliases()) do
		known[alias] = true
	end
	for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		local kind, alias, file = read_line(line)
		if kind == "row" and file ~= "" then
			local filehash = resolve(file)
			local arrow = line:find("->", 1, true)
			local col = arrow and line:find("%S", arrow + 2) -- the name's first character, however it's spaced
			if filehash and history.handles.kept_closed(filehash) and col then
				vim.api.nvim_buf_set_extmark(buf, ns, i - 1, col - 1, {
					virt_text = { { glyphs.closed .. " ", "FrogmanTrailClosed" } }, virt_text_pos = "inline",
				})
			end
			local after = {}
			local state = filehash and open.states[alias .. "\0" .. filehash]
			if state then
				table.insert(after, { "  " .. state, "FrogmanTrailDim" })
			end
			if not known[alias] then
				table.insert(after, { "  unassigned", "FrogmanTrailDim" })
			end
			if filehash and history.data.missing[filehash] then
				table.insert(after, { "  " .. glyphs.tag .. history.data.missing[filehash], "FrogmanTrailTag" })
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

---Put the scope's marks in the pop-up's lines, as they are now.
---@param conflict {alias: string, hash: Filehash}|nil
---@return nil
local function redraw(conflict)
	local lines, names, states, held = draw(open.kind, open.id, conflict)
	open.names, open.states, open.held = names, states, held
	-- what the write rebuilds from the lines: a group that comes in after stays
	local scope = data.scopes[open.kind][open.id]
	open.drawn = {}
	for _, group in ipairs(scope and scope.groups or {}) do
		open.drawn[group] = true
	end
	-- each name drawn by its file's handle, so a row follows its file through a move
	open.handles = {}
	for name, filehash in pairs(names) do
		local handle = history.handles.of_hash(filehash)
		open.handles[name] = handle and handle.id or nil
	end
	vim.api.nvim_buf_set_lines(open.buf, 0, -1, false, lines)
	vim.bo[open.buf].modified = conflict ~= nil -- a conflict waits to be settled and written
	decorate()
	show_mode_line()
end

---Draw the pop-up again when its scope changed and it has nothing unwritten, so it shows what's there.
---
---@param kind "window"|"tab"|"session" The kind of the scope that changed
---@param id any Its window, tab or session's pool id
---@return nil
function M.scope_changed(kind, id)
	if is_open() and open.kind == kind and open.id == id and not vim.bo[open.buf].modified then
		redraw(nil)
	end
end

---Write the pop-up's lines into the scope.
---
---A row above the first header, or an alias that holds two files in one group, refuses the write, and
---so does a window or a tab the scope was for that's gone.
---A line naming nothing, a row naming no file, and a second group of one name are asked about in
---one prompt, and No writes nothing. The lines are the scope's groups from then on, in order, and
---what came in since the pop-up was drawn stays below them: a group held over meanwhile, and a load's
---marks, held over under its header. A row it drew follows its file through a move.
---
---@return boolean written
local function write()
	if (open.kind == "window" and not vim.api.nvim_win_is_valid(open.id))
		or (open.kind == "tab" and not vim.api.nvim_tabpage_is_valid(open.id)) then
		vim.notify("frogman: the " .. open.kind .. " these marks are for is gone, so they aren't written.", vim.log.levels.WARN)
		return false
	end
	local groups, items, first_item = {}, {}, nil
	local current
	local lines = vim.api.nvim_buf_get_lines(open.buf, 0, -1, false)
	local function refuse(row, words)
		vim.notify(words, vim.log.levels.WARN)
		if open.win and vim.api.nvim_win_is_valid(open.win) then
			vim.api.nvim_win_set_cursor(open.win, { row, 0 })
		end
		return false
	end
	local named, fresh = {}, {}
	for row, line in ipairs(lines) do
		local kind, a, b = read_line(line)
		if kind == "header" then
			current = { name = a, marks = {}, rows = {} }
			if named[a] then
				table.insert(items, line .. "  is a second group of that name")
				first_item = first_item or row
			end
			named[a] = true
			table.insert(groups, current)
		elseif kind == "row" then
			if current == nil then
				return refuse(row, "frogman: the marks above the first group's header have no group: put a header back above them, or delete them.")
			end
			if b ~= "" then
				local filehash, path = resolve(b)
				if path then
					fresh[filehash] = path
				end
				if filehash == nil then
					table.insert(items, line .. "  names no file")
					first_item = first_item or row
				elseif current.marks[a] and current.marks[a] ~= filehash then
					return refuse(row, "frogman: ⟨" .. a .. "⟩ holds two files in " .. group_glyph() .. " " .. current.name .. ": keep one.")
				else
					current.marks[a] = filehash
				end
			end
		elseif kind == "other" then
			if current == nil then
				return refuse(row, "frogman: the marks above the first group's header have no group: put a header back above them, or delete them.")
			end
			table.insert(items, line .. "  names nothing")
			first_item = first_item or row
		end
	end
	if #items > 0 and vim.fn.confirm("frogman: before writing the marks:\n" .. table.concat(items, "\n") ..
			"\nWrite as it stands?", "&Yes\n&No", 2) ~= 1 then
		if open.win and vim.api.nvim_win_is_valid(open.win) then
			vim.api.nvim_win_set_cursor(open.win, { first_item, 0 })
		end
		return false
	end
	for _, path in pairs(fresh) do
		history.register_filepath(path) -- a file typed by its path, known from now on
	end
	local scope = routines().scope(open.kind, open.id, true)
	-- what came in since the draw: a group held over, or a load's, with marks
	local arrived = vim.tbl_filter(function(group)
		return not open.drawn[group] and next(group.marks) ~= nil and (group.held or group.loaded ~= nil)
	end, scope.groups)
	scope.groups = {}
	for g, group in ipairs(groups) do
		local marks = {}
		for alias, filehash in pairs(group.marks) do
			local handle = history.handles.of_hash(filehash)
			if handle then
				marks[alias] = handle.id
			end
		end
		-- a held-over group stays held over, unless you moved it first
		table.insert(scope.groups, { name = group.name, marks = marks, held = (g > 1 and open.held[group.name]) or nil })
	end
	-- what came in since the draw stays below: a load's marks held over under its header, as a load
	-- holds over what it replaces
	for _, group in ipairs(arrived) do
		if not group.held then
			local taken = {}
			for _, other in ipairs(scope.groups) do
				taken[other.name] = true
			end
			group.name = require('frogman.held').held_header(group.loaded or "loaded", taken)
			group.held = true
		end
		group.loaded = nil
		table.insert(scope.groups, group)
	end
	routines().hold_scope(open.kind, open.id)
	redraw(nil)
	require('frogman.domains.ui.sm').loop:to(require('frogman.domains.ui.states').LOOP.SELF)
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
---@param opts {conflict: {alias: string, hash: Filehash}|nil}|nil
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
			open = { buf = buf, origin = origin, kind = kind, id = id, names = {}, states = {} }
			redraw(opts.conflict)
		end,
		write = write,
		changed = decorate,
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

---Write the pop-up's lines when they were edited, then leave it.
---
---A write that's refused or answered No leaves it open, its lines as typed.
---
---@return nil
function M.leave()
	if not is_open() then
		return
	end
	require('frogman.domains.ui.view').leave(open.buf, open.win, write)
end

---Get the file the row under the cursor names.
---@return Filehash|nil filehash
local function row_file()
	local kind, _, file = read_line(vim.api.nvim_get_current_line())
	if kind ~= "row" or file == "" then
		return nil
	end
	return (resolve(file))
end

---Get the row under the cursor, its alias and its file, writing the pop-up first when it was edited.
---
---The row is read before the write, which draws the lines again in the aliases' order, so what's acted
---on is the row you were on, and a path typed there is registered by the write.
---
---@return string|nil alias
---@return Filehash|nil filehash Nil when the write was refused or answered No, or the row names no file
local function written_row()
	local kind, alias, file = read_line(vim.api.nvim_get_current_line())
	local filehash = (kind == "row" and file ~= "") and (resolve(file)) or nil
	if vim.bo[open.buf].modified and not write() then
		return nil, nil
	end
	if filehash and not history.get_filepath_from_hash(filehash) then
		return alias, nil -- a row the write left out
	end
	return alias, filehash
end

---Jump to the row's file in the window the pop-up was opened from, as a mark's jump goes.
---
---The pop-up is written first when it was edited, and stays when that's refused. With `stay`, the
---pop-up stays open.
---
---@param stay boolean|nil
---@return nil
function M.act(stay)
	if not is_open() then
		return
	end
	local alias, filehash = written_row()
	local origin = M.origin()
	if filehash == nil or origin == nil then
		return
	end
	local here = vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(origin)
	require('frogman.domains.window').routines.jump_to_mark(origin, filehash, "⟨" .. alias .. "⟩")
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
	local _, filehash = written_row()
	local origin = M.origin()
	local triquetra = origin and require('frogman.domains.window').data.get_window_triquetra(origin)
	if filehash == nil or triquetra == nil then
		return
	end
	local at = vim.fn.index(triquetra.primary_buffer, filehash)
	if at ~= -1 then
		triquetra:queue_remove(at + 1)
	end
	triquetra:queue_insert(1, filehash)
	triquetra.primary_enabled = true
	require('frogman.domains.ui.sm').loop:to(require('frogman.domains.ui.states').LOOP.SELF)
	vim.cmd("redrawstatus!")
	vim.cmd("redrawtabline")
	vim.notify("frogman: " .. require('frogman.domains.ui').routines.get_smart_basename(filehash) ..
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
		attach_mappings = function(prompt_bufnr)
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
			local filehash = history.routines.get_filehash(vim.fn.fnamemodify(path, ":p"))
			local text = vim.fn.fnamemodify(path, ":.")
			if open.names[text] and open.names[text] ~= filehash then
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
			open.states[alias .. "\0" .. filehash] = "incoming"
			vim.api.nvim_buf_set_lines(buf, at, at, false, { alias .. " -> " .. text })
			decorate()
		end)
	end)
end

---Switch the mode from inside the pop-up, and show the new mode's scope.
---
---Edits not written yet are written first, and a write that's refused or answered No keeps the mode
---and the pop-up as they are. With the window it was opened from gone, it refuses and says so.
---
---@param mode "window"|"tab"|"session"
---@return boolean switched
function M.switch_mode(mode)
	if not M.origin() then
		vim.notify("frogman: the window these marks are for is gone.", vim.log.levels.WARN)
		return false
	end
	if vim.bo[open.buf].modified and not write() then
		return false
	end
	data.mode = mode
	open.kind, open.id = routines().scope_key(mode, open.origin)
	redraw(nil)
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
		local filehash = row_file()
		local filepath = filehash and history.get_filepath_from_hash(filehash)
		if filepath and not filepath:match("^NONAME_") then
			require('frogman.domains.ui.trail').open(vim.fs.basename(filepath))
		end
	end, "Search the trail for the line's file")
end

return M
