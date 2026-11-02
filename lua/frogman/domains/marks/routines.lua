---Marks domain routines.
---
---This module contains the marks' business logic: which scope a mode reads, the groups and their
---default, the add and the jump, and what the bufferline and the winbar show of them.

local data = require('frogman.domains.marks.data')
local history = require('frogman.domains.history')

local M = {}

---How long the winbar says what an add did, in milliseconds
---@type integer
local FLASH_MS = 2000

---Get the scope a mode reads in a window.
---
---A window's mode reads the window, a tab's its tab, and a session's the tab session the tab is in, or
---the whole editor's. In a tab session's tab, the tab's mode is the session's.
---
---@param mode "window"|"tab"|"session"
---@param winid WinId|nil The window (nil = the current one)
---@return "window"|"tab"|"session" kind The scope's kind
---@return any id The window, the tab page, or the session's pool id ("" for the whole editor's)
function M.scope_key(mode, winid)
	winid = winid or vim.api.nvim_get_current_win()
	if mode == "window" then
		return "window", winid
	end
	local session = history.data.tab_pools[vim.api.nvim_win_get_tabpage(winid)]
	if mode == "tab" and session == nil then
		return "tab", vim.api.nvim_win_get_tabpage(winid)
	end
	return "session", session or ""
end

---Get a scope.
---
---@param kind "window"|"tab"|"session"
---@param id any
---@param create boolean|nil Whether to make it when it's not there
---@return MarksScope|nil scope
function M.scope(kind, id, create)
	local scopes = data.scopes[kind]
	if scopes[id] == nil and create then
		scopes[id] = { groups = {} }
	end
	return scopes[id]
end

---Get a scope's first group that isn't held over, the one the keys use.
---
---A scope with none gets its default group, named by the config, first, ahead of what's held over.
---
---@param scope MarksScope|nil
---@param create boolean|nil Whether to make the default group when there's none
---@return MarksGroup|nil group
function M.first_group(scope, create)
	if scope == nil then
		return nil
	end
	for _, group in ipairs(scope.groups) do
		if not group.held then
			return group
		end
	end
	if create then
		table.insert(scope.groups, 1, { name = require('frogman.configs').marks.default_group, marks = {} })
		return scope.groups[1]
	end
	return nil
end

---Get the handle a mark holds now.
---
---A handle let go for a moved file that took its name is followed to the moved file's, and the mark
---keeps that one from then on.
---
---@param group MarksGroup
---@param alias string
---@return FileHandle|nil handle
function M.handle_of(group, alias)
	local id = group.marks[alias]
	if id == nil then
		return nil
	end
	local resolved = history.handles.resolve(id)
	group.marks[alias] = resolved
	return history.handles.get(resolved)
end

---Get the name of a mark's holder place.
---
---@param kind string
---@param id any
---@param position integer The group's position in the scope
---@param alias string
---@return string place Like "mark:session::1:a"
local function place_of(kind, id, position, alias)
	return "mark:" .. kind .. ":" .. tostring(id) .. ":" .. position .. ":" .. alias
end

---Hold the files a scope's marks hold, each by its place.
---
---The new places hold first and the ones it no longer has let go after, so a mark that stays is
---never left with nothing holding its file in between.
---
---@param kind "window"|"tab"|"session"
---@param id any
---@return nil
function M.hold_scope(kind, id)
	local scope = data.scopes[kind][id]
	local key = kind .. ":" .. tostring(id)
	local now = {}
	for position, group in ipairs(scope and scope.groups or {}) do
		for alias, _ in pairs(group.marks) do
			local handle = M.handle_of(group, alias)
			if handle then
				local place = place_of(kind, id, position, alias)
				history.handles.hold(place, { handle.hash })
				now[place] = true
			end
		end
	end
	for place, _ in pairs(data.places[key] or {}) do
		if not now[place] then
			history.handles.drop_place(place)
		end
	end
	data.places[key] = next(now) and now or nil
end

---Let a scope go, and everything its marks held.
---
---@param kind "window"|"tab"|"session"
---@param id any
---@return nil
function M.drop_scope(kind, id)
	data.scopes[kind][id] = nil
	M.hold_scope(kind, id)
end

