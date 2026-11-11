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
---@param mode "window"|"tab"|"session" The mode whose scope is wanted
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
---@param kind "window"|"tab"|"session" The scope's kind
---@param id any Its window, tab or session's pool id
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
---@param scope MarksScope|nil The scope
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
		table.insert(scope.groups, 1, { name = require('frogman.configs').marks.default_group, marks = {}, default = true })
		return scope.groups[1]
	end
	return nil
end

---Get a group's key in its scope: its name and its place among the scope's groups of that name.
---
---The place counts from the top, so two groups named `feature-x` are `feature-x/1` and `feature-x/2`.
---Nothing is stored for it: two of one name that swap places swap keys too. The place is the last
---`/<digits>`, so a group named `v/2` is `v/2/1`.
---
---@param groups {name: string}[] The scope's groups, in order
---@param index integer The group's place among them
---@return string key Like "feature-x/2"
function M.group_key(groups, index)
	local name, place = groups[index].name, 0
	for i = 1, index do
		if groups[i].name == name then
			place = place + 1
		end
	end
	return name .. "/" .. place
end

---Get the handle a mark holds now.
---
---A handle let go for a moved file that took its name is followed to the moved file's, and the mark
---keeps that one from then on.
---
---@param group MarksGroup The group the mark is in
---@param alias string The mark's alias
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
---@param kind string The scope's kind
---@param id any Its window, tab or session's pool id
---@param position integer The group's position in the scope
---@param alias string The mark's alias
---@return string place Like "mark:session::1:a"
local function place_of(kind, id, position, alias)
	return "mark:" .. kind .. ":" .. tostring(id) .. ":" .. position .. ":" .. alias
end

---Hold the files a scope's marks hold, each by its place.
---
---The new places hold first and the ones it no longer has let go after, so a mark that stays is
---never left with nothing holding its file in between.
---
---@param kind "window"|"tab"|"session" The scope's kind
---@param id any Its window, tab or session's pool id
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
				history.handles.hold(place, { handle.id })
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
	if kind == "session" then
		require('frogman.held').records_changed(id) -- a session's own marks are records
	elseif kind == "window" then
		require('frogman.held').note_session(id)
	elseif vim.api.nvim_tabpage_is_valid(id) then
		require('frogman.held').note_session(vim.api.nvim_tabpage_get_win(id)) -- what the tab shows
	end
	local popup = package.loaded['frogman.domains.marks.popup']
	if popup then
		popup.scope_changed(kind, id) -- an open pop-up with nothing unwritten shows the change
	end
end

---Let a scope go, and everything its marks held.
---
---@param kind "window"|"tab"|"session" The scope's kind
---@param id any Its window, tab or session's pool id
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
	data.copies = {}
	local popup = package.loaded['frogman.domains.marks.popup']
	if popup then
		popup.every_scope_changed() -- an open pop-up with nothing unwritten shows the scopes as the load leaves them
	end
end

---Check if a window's marks are a copy another window still holds alike: the copy it was given, the
---window it came from alive holding the same, or the copy it gave, alive and unchanged. Its close, or
---a load into it, would lose nothing.
---
---@param winid WinId The window to check
---@return boolean unchanged
function M.unchanged_copy(winid)
	local function alike(other, given)
		return other ~= winid and vim.api.nvim_win_is_valid(other) and vim.deep_equal(M.serialise("window", other), given)
			and vim.deep_equal(M.serialise("window", winid), given)
	end
	local copy = data.copies[winid]
	if copy and alike(copy.from, copy.given) then
		return true
	end
	for other, given in pairs(data.copies) do
		if given.from == winid and alike(other, given.given) then
			return true
		end
	end
	return false
end

