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
---One entry per window with a triquetra, in window order (tab by tab)
---Example: { [1] = { "a1b2c3d4e5f6g7h8", vim.NIL, {}, "z9y8x7w6v5u4t3s2", {}, {}, "a1b2c3d4e5f6g7h8", false, { ["a1b2c3d4e5f6g7h8"] = 42 } } }
---@class WindowBufferData: table<number, WindowTriquetraSerialised>
---
---Closed buffer history data structure
---Array of the hashes of buffers that were closed and can be reopened, newest last
---Example: { "a1b2c3d4e5f6g7h8", "z9y8x7w6v5u4t3s2" }
---@class ClosedBufferData: Filehash[]
---
---Every saved hash's path is in the session file's paths table, so a hash whose buffer doesn't
---come back still resolves to its file.
---Example: { ["a1b2c3d4e5f6g7h8"] = "/path/to/file.lua" }
---@class PathsData: table<Filehash, string>

local data = require('cavediver.domains.storage.data')
local history = require('cavediver.domains.history')
local historyState = require('cavediver.domains.history.states')
local window = require('cavediver.domains.window')
local configs = require('cavediver.configs')
local crypto = require('cavediver.domains.storage.crypto')

local M = {}


---The clear header at the start of a main file, saying which format it is. The tag covers it.
local HEADER = "CDV1"

---A key's text form, for naming a session's files.
---@param bytes string
---@return string
local function hex(bytes)
	return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

---Read a whole file.
---@param path string
---@return string|nil bytes nil when the file can't be read
local function read_file(path)
	local fh = io.open(path, "rb")
	if not fh then
		return nil
	end
	local bytes = fh:read("*a")
	fh:close()
	return bytes
end

---Write a file atomically: a temporary file in the same directory, synced, then renamed over the
---old one, readable by the user only. A crash leaves the old file or the new one, never half of one.
---@param path string
---@param bytes string
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

---A No Name text's file name. It changes with the text, so an unchanged text keeps its file, and
---through the key it gives nothing of the text away.
---@param key string
---@param filehash Filehash
---@param plaintext string
---@return string
local function scratch_name(key, filehash, plaintext)
	return vim.fn.sha256(hex(key) .. "\n" .. filehash .. "\n" .. plaintext)
end

---Reads a No Name text from its file when it's called. A text whose file fails its check (edited or
---corrupted) is lost on its own, and the rest of the session isn't.
---@param path string
---@param key string
---@param filehash Filehash
---@return fun(): NoNameBufferContent|nil
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

---Whether the path registry knows a hash. Hashes are saved as they are, and the paths behind
---them go into the paths table.
---@param filehash Filehash|nil
---@return boolean
local function is_known(filehash)
	return filehash ~= nil and history.get_filepath_from_hash(filehash) ~= nil
end

---The hash when the path registry knows it, otherwise nil.
---@param filehash Filehash|nil
---@return Filehash|nil
local function known(filehash)
	if is_known(filehash) then
		return filehash
	end
	-- nothing knows this hash (a path is kept while anything references it, so this shouldn't
	-- happen). it's dropped rather than failing the save on cavediver's own data.
	return nil
end

---What a window shows, as a hash: its buffer's when the buffer is registered, otherwise its
---name's, an outsider such as an oil listing or a help file. An untracked buffer with no name
---gives nil.
---@param winid WinId
---@return Filehash|nil filehash
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

---Loads the paths table: hash to path, with the outsiders left out (they only help match windows,
---through what each window shows).
---
---@param paths PathsData
---@param outsiders Filehash[] The hashes in paths that untracked buffers had
---@return table<Filehash, Filepath> paths
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
---Every path the file knows becomes known again, so a reference whose buffer doesn't come back
---still resolves to its file. Every restored buffer the file knows is registered, loaded or not;
---one it doesn't know waits for its BufEnter, like any new buffer. A No Name buffer still open
---from before the load (a reload in the same process) is known by its id. Then restores saved
---buffer access history with original timestamps.
---
---@param buffers BufferCruxInternalsSerialised The global access history
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

---A file the session manager didn't bring back is a closed buffer from then on: its slot keeps it
---and reopens it when used. It goes under what was closed in the session, as the oldest.
---@param filehash Filehash|nil
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
	end
end

