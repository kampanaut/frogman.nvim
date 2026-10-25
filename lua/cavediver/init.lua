---Cavediver - Sophisticated buffer and window management plugin
---
---A state machine-driven buffer management system with triquetra window relationships,
---hash-based buffer tracking, and encrypted session persistence.
---
---@class Cavediver
local M = {}

-- Import all domains
local navigation = require('cavediver.domains.navigation')
local history = require('cavediver.domains.history')
local window = require('cavediver.domains.window')
local ui = require('cavediver.domains.ui')
local storage = require('cavediver.domains.storage')
local ledger = require('cavediver.domains.ledger')
local settle = require('cavediver.settle')
local engine = require('cavediver.engine')

local settings = require('cavediver.configs')
-- the defaults as they are before any setup(), which every setup() starts from
local defaults = vim.deepcopy(settings)

-- Export domains for direct access (backward compatibility)
M.navigation = navigation
M.history = history
M.window = window
M.ui = ui
M.storage = storage
M.ledger = ledger
M.engine = engine

-- The keys the last setup mapped, each with its callback, so the next one takes off those that are
-- still cavediver's
local mapped = {}

-- Each key cavediver maps: its name in the config, the export it runs and its description. The
-- same table wraps the exports, so a key's export can't be left unwrapped.
local keymap_actions = {
	-- Buffer lifecycle
	{ "reopen_last_closed", "reopen_last_closed", "Reopen last closed buffer" },
	-- Core triquetra operations
	{ "toggle_secondary", "toggle_secondary", "Toggle current ↔ secondary buffer" },
	{ "toggle_ternary", "toggle_ternary", "Toggle current ↔ ternary buffer" },
	{ "jump_to_primary", "jump_to_primary", "Bring primary buffer to current" },
	{ "restore_ternary", "restore_ternary", "Restore ternary relationship" },
	{ "restore_secondary", "restore_secondary", "Restore secondary relationship" },
	-- Cycling mode navigation
	{ "cycle_left", "cycle_left", "Cycle left during cycling mode" },
	{ "cycle_right", "cycle_right", "Cycle right during cycling mode" },
	{ "cycle_select", "cycle_select", "Select cycling buffer and attach history" },
	{ "toggle_window", "toggle_window", "Toggle between current and previous window" },
	{ "set_primary", "set_primary", "Set current buffer as primary" },
	-- Primary buffer management
	{ "toggle_primary", "toggle_primary", "Switch the primary on or off" },
	{ "close_buffer", "delete_buffer", "Close the current buffer" },
	{ "open_primary_buffer_history", "open_primary_buffer_history", "Open the primary queue" },
	{ "open_closed_lists", "open_closed_lists", "Open the closed lists" },
}

---Setup keymaps for cavediver operations
---@param keymaps CavediverKeymaps Keymap configuration
local function setup_keymaps(keymaps)
	-- the last setup's keys go first, those another mapping hasn't replaced since
	for lhs, callback in pairs(mapped) do
		if vim.fn.maparg(lhs, 'n', false, true).callback == callback then
			vim.keymap.del('n', lhs)
		end
	end
	mapped = {}
	if not keymaps then return end

	for _, action in ipairs(keymap_actions) do
		local lhs, desc = keymaps[action[1]], action[3]
		if lhs then
			vim.keymap.set('n', lhs, function()
				-- the export as it is when the key is pressed, so a reassigned one takes the key
				ledger.run_key(lhs, vim.api.nvim_get_current_win(), M[action[2]])
			end, { desc = desc })
		end
	end

	for action, lhs in pairs(keymaps) do
		if type(lhs) == "string" and type(defaults.keymaps[action]) == "string" then
			mapped[lhs] = vim.fn.maparg(lhs, 'n', false, true).callback
		end
	end
end

local setup_debug_commands