---Move a session scope's held-over groups into another's, as a detached list that goes leaves them to
---the whole editor's, each keeping its name, numbered on when the scope it goes to has it.
---
---@param from_id string The pool id of the session they leave
---@param to_id string The pool id of the session they go to ("" for the whole editor's)
---@return nil
function M.move_held(from_id, to_id)
	local from = data.scopes.session[from_id]
	if from == nil then
		return
	end
	local to = M.scope("session", to_id, true)
	local taken, kept = {}, {}
	for _, group in ipairs(to.groups) do
		taken[group.name] = true
	end
	for _, group in ipairs(from.groups) do
		if group.held then
			local name, n = group.name, 1
			while taken[name] do
				n = n + 1
				name = group.name .. " #" .. n
			end
			taken[name] = true
			table.insert(to.groups, { name = name, marks = vim.deepcopy(group.marks), held = true, from = group.from })
		else
			table.insert(kept, group)
		end
	end
	from.groups = kept
	M.hold_scope("session", to_id) -- the new places hold first, then the old ones let go
	M.hold_scope("session", from_id)
end

---Give a session's scope the held-over groups a session file holds, each kept as it is, after its own,
---with marks or none, but for one a held-over group there has already, which it would only repeat: one
---with its marks, or, for one with none, held over before from a group of the same name.
---
---@param session_id string The session's pool id ("" for the whole editor's)
---@param groups table[]|nil Saved groups, their marks by hash; only the held-over ones come in
---@param paths table<Filehash, string>|nil The file's paths, for a file the registry doesn't know yet
---@return nil
function M.adopt_held(session_id, groups, paths)
	local held = vim.tbl_filter(function(g) return type(g) == "table" and g.held end, type(groups) == "table" and groups or {})
	if #held == 0 then
		return
	end
	local scope = M.scope("session", session_id, true)
	local before = vim.tbl_filter(function(g) return g.held end, scope.groups) -- what's there before these come in
	for _, saved in ipairs(held) do
		local group = { name = saved.name, marks = {}, held = true, from = type(saved.from) == "string" and saved.from or nil }
		for alias, filehash in pairs(type(saved.marks) == "table" and saved.marks or {}) do
			if not history.handles.of_hash(filehash) and paths and paths[filehash] then
				history.register_filepath(paths[filehash])
			end
			local handle = history.handles.of_hash(filehash)
			if handle then
				group.marks[alias] = handle.id
			end
		end
		local there = false
		if next(group.marks) then
			for _, other in ipairs(scope.groups) do
				there = there or (other.held and vim.deep_equal(other.marks, group.marks))
			end
		else
			for _, other in ipairs(before) do
				there = there or (group.from ~= nil and other.from == group.from and next(other.marks) == nil)
			end
		end
		if not there then
			table.insert(scope.groups, group)
		end
	end
	M.hold_scope("session", session_id)
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
---@param alias string The alias to check
---@return boolean assigned
local function assigned(alias)
	return alias_index()[alias] ~= nil
end

---Check if one alias comes before another, by their indices: numbers first, by value, then anything
---else by its text, so any mix of indices sorts one way.
---
---@param index table<string, any> Alias → index
---@param a string The first alias
---@param b string The alias it's compared with
---@return boolean before
local function before(index, a, b)
	local x, y = index[a] or a, index[b] or b
	local x_number, y_number = type(x) == "number", type(y) == "number"
	if x_number and y_number then
		return x < y
	end
	if x_number ~= y_number then
		return x_number
	end
	return tostring(x) < tostring(y)
end
M.alias_before = before

---Say something in a window's winbar for a moment.
---
---@param winid WinId The window whose winbar says it
---@param text string What the winbar says
---@return nil
local function flash(winid, text)
	data.flashes[winid] = { text = text, till = vim.uv.now() + FLASH_MS }
end

---Get what a window's winbar says for a moment, while it does.
---
---@param winid WinId The window whose winbar is read
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
---From inside the marks pop-up it shows the new mode's scope there, the scope it leaves kept as a
---draft when the pop-up's screen holds edits; outside it, while the pop-up has edits not written yet,
---it refuses and says why.
---
---@param mode "window"|"tab"|"session" The mode to switch to
---@return nil
function M.set_mode(mode)
	local popup = require('frogman.domains.marks.popup')
	local winid = vim.api.nvim_get_current_win()
	if popup.is_current() then
		-- inside the pop-up: its edits kept as a draft, then the new mode's scope shown
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
---@param alias string The alias to mark the current buffer's file under
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
		require('frogman.domains.marks.popup').open({ conflict = { alias = alias, id = handle.id } })
		return
	end
	group.marks[alias] = handle.id
	M.hold_scope(kind, id)
	flash(winid, "⟨" .. alias .. "⟩ marked")
	repaint()
end

