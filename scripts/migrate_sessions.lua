-- Convert cavediver's session files from the format before encryption to the encrypted one.
--
-- Run it once, with nothing else of your config loaded:
--
--   nvim --clean -l scripts/migrate_sessions.lua [--resession-dir <dir>] [--session-dir <path>] [--dry-run] [--replace]
--
-- Files from before encryption are plain JSON with paths XOR'd with the cwd, named after the first
-- 32 hex characters of sha256(cwd .. "\n"). The script finds which directory and session name each
-- one belongs to through resession's own session list: every session resession saved (in
-- stdpath("data")/<resession-dir>, "session" unless you pass another) names its cwd, and its name is
-- its file's name. Each old file it finds is written again in the encrypted format, under
-- sha256(directory .. "\n" .. name), the name cavediver reads when the session manager passes that
-- name. Hashes are worked out again with vim.fn.sha256, so a name the shell had mangled gets its
-- right hash where its path is known. Each old file it converts is kept, renamed with
-- ".migrated" added, which is also how the script knows what it has converted: running it again
-- changes nothing. Run it before your first session on the encrypted format: a session saved first
-- has a file in the new format already, and the script reports it instead of converting over it,
-- unless you pass --replace.
--
-- --session-dir is cavediver's session_dir, stdpath("data")/cavediver/sessions/ unless your setup()
-- sets another. --dry-run reports what would be converted and writes nothing.

local script_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(script_dir, ":h"))

local options = {
	resession_dir = "session",
	session_dir = vim.fn.stdpath("data") .. "/cavediver/sessions/",
	dry_run = false,
	replace = false,
}
local i = 1
while i <= #_G.arg do
	local a = _G.arg[i]
	if a == "--resession-dir" then
		options.resession_dir = _G.arg[i + 1]
		i = i + 1
	elseif a == "--session-dir" then
		options.session_dir = _G.arg[i + 1]
		i = i + 1
	elseif a == "--dry-run" then
		options.dry_run = true
	elseif a == "--replace" then
		options.replace = true
	else
		io.stderr:write("unknown argument: " .. a .. "\n")
		os.exit(2)
	end
	i = i + 1
end
if options.session_dir:sub(-1) ~= "/" then
	options.session_dir = options.session_dir .. "/"
end

require("cavediver.configs").session_dir = options.session_dir
local storage = require("cavediver.domains.storage.routines")
local filehash = require("cavediver.domains.history").routines.get_filehash -- as the editor hashes a name

