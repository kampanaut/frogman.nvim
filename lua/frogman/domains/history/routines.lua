local data = require("frogman.domains.history.data")
local configs = require("frogman.configs")
local handles = require("frogman.domains.history.handles")

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
---efficient buffer lookup and validation. A buffer Neovim opened as a new file carries its
---never-written mark over to its handle.
---
---@param bufnr number Buffer number to register
---@param context HandleContext|nil What its file's reopen is, when its handle was closed: asked for, or a load's
---@return HandleId id The handle of the buffer's file
function M.register_buffer(bufnr, context)
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
	local handle = handles.opened(filehash, context) -- its handle, made or opened
	if vim.b[bufnr].frogman_unwritten then
		handle.unwritten, vim.b[bufnr].frogman_unwritten = bufnr, nil -- a new file, not written yet
	end

	-- print(
	-- 	"Registered buffer: " .. bufnr ..
	-- 	"\n with filehash: " .. filehash ..
	-- 	"\n with filepath: " .. filepath ..
	-- 	"\n with filetype: " .. vim.bo[bufnr].filetype ..
	-- 	"\n" .. debug.traceback()
	-- )

	return handle.id
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
	handles.known(filehash) -- its handle, made closed when it has none

	-- print("Registered filepath: " .. filepath .. "\n with filehash: " .. filehash)
end

---Unregister a buffer from the regietry
---
---Removes the buffer from the hash-to-buffer mapping system. Given a hash, it drops that pair alone,
---as a close read at its event does once it runs: by then the buffer number may name another file.
---@param bufnr number Buffer number to unregister
---@param context HandleContext|nil What the close is: the lists it went on, a repair's words, or quiet
---@param filehash Filehash|nil The hash it was registered under, when the caller read it before
function M.unregister_buffer(bufnr, context, filehash)
	filehash = filehash or data.hash_buffer_registry.hashes[bufnr]
	if filehash == nil then return end

	if data.hash_buffer_registry.hashes[bufnr] == filehash then
		data.hash_buffer_registry.hashes[bufnr] = nil
	end
	if data.hash_buffer_registry.buffers[filehash] == bufnr then
		data.hash_buffer_registry.buffers[filehash] = nil
	end
	handles.closed(filehash, context)

	-- print("Unregistered buffer: " .. bufnr .. "\n with filehash: " .. filehash .. "\n" .. debug.traceback())
end

---Check if anything still references a file's handle.
---
---Asks the handle for a strong holder first, a mark among them, then looks in every window's slots,
---primary queue and notes, in the history and the pools' visits, and on every closed stack.
---
---@param id HandleId The file's handle
---@return boolean referenced True if anything still references the handle
function M.is_handle_referenced(id)
	if data.crux[id] or data.crux_internals.global[id] then
		return true
	end
	local handle = handles.get(id)
	if handle and next(handle.holders) ~= nil then
		return true -- a strong holder, a mark among them, holds it
	end
	for _, window_crux in pairs(data.crux_internals.window) do
		if window_crux[id] then
			return true
		end
	end
	for _, pool in pairs(M.pools()) do
		if pool.visits[id] or vim.tbl_contains(pool.closed, id) then
			return true
		end
	end
	local window_data = require('frogman.domains.window.data')
	for _, triquetra in pairs(window_data.crux) do
		if
			triquetra.current_slot == id or
			triquetra.secondary_slot == id or
			triquetra.ternary_slot == id or
			vim.tbl_contains(triquetra.primary_buffer or {}, id)
		then
			return true
		end
		for _, map in ipairs({ triquetra.displacement_ternary_map, triquetra.displacement_secondary_map }) do
			for key, value in pairs(map or {}) do
				if value == id or window_data.note_owner(key) == id then
					return true
				end
			end
		end
	end
	return false
end

---Get every file frogman still knows, as a set of its handles.
---
---A file is known while a strong holder holds its handle: an open buffer, a slot, a primary queue
---or a closed list, each by its place. Notes and history never keep a file known. They follow along
---instead. It's built once for a pass over many files.
---
---@return table<HandleId, boolean> known The handle of every known file → true
function M.known_handles()
	local known = {}
	for id, handle in pairs(handles.live()) do
		if next(handle.holders) ~= nil then
			known[id] = true
		end
	end
	return known
end

---Get the name of a list's place, as the handles' holders know it.
---
---@param pool Pool
---@return string place "pool:editor", or "pool:" and the pool's id, the session's name and directory
local function pool_place(pool)
	return "pool:" .. (pool.id == "" and "editor" or pool.id) -- the id as it is, so two never read alike
end
M.pool_place = pool_place

---Hold the files a list holds now, by its place.
---
---Called at every change to a list's closed files, and once a list is made or filled.
---
---@param pool Pool
---@return nil
function M.hold_pool(pool)
	handles.hold(pool_place(pool), pool.closed)
end

---Let go of everything a list held, as it leaves memory.
---
---@param pool Pool
---@return nil
function M.drop_pool(pool)
	handles.drop_place(pool_place(pool))
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
		M.hold_pool(pool) -- the table it's made around holds what it holds
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
	M.hold_pool(pool) -- its holders follow its closed files at once
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
	for _, pool in pairs(data.pools) do
		M.drop_pool(pool)
	end
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
---@param pool Pool The pool it goes on
---@param id HandleId The file's handle
---@param time integer|nil When it was closed (defaults to now)
---@return nil
local function push_closed(pool, id, time)
	for i = #pool.closed, 1, -1 do
		if pool.closed[i] == id then
			table.remove(pool.closed, i)
		end
	end
	table.insert(pool.closed, id)
	pool.times[id] = time or require('frogman.domains.ledger').now() -- to the microsecond, so closes in one second keep their order
	changed(pool)