---Loads window buffer relationship data.
---
---Restores per-window triquetra relationships (primary/secondary/ternary buffers). Each entry
---records what its window showed, and a restored window takes the first entry, in saved order,
---that showed what it shows, so windows on the same file keep their order. An entry that matches
---no window is dropped, and a window that matches no entry starts fresh.
---
---@param window_buffer WindowBufferData Window relationships, in window order
---@param tabpage integer|nil The tab whose windows are matched, for a tab session; every window otherwise
---@return table<WinId, table<Filehash, number>> window_histories Each matched window's own access history
---@return WinId[] matched The windows that took an entry
local function load_window_buffer_relationships(window_buffer, tabpage)
	local window_histories = {}
	local matched = {}

	-- the entries for each thing a window showed, in saved order
	local unmatched = {}
	for _, triquetra_serialised in ipairs(window_buffer) do
		local shows = triquetra_serialised[7]
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

		if triquetra_serialised[5] ~= nil and triquetra_serialised ~= vim.NIL then
			tdisplacement_map = triquetra_serialised[5]
		end

		if triquetra_serialised[6] ~= nil and triquetra_serialised ~= vim.NIL then
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
		::continue::
	end
	return window_histories, matched
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
---that can be safely serialized to JSON: one entry per window with a triquetra,
---holding hashes, and what the window shows so the load can find it.
---
---@return WindowBufferData compressed Serializable window relationship data
---@param outsiders table<Filehash, string> Filled with the untracked buffers the windows show
---@param tabpage integer|nil Only this tab's windows, for a tab session
local function serialise_window_relationships(outsiders, tabpage)
	local compressed = {}

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
				error("This is impossible. The window triquetra must exist.")
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
			if outsider then
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
			compressed_index = compressed_index + 1
		end
	end
	return compressed
end

---Serialize the paths every saved hash points at.
---
---Everything the path registry knows, closed buffers and No Name names included,
---plus the outsiders.
---
---@return PathsData paths
---@param outsiders table<Filehash, string> The untracked buffers the windows show
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
---merged by when their entries were closed, each pool's own order kept, with one
---copy of a file, the newer.
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
---The closed [No Name] texts, with their filetype and cursor position, and every
---open, non-empty [No Name] buffer's text the same way, marked to be reopened at
---load: no session manager saves its text.
---
---With `owner`, only the texts a pool owns: its closed texts, and the open ones its tabs visited
---(their windows show them or have them in their history); the editor's pool owns those no tab
---session's tab visited.
---
---@param owner Pool|nil
---@return table<Filehash, NoNameBufferContent> texts
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
			if history.routines.pool_of_tab(tabpage).id ~= "" then
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

---Each [No Name] text goes into a file of its own in the session's scratch directory,
---encrypted, and the main file keeps each text's file name. Only a text that changed is
---written; a closed text never read since the load keeps its file.
---
---@param texts table<Filehash, NoNameBufferContent> `reopen` marks a text open at the save
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
			elseif vim.uv.fs_stat(scratch_dir .. name) == nil then
				text = nil -- its file is gone, swept by another editor's save: nothing is left to keep
			end
		end
		if text and text.lines then
			local plaintext = vim.json.encode({ lines = text.lines, filetype = text.filetype, cursor = text.cursor })
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

---The unnamed buffer that is already the No Name buffer saved as `filehash`, when there's one: a
---reopened one carries the hash it came back from, and one never torn down still has its id.
---@param filehash Filehash
---@return Bufnr|nil
local function noname_already_back(filehash)
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(bufnr) == "" then
			local id = vim.b[bufnr].cavediver_noname
			if
				vim.b[bufnr].cavediver_reopened == filehash or
				(id ~= nil and history.routines.get_filehash("NONAME_" .. id) == filehash)
			then
				return bufnr
			end
		end
	end
	return nil
end