---Jump to the file an alias marks, in the first group of the current mode's scope.
---
---It goes there as a primary jump goes to the primary. An alias that marks nothing does nothing, and
---so does every jump while the marks pop-up has edits not written yet. While a cycle runs, the jump
---cancels it as a cancel ends it, its window back on its start, and jumps from there. From the pop-up,
---it leaves it and jumps in the window it was opened from.
---
---@param alias string The alias whose file to jump to
---@return nil
function M.jump(alias)
	local popup = require('frogman.domains.marks.popup')
	if popup.refuse_if_dirty() then
		return -- refused, it changes nothing, a cycle running included
	end
	local navigation = require('frogman.domains.navigation')
	if navigation.is_cycling() then
		-- a cycle in another window was cancelled before this ran; this is the window it runs in
		navigation.routines.cancel_cycle(navigation.data.cycling_window)
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
	require('frogman.domains.window').routines.jump_to_mark(winid, handle.id, "⟨" .. alias .. "⟩")
end

---Get the aliases a file has in the first group of the current mode's scope, in their order.
---
---@param id HandleId|nil The file's handle
---@param winid WinId|nil The window whose scope it reads (nil = the current one)
---@return string|nil aliases Like "a,s", or nil when the file isn't marked there
function M.label_of(id, winid)
	if id == nil then
		return nil
	end
	return M.labels(winid)[id]
end

---Get every marked file's aliases in the first group of the current mode's scope, at once: what a
---refresh draws, read from one walk of the group rather than one for each buffer.
---
---@param winid WinId|nil The window whose scope it reads (nil = the current one)
---@return table<HandleId, string> labels File's handle → its aliases, like "a,s"
function M.labels(winid)
	local group = M.first_group(M.scope(M.scope_key(data.mode, winid)))
	if group == nil then
		return {}
	end
	local index, found = alias_index(), {}
	for alias, _ in pairs(group.marks) do
		local handle = assigned(alias) and M.handle_of(group, alias)
		if handle then
			found[handle.id] = found[handle.id] or {}
			table.insert(found[handle.id], alias)
		end
	end
	local labels = {}
	for id, aliases in pairs(found) do
		table.sort(aliases, function(a, b) return before(index, a, b) end)
		labels[id] = table.concat(aliases, ",")
	end
	return labels
end

---Check that the alias table maps one alias to one index, and back.
---
---An index is a number or a string, so 1 and "1" are two. An alias can't be a glyph a group's header
---opens with in the marks pop-up, the set in use's or one of one's own, nor either set's: a row under
---it would read as a header.
---
---@param aliases table<string, any> Alias → index
---@return nil
---@error "frogman: marks.aliases maps ... to one index" if two aliases share an index
---@error "frogman: ... opens a group's header" if an alias is a header's glyph
function M.check_aliases(aliases)
	local glyph = require('frogman.domains.ui').routines.glyphs().group
	local seen = {}
	for alias, index in pairs(aliases or {}) do
		if alias == glyph or alias == "❖" or alias == "*" then
			error("frogman: marks.aliases can't have " .. alias .. ": it opens a group's header in the marks pop-up.", 0)
		end
		local key = type(index) .. ":" .. tostring(index)
		if seen[key] then
			local pair = { seen[key], alias }
			table.sort(pair)
			error("frogman: marks.aliases maps " .. pair[1] .. " and " .. pair[2] .. " to one index, " .. vim.inspect(index) .. ".", 0)
		end
		seen[key] = alias
	end
end

---Get the files a group's marks hold now, as its session file writes them.
---
---@param group MarksGroup The group
---@return table<string, Filehash> marks Alias → its file's hash, for the marks whose handle lives
function M.hashes_of(group)
	local marks = {}
	for alias, _ in pairs(group.marks) do
		local handle = M.handle_of(group, alias)
		if handle then
			marks[alias] = handle.hash
		end
	end
	return marks
end

---Check if any of the groups holds a mark.
---
---Takes live groups and saved ones alike: only whether a group's marks are empty is read.
---
---@param groups {marks: table}[]|nil The groups
---@return boolean marked
function M.any_mark(groups)
	for _, group in ipairs(type(groups) == "table" and groups or {}) do
		if type(group) == "table" and type(group.marks) == "table" and next(group.marks) ~= nil then
			return true
		end
	end
	return false
end