end

---Get the tabs that visited a file.
---
---A tab visited it when one of its windows shows it or has it in its history.
---
---@param id HandleId The file's handle
---@return table<integer, boolean> tabpages Tab page → true for every tab that visited it
function M.tabs_that_visited(id)
	local tabpages = {}
	for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
		for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
			local window_crux = data.crux_internals.window[winid]
			if
				(window_crux and window_crux[id]) or
				M.get_handle_from_buffer(vim.api.nvim_win_get_buf(winid)) == id
			then
				tabpages[tabpage] = true
				break
			end
		end
	end
	return tabpages
end

---Get the pools a file closes into.
---
---Its pools are the current tab's, every pool it came out of when it was opened again, and the
---pool of every tab that visited it (see `M.tabs_that_visited()`). A delete reads them at its event,
---while the window still shows the buffer, and its close goes on them once the editor settles.
---
---@param id HandleId The file's handle
---@return string[] targets The pools' ids
function M.close_targets(id)
	local pools = M.pools()
	local targets = { [M.current_pool()] = true }
	for pool_id, _ in pairs(data.came_from[id] or {}) do
		if pools[pool_id] then
			targets[pools[pool_id]] = true
		end
	end
	for tabpage, _ in pairs(M.tabs_that_visited(id)) do
		targets[M.pool_of_tab(tabpage)] = true
	end
	local ids = {}
	for pool, _ in pairs(targets) do
		table.insert(ids, pool.id)
	end
	return ids
end

---Close a file into its pools.
---
---Each of its pools (see `M.close_targets()`) gets it as its newest entry, with the same close time;
---one gone since its close was read is skipped. The trail gets the close from the handle's own
---close, which these lists' names go to, and a close onto lists other than the current tab's also
---gets a message there.
---
---@param id HandleId The file's handle
---@param targets string[]|nil The pools' ids, when the close read them before (at its event)
---@return string[] lists The lists it went on, by name, the current tab's first
---@return string[] others Of those, the lists other than the current tab's
function M.close_into_pools(id, targets)
	local time = require('frogman.domains.ledger').now()
	local pools, into = M.pools(), {}
	for _, pool_id in ipairs(targets or M.close_targets(id)) do
		if pools[pool_id] then
			into[pools[pool_id]] = true
		end
	end
	data.came_from[id] = nil
	for pool, _ in pairs(into) do
		push_closed(pool, id, time)
	end
	return named_lists(into)
end

---Take a file that's open again off every pool's closed stack.
---
---A file open again is closed nowhere, and the pools it left are remembered for its next
---close. The trail gets the reopen from the handle's own reopen, which these lists' names go to, and
---a reopen off lists other than the current tab's also gets a message there.
---
---@param id HandleId The file's handle
---@return string[] left The lists it left, by name, the current tab's first
---@return string[] others Of those, the lists other than the current tab's
function M.open_out_of_pools(id)
	local left = {}
	for pool_id, pool in pairs(M.pools()) do
		for i = #pool.closed, 1, -1 do
			if pool.closed[i] == id then
				table.remove(pool.closed, i)
				pool.times[id] = nil
				changed(pool)
				data.came_from[id] = data.came_from[id] or {}
				data.came_from[id][pool_id] = true
				left[pool] = true
			end
		end
	end
	return named_lists(left)
end

---Take a file off every pool's closed stack, remembering nothing.
---
---Used for a file that's gone rather than opened again, so no pool is kept for its next close.
---
---@param id HandleId The file's handle
---@return nil
function M.discard_from_pools(id)
	for _, pool in pairs(M.pools()) do
		for i = #pool.closed, 1, -1 do
			if pool.closed[i] == id then
				table.remove(pool.closed, i)
				pool.times[id] = nil
				changed(pool)
			end
		end
	end
	data.came_from[id] = nil
end