---Let every scope go, as a whole-editor load from idle starts from nothing.
---
---@return nil
function M.teardown()
	for key, places in pairs(data.places) do
		for place, _ in pairs(places) do
			history.handles.drop_place(place)
		end
		data.places[key] = nil
	end
	data.scopes = { window = {}, tab = {}, session = {} }
	data.flashes = {}
	data.pending = {} -- what was queued to be held over goes with the rest
	data.tab_shows = {}
end

---Get the aliases' order: each alias's index in the config's table.
---
---@return table<string, any> index Alias → its index
local function alias_index()
	return require('frogman.configs').marks.aliases or {}
end

---Check if an alias has a key: the config's table names it.
---
---A saved mark whose alias the config no longer has is kept, holding its file, until it's given one.
---
---@param alias string
---@return boolean assigned
local function assigned(alias)
	return alias_index()[alias] ~= nil
end

---Check if one alias comes before another, by their indices: numbers by value, anything else by text.
---
---@param index table<string, any> Alias → index
---@param a string
---@param b string
---@return boolean before
local function before(index, a, b)
	local x, y = index[a] or a, index[b] or b
	if type(x) == "number" and type(y) == "number" then
		return x < y
	end
	return tostring(x) < tostring(y)
end

---Say something in a window's winbar for a moment.
---
---@param winid WinId
---@param text string
---@return nil
local function flash(winid, text)
	data.flashes[winid] = { text = text, till = vim.uv.now() + FLASH_MS }
end

---Get what a window's winbar says for a moment, while it does.
---
---@param winid WinId
---@return string|nil text
function M.flash_of(winid)
	local f = data.flashes[winid]
	if f and vim.uv.now() < f.till then
		return f.text
	end
	data.flashes[winid] = nil
	return nil
end

---Redraw the UI once marks changed.
---@return nil
local function repaint()
	require('frogman.domains.ui.sm').loop:to(require('frogman.domains.ui.states').LOOP.SELF)
end

---Switch the editor's mode.
---
---From inside the marks pop-up it shows the new mode's scope there, writing its edits first; outside
---it, while the pop-up has edits not written yet, it refuses and says why.
---
---@param mode "window"|"tab"|"session"
---@return nil
function M.set_mode(mode)
	local popup = require('frogman.domains.marks.popup')
	local winid = vim.api.nvim_get_current_win()
	if popup.is_current() then
		-- inside the pop-up: its edits written first, then the new mode's scope shown
		if not popup.switch_mode(mode) then
			return
		end
		winid = popup.origin() or winid
	elseif popup.refuse_if_dirty() then
		return
	else
		data.mode = mode
	end
	local kind = M.scope_key(mode, winid)
	flash(winid, "marks · " .. kind)
	repaint()
end

---Mark the current buffer under an alias, in the first group of the current mode's scope.
---
---Something frogman doesn't track can't be marked, and onto an alias another file holds it opens the
---marks pop-up on the conflict. The winbar says what the add did. While the pop-up has edits not
---written yet, it refuses and says why.
---
---@param alias string
---@return nil
function M.add(alias)
	if require('frogman.domains.marks.popup').refuse_if_dirty() then
		return
	end
	local winid = vim.api.nvim_get_current_win()
	local filehash = history.get_hash_from_buffer(vim.api.nvim_win_get_buf(winid))
	local handle = filehash and history.handles.of_hash(filehash)
	if handle == nil then
		vim.notify("frogman: only files can be marked.", vim.log.levels.WARN)
		return
	end
	local kind, id = M.scope_key(data.mode, winid)
	local group = M.first_group(M.scope(kind, id, true), true)
	local held = M.handle_of(group, alias)
	if held and held ~= handle then
		-- the conflict is settled in the marks pop-up: the incoming file, and the one already set
		require('frogman.domains.marks.popup').open({ conflict = { alias = alias, hash = filehash } })
		return
	end
	group.marks[alias] = handle.id
	M.hold_scope(kind, id)
	flash(winid, "⟨" .. alias .. "⟩ marked")
	repaint()
end