---Get a scope's groups as a session file holds them.
---
---Each group keeps its name, its marks, each by its alias and its file's hash, whether it's held over or
---the default group, and the name a held-over group with no marks came from. Every group is kept, with
---marks or none, so it stays where it is across a restart: a group goes only when its header is deleted
---in the marks pop-up. A scope with none gives nil.
---
---@param kind "window"|"tab"|"session" The scope's kind
---@param id any Its window, tab or session's pool id
---@return {name: string, marks: table<string, Filehash>, held: true|nil, default: true|nil, from: string|nil}[]|nil groups
function M.serialise(kind, id)
	local scope = data.scopes[kind][id]
	local groups = {}
	for _, group in ipairs(scope and scope.groups or {}) do
		table.insert(groups, {
			name = group.name, marks = M.hashes_of(group), held = group.held or nil, default = group.default or nil, from = group.from,
		})
	end
	return #groups > 0 and groups or nil
end

---Make a live group from one a session file holds: each mark by its file's handle, a file the registry
---doesn't know left out.
---
---@param saved {name: string, marks: table<string, Filehash>, held: true|nil, default: true|nil, from: string|nil} The file's group
---@param what string|nil The load, as a held-over group names it, kept on the group
---@return MarksGroup group
local function from_saved(saved, what)
	local group = {
		name = saved.name, marks = {}, held = saved.held == true or nil, default = saved.default == true or nil, loaded = what,
		from = type(saved.from) == "string" and saved.from or nil,
	}
	for alias, filehash in pairs(type(saved.marks) == "table" and saved.marks or {}) do
		local handle = history.handles.of_hash(filehash)
		if handle then
			group.marks[alias] = handle.id
		end
	end
	return group
end

---Give a scope the groups a session file holds.
---
---Each mark takes its file's handle. A file the registry doesn't know is left out. Every group comes
---back, with marks or none. A scope left with no group goes.
---
---@param kind "window"|"tab"|"session" The scope's kind
---@param id any Its window, tab or session's pool id
---@param groups {name: string, marks: table<string, Filehash>, held: true|nil, default: true|nil}[]|nil The file's groups
---@param what string|nil The load, as a held-over group names it: kept on each group, for a marks pop-up
---with edits not written, whose write holds them over under it
---@return nil
function M.restore(kind, id, groups, what)
	local scope = { groups = {} }
	for _, saved in ipairs(type(groups) == "table" and groups or {}) do
		if type(saved) == "table" then
			table.insert(scope.groups, from_saved(saved, what))
		end
	end
	data.scopes[kind][id] = #scope.groups > 0 and scope or nil
	M.hold_scope(kind, id)
end

---Add the groups a session file holds below a scope's own, but for one whose name the scope has and the
---default group with no marks: a window that keeps its own marks at a load takes its entry's groups typed
---in with none so.
---
---@param kind "window"|"tab"|"session" The scope's kind
---@param id any Its window, tab or session's pool id
---@param groups table[]|nil The file's groups
---@param what string|nil The load, as a held-over group names it: kept on each group, for a marks pop-up
---with edits not written, whose write holds them over under it
---@return nil
function M.add_below(kind, id, groups, what)
	local scope = M.scope(kind, id, true)
	local named = {}
	for _, group in ipairs(scope.groups) do
		named[group.name] = true
	end
	for _, saved in ipairs(type(groups) == "table" and groups or {}) do
		local empty_default = type(saved) == "table" and saved.default and not next(type(saved.marks) == "table" and saved.marks or {})
		if type(saved) == "table" and not named[saved.name] and not empty_default then
			named[saved.name] = true
			table.insert(scope.groups, from_saved(saved, what))
		end
	end
	M.hold_scope(kind, id)
end

---Copy one scope's marks into another, the two going their own ways after.
---
---@param kind "window"|"tab"|"session" The scope's kind
---@param id any The scope copied
---@param to_id any The scope it's copied into
---@return nil
function M.copy_scope(kind, id, to_id)
	local scope = data.scopes[kind][id]
	data.scopes[kind][to_id] = scope and vim.deepcopy(scope) or nil
	M.hold_scope(kind, to_id)
end

---Carry a copy of one session's marks into another's, below the groups it has, its held-over groups
---among them, the two going their own ways after: a tab session's, as its tab is saved as another.
---
---@param id string The session's pool id carried from
---@param to_id string The session's pool id carried into
---@return nil
function M.carry_scope(id, to_id)
	local scope = data.scopes.session[id]
	if scope == nil then
		return
	end
	local into = data.scopes.session[to_id] or { groups = {} }
	vim.list_extend(into.groups, vim.deepcopy(scope.groups))
	data.scopes.session[to_id] = into
	M.hold_scope("session", to_id)
