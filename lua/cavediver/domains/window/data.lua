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

---Windows whose buffer got deleted and that land once the delete is over: the buffer being
---deleted, and neovim's own pick once it's entered.
---@type table<WinId, { deleted: Bufnr, pick: Bufnr|nil }>
M.landing = {}

---Each window's last arrival: the buffer, and its triquetra just before and just after, so the arrival
---can be undone when that buffer turns into something we don't track.
---@type table<WinId, { hash: Filehash, before: WindowTriquetra, after: WindowTriquetra|nil }>
M.arrivals = {}

local history = require('cavediver.domains.history')

---Create a new empty window buffer relationship.
---
---@param winid number Window ID to create the relationship for
function M.register_triquetra(winid)
	local current_slot = history.get_hash_from_buffer(vim.api.nvim_win_get_buf(winid))
	if not current_slot then
		error("Cannot create empty window buffer relationship: The window has an unregistered buffer.")
	end
	history.routines.ensure_window_entry(winid) -- every triquetra comes with its window's history entry.
    M.crux[winid] = {
		current_slot = current_slot,
		secondary_slot = nil,
		ternary_slot = nil,
		primary_buffer = {},
		displacement_ternary_map = {},
		displacement_secondary_map = {},
		primary_enabled = false,
    }
	-- print("Registered triquetra for window " .. winid .. " with current slot: " .. current_slot .. "\n" .. debug.traceback())
end

local counter = 0

function M.unregister_triquetra(winid)
	local navigation = require('cavediver.domains.navigation.routines')
	if not M.crux[winid] then
		return
	end

	M.crux[winid] = nil
	M.arrivals[winid] = nil
	history.routines.unregister_window(winid)
	require("cavediver.domains.ui.data").clear_window_display_cache(winid)
	M.last_valid_window = navigation.get_the_previous_window_traverse_chain(winid)
	if M.last_valid_window then
		history.routines.construct_crux(M.last_valid_window)
	end

	require('cavediver.domains.ui.routines').remove_winbar_string(winid)
	-- print("Unregistered triquetra for window " .. winid .. "\n" .. debug.traceback())
end

---Get or create window buffer relationships for a window.
---
---@param winid number Window ID to get relationships for
---@return WindowTriquetra|nil relationship The window's buffer relationships
function M.get_window_triquetra(winid)
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

---Take a hash out of every triquetra's secondary and ternary slots and primary queue. The current
---slot is left to whatever lands the window.
---
---@param hash Filehash
function M.forget_hash_in_slots(hash)
	for _, triquetra in pairs(M.crux) do
		if triquetra.secondary_slot == hash then
			triquetra.secondary_slot = nil
		end
		if triquetra.ternary_slot == hash then
			triquetra.ternary_slot = nil
		end
		for i = #triquetra.primary_buffer, 1, -1 do
			if triquetra.primary_buffer[i] == hash then
				table.remove(triquetra.primary_buffer, i)
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
            triquetra.current_slot = new_hash
        end
        if triquetra.secondary_slot == old_hash then
            triquetra.secondary_slot = new_hash
        end
        if triquetra.ternary_slot == old_hash then
            triquetra.ternary_slot = new_hash
        end

		local index = vim.fn.index(triquetra.primary_buffer, old_hash) + 1
        if index ~= 0 then
            triquetra.primary_buffer[index] = new_hash
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
