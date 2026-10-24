local data = require("cavediver.domains.history.data")
local configs = require("cavediver.configs")

local M = {}

local function is_no_name_buffer(bufnr)
	local filename = vim.api.nvim_buf_get_name(bufnr)

	return vim.bo[bufnr].buftype == ""  -- Normal buffer (not terminal, help, etc.)
		and (not filename:match("://"))
		and filename == ""              -- No filename set
		and vim.api.nvim_buf_is_loaded(bufnr) -- Buffer is loaded
end

---The name cavediver gives a No Name buffer: NONAME_ and an id kept on the buffer, made of the time and
---a high-resolution clock, so a later session's buffer with the same number doesn't take it over.
---
---@param bufnr Bufnr
---@return string
function M.noname_name(bufnr)
	if vim.b[bufnr].cavediver_noname == nil then
		vim.b[bufnr].cavediver_noname = tostring(os.time()) .. string.format("%.0f", vim.uv.hrtime()) -- digits, however large
	end
	return "NONAME_" .. vim.b[bufnr].cavediver_noname
end

---Generate a file hash from filename for buffer tracking.
---
---Creates a 16-character SHA256 hash prefix from the filename for use as
---a unique identifier in the buffer history system.
---
---@param filename string Full path to the file
---@return string filehash 16-character hash prefix
function M.get_filehash(filename)
	-- with the "\n" a name hashes as `echo "<name>" | sha256sum` does, so saved hashes still match.
	local filehash = string.sub(
		vim.fn.sha256(filename .. "\n"),
		1,
		16
	)
	return filehash
end

