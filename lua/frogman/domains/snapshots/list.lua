---The snapshot list.
---
---One editable floating window on a window's snapshots, newest first, then those held over in its
---session's scope, each group under its held-over header. Each line's text is its snapshot's whole
---encoding, concealed, and what shows is drawn over it in the trail's language: the time, the triquetra
---in the winbar's colours, and the order its bufferline drew. Deleting a line and writing deletes its
---snapshot, and a line yanked or cut from one window's list and put in another's carries its snapshot
---there.

local routines = require('frogman.domains.snapshots.routines')
local history = require('frogman.domains.history')

local M = {}

local NAME = "frogman://snapshots"
local ns = vim.api.nvim_create_namespace("frogman_snapshots")

---The list that's open: its buffer, its window and the window it was opened from.
---@type {buf: Bufnr, win: WinId, origin: WinId}|nil
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

---Wrap a carried snapshot as a line: `fs1:`, the base64 of its JSON, a dot and a checksum, the first 8
---hex characters of the JSON's sha256.
---
---@param carried table As `routines.carried` gives it
---@return string line
function M.wrap(carried)
	local json = vim.json.encode(carried)
	return "fs1:" .. vim.base64.encode(json) .. "." .. vim.fn.sha256(json):sub(1, 8)
end

---Decode a line: the snapshot it carries, when it's one of frogman's and its checksum holds against
---the JSON's bytes as they are.
---
---@param line string
---@return table|nil carried A copy of what it carries
function M.decode(line)
	line = vim.trim(line or "")
	if decoded[line] == nil then
		decoded[line] = false
		local base64, sum = line:match("^fs1:([%w%+/=]+)%.(%x+)$")
		local ok, json = pcall(vim.base64.decode, base64 or "")
		if base64 and ok and type(json) == "string" and vim.fn.sha256(json):sub(1, 8) == sum then
			local parsed, carried = pcall(vim.json.decode, json)
			if parsed and type(carried) == "table" and carried.v == 1 and type(carried.id) == "string"
				and type(carried.files) == "table" then
				decoded[line] = carried
			end
		end
	end
	return decoded[line] and vim.deepcopy(decoded[line]) or nil
end

---Get a snapshot's line: its whole encoding.
---@param snapshot Snapshot
---@return string line
local function line_of(snapshot)
	return M.wrap(routines.carried(snapshot))
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
---@param snapshot Snapshot
---@return table chunks The `{text, highlight}` chunks
local function drawing(snapshot)
	local ui = require('frogman.domains.ui').routines
	local glyphs = ui.glyphs()
	local marks = require('frogman.domains.marks')
	local function name(id)
		local handle = routines.handle(id)
		return handle and ui.get_smart_basename(handle.hash) or "?"
	end
	local today = os.date("%Y-%m-%d") == os.date("%Y-%m-%d", snapshot.time)
	local chunks = { { os.date(today and "%H:%M" or "%m-%d %H:%M", snapshot.time) .. "  ", "FrogmanTrailTime" } }
	table.insert(chunks, { "⦉" .. (snapshot.ternary and name(snapshot.ternary) or "-") .. "⦊ ", "WinbarBufnrTernary" })
	table.insert(chunks, { "[" .. name(snapshot.current) .. "] ", "WinbarBufnrCurrent" })
	table.insert(chunks, { "⟦" .. (snapshot.secondary and name(snapshot.secondary) or "-") .. "⟧", "WinbarBufnrSecondary" })
	for _, id in ipairs(snapshot.order) do
		local handle = routines.handle(id)
		if handle then
			local bufnr = history.get_buffer_from_hash(handle.hash)
			local label = marks.label_of(handle.hash, M.origin())
			local text = name(id) .. (label and (" ⟨" .. label .. "⟩") or "")
			if history.data.missing[handle.hash] then
				table.insert(chunks, { "  ✗ ", "DiagnosticError" })
				table.insert(chunks, { text .. " " .. glyphs.tag .. history.data.missing[handle.hash], "FrogmanTrailDim" })
			elseif bufnr == nil then
				table.insert(chunks, { "  " .. glyphs.closed .. " " .. text, "FrogmanTrailDim" })
			else
				table.insert(chunks, { "  " .. bufnr .. " " .. text, "FrogmanTrail" })
			end
		end
	end
	return chunks
