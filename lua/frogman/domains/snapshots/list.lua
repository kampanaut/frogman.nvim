---The snapshot list.
---
---One editable floating window on a window's snapshots, newest first, then those held over in its
---session's scope, a group to a header, each header a line of its own that the list keeps in place.
---Each snapshot's line is its whole encoding, sealed and concealed, and what shows is drawn over it in
---the trail's language: the time, the triquetra in the winbar's colours, and the order its bufferline
---drew. Deleting a line and writing deletes its snapshot, and a line moved under another header, or
---yanked or cut from one window's list and put in another's, carries its snapshot to where it sits.

local routines = require('frogman.domains.snapshots.routines')
local history = require('frogman.domains.history')

local M = {}

local NAME = "frogman://snapshots"
local DIRTY = "frogman: the snapshot list has edits not written yet: write them with :w, or leave them, first."
local ns = vim.api.nvim_create_namespace("frogman_snapshots")

---The list that's open: its buffer, its window, the window it was opened from, the session whose
---held-over snapshots it shows, its headers as drawn with their marks and the snapshots drawn under each,
---and the lines last intact.
---@type {buf: Bufnr, win: WinId, origin: WinId, session: string, headers: table<string, true>, header_order: string[], header_marks: table<string, integer>, drawn_under: table<string, string[]>, intact: string[], intact_rows: table<string, integer>}|nil
local open = nil

---Check if the list is open, its buffer still there.
---@return boolean
local function is_open()
	return open ~= nil and vim.api.nvim_buf_is_valid(open.buf)
end

---Get the session whose held-over snapshots the list shows: the one the window it was opened from
---is in, read as the list opened.
---@return string session_id
local function session()
	return open.session
end

---Get the window the list acts on: the one it was opened from, while it's there.
---@return WinId|nil winid
function M.origin()
	if is_open() and vim.api.nvim_win_is_valid(open.origin) then
		return open.origin
	end
	return nil
end

---What each line text decodes to, once each: its carried snapshot, or false
---@type table<string, table|false>
local decoded = {}

---This editor's salt for the lines it draws, made with its first line. A line carries it, so any
---editor started in the same directory stretches the same key from it.
---@type string|nil
local salt = nil

---The directories this editor drew lines under, where a line carrying its own salt is tried besides the
---cwd, so one a plugin's change of cwd left behind opens; another editor's line can't be one of those.
---@type table<string, true>
local drawn_in = {}

---The directories an answer opened a line under while the list is open, where every line is tried
---besides the cwd.
---@type table<string, true>
local answered = {}

---The lines the open list sealed, by the directory and the JSON each carries.
---@type table<string, string>
local sealed_lines = {}

---Wrap a carried snapshot as a line: `fs1:` and the base64 of its JSON sealed as a session's file is,
---under a key stretched from the editor's global directory and this editor's salt, the word
---`snapshot` under the seal besides.
---
---@param carried table As `routines.carried` gives it
---@return string line
function M.wrap(carried)
	local crypto = require('frogman.domains.storage.crypto')
	local storage = require('frogman.domains.storage.routines')
	salt = salt or crypto.random_bytes(crypto.salt_length)
	local cwd = vim.fn.getcwd(-1, -1)
	drawn_in[cwd] = true
	return "fs1:" .. vim.base64.encode(storage.sealed(storage.key_for(cwd, salt), salt, vim.json.encode(carried), "snapshot"))
end

---Open a line's seal under one directory: what it carries, or nil.
---
---@param bytes string The line's sealed bytes
---@param directory string
---@return table|nil carried
local function open_under(bytes, directory)
	local opened, json = pcall(require('frogman.domains.storage.routines').open_sealed, bytes, directory, "snapshot")
	if not (opened and type(json) == "string") then
		return nil
	end
	local parsed, carried = pcall(vim.json.decode, json)
	if parsed and type(carried) == "table" and carried.v == 1 and type(carried.id) == "string"
		and type(carried.files) == "table" then
		return carried
	end
	return nil
end

---Check if a line is a snapshot's line by its shape, opening or not.
---@param line string
---@return boolean
local function is_sealed_line(line)
	return vim.trim(line or ""):match("^fs1:[%w%+/=]+$") ~= nil
end