---Whether a buffer is `nowrite` on an existing regular file, as image.nvim leaves an image's
---buffer. cavediver tracks those like files.
---
---@param bufnr Bufnr
---@return boolean
function M.is_nowrite_file(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	return vim.bo[bufnr].buftype == "nowrite" and
		name ~= "" and
		vim.fn.filereadable(name) == 1 and
		vim.fn.isdirectory(name) == 0
end

---Whether cavediver tracks a buffer: a listed buffer with buftype "" (or `nowrite` on an
---existing regular file), whose name is empty (a No Name buffer) or a plain path. A plugin's
---scratch or helper buffers are unlisted, so they're left alone.
---
---@param bufnr Bufnr
---@return boolean
function M.is_trackable(bufnr)
	if not vim.bo[bufnr].buflisted or vim.api.nvim_buf_get_name(bufnr):match("://") then
		return false
	end
	return vim.bo[bufnr].buftype == "" or M.is_nowrite_file(bufnr)
end

---Register a buffer in the hash-to-buffer mapping system.
---
---Creates bidirectional mapping between file hash and buffer number for
---efficient buffer lookup and validation.
---
---@param bufnr number Buffer number to register
---@return Filehash filehash
function M.register_buffer(bufnr)
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	if vim.bo[bufnr].buftype ~= "" and not M.is_nowrite_file(bufnr) then
		error("I don't want to track non-file buffers.")
	end
	if filepath == "" then
		filepath = M.noname_name(bufnr)
	end
	local filehash = M.get_filehash(filepath)

	if data.hash_buffer_registry.buffers[filehash] then
		-- print("Oh yes I did.")
		data.hash_buffer_registry.hashes[data.hash_buffer_registry.buffers[filehash]] = nil
	end

	-- skip if for filepath is already registered. It's already one-to-one.

	data.hash_buffer_registry.buffers[filehash] = bufnr
	data.hash_buffer_registry.hashes[bufnr] = filehash
	data.hash_filepath_registry.filepaths[filehash] = filepath
	data.hash_filepath_registry.hashes[filepath] = filehash

	-- print(
	-- 	"Registered buffer: " .. bufnr ..
	-- 	"\n with filehash: " .. filehash ..
	-- 	"\n with filepath: " .. filepath ..
	-- 	"\n with filetype: " .. vim.bo[bufnr].filetype ..
	-- 	"\n" .. debug.traceback()
	-- )

	return filehash
end

---Register a filepath in the hash-to-filepath mapping system.
---
---@param filepath Filepath
---@return nil
function M.register_filepath(filepath)
	if filepath == "" then
		error("Cannot register an empty filepath.")
	end

	local filehash = M.get_filehash(filepath)

	data.hash_filepath_registry.hashes[filepath] = filehash
	data.hash_filepath_registry.filepaths[filehash] = filepath

	-- print("Registered filepath: " .. filepath .. "\n with filehash: " .. filehash)
end

---Unregister a buffer from the regietry
---
---Removes the buffer from the hash-to-buffer mapping system.
---@param bufnr number Buffer number to unregister
function M.unregister_buffer(bufnr)
	local filehash = data.hash_buffer_registry.hashes[bufnr]
	if filehash == nil then return end

	data.hash_buffer_registry.hashes[bufnr] = nil
	data.hash_buffer_registry.buffers[filehash] = nil

	-- print("Unregistered buffer: " .. bufnr .. "\n with filehash: " .. filehash .. "\n" .. debug.traceback())
end

---Whether anything still references this filehash: a slot, a primary queue, a displacement map
---(keys and values), the history or the closed stack.
---
---@param filehash Filehash
---@return boolean
function M.is_filehash_referenced(filehash)
	if data.crux[filehash] or data.crux_internals.global[filehash] then
		return true
	end
	for _, window_crux in pairs(data.crux_internals.window) do
		if window_crux[filehash] then
			return true
		end
	end
	for _, pool in pairs(M.pools()) do
		if pool.visits[filehash] or vim.tbl_contains(pool.closed, filehash) then
			return true
		end
	end
	for _, triquetra in pairs(require('cavediver.domains.window.data').crux) do
		if
			triquetra.current_slot == filehash or
			triquetra.secondary_slot == filehash or
			triquetra.ternary_slot == filehash or
			vim.tbl_contains(triquetra.primary_buffer or {}, filehash)
		then
			return true
		end
		for _, map in ipairs({ triquetra.displacement_ternary_map, triquetra.displacement_secondary_map }) do
			for key, value in pairs(map or {}) do
				if value == filehash or key == filehash or key == filehash .. "-swap" then
					return true
				end
			end
		end
	end
	return false
end

---Whether cavediver still knows a hash: an open buffer, a slot or a primary queue holds it, or the
---closed stack does. Notes and history never keep a hash known; they follow along.
---
---@param filehash Filehash
---@return boolean
function M.is_filehash_known(filehash)
	return M.known_filehashes()[filehash] == true
end

---Every hash cavediver still knows, as a set, built once for a pass over many hashes.
---
---@return table<Filehash, boolean>
function M.known_filehashes()
	local known = {}
	for filehash, _ in pairs(data.hash_buffer_registry.buffers) do
		known[filehash] = true
	end
	for _, pool in pairs(M.pools()) do
		for _, filehash in ipairs(pool.closed) do
			known[filehash] = true
		end
	end
	for _, triquetra in pairs(require('cavediver.domains.window.data').crux) do
		for _, filehash in pairs({ triquetra.current_slot, triquetra.secondary_slot, triquetra.ternary_slot }) do
			known[filehash] = true
		end
		for _, filehash in ipairs(triquetra.primary_buffer or {}) do
			known[filehash] = true
		end
	end
	return known
end

---The editor's pool. It holds closed_buffers itself, whatever replaced that table last.
---
---@return Pool
local function editor_pool()
	local pool = data.pools[""]
	if pool == nil or not rawequal(pool.closed, data.closed_buffers) then
		pool = { id = "", closed = data.closed_buffers, times = {}, visits = {}, tabs = {} }
		data.pools[""] = pool
	end
	return pool
end

---Told when a pool's records (its closed list, its close times) change, with the pool's id; the
---storage domain writes them.
---@type fun(id: string)|nil
M.on_records_change = nil

---A pool's records changed.
---@param pool Pool
local function changed(pool)
	pool.changed_at = vim.uv.hrtime()
	if M.on_records_change then
		M.on_records_change(pool.id)
	end
end
M.pool_changed = changed

---A list's name, as the closed lists and the trail show it: "editor", or its session's.
---
---@param pool Pool
---@return string
function M.list_name(pool)
	return pool.id == "" and "editor" or (pool.name or vim.fn.fnamemodify(pool.directory or "", ":t"))
end

---The names of some lists, the tab's own first, and the others' apart.
---
---@param pools table<Pool, boolean>
---@return string[] names
---@return string[] others the lists other than the tab's
local function named_lists(pools)
	local here = M.current_pool()
	local others = {}
	for pool, _ in pairs(pools) do
		if pool ~= here then
			table.insert(others, M.list_name(pool))
		end
	end
	table.sort(others)
	local names = vim.list_extend(pools[here] and { M.list_name(here) } or {}, others)
	return names, others
end

---The id of a tab session's pool.
---@param name string|nil
---@param directory string
---@return string
function M.pool_id(name, directory)
	return (name or "") .. "\n" .. directory
end

---Every pool, the editor's included.
---
---@return table<string, Pool>
function M.pools()
	editor_pool()
	return data.pools
end

---Back to the editor's pool alone, as at startup.
function M.reset_pools()
	data.pools = {}
	data.tab_pools = {}
	data.came_from = {}
	editor_pool()
end

---The pool a tab belongs to: its tab session's, or the editor's.
---
---@param tabpage integer
---@return Pool
function M.pool_of_tab(tabpage)
	local id = data.tab_pools[tabpage]
	return id and data.pools[id] or editor_pool()
end

---The pool of the tab you're in.
---
---@return Pool
function M.current_pool()
	return M.pool_of_tab(vim.api.nvim_get_current_tabpage())
end

---A tab session's pool, made when it's first needed, with the tab joining it.
---
---@param tabpage integer
---@param name string|nil
---@param directory string
---@return Pool
function M.join_pool(tabpage, name, directory)
	local id = M.pool_id(name, directory)
	local pool = data.pools[id]
	if pool == nil then
		pool = { id = id, name = name, directory = directory, closed = {}, times = {}, visits = {}, tabs = {} }
		data.pools[id] = pool
	end
	local previous = data.tab_pools[tabpage]
	if previous and previous ~= id and data.pools[previous] then
		data.pools[previous].tabs[tabpage] = nil
	end
	data.tab_pools[tabpage] = id
	pool.tabs[tabpage] = true
	return pool
end

---Now, to the microsecond, so closes within one second still have an order.
---@return number
local function close_time()
	local seconds, microseconds = vim.uv.gettimeofday()
	return seconds + microseconds / 1e6
end

---Put a file on a pool's closed stack as its newest entry, one copy per pool.
---
---@param pool Pool
---@param filehash Filehash
---@param time integer|nil When it was closed; now when nil
local function push_closed(pool, filehash, time)
	for i = #pool.closed, 1, -1 do
		if pool.closed[i] == filehash then
			table.remove(pool.closed, i)
		end
	end
	table.insert(pool.closed, filehash)
	pool.times[filehash] = time or close_time()
	changed(pool)
end

---The tabs that visited a file: their windows show it or have it in their history.
---
---@param filehash Filehash
---@return table<integer, boolean> tabpages
function M.tabs_that_visited(filehash)
	local tabpages = {}
	for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
		for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
			local window_crux = data.crux_internals.window[winid]
			if
				(window_crux and window_crux[filehash]) or
				data.hash_buffer_registry.hashes[vim.api.nvim_win_get_buf(winid)] == filehash
			then
				tabpages[tabpage] = true
				break
			end
		end
	end
	return tabpages
end

---Close a file into its pools: the pool of the tab it's closed in, every pool it came out of when it
---was opened again, and the pool of every tab whose windows show it or have it in their history.
---The trail gets the close, and a close onto lists other than the tab's is said too.
---
---@param filehash Filehash
---@param quiet boolean|nil The caller records the close itself
---@return table<Pool, boolean> pools the pools it went on
function M.close_into_pools(filehash, quiet)
	local time = close_time()
	local targets = { [M.current_pool()] = true }
	for id, _ in pairs(data.came_from[filehash] or {}) do
		if data.pools[id] then
			targets[data.pools[id]] = true
		end
	end
	data.came_from[filehash] = nil
	for tabpage, _ in pairs(M.tabs_that_visited(filehash)) do
		targets[M.pool_of_tab(tabpage)] = true
	end
	for pool, _ in pairs(targets) do
		push_closed(pool, filehash, time)
	end
	if not quiet then
		local ledger = require('cavediver.domains.ledger')
		local name = ledger.name_of(filehash) or filehash
		local lists, others = named_lists(targets)
		ledger.move("closed", { subject = filehash, name = name, lists = lists, dim = #others == 0 })
		if #others > 0 then
			ledger.tell("closed", name, others)
		end
	end
	return targets
end

---A file open again is closed nowhere: it leaves every pool, and the pools it left are remembered for
---its next close.
---
---@param filehash Filehash
function M.open_out_of_pools(filehash)
	local left = {}
	for id, pool in pairs(M.pools()) do
		for i = #pool.closed, 1, -1 do
			if pool.closed[i] == filehash then
				table.remove(pool.closed, i)
				pool.times[filehash] = nil
				changed(pool)
				data.came_from[filehash] = data.came_from[filehash] or {}
				data.came_from[filehash][id] = true
				left[pool] = true
			end
		end
	end
	-- the trail gets the reopen, and one off lists other than the tab's is said too
	if next(left) then
		local ledger = require('cavediver.domains.ledger')
		local name = ledger.name_of(filehash) or filehash
		local lists, others = named_lists(left)
		ledger.move("reopened", { subject = filehash, name = name, lists = lists, dim = #others == 0 })
		if #others > 0 then
			ledger.tell("reopened", name, others)
		end
	end
end

---Take a hash off every pool, remembering nothing: it's gone, not opened again.
---
---@param filehash Filehash
function M.discard_from_pools(filehash)
	for _, pool in pairs(M.pools()) do
		for i = #pool.closed, 1, -1 do
			if pool.closed[i] == filehash then
				table.remove(pool.closed, i)
				pool.times[filehash] = nil
				changed(pool)
			end
		end
	end
	data.came_from[filehash] = nil
end

---A file closed on one pool goes on another too, under that pool's own entries, with its close time.
---
---@param from Pool
---@param to Pool
---@param filehash Filehash|nil
function M.carry_closed(from, to, filehash)
	if filehash == nil or not vim.tbl_contains(from.closed, filehash) or vim.tbl_contains(to.closed, filehash) then
		return
	end
	table.insert(to.closed, 1, filehash)
	to.times[filehash] = from.times[filehash]
	changed(to)
end

---The git directory for the session's directory, found upward from it. A `.git` file, as a
---worktree has, points to it.
---
---@return string|nil git_dir
function M.git_dir()
	local found = vim.fs.find(".git", { upward = true, path = vim.fn.getcwd(-1, -1) })[1]
	if not found then
		return nil
	end
	if vim.fn.isdirectory(found) == 1 then
		return found
	end
	local ok, lines = pcall(vim.fn.readfile, found, "", 1)
	local gitdir = ok and lines[1] and lines[1]:match("^gitdir:%s*(.-)%s*$")
	if not gitdir then
		return nil
	end
	if not gitdir:match("^/") then
		gitdir = vim.fn.fnamemodify(found, ":h") .. "/" .. gitdir
	end
	return gitdir
end

---The label from git's HEAD, read as a file: the branch, or the first 7 hex characters of a
---detached HEAD.
---
---@return string|nil label
function M.git_label()
	local git_dir = M.git_dir()
	if not git_dir then
		return nil
	end
	local ok, lines = pcall(vim.fn.readfile, git_dir .. "/HEAD", "", 1)
	local head = ok and lines[1] or nil
	if not head then
		return nil
	end
	return head:match("^ref:%s*refs/heads/(.+)$") or head:match("^ref:%s*(.+)$") or head:match("^(%x%x%x%x%x%x%x)")
end

---Where you are right now, as the label provider in config says: a git branch, by default.
---
---@return string|nil label nil when there's no label
function M.current_label()
	local provider = require('cavediver.configs').label_provider
	if provider == false then
		return nil
	elseif type(provider) == "function" then
		local ok, label = pcall(provider)
		return ok and type(label) == "string" and label or nil
	end
	return M.git_label()
end

-- files checked for being gone from disk per cleanup tick, besides the ones on screen
local mark_slice = 500
local mark_queue, mark_next = {}, 1

---Mark the known files that are gone from disk, each tagged with where you were when it went
---missing (or the time, with no label), and clear the marks of files that are back.
---
---@param label string|nil The label the files went missing under
---@param limit integer|nil At most this many files are checked, carrying on from where the last such
---pass stopped, besides the open buffers and the slots, which are always checked; nil checks every one
---@return nil
function M.mark_missing(label, limit)
	local known = M.known_filehashes()
	local filepaths = data.hash_filepath_registry.filepaths
	local function mark(filehash)
		local filepath = filepaths[filehash]
		if not filepath or not known[filehash] or filepath:match("^NONAME_") then
			return
		end
		if vim.fn.filereadable(filepath) == 1 then
			if data.missing[filehash] ~= nil then
				require('cavediver.domains.ledger').move("back", { subject = filehash,
					name = require('cavediver.domains.ledger').name_of(filehash), words = "back on disk" })
			end
			data.missing[filehash] = nil
			data.unwritten[filehash] = nil
		elseif data.unwritten[filehash] then
			return -- never written, so it didn't go missing
		elseif data.missing[filehash] == nil then
			data.missing[filehash] = label or os.date("%H:%M")
			require('cavediver.domains.ledger').move("gone", { subject = filehash,
				name = require('cavediver.domains.ledger').name_of(filehash), words = "gone from disk ⎇" .. data.missing[filehash] })
		end
	end
	if limit then
		-- what the winbar and the bufferline show, every time
		for filehash, _ in pairs(data.hash_buffer_registry.buffers) do
			mark(filehash)
		end
		for _, triquetra in pairs(require('cavediver.domains.window.data').crux) do
			mark(triquetra.current_slot)
			mark(triquetra.secondary_slot)
			mark(triquetra.ternary_slot)
			for _, filehash in ipairs(triquetra.primary_buffer or {}) do
				mark(filehash)
			end
		end
		-- the rest a slice at a time, going round
		local wrapped = false
		for _ = 1, limit do
			if mark_next > #mark_queue then
				if wrapped then
					break
				end
				mark_queue, mark_next, wrapped = vim.tbl_keys(filepaths), 1, true
				if #mark_queue == 0 then
					break
				end
			end
			mark(mark_queue[mark_next])
			mark_next = mark_next + 1
		end
	else
		for filehash, _ in pairs(filepaths) do
			mark(filehash)
		end
	end
	for filehash, _ in pairs(data.missing) do
		if not known[filehash] then
			data.missing[filehash] = nil
		end
	end
	for filehash, _ in pairs(data.unwritten) do
		if not known[filehash] then
			data.unwritten[filehash] = nil
		end
	end
end

local head_watch, head_watch_dir
-- the watch runs only between setup() and disable()
local head_watch_on = false

---Stop watching git's HEAD.
function M.stop_head_watch()
	if head_watch then
		head_watch:stop()
		head_watch:close()
	end
	head_watch, head_watch_dir = nil, nil
end

---Let git's HEAD be watched, or stop watching it for good: setup() lets it, disable() stops it.
---
---@param on boolean
function M.enable_head_watch(on)
	head_watch_on = on
	if not on then
		M.stop_head_watch()
	end
end

---Watch git's HEAD, so a branch switch is seen when it happens. The git directory is watched, not
---the file, since git replaces HEAD by renaming a new one over it.
---
---@param git_dir string|nil
local function watch_head(git_dir)
	if git_dir == head_watch_dir then
		return
	end
	M.stop_head_watch()
	if not git_dir then
		return
	end
	head_watch = vim.uv.new_fs_event()
	if not head_watch then
		return
	end
	head_watch:start(git_dir, {}, vim.schedule_wrap(function(err, filename)
		if not err and filename == "HEAD" then
			M.refresh_label()
		end
	end))
	head_watch_dir = git_dir
end

---Read the label again. When it changed, the files that went missing with the change are tagged
---with the label being left. The first label seen only starts the record.
---
---@return boolean checked Whether every known file was just checked, for a change of label
function M.refresh_label()
	if require('cavediver.configs').label_provider == nil and head_watch_on then
		watch_head(M.git_dir())
	else
		M.stop_head_watch()
	end
	local label = M.current_label()
	local checked = false
	if not data.label_seen then
		data.label_seen = true
	elseif label ~= data.last_label then
		-- a change of label is a step of its own, the files it finds gone tagged under it
		require('cavediver.domains.ledger').within("label", (data.last_label or "—") .. " → " .. (label or "—"),
			M.mark_missing, data.last_label)
		checked = true
	end
	data.last_label = label
	return checked
end

---Follow along: a note or a history entry goes once what it points at is no longer known, and then
---the path of a hash nothing references any more is forgotten.
---
---@param known_set table<Filehash, boolean>|nil The known hashes, when a caller has them already
---@return integer forgotten How many hashes went
function M.follow_along(known_set)
	known_set = known_set or M.known_filehashes()
	local unknown, notes = {}, {}
	local function known(filehash)
		if not known_set[filehash] then
			unknown[filehash] = true
		end
		return known_set[filehash] == true
	end
	for _, triquetra in pairs(require('cavediver.domains.window.data').crux) do
		for _, map in ipairs({ triquetra.displacement_ternary_map or {}, triquetra.displacement_secondary_map or {} }) do
			for key, value in pairs(map) do
				local base = key:gsub("%-swap$", "")
				local key_known, value_known = known(base), known(value)
				if not key_known or not value_known then
					map[key] = nil
					local gone = not key_known and base or value
					notes[gone] = (notes[gone] or 0) + 1
				end
			end
		end
	end
	local histories = { data.crux, data.crux_internals.global }
	for _, window_crux in pairs(data.crux_internals.window) do
		table.insert(histories, window_crux)
	end
	for _, pool in pairs(M.pools()) do
		table.insert(histories, pool.visits)
	end
	for _, history in ipairs(histories) do
		for filehash, _ in pairs(history) do
			if not known(filehash) then
				history[filehash] = nil
			end
		end
	end
	local forgotten = 0
	local ledger = require('cavediver.domains.ledger')
	for filehash, is_unknown in pairs(unknown) do
		local filepath = data.hash_filepath_registry.filepaths[filehash]
		if is_unknown and filepath then
			local name = ledger.name_of(filehash)
			M.unregister_filepath(filepath)
			if data.hash_filepath_registry.filepaths[filehash] == nil then
				forgotten = forgotten + 1
				-- the trail gets what's forgotten, with the notes about it that went
				ledger.move("forgotten", { subject = filehash, name = name, notes = notes[filehash] or 0,
					words = "nothing holds it any more" })
			elseif notes[filehash] then
				ledger.move("note_dropped", { subject = filehash, name = name, notes = notes[filehash],
					words = "notes naming it dropped: nothing holds it any more" })
			end
		end
	end
	return forgotten
end

---unregister a filepath from the registry. A path is never forgotten while anything references its
---hash, so a referenced one stays.
---@param filepath Filepath
function M.unregister_filepath(filepath)
	local filehash = data.hash_filepath_registry.hashes[filepath]

	if filehash == nil then return end
	if M.is_filehash_referenced(filehash) then return end

	data.hash_filepath_registry.hashes[filepath] = nil
	data.hash_filepath_registry.filepaths[filehash] = nil

	-- print("Unregistered filepath: " .. filepath .. "\n with filehash: " .. filehash .. "\n" .. debug.traceback())
end

---Make sure a window has its history entry. Every triquetra comes with one, wherever it's made.
---@param winid WinId
function M.ensure_window_entry(winid)
	if data.crux_internals.window[winid] == nil then
		data.crux_internals.window[winid] = {}
	end
end

---unregister a window from the itnernal crux
---@param winid WinId
function M.unregister_window(winid) 
	data.crux_internals.window[winid] = nil
end

local previous_window_constructed = nil

---Initialize the history crux and internal crux structures.
---
---@param crux_internals BufferCruxInternals The global history, and each window's own history by window id
---@return nil
function M.initialise_crux_internals(crux_internals)
	data.crux_internals.window = {}

	-- each window's history was matched to it along with its triquetra
	for winid, window_crux_serialised in pairs(crux_internals.window) do
		data.crux_internals.window[winid] = window_crux_serialised
	end
	data.crux_internals.global = crux_internals.global
	-- windows the file had no history for still get their entry, every triquetra comes with one.
	for winid, _ in pairs(require('cavediver.domains.window').data.crux) do
		M.ensure_window_entry(winid)
	end
	local cwin = require('cavediver.domains.window').data.last_valid_window
	M.construct_crux(cwin)
	previous_window_constructed = cwin
	-- the window the restore leaves focused gets its view once the restore settles (the storage
	-- domain's after_restore).
end

---Construct the crux from the internal cruxes, from the global and
---a window specific crux, if winid is provided. Otherwise it will
---construct the crux with only the global crux.
---
---This function merges the global crux with the window-specific crux
---
---@param winid WinId|nil
function M.construct_crux(winid)
	local global_copy = vim.fn.deepcopy(data.crux_internals.global)

	if previous_window_constructed == winid then
		return
	else
		previous_window_constructed = winid
	end

	-- in a tab session's tab, the session's own visits rank above the editor's history, in either view
	local pool = winid and vim.api.nvim_win_is_valid(winid) and M.pool_of_tab(vim.api.nvim_win_get_tabpage(winid))
	if pool and pool.id ~= "" and next(pool.visits) then
		local visits = {}
		for hash, time in pairs(pool.visits) do
			table.insert(visits, { hash = hash, time = time })
		end
		table.sort(visits, function(a, b) return a.time > b.time end)
		data.history_index = data.history_index + #visits
		for rank, visit in ipairs(visits) do
			global_copy[visit.hash] = data.history_index - rank
		end
	end

	if not winid or configs.bufferline.history_view == "global" then
		data.crux = global_copy
		return
	end

	if data.crux_internals.window[winid] == nil or next(data.crux_internals.window[winid]) == nil then
		data.crux_internals.window[winid] = {}
		data.crux = global_copy
		return
	end

	local window_buffers = {}
	for key, value in pairs(data.crux_internals.window[winid]) do
		table.insert(window_buffers, { hash = key, time = value })
	end
	table.sort(window_buffers, function(a, b) return a.time > b.time end)

	-- the window's n buffers take the n fresh times, and the next free one is after them, so the next
	-- buffer recorded ranks strictly first instead of tying with this window's newest.
	data.history_index = data.history_index + #window_buffers
	-- Assign increments based on rank
	for rank, buffer in ipairs(window_buffers) do
		global_copy[buffer.hash] = data.history_index - rank
	end

	data.crux = global_copy
end

---Track buffer access in the history timeline.
---
---Adds or updates buffer access time in the history crux. If no time is provided,
---uses current history index and increments it. Used for both new access tracking
---and restoring saved session data.
---
---@param filehash Filehash File hash of the buffer to track
---@param time number|nil Access time index (nil = use current index)
function M.track_buffer(filehash, time)
	if time == nil then
		data.crux[filehash] = data.history_index
		data.crux_internals.global[filehash] = data.history_index
		data.history_index = data.history_index + 1
	else
		data.crux[filehash] = time
		data.crux_internals.global[filehash] = time
		if data.history_index <= time then
			data.history_index = time + 1
		end
	end

	-- the visit goes to the window it happens in (an arrival runs in its own window), not the focused one.
	local winid = vim.api.nvim_get_current_win()
	if not require("cavediver.domains.window").get_triquetra(winid) then
		winid = require("cavediver.domains.navigation.routines").find_most_recent_tracked_window()
	end
	if winid then
		if data.crux_internals.window[winid] == nil then
			data.crux_internals.window[winid] = {}
		end
		data.crux_internals.window[winid][filehash] = data.history_index - 1
	end

	-- open again, it's closed nowhere: it leaves every pool, which remember it for its next close.
	M.open_out_of_pools(filehash)
	-- a visit in a tab session's tab is the session's own too.
	local pool = M.pool_of_tab(winid and vim.api.nvim_win_get_tabpage(winid) or vim.api.nvim_get_current_tabpage())
	if time == nil and pool.id ~= "" then
		pool.visits[filehash] = data.history_index - 1
		pool.changed_at = vim.uv.hrtime()
	end
end

---Untrack the buffer access in the history crux.
---
---Removes the buffer from the history crux, effectively
---@param bufnr Bufnr File hash of the buffer to untrack
function M.untrack_buffer(bufnr)
	local filehash = data.hash_buffer_registry.hashes[bufnr]
	if data.crux[filehash] ~= nil then
		data.crux[filehash] = nil
	end

	if data.crux_internals.global[filehash] ~= nil then
		data.crux_internals.global[filehash] = nil
	end

	for winid, _ in pairs(data.crux_internals.window) do
		if filehash ~= nil then
			data.crux_internals.window[winid][filehash] = nil
		end
	end

	M.update_buffer_history_ordered()
	M.update_buffer_history_ordered_nonharpooned()
end

---Update buffer history with the current access time for regular file buffers.
---
---Records buffer access in the history system if it's a valid file buffer.
---Only tracks buffers that pass `M.is_trackable()`.
---
---@param cbufnr number|nil Buffer number (defaults to current buffer)
---@return boolean history_modified True if the buffer was successfully registered and tracked
function M.update_buffer_history(cbufnr)
	cbufnr = cbufnr or vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(cbufnr)

	-- Check if the buffer is a "normal" file buffer
	---@type Filehash
	local filehash = data.hash_buffer_registry.hashes[cbufnr]
	if filehash == nil then
		if M.is_trackable(cbufnr) then
			filehash = M.register_buffer(cbufnr)
		else
			return false
		end
	else
		if is_no_name_buffer(cbufnr) then
			filehash = M.get_filehash(M.noname_name(cbufnr))
		elseif
			vim.fn.isdirectory(filename) == 0 and
			(
				vim.fn.filereadable(filename) == 1 or
				-- a missing file says nothing, it's not written yet or it's gone for now.
				(vim.bo[cbufnr].buftype == "" and not filename:match("://"))
			)
		then
			filehash = M.get_filehash(filename)
		else
			M.untrack_buffer(cbufnr)
			M.unregister_buffer(cbufnr) -- clean this up. this buffer evolved into something we don't like.
			M.unregister_filepath(filename)
			return false
		end
	end

	M.track_buffer(filehash, nil)
	return true
end

---Update ordered buffer history list sorted by recency.
---
---Rebuilds the ordered buffer list from the current history crux.
---Validates buffer hash mappings and removes invalid entries.
---
---@return BufferHistoryItem[] ordered Buffers ordered by recency (most recent first)
function M.update_buffer_history_ordered()
	data.ordered.crux = {}
	for filehash, access_time in pairs(data.crux) do
		-- print_table(filehash_to_bufnr)
		if not data.hash_buffer_registry.buffers[filehash] then
			data.crux[filehash] = nil -- Remove invalid buffer from history
			goto continue
		end
		table.insert(
			data.ordered.crux,
			{ buf = data.hash_buffer_registry.buffers[filehash], time = access_time }
		)
		::continue::
	end
	table.sort(data.ordered.crux, function(a, b)
		return a.time > b.time
	end)
	return data.ordered.crux
end

---The marked files, in their order, as full paths: config's `marks_provider`, a function giving their
---paths; with none set, harpoon's list when harpoon is installed; `false` marks nothing.
---
---@return string[]
function M.marked_paths()
	local provider = require('cavediver.configs').marks_provider
	local list = {}
	if type(provider) == "function" then
		local ok, result = pcall(provider)
		list = ok and type(result) == "table" and result or {}
	elseif provider == nil then
		local ok, harpoon = pcall(require, "harpoon")
		if ok then
			local listed, result = pcall(function() return harpoon:list():display() end)
			list = listed and type(result) == "table" and result or {}
		end
	end
	local paths = {}
	for _, path in ipairs(list) do
		if type(path) == "string" then
			table.insert(paths, vim.fn.fnamemodify(path, ":p"))
		end
	end
	return paths
end

---Check if a bufnr is harpooned mark.
---
---@param bufnr Bufnr
---@return boolean
local function is_harpooned(bufnr)
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		return vim.tbl_contains(
			M.marked_paths(),
			vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p")
		)
	else
		return false
	end
end

---Update ordered non-harpooned buffer history list.
---
---Rebuilds the non-harpooned buffer list by filtering out harpooned buffers
---from the main ordered list. Updates the harpooned buffer count.
---
---@return BufferHistoryItem[] ordered Non-harpooned buffers ordered by recency
function M.update_buffer_history_ordered_nonharpooned()
	data.ordered.nonharpooned = {}
	for _, item in pairs(data.ordered.crux) do
		-- print_table(item)
		-- Only consider buffers that are valid and loaded
		if not is_harpooned(item.buf) then
			table.insert(
				data.ordered.nonharpooned,
				{ buf = item.buf, time = item.time }
			)
		end
	end
	table.sort(data.ordered.nonharpooned, function(a, b)
		return a.time > b.time
	end)
	return data.ordered.nonharpooned
end

---Mark the window's triquetra as the cycle's checkpoint. The checkpoint is the window's own triquetra,
---not a copy, so it always names the window's current slot.
---
---@param winid number Window ID to snapshot
function M.snapshot_origin(winid)
	-- window's data.crux[winid] is ensured to be non-nil.
	local get_smart_basename = require('cavediver.domains.ui.routines').get_smart_basename
	data.cycling_origins[winid] = require('cavediver.domains.window').get_triquetra(winid)

	local current_slot = data.hash_buffer_registry.hashes[vim.api.nvim_win_get_buf(winid)] or data.cycling_origins[winid].current_slot
	local secondary_slot = data.cycling_origins[winid].secondary_slot
	local sslot_display_string

	if current_slot == nil then
		error("This is impossible: current buffer is not registered.")
	end

	if secondary_slot == nil then
		sslot_display_string = "Unfilled"
	else
		sslot_display_string = get_smart_basename(secondary_slot)
	end

	data.cycling_origins[winid].current_slot = current_slot

	vim.notify(
		"Checkpoint saved: \n" ..
		get_smart_basename(current_slot) ..
		" -> " ..
		sslot_display_string
	)
end

---Reopen a filepath derived from a file hash. The file hash
---must be registered during this session.
---
---@param filehash Filehash
---@return Bufnr|nil bufnr Buffer number if hash is registered, nil if not found
function M.reopen_filehash(filehash)
	local filepath = data.hash_filepath_registry.filepaths[filehash]
	if filepath == nil then
		return nil
	end
	if not filepath:match("^NONAME_") and vim.fn.filereadable(filepath) ~= 1 then
		return nil -- a file gone from disk keeps its place on the closed stack: it may come back
	end

	M.open_out_of_pools(filehash)
	local bufnr
	if filepath:match("^NONAME_") then
		local cache = data.noname_content[filehash]
		if cache and cache.lines == nil and cache.read then
			cache = cache.read() -- a text from the session file is read only when it's reopened
		end
		if cache == nil then
			return nil -- a No Name buffer with nothing cached (it was empty) can't be brought back.
		end
		bufnr = vim.api.nvim_create_buf(true, false)

		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, cache.lines)
		vim.bo[bufnr].filetype = cache.filetype
		vim.bo[bufnr].buftype = ""
		-- the cursor goes back in the window that shows the buffer, once one does.
		local cursor = cache.cursor
		vim.api.nvim_create_autocmd("BufWinEnter", {
			buffer = bufnr,
			once = true,
			callback = function()
				pcall(vim.api.nvim_win_set_cursor, 0, cursor)
			end,
		})
		data.noname_content[filehash] = nil
		local old_filehash = filehash
		filehash = M.register_buffer(bufnr)
		M.track_buffer(filehash)
		if filehash ~= old_filehash then
			-- it comes back under a new name, and everything that named the old one follows: slots, notes
			-- and history.
			require('cavediver.domains.window.data').rename_hash_in_triquetras(old_filehash, filehash)
			M.rename_hash_in_history(old_filehash, filehash)
			data.came_from[filehash], data.came_from[old_filehash] = data.came_from[old_filehash], nil
		end
		if M.get_filepath_from_buffer(bufnr) ~= filepath then
			M.unregister_filepath(filepath) -- This NONAME_ buffer is now irrelevant, we don't want to track it anymore.
		end
	elseif filepath and vim.fn.filereadable(filepath) == 1 then
		bufnr = vim.fn.bufadd(filepath)
		vim.bo[bufnr].buflisted = true -- listed before bufload, whose BufEnter only tracks listed buffers.
		vim.fn.bufload(bufnr)
		M.register_buffer(bufnr)
		M.track_buffer(filehash)
	end

	if bufnr then
		M.update_buffer_history(bufnr)
		M.update_buffer_history_ordered()
		M.update_buffer_history_ordered_nonharpooned()
		return bufnr
	else
		return nil
	end
end

---Carry a hash's history to a new hash, as a reopened No Name buffer takes a new name: its visits,
---overall and in each window. A visit the new hash has already, being newer, stays.
---
---@param old_hash Filehash
---@param new_hash Filehash
function M.rename_hash_in_history(old_hash, new_hash)
	local cruxes = { data.crux, data.crux_internals.global }
	for _, window_crux in pairs(data.crux_internals.window) do
		table.insert(cruxes, window_crux)
	end
	for _, pool in pairs(M.pools()) do
		table.insert(cruxes, pool.visits)
	end
	for _, crux in ipairs(cruxes) do
		if crux[old_hash] ~= nil then
			crux[new_hash] = crux[new_hash] or crux[old_hash]
			crux[old_hash] = nil
		end
	end
end

---A hash's visits, overall and in each window, kept so that a rename which turns out to be a move can
---hand them to the new name: the delete a rename starts with untracks them.
---
---@param hash Filehash
---@return { crux: integer|nil, global: integer|nil, windows: table<WinId, integer> }
function M.history_of(hash)
	local windows = {}
	for winid, window_crux in pairs(data.crux_internals.window) do
		windows[winid] = window_crux[hash]
	end
	return { crux = data.crux[hash], global = data.crux_internals.global[hash], windows = windows }
end

---Decide a rename once the command that made it is over: the disk decides. If the old name is still a
---file, it was a copy (the caller closes the old name). If it isn't, or never was (a No Name buffer), it
---was a move: the buffer, and every slot, note and history entry that named the old hash, follow to the
---new name, and nothing stays on the closed stack.
---
---@param bufnr Bufnr The renamed buffer
---@param old_hash Filehash Its hash before the rename
---@param old_history table|nil Its history, when a delete untracked it before the rename settled
---@return string|nil moved_from The old name, when it was a move
function M.settle_rename(bufnr, old_hash, old_history)
	local old_path = data.hash_filepath_registry.filepaths[old_hash]
	if
		old_path == nil or
		not M.is_trackable(bufnr) or
		(not old_path:match("^NONAME_") and vim.fn.filereadable(old_path) == 1)
	then
		return nil
	end
	local new_hash = M.get_filehash(vim.api.nvim_buf_get_name(bufnr))
	M.discard_from_pools(old_hash)
	data.noname_content[old_hash] = nil -- a No Name buffer's text is in its file now.
	if data.hash_buffer_registry.hashes[bufnr] == old_hash then
		M.unregister_buffer(bufnr) -- the buffer is registered under its new name next.
	end
	require('cavediver.domains.window.data').rename_hash_in_triquetras(old_hash, new_hash)
	M.rename_hash_in_history(old_hash, new_hash)
	if old_history then
		data.crux[new_hash] = data.crux[new_hash] or old_history.crux
		data.crux_internals.global[new_hash] = data.crux_internals.global[new_hash] or old_history.global
		for winid, time in pairs(old_history.windows) do
			if data.crux_internals.window[winid] then
				data.crux_internals.window[winid][new_hash] = data.crux_internals.window[winid][new_hash] or time
			end
		end
	end
	return old_path
end

---Track closed filehashes for potential reopening.
---
---The filehash must still be rigistered in the hash_buffer_registry.
---@param filehash Filehash THE FILEHASH MUST BE REGISTERED
---@return boolean success True if the filehash was added to the closed buffers registry
function M.track_closing_filehash(filehash)
	local filepath = data.hash_filepath_registry.filepaths[filehash]
	local bufnr = data.hash_buffer_registry.buffers[filehash]

	if filepath == nil then
		error("This must not happen: Closing filehash is not registered at all.")
	end
	if bufnr == nil then
		error("The closing filehash must be registered in the hash_buffer_registry.")
	end

	if filepath:match("^NONAME_") then
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

		-- Check if buffer is empty (no lines or single empty line)
		if #lines == 0 or (#lines == 1 and lines[1] == "") then
			M.untrack_buffer(bufnr) -- its own history goes first, and it leaves the slots.
			require('cavediver.domains.window.data').forget_hash_in_slots(filehash)
			M.unregister_buffer(bufnr)
			M.follow_along() -- the notes about it go, and then its path
			M.unregister_filepath(filepath) -- Yes, remove it from the system entirely. We are not interested in empty no name buffers.
			return false           -- Don't track empty [No Name] buffers
		end

		local winid = vim.fn.bufwinid(bufnr)
		data.noname_content[filehash] = {
			lines = lines,
			filetype = vim.bo[bufnr].filetype,
			-- the close key switches the window away first, so it keeps the cursor on the buffer.
			cursor = winid ~= -1 and vim.api.nvim_win_get_cursor(winid) or vim.b[bufnr].cavediver_cursor or { 1, 0 }
		}
	end

	M.close_into_pools(filehash) -- one copy per pool: a file closed again is the newest
	return true
end


---Force label a filehash as a closed filehash
---
---BE CAREFUL: 
---    - This will not check if the filehash is registered in the hash_buffer_registry.
---    - This is not designed for NONAME_ buffers as well!
function M.track_closing_filehash_force(filehash)
	if filehash == nil then
		error("This must not happen: Closing filehash is not registered at all.")
	end

	push_closed(M.current_pool(), filehash)
end


---Check if filehash is still in closed_buffers
---
---@param filehash Filehash
function M.is_filehash_closed(filehash)
	if filehash == nil then 
		return false
	end

	for _, pool in pairs(M.pools()) do
		if vim.tbl_contains(pool.closed, filehash) then
			return true
		end
	end
	return false
end


---Reopen last closed buffer
---
---@return Bufnr|nil bufnr Buffer number of the reopened buffer, or nil if no closed buffers exist
function M.reopen_last_closed()
	local closed = M.current_pool().closed -- the pool of the tab you're in
	if #closed == 0 then
		-- the other lists may hold some, in memory or in the whole editor's file alone: say where they are
		local files = require('cavediver.domains.storage').routines.file_only_closed()
		for _, pool in pairs(M.pools()) do
			for _, filehash in ipairs(pool.closed) do
				files[filehash] = true
			end
		end
		local elsewhere = vim.tbl_count(files)
		if elsewhere > 0 then
			vim.notify("No closed buffers to reopen in this tab.\n" .. (elsewhere == 1 and "1 is on another tab's list"
				or (elsewhere .. " are on other tabs' lists")) .. ": :CavediverClosed", vim.log.levels.WARN)
		else
			vim.notify("No closed buffers to reopen.", vim.log.levels.WARN)
		end
		return nil
	end

	local filehash = closed[#closed]
	local bufnr = M.reopen_filehash(filehash)
	if bufnr then
		vim.api.nvim_set_current_buf(bufnr)
	elseif closed[#closed] == filehash then
		vim.notify(require('cavediver.domains.ui').routines.get_smart_basename(filehash) ..
			" isn't on disk right now; it stays on the closed stack.", vim.log.levels.WARN)
	end
end

---Unregister a buffer and delete it from the tracking system
function M.delete_buffer(winid)
	local bufnr = vim.api.nvim_win_get_buf(winid)

	-- a buffer we don't track (help, quickfix, a terminal) is closed as it is.
	if data.hash_buffer_registry.hashes[bufnr] == nil then
		if vim.bo[bufnr].buftype == "terminal" and vim.fn.jobwait({ vim.bo[bufnr].channel }, 0)[1] == -1 then
			vim.notify("Terminal job is still running", vim.log.levels.WARN)
			return false
		end
		-- a buffer that writes somewhere (oil's acwrite) keeps its unsaved changes, as a file does.
		if vim.bo[bufnr].modified and (vim.bo[bufnr].buftype == "acwrite" or vim.bo[bufnr].buftype == "") then
			vim.notify("Buffer has unsaved changes", vim.log.levels.WARN)
			return false
		end
		-- a window visiting it goes back to the file it was on; a window born on it is left to neovim,
		-- which closes it, or picks what it shows when it's the only one.
		local triquetra = require('cavediver.domains.window.data').crux[winid]
		local current_bufnr = triquetra and
			(M.get_buffer_from_hash(triquetra.current_slot) or M.reopen_filehash(triquetra.current_slot))
		if current_bufnr and vim.api.nvim_buf_is_valid(current_bufnr) then
			vim.api.nvim_win_set_buf(winid, current_bufnr)
		elseif triquetra and M.get_filepath_from_hash(triquetra.current_slot) then
			vim.notify(require('cavediver.domains.ui').routines.get_smart_basename(triquetra.current_slot) ..
				" isn't on disk right now, so the window can't go back to it.", vim.log.levels.WARN)
		end
		vim.api.nvim_buf_delete(bufnr, { force = true })
		return true
	end

	-- Check if buffer has unsaved changes. Avoid deleting unsaved buffers.
	if vim.api.nvim_buf_get_name(bufnr) ~= "" and vim.bo[bufnr].modified then
		vim.notify("Buffer has unsaved changes", vim.log.levels.WARN)
		return false
	end

	-- Check if buffer is shown in multiple windows
	local buffer_usage_count = 0
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == bufnr then
			buffer_usage_count = buffer_usage_count + 1
		end
	end

	if buffer_usage_count > 1 then
		vim.notify("Can't delete buffer because it's shown in another window.", vim.log.levels.WARN)
		return false
	end

	-- Check if it's the only buffer left
	local total_buffers = 0
	for _ in pairs(data.crux) do
		total_buffers = total_buffers + 1
	end

	if total_buffers <= 1 then
		vim.notify("Can't delete buffer because it's the only one left", vim.log.levels.WARN)
		return false
	end

	-- Find next buffer in ordered history list
	local ordered_buffers = data.ordered.crux
	local current_index = nil

	-- Find current buffer's position in ordered list
	for i, entry in ipairs(ordered_buffers) do
		if entry.buf == bufnr then
			current_index = i
			break
		end
	end

	local next_bufnr
	if current_index then
		if current_index == 1 and #ordered_buffers >= 2 then
			-- If deleting most recent, go to second most recent
			next_bufnr = ordered_buffers[2].buf
		elseif current_index > 1 then
			-- Otherwise go to most recent relative to the one deleted (next in list, wraps around)
			next_bufnr = ordered_buffers[((current_index) % #ordered_buffers) + 1].buf
		end
	else
		error("This is impossible: Current buffer not found in ordered history.")
	end

	-- Switch to next buffer before deletion
	vim.b[bufnr].cavediver_cursor = vim.api.nvim_win_get_cursor(winid) -- for a No Name buffer's cache
	if next_bufnr and vim.api.nvim_buf_is_valid(next_bufnr) then
		vim.api.nvim_set_current_buf(next_bufnr)
	end

	-- Delete the buffer once the switch has settled, so the window's arrival is slotted first. a file
	-- is only deleted, so neovim keeps its marks for when it's reopened; a No Name buffer is wiped,
	-- its text is cached.
	local loads = data.loads
	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(bufnr) or data.loads ~= loads then
			return -- gone already, or a session loaded since.
		end
		if vim.api.nvim_buf_get_name(bufnr) ~= "" then
			vim.cmd("bdelete " .. bufnr)
		else
			vim.cmd("bw! " .. bufnr)
		end
	end)
	-- Our own BufDelete hook handles the untracking and wrapup

	return true
end

---Get buffer number from file hash.
---
---@param hash Filehash File hash
---@return Bufnr|nil bufnr Buffer number or nil if not found
function M.get_buffer_from_hash(hash)
	if hash == nil then
		return nil
	end
	return data.hash_buffer_registry.buffers[hash]
end

---Get file hash from buffer number.
---
---@param bufnr Bufnr Buffer number
---@return Filehash|nil hash File hash or nil if not found
function M.get_hash_from_buffer(bufnr)
	if bufnr == nil then
		return nil
	end
	return data.hash_buffer_registry.hashes[bufnr]
end

---Get filepath from file hash
---
---@param hash Filehash File hash
---@return Filepath|nil filepath File path or nil if not found
function M.get_filepath_from_hash(hash)
	if hash == nil then
		return nil
	end
	return data.hash_filepath_registry.filepaths[hash]
end

---Get filepath from buffer number
---
---@param bufnr Bufnr File hash
---@return Filepath|nil filepath File path or nil if not found
function M.get_filepath_from_buffer(bufnr)
	local filehash = data.hash_buffer_registry.hashes[bufnr]
	if bufnr == nil or filehash == nil then
		return nil
	end
	return data.hash_filepath_registry.filepaths[filehash]
end

---Get filepath from buffer number
---
---@param filepath Filehash File hash
---@return Filehash|nil filepath File hash or nil if not found
function M.get_hash_from_filepath(filepath)
	if filepath == nil then
		return nil
	end
	return data.hash_filepath_registry.hashes[filepath]
end

---A short routine on forgetting a filehash from the system. It only touches cavediver's own
---data, never a buffer.
---
---@param filepath Filepath
---@param filehash Filehash
local function detach_filehash_from_crux(filepath, filehash)
	data.crux[filehash] = nil
	data.crux_internals.global[filehash] = nil
	for winid, _ in pairs(data.crux_internals.window) do
		if data.crux_internals.window[winid][filehash] then
			 data.crux_internals.window[winid][filehash] = nil
		end
	end

	if filehash == nil then
		return
	end
	local bufnr = data.hash_buffer_registry.buffers[filehash]
	if bufnr then
		data.hash_buffer_registry.hashes[bufnr] = nil
	end
	data.hash_buffer_registry.buffers[filehash] = nil
end

---Find the buffer that holds this exact filepath, if any. `vim.fn.bufnr()` would pattern-match,
---so the names are compared as they are.
---
---@param filepath Filepath|nil
---@return Bufnr|nil
local function find_buffer_by_filepath(filepath)
	if not filepath or filepath:match("^NONAME_") then
		return nil
	end
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(bufnr) == filepath then
			return bufnr
		end
	end
	return nil
end

---Comprehensive system cleanup and validation.
---
---Removes orphaned entries, validates registries, and ensures data consistency.
---Should be called periodically and before critical operations like saving.
---
---@param on_tick boolean|nil True when the cleanup timer runs it: files are then checked for being
---gone from disk a slice at a time
---@return table cleanup_report Summary of what was cleaned up
function M.cleanup_system(on_tick)
	local report = {
		orphaned_history = 0,
		orphaned_hashes = {},
		orphaned_paths = {},
		invalid_closed_buffers = 0,
		invalid_closed_hashes = {},
		stale_hash_entries = 0,
		stale_hashes = {},
		invalid_triquetra_refs = 0,
		updated_lists = false
	}


	-- 3. Clean stale hash registry entries (buffers that no longer exist)
	for filehash, bufnr in pairs(data.hash_buffer_registry.buffers) do
		local filepath = data.hash_filepath_registry.filepaths[filehash]
		if vim.api.nvim_buf_is_valid(bufnr) then
			goto continue
		end
		-- the same file can be open as another buffer (e.g. reloaded without events), then we
		-- track that one instead of forgetting the file.
		local live_bufnr = find_buffer_by_filepath(filepath)
		local ledger = require('cavediver.domains.ledger')
		if live_bufnr then
			data.hash_buffer_registry.hashes[bufnr] = nil
			data.hash_buffer_registry.buffers[filehash] = live_bufnr
			data.hash_buffer_registry.hashes[live_bufnr] = filehash
			ledger.move("repair", { subject = filehash, name = ledger.name_of(filehash),
				words = "its buffer was replaced without an event; the new one is tracked" })
			goto continue
		end
		-- a file whose buffer went without events is closed like any other: slots keep it and reopen it.
		if filepath and not filepath:match("^NONAME_") then
			local holding = {}
			if not M.is_filehash_closed(filehash) then
				holding = M.close_into_pools(filehash, true)
			else
				for _, pool in pairs(M.pools()) do
					if vim.tbl_contains(pool.closed, filehash) then
						holding[pool] = true
					end
				end
			end
			ledger.move("repair", { subject = filehash, name = ledger.name_of(filehash), lists = named_lists(holding),
				state = "closed", words = "its buffer vanished without an event; kept on the closed lists" })
			-- closed, it's still known, so its history stays: only its buffer is forgotten
			data.hash_buffer_registry.hashes[bufnr] = nil
			data.hash_buffer_registry.buffers[filehash] = nil
		else
			ledger.move("repair", { subject = filehash, name = ledger.name_of(filehash),
				words = "its buffer vanished without an event, and its text with it" })
			detach_filehash_from_crux(filepath, filehash)
		end
		table.insert(report.stale_hashes, filehash)
		report.stale_hash_entries = report.stale_hash_entries + 1
		::continue::
	end
	
	-- 2. Clean invalid closed buffers (entries nothing names, or open again). A closed file gone from
	-- disk stays: it may come back.
	for id, pool in pairs(M.pools()) do
		for i = #pool.closed, 1, -1 do
			local filehash = pool.closed[i]
			local filepath = data.hash_filepath_registry.filepaths[filehash]
			if filepath and data.hash_buffer_registry.buffers[filehash] == nil then
				goto continue
			end

			table.insert(report.invalid_closed_hashes, filehash)
			require('cavediver.domains.ledger').move("repair", {
				subject = filehash, name = require('cavediver.domains.ledger').name_of(filehash) or filehash,
				lists = { M.list_name(pool) },
				state = filepath and "open" or nil,
				words = filepath and "open again without a visit cavediver saw; taken off its list"
					or "nothing names it; taken off its list",
			})
			table.remove(pool.closed, i)
			pool.times[filehash] = nil
			changed(pool)
			if filepath then -- open again: the pool is remembered for its next close
				data.came_from[filehash] = data.came_from[filehash] or {}
				data.came_from[filehash][id] = true
			end
			report.invalid_closed_buffers = report.invalid_closed_buffers + 1
			::continue::
		end
	end

	-- 1. Follow along: the notes and history of hashes no longer known go, and then their paths. A
	-- registered buffer stays whatever the disk says: its file may not be written yet, or may come back.
	local known = M.known_filehashes()
	for filehash, _ in pairs(data.crux_internals.global) do
		if not known[filehash] then
			table.insert(report.orphaned_hashes, filehash)
			report.orphaned_paths[filehash] = data.hash_filepath_registry.filepaths[filehash] -- before it goes
			report.orphaned_history = report.orphaned_history + 1
		end
	end
	M.follow_along(known)

	-- files gone from disk are marked with where you are, and back ones cleared
	if not M.refresh_label() then
		M.mark_missing(data.last_label, on_tick and mark_slice or nil)
	end


	-- 4. Validate triquetra references across windows
	local window = require('cavediver.domains.window')
	for winid, triquetra in pairs(window.data.crux) do
		local slots_to_check = { triquetra.current_slot, triquetra.secondary_slot, triquetra.ternary_slot, triquetra
			.primary_buffer[1] }
		for _, slot in ipairs(slots_to_check) do
			if slot and not data.hash_filepath_registry.filepaths[slot] then
				-- Triquetra references invalid filehash
				report.invalid_triquetra_refs = report.invalid_triquetra_refs + 1
			end
		end
	end

	-- 5. Update ordered lists after cleanup
	if report.orphaned_history > 0 or report.stale_hash_entries > 0 then
		require('cavediver.domains.window.routines').cleanup_triquetras()
		M.update_buffer_history_ordered()
		M.update_buffer_history_ordered_nonharpooned()
		report.updated_lists = true
	end

	return report
end

-- Fucking reset everything.
---Tear the history domain's state down, for a load from idle: it starts from nothing, as at startup.
---
---@return nil
function M.teardown()
	data.crux = {}
	data.crux_internals = { window = {}, global = {} }
	data.ordered = { crux = {}, nonharpooned = {} }
	data.history_index = 1
	data.hash_buffer_registry = { buffers = {}, hashes = {} }
	data.hash_filepath_registry = { filepaths = {}, hashes = {} }
	data.cycling_origins = {}
	data.closed_buffers = {}
	data.noname_content = {}
	data.missing = {}
	data.unwritten = {}
	data.last_label = nil
	data.label_seen = false
	M.reset_pools()
	previous_window_constructed = nil
end

function M.repopulate_history()
	data.crux = {}
	data.hash_buffer_registry.buffers = {}
	data.hash_buffer_registry.hashes = {}
	data.hash_filepath_registry.hashes = {}
	data.hash_filepath_registry.filepaths = {}
	data.history_index = 1
	data.cycling_origins = {}
	data.closed_buffers = {}
	data.noname_content = {}
	M.reset_pools()

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
			M.update_buffer_history(bufnr)
		end
	end
	M.update_buffer_history_ordered()
	M.update_buffer_history_ordered_nonharpooned()
end

return M