---Copy a closed file from one pool's closed stack onto another's.
---
---It goes under the other pool's own entries, as its oldest, with its close time, and the
---first pool keeps its entry. Nothing happens when the file isn't closed on the first pool, or
---is already on the second.
---
---@param from Pool The pool it's closed on
---@param to Pool The pool it's copied onto
---@param id HandleId|nil The file's handle
---@return nil
function M.carry_closed(from, to, id)
	if id == nil or not vim.tbl_contains(from.closed, id) or vim.tbl_contains(to.closed, id) then
		return
	end
	table.insert(to.closed, 1, id)
	to.times[id] = from.times[id]
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
---from where the last such pass stopped. The trail records each file that goes and comes back.
---A tag and a never-written mark are the handle's own, so a file frogman no longer knows takes
---them with it when its handle is let go.
---
---@param label string|nil The label the files went missing under
---@param limit integer|true|nil How many other files to check at most, true for a tick's slice (nil = every file)
---@param known table<HandleId, boolean>|nil The files frogman knows, by their handles, when the caller has them already
---@return nil
function M.mark_missing(label, limit, known)
	limit = limit == true and mark_slice or limit
	known = known or M.known_handles()
	local checked = {} -- a file open, in a slot and in the slice is checked once all the same
	local function mark(id)
		local handle = id and handles.get(id)
		local filepath = handle and M.get_filepath_from_hash(handle.hash)
		if not filepath or not known[id] or filepath:match("^NONAME_") or checked[id] then
			return
		end
		checked[id] = true
		-- the trail gets each tag put on and taken off from the handle's own vanish and return
		if vim.fn.filereadable(filepath) == 1 then
			handles.set_tag(id, nil)
			handle.unwritten = nil
		elseif handle.unwritten then
			return -- never written, so it didn't go missing
		elseif handle.tag == nil then
			handles.set_tag(id, label or os.date("%H:%M"))
		end
	end
	if limit then
		-- what the winbar and the bufferline show, every time
		for filehash, _ in pairs(data.hash_buffer_registry.buffers) do
			local handle = handles.of_hash(filehash)
			mark(handle and handle.id)
		end
		for _, triquetra in pairs(require('frogman.domains.window.data').crux) do
			mark(triquetra.current_slot)
			mark(triquetra.secondary_slot)
			mark(triquetra.ternary_slot)
			for _, id in ipairs(triquetra.primary_buffer or {}) do
				mark(id)
			end
		end
		-- the rest a slice at a time, going round
		local wrapped = false
		for _ = 1, limit do
			if mark_next > #mark_queue then
				if wrapped then
					break
				end
				mark_queue, mark_next, wrapped = vim.tbl_keys(handles.live()), 1, true
				if #mark_queue == 0 then
					break
				end
			end
			mark(mark_queue[mark_next])
			mark_next = mark_next + 1
		end
	else
		for id, _ in pairs(handles.live()) do
			mark(id)
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
			require('frogman.settle').later("label", M.refresh_label) -- once the editor settles
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

---Drop the notes and history entries that point at files frogman no longer knows.
---
---A note goes when either file it names is no longer known, and a history entry (overall,
---each window's, each pool's visits) when its file isn't. Then the path of each unknown file
---is forgotten, unless something still references its handle. The trail records each file
---forgotten, by the hash it had, and the notes that went with it.
---
---@param known_set table<HandleId, boolean>|nil The known files' handles, if the caller has them
---@return integer forgotten How many files were forgotten
function M.follow_along(known_set)
	known_set = known_set or M.known_handles()
	local unknown, notes = {}, {}
	local function known(id)
		if not known_set[id] then
			unknown[id] = true
		end
		return known_set[id] == true
	end
	local window_data = require('frogman.domains.window.data')
	for _, triquetra in pairs(window_data.crux) do
		for _, map in ipairs({ triquetra.displacement_ternary_map or {}, triquetra.displacement_secondary_map or {} }) do
			for key, value in pairs(map) do
				local owner = window_data.note_owner(key)
				local key_known, value_known = owner ~= nil and known(owner), known(value)
				if not key_known or not value_known then
					map[key] = nil
					local gone = not key_known and owner or value
					if gone ~= nil then
						notes[gone] = (notes[gone] or 0) + 1
					end
				end
			end
		end
	end
	-- the arrivals' copies follow along too, so a note dropped from the window is dropped from its copy
	for _, arrival in pairs(window_data.arrivals) do
		for _, copy in ipairs({ arrival.before or {}, arrival.after or {} }) do
			for _, map in ipairs({ copy.displacement_ternary_map or {}, copy.displacement_secondary_map or {} }) do
				for key, value in pairs(map) do
					if not known_set[window_data.note_owner(key)] or not known_set[value] then
						map[key] = nil
					end
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
		for id, _ in pairs(history) do
			if not known(id) then
				history[id] = nil
			end
		end
	end
	local forgotten = 0
	local ledger = require('frogman.domains.ledger')
	for id, is_unknown in pairs(unknown) do
		local filehash = M.get_hash_from_handle(id)
		local filepath = M.get_filepath_from_hash(filehash)
		if is_unknown and filepath then
			local name = ledger.name_of(filehash)
			-- the trail gets what's forgotten from its handle's let-go, with the notes about it that went
			M.unregister_filepath(filepath, { notes = notes[id] or 0 })
			if M.get_filepath_from_hash(filehash) == nil then
				forgotten = forgotten + 1
			elseif notes[id] then
				ledger.move("note_dropped", { subject = filehash, name = name, notes = notes[id],
					words = "notes naming it dropped: nothing holds it any more" })
			end
		end
	end
	return forgotten
end

