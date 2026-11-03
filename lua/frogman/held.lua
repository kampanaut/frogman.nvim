---What a close holds over, a window's marks and its snapshots alike.
---
---This module names what's held over and waits a tick before holding it, so a close that turns
---out to be a tab's, or a load, can drop it first. The marks and the snapshots both hold over
---through it, so their headers and their waits can't go apart.

local M = {}

-- the waits queued so far, numbered in order
local waits = 0

---Get a held-over header, a group's or a snapshot's: what it was and when, numbered on when the
---names where it goes have it already.
---
---@param what string What it was, like "window on api.lua" or "proj, loaded into tab 2"
---@param taken table<string, true> The names where it goes
---@return string header Like "held over · window on api.lua · 10-31 13:05"
function M.held_header(what, taken)
	local base = "held over · " .. what .. " · " .. os.date("%m-%d %H:%M")
	local name, n = base, 1
	while taken[name] do
		n = n + 1
		name = base .. " #" .. n
	end
	return name
end

---Wait a tick before doing what a close left, in a queue a load or a tab's close can drop from.
---
---The entry runs once the editor settles, unless it's off the queue by then.
---
---@param queue fun(): table[] The queue as it is when the tick comes, each entry with the `tab` it came from
---@param entry table
---@param run fun(entry: table)
---@return nil
function M.wait_a_tick(queue, entry, run)
	waits = waits + 1
	entry.seq = waits -- so a tab's close drops only what was queued once it began
	table.insert(queue(), entry)
	vim.schedule(function()
		-- one a teardown or a load dropped meanwhile isn't there any more
		for i, waiting in ipairs(queue()) do
			if waiting == entry then
				table.remove(queue(), i)
				run(entry)
				return
			end
		end
	end)
end

---Check if a window closing takes its tab with it: the tab's last window but its floats, with another
---tab left. Its `WinClosed` then fires ahead of the tab's `TabClosedPre`, the window still in the tab.
---
---@param winid WinId The window closing
---@return boolean closes Whether its tab closes with it
function M.closes_tab(winid)
	if #vim.api.nvim_list_tabpages() < 2 then
		return false
	end
	for _, other in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(winid))) do
		if other ~= winid and vim.api.nvim_win_get_config(other).relative == "" then
			return false
		end
	end
	return true
end

---Get the number of the last wait queued, which a tab's close notes as it begins.
---@return integer
function M.last_wait()
	return waits
end

---Drop what a queue holds from a tab, each entry handed to `dropped` as it goes.
---
---@param queue table[]
---@param tabpage integer
---@param dropped fun(entry: table)
---@param after integer|nil Only what was queued after this wait, and what a window that took the tab with it queued (nil = all of it)
---@return nil
function M.drop_waiting(queue, tabpage, dropped, after)
	for i = #queue, 1, -1 do
		if queue[i].tab == tabpage and (after == nil or (queue[i].seq or 0) > after or queue[i].last) then
			dropped(table.remove(queue, i))
		end
	end
end

return M