---Initialize cavediver plugin with configuration.
---
---Nothing runs at require, so this creates the autocmds (in the cavediver augroup), the commands
---and the timers, and calling it again replaces them, the last call's keys too. Each call starts
---from the defaults. A list replaces the default list whole, a key the defaults lack takes the
---user's value, and a table given where the default is something else (or the other way) throws.
---
---@param user_config? CavediverConfig User configuration (merged with defaults)
---@return nil
function M.setup(user_config)
	-- Start from the defaults, put back in place, since the domains hold this table
	local function reset_into(current, default)
		for key in pairs(current) do
			if default[key] == nil then
				current[key] = nil
			end
		end
		for key, value in pairs(default) do
			if type(value) == "table" and type(current[key]) == "table" and not vim.islist(value) then
				reset_into(current[key], value)
			else
				current[key] = vim.deepcopy(value)
			end
		end
	end

	reset_into(settings, defaults)

	-- Merge user configuration with defaults
	
	local function deep_merge_into(default, user_config)
		for key, value in pairs(user_config) do
			local type_value = type(value)
			local type_default = type(default[key])
			if type(value) == "table" and type(default[key]) == "table" and vim.islist(value) and vim.islist(default[key]) then
				default[key] = vim.deepcopy(value) -- a list replaces the default list whole
			elseif type(value) == "table" and type(default[key]) == "table" then 
				deep_merge_into(default[key], value)
			elseif type_default == "nil" then
				default[key] = vim.deepcopy(value) -- a key the defaults don't have takes the user's value
			elseif type_value ~= "table" and type_default ~= "table" then
				default[key] = value
			else
				error("Type mismatch for key '" .. key .. "': default is " .. type_default .. ", user config is " .. type_value)
			end
		end
	end

	deep_merge_into(settings, user_config or {})

	-- Store config for domain access
	M.config = settings
	
	local group = vim.api.nvim_create_augroup("cavediver", { clear = true })
	ledger.init_autocmds(group) -- first, so a step has begun before the others act on its event
	history.init_autocmds(group)
	navigation.init_autocmds(group)
	window.init_autocmds(group)
	ui.init_autocmds(group)
	storage.init_autocmds(group)

	ui.init_winbar_highlights()
	ui.init_trail_highlights()
	ui.init_refresh_timer()
	history.init_cleanup_timer()
	history.routines.enable_head_watch(true)
	setup_debug_commands()
	vim.api.nvim_create_user_command("CavediverClosed", function()
		M.open_closed_lists()
	end, { desc = "Open the closed lists" })
	vim.api.nvim_create_user_command("CavediverDump", function(opts)
		require('cavediver.domains.ledger.dump').open(opts.args)
	end, { nargs = 1, complete = "file", desc = "Open a flight recorder dump, decrypted, in a window (only from the directory it was written in)" })
	-- the winbar, indicator and bufferline toggles: on, off, or toggle (no argument toggles)
	for name, part in pairs({ CavediverWinbar = "winbar", CavediverIndicators = "indicators", CavediverBufferline = "bufferline" }) do
		vim.api.nvim_create_user_command(name, function(opts)
			local args = vim.deepcopy(opts.fargs)
			local kind = part == "indicators" and (args[1] == "roles" or args[1] == "harpoon") and table.remove(args, 1) or nil
			local hidden = ui.is_hidden(part, kind)
			local want = args[1] or "toggle"
			if #args > 1 then
				want = nil
			end
			if want == "on" or (want == "toggle" and hidden) then
				ui["show_" .. part](kind)
			elseif want == "off" or (want == "toggle" and not hidden) then
				ui["hide_" .. part](kind)
			else
				vim.notify("cavediver: :" .. name .. " takes " .. (part == "indicators" and "roles or harpoon, then " or "")
					.. "on, off or toggle.", vim.log.levels.WARN)
			end
		end, { nargs = "*", complete = function()
			return part == "indicators" and { "roles", "harpoon", "on", "off", "toggle" } or { "on", "off", "toggle" }
		end,
			desc = "Switch cavediver's " .. part .. " on or off, or toggle it" })
	end
	vim.api.nvim_create_user_command("CavediverTrail", function(opts)
		M.open_trail(opts.args)
	end, { nargs = "?", desc = "Open the trail, or with a name, that name's life line across every page" })

	-- Setup keymaps
	setup_keymaps(settings.keymaps)
end

