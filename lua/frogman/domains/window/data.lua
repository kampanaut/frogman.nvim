---Window domain data structures and state management.
---@alias WinId number -- Window ID type alias
---
---@class WindowState Per-window buffer relationship data
---@field altbufs table<WinId, WindowTriquetra> Window ID to buffer relationships mapping
---@field current_window number Currently active window ID

---@class WindowTriquetra Triquetra buffer relationships for a single window
---@field current_slot Filehash The current slot filename. Whatever is currently shown in the window.
---@field secondary_slot Filehash|nil User-controlled "waiting" slot, user can store what buffer is in the secondary slot.
---@field ternary_slot Filehash|nil Auto-populated waiting slot, the "previous" current.
---@field primary_buffer Filehash[]|nil The file buffer which can take its place in one of the three at a time.
---@field primary_enabled boolean Whether the primary buffer is enabled in this triquetra.
---@field displacement_ternary_map table<Filehash, Filehash> -- This is filename's ternary before it got displaced.
---@field displacement_secondary_map table<Filehash, Filehash> -- This is filename's secondary before it got displaced.
---
local M = {}

---@type table<number, WindowTriquetra>
M.crux = {}

---Windows whose buffer got deleted, waiting to land once the delete is over (window → the buffer
---being deleted, and Neovim's own pick once it's entered)
---@type table<WinId, { deleted: Bufnr, pick: Bufnr|nil }>
M.landing = {}

---Each window's last arrival (window → the buffer, and its triquetra just before and just after),
---so the arrival can be undone when that buffer turns into something frogman doesn't track
---@type table<WinId, { hash: Filehash, before: WindowTriquetra, after: WindowTriquetra|nil }>
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

---Hold the files a live triquetra's slots and primary queue hold now, each by its place.
---
---@param triquetra Triquetra
---@return nil
local function hold_places(triquetra)
	local winid = window_of[triquetra]
	if winid == nil or M.crux[winid] ~= triquetra then
		return -- a copy, or one replaced: it holds nothing
	end
	local handles = history.handles
	handles.hold(place_of(winid, "current"), { triquetra.current_slot })
	handles.hold(place_of(winid, "secondary"), { triquetra.secondary_slot })
	handles.hold(place_of(winid, "ternary"), { triquetra.ternary_slot })
	handles.hold(place_of(winid, "primary"), triquetra.primary_buffer or {})
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
---@param slot "current_slot"|"secondary_slot"|"ternary_slot"
---@param filehash Filehash|nil The file it holds now (nil = empty)
---@return nil
function Triquetra:set(slot, filehash)
	self[slot] = filehash
	hold_places(self)
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
	hold_places(self)
end

---Replace the primary queue.
---
---@param queue Filehash[]
---@return nil
function Triquetra:set_queue(queue)
	self.primary_buffer = queue
	hold_places(self)
end

---Put a file in the primary queue.
---
---@param position integer Where it goes (1 = the primary)
---@param filehash Filehash
---@return nil
function Triquetra:queue_insert(position, filehash)
	table.insert(self.primary_buffer, position, filehash)
	hold_places(self)
end

---Take an entry out of the primary queue.
---
---@param index integer
---@return Filehash|nil filehash The entry taken out
function Triquetra:queue_remove(index)
	local filehash = table.remove(self.primary_buffer, index)
	hold_places(self)
	return filehash
end

---Write one entry of the primary queue.
---
---@param index integer
---@param filehash Filehash
---@return nil
function Triquetra:queue_set(index, filehash)
	self.primary_buffer[index] = filehash
	hold_places(self)
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
	local current_slot = history.get_hash_from_buffer(vim.api.nvim_win_get_buf(winid))
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

---Take a hash out of every triquetra's secondary and ternary slots and primary queue.
---
---The current slot is left to whatever lands the window.
---
---@param hash Filehash The hash to take out
---@return nil
function M.forget_hash_in_slots(hash)
	for _, triquetra in pairs(M.crux) do
		if triquetra.secondary_slot == hash then
			triquetra:set("secondary_slot", nil)
		end
		if triquetra.ternary_slot == hash then
			triquetra:set("ternary_slot", nil)
		end
		for i = #triquetra.primary_buffer, 1, -1 do
			if triquetra.primary_buffer[i] == hash then
				triquetra:queue_remove(i)
			end
		end
	end
end

---Rename a hash to a new hash across all window triquetras.
---
---Updates all references to old_hash in triquetra slots and displacement maps.
---
---@param old_hash Filehash The hash to be renamed
---@param new_hash Filehash The new hash to replace it with
function M.rename_hash_in_triquetras(old_hash, new_hash)
    for _, triquetra in pairs(M.crux) do
        -- Update slots
        if triquetra.current_slot == old_hash then
            triquetra:set("current_slot", new_hash)
        end
        if triquetra.secondary_slot == old_hash then
            triquetra:set("secondary_slot", new_hash)
        end
        if triquetra.ternary_slot == old_hash then
            triquetra:set("ternary_slot", new_hash)
        end

		local index = vim.fn.index(triquetra.primary_buffer, old_hash) + 1
        if index ~= 0 then
            triquetra:queue_set(index, new_hash)
        end
        
        -- Update displacement maps (keys)
        if triquetra.displacement_ternary_map[old_hash] then
            local displaced_value = triquetra.displacement_ternary_map[old_hash]
            triquetra.displacement_ternary_map[old_hash] = nil
            triquetra.displacement_ternary_map[new_hash] = displaced_value
        end
		if triquetra.displacement_ternary_map[old_hash.."-swap"] then
            local displaced_value = triquetra.displacement_ternary_map[old_hash.."-swap"]
            triquetra.displacement_ternary_map[old_hash.."-swap"] = nil
            triquetra.displacement_ternary_map[new_hash.."-swap"] = displaced_value
		end
        if triquetra.displacement_secondary_map[old_hash] then
            local displaced_value = triquetra.displacement_secondary_map[old_hash]
            triquetra.displacement_secondary_map[old_hash] = nil
            triquetra.displacement_secondary_map[new_hash] = displaced_value
        end
		if triquetra.displacement_secondary_map[old_hash.."-swap"] then
            local displaced_value = triquetra.displacement_secondary_map[old_hash.."-swap"]
            triquetra.displacement_secondary_map[old_hash.."-swap"] = nil
            triquetra.displacement_secondary_map[new_hash.."-swap"] = displaced_value
		end

        -- Update displacement maps (values)
        for hash, displaced_hash in pairs(triquetra.displacement_ternary_map) do
            if displaced_hash == old_hash then
                triquetra.displacement_ternary_map[hash] = new_hash
            end
        end
        for hash, displaced_hash in pairs(triquetra.displacement_secondary_map) do
            if displaced_hash == old_hash then
                triquetra.displacement_secondary_map[hash] = new_hash
            end
        end
    end
end

---@type WinId|nil
M.last_valid_window = vim.api.nvim_get_current_win()
---@type WinId
M.current_window = vim.api.nvim_get_current_win()

return M
