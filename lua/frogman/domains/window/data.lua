---Window domain data structures and state management.
---@alias WinId number -- Window ID type alias
---
---@class WindowState Per-window buffer relationship data
---@field altbufs table<WinId, WindowTriquetra> Window ID to buffer relationships mapping
---@field current_window number Currently active window ID

---@class WindowTriquetra Triquetra buffer relationships for a single window, each file by its handle
---@field current_slot HandleId The current slot's file. Whatever is currently shown in the window.
---@field secondary_slot HandleId|nil User-controlled "waiting" slot, user can store what buffer is in the secondary slot.
---@field ternary_slot HandleId|nil Auto-populated waiting slot, the "previous" current.
---@field primary_buffer HandleId[]|nil The file buffer which can take its place in one of the three at a time.
---@field primary_enabled boolean Whether the primary buffer is enabled in this triquetra.
---@field displacement_ternary_map table<HandleId|string, HandleId> -- This is a file's ternary before it got displaced, its swap note under `<id>-swap`.
---@field displacement_secondary_map table<HandleId|string, HandleId> -- This is a file's secondary before it got displaced, its swap note under `<id>-swap`.
---
local M = {}

---@type table<number, WindowTriquetra>
M.crux = {}

---Windows whose buffer got deleted, waiting to land once the delete is over (window → the buffer
---being deleted, and Neovim's own pick once it's entered)
---@type table<WinId, { deleted: Bufnr, pick: Bufnr|nil }>
M.landing = {}

---Each window's last arrival (window → the arriving file's handle, and its triquetra just before and
---just after), so the arrival can be undone when that buffer turns into something frogman doesn't track
---@type table<WinId, { id: HandleId, before: WindowTriquetra, after: WindowTriquetra|nil }>
M.arrivals = {}

local history = require('frogman.domains.history')

---@class Triquetra: WindowTriquetra A window's triquetra, whose writes hold its files
local Triquetra = {}
Triquetra.__index = Triquetra
M.Triquetra = Triquetra

---The window each live triquetra belongs to (triquetra → window). A copy isn't in it, so its
---writes hold nothing.
---@type table<Triquetra, WinId>
local window_of = setmetatable({}, { __mode = "k" })

---Get the name of a window's place for one of its slots, as the handles' holders know it.
---
---@param winid WinId
---@param slot "current"|"secondary"|"ternary"|"primary"
---@return string place Like "win:1000:ternary"
local function place_of(winid, slot)
	return "win:" .. winid .. ":" .. slot
end

-- each field a write can change, and the place that holds what it holds
local PLACE_OF_FIELD = { current_slot = "current", secondary_slot = "secondary", ternary_slot = "ternary", primary_buffer = "primary" }

---Hold the files a live triquetra's slots and primary queue hold now, each by its place.
---
---@param triquetra Triquetra
---@param fields string[]|nil The fields the write changed, so only their places are written (nil = every one)
---@return nil
local function hold_places(triquetra, fields)
	local winid = window_of[triquetra]
	if winid == nil or M.crux[winid] ~= triquetra then
		return -- a copy, or one replaced: it holds nothing
	end
	for _, field in ipairs(fields or { "current_slot", "secondary_slot", "ternary_slot", "primary_buffer" }) do
		local slot = PLACE_OF_FIELD[field]
		if slot then
			local value = triquetra[field]
			history.handles.hold(place_of(winid, slot), field == "primary_buffer" and (value or {}) or { value })
		end
	end
end

---Let go of everything a window's places hold.
---
---@param winid WinId
---@return nil
local function drop_places(winid)
	local handles = history.handles
	for _, slot in ipairs({ "current", "secondary", "ternary", "primary" }) do
		handles.drop_place(place_of(winid, slot))
	end
end

---Write one of the three slots.
---
---Its place holds the new file at once, and lets the old one go.
---
---@param slot "current_slot"|"secondary_slot"|"ternary_slot" The slot to write
---@param id HandleId|nil The handle of the file it holds now (nil = empty)
---@return nil
function Triquetra:set(slot, id)
	self[slot] = id
	hold_places(self, { slot })
