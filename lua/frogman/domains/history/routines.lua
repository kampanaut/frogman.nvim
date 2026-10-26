local data = require("frogman.domains.history.data")
local configs = require("frogman.configs")

local M = {}

local function is_no_name_buffer(bufnr)
	local filename = vim.api.nvim_buf_get_name(bufnr)

	return vim.bo[bufnr].buftype == ""  -- Normal buffer (not terminal, help, etc.)
		and (not filename:match("://"))
		and filename == ""              -- No filename set
		and vim.api.nvim_buf_is_loaded(bufnr) -- Buffer is loaded
end

---Get the name frogman gives a No Name buffer.
---
---The name is NONAME_ and an id kept on the buffer, made on the first call from the time and a
---high-resolution clock, so a later session's buffer with the same number can't take it over.
---
---@param bufnr Bufnr The No Name buffer
---@return string name NONAME_ and the buffer's id
function M.noname_name(bufnr)
	if vim.b[bufnr].frogman_noname == nil then
		vim.b[bufnr].frogman_noname = tostring(os.time()) .. string.format("%.0f", vim.uv.hrtime()) -- digits, however large
	end
	return "NONAME_" .. vim.b[bufnr].frogman_noname
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

---Check if a buffer is `nowrite` on an existing regular file.
---
---This is how image.nvim leaves an image's buffer, and frogman tracks those like files.
---
---@param bufnr Bufnr
---@return boolean nowrite_file True if it's `nowrite` on a readable file, not a directory
function M.is_nowrite_file(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	return vim.bo[bufnr].buftype == "nowrite" and
		name ~= "" and
		vim.fn.filereadable(name) == 1 and
		vim.fn.isdirectory(name) == 0
end

---Check if frogman tracks a buffer.
---
---A tracked buffer is listed and has buftype "" (or is `nowrite` on an existing regular file).
---Its name is empty (a No Name buffer) or a plain path, with no `://` in it. A plugin's
---scratch and helper buffers are unlisted, so they're left alone.
---
---@param bufnr Bufnr
---@return boolean trackable True if frogman tracks the buffer
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
		require('frogman.domains.ledger').never("I don't want to track non-file buffers.")
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
		require('frogman.domains.ledger').never("Cannot register an empty filepath.")
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

---Check if anything still references a filehash.
---
---Looks in every window's slots, primary queue and displacement maps (keys and values), in the
---history (overall, each window's and each pool's visits), and on every pool's closed stack.
---
---@param filehash Filehash
---@return boolean referenced True if anything still references the filehash
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
	for _, triquetra in pairs(require('frogman.domains.window.data').crux) do
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

---Get every hash frogman still knows, as a set.
---
---A hash is known while an open buffer, a slot, a primary queue or a closed stack holds it.
---Notes and history never keep a hash known. They follow along instead. It's built once for a pass
---over many hashes.
---
---@return table<Filehash, boolean> known File hash → true for every known hash
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
	for _, triquetra in pairs(require('frogman.domains.window.data').crux) do
		for _, filehash in pairs({ triquetra.current_slot, triquetra.secondary_slot, triquetra.ternary_slot }) do
			known[filehash] = true
		end
		for _, filehash in ipairs(triquetra.primary_buffer or {}) do
			known[filehash] = true
		end
	end
	return known
end

---Get the editor's pool.
---
---Its closed stack is closed_buffers itself, whatever replaced that table last. When it isn't,
---or there's no editor's pool yet, a fresh pool is made around that table.
---
---@return Pool pool The editor's pool
local function editor_pool()
	local pool = data.pools[""]
	if pool == nil or not rawequal(pool.closed, data.closed_buffers) then
		pool = { id = "", closed = data.closed_buffers, times = {}, visits = {}, tabs = {} }
		data.pools[""] = pool
	end
	return pool
end

---Callback given a pool's id when its records (closed list, close times) change
---
---The storage domain sets it while it writes records, and clears it when it stops.
---
---@type fun(id: string)|nil
M.on_records_change = nil

---Mark a pool's records as changed.
---
---Tells `M.on_records_change`, when that's set.
---
---@param pool Pool The pool whose closed list or close times changed
---@return nil
local function changed(pool)
	if M.on_records_change then
		M.on_records_change(pool.id)
	end
end
M.pool_changed = changed

---Get a pool's list name, as the closed lists and the trail show it.
---
---Returns "editor" for the editor's pool, otherwise the tab session's name, or the last part
---of its directory when it has no name.
---
---@param pool Pool
---@return string name The list's name
function M.list_name(pool)
	return pool.id == "" and "editor" or (pool.name or vim.fn.fnamemodify(pool.directory or "", ":t"))
end

---Get the list names of a set of pools, the current tab's own first.
---
---The other names are sorted, and are also returned apart.
---
---@param pools table<Pool, boolean> The pools to name (pool → true)
---@return string[] names Every pool's name, the current tab's first
---@return string[] others The names of the pools other than the current tab's
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

---Get the id of a tab session's pool.
---
---The id is the session's name (empty when nil), a newline, then its directory.
---
---@param name string|nil The tab session's name
---@param directory string The tab session's directory
---@return string id The pool's id
function M.pool_id(name, directory)
	return (name or "") .. "\n" .. directory
end

---Get every pool, the editor's included.
---
---@return table<string, Pool> pools Pool id → pool
function M.pools()
	editor_pool()
	return data.pools
end

---Reset the pools to the editor's pool alone, as at startup.
---
---Every tab session's pool goes, with the record of which tab is in which pool and of the
---pools each reopened file came out of.
---
---@return nil
function M.reset_pools()
	data.pools = {}
	data.tab_pools = {}
	data.came_from = {}
	editor_pool()
end

---Get the pool a tab belongs to.
---
---Returns its tab session's pool, or the editor's when the tab is in no tab session.
---
---@param tabpage integer The tab
---@return Pool pool The tab's pool
function M.pool_of_tab(tabpage)
	local id = data.tab_pools[tabpage]
	return id and data.pools[id] or editor_pool()
end

---Get the pool of the current tab.
---
---@return Pool pool The current tab's pool
function M.current_pool()
	return M.pool_of_tab(vim.api.nvim_get_current_tabpage())
end

---Join a tab to a tab session's pool, making the pool when it's first needed.
---
---The tab leaves the pool it was in before.
---
---@param tabpage integer The tab joining
---@param name string|nil The tab session's name
---@param directory string The tab session's directory
---@return Pool pool The tab session's pool
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

---Put a file on a pool's closed stack as its newest entry.
---
---A pool keeps one copy of each file, so an older entry for it is taken off first. The close
---time is stored, and the pool is marked as changed.
---
---@param pool Pool
---@param filehash Filehash
---@param time integer|nil When it was closed (defaults to now)
---@return nil
local function push_closed(pool, filehash, time)
	for i = #pool.closed, 1, -1 do
		if pool.closed[i] == filehash then
			table.remove(pool.closed, i)
		end
	end
	table.insert(pool.closed, filehash)
	pool.times[filehash] = time or require('frogman.domains.ledger').now() -- to the microsecond, so closes in one second keep their order
	changed(pool)
end

---Get the tabs that visited a file.
---
---A tab visited it when one of its windows shows it or has it in its history.
---
---@param filehash Filehash
---@return table<integer, boolean> tabpages Tab page → true for every tab that visited it
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

---Close a file into its pools.
---
---Its pools are the current tab's, every pool it came out of when it was opened again, and the
---pool of every tab that visited it (see `M.tabs_that_visited()`). Each one gets it as its
---newest entry, with the same close time. The trail records the close, and a close onto lists
---other than the current tab's also gets a message.
---
---@param filehash Filehash
---@param quiet boolean|nil Whether the caller records the close itself
---@return table<Pool, boolean> pools The pools it went on (pool → true)
function M.close_into_pools(filehash, quiet)
	local time = require('frogman.domains.ledger').now()
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
		M.ledger_record_close(filehash, targets)
	end
	return targets
end

---Record a close in the trail, and say it when it went on lists other than the tab's.
---
---A close the caller held back, as a No Name buffer's that a write may yet make a rename, is
---recorded here once it turns out to be one.
---
---@param filehash Filehash The closed file's hash
---@param targets table<Pool, boolean> The pools it went on (pool → true)
---@return nil
function M.ledger_record_close(filehash, targets)
	local ledger = require('frogman.domains.ledger')
	local name = ledger.name_of(filehash) or filehash
	local lists, others = named_lists(targets)
	ledger.move("closed", { subject = filehash, name = name, lists = lists, dim = #others == 0 })
	if #others > 0 then
		ledger.tell("closed", name, others)
	end
end

---Take a file that's open again off every pool's closed stack.
---
---A file open again is closed nowhere, and the pools it left are remembered for its next
---close. The trail records the reopen, and a reopen off lists other than the current tab's
---also gets a message.
---
---@param filehash Filehash
---@return nil
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
		local ledger = require('frogman.domains.ledger')
		local name = ledger.name_of(filehash) or filehash
		local lists, others = named_lists(left)
		-- a file never written comes back as a new one, which the trail says
		local filepath = data.hash_filepath_registry.filepaths[filehash]
		local new = data.unwritten[filehash] ~= nil and filepath ~= nil and vim.fn.filereadable(filepath) == 0
		ledger.move("reopened", { subject = filehash, name = name, lists = lists, dim = #others == 0, new = new or nil })
		if #others > 0 then
			ledger.tell("reopened", name, others)
		end
	end
end

---Take a hash off every pool's closed stack, remembering nothing.
---
---Used for a hash that's gone rather than opened again, so no pool is kept for its next close.
---
---@param filehash Filehash
---@return nil
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

---Copy a closed file from one pool's closed stack onto another's.
---
---It goes under the other pool's own entries, as its oldest, with its close time, and the
---first pool keeps its entry. Nothing happens when the file isn't closed on the first pool, or
---is already on the second.
---
---@param from Pool The pool it's closed on
---@param to Pool The pool it's copied onto
---@param filehash Filehash|nil
---@return nil
function M.carry_closed(from, to, filehash)
	if filehash == nil or not vim.tbl_contains(from.closed, filehash) or vim.tbl_contains(to.closed, filehash) then
		return
	end
	table.insert(to.closed, 1, filehash)
	to.times[filehash] = from.times[filehash]
	changed(to)
end

---Find the git directory for the session's directory.
---
---Searches upward from the global working directory. A `.git` file, as a worktree has, is
---followed to the directory it points to.
---
---@return string|nil git_dir The git directory, or nil if there's none
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

---Get the label from git's HEAD.
---
---HEAD is read as a file, without running git. Returns the branch, or the first 7 hex
---characters of a detached HEAD.
---
---@param git_dir string|false|nil The git directory when it's found already, false when it was looked for and there's none
---@return string|nil label The label, or nil when there's no HEAD to read
function M.git_label(git_dir)
	if git_dir == nil then
		git_dir = M.git_dir()
	end
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

---Get the label for where you are right now.
---
---The `label_provider` config decides it. A function there gives the label, and `false` turns
---labels off. With no provider set, it's the git branch (see `M.git_label()`).
---
---@param git_dir string|false|nil The git directory when it's found already, false when it was looked for and there's none
---@return string|nil label The label, or nil when there's none
function M.current_label(git_dir)
	local provider = require('frogman.configs').label_provider
	if provider == false then
		return nil
	elseif type(provider) == "function" then
		local ok, label = pcall(provider)
		return ok and type(label) == "string" and label or nil
	end
	return M.git_label(git_dir)
end

-- files checked for being gone from disk per cleanup tick, besides the ones on screen
local mark_slice = 500
local mark_queue, mark_next = {}, 1

---Mark the known files that are gone from disk, and clear the marks of files that are back.
---
---Each missing file is tagged with where you were when it went missing (the label), or the
---time when there's no label. A file never written isn't missing. With a limit, the open
---buffers and the slots are always checked, and the other files a slice at a time, carrying on
---from where the last such pass stopped. The trail records each file that goes and comes back,
---and the marks of files frogman no longer knows are dropped.
---
---@param label string|nil The label the files went missing under
---@param limit integer|true|nil How many other files to check at most, true for a tick's slice (nil = every file)
---@param known table<Filehash, boolean>|nil The files frogman knows, when the caller has them already
---@return nil
function M.mark_missing(label, limit, known)
	limit = limit == true and mark_slice or limit
	known = known or M.known_filehashes()
	local filepaths = data.hash_filepath_registry.filepaths
	local checked = {} -- a file open, in a slot and in the slice is checked once all the same
	local function mark(filehash)
		local filepath = filepaths[filehash]
		if not filepath or not known[filehash] or filepath:match("^NONAME_") or checked[filehash] then
			return
		end
		checked[filehash] = true
		if vim.fn.filereadable(filepath) == 1 then
			if data.missing[filehash] ~= nil then
				require('frogman.domains.ledger').move("back", { subject = filehash,
					name = require('frogman.domains.ledger').name_of(filehash), words = "back on disk" })
			end
			data.missing[filehash] = nil
			data.unwritten[filehash] = nil
		elseif data.unwritten[filehash] then
			return -- never written, so it didn't go missing
		elseif data.missing[filehash] == nil then
			data.missing[filehash] = label or os.date("%H:%M")
			require('frogman.domains.ledger').move("gone", { subject = filehash,
				name = require('frogman.domains.ledger').name_of(filehash), words = "gone from disk ⎇" .. data.missing[filehash] })
		end
	end
	if limit then
		-- what the winbar and the bufferline show, every time
		for filehash, _ in pairs(data.hash_buffer_registry.buffers) do
			mark(filehash)
		end
		for _, triquetra in pairs(require('frogman.domains.window.data').crux) do
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
	for filehash, mark in pairs(data.unwritten) do
		-- a mark stays while the buffer it was made with is there under that name, taken in yet or not
		local waiting = type(mark) == "number" and vim.api.nvim_buf_is_valid(mark)
			and M.get_filehash(vim.api.nvim_buf_get_name(mark)) == filehash
		if not known[filehash] and not waiting then
			data.unwritten[filehash] = nil
		end
	end
end

local head_watch, head_watch_dir
-- the watch runs only between setup() and disable()
local head_watch_on = false

---Stop watching git's HEAD.
---
---@return nil
function M.stop_head_watch()
	if head_watch then
		head_watch:stop()
		head_watch:close()
	end
	head_watch, head_watch_dir = nil, nil
end

---Allow git's HEAD to be watched, or stop the watch for good.
---
---Called by setup() to allow it, and by disable() to stop it. While it's stopped,
---`M.refresh_label()` doesn't start the watch again.
---
---@param on boolean Whether HEAD may be watched
---@return nil
function M.enable_head_watch(on)
	head_watch_on = on
	if not on then
		M.stop_head_watch()
	end
end

---Watch git's HEAD, so a branch switch is seen when it happens.
---
---The git directory is watched, not the file, since git replaces HEAD by renaming a new one
---over it. A change to HEAD reads the label again. Watching another directory, or none, stops
---the old watch first.
---
---@param git_dir string|nil The git directory to watch (nil = stop watching)
---@return nil
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

---Read the label again.
---
---When it changed, every known file is checked, and the ones that went missing with the change
---are tagged with the label being left. The first label seen only starts the record. It also
---starts or stops the watch on git's HEAD, which runs only for the default label provider, and
---only while `M.enable_head_watch()` allows it.
---
---@return boolean checked True if every known file was just checked, for a change of label
function M.refresh_label()
	local git_dir
	if require('frogman.configs').label_provider == nil and head_watch_on then
		git_dir = M.git_dir() or false -- found once, for the watch and the label; false when there's none
		watch_head(git_dir or nil)
	else
		M.stop_head_watch()
	end
	local label = M.current_label(git_dir)
	local checked = false
	if not data.label_seen then
		data.label_seen = true
	elseif label ~= data.last_label then
		-- a change of label is a step of its own, the files it finds gone tagged under it; the step
		-- keeps both labels apart too, so the trail draws a label's own characters as they are
		local ledger = require('frogman.domains.ledger')
		ledger.within("label", (data.last_label or "—") .. " → " .. (label or "—"), function(left)
			ledger.step_fields({ labels = { from = left, to = label } })
			return M.mark_missing(left)
		end, data.last_label)
		checked = true
	end
	data.last_label = label
	return checked
end

---Drop the notes and history entries that point at hashes frogman no longer knows.
---
---A note goes when either buffer it names is no longer known, and a history entry (overall,
---each window's, each pool's visits) when its hash isn't. Then the path of each unknown hash
---is forgotten, unless something still references it. The trail records each hash forgotten,
---and the notes that went with it.
---
---@param known_set table<Filehash, boolean>|nil The known hashes, if the caller has them
---@return integer forgotten How many hashes were forgotten
function M.follow_along(known_set)
	known_set = known_set or M.known_filehashes()
	local unknown, notes = {}, {}
	local function known(filehash)
		if not known_set[filehash] then
			unknown[filehash] = true
		end
		return known_set[filehash] == true
	end
	for _, triquetra in pairs(require('frogman.domains.window.data').crux) do
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
	local ledger = require('frogman.domains.ledger')
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

---unregister a filepath from the registry
---
---A path is never forgotten while anything references its hash, so a referenced one stays.
---
---@param filepath Filepath
---@return nil
function M.unregister_filepath(filepath)
	local filehash = data.hash_filepath_registry.hashes[filepath]

	if filehash == nil then return end
	if M.is_filehash_referenced(filehash) then return end

	data.hash_filepath_registry.hashes[filepath] = nil
	data.hash_filepath_registry.filepaths[filehash] = nil

	-- print("Unregistered filepath: " .. filepath .. "\n with filehash: " .. filehash .. "\n" .. debug.traceback())
end

---Make sure a window has its own history entry.
---
---Every triquetra comes with one, wherever it's made.
---
---@param winid WinId
---@return nil
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
---@param crux_internals BufferCruxInternals Global crux, and each window's crux by window id
---@return nil
function M.initialise_crux_internals(crux_internals)
	data.crux_internals.window = {}

	-- each window's history was matched to it along with its triquetra
	for winid, window_crux_serialised in pairs(crux_internals.window) do
		data.crux_internals.window[winid] = window_crux_serialised
	end
	data.crux_internals.global = crux_internals.global
	-- windows the file had no history for still get their entry, every triquetra comes with one.
	for winid, _ in pairs(require('frogman.domains.window').data.crux) do
		M.ensure_window_entry(winid)
	end
	local cwin = require('frogman.domains.window').data.last_valid_window
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
	if previous_window_constructed == winid then
		return
	else
		previous_window_constructed = winid
	end
	-- copied only once it's needed, the visits being numbers: a plain copy does
	local global_copy = vim.tbl_extend("force", {}, data.crux_internals.global)

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
	if not require("frogman.domains.window").get_triquetra(winid) then
		winid = require("frogman.domains.navigation.routines").find_most_recent_tracked_window()
	end
	if winid then
		if data.crux_internals.window[winid] == nil then
			data.crux_internals.window[winid] = {}
		end
		data.crux_internals.window[winid][filehash] = data.history_index - 1
	end

	-- open again, it's closed nowhere: it leaves every pool, which remember it for its next close. A
	-- load's entry, given its time, opens nothing: the load fills the closed lists from its file.
	if time == nil then
		M.open_out_of_pools(filehash)
	end
	-- a visit in a tab session's tab is the session's own too.
	local pool = M.pool_of_tab(winid and vim.api.nvim_win_get_tabpage(winid) or vim.api.nvim_get_current_tabpage())
	if time == nil and pool.id ~= "" then
		pool.visits[filehash] = data.history_index - 1
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
---Only takes in buffers that pass `M.is_trackable()`, and drops a registered one that has
---turned into a directory, or into a non-file buffer with nothing on disk.
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

---Get the marked files, in their order, as full paths.
---
---The `marks_provider` config gives them. A function there returns their paths, and `false`
---marks nothing. With no provider set, harpoon's list is used when harpoon is installed.
---Anything in the list that isn't a string is skipped.
---
---@return string[] paths Full paths of the marked files
function M.marked_paths()
	local provider = require('frogman.configs').marks_provider
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
---@param marked string[] The marked files' full paths, read once for every buffer checked
---@return boolean
local function is_harpooned(bufnr, marked)
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		return vim.tbl_contains(
			marked,
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
	local marked = M.marked_paths() -- once, not for each buffer: a provider or a require can be slow
	for _, item in pairs(data.ordered.crux) do
		-- print_table(item)
		-- Only consider buffers that are valid and loaded
		if not is_harpooned(item.buf, marked) then
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
---@return nil
function M.snapshot_origin(winid)
	-- window's data.crux[winid] is ensured to be non-nil.
	local get_smart_basename = require('frogman.domains.ui.routines').get_smart_basename
	data.cycling_origins[winid] = require('frogman.domains.window').get_triquetra(winid)

	local current_slot = data.hash_buffer_registry.hashes[vim.api.nvim_win_get_buf(winid)] or data.cycling_origins[winid].current_slot
	local secondary_slot = data.cycling_origins[winid].secondary_slot
	local sslot_display_string

	if current_slot == nil then
		require('frogman.domains.ledger').never("This is impossible: current buffer is not registered.")
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

---Make a listed buffer holding a saved No Name text.
---
---The buffer is shown in no window, and its cursor goes back in the window that shows it, once
---one does.
---
---@param text { lines: string[], filetype: string, cursor: integer[] } The saved text
---@return Bufnr bufnr The new buffer
function M.buffer_from_text(text)
	local bufnr = vim.api.nvim_create_buf(true, false)

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, text.lines)
	vim.bo[bufnr].filetype = text.filetype
	-- the cursor goes back in the window that shows the buffer, once one does.
	local cursor = text.cursor
	vim.api.nvim_create_autocmd("BufWinEnter", {
		buffer = bufnr,
		once = true,
		callback = function()
			pcall(vim.api.nvim_win_set_cursor, 0, cursor)
		end,
	})
	return bufnr
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
	if not filepath:match("^NONAME_") and vim.fn.filereadable(filepath) ~= 1 and not data.unwritten[filehash] then
		return nil -- a file gone from disk keeps its place on the closed stack: it may come back
	end

	local cache
	if filepath:match("^NONAME_") then
		cache = data.noname_content[filehash]
		if cache and cache.lines == nil and cache.read then
			cache = cache.read() -- a text from the session file is read only when it's reopened
		end
		if cache == nil then
			-- a No Name buffer with nothing cached (it was empty, or its text is lost) can't be brought
			-- back: it leaves every list with nothing remembered, and wasn't reopened
			M.discard_from_pools(filehash)
			data.noname_content[filehash] = nil
			return nil
		end
	end
	M.open_out_of_pools(filehash)
	local bufnr
	if filepath:match("^NONAME_") then
		bufnr = M.buffer_from_text(cache)
		vim.bo[bufnr].buftype = ""
		data.noname_content[filehash] = nil
		local old_filehash = filehash
		filehash = M.register_buffer(bufnr)
		if filehash ~= old_filehash then
			-- it comes back under a new name, and everything that named the old one follows: slots, notes
			-- and history.
			require('frogman.domains.window.data').rename_hash_in_triquetras(old_filehash, filehash)
			M.rename_hash_in_history(old_filehash, filehash)
			data.came_from[filehash], data.came_from[old_filehash] = data.came_from[old_filehash], nil
		end
		if M.get_filepath_from_buffer(bufnr) ~= filepath then
			M.unregister_filepath(filepath) -- This NONAME_ buffer is now irrelevant, we don't want to track it anymore.
		end
	elseif filepath and (vim.fn.filereadable(filepath) == 1 or data.unwritten[filehash]) then
		-- a file never written opens as the new file it was
		bufnr = vim.fn.bufadd(filepath)
		vim.bo[bufnr].buflisted = true -- listed before bufload, whose BufEnter only tracks listed buffers.
		vim.fn.bufload(bufnr)
		M.register_buffer(bufnr)
	end

	if bufnr then
		M.update_buffer_history(bufnr) -- its visit, once, and it leaves the closed lists
		M.update_buffer_history_ordered()
		M.update_buffer_history_ordered_nonharpooned()
		return bufnr
	else
		return nil
	end
end

---Carry a hash's history over to a new hash.
---
---Used when a file takes a new hash: a reopened No Name buffer, or a rename that was a move.
---Its visits move overall, in each window and in each pool, and where the new hash has a visit
---already, the newer of the two stays.
---
---@param old_hash Filehash The hash it had
---@param new_hash Filehash The hash it takes
---@return nil
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
			crux[new_hash] = math.max(crux[new_hash] or crux[old_hash], crux[old_hash])
			crux[old_hash] = nil
		end
	end
end

---Get a hash's visits, overall and in each window.
---
---Used to keep them through the delete a rename starts with, which untracks them. A rename
---that turns out to be a move then hands them to the new name.
---
---@param hash Filehash
---@return { crux: integer|nil, global: integer|nil, windows: table<WinId, integer> } visits
function M.history_of(hash)
	local windows = {}
	for winid, window_crux in pairs(data.crux_internals.window) do
		windows[winid] = window_crux[hash]
	end
	return { crux = data.crux[hash], global = data.crux_internals.global[hash], windows = windows }
end

---Decide whether a rename was a copy or a move, once the command that made it is over.
---
---The disk decides. If the old name is still a file, it was a copy, and the caller closes the
---old name. If it isn't, or never was (a No Name buffer), it was a move. Every slot, note and
---history entry that named the old hash then follows to the new name, the newer visit staying where
---the new name had one, and the old hash leaves every closed stack, and so does the new one, whose
---buffer holds it open now. The buffer is unregistered from the old hash, for the caller to register
---under the new one. A buffer frogman doesn't track is left alone.
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
	local new_name = vim.api.nvim_buf_get_name(bufnr)
	local new_hash = M.get_filehash(new_name ~= "" and new_name or M.noname_name(bufnr)) -- no name: a No Name buffer's
	M.discard_from_pools(old_hash)
	-- a name still on a closed list is open now, the buffer holding it: its old entry goes, nothing remembered
	M.discard_from_pools(new_hash)
	data.noname_content[old_hash] = nil -- a No Name buffer's text is in its file now.
	if data.hash_buffer_registry.hashes[bufnr] == old_hash then
		M.unregister_buffer(bufnr) -- the buffer is registered under its new name next.
	end
	local window_data = require('frogman.domains.window.data')
	-- a triquetra holding both names would hold one file twice: the renamed buffer keeps its slot,
	-- and the other slot lets the file go, unless that's the current slot, which keeps it
	for _, triquetra in pairs(window_data.crux) do
		local gone = triquetra.current_slot == new_hash and old_hash or new_hash
		if triquetra.current_slot == old_hash or triquetra.current_slot == new_hash or
			triquetra.secondary_slot == old_hash or triquetra.ternary_slot == old_hash then
			if triquetra.secondary_slot == gone then triquetra.secondary_slot = nil end
			if triquetra.ternary_slot == gone then triquetra.ternary_slot = nil end
		end
	end
	window_data.rename_hash_in_triquetras(old_hash, new_hash)
	-- a queue that held both names keeps the file once, where it came first, and a note that named
	-- one name from the other now names its own buffer, so it goes
	for _, triquetra in pairs(window_data.crux) do
		local seen = {}
		for i = #triquetra.primary_buffer, 1, -1 do
			if triquetra.primary_buffer[i] == new_hash then
				if seen[new_hash] then
					table.remove(triquetra.primary_buffer, seen[new_hash])
				end
				seen[new_hash] = i
			end
		end
		for _, map in ipairs({ triquetra.displacement_ternary_map, triquetra.displacement_secondary_map }) do
			for _, key in ipairs({ new_hash, new_hash .. "-swap" }) do
				if map[key] == new_hash then
					map[key] = nil
				end
			end
		end
	end
	M.rename_hash_in_history(old_hash, new_hash)
	if old_history then
		-- the newer visit stays, where the new name had one already
		if old_history.crux then
			data.crux[new_hash] = math.max(data.crux[new_hash] or old_history.crux, old_history.crux)
		end
		if old_history.global then
			data.crux_internals.global[new_hash] = math.max(data.crux_internals.global[new_hash] or old_history.global, old_history.global)
		end
		for winid, time in pairs(old_history.windows) do
			if data.crux_internals.window[winid] then
				data.crux_internals.window[winid][new_hash] = math.max(data.crux_internals.window[winid][new_hash] or time, time)
			end
		end
	end
	return old_path
end

---Track closed filehashes for potential reopening.
---
---The filehash must still be rigistered in the hash_buffer_registry.
---@param filehash Filehash THE FILEHASH MUST BE REGISTERED
---@param quiet boolean|nil Whether the close is left out of the trail, for the caller to record
---@return boolean success True if the filehash was added to the closed buffers registry
---@return table<Pool, boolean>|nil targets The pools it went on, when it was added
function M.track_closing_filehash(filehash, quiet)
	local filepath = data.hash_filepath_registry.filepaths[filehash]
	local bufnr = data.hash_buffer_registry.buffers[filehash]

	if filepath == nil then
		require('frogman.domains.ledger').never("This must not happen: Closing filehash is not registered at all.")
	end
	if bufnr == nil then
		require('frogman.domains.ledger').never("The closing filehash must be registered in the hash_buffer_registry.")
	end

	if filepath:match("^NONAME_") then
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

		-- Check if buffer is empty (no lines or single empty line)
		if #lines == 0 or (#lines == 1 and lines[1] == "") then
			M.untrack_buffer(bufnr) -- its own history goes first, and it leaves the slots.
			require('frogman.domains.window.data').forget_hash_in_slots(filehash)
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
			cursor = winid ~= -1 and vim.api.nvim_win_get_cursor(winid) or vim.b[bufnr].frogman_cursor or { 1, 0 }
		}
	end

	-- one copy per pool: a file closed again is the newest
	return true, M.close_into_pools(filehash, quiet)
end


---Force label a filehash as a closed filehash
---
---BE CAREFUL: 
---    - This will not check if the filehash is registered in the hash_buffer_registry.
---    - This is not designed for NONAME_ buffers as well!
function M.track_closing_filehash_force(filehash)
	if filehash == nil then
		require('frogman.domains.ledger').never("This must not happen: Closing filehash is not registered at all.")
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
		local files = require('frogman.domains.storage').routines.file_only_closed()
		for _, pool in pairs(M.pools()) do
			for _, filehash in ipairs(pool.closed) do
				files[filehash] = true
			end
		end
		local elsewhere = vim.tbl_count(files)
		if elsewhere > 0 then
			vim.notify("No closed buffers to reopen in this tab.\n" .. (elsewhere == 1 and "1 is on another tab's list"
				or (elsewhere .. " are on other tabs' lists")) .. ": :FrogmanClosed", vim.log.levels.WARN)
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
		vim.notify(require('frogman.domains.ui').routines.get_smart_basename(filehash) ..
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
		local triquetra = require('frogman.domains.window.data').crux[winid]
		local current_bufnr = triquetra and
			(M.get_buffer_from_hash(triquetra.current_slot) or M.reopen_filehash(triquetra.current_slot))
		if current_bufnr and vim.api.nvim_buf_is_valid(current_bufnr) then
			vim.api.nvim_win_set_buf(winid, current_bufnr)
		elseif triquetra and M.get_filepath_from_hash(triquetra.current_slot) then
			vim.notify(require('frogman.domains.ui').routines.get_smart_basename(triquetra.current_slot) ..
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
	for _ in ipairs(data.ordered.crux) do -- the open ones: a closed file keeps its history in the view
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
		require('frogman.domains.ledger').never("This is impossible: Current buffer not found in ordered history.")
	end

	-- Switch to next buffer before deletion
	vim.b[bufnr].frogman_cursor = vim.api.nvim_win_get_cursor(winid) -- for a No Name buffer's cache
	local switched = next_bufnr and vim.api.nvim_buf_is_valid(next_bufnr)
	if switched then
		vim.api.nvim_set_current_buf(next_bufnr)
	end

	-- Delete the buffer once the switch has settled, so the window's arrival is slotted first. a file
	-- is only deleted, so neovim keeps its marks for when it's reopened; a No Name buffer is wiped,
	-- its text is cached.
	local loads = data.loads
	require('frogman.settle').later("close " .. require('frogman.domains.ledger.routines').buffer_label(bufnr), function()
		if not vim.api.nvim_buf_is_valid(bufnr) or data.loads ~= loads then
			return -- gone already, or a session loaded since.
		end
		if switched and #vim.fn.win_findbuf(bufnr) > 0 then
			return -- shown again, by a command later in the same batch: it's open again, so it isn't closed
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

---A short routine on cleaning up the buffer from the system
---
---Drops the hash's history, overall and in each window, and its buffer's registration. Its
---path stays registered, and no Neovim buffer is touched.
---
---@param filepath Filepath
---@param filehash Filehash
---@return nil
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

---Find the buffer whose name is exactly this filepath.
---
---`vim.fn.bufnr()` would pattern-match, so the names are compared as they are. A NONAME_ path
---never has a buffer by that name, so it finds none.
---
---@param filepath Filepath|nil
---@return Bufnr|nil bufnr Buffer number or nil if not found
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
M.find_buffer_by_filepath = find_buffer_by_filepath

---Comprehensive system cleanup and validation.
---
---Removes orphaned entries, validates registries, and ensures data consistency.
---Should be called periodically and before critical operations like saving.
---
---@param on_tick boolean|nil Whether a timer tick runs it, checking the disk a slice at a time
---@return table cleanup_report Summary of what was cleaned up
function M.cleanup_system(on_tick)
	local report = {
		orphaned_history = 0,
		stale_hash_entries = 0,
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
		local ledger = require('frogman.domains.ledger')
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

			require('frogman.domains.ledger').move("repair", {
				subject = filehash, name = require('frogman.domains.ledger').name_of(filehash) or filehash,
				lists = { M.list_name(pool) },
				state = filepath and "open" or nil,
				words = filepath and "open again without a visit frogman saw; taken off its list"
					or "nothing names it; taken off its list",
			})
			table.remove(pool.closed, i)
			pool.times[filehash] = nil
			changed(pool)
			if filepath then -- open again: the pool is remembered for its next close
				data.came_from[filehash] = data.came_from[filehash] or {}
				data.came_from[filehash][id] = true
			end
			::continue::
		end
	end

	-- 1. Follow along: the notes and history of hashes no longer known go, and then their paths. A
	-- registered buffer stays whatever the disk says: its file may not be written yet, or may come back.
	local known = M.known_filehashes()
	for filehash, _ in pairs(data.crux_internals.global) do
		if not known[filehash] then
			report.orphaned_history = report.orphaned_history + 1
		end
	end
	M.follow_along(known)

	-- files gone from disk are marked with where you are, and back ones cleared
	if not M.refresh_label() then
		M.mark_missing(data.last_label, on_tick and true or nil, known)
	end

	-- 5. Update ordered lists after cleanup
	if report.orphaned_history > 0 or report.stale_hash_entries > 0 then
		require('frogman.domains.window.routines').enforce_editor_policy()
		M.update_buffer_history_ordered()
		M.update_buffer_history_ordered_nonharpooned()
	end

	return report
end

-- Fucking reset everything.
---Tear the history domain's state down, so a load from idle starts from nothing.
---
---Everything goes back to how it is at startup, the pools included.
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
	mark_queue, mark_next = {}, 1 -- the tick's round starts over, on the new session's files
end

function M.repopulate_history()
	mark_queue, mark_next = {}, 1
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
