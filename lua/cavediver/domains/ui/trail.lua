---The trail's view, :CavediverTrail: a day's page of the ledger's steps and moves, in the trail's
---language. Every line is drawn from the records, and every key reads what a line stands for from
---the map the drawing keeps, never the text.

local M = {}

local ns = vim.api.nvim_create_namespace("cavediver_trail")

-- The view open now: { buf, win, from, days, day, open, lines }
local view = nil

-- A move kind's family, which gives its colour.
local FAMILY = {
	closed = "Closed", reopened = "Reopened", forgotten = "Forgot", note_dropped = "Note", rewritten = "Note",
	gone = "Gone", back = "Back", repair = "Repair", repointed = "Slot", landed = "Slot", undone = "Slot",
	dropped = "Slot", cleared = "Slot", cancelled = "Cycle", loaded = "Session", fresh = "Session", saved = "Session",
	refreshed = "Session", tab_closed = "Session", copied = "Rename", moved = "Rename", detached = "List",
	detached_left = "List",
}

-- How a count of moves of one kind reads, folded.
local PLURAL = {
	closed = "closed", reopened = "reopened", forgotten = "forgotten", note_dropped = "notes dropped",
	rewritten = "notes rewritten", gone = "gone from disk", back = "back on disk", repair = "repairs",
	repointed = "repointed", landed = "landed", undone = "undone", dropped = "dropped", cleared = "cleared",
	cancelled = "cancelled", copied = "copied", moved = "moved",
}

-- The tally: each family, in order, with the kind whose glyph stands for it.
local TALLY = {
	{ "Closed", "closed" }, { "Reopened", "reopened" }, { "Gone", "gone" }, { "Back", "back" }, { "Repair", "repair" },
	{ "Slot", "repointed" }, { "Note", "rewritten" }, { "Forgot", "forgotten" }, { "Cycle", "cancelled" },
	{ "Session", "loaded" }, { "Rename", "moved" }, { "List", "detached" },
}

---@param segs table[] { text, group } pieces
---@return integer
local function width(segs)
	local w = 0
	for _, seg in ipairs(segs) do
		w = w + vim.api.nvim_strwidth(seg[1])
	end
	return w
end

---A file's name in a row: its basename without the extension.
---@param names table<string, string>
---@param filehash string|nil
---@return string
local function stem(names, filehash)
	if filehash == nil then
		return "-"
	end
	local name = names[filehash] or "?"
	return name:match("^%[") and name or vim.fn.fnamemodify(name, ":r")
end

---A row, `⦉t⦊ [c] ⟦s⟧`, as coloured pieces.
local function row_segs(glyphs, names, row)
	row = row or {}
	return {
		{ glyphs.row_t[1] .. stem(names, row.t) .. glyphs.row_t[2], "CavediverTrailRowT" }, { " ", nil },
		{ glyphs.row_c[1] .. stem(names, row.c) .. glyphs.row_c[2], "CavediverTrailRowC" }, { " ", nil },
		{ glyphs.row_s[1] .. stem(names, row.s) .. glyphs.row_s[2], "CavediverTrailRowS" },
	}
end

---Lists, `≡editor, ≡t`.
local function lists_text(glyphs, lists)
	local out = {}
	for _, list in ipairs(lists or {}) do
		table.insert(out, glyphs.list .. list)
	end
	return table.concat(out, ", ")
end