end

---Get what a window shows, as a held-over group names it: its file's name, or its buffer's.
---
---@param winid WinId The window
---@return string what
function M.shows(winid)
	if not vim.api.nvim_win_is_valid(winid) then
		return "[No Name]"
	end
	return M.name_of(vim.api.nvim_win_get_buf(winid))
end

---Get what a buffer is called in a held-over header: its file's unique name while frogman has taken it
---in, or else its buffer's name.
---
---@param bufnr Bufnr The buffer
---@return string name
function M.name_of(bufnr)
	local id = history.get_handle_from_buffer(bufnr)
	if id then
		return require('frogman.domains.ui').routines.get_smart_basename(id)
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
	local taken = {}
	for _, group in ipairs(scope and scope.groups or {}) do
		taken[group.name] = true
	end
	return require('frogman.held').held_header(what, taken)
end

---Get the groups held over in a session's scope now, or in every session's, for a load to tell them from
---those it holds over.
---
---@param session_id string|nil The session's pool id ("" for the whole editor's), or nil for every session's
---@return table<MarksGroup, true> held
function M.held_now(session_id)
	local held = {}
	for id, scope in pairs(data.scopes.session) do
		if session_id == nil or id == session_id then
			for _, group in ipairs(scope.groups) do
				if group.held then
					held[group] = true
				end
			end
		end
	end
	return held
end

---Let go of the copies held over of these groups, as the window they came from takes them back from its
---entry: for each group, one held over before the load, a close's or a load's, holding it alias for alias.
---
---Both are read by the files their marks name now: a No Name text the file names under its old hash and
---memory holds back under a new one is the same text. A copy you edited no longer holds one of them, and
---one you moved up first is a group of your own, not held over, so both stay; what the load itself holds
---over, another entry's, stays too. A copy with no marks is known by the name of the group it was held
---over from, and goes when the window takes back an empty group of that name. A group takes one copy
---back, so another window's copy of the same stays.
---
---@param session_id string The session's pool id ("" for the whole editor's)
---@param groups {name: string, marks: table<string, Filehash>}[] The groups the window took back, saved
---@param earlier table<MarksGroup, true> The groups held over before the load
---@param now fun(filehash: Filehash): Filehash The hash a file's hash names now
---@return nil
function M.drop_copies(session_id, groups, earlier, now)
	local scope = data.scopes.session[session_id]
	if scope == nil then
		return
	end
	for _, saved in ipairs(groups) do
		local brings = {}
		for alias, filehash in pairs(type(saved) == "table" and type(saved.marks) == "table" and saved.marks or {}) do
			brings[alias] = now(filehash)
		end
		for i, group in ipairs(scope.groups) do
			local marks = earlier[group] and M.hashes_of(group)
			if type(saved) == "table" and marks and vim.deep_equal(brings, marks)
				and (next(marks) ~= nil or (group.from ~= nil and group.from == saved.name)) then
				table.remove(scope.groups, i)
				break
			end
		end
	end
	M.hold_scope("session", session_id)
end

