---UI domain trail view for the ledger's steps and moves.
---
---This module draws :CavediverTrail, a day's page of the ledger's steps and moves in the
---trail's language, or a search's results across every page. Every line is drawn from the
---records, and every key reads what a line stands for from the map the drawing keeps, never
---from the text.

local M = {}

local ns = vim.api.nvim_create_namespace("cavediver_trail")

-- The view open now: { buf, win, from, reader, days, day, open, more, mode, query, results, lines }
local view = nil

-- How many of the ring's steps a line opens at a time.
local CHUNK = 20

-- A move kind's family, which gives its colour.
local FAMILY = {
	closed = "Closed", reopened = "Reopened", forgotten = "Forgot", note_dropped = "Note", rewritten = "Note",
	gone = "Gone", back = "Back", repair = "Repair", repointed = "Slot", landed = "Slot", undone = "Slot",
	dropped = "Slot", cleared = "Slot", cancelled = "Cycle", loaded = "Session", fresh = "Session", saved = "Session",
	refreshed = "Session", tab_closed = "Session", copied = "Rename", moved = "Rename", detached = "List",
	detached_left = "List",
}

-- The moves whose subject is a list, which gf shows in the closed lists.
local LIST_KINDS = { detached = true, detached_left = true, tab_closed = true }

-- What a move of a kind leaves its file as, for a search's life line: a copy closes the old name. A
-- move whose result isn't its kind's says so itself (`state`); any other leaves the file as it was.
local STATE_AFTER = { closed = "Closed", copied = "Closed", reopened = "Open", gone = "Gone" }

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

---Get the display width of a line's pieces.
---@param segs table[] The { text, group } pieces
---@return integer width Display width in cells
local function width(segs)
	local w = 0
	for _, seg in ipairs(segs) do
		w = w + vim.api.nvim_strwidth(seg[1])
	end
	return w
end

---Get a file's name as a row shows it, its basename without the extension.
---
---A name in brackets ([No Name]) is kept whole. No file shows as "-", and a file with no name
---as "?".
---
---@param names table<string, string> File hash → basename, as the step keeps them
---@param filehash string|nil The file's hash
---@return string stem The name to show
local function stem(names, filehash)
	if filehash == nil then
		return "-"
	end
	local name = names[filehash] or "?"
	return name:match("^%[") and name or vim.fn.fnamemodify(name, ":r")
end

---Build a row, `⦉t⦊ [c] ⟦s⟧`, as coloured pieces.
local function row_segs(glyphs, names, row)
	row = row or {}
	return {
		{ glyphs.row_t[1] .. stem(names, row.t) .. glyphs.row_t[2], "CavediverTrailRowT" }, { " ", nil },
		{ glyphs.row_c[1] .. stem(names, row.c) .. glyphs.row_c[2], "CavediverTrailRowC" }, { " ", nil },
		{ glyphs.row_s[1] .. stem(names, row.s) .. glyphs.row_s[2], "CavediverTrailRowS" },
	}
end

---Join lists into the trail's text for them, `≡editor, ≡t`.
local function lists_text(glyphs, lists)
	local out = {}
	for _, list in ipairs(lists or {}) do
		table.insert(out, glyphs.list .. list)
	end
	return table.concat(out, ", ")
end