---Decode a line: the snapshot it carries, when it's one of frogman's and its seal opens, its bytes as
---they are, under the cwd, a directory an answer opened a line under, or, for a line carrying this
---editor's own salt, a directory this editor drew lines under.
---
---@param line string
---@return table|nil carried A copy of what it carries
function M.decode(line)
	line = vim.trim(line or "")
	if decoded[line] == nil then
		decoded[line] = false
		local base64 = line:match("^fs1:([%w%+/=]+)$")
		local ok, bytes = pcall(vim.base64.decode, base64 or "")
		if base64 and ok and type(bytes) == "string" then
			local cwd = vim.fn.getcwd(-1, -1)
			decoded[line] = open_under(bytes, cwd) or false
			-- the answered directories for any line; the ones drawn in for this editor's own lines alone,
			-- so another editor's line stretches no key for each
			local tried = { [cwd] = true }
			local own = salt ~= nil and require('frogman.domains.storage.routines').salt_of(bytes) == salt
			for _, directories in ipairs({ answered, own and drawn_in or {} }) do
				for directory, _ in pairs(directories) do
					if not decoded[line] and not tried[directory] then
						tried[directory] = true
						decoded[line] = open_under(bytes, directory) or false
					end
				end
			end
		end
	end
	return decoded[line] and vim.deepcopy(decoded[line]) or nil
end

---Ask for the directory the lines that don't open were drawn in: once for all of them, and again while
---any is still shut, stopping once an answer opens nothing new, as an empty answer does. A directory that
---opened one is tried from then on.
---
---@param lines string[] The list's lines
---@return nil
local function open_shut(lines)
	local function shut()
		return vim.tbl_filter(function(line) return is_sealed_line(line) and not M.decode(line) end, lines)
	end
	local left = shut()
	while #left > 0 do
		local answer = vim.fn.input({
			prompt = "frogman: " .. #left .. " snapshot line" .. (#left == 1 and " doesn't" or "s don't") ..
				" open here; the directory " .. (#left == 1 and "it was" or "they were") .. " drawn in: ",
			completion = "dir", cancelreturn = "",
		})
		if vim.trim(answer or "") == "" then
			return
		end
		local directory = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(vim.trim(answer)), ":p"))
		if directory ~= "/" then
			directory = directory:gsub("/+$", "")
		end
		local was = answered[directory]
		answered[directory] = true
		for line, carried in pairs(decoded) do
			if carried == false then
				decoded[line] = nil -- tried again, with the new directory among the rest
			end
		end
		local now = shut()
		if #now == #left then
			if not was then
				answered[directory] = nil -- it opened nothing: not one to try again
			end
			return
		end
		left = now
	end
end

---Get a snapshot's line: its whole encoding.
---@param snapshot Snapshot
---@return string line
local function line_of(snapshot)
	local carried = routines.carried(snapshot)
	-- sealed once while the list is open: the same snapshot, carrying the same, draws the same line
	local key = vim.fn.getcwd(-1, -1) .. "\n" .. vim.json.encode(carried)
	sealed_lines[key] = sealed_lines[key] or M.wrap(carried)
	return sealed_lines[key]
end

---Get the snapshot a line names.
---@param line string
---@return string|nil id
local function id_in(line)
	local carried = M.decode(line)
	return carried and carried.id
end

---Draw a line no snapshot here answers to yet, a pasted one, from what it carries: its time, its
---triquetra by the files' names, and that a write takes it in.
---
---@param carried table
---@return table chunks
local function drawing_of_carried(carried)
	local function name(i)
		local file = type(i) == "number" and carried.files[i]
		return type(file) == "table" and type(file.path) == "string" and vim.fs.basename(file.path) or "-"
	end
	local time = type(carried.time) == "number" and os.date("%m-%d %H:%M", carried.time) or "--"
	return {
		{ time .. "  ", "FrogmanTrailTime" },
		{ "⦉" .. name(carried.t) .. "⦊ [" .. name(carried.c) .. "] ⟦" .. name(carried.s) .. "⟧", "FrogmanTrailDim" },
		{ "  pasted: a write takes it in", "FrogmanTrailDim" },
	}
end