---unregister a filepath from the registry
---
---A path is never forgotten while anything references its file's handle, so a referenced one stays.
---Its handle is let go first, while the path still names it, so the trail names what's forgotten.
---
---@param filepath Filepath The path to forget, or a No Name text's NONAME_ name
---@param context HandleContext|nil What the let-go is: the notes that went with it, a load's, or quiet
---@return nil
function M.unregister_filepath(filepath, context)
	local filehash = data.hash_filepath_registry.hashes[filepath]

	if filehash == nil then return end
	local handle = handles.of_hash(filehash)
	if handle and M.is_handle_referenced(handle.id) then return end

	handles.let_go(filehash, context) -- forgotten, its handle goes with it
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
---@param winid WinId|nil The window whose own history ranks first (nil = the global crux alone)
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
		for id, time in pairs(pool.visits) do
			table.insert(visits, { id = id, time = time })
		end
		table.sort(visits, function(a, b) return a.time > b.time end)
		data.history_index = data.history_index + #visits
		for rank, visit in ipairs(visits) do
			global_copy[visit.id] = data.history_index - rank
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
	for id, value in pairs(data.crux_internals.window[winid]) do
		table.insert(window_buffers, { id = id, time = value })
	end
	table.sort(window_buffers, function(a, b) return a.time > b.time end)

	-- the window's n buffers take the n fresh times, and the next free one is after them, so the next
	-- buffer recorded ranks strictly first instead of tying with this window's newest.
	data.history_index = data.history_index + #window_buffers
	-- Assign increments based on rank
	for rank, buffer in ipairs(window_buffers) do
		global_copy[buffer.id] = data.history_index - rank
	end

	data.crux = global_copy
end

---Track buffer access in the history timeline.
---
---Adds or updates buffer access time in the history crux. If no time is provided,
---uses current history index and increments it. Used for both new access tracking
---and restoring saved session data.
---
---@param id HandleId The handle of the buffer's file
---@param time number|nil Access time index (nil = use current index)
function M.track_buffer(id, time)
	if time == nil then
		data.crux[id] = data.history_index
		data.crux_internals.global[id] = data.history_index
		data.history_index = data.history_index + 1
	else
		data.crux[id] = time
		data.crux_internals.global[id] = time
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
		data.crux_internals.window[winid][id] = data.history_index - 1
	end

	-- a visit in a tab session's tab is the session's own too.
	local pool = M.pool_of_tab(winid and vim.api.nvim_win_get_tabpage(winid) or vim.api.nvim_get_current_tabpage())
	if time == nil and pool.id ~= "" then
		pool.visits[id] = data.history_index - 1
	end
end

---Untrack the buffer access in the history crux.
---
---Removes the buffer's file from the history, overall and in every window.
---
---@param bufnr Bufnr The buffer to untrack
function M.untrack_buffer(bufnr)
	M.untrack_handle(M.get_handle_from_buffer(bufnr))
end

---Untrack a file's visits in the history crux, by its handle.
---
---Removes the file from the history, overall and in every window. A close read at its event goes by
---its handle, since by the time it runs the buffer's number may name another file.
---
---@param id HandleId|nil The file's handle
function M.untrack_handle(id)
	if id ~= nil then
		data.crux[id] = nil
		data.crux_internals.global[id] = nil
		for winid, _ in pairs(data.crux_internals.window) do
			data.crux_internals.window[winid][id] = nil
		end
	end

	M.update_buffer_history_ordered()
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
	local id = M.get_handle_from_buffer(cbufnr)
	if id == nil then
		if M.is_trackable(cbufnr) then
			id = M.register_buffer(cbufnr)
		else
			return false
		end
	elseif
		not is_no_name_buffer(cbufnr) and
		not (
			vim.fn.isdirectory(filename) == 0 and
			(
				vim.fn.filereadable(filename) == 1 or
				-- a missing file says nothing, it's not written yet or it's gone for now.
				(vim.bo[cbufnr].buftype == "" and not filename:match("://"))
			)
		)
	then
		M.untrack_buffer(cbufnr)
		-- its close is part of its let-go, which the trail records once its path is forgotten
		M.unregister_buffer(cbufnr, { quiet = true }) -- clean this up. this buffer evolved into something we don't like.
		M.unregister_filepath(filename)
		return false
	end

	M.track_buffer(id, nil)
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
	for id, access_time in pairs(data.crux) do
		-- print_table(filehash_to_bufnr)
		local bufnr = M.get_buffer_from_handle(id)
		if not bufnr then
			data.crux[id] = nil -- Remove invalid buffer from history
			goto continue
		end
		table.insert(
			data.ordered.crux,
			{ buf = bufnr, time = access_time }
		)
		::continue::
	end
	table.sort(data.ordered.crux, function(a, b)
		return a.time > b.time
	end)
	return data.ordered.crux
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

	local current_slot = M.get_handle_from_buffer(vim.api.nvim_win_get_buf(winid)) or data.cycling_origins[winid].current_slot
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

	data.cycling_origins[winid]:set("current_slot", current_slot)

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