---Setup debug commands for inspecting internal state
function setup_debug_commands()
	-- Command 0: Print Current Window Triquetra
	vim.api.nvim_create_user_command("CavediverHistoryData", function()
		print(vim.inspect(history.data))
	end, { desc = "Print curernt history state" })
	vim.api.nvim_create_user_command("CavediverNavigationData", function()
		print(vim.inspect(navigation.data))
	end, { desc = "Print curernt navigation state" })
	vim.api.nvim_create_user_command("CavediverWindowData", function()
		print(vim.inspect(window.data))
	end, { desc = "Print current window state" })
	vim.api.nvim_create_user_command("CavediverUIData", function()
		print(vim.inspect(ui.data))
	end, { desc = "Print current UI state" })
	-- Command 1: Print Current Window Triquetra
	vim.api.nvim_create_user_command("CavediverTriquetra", function()
		local winid = vim.api.nvim_get_current_win()
		local triquetra = window.get_triquetra(winid)

		if not triquetra then
			print("No triquetra data for window " .. winid)
			return
		end

		print("=== Window " .. winid .. " Triquetra ===")
		print("Current slot:    " .. (triquetra.current_slot or "nil"))
		print("Secondary slot:  " .. (triquetra.secondary_slot or "nil"))
		print("Ternary slot:    " .. (triquetra.ternary_slot or "nil"))
		print("Primary buffer:  " .. (triquetra.primary_buffer[1] or "nil"))
		print("Primary enabled: " .. tostring(triquetra.primary_enabled or false))

		print("\n--- Displacement Maps ---")
		print("Secondary displacement map:")
		for k, v in pairs(triquetra.displacement_secondary_map or {}) do
			print("  " .. k .. " -> " .. v)
		end

		print("Ternary displacement map:")
		for k, v in pairs(triquetra.displacement_ternary_map or {}) do
			print("  " .. k .. " -> " .. v)
		end
	end, { desc = "Print current window triquetra relationships" })

	-- Command 2: Print Registry Mappings
	vim.api.nvim_create_user_command("CavediverRegistry", function()
		print("=== Hash-Buffer Registry ===")
		print("Hash -> Buffer mapping:")
		for hash, bufnr in pairs(history.data.hash_buffer_registry.buffers) do
			local valid = vim.api.nvim_buf_is_valid(bufnr) and "valid" or "invalid"
			print("  " .. hash .. " -> [" .. bufnr .. "] (" .. valid .. ")")
		end

		print("\nBuffer -> Hash mapping:")
		for bufnr, hash in pairs(history.data.hash_buffer_registry.hashes) do
			local valid = vim.api.nvim_buf_is_valid(bufnr) and "valid" or "invalid"
			print("  [" .. bufnr .. "] -> " .. hash .. " (" .. valid .. ")")
		end

		print("\n=== Hash-Filepath Registry ===")
		print("Hash -> Filepath mapping:")
		for hash, filepath in pairs(history.data.hash_filepath_registry.filepaths) do
			print("  " .. hash .. " -> " .. filepath)
		end

		print("\nFilepath -> Hash mapping:")
		for filepath, hash in pairs(history.data.hash_filepath_registry.hashes) do
			print("  " .. filepath .. " -> " .. hash)
		end

		print("\n=== Closed Buffers ===")
		for id, pool in pairs(history.routines.pools()) do
			print(id == "" and "  (the editor's)" or ("  (" .. (pool.name or id) .. ")"))
			for i, hash in ipairs(pool.closed) do
				local filepath = history.get_filepath_from_hash(hash)
				print("  [" .. i .. "] " .. hash .. " -> " .. (filepath or "unknown"))
			end
		end
	end, { desc = "Print hash-buffer and hash-filepath registry mappings" })

	-- Command 3: Enhanced Triquetra with Filenames
	vim.api.nvim_create_user_command("CavediverTriquetraVerbose", function()
		local winid = vim.api.nvim_get_current_win()
		local triquetra = window.get_triquetra(winid)

		if not triquetra then
			print("No triquetra data for window " .. winid)
			return
		end

		local function hash_to_info(hash)
			if not hash then return "nil" end
			local filepath = history.get_filepath_from_hash(hash)
			local bufnr = history.get_buffer_from_hash(hash)
			local basename = filepath and vim.fn.fnamemodify(filepath, ":t") or "unknown"
			local loaded = bufnr and vim.api.nvim_buf_is_valid(bufnr) and "loaded" or "closed"
			return hash .. " (" .. basename .. " - " .. loaded .. ")"
		end

		print("=== Window " .. winid .. " Triquetra (Verbose) ===")
		print("Current slot:    " .. hash_to_info(triquetra.current_slot))
		print("Secondary slot:  " .. hash_to_info(triquetra.secondary_slot))
		print("Ternary slot:    " .. hash_to_info(triquetra.ternary_slot))
		print("Primary buffer:  " .. hash_to_info(triquetra.primary_buffer[1]))
		print("Primary enabled: " .. tostring(triquetra.primary_enabled or false))
	end, { desc = "Print current window triquetra with filenames" })

	-- Command 4: Print All Triquetra Objects
	vim.api.nvim_create_user_command("CavediverAllTriquetras", function()
		local function hash_to_info(hash)
			if not hash then return "nil" end
			local filepath = history.get_filepath_from_hash(hash)
			local bufnr = history.get_buffer_from_hash(hash)
			local basename = filepath and vim.fn.fnamemodify(filepath, ":t") or "unknown"
			local loaded = bufnr and vim.api.nvim_buf_is_valid(bufnr) and "loaded" or "closed"
			return hash .. " (" .. basename .. " - " .. loaded .. ")"
		end

		print("=== All Window Triquetras ===")

		-- Get all windows with triquetra data
		local windows_with_data = {}
		for winid, triquetra in pairs(window.data.crux) do
			windows_with_data[winid] = true
		end

		-- Also check UI cache for any additional windows
		for winid, _ in pairs(ui.data.window_display_cache) do
			windows_with_data[winid] = true
		end

		if vim.tbl_isempty(windows_with_data) then
			print("No triquetra data found for any windows")
			return
		end

		for winid, _ in pairs(windows_with_data) do
			local win_valid = vim.api.nvim_win_is_valid(winid)
			local triquetra = window.data.crux[winid]
			local ui_cache = ui.data.window_display_cache[winid]

			print("\n--- Window " .. winid .. " (" .. (win_valid and "valid" or "invalid") .. ") ---")

			if triquetra then
				print("Hash-based triquetra:")
				print("  Current slot:    " .. hash_to_info(triquetra.current_slot))
				print("  Secondary slot:  " .. hash_to_info(triquetra.secondary_slot))
				print("  Ternary slot:    " .. hash_to_info(triquetra.ternary_slot))
				print("  Primary buffer:  " .. hash_to_info(triquetra.primary_buffer[1]))
				print("  Primary enabled: " .. tostring(triquetra.primary_enabled or false))

				-- Show displacement maps if they exist
				local has_secondary_displacement = triquetra.displacement_secondary_map and
					not vim.tbl_isempty(triquetra.displacement_secondary_map)
				local has_ternary_displacement = triquetra.displacement_ternary_map and
					not vim.tbl_isempty(triquetra.displacement_ternary_map)

				if has_secondary_displacement or has_ternary_displacement then
					print("  Displacement maps:")
					if has_secondary_displacement then
						print("    Secondary:")
						for from_hash, to_hash in pairs(triquetra.displacement_secondary_map) do
							print("      " .. hash_to_info(from_hash) .. " -> " .. hash_to_info(to_hash))
						end
					end
					if has_ternary_displacement then
						print("    Ternary:")
						for from_hash, to_hash in pairs(triquetra.displacement_ternary_map) do
							print("      " .. hash_to_info(from_hash) .. " -> " .. hash_to_info(to_hash))
						end
					end
				end
			else
				print("  No hash-based triquetra data")
			end

			if ui_cache then
				print("UI display cache:")
				print("  Current:   [" ..
					(ui_cache.current_bufnr or "nil") .. "] " .. (ui_cache.current_display_name or "nil"))
				print("  Secondary: [" ..
					(ui_cache.secondary_bufnr or "nil") ..
					"] " ..
					(ui_cache.secondary_display_name or "nil") ..
					" (has: " .. tostring(ui_cache.has_secondary or false) .. ")")
				print("  Ternary:   [" ..
					(ui_cache.ternary_bufnr or "nil") ..
					"] " ..
					(ui_cache.ternary_display_name or "nil") ..
					" (has: " .. tostring(ui_cache.has_ternary or false) .. ")")
				print("  Primary:   [" ..
					(ui_cache.primary_bufnr or "nil") ..
					"] " ..
					(ui_cache.primary_display_name or "nil") ..
					" (has: " .. tostring(ui_cache.has_primary or false) .. ")")

				if ui_cache.loaded_slots then
					print("  Loaded slots: secondary=" ..
						tostring(ui_cache.loaded_slots.secondary or false) ..
						", ternary=" .. tostring(ui_cache.loaded_slots.ternary or false))
				end
				if ui_cache.deleted_slots then
					print("  Deleted slots: secondary=" ..
						tostring(ui_cache.deleted_slots.secondary or false) ..
						", ternary=" .. tostring(ui_cache.deleted_slots.ternary or false))
				end
			else
				print("  No UI display cache")
			end
		end

		print("\n=== Summary ===")
		print("Total windows with triquetra data: " .. vim.tbl_count(windows_with_data))
		print("Hash-based triquetras: " .. vim.tbl_count(window.data.crux))
		print("UI display caches: " .. vim.tbl_count(ui.data.window_display_cache))
	end, { desc = "Print all window triquetra objects and UI caches" })
