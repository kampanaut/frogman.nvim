local data = require('frogman.domains.history.data')
local handles = require('frogman.domains.history.handles')

---The closed lists, each one a `Pool`, which every write to it goes through.
---
---A list holds its closed files by its place, as a triquetra holds its slots by theirs, and keeps
---its two rules at every change: a file is on it once at most (I22), and no file on it has a buffer
---registered (I7). A change that would break one is refused, the list staying as it was, and it
---dumps, since only a bug can cause it. The editor's list is made as this module loads.
local M = {}

---@class Pool A session's own closed stack, close times and visits
---@field id string Pool id: "" for the editor's, the tab session's name and directory, or a detached list's
---@field name string|nil The tab session's name, or the detached list's
---@field directory string|nil The tab session's directory
---@field closed HandleId[] Stack of closed buffer handles that can be reopened via hash_filepath_registry, newest last
---@field times table<HandleId, number> File's handle → close time, in seconds to the microsecond
---@field visits table<HandleId, integer> Its own visits, ranked above the editor's in its tab
---@field tabs table<integer, boolean> Tabs it's in (tabpage → true), none if its last tab closed unsaved
---@field detached boolean|nil Whether it's a detached list: a tab's own once its session moved to another tab
---@field of string|nil For a detached list, the id of the session it was detached from
---@field merging boolean|nil Whether a detached list waits in memory for the closed lists opened on it to close
local Pool = {}
Pool.__index = Pool
M.Pool = Pool

---Make a list, and put it among the pools.
---
---The editor's is made as this module loads and again at a teardown, a tab session's when it's first
---needed, and a detached list's as its tab is pushed out. A list made under the id of one in memory
---takes its place, the old one let go first.
---
---@param fields table Its id, and its name, directory, detached and of where it has them
---@return Pool pool The new list, empty
function M.new(fields)
	if data.pools[fields.id] then
		data.pools[fields.id]:drop()
	end
	local pool = setmetatable({
		id = fields.id, name = fields.name, directory = fields.directory, detached = fields.detached, of = fields.of,
		closed = {}, times = {}, visits = {}, tabs = {},
	}, Pool)
	data.pools[pool.id] = pool
	return pool
end

---Get the editor's list.
---@return Pool pool The editor's list
function M.editor()
	return data.pools[""] or M.new({ id = "" })
end

---Get the name of the list's place, as the handles' holders know it.
---@return string place "pool:editor", or "pool:" and the list's id, the session's name and directory
function Pool:place()
	return "pool:" .. (self.id == "" and "editor" or self.id) -- the id as it is, so two never read alike
end

---Make one change to the list: the files and close times it holds after it.
---
---A change that would leave a file on it twice, or a file whose buffer is registered, is refused: the
---list stays as it was, and it dumps. Kept, the list is written in place, so what reads it keeps the
---same table, its files are held by its place, and storage is told its session's records changed,
---but for a load's or a reset's own change, which isn't news to the session's file.
---
---@param closed HandleId[] The files it holds after the change, newest last, a table of its own
---@param times table<HandleId, number> Their close times, a table of its own
---@param quiet boolean|nil Whether it's a load's or a reset's own change
---@return nil
function Pool:change(closed, times, quiet)
	local seen = {}
	for _, id in ipairs(closed) do
		if seen[id] then
			require('frogman.domains.ledger').never("Refused a change putting one file twice on a closed list.")
		end
		seen[id] = true
		local handle = handles.get(id)
		if handle and data.hash_buffer_registry.buffers[handle.hash] ~= nil then
			require('frogman.domains.ledger').never("Refused a change putting an open file on a closed list.")
		end
	end
	for i = #self.closed, 1, -1 do
		self.closed[i] = nil
	end
	vim.list_extend(self.closed, closed)
	for id, _ in pairs(self.times) do
		self.times[id] = nil
	end
	for id, time in pairs(times) do
		self.times[id] = time
	end
	handles.hold(self:place(), self.closed)
	local notify = not quiet and require('frogman.domains.history.routines').on_records_change
	if notify then
		notify(self.id)
	end
end

---Put a file on the list as its newest entry.
---
---A list keeps one copy of each file, so an older entry for it comes off first: a file closed again
---is the newest.
---
---@param id HandleId The file's handle
---@param time number|nil When it was closed (nil = now)
---@param quiet boolean|nil Whether it's a load's or a reset's own change
---@return nil
function Pool:push(id, time, quiet)
	local closed = vim.tbl_filter(function(other) return other ~= id end, self.closed)
	table.insert(closed, id)
	local times = vim.deepcopy(self.times)
	-- to the microsecond, so closes in one second keep their order
	times[id] = time or require('frogman.domains.ledger').now()
	self:change(closed, times, quiet)
end

---Put a file on the list as its oldest entry, under its own.
---
---@param id HandleId The file's handle
---@param time number|nil When it was closed (nil = no close time, older than any)
---@param quiet boolean|nil Whether it's a load's or a reset's own change
---@return nil
function Pool:push_oldest(id, time, quiet)
	local closed = { id }
	vim.list_extend(closed, self.closed)
	local times = vim.deepcopy(self.times)
	times[id] = time
	self:change(closed, times, quiet)
end

---Take a file off the list.
---
---@param id HandleId The file's handle
---@param quiet boolean|nil Whether it's a load's or a reset's own change
---@return boolean held True if the list held it
function Pool:remove(id, quiet)
	if not vim.tbl_contains(self.closed, id) then
		return false
	end
	local times = vim.deepcopy(self.times)
	times[id] = nil
	self:change(vim.tbl_filter(function(other) return other ~= id end, self.closed), times, quiet)
	return true
end

---Put a whole list in place of the list's: a load's fill, the closed lists' write.
---
---@param closed HandleId[] The files, newest last
---@param times table<HandleId, number> Their close times
---@param quiet boolean|nil Whether it's a load's or a reset's own change
---@return nil
function Pool:replace(closed, times, quiet)
	self:change(vim.list_slice(closed, 1, #closed), vim.deepcopy(times), quiet)
end

---Let the list go: out of the pools, and everything it held let go.
---@return nil
function Pool:drop()
	handles.drop_place(self:place())
	if data.pools[self.id] == self then
		data.pools[self.id] = nil
	end
end

-- a file open again is closed nowhere: it leaves every list, which remembers it for its next close, and
-- the lists' names go to the trail
handles.model:on(handles.states.CLOSED, handles.states.OPEN, "off_the_lists", function(context, handle)
	local routines = require('frogman.domains.history.routines')
	context.left, context.others = routines.open_out_of_pools(handle.id)
	-- a file never written comes back as a new one, which the trail says
	local filepath = routines.get_filepath_from_hash(context.hash)
	context.new = handle.unwritten ~= nil and filepath ~= nil and not filepath:match("^NONAME_")
		and vim.fn.filereadable(filepath) == 0 or nil
end, 2, true)

-- a file let go takes with it the lists it came off, which only its next close would read
handles.model:on("*", "*", "came_from_let_go", function(_, handle)
	data.came_from[handle.id] = nil
end, 6, true, handles.states.mode.FORGET)

M.editor()

return M