---Reopen a closed file by its handle.
---
---A file whose name another buffer has, one that turned into something frogman doesn't track, isn't
---reopened while that buffer is there: it says so, and gives "taken" as the reason, so the caller adds
---nothing and keeps the file where it is. A No Name text comes back under a new id, its handle kept,
---so everything that holds the handle holds the text again, and only the hash behind it changes.
---
---@param id HandleId The file's handle
---@return Bufnr|nil bufnr The file's buffer once it's open, nil when it couldn't be reopened
---@return "taken"|nil reason Why it wasn't reopened, when another buffer has its name
function M.reopen_handle(id)
	local handle = handles.get(id)
	local filepath = handle and M.get_filepath_from_hash(handle.hash)
	if filepath == nil then
		return nil
	end
	if not filepath:match("^NONAME_") and vim.fn.filereadable(filepath) ~= 1 and not handle.unwritten then
		return nil -- a file gone from disk keeps its place on the closed stack: it may come back
	end
	local holder = M.find_buffer_by_filepath(filepath)
	if holder and vim.bo[holder].buftype ~= "" and not M.is_nowrite_file(holder) then
		vim.notify(require('frogman.domains.ui').routines.get_smart_basename(id) ..
			" can't be reopened while another buffer has its name.", vim.log.levels.WARN)
		return nil, "taken"
	end

	local cache
	if filepath:match("^NONAME_") then
		cache = handle.text
		if cache and cache.lines == nil and cache.read then
			cache = cache.read() -- a text from the session file is read only when it's reopened
		end
		if cache == nil then
			-- a No Name buffer with nothing cached (it was empty, or its text is lost) can't be brought
			-- back: it leaves every list with nothing remembered, and wasn't reopened
			M.discard_from_pools(id)
			handle.text = nil
			return nil
		end
	end
	-- the handle's reopen takes the file off every list, its buffer holding a text now, and the trail
	-- gets it from there, off no list too
	local bufnr
	if filepath:match("^NONAME_") then
		bufnr = M.buffer_from_text(cache)
		vim.bo[bufnr].buftype = ""
		local old_filehash = handle.hash
		-- the text keeps its handle under the new id it comes back with, and its reopen links the two
		handles.renamed(old_filehash, M.get_filehash(M.noname_name(bufnr)), { kind = "reopen" })
		M.register_buffer(bufnr, { reopen = true, from = old_filehash })
		if M.get_filepath_from_buffer(bufnr) ~= filepath then
			M.unregister_filepath(filepath) -- This NONAME_ buffer is now irrelevant, we don't want to track it anymore.
		end
	elseif filepath and (vim.fn.filereadable(filepath) == 1 or handle.unwritten) then
		-- a file never written opens as the new file it was
		bufnr = vim.fn.bufadd(filepath)
		vim.bo[bufnr].buflisted = true -- listed before bufload, whose BufEnter only tracks listed buffers.
		vim.fn.bufload(bufnr)
		M.register_buffer(bufnr, { reopen = true })
	end

	if bufnr then
		M.update_buffer_history(bufnr) -- its visit, once
		M.update_buffer_history_ordered()
		return bufnr
	else
		return nil
	end
end

---Hand one file's visits to another, the newer of two staying.
---
---Used when a move takes a name a live handle had: the name's old visits go to the moved file,
---overall, in each window and in each pool, and where the moved file has a visit already, the newer
---of the two stays.
---
---@param from HandleId The handle whose visits go
---@param to HandleId The handle that takes them
---@return nil
function M.merge_history(from, to)
	local cruxes = { data.crux, data.crux_internals.global }
	for _, window_crux in pairs(data.crux_internals.window) do
		table.insert(cruxes, window_crux)
	end
	for _, pool in pairs(M.pools()) do
		table.insert(cruxes, pool.visits)
	end
	for _, crux in ipairs(cruxes) do
		if crux[from] ~= nil then
			crux[to] = math.max(crux[to] or crux[from], crux[from])
			crux[from] = nil
		end
	end
end

---Decide whether a rename was a copy or a move, once the command that made it is over.
---
---The disk decides. If the old name is still a file, it was a copy, and the caller closes the
---old name. If it isn't, or never was (a No Name buffer), it was a move: the moved file keeps its
---handle, which takes the new name's hash, so every slot, note and history entry holding it holds it
---still, and the trail gets the move from the handle's rename. Its buffer was never closed (a No Name
---buffer written under a name is claimed before its close runs), so it's on no list. A live handle
---the new name had is let go, the rename's hooks giving the moved file its place in every window and
---the newer of the two names' visits.
---The buffer is unregistered from the old hash, for the caller to register under the new one. A
---buffer frogman doesn't track is left alone.
---
---@param bufnr Bufnr The renamed buffer
---@param id HandleId The handle of its file before the rename, which still has the old name's hash
---@return string|nil moved_from The old name, when it was a move
function M.settle_rename(bufnr, id)
	local old_hash = M.get_hash_from_handle(id)
	local old_path = M.get_filepath_from_hash(old_hash)
	if
		old_path == nil or
		not M.is_trackable(bufnr) or
		(not old_path:match("^NONAME_") and vim.fn.filereadable(old_path) == 1)
	then
		return nil
	end
	local new_name = vim.api.nvim_buf_get_name(bufnr)
	local new_hash = M.get_filehash(new_name ~= "" and new_name or M.noname_name(bufnr)) -- no name: a No Name buffer's
	local new_label = new_name ~= "" and vim.fs.basename(new_name) or "[No Name]"
	handles.renamed(old_hash, new_hash, { kind = "move", words = (old_path:match("^NONAME_") and "written as " or "renamed to ")
		.. new_label .. ": a move" })
	if data.hash_buffer_registry.hashes[bufnr] == old_hash then
		M.unregister_buffer(bufnr) -- the buffer is registered under its new name next.
	end
	return old_path
end

---@class FrogmanClose A file's close, read when its buffer goes (its delete's event), run once the editor settles
---@field seq integer Its number, so a newer close of the same buffer is told apart
---@field id HandleId The file's handle
---@field hash Filehash The hash its buffer was registered under
---@field bufnr Bufnr The buffer that went
---@field targets string[] The lists it goes on, by their pools' ids
---@field text NoNameBufferContent|nil A No Name buffer's text, copied while the buffer was there

-- counts the closes read, so each is told apart from a newer one of the same buffer
local closes = 0