end

---Turn cavediver off.
---
---Clears its autocmds, stops its timers and the head watch, and stops writing records, so nothing
---is tracked until setup() runs again.
---
---@return nil
function M.disable()
	vim.api.nvim_create_augroup("cavediver", { clear = true })
	ui.stop_refresh_timer()
	history.stop_cleanup_timer()
	history.routines.enable_head_watch(false)
	require('cavediver.domains.storage').routines.write_records_on(false)
end

---API Exports - Direct access to domain functionality

-- Session management
M.save_session = storage.save_session
M.load_session = storage.load_session

-- Buffer lifecycle
M.reopen_last_closed = history.reopen_last_closed

-- Triquetra operations (to be implemented in window domain)
M.toggle_secondary = function()
	local winid = vim.api.nvim_get_current_win()
	window.swap_with_secondary(winid)
end

M.toggle_ternary = function()
	local winid = vim.api.nvim_get_current_win()
	window.swap_with_ternary(winid)
end

M.jump_to_primary = function()
	local winid = vim.api.nvim_get_current_win()
	window.jump_to_primary(winid)
end

M.restore_ternary = function()
	local winid = vim.api.nvim_get_current_win()
	window.restore_triquetra_ternary(winid)
end

M.restore_secondary = function()
	local winid = vim.api.nvim_get_current_win()
	window.restore_triquetra_secondary(winid)