---No Name buffers open at the save come back in the background: listed, hidden and modified,
---under a fresh id, and every slot, note and history entry that named them follows. One that is
---already back is taken as it is.
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
				bufnr = vim.api.nvim_create_buf(true, false)
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content.lines)
				vim.bo[bufnr].filetype = content.filetype
				vim.b[bufnr].cavediver_reopened = filehash
				-- the cursor goes back in the window that shows the buffer, once one does.
				local cursor = content.cursor
				vim.api.nvim_create_autocmd("BufWinEnter", {
					buffer = bufnr,
					once = true,
					callback = function()
						pcall(vim.api.nvim_win_set_cursor, 0, cursor)
					end,
				})
			end
			local new_filehash = history.register_buffer(bufnr)
			if new_filehash ~= filehash then
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
---Restores the stack of closed buffer hashes that can be reopened. A closed
---buffer the session manager brought back isn't closed any more, so it stays
---off the stack.
---
---A closed [No Name] text is read from its file only when it's reopened.
---
---@param closed_buffers ClosedBufferData Closed buffer list
---@param noname_content table<Filehash, {scratch: string, reopen: boolean|nil}> Each text's file name
---@param key string The session's key
---@param scratch_dir string The session's scratch directory
---@param times table<Filehash, integer>|nil When each was closed
---@return nil
local function load_closed_buffers(closed_buffers, noname_content, key, scratch_dir, times)
	if load_pool.id == "" then
		history.clear_closed_buffers()
		load_pool = history.routines.pools()[""]
	else
		load_pool.closed, load_pool.times = {}, {}
	end

	-- TODO: Open closed no name buffers with their content.
	if closed_buffers == nil then
		return
	end

	for _, filehash in ipairs(closed_buffers) do
		local filepath = history.get_filepath_from_hash(filehash) -- return: either closed filepath or NONAME_<x>
		if not filepath then
			error("What the fuck. This is impossible.")
		end
		if history.get_buffer_from_hash(filehash) then
			goto continue -- the session manager brought it back
		end
		if filepath:match("^NONAME_") then
			if history.data.noname_content[filehash] == nil or load_pool.id ~= "" then
				local content = noname_content[filehash]
				if content == nil then
					error("This is impossible. Noname content must be created for this closed No Name buffer.")
				end
				local source = scratch_dir .. content.scratch
				history.data.noname_content[filehash] = {
					scratch = content.scratch,
					source = source,
					key = key,
					read = scratch_reader(source, key, filehash),
				}
			else
				error("This is impossible. The closed buffer must not already exist in noname_content.")
			end
		end
		table.insert(load_pool.closed, filehash)
		load_pool.times[filehash] = times and times[filehash] or nil
		::continue::
	end
	-- print_table(history.data.closed_buffers)
end

---Helper function to get the session's file path from its directory and name.
---@param directory string The session's directory
---@param name string|nil The session's name; nil for a nameless save
---@return string project_filepath
local function get_session_filepath(directory, name)
	if not directory then
		error("No directory provided to get_session_filepath")
	end

	-- the separator keeps a session "a" in /proj apart from a nameless save in /proja
	local session_hash = vim.fn.sha256(name and (directory .. "\n" .. name) or directory)

	-- TODO: implement configurable path for session storage
	local session_dir = configs.session_dir
	local project_filepath = session_dir .. session_hash

	vim.fn.mkdir(session_dir, "p")

	return project_filepath
end