---Draw a snapshot's line as it shows: the time, the triquetra, then the stored order.
---
---@param snapshot Snapshot The snapshot to draw
---@param labels table<HandleId, string> The marks' aliases, as `marks.labels` gives them
---@return table chunks The `{text, highlight}` chunks
local function drawing(snapshot, labels)
	local ui = require('frogman.domains.ui').routines
	local glyphs = ui.glyphs()
	local function name(id)
		local handle = routines.handle(id)
		return handle and ui.get_smart_basename(handle.id) or "?"
	end
	local today = os.date("%Y-%m-%d") == os.date("%Y-%m-%d", snapshot.time)
	local chunks = { { os.date(today and "%H:%M" or "%m-%d %H:%M", snapshot.time) .. "  ", "FrogmanTrailTime" } }
	table.insert(chunks, { "⦉" .. (snapshot.ternary and name(snapshot.ternary) or "-") .. "⦊ ", "WinbarBufnrTernary" })
	table.insert(chunks, { "[" .. name(snapshot.current) .. "] ", "WinbarBufnrCurrent" })
	table.insert(chunks, { "⟦" .. (snapshot.secondary and name(snapshot.secondary) or "-") .. "⟧", "WinbarBufnrSecondary" })
	for _, id in ipairs(snapshot.order) do
		local handle = routines.handle(id)
		if handle then
			local bufnr = history.get_buffer_from_handle(handle.id)
			local label = labels[handle.id]
			local text = name(id) .. (label and (" ⟨" .. label .. "⟩") or "")
			if handle.tag then
				table.insert(chunks, { "  ✗ ", "DiagnosticError" })
				table.insert(chunks, { text .. " " .. glyphs.tag .. handle.tag, "FrogmanTrailDim" })
			elseif bufnr == nil then
				table.insert(chunks, { "  " .. glyphs.closed .. " " .. text, "FrogmanTrailDim" })
			else
				table.insert(chunks, { "  " .. bufnr .. " " .. text, "FrogmanTrail" })
			end
		end
	end
	return chunks
end