---Hold groups over in a session's scope, below its groups.
---
---Each group becomes one of its own, held over, with marks or none, named after what it was and when,
---and after its own name when it's one of several; the default group goes instead while it has no marks,
---frogman having made it. A held-over group drives the keys only once you move it first yourself.
---
---@param session_id string The session's pool id ("" for the whole editor's)
---@param groups MarksGroup[]|{name: string, marks: table<string, Filehash>, default: true|nil}[] The groups, live (handle ids) or saved (hashes)
---@param what string What they were, like "window on api.lua"
---@param saved boolean|nil Whether the groups are saved ones, their marks by hash
---@param once boolean|nil Whether to skip a group a held-over group of the scope has already, alias for alias, as a load's are: a records write keeps the windows as the last save wrote them, so the same entry comes back at every load
---@param earlier table<MarksGroup, true>|nil With `once`, the groups held over before the load: a group with no marks is one of them already when one of them was held over from a group of its name and has none
---@return nil
function M.hold_over(session_id, groups, what, saved, once, earlier)
	local scope = M.scope("session", session_id, true)
	-- each group's marks by the handles they still have: a mark whose file nothing knows goes
	local kept = {}
	for i, group in ipairs(groups) do
		kept[i] = {}
		for alias, value in pairs(group.marks or {}) do
			local handle
			if saved then
				handle = history.handles.of_hash(value)
			else
				handle = M.handle_of(group, alias)
			end
			if handle then
				kept[i][alias] = handle.id
			end
		end
	end
	-- the default group with no marks goes; a group's name goes in its header when it's one of several held
	-- over, with marks or none
	local going = {}
	for i, group in ipairs(groups) do
		going[i] = group.default and next(kept[i]) == nil or nil
	end
	local several = #groups - vim.tbl_count(going) > 1
	-- the groups held over before this call: two groups of one entry with the same marks are both kept
	local before = vim.tbl_filter(function(g) return g.held end, scope.groups)
	local function held_already(marks, name)
		if next(marks) == nil then
			-- one with no marks is known by the name it was held over from, among the groups held before the
			-- load, so two empty groups of one name this load holds over are both kept
			for _, other in ipairs(scope.groups) do -- one this load cleared since isn't there to be it
				if earlier and earlier[other] and other.held and other.from == name and next(other.marks) == nil then
					return true
				end
			end
			return false
		end
		for _, other in ipairs(before) do
			if vim.deep_equal(other.marks, marks) then
				return true
			end
		end
		return false
	end
	for i, group in ipairs(groups) do
		local marks = kept[i]
		if not going[i] and not (once and held_already(marks, group.name)) then
			if not M.first_group(scope) then
				M.first_group(scope, true) -- the keys keep a group of their own, ahead of what's held over
			end
			table.insert(scope.groups, {
				name = held_name(scope, several and (what .. ", " .. group.name) or what), marks = marks, held = true,
				from = next(marks) == nil and (group.from or group.name) or nil, -- what an empty one is known by
			})
		end
	end
	M.hold_scope("session", session_id)
	if scope.groups[1] == nil then
		data.scopes.session[session_id] = nil
	end
end

---Put what a window going holds onto its saved entry in its session's file as it stands, or queue its groups
---to be held over in its session's scope with none: a window closing, or one a whole-editor load is about to
---tear down. A copy no one changed, or one whose copy lives unchanged, loses nothing.
---
---@param winid WinId The window going, still there
---@param session string The pool id of the session it's in ("" for the whole editor's)
---@param what string What it shows, as a held-over header names it
---@return boolean onto Whether its entry took what it holds
function M.window_going(winid, session, what)
	local onto = require('frogman.domains.storage').routines.close_onto_entry("window", winid, session, what)
	local scope = data.scopes.window[winid]
	if scope and not onto and not M.unchanged_copy(winid) then
		M.queue_hold_over(vim.api.nvim_win_get_tabpage(winid), session, scope.groups, what)
	end
	return onto
end

---Put a plain tab's groups onto its saved tab entry as they stand as it goes, or queue them to be held over
---with none: a tab closing, or one a whole-editor load is about to tear down.
---
---@param tabpage integer The tab going
---@param session string The pool id of the session it's in ("" for the whole editor's)
---@param what string What it shows, as a held-over header names it
---@return nil
function M.tab_going(tabpage, session, what)
	local scope = data.scopes.tab[tabpage]
	if scope and not require('frogman.domains.storage').routines.close_onto_entry("tab", tabpage, session, what) then
		M.queue_hold_over(tabpage, session, scope.groups, what)
	end
end

