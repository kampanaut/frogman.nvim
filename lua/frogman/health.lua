---The health check, `:checkhealth frogman`.
---
---Tells whether frogman can save and load its sessions and draw everything it draws, and what to
---change when it can't. Each check asks the code that does the work, the save's own search for
---libcrypto, the folders the files go in, the modules the pop-ups load, so a check and the work it
---checks can't disagree. It writes nothing.

local M = {}

local health = vim.health

---Say a path the way the user reads it, the home folder as `~`.
---
---@param path string A full path
---@return string shown The path, with the home folder as `~`
local function shown(path)
	return vim.fn.fnamemodify(path, ":~")
end

---Check that Neovim is 0.12 or newer.
---
---@return nil
local function check_neovim()
	health.start("Neovim")
	local v = vim.version()
	local version = string.format("%d.%d.%d", v.major, v.minor, v.patch)
	if vim.fn.has("nvim-0.12") == 1 then
		health.ok("Neovim " .. version)
	else
		health.error("Neovim " .. version .. ": frogman needs 0.12 or newer", { "Update Neovim." })
	end
end

---Check that the session files can be encrypted: LuaJIT's FFI, libcrypto found by the save's own
---search, and a test text through AES-256-GCM and back.
---
---@return nil
local function check_encryption()
	health.start("Encryption")
	local crypto = require('frogman.domains.storage.crypto')
	local status = crypto.status()
	if not status.ffi then
		health.error("this Neovim has no LuaJIT FFI, which encrypts the session files", { "Use a Neovim built with LuaJIT." })
		return
	end
	health.ok("LuaJIT's FFI is there")
	if not status.library then
		local message = string.gsub(status.error or "libcrypto didn't load", "^frogman: ", "")
		health.error(message)
		return
	end
	if status.rejected then
		health.warn("libcrypto_path (" .. status.rejected.path .. ") didn't load: " .. status.rejected.why
			.. "; frogman's own list found one", { "Point libcrypto_path at OpenSSL's libcrypto, or leave it out." })
	end
	health.ok("libcrypto loaded: " .. status.library)
	local text, aad = "frogman", "health"
	local ok, back = pcall(function()
		local key = crypto.random_bytes(crypto.key_length)
		return crypto.open(key, crypto.seal(key, text, aad), aad)
	end)
	if ok and back == text then
		health.ok("a test text encrypted and decrypted again (AES-256-GCM)")
	else
		health.error("a test text didn't come back through AES-256-GCM" .. (ok and "" or ": " .. tostring(back)),
			{ "Point libcrypto_path at OpenSSL 3's or 4's libcrypto." })
	end
end

---Find whether files can be written into a folder, or into the folder it would be made in.
---
---Looks at the folder, or, while it doesn't exist yet, at its nearest parent that does, which the
---first write makes it in. Makes nothing.
---
---@param directory string The folder
---@return boolean writable Whether files can be written there
---@return string at The folder looked at: the folder itself, or its nearest parent that exists
---@return string|nil problem Why it can't be written, when it can't
local function writable(directory)
	local path = vim.fs.normalize(directory):gsub("(.)/+$", "%1")
	while true do
		local stat = vim.uv.fs_stat(path)
		if stat then
			if stat.type ~= "directory" then
				return false, path, "isn't a folder"
			end
			if vim.uv.fs_access(path, "W") and vim.uv.fs_access(path, "X") then
				return true, path, nil
			end
			return false, path, "can't be written"
		end
		local parent = vim.fs.dirname(path)
		if parent == path then
			return false, path, "doesn't exist"
		end
		path = parent
	end
end

---Check that one folder frogman writes into can be written.
---
---@param label string What the folder holds
---@param directory string The folder
---@param advice string What to do when it can't be written
---@return nil
local function check_folder(label, directory, advice)
	local ok, at, problem = writable(directory)
	if ok and at == vim.fs.normalize(directory):gsub("(.)/+$", "%1") then
		health.ok(label .. ": " .. shown(directory) .. " (writable)")
	elseif ok then
		health.ok(label .. ": " .. shown(directory) .. " (made at the first write, inside " .. shown(at) .. ", which is writable)")
	else
		health.error(label .. ": " .. shown(directory) .. " can't be used: " .. shown(at) .. " " .. problem, { advice })
	end
end

---Check that the session files and the dumps can be written, without writing anything.
---
---@return nil
local function check_folders()
	health.start("Folders")
	check_folder("sessions", require('frogman.configs').session_dir,
		"Set session_dir to a folder you can write, or make this one writable.")
	check_folder("dumps", require('frogman.domains.ledger.dump').directory(),
		"Make this folder writable: the flight recorder writes its dumps there.")
end

