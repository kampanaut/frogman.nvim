---Settle queue for the work cavediver puts off until the editor settles.
---
---This module queues the work an event leaves for later when that work changes what cavediver
---knows about the editor. While anything is queued, cavediver isn't settled. A key runs what's
---still queued before acting, so keys in one batch (a macro, a mapping) act as if they were
---typed by hand.

local M = {}

---The work still queued, oldest first
---@type { name: string, fn: function, done: boolean }[]
local queue = {}

---How many keys or queued items are running now (no drain starts inside one)
---@type integer
local busy = 0

---Run one item of the queue, once.
---
---Takes it off the queue before running it, so whichever runs it (a drain or its own schedule),
---the other finds it done. An error is reported the way a scheduled callback's is, and doesn't
---stop the rest.
---
---@param item { name: string, fn: function, done: boolean } The queued item
---@return nil
local function run(item)
	if item.done then
		return
	end
	item.done = true
	for i, queued in ipairs(queue) do
		if queued == item then
			table.remove(queue, i)
			break
		end
	end
	busy = busy + 1
	local ok, err = xpcall(item.fn, debug.traceback)
	busy = busy - 1
	if not ok then
		vim.schedule(function()
			error(err, 0)
		end)
	end
end

---Queue settle work, to run once the editor settles.
---
---The work runs by itself on `vim.schedule`, as it would without the queue, unless a key runs
---it first.
---
---@param name string Name of the work, as the dump lists it ("arrival b.txt")
---@param fn function The work to run
---@return nil
function M.later(name, fn)
	local item = { name = name, fn = fn, done = false }
	table.insert(queue, item)
	vim.schedule(function()
		run(item)
	end)
end

---Run all the settle work still queued, oldest first.
---
---Work queued while it runs is run too. Does nothing inside a key or a running item, so
---nothing runs out of its order.
---
---@return nil
function M.drain()
	if busy > 0 then
		return
	end
	while queue[1] do
		run(queue[1])
	end
end

---Run a key's job once cavediver has settled.
---
---Drains the queue, then runs the job. No drain starts until the job is done, so the work
---the key queues itself keeps its order. The job's error is raised again as it was raised.
---
---@param fn function The key's job
---@param ... any The job's arguments
---@return any ... The job's results
function M.guard(fn, ...)
	M.drain()
	busy = busy + 1
	local results = { pcall(fn, ...) } -- the job's error comes back as it was raised
	busy = busy - 1
	if not results[1] then
		error(results[2], 0)
	end
	return unpack(results, 2, table.maxn(results))
end

---Get the names of the settle work still queued, oldest first.
---
---@return string[] names Names of the work still to run, as `M.later()` got them
function M.pending()
	local names = {}
	for _, item in ipairs(queue) do
		table.insert(names, item.name)
	end
	return names
end

return M