---The XOR the format before encryption used: the cwd repeated as the key, then base64.
---@param encoded string
---@param key string
---@return string
local function xor_decipher(encoded, key)
	local text = vim.base64.decode(encoded)
	local out = {}
	for n = 1, #text do
		local k = key:byte(((n - 1) % #key) + 1)
		out[n] = string.char(bit.bxor(text:byte(n), k))
	end
	return table.concat(out)
end

---@param path string
---@return table|nil
local function read_json(path)
	local fh = io.open(path, "rb")
	if not fh then
		return nil
	end
	local text = fh:read("*a")
	fh:close()
	local ok, data = pcall(vim.fn.json_decode, text)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

---Convert one old file. `cwd` is the cwd its save was passed (the XOR key), `known` maps the hashes
---of the buffers resession saved with the session to their names.
---@return table storage, table texts, integer dropped
local function convert(old, cwd, known)
	local paths, texts, dropped = {}, {}, 0
	-- an old hash is right when its path is known (a resession buffer, or a path the old file kept)
	local function resolve(value, ciphered)
		if value == nil or value == vim.NIL then
			return nil
		end
		local path
		if known[value] then
			path = known[value]
		elseif ciphered and not value:match("^%x+$") then -- a raw hash nothing names isn't a path
			path = xor_decipher(value, cwd)
		end
		if path == nil or not (path:match("^/") or path:match("^NONAME_")) then
			dropped = dropped + 1
			return nil
		end
		local hash = filehash(path)
		paths[hash] = path
		return hash
	end
	-- a value in a slot was a raw hash when its buffer was open, otherwise a ciphered path
	local function slot(value)
		if value == nil or value == vim.NIL then
			return nil
		end
		if known[value] then
			return resolve(value, false)
		end
		return resolve(value, true)
	end
	local function map(tbl)
		local out = {}
		for k, v in pairs(tbl or {}) do
			local base, swap = k:match("^(.-)(%-swap)$")
			local key = resolve(base or k, false)
			local value = resolve(v, false)
			if key and value then
				out[key .. (swap or "")] = value
			end
		end
		return out
	end
	local function visits(tbl)
		local out = {}
		for k, v in pairs(tbl or {}) do
			local hash = resolve(k, false)
			if hash then
				out[hash] = v
			end
		end
		return out
	end

	-- the closed paths and No Name names the old file kept are known too, for the history and the notes
	for _, value in ipairs(old.closed or {}) do
		local path = xor_decipher(value, cwd)
		known[filehash(path)] = path
	end
	for value in pairs(old.noname_content or {}) do
		local path = xor_decipher(value, cwd)
		known[filehash(path)] = path
	end

	local windows = {}
	local histories = (old.buffers or {}).window or {}
	for n, w in ipairs(old.windows or {}) do
		if w ~= vim.NIL then
			local primary = {}
			for _, p in ipairs(w[3] or {}) do
				table.insert(primary, slot(p))
			end
			local current = slot(w[1])
			table.insert(windows, {
				current or vim.NIL,
				slot(w[2]) or vim.NIL,
				primary,
				slot(w[4]) or vim.NIL,
				map(w[5]),
				map(w[6]),
				current or vim.NIL, -- what the window showed: its current slot, as the old save left it
				#primary > 0, -- the old load switched a non-empty queue on
				-- the old file's window histories only line up with its windows when they're as many
				#histories == #old.windows and visits(histories[n]) or {},
			})
		end
	end

	local closed = {}
	for _, value in ipairs(old.closed or {}) do
		local hash = resolve(value, true)
		if hash then
			table.insert(closed, hash)
		end
	end
	for value, content in pairs(old.noname_content or {}) do
		local hash = resolve(value, true)
		if hash then
			texts[hash] = {
				lines = vim.tbl_map(function(line) return xor_decipher(line, cwd) end, content.lines or {}),
				filetype = content.filetype,
				cursor = content.cursor,
			}
		end
	end

	return {
		paths = paths,
		outsiders = {},
		buffers = { global = visits((old.buffers or {}).global) },
		windows = windows,
		closed = closed,
	}, texts, dropped
end

local resession_dir = vim.fn.stdpath("data") .. "/" .. options.resession_dir .. "/"
if vim.fn.isdirectory(resession_dir) == 0 then
	io.stdout:write("no resession sessions in " .. resession_dir .. "\n")
	os.exit(1)
end

local report = { converted = 0, already = 0, conflict = 0, no_file = 0, unnamed = 0, dropped = 0, unreadable = 0, failed = 0 }
local used = {}
for _, entry in ipairs(vim.fn.readdir(resession_dir)) do
	local stem = entry:match("^(.+)%.json$")
	local session = stem and read_json(resession_dir .. entry)
	if session and session.global then
		local directory = session.tab_scoped and session.tabs and session.tabs[1] and session.tabs[1].cwd
			or session.global.cwd
		-- the name resession was given: its file name, with "/" and ":" made "_"; the cwds it saved are
		-- the candidates
		local name
		for _, candidate in ipairs({ session.global.cwd, directory }) do
			if candidate and (candidate:gsub("/", "_"):gsub(":", "_")) == stem then
				name = candidate
			end
		end
		-- the old wiring named the file after the cwd it was saved from: a tab session's is its tab's
		local old_path, migrated
		for _, cwd in ipairs(session.tab_scoped and { directory } or { session.global.cwd }) do
			local path = options.session_dir .. vim.fn.sha256(cwd .. "\n"):sub(1, 32) .. ".json"
			if old_path == nil and vim.fn.filereadable(path) == 1 then
				old_path = { path = path, cwd = cwd }
			elseif vim.fn.filereadable(path .. ".migrated") == 1 then
				migrated = true
			end
		end
		if old_path == nil then
			if migrated then
				report.already = report.already + 1
			else
				report.no_file = report.no_file + 1
			end
		elseif name == nil then
			report.unnamed = report.unnamed + 1
			io.stdout:write("can't tell the session name of " .. entry .. "; left as it is\n")
		elseif storage.session_exists(directory, name) and not options.replace then
			-- a session saved on the encrypted format before the script ran: not a conversion
			report.conflict = report.conflict + 1
			used[old_path.path] = true
			io.stdout:write(entry .. " has a file in the new format already, saved before this script ran; --replace converts over it\n")
		else
			local old = read_json(old_path.path)
			if old then
				local known = {}
				for _, buf in ipairs(session.buffers or {}) do
					if buf.name and buf.name ~= "" then
						known[filehash(buf.name)] = buf.name
					end
				end
				local data, texts, dropped = convert(old, old_path.cwd, known)
				data.scope = session.tab_scoped and "tab" or "editor"
				report.dropped = report.dropped + dropped
				local ok, err = true, nil
				if not options.dry_run then
					-- over a fresh file with --replace too: the commit sweeps that file's own texts, and a write
					-- that fails leaves it as it was
					ok, err = pcall(storage.write_session, directory, name, data, texts)
					if ok then
						-- kept under a new name, the script's record of what it has converted
						local renamed, why = os.rename(old_path.path, old_path.path .. ".migrated")
						if not renamed then
							io.stdout:write(entry .. "'s old file couldn't be marked converted (" .. tostring(why) .. ")\n")
						end
					end
				end
				if ok then
					report.converted = report.converted + 1
				else
					report.failed = report.failed + 1
					io.stdout:write(entry .. "'s new file couldn't be written (" .. tostring(err) .. "); its old file is left as it is\n")
				end
				used[old_path.path] = true
			else
				report.unreadable = report.unreadable + 1
				used[old_path.path] = true
				io.stdout:write(entry .. "'s old cavediver file can't be read; left as it is\n")
			end
		end
	end
end

local leftover = 0
for _, entry in ipairs(vim.fn.isdirectory(options.session_dir) == 1 and vim.fn.readdir(options.session_dir) or {}) do
	if entry:match("^%x+%.json$") and not used[options.session_dir .. entry] then
		leftover = leftover + 1
	end
end

io.stdout:write(string.format(
	"%s %d session(s); %d already converted; %d with a file in the new format already (--replace converts over them); %d with no cavediver file; %d with a name that can't be told; %d old file(s) no resession session points to; %d reference(s) with no known path dropped; %d old file(s) that can't be read; %d that couldn't be written\n",
	options.dry_run and "would convert" or "converted",
	report.converted, report.already, report.conflict, report.no_file, report.unnamed, leftover, report.dropped,
	report.unreadable, report.failed
))
