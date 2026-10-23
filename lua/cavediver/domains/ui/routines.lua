---UI domain core routines for visual component management.
---
---This module contains the main business logic for managing visual interface
---components, including the bufferline cache optimization that was previously
---in update_bufferline_state() from buffers.lua.

local data = require('cavediver.domains.ui.data')
local history = require('cavediver.domains.history')
local window = require('cavediver.domains.window')
local navigation = require('cavediver.domains.navigation')
local uiMachines = require('cavediver.domains.ui.sm')
local states = require('cavediver.domains.ui.states')

local preserve_winbar_overlap = {} -- Table to track winbar overlap state

local update_timer = vim.loop:new_timer()

local M = {}

---Display primary buffer history managgement floating window.
function M.show_primary_buffer_history()
	local cwin = vim.api.nvim_get_current_win()

	local triquetra = window.get_triquetra(cwin)

	local basename_filepath_mapping = {}
	
	for filepath, filehash in pairs(history.data.hash_filepath_registry.hashes) do
		data.clear_display_name_cache()
		local basename = M.get_smart_basename(filehash) -- Ensure cache is populated
		if filepath then
			if filepath:match("^NONAME_") then
				basename_filepath_mapping[filepath] = filepath
			else
				basename_filepath_mapping[basename] = filepath
			end
		end
	end

	if not triquetra then
		vim.notify("No triquetra found for current window.", vim.log.levels.INFO)
		return
	end
	
	if #triquetra.primary_buffer == 0 then
		vim.notify("No primary buffer history available.", vim.log.levels.INFO)
		return
	end

	local dbuf = vim.api.nvim_create_buf(true, false)
	local dwin

	vim.bo[dbuf].filetype = "cavediver-primary-buffer-history"
	vim.bo[dbuf].buftype = "acwrite"
	vim.bo[dbuf].swapfile = false

	local function to_display(hash)
		local basename = M.get_smart_basename(hash)
		local filepath = history.get_filepath_from_hash(hash)
		if filepath and filepath:match("^NONAME_") then
			basename = filepath
		end
		return basename
	end

	vim.api.nvim_buf_set_name(dbuf, "cavediver://primary-buffer-queue-history")
	vim.api.nvim_buf_set_lines(dbuf, 0, -1, false, vim.tbl_map(to_display, triquetra.primary_buffer))
	vim.bo[dbuf].modified = false

	vim.api.nvim_create_autocmd("BufDelete", {
		buffer = dbuf,
		once = true,
		callback = function()
			vim.defer_fn(function()
					if vim.api.nvim_win_is_valid(dwin) then
						vim.api.nvim_win_close(dwin, true)
					end
				end,
			800)
		end
	})

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = dbuf,
		callback = function()
			if not vim.bo[dbuf].modified then
				return
			end
			local lines = vim.api.nvim_buf_get_lines(dbuf, 0, -1, false)
			lines = vim.tbl_map(function(basename)
				basename = vim.trim(basename)
				return basename_filepath_mapping[basename] or basename
			end, vim.tbl_filter(function(value) return vim.trim(value) ~= "" end, lines))
			window.update_primary_buffer(lines, cwin)
			vim.api.nvim_buf_set_lines(dbuf, 0, -1, false,
				vim.tbl_map(to_display, triquetra.primary_buffer))
			vim.bo[dbuf].modified = false
			vim.cmd("redraw")
		end,
		desc = "Save primary buffer queue changes"
	})

	local configs = require('cavediver.configs')
	local width, height
	configs.primary_buffer_history_popup.width = math.abs(configs.primary_buffer_history_popup.width)
	configs.primary_buffer_history_popup.height = math.abs(configs.primary_buffer_history_popup.height)

	if configs.primary_buffer_history_popup.width <= 1 then
		width = math.floor(vim.o.columns * configs.primary_buffer_history_popup.width)
	else
		width = math.min(vim.o.columns, math.floor(configs.primary_buffer_history_popup.width))
	end
	if configs.primary_buffer_history_popup.height <= 1 then
		height = math.floor(vim.o.lines * configs.primary_buffer_history_popup.height)
	else
		height = math.min(vim.o.lines, math.floor(configs.primary_buffer_history_popup.height))
	end

	dwin = vim.api.nvim_open_win(dbuf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = " Primary Buffer Queue (History) ",
		title_pos = "center",
	})

	vim.b[dbuf].display_window = dwin

	vim.wo[dwin].wrap = false
	vim.wo[dwin].cursorline = true
	vim.wo[dwin].number = true
	vim.wo[dwin].relativenumber = false
end

-- The closed lists ---------------------------------------------------------------------------------
--
-- One editable floating window for every list of closed files: the editor's, and each tab session's.
-- The text of a line is only what you edit: a list's header (`≡editor`, `≡notes`) or an entry's name
-- (a path, or `[No Name] "first line…"`). Everything else is drawn around it as virtual text, and drawn
-- again as you edit: the closed glyph, the close time, a No Name text's filetype, a missing file's
-- tag, a list's tabs.

local closed_ns = vim.api.nvim_create_namespace("cavediver_closed_lists")
-- each open closed-lists buffer's state, by buffer
local closed_pickers = {}

local glyph_sets = {
	unicode = {
		list = "≡", closed = "↓", tag = "⎇", more = "…",
		-- the trail's: its title, fills by depth (and unshaded), gauge, marks, branches, folds, arrows, and a
		-- search's mark and life line
		title = "⦉ trail ⦊", shade0 = "≋", shade1 = "░", shade2 = "▒", shade3 = "▓", rule = "─",
		bars = "▁▂▃▄▅▆▇█", now_left = "❬", now_right = "❭", dot = " · ", older = "<<<", newer = ">>>",
		branch = "├ ", last = "└ ", stem = "│ ", folded = "▸", unfolded = "▾", arrow = " → ", ring = "┊",
		row_t = { "⦉", "⦊" }, row_c = { "[", "]" }, row_s = { "⟦", "⟧" }, search = "⌕", life = "┃",
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
		row_t = { "<", ">" }, row_c = { "[", "]" }, row_s = { "{", "}" }, search = "?", life = "|",
		keymap = "K", command = ":", event = "E", timer = "T", load = "L", save = "S", restart = "R", label = "@",
		reopened = "^", forgotten = "0", note_dropped = "x", gone = "X", back = "+", repair = "!", repointed = "~",
		landed = ">", undone = "<", dropped = "/", cleared = "/", rewritten = "*", cancelled = "|", loaded = "L",
		fresh = "L", saved = "S", refreshed = "S", tab_closed = "S", copied = "=", moved = ">", detached = "#",
		detached_left = "#",
	},
}