end

---Write several fields at once.
---
---A slot given vim.NIL is emptied. The current, secondary and ternary slots are checked once, after
---every field is written: an update leaving one file in two of them is refused, since only a bug
---can make one, and the triquetra stays as it was.
---
---@param fields table<string, any> The fields and what they become
---@return nil
---@error "Refused an update leaving one file in two triquetra slots." if it would break I1
function Triquetra:update(fields)
	local after = {}
	for _, slot in ipairs({ "current_slot", "secondary_slot", "ternary_slot" }) do
		local value = fields[slot]
		if value == nil then
			value = self[slot]
		elseif value == vim.NIL then
			value = nil
		end
		after[slot] = value
	end
	local c, s, t = after.current_slot, after.secondary_slot, after.ternary_slot
	if (s and s == c) or (t and t == c) or (s and t and s == t) then
		require('frogman.domains.ledger').never("Refused an update leaving one file in two triquetra slots.")
	end
	for key, value in pairs(fields) do
		if value == vim.NIL then
			self[key] = nil
		else
			self[key] = value
		end
	end
	hold_places(self, vim.tbl_keys(fields))
end

---Replace the primary queue.
---
---@param queue HandleId[] The files' handles, the primary first
---@return nil
function Triquetra:set_queue(queue)
	self.primary_buffer = queue
	hold_places(self, { "primary_buffer" })
end

---Put a file in the primary queue.
---
---@param position integer Where it goes (1 = the primary)
---@param id HandleId The file's handle
---@return nil
function Triquetra:queue_insert(position, id)
	table.insert(self.primary_buffer, position, id)
	hold_places(self, { "primary_buffer" })
end

---Take an entry out of the primary queue.
---
---@param index integer The entry's position
---@return HandleId|nil id The entry taken out
function Triquetra:queue_remove(index)
	local id = table.remove(self.primary_buffer, index)
	hold_places(self, { "primary_buffer" })
	return id
end

---Write one entry of the primary queue.
---
---@param index integer The entry's position
---@param id HandleId The file's handle
---@return nil
function Triquetra:queue_set(index, id)
	self.primary_buffer[index] = id
	hold_places(self, { "primary_buffer" })
end

---Make a window's triquetra from its fields, and hold what it holds.
---
---Every live triquetra is made here. One the window had already is let go first.
---
---@param winid WinId
---@param fields WindowTriquetra The triquetra's fields
---@return Triquetra triquetra
function M.make_triquetra(winid, fields)
	if M.crux[winid] and M.crux[winid] ~= fields then
		window_of[M.crux[winid]] = nil
		drop_places(winid)
	end
	local triquetra = setmetatable(fields, Triquetra)
	M.crux[winid] = triquetra
	window_of[triquetra] = winid
	hold_places(triquetra)
	return triquetra
end

---Let go of every triquetra at once, as a teardown or a fresh start does.
---
---@return nil
function M.drop_all_triquetras()
	for winid, triquetra in pairs(M.crux) do
		window_of[triquetra] = nil
		drop_places(winid)
	end
	M.crux = {}
end

---Create a new empty window buffer relationship.
---
---@param winid number Window ID to create the relationship for
function M.register_triquetra(winid)
	local current_slot = history.routines.get_handle_from_buffer(vim.api.nvim_win_get_buf(winid))
	if not current_slot then
		error("Cannot create empty window buffer relationship: The window has an unregistered buffer.")
	end
	history.routines.ensure_window_entry(winid) -- every triquetra comes with its window's history entry.
    M.make_triquetra(winid, {
		current_slot = current_slot,
		secondary_slot = nil,
		ternary_slot = nil,
		primary_buffer = {},
		displacement_ternary_map = {},
		displacement_secondary_map = {},
		primary_enabled = false,
    })
	-- print("Registered triquetra for window " .. winid .. " with current slot: " .. current_slot .. "\n" .. debug.traceback())
