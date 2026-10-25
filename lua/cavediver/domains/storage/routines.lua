---Storage domain core routines for session persistence.
---
---This module contains the main business logic for saving and loading
---complete system state across all domains, including serialization
---and file management operations.
---
---Buffer access history data structure (from buffers.lua M.sequence_buffer_history())
---Maps filehash (16-char SHA256 prefix) to access time (monotonically increasing index)
---Example: { ["a1b2c3d4e5f6g7h8"] = 42, ["z9y8x7w6v5u4t3s2"] = 43 }
---@class BufferHistoryData: table<string, number>
---
---@class WindowTriquetraSerialised
---@field [1] Filehash|vim.NIL Current slot
---@field [2] Filehash|vim.NIL Secondary slot
---@field [3] Filehash[] Primary queue, the primary first
---@field [4] Filehash|vim.NIL Ternary slot
---@field [5] table<Filehash, Filehash> Ternary notes (the ternary displacement map)
---@field [6] table<Filehash, Filehash> Secondary notes (the secondary displacement map)
---@field [7] Filehash|vim.NIL What the window shows: its buffer's hash, or an outsider's (oil, help)
---@field [8] boolean Whether the primary is on
---@field [9] table<Filehash, number> The window's own access history
---
---Window buffer relationships data structure
---Holds one entry per window with a triquetra, in window order (tab by tab)
---Example: { [1] = { "a1b2c3d4e5f6g7h8", vim.NIL, {}, "z9y8x7w6v5u4t3s2", {}, {}, "a1b2c3d4e5f6g7h8", false, { ["a1b2c3d4e5f6g7h8"] = 42 } } }
---@class WindowBufferData: table<number, WindowTriquetraSerialised>
---
---Closed buffer history data structure
---Array of the hashes of buffers that were closed and can be reopened, newest last
---Example: { "a1b2c3d4e5f6g7h8", "z9y8x7w6v5u4t3s2" }
---@class ClosedBufferData: Filehash[]
---
---Paths data structure
---Maps every saved hash to its path, so a hash whose buffer doesn't come back still
---resolves to its file
---Example: { ["a1b2c3d4e5f6g7h8"] = "/path/to/file.lua" }
---@class PathsData: table<Filehash, string>

local data = require('cavediver.domains.storage.data')
local history = require('cavediver.domains.history')
local historyState = require('cavediver.domains.history.states')
local window = require('cavediver.domains.window')
local configs = require('cavediver.configs')
local crypto = require('cavediver.domains.storage.crypto')

local M = {}


---Format header at the start of a main file, in the clear but covered by the seal's tag
local HEADER = "CDV1"

---Turn bytes into hex text, for naming a session's files after its key.
---@param bytes string Raw bytes, such as a key
---@return string hex The bytes as lowercase hex
local function hex(bytes)
	return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

---Read a whole file.
---@param path string Path of the file to read
---@return string|nil bytes The file's bytes, or nil if it can't be opened
local function read_file(path)
	local fh = io.open(path, "rb")
	if not fh then
		return nil
	end
	local bytes = fh:read("*a")
	fh:close()
	return bytes
end

---Write a file atomically.
---
---Writes the bytes to a temporary file in the same directory, syncs it, then renames it over the
---old one, readable by the user only. A crash leaves the old file or the new one, never half of
---one. Throws if the temporary file can't be opened, written, synced or renamed.
---
---@param path string Path of the file to write
---@param bytes string The file's new content
---@return nil
local function write_atomic(path, bytes)
	local temporary = path .. ".tmp" .. string.format("%.0f", vim.uv.hrtime())
	local fd, open_err = vim.uv.fs_open(temporary, "w", 384) -- 0600
	if not fd then
		error("Failed to write session data to file: " .. path .. " (" .. tostring(open_err) .. ")")
	end
	local written, write_err = vim.uv.fs_write(fd, bytes, 0)
	local synced, sync_err = vim.uv.fs_fsync(fd)
	vim.uv.fs_close(fd)
	if written ~= #bytes or not synced then
		vim.uv.fs_unlink(temporary)
		error("Failed to write session data to file: " .. path .. " (" .. tostring(write_err or sync_err) .. ")")
	end
	vim.uv.fs_chmod(temporary, 384)
	local renamed, rename_err = vim.uv.fs_rename(temporary, path)
	if not renamed then
		vim.uv.fs_unlink(temporary)
		error("Failed to write session data to file: " .. path .. " (" .. tostring(rename_err) .. ")")
	end
end
M.write_atomic = write_atomic

---Get a No Name text's file name.
---
---The name hashes the key, the buffer's hash and the text, so it changes with the text and an
---unchanged text keeps its file. Through the key it gives nothing of the text away.
---
---@param key string The session's key
---@param filehash Filehash The No Name buffer's hash
---@param plaintext string The text as it's saved, its lines, filetype and cursor in JSON
---@return string name The file's name in the session's scratch directory
local function scratch_name(key, filehash, plaintext)
	return vim.fn.sha256(hex(key) .. "\n" .. filehash .. "\n" .. plaintext)
end

---Make a reader for a No Name text's file.
---
---The reader opens the file only when it's called. A text whose file is missing or fails its check
---(edited or corrupted) is lost on its own, with a warning, and the rest of the session isn't.
---
---@param path string Path of the text's file
---@param key string The session's key
---@param filehash Filehash The No Name buffer's hash, which the file's seal is bound to
---@return fun(): NoNameBufferContent|nil read Reads the text, or gives nil when it's lost
local function scratch_reader(path, key, filehash)
	return function()
		local bytes = read_file(path)
		local plaintext = bytes and crypto.open(key, bytes, HEADER .. filehash)
		local ok, text = pcall(vim.json.decode, plaintext or "")
		if not plaintext or not ok or type(text) ~= "table" then
			vim.notify("cavediver: a No Name text's file failed its integrity check (edited or corrupted), so that text is lost.", vim.log.levels.WARN)
			return nil
		end
		return text
	end
end

---Check if the path registry knows a hash.
---
---Hashes are saved as they are, and the paths behind them go into the paths table.
---
---@param filehash Filehash|nil The hash to look up
---@return boolean known True if the registry has a path for it
local function is_known(filehash)
	return filehash ~= nil and history.get_filepath_from_hash(filehash) ~= nil
end

---Keep a hash only if the path registry knows it.
---@param filehash Filehash|nil The hash to look up
---@return Filehash|nil filehash The same hash, or nil if nothing knows it
local function known(filehash)
	if is_known(filehash) then
		return filehash
	end
	-- nothing knows this hash (a path is kept while anything references it, so this shouldn't
	-- happen). it's dropped rather than failing the save on cavediver's own data.
	return nil
end

---Get the hash of what a window shows.
---
---Returns its buffer's hash when the buffer is registered, otherwise the hash of the buffer's name,
---for an outsider such as an oil listing or a help file. An untracked buffer with no name gives nil.
---
---@param winid WinId The window to look at
---@return Filehash|nil filehash What the window shows, or nil for an untracked buffer with no name
---@return string|nil outsider The outsider's name, when the window shows one
local function shown_by(winid)
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local filehash = history.get_hash_from_buffer(bufnr)
	if filehash then
		return filehash, nil
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return nil, nil
	end
	return history.routines.get_filehash(name), name
end

---Get the paths table from a session's file, outsiders left out.
---
---Outsiders only help match windows, through what each window shows.
---
---@param paths PathsData The file's paths table
---@param outsiders Filehash[] The hashes in paths that untracked buffers had
---@return table<Filehash, Filepath> paths Hash → path, outsiders left out
local function load_paths(paths, outsiders)
	local outsider = {}
	for _, filehash in ipairs(outsiders or {}) do
		outsider[filehash] = true
	end
	local loaded = {}
	for filehash, filepath in pairs(paths) do
		if not outsider[filehash] then
			loaded[filehash] = filepath
		end
	end
	return loaded
end


---Loads buffer access history data.
---
---Registers every path the file knows, so a reference whose buffer doesn't come back still
---resolves to its file. Every buffer in the editor that the file knows is registered too, loaded
---or not, and one it doesn't know waits for its BufEnter, like any new buffer. A No Name buffer
---still open from before the load (a reload in the same process) is known by its id. Then
---restores saved buffer access history with original timestamps.
---
---@param buffers BufferCruxInternalsSerialised The saved global access history
---@param paths table<Filehash, Filepath> The paths the file knows, outsiders left out
---@return nil
local function load_buffer_history(buffers, paths)
	for _, filepath in pairs(paths) do
		history.register_filepath(filepath)
	end

	for _, bufnr in pairs(vim.api.nvim_list_bufs()) do
		local name = vim.api.nvim_buf_get_name(bufnr)
		if name == "" and vim.b[bufnr].cavediver_noname then
			name = "NONAME_" .. vim.b[bufnr].cavediver_noname
		end
		if
			vim.api.nvim_buf_is_valid(bufnr)
			and name ~= ""
			and paths[history.routines.get_filehash(name)]
			and history.routines.is_trackable(bufnr)
		then
			history.register_buffer(bufnr)
		end
	end

	for saved_filehash, time in pairs(buffers.global) do
		history.track_buffer(saved_filehash, time)
	end
end


-- the pool a load fills: the editor's for a whole-editor file, the tab session's for a tab's
local load_pool = nil

---Close a slot's file if the session manager didn't bring it back.
---
---The file is a closed buffer from then on, and its slot keeps it and reopens it when used. It goes
---under what was closed in the session, as the oldest. A No Name buffer, or a file already on the
---closed stack, is left alone.
---
---@param filehash Filehash|nil The slot's file
---@return nil
local function close_if_not_restored(filehash)
	local filepath = filehash and history.get_filepath_from_hash(filehash)
	local closed = load_pool and load_pool.closed or history.data.closed_buffers
	if
		filepath and
		not filepath:match("^NONAME_") and
		history.get_buffer_from_hash(filehash) == nil and
		not vim.tbl_contains(closed, filehash)
	then
		table.insert(closed, 1, filehash)
		if load_pool then
			load_pool.changed_at = vim.uv.hrtime()
		end
		local ledger = require('cavediver.domains.ledger')
		ledger.move("closed", { subject = filehash, name = ledger.name_of(filehash),
			lists = { history.routines.list_name(load_pool or history.routines.pools()[""]) },
			words = "not restored by the session manager" })
	end
end