---What a move says, from its own words or its fields.
---@return string
local function move_words(glyphs, names, move)
	local words = move.words
	if move.kind == "closed" and not words then
		words = "closed"
	elseif move.kind == "reopened" and not words then
		words = "reopened" .. ((move.lists and #move.lists > 0) and (glyphs.dot .. "off ") or "")
		return words .. lists_text(glyphs, move.lists)
	elseif move.note then
		local by = ({ guard = "Q6's guard: ", navigation = "navigation's check: ", ["no path"] = "no path: " })[move.by] or "stale "
		local function n(h) return stem(names, h) end
		local owner = n(move.subject)
		words = by .. move.note.map .. " note " .. (move.note.after and "rewritten" or "dropped") .. "   " ..
			owner .. ">" .. n(move.note.before) .. glyphs.arrow .. owner .. ">" .. (move.note.after and n(move.note.after) or "-")
	elseif move.kind == "landed" and move.from then
		words = "landed" .. (move.from == "empty" and " on an empty buffer" or (", from the " .. move.from))
	end
	words = words or move.kind:gsub("_", " ")
	if move.notes and move.notes > 0 and move.kind == "forgotten" then
		words = words .. glyphs.dot .. move.notes .. (move.notes == 1 and " note" or " notes") .. " dropped"
	end
	if move.lists and #move.lists > 0 then
		words = words .. glyphs.dot .. lists_text(glyphs, move.lists)
	end
	return words
end

---Words with each `≡list` and `⎇tag` picked out.
local function word_segs(glyphs, text, group)
	local out = {}
	local i = 1
	while i <= #text do
		local s, e, mark
		for _, m in ipairs({ glyphs.list, glyphs.tag }) do
			local ms, me = text:find(vim.pesc(m) .. "[^%s,]+", i)
			if ms and (s == nil or ms < s) then
				s, e, mark = ms, me, m
			end
		end
		if not s then
			table.insert(out, { text:sub(i), group })
			break
		end
		if s > i then
			table.insert(out, { text:sub(i, s - 1), group })
		end
		table.insert(out, { text:sub(s, e), mark == glyphs.list and "CavediverTrailList" or "CavediverTrailTag" })
		i = e + 1
	end
	return out
end

---A day's depth: how many calendar days before today.
---@param day string `YYYY-MM-DD`
---@return integer
local function depth_of(day)
	local y, m, d = day:match("^(%d+)-(%d+)-(%d+)$")
	local then_ = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
	local now = os.date("*t")
	local today = os.time({ year = now.year, month = now.month, day = now.day, hour = 12 })
	return math.floor((today - then_) / 86400 + 0.5)
end

---The fill's glyph and group for a depth.
local function fill_of(glyphs, depth, shade)
	if not shade then
		return glyphs.rule, "CavediverTrailGutter"
	elseif depth <= 0 then
		return glyphs.shade0, "CavediverTrailWave0"
	elseif depth <= 7 then
		return glyphs.shade1, "CavediverTrailWave1"
	elseif depth <= 30 then
		return glyphs.shade2, "CavediverTrailWave2"
	end
	return glyphs.shade3, "CavediverTrailWave3"
end

---The days the gauge draws: up to 15 around the one shown, newest on the right.
---@return integer first
---@return integer last
local function gauge_window(shown, days)
	local first = math.max(1, math.min(shown - 7, days - 14))
	return first, math.min(days, first + 14)
end

---The gauge: a bar per day it draws, its height the day's moves.
---@param counts table<integer, integer> The moves of each day it draws, by the day's index
local function gauge_segs(glyphs, counts, shown, first, last)
	local bars = vim.fn.split(glyphs.bars, "\\zs")
	local most = 1
	for i = first, last do
		most = math.max(most, counts[i])
	end
	local out = {}
	for i = first, last do
		local bar = bars[math.max(1, math.ceil(counts[i] / most * #bars))]
		if i == shown then
			table.insert(out, { glyphs.now_left .. bar .. glyphs.now_right, "CavediverTrailGaugeNow" })
		else
			table.insert(out, { bar, "CavediverTrailGauge" })
		end
	end
	return out
end

---The day's moves, and its tally by kind.
local function count_moves(steps)
	local total, kinds = 0, {}
	for _, step in ipairs(steps) do
		for _, move in ipairs(step.moves or {}) do
			total = total + 1
			kinds[move.kind] = (kinds[move.kind] or 0) + 1
		end
	end
	return total, kinds
end

---The header line, the dive: the fill shaded by depth, the title, the date, the depth, the moves, the
---tally and the gauge, the keys to the older and the newer day at the sides. A narrow window drops the
---tally first, then the gauge.
local function header(glyphs, keys, winwidth)
	local configured = (require('cavediver.configs').trail or {}).header or {}
	local day = view.days[view.day]
	local depth = day and depth_of(day) or 0
	local steps = view.steps
	local total, kinds = count_moves(steps)
	local ch, group = fill_of(glyphs, depth, configured.shade ~= false)
	local date = day and os.date("%a %d %b %Y", os.time({ year = tonumber(day:sub(1, 4)), month = tonumber(day:sub(6, 7)),
		day = tonumber(day:sub(9, 10)), hour = 12 })) or os.date("%a %d %b %Y")
	local mid = {
		{ glyphs.title, "CavediverTrailTitle" }, { " ", nil }, { date, "CavediverTrailDate" },
		{ glyphs.dot, "CavediverTrailCount" },
		{ depth == 0 and "today" or (depth .. (depth == 1 and " day down" or " days down")), "CavediverTrailDepth" },
		{ glyphs.dot, "CavediverTrailCount" }, { total .. (total == 1 and " move" or " moves"), "CavediverTrailCount" },
	}
	local tally = {}
	if configured.tally ~= false then
		local families = {}
		for kind, n in pairs(kinds) do
			local family = FAMILY[kind] or "Words"
			families[family] = (families[family] or 0) + n
		end
		for _, entry in ipairs(TALLY) do
			if families[entry[1]] then
				table.insert(tally, { "  ", nil })
				table.insert(tally, { (glyphs[entry[2]] or "?") .. families[entry[1]], "CavediverTrail" .. entry[1] })
			end
		end
	end
	local gauge = {}
	if configured.gauge ~= false and #view.days > 0 then
		-- only the days the gauge draws are counted, each page read once while the view is open
		local first, last = gauge_window(view.day, #view.days)
		local counts = {}
		for i = first, last do
			counts[i] = i == view.day and total or count_moves(view.reader.steps(view.days[i]))
		end
		gauge = { { "  " .. ch .. " ", group } }
		vim.list_extend(gauge, gauge_segs(glyphs, counts, view.day, first, last))
	end
	local left_key = keys.previous_section or "H"
	local right_key = keys.next_section or "L"
	local l = { { glyphs.older .. " " .. left_key, view.day > 1 and "CavediverTrailKeyOn" or "CavediverTrailKeyOff" }, { " ", nil } }
	local r = { { " ", nil }, { right_key .. " " .. glyphs.newer, view.day < #view.days and "CavediverTrailKeyOn" or "CavediverTrailKeyOff" } }
	local function fits(segs)
		return width(l) + width(r) + width(segs) + 2 + 8 <= winwidth
	end
	local chosen = vim.list_extend(vim.list_extend(vim.deepcopy(mid), tally), gauge)
	if not fits(chosen) then
		chosen = vim.list_extend(vim.deepcopy(mid), gauge)
		if not fits(chosen) then
			chosen = mid
		end
	end
	local free = winwidth - width(l) - width(r) - width(chosen) - 2
	local a = math.max(2, math.floor(free / 2))
	local b = math.max(2, free - a)
	local line = vim.deepcopy(l)
	table.insert(line, { string.rep(ch, a), group })
	table.insert(line, { " ", nil })
	vim.list_extend(line, chosen)
	table.insert(line, { " ", nil })
	table.insert(line, { string.rep(ch, b), group })
	vim.list_extend(line, r)
	return line
end

---The day's lines, each with what it stands for.
local function day_lines(glyphs, winwidth)
	local keys = require('cavediver.configs').keymaps.views or {}
	local lines = { { segs = header(glyphs, keys, winwidth) }, { segs = { { "", nil } } } }
	if #view.steps == 0 then
		table.insert(lines, { segs = { { "no moves", "CavediverTrailDim" } } })
	end
	for _, step in ipairs(view.steps) do
		local names = step.names or {}
		local time = os.date("%H:%M", math.floor(step.time or 0))
		table.insert(lines, { segs = {
			{ time .. " ", "CavediverTrailTime" }, { (glyphs[step.cause] or "?") .. " ", "CavediverTrailCause" },
			{ step.trigger or "", "CavediverTrailTrigger" },
		}, step = step })
		-- more than three of a kind under one step fold to a count
		local of_kind = {}
		for _, move in ipairs(step.moves or {}) do
			of_kind[move.kind] = (of_kind[move.kind] or 0) + 1
		end
		local shown, seen = {}, {}
		for _, move in ipairs(step.moves or {}) do
			if of_kind[move.kind] > 3 then
				if not seen[move.kind] then
					-- a fold is the day's and the step's own, so it doesn't open on another day
					seen[move.kind] = true
					local group, lists, lset = {}, {}, {}
					for _, other in ipairs(step.moves) do
						if other.kind == move.kind then
							table.insert(group, other)
							for _, list in ipairs(other.lists or {}) do
								if not lset[list] then
									lset[list] = true
									table.insert(lists, list)
								end
							end
						end
					end
					table.insert(shown, { fold = group, kind = move.kind, lists = lists })
				end
			else
				table.insert(shown, { move = move })
			end
		end
		for mi, item in ipairs(shown) do
			local last = mi == #shown
			local branch = last and glyphs.last or glyphs.branch
			local stem_ = last and string.rep(" ", vim.api.nvim_strwidth(glyphs.stem)) or glyphs.stem
			local indent = { "        ", nil }
			if item.fold then
				local key = view.days[view.day] .. ":" .. (step.seq or 0) .. ":" .. (step.time or 0) .. ":" .. item.kind
				local open = view.open[key]
				local segs = { indent, { branch, "CavediverTrailGutter" },
					{ (glyphs[item.kind] or "?") .. " ", "CavediverTrail" .. (FAMILY[item.kind] or "Words") },
					{ string.format("%-14s", #item.fold .. " " .. (PLURAL[item.kind] or item.kind)), "CavediverTrailName" } }
				vim.list_extend(segs, word_segs(glyphs, lists_text(glyphs, item.lists), "CavediverTrailWords"))
				local pad = winwidth - width(segs) - 2
				table.insert(segs, { string.rep(" ", math.max(1, pad)), nil })
				table.insert(segs, { open and glyphs.unfolded or glyphs.folded, "CavediverTrailFold" })
				table.insert(lines, { segs = segs, fold = key, step = step })
				if open then
					for _, move in ipairs(item.fold) do
						table.insert(lines, { segs = { indent, { stem_ .. "  ", "CavediverTrailGutter" },
							{ (glyphs[move.kind] or "?") .. " ", "CavediverTrail" .. (move.dim and "Dim" or FAMILY[move.kind] or "Words") },
							{ move.name or "?", move.dim and "CavediverTrailDim" or "CavediverTrailName" } }, move = move, step = step })
					end
				end
			else
				local move = item.move
				local dim = move.dim == true
				local family = dim and "CavediverTrailDim" or ("CavediverTrail" .. (FAMILY[move.kind] or "Words"))
				local segs = { indent, { branch, "CavediverTrailGutter" }, { (glyphs[move.kind] or "?") .. " ", family },
					{ string.format("%-14s", move.name or ""), dim and "CavediverTrailDim" or "CavediverTrailName" } }
				vim.list_extend(segs, word_segs(glyphs, move_words(glyphs, names, move), dim and "CavediverTrailDim" or "CavediverTrailWords"))
				table.insert(lines, { segs = segs, move = move, step = step })
				if move.row then
					local r = { indent, { stem_ .. "  ", "CavediverTrailGutter" } }
					vim.list_extend(r, row_segs(glyphs, names, move.row.before))
					table.insert(r, { glyphs.arrow, "CavediverTrailDim" })
					vim.list_extend(r, row_segs(glyphs, names, move.row.after))
					table.insert(lines, { segs = r, move = move, step = step })
				end
			end
		end
	end
	return lines
end

---Draw the view: its lines, their colours, and the map of what each line stands for.
local function draw()
	if not view or not vim.api.nvim_buf_is_valid(view.buf) then
		return
	end
	local glyphs = require('cavediver.domains.ui.routines').glyphs()
	local winwidth = vim.api.nvim_win_is_valid(view.win) and vim.api.nvim_win_get_width(view.win) or 80
	local day = view.days[view.day]
	view.steps = day and view.reader.steps(day) or {}
	local lines = day_lines(glyphs, winwidth)
	local text = {}
	for _, line in ipairs(lines) do
		local s = ""
		for _, seg in ipairs(line.segs) do
			s = s .. seg[1]
		end
		table.insert(text, s)
	end
	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, text)
	vim.bo[view.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(view.buf, ns, 0, -1)
	for i, line in ipairs(lines) do
		local col = 0
		for _, seg in ipairs(line.segs) do
			if seg[2] and #seg[1] > 0 then
				vim.api.nvim_buf_set_extmark(view.buf, ns, i - 1, col, { end_col = col + #seg[1], hl_group = seg[2] })
			end
			col = col + #seg[1]
		end
	end
	view.lines = lines
end

---What the line under the cursor stands for.
local function at_cursor()
	if not view or not vim.api.nvim_win_is_valid(view.win) then
		return nil
	end
	return view.lines and view.lines[vim.api.nvim_win_get_cursor(view.win)[1]]
end

---Leave the view.
function M.leave()
	if view and vim.api.nvim_win_is_valid(view.win) then
		local from = view.from
		vim.api.nvim_win_close(view.win, true)
		if from and vim.api.nvim_win_is_valid(from) then
			vim.api.nvim_set_current_win(from)
		end
	end
	view = nil
end

---Go to the older (-1) or the newer (1) day.
---@param step integer
function M.page(step)
	if not view then
		return
	end
	local day = view.day + step
	if day >= 1 and day <= #view.days then
		view.day = day
		draw()
		vim.api.nvim_win_set_cursor(view.win, { 1, 0 })
	end
end

---Open or close the fold under the cursor.
function M.fold()
	local line = at_cursor()
	if line and line.fold then
		view.open[line.fold] = not view.open[line.fold]
		draw()
	end
end

---Open the trail of the tab you're in, on today's page or the newest day with moves.
function M.open()
	local window = require('cavediver.domains.window')
	local from = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_config(from).relative ~= "" and window.data.last_valid_window then
		from = window.data.last_valid_window -- opened from a float: back to the last tracked window
	end
	if view then
		M.leave()
	end
	-- the session's main file read once; a page only when it's shown
	local reader = require('cavediver.domains.storage').routines.trail_reader()
	local days = reader.days()
	local buf = vim.api.nvim_create_buf(false, true) -- unlisted, a scratch: cavediver doesn't track it
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	local size = require('cavediver.configs').trail_popup
	local w = math.abs(size.width) <= 1 and math.floor(vim.o.columns * math.abs(size.width)) or math.min(vim.o.columns, math.floor(math.abs(size.width)))
	local h = math.abs(size.height) <= 1 and math.floor(vim.o.lines * math.abs(size.height)) or math.min(vim.o.lines, math.floor(math.abs(size.height)))
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor", width = w, height = h, style = "minimal", border = "rounded",
		col = math.floor((vim.o.columns - w) / 2), row = math.floor((vim.o.lines - h) / 2),
	})
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	view = { buf = buf, win = win, from = from, reader = reader, days = days, day = math.max(1, #days), open = {} }
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = buf,
		once = true,
		callback = function()
			if view and view.buf == buf then
				view = nil
			end
		end,
	})
	local keys = require('cavediver.configs').keymaps.views or {}
	local function map(lhs, fn, desc)
		if type(lhs) == "string" then
			vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = desc })
		end
	end
	map(keys.leave, M.leave, "Leave the trail")
	map(keys.leave_too, M.leave, "Leave the trail")
	map(keys.previous_section, function() M.page(-1) end, "The older day")
	map(keys.next_section, function() M.page(1) end, "The newer day")
	map(keys.fold, M.fold, "Open or close what's under the cursor")
	vim.bo[buf].filetype = "cavediver-trail"
	draw()
end

return M