end

local counter = 0

function M.unregister_triquetra(winid)
	local navigation = require('frogman.domains.navigation.routines')
	if not M.crux[winid] then
		return
	end

	window_of[M.crux[winid]] = nil
	drop_places(winid)
	M.crux[winid] = nil
	M.arrivals[winid] = nil
	history.routines.unregister_window(winid)
	require("frogman.domains.ui.data").clear_window_display_cache(winid)
	local current = vim.api.nvim_get_current_win()
	if current ~= winid and M.crux[current] then
		M.last_valid_window = current -- the window you're in, whose view the bufferline and the fill read
	else
		M.last_valid_window = navigation.get_the_previous_window_traverse_chain(winid)
	end
	if M.last_valid_window then
		history.routines.construct_crux(M.last_valid_window)
	end

	require('frogman.domains.ui.routines').remove_winbar_string(winid)
	-- print("Unregistered triquetra for window " .. winid .. "\n" .. debug.traceback())
end

---Get or create window buffer relationships for a window.
---
---@param winid number Window ID to get relationships for
---@return WindowTriquetra|nil relationship The window's buffer relationships
function M.get_window_triquetra(winid)
	if winid == 0 then
		winid = vim.api.nvim_get_current_win() -- Neovim's "current window"
	end
	if winid == nil or not vim.api.nvim_win_is_valid(winid) then
		return nil -- a window that's gone (e.g. :only closed it) has no triquetra to give.
	end
	local wbufnr = vim.api.nvim_win_get_buf(winid)
    if not M.crux[winid] then
		local config = vim.api.nvim_win_get_config(winid)
		if config.relative == "" and history.get_hash_from_buffer(wbufnr) then
			M.register_triquetra(winid)
		else
			return nil
		end
    end
	-- a window keeps its triquetra while it shows something we don't track (it's visiting), and its current
	-- slot stays the file it was last on. a window born untracked (a :help or :copen split) never gets one:
	-- it's only taken in once the editor settles, when it already shows what it was born with.
    return M.crux[winid]
end

---Take a file out of every triquetra's secondary and ternary slots and primary queue.
---
---The current slot is left to whatever lands the window.
---
---@param id HandleId The file's handle
---@return nil
function M.forget_handle_in_slots(id)
	for _, triquetra in pairs(M.crux) do
		if triquetra.secondary_slot == id then
			triquetra:set("secondary_slot", nil)
		end
		if triquetra.ternary_slot == id then
			triquetra:set("ternary_slot", nil)
		end
		for i = #triquetra.primary_buffer, 1, -1 do
			if triquetra.primary_buffer[i] == id then
				triquetra:queue_remove(i)
			end
		end
	end
end

---Get the file a note belongs to, from its key in a note map.
---
---A plain note is keyed by its file's handle, a swap note by the handle and `-swap`.
---
---@param key HandleId|string A note map's key
---@return HandleId|nil id The handle of the file whose note it is
function M.note_owner(key)
	if type(key) == "number" then
		return key
	end
	return tonumber((tostring(key):gsub("%-swap$", "")))
end

---Check if a note map's key is a swap note's.
---
---@param key HandleId|string A note map's key
---@return boolean swap
function M.is_swap_note(key)
	return type(key) == "string" and key:match("%-swap$") ~= nil
end

---Get a note map as a session file or a dump holds it, by hash.
---
---A plain note's key is its file's hash, and a swap note's the hash and `-swap`. A note naming a
---handle let go since is left out.
---
---@param map table<HandleId|string, HandleId>|nil The note map, as memory holds it
---@return table<string, Filehash> saved The note map, by hash
function M.notes_by_hash(map)
	local saved = {}
	for key, id in pairs(map or {}) do
		local owner = history.get_hash_from_handle(M.note_owner(key))
		local filehash = history.get_hash_from_handle(id)
		if owner and filehash then
			saved[M.is_swap_note(key) and owner .. "-swap" or owner] = filehash
		end
	end
	return saved