end

---Draw the list's lines again: each known snapshot's line concealed, and its drawing over it, and
---above the first line of each held-over group, its header.
---@return nil
local function decorate()
	if not is_open() then
		return
	end
	vim.api.nvim_buf_clear_namespace(open.buf, ns, 0, -1)
	local header = nil
	for i, line in ipairs(vim.api.nvim_buf_get_lines(open.buf, 0, -1, false)) do
		local carried = M.decode(line)
		local snapshot, _, held_in = nil, nil, nil
		if carried then
			snapshot, _, held_in = routines.find(carried.id)
		end
		if carried then
			-- the encoding hidden, and the drawing after it, so the cursor at the line's start stays there
			vim.api.nvim_buf_set_extmark(open.buf, ns, i - 1, 0, { end_col = #line, conceal = "" })
			vim.api.nvim_buf_set_extmark(open.buf, ns, i - 1, #line,
				{ virt_text = snapshot and drawing(snapshot) or drawing_of_carried(carried), virt_text_pos = "inline" })
		end
		if snapshot then
			if snapshot.held and held_in == session() and snapshot.held ~= header then
				vim.api.nvim_buf_set_extmark(open.buf, ns, i - 1, 0, {
					virt_lines = { { { snapshot.held, "FrogmanTrailDim" } } }, virt_lines_above = true,
				})
			end
		end
		header = snapshot and held_in == session() and snapshot.held or nil
	end
end

---Show a header above the first line: a window shows a line above its top one only when told to.
---@return nil
local function show_header_above()
	if open and open.win and vim.api.nvim_win_is_valid(open.win) then
		vim.api.nvim_win_call(open.win, function()
			vim.fn.winrestview({ topline = 1, topfill = 1 })
		end)
	end
end

---Put the window's snapshots in the list's lines, newest first, then its session's held-over ones,
---newest first.
---@return nil
local function redraw()
	local lines = {}
	local snapshots = routines.of_window(open.origin)
	for i = #snapshots, 1, -1 do
		table.insert(lines, line_of(snapshots[i]))
	end
	local held = routines.held_in(session())
	for i = #held, 1, -1 do
		table.insert(lines, line_of(held[i]))
	end
	vim.api.nvim_buf_set_lines(open.buf, 0, -1, false, lines)
	vim.bo[open.buf].modified = false
	decorate()
	show_header_above()
end

---Write the list: a snapshot whose line is gone is deleted, and a line put in carries its snapshot in.
---
---A line naming one of the list's own, the window's or one held over in its session's scope, keeps it.
---One naming a snapshot alive elsewhere, or a second line naming one kept here, makes a copy of it the
---window's own. Any other is rebuilt from what it carries. A line that doesn't decode, or that carries a
---snapshot with nothing left to come back, is asked about first, and No writes nothing, the cursor on
---the first such line. With the window the list was opened from gone, nothing is written, the edits
---kept, as the marks pop-up keeps them.
---
---@return boolean written
local function write()
	if not M.origin() then
		vim.notify("frogman: the window this list was for is gone, so it isn't written.", vim.log.levels.WARN)
		return false
	end
	local kept, copies, rebuilt, items, first = {}, {}, {}, {}, nil
	for row, line in ipairs(vim.api.nvim_buf_get_lines(open.buf, 0, -1, false)) do
		line = vim.trim(line)
		if line ~= "" then
			local carried = M.decode(line)
			local snapshot, winid, held_in = nil, nil, nil
			if carried then
				snapshot, winid, held_in = routines.find(carried.id)
			end
			if snapshot and not kept[carried.id] and (winid == open.origin or (held_in ~= nil and held_in == session())) then
				kept[carried.id] = true
			elseif snapshot then
				table.insert(copies, snapshot)
			elseif carried and routines.rebuild(open.origin, carried, true) then
				table.insert(rebuilt, carried)
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
		for _, snapshot in ipairs(vim.deepcopy(list)) do
			if not kept[snapshot.id] then
				routines.delete(snapshot.id)
			end
		end
	end
	for _, snapshot in ipairs(copies) do
		routines.copy(open.origin, snapshot)
	end
	for _, carried in ipairs(rebuilt) do
		routines.rebuild(open.origin, carried)
	end
	redraw()
	return true
end

---Write the list when it was edited, then leave it; a write answered No leaves it open.
---@return nil
function M.leave()
	if not is_open() then
		return
	end
	if vim.bo[open.buf].modified and not write() then
		return
	end
	if open.win and vim.api.nvim_win_is_valid(open.win) then
		vim.api.nvim_win_close(open.win, true)
	end
end

---Open the snapshot list on the window you're in.
---
---With edits not written yet, the list stays as it is, focused, and says so.
---
---@return nil
function M.open()
	if is_open() then
		if vim.bo[open.buf].modified then
			if open.win and vim.api.nvim_win_is_valid(open.win) then
				vim.api.nvim_set_current_win(open.win)
			end
			vim.notify("frogman: the snapshot list has edits not written yet: write them with :w, or leave them, first.", vim.log.levels.WARN)
			return
		end
		if open.win and vim.api.nvim_win_is_valid(open.win) then
			vim.api.nvim_win_close(open.win, true)
		end
	end
	local origin = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_config(origin).relative ~= "" then
		origin = require('frogman.domains.navigation.routines').find_most_recent_tracked_window() or origin
	end
	local buf = vim.api.nvim_create_buf(false, false)
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].swapfile = false
	vim.bo[buf].bufhidden = "wipe"
	vim.api.nvim_buf_set_name(buf, NAME)
	decoded = {} -- what the last list decoded, its lines no longer here
	open = { buf = buf, origin = origin, session = routines.session_of(origin) }
	redraw()
	vim.bo[buf].filetype = "frogman-snapshots"
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = buf,
		callback = decorate,
		desc = "Draw the snapshots again",
	})
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			if vim.bo[buf].modified then
				write()
			end
		end,
		desc = "Write the snapshot list",
	})
	local width, height, col, row = require('frogman.domains.ui').routines.resolve_float_geometry(
		require('frogman.configs').snapshots_popup)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor", width = width, height = height, col = col, row = row,
		style = "minimal", border = "rounded", title = " Snapshots ", title_pos = "center",
	})
	open.win = win
	vim.api.nvim_create_autocmd("WinClosed", {
		group = "frogman",
		pattern = tostring(win),
		once = true,
		callback = function()
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
			if open and open.buf == buf then
				open = nil
			end
		end,
	})
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	vim.wo[win].conceallevel = 2
	vim.wo[win].concealcursor = "nvic"
	show_header_above()
end

---Show the snapshot on the cursor's line in the window the list was opened from, leaving the list.
---
---While the list has edits not written yet, it refuses and says so.
---
---@return nil
function M.show()
	if not is_open() then
		return
	end
	if vim.bo[open.buf].modified then
		vim.notify("frogman: the snapshot list has edits not written yet: write them with :w, or leave them, first.", vim.log.levels.WARN)
		return
	end
	local id = id_in(vim.api.nvim_get_current_line())
	local snapshot = id and routines.find(id)
	local origin = M.origin()
	if not snapshot then
		return
	end
	if not origin then
		vim.notify("frogman: the window this list was for is gone.", vim.log.levels.WARN)
		return
	end
	if open.win and vim.api.nvim_win_is_valid(open.win) then
		vim.api.nvim_win_close(open.win, true)
	end
	vim.api.nvim_set_current_win(origin)
	require('frogman.domains.snapshots.preview').start(snapshot, origin)
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
