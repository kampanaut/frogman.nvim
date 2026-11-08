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
---@field [10] {name: string, marks: table<string, Filehash>}[]|nil The window's marks, when it has some
---@field [11] table[]|nil The window's snapshots, when it has some, each its files by hash
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

local data = require('frogman.domains.storage.data')
local history = require('frogman.domains.history')
local pool_class = require('frogman.domains.history.pool')
local historyState = require('frogman.domains.history.states')
local window = require('frogman.domains.window')
local configs = require('frogman.configs')
local crypto = require('frogman.domains.storage.crypto')

local M = {}

---Get the marks domain's routines, required when first used, since it requires the storage machine.
---@return table routines
local function marks()
	return require('frogman.domains.marks').routines
end

---Get the snapshots domain's routines, required when first used, as the marks' are.
---@return table routines
local function snapshots()
	return require('frogman.domains.snapshots').routines
end


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
	local said = false
	return function()
		local bytes = read_file(path)
		local plaintext = bytes and crypto.open(key, bytes, HEADER .. filehash)
		local ok, text = pcall(vim.json.decode, plaintext or "")
		if not plaintext or not ok or type(text) ~= "table" then
			if not said then -- said once for the text, however often it's read
				said = true
				vim.notify(bytes == nil and "frogman: a No Name text's file is missing, so that text is lost."
					or "frogman: a No Name text's file failed its integrity check (edited or corrupted), so that text is lost.", vim.log.levels.WARN)
			end
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