end

---Get a note map from a session file or a dump, by handle.
---
---A note naming a hash no handle has is left out.
---
---@param saved table<string, Filehash>|nil The note map, as the file holds it
---@return table<HandleId|string, HandleId> map The note map, as memory holds it
function M.notes_by_handle(saved)
	local map = {}
	for key, filehash in pairs(type(saved) == "table" and saved or {}) do
		local owner = history.get_handle_from_hash((tostring(key):gsub("%-swap$", "")))
		local id = history.get_handle_from_hash(filehash)
		if owner and id then
			map[tostring(key):match("%-swap$") and owner .. "-swap" or owner] = id
		end
	end
	return map
end

---Let a moved file take the place of the file whose name it took, in one triquetra or a copy of one.
---
---@param triquetra WindowTriquetra The triquetra, or an arrival's copy of one
---@param from HandleId The handle of the file whose name was taken
---@param to HandleId The moved file's handle
---@return nil
local function take_over_in(triquetra, from, to)
	if triquetra.current_slot == from then
		-- the current slot keeps the name, which is the moved file now
		if triquetra.secondary_slot == to then triquetra:set("secondary_slot", nil) end
		if triquetra.ternary_slot == to then triquetra:set("ternary_slot", nil) end
		triquetra:set("current_slot", to)
	elseif triquetra.current_slot == to or triquetra.secondary_slot == to or triquetra.ternary_slot == to then
		if triquetra.secondary_slot == from then triquetra:set("secondary_slot", nil) end
		if triquetra.ternary_slot == from then triquetra:set("ternary_slot", nil) end
	else
		if triquetra.secondary_slot == from then triquetra:set("secondary_slot", to) end
		if triquetra.ternary_slot == from then triquetra:set("ternary_slot", to) end
	end
	local queue, seen = {}, false
	for _, id in ipairs(triquetra.primary_buffer) do
		if id == from then
			id = to
		end
		if id ~= to or not seen then
			table.insert(queue, id)
		end
		seen = seen or id == to
	end
	if #queue ~= #triquetra.primary_buffer or vim.tbl_contains(triquetra.primary_buffer, from) then
		triquetra:set_queue(queue)
	end
	for _, map in ipairs({ triquetra.displacement_ternary_map, triquetra.displacement_secondary_map }) do
		for _, keys in ipairs({ { from, to }, { from .. "-swap", to .. "-swap" } }) do
			if map[keys[1]] ~= nil then
				if map[keys[2]] == nil then
					map[keys[2]] = map[keys[1]]
				end
				map[keys[1]] = nil
			end
		end
		for key, value in pairs(map) do
			if value == from then
				map[key] = to
			end
		end
		for _, key in ipairs({ to, to .. "-swap" }) do
			if map[key] == to then
				map[key] = nil
			end
		end
	end
end

---Let a moved file take the place of the file whose name it took, in every triquetra.
---
---Used when a move takes a name a live handle had: that handle is let go, and what held it holds the
---moved file. A triquetra holding both would hold one file twice: the moved file keeps its slot, and
---the other slot lets it go, unless that's the current slot, which keeps it. A primary queue keeps
---the file once, where it came first. The name's notes become the moved file's where it has none of
---its own, every note naming the name names the moved file, and a note that now names its own buffer
---goes. Each window's arrival copies take it the same way, so an undo still finds the window as its
---arrival left it.
---
---@param from HandleId The handle of the file whose name was taken
---@param to HandleId The moved file's handle
---@return nil
function M.take_over_handle(from, to)
	for _, triquetra in pairs(M.crux) do
		take_over_in(triquetra, from, to)
	end
	for _, arrival in pairs(M.arrivals) do
		take_over_in(arrival.before, from, to)
		if arrival.after then
			take_over_in(arrival.after, from, to)
		end
	end
end

---@type WinId|nil
M.last_valid_window = vim.api.nvim_get_current_win()
---@type WinId
M.current_window = vim.api.nvim_get_current_win()

return M
