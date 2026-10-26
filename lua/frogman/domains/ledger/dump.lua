---Ledger domain dumps for the failures that shouldn't happen.
---
---When something that shouldn't happen fires, this module writes the steps that led there to
---a file under stdpath("state")/cavediver/ and shows them in a window. The file is sealed as a
---session's is, since it's usage data, so it holds things as they are (files by their hashes
---and paths, lists by their sessions, windows by number and id).

local data = require('frogman.domains.ledger.data')

local M = {}

---Steps the ring keeps between two snapshots (the last two snapshots are kept, so a dump
---starts 50 to 100 steps back)
---@type integer
local EVERY = 50

---Steps the ring kept since the last snapshot (a timer's tick that did nothing isn't kept, so
---an idle editor doesn't push the steps worth seeing out of the dump)
---@type integer
local kept_since = 0

---Snapshots kept for the dumps, the last two at most, oldest first
---@type { seq: integer, snapshot: table }[]
local checkpoints = {}

---Failures already dumped, by key (one dump each)
---@type table<string, boolean>
local dumped = {}

---Messages `M.never()` has dumped, so a hook failure carrying one isn't dumped again
---@type table<string, boolean>
local nevers = {}

---Last number this editor put in a dump's name (a name already on disk is skipped)
---@type integer
local count = 0

---The salt this editor's dumps are sealed with, made with its first dump
---@type string|nil
local salt

---Check if dumps are turned on.
---
---Reads `ledger.dump` from the config. Anything but false counts as on.
---
---@return boolean enabled True if a failure gets dumped
local function enabled()
	return (require('frogman.configs').ledger or {}).dump ~= false
end

-- what fired during a replay, which writes no dump of its own: it reports them instead
local replay_fired = {}

---Get what fired during a replay, and start the list again.
---
---@return string[] fired What fired, as a dump's heading would name it
function M.replay_fired()
	local fired = replay_fired
	replay_fired = {}
	return fired
end

---Take a snapshot of the state a replay starts from.
---
---Copies the triquetra and history of every valid window, the global history, every list's
---closed files, the missing tags, the machines' states, the cycling window and the history
---view. Files are kept by hash, as the dump writes them.
---
---@return table snapshot The state as it is now
local function snapshot()
	local history = require('frogman.domains.history')
	local window = require('frogman.domains.window')
	local hdata = history.data
	local windows = {}
	for winid, t in pairs(window.data.crux) do
		if vim.api.nvim_win_is_valid(winid) then
			table.insert(windows, {
				win = winid,
				number = vim.api.nvim_win_get_number(winid),
				tab = vim.api.nvim_tabpage_get_number(vim.api.nvim_win_get_tabpage(winid)),
				shows = history.get_hash_from_buffer(vim.api.nvim_win_get_buf(winid)),
				c = t.current_slot, s = t.secondary_slot, t = t.ternary_slot,
				p = vim.deepcopy(t.primary_buffer or {}), on = t.primary_enabled == true,
				dtm = vim.deepcopy(t.displacement_ternary_map or {}), dsm = vim.deepcopy(t.displacement_secondary_map or {}),
				history = vim.deepcopy(hdata.crux_internals.window[winid] or {}),
			})
		end
	end
	local lists = {}
	for _, pool in pairs(history.routines.pools()) do
		table.insert(lists, { id = pool.id, name = pool.name, directory = pool.directory, closed = vim.deepcopy(pool.closed),
			times = vim.deepcopy(pool.times or {}) })
	end
	return {
		windows = windows,
		global = vim.deepcopy(hdata.crux_internals.global or {}),
		history_index = hdata.history_index,
		lists = lists,
		missing = vim.deepcopy(hdata.missing or {}),
		navigation = require('frogman.domains.navigation').sm:state(),
		history_state = history.sm:state(),
		cycle = require('frogman.domains.navigation').data.cycling_window,
		cycle_number = (function(w) return w and vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_number(w) or nil end)(
			require('frogman.domains.navigation').data.cycling_window),
		history_view = require('frogman.configs').bufferline.history_view,
		-- where a split puts its new window, which numbers the windows after it
		splitright = vim.o.splitright,
		splitbelow = vim.o.splitbelow,
	}
end

---Record a step's start for the snapshots.
---
---Takes the first snapshot at the first step, then another once the ring has kept 50 steps
---since the last one. The last two are kept, so a dump starts 50 to 100 steps back. Does
---nothing while dumps are off.
---
---@param step CavediverLedgerStep The step that just began
---@return nil
function M.began(step)
	if not enabled() then
		return
	end
	-- under half the ring when it's shorter, so the older snapshot's steps are still in the ring
	local ring = (require('frogman.configs').ledger or {}).ring or 1000
	local every = math.max(1, math.min(EVERY, math.floor((ring - 1) / 2)))
	if #checkpoints == 0 or kept_since >= every then
		local ok, snap = pcall(snapshot)
		if ok then
			kept_since = 0
			table.insert(checkpoints, { seq = step.seq, snapshot = snap })
			while #checkpoints > 2 do
				table.remove(checkpoints, 1)
			end
		end
	end
end

---Count a step the ring kept, for the snapshots.
---
---@return nil
function M.kept()
	kept_since = kept_since + 1
end

---Find every triquetra that breaks the slot rules.
---
---Checks each valid window for a file in two of its slots (I1), and for a note a restore would
---read that names the buffer already in that slot (I23).
---
---@return table<string, table> breaks Each break by its key, with its rule, window and what broke
function M.breaks()
	local window = require('frogman.domains.window')
	local found = {}
	for winid, t in pairs(window.data.crux) do
		if vim.api.nvim_win_is_valid(winid) then
			local c, s, r = t.current_slot, t.secondary_slot, t.ternary_slot
			if (c and (c == s or c == r)) or (s and s == r) then
				found["I1:" .. winid] = { rule = "I1", win = winid, what = "a file is in two of its slots" }
			end
			for _, m in ipairs({ { "dtm", r, "ternary" }, { "dsm", s, "secondary" } }) do
				local map = t[m[1] == "dtm" and "displacement_ternary_map" or "displacement_secondary_map"] or {}
				local swap = c and map[c .. "-swap"]
				local note = (swap ~= nil and swap ~= m[2]) and swap or (c and map[c])
				if note ~= nil and note == m[2] then
					found["I23:" .. winid .. ":" .. m[1] .. ":" .. c] = { rule = "I23", win = winid, file = c,
						what = "the current file's " .. m[3] .. " note names the " .. m[3] }
				end
			end
		end
	end
	return found
end

---Compose a dump's text.
---
---Takes the steps from the older snapshot up to the step the failure fired in. Returns the
---heading, with the settle work still pending and every file the dump names, then one row per
---step, and the replay part as JSON. The file is sealed, so everything is written as it is
---(files by hash and path, lists by their sessions, windows by number and id).
---
---@param what string What fired, in words
---@param failing CavediverLedgerStep|nil The step it fired in
---@return string[] rows, string replay
local function compose(what, failing)
	local history = require('frogman.domains.history')
	local ledger = require('frogman.domains.ledger.routines')
	local files, seen = {}, {}
	-- Each file the dump names, listed once with its path
	local function file(hash)
		if hash == nil or hash == vim.NIL then
			return nil
		end
		hash = tostring(hash)
		local base = hash:gsub("%-swap$", "")
		if not seen[base] then
			seen[base] = true
			local path = history.data.hash_filepath_registry.filepaths[base]
			table.insert(files, { hash = base, path = path,
				exists = path ~= nil and not path:match("^NONAME_") and vim.fn.filereadable(path) == 1 })
		end
		return hash
	end
	local function number(winid)
		return winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_number(winid) or nil
	end
	local function tab_number(winid)
		return winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_tabpage_get_number(vim.api.nvim_win_get_tabpage(winid)) or nil
	end
	local function map(m)
		local out = {}
		for k, v in pairs(m or {}) do
			out[file(k)] = file(v)
		end
		return out
	end
	local function slots(r)
		return r and { c = file(r.c), s = file(r.s), t = file(r.t), p = vim.tbl_map(file, r.p or {}), on = r.on,
			dtm = map(r.dtm), dsm = map(r.dsm), shows = file(r.shows) }
	end
	local function notes(r)
		if not r or not r.c then
			return ""
		end
		local out = {}
		for _, m in ipairs({ { "dtm", r.dtm }, { "dsm", r.dsm } }) do
			local parts = {}
			for _, key in ipairs({ r.c, r.c .. "-swap" }) do
				local v = (m[2] or {})[key]
				if v then
					table.insert(parts, ledger.slot_name(r.c) .. (key:match("%-swap$") and "-swap" or "") .. ">" .. ledger.slot_name(v))
				end
			end
			if #parts > 0 then
				table.insert(out, m[1] .. "{" .. table.concat(parts, " ") .. "}")
			end
		end
		return table.concat(out, " ")
	end

	-- The steps since the older snapshot, and the one the failure fired in
	local from = checkpoints[1]
	local steps = {}
	for _, step in ipairs(data.ring) do
		if not from or step.seq >= from.seq then
			table.insert(steps, step)
		end
	end
	-- the failing step once: a step closed already may be in the ring, with steps kept after it
	if failing and not vim.tbl_contains(steps, failing) then
		table.insert(steps, failing)
	end

	local rows = {}
	local replay_steps = {}
	for _, step in ipairs(steps) do
		-- the failing step as the failure found it: as it closed, or as it stands when still open
		local after = step == failing and (step.closed and step.row_after or ledger.row_of(step.win, step.names)) or step.row_after
		local n = step.win_nr or number(step.win)
		table.insert(rows, string.format("%s  %-7s %-16s %-6s %s → %s  %s%s", os.date("%H:%M:%S", math.floor(step.time)),
			step.cause, step.trigger or "", n and ("win " .. n) or "win -", ledger.draw_row(step.row_before), ledger.draw_row(after), notes(after),
			step == failing and "   ← fired here" or ""))
		table.insert(replay_steps, {
			seq = step.seq, cause = step.cause, trigger = step.trigger, cut = step.cut, window = n, winid = step.win,
			tab = step.tab_nr or tab_number(step.win),
			before = slots(step.row_before), after = slots(after), events = step.events or {},
		})
	end

	local snap = from and from.snapshot
	local replay = { version = 1, fired = what, steps = replay_steps }
	if snap then
		local windows = {}
		for _, w in ipairs(snap.windows) do
			local history_ = {}
			for k, v in pairs(w.history) do history_[file(k)] = v end
			table.insert(windows, { window = w.number or number(w.win), winid = w.win, tab = w.tab or tab_number(w.win),
				shows = file(w.shows), c = file(w.c), s = file(w.s),
				t = file(w.t), p = vim.tbl_map(file, w.p), on = w.on, dtm = map(w.dtm), dsm = map(w.dsm), history = history_ })
		end
		local global, missing, lists = {}, {}, {}
		for k, v in pairs(snap.global) do global[file(k)] = v end
		for k, v in pairs(snap.missing) do missing[file(k)] = v end
		for _, l in ipairs(snap.lists) do
			local times = {}
			for k, v in pairs(l.times) do times[file(k)] = v end
			table.insert(lists, { name = l.id == "" and "editor" or l.name, directory = l.directory,
				closed = vim.tbl_map(file, l.closed), times = times })
		end
		replay.snapshot = { windows = windows, global = global, history_index = snap.history_index, lists = lists,
			missing = missing, navigation = snap.navigation, history = snap.history_state, cycle = snap.cycle_number or number(snap.cycle),
			cycle_winid = snap.cycle, history_view = snap.history_view, splitright = snap.splitright, splitbelow = snap.splitbelow }
	end
	local head = {
		"cavediver: something that shouldn't happen did",
		what,
		os.date("%Y-%m-%d %H:%M:%S"),
	}
	-- The settle work still queued: what cavediver hadn't taken in yet when it fired
	local pending = require('frogman.settle').pending()
	replay.pending = pending
	if #pending > 0 then
		table.insert(head, "pending: " .. table.concat(pending, " · "))
	end
	vim.list_extend(head, { "", "files:" })
	replay.files = {}
	for _, f in ipairs(files) do
		table.insert(head, "  " .. f.hash .. "  " .. (f.path or "?"))
		replay.files[f.hash] = { path = f.path, exists = f.exists }
	end
	table.insert(head, "")
	return vim.list_extend(head, rows), vim.json.encode(replay)
end

---Open the dump's window once the editor settles.
---
---The window is a float on a scratch buffer, which the ledger records no step about. It isn't
---entered when a dump fires, and is when `:CavediverDump` opens one. `q` closes it.
---
---@param name string The dump's name
---@param lines string[] The rows to show
---@param enter boolean|nil True to enter the window
---@return nil
local function show(name, lines, enter)
	vim.schedule(function()
		local buf = vim.api.nvim_create_buf(false, true) -- Unlisted scratch buffer, so cavediver doesn't track it
		vim.b[buf].cavediver_dump = true -- Marked first, so the ledger begins no step about it
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].swapfile = false
		pcall(vim.api.nvim_buf_set_name, buf, "cavediver://" .. name)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
		local width = math.max(20, math.min(vim.o.columns - 4, math.floor(vim.o.columns * 0.8)))
		local height = math.max(3, math.min(#lines, math.floor(vim.o.lines * 0.4)))
		local win = vim.api.nvim_open_win(buf, enter == true, {
			relative = "editor", width = width, height = height, style = "minimal", border = "rounded",
			row = math.max(0, vim.o.lines - height - 4), col = math.max(0, vim.o.columns - width - 2),
			title = " cavediver: something that shouldn't happen did ", title_pos = "center",
		})
		vim.wo[win].wrap = false
		vim.keymap.set("n", "q", function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end, { buffer = buf, nowait = true, desc = "Close the dump" })
	end)
end

---Write a sealed file, the way a session's is written.
---
---Seals the text with the key stretched from the global working directory and this editor's
---salt, made with its first dump, and writes it atomically. Its directory is made first when
---it's missing.
---
---@param path string Where the dump goes
---@param text string The dump's text
---@return nil
local function write(path, text)
	local crypto = require('frogman.domains.storage.crypto')
	local dir = vim.fs.dirname(path)
	if not vim.uv.fs_stat(dir) then
		vim.fn.mkdir(dir, "p", tonumber("700", 8))
	end
	salt = salt or crypto.random_bytes(crypto.salt_length)
	-- sealed as a session's file is, the word `dump` under the seal too, so it can't pass for one
	local storage = require('frogman.domains.storage.routines')
	storage.seal_file(path, storage.key_for(vim.fn.getcwd(-1, -1), salt), salt, text, "dump")
end

---Write a dump, once per failure.
---
---Writes the sealed file right away, then shows the rows in a window and says where the file
---is once the editor settles. When the file can't be written, the window still shows the rows.
---The step it fired in is marked as dumped. A failure already dumped is skipped, and so is
---every failure while dumps are off.
---
---@param key string What makes this failure distinct
---@param what string What fired, in words
---@param failing CavediverLedgerStep|nil The step it fired in
---@return nil
function M.fire(key, what, failing)
	if not enabled() or dumped[key] then
		return
	end
	dumped[key] = true
	if failing then
		failing.dumped = true
	end
	if require('frogman.domains.storage').data.replayed then
		table.insert(replay_fired, what) -- a replay reports what it reproduces, and writes no dump
		return
	end
	local made, text = pcall(function()
		local rows, replay = compose(what, failing)
		return table.concat(rows, "\n") .. "\n\nreplay:\n" .. replay .. "\n"
	end)
	if not made then
		vim.schedule(function()
			vim.notify("cavediver: a dump couldn't be made (" .. tostring(text) .. ").", vim.log.levels.WARN)
		end)
		return
	end
	-- Another editor may have written a dump this second, so the number goes past its files
	local dir = vim.fn.stdpath("state") .. "/cavediver"
	local name, path
	repeat
		count = count + 1
		name = "dump-" .. os.date("%Y%m%d-%H%M%S") .. "-" .. count
		path = dir .. "/" .. name .. ".txt"
	until not vim.uv.fs_stat(path)
	local written, err = pcall(write, path, text)
	local lines = vim.split(text, "\n", { plain = true })
	local cut = #lines
	for i, line in ipairs(lines) do
		if line == "replay:" then
			cut = i - 2
			break
		end
	end
	show(name, vim.list_slice(lines, 1, cut))
	local said = what:match("[^\n]*")
	vim.schedule(function()
		if written then
			vim.notify("cavediver: something that shouldn't happen did (" .. said .. "); its last steps are in " .. path .. ".",
				vim.log.levels.WARN)
		else
			vim.notify("cavediver: something that shouldn't happen did (" .. said .. "); its last steps are in the window, "
				.. "since the file couldn't be written (" .. tostring(err) .. ").", vim.log.levels.WARN)
		end
	end)
end

---Read a dump back, decrypted.
---
---Opens only from the directory the dump was written in, since its key is stretched from it.
---`:CavediverDump` and the replay both read dumps through here.
---
---@param path string The dump's file
---@return string|nil text The dump's text, or nil when it can't be read here
---@return string|nil problem "missing", "not a dump" or "not here" (another directory, or edited)
function M.read(path)
	local file = io.open(path, "rb")
	if not file then
		return nil, "missing"
	end
	local bytes = file:read("*a")
	file:close()
	-- a directory opens, and reads as nothing
	if type(bytes) ~= "string" then
		return nil, "not a dump"
	end
	local opened, text, _, problem = pcall(require('frogman.domains.storage.routines').open_sealed, bytes, vim.fn.getcwd(-1, -1), "dump")
	if opened and problem == "not sealed" then
		return nil, "not a dump"
	elseif not opened or text == nil then
		return nil, "not here"
	end
	return text
end

---Open a dump in a window to read it.
---
---Shows it decrypted, with its replay part, and enters the window. When it can't, it says why
---(no such file, not a dump, or a dump that was edited or written from another directory).
---
---@param path string The dump's file, as typed
---@return nil
function M.open(path)
	path = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
	local text, problem = M.read(path)
	if not text then
		local why = problem == "missing" and "there's no such file"
			or problem == "not a dump" and "it isn't a dump"
			or "it doesn't open here: a dump opens only from the directory it was written in, unedited"
		vim.notify("cavediver: " .. vim.fn.fnamemodify(path, ":t") .. " can't be opened, since " .. why .. ".", vim.log.levels.WARN)
		return
	end
	show(vim.fn.fnamemodify(path, ":t:r"), vim.split(text, "\n", { plain = true }), true)
end

---Dump a message that `ledger.never()` is about to raise.
---
---The step it fired in is a running call's own, such as a tick's, or else the open one. The
---message is marked too, so the hook failure carrying it isn't dumped a second time.
---
---@param message string The message being raised
---@return nil
function M.never(message)
	nevers[message] = true
	M.fire("never:" .. message, message, data.scopes[#data.scopes] or data.open)
end

---Dump a hook that failed without being critical.
---
---The engine calls this through its `on_failure`. Dumps once per hook and error message,
---unless the error carries a message `ledger.never()` already dumped.
---
---@param name string The hook's name
---@param err string The hook's error, with its traceback
---@return nil
function M.hook_failed(name, err)
	local text = tostring(err)
	for message, _ in pairs(nevers) do
		if text:find(message, 1, true) then
			return
		end
	end
	local first = text:match("[^\n]*"):gsub("^[^:]*:%d+: ", "")
	M.fire("hook:" .. name .. ":" .. first, "Hook '" .. name .. "' failed: " .. text, data.scopes[#data.scopes] or data.open)
end

---Dump a key's error, a plain Lua error raised inside its job.
---
---`settle.now` calls this at the error's site. A Vim error, an `E` number a command or the
---API gave, which the editor's state can reach, isn't dumped, and neither is a message
---`ledger.never()` dumped already. Dumps once per distinct error.
---
---@param err any The error, as raised
---@param traceback string The traceback from where it was raised
---@return nil
function M.key_failed(err, traceback)
	local text = tostring(err)
	if text:match("Vim[^:]*:E%d+") or text:match("^E%d+:") then
		return
	end
	for message, _ in pairs(nevers) do
		if text:find(message, 1, true) then
			return
		end
	end
	local first = text:match("[^\n]*"):gsub("^[^:]*:%d+: ", "")
	M.fire("key:" .. first, "A key failed: " .. text .. "\n" .. traceback, data.scopes[#data.scopes] or data.open)
end

---Check the slot rules once a step has been held open its full time.
---
---Dumps a break only when it's still there after the editor settles, so a break the
---next event repairs isn't dumped. A step that dumped already marks the breaks it left as
---dumped, since its own dump shows them.
---
---@param step CavediverLedgerStep The step that closed
---@return nil
function M.closed(step)
	if not enabled() then
		return
	end
	local first = M.breaks()
	if step.dumped then
		for key, _ in pairs(first) do
			dumped["rule:" .. key] = true
		end
		return
	end
	if next(first) == nil then
		return
	end
	vim.schedule(function()
		local still = M.breaks()
		for key, b in pairs(first) do
			if still[key] and not dumped["rule:" .. key] then
				local n = vim.api.nvim_win_is_valid(b.win) and vim.api.nvim_win_get_number(b.win) or "?"
				M.fire("rule:" .. key, b.rule .. " broke in win " .. n .. ": " .. b.what, step)
			end
		end
	end)
end

return M