end

-- Navigation operations (to be implemented in navigation domain)
M.cycle_left = navigation.cycle_left

M.cycle_right = navigation.cycle_right

M.toggle_window = navigation.toggle_window
M.cycle_select = navigation.select_buffer

M.open_primary_buffer_history = ui.routines.show_primary_buffer_history
M.open_closed_lists = ui.routines.show_closed_lists
M.replay_dump = function(path)
	return require('cavediver.domains.ledger.replay').run(path)
end
M.open_trail = function(name)
	require('cavediver.domains.ui.trail').open(name)
end

-- Primary buffer management (to be implemented in window domain)
M.toggle_primary = function()
	local winid = vim.api.nvim_get_current_win()
	window.toggle_primary_buffer(winid)
end

M.delete_buffer = function()
	local winid = vim.api.nvim_get_current_win()
	history.delete_buffer(winid)
end

M.set_primary = function()
	local winid = vim.api.nvim_get_current_win()
	window.set_primary_buffer(winid)
end

-- Each key's export runs once cavediver has settled: keys in one batch (a macro, a mapping,
-- cavediver's own or a user's) can come before the settle work their events queued. A cycle still
-- running in another window, which no window entry queued a cancel for, ends too.
for _, action in ipairs(keymap_actions) do
	local export = M[action[2]]
	M[action[2]] = function(...)
		return settle.now(function(...)
			navigation.cancel_cycle_elsewhere()
			return export(...)
		end, ...)
	end
end

M.get_storage_state = function()
	return storage.sm:state()
end

-- State machine access
M.get_navigation_state = function()
	return navigation.sm:state()
end

M.get_history_state = function()
	return history.sm:state()
end

M.is_cycling = function()
	local nav_states = require('cavediver.domains.navigation.states')
	return navigation.sm:state() == nav_states.CYCLING
end

M.set_cache_from_window_triquetra = ui.set_cache_from_window_triquetra

-- Utility functions
M.get_buffer_history = history.get_buffer_history
M.get_window_triquetra = window.get_triquetra
M.get_smart_basename = ui.routines.get_smart_basename
M.winbar_segment = ui.routines.winbar_segment
M.get_all_triquetras = window.get_window_relationships

M.bufferline = ui.bufferline
return M