---Draw the list's lines again: each header dimmed, and each known snapshot's line concealed, with its
---drawing over it.
---@return nil
local function decorate()
	if not is_open() then
		return
	end
	vim.api.nvim_buf_clear_namespace(open.buf, ns, 0, -1)
	local labels = require('frogman.domains.marks').labels(M.origin())
	for i, line in ipairs(vim.api.nvim_buf_get_lines(open.buf, 0, -1, false)) do
		if open.headers[vim.trim(line)] then
			vim.api.nvim_buf_set_extmark(open.buf, ns, i - 1, 0, { end_col = #line, hl_group = "FrogmanTrailDim" })
		else
			local carried = M.decode(line)
			if carried then
				local snapshot = routines.find(carried.id)
				-- the encoding hidden, and the drawing after it, so the cursor at the line's start stays there
				vim.api.nvim_buf_set_extmark(open.buf, ns, i - 1, 0, { end_col = #line, conceal = "" })
				vim.api.nvim_buf_set_extmark(open.buf, ns, i - 1, #line,
					{ virt_text = snapshot and drawing(snapshot, labels) or drawing_of_carried(carried), virt_text_pos = "inline" })
			end
		end
	end
end

---Put the window's snapshots in the list's lines, newest first, then its session's held-over ones, a
---group to a header: the group held over last first, and each group's newest first.
---@return nil
local function redraw()
	local lines, headers, header_order, drawn, drawn_under = {}, {}, {}, {}, {}
	local snapshots = routines.of_window(open.origin)
	for i = #snapshots, 1, -1 do
		table.insert(lines, line_of(snapshots[i]))
		drawn[snapshots[i].id] = true
	end
	local groups, order = {}, {}
	for _, snapshot in ipairs(routines.held_in(session())) do
		if groups[snapshot.held] == nil then
			groups[snapshot.held] = {}
			table.insert(order, snapshot.held)
		end
		table.insert(groups[snapshot.held], snapshot)
	end
	for g = #order, 1, -1 do
		local header, members = order[g], groups[order[g]]
		headers[header] = true
		table.insert(header_order, header)
		table.insert(lines, header)
		drawn_under[header] = {}
		for i = #members, 1, -1 do
			table.insert(lines, line_of(members[i]))
			drawn[members[i].id] = true
			table.insert(drawn_under[header], members[i].id)
		end
	end
	-- what the write may delete: a snapshot taken or held over since stays
	open.headers, open.header_order, open.intact, open.drawn = headers, header_order, lines, drawn
	open.drawn_under = drawn_under
	vim.api.nvim_buf_set_lines(open.buf, 0, -1, false, lines)
	require('frogman.domains.ui').routines.mark_headers(open.buf, open)
	vim.bo[open.buf].modified = false
	decorate()
end

---Write the list: a snapshot it drew whose line is gone is deleted, and a line carries its snapshot to
---where it sits. One taken or held over since the list was drawn stays.
---
---Each line is read by where it sits: above the first header, among the window's own, or under a
---held-over header. A line naming a snapshot already where it sits keeps it. One naming a snapshot
---alive elsewhere, another window's, held over elsewhere or under another header, or a second line
---naming one kept here, makes a copy of it where it sits. Any other is rebuilt from what it carries,
---where it sits. A line that doesn't open, one that carries a snapshot with nothing left to come back,
---and a pasted copy of a header are asked about first: Yes leaves them out, the lines under a copy staying
---with the group above, and No writes nothing, the cursor on the first such line. A header it drew that
---no line holds refuses the write, saying so, the cursor on the first snapshot drawn under it. With the
---window the list was opened from gone, nothing is written, the edits kept, as the marks pop-up keeps them.
---
---@return boolean written
local function write()
	if not M.origin() then
		vim.notify("frogman: the window this list was for is gone, so it isn't written.", vim.log.levels.WARN)
		return false
	end
	local lines = vim.api.nvim_buf_get_lines(open.buf, 0, -1, false)
	local ui = require('frogman.domains.ui').routines
	local rows, header_copies, missing, live = ui.header_rows(open.buf, open, lines)
	if missing then
		-- the cursor on the first snapshot drawn under it: where the header was while the marks are live, else
		-- that snapshot's line where it still stands
		local row = live and ui.missing_row(open.buf, open, missing)
		if not row then
			local under = {}
			for _, id in ipairs(open.drawn_under[missing] or {}) do
				under[id] = true
			end
			for at, line in ipairs(lines) do
				if under[id_in(line) or false] then
					row = at
					break
				end
			end
		end
		if row and open.win and vim.api.nvim_win_is_valid(open.win) then
			vim.api.nvim_win_set_cursor(open.win, { row, 0 })
		end
		vim.notify('frogman: the header "' .. missing .. '" is missing: put it back, or :q! to discard.', vim.log.levels.WARN)
		return false
	end
	open_shut(lines)
	local kept, copies, rebuilt, items, first = {}, {}, {}, {}, nil
	local into = { winid = open.origin } -- above the first header, the window's own
	for row, line in ipairs(lines) do
		line = vim.trim(line)
		if rows[row] then
			into = { session = session(), held = line }
		elseif header_copies[row] then
			-- the lines under it stay with the group above
			table.insert(items, line .. "  a copy of a header")
			first = first or row
		elseif line ~= "" then
			local carried = M.decode(line)
			local snapshot, winid, held_in = nil, nil, nil
			if carried then
				snapshot, winid, held_in = routines.find(carried.id)
			end
			local here = snapshot ~= nil and (into.held == nil and winid == open.origin
				or (into.held ~= nil and held_in == session() and snapshot.held == into.held))
			if here and not kept[carried.id] then
				kept[carried.id] = true
			elseif snapshot then
				table.insert(copies, { into = into, snapshot = snapshot })
			elseif carried and routines.rebuild(into, carried, true) then
				table.insert(rebuilt, { into = into, carried = carried })
			else
				-- a line of a few thousand characters is named by its start
				table.insert(items, (#line > 40 and (line:sub(1, 40) .. "…") or line) .. "  names no snapshot of this window")
				first = first or row
			end
		end
	end
	if #items > 0 and vim.fn.confirm("frogman: these lines would be left out:\n" .. table.concat(items, "\n") ..
			"\nWrite the rest?", "&Yes\n&No", 2) ~= 1 then
		if open.win and vim.api.nvim_win_is_valid(open.win) then
			vim.api.nvim_win_set_cursor(open.win, { first, 0 })
		end
		return false
	end
	for _, list in ipairs({ routines.of_window(open.origin), routines.held_in(session()) }) do
		for _, snapshot in ipairs(vim.list_slice(list)) do
			if open.drawn[snapshot.id] and not kept[snapshot.id] then
				routines.delete(snapshot.id)
			end
		end
	end
	for _, copy in ipairs(copies) do
		routines.copy(copy.into, copy.snapshot)
	end
	for _, line in ipairs(rebuilt) do
		routines.rebuild(line.into, line.carried)
	end
	redraw()
	return true
end

---Write the list when it was edited, then leave it; a write answered No leaves it open. With the window it
---was opened from gone, it leaves, the edits dropped, and says so.
---@return nil
function M.leave()
	if not is_open() then
		return
	end
	if not M.origin() and vim.bo[open.buf].modified then
		vim.notify("frogman: the window these were for is gone: the edits are dropped.", vim.log.levels.WARN)
		if open.win and vim.api.nvim_win_is_valid(open.win) then
			vim.api.nvim_win_close(open.win, true)
		end
		return
	end
	require('frogman.domains.ui.view').leave(open.buf, open.win, write)
end

---Open the snapshot list on the window you're in, the cursor on its first snapshot's line.
---
---With edits not written yet, the list stays as it is, focused, and says so. The lines are sealed, so
---with no way to seal them, libcrypto missing, it says so and opens nothing.
---
---@return nil
function M.open()
	local view = require('frogman.domains.ui.view')
	if is_open() then
		if view.keep_if_dirty(open.buf, open.win, DIRTY) then
			return
		end
		if open.win and vim.api.nvim_win_is_valid(open.win) then
			vim.api.nvim_win_close(open.win, true)
		end
	end
	local sealing, problem = pcall(M.wrap, { v = 1 })
	if not sealing then
		vim.notify("frogman: the snapshot list's lines are sealed, and sealing failed: " .. tostring(problem), vim.log.levels.WARN)
		return
	end
	local origin = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_config(origin).relative ~= "" then
		origin = require('frogman.domains.navigation.routines').find_most_recent_tracked_window() or origin
	end
	decoded = {} -- what the last list decoded, its lines no longer here
	answered = {} -- and the directories its answers opened
	sealed_lines = {} -- and the lines it sealed
	local _, win = view.open({
		name = NAME, filetype = "frogman-snapshots", title = "Snapshots", size = require('frogman.configs').snapshots_popup,
		events = { "TextChanged", "TextChangedI", "TextChangedP" },
		fill = function(buf)
			open = { buf = buf, origin = origin, session = routines.session_of(origin) }
			redraw()
		end,
		write = write,
		changed = function(event)
			if is_open() then
				require('frogman.domains.ui').routines.guard_headers(open.buf, event ~= "TextChanged", open)
				decorate()
			end
		end,
		closed = function(buf)
			if open and open.buf == buf then
				open = nil
			end
		end,
		window = { conceallevel = 2, concealcursor = "nvic" },
	})
	open.win = win
	for i, line in ipairs(open.intact) do
		if not open.headers[line] then
			vim.api.nvim_win_set_cursor(win, { i, 0 }) -- the first snapshot's line (mine)
			break
		end
	end
end

---Show the snapshot on the cursor's line in the window the list was opened from, leaving the list.
---
---While the list has edits not written yet, it refuses and says so. With that window gone, it says so
---and opens nvim-window-picker's picker; the snapshot shows in the window picked, and picking none, or
---a float, leaves the list open, and so does a picker that raises, which says so.
---
---@return nil
function M.show()
	if not is_open() then
		return
	end
	if vim.bo[open.buf].modified then
		vim.notify(DIRTY, vim.log.levels.WARN)
		return
	end
	local id = id_in(vim.api.nvim_get_current_line())
	local snapshot = id and routines.find(id)
	local origin = M.origin()
	if not snapshot then
		return
	end
	if not origin then
		local ok, picker = pcall(require, 'window-picker')
		if not ok or type(picker) ~= "table" or type(picker.pick_window) ~= "function" then
			vim.notify("frogman: the snapshot list's window picker is nvim-window-picker's, and it isn't installed.", vim.log.levels.WARN)
			return
		end
		vim.notify("frogman: the window this list was for is gone; pick a window to show the snapshot in.", vim.log.levels.WARN)
		-- the picker is another plugin's: its error is the world's, said and not dumped
		local picking, picked = pcall(picker.pick_window)
		if not picking then
			vim.notify("frogman: nvim-window-picker's picker failed: " .. tostring(picked), vim.log.levels.WARN)
			return
		end
		if not (picked and vim.api.nvim_win_is_valid(picked) and vim.api.nvim_win_get_config(picked).relative == "") then
			return
		end
		origin = picked
	end
	if vim.wo[origin].winfixbuf then
		vim.notify("frogman: window " .. vim.api.nvim_win_get_number(origin) ..
			" keeps its buffer ('winfixbuf'), so a snapshot can't show there.", vim.log.levels.WARN)
		return
	end
	local row = open.win and vim.api.nvim_win_is_valid(open.win) and vim.api.nvim_win_get_cursor(open.win)[1]
	if open.win and vim.api.nvim_win_is_valid(open.win) then
		vim.api.nvim_win_close(open.win, true)
	end
	vim.api.nvim_set_current_win(origin)
	if not require('frogman.domains.snapshots.preview').start(snapshot, origin) then
		-- it said why: the list again, on the line it was on
		M.open()
		if is_open() and row and row <= vim.api.nvim_buf_line_count(open.buf) then
			vim.api.nvim_win_set_cursor(open.win, { row, 0 })
		end
	end
end

---Map the list's keys on its buffer, from `keymaps.views`.
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
	map(keys.write, function() vim.cmd("write") end, "Write the snapshot list")
	map(keys.leave, M.leave, "Write the snapshot list and leave")
	map(keys.leave_too, M.leave, "Write the snapshot list and leave")
	map(keys.act, M.show, "Show the snapshot in its window")
end

return M
