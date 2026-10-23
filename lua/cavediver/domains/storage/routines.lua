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
---Every saved hash's path is in the session file's paths table, XOR'd with the session's
---directory, so a hash whose buffer doesn't come back still resolves to its file.
---Example: { ["a1b2c3d4e5f6g7h8"] = "<the path, XOR'd and base64-encoded>" }
---@class PathsData: table<Filehash, string>

local data = require('cavediver.domains.storage.data')
local history = require('cavediver.domains.history')
local historyState = require('cavediver.domains.history.states')
local window = require('cavediver.domains.window')
local configs = require('cavediver.configs')

local M = {}


local function repeat_key(key, length)
	if #key >= length then
		return key:sub(1, length)
	end

	local times = math.floor(length / #key)
	local remain = length % #key

	local result = ''

	for i = 1, times do
		result = result .. key
	end

	if remain > 0 then
		result = result .. key:sub(1, remain)
	end

	return result
end

---Create a one-pass xor cipher for text encryption.
---@param text string
---@param key string
---@return string ciphered Base64-encoded XOR result
local function xor_cipher(text, key)
	local rkey = repeat_key(key, #text)

	local result = ''

	for i = 1, #text do
		local k_char = rkey:sub(i, i)
		local m_char = text:sub(i, i)

		local k_byte = k_char:byte()
		local m_byte = m_char:byte()

		local xor_byte = bit.bxor(m_byte, k_byte)

		local xor_char = string.char(xor_byte)

		result = result .. xor_char
	end

	-- Base64 encode the result to make it JSON-safe
	return vim.base64.encode(result)
end

---Create a one-pass xor decipher for text decryption.
---@param encoded_text string Base64-encoded XOR result
---@param key string
---@return string deciphered Original text
local function xor_decipher(encoded_text, key)
	-- Base64 decode first
	local text = vim.base64.decode(encoded_text)
	local rkey = repeat_key(key, #text)

	local result = ''

	for i = 1, #text do
		local k_char = rkey:sub(i, i)
		local m_char = text:sub(i, i)

		local k_byte = k_char:byte()
		local m_byte = m_char:byte()

		local xor_byte = bit.bxor(m_byte, k_byte)

		local xor_char = string.char(xor_byte)

		result = result .. xor_char
	end

	return result
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

---Loads the paths table: hash to path, deciphered, with the outsiders left out (they only help
---match windows, through what each window shows).
---
---@param paths PathsData
---@param outsiders Filehash[] The hashes in paths that untracked buffers had
---@param cwd string The session's directory
---@return table<Filehash, Filepath> paths
local function load_paths(paths, outsiders, cwd)
	local outsider = {}
	for _, filehash in ipairs(outsiders or {}) do
		outsider[filehash] = true
	end
	local loaded = {}
	for filehash, ciphered in pairs(paths) do
		if not outsider[filehash] then
			loaded[filehash] = xor_decipher(ciphered, cwd)
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


---A file the session manager didn't bring back is a closed buffer from then on: its slot keeps it
---and reopens it when used. It goes under what was closed in the session, as the oldest.
---@param filehash Filehash|nil
local function close_if_not_restored(filehash)
	local filepath = filehash and history.get_filepath_from_hash(filehash)
	if
		filepath and
		not filepath:match("^NONAME_") and
		history.get_buffer_from_hash(filehash) == nil and
		not history.filehash_is_closed(filehash)
	then
		table.insert(history.data.closed_buffers, 1, filehash)
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
---@return table<WinId, table<Filehash, number>> window_histories Each matched window's own access history
---@return WinId[] matched The windows that took an entry
local function load_window_buffer_relationships(window_buffer)
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

	for _, actual_winid in pairs(vim.api.nvim_list_wins()) do
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
local function serialise_window_relationships(outsiders)
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
	for _, winid in pairs(vim.api.nvim_list_wins()) do
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
---plus the outsiders, each path XOR'd with the session's directory.
---
---@return PathsData paths
---@param outsiders table<Filehash, string> The untracked buffers the windows show
---@param cwd string The session's directory
local function serialise_paths(outsiders, cwd)
	local paths = {}
	if cwd == nil then
		error("Current working directory is not set.")
	end
	for filehash, filepath in pairs(history.data.hash_filepath_registry.filepaths) do
		paths[filehash] = xor_cipher(filepath, cwd)
	end
	for filehash, name in pairs(outsiders) do
		paths[filehash] = xor_cipher(name, cwd)
	end
	return paths
end

---Serialize closed buffer list for session saving.
---
---Creates a copy of the closed buffer hashes that can be safely
---serialized to JSON. Preserves the stack of reopenable files.
---
---@return ClosedBufferData copy Serializable copy of closed buffer list
local function serialise_closed_buffers()
	local copy = {}
	for _, v in ipairs(history.get_closed_buffers()) do
		if is_known(v) then
			table.insert(copy, v)
		end
	end
	return copy
end

---Serialize [No Name] buffer content for session saving.
---
---Creates a copy of the [No Name] buffer content mapping that can be safely
---serialized to JSON. Preserves content, filetype, and cursor position. An
---open, non-empty [No Name] buffer is saved the way a closed one is, marked to
---be reopened at load: no session manager saves its text.
---
---@return table<Filehash, NoNameBufferContent> copy Serializable copy of [No Name] content
---@param cwd string The session's directory
local function serialise_noname_content(cwd)
	local copy = {}
	if cwd == nil then
		error("Current working directory is not set.")
	end
	for identifier, content in pairs(history.data.noname_content) do
		-- print("identifier: " .. identifier)
		if is_known(identifier) then
			copy[identifier] = {
				lines = vim.tbl_map(function(line) return xor_cipher(line, cwd) end, content.lines),
				filetype = content.filetype,
				cursor = content.cursor
			}
		end
	end
	for filehash, bufnr in pairs(history.data.hash_buffer_registry.buffers) do
		local filepath = history.get_filepath_from_hash(filehash)
		if filepath and filepath:match("^NONAME_") and vim.api.nvim_buf_is_loaded(bufnr) then
			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			if not (#lines == 0 or (#lines == 1 and lines[1] == "")) then -- empty ones are skipped, as when closed
				local winid = vim.fn.bufwinid(bufnr)
				copy[filehash] = {
					lines = vim.tbl_map(function(line) return xor_cipher(line, cwd) end, lines),
					filetype = vim.bo[bufnr].filetype,
					cursor = winid ~= -1 and vim.api.nvim_win_get_cursor(winid) or { 1, 0 },
					reopen = true
				}
			end
		end
	end
	return copy
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
---@param noname_content table<Filehash, NoNameBufferContent> [No Name] content from session
---@param cwd string The session's directory
---@return nil
local function reopen_noname_buffers(noname_content, cwd)
	for filehash, content in pairs(noname_content) do
		local filepath = history.get_filepath_from_hash(filehash)
		if content.reopen and filepath then
			local bufnr = noname_already_back(filehash)
			if bufnr == nil then
				bufnr = vim.api.nvim_create_buf(true, false)
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false,
					vim.tbl_map(function(line) return xor_decipher(line, cwd) end, content.lines))
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
	end
end

---Loads closed buffer history data.
---
---Restores the stack of closed buffer hashes that can be reopened. A closed
---buffer the session manager brought back isn't closed any more, so it stays
---off the stack.
---
---@param closed_buffers ClosedBufferData Closed buffer list
---@param noname_content table<Filehash, NoNameBufferContent> [No Name] content from session
---@param cwd string The session's directory
---@return nil
local function load_closed_buffers(closed_buffers, noname_content, cwd)
	if cwd == nil then
		error("Current working directory is not set.")
	end
	history.clear_closed_buffers()

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
			if history.data.noname_content[filehash] == nil then
				local content = noname_content[filehash]
				if content == nil then
					error("This is impossible. Noname content must be created for this closed No Name buffer.")
				end
				history.data.noname_content[filehash] = {
					lines = vim.tbl_map(function(line) return xor_decipher(line, cwd) end, content.lines),
					filetype = content.filetype,
					cursor = content.cursor
				}
			else
				error("This is impossible. The closed buffer must not already exist in noname_content.")
			end
		end
		table.insert(history.data.closed_buffers, filehash)
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
	local project_filepath = session_dir .. session_hash .. '.json'

	vim.fn.mkdir(session_dir, "p")

	return project_filepath
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

	-- Try to load existing session data
	local saved_data = nil
	if vim.loop.fs_stat(file_path) then
		local success, file_content = pcall(vim.fn.readfile, file_path)
		if success then
			local json_success, json_data = pcall(vim.fn.json_decode, file_content)
			if json_success and json_data then
				if json_data.paths and json_data.buffers and json_data.windows then
					saved_data = json_data
				end
			end
		end
	end

	if saved_data then
		-- Restore from saved session
		load_buffer_history(saved_data.buffers, load_paths(saved_data.paths, saved_data.outsiders, cwd))
		if saved_data.closed then
			load_closed_buffers(saved_data.closed, saved_data.noname_content or {}, cwd)
		end
		local window_histories, matched = load_window_buffer_relationships(saved_data.windows)
		history.routines.initialise_crux_internals({ window = window_histories, global = saved_data.buffers.global })
		reopen_noname_buffers(saved_data.noname_content or {}, cwd)
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
	end

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

---Save complete session history data to persistent storage.
---
---Serializes all buffer history, window relationships, and closed buffers
---to a JSON file named after the session's directory and name.
---
---@param cwd string The session's directory to save session data for
---@param name string|nil The session's name; nil for a nameless save
---@return nil
function M.save_history(cwd, name)
	if not cwd then
		error("Invalid current working directory.")
	end

	-- Run cleanup before saving to ensure clean state
	history.cleanup_system()

	local file_path = get_session_filepath(cwd, name)

	-- Create empty JSON file if it doesn't exist
	---@diagnostic disable-next-line: undefined-field
	if vim.loop.fs_stat(file_path) == nil then
		vim.fn.writefile({ "{}" }, file_path)
	end

	local outsiders = {}
	local windows = serialise_window_relationships(outsiders)
	local storage = {
		paths = serialise_paths(outsiders, cwd),
		outsiders = vim.tbl_keys(outsiders),
		buffers = serialise_buffer_history(),
		windows = windows,
		closed = serialise_closed_buffers(),
		noname_content = serialise_noname_content(cwd),
	}

	-- Write updated data back to file
	local write_success = pcall(vim.fn.writefile, { vim.fn.json_encode(storage) }, file_path)
	if not write_success then
		error("Failed to write session data to file: " .. file_path)
	end
end

return M