---Read and decrypt a session's main file.
---
---@param file_path string
---@param directory string The session's directory, the secret its key is stretched from
---@return table|nil saved_data
---@return string|nil key
---@return string|nil problem "missing", "newer" (a newer format's header), "unencrypted" (the format
---before encryption) or "integrity" (the check failed: edited or corrupted, or not this directory's)
local function read_session_file(file_path, directory)
	local bytes = read_file(file_path)
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
	local key = crypto.derive_key(directory, salt)
	local plaintext = crypto.open(key, bytes:sub(#HEADER + crypto.salt_length + 1), HEADER .. salt)
	local ok, saved_data = pcall(vim.json.decode, plaintext or "")
	if not plaintext or not ok or type(saved_data) ~= "table" then
		return nil, nil, "integrity"
	end
	return saved_data, key, nil
end

---Read a session's saved data, as the load reads it.
---
---@param directory string The session's directory
---@param name string|nil The session's name; nil for a nameless save
---@return table|nil saved_data
---@return string|nil problem See read_session_file
function M.read_session(directory, name)
	local saved_data, _, problem = read_session_file(get_session_filepath(directory, name), directory)
	return saved_data, problem
end

-- the file a load read before it started, so its scope could decide how the storage machine moves
local prepared = nil

---Read a session's file for the load about to run.
---
---@param directory string The session's directory
---@param name string|nil The session's name; nil for a nameless save
---@return boolean tab_session Whether it's a tab session's file
function M.prepare_load(directory, name)
	local saved_data, key, problem = read_session_file(get_session_filepath(directory, name), directory)
	prepared = { directory = directory, name = name, saved_data = saved_data, key = key, problem = problem }
	return saved_data ~= nil and saved_data.scope == "tab"
end

---Whether a session has a file, in that directory under that name.
---
---@param directory string
---@param name string|nil
---@return boolean
function M.session_exists(directory, name)
	return vim.uv.fs_stat(get_session_filepath(directory, name)) ~= nil
end

---A tab session loads into the tab you're in, and nothing else changes: that tab's windows start over
---and take the file's entries, the session's pool comes in with its closed stack and its own visits,
---and the editor's history stays underneath.
---
---@param saved_data table
---@param key string
---@param file_path string
---@param directory string
---@param name string|nil
---@return WinId[] matched
local function load_tab_session(saved_data, key, file_path, directory, name)
	local tabpage = vim.api.nvim_get_current_tabpage()
	for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		if window.data.crux[winid] then
			window.data.unregister_triquetra(winid)
		end
	end
	if data.unnamed == nil and data.editor_session then
		data.unnamed = vim.deepcopy(data.editor_session) -- the whole editor's session, as tab sessions start
	end
	load_pool = history.routines.join_pool(tabpage, name, directory)
	local scratch_dir = file_path .. ".d/"
	load_buffer_history({ global = {} }, load_paths(saved_data.paths, saved_data.outsiders))
	-- its own visits, older than any made from now on
	load_pool.visits = {}
	local latest = 0
	for _, time in pairs(saved_data.buffers.global or {}) do
		latest = math.max(latest, time)
	end
	for filehash, time in pairs(saved_data.buffers.global or {}) do
		load_pool.visits[filehash] = time - latest - 1
	end
	load_closed_buffers(saved_data.closed or {}, saved_data.noname_content or {}, key, scratch_dir, saved_data.closed_times)
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
---@param cwd string the session's directory
---@param name string|nil the session's name; nil for a nameless save
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
	local saved_data, key, problem
	if prepared and prepared.directory == cwd and prepared.name == name then
		saved_data, key, problem = prepared.saved_data, prepared.key, prepared.problem
	else
		saved_data, key, problem = read_session_file(file_path, cwd)
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

	if saved_data and saved_data.scope == "tab" then
		local matched = load_tab_session(saved_data, key, file_path, cwd, name)
		local set_cache_from_window_triquetra = require('cavediver').set_cache_from_window_triquetra
		for _, winid in ipairs(matched) do
			set_cache_from_window_triquetra(winid)
			window.routines.check_notes_under_current(window.data.crux[winid])
		end
	elseif saved_data then
		-- Restore from saved session
		load_pool = history.routines.pools()[""]
		data.editor_session, data.unnamed = { name = name, directory = cwd }, nil
		local scratch_dir = file_path .. ".d/"
		load_buffer_history(saved_data.buffers, load_paths(saved_data.paths, saved_data.outsiders))
		if saved_data.closed then
			load_closed_buffers(saved_data.closed, saved_data.noname_content or {}, key, scratch_dir, saved_data.closed_times)
		end
		local window_histories, matched = load_window_buffer_relationships(saved_data.windows)
		history.routines.initialise_crux_internals({ window = window_histories, global = saved_data.buffers.global })
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
	end
	load_pool = nil

	-- Run cleanup after loading to handle any inconsistencies
	history.cleanup_system()

	history.sm:to(historyState.ATTACHED, { buf = vim.api.nvim_get_current_buf() }, history.states.mode.UPDATE)
	-- print_table(history.data)
	-- print_table(window.data)
end

---Once the restore's batch is over: the window the restore left focused becomes the last valid
---window when it has a triquetra, and the bufferline order is built for it.
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

---The key for a session's file, and its salt. The salt stays from one save to the next, so the
---key does too, and a text that didn't change keeps its file. A file a newer cavediver made isn't
---overwritten.
---
---@param file_path string
---@param directory string The session's directory
---@return string key
---@return string salt
local function session_key(file_path, directory)
	local existing = read_file(file_path) or ""
	if existing:match("^CDV%d") and existing:sub(1, #HEADER) ~= HEADER then
		error("cavediver: this session's file was made by a newer cavediver, so it isn't overwritten: " .. file_path)
	end
	local salt = existing:sub(#HEADER + 1, #HEADER + crypto.salt_length)
	if existing:sub(1, #HEADER) ~= HEADER or #salt ~= crypto.salt_length then
		salt = crypto.random_bytes(crypto.salt_length)
	end
	return crypto.derive_key(directory, salt), salt
end

---Write the main file, the commit point, after the texts it names; then sweep the text files
---nothing references any more, and anything a crash left half-written. A closed No Name buffer
---whose text couldn't be kept leaves the closed stack in the file too, so no load meets a closed
---No Name entry without its text.
---
---@param file_path string
---@param key string
---@param salt string
---@param storage table The session's data
---@param kept table<string, boolean> The text files the main file references
---@return nil
local function commit_session(file_path, key, salt, storage, kept)
	storage.closed = vim.tbl_filter(function(filehash)
		local filepath = storage.paths[filehash]
		return storage.noname_content[filehash] ~= nil or not (filepath and filepath:match("^NONAME_"))
	end, storage.closed or {})
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

---Every pool, the editor's first, for a whole-editor save.
---@return Pool[]
local function every_pool()
	local pools = {}
	for id, pool in pairs(history.routines.pools()) do
		if id ~= "" then
			table.insert(pools, pool)
		end
	end
	table.sort(pools, function(a, b) return a.id < b.id end) -- a fixed order for closes at one time
	table.insert(pools, 1, history.routines.pools()[""])
	return pools
end

---A tab session's file holds only what it references: its windows' slots, queues, notes, histories
---and what they show, its pool's closed entries and visits, and its texts.
---@param storage table The tab session's data, narrowed in place
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

---At a tab-session save, the unnamed session's records are refreshed in its file: its closed stack and
---its No Name texts, from the editor's pool. Its references stay as the session manager last saved them.
---A file that isn't there isn't made, and one that can't be read isn't overwritten.
---@return nil
local function refresh_unnamed()
	local unnamed = data.unnamed
	if unnamed == nil then
		return
	end
	local file_path = get_session_filepath(unnamed.directory, unnamed.name)
	local saved, key, problem = read_session_file(file_path, unnamed.directory)
	if problem == "missing" then
		return
	end
	if not saved or not key or saved.scope == "tab" then
		vim.notify("cavediver: the whole editor's session file couldn't be read, so its closed files and No Name texts weren't refreshed: " .. file_path, vim.log.levels.WARN)
		return
	end
	-- the tab session's own file is written by now, so nothing here may fail its save
	local ok, err = pcall(function()
		local salt = (read_file(file_path) or ""):sub(#HEADER + 1, #HEADER + crypto.salt_length)
		if #salt ~= crypto.salt_length then
			error("its file went away while it was refreshed")
		end
		local editor = history.routines.pools()[""]
		saved.closed, saved.closed_times = serialise_closed_buffers({ editor })
		local noname_content, kept = write_noname_texts(serialise_noname_content(editor), key, file_path .. ".d/")
		saved.noname_content = noname_content
		saved.paths = saved.paths or {}
		for _, filehash in ipairs(saved.closed) do
			saved.paths[filehash] = saved.paths[filehash] or history.get_filepath_from_hash(filehash)
		end
		for filehash, _ in pairs(noname_content) do
			saved.paths[filehash] = saved.paths[filehash] or history.get_filepath_from_hash(filehash)
		end
		commit_session(file_path, key, salt, saved, kept)
	end)
	if not ok then
		vim.notify("cavediver: the whole editor's session file couldn't be written, so its closed files and No Name texts weren't refreshed: " .. tostring(err), vim.log.levels.WARN)
	end
end

---Save complete session history data to persistent storage.
---
---Serializes all buffer history, window relationships, and closed buffers
---into a file named after the session's directory and name, encrypted with a
---key stretched from the directory. Every [No Name] text that changed goes into
---a file of its own first; the main file goes last, so it's the commit point; then
---the text files nothing references any more are swept.
---
---@param cwd string The session's directory to save session data for
---@param name string|nil The session's name; nil for a nameless save
---@param tab integer|nil The tab, for a tab session: only its windows, its pool and its texts, and the tab
---joins that session's pool
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
	end

	local outsiders = {}
	local windows = serialise_window_relationships(outsiders, tab)
	local noname_content, kept = write_noname_texts(serialise_noname_content(pool), key, file_path .. ".d/")
	local closed, closed_times = serialise_closed_buffers(pool and { pool } or every_pool())
	local storage = {
		scope = tab and "tab" or "editor", -- a tab session's file loads into a tab
		paths = serialise_paths(outsiders),
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

	-- Write updated data back to file
	commit_session(file_path, key, salt, storage, kept)
	if pool then
		pool.saved_at = vim.uv.hrtime()
		refresh_unnamed()
	else
		data.editor_session = { name = name, directory = cwd }
	end
end

---Write a session's file from data in the saved shape, as a save writes it. The migration script
---writes the files it converts with this.
---
---@param directory string The session's directory
---@param name string|nil The session's name; nil for a nameless save
---@param storage table `paths`, `outsiders`, `buffers`, `windows` and `closed`, as a save writes them
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
