---Ledger domain replay of a flight recorder's dump.
---
---This module replays a dump into a fresh editor in its project. It plants the snapshot,
---then takes the steps in order. A step from cavediver's keys, or a command that only moves
---windows and buffers, is driven and checked against its recorded row. Any other step has
---its recorded row planted, so a replay writes no file and runs none of the dump's code.

local M = {}

---Commands a replay runs, by their full names (they only move windows and buffers)
---@type table<string, boolean>
local DRIVEN = {
	edit = true, buffer = true, bdelete = true, bwipeout = true, split = true, vsplit = true,
	close = true, only = true, enew = true, wincmd = true,
}

---Parse a recorded command line into the command a replay runs, when it runs one.
---
---It must be one of the commands that only move windows and buffers, with nothing chained
---after it by `|`, no `+cmd` argument and no backtick in a file name. It runs as parsed, with
---no file expansion.
---
---@param trigger string The command line as the ledger recorded it (`:e b.txt`)
---@return table|nil cmd The command for `nvim_cmd`, or nil when the step is planted
local function driven_command(trigger)
	local ok, cmd = pcall(vim.api.nvim_parse_cmd, (trigger or ""):gsub("^:", ""), {})
	if not ok or not DRIVEN[cmd.cmd] or (cmd.nextcmd or "") ~= "" then
		return nil
	end
	for _, arg in ipairs(cmd.args or {}) do
		if arg:match("^%+") or arg:find("`", 1, true) then
			return nil
		end
	end
	cmd.nextcmd, cmd.addr, cmd.nargs = nil, nil, nil
	cmd.magic = { file = false, bar = false }
	return cmd
end

---Check if a recorded key is one of cavediver's own keymaps.
---
---A view's keys aren't counted.
---
---@param lhs string The key, as the step's trigger
---@return boolean own True if cavediver maps it
local function own_key(lhs)
	for _, key in pairs(require('cavediver.configs').keymaps or {}) do
		if type(key) == "string" and key == lhs then
			return true
		end
	end
	return false
end

---Check if a buffer is empty and unnamed, as the one Neovim starts on is.
---
---@param bufnr Bufnr
---@return boolean empty True if it has no name, no text and no unsaved changes
local function empty_noname(bufnr)
	return vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == "" and not vim.bo[bufnr].modified
		and vim.api.nvim_buf_line_count(bufnr) == 1 and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == ""
end

---Check if this editor tracks nothing yet but the buffer it started on.
---
---Every registered buffer must be an empty No Name buffer, and every triquetra must hold one
---alone, in its current slot.
---
---@return boolean fresh True if it tracks nothing else
local function fresh()
	local history = require('cavediver.domains.history')
	for bufnr, _ in pairs(history.data.hash_buffer_registry.hashes) do
		if not empty_noname(bufnr) then
			return false
		end
	end
	for _, triquetra in pairs(require('cavediver.domains.window').data.crux) do
		if triquetra.secondary_slot or triquetra.ternary_slot or next(triquetra.primary_buffer or {})
			or not history.data.hash_buffer_registry.buffers[triquetra.current_slot] then
			return false
		end
	end
	return true
end

---Forget the empty No Name buffers a fresh editor tracks, and their triquetras.
---
---The snapshot is planted over nothing, so the buffer Neovim starts on is forgotten first when
---`setup()` took it in at startup. It stays open.
---
---@return nil
local function forget_start()
	local window = require('cavediver.domains.window')
	local history = require('cavediver.domains.history')
	for winid, _ in pairs(window.data.crux) do
		window.data.unregister_triquetra(winid)
	end
	for bufnr, hash in pairs(vim.deepcopy(history.data.hash_buffer_registry.hashes)) do
		local path = history.data.hash_filepath_registry.filepaths[hash]
		history.routines.untrack_buffer(bufnr)
		history.routines.unregister_buffer(bufnr)
		if path then
			history.routines.unregister_filepath(path)
		end
	end