---The glyphs cavediver's views draw with: config's set, with any glyph it names in that glyph's place.
---@return table<string, string>
function M.glyphs()
	local configured = require('cavediver.configs').glyphs or {}
	local glyphs = vim.deepcopy(glyph_sets[configured.set] or glyph_sets.unicode)
	for name, glyph in pairs(configured) do
		if name ~= "set" then
			glyphs[name] = glyph
		end
	end
	return glyphs
end

---A close time, short when it's today.
---@param time number|nil
---@return string
local function close_time_text(time)
	if time == nil then
		return ""
	elseif os.date("%Y%m%d", math.floor(time)) == os.date("%Y%m%d") then
		return os.date("%H:%M", math.floor(time))
	end
	return os.date("%a %d %b %H:%M", math.floor(time))
end

---A closed entry's name, as its line holds it: the path from the cwd, or a No Name text's first line.
---@param filehash Filehash
---@param glyphs table
---@param file table|nil A list in the file alone: its `paths` and `texts` ({first, filetype})
---@return string name
---@return string|nil filetype A No Name text's
local function closed_entry_name(filehash, glyphs, file)
	local filepath = history.get_filepath_from_hash(filehash) or (file and file.paths[filehash]) or filehash
	if not filepath:match("^NONAME_") then
		return vim.fn.fnamemodify(filepath, ":~:."), nil
	end
	if file and file.texts[filehash] and history.data.noname_content[filehash] == nil then
		local first = vim.trim(file.texts[filehash].first or "")
		if vim.fn.strchars(first) > 24 then
			first = vim.fn.strcharpart(first, 0, 24) .. glyphs.more
		end
		return '[No Name] "' .. first .. '"', file.texts[filehash].filetype ~= "" and file.texts[filehash].filetype or nil
	end
	local content = history.data.noname_content[filehash]
	if content and content.lines == nil and content.read then
		-- a text from the session file, read now to show it, and kept so it's read once; one whose
		-- file fails its check stays as it was
		local read = content.read()
		if read then
			history.data.noname_content[filehash] = read
		end
		content = read
	end
	local first = content and content.lines and vim.trim(content.lines[1] or "") or ""
	if vim.fn.strchars(first) > 24 then
		first = vim.fn.strcharpart(first, 0, 24) .. glyphs.more
	end
	local filetype = content and content.filetype ~= "" and content.filetype or nil
	return '[No Name] "' .. first .. '"', filetype
end

---The time an entry is drawn and written with under a list: the list's own, when it held the file;
---otherwise the newest of the lists that held it, since the line came from one of them.
---@param picker table
---@param pool Pool
---@param filehash Filehash
---@param own boolean Whether to take the list's own time when it has one
---@return number|nil
local function closed_entry_time(picker, pool, filehash, own)
	if own and picker.times[pool] and picker.times[pool][filehash] then
		return picker.times[pool][filehash]
	end
	local newest
	for _, other in ipairs(picker.order) do
		local time = picker.times[other][filehash]
		if time and (newest == nil or time > newest) then
			newest = time
		end
	end
	return newest
end

---The virtual text after an entry: a No Name text's filetype, the close time, a missing file's tag.
---@param entry CavediverClosedEntry
---@param glyphs table
---@return table[]
local function closed_entry_text(entry, glyphs)
	local after = {}
	if entry.filetype then
		table.insert(after, { "  " .. entry.filetype, "CavediverTrailDim" })
	end
	table.insert(after, { "  " .. close_time_text(entry.time), "CavediverTrailTime" })
	if entry.tag then
		table.insert(after, { "  " .. glyphs.tag .. entry.tag, "CavediverTrailTag" })
	end
	return after
end

---Draw the virtual text around each line, from what the line's text names.
---@param dbuf Bufnr
---@return nil
local function decorate_closed_lists(dbuf)
	local picker = closed_pickers[dbuf]
	if not picker then
		return
	end
	local glyphs = M.glyphs()
	local formatter = require('cavediver.configs').formatters.closed_entry or closed_entry_text
	vim.api.nvim_buf_clear_namespace(dbuf, closed_ns, 0, -1)
	local current
	for i, line in ipairs(vim.api.nvim_buf_get_lines(dbuf, 0, -1, false)) do
		local text = vim.trim(line)
		local pool = picker.headers[text]
		local filehash = picker.hashes[text]
		if pool then
			current = pool
			vim.api.nvim_buf_set_extmark(dbuf, closed_ns, i - 1, 0, {
				end_col = #line, hl_group = "CavediverTrailList",
				virt_text = { { "  " .. picker.where[pool], "CavediverTrailDim" } }, virt_text_pos = "eol",
			})
		elseif filehash then
			local entry = {
				name = text,
				path = history.get_filepath_from_hash(filehash) or filehash,
				time = current and closed_entry_time(picker, current, filehash, true),
				filetype = picker.filetypes[filehash],
				tag = history.data.missing[filehash],
				list = current and picker.label[current] or "",
			}
			vim.api.nvim_buf_set_extmark(dbuf, closed_ns, i - 1, 0, {
				virt_text = { { "  " .. glyphs.closed .. " ", "CavediverTrailClosed" } }, virt_text_pos = "inline",
			})
			vim.api.nvim_buf_set_extmark(dbuf, closed_ns, i - 1, 0, { virt_text = formatter(entry, glyphs) or {}, virt_text_pos = "eol" })
		end
	end
end

