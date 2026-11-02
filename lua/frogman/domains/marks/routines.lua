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

---Get a scope's first group, the one the keys use.
---
---A scope where no group has been typed gets its default group, named by the config.
---
---@param scope MarksScope|nil
---@param create boolean|nil Whether to make the default group when there's none
---@return MarksGroup|nil group
function M.first_group(scope, create)
	if scope == nil then
		return nil
	end
	if scope.groups[1] == nil and create then
		table.insert(scope.groups, { name = require('frogman.configs').marks.default_group, marks = {} })
	end
	return scope.groups[1]
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
end

---Get the aliases' order: each alias's index in the config's table.
---
---@return table<string, any> index Alias → its index
local function alias_index()
	return require('frogman.configs').marks.aliases or {}
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
---@param mode "window"|"tab"|"session"
---@return nil
function M.set_mode(mode)
	data.mode = mode
	local kind = M.scope_key(mode)
	flash(vim.api.nvim_get_current_win(), "marks · " .. kind)
	repaint()
end

---Mark the current buffer under an alias, in the first group of the current mode's scope.
---
---Something frogman doesn't track can't be marked, and an alias another file holds is left as it is.
---The winbar says what the add did.
---
---@param alias string
---@return nil
function M.add(alias)
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
		local name = require('frogman.domains.ui').routines.get_smart_basename
		vim.notify("frogman: ⟨" .. alias .. "⟩ holds " .. name(held.hash) .. ", so " .. name(filehash) ..
			" isn't marked there.", vim.log.levels.WARN)
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
---and so does every jump while a cycle runs, which says so.
---
---@param alias string
---@return nil
function M.jump(alias)
	if require('frogman.domains.navigation').is_cycling() then
		vim.notify("frogman: pick or cancel the cycle first.", vim.log.levels.WARN)
		return
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
		local handle = M.handle_of(group, alias)
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
		table.insert(aliases, alias)
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
			table.insert(groups, { name = group.name, marks = marks })
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
		local group = { name = saved.name, marks = {} }
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
