---What a close holds over, a window's marks and its snapshots alike.
---
---This module names what's held over and waits for the editor to settle before holding it, so a
---close that turns out to be a tab's, or a load, can drop it first; it lets a closed window's data
---go once the close is over, tells a session its held-over records changed, and keeps the session
---each window was last seen in. The marks and the snapshots both hold over through it, so their
---headers and their waits can't go apart.

local M = {}

-- the waits queued so far, numbered in order
local waits = 0

-- the windows whose data waits for their close to be over, each with how many waits it has
local closing = {}

-- the session each window was last seen in and the buffer it showed then, with that buffer's name, for
-- one that closes without its WinClosed
local seen = {}

-- the buffer each tab's current window showed when it was last seen, with its name, for a tab that
-- closes without its events
local seen_tabs = {}

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

---Wait for the editor to settle before doing what a close left, in a queue a load or a tab's close
---can drop from.
---
---The entry runs as settle work, so a key later in the same batch, or a quit, runs it first, unless
---it's off the queue by then.
---
---A tab session's last window waits on a plain tick instead, out of the settle queue, so a save its
---tab's close runs drains nothing of it: once its tab has closed, its session ended there, and `ended`
---lets it go; a tab another window keeps open has it held over, as at any close.
---
---@param queue fun(): table[] The queue as it is when the tick comes, each entry with the `tab` it came from
---@param entry table
---@param run fun(entry: table)
---@param ended fun(entry: table)|nil For a tab session's last window: what lets it go once its tab has closed
---@return nil
function M.wait_a_tick(queue, entry, run, ended)
	waits = waits + 1
	entry.seq = waits -- so a tab's close drops only what was queued once it began
	table.insert(queue(), entry)
	local function turn()
		-- one a teardown or a load dropped meanwhile isn't there any more
		for i, waiting in ipairs(queue()) do
			if waiting == entry then
				table.remove(queue(), i)
				if ended and not vim.api.nvim_tabpage_is_valid(entry.tab) then
					ended(entry) -- the session ended with its tab: its marks and snapshots live on its entry
				else
					run(entry)
				end
				return
			end
		end
	end
	if ended then
		vim.schedule(turn)
	else
		require('frogman.settle').later("hold over", turn)
	end
end

---Check if a window closing takes a tab session's tab with it, a detached list's aside: its session
---ends there, unless another window keeps the tab open.
---
---@param winid WinId The window closing
---@return boolean ends Whether its tab session's tab closes with it
function M.ends_session(winid)
	if not M.closes_tab(winid) then
		return false
	end
	local history = require('frogman.domains.history')
	local pool = history.data.pools[history.data.tab_pools[vim.api.nvim_win_get_tabpage(winid)] or ""]
	return pool ~= nil and pool.id ~= "" and not pool.detached
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

---Let a closed window's data go once its close is over: at once, or, for a window that takes its tab
---with it, on the next tick, after the tab's TabClosedPre, which may save it whole, and its TabClosed.
---A tab another window keeps open, as a plugin's WinClosed that splits into it does, still has it go
---then.
---
---@param winid WinId The window closing
---@param drop fun() What lets its data go
---@return nil
function M.after_close(winid, drop)
	if not M.closes_tab(winid) then
		drop()
		return
	end
	closing[winid] = (closing[winid] or 0) + 1
	vim.schedule(function()
		closing[winid] = closing[winid] > 1 and closing[winid] - 1 or nil
		if not vim.api.nvim_win_is_valid(winid) then
			drop()
		end
	end)
end

---Check if a window that's gone still has data waiting for its close to be over.
---
---@param winid WinId The window gone
---@return boolean waiting Whether its data still waits
function M.closing(winid)
	return closing[winid] ~= nil
end

---Tell a session its held-over records changed, as a change to its closed list does, when the change
---is made while storage is idle: a load's own restoring isn't a change.
---
---@param session_id string The session's pool id ("" for the whole editor's)
---@return nil
function M.records_changed(session_id)
	local notify = require('frogman.domains.history').routines.on_records_change
	if notify and require('frogman.domains.storage.sm'):state() == require('frogman.domains.storage.states').IDLE then
		notify(session_id)
	end
end