---Get what a move says, from its own words or its fields.
---
---A move without words of its own is told from its kind and fields, such as a note's change or
---where a landing came from. The lists it names come last.
---
---@return string words The move's words, in the trail's language
local function move_words(glyphs, names, move)
	local words = move.words
	if move.kind == "closed" and not words then
		words = "closed"
	elseif move.kind == "reopened" and not words then
		words = "reopened" .. (move.new and (glyphs.dot .. "never written, a new file") or "")
			.. ((move.lists and #move.lists > 0) and (glyphs.dot .. "off ") or "")
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

-- What moves and triggers are recorded with: the unicode set's tag, dot and arrow, and a dash for a
-- step with no trigger, as the pages keep them
local RECORDED = { tag = "⎇", dot = " · ", arrow = " → ", none = "—" }

---Put what a move or a trigger was recorded with in the glyph set in use.
---
---@param glyphs table The glyphs in use
---@param text string|nil What was recorded
---@return string|nil text The same, in the set in use
local function in_set(glyphs, text)
	if type(text) ~= "string" then
		return text
	end
	for name, recorded in pairs(RECORDED) do
		local now = glyphs[name]
		if type(now) == "string" and now ~= recorded then
			text = text:gsub(vim.pesc(recorded), (now:gsub("%%", "%%%%")))
		end
	end
	return text
end

---Split words into coloured pieces, with each `≡list` and `⎇tag` picked out.
---
---A list's piece carries its target, so the keys can act on it.
local function word_segs(glyphs, text, group)
	text = in_set(glyphs, text)
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
		local token = text:sub(s, e)
		if mark == glyphs.list then
			table.insert(out, { token, "CavediverTrailList", target = { kind = "list", value = token:sub(#glyphs.list + 1) } })
		else
			table.insert(out, { token, "CavediverTrailTag" })
		end
		i = e + 1
	end
	return out
end

---Get a day's depth, how many calendar days ago it was.
---@param day string The day, as `YYYY-MM-DD`
---@return integer depth Calendar days ago, 0 for the current day
local function depth_of(day)
	local y, m, d = day:match("^(%d+)-(%d+)-(%d+)$")
	local then_ = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
	local now = os.date("*t")
	local today = os.time({ year = now.year, month = now.month, day = now.day, hour = 12 })
	return math.floor((today - then_) / 86400 + 0.5)
end

---Get the header fill's glyph and highlight group for a depth.
---
---There are four shades, for the current day, up to a week, up to a month, and older. With
---shading off it's the plain rule.
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

---Get the days the gauge draws, up to 15 around the one shown.
---
---They're indices into the view's days, oldest first, so the newest is on the right.
---
---@return integer first The index of the first day drawn
---@return integer last The index of the last day drawn
local function gauge_window(shown, days)
	local first = math.max(1, math.min(shown - 7, days - 14))
	return first, math.min(days, first + 14)
end

---Build the gauge's pieces, a bar per day it draws.
---
---A bar's height is the day's moves against the busiest day drawn, and the day shown is marked.
---
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

---Count a day's moves, in all and by kind.
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

local frame, target_of, earlier_window

---Build the day's header line, the dive.
---
---It holds the fill shaded by the day's depth, the title, the date, the depth, the move count,
---the tally and the gauge, with the keys to the older and the newer day at the sides. A narrow
---window drops the tally first, then the gauge. The config's `trail.header` can turn off the
---shading, the tally and the gauge, and a `trail_header` formatter replaces the whole line.
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
	local formatter = (require('cavediver.configs').formatters or {}).trail_header
	local custom = formatter and formatter({ day = day, date = date, depth = depth, moves = total, kinds = kinds }, glyphs)
	if custom then
		return custom
	end
	local l = { { glyphs.older .. " " .. (keys.previous_section or "H"), view.day > 1 and "CavediverTrailKeyOn" or "CavediverTrailKeyOff" }, { " ", nil } }
	local r = { { " ", nil }, { (keys.next_section or "L") .. " " .. glyphs.newer, view.day < #view.days and "CavediverTrailKeyOn" or "CavediverTrailKeyOff" } }
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
	return frame(l, r, chosen, ch, group, winwidth)
end

---Frame a header's middle with the fill, and the keys at the sides.
---
---The fill takes the room that's left, split between the two sides, at least two on each.
frame = function(l, r, chosen, ch, group, winwidth)
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

---Check if a step is this editor's own.
---
---A reader gives this editor's steps from its ledger, and earlier editors' from the pages, so a
---step began after this editor's ledger did exactly when it's this editor's.
---
---@param step CavediverLedgerStep The step
---@return boolean mine True if this editor made it
local function of_this_editor(step)
	return type(step.time) == "number" and step.time >= require('cavediver.domains.ledger').data.started
end

---Get what a move's name stands for, for gf and *.
---
---A file is named by its hash, a window by its id, and a list by its name. Anything else is a
---plain name. A window's id is only this editor's to follow: on a line an earlier editor wrote, the
---window is marked `earlier` and has no id, since ids start again in every editor.
---
---@param move CavediverLedgerMove The move
---@param step CavediverLedgerStep The step it's on
---@return table target The target's `kind`, `value` and `name`
target_of = function(move, step)
	local subject = move.subject
	if type(subject) == "string" and #subject == 16 and subject:match("^%x+$") then
		return { kind = "file", value = subject, name = move.name }
	elseif type(subject) == "string" and subject:match("^%d+$") and move.name and move.name:match("^win ") then
		if not of_this_editor(step) then
			return { kind = "window", earlier = true, name = move.name }
		end
		return { kind = "window", value = tonumber(subject), name = move.name }
	elseif LIST_KINDS[move.kind] and move.name then
		return { kind = "list", value = move.name, name = move.name }
	end
	return { kind = "name", value = move.name, name = move.name }
end

---Index the ring's steps by the very records it holds.
---
---A step is found by its own table, so only this editor's steps that the ring still keeps are
---in it.
---
---@return table<CavediverLedgerStep, integer> in_ring Each step's index in the ring
local function ring_index()
	local in_ring = {}
	for i, step in ipairs(require('cavediver.domains.ledger').data.ring) do
		in_ring[step] = i
	end
	return in_ring
end

---Get a step's index in the ring when it's this editor's own.
---
---A step on a page that an editor before this one wrote gets nil, so its line never opens.
local function own_of(in_ring, step)
	return of_this_editor(step) and in_ring[step] or nil
end

---Get the ring's index of the trail's line before a step of this editor's, on any day.
---
---It's the nearest step before it in the ring that made moves the trail shows, so a day's first
---step opens from the last line of the day before.
---
---@param own integer The step's index in the ring
---@return integer before The ring's index of the line before it, 0 for none
local function line_before(own)
	local ring = require('cavediver.domains.ledger').data.ring
	for i = own - 1, 1, -1 do
		if #ring[i].moves > 0 and view.reader.keeps(ring[i]) then
			return i
		end
	end
	return 0
end

---Get the key a step opens under, made of the day and the step's own number and time.
local function ring_key(day, step)
	return "ring:" .. day .. ":" .. step.seq .. ":" .. step.time
end

---Build the lines of the ring's steps between a step and the trail's line before it.
---
---The steps nearest the step are shown, 20 at a time, and a line above them counts the earlier
---ones still hidden. Each step shows its time, its trigger and its window, then the row it
---changed or its events.
---
---@param own integer The step's index in the ring
---@param before integer The ring's index of the trail's line before it, 0 for none
---@param key string The step's key in view.open and view.more
---@return table[] lines The lines, each with its pieces and what it stands for
local function ring_lines(glyphs, own, before, key)
	local ledger = require('cavediver.domains.ledger')
	local lines = {}
	local earlier = {}
	for i = before + 1, own - 1 do
		table.insert(earlier, ledger.data.ring[i])
	end
	local count = CHUNK * (1 + (view.more[key] or 0))
	local hidden = math.max(0, #earlier - count)
	if hidden > 0 then
		table.insert(lines, { segs = { { "        " .. glyphs.ring .. " " .. glyphs.more .. " " .. hidden ..
			(hidden == 1 and " earlier step" or " earlier steps"), "CavediverTrailRing" },
			{ "   (" .. ((require('cavediver.configs').keymaps.views or {}).fold or "za") .. " for " .. CHUNK .. " more)", "CavediverTrailDim" } },
			more = key })
	end
	for i = hidden + 1, #earlier do
		local ringed = earlier[i]
		local r = { { "        " .. glyphs.ring .. " " .. os.date("%H:%M:%S", math.floor(ringed.time)) .. "  ", "CavediverTrailRing" },
			{ string.format("%-15s", in_set(glyphs, ringed.trigger) or ""), "CavediverTrailTrigger" },
			{ (ringed.win and ledger.window_name(ringed.win) or "") .. "   ", "CavediverTrailRing" } }
		if ringed.row_before and ringed.row_after and not require('cavediver.domains.ledger.routines').same_row(ringed.row_before, ringed.row_after) then
			vim.list_extend(r, row_segs(glyphs, ringed.names or {}, ringed.row_before))
			table.insert(r, { glyphs.arrow, "CavediverTrailDim" })
			vim.list_extend(r, row_segs(glyphs, ringed.names or {}, ringed.row_after))
		else
			table.insert(r, { table.concat(ringed.events or {}, ", "), "CavediverTrailRing" })
		end
		table.insert(lines, { segs = r, ringed = ringed })
	end
	return lines
end

---Build the day's lines, each with what it stands for.
---
---The header comes first, then each step with its moves under it. More than three moves of a
---kind under one step fold to a count, and a step of this editor's opens into the ring's steps
---before it. The config's `trail_step` and `trail_move` formatters can draw a line instead.
local function day_lines(glyphs, winwidth)
	local keys = require('cavediver.configs').keymaps.views or {}
	local lines = { { segs = header(glyphs, keys, winwidth) }, { segs = { { "", nil } } } }
	if #view.steps == 0 then
		table.insert(lines, { segs = { { "no moves", "CavediverTrailDim" } } })
	end
	local formatters = require('cavediver.configs').formatters or {}
	local in_ring = ring_index()
	for _, step in ipairs(view.steps) do
		local names = step.names or {}
		local time = os.date("%H:%M", math.floor(step.time or 0))
		local own = own_of(in_ring, step)
		local key = own and ring_key(view.days[view.day], step)
		local segs = formatters.trail_step and formatters.trail_step(step, glyphs)
		if not segs then
			segs = {
				{ time .. " ", "CavediverTrailTime" }, { (glyphs[step.cause] or "?") .. " ", "CavediverTrailCause" },
				{ in_set(glyphs, step.trigger) or "", "CavediverTrailTrigger" },
			}
			if own then
				local pad = winwidth - width(segs) - 2
				table.insert(segs, { string.rep(" ", math.max(1, pad)), nil })
				table.insert(segs, { view.open[key] and glyphs.unfolded or glyphs.folded, "CavediverTrailFold" })
			end
		end
		table.insert(lines, { segs = segs, step = step, ring = key })
		if own and view.open[key] then
			vim.list_extend(lines, ring_lines(glyphs, own, line_before(own), key))
		end
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
							{ move.name or "?", move.dim and "CavediverTrailDim" or "CavediverTrailName", target = target_of(move, step) } },
							move = move, step = step })
					end
				end
			else
				local move = item.move
				local dim = move.dim == true
				local family = dim and "CavediverTrailDim" or ("CavediverTrail" .. (FAMILY[move.kind] or "Words"))
				local segs = formatters.trail_move and formatters.trail_move(move, glyphs, step)
				if not segs then
					segs = { indent, { branch, "CavediverTrailGutter" }, { (glyphs[move.kind] or "?") .. " ", family },
						{ string.format("%-14s", move.name or ""), dim and "CavediverTrailDim" or "CavediverTrailName", target = target_of(move, step) } }
					vim.list_extend(segs, word_segs(glyphs, move_words(glyphs, names, move), dim and "CavediverTrailDim" or "CavediverTrailWords"))
				end
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

---Find every move about a name, on every page, oldest first.
---
---Each result carries the name's state after its move, and a file back on disk returns to the
---state it had before it went. With a subject, only its own moves are found, not every one of
---that name, and a window's, this editor's alone.
---
---@param name string The name to search for
---@param subject string|nil A file's hash or a window's id
---@param mine boolean|nil Whether only this editor's steps count, as for a window
---@return table[] results Each move found, with its day, its step and the state after it
local function find(name, subject, mine)
	local results, state, before_gone = {}, "Open", nil
	for _, day in ipairs(view.reader.days()) do
		for _, step in ipairs(view.reader.steps(day)) do
			for _, move in ipairs((not mine or of_this_editor(step)) and step.moves or {}) do
				if (subject and move.subject == subject) or (not subject and move.name == name) then
					if move.kind == "gone" then
						before_gone = state
					end
					if move.kind == "back" then
						state = before_gone or "Closed"
					elseif move.state then
						state = move.state == "closed" and "Closed" or "Open"
					else
						state = STATE_AFTER[move.kind] or state
					end
					table.insert(results, { day = day, step = step, move = move, state = state })
				end
			end
		end
	end
	return results
end

---Build a search's lines, with the name's life line down the gutter.
---
---The life line is a bar on each result, coloured by the name's state after its move. A result
---of this editor's opens into the ring's steps as its step does on its day.
local function search_lines(glyphs, winwidth)
	local keys = require('cavediver.configs').keymaps.views or {}
	local days = {}
	for _, result in ipairs(view.results) do
		days[result.day] = true
	end
	local n_days = vim.tbl_count(days)
	local mid = {
		{ glyphs.title, "CavediverTrailTitle" }, { " " .. glyphs.search .. " ", "CavediverTrailCount" },
		{ view.query, "CavediverTrailName" },
		{ glyphs.dot .. #view.results .. (#view.results == 1 and " move" or " moves") .. " over " .. n_days ..
			(n_days == 1 and " day" or " days"), "CavediverTrailCount" },
	}
	local ch, group = fill_of(glyphs, 0, ((require('cavediver.configs').trail or {}).header or {}).shade ~= false)
	local l = { { glyphs.older .. " " .. (keys.leave or "q"), "CavediverTrailKeyOn" }, { " ", nil } }
	local r = { { " ", nil }, { (keys.act or "<CR>") .. " " .. glyphs.newer, "CavediverTrailKeyOn" } }
	local lines = { { segs = frame(l, r, mid, ch, group, winwidth) }, { segs = { { "", nil } } } }
	local trigger_width = 0
	for _, result in ipairs(view.results) do
		trigger_width = math.max(trigger_width, vim.api.nvim_strwidth(result.step.trigger or ""))
	end
	-- a result opens into the ring as its step does on its day: since the trail's line before it
	local in_ring = ring_index()
	local expanded = {}
	local last_day
	for _, result in ipairs(view.results) do
		local step, move = result.step, result.move
		local stamp = os.time({ year = tonumber(result.day:sub(1, 4)), month = tonumber(result.day:sub(6, 7)),
			day = tonumber(result.day:sub(9, 10)), hour = 12 })
		local label = result.day ~= last_day and os.date("%a %d", stamp) or string.rep(" ", #os.date("%a %d", stamp))
		last_day = result.day
		local trigger = in_set(glyphs, step.trigger) or ""
		local segs = {
			{ label .. " " .. os.date("%H:%M", math.floor(step.time or 0)) .. "  ", "CavediverTrailTime" },
			{ glyphs.life .. " ", "CavediverTrailLife" .. result.state },
			{ (glyphs[step.cause] or "?") .. " ", "CavediverTrailCause" },
			{ trigger .. string.rep(" ", trigger_width - vim.api.nvim_strwidth(trigger) + 2), "CavediverTrailTrigger" },
			{ (glyphs[move.kind] or "?") .. " ", "CavediverTrail" .. (FAMILY[move.kind] or "Words") },
		}
		vim.list_extend(segs, word_segs(glyphs, move_words(glyphs, step.names or {}, move), "CavediverTrailWords"))
		-- a step with two results opens under the first
		local own = not expanded[step] and own_of(in_ring, step)
		local key = own and ring_key(result.day, step)
		if own then
			expanded[step] = true
			table.insert(segs, { string.rep(" ", math.max(1, winwidth - width(segs) - 2)), nil })
			table.insert(segs, { view.open[key] and glyphs.unfolded or glyphs.folded, "CavediverTrailFold" })
		end
		table.insert(lines, { segs = segs, result = result, move = move, step = step, ring = key })
		if own and view.open[key] then
			vim.list_extend(lines, ring_lines(glyphs, own, line_before(own), key))
		end
	end
	if #view.results == 0 then
		table.insert(lines, { segs = { { "no moves name it", "CavediverTrailDim" } } })
	end
	return lines
end

---Read the trail's days again, keeping the day shown.
---
---A day that got its first move since the view last looked is in the list then.
---
---@return nil
local function read_days()
	local shown = view.days[view.day]
	view.days = view.reader.days()
	for i, day in ipairs(view.days) do
		if day == shown then
			view.day = i
		end
	end
	view.day = math.max(1, math.min(view.day, #view.days))
end

---Draw the view.
---
---Writes its lines and their colours, and keeps the map of what each line stands for, with
---where its targets sit, for the keys to read.
---
---@return nil
local function draw()
	if not view or not vim.api.nvim_buf_is_valid(view.buf) then
		return
	end
	local glyphs = require('cavediver.domains.ui.routines').glyphs()
	local winwidth = vim.api.nvim_win_is_valid(view.win) and vim.api.nvim_win_get_width(view.win) or 80
	local lines
	if view.mode == "search" then
		lines = search_lines(glyphs, winwidth)
	else
		read_days()
		local day = view.days[view.day]
		view.steps = day and view.reader.steps(day) or {}
		lines = day_lines(glyphs, winwidth)
	end
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
		line.targets = {}
		for _, seg in ipairs(line.segs) do
			if seg[2] and #seg[1] > 0 then
				vim.api.nvim_buf_set_extmark(view.buf, ns, i - 1, col, { end_col = col + #seg[1], hl_group = seg[2] })
			end
			if seg.target then
				table.insert(line.targets, { first = col, last = col + #seg[1] - 1, target = seg.target })
			end
			col = col + #seg[1]
		end
	end
	view.lines = lines
end

---Get what the line under the cursor stands for (nil when the trail isn't open).
local function at_cursor()
	if not view or not vim.api.nvim_win_is_valid(view.win) then
		return nil
	end
	return view.lines and view.lines[vim.api.nvim_win_get_cursor(view.win)[1]]
end

---Leave the trail.
---
---Closes its window and goes back to the window it was opened from.
---
---@return nil
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

---Go to the older or the newer day.
---
---Nothing happens past the oldest or the newest day. The cursor goes back to the header.
---
---@param step integer Which way to go, -1 for the older day and 1 for the newer
---@return nil
function M.page(step)
	if not view then
		return
	end
	read_days()
	local day = view.day + step
	if day >= 1 and day <= #view.days then
		view.day = day
		draw()
		vim.api.nvim_win_set_cursor(view.win, { 1, 0 })
	end
end

---Open or close what's under the cursor.
---
---A folded count opens into its moves, a step of this editor's into the ring's steps before it,
---and the line that counts the hidden steps shows 20 more. The cursor stays where it was.
---
---@return nil
function M.fold()
	local line = at_cursor()
	if not line then
		return
	end
	if line.fold then
		view.open[line.fold] = not view.open[line.fold]
	elseif line.more then
		view.more[line.more] = (view.more[line.more] or 0) + 1
	elseif line.ring then
		view.open[line.ring] = not view.open[line.ring]
		view.more[line.ring] = nil
	else
		return
	end
	local cursor = vim.api.nvim_win_get_cursor(view.win)
	draw()
	pcall(vim.api.nvim_win_set_cursor, view.win, cursor)
end

---Get the target under the cursor.
---
---It's the target at the cursor's column, or the line's first when the cursor is on none.
---
---@return table|nil target The target, or nil when the line has none
local function target_at_cursor()
	local line = at_cursor()
	if not line or not line.targets or #line.targets == 0 then
		return nil
	end
	local col = vim.api.nvim_win_get_cursor(view.win)[2]
	for _, t in ipairs(line.targets) do
		if col >= t.first and col <= t.last then
			return t.target
		end
	end
	return line.targets[1].target
end

---Search every page for a name, and show its life line.
---
---@param name string The name to search for
---@param subject string|nil A file's hash or a window's id, to follow that one alone
---@param mine boolean|nil Whether only this editor's steps count, as for a window
---@return nil
function M.search(name, subject, mine)
	if not view or name == nil or name == "" then
		return
	end
	view.mode, view.query = "search", name
	view.results = find(name, subject, mine)
	draw()
	pcall(vim.api.nvim_win_set_cursor, view.win, { math.min(3, vim.api.nvim_buf_line_count(view.buf)), 0 })
end

---Search for what's typed: a name, or a window of the tab the trail came from.
---
---`win <N>`, or `win` alone, is that tab's window N, or the window the trail came from, followed by
---its id in this editor. Anything else is a name.
---
---@param query string What's typed
---@param from integer The window the trail came from
---@return nil
local function search_typed(query, from)
	local number = query:match("^win%s*(%d*)$")
	if not number then
		M.search(query)
		return
	end
	local winid = number == "" and from or vim.fn.win_getid(tonumber(number), vim.api.nvim_tabpage_get_number(vim.api.nvim_win_get_tabpage(from)))
	if winid == 0 then
		vim.notify("cavediver: there's no window " .. number .. " in this tab.", vim.log.levels.WARN)
		return
	end
	M.search("win " .. vim.api.nvim_win_get_number(winid), tostring(winid), true)
end

---Ask for a name and search for it.
---@return nil
function M.ask()
	vim.ui.input({ prompt = "Search the trail for: " }, function(input)
		if view and input and input ~= "" then
			-- the window gone, the trail's own stands in for its tab
			search_typed(input, vim.api.nvim_win_is_valid(view.from) and view.from or view.win)
		end
	end)
end

---Say a window on a line an earlier editor wrote can't be followed.
---
---Its id meant a window of that editor, and ids start again in every editor.
---
---@param target table The window's target, marked `earlier`
---@return nil
earlier_window = function(target)
	vim.notify("cavediver: " .. (target.name or "that window") .. " was a window in an earlier editor, so the trail can't follow it.",
		vim.log.levels.WARN)
end

---Search for the name under the cursor.
---
---A file is followed by its hash and a window by its id, and anything else by its name. On a
---line with no target, the line's move gives one.
---
---@return nil
function M.search_word()
	local target = target_at_cursor()
	local line = at_cursor()
	if not target and line and line.move then
		target = target_of(line.move, line.step)
	end
	if target and target.earlier then
		earlier_window(target)
		return
	end
	local name = target and (target.name or target.value)
	if type(name) == "string" then
		-- a file follows its hash and a window its id, this editor's; anything else is its name
		M.search(name, (target.kind == "file" or target.kind == "window") and tostring(target.value) or nil, target.kind == "window")
	end
end

---Act on the target under the cursor, and keep the trail open.
---
---A file opens in the window the trail came from, a list shows in the closed lists with the
---cursor on its header, and a window becomes the current one. A No Name text, a file with no
---path, or any file once the window the trail came from is gone, isn't opened, and it says so.
---
---@return nil
function M.act_and_stay()
	local target = target_at_cursor()
	if not target then
		return
	end
	if target.kind == "file" then
		local path = require('cavediver.domains.history').get_filepath_from_hash(target.value)
		if not path or path:match("^NONAME_") or not (view.from and vim.api.nvim_win_is_valid(view.from)) then
			vim.notify("cavediver: " .. (target.name or "that file") .. " can't be opened from the trail.", vim.log.levels.WARN)
			return
		end
		vim.api.nvim_win_call(view.from, function()
			vim.cmd("edit " .. vim.fn.fnameescape(path))
		end)
	elseif target.kind == "window" then
		if target.earlier then
			earlier_window(target)
		elseif vim.api.nvim_win_is_valid(target.value) then
			vim.api.nvim_set_current_win(target.value)
		end
	elseif target.kind == "list" then
		local focus
		for _, pool in pairs(require('cavediver.domains.history').routines.pools()) do
			if require('cavediver.domains.history').routines.list_name(pool) == target.value then
				focus = pool
			end
		end
		require('cavediver.domains.ui.routines').show_closed_lists({ focus = focus })
	end
end

---Open the day of the search result under the cursor, on its step.
---
---It's the main action on a line, which only a search's results have.
---
---@return nil
function M.act()
	local line = at_cursor()
	if not (view and view.mode == "search" and line and line.result) then
		return
	end
	local result = line.result
	view.mode = "day"
	read_days()
	for i, day in ipairs(view.days) do
		if day == result.day then
			view.day = i
		end
	end
	draw()
	for i, drawn in ipairs(view.lines) do
		if drawn.step == result.step and not drawn.move then
			pcall(vim.api.nvim_win_set_cursor, view.win, { i, 0 })
			break
		end
	end
end

---Go back from a search to the day it was opened on, or leave the trail from a day.
---
---It's the views' leave key (`q`).
---
---@return nil
function M.back()
	if view and view.mode == "search" then
		view.mode = "day"
		draw()
		pcall(vim.api.nvim_win_set_cursor, view.win, { 1, 0 })
	else
		M.leave()
	end
end

---Open the trail of the current tab, on its newest day with moves, or on a search.
---
---Opened from a float, it takes the last tracked window as the one it came from. A query of
---`win <N>`, or `win` alone, searches for a window of this tab by its id.
---
---@param query string|nil A name to search for
---@return nil
function M.open(query)
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
	view = { buf = buf, win = win, from = from, reader = reader, days = days, day = math.max(1, #days), open = {}, more = {},
		mode = "day" }
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
	map(keys.leave, M.back, "Leave the trail, or the search back to the day")
	map(keys.leave_too, M.leave, "Leave the trail")
	map(keys.previous_section, function() if view and view.mode == "day" then M.page(-1) end end, "The older day")
	map(keys.next_section, function() if view and view.mode == "day" then M.page(1) end end, "The newer day")
	map(keys.fold, M.fold, "Open or close what's under the cursor")
	map(keys.act, M.act, "Open the result's day")
	map(keys.act_and_stay, function()
		-- it can change the editor, so it's a step, as the closed lists' keys are; the rest only move the view
		local settle = require('cavediver.settle')
		settle.drain()
		require('cavediver.domains.ledger').begin("keymap", keys.act_and_stay, view and view.from or vim.api.nvim_get_current_win())
		settle.guard(function()
			require('cavediver.domains.navigation').cancel_cycle_elsewhere()
			M.act_and_stay()
		end)
	end, "Act on the name under the cursor, and stay")
	map(keys.search, M.ask, "Search the trail")
	map(keys.search_word, M.search_word, "Search the trail for the name under the cursor")
	vim.bo[buf].filetype = "cavediver-trail"
	draw()
	if query and query ~= "" then
		search_typed(query, from)
	end
end

return M