---Jump to the file an alias marks, in the first group of the current mode's scope.
---
---It goes there as a primary jump goes to the primary. An alias that marks nothing does nothing,
---and so does every jump while a cycle runs, which says so, and while the marks pop-up has edits not
---written yet. From the pop-up, it leaves it and jumps in the window it was opened from.
---
---@param alias string
---@return nil
function M.jump(alias)
	if require('frogman.domains.navigation').is_cycling() then
		vim.notify("frogman: pick or cancel the cycle first.", vim.log.levels.WARN)
		return
	end
	local popup = require('frogman.domains.marks.popup')
	if popup.refuse_if_dirty() then
		return
	end
	if popup.is_current() then
		-- from the pop-up, the jump goes in the window it was opened from
		local origin = popup.origin()
		popup.leave()
		if origin then
			vim.api.nvim_set_current_win(origin)
		end
	end
	local winid = vim.api.nvim_get_current_win()
	local group = M.first_group(M.scope(M.scope_key(data.mode, winid)))
	local handle = group and M.handle_of(group, alias)
	if handle == nil then
		return
	end
	require('frogman.domains.window').routines.jump_to_mark(winid, handle.hash, "⟨" .. alias .. "⟩")
end

---Get the aliases a file has in the first group of the current mode's scope, in their order.
---
---@param filehash Filehash|nil
---@param winid WinId|nil The window whose scope it reads (nil = the current one)
---@return string|nil aliases Like "a,s", or nil when the file isn't marked there
function M.label_of(filehash, winid)
	if filehash == nil then
		return nil
	end
	local group = M.first_group(M.scope(M.scope_key(data.mode, winid)))
	if group == nil then
		return nil
	end
	local index, found = alias_index(), {}
	for alias, _ in pairs(group.marks) do
		local handle = assigned(alias) and M.handle_of(group, alias)
		if handle and handle.hash == filehash then
			table.insert(found, alias)
		end
	end
	if #found == 0 then
		return nil
	end
	table.sort(found, function(a, b) return before(index, a, b) end)
	return table.concat(found, ",")
end

---Get the paths of the files the first group of the current mode's scope marks, in their aliases' order.
---
---@param winid WinId|nil The window whose scope it reads (nil = the current one)
---@return Filepath[] paths
function M.marked_paths(winid)
	local group = M.first_group(M.scope(M.scope_key(data.mode, winid)))
	if group == nil then
		return {}
	end
	local index, aliases = alias_index(), {}
	for alias, _ in pairs(group.marks) do
		if assigned(alias) then
			table.insert(aliases, alias)
		end
	end
	table.sort(aliases, function(a, b) return before(index, a, b) end)
	local paths = {}
	for _, alias in ipairs(aliases) do
		local handle = M.handle_of(group, alias)
		local filepath = handle and history.get_filepath_from_hash(handle.hash)
		if filepath and not filepath:match("^NONAME_") then
			table.insert(paths, filepath)
		end
	end
	return paths
end

---Check that the alias table maps one alias to one index, and back.
---
---@param aliases table<string, any> Alias → index
---@return nil
---@error "frogman: marks.aliases maps ... to one index" if two aliases share an index
function M.check_aliases(aliases)
	local seen = {}
	for alias, index in pairs(aliases or {}) do
		local key = tostring(index)
		if seen[key] then
			local pair = { seen[key], alias }
			table.sort(pair)
			error("frogman: marks.aliases maps " .. pair[1] .. " and " .. pair[2] .. " to one index, " .. key .. ".", 0)
		end
		seen[key] = alias
	end
end

---Get a scope's groups as a session file holds them.
---
---Each group keeps its name and its marks, each by its alias and its file's hash. A group with no
---marks isn't kept, and a scope with none gives nil.
---
---@param kind "window"|"tab"|"session"
---@param id any
---@return {name: string, marks: table<string, Filehash>}[]|nil groups
function M.serialise(kind, id)
	local scope = data.scopes[kind][id]
	local groups = {}
	for _, group in ipairs(scope and scope.groups or {}) do
		local marks = {}
		for alias, _ in pairs(group.marks) do
			local handle = M.handle_of(group, alias)
			if handle then
				marks[alias] = handle.hash
			end
		end
		if next(marks) then
			table.insert(groups, { name = group.name, marks = marks, held = group.held or nil })
		end
	end
	return #groups > 0 and groups or nil