---Note the session a window is in now and the buffer it shows, and the buffer its tab shows when it's the
---tab's current window, each with its name now. A note is taken inside events and a save, so a name that
---can't be looked up keeps what was noted before rather than failing them.
---
---@param winid WinId The window seen
---@return nil
function M.note_session(winid)
	if winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_config(winid).relative == "" then
		local tabpage = vim.api.nvim_win_get_tabpage(winid)
		local bufnr = vim.api.nvim_win_get_buf(winid)
		local found, shows = pcall(function()
			return require('frogman.domains.marks').routines.name_of(bufnr)
		end)
		if not found then
			local was = seen[winid]
			bufnr, shows = was and was.bufnr, was and was.shows
		end
		seen[winid] = { session = require('frogman.domains.history').data.tab_pools[tabpage] or "", bufnr = bufnr, shows = shows }
		if found and vim.api.nvim_tabpage_get_win(tabpage) == winid then
			seen_tabs[tabpage] = { bufnr = bufnr, shows = shows }
		end
	end
end

---Note every window of a tab as it joins a session, so one not seen since goes by the tab's session.
---
---@param tabpage integer The tab joining
---@return nil
function M.note_tab(tabpage)
	for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		M.note_session(winid)
	end
end

---Get the session a window that's gone was last seen in, while that session is still known.
---
---@param winid WinId The window gone
---@return string|nil session_id Its pool id ("" for the whole editor's), or nil when none was seen
function M.last_session(winid)
	local id = seen[winid] and seen[winid].session
	if id and id ~= "" and not require('frogman.domains.history').data.pools[id] then
		return "" -- its session went since: the whole editor's
	end
	return id
end

---Get what a window or a tab that's gone was, as a held-over header names it: the buffer it showed when
---it was last seen, named as a close names it, by its file's unique name while frogman has it taken in,
---or else by the name noted then.
---
---@param kind "window"|"tab" Whether it was a window or a tab
---@param id WinId|integer The window or the tab gone
---@return string what Like "window on api.lua", or "window" alone when it was never seen
function M.last_seen_as(kind, id)
	local last = (kind == "window" and seen or seen_tabs)[id]
	if last == nil then
		return kind
	end
	local found, name = pcall(function()
		if last.bufnr and vim.api.nvim_buf_is_valid(last.bufnr)
			and require('frogman.domains.history').get_handle_from_buffer(last.bufnr) then
			return require('frogman.domains.marks').routines.name_of(last.bufnr)
		end
	end)
	local shows = found and name or last.shows
	return shows and (kind .. " on " .. shows) or kind
end

---Forget where a window was seen and what it showed, as it closes with its WinClosed.
---
---@param winid WinId The window closing
---@return nil
function M.forget_session(winid)
	seen[winid] = nil
end

---Forget what was seen of the windows and tabs that are gone, once the passes that hold over what those
---closed without their events left have read it.
---
---@return nil
function M.forget_gone()
	for winid, _ in pairs(seen) do
		if not vim.api.nvim_win_is_valid(winid) then
			seen[winid] = nil
		end
	end
	for tabpage, _ in pairs(seen_tabs) do
		if not vim.api.nvim_tabpage_is_valid(tabpage) then
			seen_tabs[tabpage] = nil
		end
	end
end

---Check if a session owns a scope of marks or snapshots: with no session, every scope; a window or a
---tab when it's in the session's tabs; a session's scope its own, the whole editor's taking the
---detached lists' too.
---
---@param owner Pool|nil The session's pool (nil = every session)
---@param kind "window"|"tab"|"session" The scope's kind
---@param id any The window, the tab page, or the session's pool id
---@return boolean owns Whether the scope is the session's
function M.owns(owner, kind, id)
	if owner == nil then
		return true
	end
	local history = require('frogman.domains.history')
	if kind == "window" then
		return vim.api.nvim_win_is_valid(id) and M.owns(owner, "tab", vim.api.nvim_win_get_tabpage(id))
	elseif kind == "tab" then
		return vim.api.nvim_tabpage_is_valid(id) and history.routines.pool_of_tab(id) == owner
	end
	local pool = history.data.pools[id]
	return id == owner.id or (owner.id == "" and pool ~= nil and pool.detached == true)
end

---Get the hashes of the files a session's marks and snapshots hold, both at once.
---
---@param owner Pool|nil The session's pool (nil = every mark's and snapshot's)
---@return table<Filehash, boolean> held
function M.files_held(owner)
	local held = require('frogman.domains.marks').routines.held_by(owner)
	for filehash, _ in pairs(require('frogman.domains.snapshots').routines.held_by(owner)) do
		held[filehash] = true
	end
	return held
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
---@param after integer|nil Only what was queued after this wait (nil = all of it)
---@return nil
function M.drop_waiting(queue, tabpage, dropped, after)
	for i = #queue, 1, -1 do
		if queue[i].tab == tabpage and (after == nil or (queue[i].seq or 0) > after) then
			dropped(table.remove(queue, i))
		end
	end
end

return M