---Draw the closed lists into a buffer: each list a header with its closed entries under it, newest
---first; the editor's list first, then the tab sessions' with a tab, then any with none.
---@param dbuf Bufnr
---@return nil
local function draw_closed_lists(dbuf)
	local picker = closed_pickers[dbuf]
	local glyphs = M.glyphs()
	local pools = history.routines.pools()
	local order, others = { pools[""] }, {}
	for id, pool in pairs(pools) do
		if id ~= "" then
			table.insert(others, pool)
		end
	end
	table.sort(others, function(a, b)
		local a_tab, b_tab = next(a.tabs) ~= nil, next(b.tabs) ~= nil
		if a_tab ~= b_tab then
			return a_tab
		end
		return a.id < b.id
	end)
	vim.list_extend(order, others)
	-- the detached lists in the whole editor's file alone, after the lists in memory
	local files = {}
	for _, list in ipairs(require('cavediver.domains.storage').routines.file_only_lists()) do
		local pool = { id = "\0file\n" .. list.label, name = list.label, detached = true, file_only = true, closed = list.closed, times = list.times, tabs = {} }
		files[pool] = { paths = list.paths, texts = list.texts }
		table.insert(order, pool)
	end

	-- a list's name: "editor", or its session's; two sessions of one name are told apart by directory
	local label, named = {}, {}
	for _, pool in ipairs(order) do
		label[pool] = pool.id == "" and "editor" or (pool.name or vim.fn.fnamemodify(pool.directory, ":t"))
		named[label[pool]] = (named[label[pool]] or 0) + 1
	end
	for _, pool in ipairs(order) do
		if named[label[pool]] > 1 and pool.directory then
			label[pool] = label[pool] .. " (" .. vim.fn.fnamemodify(pool.directory, ":t") .. ")"
		end
	end

	local headers, where, hashes, filetypes, times, drawn, lines = {}, {}, {}, {}, {}, {}, {}
	for _, pool in ipairs(order) do
		local tabs = {}
		for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
			if history.routines.pool_of_tab(tabpage) == pool then
				table.insert(tabs, vim.api.nvim_tabpage_get_number(tabpage))
			end
		end
		where[pool] = pool.file_only and "in the file" or #tabs == 0 and "no tab" or (#tabs == 1 and ("tab " .. tabs[1]) or ("tabs " .. table.concat(tabs, ", ")))
		local header = glyphs.list .. label[pool]
		headers[header] = pool
		table.insert(lines, header)
		times[pool], drawn[pool] = vim.deepcopy(pool.times), {}
		for i = #pool.closed, 1, -1 do
			local filehash = pool.closed[i]
			local name, filetype = closed_entry_name(filehash, glyphs, files[pool])
			-- one line's text names one file: another file with the same name gets a number
			local text, n = name, 1
			while hashes[text] and hashes[text] ~= filehash do
				n = n + 1
				text = name .. "  #" .. n
			end
			hashes[text], filetypes[filehash] = filehash, filetype
			table.insert(drawn[pool], filehash)
			table.insert(lines, text)
		end
	end
	picker.order, picker.label, picker.headers, picker.where = order, label, headers, where
	picker.hashes, picker.filetypes, picker.times, picker.drawn = hashes, filetypes, times, drawn
	picker.paths = {} -- the paths of the entries in lists in the file alone
	for _, file in pairs(files) do
		for filehash, path in pairs(file.paths) do
			picker.paths[filehash] = path
		end
	end
	vim.api.nvim_buf_set_lines(dbuf, 0, -1, false, lines)
	vim.bo[dbuf].modified = false
	decorate_closed_lists(dbuf)
end

---Write a closed-lists buffer back: each list becomes its lines, newest first. A line moved under
---another header moves to that list; a file twice in one list is kept once, with the newer close; a
---deleted line is discarded, a No Name text only once you confirm, since it exists nowhere else. Each
---list keeps its own close times for the files it held. A line that names no list or entry refuses
---the whole write, and so does a No Name text kept at the question.
---@param dbuf Bufnr
---@return boolean written
local function write_closed_lists(dbuf)
	local picker = closed_pickers[dbuf]
	local current, new, count, errors = nil, {}, {}, {}
	for _, line in ipairs(vim.api.nvim_buf_get_lines(dbuf, 0, -1, false)) do
		local text = vim.trim(line)
		if text ~= "" then
			local filehash = picker.hashes[text]
			if picker.headers[text] then
				current = picker.headers[text]
				new[current], count[current] = new[current] or {}, count[current] or {}
			elseif filehash and current then
				count[current][filehash] = (count[current][filehash] or 0) + 1
				if count[current][filehash] == 1 then
					table.insert(new[current], filehash)
				end
			else
				table.insert(errors, text)
			end
		end
	end
	if #errors > 0 then
		vim.notify("cavediver: the closed lists weren't written: these lines name no list or entry (a list's header comes first):\n  " ..
			table.concat(errors, "\n  "), vim.log.levels.ERROR)
		return false
	end

	-- what's left on no list: a No Name text goes for good, so it's asked first
	local placed, gone, lost = {}, {}, {}
	for _, filehashes in pairs(new) do
		for _, filehash in ipairs(filehashes) do
			placed[filehash] = true
		end
	end
	for text, filehash in pairs(picker.hashes) do
		if not placed[filehash] and not gone[filehash] then
			gone[filehash] = true
			if (history.get_filepath_from_hash(filehash) or picker.paths[filehash] or ""):match("^NONAME_") then
				table.insert(lost, text)
			end
		end
	end
	table.sort(lost)
	if #lost > 0 and vim.fn.confirm("Discard these No Name texts? They exist nowhere else.\n" ..
			table.concat(lost, "\n"), "&Discard\n&Keep", 2) ~= 1 then
		return false
	end

	local storage = require('cavediver.domains.storage').routines
	local file_changes = nil
	for _, pool in ipairs(picker.order) do
		if pool.file_only then
			-- a list in the file alone: its new lines go back to the file, and an empty one goes
			local filehashes, closed, times = new[pool] or {}, {}, {}
			for i = #filehashes, 1, -1 do
				table.insert(closed, filehashes[i])
				times[filehashes[i]] = closed_entry_time(picker, pool, filehashes[i], count[pool][filehashes[i]] == 1)
			end
			if not vim.deep_equal(closed, pool.closed) or not vim.deep_equal(times, pool.times) then
				file_changes = file_changes or {}
				file_changes[pool.name] = #closed > 0 and { closed = closed, times = times } or false
			end
		end
	end
	for _, pool in ipairs(picker.order) do
		-- a list a load tore down while the window was open is left alone
		if not pool.file_only and history.data.pools[pool.id] == pool then
			local filehashes, was_drawn = new[pool] or {}, {}
			for _, filehash in ipairs(picker.drawn[pool]) do
				was_drawn[filehash] = true
			end
			local closed, times = {}, {}
			for i = #filehashes, 1, -1 do
				local filehash = filehashes[i]
				table.insert(closed, filehash)
				times[filehash] = closed_entry_time(picker, pool, filehash, count[pool][filehash] == 1)
			end
			-- closed onto it since it was drawn: kept, as the newest
			for _, filehash in ipairs(pool.closed) do
				if not was_drawn[filehash] and not placed[filehash] then
					table.insert(closed, filehash)
					times[filehash] = pool.times[filehash]
				end
			end
			if not vim.deep_equal(closed, pool.closed) or not vim.deep_equal(times, pool.times) then
				for _, filehash in ipairs(closed) do
					storage.adopt_file_entry(filehash) -- moved in from a list in the file alone
				end
				for i = #pool.closed, 1, -1 do
					pool.closed[i] = nil -- in place: the editor's list is closed_buffers itself
				end
				vim.list_extend(pool.closed, closed)
				pool.times = times
				history.routines.pool_changed(pool)
			end
		end
	end
	if file_changes then
		local ok, problem = storage.write_file_only_lists(file_changes)
		if not ok then
			vim.notify("cavediver: the closed lists' edits to the lists in the whole editor's file alone weren't written, since " ..
				(problem == "missing" and "there's no whole-editor session file" or problem) .. "; they're still on screen.", vim.log.levels.WARN)
			return false
		end
	end
	for filehash, _ in pairs(gone) do
		if not history.routines.is_filehash_closed(filehash) then
			history.data.noname_content[filehash] = nil
			history.data.came_from[filehash] = nil
		end
	end
	return true