end

---Check if a dump's windows span more than one tab.
---
---@param replay table The dump's replay part
---@return boolean spans True if a snapshot window or a step sits in a tab other than the first
local function spans_tabs(replay)
	for _, w in ipairs(replay.snapshot and replay.snapshot.windows or {}) do
		if (w.tab or 1) ~= 1 then
			return true
		end
	end
	for _, step in ipairs(replay.steps or {}) do
		if (step.tab or 1) ~= 1 then
			return true
		end
	end
	return false
end

---Read a row back from a window, as the dump wrote rows.
---
---@param winid WinId
---@return table row The window's slots, queue, switch, notes and what it shows
local function row_now(winid)
	local row = require('cavediver.domains.ledger.routines').row_of(winid, {}) or {}
	return { c = row.c, s = row.s, t = row.t, p = row.p or {}, on = row.on == true, dtm = row.dtm or {},
		dsm = row.dsm or {}, shows = row.shows }
end

---Check if a window's row is the recorded one.
---
---JSON writes an empty map as `[]` and a missing slot as nothing, so both sides are read the
---same way first.
---
---@param got table The row as it is now
---@param want table|nil The recorded row
---@return boolean same True if the slots, queue, switch, notes and what the window shows match
local function same(got, want)
	want = want or {}
	return got.c == want.c and got.s == want.s and got.t == want.t and got.shows == want.shows
		and (got.on == true) == (want.on == true)
		and vim.deep_equal(got.p or {}, want.p or {})
		and vim.deep_equal(got.dtm or {}, want.dtm or {})
		and vim.deep_equal(got.dsm or {}, want.dsm or {})
end

---Format a row in the trail's brackets, for a mismatch's report.
---
---@param row table|nil The row to format
---@return string text `⦉t⦊ [c] ⟦s⟧`, by file name
local function text_of(row)
	local name = function(hash)
		return hash and (require('cavediver.domains.ledger.routines').name_of(hash) or hash) or "-"
	end
	row = row or {}
	return "⦉" .. name(row.t) .. "⦊ [" .. name(row.c) .. "] ⟦" .. name(row.s) .. "⟧"
end