---Loads window buffer relationship data.
---
---Restores per-window triquetra relationships (primary/secondary/ternary buffers). Each entry
---records what its window showed, and a restored window takes the first entry, in saved order,
---that showed what it shows, so windows on the same file keep their order. An entry that matches
---no window is dropped, and a window that matches no entry starts fresh. Floating windows are
---left out.
---
---@param window_buffer WindowBufferData Window relationships, in window order
---@param tabpage integer|nil The tab to match windows in, for a tab session (nil = every window)
---@return table<WinId, table<Filehash, number>> window_histories Each matched window's own access history
---@return WinId[] matched The windows that took an entry
---@return table<integer, WinId> taken The window each saved entry went to, by the entry's index
local function load_window_buffer_relationships(window_buffer, tabpage)
	local window_histories = {}
	local matched = {}
	local taken, index_of = {}, {}

	-- the entries for each thing a window showed, in saved order
	local unmatched = {}
	for i, triquetra_serialised in ipairs(window_buffer) do
		local shows = triquetra_serialised[7]
		index_of[triquetra_serialised] = i
		if shows ~= nil and shows ~= vim.NIL then
			unmatched[shows] = unmatched[shows] or {}
			table.insert(unmatched[shows], triquetra_serialised)
		end
	end

	for _, actual_winid in pairs(tabpage and vim.api.nvim_tabpage_list_wins(tabpage) or vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_config(actual_winid).relative ~= "" then
			goto continue -- floats never get a triquetra
		end
		local shows = shown_by(actual_winid)
		local triquetra_serialised = shows and unmatched[shows] and table.remove(unmatched[shows], 1)
		local reopened = vim.b[vim.api.nvim_win_get_buf(actual_winid)].cavediver_reopened
		if not triquetra_serialised and reopened and unmatched[reopened] then
			-- a No Name text an earlier load reopened, still under the hash the file knows it by
			triquetra_serialised = table.remove(unmatched[reopened], 1)
		end
		if not triquetra_serialised then
			-- a window that matches nothing starts fresh, once what it shows is tracked
			window.get_triquetra(actual_winid)
			goto continue
		end

		---@type Filehash|nil
		local cfilehash
		---@type Filehash|nil
		local sfilehash
		---@type Filehash|nil
		local tfilehash
		---@type Filehash[]|nil
		local pfilehashes = {}
		---@type table<Filehash, Filehash>
		local sdisplacement_map = {}
		---@type table<Filehash, Filehash>
		local tdisplacement_map = {}

		-- Current buffer [1] - the saved one, or the window's current buffer
		if triquetra_serialised[1] ~= vim.NIL then
			cfilehash = triquetra_serialised[1]
		end
		local current_slot = cfilehash or history.get_hash_from_buffer(vim.api.nvim_win_get_buf(actual_winid))

		-- Secondary slot [2]
		if triquetra_serialised[2] ~= vim.NIL then
			sfilehash = triquetra_serialised[2]
		end

		-- Primary buffer [3] - an array
		if #triquetra_serialised[3] > 0 then
			pfilehashes = triquetra_serialised[3]
		end

		-- Ternary slot [4]
		if triquetra_serialised[4] ~= vim.NIL then
			tfilehash = triquetra_serialised[4]
		end

		if triquetra_serialised[5] ~= nil and triquetra_serialised[5] ~= vim.NIL then
			tdisplacement_map = triquetra_serialised[5]
		end

		if triquetra_serialised[6] ~= nil and triquetra_serialised[6] ~= vim.NIL then
			sdisplacement_map = triquetra_serialised[6]
		end

		if current_slot == nil then
			goto continue -- nothing to put in the current slot: the window shows something untracked
		end

		window.set_buffer_relationship(
			actual_winid,
			{
				current_slot = current_slot,
				secondary_slot = sfilehash,
				ternary_slot = tfilehash,
				primary_buffer = pfilehashes,
				displacement_ternary_map = tdisplacement_map,
				displacement_secondary_map = sdisplacement_map,
				primary_enabled = triquetra_serialised[8] == true
			}
		)
		window_histories[actual_winid] = triquetra_serialised[9] or {}
		-- oil keeps the buffer it was opened from in a window variable no session manager saves, so
		-- `q` there goes back to the window's current slot
		local wbufnr = vim.api.nvim_win_get_buf(actual_winid)
		local current_bufnr = history.get_buffer_from_hash(current_slot)
		if vim.bo[wbufnr].filetype == "oil" and current_bufnr then
			vim.w[actual_winid].oil_original_buffer = current_bufnr
		end
		close_if_not_restored(current_slot)
		close_if_not_restored(sfilehash)
		close_if_not_restored(tfilehash)
		for _, filehash in ipairs(pfilehashes) do
			close_if_not_restored(filehash)
		end
		table.insert(matched, actual_winid)
		taken[index_of[triquetra_serialised]] = actual_winid
		::continue::
	end
	return window_histories, matched, taken
end

---Populate fresh buffer history from currently open buffers.
---
---Registers and tracks all valid buffers currently open in Neovim.
---Used when no saved session data exists to create initial history state.
---
---@return nil
local function populate_history()
	history.repopulate_history()
	window.repopulate_window_relationships()
end

---Serialize buffer access history for session saving.
---
---Creates a copy of the current global buffer access history that can be
---safely serialized to JSON. Maps filehash to access timestamps. Each window's
---own history goes with its window entry, so it follows the window matching.
---
---@return BufferCruxInternalsSerialised crux_serialised Serializable copy of buffer history
local function serialise_buffer_history()
	return {
		global = history.data.crux_internals.global
	}
end

---Serialize window buffer relationships for session saving.
---
---Creates a compressed representation of all window triquetra relationships
---that can be safely serialized to JSON. Holds one entry per window with a triquetra,
---in window order, with its slots and notes as hashes, its own access history and what
---it shows, so the load can find it. A slot's hash the path registry doesn't know is
---dropped.
---
---@return WindowBufferData compressed Serializable window relationship data
---@return WinId[] entry_wins The window each entry came from
---@param outsiders table<Filehash, string> Filled with the untracked buffers the windows show
---@param tabpage integer|nil The tab to save windows from, for a tab session (nil = every window)
local function serialise_window_relationships(outsiders, tabpage)
	local compressed = {}
	local entry_wins = {} -- the window each entry was written from

	local function get_keys(tbl)
		local keys = {}
		for k, _ in pairs(tbl) do
			table.insert(keys, k)
		end
		return keys
	end

	---@type Filehash[]
	local bufnr_list = get_keys(history.get_buffer_history())
	table.sort(bufnr_list)

	---@type WinId[]>
	local winid_list = get_keys(window.get_window_relationships())
	table.sort(winid_list)

	---@type table<WinId, boolean>

	local compressed_index = 1
	for _, winid in pairs(tabpage and vim.api.nvim_tabpage_list_wins(tabpage) or vim.api.nvim_list_wins()) do
		if window.data.crux[winid] ~= nil then -- yes, a direct existence check sorry for breaking encapsulation
			local triquetra = window.get_triquetra(winid)

			---@type Filehash|vim.NIL|nil
			local cfilehash 
			---@type Filehash|vim.NIL|nil
			local sfilehash
			---@type Filehash|vim.NIL|nil
			local tfilehash
			---@type Filehash[]|nil
			local pfilehashes = {}
			---@type table<Filehash, Filehash>|nil
			local sdisplacement_map = {}
			---@type table<Filehash, Filehash>|nil
			local tdisplacement_map = {}

			if not triquetra then
				require('cavediver.domains.ledger').never("This is impossible. The window triquetra must exist.")
			end

			-- Current buffer (window's active buffer)
			cfilehash = triquetra.current_slot
			sfilehash = triquetra.secondary_slot
			pfilehashes = triquetra.primary_buffer
			tfilehash = triquetra.ternary_slot

			tdisplacement_map = triquetra.displacement_ternary_map
			sdisplacement_map = triquetra.displacement_secondary_map

			if cfilehash == nil then
				cfilehash = vim.NIL
			else
				cfilehash = known(cfilehash) or vim.NIL
			end

			-- Secondary slot
			if sfilehash == nil then
				sfilehash = vim.NIL
			else
				sfilehash = known(sfilehash) or vim.NIL
			end

			-- Primary buffer (mobile)
			if pfilehashes == nil then
				pfilehashes = {}
			else
				local serialised = {}
				for _, hash in ipairs(pfilehashes) do -- no holes: a hash nothing knows is dropped
					table.insert(serialised, known(hash))
				end
				pfilehashes = serialised
			end

			-- Ternary slot
			if tfilehash == nil then
				tfilehash = vim.NIL
			else
				tfilehash = known(tfilehash) or vim.NIL
			end

			if tdisplacement_map == nil then
				tdisplacement_map = {}
			end

			if sdisplacement_map == nil then
				sdisplacement_map = {}
			end

			-- what the window shows, which is what the session manager saves
			local shows, outsider = shown_by(winid)
			if outsider and not is_known(shows) then -- a file cavediver knows isn't one, even through its unlisted buffer
				outsiders[shows] = outsider
			end

			compressed[compressed_index] = {
				[1] = cfilehash, -- Current buffer
				[2] = sfilehash, -- Secondary slot
				[3] = pfilehashes, -- Primary buffer
				[4] = tfilehash, -- Ternary slot
				[5] = tdisplacement_map,
				[6] = sdisplacement_map,
				[7] = shows or vim.NIL, -- What the window shows
				[8] = triquetra.primary_enabled == true,
				[9] = history.data.crux_internals.window[winid] or {}
			}
			entry_wins[compressed_index] = winid
			compressed_index = compressed_index + 1
		end
	end
	return compressed, entry_wins
end

---Serialize the paths every saved hash points at.
---
---Copies everything the path registry knows, closed buffers and No Name names included, and
---adds the outsiders the windows show.
---
---@param outsiders table<Filehash, string> The untracked buffers the windows show, hash → name
---@return PathsData paths Hash → path for every saved hash
local function serialise_paths(outsiders)
	local paths = vim.deepcopy(history.data.hash_filepath_registry.filepaths)
	for filehash, name in pairs(outsiders) do
		paths[filehash] = name
	end
	return paths
end

---Serialize closed buffer list for session saving.
---
---Creates a copy of the closed buffer hashes that can be safely
---serialized to JSON. Preserves the stack of reopenable files. Several pools are
---merged by when their entries were closed, each pool's own order kept. A file
---closed in more than one pool is kept once, at its newer close, and a hash the
---path registry doesn't know is left out.
---
---@param pools Pool[] The pools to save, the editor's first
---@return ClosedBufferData copy Serializable copy of closed buffer list
---@return table<Filehash, integer> times When each was closed
local function serialise_closed_buffers(pools)
	-- the copy of each file that's kept: its newer close
	local keep = {}
	for order, pool in ipairs(pools) do
		for _, v in ipairs(pool.closed) do
			local time = pool.times[v] or 0
			if is_known(v) and (keep[v] == nil or time > keep[v].time) then
				keep[v] = { order = order, time = time }
			end
		end
	end
	local copy, times, heads = {}, {}, {}
	for order, _ in ipairs(pools) do
		heads[order] = 1
	end
	while true do
		local best, best_time
		for order, pool in ipairs(pools) do
			local v = pool.closed[heads[order]]
			while v and not (keep[v] and keep[v].order == order) do
				heads[order] = heads[order] + 1
				v = pool.closed[heads[order]]
			end
			if v and (best == nil or (pool.times[v] or 0) < best_time) then
				best, best_time = order, pool.times[v] or 0
			end
		end
		if best == nil then
			break
		end
		local v = pools[best].closed[heads[best]]
		heads[best] = heads[best] + 1
		table.insert(copy, v)
		times[v] = pools[best].times[v]
	end
	return copy, times
end

---Serialize [No Name] buffer content for session saving.
---
---Collects the closed [No Name] texts, with their filetype and cursor position, and
---every open, non-empty [No Name] buffer's text the same way. The open ones are marked
---to be reopened at load, since no session manager saves their text.
---
---With `owner`, only the texts that pool owns are collected: its closed texts, and the open
---ones its tabs visited (their windows show them or have them in their history). The editor's
---pool also owns the open ones no tab session's tab visited.
---
---@param owner Pool|nil The pool whose texts are collected (nil = every text)
---@return table<Filehash, NoNameBufferContent> texts Each text, by its buffer's hash
local function serialise_noname_content(owner)
	local function owned(filehash)
		if owner == nil then
			return true
		end
		local visited = history.routines.tabs_that_visited(filehash)
		for tabpage, _ in pairs(visited) do
			if history.routines.pool_of_tab(tabpage) == owner then
				return true
			end
		end
		if owner.id ~= "" then
			return false
		end
		for tabpage, _ in pairs(visited) do
			local pool = history.routines.pool_of_tab(tabpage)
			if pool.id ~= "" and not pool.detached then
				return false -- a tab session's text
			end
		end
		return true
	end
	local texts = {}
	for identifier, content in pairs(history.data.noname_content) do
		-- print("identifier: " .. identifier)
		if is_known(identifier) and (owner == nil or vim.tbl_contains(owner.closed, identifier)) then
			texts[identifier] = content
		end
	end
	for filehash, bufnr in pairs(history.data.hash_buffer_registry.buffers) do
		local filepath = history.get_filepath_from_hash(filehash)
		if filepath and filepath:match("^NONAME_") and vim.api.nvim_buf_is_loaded(bufnr) and owned(filehash) then
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			if not (#lines == 0 or (#lines == 1 and lines[1] == "")) then -- empty ones are skipped, as when closed
				local winid = vim.fn.bufwinid(bufnr)
				winid = winid ~= -1 and winid or (vim.fn.win_findbuf(bufnr)[1] or -1) -- or one in another tab
				texts[filehash] = {
					lines = lines,
					filetype = vim.bo[bufnr].filetype,
					cursor = winid ~= -1 and vim.api.nvim_win_get_cursor(winid) or { 1, 0 },
					reopen = true
				}
			end
		end
	end
	return texts
end

---Write each [No Name] text into a file of its own in the session's scratch directory.
---
---Each file is encrypted, and the main file keeps its name. A file is named after its text, so
---only a text that changed is written. A closed text never read since the load keeps its file,
---unless it was saved under another session or key, when it's read, written again here and kept
---read. One whose file has gone, swept by another editor's save, is dropped.
---
---@param texts table<Filehash, NoNameBufferContent> The texts, `reopen` marking the open ones
---@param key string The session's key
---@param scratch_dir string The session's scratch directory
---@return table<Filehash, {scratch: string, reopen: boolean|nil}> noname_content Each text's file name
---@return table<string, boolean> kept The file names the main file references
local function write_noname_texts(texts, key, scratch_dir)
	local noname_content = {}
	local kept = {}
	for filehash, text in pairs(texts) do
		local reopen = text.reopen
		local name = text.scratch
		if text.lines == nil then
			if text.source ~= scratch_dir .. name or text.key ~= key then
				text = text.read() -- saved under another session or key: read, and written again here
				if text then
					history.data.noname_content[filehash] = text -- kept read, so it no longer needs that file
				end
			elseif vim.uv.fs_stat(scratch_dir .. name) == nil then
				text = nil -- its file is gone, swept by another editor's save: nothing is left to keep
			end
		end
		if text and text.lines then
			-- its keys always in this order, so a text is the same JSON, and the same name, in every editor
			local plaintext = ('{"lines":%s,"filetype":%s,"cursor":%s}'):format(
				vim.json.encode(text.lines), vim.json.encode(text.filetype), vim.json.encode(text.cursor))
			name = scratch_name(key, filehash, plaintext)
			if vim.uv.fs_stat(scratch_dir .. name) == nil then
				vim.fn.mkdir(scratch_dir, "p", 448) -- 0700
				write_atomic(scratch_dir .. name, crypto.seal(key, plaintext, HEADER .. filehash))
			end
		end
		if text then
			noname_content[filehash] = { scratch = name, reopen = reopen }
			kept[name] = true
		end
	end
	return noname_content, kept
end

---Find the unnamed buffer that is already the No Name buffer saved as `filehash`.
---
---A reopened one carries the hash it came back from, and one never torn down still has its id.
---
---@param filehash Filehash The saved No Name buffer's hash
---@return Bufnr|nil bufnr The buffer, or nil if it isn't back
local function noname_already_back(filehash)
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(bufnr) == "" then
			local id = vim.b[bufnr].cavediver_noname
			if
				(vim.b[bufnr].cavediver_reopened == filehash or
				(id ~= nil and history.routines.get_filehash("NONAME_" .. id) == filehash))
				and history.routines.is_trackable(bufnr) -- one turned nofile since isn't that buffer any more
			then
				return bufnr
			end
		end
	end
	return nil
end

---Reopen the No Name buffers that were open at the save.
---
---They come back in the background, listed, hidden and modified, under a fresh id, and every slot,
---note and history entry that named them follows. One that is already back is taken as it is. The
---cursor goes back once a window shows the buffer. A text whose file fails its check is lost, and
---the rest still come back.
---
---@param noname_content table<Filehash, {scratch: string, reopen: boolean|nil}> Each text's file name
---@param key string The session's key
---@param scratch_dir string The session's scratch directory
---@return nil
local function reopen_noname_buffers(noname_content, key, scratch_dir)
	for filehash, entry in pairs(noname_content) do
		local filepath = history.get_filepath_from_hash(filehash)
		if entry.reopen and filepath then
			local bufnr = noname_already_back(filehash)
			local content = bufnr == nil and scratch_reader(scratch_dir .. entry.scratch, key, filehash)()
			if bufnr == nil and not content then
				goto continue -- its file failed its check: that text is lost, not the session
			end
			if bufnr == nil then
				bufnr = history.routines.buffer_from_text(content)
				vim.b[bufnr].cavediver_reopened = filehash
			end
			local new_filehash = history.register_buffer(bufnr)
			if new_filehash ~= filehash then
				require('cavediver.domains.ledger').move("reopened", { subject = new_filehash, name = "[No Name]",
					words = "open at the save, reopened under a new id" })
				window.data.rename_hash_in_triquetras(filehash, new_filehash)
				history.routines.rename_hash_in_history(filehash, new_filehash)
				history.routines.unregister_filepath(filepath)
			end
		end
		::continue::
	end
end

---Loads closed buffer history data.
---
---Restores the stack of closed buffer hashes that can be reopened, into the pool
---being loaded. A closed buffer the session manager brought back isn't closed any
---more, so it stays off the stack.
---
---A closed [No Name] text is read from its file only when it's reopened.
---
---@param closed_buffers ClosedBufferData Closed buffer list, newest last
---@param noname_content table<Filehash, {scratch: string, reopen: boolean|nil}> Each text's file name
---@param key string The session's key
---@param scratch_dir string The session's scratch directory
---@param times table<Filehash, integer>|nil When each was closed
---@param merge boolean|nil Whether the pool is open already, so what's in memory stays and the file's
---entries it doesn't have go under them, as the oldest
---@return nil
local function load_closed_buffers(closed_buffers, noname_content, key, scratch_dir, times, merge)
	if merge then
		-- what's in memory is newer than the file
	elseif load_pool.id == "" then
		history.clear_closed_buffers()
		load_pool = history.routines.pools()[""]
	else
		load_pool.closed, load_pool.times = {}, {}
	end
	local at = 1

	-- TODO: Open closed no name buffers with their content.
	if closed_buffers == nil then
		return
	end

	for _, filehash in ipairs(closed_buffers) do
		local filepath = history.get_filepath_from_hash(filehash) -- return: either closed filepath or NONAME_<x>
		if not filepath then
			require('cavediver.domains.ledger').never("What the fuck. This is impossible.")
		end
		if history.get_buffer_from_hash(filehash) then
			goto continue -- the session manager brought it back
		end
		if merge and vim.tbl_contains(load_pool.closed, filehash) then
			goto continue
		end
		if filepath:match("^NONAME_") then
			if history.data.noname_content[filehash] == nil or (load_pool.id ~= "" and not merge) then
				local content = noname_content[filehash]
				if content == nil then
					require('cavediver.domains.ledger').never("This is impossible. Noname content must be created for this closed No Name buffer.")
				end
				local source = scratch_dir .. content.scratch
				history.data.noname_content[filehash] = {
					scratch = content.scratch,
					source = source,
					key = key,
					read = scratch_reader(source, key, filehash),
				}
			elseif not merge then -- merged into an open pool, its text is cached already
				require('cavediver.domains.ledger').never("This is impossible. The closed buffer must not already exist in noname_content.")
			end
		end
		if merge then
			table.insert(load_pool.closed, at, filehash)
			at = at + 1
		else
			table.insert(load_pool.closed, filehash)
		end
		load_pool.times[filehash] = load_pool.times[filehash] or (times and times[filehash]) or nil
		::continue::
	end
	-- print_table(history.data.closed_buffers)
end

---Get a session's file path from its directory and name.
---
---The file is named after a hash of the two, in the configured session directory, which is made
---when it's missing.
---
---@param directory string The session's directory
---@param name string|nil The session's name (nil for a nameless save)
---@return string project_filepath Path of the session's main file
local function get_session_filepath(directory, name)
	if not directory then
		require('cavediver.domains.ledger').never("No directory provided to get_session_filepath")
	end

	-- the separator keeps a session "a" in /proj apart from a nameless save in /proja
	local session_hash = vim.fn.sha256(name and (directory .. "\n" .. name) or directory)

	-- TODO: implement configurable path for session storage
	local session_dir = configs.session_dir
	local project_filepath = session_dir .. session_hash

	vim.fn.mkdir(session_dir, "p")

	return project_filepath
end

-- each session's key once it's made, by directory and salt: another editor's save can give a file a
-- new salt, and a key kept by the file's path would then seal it with the wrong one. Each file's last
-- key is noted, so a session's key can go once the session isn't open.
local keys, key_of = {}, {}

---Get a session's key, made once for its directory and salt.
---
---The key is noted as the file's last one, so it can go once the session isn't open.
---
---@param directory string The session's directory, the secret the key is stretched from
---@param salt string The salt from the file's header
---@param file_path string The session's file, whose key this is now
---@return string key The session's key
local function key_for(directory, salt, file_path)
	local id = directory .. "\0" .. salt
	keys[id] = keys[id] or crypto.derive_key(directory, salt)
	key_of[file_path] = id
	return keys[id]
end

---Forgets the keys of sessions no longer open (defined further down, with the records)
---@type fun()
local forget_closed_keys

---Make a session's data keep the session file's policy.
---
---These are the rules every session file keeps, whichever writer made it: every closed entry, on
---`closed` or on a detached list, has its path in `paths`; a closed No Name entry has its text; and a
---hash the data holds as a record, closed, on a detached list or as a text, isn't an outsider, the
---record winning, since the registry is the authority on what a hash means. Whatever breaks a rule
---is taken out, and said in the lines it gives back.
---
---@param storage table The session's data, as it's written or as it was read
---@return string[] fixed What broke a rule, a line for each kind, empty when nothing did
local function enforce_session_file_policy(storage)
	local fixed, counts = {}, {}
	local function broke(line)
		if counts[line] == nil then
			table.insert(fixed, line)
		end
		counts[line] = (counts[line] or 0) + 1
	end
	local paths = storage.paths or {}
	local function keeps(filehash)
		local filepath = paths[filehash]
		if filepath == nil then
			broke("a closed entry no path names was left out")
			return false
		end
		if filepath:match("^NONAME_") and (storage.noname_content or {})[filehash] == nil then
			broke("a closed No Name entry with no text was left out")
			return false
		end
		return true
	end
	storage.closed = vim.tbl_filter(keeps, storage.closed or {})
	for _, list in ipairs(storage.detached or {}) do
		list.closed = vim.tbl_filter(keeps, list.closed or {})
	end
	if storage.outsiders then
		local held = {}
		for _, filehash in ipairs(storage.closed) do
			held[filehash] = true
		end
		for _, list in ipairs(storage.detached or {}) do
			for _, filehash in ipairs(list.closed) do
				held[filehash] = true
			end
		end
		for filehash, _ in pairs(storage.noname_content or {}) do
			held[filehash] = true
		end
		storage.outsiders = vim.tbl_filter(function(filehash)
			if held[filehash] then
				broke(vim.fn.fnamemodify(paths[filehash] or filehash, ":t") .. " was both an outsider and a record, and is kept as the record")
				return false
			end
			return true
		end, storage.outsiders)
	end
	for i, line in ipairs(fixed) do
		if counts[line] > 1 then
			fixed[i] = line .. " (" .. counts[line] .. " times)"
		end
	end
	return fixed
end

---Read and decrypt a session's main file.
---
---The header is checked first, so a newer format's file or one from before encryption is told apart
---from a damaged one. The key comes from the directory and the salt in the header.
---
---@param file_path string The session's main file
---@param directory string The session's directory, the secret its key is stretched from
---@param bytes string|nil The file's bytes, when they're read already
---@return table|nil saved_data The decoded data, or nil if there's a problem
---@return string|nil key The session's key, or nil if there's a problem
---@return string|nil problem "missing", "newer" (a newer format's header), "unencrypted" (the format
---before encryption) or "integrity" (an edited or corrupted file, or one that isn't this directory's)
---@return string[]|nil fixed What the data broke of the session file's policy and was fixed, as
---`enforce_session_file_policy()` says it
local function read_session_file(file_path, directory, bytes)
	bytes = bytes or read_file(file_path)
	if bytes == nil then
		return nil, nil, "missing"
	end
	if bytes:sub(1, #HEADER) ~= HEADER then
		if bytes:match("^CDV%d") then
			return nil, nil, "newer"
		elseif bytes:match("^%s*{") then
			return nil, nil, "unencrypted"
		end
		return nil, nil, "integrity"
	end
	local salt = bytes:sub(#HEADER + 1, #HEADER + crypto.salt_length)
	local key = key_for(directory, salt, file_path)
	local plaintext = crypto.open(key, bytes:sub(#HEADER + crypto.salt_length + 1), HEADER .. salt)
	local ok, saved_data = pcall(vim.json.decode, plaintext or "")
	if not plaintext or not ok or type(saved_data) ~= "table" then
		return nil, nil, "integrity"
	end
	return saved_data, key, nil, enforce_session_file_policy(saved_data) -- every read keeps the file's policy
end

---Read a session's saved data, as the load reads it.
---
---@param directory string The session's directory
---@param name string|nil The session's name (nil for a nameless save)
---@return table|nil saved_data The decoded data, or nil if it can't be read
---@return string|nil problem Why not, as `read_session_file()` says it
function M.read_session(directory, name)
	local saved_data, _, problem = read_session_file(get_session_filepath(directory, name), directory)
	return saved_data, problem
end

-- the file a load read before it started, so its scope could decide how the storage machine moves
local prepared = nil

---Read a session's file for the load about to run.
---
---The read is kept for `M.load_history()`, and its scope decides how the storage machine moves. A
---file's own scope wins over the hint, and with no usable file the hint decides.
---
---@param directory string The session's directory
---@param name string|nil The session's name (nil for a nameless save)
---@param hint integer|nil The tab the call names (load_session's `{ tab = … }`), which makes it
---a tab session loading into that tab
---@return boolean tab_session True if it's a tab session's load
function M.prepare_load(directory, name, hint)
	-- this runs before the storage machine moves, outside its hooks' catch: a failure here (libcrypto
	-- missing, a session directory that can't be made) is kept for the load's hook to raise
	local ok, saved_data, key, problem, fixed = xpcall(function()
		return read_session_file(get_session_filepath(directory, name), directory)
	end, debug.traceback)
	if not ok then
		prepared = { directory = directory, name = name, err = saved_data, hint = hint }
		return hint ~= nil
	end
	prepared = { directory = directory, name = name, saved_data = saved_data, key = key, problem = problem, hint = hint,
		fixed = fixed }
	if saved_data and saved_data.paths and saved_data.buffers and saved_data.windows then
		return saved_data.scope == "tab" -- a file's scope wins over the hint
	end
	return hint ~= nil
end

---Check if a session has a file, in that directory under that name.
---
---@param directory string The session's directory
---@param name string|nil The session's name (nil for a nameless save)
---@return boolean exists True if the session's main file is there
function M.session_exists(directory, name)
	return vim.uv.fs_stat(get_session_filepath(directory, name)) ~= nil
end

-- Detached lists ----------------------------------------------------------------------------------
--
-- A tab session is in one tab at a time: the tab the last load or save named. A tab it was in keeps a
-- detached list of its own, a copy of the session's list, named after the session (`t_DETACHED`,
-- `t_DETACHED_2`, …). It belongs to the whole editor's session: it's written into the whole editor's
-- file, apart from its closed list, and found again at a whole-editor load through its tab's windows;
-- once its tab is gone, it's in that file alone.

---Get the detached lists the whole editor's file holds.
---@return table[] lists The file's detached lists, or none if there's no such session or file
local function file_detached_lists()
	local session = data.unnamed or data.editor_session
	if session == nil then
		return {}
	end
	local saved = read_session_file(get_session_filepath(session.directory, session.name), session.directory)
	return saved and saved.detached or {}
end

---Create a detached pool, in no tab yet.
---@param label string The detached list's name
---@param of string|nil The id of the session's pool it came from
---@return Pool pool The new pool, added to the pools
local function new_detached_pool(label, of)
	local pool = { id = "\0detached\n" .. label, name = label, detached = true, of = of, closed = {}, times = {}, visits = {}, tabs = {} }
	history.data.pools[pool.id] = pool
	return pool
end

---Move a tab into a detached pool, out of the pool it was in.
---@param tabpage integer The tab that joins
---@param pool Pool The detached pool
---@return nil
local function join_detached(tabpage, pool)
	local previous = history.data.tab_pools[tabpage]
	if previous and history.data.pools[previous] then
		history.data.pools[previous].tabs[tabpage] = nil
	end
	history.data.tab_pools[tabpage] = pool.id
	pool.tabs[tabpage] = true
end

---Get the next free name for a detached list of a session.
---
---The names go `t_DETACHED`, then `t_DETACHED_2`, and so on, after the session's name (or its
---directory's), counting the names in memory and in the whole editor's file.
---
---@param pool Pool The session's pool
---@return string label The free name
local function detached_label(pool)
	local base = (pool.name or vim.fn.fnamemodify(pool.directory or "", ":t")) .. "_DETACHED"
	local taken = {}
	for _, other in pairs(history.data.pools) do
		if other.detached then
			taken[other.name] = true
		end
	end
	for _, list in ipairs(file_detached_lists()) do
		taken[list.label] = true
	end
	local label, n = base, 1
	while taken[label] do
		n = n + 1
		label = base .. "_" .. n
	end
	return label
end

---Push every other tab out of a session's pool.
---
---A session is in one tab at a time, so every other tab in its pool leaves it for a detached list
---of its own, a copy of the session's closed list, close times and visits.
---
---@param pool Pool The session's pool
---@param tabpage integer The tab the session is in now
---@return nil
local function push_out(pool, tabpage)
	for other, _ in pairs(vim.deepcopy(pool.tabs)) do
		if other ~= tabpage and vim.api.nvim_tabpage_is_valid(other) then
			local detached = new_detached_pool(detached_label(pool), pool.id)
			detached.closed, detached.times, detached.visits = vim.deepcopy(pool.closed), vim.deepcopy(pool.times), vim.deepcopy(pool.visits)
			join_detached(other, detached)
			history.routines.pool_changed(detached)
			require('cavediver.domains.ledger').move("detached", { subject = detached.id, name = detached.name,
				words = "tab " .. vim.api.nvim_tabpage_get_number(other) .. " keeps " .. history.routines.list_name(pool) .. "'s list" })
		end
	end
end

---Build the detached lists as the whole editor's file holds them.
---
---Each detached pool in memory comes first, with its closed list and close times. Its window
---entries come from `windows_of` at a save, and otherwise from the file, which a records write
---leaves as the session manager last saved them. Then each list the file holds and memory doesn't
---comes as it is, but with no windows at a save, since a save writes the windows anew.
---
---@param old table|nil The file's data
---@param windows_of (fun(pool: Pool): integer[])|nil A pool's window entries, at a save
---@return table[] lists The detached lists to write
---@return table<string, boolean> live The names of the lists in memory
local function detached_lists(old, windows_of)
	local lists, live, old_windows, pools = {}, {}, {}, {}
	for _, list in ipairs(old and old.detached or {}) do
		old_windows[list.label] = list.windows
	end
	for _, pool in pairs(history.data.pools) do
		if pool.detached then
			table.insert(pools, pool)
		end
	end
	table.sort(pools, function(a, b) return a.id < b.id end)
	for _, pool in ipairs(pools) do
		live[pool.name] = true
		local closed, times = serialise_closed_buffers({ pool })
		table.insert(lists, {
			label = pool.name, of = pool.of, closed = closed, closed_times = times,
			windows = windows_of and windows_of(pool) or old_windows[pool.name] or {},
		})
	end
	for _, list in ipairs(old and old.detached or {}) do
		if not live[list.label] then
			if windows_of then
				list.windows = {}
			end
			table.insert(lists, list)
		end
	end
	return lists, live
end

---Carry the detached lists' texts and paths into a whole-editor write.
---
---The closed No Name texts of the detached lists in memory are added to the texts the write takes.
---For the lists in the file alone, their texts' files are carried from the file by reference,
---unread, and so are their entries' paths, so the sweep keeps the files and nothing forgets where
---they point.
---
---@param lists table[] The detached lists to write
---@param live table<string, boolean> The names of the lists in memory
---@param old table|nil The file's data
---@param texts table<Filehash, table> The texts the write takes, added to in place
---@param paths table<Filehash, string> The paths the write takes, added to in place
---@param key string The session's key
---@param scratch_dir string The session's scratch directory
---@return nil
local function carry_detached(lists, live, old, texts, paths, key, scratch_dir)
	for _, pool in pairs(history.data.pools) do
		if pool.detached then
			for _, filehash in ipairs(pool.closed) do
				if texts[filehash] == nil and history.data.noname_content[filehash] and is_known(filehash) then
					texts[filehash] = history.data.noname_content[filehash]
				end
			end
		end
	end
	for _, list in ipairs(lists) do
		if not live[list.label] then
			for _, filehash in ipairs(list.closed or {}) do
				local entry = old and old.noname_content and old.noname_content[filehash]
				if texts[filehash] == nil and entry then
					local source = scratch_dir .. entry.scratch
					texts[filehash] = { scratch = entry.scratch, source = source, key = key, read = scratch_reader(source, key, filehash) }
				elseif texts[filehash] == nil and history.data.noname_content[filehash] then
					texts[filehash] = history.data.noname_content[filehash] -- moved in from a list in memory
				end
				if paths[filehash] == nil then
					paths[filehash] = old and old.paths and old.paths[filehash] or history.get_filepath_from_hash(filehash)
				end
			end
		end
	end
end

---Move a tab into a session's pool for a load.
---
---The session it was in until then is closed in that tab, its windows' triquetras dropped already.
---Once no tab is left in that session, its records are written and its pool goes, as when its last
---tab closes. When the session loads back into the tab of its own detached list, that list waits
---in memory instead, and the closed lists open on it at once.
---
---@param tabpage integer The tab the load goes into
---@param name string|nil The session's name (nil for a nameless save)
---@param directory string The session's directory
---@return Pool pool The session's pool
local function join_for_load(tabpage, name, directory)
	local before = history.routines.pool_of_tab(tabpage)
	local pool = history.routines.join_pool(tabpage, name, directory)
	if before ~= pool and before.detached and before.of == pool.id and next(before.tabs) == nil then
		-- the session loaded back into its detached tab: the closed lists open at once, on that list,
		-- which waits in memory for them to close
		before.merging = true
		vim.schedule(function()
			require('cavediver.domains.ui').routines.show_closed_lists({ focus = before })
		end)
	elseif before ~= pool and before.id ~= "" and next(before.tabs) == nil then
		M.close_tab_pool(before) -- a detached list goes into the whole editor's file instead
	end
	return pool
end

---Start a tab session fresh in the tab its hint names.
---
---Runs when a tab session loaded with the hint has no file it can use. Only that tab starts over,
---its windows taking what they show. Any other tab in the session's pool gets a detached list of
---its own.
---
---@param directory string The session's directory
---@param name string|nil The session's name (nil for a nameless save)
---@param tabpage integer The tab the hint names
---@return nil
local function start_tab_fresh(directory, name, tabpage)
	for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		if window.data.crux[winid] then
			window.data.unregister_triquetra(winid)
		end
	end
	if data.unnamed == nil and data.editor_session then
		data.unnamed = vim.deepcopy(data.editor_session) -- the whole editor's session, as tab sessions start
	end
	load_pool = join_for_load(tabpage, name, directory)
	push_out(load_pool, tabpage)
	for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		local bufnr = vim.api.nvim_win_get_buf(winid)
		if vim.api.nvim_win_get_config(winid).relative == "" and history.routines.is_trackable(bufnr) then
			vim.api.nvim_win_call(winid, function()
				history.routines.update_buffer_history(bufnr)
			end)
			window.get_triquetra(winid)
		end
	end
end

---Load a tab session into one tab.
---
---That tab's windows start over and take the file's entries, and the session's pool comes in with
---its closed stack and its own visits, older than any made from then on. The editor's history stays
---underneath. A pool already in memory is newer than the file, so it keeps its visits and its
---closed stack, and the file's closed entries it lacks go under them. Any other tab in the pool
---gets a detached list of its own.
---
---@param saved_data table The file's data
---@param key string The session's key
---@param file_path string The session's main file
---@param directory string The session's directory
---@param name string|nil The session's name (nil for a nameless save)
---@param tabpage integer The tab it loads into, the hint's or the current one
---@return WinId[] matched The windows that took an entry
local function load_tab_session(saved_data, key, file_path, directory, name, tabpage)
	for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		if window.data.crux[winid] then
			window.data.unregister_triquetra(winid)
		end
	end
	if data.unnamed == nil and data.editor_session then
		data.unnamed = vim.deepcopy(data.editor_session) -- the whole editor's session, as tab sessions start
	end
	-- a session already open in a tab, or whose list was kept: what's in memory is newer than the file
	local open = history.data.pools[history.routines.pool_id(name, directory)] ~= nil
	load_pool = join_for_load(tabpage, name, directory)
	push_out(load_pool, tabpage)
	local scratch_dir = file_path .. ".d/"
	load_buffer_history({ global = {} }, load_paths(saved_data.paths, saved_data.outsiders))
	if not open then
		-- its own visits, older than any made from now on
		load_pool.visits = {}
		local latest = 0
		for _, time in pairs(saved_data.buffers.global or {}) do
			latest = math.max(latest, time)
		end
		for filehash, time in pairs(saved_data.buffers.global or {}) do
			load_pool.visits[filehash] = time - latest - 1
		end
	end
	load_closed_buffers(saved_data.closed or {}, saved_data.noname_content or {}, key, scratch_dir, saved_data.closed_times, open)
	local window_histories, matched = load_window_buffer_relationships(saved_data.windows, tabpage)
	for winid, window_crux in pairs(window_histories) do
		history.data.crux_internals.window[winid] = window_crux
	end
	for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		if window.data.crux[winid] then
			history.routines.ensure_window_entry(winid)
		end
	end
	reopen_noname_buffers(saved_data.noname_content or {}, key, scratch_dir)
	for filehash, tag in pairs(saved_data.missing or {}) do
		history.data.missing[filehash] = history.data.missing[filehash] or tag
	end
	for _, filehash in ipairs(saved_data.unwritten or {}) do
		history.data.unwritten[filehash] = true
	end
	load_pool.changed_at, load_pool.saved_at = vim.uv.hrtime(), nil
	return matched
end

---Load complete session history data.
---
---Main entry point for restoring all buffer and window state from saved session.
---Coordinates loading of buffer history, window relationships, and closed buffers.
---
---@param cwd string The session's directory
---@param name string|nil The session's name (nil for a nameless save)
---@return nil
function M.load_history(cwd, name)
	if not cwd then
		error("Invalid current working directory.")
	end
	local file_path = get_session_filepath(cwd, name)
	-- an arrival queued before this load (the restore's own buffers flashing by) is noise the load
	-- replaces, so it's dropped when it settles.
	history.data.loads = history.data.loads + 1

	-- Try to load existing session data: the read the load made before it started, when it's this one
	local saved_data, key, problem, fixed
	local hint = nil
	if prepared and prepared.directory == cwd and prepared.name == name then
		if prepared.err then
			local err = prepared.err
			prepared = nil
			error(err, 0) -- the read's failure, raised here, where the hook's catch reports it
		end
		saved_data, key, problem, hint, fixed = prepared.saved_data, prepared.key, prepared.problem, prepared.hint,
			prepared.fixed
	else
		saved_data, key, problem, fixed = read_session_file(file_path, cwd)
	end
	prepared = nil
	if problem == "newer" then
		vim.notify("cavediver: this session's file was made by a newer cavediver. It's left alone, and the session starts fresh.", vim.log.levels.WARN)
	elseif problem == "unencrypted" then
		vim.notify("cavediver: this session's file is in the format from before encryption. Run the migration script, scripts/migrate_sessions.lua, to convert it; the session starts fresh.", vim.log.levels.WARN)
	elseif problem == "integrity" then
		vim.notify("cavediver: this session's file failed its integrity check (edited or corrupted). The session starts fresh, and the next save replaces the file.", vim.log.levels.WARN)
	elseif problem == "missing" and vim.uv.fs_stat(configs.session_dir .. vim.fn.sha256(cwd .. "\n"):sub(1, 32) .. ".json") then
		-- a file named the way it was before sessions had names and were encrypted: left as it is
		vim.notify("cavediver: this session has a file from before encryption. Run the migration script, scripts/migrate_sessions.lua, to convert it; the session starts fresh.", vim.log.levels.WARN)
	end
	if saved_data and not (saved_data.paths and saved_data.buffers and saved_data.windows) then
		saved_data = nil
	end
	-- only a writer's bug leaves a file breaking its rules: the read fixed the data, and the load says so
	fixed = saved_data and fixed or {}

	-- why there's no data, for the trail
	local why = ({ missing = "no session file", newer = "made by a newer cavediver", unencrypted = "from before encryption",
		integrity = "failed its integrity check" })[problem] or "its file holds no session"
	local ledger = require('cavediver.domains.ledger')
	if #fixed > 0 then
		vim.notify("cavediver: this session's file broke its own rules, and the load fixed them: " .. table.concat(fixed, "; ") .. ".",
			vim.log.levels.WARN)
	end
	---Record the load in the ledger, with how many windows matched or started fresh, and how many
	---entries were dropped.
	---@param matched integer[] The windows that took an entry
	---@param windows integer[] The windows the load lays its entries over
	---@param entries integer How many entries the file had
	---@return nil
	local function loaded(matched, windows, entries)
		local fresh = 0
		for _, winid in ipairs(windows) do
			if vim.api.nvim_win_get_config(winid).relative == "" and not vim.tbl_contains(matched, winid) then
				fresh = fresh + 1
			end
		end
		local words = #matched .. (#matched == 1 and " window" or " windows") .. " matched"
		if fresh > 0 then
			words = words .. " · " .. fresh .. " started fresh"
		end
		if entries > #matched then
			words = words .. " · " .. (entries - #matched) .. (entries - #matched == 1 and " entry" or " entries") .. " dropped"
		end
		if #fixed > 0 then
			words = words .. " · its file broke its own rules: " .. table.concat(fixed, "; ")
		end
		ledger.move("loaded", { name = vim.fn.fnamemodify(name or cwd, ":t"), words = words })
	end
	if (saved_data == nil and hint) or (saved_data and saved_data.scope == "tab") then
		-- either tab route drops the tab's triquetras and attaches history: a cycle ends first
		local tabpage = hint or vim.api.nvim_get_current_tabpage()
		local navigation = require('cavediver.domains.navigation')
		local cycling = navigation.data.cycling_window
		if cycling and vim.api.nvim_win_is_valid(cycling) then
			if vim.api.nvim_win_get_tabpage(cycling) == tabpage then
				-- a cycle running in the tab ends with nothing picked, as at a whole-editor load
				navigation.sm.current_state = navigation.states.NORMAL
				navigation.data.cycling_window = nil
			else
				-- one running elsewhere is cancelled, as a window jump cancels it: the load attaches history
				require('cavediver.domains.navigation.routines').cancel_cycle(cycling)
			end
		end
	end
	if saved_data == nil and hint then
		start_tab_fresh(cwd, name, hint)
		ledger.move("fresh", { name = vim.fn.fnamemodify(name or cwd, ":t"), words = "the tab started fresh: " .. why })
	elseif saved_data and saved_data.scope == "tab" then
		local matched = load_tab_session(saved_data, key, file_path, cwd, name, hint or vim.api.nvim_get_current_tabpage())
		loaded(matched, vim.api.nvim_tabpage_list_wins(hint or vim.api.nvim_get_current_tabpage()), #saved_data.windows)
		local set_cache_from_window_triquetra = require('cavediver').set_cache_from_window_triquetra
		for _, winid in ipairs(matched) do
			set_cache_from_window_triquetra(winid)
			window.routines.check_notes_under_current(window.data.crux[winid])
		end
	elseif saved_data then
		-- Restore from saved session
		load_pool = history.routines.pools()[""]
		data.editor_session, data.unnamed = { name = name, directory = cwd }, nil
		ledger.set_session(name, cwd)
		local scratch_dir = file_path .. ".d/"
		load_buffer_history(saved_data.buffers, load_paths(saved_data.paths, saved_data.outsiders))
		if saved_data.closed then
			load_closed_buffers(saved_data.closed, saved_data.noname_content or {}, key, scratch_dir, saved_data.closed_times)
		end
		local window_histories, matched, taken = load_window_buffer_relationships(saved_data.windows)
		loaded(matched, vim.api.nvim_list_wins(), #saved_data.windows)
		history.routines.initialise_crux_internals({ window = window_histories, global = saved_data.buffers.global })
		-- each detached list whose tab came back, found through its windows, joins that tab; the
		-- rest stay in the file alone
		for _, list in ipairs(saved_data.detached or {}) do
			local tabpage
			for _, i in ipairs(list.windows or {}) do
				if taken[i] and vim.api.nvim_win_is_valid(taken[i]) then
					tabpage = vim.api.nvim_win_get_tabpage(taken[i])
					break
				end
			end
			if tabpage and history.data.tab_pools[tabpage] == nil then
				load_pool = new_detached_pool(list.label, list.of)
				join_detached(tabpage, load_pool)
				ledger.move("detached", { subject = load_pool.id, name = list.label,
					words = "back with tab " .. vim.api.nvim_tabpage_get_number(tabpage) })
				load_closed_buffers(list.closed or {}, saved_data.noname_content or {}, key, scratch_dir, list.closed_times, true)
			end
		end
		load_pool = history.routines.pools()[""]
		reopen_noname_buffers(saved_data.noname_content or {}, key, scratch_dir)
		for filehash, tag in pairs(saved_data.missing or {}) do
			history.data.missing[filehash] = tag
		end
		for _, filehash in ipairs(saved_data.unwritten or {}) do
			history.data.unwritten[filehash] = true
		end
		if type(saved_data.label) == "string" then
			history.data.last_label = saved_data.label
			history.data.label_seen = true
		end
		-- the caches once every slot's buffer is back, the reopened No Name texts included
		local set_cache_from_window_triquetra = require('cavediver').set_cache_from_window_triquetra
		for _, winid in ipairs(matched) do
			set_cache_from_window_triquetra(winid)
		end
		-- the notes come from the file, so a slot loaded under a buffer can leave its notes naming it.
		for _, triquetra in pairs(window.data.crux) do
			window.routines.check_notes_under_current(triquetra)
		end
	else
		populate_history()
		data.editor_session, data.unnamed = { name = name, directory = cwd }, nil
		ledger.set_session(name, cwd)
		ledger.move("fresh", { name = vim.fn.fnamemodify(name or cwd, ":t"), words = "the session started fresh: " .. why })
	end
	load_pool = nil
	forget_closed_keys() -- the sessions this load closed let their keys go

	-- Run cleanup after loading to handle any inconsistencies
	history.cleanup_system()

	history.sm:to(historyState.ATTACHED, { buf = vim.api.nvim_get_current_buf() }, history.states.mode.UPDATE)
	-- print_table(history.data)
	-- print_table(window.data)
end

---Take in the window the restore left focused, once the restore's batch is over.
---
---When that window has a triquetra, it becomes the last valid window and the current one, and its
---crux and the bufferline order are built for it.
---
---@return nil
function M.after_restore()
	local winid = vim.api.nvim_get_current_win()
	if window.data.crux[winid] then
		window.data.last_valid_window = winid
		window.data.current_window = winid
		history.routines.construct_crux(winid)
		history.routines.update_buffer_history_ordered()
		history.routines.update_buffer_history_ordered_nonharpooned()
	end
end

---Get the key for a session's file, and its salt.
---
---The salt is read from the file and stays from one save to the next, so the key does too, and a
---text that didn't change keeps its file. A file with no usable salt gets a new random one. Throws
---if a newer cavediver made the file, so it isn't overwritten.
---
---@param file_path string The session's main file
---@param directory string The session's directory
---@return string key The session's key
---@return string salt The salt the file is written with
local function session_key(file_path, directory)
	local existing = read_file(file_path) or ""
	if existing:match("^CDV%d") and existing:sub(1, #HEADER) ~= HEADER then
		error("cavediver: this session's file was made by a newer cavediver, so it isn't overwritten: " .. file_path)
	end
	local salt = existing:sub(#HEADER + 1, #HEADER + crypto.salt_length)
	if existing:sub(1, #HEADER) ~= HEADER or #salt ~= crypto.salt_length then
		salt = crypto.random_bytes(crypto.salt_length)
	end
	return key_for(directory, salt, file_path), salt
end

---Write a session's main file, then sweep what it no longer needs.
---
---The main file is the commit point, so it's written after the texts it names. Then the text files
---nothing references any more are swept, with anything a crash left half-written. A closed No Name
---buffer whose text couldn't be kept leaves the file's closed stacks first, so no load meets a
---closed No Name entry without its text.
---
---@param file_path string The session's main file
---@param key string The session's key
---@param salt string The salt written into the header
---@param storage table The session's data
---@param kept table<string, boolean> The files in the scratch directory the main file references
---@return nil
local function commit_session(file_path, key, salt, storage, kept)
	enforce_session_file_policy(storage) -- whichever writer made the data, the file keeps its rules
	write_atomic(file_path, HEADER .. salt .. crypto.seal(key, vim.json.encode(storage), HEADER .. salt))

	local scratch_dir = file_path .. ".d/"
	if vim.fn.isdirectory(scratch_dir) == 1 then
		for _, entry in ipairs(vim.fn.readdir(scratch_dir)) do
			if not kept[entry] then
				vim.uv.fs_unlink(scratch_dir .. entry)
			end
		end
	end
	local base = vim.fn.fnamemodify(file_path, ":t")
	for _, entry in ipairs(vim.fn.readdir(configs.session_dir)) do
		if entry:sub(1, #base + 4) == base .. ".tmp" then
			vim.uv.fs_unlink(configs.session_dir .. entry)
		end
	end
end

---Get every pool for a whole-editor save, the editor's first.
---@return Pool[] pools The editor's pool, then each tab session's by id, detached lists left out
local function every_pool()
	local pools = {}
	for id, pool in pairs(history.routines.pools()) do
		if id ~= "" and not pool.detached then -- detached lists are written apart
			table.insert(pools, pool)
		end
	end
	table.sort(pools, function(a, b) return a.id < b.id end) -- a fixed order for closes at one time
	table.insert(pools, 1, history.routines.pools()[""])
	return pools
end

---Narrow a tab session's data to what it references.
---
---What it references is its windows' slots, queues, notes, histories and what they show, its
---pool's closed entries and visits, and its texts. The paths, missing files, outsiders and
---unwritten files are cut down to those.
---
---@param storage table The tab session's data, narrowed in place
---@return nil
local function narrow(storage)
	local referenced = {}
	local function add(filehash)
		if type(filehash) == "string" then
			referenced[(filehash:gsub("%-swap$", ""))] = true
		end
	end
	for _, entry in ipairs(storage.windows) do
		add(entry[1])
		add(entry[2])
		add(entry[4])
		add(entry[7])
		for _, filehash in ipairs(entry[3]) do
			add(filehash)
		end
		for _, map in ipairs({ entry[5], entry[6] }) do
			for k, v in pairs(map) do
				add(k)
				add(v)
			end
		end
		for filehash, _ in pairs(entry[9]) do
			add(filehash)
		end
	end
	for _, filehash in ipairs(storage.closed) do
		add(filehash)
	end
	for _, tbl in ipairs({ storage.buffers.global, storage.noname_content }) do
		for filehash, _ in pairs(tbl) do
			add(filehash)
		end
	end
	local function only(tbl)
		local out = {}
		for filehash, value in pairs(tbl) do
			if referenced[filehash] then
				out[filehash] = value
			end
		end
		return out
	end
	storage.paths = only(storage.paths)
	storage.missing = only(storage.missing)
	storage.outsiders = vim.tbl_filter(function(filehash) return referenced[filehash] end, storage.outsiders)
	storage.unwritten = storage.unwritten and vim.tbl_filter(function(filehash) return referenced[filehash] end, storage.unwritten)
	if storage.unwritten and #storage.unwritten == 0 then
		storage.unwritten = nil
	end
end

---The trail's pages --------------------------------------------------------------------

---Get a trail page's file name.
---
---The name hashes the session's key with the page's day, and ends in `.trail`, so it's told apart
---from a No Name text's file beside it.
---
---@param key string The session's key
---@param day string The page's day, `YYYY-MM-DD`
---@return string name The page's file name in the session's scratch directory
local function page_name(key, day)
	return vim.fn.sha256(hex(key) .. "\ntrail\n" .. day) .. ".trail"
end

---Trail pages read since cavediver started (a view reads only the pages it shows or searches, and
---a save reads a day's earlier page only the first time it writes that day)
M.page_reads = 0

---Read a trail page's steps from its file.
---
---Every call counts in `M.page_reads`.
---
---@param path string Path of the page's file
---@param key string The session's key
---@param day string The page's day, `YYYY-MM-DD`
---@return table[]|nil steps The page's steps, or nil if the file is missing or fails its check
local function read_page(path, key, day)
	M.page_reads = M.page_reads + 1
	local bytes = read_file(path)
	if bytes == nil then
		return nil
	end
	local plaintext = crypto.open(key, bytes, HEADER .. "trail\n" .. day)
	local ok, page = pcall(vim.json.decode, plaintext or "")
	if not plaintext or not ok or type(page) ~= "table" or type(page.steps) ~= "table" then
		return nil
	end
	return page.steps
end

---Filter the steps a session's file keeps.
---
---The whole editor's session keeps every step made under it while it covers every tab. The unnamed
---session keeps the steps made under it in tabs in no tab session, in detached tabs, and with no
---tab. A tab session keeps the steps in its tab and those whose moves name its pool or its list.
---
---@param owner Pool|nil The session's pool (nil for the whole editor's session)
---@param steps CavediverLedgerStep[] The steps to filter
---@param session string|nil The whole editor's session's key (`ledger.session_of`), nil before the first
---@return CavediverLedgerStep[] kept The steps the file keeps, in their order
local function steps_kept(owner, steps, session)
	local out = {}
	local list = owner and history.routines.list_name(owner)
	for _, step in ipairs(steps) do
		local kept
		if owner == nil then
			kept = step.session == session
		elseif owner.id == "" then
			kept = step.session == session
				and (step.pool == nil or step.pool == "" or step.pool:sub(1, 10) == "\0detached\n")
		else
			kept = step.pool == owner.id
			for _, move in ipairs(kept and {} or step.moves) do
				if move.subject == owner.id or (move.lists and vim.tbl_contains(move.lists, list)) then
					kept = true
					break
				end
			end
		end
		if kept then
			table.insert(out, step)
		end
	end
	return out
end

-- Per session file and day: the steps earlier editors wrote that day, read once, and how many of this
-- editor's steps the page holds already.
local pages_written = {}
-- A page that couldn't be written at a save is said once.
local trail_warned = false

---Write the trail pages a session's file keeps.
---
---Writes a page for each day the ledger holds steps of the session, with the steps earlier editors
---wrote that day, then this editor's. A day with nothing new isn't written again, and earlier days'
---pages stay as they are.
---
---@param file_path string The session's main file
---@param old_trail table<string, string>|nil The pages the main file lists, day → file name
---@param owner Pool|nil The session's pool (nil for the whole editor's session)
---@param session string The session's own key (`ledger.session_of`), which a whole editor's steps are marked with
---@param key string The session's key
---@param kept table<string, boolean> The names to keep in `<main>.d/`, which the pages are added to
---@return table<string, string>|nil trail The pages the main file lists now (nil if none)
local function write_trail_pages(file_path, old_trail, owner, session, key, kept)
	local ledger = require('cavediver.domains.ledger')
	local scratch_dir = file_path .. ".d/"
	local trail = {}
	for day, name in pairs(old_trail or {}) do
		trail[day] = name
	end
	pages_written[file_path] = pages_written[file_path] or {}
	for _, day in ipairs(ledger.trail_days()) do
		local mine = steps_kept(owner, ledger.trail(day), session)
		local moves = 0
		for _, step in ipairs(mine) do
			moves = moves + #step.moves
		end
		local count = #mine .. ":" .. moves
		local name = page_name(key, day)
		local written = pages_written[file_path][day]
		if #mine > 0 and not (written and written.key == key and written.count == count and trail[day] == name) then
			if not (written and written.key == key) then
				-- what editors before this one wrote that day stays
				local before = {}
				for _, step in ipairs(trail[day] and read_page(scratch_dir .. trail[day], key, day) or {}) do
					if type(step.time) == "number" and step.time < ledger.data.started then
						table.insert(before, step)
					end
				end
				written = { key = key, before = before }
			end
			local page = vim.list_slice(written.before, 1, #written.before)
			for _, step in ipairs(mine) do
				table.insert(page, {
					seq = step.seq, time = step.time, cause = step.cause, trigger = step.trigger, pool = step.pool,
					names = step.names, events = step.events, moves = step.moves, torn = step.torn,
				})
			end
			vim.fn.mkdir(scratch_dir, "p", 448) -- 0700
			write_atomic(scratch_dir .. name, crypto.seal(key, vim.json.encode({ steps = page }), HEADER .. "trail\n" .. day))
			written.count = count
			pages_written[file_path][day] = written
			trail[day] = name
		end
	end
	for _, name in pairs(trail) do
		kept[name] = true
	end
	return next(trail) and trail or nil
end

---Get the days a session's file has trail pages for, oldest first.
---@param directory string The session's directory
---@param name string|nil The session's name (nil for a nameless save)
---@return string[] days The days, `YYYY-MM-DD`, or none if the file can't be read
function M.trail_days(directory, name)
	local saved = read_session_file(get_session_filepath(directory, name), directory)
	local days = vim.tbl_keys(saved and saved.trail or {})
	table.sort(days)
	return days
end

---Read a day's page of a session's trail.
---@param directory string The session's directory
---@param name string|nil The session's name (nil for a nameless save)
---@param day string The page's day, `YYYY-MM-DD`
---@return table[]|nil steps The page's steps oldest first, or nil if it's missing or unreadable
function M.read_trail(directory, name, day)
	local file_path = get_session_filepath(directory, name)
	local saved, key = read_session_file(file_path, directory)
	local page = saved and saved.trail and saved.trail[day]
	if not page then
		return nil
	end
	return read_page(file_path .. ".d/" .. page, key, day)
end

---Write a session's records into its file.
---
---The records are its closed list, close times and No Name texts, from its pools, and the trail's
---pages ride along. Its references stay as the session manager last saved them, and the whole
---editor's records carry the detached lists too. A file that isn't there isn't made, and one that
---can't be read, or whose scope isn't the session's, isn't touched.
---
---@param session {name: string|nil, directory: string, pools: Pool[], owner: Pool|nil, scope: string}
---@param changes table<string, {closed: Filehash[], times: table}|false>|nil For the whole editor's
---session, new entries and close times for the lists in the file alone, by name (false, or no
---entries, drops the list)
---@return boolean written True if the file was written
---@return string|nil problem "missing" when there's no file, otherwise what went wrong
local function write_records(session, changes)
	if data.replayed then
		return true -- a replayed editor isn't a session: nothing waits to be written, and nothing is
	end
	local file_path = get_session_filepath(session.directory, session.name)
	local bytes = read_file(file_path)
	if bytes == nil then
		return false, "missing"
	end
	-- one read: the salt and the key come from the same bytes
	local saved, key, problem = read_session_file(file_path, session.directory, bytes)
	if not saved or not key or (saved.scope == "tab") ~= (session.scope == "tab") then
		return false, "it couldn't be read (" .. (problem or "another scope") .. "): " .. file_path
	end
	local gone = false
	local ok, err = pcall(function()
		local salt = bytes:sub(#HEADER + 1, #HEADER + crypto.salt_length)
		saved.closed, saved.closed_times = serialise_closed_buffers(session.pools)
		saved.paths = saved.paths or {}
		local texts = serialise_noname_content(session.owner)
		if session.scope == "editor" then
			-- the detached lists ride with the whole editor's records
			local lists, live = detached_lists(saved, nil)
			if changes then
				local kept = {}
				for _, list in ipairs(lists) do
					local change = changes[list.label]
					if live[list.label] or change == nil then
						table.insert(kept, list)
					elseif change and #change.closed > 0 then
						list.closed, list.closed_times = change.closed, change.times
						table.insert(kept, list)
					end
				end
				lists = kept
			end
			carry_detached(lists, live, saved, texts, saved.paths, key, file_path .. ".d/")
			saved.detached = #lists > 0 and lists or nil
			for _, list in ipairs(lists) do
				for _, filehash in ipairs(list.closed or {}) do
					saved.paths[filehash] = saved.paths[filehash] or history.get_filepath_from_hash(filehash)
				end
			end
		end
		local noname_content, kept = write_noname_texts(texts, key, file_path .. ".d/")
		saved.noname_content = noname_content
		for _, filehash in ipairs(saved.closed) do
			saved.paths[filehash] = saved.paths[filehash] or history.get_filepath_from_hash(filehash)
		end
		for filehash, _ in pairs(noname_content) do
			saved.paths[filehash] = saved.paths[filehash] or history.get_filepath_from_hash(filehash)
		end
		-- a file removed meanwhile isn't made again
		if not vim.uv.fs_stat(file_path) then
			gone = true
			return
		end
		saved.trail = write_trail_pages(file_path, saved.trail, session.owner,
			require('cavediver.domains.ledger').session_of(session.name, session.directory), key, kept) -- today's page rides along
		commit_session(file_path, key, salt, saved, kept)
	end)
	if not ok then
		return false, "it couldn't be written: " .. tostring(err)
	elseif gone then
		return false, "missing"
	end
	return true, nil
end

---Refresh the unnamed session's records in its file.
---
---Runs at a tab-session save. The closed stack and the No Name texts come from the editor's pool,
---and the references stay as the session manager last saved them. A file that isn't there isn't
---made, and one that can't be read or written isn't overwritten, with a warning. The tab session's
---own save, written by then, still goes through.
---
---@return nil
local function refresh_unnamed()
	local unnamed = data.unnamed
	if unnamed == nil then
		return
	end
	local editor = history.routines.pools()[""]
	local ledger = require('cavediver.domains.ledger')
	-- the whole editor's session's step of its own, so its page keeps it and the tab session's doesn't
	local ok, problem = ledger.within("save", vim.fn.fnamemodify(unnamed.name or unnamed.directory, ":t"), function()
		local written, why = write_records({
			name = unnamed.name, directory = unnamed.directory, pools = { editor }, owner = editor, scope = "editor",
		}) -- its detached lists ride with it
		if written then
			ledger.move("refreshed", { subject = "", name = "editor",
				words = "the whole editor's closed files and No Name texts written" })
		end
		return written, why
	end)
	if not ok and problem ~= "missing" then
		vim.notify("cavediver: the whole editor's session file wasn't refreshed with its closed files and No Name texts, since " .. problem, vim.log.levels.WARN)
	end
end

-- Records written on time ------------------------------------------------------------------------

-- the sessions whose records changed since they were last written (pool id → true), whether writes
-- run (between setup() and disable()), a generation a load moves on so a write it overtook is dropped,
-- the second's timer, the problems already reported (so each is told once), and the pools whose last
-- tab closed, waiting for the next tick (pool id → pool)
local dirty, writing, generation, quiet, told, closing = {}, false, 0, nil, {}, {}

---Get the whole editor's session, if there's one.
---
---It covers every tab, so every pool, until tab sessions start after its last save or load. From
---then on it's the unnamed session, which covers the tabs in no tab session, so the editor's pool.
---Either way the detached lists ride with it.
---
---@return table|nil session The session as a records write takes it, or nil if there's none
local function whole_editor_session()
	local editor_pool = history.routines.pools()[""]
	if data.unnamed then
		return { id = "", name = data.unnamed.name, directory = data.unnamed.directory, pools = { editor_pool }, owner = editor_pool, scope = "editor" }
	elseif data.editor_session then
		return { id = "", name = data.editor_session.name, directory = data.editor_session.directory, pools = every_pool(), scope = "editor" }
	end
	return nil
end

-- what the last look at the whole editor's file found, for an entry moved out of a list there
local file_view = nil

---Get the detached lists the whole editor's file holds alone, as the closed lists show them.
---
---Each list comes with its entries and close times, their paths, and each No Name text's first line
---and filetype, read from the file. What it finds is kept for `M.adopt_file_entry()`.
---
---@return {label: string, closed: Filehash[], times: table, paths: table, texts: table}[]
function M.file_only_lists()
	file_view = nil
	local session = whole_editor_session()
	if session == nil then
		return {}
	end
	local file_path = get_session_filepath(session.directory, session.name)
	local saved, key = read_session_file(file_path, session.directory)
	if not saved or not saved.detached then
		return {}
	end
	local scratch_dir = file_path .. ".d/"
	file_view = { paths = saved.paths or {}, noname_content = saved.noname_content or {}, key = key, scratch_dir = scratch_dir }
	local in_memory, lists = {}, {}
	for _, pool in pairs(history.data.pools) do
		if pool.detached then
			in_memory[pool.name] = true
		end
	end
	for _, list in ipairs(saved.detached) do
		if not in_memory[list.label] then
			local texts = {}
			for _, filehash in ipairs(list.closed or {}) do
				local entry = file_view.noname_content[filehash]
				if entry then
					local text = scratch_reader(scratch_dir .. entry.scratch, key, filehash)()
					texts[filehash] = { first = text and text.lines and text.lines[1] or "", filetype = text and text.filetype }
				end
			end
			table.insert(lists, { label = list.label, closed = list.closed or {}, times = list.closed_times or {}, paths = file_view.paths, texts = texts })
		end
	end
	return lists
end

---Get the closed files on the lists the whole editor's file holds alone.
---
---Only the main file is read, none of the texts.
---
---@return table<Filehash, boolean> closed Each closed file's hash → true
function M.file_only_closed()
	local closed = {}
	local session = whole_editor_session()
	if session == nil then
		return closed
	end
	local saved = read_session_file(get_session_filepath(session.directory, session.name), session.directory)
	if not saved or not saved.detached then
		return closed
	end
	local in_memory = {}
	for _, pool in pairs(history.data.pools) do
		if pool.detached then
			in_memory[pool.name] = true
		end
	end
	for _, list in ipairs(saved.detached) do
		if not in_memory[list.label] then
			for _, filehash in ipairs(list.closed or {}) do
				closed[filehash] = true
			end
		end
	end
	return closed
end

---Adopt an entry moved out of a list in the file alone onto a list in memory.
---
---Its path is registered, and a No Name text's file is held unread, as a load holds a closed one's.
---It uses what the last `M.file_only_lists()` found, and does nothing without it.
---
---@param filehash Filehash The entry's hash
---@return nil
function M.adopt_file_entry(filehash)
	if file_view == nil then
		return
	end
	local path = file_view.paths[filehash]
	if path and history.get_filepath_from_hash(filehash) == nil then
		history.register_filepath(path)
	end
	local entry = file_view.noname_content[filehash]
	if entry and history.data.noname_content[filehash] == nil then
		local source = file_view.scratch_dir .. entry.scratch
		history.data.noname_content[filehash] = { scratch = entry.scratch, source = source, key = file_view.key, read = scratch_reader(source, file_view.key, filehash) }
	end
end

---Write the closed lists' edits to the lists in the whole editor's file alone.
---@param changes table<string, {closed: Filehash[], times: table}|false> Each list's new entries
---and close times, by name (false, or no entries, drops the list)
---@return boolean written True if the file was written
---@return string|nil problem "missing" when there's no session or file, otherwise what went wrong
function M.write_file_only_lists(changes)
	local session = whole_editor_session()
	if session == nil then
		return false, "missing"
	end
	return write_records(session, changes)
end

---Settle the detached lists that waited on the closed lists, once those are gone.
---
---A session loaded back into its own detached list's tab opens the closed lists on that list, and
---the list waits in memory until they close. Then a list still holding entries goes into the whole
---editor's file, as any left with no tab does, and one the merge emptied goes from memory and from
---the file.
---
---@return nil
function M.settle_merging()
	for id, pool in pairs(history.data.pools) do
		if pool.merging and next(pool.tabs) == nil then
			pool.merging = nil
			if #pool.closed == 0 then
				history.data.pools[id] = nil
				require('cavediver.domains.ledger').move("detached_left", { subject = id, name = pool.name, words = "merged, and gone" })
				local session = whole_editor_session()
				if session then
					write_records(session, { [pool.name] = false })
				end
			else
				M.close_tab_pool(pool)
			end
		end
	end
end

---Get every session cavediver knows, the whole editor's and each tab session's.
---@return {id: string, name: string|nil, directory: string, pools: Pool[], owner: Pool|nil, tabs: table|nil, scope: string}[]
local function known_sessions()
	local sessions = {}
	table.insert(sessions, whole_editor_session())
	for id, pool in pairs(history.routines.pools()) do
		if id ~= "" and pool.directory then
			table.insert(sessions, { id = id, name = pool.name, directory = pool.directory, pools = { pool }, owner = pool, tabs = pool.tabs, scope = "tab" })
		end
	end
	return sessions
end

---Check if the editor is still where a session would be saved from.
---
---For the whole editor's session that's the global directory, and for a tab session one of its
---tabs' directories. A switch whose load isn't wired leaves the editor elsewhere, and nothing is
---written then.
---
---@param session table The session, as `known_sessions()` gives it
---@return boolean there True if the editor is still in the session's directory
local function still_there(session)
	if session.scope == "editor" then
		return vim.fn.getcwd(-1, -1) == session.directory
	end
	for tabpage, _ in pairs(session.tabs or {}) do
		if vim.api.nvim_tabpage_is_valid(tabpage) and vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tabpage)) == session.directory then
			return true
		end
	end
	return false
end

forget_closed_keys = function()
	local open = {}
	for _, session in ipairs(known_sessions()) do
		local id = key_of[get_session_filepath(session.directory, session.name)]
		if id then
			open[id] = true
		end
	end
	for id, _ in pairs(keys) do
		if not open[id] then
			keys[id] = nil
		end
	end
	for file_path, id in pairs(key_of) do
		if not open[id] then
			key_of[file_path] = nil
		end
	end
end

---Write a session's records now, warning once about what stops it.
---
---A missing file isn't warned about. A session that's written is no longer marked as changed.
---
---@param session table The session, as `known_sessions()` gives it
---@return boolean written True if the records were written
local function write_now(session)
	local ok, problem = write_records(session)
	if ok then
		dirty[session.id] = nil
	elseif problem ~= "missing" and not told[session.id .. problem] then
		told[session.id .. problem] = true
		vim.notify("cavediver: " .. (session.name or vim.fn.fnamemodify(session.directory, ":t")) .. "'s closed files and No Name texts weren't written, since " .. problem, vim.log.levels.WARN)
	end
	return ok
end

---Write the records of a pool whose last tab closed, then let the pool go.
---
---A tab session's records go into its own file, and a detached list's into the whole editor's. When
---they can't be written, the pool is kept with no tab, and a warning says so. A load since, which
---tore it down, or a tab back in it, leaves it alone.
---
---@param pool Pool The pool whose last tab closed
---@return nil
local function close_now(pool)
	closing[pool.id] = nil
	if history.data.pools[pool.id] ~= pool or next(pool.tabs) ~= nil then
		return
	end
	if pool.detached then
		-- a detached list goes into the whole editor's file, and leaves memory
		local session = whole_editor_session()
		local ok, problem = false, "missing"
		if session then
			ok, problem = write_records(session)
		end
		local ledger = require('cavediver.domains.ledger')
		if ok then
			history.data.pools[pool.id] = nil
			ledger.move("detached_left", { subject = pool.id, name = pool.name, words = data.replayed and "let go" or "into the whole editor's file" })
			return
		end
		ledger.move("detached_left", { subject = pool.id, name = pool.name, words = "kept, with no tab" })
		vim.notify("cavediver: " .. pool.name .. "'s tab is gone, and its closed files couldn't be written into the whole editor's session file (" ..
			(problem == "missing" and "it has no session file yet" or problem) .. "); they stay, with no tab, in :CavediverClosed.", vim.log.levels.WARN)
		return
	end
	local ok, problem = write_records({ name = pool.name, directory = pool.directory, pools = { pool }, owner = pool, scope = "tab" })
	local ledger = require('cavediver.domains.ledger')
	if ok then
		dirty[pool.id] = nil
		history.data.pools[pool.id] = nil
		forget_closed_keys()
		ledger.move("tab_closed", { subject = pool.id, name = history.routines.list_name(pool),
			words = data.replayed and "its list let go" or "its records written; its list let go" })
		return
	end
	ledger.move("tab_closed", { subject = pool.id, name = history.routines.list_name(pool), words = "kept, with no tab" })
	vim.notify("cavediver: " .. (pool.name or vim.fn.fnamemodify(pool.directory or "", ":t")) .. "'s tab closed, and its closed files couldn't be written (" ..
		(problem == "missing" and "it has no session file yet" or problem) .. "); they stay, with no tab, in :CavediverClosed.", vim.log.levels.WARN)
end

---Write every changed session's records.
---
---Runs only while records are being written and storage is idle, and skips a session when the
---editor isn't where it would be saved from.
---
---@param all boolean|nil Whether to write every known session, changed or not, and the pools whose
---last tab closed, as at quit, when nothing scheduled runs any more
---@return nil
function M.write_records(all)
	if not writing or require('cavediver.domains.storage.sm'):state() ~= "idle" then
		return
	end
	if all then
		for _, pool in pairs(closing) do
			close_now(pool)
		end
	end
	for _, session in ipairs(known_sessions()) do
		if (all or dirty[session.id]) and still_there(session) then
			write_now(session)
		end
	end
end

---Mark a pool's records as changed, and schedule their write.
---
---The first change after a quiet second is written on the next tick, and the rest of that second
---when it ends. A detached list's changes count as the whole editor's. Nothing happens while
---records aren't being written.
---
---@param id string The pool's id
---@return nil
function M.records_changed(id)
	if not writing then
		return
	end
	local pool = history.data.pools[id]
	if pool and pool.detached then
		id = "" -- a detached list's records are the whole editor's
	end
	dirty[id] = true
	if quiet and quiet:is_active() then
		return
	end
	local mine = generation
	vim.schedule(function()
		if mine == generation then
			M.write_records()
		end
	end)
	quiet = quiet or vim.uv.new_timer()
	quiet:start(1000, 0, vim.schedule_wrap(function()
		if mine == generation then
			M.write_records()
		end
	end))
end

---Drop the record writes still waiting, as a load starts.
---
---A write still waiting may hold the session manager's teardown, so it's dropped, and so is the
---write of a tab the teardown closed. Writes already scheduled see the generation move on, and
---skip themselves.
---
---@return nil
function M.drop_pending_records()
	generation = generation + 1
	if quiet then
		quiet:stop()
	end
	dirty = {}
	closing = {}
end

---Start or stop writing records.
---
---Turned on by setup(), and off by disable() and by a dump's replay. While it's on, history tells
---`M.records_changed()` of each change to a pool's records. Turning it off drops the writes still
---waiting.
---
---@param on boolean Whether records are written
---@return nil
function M.write_records_on(on)
	writing = on
	if not on then
		M.drop_pending_records()
	end
	history.routines.on_records_change = on and M.records_changed or nil
end

---Close a pool whose last tab left it, on the next tick.
---
---Its records are written, a detached list's into the whole editor's file, and then the pool goes.
---A session manager's switch closes tabs inside its teardown, before the load it ends with, so a
---load in the same batch drops this write with the rest.
---
---@param pool Pool The pool whose last tab left
---@return nil
function M.close_tab_pool(pool)
	closing[pool.id] = pool
	local mine = generation
	vim.schedule(function()
		if mine == generation and closing[pool.id] == pool then
			close_now(pool)
		end
	end)
end

---Save complete session history data to persistent storage.
---
---Serializes all buffer history, window relationships, and closed buffers
---into a file named after the session's directory and name, encrypted with a
---key stretched from the directory. Every [No Name] text that changed goes into
---a file of its own first, and the main file goes last, so it's the commit point.
---Then the text files nothing references any more are swept.
---
---@param cwd string The session's directory to save session data for
---@param name string|nil The session's name (nil for a nameless save)
---@param tab integer|nil The tab, for a tab session, which joins that session's pool and saves only
---its windows, its pool and its texts
---@return nil
function M.save_history(cwd, name, tab)
	if not cwd then
		error("Invalid current working directory.")
	end

	-- Run cleanup before saving to ensure clean state
	history.cleanup_system()

	local file_path = get_session_filepath(cwd, name)
	local key, salt = session_key(file_path, cwd)

	local pool
	if tab then
		local before = history.routines.pool_of_tab(tab)
		pool = history.routines.join_pool(tab, name, cwd)
		if pool ~= before and next(pool.visits) == nil then
			-- a tab saved as this session for the first time: its own visits start the pool's
			for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
				for filehash, time in pairs(history.data.crux_internals.window[winid] or {}) do
					pool.visits[filehash] = math.max(pool.visits[filehash] or time, time)
				end
			end
		end
		if data.unnamed == nil and data.editor_session then
			data.unnamed = vim.deepcopy(data.editor_session) -- the whole editor's session, as tab sessions start
		end
		push_out(pool, tab)
		if pool ~= before then
			-- saved under a session it wasn't in: what the tab holds goes under that name, the closed
			-- files its slots hold included; the list it leaves keeps its copy
			for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
				local triquetra = window.data.crux[winid]
				if triquetra then
					history.routines.carry_closed(before, pool, triquetra.current_slot)
					history.routines.carry_closed(before, pool, triquetra.secondary_slot)
					history.routines.carry_closed(before, pool, triquetra.ternary_slot)
					for _, filehash in ipairs(triquetra.primary_buffer or {}) do
						history.routines.carry_closed(before, pool, filehash)
					end
				end
			end
			if before.id ~= "" and next(before.tabs) == nil then
				M.close_tab_pool(before) -- the session it leaves, with no tab left, is written and goes
			end
		end
	end

	local outsiders = {}
	local windows, entry_wins = serialise_window_relationships(outsiders, tab)
	local texts, paths = serialise_noname_content(pool), serialise_paths(outsiders)
	local detached
	if not pool then
		-- the detached lists, apart: each in memory with its tab's window entries, and each the file
		-- holds alone carried over, with its texts and paths
		local old = read_session_file(file_path, cwd)
		local live
		detached, live = detached_lists(old, function(detached_pool)
			local indices = {}
			for i, winid in ipairs(entry_wins) do
				if vim.api.nvim_win_is_valid(winid) and detached_pool.tabs[vim.api.nvim_win_get_tabpage(winid)] then
					table.insert(indices, i)
				end
			end
			return indices
		end)
		carry_detached(detached, live, old, texts, paths, key, file_path .. ".d/")
	end
	local noname_content, kept = write_noname_texts(texts, key, file_path .. ".d/")
	local closed, closed_times = serialise_closed_buffers(pool and { pool } or every_pool())
	local storage = {
		scope = tab and "tab" or "editor", -- a tab session's file loads into a tab
		detached = detached and #detached > 0 and detached or nil, -- the whole editor's detached lists, when there are some
		paths = paths,
		outsiders = vim.tbl_keys(outsiders),
		buffers = pool and { global = pool.visits } or serialise_buffer_history(),
		windows = windows,
		closed = closed,
		closed_times = closed_times, -- when each was closed, to merge pools by
		noname_content = noname_content,
		missing = history.data.missing, -- where each file gone from disk went missing
		label = history.data.last_label, -- where you were at this save: the label being left at the next load
		unwritten = next(history.data.unwritten) and vim.tbl_keys(history.data.unwritten) or nil, -- files never written
	}

	if pool then
		narrow(storage)
	end
	-- the trail's pages: today's written, earlier days' kept. A page that can't be written doesn't stop
	-- the save: the pages it had stay.
	local previous = read_session_file(file_path, cwd)
	if not pool then
		require('cavediver.domains.ledger').claim(name, cwd) -- a first whole-editor save takes the steps before it
	end
	local written, trail = pcall(write_trail_pages, file_path, previous and previous.trail, pool,
		require('cavediver.domains.ledger').session_of(name, cwd), key, kept)
	if written then
		storage.trail = trail
	else
		storage.trail = previous and previous.trail
		for _, page in pairs(storage.trail or {}) do
			kept[page] = true
		end
		if not trail_warned then
			trail_warned = true
			vim.notify("cavediver: the trail's page couldn't be written (" .. tostring(trail) .. "); the session is saved without it.",
				vim.log.levels.WARN)
		end
	end

	-- Write updated data back to file
	commit_session(file_path, key, salt, storage, kept)
	require('cavediver.domains.ledger').move("saved", { name = vim.fn.fnamemodify(name or cwd, ":t"),
		words = pool and "the tab session" or "the whole editor" })
	if pool then
		pool.saved_at = vim.uv.hrtime()
		dirty[pool.id] = nil
		refresh_unnamed()
	else
		-- a whole-editor save covers every tab again: tab sessions started after it make it the unnamed one
		data.editor_session, data.unnamed = { name = name, directory = cwd }, nil
		require('cavediver.domains.ledger').set_session(name, cwd)
		dirty[""] = nil
	end
	forget_closed_keys()
end

---Get the session whose trail the current tab shows.
---
---That's the tab's own tab session, or else the whole editor's. The owner is the list whose steps
---the session's file keeps, nil while the whole editor's session covers every tab. With no
---whole-editor session yet but tab sessions about, the tabs in none are the editor's list.
---
---@return {name: string|nil, directory: string}|nil session The session (nil with no file yet)
---@return Pool|nil owner The list whose steps the session's file keeps
function M.trail_session()
	local pool = history.routines.current_pool()
	if pool.id ~= "" and not pool.detached then
		return { name = pool.name, directory = pool.directory }, pool
	end
	local session = whole_editor_session()
	if session then
		return session, session.owner
	end
	-- no whole-editor session yet: with tab sessions about, the tabs in none are the editor's list
	for id, other in pairs(history.data.pools) do
		if id ~= "" and not other.detached then
			return nil, history.routines.pools()[""]
		end
	end
	return nil, nil
end

---Make a reader of the current tab's trail.
---
---The session's main file is read once, and each page once, when it's asked for, so a view reads
---only the pages it shows. A day's steps are the page's steps from editors before this one, then
---this editor's steps that the session's file keeps, by the same rule its pages are written by.
---
---@return {days: fun(): string[], steps: fun(day: string): table[]} reader
function M.trail_reader()
	local ledger = require('cavediver.domains.ledger')
	local session, owner = M.trail_session()
	local file_path, saved, key
	if session then
		file_path = get_session_filepath(session.directory, session.name)
		saved, key = read_session_file(file_path, session.directory)
	end
	local trail = saved and saved.trail or {}
	local whole = session and ledger.session_of(session.name, session.directory)
	local pages = {}
	local reader = {}
	---Get the days the trail has steps of, from its pages and this editor's ledger, oldest first.
	function reader.days()
		local days = {}
		for day, _ in pairs(trail) do
			days[day] = true
		end
		for _, day in ipairs(ledger.trail_days()) do
			if #steps_kept(owner, ledger.trail(day), whole) > 0 then
				days[day] = true
			end
		end
		local list = vim.tbl_keys(days)
		table.sort(list)
		return list
	end
	---Get a day's steps, oldest first, reading its page only the first time.
	function reader.steps(day)
		if pages[day] == nil then
			local steps = {}
			if trail[day] and key then
				for _, step in ipairs(read_page(file_path .. ".d/" .. trail[day], key, day) or {}) do
					if type(step.time) == "number" and step.time < ledger.data.started then
						table.insert(steps, step)
					end
				end
			end
			pages[day] = steps
		end
		return vim.list_extend(vim.list_slice(pages[day], 1, #pages[day]), steps_kept(owner, ledger.trail(day), whole))
	end
	---Check if a step of this editor's is the trail's, by the rule its pages are written by.
	function reader.keeps(step)
		return #steps_kept(owner, { step }, whole) > 0
	end
	return reader
end

---Write a session's file from data in the saved shape, as a save writes it.
---
---Used by the migration script to write the files it converts. The data holds `paths`,
---`outsiders`, `buffers`, `windows` and `closed`, as a save writes them.
---
---@param directory string The session's directory
---@param name string|nil The session's name (nil for a nameless save)
---@param storage table The session's data, in the saved shape
---@param texts table<Filehash, NoNameBufferContent> The No Name texts, `reopen` marking open ones
---@return nil
function M.write_session(directory, name, storage, texts)
	local file_path = get_session_filepath(directory, name)
	local key, salt = session_key(file_path, directory)
	local noname_content, kept = write_noname_texts(texts, key, file_path .. ".d/")
	storage.noname_content = noname_content
	commit_session(file_path, key, salt, storage, kept)
end

return M
