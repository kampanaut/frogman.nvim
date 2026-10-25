---Settle queue for the work cavediver puts off until the editor settles.
---
---This module queues the work an event leaves for later when that work changes what cavediver
---knows about the editor. While anything is queued, cavediver isn't settled. A key runs what's
---still queued before acting, so keys in one batch (a macro, a mapping) act as if they were
---typed by hand.
---
---Everything queued ends in `run()`, whichever reaches it first: its own scheduled turn, which
---`later()` books as it queues it, or a drain that comes sooner. `run()` keeps track of what ran
---and what's still queued, so each item runs once. `now()` runs everything still queued first,
---then the key's own job, and no drain starts until that job is done.

local M = {}

---The work still queued, oldest first
---@type { name: string, fn: function, done: boolean }[]
local queue = {}

---How many of cavediver's key jobs and queued items are running now. At 0 a drain may run the
---queue. 1 is one job or one item, the most cavediver's own code reaches. 2 or more is a job
---running inside another, when code a job calls (a provider, a formatter, an autocmd on an event
---the job causes) runs a key's job of its own.
---@type integer
local working_count = 0

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
	working_count = working_count + 1
	local ok, err = xpcall(item.fn, debug.traceback)
	working_count = working_count - 1
	if not ok then
		vim.schedule(function()
			error(err, 0)
		end)
	end
end

---Queue settle work, to run once the editor settles.
---
---The work runs by itself on `vim.schedule`, as it would without the queue, unless a key runs
---it first. Its own turn waits while a key's job or an item is running, as one can be while it
---waits at a prompt, which lets the event loop run.
---
---@param name string Name of the work, as the dump lists it ("arrival b.txt")
---@param fn function The work to run
---@return nil
function M.later(name, fn)
	local item = { name = name, fn = fn, done = false }
	table.insert(queue, item)
	local function own_turn()
		if not item.done and working_count > 0 then
			vim.defer_fn(own_turn, 10) -- a job is still running: the item runs once it's done
			return
		end
		run(item)
	end
	vim.schedule(own_turn)
end

---Run all the settle work still queued, oldest first.
---
---Work queued while it runs is run too. Does nothing inside a key or a running item, so
---nothing runs out of its order. A drain skipped that way isn't put off: what's queued still
---runs on its own turn.
---
---@return nil
function M.drain()
	if working_count > 0 then
		return
	end
	while queue[1] do
		run(queue[1])
	end
end

---Run a key's job once cavediver has settled.
---
---Drains the queue, then runs the job. No drain starts until the job is done, so the work
---the key queues itself keeps its order. The job's error is raised again as it was raised, and
---a Lua error is dumped first, with its traceback.
---
---@param fn function The key's job
---@param ... any The job's arguments
---@return any ... The job's results
function M.now(fn, ...)
	M.drain()
	working_count = working_count + 1
	-- the job's error comes back as it was raised; at its site, with the stack still whole, the dump
	-- takes it with its traceback
	local results = { xpcall(fn, function(err)
		pcall(require('cavediver.domains.ledger.dump').key_failed, err, debug.traceback("", 2))
		return err
	end, ...) }
	working_count = working_count - 1
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