---Make the planting functions for one replay.
---
---@param files table<Filehash, {path: string|nil}> The dump's files
---@return table plant The planting functions (`known`, `open`, `closed` and `row`)
local function planter(files)
	local history = require('cavediver.domains.history')
	local plant = {}

	---Register the path the dump has for a hash, so cavediver knows the file.
	function plant.known(hash)
		if hash == nil then
			return
		end
		local base = hash:gsub("%-swap$", "")
		local path = files[base] and files[base].path
		if path and not history.data.hash_filepath_registry.filepaths[base] then
			history.routines.register_filepath(path)
		end
	end

	---Check if a hash is on the editor's closed list.
	function plant.closed(hash)
		return vim.tbl_contains(history.data.closed_buffers, hash)
	end

	---Open a hash's buffer and register it, loading it without autocmds.
	function plant.open(hash)
		local path = files[hash] and files[hash].path
		if not path then
			return nil
		end
		local bufnr
		if path:match("^NONAME_") then
			bufnr = vim.api.nvim_create_buf(true, false)
			vim.b[bufnr].cavediver_noname = path:sub(#"NONAME_" + 1)
		else
			bufnr = vim.fn.bufadd(path)
			vim.bo[bufnr].buflisted = true
			vim.cmd("noautocmd call bufload(" .. bufnr .. ")")
		end
		history.routines.register_buffer(bufnr)
		return bufnr
	end

	---Plant a recorded row on a window, with what it shows, its files and its triquetra.
	function plant.row(winid, row)
		if not row or not winid or not vim.api.nvim_win_is_valid(winid) then
			return
		end
		local hashes = { row.c, row.s, row.t, row.shows }
		vim.list_extend(hashes, row.p or {})
		for _, map in ipairs({ row.dtm or {}, row.dsm or {} }) do
			for key, value in pairs(map) do
				table.insert(hashes, key)
				table.insert(hashes, value)
			end
		end
		for _, hash in pairs(hashes) do
			plant.known(hash)
		end
		local slots = { row.shows, row.c, row.s, row.t }
		vim.list_extend(slots, row.p or {})
		for _, hash in pairs(slots) do
			if hash and not history.get_buffer_from_hash(hash) and not plant.closed(hash) then
				plant.open(hash)
			end
		end
		local shown = row.shows and history.get_buffer_from_hash(row.shows)
		if shown and vim.api.nvim_win_get_buf(winid) ~= shown then
			vim.api.nvim_win_call(winid, function()
				vim.cmd("noautocmd buffer " .. shown)
			end)
		end
		require('cavediver.domains.window').set_buffer_relationship(winid, {
			current_slot = row.c, secondary_slot = row.s, ternary_slot = row.t, primary_buffer = vim.deepcopy(row.p or {}),
			primary_enabled = row.on == true, displacement_ternary_map = vim.deepcopy(row.dtm or {}),
			displacement_secondary_map = vim.deepcopy(row.dsm or {}),
		})
	end

	return plant
end

---Plant the snapshot a dump starts from.
---
---Splits this tab until it has as many windows as the snapshot numbers, and matches them by
---number in order. Every list's closed files go on the editor's list, since a replay has no
---tab sessions. The histories, the missing tags, the history view and a cycle under way are
---planted too.
---
---@param snapshot table The dump's snapshot
---@param plant table The planting functions
---@return nil
local function plant_snapshot(snapshot, plant)
	local history = require('cavediver.domains.history')
	local most = 0
	for _, w in ipairs(snapshot.windows or {}) do
		most = math.max(most, w.window or 0)
	end
	while #vim.api.nvim_tabpage_list_wins(0) < most do
		vim.cmd("noautocmd vsplit")
	end
	local windows = vim.api.nvim_tabpage_list_wins(0)
	local editor
	for _, pool in pairs(history.routines.pools()) do
		if pool.id == "" then
			editor = pool
		end
	end
	for _, list in ipairs(snapshot.lists or {}) do
		for _, hash in ipairs(list.closed or {}) do
			plant.known(hash)
			if not plant.closed(hash) then
				table.insert(history.data.closed_buffers, hash)
				if editor and list.times and list.times[hash] then
					editor.times = editor.times or {}
					editor.times[hash] = list.times[hash]
				end
			end
		end
	end
	for _, w in ipairs(snapshot.windows or {}) do
		local winid = windows[w.window]
		plant.row(winid, w)
		if winid then
			history.data.crux_internals.window[winid] = vim.deepcopy(w.history or {})
		end
	end
	for hash, _ in pairs(snapshot.global or {}) do
		plant.known(hash)
	end
	history.data.crux_internals.global = vim.deepcopy(snapshot.global or {})
	history.data.history_index = snapshot.history_index or history.data.history_index
	history.data.missing = vim.deepcopy(snapshot.missing or {})
	if snapshot.history_view then
		require('cavediver.configs').bufferline.history_view = snapshot.history_view
	end
	local cycling = snapshot.navigation == "cycling" and snapshot.cycle and windows[snapshot.cycle]
	if cycling then
		local navigation = require('cavediver.domains.navigation')
		navigation.sm.current_state = navigation.states.CYCLING
		navigation.data.cycling_window = cycling
		history.sm.current_state = history.states.DETACHED
		history.data.cycling_origins[cycling] = require('cavediver.domains.window').data.crux[cycling]
	end
	history.routines.construct_crux(vim.api.nvim_get_current_win())
	history.routines.update_buffer_history_ordered()
end

---Replay a dump into this editor.
---
---Runs from the directory the dump was written in, in an editor with cavediver set up that
---tracks nothing yet but the empty buffer it started on. A dump that spans more than one tab
---is refused. Once a replay starts, this editor's state isn't a session, so `save_session`
---refuses and no records are written. The result holds `steps`, `driven`, `matched`,
---`mismatches`, `failure` and `snapshot`.
---
---@param path string The dump's file
---@return table|nil result What the replay found, or nil if it was refused
function M.run(path)
	path = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
	local text, problem = require('cavediver.domains.ledger.dump').read(path)
	if not text then
		vim.notify("cavediver: " .. vim.fn.fnamemodify(path, ":t") .. " can't be replayed, since "
			.. (problem == "missing" and "there's no such file" or problem == "not a dump" and "it isn't a dump"
				or "it doesn't open here: a dump opens only from the directory it was written in, unedited") .. ".",
			vim.log.levels.WARN)
		return nil
	end
	local replay = vim.json.decode(text:match("\nreplay:\n(.*)$") or "{}", { luanil = { object = true, array = true } })
	if spans_tabs(replay) then
		vim.notify("cavediver: this dump spans more than one tab, which a replay doesn't recreate.", vim.log.levels.WARN)
		return nil
	end
	if vim.fn.exists(":CavediverDump") ~= 2 then
		vim.notify("cavediver: a dump replays once cavediver is set up, and setup() hasn't run in this editor.", vim.log.levels.WARN)
		return nil
	end
	local settle = require('cavediver.settle')
	settle.drain() -- the start buffer's arrival, still queued when the replay runs straight from startup
	if not fresh() then
		vim.notify("cavediver: a dump replays into a fresh editor, started in its project with cavediver set up and no"
			.. " session loaded, and this one tracks buffers already.", vim.log.levels.WARN)
		return nil
	end
	local storage = require('cavediver.domains.storage')
	storage.data.replayed = true
	storage.routines.write_records_on(false)
	forget_start()

	local plant = planter(replay.files or {})
	if replay.snapshot then
		plant_snapshot(replay.snapshot, plant)
	end
	settle.drain()

	local result = { steps = 0, driven = 0, matched = 0, mismatches = {}, failure = nil, snapshot = replay.snapshot ~= nil }
	for _, step in ipairs(replay.steps or {}) do
		result.steps = result.steps + 1
		local windows = vim.api.nvim_tabpage_list_wins(0)
		local winid = step.window and windows[step.window] or vim.api.nvim_get_current_win()
		if vim.api.nvim_get_current_win() ~= winid then
			vim.cmd("noautocmd " .. step.window .. "wincmd w")
		end
		local drive
		if step.cause == "keymap" and own_key(step.trigger) then
			local mapping = vim.fn.maparg(step.trigger, "n", false, true)
			drive = mapping and mapping.callback
		elseif step.cause == "command" then
			local cmd = driven_command(step.trigger)
			drive = cmd and function()
				vim.api.nvim_cmd(cmd, {})
			end
		end
		if drive then
			result.driven = result.driven + 1
			local ok, err = pcall(drive)
			settle.drain()
			if not ok then
				result.failure = { seq = step.seq, trigger = step.trigger, error = tostring(err) }
				break
			end
			local got = row_now(winid)
			if same(got, step.after) then
				result.matched = result.matched + 1
			else
				table.insert(result.mismatches, { seq = step.seq, trigger = step.trigger, want = text_of(step.after), got = text_of(got) })
			end
		else
			plant.row(winid, step.after)
			settle.drain()
		end
	end

	local words = ("cavediver: replayed %d steps, %d driven, %d matching"):format(result.steps, result.driven, result.matched)
	if #result.mismatches > 0 then
		words = words .. ("; %d didn't match, the first at %s"):format(#result.mismatches, result.mismatches[1].trigger)
	end
	if result.failure then
		words = words .. "; it stopped at " .. tostring(result.failure.trigger) .. ": " .. result.failure.error:match("[^\n]*")
	end
	vim.notify(words .. ".", vim.log.levels.INFO)
	return result
end

return M