---Check that setup() has run and that disable() hasn't turned frogman off since.
---
---@return nil
local function check_setup()
	health.start("Setup")
	local on = require('frogman.state').on
	if on == nil then
		health.warn("setup() hasn't run, so nothing is tracked",
			{ "Call require('frogman').setup(), or set config = true in lazy.nvim's spec." })
	elseif on == false then
		health.warn("disable() turned frogman off, so nothing is tracked", { "Call require('frogman').setup() to turn it on again." })
	else
		health.ok("setup() has run, and frogman is on")
	end
end

---Load a module the way frogman's own code does, nothing said when it isn't there.
---
---@param name string The module
---@return any|nil module The module, or nil when it doesn't load
local function loads(name)
	local ok, module = pcall(require, name)
	return ok and module or nil
end

---Check the plugins frogman uses, by the modules its own code loads: telescope and
---nvim-window-picker are required, cokeline has a fallback.
---
---@return nil
local function check_plugins()
	health.start("Plugins frogman uses")
	if loads("telescope.builtin") and loads("telescope.pickers") then
		health.ok("telescope.nvim")
	else
		health.error("telescope.nvim isn't installed: the primary pop-up can't add files through a picker, and the marks pop-up can't pick an alias or a file",
			{ "Install nvim-telescope/telescope.nvim." })
	end
	local picker = loads("window-picker")
	if type(picker) == "table" and type(picker.pick_window) == "function" then
		health.ok("nvim-window-picker")
	else
		health.error("nvim-window-picker isn't installed: a snapshot whose list's window is gone can't be shown anywhere",
			{ "Install s1n7ax/nvim-window-picker." })
	end
	if loads("cokeline.mappings") then
		health.ok("nvim-cokeline")
	else
		health.warn("nvim-cokeline isn't installed: the bufferline shows no visit order or role colours, and the cycle keys step through frogman's own order",
			{ "Install willothy/nvim-cokeline, and set it up as frogman's README shows." })
	end
end

---Say what to do about a key that clashes.
---
---@param key {lhs: string, desc: string, name: string|nil} The key, as the state lists it
---@return string advice
local function move_it(key)
	if key.name then
		return "Set keymaps." .. key.name .. " to another key, or to false to leave it unmapped."
	end
	return "Move the marks' keys in the config: keymaps.mark_prefix, keymaps.mark_modes, keymaps.mark_popup or marks.aliases."
end

---Check frogman's keys: a key another mapping had before setup() took it, a key mapped over or
---unmapped since, and a main key that's the same as one of the marks' keys.
---
---@return nil
local function check_keys()
	health.start("Keys")
	local state = require('frogman.state')
	if state.on == nil then
		health.info("no keys mapped yet: setup() hasn't run")
		return
	end
	local ours, said, keys, found = {}, {}, {}, 0
	for _, callback in pairs(state.mapped) do
		ours[callback] = true
	end
	for _, key in ipairs(state.keys) do
		if not said[key.lhs] then
			said[key.lhs] = true
			table.insert(keys, key)
		end
	end
	for _, key in ipairs(keys) do
		local took = state.took[key.lhs]
		if took then
			found = found + 1
			health.warn(key.lhs .. " was mapped to " .. took .. " before setup() mapped it to " .. key.desc:lower(), { move_it(key) })
		end
		local now = state.global_mapping(key.lhs)
		if not now then
			found = found + 1
			health.warn(key.lhs .. ", frogman's key to " .. key.desc:lower() .. ", isn't mapped any more",
				{ "Something unmapped it after setup(); calling setup() again maps it again." })
		elseif now.callback ~= state.mapped[key.lhs] and not ours[now.callback] then
			found = found + 1
			health.warn(key.lhs .. ", frogman's key to " .. key.desc:lower() .. ", was mapped over after setup(): it's mapped to "
				.. state.describe(now) .. " now", { move_it(key) })
		end
	end
	-- every key mapped, a main key and a marks' key spelled alike included, which the list above
	-- holds once
	for _, main in ipairs(state.keys) do
		if main.name then
			for _, mark in ipairs(state.keys) do
				if not mark.name and vim.keycode(mark.lhs) == vim.keycode(main.lhs) then
					found = found + 1
					health.warn(main.lhs .. " is frogman's key to both " .. main.desc:lower() .. " and " .. mark.desc:lower()
						.. "; the marks' key took it", { move_it(main) })
				end
			end
		end
	end
	if found == 0 and #keys == 0 then
		health.info("frogman maps no keys: every one is off in the config")
	elseif found == 0 then
		health.ok("each of frogman's " .. #keys .. " keys is its own, and none took another mapping")
	end
end

---Run every check, each one's own failure an error of its own, so the rest still run.
---
---@return nil
function M.check()
	for _, check in ipairs({ check_neovim, check_encryption, check_folders, check_setup, check_plugins, check_keys }) do
		local ok, err = pcall(check)
		if not ok then
			health.error("the check failed: " .. tostring(err))
		end
	end
end

return M