---Read a buffer's close while the buffer is still there.
---
---A delete reads it at its event: the file's handle, the hash and buffer number it's registered under,
---the lists it goes on, and a No Name buffer's text with its cursor, which the buffer won't have once
---the delete is over. The close itself runs once the editor settles (`M.close()`); until then the
---cleanup and the UI leave the buffer to it.
---
---@param bufnr Bufnr The buffer going
---@param text NoNameBufferContent|nil A No Name buffer's text copied before, to keep in place of what the buffer holds now
---@return FrogmanClose|nil close The close, or nil for a buffer frogman doesn't track
function M.closing(bufnr, text)
	local id = M.get_handle_from_buffer(bufnr)
	if id == nil then
		return nil
	end
	closes = closes + 1
	local hash = M.get_hash_from_handle(id)
	local close = { seq = closes, id = id, hash = hash, bufnr = bufnr, targets = M.close_targets(id) }
	if M.get_filepath_from_hash(hash):match("^NONAME_") then
		local winid = vim.fn.bufwinid(bufnr)
		close.text = text or {
			lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
			filetype = vim.bo[bufnr].filetype,
			-- the close key switches the window away first, so it keeps the cursor on the buffer.
			cursor = winid ~= -1 and vim.api.nvim_win_get_cursor(winid) or vim.b[bufnr].frogman_cursor or { 1, 0 },
		}
	end
	data.closing[bufnr] = close
	return close
end

---Run a close read before (`M.closing()`).
---
---The file goes on its lists and its buffer's registration goes, the handle's close carrying the
---lists' names to the trail. Nothing happens when its handle was let go since, as a load's teardown
---lets every handle go, or when the file isn't registered to that buffer any more, open again in
---another or closed already.
---
---@param close FrogmanClose The close, as read
---@return boolean closed True if the file went on its lists
function M.close(close)
	if data.closing[close.bufnr] and data.closing[close.bufnr].seq == close.seq then
		data.closing[close.bufnr] = nil
	end
	if handles.get(close.id) == nil or data.hash_buffer_registry.buffers[close.hash] ~= close.bufnr then
		return false
	end
	local closed, lists, others = M.track_closing_handle(close)
	if closed then
		-- closed, it's still known, so its history stays; it leaves the bufferline.
		M.unregister_buffer(close.bufnr, { lists = lists, others = others }, close.hash)
		M.update_buffer_history_ordered()
	end
	-- not closed, an empty No Name buffer: its close untracked and forgot it already
	return closed
end

---Run the closes still to settle, whose buffers the screen shows gone already.
---
---What fits frogman's model to the screen asks for it first (`enforce_editor_policy`), so a window
---whose buffer was deleted in the same batch as an earlier arrival is judged with that buffer gone,
---as it is on screen; each close's own queued turn then finds it done. Never inside an autocommand:
---nothing acts inside an event, and a No Name buffer's close waits there for a write that may claim it.
---
---@return nil
function M.run_closes()
	if next(data.closing) == nil or vim.fn.state("x") ~= "" then
		return
	end
	local waiting = vim.tbl_values(data.closing)
	table.sort(waiting, function(a, b) return a.seq < b.seq end)
	for _, close in ipairs(waiting) do
		M.close(close)
	end
end