end

---Give a scope the groups a session file holds.
---
---Each mark takes its file's handle. A file the registry doesn't know is left out, and a scope
---left with no group goes.
---
---@param kind "window"|"tab"|"session"
---@param id any
---@param groups {name: string, marks: table<string, Filehash>}[]|nil The file's groups
---@return nil
function M.restore(kind, id, groups)
	local scope = { groups = {} }
	for _, saved in ipairs(type(groups) == "table" and groups or {}) do
		local group = { name = saved.name, marks = {}, held = saved.held == true or nil }
		for alias, filehash in pairs(type(saved.marks) == "table" and saved.marks or {}) do
			local handle = history.handles.of_hash(filehash)
			if handle then
				group.marks[alias] = handle.id
			end
		end
		if next(group.marks) then
			table.insert(scope.groups, group)
		end
	end
	data.scopes[kind][id] = #scope.groups > 0 and scope or nil
	M.hold_scope(kind, id)
end

---Copy one scope's marks into another, the two going their own ways after.
---
---@param kind "window"|"tab"|"session"
---@param id any The scope copied
---@param to_id any The scope it's copied into
---@return nil
function M.copy_scope(kind, id, to_id)
	local scope = data.scopes[kind][id]
	data.scopes[kind][to_id] = scope and vim.deepcopy(scope) or nil
	M.hold_scope(kind, to_id)
end

---Get what a window shows, as a held-over group names it: its file's name, or its buffer's.
---
---@param winid WinId
---@return string what
function M.shows(winid)
	if not vim.api.nvim_win_is_valid(winid) then
		return "[No Name]"
	end
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local filehash = history.get_hash_from_buffer(bufnr)
	if filehash then
		return require('frogman.domains.ui').routines.get_smart_basename(filehash)
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	return name ~= "" and vim.fs.basename(name) or "[No Name]"
end

---Get a held-over group's name: what it was and when, numbered on when the scope has that name.
---
---@param scope MarksScope|nil The scope it goes to
---@param what string What it was, like "window on api.lua" or "proj, loaded into tab 2"
---@return string name Like "held over · window on api.lua · 10-31 13:05"
local function held_name(scope, what)
	local base = "held over · " .. what .. " · " .. os.date("%m-%d %H:%M")
	local taken = {}
	for _, group in ipairs(scope and scope.groups or {}) do
		taken[group.name] = true
	end
	local name, n = base, 1
	while taken[name] do
		n = n + 1
		name = base .. " #" .. n
	end
	return name
end

---Hold groups over in a session's scope, below its groups.
---
---Each group with marks becomes one of its own, held over, named after what it was and when. A
---held-over group drives the keys only once you move it first yourself.
---
---@param session_id string The session's pool id ("" for the whole editor's)
---@param groups MarksGroup[]|{name: string, marks: table<string, Filehash>}[] The groups, live (handle ids) or saved (hashes)
---@param what string What they were, like "window on api.lua"
---@param saved boolean|nil Whether the groups are saved ones, their marks by hash
---@return nil
function M.hold_over(session_id, groups, what, saved)
	local scope = M.scope("session", session_id, true)
	local several = #groups > 1
	for _, group in ipairs(groups) do
		local marks = {}
		for alias, value in pairs(group.marks or {}) do
			local handle
			if saved then
				handle = history.handles.of_hash(value)
			else
				handle = M.handle_of(group, alias)
			end
			if handle then
				marks[alias] = handle.id
			end
		end
		if next(marks) then
			if not M.first_group(scope) then
				M.first_group(scope, true) -- the keys keep a group of their own, ahead of what's held over
			end
			table.insert(scope.groups, { name = held_name(scope, several and (what .. ", " .. group.name) or what), marks = marks, held = true })
		end
	end
	M.hold_scope("session", session_id)
	if scope.groups[1] == nil then
		data.scopes.session[session_id] = nil
	end
end