---Get the hash a file is saved under, only if the path registry knows it.
---@param id HandleId|nil The file's handle
---@return Filehash|nil filehash Its hash, or nil if nothing knows it
local function known(id)
	local filehash = history.get_hash_from_handle(id)
	if is_known(filehash) then
		return filehash
	end
	-- nothing knows this hash (a path is kept while anything references it, so this shouldn't
	-- happen). it's dropped rather than failing the save on frogman's own data.
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
		if name == "" and vim.b[bufnr].frogman_noname then
			name = "NONAME_" .. vim.b[bufnr].frogman_noname
		end
		if
			vim.api.nvim_buf_is_valid(bufnr)
			and name ~= ""
			and paths[history.routines.get_filehash(name)]
			and history.routines.is_trackable(bufnr)
		then
			history.register_buffer(bufnr, { load = true }) -- the load's own, which the trail leaves out
		end
	end

	for id, time in pairs(history.keyed_by_handle(buffers.global)) do
		history.track_buffer(id, time)
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
---@param id HandleId|nil The slot's file's handle
---@return nil
local function close_if_not_restored(id)
	local filepath = history.get_filepath_from_handle(id)
	local into = load_pool or history.routines.pools()[""]
	if
		filepath and
		not filepath:match("^NONAME_") and
		history.get_buffer_from_handle(id) == nil and
		not vim.tbl_contains(into.closed, id)
	then
		into:push_oldest(id, nil, true) -- the load's own: not news to its file
		local ledger = require('frogman.domains.ledger')
		local filehash = history.get_hash_from_handle(id)
		ledger.move("closed", { subject = filehash, name = ledger.name_of(filehash),
			lists = { history.routines.list_name(into) },
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
---@return table<WinId, table<HandleId, number>> window_histories Each matched window's own access history
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
		local reopened = vim.b[vim.api.nvim_win_get_buf(actual_winid)].frogman_reopened
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
		local current_slot = history.get_handle_from_hash(cfilehash)
			or history.get_handle_from_buffer(vim.api.nvim_win_get_buf(actual_winid))

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

		-- the file's hashes, as the slots' handles
		local secondary_slot = history.get_handle_from_hash(sfilehash)
		local ternary_slot = history.get_handle_from_hash(tfilehash)
		local primary_buffer = history.handles_of(pfilehashes)

		window.set_buffer_relationship(
			actual_winid,
			{
				current_slot = current_slot,
				secondary_slot = secondary_slot,
				ternary_slot = ternary_slot,
				primary_buffer = primary_buffer,
				displacement_ternary_map = window.data.notes_by_handle(tdisplacement_map),
				displacement_secondary_map = window.data.notes_by_handle(sdisplacement_map),
				primary_enabled = triquetra_serialised[8] == true
			}
		)
		window_histories[actual_winid] = history.keyed_by_handle(triquetra_serialised[9])
		-- oil keeps the buffer it was opened from in a window variable no session manager saves, so
		-- `q` there goes back to the window's current slot
		local wbufnr = vim.api.nvim_win_get_buf(actual_winid)
		local current_bufnr = history.get_buffer_from_handle(current_slot)
		if vim.bo[wbufnr].filetype == "oil" and current_bufnr then
			vim.w[actual_winid].oil_original_buffer = current_bufnr
		end
		close_if_not_restored(current_slot)
		close_if_not_restored(secondary_slot)
		close_if_not_restored(ternary_slot)
		for _, id in ipairs(primary_buffer) do
			close_if_not_restored(id)
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
		global = history.keyed_by_hash(history.data.crux_internals.global)
	}
end

---Serialize window buffer relationships for session saving.
---
---Creates a compressed representation of all window triquetra relationships
---that can be safely serialized to JSON. Holds one entry per window with a triquetra,
---in window order, with its slots and notes as hashes, its own access history and what
---it shows, so the load can find it. A slot whose file the path registry doesn't know is
---dropped.
---
---@return WindowBufferData compressed Serializable window relationship data
---@return WinId[] entry_wins The window each entry came from
---@param outsiders table<Filehash, string> Filled with the untracked buffers the windows show
---@param tabpage integer|nil The tab to save windows from, for a tab session (nil = every window)
local function serialise_window_relationships(outsiders, tabpage)
	local compressed = {}
	local entry_wins = {} -- the window each entry was written from

	local compressed_index = 1
	for _, winid in pairs(tabpage and vim.api.nvim_tabpage_list_wins(tabpage) or vim.api.nvim_list_wins()) do
		if window.data.crux[winid] ~= nil then -- yes, a direct existence check sorry for breaking encapsulation
			local triquetra = window.get_triquetra(winid)

			-- each slot's handle first, then the hash it's saved under
			---@type HandleId|Filehash|vim.NIL|nil
			local cfilehash
			---@type HandleId|Filehash|vim.NIL|nil
			local sfilehash
			---@type HandleId|Filehash|vim.NIL|nil
			local tfilehash
			---@type HandleId[]|Filehash[]|nil
			local pfilehashes = {}
			---@type table<HandleId|string, HandleId>|nil
			local sdisplacement_map = {}
			---@type table<HandleId|string, HandleId>|nil
			local tdisplacement_map = {}

			if not triquetra then
				require('frogman.domains.ledger').never("This is impossible. The window triquetra must exist.")
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
				for _, id in ipairs(pfilehashes) do -- no holes: a file nothing knows is dropped
					table.insert(serialised, known(id))
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
			if outsider and not is_known(shows) then -- a file frogman knows isn't one, even through its unlisted buffer
				outsiders[shows] = outsider
			end

			compressed[compressed_index] = {
				[1] = cfilehash, -- Current buffer
				[2] = sfilehash, -- Secondary slot
				[3] = pfilehashes, -- Primary buffer
				[4] = tfilehash, -- Ternary slot
				[5] = window.data.notes_by_hash(tdisplacement_map),
				[6] = window.data.notes_by_hash(sdisplacement_map),
				[7] = shows or vim.NIL, -- What the window shows
				[8] = triquetra.primary_enabled == true,
				[9] = history.keyed_by_hash(history.data.crux_internals.window[winid])
			}
			compressed[compressed_index][10] = marks().serialise("window", winid) -- its marks, when it has some
			compressed[compressed_index][11] = snapshots().serialise_window(winid) -- its snapshots, when it has some
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
---closed in more than one pool is kept once, at its newer close, and a file the
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
			if known(v) and (keep[v] == nil or time > keep[v].time) then
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
		local filehash = known(v) -- saved by hash
		table.insert(copy, filehash)
		times[filehash] = pools[best].times[v]
	end
	return copy, times
end

---Check if a pool owns an open No Name text.
---
---A pool owns the texts its tabs visited, those a window of its tabs shows or has in its history, and
---a tab session's pool the ones its visits hold, once the window that visited one has closed. The
---editor's pool also owns the ones no tab session visited, by its windows or its visits. With no
---pool, every text is owned, as the whole editor's session holds them all while it covers every tab.
---
---@param owner Pool|nil The pool (nil = every text)
---@param handle_id HandleId|nil The No Name buffer's file's handle
---@return boolean owned True if the pool owns the text
local function owned(owner, handle_id)
	if owner == nil then
		return true
	end
	local visited = history.routines.tabs_that_visited(handle_id)
	for tabpage, _ in pairs(visited) do
		if history.routines.pool_of_tab(tabpage) == owner then
			return true
		end
	end
	if owner.id ~= "" then
		return owner.visits[handle_id] ~= nil -- visited in its tab, though the window that did is gone
	end
	for tabpage, _ in pairs(visited) do
		local pool = history.routines.pool_of_tab(tabpage)
		if pool.id ~= "" and not pool.detached then
			return false -- a tab session's text
		end
	end
	for id, pool in pairs(history.routines.pools()) do
		if id ~= "" and not pool.detached and pool.visits[handle_id] then
			return false -- a tab session's text, by its visits
		end
	end
	return true
end

---Get an open [No Name] buffer's text as a session file keeps it: its lines, its filetype and the cursor
---of a window showing it, in any tab, marked to be reopened at load, since no session manager saves it.
---
---@param bufnr Bufnr The No Name buffer
---@return NoNameBufferContent text
local function open_text(bufnr)
	local winid = vim.fn.bufwinid(bufnr)
	winid = winid ~= -1 and winid or (vim.fn.win_findbuf(bufnr)[1] or -1) -- or one in another tab
	return {
		lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
		filetype = vim.bo[bufnr].filetype,
		cursor = winid ~= -1 and vim.api.nvim_win_get_cursor(winid) or { 1, 0 },
		reopen = true
	}
end

---Get the [No Name] texts a session's lists and windows hold: its closed texts, and every open, non-empty
---[No Name] buffer's text it owns.
---
---With `owner`, only the texts that pool owns are collected: its closed texts, and the open
---ones its tabs visited (their windows show them or have them in their history). The editor's
---pool also owns the open ones no tab session's tab visited.
---
---@param owner Pool|nil The pool whose texts are collected (nil = every text)
---@return table<Filehash, NoNameBufferContent> texts Each text, by its buffer's hash
local function owned_texts(owner)
	local texts = {}
	for id, handle in pairs(history.handles.live()) do
		local identifier = handle.hash
		if handle.text and is_known(identifier) and (owner == nil or vim.tbl_contains(owner.closed, id)) then
			texts[identifier] = handle.text
		end
	end
	for filehash, bufnr in pairs(history.data.hash_buffer_registry.buffers) do
		local filepath = history.get_filepath_from_hash(filehash)
		if filepath and filepath:match("^NONAME_") and vim.api.nvim_buf_is_loaded(bufnr)
			and owned(owner, history.get_handle_from_hash(filehash)) then
			local text = open_text(bufnr)
			-- empty ones are skipped, as when closed
			if not (#text.lines == 0 or (#text.lines == 1 and text.lines[1] == "")) then
				texts[filehash] = text
			end
		end
	end
	return texts
end

---Get the [No Name] texts a session's marks and its snapshots hold, open or closed, an empty one included.
---
---@param owner Pool|nil The pool whose marks and snapshots count (nil = every one's)
---@return table<Filehash, NoNameBufferContent> texts Each text, by its buffer's hash
local function marked_texts(owner)
	local texts = {}
	local marked = require('frogman.held').files_held(owner)
	for _, handle in pairs(history.handles.live()) do
		if marked[handle.hash] and handle.text and is_known(handle.hash) then
			texts[handle.hash] = handle.text
		end
	end
	for filehash, bufnr in pairs(history.data.hash_buffer_registry.buffers) do
		local filepath = history.get_filepath_from_hash(filehash)
		if marked[filehash] and filepath and filepath:match("^NONAME_") and vim.api.nvim_buf_is_loaded(bufnr) then
			texts[filehash] = open_text(bufnr)
		end
	end
	return texts
end

---Serialize [No Name] buffer content for session saving.
---
---The texts a session's lists and windows hold, and those its marks and its snapshots hold, an empty
---one among them. The open ones are marked to be reopened at load, since no session manager saves their
---text.
---
---@param owner Pool|nil The pool whose texts are collected (nil = every text)
---@return table<Filehash, NoNameBufferContent> texts Each text, by its buffer's hash
local function serialise_noname_content(owner)
	local texts = owned_texts(owner)
	for filehash, text in pairs(marked_texts(owner)) do
		texts[filehash] = text
	end
	return texts
end

---Write each [No Name] text into a file of its own in the session's scratch directory.
---
---Each file is encrypted, and the main file keeps its name. A file is named after its text, so
---only a text that changed is written. A closed text never read since the load keeps its file,
---unless it was saved under another session or key, when it's read, written again here and kept
---read. One whose file has gone, swept by another editor's save, is dropped, in memory too.
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
		local handle = history.handles.of_hash(filehash) -- the text in memory, when a handle has it
		if text.lines == nil then
			if text.source ~= scratch_dir .. name or text.key ~= key then
				text = text.read() -- saved under another session or key: read, and written again here
				if text then
					if handle then
						handle.text = text -- kept read, so it no longer needs that file
					end
				elseif handle then
					-- lost, as a reopen that can't read it finds it: no later write reads it again
					handle.text = nil
					history.routines.discard_from_pools(handle.id)
				end
			elseif vim.uv.fs_stat(scratch_dir .. name) == nil then
				-- its file is gone, swept by another editor's save: nothing is left to keep, here or in memory
				text = nil
				if handle then
					handle.text = nil
					history.routines.discard_from_pools(handle.id)
				end
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
			local id = vim.b[bufnr].frogman_noname
			if
				(vim.b[bufnr].frogman_reopened == filehash or
				(id ~= nil and history.routines.get_filehash("NONAME_" .. id) == filehash))
				and history.routines.is_trackable(bufnr) -- one turned nofile since isn't that buffer any more
			then
				return bufnr
			end
		end
	end
	return nil
end

---Get what a tab's windows show, sorted, floats left out.
---
---@param tabpage integer
---@return string[] shows What each window shows, its hash, or "" for an untracked buffer with no name
local function tab_shows(tabpage)
	local shows = {}
	for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		if vim.api.nvim_win_get_config(winid).relative == "" then
			table.insert(shows, shown_by(winid) or "")
		end
	end
	table.sort(shows)
	return shows
end

---Serialize the plain tabs' marks for a whole-editor save.
---
---Each plain tab with marks keeps what its windows show and its number, so a load can find it again;
---tabs whose windows show the same have as many windows, so the count tells nothing more. A tab
---session's tab has none: its tab mode is its session's.
---
---@return table[]|nil tabs Each tab's `{ shows, position, groups }`, or nil with none
---@return integer[] tab_pages The tab each entry came from, in their order
local function serialise_tabs()
	local tabs, pages = {}, {}
	for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
		local groups = marks().serialise("tab", tabpage)
		if groups and history.data.tab_pools[tabpage] == nil then
			table.insert(tabs, { shows = tab_shows(tabpage), position = vim.api.nvim_tabpage_get_number(tabpage), groups = groups })
			table.insert(pages, tabpage)
		end
	end
	return #tabs > 0 and tabs or nil, pages
end

---Give each plain tab the marks of the saved tab it is.
---
---A saved tab finds its tab by what its windows show, and among several that show the same, by its
---number, among the tabs in no tab session that no saved tab took yet. One no tab takes is held
---over in the whole editor's scope, naming the load.
---
---@param saved_tabs table[]|nil The file's `tabs`
---@param what string The load, as a held-over group names it
---@param earlier table<MarksGroup, true> The groups held over in the whole editor's scope before the load
---@return table<integer, true> unclaimed The saved tabs no tab took, by index, for the records to take off
---@return table<integer, integer> claimed The tab each saved tab went to, by index
local function restore_tabs(saved_tabs, what, earlier)
	local taken, unclaimed, claimed = {}, {}, {}
	for i, saved in ipairs(type(saved_tabs) == "table" and saved_tabs or {}) do
		local want = table.concat(type(saved.shows) == "table" and saved.shows or {}, ",")
		local best
		for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
			if not taken[tabpage] and history.data.tab_pools[tabpage] == nil then
				local shows = tab_shows(tabpage)
				if table.concat(shows, ",") == want then
					local score = vim.api.nvim_tabpage_get_number(tabpage) == saved.position and 1 or 0
					if best == nil or score > best.score then
						best = { tabpage = tabpage, score = score }
					end
				end
			end
		end
		if best then
			taken[best.tabpage] = true
			claimed[i] = best.tabpage
			marks().restore("tab", best.tabpage, saved.groups, what) -- named by the load, for a pop-up with edits not written
		else
			marks().hold_over("", type(saved.groups) == "table" and saved.groups or {}, what, true, true, earlier)
			unclaimed[i] = true -- every group is held over, so the tab leaves the file
		end
	end
	return unclaimed, claimed
end

---Get the hashes a session file's marks and snapshots name, in the parts of it asked for: its own,
---its windows', its tabs' and its detached lists'.
---
---@param storage table The file's data
---@param parts {session: boolean|nil, windows: boolean|nil, tabs: boolean|nil, detached: boolean|nil}
---@return table<Filehash, true> named
local function named_in(storage, parts)
	local named = {}
	if parts.session then
		marks().named_by(storage.marks, named)
		snapshots().named_by(storage.snapshots, named)
	end
	if parts.windows then
		for _, entry in ipairs(storage.windows or {}) do
			marks().named_by(entry[10], named)
			snapshots().named_by(entry[11], named)
		end
	end
	if parts.tabs then
		for _, tab in ipairs(storage.tabs or {}) do
			marks().named_by(tab.groups, named)
		end
	end
	if parts.detached then
		for _, list in ipairs(storage.detached or {}) do
			marks().named_by(list.marks, named)
			snapshots().named_by(list.snapshots, named)
		end
	end
	return named
end

---Carry into a write the No Name texts the file's marks and its windows' snapshots name.
---
---A records write leaves the windows and the tabs as the last save wrote them, but for what closes put
---onto their entries, and a list in the file alone keeps its marks, so the texts those name stay: from
---memory when it holds them, an open one's lines as they stand, its window gone, and otherwise carried
---from the file, unread. A save writes the windows and tabs anew, so it carries only the lists' in the
---file alone.
---
---@param texts table<Filehash, table> The texts the write takes, added to in place
---@param saved table The file's data
---@param key string The session's key
---@param scratch_dir string The session's scratch directory
---@param references boolean Whether the file's windows and tabs are kept, as a records write keeps them
---@return nil
local function carry_marked_texts(texts, saved, key, scratch_dir, references)
	local named = named_in(saved, { windows = references, tabs = references, detached = true })
	for filehash, _ in pairs(named) do
		local entry = type(saved.noname_content) == "table" and saved.noname_content[filehash]
		if texts[filehash] == nil then
			local handle = history.handles.of_hash(filehash)
			local bufnr = history.data.hash_buffer_registry.buffers[filehash]
			local filepath = history.get_filepath_from_hash(filehash)
			if bufnr and filepath and filepath:match("^NONAME_") and vim.api.nvim_buf_is_loaded(bufnr) then
				texts[filehash] = open_text(bufnr)
			elseif handle and handle.text and is_known(filehash) then
				texts[filehash] = handle.text
			elseif type(entry) == "table" and type(entry.scratch) == "string" then
				local source = scratch_dir .. entry.scratch
				texts[filehash] = { scratch = entry.scratch, source = source, key = key,
					read = scratch_reader(source, key, filehash), reopen = entry.reopen }
			end
		end
	end
end

---Hold a tab's tab marks over in a session's scope, as the tab becomes that session's tab.
---
---A tab session's tab has no tab marks of its own: its tab mode is its session's. Held over at a load,
---they name the load; at a save as the session, which isn't a load, what the tab showed.
---
---@param tabpage integer The tab becoming the session's
---@param session_id string The session's pool id
---@param what string|nil The load, like "proj, loaded into tab 2" (nil at a save)
---@return nil
local function tab_marks_held_over(tabpage, session_id, what)
	local scope = marks().scope("tab", tabpage)
	if scope then
		marks().hold_over(session_id, scope.groups, what or ("tab on " .. marks().shows(vim.api.nvim_tabpage_get_win(tabpage))))
		marks().drop_scope("tab", tabpage)
	end
end

---Get the window entries a detached list waits on, its tab taking them back when it comes back: those
---its `windows` name, by index.
---
---@param saved_data table A whole editor's file, as read
---@return table<integer, true> waited
local function waited_on(saved_data)
	local waited = {}
	for _, list in ipairs(type(saved_data.detached) == "table" and saved_data.detached or {}) do
		for _, i in ipairs(type(list.windows) == "table" and list.windows or {}) do
			waited[i] = true
		end
	end
	return waited
end

---Give the windows and a session's scope a session file's snapshots.
---
---Each matched window takes its entry's, the ones it had held over under the load's header, and the
---snapshots of an entry no window took are held over under it too. The held-over ones come from `snapshots`, each under its own header, unless
---the session is open already, when memory's win: the file's whose id memory holds are skipped, and
---the rest come in under the load's header. An entry's snapshot the file's `snapshots` holds too was
---held over after the save that wrote the entry, by the records written since, so the held-over one,
---the newer, is the one that comes back.
---
---@param saved_data table The file's data
---@param taken table<integer, WinId> The window each saved entry went to, by the entry's index
---@param session_id string The session's pool id ("" for the whole editor's)
---@param own boolean Whether the session's own held-over snapshots come from the file
---@param what string The load, as a held-over header names it
---@return table<integer, true> gone The entries no window took that carried snapshots, by index
local function restore_snapshots(saved_data, taken, session_id, own, what)
	local unclaimed, held_over, gone = {}, {}, {}
	for _, saved in ipairs(type(saved_data.snapshots) == "table" and saved_data.snapshots or {}) do
		if type(saved) == "table" and saved.id ~= nil then
			held_over[saved.id] = true
		end
	end
	if own then
		snapshots().restore_held(session_id, saved_data.snapshots)
	else
		unclaimed = snapshots().not_held(saved_data.snapshots)
	end
	for i, entry in ipairs(saved_data.windows or {}) do
		local winid = (taken or {})[i]
		if type(entry) == "table" and type(entry[11]) == "table" then
			local back = winid and vim.api.nvim_win_is_valid(winid)
			local list = vim.tbl_filter(function(saved)
				if type(saved) ~= "table" then
					return false
				end
				-- a window taking its entry takes a snapshot held over meanwhile back when the copy is unchanged,
				-- a close's or a load's; a changed copy stays held over, and so does one only the file holds so
				if back and snapshots().held_copy(session_id, saved.id) then
					return snapshots().drop_copy(session_id, saved)
				end
				return not held_over[saved.id]
			end, entry[11])
			if winid and vim.api.nvim_win_is_valid(winid) then
				snapshots().restore_window(winid, list, session_id, what)
			else
				-- a window the load didn't bring back, but for a snapshot an earlier load of the file held over
				vim.list_extend(unclaimed, snapshots().not_held(list))
				gone[i] = true
			end
		end
	end
	snapshots().hold_saved(session_id, unclaimed, what)
	return gone
end

---Give the scopes a session file's marks.
---
---The session's own come from its `marks`, unless it's open already, when memory's stay, each
---matched window's from the entry it took, the groups it had held over but for those the entry
---brings back, and each plain tab's from the saved tab it is. An entry that brings no marks, only
---groups typed in with none, leaves a window that has marks of its own with them, the entry's groups
---below them but for a name it has. What no
---window or tab takes is held over, and so, when memory's marks win, are the file's it doesn't hold. A No Name text a mark names that no list holds and that
---isn't reopened is held unread, as a closed one is, on no list.
---
---@param saved_data table The file's data
---@param taken table<integer, WinId> The window each saved entry went to, by the entry's index
---@param session_id string The session's pool id ("" for the whole editor's)
---@param own boolean Whether the session's own marks come from the file
---@param key string The session's key
---@param scratch_dir string The session's scratch directory
---@param what string The load, as a held-over group names it
---@return table<integer, true> gone The window entries no window took that carried marks, by index
---@return table<integer, true> gone_tabs The tab entries no tab took, by index
---@return table<integer, integer> claimed The tab each tab entry went to, by index
local function restore_marks(saved_data, taken, session_id, own, key, scratch_dir, what)
	local gone, earlier = {}, nil -- earlier: the groups held over before this load, which a window taking its entry clears
	if own then
		marks().restore("session", session_id, saved_data.marks, what) -- named by the load, for a pop-up with edits not written
		earlier = marks().held_now(session_id)
	else
		earlier = marks().held_now(session_id)
		-- memory's marks win: every file mark memory doesn't hold, alias by alias, is held over
		local scope = marks().scope("session", session_id)
		for _, saved in ipairs(type(saved_data.marks) == "table" and saved_data.marks or {}) do
			local left = {}
			for alias, filehash in pairs(type(saved.marks) == "table" and saved.marks or {}) do
				local held = false
				for _, group in ipairs(scope and scope.groups or {}) do
					local handle = group.marks[alias] and marks().handle_of(group, alias)
					held = held or (handle ~= nil and handle.hash == filehash)
				end
				if not held then
					left[alias] = filehash
				end
			end
			if next(left) then
				marks().hold_over(session_id, { { name = saved.name, marks = left } }, what, true, true, earlier)
			elseif next(type(saved.marks) == "table" and saved.marks or {}) == nil then
				-- a group with no marks memory has none of its name for is held over too, as its marks would be
				local named = false
				for _, group in ipairs(scope and scope.groups or {}) do
					named = named or group.name == saved.name
				end
				if not named then
					marks().hold_over(session_id, { { name = saved.name, marks = {}, default = saved.default, from = saved.from } }, what,
						true, true, earlier)
				end
			end
		end
	end
	-- the windows that take their entries first, so the copies they take back are gone before what no
	-- window takes is held over against what's held already
	for i, entry in ipairs(saved_data.windows or {}) do
		local winid = (taken or {})[i]
		if type(entry) == "table" and type(entry[10]) == "table" then
			if winid and vim.api.nvim_win_is_valid(winid) then
				local had = marks().scope("window", winid)
				-- an entry that brings no marks, only groups typed in with none, leaves a window that has
				-- marks of its own with them, and gives it the groups below them
				if marks().any_mark(entry[10]) or not marks().any_mark(had and had.groups) then
					-- what the window had is held over under the load's header, but for what the entry brings back
					if had and not marks().unchanged_copy(winid) then -- a copy no one changed loses nothing
						local keep = {}
						for _, group in ipairs(had.groups) do
							local by_hash = marks().hashes_of(group)
							local brought = false
							for _, saved in ipairs(entry[10]) do
								-- a group with no marks is the entry's one of its name, having nothing else to be known by
								brought = brought or (type(saved) == "table"
									and vim.deep_equal(type(saved.marks) == "table" and saved.marks or {}, by_hash)
									and (next(by_hash) ~= nil or saved.name == group.name))
							end
							if not brought then
								table.insert(keep, group)
							end
						end
						marks().hold_over(session_id, keep, what, nil, true, earlier)
					end
					marks().restore("window", winid, entry[10], what)
					-- what a close or an earlier load held over of the entry's groups goes, the window holding them
					marks().drop_copies(session_id, entry[10], earlier)
				else
					marks().add_below("window", winid, entry[10], what)
				end
			end
		end
	end
	for i, entry in ipairs(saved_data.windows or {}) do
		local winid = (taken or {})[i]
		if type(entry) == "table" and type(entry[10]) == "table" and not (winid and vim.api.nvim_win_is_valid(winid)) then
			marks().hold_over(session_id, entry[10], what, true, true, earlier) -- a window the load didn't bring back
			gone[i] = next(entry[10]) ~= nil or nil -- every group is held over, so they leave the file
		end
	end
	local gone_tabs, claimed = restore_tabs(saved_data.tabs, what, earlier) -- a tab session's file has none
	local held = require('frogman.held').files_held(nil) -- the snapshots' texts too, which `restore_snapshots` gave before
	for filehash, _ in pairs(held) do
		local entry = type(saved_data.noname_content) == "table" and saved_data.noname_content[filehash]
		local filepath = history.get_filepath_from_hash(filehash)
		local handle = history.handles.of_hash(filehash)
		if type(entry) == "table" and not entry.reopen and type(entry.scratch) == "string" and filepath
			and filepath:match("^NONAME_") and handle and handle.text == nil then
			local source = scratch_dir .. entry.scratch
			handle.text = { scratch = entry.scratch, source = source, key = key,
				read = scratch_reader(source, key, filehash) }
		end
	end
	return gone, gone_tabs, claimed
end

---Get an entry as the session file holds it, written and read back, its holes and nulls as a read finds
---them, so the records write knows it again by comparing what it reads.
---
---@param entry table An entry as a save builds it
---@return table entry
local function as_filed(entry)
	return vim.json.decode(vim.json.encode(entry))
end

-- counts the holder places the closes' files wait in until their entries take them
local closes_held = 0

---Let go of what a session file's known entries hold, as a save or a load sets them anew.
---
---@param file_path string The session's main file
---@return nil
local function forget_entries(file_path)
	local known = data.entries[file_path]
	for _, kind in ipairs({ "windows", "tabs" }) do
		for _, slot in pairs(known and known[kind] or {}) do
			if slot.close and slot.close.state ~= "held" then
				history.handles.drop_place(slot.close.place)
			end
		end
	end
	data.entries[file_path] = nil
end

---Hold over what a close put onto an entry that won't take it, in the scope of the session it closed in,
---under what it showed: its groups and snapshots as they stood. Its files go from their wait, the held-over
---groups and snapshots holding them now.
---
---@param close EntryClose What the close put onto the entry, with what it showed and the session it closed in
---@return nil
local function hold_closed(close)
	if close.groups then
		marks().hold_over(close.session, close.groups, close.what, true)
	end
	if close.snapshots then
		snapshots().hold_saved(close.session, close.snapshots, close.what)
	end
	history.handles.drop_place(close.place)
	close.state = "held"
end

---Remember which window or tab each entry a load read is: the window or tab that took it, or, for one none
---took that carried marks or snapshots, to take those off the file at the next records write, held over
---since, so one you clear, or move up, isn't held over again at the next load; but for an entry a detached
---list names among its windows, which its tab takes back when it comes back.
---
---Each is kept as the load read it, so a write touches it only while it's still that entry: another
---editor's save may have rewritten the windows meanwhile.
---
---@param file_path string The session's main file
---@param saved_data table The file's data, as the load read it
---@param taken table<integer, WinId> The window each entry went to, by its index
---@param claimed table<integer, integer> The tab each tab entry went to, by its index
---@param snapped table<integer, true> The window entries no window took that carried snapshots
---@param marked table<integer, true> The window entries no window took that carried marks
---@param tabs table<integer, true> The tab entries no tab took
---@return nil
local function remember_loaded(file_path, saved_data, taken, claimed, snapped, marked, tabs)
	forget_entries(file_path)
	local known = { windows = {}, tabs = {} }
	local listed = waited_on(saved_data)
	for i, entry in ipairs(type(saved_data.windows) == "table" and saved_data.windows or {}) do
		local winid = (taken or {})[i]
		if winid and vim.api.nvim_win_is_valid(winid) then
			known.windows[i] = { win = winid, entry = vim.deepcopy(entry) }
		elseif (snapped[i] or marked[i]) and not listed[i] then
			known.windows[i] = { entry = vim.deepcopy(entry), take_off = true }
		end
	end
	for i, tab in ipairs(type(saved_data.tabs) == "table" and saved_data.tabs or {}) do
		if claimed[i] then
			known.tabs[i] = { tab = claimed[i], entry = vim.deepcopy(tab) }
		elseif tabs[i] then
			known.tabs[i] = { entry = vim.deepcopy(tab), take_off = true }
		end
	end
	data.entries[file_path] = known
end

---Hold over what closes put onto the entries of a file a save doesn't write again, the windows and tabs
---written anew without them: once, whether the close's write landed or not.
---
---@param file_path string The session's main file
---@param entry_wins WinId[] The window each entry the save writes came from
---@param tab_pages integer[] The tab each tab entry the save writes came from
---@return nil
local function hold_dropped(file_path, entry_wins, tab_pages)
	local known = data.entries[file_path]
	local writing = { windows = {}, tabs = {} }
	for _, winid in ipairs(entry_wins) do
		writing.windows[winid] = true
	end
	for _, tabpage in ipairs(tab_pages) do
		writing.tabs[tabpage] = true
	end
	for _, kind in ipairs({ "windows", "tabs" }) do
		for _, slot in pairs(known and known[kind] or {}) do
			local id = slot.win or slot.tab
			if slot.close and slot.close.state ~= "held" and not (id and writing[kind][id]) then
				hold_closed(slot.close)
			end
		end
	end
end

---Remember which window or tab each entry a save wrote is, as the file holds it.
---
---@param file_path string The session's main file
---@param windows table[] The window entries written
---@param entry_wins WinId[] The window each came from
---@param tabs table[]|nil The tab entries written
---@param tab_pages integer[] The tab each came from
---@return nil
local function remember_saved(file_path, windows, entry_wins, tabs, tab_pages)
	forget_entries(file_path)
	local known = { windows = {}, tabs = {} }
	for i, winid in ipairs(entry_wins) do
		known.windows[i] = { win = winid, entry = as_filed(windows[i]) }
	end
	for i, tabpage in ipairs(tab_pages) do
		known.tabs[i] = { tab = tabpage, entry = as_filed(tabs[i]) }
	end
	data.entries[file_path] = known
end

---Reopen the No Name buffers that were open at the save.
---
---They come back in the background, listed, hidden and modified, under a fresh id, each keeping its
---handle, so every slot, note and history entry holding it holds it still. One that is already back
---is taken as it is, and its handle, when it has one, gives way to the text's (`handles.renamed`). The
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
		-- one memory holds closed stays closed: a session open in another tab may have closed it since
		-- its file was written
		if entry.reopen and filepath and not history.routines.is_handle_closed(history.get_handle_from_hash(filehash)) then
			local bufnr = noname_already_back(filehash)
			local content = bufnr == nil and scratch_reader(scratch_dir .. entry.scratch, key, filehash)()
			if bufnr == nil and not content then
				goto continue -- its file failed its check: that text is lost, not the session
			end
			if bufnr == nil then
				bufnr = history.routines.buffer_from_text(content)
				vim.b[bufnr].frogman_reopened = filehash
			end
			-- the text keeps its handle under the hash it's back under, and its reopen links the two in the
			-- trail, the one thing of a load's the trail gets from the handle
			local new_filehash = history.routines.get_filehash(history.routines.noname_name(bufnr))
			history.handles.renamed(filehash, new_filehash, { kind = "load" })
			history.register_buffer(bufnr, { load = true, from = new_filehash ~= filehash and filehash or nil })
			if new_filehash ~= filehash then
				history.routines.unregister_filepath(filepath)
			end
		end
		::continue::
	end
end

---Loads closed buffer history data.
---
---Restores the stack of closed buffer handles that can be reopened, from the file's hashes,
---into the pool being loaded. A closed buffer the session manager brought back isn't closed any
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
	-- the list as it stands once the load is done, written through its class in one change
	local closed, closed_times, placed = {}, {}, {}
	if merge then
		-- what's in memory is newer than the file
		closed, closed_times = vim.list_slice(load_pool.closed, 1, #load_pool.closed), vim.deepcopy(load_pool.times)
	end
	for _, id in ipairs(closed) do
		placed[id] = true
	end
	local at = 1

	for _, filehash in ipairs(closed_buffers or {}) do
		local filepath = history.get_filepath_from_hash(filehash) -- return: either closed filepath or NONAME_<x>
		if not filepath then
			require('frogman.domains.ledger').never("What the fuck. This is impossible.")
		end
		if history.get_buffer_from_hash(filehash) then
			goto continue -- the session manager brought it back
		end
		local handle = history.handles.of_hash(filehash) -- the list holds its file's handle
		if placed[handle.id] then
			goto continue -- in memory already, or a hash the file holds twice: placed once
		end
		placed[handle.id] = true
		if filepath:match("^NONAME_") then
			if handle.text == nil or (load_pool.id ~= "" and not merge) then
				local content = noname_content[filehash]
				if content == nil then
					require('frogman.domains.ledger').never("This is impossible. Noname content must be created for this closed No Name buffer.")
				end
				local source = scratch_dir .. content.scratch
				handle.text = {
					scratch = content.scratch,
					source = source,
					key = key,
					read = scratch_reader(source, key, filehash),
				}
			elseif not merge then -- merged into an open pool, its text is cached already
				require('frogman.domains.ledger').never("This is impossible. The closed buffer must not already have its text on its handle.")
			end
		end
		if merge then
			table.insert(closed, at, handle.id)
			at = at + 1
		else
			table.insert(closed, handle.id)
		end
		closed_times[handle.id] = closed_times[handle.id] or (times and times[filehash]) or nil
		::continue::
	end
	load_pool:replace(closed, closed_times, true) -- the load's own: not news to its file
	-- print_table(history.routines.pools()[""].closed)
end

---Get a session's file path from its directory and name.
---
---The file is named after a hash of the two, in the configured session directory. Nothing is made:
---the directory comes with the first write into it.
---
---@param directory string The session's directory
---@param name string|nil The session's name (nil for a nameless save)
---@return string project_filepath Path of the session's main file
local function get_session_filepath(directory, name)
	if not directory then
		require('frogman.domains.ledger').never("No directory provided to get_session_filepath")
	end

	-- the separator keeps a session "a" in /proj apart from a nameless save in /proja
	local session_hash = vim.fn.sha256(name and (directory .. "\n" .. name) or directory)

	local session_dir = configs.session_dir
	local project_filepath = session_dir .. session_hash

	return project_filepath
end

-- each key once it's made, by directory and salt, { key, file }: another editor's save can give a file
-- a new salt, and a key kept by the file's path would then seal it with the wrong one. Each file's last
-- key is noted, so a session's key can go once the session isn't open; a key taken for no file, a
-- dump's, stays.
local keys, key_of = {}, {}

-- the files in the sessions' `<main>.d/` this editor knows, by path: those the main files it wrote or
-- read name. A sweep takes one of these at once, and another editor's, written a moment before its own
-- main file lands, only once it's a minute old.
local own_files = {}

-- the No Name texts each main file held at its last write, by the file's path (path → hash → true),
-- so an edit also reaches a file that holds a text no longer its own, which is then written without it
local noname_held = {}

---Get a sealed file's key, made once for its directory and salt.
---
---With a session's file named, the key is noted as that file's last one, so it can go once the
---session isn't open. With none, as a dump takes one, it stays for the editor's life.
---
---@param directory string The directory, the secret the key is stretched from
---@param salt string The salt from the file's header
---@param file_path string|nil The session's file, whose key this is now
---@return string key The key
local function key_for(directory, salt, file_path)
	local id = directory .. "\0" .. salt
	keys[id] = keys[id] or { key = crypto.derive_key(directory, salt) }
	if file_path then
		keys[id].file = true
		key_of[file_path] = id
	end
	return keys[id].key
end
M.key_for = key_for

---Write text sealed into a file, atomically.
---
---The file is the header, the salt, then the text sealed under the key. The seal covers the header,
---the salt and the purpose word besides, so a file sealed for one purpose doesn't open as another's.
---
---@param path string The file
---@param key string The key the text is sealed under
---@param salt string The salt the key was stretched with
---@param text string The text
---@param purpose string|nil The word the seal covers besides (nil for a session's file)
---@return nil
function M.seal_file(path, key, salt, text, purpose)
	write_atomic(path, M.sealed(key, salt, text, purpose))
end

---Get the salt sealed bytes carry, the key's other half besides the directory.
---
---@param bytes string
---@return string|nil salt Nil when the bytes aren't sealed this way
function M.salt_of(bytes)
	if type(bytes) ~= "string" or bytes:sub(1, #HEADER) ~= HEADER or #bytes <= #HEADER + crypto.salt_length then
		return nil
	end
	return bytes:sub(#HEADER + 1, #HEADER + crypto.salt_length)
end

---Get text sealed as a sealed file holds it: the header, the salt, then the text sealed under the key,
---the seal covering the header, the salt and the purpose word besides. `open_sealed` opens it.
---
---@param key string The key the text is sealed under
---@param salt string The salt the key was stretched with
---@param text string The text
---@param purpose string|nil The word the seal covers besides (nil for a session's file)
---@return string bytes
function M.sealed(key, salt, text, purpose)
	return HEADER .. salt .. crypto.seal(key, text, HEADER .. salt .. (purpose and "\n" .. purpose or ""))
end

---Open a sealed file's bytes.
---
---The key comes from the directory and the file's salt, kept once it's made. Gives no text when the
---bytes aren't sealed this way, or don't open: an edit, a cut, another directory's file or another
---purpose's.
---
---@param bytes string The file's bytes
---@param directory string The directory the key is stretched from
---@param purpose string|nil The word the seal covers besides (nil for a session's file)
---@param file_path string|nil The session's file, whose key this is then
---@return string|nil text The text, or nil when it doesn't open
---@return string|nil key The key, when the bytes are sealed this way
---@return string|nil problem "not sealed" or "integrity", when it doesn't open
function M.open_sealed(bytes, directory, purpose, file_path)
	if bytes:sub(1, #HEADER) ~= HEADER or #bytes <= #HEADER + crypto.salt_length then
		return nil, nil, "not sealed"
	end
	local salt = bytes:sub(#HEADER + 1, #HEADER + crypto.salt_length)
	local key = key_for(directory, salt, file_path)
	local text = crypto.open(key, bytes:sub(#HEADER + crypto.salt_length + 1), HEADER .. salt .. (purpose and "\n" .. purpose or ""))
	if text == nil then
		return nil, key, "integrity"
	end
	return text, key, nil
end

---Forgets the keys of sessions no longer open (defined further down, with the records)
---@type fun()
local forget_closed_keys

---Make a session's data keep the session file's policy.
---
---These are the rules every session file keeps, whichever writer made it: every closed entry, on
---`closed` or on a detached list, has its path in `paths`; a closed No Name entry has its text; a mark
---has its file's path, and a No Name one its text; and a hash the data holds as a record, closed, on a
---detached list, as a text or under a mark, isn't an outsider, the record winning, since the registry is the authority on what a hash means. Whatever breaks a rule
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
	-- a mark keeps its file: one no path names, or a No Name one with no text, is left out
	local marked = {}
	local function clean(groups)
		for _, group in ipairs(type(groups) == "table" and groups or {}) do
			for alias, filehash in pairs(type(group) == "table" and type(group.marks) == "table" and group.marks or {}) do
				local filepath = paths[filehash]
				if filepath == nil then
					broke("a mark no path names was left out")
					group.marks[alias] = nil
				elseif filepath:match("^NONAME_") and (storage.noname_content or {})[filehash] == nil then
					broke("a No Name mark with no text was left out")
					group.marks[alias] = nil
				else
					marked[filehash] = true
				end
			end
		end
	end
	clean(storage.marks)
	for _, entry in ipairs(storage.windows or {}) do
		if type(entry) == "table" then
			clean(entry[10])
		end
	end
	for _, tab in ipairs(storage.tabs or {}) do
		clean(tab.groups)
	end
	for _, list in ipairs(storage.detached or {}) do
		clean(list.marks)
	end
	-- a snapshot keeps its files as a mark does: one whose current file no path names, or that's a No
	-- Name text with no text, is left out, and so is any other file of it like that; its notes are weak
	local function usable(filehash)
		local filepath = type(filehash) == "string" and paths[filehash]
		return filepath and not (filepath:match("^NONAME_") and (storage.noname_content or {})[filehash] == nil) or false
	end
	local function clean_snapshots(list)
		if type(list) ~= "table" then
			return nil
		end
		local kept = {}
		for _, saved in ipairs(list) do
			if type(saved) == "table" and usable(saved.current) then
				for _, slot in ipairs({ "secondary", "ternary" }) do
					if saved[slot] ~= nil and not usable(saved[slot]) then
						broke("a snapshot's file no path names, or a No Name one with no text, was left out")
						saved[slot] = nil
					end
				end
				for _, key in ipairs({ "queue", "order" }) do
					local files = vim.tbl_filter(usable, type(saved[key]) == "table" and saved[key] or {})
					if #files < #(type(saved[key]) == "table" and saved[key] or {}) then
						broke("a snapshot's file no path names, or a No Name one with no text, was left out")
					end
					saved[key] = files
				end
				for _, key in ipairs({ "dtm", "dsm" }) do
					local map = {}
					for k, v in pairs(type(saved[key]) == "table" and saved[key] or {}) do
						if usable((tostring(k):gsub("%-swap$", ""))) and usable(v) then
							map[k] = v
						end
					end
					saved[key] = map
				end
				for filehash, _ in pairs(snapshots().named_by({ saved })) do
					marked[filehash] = true
				end
				table.insert(kept, saved)
			else
				broke("a snapshot whose current file no path names, or a No Name one with no text, was left out")
			end
		end
		return #kept > 0 and kept or nil
	end
	storage.snapshots = clean_snapshots(storage.snapshots)
	for _, entry in ipairs(storage.windows or {}) do
		if type(entry) == "table" then
			entry[11] = clean_snapshots(entry[11])
		end
	end
	for _, list in ipairs(storage.detached or {}) do
		list.closed = vim.tbl_filter(keeps, list.closed or {})
		list.snapshots = clean_snapshots(list.snapshots)
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
		for filehash, _ in pairs(marked) do
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
	local plaintext, key = M.open_sealed(bytes, directory, nil, file_path)
	local ok, saved_data = pcall(vim.json.decode, plaintext or "")
	if not plaintext or not ok or type(saved_data) ~= "table" then
		return nil, nil, "integrity"
	end
	local scratch_dir = file_path .. ".d/"
	for _, entry in pairs(type(saved_data.noname_content) == "table" and saved_data.noname_content or {}) do
		if type(entry) == "table" and type(entry.scratch) == "string" then
			own_files[scratch_dir .. entry.scratch] = true
		end
	end
	for _, page in pairs(type(saved_data.trail) == "table" and saved_data.trail or {}) do
		own_files[scratch_dir .. tostring(page)] = true
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

---Keep the teardown's closes off the list of the tab session in a tab a load is about to take, that session
---loaded again or another: the closes still to settle that were made in that tab. The session manager's
---teardown closed those files, not you, so the session's closed list stays as its file has it, as at a
---whole-editor switch, the trail still naming it on each close. A plain tab's and a detached list's
---teardown closes go onto their lists.
---
---@param tabpage integer The tab the load goes into
---@return nil
function M.keep_teardown_off(tabpage)
	local pool = history.routines.pool_of_tab(tabpage)
	if pool and pool.id ~= "" and not pool.detached then
		history.routines.keep_closes_off(tabpage)
	end
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
	return pool_class.new({ id = "\0detached\n" .. label, name = label, detached = true, of = of })
end

---Move a tab into a detached pool, out of the pool it was in, its windows noted as seen in the list, so
---one that closes without its events is held over there.
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
	require('frogman.held').note_tab(tabpage)
end

---Get the names of the detached lists in memory.
---
---@return table<string, boolean> names Each detached list's name in memory → true
local function detached_tab_sessions()
	local names = {}
	for _, pool in pairs(history.data.pools) do
		if pool.detached then
			names[pool.name] = true
		end
	end
	return names
end

---Get the next free name for a detached list of a session.
---
---The names go `t_DETACHED`, then `t_DETACHED_2`, and so on, after the session's name (or its
---directory's), counting the names in memory and in the whole editor's file.
---
---@param pool Pool The session's pool
---@param in_file table[] The detached lists the whole editor's file holds (`file_detached_lists()`)
---@return string label The free name
local function detached_label(pool, in_file)
	local base = (pool.name or vim.fn.fnamemodify(pool.directory or "", ":t")) .. "_DETACHED"
	local taken = detached_tab_sessions()
	for _, list in ipairs(in_file) do
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
	local in_file -- the whole editor's file, read once however many tabs are pushed out
	for other, _ in pairs(vim.deepcopy(pool.tabs)) do
		if other ~= tabpage and vim.api.nvim_tabpage_is_valid(other) then
			in_file = in_file or file_detached_lists()
			local detached = new_detached_pool(detached_label(pool, in_file), pool.id)
			detached:replace(pool.closed, pool.times) -- the whole editor's records hold it from now on
			detached.visits = vim.deepcopy(pool.visits)
			join_detached(other, detached)
			marks().copy_scope("session", pool.id, detached.id) -- the session's marks, the two going their own ways after
			snapshots().copy_held(pool.id, detached.id) -- and its held-over snapshots, the same way
			require('frogman.domains.ledger').move("detached", { subject = detached.id, name = detached.name,
				words = "tab " .. vim.api.nvim_tabpage_get_number(other) .. " keeps " .. history.routines.list_name(pool) .. "'s list" })
		end
	end
end

---Check if a detached list in memory has nothing left in it: no tab, no closed file the file would keep, no
---group and no held-over snapshot. The whole editor's file leaves such a list out.
---
---@param pool Pool The detached list's pool
---@return boolean empty
local function nothing_left(pool)
	return next(pool.tabs) == nil and #serialise_closed_buffers({ pool }) == 0
		and marks().serialise("session", pool.id) == nil and snapshots().serialise_held(pool.id) == nil
end

---Build the detached lists as the whole editor's file holds them.
---
---Each detached pool in memory comes first, with its closed list and close times, but for one with no
---tab and nothing left in it, no closed file, no group and no held-over snapshot, which goes from the
---file. Its window entries come from `windows_of` at a save, and otherwise from the file, which a
---records write leaves as the session manager last saved them. Then each list the file holds and memory
---doesn't comes as it is, but with no windows at a save, since a save writes the windows anew.
---
---@param old table|nil The file's data
---@param windows_of (fun(pool: Pool): integer[])|nil A pool's window entries, at a save
---@return table[] lists The detached lists to write
---@return table<string, boolean> live The names of the lists in memory
local function detached_lists(old, windows_of)
	local lists, old_windows, pools = {}, {}, {}
	local live = detached_tab_sessions()
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
		-- one with no tab and nothing left goes from the file, which keeps no copy of it, the list being in memory
		if not nothing_left(pool) then
			local closed, times = serialise_closed_buffers({ pool })
			table.insert(lists, {
				label = pool.name, of = pool.of, closed = closed, closed_times = times,
				windows = windows_of and windows_of(pool) or old_windows[pool.name] or {},
				marks = marks().serialise("session", pool.id), -- its copy of its session's marks
				snapshots = snapshots().serialise_held(pool.id), -- and the snapshots held over in its scope
			})
		end
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
			for _, id in ipairs(pool.closed) do
				local handle = history.handles.get(id)
				local filehash = handle and handle.hash
				if filehash and texts[filehash] == nil and handle.text and is_known(filehash) then
					texts[filehash] = handle.text
				end
			end
		end
	end
	for _, list in ipairs(lists) do
		if not live[list.label] then
			for _, filehash in ipairs(list.closed or {}) do
				local entry = old and old.noname_content and old.noname_content[filehash]
				local handle = history.handles.of_hash(filehash)
				if texts[filehash] == nil and entry then
					local source = scratch_dir .. entry.scratch
					texts[filehash] = { scratch = entry.scratch, source = source, key = key, read = scratch_reader(source, key, filehash) }
				elseif texts[filehash] == nil and handle and handle.text then
					texts[filehash] = handle.text -- moved in from a list in memory
				end
				if paths[filehash] == nil then
					paths[filehash] = old and old.paths and old.paths[filehash] or history.get_filepath_from_hash(filehash)
				end
			end
			-- and the files its marks and snapshots name, which nothing in memory may hold any more, from the old file first
			for filehash, _ in pairs(snapshots().named_by(list.snapshots, marks().named_by(list.marks))) do
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
			require('frogman.domains.ui').routines.show_closed_lists({ focus = before })
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
	tab_marks_held_over(tabpage, load_pool.id, vim.fn.fnamemodify(name or directory, ":t") .. ", loaded into tab " .. vim.api.nvim_tabpage_get_number(tabpage))
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
		for id, time in pairs(history.keyed_by_handle(saved_data.buffers.global)) do
			load_pool.visits[id] = time - latest - 1
		end
	end
	load_closed_buffers(saved_data.closed or {}, saved_data.noname_content or {}, key, scratch_dir, saved_data.closed_times, open)
	local window_histories, matched, taken = load_window_buffer_relationships(saved_data.windows, tabpage)
	for winid, window_crux in pairs(window_histories) do
		history.data.crux_internals.window[winid] = window_crux
	end
	local what = vim.fn.fnamemodify(name or directory, ":t") .. ", loaded into tab " .. vim.api.nvim_tabpage_get_number(tabpage)
	local gone = restore_snapshots(saved_data, taken, load_pool.id, not open, what)
	local marked, gone_tabs, claimed = restore_marks(saved_data, taken, load_pool.id, not open, key, scratch_dir, what)
	remember_loaded(file_path, saved_data, taken, claimed, gone, marked, gone_tabs) -- before the texts reopen under new hashes
	tab_marks_held_over(tabpage, load_pool.id, what)
	for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		if window.data.crux[winid] then
			history.routines.ensure_window_entry(winid)
		end
	end
	reopen_noname_buffers(saved_data.noname_content or {}, key, scratch_dir)
	for filehash, tag in pairs(saved_data.missing or {}) do
		local handle = history.handles.of_hash(filehash)
		if handle and handle.tag == nil then -- a tag memory holds stays
			history.handles.set_tag(handle.id, tag, { load = true })
		end
	end
	for _, filehash in ipairs(saved_data.unwritten or {}) do
		local handle = history.handles.of_hash(filehash)
		if handle then
			handle.unwritten = true
		end
	end
	-- the tab's windows' histories and the pool's visits were replaced in place, so the next view is
	-- built afresh, even for the window the last one was built for.
	history.routines.construct_crux(nil)
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
	-- the migration script as it runs in this install: its path in the plugin's directory, on the runtimepath
	local migrate = "nvim --clean -l " ..
		(vim.api.nvim_get_runtime_file("scripts/migrate_sessions.lua", false)[1] or "scripts/migrate_sessions.lua")
	-- cavediver's sessions folder, from before the rename, while session_dir is left as it is: the migration
	-- script moves what it holds
	local cavediver_dir = configs.session_dir == vim.fn.stdpath("data") .. "/frogman/sessions/"
		and vim.fn.stdpath("data") .. "/cavediver/sessions/"
	local old_name = vim.fn.sha256(cwd .. "\n"):sub(1, 32) .. ".json"
	if problem == "newer" then
		vim.notify("frogman: this session's file was made by a newer frogman. It's left alone, and the session starts fresh.", vim.log.levels.WARN)
	elseif problem == "unencrypted" then
		vim.notify("frogman: this session's file is in the format from before encryption. Run the migration script to convert it, " .. migrate .. "; the session starts fresh.", vim.log.levels.WARN)
	elseif problem == "integrity" then
		vim.notify("frogman: this session's file failed its integrity check (edited or corrupted). The session starts fresh, and the next save replaces the file.", vim.log.levels.WARN)
	elseif problem == "missing" and cavediver_dir and vim.uv.fs_stat(cavediver_dir .. vim.fs.basename(file_path)) then
		-- cavediver's folder still has it: left there until the migration script moves it
		vim.notify("frogman: this session's file is still in cavediver's folder. Run the migration script to move it, " .. migrate .. "; the session starts fresh.", vim.log.levels.WARN)
	elseif problem == "missing" and (vim.uv.fs_stat(configs.session_dir .. old_name)
		or cavediver_dir and vim.uv.fs_stat(cavediver_dir .. old_name)) then
		-- a file named the way it was before sessions had names and were encrypted, in either folder: left as it is
		vim.notify("frogman: this session has a file from before encryption. Run the migration script to convert it, " .. migrate .. "; the session starts fresh.", vim.log.levels.WARN)
	end
	if saved_data and not (saved_data.paths and saved_data.buffers and saved_data.windows) then
		saved_data = nil
	end
	-- only a writer's bug leaves a file breaking its rules: the read fixed the data, and the load says so
	fixed = saved_data and fixed or {}

	-- why there's no data, for the trail
	local why = ({ missing = "no session file", newer = "made by a newer frogman", unencrypted = "from before encryption",
		integrity = "failed its integrity check" })[problem] or "its file holds no session"
	local ledger = require('frogman.domains.ledger')
	if #fixed > 0 then
		vim.notify("frogman: this session's file broke its own rules, and the load fixed them: " .. table.concat(fixed, "; ") .. ".",
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
		local parts = { #matched .. (#matched == 1 and " window" or " windows") .. " matched" }
		if fresh > 0 then
			table.insert(parts, fresh .. " started fresh")
		end
		if entries > #matched then
			table.insert(parts, (entries - #matched) .. (entries - #matched == 1 and " entry" or " entries") .. " dropped")
		end
		if #fixed > 0 then
			table.insert(parts, "its file broke its own rules: " .. table.concat(fixed, "; "))
		end
		-- the parts kept apart too, so the trail joins them with its own dot, and a name in one keeps its own
		ledger.move("loaded", { name = vim.fn.fnamemodify(name or cwd, ":t"), words = table.concat(parts, " · "), parts = parts })
	end
	if (saved_data == nil and hint) or (saved_data and saved_data.scope == "tab") then
		-- either tab route drops the tab's triquetras and attaches history: a cycle ends first, and so
		-- does a snapshot showing: forgotten in the tab, as its windows start over, cancelled elsewhere
		local tabpage = hint or vim.api.nvim_get_current_tabpage()
		local preview = require('frogman.domains.snapshots').preview
		local shown_in = preview.window()
		if shown_in and vim.api.nvim_win_is_valid(shown_in) and vim.api.nvim_win_get_tabpage(shown_in) == tabpage then
			preview.teardown()
			history.sm:force_state(history.states.ATTACHED)
		elseif shown_in then
			preview.cancel()
		end
		local navigation = require('frogman.domains.navigation')
		local cycling = navigation.data.cycling_window
		if cycling and vim.api.nvim_win_is_valid(cycling) then
			if vim.api.nvim_win_get_tabpage(cycling) == tabpage then
				-- a cycle running in the tab ends with nothing picked, as at a whole-editor load
				navigation.sm:force_state(navigation.states.NORMAL)
				navigation.data.cycling_window = nil
			else
				-- one running elsewhere is cancelled, as a window jump cancels it: the load attaches history
				require('frogman.domains.navigation.routines').cancel_cycle(cycling)
			end
		end
	end
	if saved_data == nil and hint then
		start_tab_fresh(cwd, name, hint)
		ledger.move("fresh", { name = vim.fn.fnamemodify(name or cwd, ":t"), words = "the tab started fresh: " .. why })
	elseif saved_data and saved_data.scope == "tab" then
		local matched = load_tab_session(saved_data, key, file_path, cwd, name, hint or vim.api.nvim_get_current_tabpage())
		loaded(matched, vim.api.nvim_tabpage_list_wins(hint or vim.api.nvim_get_current_tabpage()), #saved_data.windows)
		local set_cache_from_window_triquetra = require('frogman').set_cache_from_window_triquetra
		for _, winid in ipairs(matched) do
			set_cache_from_window_triquetra(winid)
			window.routines.enforce_note_maps_policy(window.data.crux[winid])
		end
	elseif saved_data then
		-- Restore from saved session
		marks().teardown() -- from bare as from idle: the file's marks alone, and none left on a handle the load lets go
		require('frogman.domains.snapshots').routines.teardown()
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
		history.routines.initialise_crux_internals({ window = window_histories, global = history.keyed_by_handle(saved_data.buffers.global) })
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
				marks().restore("session", load_pool.id, list.marks)
				snapshots().restore_held(load_pool.id, list.snapshots)
			end
		end
		load_pool = history.routines.pools()[""]
		local what = vim.fn.fnamemodify(name or cwd, ":t") .. ", loaded"
		local gone = restore_snapshots(saved_data, taken, "", true, what)
		local marked, gone_tabs, claimed = restore_marks(saved_data, taken, "", true, key, scratch_dir, what)
		remember_loaded(file_path, saved_data, taken, claimed, gone, marked, gone_tabs) -- before the texts reopen under new hashes
		reopen_noname_buffers(saved_data.noname_content or {}, key, scratch_dir)
		for filehash, tag in pairs(saved_data.missing or {}) do
			history.handles.set_tag(history.get_handle_from_hash(filehash), tag, { load = true })
		end
		for _, filehash in ipairs(saved_data.unwritten or {}) do
			local handle = history.handles.of_hash(filehash)
			if handle then
				handle.unwritten = true
			end
		end
		if type(saved_data.label) == "string" then
			history.data.last_label = saved_data.label
			history.data.label_seen = true
		end
		-- the caches once every slot's buffer is back, the reopened No Name texts included
		local set_cache_from_window_triquetra = require('frogman').set_cache_from_window_triquetra
		for _, winid in ipairs(matched) do
			set_cache_from_window_triquetra(winid)
		end
		-- the notes come from the file, so a slot loaded under a buffer can leave its notes naming it.
		for _, triquetra in pairs(window.data.crux) do
			window.routines.enforce_note_maps_policy(triquetra)
		end
		if not window.data.crux[window.data.last_valid_window] then
			-- the focused window has none (a help or quickfix window): the last valid window is one that has,
			-- as a fresh start's is
			for _, winid in ipairs(vim.api.nvim_list_wins()) do
				if window.data.crux[winid] then
					window.data.last_valid_window = winid
					break
				end
			end
		end
	else
		marks().teardown() -- before the fresh start lets every handle go
		require('frogman.domains.snapshots').routines.teardown()
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
	end
end

---Get the key for a session's file, and its salt.
---
---The salt is read from the file's bytes and stays from one save to the next, so the key does too,
---and a text that didn't change keeps its file. A file with no usable salt gets a new random one.
---Throws if a newer frogman made the file, so it isn't overwritten.
---
---@param file_path string The session's main file
---@param directory string The session's directory
---@param existing string|nil The main file's bytes, nil when there's no file
---@return string key The session's key
---@return string salt The salt the file is written with
local function session_key(file_path, directory, existing)
	existing = existing or ""
	if existing:match("^CDV%d") and existing:sub(1, #HEADER) ~= HEADER then
		error("frogman: this session's file was made by a newer frogman, so it isn't overwritten: " .. file_path)
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
---nothing references any more are swept, this editor's own at once and one it doesn't know, another
---editor's written a moment ago, once it's a minute old, with anything a crash left half-written. A
---closed No Name buffer whose text couldn't be kept leaves the file's closed stacks first, so no load
---meets a closed No Name entry without its text.
---
---@param file_path string The session's main file
---@param key string The session's key
---@param salt string The salt written into the header
---@param storage table The session's data
---@param kept table<string, boolean> The files in the scratch directory the main file references
---@return nil
local function commit_session(file_path, key, salt, storage, kept)
	enforce_session_file_policy(storage) -- whichever writer made the data, the file keeps its rules
	M.seal_file(file_path, key, salt, vim.json.encode(storage))
	noname_held[file_path] = {}
	for filehash, _ in pairs(storage.noname_content or {}) do
		noname_held[file_path][filehash] = true
	end

	local scratch_dir = file_path .. ".d/"
	for name, _ in pairs(kept) do
		own_files[scratch_dir .. name] = true
	end
	-- a file a closed No Name text held unread still reads from stays until that text is read
	local held = {}
	for _, handle in pairs(history.handles.live()) do
		local text = handle.text
		if text and text.lines == nil and text.source then
			held[text.source] = true
		end
	end
	if vim.fn.isdirectory(scratch_dir) == 1 then
		for _, entry in ipairs(vim.fn.readdir(scratch_dir)) do
			local path = scratch_dir .. entry
			-- this editor's own goes at once; another editor's, written a moment ago, once a minute old
			local stat = not kept[entry] and not own_files[path] and vim.uv.fs_stat(path)
			if not kept[entry] and not held[path] and (own_files[path] or (stat and stat.mtime.sec <= os.time() - 60)) then
				vim.uv.fs_unlink(path)
				own_files[path] = nil
			end
		end
	end
	-- a crash's leftovers, a minute old or more: a younger one is another editor's write in flight. They're
	-- found by name, so the session directory isn't listed
	for _, leftover in ipairs(vim.fn.glob(vim.fn.escape(file_path, "\\*?[]{}") .. ".tmp*", true, true)) do
		local stat = vim.uv.fs_stat(leftover)
		if stat and stat.mtime.sec <= os.time() - 60 then
			vim.uv.fs_unlink(leftover)
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
	-- the files the marks and the snapshots name, one only a mark or a snapshot holds among them (a tab
	-- session's file has no tabs, and no detached lists)
	local named = named_in(storage, { session = true, windows = true })
	for filehash, _ in pairs(named) do
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

---Trail pages read since frogman started (a view reads only the pages it shows or searches, and
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
---session keeps the steps made under it in its tabs: those in no tab session, the detached ones, and
---none. A tab session keeps the steps in its tab and those with a move about its list or naming it.
---Each keeps a step with a move or a copy of a file its lists or its windows held then too, so the
---file's line goes on there across a move made from another tab.
---
---@param owner Pool|nil The session's pool (nil for the whole editor's session)
---@param steps FrogmanLedgerStep[] The steps to filter
---@param session string|nil The whole editor's session's key (`ledger.session_of`), nil before the first
---@return FrogmanLedgerStep[] kept The steps the file keeps, in their order
local function steps_kept(owner, steps, session)
	local out = {}
	local list = owner and history.routines.list_name(owner)
	-- a list the session's own: the unnamed session's are the editor's, the detached ones and none
	local function its_own(id)
		if owner.id == "" then
			return id == nil or id == "" or id:sub(1, 10) == "\0detached\n"
		end
		return id == owner.id
	end
	-- a move or a copy of a file the session's lists or windows held, or a move about its list or naming it
	local function moves_about_it(step)
		for _, move in ipairs(step.moves) do
			for _, id in ipairs(move.holding or {}) do
				if its_own(id) then
					return true
				end
			end
			if owner.id ~= "" and (move.subject == owner.id or (move.lists and vim.tbl_contains(move.lists, list))) then
				return true
			end
		end
		return false
	end
	for _, step in ipairs(steps) do
		local kept
		if owner == nil then
			kept = step.session == session
		elseif owner.id == "" then
			kept = step.session == session and (its_own(step.pool) or moves_about_it(step))
		else
			kept = its_own(step.pool) or moves_about_it(step)
		end
		if kept then
			table.insert(out, step)
		end
	end
	return out
end

-- Per session file and day: the steps earlier editors wrote that day and this editor's the ledger let go,
-- read once, and how many of this editor's steps the page holds already.
local pages_written = {}
-- A page that couldn't be written at a save is said once.
local trail_warned = false

---Lets go the past days whose steps are all on their pages (defined further down, with the records)
---@type fun(file_path: string, steps: FrogmanLedgerStep[])
local settle_days

---Check if a step read from a trail page stays beside the day's steps in memory.
---
---This editor's steps stay when the ledger let them go, and the ones still in memory come from
---there instead. Another editor's stay when it started before this one; a later editor's are left
---to it, the last writer winning. A step with no mark, from a page written before steps had one,
---goes by its own time.
---
---@param step table A step as its page holds it
---@param in_memory table<integer, boolean> The numbers of this editor's steps of that day in memory
---@return boolean stays True if it stays
local function page_keeps(step, in_memory)
	local ledger = require('frogman.domains.ledger')
	if ledger.of_this_editor(step) then
		return not in_memory[step.seq]
	end
	local began = type(step.epoch) == "string" and tonumber(step.epoch:match("^([%d.]+)")) or step.time
	return type(began) == "number" and began < ledger.data.started
end

---Write the trail pages a session's file keeps.
---
---Writes a page for each day the ledger holds steps of the session: the steps earlier editors wrote
---that day and this editor's the ledger let go (`page_keeps`), then this editor's in memory. A day
---with nothing new isn't written again, and earlier days' pages stay as they are.
---
---@param file_path string The session's main file
---@param old_trail table<string, string>|nil The pages the main file lists, day → file name
---@param owner Pool|nil The session's pool (nil for the whole editor's session)
---@param session string The session's own key (`ledger.session_of`), which a whole editor's steps are marked with
---@param key string The session's key
---@param kept table<string, boolean> The names to keep in `<main>.d/`, which the pages are added to
---@return table<string, string>|nil trail The pages the main file lists now (nil if none)
---@return FrogmanLedgerStep[] paged This editor's steps the pages hold now
local function write_trail_pages(file_path, old_trail, owner, session, key, kept)
	local ledger = require('frogman.domains.ledger')
	local scratch_dir = file_path .. ".d/"
	local trail, paged = {}, {}
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
				-- what editors before this one wrote that day stays, and so do this editor's the ledger let go
				local in_memory = {}
				for _, step in ipairs(ledger.trail(day)) do
					in_memory[step.seq] = true
				end
				local before = {}
				for _, step in ipairs(trail[day] and read_page(scratch_dir .. trail[day], key, day) or {}) do
					if page_keeps(step, in_memory) then
						table.insert(before, step)
					end
				end
				written = { key = key, before = before }
			end
			local page = vim.list_slice(written.before, 1, #written.before)
			for _, step in ipairs(mine) do
				table.insert(page, {
					seq = step.seq, time = step.time, epoch = step.epoch, cause = step.cause, trigger = step.trigger,
					labels = step.labels, pool = step.pool, names = step.names, events = step.events, moves = step.moves,
					torn = step.torn,
				})
			end
			vim.fn.mkdir(scratch_dir, "p", 448) -- 0700
			write_atomic(scratch_dir .. name, crypto.seal(key, vim.json.encode({ steps = page }), HEADER .. "trail\n" .. day))
			written.count = count
			pages_written[file_path][day] = written
			trail[day] = name
		end
		vim.list_extend(paged, #mine > 0 and mine or {})
	end
	for _, name in pairs(trail) do
		kept[name] = true
	end
	return next(trail) and trail or nil, paged
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

---Put a session's closed lists into its file's data: its pools' closed entries and their close times, and,
---for the whole editor's, the detached lists, the closed lists' changes to those in the file alone among them,
---a list they empty giving what it keeps of marks and snapshots to the whole editor's scope as it goes.
---
---@param saved table The file's data, written into in place
---@param session {name: string|nil, directory: string, pools: Pool[], owner: Pool|nil, scope: string}
---@param changes table<string, {closed: Filehash[], times: table}|false>|nil For the whole editor's
---session, new entries and close times for the lists in the file alone, by name (false, or no
---entries, drops the list)
---@param key string The session's key
---@param scratch_dir string The session's scratch directory
---@return table<Filehash, table> texts The texts its lists and windows hold, the detached lists' among them
local function put_closed_part(saved, session, changes, key, scratch_dir)
	saved.closed, saved.closed_times = serialise_closed_buffers(session.pools)
	saved.paths = saved.paths or {}
	local texts = owned_texts(session.owner)
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
				else
					-- emptied: its copy of its session's marks, held over under its name, and what windows closed in its
					-- tab left held over go to the whole editor's scope, which the marks part writes
					local copy = vim.tbl_filter(function(group) return type(group) == "table" and not group.held end,
						type(list.marks) == "table" and list.marks or {})
					for filehash, _ in pairs(marks().named_by(copy)) do
						if not history.handles.of_hash(filehash) and saved.paths[filehash] then
							history.register_filepath(saved.paths[filehash])
						end
					end
					marks().hold_over("", copy, list.label, true, true, marks().held_now("")) -- not again after a write that failed
					marks().adopt_held("", list.marks, saved.paths)
					for _, held in ipairs(type(list.snapshots) == "table" and list.snapshots or {}) do
						for filehash, _ in pairs(snapshots().named_by({ held })) do
							if not history.handles.of_hash(filehash) and saved.paths[filehash] then
								history.register_filepath(saved.paths[filehash])
							end
						end
					end
					snapshots().restore_held("", snapshots().not_held(list.snapshots)) -- not again, once memory has them
				end
			end
			lists = kept
		end
		carry_detached(lists, live, saved, texts, saved.paths, key, scratch_dir)
		saved.detached = #lists > 0 and lists or nil
		for _, list in ipairs(lists) do
			for _, filehash in ipairs(list.closed or {}) do
				saved.paths[filehash] = saved.paths[filehash] or history.get_filepath_from_hash(filehash)
			end
		end
	end
	return texts
end

---Put a session's marks and snapshots into its file's data: what a close put onto a window's or a tab's
---entry, and the marks and snapshots taken off an entry the last load left, each only while it's still the
---entry this editor knows, as the file holds it, one another editor's save rewrote holding the close over
---instead; the session's own marks and the snapshots held over in its scope; and the texts they name but
---those the closed part took already, which stay as it took them, and the paths they name, the detached
---lists' copies among them, the closed part having built the lists.
---
---@param saved table The file's data, written into in place
---@param session {name: string|nil, directory: string, pools: Pool[], owner: Pool|nil, scope: string}
---@param texts table<Filehash, table> The texts the file takes, added to in place
---@param key string The session's key
---@param file_path string The session's main file
---@return table landing The entries it wrote, for `land_entries` once the file is committed
local function put_marks_part(saved, session, texts, key, file_path)
	-- the entries this editor knows, each only while it's still the entry it knows: one the last load
	-- didn't take gives up its marks and snapshots, held over since; one a close left takes what the
	-- close put onto it; one another editor's save rewrote has the close's held over instead
	local known = data.entries[file_path]
	local wrote, at = {}, {}
	for i, slot in pairs(known and known.windows or {}) do
		local entry = type(saved.windows) == "table" and saved.windows[i]
		local same = type(entry) == "table" and vim.deep_equal(entry, slot.entry)
		if slot.take_off and same then
			entry[10], entry[11] = nil, nil
			wrote[slot] = entry
		elseif slot.close and slot.close.state == nil then
			if same then
				entry[10], entry[11] = slot.close.groups, slot.close.snapshots
				wrote[slot] = entry
			else
				hold_closed(slot.close)
			end
		end
	end
	if known then
		local file_tabs, keep = type(saved.tabs) == "table" and saved.tabs or {}, {}
		for i, tab in ipairs(file_tabs) do
			keep[i] = true
		end
		for i, slot in pairs(known.tabs) do
			local tab = file_tabs[i]
			local same = tab ~= nil and vim.deep_equal(tab, slot.entry)
			if slot.take_off and same then
				keep[i] = false
			elseif slot.close and slot.close.state == nil then
				if same then
					tab.groups = slot.close.groups
					keep[i] = tab.groups ~= nil -- a tab entry with no groups left comes off
					wrote[slot] = tab
				else
					hold_closed(slot.close)
				end
			end
		end
		local tabs = {}
		for i, tab in ipairs(file_tabs) do
			if keep[i] then
				table.insert(tabs, tab)
				at[i] = #tabs
			end
		end
		saved.tabs = #tabs > 0 and tabs or nil
	end
	saved.paths = saved.paths or {}
	local scope_id = session.scope == "tab" and session.owner.id or ""
	saved.marks = marks().serialise("session", scope_id)
	saved.snapshots = snapshots().serialise_held(scope_id) -- the snapshots held over in its scope
	for filehash, text in pairs(marked_texts(session.owner)) do
		texts[filehash] = texts[filehash] or text -- at a switch, the closed part's copy is open or closed as the file has it
	end
	carry_marked_texts(texts, saved, key, file_path .. ".d/", true)
	for filehash, _ in pairs(named_in(saved, { session = true, windows = true, tabs = true })) do
		saved.paths[filehash] = saved.paths[filehash] or history.get_filepath_from_hash(filehash)
	end
	if session.scope == "editor" then
		-- the paths the detached lists' marks and held-over snapshots need, the lists as the closed part built them
		for _, list in ipairs(saved.detached or {}) do
			for filehash, _ in pairs(snapshots().named_by(list.snapshots, marks().named_by(list.marks))) do
				saved.paths[filehash] = saved.paths[filehash] or history.get_filepath_from_hash(filehash)
			end
		end
	end
	return { known = known, wrote = wrote, at = at }
end

---Settle the entries a write put marks and snapshots onto, once its file is committed: each is the entry
---this editor knows now, a close on it landed; an entry taken off, or a tab entry gone, leaves what it knew
---of it.
---
---@param landing table What `put_marks_part` wrote
---@return nil
local function land_entries(landing)
	local known, wrote, at = landing.known, landing.wrote, landing.at
	for i, slot in pairs(known and known.windows or {}) do
		if wrote[slot] then
			slot.entry = as_filed(wrote[slot])
			if slot.close then
				slot.close.state = "landed"
			end
			if slot.take_off then
				known.windows[i] = nil
			end
		end
	end
	if known then
		local tabs = {}
		for i, slot in pairs(known.tabs) do
			if at[i] then
				if wrote[slot] then
					slot.entry = as_filed(wrote[slot])
					slot.close.state = "landed"
				end
				tabs[at[i]] = slot
			elseif slot.close and slot.close.state ~= "held" then
				history.handles.drop_place(slot.close.place) -- its entry came off with nothing left to hold over
			end
		end
		known.tabs = tabs
	end
end

---Write a session's records into its file again: what `fill` puts into the file's data, and today's trail
---page, everything else as the file has it.
---
---A file that isn't there isn't made, and one that can't be read, or whose scope isn't the session's,
---isn't touched. The texts are written before the main file, the trail's pages beside them, then the main
---file is committed and the entries the write put marks and snapshots onto are settled.
---
---@param session {name: string|nil, directory: string, pools: Pool[], owner: Pool|nil, scope: string}
---@param fill fun(saved: table, key: string, file_path: string): table<Filehash, table>, table What the write puts into the file's data, giving the texts the file takes and what `put_marks_part` wrote
---@return boolean written True if the file was written
---@return string|nil problem "missing" when there's no file, otherwise what went wrong
local function rewrite_records(session, fill)
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
		local texts, landing = fill(saved, key, file_path)
		local noname_content, kept = write_noname_texts(texts, key, file_path .. ".d/")
		saved.noname_content = noname_content
		saved.paths = saved.paths or {}
		for _, filehash in ipairs(saved.closed or {}) do
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
		local paged
		saved.trail, paged = write_trail_pages(file_path, saved.trail, session.owner,
			require('frogman.domains.ledger').session_of(session.name, session.directory), key, kept) -- today's page rides along
		commit_session(file_path, key, salt, saved, kept)
		land_entries(landing)
		settle_days(file_path, paged)
	end)
	if not ok then
		return false, "it couldn't be written: " .. tostring(err)
	elseif gone then
		return false, "missing"
	end
	return true, nil
end

---Write a session's records into its file.
---
---The records are its closed list, close times and No Name texts, from its pools, and its marks and the
---snapshots held over in its scope, and the trail's pages ride along. Its references stay as the
---session manager last saved them, but for what closes put onto their entries and what a load left taken
---off, and the whole editor's records carry the detached lists too. A file that isn't there isn't made,
---and one that can't be read, or whose scope isn't the session's, isn't touched.
---
---@param session {name: string|nil, directory: string, pools: Pool[], owner: Pool|nil, scope: string}
---@param changes table<string, {closed: Filehash[], times: table}|false>|nil For the whole editor's
---session, new entries and close times for the lists in the file alone, by name (false, or no
---entries, drops the list)
---@return boolean written True if the file was written
---@return string|nil problem "missing" when there's no file, otherwise what went wrong
local function write_records(session, changes)
	return rewrite_records(session, function(saved, key, file_path)
		local texts = put_closed_part(saved, session, changes, key, file_path .. ".d/")
		return texts, put_marks_part(saved, session, texts, key, file_path)
	end)
end

---Put a session's closed lists into its file's data as the file has them, and what else they hold as memory
---has it: the file's closed entries and close times, and its detached lists', a detached list made since it
---was written taking its own; and every text the file names, memory's lines where memory holds it, the
---file's word on whether it's open kept, and otherwise carried from the file, unread.
---
---@param saved table The file's data, written into in place
---@param session {name: string|nil, directory: string, pools: Pool[], owner: Pool|nil, scope: string}
---@param key string The session's key
---@param scratch_dir string The session's scratch directory
---@return table<Filehash, table> texts The texts the file names
local function keep_closed_part(saved, session, key, scratch_dir)
	saved.paths = saved.paths or {}
	local texts = {}
	for filehash, entry in pairs(type(saved.noname_content) == "table" and saved.noname_content or {}) do
		if type(entry) == "table" then
			local handle = history.handles.of_hash(filehash)
			local bufnr = history.data.hash_buffer_registry.buffers[filehash]
			local text
			if bufnr and vim.api.nvim_buf_is_loaded(bufnr) and is_known(filehash) then
				text = open_text(bufnr)
			elseif handle and handle.text and is_known(filehash) then
				text = handle.text
			end
			if text then
				local copy = {}
				for field, value in pairs(text) do
					copy[field] = value
				end
				copy.reopen = entry.reopen -- open or closed as the file has it, whatever the teardown closed
				texts[filehash] = copy
			elseif type(entry.scratch) == "string" then
				local source = scratch_dir .. entry.scratch
				texts[filehash] = { scratch = entry.scratch, source = source, key = key,
					read = scratch_reader(source, key, filehash), reopen = entry.reopen }
			end
		end
	end
	if session.scope == "editor" then
		-- the detached lists ride with the whole editor's records, each the file has with its closed entries
		local lists, live = detached_lists(saved, nil)
		local filed = {}
		for _, list in ipairs(saved.detached or {}) do
			filed[list.label] = list
		end
		for _, list in ipairs(lists) do
			local was = live[list.label] and filed[list.label]
			if was then
				list.closed, list.closed_times = was.closed, was.closed_times
			end
		end
		carry_detached(lists, live, saved, texts, saved.paths, key, scratch_dir)
		saved.detached = #lists > 0 and lists or nil
		for _, list in ipairs(lists) do
			for _, filehash in ipairs(list.closed or {}) do
				saved.paths[filehash] = saved.paths[filehash] or history.get_filepath_from_hash(filehash)
			end
		end
	end
	return texts
end

---Write the session left's records into its file at a load: everything memory holds of them but its closed
---lists' changes, which a session manager's teardown made, the closed lists staying as the file has them.
---
---@param session {name: string|nil, directory: string, pools: Pool[], owner: Pool|nil, scope: string}
---@return boolean written True if the file was written
---@return string|nil problem "missing" when there's no file, otherwise what went wrong
local function write_session_left(session)
	return rewrite_records(session, function(saved, key, file_path)
		local texts = keep_closed_part(saved, session, key, file_path .. ".d/")
		return texts, put_marks_part(saved, session, texts, key, file_path)
	end)
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
	local ledger = require('frogman.domains.ledger')
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
		vim.notify("frogman: the whole editor's session file wasn't refreshed with its closed files and No Name texts, since " .. problem, vim.log.levels.WARN)
	end
end

-- Records written on time ------------------------------------------------------------------------

-- the sessions whose records changed since they were last written (pool id → true), whether writes
-- run (between setup() and disable()), a generation a load moves on so a write it overtook is dropped,
-- the second's timer, the problems already reported (so each is told once), and the pools whose last
-- tab closed, waiting for the next tick (pool id → pool)
local dirty, writing, generation, quiet, told, closing = {}, false, 0, nil, {}, {}

-- the No Name texts whose sessions an edit has marked since the records were last written: the next
-- edit of one finds them marked already (hash → true)
local noname_edited = {}

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

---Get the main file a session's records go into: a tab session's own, the whole editor's for its own and
---for a detached list's.
---
---@param session_id string The session's pool id ("" for the whole editor's)
---@return string|nil file_path Nil while the session has no file
local function records_file(session_id)
	local pool = history.data.pools[session_id]
	if session_id == "" or (pool and pool.detached) then
		local session = whole_editor_session()
		return session and get_session_filepath(session.directory, session.name) or nil
	end
	return pool and pool.directory and get_session_filepath(pool.directory, pool.name) or nil
end

---Put what a closing window or plain tab holds onto its entry in its session's file, as it stands, for the
---next records write: its groups, and a window's snapshots. Taken once, by whichever close comes first,
---both parts at once, so neither is missed for the other's having none. Its files stay held while the
---entry waits, so a save that holds them over finds them.
---
---@param kind "window"|"tab" Whether a window or a plain tab is closing
---@param id WinId|integer The window or the tab closing
---@param session_id string The pool id of the session it's in ("" for the whole editor's)
---@param what string What it was, as a held-over header names it, should the entry not take it
---@return boolean onto Whether it has an entry there: one without has nothing put anywhere, to be held over
function M.close_onto_entry(kind, id, session_id, what)
	local file_path = records_file(session_id)
	local known = file_path and data.entries[file_path]
	local slot
	for _, candidate in pairs(known and known[kind == "window" and "windows" or "tabs"] or {}) do
		if (kind == "window" and candidate.win == id) or (kind == "tab" and candidate.tab == id) then
			slot = candidate
		end
	end
	if slot == nil then
		return false
	end
	if slot.close == nil then
		local groups = marks().serialise(kind, id)
		local saved = kind == "window" and snapshots().serialise_window(id) or nil
		closes_held = closes_held + 1
		local place, ids = "entry:closed:" .. closes_held, {}
		for filehash, _ in pairs(snapshots().named_by(saved, marks().named_by(groups))) do
			local handle = history.handles.of_hash(filehash)
			if handle then
				table.insert(ids, handle.id)
			end
		end
		history.handles.hold(place, ids)
		slot.close = { groups = groups, snapshots = saved, what = what, session = session_id, place = place }
		require('frogman.held').records_changed(session_id)
	end
	return true
end

-- what the last look at the whole editor's file found, for an entry moved out of a list there
local file_view = nil
-- each No Name text's first line and filetype on a list in the file alone, by its file: a file's name
-- follows its text, so one read stands for every draw, and a lost one is said once
local file_only_texts = {}

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
	local in_memory, lists = detached_tab_sessions(), {}
	for _, list in ipairs(saved.detached) do
		if not in_memory[list.label] then
			local texts = {}
			for _, filehash in ipairs(list.closed or {}) do
				local entry = file_view.noname_content[filehash]
				if entry then
					local path = scratch_dir .. entry.scratch
					if file_only_texts[path] == nil then
						local text = scratch_reader(path, key, filehash)()
						file_only_texts[path] = { first = text and text.lines and text.lines[1] or "", filetype = text and text.filetype }
					end
					texts[filehash] = file_only_texts[path]
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
	local in_memory = detached_tab_sessions()
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
---Its path is registered, and a No Name text's file is held unread on its handle, as a load holds a
---closed one's. It uses what the last `M.file_only_lists()` found, and registers nothing without it.
---
---@param filehash Filehash The entry's hash
---@return HandleId|nil id The entry's file's handle, or nil when nothing knows its path
function M.adopt_file_entry(filehash)
	if file_view == nil then
		return history.get_handle_from_hash(filehash)
	end
	local path = file_view.paths[filehash]
	if path and history.get_filepath_from_hash(filehash) == nil then
		history.register_filepath(path)
	end
	local handle = history.handles.of_hash(filehash)
	local entry = file_view.noname_content[filehash]
	if entry and handle and handle.text == nil then
		local source = file_view.scratch_dir .. entry.scratch
		handle.text = { scratch = entry.scratch, source = source, key = file_view.key, read = scratch_reader(source, file_view.key, filehash) }
	end
	return handle and handle.id or nil
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

---Hand what a detached list in memory keeps of marks and snapshots to the whole editor's scope, as it goes
---with nothing in its closed list: its copy of its session's marks, each group held over under the list's
---name, and the group's when it had several, then the groups and the snapshots its tab's windows left held
---over, each as it is. The list keeps none, so the next whole-editor write leaves it out of the file.
---
---@param pool Pool The detached list's pool
---@return nil
local function hand_to_editor(pool)
	local scope = marks().scope("session", pool.id)
	marks().hold_over("", vim.tbl_filter(function(group) return not group.held end, scope and scope.groups or {}), pool.name)
	marks().move_held(pool.id, "")
	snapshots().move_held(pool.id, "")
	marks().drop_scope("session", pool.id)
	snapshots().drop_held(pool.id)
end

---Settle the detached lists that waited on the closed lists, once those are gone.
---
---A session loaded back into its own detached list's tab opens the closed lists on that list, and
---the list waits in memory until they close. Then a list still holding entries goes into the whole
---editor's file, as any left with no tab does, and one the merge emptied goes from memory and from
---the file, what it keeps of marks and snapshots going to the whole editor's scope.
---
---@return nil
function M.settle_merging()
	for id, pool in pairs(history.data.pools) do
		if pool.merging and next(pool.tabs) == nil then
			pool.merging = nil
			if #pool.closed == 0 then
				hand_to_editor(pool)
				local session = whole_editor_session()
				local ok, problem = true, nil
				if session then
					ok, problem = write_records(session) -- the list in memory with nothing left: the file loses it
				end
				-- a write that failed leaves it in memory, with nothing in it, so the next one leaves it out of the file
				local gone = ok or problem == "missing"
				if gone then
					pool:drop()
				end
				require('frogman.domains.ledger').move("detached_left", { subject = id, name = pool.name,
					words = gone and "merged, and gone" or "merged; kept, with no tab" })
			else
				M.close_tab_pool(pool)
			end
		end
	end
end

---Get every session frogman knows, the whole editor's and each tab session's.
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

---Note the steps a session's pages now hold, and let go the past days that are all on disk.
---
---Runs once a main file that lists the pages has landed. A day before today, but the open step's,
---goes from the ledger's memory once every step on it is on one page at least, and on the page of
---every session frogman knows that keeps it, and none of them is still in the ring. So a session
---with no file keeps its steps, and so does a step no page has taken. The page cache of a day that
---goes is dropped, so a step landing on it later is written beside what its page holds.
---
---@param file_path string The session's main file, just committed
---@param steps FrogmanLedgerStep[] The steps its pages hold
---@return nil
settle_days = function(file_path, steps)
	local ledger = require('frogman.domains.ledger')
	local today, open = os.date("%Y-%m-%d"), ledger.data.open
	for _, step in ipairs(steps or {}) do
		if step ~= open then -- the open step may make more moves, which no page has yet
			step.written_to = step.written_to or {}
			step.written_to[file_path] = true
		end
	end
	local past = false
	for _, day in ipairs(ledger.trail_days()) do
		past = past or day < today
	end
	if not past then
		return -- no day to let go
	end
	local open_day = open and os.date("%Y-%m-%d", math.floor(open.time))
	local unclaimed = whole_editor_session() == nil
	local ringed = {}
	for _, step in ipairs(ledger.steps()) do
		ringed[step] = true
	end
	local sessions = {}
	for _, session in ipairs(known_sessions()) do
		table.insert(sessions, { file = get_session_filepath(session.directory, session.name), owner = session.owner,
			key = ledger.session_of(session.name, session.directory) })
	end
	for _, day in ipairs(ledger.trail_days()) do
		local settled = day < today and day ~= open_day
		local day_steps = settled and ledger.trail(day) or {}
		-- newest first: a day with a step still in the ring can't go, and those are its newest. A step made
		-- before any whole-editor session waits to be claimed by the first one, so its day stays too.
		for i = #day_steps, 1, -1 do
			local step = day_steps[i]
			settled = not ringed[step] and step.written_to ~= nil and next(step.written_to) ~= nil
				and not (unclaimed and step.session == nil)
			for _, session in ipairs(settled and sessions or {}) do
				if not step.written_to[session.file] and #steps_kept(session.owner, { step }, session.key) > 0 then
					settled = false
					break
				end
			end
			if not settled then
				break
			end
		end
		if settled then
			ledger.forget_day(day)
			for _, days in pairs(pages_written) do
				days[day] = nil
			end
		end
	end
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
	for id, entry in pairs(keys) do
		if entry.file and not open[id] then
			keys[id] = nil -- a dump's key, taken for no file, stays
		end
	end
	for file_path, id in pairs(key_of) do
		if not open[id] then
			key_of[file_path] = nil
		end
	end
end

---Hand what each detached list in memory with no tab and nothing in its closed list keeps of marks and snapshots to
---the whole editor's scope, ahead of a whole-editor write, so the write leaves it out as an emptied list: one a
---write that failed kept with no tab, emptied since in the closed lists or by opening its files. One waiting on the
---closed lists stays for its merge, and one whose tab has just closed for its close, which hands it over itself.
---
---@return nil
local function hand_over_emptied()
	for id, pool in pairs(history.data.pools) do
		if pool.detached and not pool.merging and not closing[id] and next(pool.tabs) == nil and #pool.closed == 0 then
			hand_to_editor(pool)
		end
	end
end

---Let go the detached lists in memory that the whole editor's file leaves out, once a write of it has gone
---through: each with no tab and nothing left in it, as an empty one a write that failed kept is, so it
---doesn't stay as a section with nothing in it. One waiting on the closed lists stays for its merge, and one
---whose tab has just closed stays for its close, which takes what its windows left held over first.
---
---@return nil
local function let_empty_lists_go()
	for id, pool in pairs(history.data.pools) do
		if pool.detached and not pool.merging and not closing[id] and nothing_left(pool) then
			pool:drop()
			require('frogman.domains.ledger').move("detached_left", { subject = id, name = pool.name, words = "empty, and gone" })
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
	if session.scope == "editor" then
		hand_over_emptied() -- an emptied list with no tab goes as emptied: the write leaves it out, its marks in
	end
	local ok, problem = write_records(session)
	if ok then
		dirty[session.id] = nil
		if session.scope == "editor" then
			let_empty_lists_go() -- the lists the file left out go from memory too
		end
	elseif problem ~= "missing" and not told[session.id .. problem] then
		told[session.id .. problem] = true
		vim.notify("frogman: " .. (session.name or vim.fn.fnamemodify(session.directory, ":t")) .. "'s closed files and No Name texts weren't written, since " .. problem, vim.log.levels.WARN)
	end
	return ok
end

---Check if a close waits to be written onto one of a session file's entries.
---
---@param file_path string The session's main file
---@return boolean waiting
local function closes_waiting(file_path)
	local known = data.entries[file_path]
	for _, kind in ipairs({ "windows", "tabs" }) do
		for _, slot in pairs(known and known[kind] or {}) do
			if slot.close and slot.close.state == nil then
				return true
			end
		end
	end
	return false
end

---Let every window and plain tab still open go as its close would, ahead of a whole-editor load that tears
---them all down: what each holds onto its saved entry as it stands, or queued to be held over in its
---session's scope with none, so the session left keeps every window's marks and snapshots, not only those
---its manager's teardown closed.
---
---@return nil
local function close_open_windows()
	local held = require('frogman.held')
	for _, winid in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_config(winid).relative == "" then
			local session, what = held.closing_in(winid)
			local onto = marks().window_going(winid, session, what)
			if require('frogman.domains.snapshots').data.by_window[winid] then
				snapshots().queue_hold_over(winid, onto)
			end
		end
	end
	for tabpage, _ in pairs(require('frogman.domains.marks').data.scopes.tab) do
		if vim.api.nvim_tabpage_is_valid(tabpage) then
			marks().tab_going(tabpage, held.tab_closing_in(tabpage))
		end
	end
end

---Write what memory holds of the session left's records into its file, as a load begins and before it
---drops anything: at a whole-editor load, which tears every window and session down, every session's, each
---window and plain tab still open going first as its close would; at a tab session's load, those of the
---sessions the closes in the tab it loads into left something to, and of a session with a close waiting to
---be written onto an entry. What the windows and tabs closed without their events left goes first, as their
---closes would have, the next cleanup tick's pass run now, and what the closes queued to hold over is held
---over, each in its session's scope; then each such session with a file gets its records written but for
---its closed lists, which stay as the file has them, so at a session manager's switch the session left keeps
---everything memory holds but its teardown's closes. It isn't held by the editor's directory, what it writes
---being each session's own; nothing is written while the records are off.
---
---@param tabpage integer|nil The tab a tab session's load goes into, or nil for a whole-editor load
---@param directory string The directory of the session the load reads
---@param name string|nil Its name (nil for a nameless session)
---@return boolean wrote Whether it wrote the file the load reads, which the load then reads again
function M.keep_session_left(tabpage, directory, name)
	if not writing then
		return false
	end
	require('frogman.held').hold_over_gone()
	if tabpage == nil then
		close_open_windows()
	end
	local due = {}
	for _, held in ipairs({ marks().flush_pending(nil, tabpage), snapshots().flush_pending(nil, tabpage) }) do
		for id, _ in pairs(held) do
			local pool = history.data.pools[id]
			due[(pool and pool.detached) and "" or id] = true -- a detached list's records are the whole editor's
		end
	end
	local reads, wrote = get_session_filepath(directory, name), false
	for _, session in ipairs(known_sessions()) do
		local file_path = get_session_filepath(session.directory, session.name)
		if tabpage == nil or due[session.id] or closes_waiting(file_path) then
			local ok, problem = write_session_left(session)
			wrote = wrote or (ok and file_path == reads)
			if not ok and problem ~= "missing" and not told["left " .. session.id .. problem] then
				told["left " .. session.id .. problem] = true
				vim.notify("frogman: " .. (session.name or vim.fn.fnamemodify(session.directory, ":t")) ..
					"'s marks, snapshots and No Name texts weren't written as the load began, since " .. problem, vim.log.levels.WARN)
			end
		end
	end
	return wrote
end

---Let go of every session file's entries this editor knows, as a whole-editor load starts from nothing: the
---session left's were written as the load began.
---
---@return nil
function M.forget_all_entries()
	for file_path, _ in pairs(data.entries) do
		forget_entries(file_path)
	end
end

---Write the records of a pool whose last tab closed, then let the pool go.
---
---A tab session's records go into its own file, and a detached list's into the whole editor's, but for
---one with nothing in its closed list, which goes as an emptied list does: what it keeps of marks and
---snapshots goes to the whole editor's scope, and the list from memory and that file, or from memory
---alone when there's no such file. When the records can't be written, the pool is kept with no tab, so the
---next write still knows it, and a warning says so. A load since, which tore it down, or a tab back in
---it, leaves it alone.
---
---@param pool Pool The pool whose last tab closed
---@return nil
local function close_now(pool)
	closing[pool.id] = nil
	if history.data.pools[pool.id] ~= pool or next(pool.tabs) ~= nil then
		return
	end
	-- what its windows' closes queued to hold over goes into its scope first, so its records take it
	marks().flush_pending(pool.id)
	snapshots().flush_pending(pool.id)
	if pool.detached then
		-- a detached list goes into the whole editor's file, and leaves memory; one with nothing in its closed
		-- list goes as an emptied one does, its marks and snapshots to the whole editor's scope
		local empty = #pool.closed == 0
		if empty then
			hand_to_editor(pool)
		end
		local session = whole_editor_session()
		local ok, problem = false, "missing"
		if session then
			ok, problem = write_records(session)
		end
		local ledger = require('frogman.domains.ledger')
		-- with no file there's nothing of an empty one to keep; a write that failed leaves it in memory, so the
		-- next one leaves it out of the file rather than taking the file's own entry for it
		if ok or (empty and problem == "missing") then
			pool:drop()
			marks().drop_scope("session", pool.id) -- its marks are on its entry in the file now
			snapshots().drop_held(pool.id) -- and its held-over snapshots
			ledger.move("detached_left", { subject = pool.id, name = pool.name,
				words = data.replayed and "let go" or empty and "empty, and gone" or "into the whole editor's file" })
			return
		end
		ledger.move("detached_left", { subject = pool.id, name = pool.name, words = "kept, with no tab" })
		if empty then
			vim.notify("frogman: " .. pool.name .. "'s tab is gone with nothing in its list, and the whole editor's session file couldn't be written (" ..
				problem .. "); its marks are held over in the whole editor's scope.", vim.log.levels.WARN)
		else
			vim.notify("frogman: " .. pool.name .. "'s tab is gone, and its closed files couldn't be written into the whole editor's session file (" ..
				(problem == "missing" and "it has no session file yet" or problem) .. "); they stay, with no tab, in :FrogmanClosed.", vim.log.levels.WARN)
		end
		return
	end
	local ok, problem = write_records({ name = pool.name, directory = pool.directory, pools = { pool }, owner = pool, scope = "tab" })
	local ledger = require('frogman.domains.ledger')
	if ok then
		dirty[pool.id] = nil
		pool:drop()
		marks().drop_scope("session", pool.id) -- its marks are in its file now, and go with its list
		snapshots().drop_held(pool.id) -- and so are the snapshots held over in its scope
		forget_closed_keys()
		ledger.move("tab_closed", { subject = pool.id, name = history.routines.list_name(pool),
			words = data.replayed and "its list let go" or "its records written; its list let go" })
		return
	end
	ledger.move("tab_closed", { subject = pool.id, name = history.routines.list_name(pool), words = "kept, with no tab" })
	vim.notify("frogman: " .. (pool.name or vim.fn.fnamemodify(pool.directory or "", ":t")) .. "'s tab closed, and its closed files couldn't be written (" ..
		(problem == "missing" and "it has no session file yet" or problem) .. "); they stay, with no tab, in :FrogmanClosed.", vim.log.levels.WARN)
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
	if not writing or require('frogman.domains.storage.sm'):state() ~= "idle" then
		return
	end
	noname_edited = {} -- an edit from here on is a new one, its sessions worked out again
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
	local function second_over()
		if mine == generation and next(dirty) ~= nil then
			M.write_records()
			-- changes kept coming: another second, so the next one isn't taken for the first after a quiet
			-- spell and written at once
			quiet:start(1000, 0, vim.schedule_wrap(second_over))
		end
	end
	quiet:start(1000, 0, vim.schedule_wrap(second_over))
end

---Mark changed the sessions whose files hold an edited No Name text, and no other.
---
---A session's file holds the texts its save would write: every text while the whole editor's
---session covers every tab, and otherwise the texts its list owns. So the edit is written with those
---sessions' records, and no other session's file is read and written again for it, but for one whose
---last write held the text, which is then written without it. The sessions are worked out at the
---text's first edit since the records were last written; the edits after it find them marked.
---
---@param filehash Filehash The No Name buffer's hash
---@return nil
function M.noname_text_changed(filehash)
	if noname_edited[filehash] then
		return
	end
	noname_edited[filehash] = true
	for _, session in ipairs(known_sessions()) do
		local held = noname_held[get_session_filepath(session.directory, session.name)]
		if owned(session.owner, history.get_handle_from_hash(filehash)) or (held and held[filehash]) then
			M.records_changed(session.id)
		end
	end
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
	vim.fn.mkdir(configs.session_dir, "p") -- made at its first write, as the umask allows, before a text's folder in it
	-- one read: the salt, the detached lists and the trail's pages come from the same bytes
	local bytes = read_file(file_path)
	local key, salt = session_key(file_path, cwd, bytes)
	local previous = bytes and read_session_file(file_path, cwd, bytes)

	local pool
	if tab then
		local before = history.routines.pool_of_tab(tab)
		pool = history.routines.join_pool(tab, name, cwd)
		tab_marks_held_over(tab, pool.id) -- a plain tab's tab marks, now its session's to hold over
		if pool ~= before and next(pool.visits) == nil then
			-- a tab saved as this session for the first time: its own visits start the pool's
			for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
				for id, time in pairs(history.data.crux_internals.window[winid] or {}) do
					pool.visits[id] = math.max(pool.visits[id] or time, time)
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
					for _, id in ipairs(triquetra.primary_buffer or {}) do
						history.routines.carry_closed(before, pool, id)
					end
				end
			end
			if before.id ~= "" then
				-- a tab session saved as another: the new one gets a copy of its marks, its held-over groups
				-- among them, and of its held-over snapshots, as its closed files are carried; the old keeps its own
				marks().carry_scope(before.id, pool.id)
				snapshots().copy_held(before.id, pool.id)
			end
			if before.id ~= "" and next(before.tabs) == nil then
				M.close_tab_pool(before) -- the session it leaves, with no tab left, is written and goes
			end
		end
	end

	local outsiders = {}
	local windows, entry_wins = serialise_window_relationships(outsiders, tab)
	local saved_tabs, tab_pages = nil, {}
	if not pool then
		hand_over_emptied() -- an emptied list with no tab goes as emptied: the save leaves it out, its marks in
		saved_tabs, tab_pages = serialise_tabs()
	end
	hold_dropped(file_path, entry_wins, tab_pages) -- before the session's own marks are written, so they're in them
	local texts, paths = serialise_noname_content(pool), serialise_paths(outsiders)
	local detached
	if not pool then
		-- the detached lists, apart: each in memory with its tab's window entries, and each the file
		-- holds alone carried over, with its texts and paths
		local live
		detached, live = detached_lists(previous, function(detached_pool)
			local indices = {}
			for i, winid in ipairs(entry_wins) do
				if vim.api.nvim_win_is_valid(winid) and detached_pool.tabs[vim.api.nvim_win_get_tabpage(winid)] then
					table.insert(indices, i)
				end
			end
			return indices
		end)
		carry_detached(detached, live, previous, texts, paths, key, file_path .. ".d/")
		carry_marked_texts(texts, previous or {}, key, file_path .. ".d/", false)
	end
	local noname_content, kept = write_noname_texts(texts, key, file_path .. ".d/")
	local closed, closed_times = serialise_closed_buffers(pool and { pool } or every_pool())
	-- the never-written marks, from the handles that carry them, of the files frogman knows
	local unwritten = {}
	for _, handle in pairs(history.handles.live()) do
		if handle.unwritten and next(handle.holders) ~= nil then
			table.insert(unwritten, handle.hash)
		end
	end
	local storage = {
		scope = tab and "tab" or "editor", -- a tab session's file loads into a tab
		detached = detached and #detached > 0 and detached or nil, -- the whole editor's detached lists, when there are some
		paths = paths,
		outsiders = vim.tbl_keys(outsiders),
		buffers = pool and { global = history.keyed_by_hash(pool.visits) } or serialise_buffer_history(),
		windows = windows,
		closed = closed,
		closed_times = closed_times, -- when each was closed, to merge pools by
		noname_content = noname_content,
		missing = history.tags_by_hash(), -- where each file gone from disk went missing
		label = history.data.last_label, -- where you were at this save: the label being left at the next load
		unwritten = #unwritten > 0 and unwritten or nil, -- files never written
		marks = marks().serialise("session", pool and pool.id or ""), -- the session's own marks, when it has some
		snapshots = snapshots().serialise_held(pool and pool.id or ""), -- the snapshots held over in its scope, when there are some
		tabs = saved_tabs, -- the plain tabs' marks, when there are some
	}

	if pool then
		narrow(storage)
	end
	-- the trail's pages: today's written, earlier days' kept. A page that can't be written doesn't stop
	-- the save: the pages it had stay.
	if not pool then
		require('frogman.domains.ledger').claim(name, cwd) -- a first whole-editor save takes the steps before it
	end
	local written, trail, paged = pcall(write_trail_pages, file_path, previous and previous.trail, pool,
		require('frogman.domains.ledger').session_of(name, cwd), key, kept)
	if written then
		storage.trail = trail
	else
		storage.trail = previous and previous.trail
		for _, page in pairs(storage.trail or {}) do
			kept[page] = true
		end
		if not trail_warned then
			trail_warned = true
			vim.notify("frogman: the trail's page couldn't be written (" .. tostring(trail) .. "); the session is saved without it.",
				vim.log.levels.WARN)
		end
	end

	-- Write updated data back to file
	commit_session(file_path, key, salt, storage, kept)
	remember_saved(file_path, windows, entry_wins, saved_tabs, tab_pages) -- the windows and tabs are written anew
	if written then
		settle_days(file_path, paged)
	end
	require('frogman.domains.ledger').move("saved", { name = vim.fn.fnamemodify(name or cwd, ":t"),
		words = pool and "the tab session" or "the whole editor" })
	if pool then
		dirty[pool.id] = nil
		refresh_unnamed()
	else
		-- a whole-editor save covers every tab again: tab sessions started after it make it the unnamed one
		local before = data.editor_session
		data.editor_session, data.unnamed = { name = name, directory = cwd }, nil
		require('frogman.domains.ledger').set_session(name, cwd)
		require('frogman.domains.marks').popup.renamed(before) -- the marks pop-up's session buffer follows the name
		dirty[""] = nil
		let_empty_lists_go() -- the lists the file left out go from memory too
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
---only the pages it shows. A day's steps are the page's steps from editors before this one and this
---editor's the ledger let go (`page_keeps`), then this editor's in memory that the session's file
---keeps, by the same rule its pages are written by. The page is kept as read, and sorted at each
---call, so a day the ledger lets go while the view is open is read from its page then.
---
---@return {days: fun(): string[], steps: fun(day: string): table[]} reader
function M.trail_reader()
	local ledger = require('frogman.domains.ledger')
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
			pages[day] = trail[day] and key and read_page(file_path .. ".d/" .. trail[day], key, day) or {}
		end
		local in_memory = {}
		for _, step in ipairs(ledger.trail(day)) do
			in_memory[step.seq] = true
		end
		local steps = {}
		for _, step in ipairs(pages[day]) do
			if page_keeps(step, in_memory) then
				table.insert(steps, step)
			end
		end
		return vim.list_extend(steps, steps_kept(owner, ledger.trail(day), whole))
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
	vim.fn.mkdir(configs.session_dir, "p") -- made at its first write, as the umask allows, before a text's folder in it
	local key, salt = session_key(file_path, directory, read_file(file_path))
	local noname_content, kept = write_noname_texts(texts, key, file_path .. ".d/")
	storage.noname_content = noname_content
	commit_session(file_path, key, salt, storage, kept)
end

return M