---Queue a closed window's or tab's groups to be held over once the editor settles.
---
---A load holds over what's still queued as it begins, so the windows and tabs a session manager's
---switch closes inside its teardown are held over in the session left, and so are those a tab
---session's load replaces.
---
---@param tabpage integer The tab the window or tab was in
---@param session_id string The session's pool id ("" for the whole editor's)
---@param groups MarksGroup[] The groups, live
---@param what string What they were
---@return nil
function M.queue_hold_over(tabpage, session_id, groups, what)
	-- each mark by its file's handle, so a file moved before the tick keeps its mark
	local copy, ids = {}, {}
	for _, group in ipairs(groups) do
		local marks = {}
		for alias, _ in pairs(group.marks) do
			local handle = M.handle_of(group, alias)
			if handle then
				marks[alias] = handle.id
				table.insert(ids, handle.id)
			end
		end
		-- with marks or none, a group going only by its header, but for the default with none
		table.insert(copy, { name = group.name, marks = marks, default = group.default })
	end
	if #copy == 0 then
		return
	end
	-- its files stay held while it waits, by a place of its own, so none is let go in between
	data.waited = data.waited + 1
	local place = "mark:waiting:" .. data.waited
	history.handles.hold(place, ids)
	data.places["waiting:" .. data.waited] = { [place] = true }
	local entry = { tab = tabpage, session = session_id, groups = copy, what = what, place = place, key = "waiting:" .. data.waited }
	local function let_go()
		history.handles.drop_place(entry.place)
		data.places[entry.key] = nil
	end
	local function hold()
		M.hold_over(entry.session, entry.groups, entry.what)
		repaint()
		let_go()
	end
	require('frogman.held').wait_a_tick(function() return data.pending end, entry, hold)
end

---Hold over at once what closes queued, each in its session's scope: a session's, as its last tab closes
---and its records are written with its closed list, so they take it; a tab's, as a tab session's load into
---it begins; or every one, as a whole-editor load begins.
---
---@param session_id string|nil The session's pool id, or nil for any session's
---@param tabpage integer|nil The tab the closes were in, or nil for any tab's
---@return table<string, true> sessions The pool ids of the sessions it held groups over in
function M.flush_pending(session_id, tabpage)
	local due, sessions = {}, {}
	for i = #data.pending, 1, -1 do
		local entry = data.pending[i]
		if (session_id == nil or entry.session == session_id) and (tabpage == nil or entry.tab == tabpage) then
			table.insert(due, 1, table.remove(data.pending, i))
		end
	end
	for _, entry in ipairs(due) do
		M.hold_over(entry.session, entry.groups, entry.what)
		history.handles.drop_place(entry.place)
		data.places[entry.key] = nil
		sessions[entry.session] = true
	end
	if #due > 0 then
		repaint()
	end
	return sessions
end

---Let the marks of the windows and tabs that closed without their events go as their closes would have, by
---noautocmd or while frogman was off, under what each showed when it was last seen: a window's onto its saved
---entry in the session it was last seen in, or held over in that session's scope, or the whole editor's, with
---none, and a plain tab's the same in the whole editor's. A split's copy no one changed holds nothing over,
---as at a close with its events. Their buffers in the marks pop-up go too.
---
---@return nil
function M.hold_over_gone()
	local held = require('frogman.held')
	local storage = require('frogman.domains.storage').routines
	for winid, scope in pairs(data.scopes.window) do
		if not vim.api.nvim_win_is_valid(winid) and not held.closing(winid) then
			-- onto its saved entry in the session it was last seen in, when it has one there; else held over
			local session, what = held.last_session(winid) or "", held.last_seen_as("window", winid)
			if not storage.close_onto_entry("window", winid, session, what) and not M.unchanged_copy(winid) then
				M.hold_over(session, scope.groups, what) -- where it was last seen
			end
			M.drop_scope("window", winid)
			data.copies[winid] = nil
		end
	end
	for tabpage, scope in pairs(data.scopes.tab) do
		if not vim.api.nvim_tabpage_is_valid(tabpage) then
			if not storage.close_onto_entry("tab", tabpage, "", held.last_seen_as("tab", tabpage)) then
				M.hold_over("", scope.groups, held.last_seen_as("tab", tabpage))
			end
			M.drop_scope("tab", tabpage)
		end
	end
	local popup = package.loaded['frogman.domains.marks.popup']
	if popup then
		popup.let_go_gone()
	end
end

---Get the hashes of the files a session's marks hold.
---
---With no pool, every mark's. With a pool, its own marks, and those of the windows and tabs in its
---tabs; the editor's pool takes the detached lists' too.
---
---@param owner Pool|nil The session's pool, or nil for every mark
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
	local owns = require('frogman.held').owns
	for kind, scopes in pairs(data.scopes) do
		for id, _ in pairs(scopes) do
			if owns(owner, kind, id) then
				take(kind, id)
			end
		end
	end
	return held
end

---Get the hashes a file's saved groups name.
---
---@param groups {name: string, marks: table<string, Filehash>}[]|nil The groups as the session file holds them
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