---Track a closed file for potential reopening.
---
---Its close was read before (`M.closing()`): the buffer registered under the hash it had, a No Name
---buffer's text copied while the buffer was there, and the lists it goes on. A No Name text is kept
---on its handle.
---@param close FrogmanClose The close, as read
---@return boolean success True if the file was added to the closed lists
---@return string[]|nil lists The lists it went on, by name, the current tab's first, when it was added
---@return string[]|nil others Of those, the lists other than the current tab's
function M.track_closing_handle(close)
	local id = close.id
	local handle = handles.get(id)
	local filepath = M.get_filepath_from_handle(id)
	local bufnr = close.bufnr

	if handle == nil or filepath == nil then
		require('frogman.domains.ledger').never("This must not happen: Closing filehash is not registered at all.")
	end
	if M.get_buffer_from_hash(close.hash) ~= bufnr then
		require('frogman.domains.ledger').never("The closing filehash must be registered in the hash_buffer_registry.")
	end

	if filepath:match("^NONAME_") then
		local lines = close.text.lines

		-- Check if buffer is empty (no lines or single empty line)
		local marked = handles.held_beyond(id, handles.WINDOWS_AND_LISTS)
		if (#lines == 0 or (#lines == 1 and lines[1] == "")) and marked then
			-- a marked one keeps its empty text, for its mark alone, and so does one a snapshot holds,
			-- as it holds texts as marks do: closed, and on no list
			handle.text = { lines = { "" }, filetype = close.text.filetype, cursor = close.text.cursor }
			return true, {}, {}
		end
		if #lines == 0 or (#lines == 1 and lines[1] == "") then
			M.untrack_handle(id) -- its own history goes first, and it leaves the slots.
			require('frogman.domains.window.data').forget_handle_in_slots(id)
			-- its close is part of its let-go, which the trail records once its path is forgotten
			M.unregister_buffer(bufnr, { quiet = true }, close.hash)
			M.follow_along() -- the notes about it go, and then its path
			M.unregister_filepath(filepath) -- Yes, remove it from the system entirely. We are not interested in empty no name buffers.
			return false           -- Don't track empty [No Name] buffers
		end

		handle.text = close.text
	end

	-- one copy per pool: a file closed again is the newest
	local lists, others = M.close_into_pools(id, close.targets)
	return true, lists, others
end


---Put a file on the current tab's closed list as its newest entry.
---
---BE CAREFUL: 
---    - This will not check if the file's buffer is registered.
---    - This is not designed for NONAME_ buffers as well!
---
---@param id HandleId The file's handle
---@return nil
function M.track_closing_handle_force(id)
	if id == nil then
		require('frogman.domains.ledger').never("This must not happen: Closing filehash is not registered at all.")
	end

	push_closed(M.current_pool(), id)
end


---Check if a file is on any closed list.
---
---@param id HandleId|nil The file's handle
---@return boolean closed
function M.is_handle_closed(id)
	if id == nil then 
		return false
	end

	for _, pool in pairs(M.pools()) do
		if vim.tbl_contains(pool.closed, id) then
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
			for _, id in ipairs(pool.closed) do
				local filehash = M.get_hash_from_handle(id) -- counted with the file's own, once each
				if filehash then
					files[filehash] = true
				end
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

	local id = closed[#closed]
	local bufnr, reason = M.reopen_handle(id)
	if bufnr then
		vim.api.nvim_set_current_buf(bufnr)
	elseif closed[#closed] == id and reason ~= "taken" then
		vim.notify(require('frogman.domains.ui').routines.get_smart_basename(id) ..
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
		local current_bufnr, reason = triquetra and M.get_buffer_from_handle(triquetra.current_slot), nil
		if triquetra and not current_bufnr then
			current_bufnr, reason = M.reopen_handle(triquetra.current_slot)
		end
		if current_bufnr and vim.api.nvim_buf_is_valid(current_bufnr) then
			vim.api.nvim_win_set_buf(winid, current_bufnr)
		elseif triquetra and M.get_filepath_from_handle(triquetra.current_slot) and reason ~= "taken" then
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

---Get the handle of a registered buffer's file.
---
---@param bufnr Bufnr|nil The buffer
---@return HandleId|nil id The file's handle, or nil when the buffer isn't registered
function M.get_handle_from_buffer(bufnr)
	local handle = handles.of_hash(M.get_hash_from_buffer(bufnr))
	return handle and handle.id or nil
end

---Get the handle of a file the path registry knows, by its path.
---
---@param filepath Filepath|nil The file's path, or a No Name text's NONAME_ name
---@return HandleId|nil id The file's handle, or nil when the path isn't known
function M.get_handle_from_filepath(filepath)
	local handle = handles.of_hash(M.get_hash_from_filepath(filepath))
	return handle and handle.id or nil
end

---Get the handle of a file by its name's hash, as a session file holds it.
---
---@param filehash Filehash|nil The hash
---@return HandleId|nil id The file's handle, or nil when no handle has the hash
function M.get_handle_from_hash(filehash)
	local handle = handles.of_hash(filehash)
	return handle and handle.id or nil
end

---Get a table keyed by the files' handles keyed by their hashes, as a session file or a dump holds it.
---
---A handle let go since is left out.
---
---@param by_handle table<HandleId, any>|nil The table, as memory holds it
---@return table<Filehash, any> by_hash The same values, by the files' hashes
function M.keyed_by_hash(by_handle)
	local out = {}
	for id, value in pairs(by_handle or {}) do
		local filehash = M.get_hash_from_handle(id)
		if filehash then
			out[filehash] = value
		end
	end
	return out
end

---Get a table a session file or a dump keys by the files' hashes keyed by their handles, as memory holds it.
---
---A hash no handle has is left out.
---
---@param by_hash table<Filehash, any>|nil The table, as the file holds it
---@return table<HandleId, any> by_handle The same values, by the files' handles
function M.keyed_by_handle(by_hash)
	local out = {}
	for filehash, value in pairs(type(by_hash) == "table" and by_hash or {}) do
		local id = M.get_handle_from_hash(filehash)
		if id then
			out[id] = value
		end
	end
	return out
end

---Get a list of files' handles as their hashes, in order, as a session file or a dump holds it.
---
---A handle let go since is left out, so the list has no holes.
---
---@param ids HandleId[]|nil The files' handles
---@return Filehash[] hashes Their hashes, in order
function M.hashes_of(ids)
	local out = {}
	for _, id in ipairs(ids or {}) do
		table.insert(out, M.get_hash_from_handle(id))
	end
	return out
end

---Get a list of files' hashes, as a session file or a dump holds it, as their handles, in order.
---
---A hash no handle has is left out, so the list has no holes.
---
---@param hashes Filehash[]|nil The files' hashes
---@return HandleId[] ids Their handles, in order
function M.handles_of(hashes)
	local out = {}
	for _, filehash in ipairs(type(hashes) == "table" and hashes or {}) do
		table.insert(out, M.get_handle_from_hash(filehash))
	end
	return out
end

---Get where each file gone from disk went missing, by hash, from the handles' tags.
---
---Only the files frogman knows, those a strong holder holds: a handle about to be let go saves nothing.
---
---@return table<Filehash, string> tags Each tagged file's hash → its tag
function M.tags_by_hash()
	local tags = {}
	for _, handle in pairs(handles.live()) do
		if handle.tag and next(handle.holders) ~= nil then
			tags[handle.hash] = handle.tag
		end
	end
	return tags
end

---Get the hash of a file's name now, from its handle.
---
---@param id HandleId|nil The file's handle
---@return Filehash|nil filehash The hash, or nil once the handle is let go
function M.get_hash_from_handle(id)
	local handle = id and handles.get(id)
	return handle and handle.hash or nil
end

---Get a file's path from its handle.
---
---@param id HandleId|nil The file's handle
---@return Filepath|nil filepath The path, or a No Name text's NONAME_ name, or nil once the handle is let go
function M.get_filepath_from_handle(id)
	return M.get_filepath_from_hash(M.get_hash_from_handle(id))
end

---Get the buffer a file is open in, from its handle.
---
---@param id HandleId|nil The file's handle
---@return Bufnr|nil bufnr The buffer, or nil when the file has none
function M.get_buffer_from_handle(id)
	return M.get_buffer_from_hash(M.get_hash_from_handle(id))
end

---A short routine on cleaning up the buffer from the system
---
---Drops the file's history, overall and in each window, and its buffer's registration. Its
---path stays registered, and no Neovim buffer is touched.
---
---@param filepath Filepath The file's path, or a No Name text's NONAME_ name
---@param filehash Filehash The hash of the file's name, as the registry knows it
---@param context HandleContext|nil What its close is, for the trail: a repair's words
---@return nil
local function detach_filehash_from_crux(filepath, filehash, context)
	if filehash == nil then
		return
	end
	local handle = handles.of_hash(filehash)
	if handle then
		data.crux[handle.id] = nil
		data.crux_internals.global[handle.id] = nil
		for winid, _ in pairs(data.crux_internals.window) do
			data.crux_internals.window[winid][handle.id] = nil
		end
	end
	local bufnr = data.hash_buffer_registry.buffers[filehash]
	if bufnr then
		data.hash_buffer_registry.hashes[bufnr] = nil
	end
	data.hash_buffer_registry.buffers[filehash] = nil
	handles.closed(filehash, context)
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
		if vim.api.nvim_buf_is_valid(bufnr) or data.closing[bufnr] then
			goto continue -- a buffer whose delete's close waits for the editor to settle is that close's
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
		local handle = handles.of_hash(filehash)
		if filepath and not filepath:match("^NONAME_") and handle then
			local lists
			if not M.is_handle_closed(handle.id) then
				lists = M.close_into_pools(handle.id)
			else
				local holding = {}
				for _, pool in pairs(M.pools()) do
					if vim.tbl_contains(pool.closed, handle.id) then
						holding[pool] = true
					end
				end
				lists = named_lists(holding)
			end
			-- closed, it's still known, so its history stays: only its buffer is forgotten. The trail gets
			-- the repair from its handle's close.
			data.hash_buffer_registry.hashes[bufnr] = nil
			data.hash_buffer_registry.buffers[filehash] = nil
			handles.closed(filehash, { lists = lists, repair = "its buffer vanished without an event; kept on the closed lists" })
		else
			detach_filehash_from_crux(filepath, filehash, { repair = "its buffer vanished without an event, and its text with it" })
		end
		report.stale_hash_entries = report.stale_hash_entries + 1
		::continue::
	end
	
	-- 2. Clean invalid closed buffers (entries nothing names, or open again). A closed file gone from
	-- disk stays: it may come back.
	for pool_id, pool in pairs(M.pools()) do
		for i = #pool.closed, 1, -1 do
			local id = pool.closed[i]
			local filehash = M.get_hash_from_handle(id)
			local filepath = M.get_filepath_from_hash(filehash)
			if filepath and M.get_buffer_from_hash(filehash) == nil then
				goto continue
			end

			require('frogman.domains.ledger').move("repair", {
				subject = filehash, name = filehash and require('frogman.domains.ledger').name_of(filehash) or tostring(id),
				lists = { M.list_name(pool) },
				state = filepath and "open" or nil,
				words = filepath and "open again without a visit frogman saw; taken off its list"
					or "nothing names it; taken off its list",
			})
			table.remove(pool.closed, i)
			pool.times[id] = nil
			changed(pool)
			if filepath then -- open again: the pool is remembered for its next close
				data.came_from[id] = data.came_from[id] or {}
				data.came_from[id][pool_id] = true
			end
			::continue::
		end
	end

	-- 1. Follow along: the notes and history of hashes no longer known go, and then their paths. A
	-- registered buffer stays whatever the disk says: its file may not be written yet, or may come back.
	local known = M.known_handles()
	for id, _ in pairs(data.crux_internals.global) do
		if not known[id] then
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
	end

	-- a window or a tab closed without its events, by noautocmd or while frogman was off: what it marked
	-- and its snapshots are held over, as a close holds them over
	require('frogman.domains.marks').routines.hold_over_gone()
	require('frogman.domains.snapshots').routines.hold_over_gone()

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
	data.ordered = { crux = {} }
	data.history_index = 1
	data.hash_buffer_registry = { buffers = {}, hashes = {} }
	data.hash_filepath_registry = { filepaths = {}, hashes = {} }
	data.cycling_origins = {}
	data.closed_buffers = {}
	data.last_label = nil
	data.label_seen = false
	handles.reset()
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
	handles.reset()
	M.reset_pools()

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
			M.update_buffer_history(bufnr)
		end
	end
	M.update_buffer_history_ordered()
end

return M