---Queue a closed window's or tab's groups to be held over once the editor settles.
---
---A session manager's switch closes windows and tabs inside its teardown, and the load it ends with
---drops what's queued, so a switch holds nothing over. A tab session's load drops what came from the
---tab it loads into.
---
---@param tabpage integer The tab the window or tab was in
---@param session_id string The session's pool id ("" for the whole editor's)
---@param groups MarksGroup[] The groups, live
---@param what string What they were
---@return nil
function M.queue_hold_over(tabpage, session_id, groups, what)
	local copy = {}
	for _, group in ipairs(groups) do
		local marks = {}
		for alias, _ in pairs(group.marks) do
			local handle = M.handle_of(group, alias)
			if handle then
				marks[alias] = handle.hash
			end
		end
		if next(marks) then
			table.insert(copy, { name = group.name, marks = marks })
		end
	end
	if #copy == 0 then
		return
	end
	-- its files stay held while it waits, by a place of its own, so none is let go in between
	data.waited = data.waited + 1
	local place = "mark:waiting:" .. data.waited
	local hashes = {}
	for _, group in ipairs(copy) do
		for _, filehash in pairs(group.marks) do
			table.insert(hashes, filehash)
		end
	end
	history.handles.hold(place, hashes)
	data.places["waiting:" .. data.waited] = { [place] = true }
	local entry = { tab = tabpage, session = session_id, groups = copy, what = what, place = place, key = "waiting:" .. data.waited }
	table.insert(data.pending, entry)
	vim.schedule(function()
		-- one a teardown or a load dropped meanwhile isn't there any more
		for i, waiting in ipairs(data.pending) do
			if waiting == entry then
				table.remove(data.pending, i)
				M.hold_over(entry.session, entry.groups, entry.what, true)
				repaint()
				history.handles.drop_place(entry.place)
				data.places[entry.key] = nil
				return
			end
		end
	end)
end

---Drop the held-over groups still queued from a tab, as a tab session's load into it starts.
---
---@param tabpage integer
---@return nil
function M.drop_pending(tabpage)
	for i = #data.pending, 1, -1 do
		local entry = data.pending[i]
		if entry.tab == tabpage then
			table.remove(data.pending, i)
			history.handles.drop_place(entry.place)
			data.places[entry.key] = nil
		end
	end
end

---Get the hashes of the files a session's marks hold.
---
---With no pool, every mark's. With a pool, its own marks, and those of the windows and tabs in its
---tabs; the editor's pool takes the detached lists' too.
---
---@param owner Pool|nil
---@return table<Filehash, boolean> held
function M.held_by(owner)
	local held = {}
	local function take(kind, id)
		local scope = data.scopes[kind][id]
		for _, group in ipairs(scope and scope.groups or {}) do
			for alias, _ in pairs(group.marks) do
				local handle = M.handle_of(group, alias)
				if handle then
					held[handle.hash] = true
				end
			end
		end
	end
	local function its_tab(tabpage)
		return owner == nil or (vim.api.nvim_tabpage_is_valid(tabpage) and history.routines.pool_of_tab(tabpage) == owner)
	end
	for kind, scopes in pairs(data.scopes) do
		for id, _ in pairs(scopes) do
			if owner == nil then
				take(kind, id)
			elseif kind == "window" then
				if vim.api.nvim_win_is_valid(id) and its_tab(vim.api.nvim_win_get_tabpage(id)) then
					take(kind, id)
				end
			elseif kind == "tab" then
				if its_tab(id) then
					take(kind, id)
				end
			elseif id == owner.id or (owner.id == "" and history.data.pools[id] and history.data.pools[id].detached) then
				take(kind, id)
			end
		end
	end
	return held
end

---Check if a mark holds a file.
---
---@param filehash Filehash|nil
---@return boolean held
function M.holds(filehash)
	local handle = filehash and history.handles.of_hash(filehash)
	for place, _ in pairs(handle and handle.holders or {}) do
		if place:match("^mark:") then
			return true
		end
	end
	return false
end

---Get the hashes a file's saved groups name.
---
---@param groups {name: string, marks: table<string, Filehash>}[]|nil
---@param into table<Filehash, boolean>|nil Added to in place, when given
---@return table<Filehash, boolean> named
function M.named_by(groups, into)
	into = into or {}
	for _, group in ipairs(type(groups) == "table" and groups or {}) do
		for _, filehash in pairs(type(group.marks) == "table" and group.marks or {}) do
			into[filehash] = true
		end
	end
	return into
end

return M