end

---Close a closed-lists window; its buffer goes with it.
---@param dbuf Bufnr
---@return nil
local function close_closed_lists(dbuf)
	local dwin = vim.b[dbuf].display_window
	if dwin and vim.api.nvim_win_is_valid(dwin) then
		vim.api.nvim_win_close(dwin, true)
	end
end

---Leave the closed lists, writing them first when they were edited. A write that's refused leaves
---the window open, so the lines can be fixed.
---@param dbuf Bufnr
---@return nil
function M.leave_closed_lists(dbuf)
	if vim.bo[dbuf].modified and not write_closed_lists(dbuf) then
		return
	end
	close_closed_lists(dbuf)
end

---Reopen the entry under the cursor in the window the closed lists were opened from, writing the
---lists first when they were edited; then leave, or stay with the lists drawn again.
---@param dbuf Bufnr
---@param stay boolean
---@return nil
function M.reopen_from_closed_lists(dbuf, stay)
	local picker = closed_pickers[dbuf]
	local text = vim.trim(vim.api.nvim_get_current_line())
	local filehash = picker and picker.hashes[text]
	if not filehash then
		return
	end
	if vim.bo[dbuf].modified and not write_closed_lists(dbuf) then
		return
	end
	-- the list the line is under; one in the file alone gives the entry up as it's reopened
	local section
	local lines = vim.api.nvim_buf_get_lines(dbuf, 0, vim.api.nvim_win_get_cursor(0)[1], false)
	for i = #lines, 1, -1 do
		section = picker.headers[vim.trim(lines[i])]
		if section then
			break
		end
	end
	local storage = require('cavediver.domains.storage').routines
	if section and section.file_only then
		storage.adopt_file_entry(filehash)
	end
	local bufnr = history.routines.reopen_filehash(filehash)
	if bufnr and section and section.file_only then
		-- the list as the file holds it now, the edits just written included
		for _, list in ipairs(storage.file_only_lists()) do
			if list.label == section.name then
				local closed, times = {}, {}
				for _, other in ipairs(list.closed) do
					if other ~= filehash then
						table.insert(closed, other)
						times[other] = list.times[other]
					end
				end
				local ok, problem = storage.write_file_only_lists({ [list.label] = #closed > 0 and { closed = closed, times = times } or false })
				if not ok then
					vim.notify("cavediver: " .. text .. " was reopened, but couldn't be taken off " .. list.label .. " in the whole editor's file, since " .. tostring(problem) .. ".", vim.log.levels.WARN)
				end
			end
		end
	end
	if not bufnr then
		if not (history.get_filepath_from_hash(filehash) or ""):match("^NONAME_") then
			vim.notify(text .. " isn't on disk right now; it stays on the closed list.", vim.log.levels.WARN)
		end
		draw_closed_lists(dbuf)
		return
	end
	local target = picker.came_from
	if not vim.api.nvim_win_is_valid(target) then
		target = window.data.last_valid_window
	end
	if stay then
		vim.api.nvim_win_call(target, function()
			vim.api.nvim_set_current_buf(bufnr)
		end)
		draw_closed_lists(dbuf)
	else
		close_closed_lists(dbuf)
		vim.api.nvim_set_current_win(target)
		vim.api.nvim_set_current_buf(bufnr)
	end
end

---Go to the next list's header (step 1) or the previous one's (step -1).
---@param dbuf Bufnr
---@param step integer
---@return nil
function M.closed_lists_section(dbuf, step)
	local picker = closed_pickers[dbuf]
	local lines = vim.api.nvim_buf_get_lines(dbuf, 0, -1, false)
	local i = vim.api.nvim_win_get_cursor(0)[1] + step
	while picker and i >= 1 and i <= #lines do
		if picker.headers[vim.trim(lines[i])] then
			vim.api.nvim_win_set_cursor(0, { i, 0 })
			return
		end
		i = i + step
	end
end

---The fold of a line in the closed lists: each list folds under its header.
---@return string
function M.closed_lists_fold()
	local picker = closed_pickers[vim.api.nvim_get_current_buf()]
	if picker and picker.headers[vim.trim(vim.fn.getline(vim.v.lnum))] then
		return ">1"
	end
	return picker and "1" or "0"
end

---Open the closed lists in a floating window: every list of closed files, the editor's, each tab
---session's, the detached ones and those in the whole editor's file alone, to reorder, merge, discard
---or reopen from.
---@param opts {focus: Pool|nil}|nil `focus`: the list whose header the cursor starts on
---@return nil
function M.show_closed_lists(opts)
	local cwin = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_config(cwin).relative ~= "" and window.data.last_valid_window then
		cwin = window.data.last_valid_window -- opened from a float: reopen into the last tracked window
	end
	local existing = vim.fn.bufnr("cavediver://closed-lists")
	if existing ~= -1 then
		vim.api.nvim_buf_delete(existing, { force = true })
	end

	local dbuf = vim.api.nvim_create_buf(false, false)
	vim.bo[dbuf].buftype = "acwrite"
	vim.bo[dbuf].swapfile = false
	vim.bo[dbuf].bufhidden = "wipe" -- the buffer goes with its window, however the window closes
	vim.api.nvim_buf_set_name(dbuf, "cavediver://closed-lists")
	closed_pickers[dbuf] = { came_from = cwin }
	draw_closed_lists(dbuf)

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = dbuf,
		callback = function()
			if write_closed_lists(dbuf) then
				draw_closed_lists(dbuf)
			end
		end,
		desc = "Write the closed lists",
	})
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = dbuf,
		callback = function()
			decorate_closed_lists(dbuf)
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = dbuf,
		once = true,
		callback = function()
			closed_pickers[dbuf] = nil
			-- a detached list case 8 kept waiting for these lists goes on now, unless another window of
			-- them took over, as opening them again does
			vim.schedule(function()
				if next(closed_pickers) == nil then
					require('cavediver.domains.storage').routines.settle_merging()
				end
			end)
		end,
	})

	local size = require('cavediver.configs').closed_lists_popup
	local width = math.abs(size.width) <= 1 and math.floor(vim.o.columns * math.abs(size.width)) or math.min(vim.o.columns, math.floor(math.abs(size.width)))
	local height = math.abs(size.height) <= 1 and math.floor(vim.o.lines * math.abs(size.height)) or math.min(vim.o.lines, math.floor(math.abs(size.height)))
	local dwin = vim.api.nvim_open_win(dbuf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = " Closed lists ",
		title_pos = "center",
	})
	vim.b[dbuf].display_window = dwin
	vim.wo[dwin].wrap = false
	vim.wo[dwin].cursorline = true
	vim.wo[dwin].foldmethod = "expr"
	vim.wo[dwin].foldexpr = "v:lua.require'cavediver.domains.ui.routines'.closed_lists_fold()"
	vim.wo[dwin].foldlevel = 99
	vim.wo[dwin].foldenable = true
	vim.bo[dbuf].filetype = "cavediver-closed-lists"
	local focus = opts and opts.focus
	if focus then
		for i, line in ipairs(vim.api.nvim_buf_get_lines(dbuf, 0, -1, false)) do
			if closed_pickers[dbuf].headers[vim.trim(line)] == focus then
				vim.api.nvim_win_set_cursor(dwin, { i, 0 })
				break
			end
		end
	end
end

---Find buffers with conflicting basenames.
---
---@param basename string The basename to check for conflicts
---@param filehash Filehash Buffer to exclude from conflict check
---@return string[] conflicts List of full paths with same basename
local function find_basename_conflicts(basename, filehash)
	local conflicts = {}
	local own_path = history.get_filepath_from_hash(filehash)
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if (bufnr ~= history.get_buffer_from_hash(filehash)) and (own_path ~= nil) then
			local path = vim.api.nvim_buf_get_name(bufnr)
			-- a closed file's own unlisted buffer has its path too, it's not a conflict with itself.
			if path ~= "" and path ~= own_path and vim.fn.fnamemodify(path, ":t") == basename then
				table.insert(conflicts, path)
			end
		end
	end
	return conflicts
end

---Compute unique suffix to distinguish path from conflicts.
---
---@param path string Full path to make unique
---@param conflicts string[] Conflicting paths with same basename
---@return string suffix Minimal distinguishing suffix
local function compute_unique_suffix(path, conflicts)
	local segments = vim.split(path, "/")

	-- Start with just basename
	for depth = 1, #segments - 1 do
		local suffix = table.concat(segments, "/", #segments - depth + 1)
		local is_unique = true

		for _, conflict in ipairs(conflicts) do
			if conflict:sub(- #suffix) == suffix then
				is_unique = false
				break
			end
		end

		if is_unique then
			return suffix
		end
	end

	-- Fallback to full path if no unique suffix found
	return path
end

---Get smart display name for a buffer with intelligent disambiguation.
---
---Returns just the basename if unique, or adds parent directories as needed
---to distinguish from other buffers with the same basename.
---
---@param filehash Filehash Buffer number to get display name for
---@return string display_name Smart basename with disambiguation
function M.get_smart_basename(filehash)
	local filepath = history.get_filepath_from_hash(filehash)

	if not filepath then
		error("Cannot get smart basename: filehash is nil or invalid")
	end

	local bufnr = history.get_buffer_from_hash(filehash)
	local name

	-- Handle invalid buffers
	if bufnr then
		-- Fast path: return cached if available
		if data.display_name_cache[filehash] then
			return data.display_name_cache[filehash]
		end

		-- Handle special buffer types
		if vim.bo[bufnr].buftype ~= "" then
			local display_name = "[" .. (vim.bo[bufnr].buftype or "No Name") .. "]"
			data.display_name_cache[filehash] = display_name
			return display_name
		end
		name = (vim.api.nvim_buf_is_valid(bufnr) or "") and vim.api.nvim_buf_get_name(bufnr)
	else
		name = filepath
	end

	if name == "" then
		local display_name = "[No Name]"
		data.display_name_cache[filehash] = display_name
		return display_name
	end

	-- Get basename and check for conflicts
	local basename = vim.fn.fnamemodify(name, ":t")
	local conflicts = find_basename_conflicts(basename, filehash)

	local display_name
	if #conflicts == 0 then
		-- No conflicts, just use basename
		display_name = basename
	else
		-- Conflicts exist, compute unique suffix
		display_name = compute_unique_suffix(name, conflicts)
	end

	-- Cache and return
	data.display_name_cache[filehash] = display_name
	return display_name
end

local derive_cache_lock = {}

---@param again boolean|nil True on the one retry after a cleanup
local function derive_cache_from_window_triquetra(winid, again)
	local window_triquetra = window.get_triquetra(winid)
	if not  window_triquetra then
		return nil
	end
	-- a slot whose buffer went without events (noautocmd) leaves the registry pointing at a dead buffer.
	-- cleanup repairs it now, as it would at its next tick: the window is re-pointed like navigation.
	for _, filehash in ipairs({
		window_triquetra.current_slot,
		window_triquetra.secondary_slot,
		window_triquetra.ternary_slot,
		window_triquetra.primary_buffer[1],
	}) do
		local bufnr = history.get_buffer_from_hash(filehash)
		if bufnr and not vim.api.nvim_buf_is_valid(bufnr) then
			require('cavediver.domains.ledger').within("timer", "cleanup", history.routines.cleanup_system)
			window_triquetra = window.get_triquetra(winid)
			if not window_triquetra then
				return nil
			end
			break
		end
	end
	local ui_triquetra = data.get_or_create_window_display_cache(winid)

	-- Helper function to resolve slot data from filehash
	local function resolve_slot(filehash)
		local filepath = history.get_filepath_from_hash(filehash)
		if not filehash or not filepath then
			return nil, nil, false, false, false, false
		end

		local bufnr = history.get_buffer_from_hash(filehash)
		local display_name = M.get_smart_basename(filehash) or nil

		if bufnr ~= nil then
			-- Buffer exists in memory
			local is_loaded = vim.api.nvim_buf_is_loaded(bufnr)
			derive_cache_lock[winid] = nil
			return bufnr, display_name, true, is_loaded, false
		else
			-- Check if it's a closed buffer
			local is_closed = history.routines.is_filehash_closed(filehash) -- on any pool
			if is_closed then
				-- Closed buffer - can be reopened
				derive_cache_lock[winid] = nil
				return nil, display_name, true, false, true -- exists=true, loaded=false
			else
				filepath = history.get_filepath_from_hash(filehash)
				if filepath == nil then
					if not derive_cache_lock[winid] then
						window.routines.cleanup_triquetras() -- I know it's really good to do this, but we need to clean up the triquetra.
						return nil, nil, false, false, false
					else
						error("This is unexpected: file " .. display_name .. " has no buffer or closed state. " .. winid .. "\n" .. debug.traceback())
					end
				elseif vim.fn.filereadable(filepath) == 1 then -- ignore if the file is already deleted.
					if not derive_cache_lock[winid] then
						window.routines.cleanup_triquetras() -- I know it's really good to do this, but we need to clean up the triquetra.
						return nil, nil, false, false, false
					else
						error("This is unexpected: file " .. display_name .. " This thing happens? " .. winid .. "\n" .. debug.traceback())
					end
				end
				return nil, nil, false, false, false
			end
		end
	end

	-- Update all slots using the hash-based WindowTriquetra structure
	ui_triquetra.current_bufnr, ui_triquetra.current_display_name, _, _, ui_triquetra.deleted_slots.current =
		resolve_slot(window_triquetra.current_slot)
	-- a window showing something we don't track is visiting it. it shows the buftype, or the filetype for a
	-- buffer that looks like a file (oil's acwrite).
	local shown = vim.api.nvim_win_get_buf(winid)
	if history.get_hash_from_buffer(shown) == nil then
		local buftype = vim.bo[shown].buftype
		ui_triquetra.visiting = (buftype == "" or buftype == "acwrite") and vim.bo[shown].filetype or buftype
	else
		ui_triquetra.visiting = nil
	end
	ui_triquetra.primary_bufnr, ui_triquetra.primary_display_name, ui_triquetra.has_primary, _, _ =
		resolve_slot(window_triquetra.primary_buffer[1])
	ui_triquetra.secondary_bufnr, ui_triquetra.secondary_display_name, ui_triquetra.has_secondary, ui_triquetra.loaded_slots.secondary, ui_triquetra.deleted_slots.secondary =
		resolve_slot(window_triquetra.secondary_slot)
	ui_triquetra.ternary_bufnr, ui_triquetra.ternary_display_name, ui_triquetra.has_ternary, ui_triquetra.loaded_slots.ternary, ui_triquetra.deleted_slots.ternary =
		resolve_slot(window_triquetra.ternary_slot)

	-- a file gone from disk shows where it went missing
	ui_triquetra.missing = {
		current = history.data.missing[window_triquetra.current_slot],
		secondary = window_triquetra.secondary_slot and history.data.missing[window_triquetra.secondary_slot],
		ternary = window_triquetra.ternary_slot and history.data.missing[window_triquetra.ternary_slot],
	}

	-- reflect the primary_enabled state.
	ui_triquetra.has_primary = ui_triquetra.has_primary and window_triquetra.primary_enabled

	if ui_triquetra.current_bufnr == nil and not (ui_triquetra.deleted_slots.current and ui_triquetra.visiting) then
		-- the retry is counted here: resolve_slot clears derive_cache_lock when another slot resolves.
		if not again then
			derive_cache_lock[winid] = true
			window.routines.cleanup_triquetras() -- I know it's really good to do this, but we need to clean up the triquetra.
			return derive_cache_from_window_triquetra(winid, true) -- We redo it again.
		else
			error("Impossible state: current_bufnr is nil in derive_cache_from_window_triquetra() for winid " .. winid .. " , even cleanup_triquetras() couldn't fix it. So what the fuck right?")
		end
	end

	derive_cache_lock[winid] = nil

	return ui_triquetra
end


function M.set_cache_from_window_triquetra(winid)
	data.window_display_cache[winid] = derive_cache_from_window_triquetra(winid)
end

---Update bufferline state cache for performance optimization.
---
---Pre-computes buffer states for the bufferline to avoid expensive calculations
---during rendering. This is the migrated update_bufferline_state() function.
---
---@return nil
-- Function to update the cache state
function M.refresh_ui(cwin)
	local harpoon = require("harpoon")
	local cbuf = vim.api.nvim_win_get_buf(cwin)
	local cache = data.bufferline_state
	-- Update harpooned buffers cache
	local harpooned_list = harpoon:list():display()
	-- Helper function to map keys (from original buffers.lua)
	local function map_keys_trans_bufnr(tbl)
		local return_tbl = {}
		for idx, value in ipairs(tbl) do
			return_tbl[value] = idx
		end
		return return_tbl
	end
	cache.harpooned_lookup = map_keys_trans_bufnr(harpooned_list)
	-- Pre-compute which buffers are harpooned
	cache.harpooned_buffers = {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")
			cache.harpooned_buffers[bufnr] = cache.harpooned_lookup[path] ~= nil
			if cache.harpooned_buffers[bufnr] then
				cache.harpooned_lookup[bufnr] = cache.harpooned_lookup[path]
				cache.harpooned_lookup[path] = nil
			end
		end
	end
	-- Pre-compute buffer rankings using history domain data
	cache.buffer_ranking = {}
	for filehash, time in pairs(history.data.crux) do
		if filehash and history.data.hash_buffer_registry.buffers[filehash] then
			cache.buffer_ranking[history.data.hash_buffer_registry.buffers[filehash]] = time
		end
	end
	-- Pre-compute recent buffers using history domain data
	cache.recent_buffers = {}
	for i = 1, math.max(#history.data.ordered.crux, 30) do
		if i <= #history.data.ordered.crux then
			local recent = history.data.ordered.crux[i]
			if recent and recent.buf then
				cache.recent_buffers[recent.buf] = true
			end
		end
	end
	cache.current_buf = cbuf
	cache.history_detached = history.is_detached()

	-- Update current window triquetra display cache
	cache.current_window_triquetra = derive_cache_from_window_triquetra(cwin) or cache.current_window_triquetra

	cache.initialized = true
end

local function get_window_column_range(win_id)
	local win_info = vim.fn.getwininfo(win_id)[1]
	return {
		start = win_info.wincol,
		end_ = win_info.wincol + win_info.width,
	}
end

---@param winid1 WinId
---@param winid2 WinId
local function windows_overlap_horizontally(winid1, winid2)
	local range1 = get_window_column_range(winid1)
	local range2 = get_window_column_range(winid2)

	-- Mathematics of intersection reveals hidden connections
	return not (range1.end_ <= range2.start or range2.end_ <= range1.start)
end


---@param winid WinId
---@param theme UITriquetraTheme
local function construct_winbar_string(winid, theme)
	local triquetra = data.get_or_create_window_display_cache(winid)

	if triquetra == nil then
		error("This should never happen, current_window_triquetra is nil")
	end

	local fmt_sbufnr, fmt_cbufnr
	fmt_cbufnr = "[%d]"
	fmt_sbufnr = "⟦%d⟧"


	if navigation.is_cycling() then
		theme.current_slot_filename = theme.base
	end

	if triquetra.has_primary then
		if triquetra.primary_display_name == triquetra.current_display_name then
			theme.current_slot_bufnr = theme.primary_bufnr
			fmt_cbufnr = "⦉%d⦊"
		elseif triquetra.primary_display_name == triquetra.secondary_display_name then
			theme.secondary_slot_bufnr = theme.primary_bufnr
			fmt_sbufnr = "⦉%d⦊"
		elseif triquetra.primary_display_name == triquetra.ternary_display_name then
			theme.ternary_slot_bufnr = theme.primary_bufnr
		end
	else
		if triquetra.primary_display_name == triquetra.current_display_name then
			fmt_cbufnr = "⦉%d⦊"
			theme.current_slot_bufnr = "WinbarBufnrPrimaryDisabled"
		elseif triquetra.primary_display_name == triquetra.secondary_display_name then
			theme.secondary_slot_bufnr = "WinbarBufnrPrimaryDisabled"
			fmt_sbufnr = "⦉%d⦊"
		elseif triquetra.primary_display_name == triquetra.ternary_display_name then
			theme.ternary_slot_bufnr = "WinbarBufnrPrimaryDisabled"
		end
	end

	local display_string = ""
	local display_string_length = 0

	-- a file gone from disk shows, dimmed, where it went missing
	local function missing_tag(slot)
		local tag = triquetra.missing and triquetra.missing[slot]
		if not tag then
			return
		end
		display_string = display_string .. string.format("%%#Comment#⎇%s ", tag)
		display_string_length = display_string_length + vim.api.nvim_strwidth("⎇" .. tag) + 1
	end

	if triquetra.has_ternary then
		if not triquetra.deleted_slots.ternary then
			display_string = display_string .. string.format(
				"%%#%s#⦉%d⦊ ",
				theme.ternary_slot_bufnr, triquetra.ternary_bufnr
			)
			display_string_length = display_string_length + 3 +
				vim.api.nvim_strwidth(tostring(triquetra.ternary_bufnr))
		else
			display_string = display_string .. string.format(
				"%%#%s#⦉ %%#%s# %%#%s# %s ⦊ ",
				theme.ternary_slot_filename, theme.ternary_slot_bufnr, theme.ternary_slot_filename,
				triquetra.ternary_display_name
			)
			display_string_length = display_string_length +
				8 + vim.api.nvim_strwidth(triquetra.ternary_display_name)
		end
		missing_tag("ternary")
	end

	local current_name = triquetra.current_display_name
	if triquetra.visiting then
		current_name = current_name .. " ← [" .. triquetra.visiting .. "]"
	end

	if triquetra.current_bufnr == nil and triquetra.deleted_slots.current then
		-- a closed current slot, while visiting: the closed icon stands where its number goes.
		display_string = display_string .. string.format(
			"%%#%s#[\u{f4c5}] %%#%s#%s%%#%s# ",
			theme.current_slot_bufnr, theme.current_slot_filename, current_name, theme.secondary_slot_filename
		)
		display_string_length = display_string_length + 5 + vim.api.nvim_strwidth(current_name)
		missing_tag("current")
		goto secondary
	end

	if triquetra.current_bufnr == nil then
		local window_triquetra = window.get_triquetra(winid)
		local debug_info = {
			winid = winid,
			current_slot = window_triquetra and window_triquetra.current_slot or "nil",
			filepath_exists = window_triquetra and window_triquetra.current_slot and
				history.get_filepath_from_hash(window_triquetra.current_slot) or "lookup_failed",
			buffer_exists = window_triquetra and window_triquetra.current_slot and
				history.get_buffer_from_hash(window_triquetra.current_slot) or "lookup_failed",
			actual_winbuf = vim.api.nvim_win_get_buf(winid)
		}
		vim.notify("WINBAR STATE CORRUPTION: current_bufnr is nil | " .. vim.inspect(debug_info), vim.log.levels.WARN)
		vim.wo[winid].winbar = ""
		return
	end

	if vim.bo[triquetra.current_bufnr].modified then
		display_string = display_string .. string.format(
			"%%#%s#" .. fmt_cbufnr .. " %%#%s#%s%%#%s#  ",
			theme.current_slot_bufnr, triquetra.current_bufnr, theme.current_slot_filename,
			current_name, theme.secondary_slot_filename
		)
		display_string_length = display_string_length + 6
	else
		display_string = display_string .. string.format(
			"%%#%s#" .. fmt_cbufnr .. " %%#%s#%s%%#%s# ",
			theme.current_slot_bufnr, triquetra.current_bufnr, theme.current_slot_filename,
			current_name, theme.secondary_slot_filename
		)
		display_string_length = display_string_length + 4
	end

	display_string_length = display_string_length +
		vim.api.nvim_strwidth(current_name) +
		vim.api.nvim_strwidth(tostring(triquetra.current_bufnr))
	missing_tag("current")

	::secondary::

	if triquetra.has_secondary then
		if not triquetra.deleted_slots.secondary then
			if vim.bo[triquetra.secondary_bufnr].modified then
				display_string = display_string .. string.format(
					"%%#%s#   %%#%s#" .. fmt_sbufnr .. " %%#%s#%s  ",
					theme.both_way_arrow, theme.secondary_slot_bufnr, triquetra.secondary_bufnr,
					theme.secondary_slot_filename, triquetra.secondary_display_name
				)
				display_string_length = display_string_length + 10
			else
				display_string = display_string .. string.format(
					"%%#%s#   %%#%s#" .. fmt_sbufnr .. " %%#%s#%s ",
					theme.both_way_arrow, theme.secondary_slot_bufnr, triquetra.secondary_bufnr,
					theme.secondary_slot_filename, triquetra.secondary_display_name
				)
				display_string_length = display_string_length + 8
			end
			display_string_length = display_string_length + vim.api.nvim_strwidth(triquetra.secondary_display_name) +
				vim.api.nvim_strwidth(tostring(triquetra.secondary_bufnr))
		else
			display_string = display_string .. string.format(
				"%%#%s#  %%#%s#   %%#%s#%s ",
				theme.both_way_arrow, theme.secondary_slot_bufnr, theme.secondary_slot_filename,
				triquetra.secondary_display_name
			)
			display_string_length = display_string_length + 8
			display_string_length = display_string_length + vim.api.nvim_strwidth(triquetra.secondary_display_name)
		end
		missing_tag("secondary")
	end

	local diff = vim.api.nvim_strwidth(display_string)
	display_string = string.gsub(display_string, "zsh:terminal", "terminal:")
	diff = diff - vim.api.nvim_strwidth(display_string)

	display_string_length = display_string_length - diff

	display_string = string.format("%%#%s#────── ", theme.base) .. display_string
	display_string_length = display_string_length + 7

	local padding_length = vim.api.nvim_win_get_width(winid) - display_string_length
	display_string = display_string .. "%#" .. theme.base .. "#" .. string.rep("─", math.max(0, padding_length))

	vim.wo[winid].winbar = display_string
end

---@param winid WinId
function M.remove_winbar_string(winid)
	vim.wo[winid].winbar = ""
end


---@param winid WinId
---@param topwin WinId
local function update_topwin_winbar(winid, topwin)
	local winid_is_focused = vim.api.nvim_get_current_win() == winid
	local top_win_is_focused = vim.api.nvim_get_current_win() == topwin
	local cache = data.bufferline_state
	---@type UITriquetraTheme
	local theme

	-- local debug = "top_win: " .. top_win

	-- if this is true that means we don't need to reupdate this top_window's winbar,
	-- because it already found a window that it overlaps to.
	if preserve_winbar_overlap[topwin] then
		return 1
	end

	if windows_overlap_horizontally(winid, topwin) then
		if top_win_is_focused then
			theme = vim.deepcopy(data.winbar_themes.focused)
			preserve_winbar_overlap[topwin] = true
		else
			if winid_is_focused then
				theme = vim.deepcopy(data.winbar_themes.topwin_overlapped)
				preserve_winbar_overlap[topwin] = true
			else
				theme = vim.deepcopy(data.winbar_themes.unfocused)
			end
		end
	else
		theme = vim.deepcopy(data.winbar_themes.unfocused)
	end
	construct_winbar_string(topwin, theme)
end

---@param winid WinId
local function update_win_winbar(winid)
	---@type UITriquetraTheme
	local theme

	local winid_is_focused = vim.api.nvim_get_current_win() == winid
	-- local debug

	-- Determine highlight groups based on focus
	if winid_is_focused then
		theme = vim.deepcopy(data.winbar_themes.focused)
	else
		theme = vim.deepcopy(data.winbar_themes.unfocused)
	end

	construct_winbar_string(winid, theme)
end


function M.is_real_file(bufnr, win_id)
	local buftype = vim.bo[bufnr].buftype
	local filetype = vim.bo[bufnr].filetype
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local filetype = vim.bo[bufnr].filetype
	local win_config = vim.api.nvim_win_get_config(win_id)

	-- Exclude floating/popup windows
	if win_config.relative ~= "" then
		return false
	end

	if filetype == "image_nvim" then
		return true
	end

	-- In the silence between keystrokes, we find truth
	local value = (buftype == "" or buftype == "terminal" or buftype == "acwrite") -- Empty buftype signifies a normal file buffer
		and vim.api.nvim_buf_is_loaded(bufnr)
		and (not vim.api.nvim_buf_get_name(bufnr):match("://") or buftype == "acwrite")
		and not vim.tbl_contains(data.excluded_filetypes, filetype)
		-- Allow no-name buffers for regular windows, exclude for popups
		and (bufname ~= "" or win_config.relative == "")

	return value
end

---Whether a window shows something we don't track (help, a terminal), so its triquetra's winbar shows
---the visit. Floats and the skipped filetypes get none, as for files.
---
---@param bufnr Bufnr
---@param win_id WinId
---@return boolean
function M.is_visiting(bufnr, win_id)
	return history.get_hash_from_buffer(bufnr) == nil
		and vim.api.nvim_buf_is_loaded(bufnr)
		and vim.api.nvim_win_get_config(win_id).relative == ""
		and not vim.tbl_contains(data.excluded_filetypes, vim.bo[bufnr].filetype)
end

local function window_touches_top(win_id)
	-- Retrieve precise window coordinates
	-- local win_config = vim.api.nvim_win_get_config(win_id)
	local win_info = vim.fn.getwininfo(win_id)[1]

	-- A window's vertical solitude is measured in its distance from origin
	return win_info.winrow <= 2
end


local function update_all_winbars()
	local top_windows = {}
	local all_windows = {}
	-- local current_win = vim.api.nvim_get_current_win()

	-- First pass: identify windows touching the upper boundary
	for win, _ in pairs(window.data.crux) do
		local buf = vim.api.nvim_win_get_buf(win)
		if M.is_real_file(buf, win) or M.is_visiting(buf, win) then
			if window_touches_top(win) then
				table.insert(top_windows, win)
				update_topwin_winbar(win, win)
			else
				table.insert(all_windows, win)
				if vim.bo[buf].buftype ~= "terminal" then -- yes we include this to the logic, but it won't be visually affected.
					update_win_winbar(win)
				end
			end
		end
	end

	-- Second pass: update winbars based on spatial relationships
	for _, top_win in ipairs(top_windows) do
		for _, win in ipairs(all_windows) do
			update_topwin_winbar(win, top_win)
		end
	end
	-- reset the preserve_winbar_overlap state table
	preserve_winbar_overlap = {}
end

---We now need to show the UI Cache.
---
---@return nil
function M.show_ui()
	update_all_winbars()
end

---Debounce UI refresh to avoid exessive updates.
---
---@return nil
function M.debounced_update()
	if not update_timer then
		return
	end

	if update_timer:is_active() then
		update_timer:stop()
	end
	update_timer:start(
		100,
		0,
		vim.schedule_wrap(function()
			uiMachines.loop:to(states.LOOP.SELF)
		end)
	)
end

return M
