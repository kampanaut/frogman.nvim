-- Snapshots (M16). IDs are the spec's (what-is-frogman.md, section 7).
local Helpers = dofile('tests/helpers.lua')
local S2 = dofile('tests/helpers_s2.lua')
local Misc = dofile('tests/helpers_misc.lua')
local eq = Helpers.eq
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = child.stop,
	},
})

local TAKE = '<M-;><M-s>'
local LIST = '<M-;>S'

-- The messages said since the last call, their text alone.
local function said()
	return vim.tbl_map(function(m) return m.msg end, child.messages())
end

-- The current window's snapshots, each as its slots, queue and order by file name.
local function snapshots(win)
	return child.lua([[
		local S = require('frogman.domains.snapshots').routines
		local H = require('frogman.domains.history')
		local function name(id)
			local h = S.handle(id)
			return h and vim.fn.fnamemodify(H.get_filepath_from_hash(h.hash), ':t:r') or '-'
		end
		local out = {}
		for _, s in ipairs(S.of_window(... or vim.api.nvim_get_current_win())) do
			table.insert(out, {
				slots = '⦉' .. (s.ternary and name(s.ternary) or '-') .. '⦊ [' .. name(s.current) .. '] ⟦' .. (s.secondary and name(s.secondary) or '-') .. '⟧',
				queue = '[' .. table.concat(vim.tbl_map(name, s.queue), ',') .. ']' .. (s.primary_enabled and 'on' or 'off'),
				order = table.concat(vim.tbl_map(name, s.order), ','),
				id = s.id,
			})
		end
		return out
	]], { win })
end

-- The setup T762 takes: ⦉c⦊ [d] ⟦b⟧ with d the primary, then a snapshot.
local function taken()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d', '<M-;><M-c>' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	child.messages()
	child.steps({ TAKE })
end

-- The list's buffer and lines, and each line's drawing; nil when it isn't open.
local function list()
	return child.lua([[
		local buf = vim.fn.bufnr('frogman://snapshots')
		if buf == -1 then return vim.NIL end
		local ns = vim.api.nvim_get_namespaces()['frogman_snapshots']
		local drawn = {}
		for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
			local text = {}
			for _, chunk in ipairs(m[4].virt_text or {}) do table.insert(text, chunk[1]) end
			local at = drawn[m[2] + 1] or { text = '', concealed = false }
			drawn[m[2] + 1] = { text = at.text .. table.concat(text), concealed = at.concealed or m[4].conceal == '' }
		end
		return { lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false), drawn = drawn, ft = vim.bo[buf].filetype,
			bt = vim.bo[buf].buftype, modified = vim.bo[buf].modified }
	]])
end

-- The open list's lines, decoded: each line's snapshot id, or false when it doesn't decode.
local function decoded_ids()
	return child.lua([[
		local L = require('frogman.domains.snapshots').list
		local out = {}
		for _, line in ipairs(vim.api.nvim_buf_get_lines(vim.fn.bufnr('frogman://snapshots'), 0, -1, false)) do
			local d = L.decode(line)
			table.insert(out, d and d.id or false)
		end
		return out
	]])
end

-- How many of the open list's lines decode to a snapshot, its header lines left out.
local function snapshot_lines()
	return #vim.tbl_filter(function(id) return id ~= false end, decoded_ids())
end

T['T762 [char] (M16) the capture holds the window\'s setup'] = function()
	taken()
	local got = snapshots()
	eq({ n = #got, slots = got[1] and got[1].slots, queue = got[1] and got[1].queue, first = got[1] and got[1].order:match('^[^,]+'),
		said = said() }, { n = 1, slots = '⦉c⦊ [d] ⟦b⟧', queue = '[d]on', first = 'd', said = { 'frogman: snapshot taken: window 1 has 1.' } })
end

T['T763 [char] (M16) a snapshot holds its files'] = function()
	taken()
	child.steps({ ':e a' })
	child.cmd('bdelete c.txt')
	child.settle()
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, S2.line_of(lines, 'c.txt'))
	S2.write_picker(child, p, lines)
	child.cmd('close')
	child.settle(100)
	local kept = child.lua([[
		local H = require('frogman.domains.history')
		local h = H.handles.of_hash(H.routines.get_filehash(_G.FRG_TEST.root .. '/c.txt'))
		local places = {}
		for place, _ in pairs(h and h.holders or {}) do table.insert(places, (place:gsub(':%d+$', ':<id>'))) end
		table.sort(places)
		return { known = h ~= nil, places = places }
	]])
	eq(kept, { known = true, places = { 'snap:<id>' } })
end

T['T764 [char] (M16) the list draws each snapshot over its concealed encoding'] = function()
	taken()
	child.steps({ ':e e', TAKE })
	local ids = vim.tbl_map(function(x) return x.id end, snapshots()) -- the window's, before the list takes the focus
	child.steps({ LIST })
	local l = list()
	local ok_ids = l ~= vim.NIL and l.lines[1]:match('^fs1:') ~= nil and l.lines[2]:match('^fs1:') ~= nil
		and vim.deep_equal(decoded_ids(), { ids[2], ids[1] })
	local older = l ~= vim.NIL and l.drawn[2] or {}
	child.lua('vim.cmd("redraw")')
	local shot = tostring(child.get_screenshot())
	local screen = { drawn = shot:find('⦉c.txt⦊ [d.txt] ⟦b.txt⟧', 1, true) ~= nil, hidden = shot:find('fs1:', 1, true) == nil }
	child.cmd('close')
	child.settle()
	child.cmd('FrogmanSnapshots')
	child.settle()
	local again = list()
	eq({ ft = l.ft, bt = l.bt, n = #l.lines, ids = ok_ids, concealed = older.concealed,
		time = (older.text or ''):match('^%d%d:%d%d') ~= nil, slots = (older.text or ''):find('⦉c.txt⦊ [d.txt] ⟦b.txt⟧', 1, true) ~= nil,
		order = (older.text or ''):find('d.txt', 1, true) ~= nil, again = again ~= vim.NIL and #again.lines, screen = screen },
		{ ft = 'frogman-snapshots', bt = 'acwrite', n = 2, ids = true, concealed = true, time = true, slots = true, order = true, again = 2,
		screen = { drawn = true, hidden = true } })
end

-- The setup T765 takes: T763's state, then the snapshot's line deleted and written.
T['T765 [char] (M16) deleting a line and writing deletes its snapshot and lets its files go'] = function()
	taken()
	child.steps({ ':e a' })
	child.cmd('bdelete c.txt')
	child.settle()
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, S2.line_of(lines, 'c.txt'))
	S2.write_picker(child, p, lines)
	child.cmd('close')
	child.settle(100)
	child.steps({ LIST })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, {})')
	child.cmd('silent! write')
	child.settle(300)
	local after = { n = #snapshots(child.lua('return vim.fn.win_getid(vim.fn.winnr("#"))')),
		c = child.lua('return require("frogman.domains.history").routines.get_hash_from_filepath(_G.FRG_TEST.root .. "/c.txt") ~= nil') }
	eq(after, { n = 0, c = false })
end

T['T766 [char] (M16) a line naming no snapshot is asked about'] = function()
	taken()
	child.steps({ LIST })
	child.lua('vim.api.nvim_buf_set_lines(0, 1, 1, false, { "snap:nothing" })')
	child.answer('No')
	child.cmd('silent! write')
	child.settle(100)
	local asked = child.prompts()
	local after_no = list().modified
	child.answer('Yes')
	child.cmd('silent! write')
	child.settle(100)
	eq({ asked = #asked, names = asked[1] and asked[1]:find('snap:nothing  names no snapshot', 1, true) ~= nil, after_no = after_no,
		after_yes = list().modified, n = #list().lines }, { asked = 1, names = true, after_no = true, after_yes = false, n = 1 })
end

T['T767 [char] (M16) the capture refuses where there\'s nothing to take'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('help')
	child.settle()
	child.messages()
	child.steps({ TAKE })
	local help = said()
	child.cmd('close')
	child.settle()
	child.steps({ '<M-m>' })
	child.messages()
	child.steps({ TAKE })
	local cycling = said()
	child.steps({ '<M-v>' })
	eq({ help = help, cycling = cycling, n = #snapshots() },
		{ help = { 'Window with unregistered buffer.' }, cycling = { 'frogman: pick or cancel the cycle first.' }, n = 0 })
end

-- A whole-editor load from idle starts with the file's snapshots alone, each once: reloading the session left,
-- whose write as the load began put the window's snapshots onto its entry as they stood, the one taken since
-- the save among them (DESK.md:1205).
T['T768 [char] (M16, S1, DESK.md:1205) a whole-editor load from idle starts with the file\'s snapshots alone, the session left\'s written first'] = function()
	taken()
	eq(S2.save(child), { true })
	child.steps({ ':e e', TAKE, ':e d' }) -- back on d, so the window takes its entry
	local before = vim.tbl_map(function(x) return x.id end, snapshots())
	table.sort(before)
	eq(S2.load(child), { true })
	child.settle(300)
	local after = vim.tbl_map(function(x) return x.id end, snapshots())
	table.sort(after)
	eq({ n = #before, after = after }, { n = 2, after = before })
end

T['T769 [char] (M16, S1 Load) a fresh start from bare drops the snapshots before their handles go'] = function()
	taken()
	eq(S2.load(child, 'nothing'), { true })
	child.settle(300)
	local left = child.lua([[
		local H = require('frogman.domains.history')
		local snap = false
		for _, h in pairs(H.handles.live and H.handles.live() or {}) do
			for place, _ in pairs(h.holders or {}) do
				if place:match('^snap:') then snap = true end
			end
		end
		return { none = next(require('frogman.domains.snapshots').data.by_window) == nil, snap = snap }
	]])
	child.messages()
	child.steps({ LIST })
	eq({ left = left, errors = vim.tbl_filter(function(m) return m.level == 4 end, child.messages()) },
		{ left = { none = true, snap = false }, errors = {} })
end

T['T770 [char] (M16) q writes and leaves the list, :q refuses, and :q! discards'] = function()
	taken()
	child.steps({ ':e e', TAKE, LIST })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, 1, false, {})')
	local ok = child.lua('return { pcall(vim.cmd, "quit") }')
	local still = list() ~= vim.NIL
	child.cmd('quit!')
	child.settle()
	local discarded = #snapshots()
	child.steps({ LIST })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, 1, false, {})')
	child.step('q')
	child.settle(100)
	eq({ e37 = (ok[2] or ''):find('E37', 1, true) ~= nil, still = still, discarded = discarded, gone = list() == vim.NIL, n = #snapshots() },
		{ e37 = true, still = true, discarded = 2, gone = true, n = 1 })
end

-- The preview, its cancel and its commit (M16, 5b) ---------------------------------------

-- The window's display: what its winbar is drawn from, by file name, and the bufferline's first file.
local function shown_as(win)
	return child.lua([[
		local win = ...
		local UI = require('frogman.domains.ui')
		local c = UI.data.window_display_cache[win] or {}
		local function name(b) return b and vim.api.nvim_buf_is_valid(b) and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ':t:r') or '-' end
		local best, at = nil, -math.huge
		for b, t in pairs(UI.data.bufferline_state.buffer_ranking or {}) do
			if t > at then best, at = b, t end
		end
		return { slots = '⦉' .. name(c.ternary_bufnr) .. '⦊ [' .. name(c.current_bufnr) .. '] ⟦' .. name(c.secondary_bufnr) .. '⟧',
			first = name(best), detached = require('frogman.domains.history').is_detached() }
	]], { win })
end

-- T762's snapshot, then :e a and :e e (⦉a⦊ [e] ⟦b⟧), and the snapshot shown from the list.
local function previewing()
	taken()
	child.steps({ ':e a', ':e e' })
	eq(child.slots(), '⦉a⦊ [e] ⟦b⟧')
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	return win
end

T['T772 [char] (M16) <CR> shows a snapshot in the window the list came from'] = function()
	local win = previewing()
	child.lua('require("frogman").set_cache_from_window_triquetra(...); require("frogman.domains.ui").routines.refresh_ui(...)', { win, win })
	eq({ list = list() == vim.NIL, shown = child.shown(win), as = shown_as(win), slots = child.slots(win) },
		{ list = true, shown = 'd', as = { slots = '⦉c⦊ [d] ⟦b⟧', first = 'd', detached = true }, slots = '⦉a⦊ [e] ⟦b⟧' })
end

T['T773 [char] (M16) <M-n> and <M-m> step through the stored order'] = function()
	local win = previewing()
	local order = snapshots(win)[1].order
	local second = vim.split(order, ',')[2]
	child.step('<M-m>')
	child.settle()
	local stepped = child.shown(win)
	child.step('<M-n>')
	child.settle()
	eq({ stepped = stepped, back = child.shown(win), slots = child.slots(win) }, { stepped = second, back = 'd', slots = '⦉a⦊ [e] ⟦b⟧' })
end

T['T774 [char] (M16) a jump to another window cancels'] = function()
	taken()
	child.steps({ ':e a', ':e e' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('vsplit')
	child.settle()
	child.cmd('wincmd p')
	child.settle()
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	local during = child.shown(win)
	child.cmd('wincmd w') -- into the split: the window before was the list, gone
	child.settle(200)
	eq({ during = during, back = child.shown(win), slots = child.slots(win),
		detached = child.lua('return require("frogman.domains.history").is_detached()') },
		{ during = 'd', back = 'e', slots = '⦉a⦊ [e] ⟦b⟧', detached = false })
end

T['T775 [char] (M16) opening the list cancels'] = function()
	local win = previewing()
	child.steps({ LIST })
	child.settle(200)
	eq({ back = child.shown(win), detached = child.lua('return require("frogman.domains.history").is_detached()'), open = list() ~= vim.NIL },
		{ back = 'e', detached = false, open = true })
end

T['T776 [char] (M16) <M-v> on the snapshot\'s current takes it'] = function()
	local win = previewing()
	child.step('<M-v>')
	child.settle(100)
	local after = { slots = child.slots(win), queue = child.lua([[
		local t = require('frogman.domains.window').data.crux[...]
		local H = require('frogman.domains.history')
		return vim.tbl_map(function(h) return vim.fn.fnamemodify(H.get_filepath_from_handle(h), ':t:r') end, t.primary_buffer)[1] .. (t.primary_enabled and 'on' or 'off')
	]], { win }), newest = child.ordered():match('^[^,]+'), detached = child.lua('return require("frogman.domains.history").is_detached()') }
	local before = child.dump_files()
	child.messages()
	child.steps({ '<M-;><M-r>', '<M-;><M-t>' })
	local errors = vim.tbl_map(function(m) return m.msg end, vim.tbl_filter(function(m) return m.level == 4 end, child.messages()))
	eq({ after = after, errors = errors, dumped = child.dumped_since(before) },
		{ after = { slots = '⦉c⦊ [d] ⟦b⟧', queue = 'don', newest = 'd', detached = false }, errors = {} })
end

T['T777 [char] (M16) <M-v> on the snapshot\'s ternary makes a pick\'s swap'] = function()
	local win = previewing()
	child.lua('vim.api.nvim_win_set_buf(..., vim.fn.bufnr(_G.FRG_TEST.root .. "/c.txt"))', { win })
	child.settle()
	child.step('<M-v>')
	child.settle(100)
	eq(child.slots(win), '⦉d⦊ [c] ⟦b⟧')
end

T['T778 [char] (M16) the buffer the preview left keeps the arrangement it had'] = function()
	local win = previewing()
	child.step('<M-v>')
	child.settle(100)
	child.steps({ ':e e' })
	local before = child.slots(win)
	child.steps({ '<M-;><M-r>' })
	local ternary = child.slots(win)
	child.steps({ '<M-;><M-t>' })
	eq({ before = before, ternary = ternary:match('^⦉(%a)⦊'), secondary = child.slots(win):match('⟦(%a)⟧$') },
		{ before = before, ternary = 'a', secondary = 'b' })
end

T['T779 [char] (M16) every other key refuses while a snapshot shows'] = function()
	local win = previewing()
	child.messages()
	child.steps({ '<M-f>', '<M-.>', "<M-'><M-a>" })
	local said = vim.tbl_map(function(m) return m.msg end, child.messages())
	local words = 'frogman: a snapshot is showing: <M-v> takes it, and opening the snapshot list or going to another window leaves it.'
	eq({ said = said, shown = child.shown(win), detached = child.lua('return require("frogman.domains.history").is_detached()') },
		{ said = { words, words, words }, shown = 'd', detached = true })
end

T['T780 [char] (M16) <CR> refuses while the list has unsaved edits'] = function()
	taken()
	child.steps({ ':e e', TAKE, LIST })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, 1, false, {})')
	child.messages()
	child.step('<CR>')
	child.settle()
	eq({ said = vim.tbl_map(function(m) return m.msg end, child.messages()), open = list() ~= vim.NIL },
		{ said = { 'frogman: the snapshot list has edits not written yet: write them with :w, or leave them, first.' }, open = true })
end

T['T782 [char] (M16) in the window view the commit lays the stored order into the window\'s history'] = function()
	child.lua('_G.FRG_TEST.setup({ bufferline = { history_view = "window" } })')
	local win = previewing()
	local order = snapshots(win)[1].order
	child.step('<M-v>')
	child.settle(100)
	local ranked = child.lua([[
		local H = require('frogman.domains.history')
		local own = H.data.crux_internals.window[...] or {}
		local items = {}
		for h, t in pairs(own) do table.insert(items, { vim.fn.fnamemodify(H.get_filepath_from_handle(h) or tostring(h), ':t:r'), t }) end
		table.sort(items, function(a, b) return a[2] > b[2] end)
		return table.concat(vim.tbl_map(function(i) return i[1] end, items), ',')
	]], { win })
	eq(ranked:sub(1, #order), order)
end

T['T783 [char] (M16, A20) the rename rule: a slot that ends up holding the current\'s file lets it go'] = function()
	child.steps({ ':e a', ':e b', '<M-f>', ':e a' })
	eq(child.slots():match('%[(%a)%] ⟦(%a)⟧'), 'a')
	child.steps({ TAKE, ':e c' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('bwipeout a.txt')
	child.settle()
	child.lua([[
		local root = _G.FRG_TEST.root
		os.rename(root .. '/b.txt', root .. '/a.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/b.txt'), root .. '/a.txt')
	]])
	child.settle(300)
	local before = child.dump_files()
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	child.step('<M-v>')
	child.settle(100)
	eq({ secondary = child.slots(win):match('⟦(.-)⟧$'), dumped = child.dumped_since(before) }, { secondary = '-' })
end

T['T784 [char] (M16) <M-v> on the snapshot\'s secondary makes a pick\'s swap'] = function()
	local win = previewing()
	child.lua('vim.api.nvim_win_set_buf(..., vim.fn.bufnr(_G.FRG_TEST.root .. "/b.txt"))', { win })
	child.settle()
	child.step('<M-v>')
	child.settle(100)
	eq(child.slots(win), '⦉c⦊ [b] ⟦d⟧')
end

T['T785 [char] (M16) <M-v> outside the snapshot\'s slots'] = function()
	local win = previewing()
	child.lua('vim.api.nvim_win_set_buf(..., vim.fn.bufnr(_G.FRG_TEST.root .. "/a.txt"))', { win })
	child.settle()
	child.step('<M-v>')
	child.settle(100)
	local note = child.lua([[
		local t = require('frogman.domains.window').data.crux[...]
		local H = require('frogman.domains.history')
		local a = H.get_handle_from_filepath(_G.FRG_TEST.root .. '/a.txt')
		local v = t.displacement_ternary_map[a]
		return v and vim.fn.fnamemodify(H.get_filepath_from_handle(v), ':t:r') or false
	]], { win })
	eq({ slots = child.slots(win), note = note }, { slots = '⦉c⦊ [a] ⟦b⟧', note = 'd' })
end

T['T786 [char] (M16, A12) a cancel ahead of typed keys keeps their slots'] = function()
	taken()
	child.steps({ ':e a', ':e e' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c' })
	local split = child.lua('return vim.api.nvim_get_current_win()')
	local before = child.slots(split)
	child.cmd('wincmd p')
	child.settle()
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	child.lua([[vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-w>w:e x.txt<CR>', true, false, true), 'xt', false)]])
	child.settle(300)
	eq({ before = before, split = child.slots(split), back = child.shown(win) },
		{ before = before, split = '⦉' .. before:match('%[(%a)%]') .. '⦊ [x] ⟦-⟧', back = 'e' })
end

T['T787 [char] (M16, S1 Load) a tab session\'s load ends a preview'] = function()
	local got = {}
	for _, where in ipairs({ 'here', 'elsewhere' }) do
		child.setup()
		local win = previewing()
		local tab = child.lua('return vim.api.nvim_get_current_tabpage()')
		if where == 'elsewhere' then
			child.lua('vim.cmd("noautocmd tabnew"); vim.cmd("noautocmd edit f.txt")')
			tab = child.lua('return vim.api.nvim_get_current_tabpage()')
			child.lua('vim.api.nvim_set_current_win(...)', { win })
		end
		child.lua('require("frogman").load_session("u", { tab = ... })', { tab })
		child.settle(300)
		local attached = not child.lua('return require("frogman.domains.history").is_detached()')
		local active = child.lua('return require("frogman.domains.snapshots").preview.active()')
		child.messages()
		child.steps({ '<M-f>' })
		local refused = #vim.tbl_filter(function(m) return m.msg:find('a snapshot is showing', 1, true) ~= nil end, child.messages())
		table.insert(got, { attached = attached, active = active, refused = refused })
	end
	eq(got, { { attached = true, active = false, refused = 0 }, { attached = true, active = false, refused = 0 } })
end

-- Held over, saved and loaded (M16, 5d) --------------------------------------------------

local STAMP = ' · %d%d%-%d%d %d%d:%d%d'

-- A session scope's held-over snapshots, each as its header and its slots by file name.
local function held(id)
	return child.lua([[
		local S = require('frogman.domains.snapshots').routines
		local H = require('frogman.domains.history')
		local function name(i)
			local h = S.handle(i)
			return h and vim.fn.fnamemodify(H.get_filepath_from_hash(h.hash), ':t:r') or '-'
		end
		local out = {}
		for _, s in ipairs(S.held_in(...)) do
			table.insert(out, { held = s.held, id = s.id,
				slots = '⦉' .. (s.ternary and name(s.ternary) or '-') .. '⦊ [' .. name(s.current) .. '] ⟦' .. (s.secondary and name(s.secondary) or '-') .. '⟧' })
		end
		return out
	]], { id or '' })
end

-- The route T771 takes: a split's snapshot holding x (⦉b⦊ [x] ⟦-⟧), the split back on b and closed.
local function split_held_over()
	child.steps({ ':e a', ':e b' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e x', TAKE, ':e b' })
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('close')
	child.settle(300)
	return split
end

-- The lines the open list draws above its lines, joined.
local function headers()
	return child.lua([[
		local buf = vim.fn.bufnr('frogman://snapshots')
		local ns = vim.api.nvim_get_namespaces()['frogman_snapshots']
		local out = {}
		for _, m in ipairs(buf ~= -1 and vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) or {}) do
			for _, vl in ipairs(m[4].virt_lines or {}) do
				local text = {}
				for _, chunk in ipairs(vl) do table.insert(text, chunk[1]) end
				table.insert(out, table.concat(text))
			end
		end
		return out
	]])
end

T['T771 [char] (M16) a window closed while you work with no saved entry leaves its snapshots held over'] = function()
	local split = split_held_over()
	local x = child.lua([[
		local H = require('frogman.domains.history')
		local h = H.handles.of_hash(H.routines.get_filehash(_G.FRG_TEST.root .. '/x.txt'))
		for place, _ in pairs(h and h.holders or {}) do
			if place:match('^snap:') then return true end
		end
		return false
	]])
	local own = child.lua('return require("frogman.domains.snapshots").data.by_window[...] ~= nil', { split })
	local h = held('')
	child.steps({ LIST })
	local l = list()
	local ids = decoded_ids()
	eq({ own = own, n = #h, slots = h[1] and h[1].slots, x = x,
		name = h[1] and h[1].held:match('^held over · window on b%.txt' .. STAMP .. '$') ~= nil,
		lines = l ~= vim.NIL and #l.lines or 0, header = l ~= vim.NIL and h[1] ~= nil and l.lines[1] == h[1].held,
		under = h[1] ~= nil and ids[2] == h[1].id },
		{ own = false, n = 1, slots = '⦉b⦊ [x] ⟦-⟧', x = true, name = true, lines = 2, header = true, under = true })
end

T['T796 [char] (M16) committing a held-over snapshot leaves it held over'] = function()
	split_held_over()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	child.steps({ '<M-v>' })
	child.settle(100)
	eq({ slots = child.slots(), held = #held(''), own = #snapshots(win) }, { slots = '⦉b⦊ [x] ⟦-⟧', held = 1, own = 0 })
end

T['T789 [char] (M16, S1) a window\'s snapshots ride on its entry'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e d', ':e b', TAKE })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e a', ':e c', TAKE })
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b', 'c', 'd' }, 'c')
	child.cmd('noautocmd vsplit')
	child.cmd('noautocmd edit b.txt')
	local wins = child.lua('return vim.api.nvim_tabpage_list_wins(0)')
	eq(S2.load(child), { true })
	child.settle(300)
	local got = {}
	for _, win in ipairs(wins) do
		table.insert(got, { shows = child.shown(win), slots = vim.tbl_map(function(x) return x.slots end, snapshots(win)) })
	end
	eq(got, { { shows = 'b', slots = { '⦉d⦊ [b] ⟦-⟧' } }, { shows = 'c', slots = { '⦉a⦊ [c] ⟦-⟧' } } })
end

T['T790 [char] (M16, S1 Load) an entry no window takes leaves its snapshots held over'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e d', ':e c', TAKE })
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	local project = vim.fn.fnamemodify(s.root, ':t')
	local h = held('')
	eq({ n = #h, slots = h[1] and h[1].slots,
		name = h[1] and h[1].held:match('^held over · ' .. vim.pesc(project) .. ', loaded' .. STAMP .. '$') ~= nil },
		{ n = 1, slots = '⦉d⦊ [c] ⟦-⟧', name = true })
end

-- The save comes first, so the held-over snapshot reaches the file by the records the quit writes.
T['T792 [char] (M16, S1 Records) held-over snapshots are saved and loaded'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	eq(S2.save(child), { true })
	split_held_over()
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	local h = held('')
	eq({ n = #h, slots = h[1] and h[1].slots, name = h[1] and h[1].held:match('^held over · window on b%.txt' .. STAMP .. '$') ~= nil },
		{ n = 1, slots = '⦉b⦊ [x] ⟦-⟧', name = true })
end

-- t in a second tab, loaded as resession loads a tab session.
local function tab_session(s)
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(S2.load_tab_session(child, 't'), { true })
end

T['T793 [char] (M16, S1 Load) a tab session loaded while it\'s open skips the file\'s held-over snapshots memory holds'] = function()
	local s = S2.shared()
	tab_session(s)
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', TAKE, ':e d' })
	child.cmd('close')
	child.settle(300)
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local before = #held(id)
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	eq(S2.load_tab_session(child, 't'), { true })
	eq({ before = before, after = #held(id) }, { before = 1, after = 1 })
end

T['T794 [char] (M16, M5) the No Name texts snapshots hold are written'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':enew' })
	local n = child.lua('return vim.api.nvim_get_current_buf()')
	child.cmd('buffer a.txt')
	child.settle()
	child.steps({ TAKE })
	child.cmd('bwipeout ' .. n)
	child.settle(100)
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a' }, 'a')
	eq(S2.load(child), { true })
	child.settle(300)
	eq(child.lua([[
		local S = require('frogman.domains.snapshots').routines
		local H = require('frogman.domains.history')
		local s = S.of_window(vim.api.nvim_get_current_win())[1]
		local h = s and s.ternary and S.handle(s.ternary)
		local path = h and H.get_filepath_from_hash(h.hash) or ''
		return { noname = path:match('^NONAME_') ~= nil, text = h ~= nil and h.text ~= nil,
			listed = h ~= nil and vim.tbl_contains(H.get_closed_buffers(), h.id) }
	]]), { noname = true, text = true, listed = false })
end

-- The split shows b at the save, as the window left does, so its entry is the first that window takes.
T['T795 [char] (M16) a switch holds no snapshot over'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e x', TAKE, ':e b' })
	eq(S2.save(child), { true })
	child.lua('vim.cmd("close"); require("frogman").load_session()')
	child.settle(300)
	eq({ held = #held(''), own = #snapshots() }, { held = 0, own = 1 })
end

-- Saved on its window, then held over before the quit's records: one snapshot comes back, the window's
-- when the window left takes the split's entry (the split back on b), the held copy going as the window
-- takes it, or held over when it doesn't (on x).
T['T797 [char] (M16, S1 Load, DESK.md:1211) a snapshot held over after its save comes back once'] = function()
	local got = {}
	for _, last in ipairs({ ':e b', ':e x' }) do
		local s = S2.shared()
		S2.start(child, s)
		child.steps({ ':e a', ':e b' })
		child.cmd('split')
		child.settle()
		child.steps({ ':e x', TAKE, last })
		eq(S2.save(child), { true })
		child.cmd('close')
		child.settle(300)
		S2.start(child, s) -- the quit writes the records, the held-over snapshot among them
		Misc.restore(child, { 'a', 'b' }, 'b')
		eq(S2.load(child), { true })
		child.settle(300)
		table.insert(got, { held = #held(''), own = #snapshots() })
	end
	eq(got, { { held = 0, own = 1 }, { held = 1, own = 0 } })
end

-- A detached list has no file of its own: the whole editor's holds what its tab's windows leave.
T['T798 [char] (M16, M5) a window closed in a detached list\'s tab is held over in the list\'s own scope'] = function()
	local s = S2.shared()
	tab_session(s)
	eq(S2.load_tab_session(child, 't'), { true }) -- the second tab keeps t_DETACHED
	child.cmd('tabnext 2')
	child.settle()
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', TAKE, ':e d' })
	child.cmd('close')
	child.settle(300)
	child.steps({ LIST })
	eq({ detached = id:match('DETACHED') ~= nil, there = #held(id), whole = #held(''), listed = snapshot_lines() },
		{ detached = true, there = 1, whole = 0, listed = 1 })
end

-- A tab session's snapshot of a No Name text held over at one load, its entry taken back at the next: the copy is
-- the same snapshot, known by its files, not by the hash the file had for the text, so the window takes it.
T['T1225 [char] (M16, DESK.md:1211, :1212) a held-over snapshot of a No Name text goes when its window takes the entry back, the window taking it'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.cmd('tabnew')
	child.steps({ ':e c' })
	S2.noname(child, { 'draft' })
	child.steps({ TAKE, ':e d' })
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e x' })
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local t = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local before = #held(t)
	eq(S2.load_tab_session(child, 't'), { true })
	eq({ before = before, after = #held(t), window = child.lua('return #require("frogman.domains.snapshots").routines.of_window(vim.api.nvim_get_current_win())') },
		{ before = 1, after = 0, window = 1 })
end

-- Borrowed files, the placeholder and untracked windows (M16, 5c) ---------------------------

-- The current window's buffer: its name's last part and whole, whether it's listed and taken in, and its lines.
local function showing()
	return child.lua([[
		local b = vim.api.nvim_get_current_buf()
		local name = vim.api.nvim_buf_get_name(b)
		return { name = name ~= '' and vim.fn.fnamemodify(name, ':t') or '', full = name, listed = vim.bo[b].buflisted,
			taken = require('frogman.domains.history').get_hash_from_buffer(b) ~= nil,
			lines = vim.api.nvim_buf_get_lines(b, 0, -1, false) }
	]])
end

-- A file's state by its stem: whether a buffer of it is taken in, and whether it's on the editor's list.
local function state(stem)
	return child.lua([[
		local H = require('frogman.domains.history')
		local h = H.routines.get_filehash(_G.FRG_TEST.root .. '/' .. ... .. '.txt')
		local id = H.get_handle_from_hash(h)
		return { taken = H.get_buffer_from_hash(h) ~= nil, listed = id ~= nil and vim.tbl_contains(H.get_closed_buffers(), id) }
	]], { stem })
end

-- How many No Name texts the editor's closed list holds.
local function texts_on_list()
	return child.lua([[
		local H = require('frogman.domains.history')
		local n = 0
		for _, h in ipairs(H.get_closed_buffers()) do
			if (H.get_filepath_from_handle(h) or ''):match('^NONAME_') then n = n + 1 end
		end
		return n
	]])
end

-- Step the preview until it shows `name` (a file name, or the first line for a text), at most six steps.
local function step_to(name)
	for _ = 1, 6 do
		local at = showing()
		if at.name == name or at.lines[1] == name then
			return
		end
		child.steps({ '<M-m>' })
		child.settle(50)
	end
end

-- T762's snapshot, then :e a and :e e, a file closed, and the list's <CR>.
local function shown_with_closed(stem)
	taken()
	child.steps({ ':e a', ':e e' })
	child.cmd('bdelete ' .. stem .. '.txt')
	child.settle()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	return win
end

T['T781 [char] (M16) a snapshot whose current is closed shows it borrowed'] = function()
	local before = #child.dump_files() -- the run's other cases dump into the same folder
	local win = shown_with_closed('d')
	child.messages()
	child.settle(300) -- the UI's ticks draw it
	local quiet = { errors = #vim.tbl_filter(function(m) return m.level == 4 end, child.messages()), dumps = #child.dump_files() - before }
	local at = showing()
	local drawn = child.lua([[
		local c = require('frogman.domains.ui').data.window_display_cache[...] or {}
		return { current = c.current_bufnr == vim.api.nvim_get_current_buf(), visiting = c.visiting ~= nil }
	]], { win })
	eq({ name = at.name, listed = at.listed, taken = at.taken, d = state('d'), drawn = drawn, quiet = quiet },
		{ name = 'd.txt', listed = true, taken = false, d = { taken = false, listed = true }, drawn = { current = true, visiting = false },
			quiet = { errors = 0, dumps = 0 } })
end

T['T799 [char] (M16) a step onto a closed file of the order borrows it, and a cancel puts it back'] = function()
	local win = shown_with_closed('b')
	step_to('b.txt')
	local at, b = showing(), state('b')
	local bufnr = child.lua('return vim.api.nvim_get_current_buf()')
	child.steps({ LIST })
	child.settle(100)
	local after = child.lua('local b = ...; return { valid = vim.api.nvim_buf_is_valid(b), loaded = vim.api.nvim_buf_is_loaded(b), listed = vim.bo[b].buflisted }', { bufnr })
	eq({ name = at.name, listed = at.listed, taken = at.taken, b = b, back = child.shown(win), after = after },
		{ name = 'b.txt', listed = true, taken = false, b = { taken = false, listed = true }, back = 'e',
			after = { valid = true, loaded = false, listed = false } })
end

T['T800 [char] (M16) a borrowed file you edit stays open'] = function()
	shown_with_closed('b')
	step_to('b.txt')
	local bufnr = child.lua('vim.api.nvim_buf_set_lines(0, -1, -1, false, { "added" }); return vim.api.nvim_get_current_buf()')
	child.messages()
	child.steps({ LIST })
	child.settle(100)
	local b = child.lua('local b = ...; return { listed = vim.bo[b].buflisted, kept = vim.tbl_contains(vim.api.nvim_buf_get_lines(b, 0, -1, false), "added") }', { bufnr })
	local told = #vim.tbl_filter(function(m) return m:find('b.txt was edited while the snapshot showed it', 1, true) ~= nil end, said())
	eq({ b = state('b'), buffer = b, told = told }, { b = { taken = true, listed = false }, buffer = { listed = true, kept = true }, told = 1 })
end

T['T801 [char] (M16) <M-v> on a borrowed file reopens it for real'] = function()
	local win = shown_with_closed('b')
	step_to('b.txt')
	child.steps({ '<M-v>' })
	child.settle(100)
	eq({ b = state('b'), current = child.slots(win):match('%[(%a)%]') }, { b = { taken = true, listed = false }, current = 'b' })
end

-- :e a, a No Name text holding draft, a snapshot of it, :e b, and the text wiped onto the list.
local function text_closed()
	child.steps({ ':e a' })
	local n = S2.noname(child, { 'draft' })
	child.steps({ TAKE, ':e b' })
	child.cmd('bwipeout! ' .. n)
	child.settle(100)
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
end

T['T802 [char] (M16, M5) a closed No Name text is borrowed from its text'] = function()
	text_closed()
	local at = showing()
	eq({ lines = at.lines, listed = at.listed, taken = at.taken, on_list = texts_on_list() },
		{ lines = { 'draft' }, listed = true, taken = false, on_list = 1 })
end

T['T803 [char] (M16, M5) a borrowed No Name text you edit comes back holding what you typed'] = function()
	text_closed()
	child.lua('vim.api.nvim_buf_set_lines(0, -1, -1, false, { "added" })')
	child.steps({ LIST })
	child.settle(100)
	local back = child.lua([[
		local H = require('frogman.domains.history')
		for b, _ in pairs(H.data.hash_buffer_registry.hashes) do
			if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == '' then
				return vim.api.nvim_buf_get_lines(b, 0, -1, false)
			end
		end
		return vim.NIL
	]])
	eq({ back = back, on_list = texts_on_list(), holding = S2.holding(child, 'draft') }, { back = { 'draft', 'added' }, on_list = 0, holding = 1 })
end

T['T804 [char] (M16, M5, S1 Load) a No Name text a load left unread is read when the preview steps onto it'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	local n = S2.noname(child, { 'draft' })
	child.cmd('buffer a.txt')
	child.settle()
	child.steps({ TAKE })
	child.cmd('bwipeout! ' .. n)
	child.settle(100)
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a' }, 'a')
	eq(S2.load(child), { true })
	child.settle(300)
	child.messages()
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	step_to('draft')
	local at = showing()
	local lost = #vim.tbl_filter(function(m) return m:find('lost', 1, true) ~= nil end, said())
	eq({ lines = at.lines, listed = at.listed, lost = lost }, { lines = { 'draft' }, listed = true, lost = 0 })
end

T['T805 [char] (M16) a file gone from disk shows as a placeholder, and <M-v> refuses there'] = function()
	local before = #child.dump_files() -- the run's other cases dump into the same folder
	taken()
	child.steps({ ':e a', ':e e' })
	child.cmd('bdelete d.txt')
	child.settle()
	child.lua('os.remove(_G.FRG_TEST.root .. "/d.txt")')
	child.steps({ LIST })
	child.step('<CR>')
	child.messages()
	child.settle(300) -- the UI's ticks draw it
	local quiet = { errors = #vim.tbl_filter(function(m) return m.level == 4 end, child.messages()), dumps = #child.dump_files() - before }
	local at = showing()
	child.steps({ '<M-v>' })
	child.settle()
	local refused = #vim.tbl_filter(function(m) return m:find("d.txt isn't on disk; step onto another file", 1, true) ~= nil end, said())
	local still = child.lua('return require("frogman.domains.snapshots").preview.active()')
	child.steps({ LIST })
	child.settle(100)
	eq({ full = at.full, lines = at.lines, refused = refused, still = still, left = child.lua('return vim.fn.bufnr("frogman://gone/d.txt")'), quiet = quiet },
		{ full = 'frogman://gone/d.txt', lines = { '[This file has been deleted off the disk]' }, refused = 1, still = true, left = -1,
			quiet = { errors = 0, dumps = 0 } })
end

T['T888 [char] (M16) a snapshot that can\'t show leaves the list open'] = function()
	taken()
	child.steps({ ':e a', ':e e', ':e d' })
	child.cmd('setlocal buftype=nofile')
	child.settle(100)
	child.steps({ ':e e' })
	child.messages()
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	local told = #vim.tbl_filter(function(m) return m:find("d.txt can't be shown while another buffer has its name", 1, true) ~= nil end, said())
	eq({ told = told, open = list() ~= vim.NIL }, { told = 1, open = true })
end

T['T889 [char] (M16) a preview whose file can\'t load leaves nothing showing'] = function()
	local before = #child.dump_files()
	taken()
	child.steps({ ':e a', ':e e' })
	child.cmd('bdelete d.txt')
	child.settle()
	child.steps({ LIST })
	child.lua([[
		local bufload = vim.fn.bufload
		_G.FRG_BUFLOAD = bufload
		vim.fn.bufload = function(buf)
			if vim.api.nvim_buf_get_name(buf):match('d%.txt$') then error('E325: ATTENTION, aborted') end
			return bufload(buf)
		end
	]])
	child.step('<CR>')
	child.settle(100)
	child.lua('vim.fn.bufload = _G.FRG_BUFLOAD')
	local active = child.lua('return require("frogman.domains.snapshots").preview.active()')
	child.messages()
	child.steps({ '<M-f>' })
	local refused = #vim.tbl_filter(function(m) return m:find('a snapshot is showing', 1, true) ~= nil end, said())
	eq({ active = active, refused = refused, dumps = #child.dump_files() - before }, { active = false, refused = 0, dumps = 0 })
end

T['T806 [char] (M16, I10) a file whose name an untracked buffer has isn\'t borrowed'] = function()
	taken()
	child.steps({ ':e a', ':e e', ':e d' })
	local nofile = child.lua('return vim.api.nvim_get_current_buf()')
	child.cmd('setlocal buftype=nofile')
	child.settle(100)
	child.steps({ ':e e' })
	child.messages()
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	local told = #vim.tbl_filter(function(m) return m:find("d.txt can't be shown while another buffer has its name", 1, true) ~= nil end, said())
	eq({ told = told, active = child.lua('return require("frogman.domains.snapshots").preview.active()'),
		nofile = child.lua('local b = ...; return vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype', { nofile }) },
		{ told = 1, active = false, nofile = 'nofile' })
end

T['T807 [char] (M16, A2) a window showing something untracked is taken off it and put back'] = function()
	taken()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	local oil = child.lua([[
		local b = vim.api.nvim_create_buf(true, false)
		vim.bo[b].buftype = 'acwrite'
		vim.api.nvim_buf_set_name(b, 'oil://' .. _G.FRG_TEST.root .. '/')
		vim.bo[b].filetype = 'oil'
		vim.api.nvim_win_set_buf(0, b)
		return b
	]])
	child.settle()
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	local during = child.shown(win)
	child.steps({ LIST })
	child.settle(100)
	eq({ during = during, back = child.lua('return vim.api.nvim_win_get_buf(...)', { win }) == oil }, { during = 'd', back = true })
end

T['T808 [char] (M16, A2) a window frogman never took in gets its triquetra at a commit'] = function()
	split_held_over()
	child.cmd('help')
	child.settle()
	local help = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	child.steps({ '<M-v>' })
	child.settle(100)
	eq(child.slots(help), '⦉b⦊ [x] ⟦-⟧')
end

T['T848 [char] (M16, A2) a preview cancelled in a window never taken in puts its buffer back'] = function()
	split_held_over()
	child.cmd('help')
	child.settle()
	local help = child.lua('return vim.api.nvim_get_current_win()')
	local buf = child.lua('return vim.api.nvim_get_current_buf()')
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	child.steps({ LIST })
	child.settle(100)
	eq(child.lua([[
		local w, b = ...
		return { back = vim.api.nvim_win_get_buf(w) == b, crux = require('frogman.domains.window').data.crux[w] == nil }
	]], { help, buf }), { back = true, crux = true })
end

T['T809 [char] (M16) a borrowed file you edit and write stays open'] = function()
	shown_with_closed('b')
	step_to('b.txt')
	child.lua('vim.api.nvim_buf_set_lines(0, -1, -1, false, { "added" })')
	child.cmd('write')
	child.settle(100)
	child.messages()
	child.steps({ LIST })
	child.settle(100)
	local told = #vim.tbl_filter(function(m) return m:find('b.txt was edited while the snapshot showed it', 1, true) ~= nil end, said())
	eq({ b = state('b'), told = told }, { b = { taken = true, listed = false }, told = 1 })
end

T['T810 [char] (M16, M5) <M-v> on a borrowed No Name text reopens it for real'] = function()
	text_closed()
	local dumps = #child.dump_files()
	child.steps({ '<M-v>' })
	child.settle(300)
	local at = showing()
	eq({ lines = at.lines, taken = at.taken, on_list = texts_on_list(), holding = S2.holding(child, 'draft'), dumps = #child.dump_files() - dumps },
		{ lines = { 'draft' }, taken = true, on_list = 0, holding = 1, dumps = 0 })
end

-- Copying between windows (M16, 5e) ---------------------------------------------------------

-- T762's snapshot in window 1 and a vertical split, back in window 1.
local function two_windows()
	taken()
	local one = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.lua('vim.api.nvim_set_current_win(...)', { one })
	child.settle()
	return one, split
end

-- In a window's list: normal-mode keys, then q, which writes an edited list and leaves.
local function in_list(win, keys)
	child.lua('vim.api.nvim_set_current_win(...)', { win })
	child.settle()
	child.steps({ LIST })
	if keys then
		child.lua('vim.cmd("normal! " .. ...)', { keys })
	end
	child.step('q')
	child.settle(100)
end

-- In a window's list: a line put in after its lines, then q.
local function put_line(win, line)
	child.lua('vim.api.nvim_set_current_win(...)', { win })
	child.settle()
	child.steps({ LIST })
	child.lua('vim.api.nvim_buf_set_lines(0, -1, -1, false, { ... })', { line })
	child.step('q')
	child.settle(100)
end

-- Window 1's line for its snapshot, changed in place by `change`, a function body over `d`, the decoded
-- table, and wrapped again with its checksum.
local function changed_line(win, change)
	child.lua('vim.api.nvim_set_current_win(...)', { win })
	child.settle()
	child.steps({ LIST })
	local line = child.lua([[
		local L = require('frogman.domains.snapshots').list
		local d = L.decode(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
		local change = loadstring('local d = ...; ' .. ...)
		change(d)
		return L.wrap(d)
	]], { change })
	child.step('q')
	child.settle(100)
	return line
end

T['T811 [char] (M16) a yanked line pasted into another window\'s list makes a copy'] = function()
	local one, split = two_windows()
	local id = snapshots(one)[1].id
	in_list(one, 'yy')
	in_list(split, 'p')
	local got = snapshots(split)
	eq({ n = #got, other = got[1] and got[1].id ~= id, slots = got[1] and got[1].slots, kept = #snapshots(one), held = got[1] and child.lua(
		'return require("frogman.domains.snapshots").routines.find(...).held == nil', { got[1].id }) },
		{ n = 1, other = true, slots = '⦉c⦊ [d] ⟦b⟧', kept = 1, held = true })
end

T['T812 [char] (M16) a cut line pasted into another window\'s list moves the snapshot'] = function()
	local one, split = two_windows()
	in_list(one, 'dd')
	local left = #snapshots(one)
	in_list(split, 'p')
	local got = snapshots(split)
	eq({ left = left, n = #got, slots = got[1] and got[1].slots }, { left = 0, n = 1, slots = '⦉c⦊ [d] ⟦b⟧' })
end

T['T813 [char] (M16, M5) a cut snapshot comes back without a No Name text only it held'] = function()
	child.steps({ ':e a', ':enew' })
	local n = child.lua('return vim.api.nvim_get_current_buf()')
	child.cmd('buffer a.txt')
	child.settle()
	child.steps({ TAKE, ':e b' })
	local one = child.lua('return vim.api.nvim_get_current_win()')
	local text = child.lua([[
		local S = require('frogman.domains.snapshots').routines
		return S.of_window(vim.api.nvim_get_current_win())[1].ternary
	]])
	child.cmd('bwipeout ' .. n)
	child.settle(100)
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	in_list(one, 'dd')
	child.settle(100) -- the cut's let-go runs once the editor settles
	in_list(split, 'p')
	local got = child.lua([[
		local S = require('frogman.domains.snapshots').routines
		local s = S.of_window(...)[1]
		return { n = #S.of_window(...), ternary = s and s.ternary or false }
	]], { split })
	eq({ got = got, gone = child.lua('return require("frogman.domains.history").handles.get(...) == nil', { text }) },
		{ got = { n = 1, ternary = false }, gone = true })
end

T['T814 [char] (M16) a line another editor drew is rebuilt by its paths'] = function()
	local one, split = two_windows()
	local line = changed_line(one, 'd.editor = "another editor"; d.id = "elsewhere"; for i, f in ipairs(d.files) do f.handle = 90000 + i end')
	put_line(split, line)
	local got = snapshots(split)
	eq({ n = #got, slots = got[1] and got[1].slots }, { n = 1, slots = '⦉c⦊ [d] ⟦b⟧' })
end

T['T815 [char] (M16) a rebuilt snapshot whose current is dropped falls to its ternary'] = function()
	local one, split = two_windows()
	local line = changed_line(one, 'table.insert(d.files, { path = "NONAME_1", handle = 99999 }); d.c = #d.files; d.id = "elsewhere"')
	put_line(split, line)
	local got = snapshots(split)
	eq({ n = #got, slots = got[1] and got[1].slots }, { n = 1, slots = '⦉-⦊ [c] ⟦b⟧' })
end

T['T816 [char] (M16) a line that doesn\'t open is asked about'] = function()
	local one, split = two_windows()
	local line = changed_line(one, 'd.id = "elsewhere"')
	line = line:sub(1, 20) .. (line:sub(21, 21) == 'A' and 'B' or 'A') .. line:sub(22) -- a byte of the seal
	child.lua('vim.api.nvim_set_current_win(...)', { split })
	child.settle()
	child.steps({ LIST })
	child.lua('vim.api.nvim_buf_set_lines(0, -1, -1, false, { ... })', { line })
	child.answer('Yes')
	child.cmd('silent! write')
	child.settle(100)
	local asked = child.prompts()
	child.step('q')
	child.settle(100)
	eq({ asked = #asked, names = asked[1] and asked[1]:find('names no snapshot', 1, true) ~= nil, n = #snapshots(split) },
		{ asked = 1, names = true, n = 0 })
end

T['T817 [char] (M16) a second line naming a snapshot the list keeps makes a copy'] = function()
	taken()
	local id = snapshots()[1].id
	in_list(child.lua('return vim.api.nvim_get_current_win()'), 'yyp')
	local got = snapshots()
	eq({ n = #got, ids = got[1] and got[2] and got[1].id ~= got[2].id, first = got[1] and got[1].id == id, slots = got[2] and got[2].slots },
		{ n = 2, ids = true, first = true, slots = '⦉c⦊ [d] ⟦b⟧' })
end

T['T818 [char] (M16) a list whose window is gone isn\'t written'] = function()
	local one, split = two_windows()
	child.steps({ LIST })
	local float = child.lua('return vim.api.nvim_get_current_win()')
	child.lua('vim.api.nvim_set_current_win(...)', { split })
	child.lua('vim.api.nvim_win_close(..., true)', { one })
	child.settle(100)
	child.lua('vim.api.nvim_set_current_win(...)', { float })
	child.settle()
	child.messages()
	child.lua('vim.cmd("normal! yyp")')
	child.cmd('silent! write')
	child.settle(100)
	local told = #vim.tbl_filter(function(m) return m:find("the window this list was for is gone, so it isn't written", 1, true) ~= nil end, said())
	eq({ told = told, modified = list().modified, kept = child.lua('return require("frogman.domains.snapshots").data.by_window[...] ~= nil', { one }) },
		{ told = 1, modified = true, kept = false })
end

-- The pile and review round 5: real headers, sealed lines, the window picker (M16, 2026-11-03) ------

-- Keys typed one group at a time, the editor settling between, as typing does.
local function keys(...)
	for _, k in ipairs({ ... }) do
		child.type_keys(k)
		child.settle()
	end
end

-- The open list's lines.
local function list_lines()
	return child.lua('return vim.api.nvim_buf_get_lines(vim.fn.bufnr("frogman://snapshots"), 0, -1, false)')
end

T['T833 [char] (M16, DESK.md:1941) a held-over header is a line the list keeps, a pasted copy of it staying'] = function()
	split_held_over()
	child.steps({ LIST })
	local drawn = list_lines()
	local h = held('')
	local got = { header = h[1] ~= nil and drawn[1] == h[1].held, under = decoded_ids()[2] == (h[1] and h[1].id) }
	for _, change in ipairs({ { 'delete', 'gg', 'dd' }, { 'clear', 'gg', 'S', '<Esc>' } }) do
		keys(unpack(change, 2))
		got[change[1]] = vim.deep_equal(list_lines(), drawn)
	end
	keys('gg', 'yy', 'p')
	local pasted = vim.deepcopy(drawn)
	table.insert(pasted, 2, drawn[1])
	got.paste = vim.deep_equal(list_lines(), pasted)
	eq(got, { header = true, under = true, delete = true, clear = true, paste = true })
end

T['T834 [char] (M16) a held-over line moved up among the window\'s own makes it the window\'s'] = function()
	split_held_over()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	local id = held('')[1].id
	child.steps({ LIST })
	keys('G', 'dd', 'gg', 'P')
	child.step('q')
	child.settle(100)
	local got = snapshots(win)
	eq({ n = #got, slots = got[1] and got[1].slots, other = got[1] and got[1].id ~= id, held = #held('') },
		{ n = 1, slots = '⦉b⦊ [x] ⟦-⟧', other = true, held = 1 })
end

-- The same snapshot as window `win`'s first line, sealed as an editor started in `dir` draws it, under a
-- salt of its own: a line from another project.
local function line_from(win, dir, id)
	local line = changed_line(win, 'd.id = "' .. id .. '"')
	return child.lua([[
		local line, dir = ...
		local d = require('frogman.domains.snapshots').list.decode(line)
		local crypto = require('frogman.domains.storage.crypto')
		local storage = require('frogman.domains.storage.routines')
		local salt = crypto.random_bytes(crypto.salt_length)
		return 'fs1:' .. vim.base64.encode(storage.sealed(storage.key_for(dir, salt), salt, vim.json.encode(d), 'snapshot'))
	]], { line, dir })
end

-- Lines put in a window's list and written, the directory questions answered from `replies`; what was asked.
local function written_with(win, lines, replies)
	child.lua('vim.api.nvim_set_current_win(...)', { win })
	child.settle()
	child.steps({ LIST })
	child.lua('_G.FRG_REPLIES, _G.FRG_ASKED = ..., {}', { replies })
	child.lua('vim.api.nvim_buf_set_lines(0, -1, -1, false, ...)', { lines })
	child.answer('Yes')
	child.cmd('silent! write')
	child.settle(100)
	local asked = { input = child.lua('return _G.FRG_ASKED'), confirm = child.prompts() }
	child.step('q')
	child.settle(100)
	return asked
end

T['T835 [char] (M16, P22) a line is sealed'] = function()
	local one, split = two_windows()
	child.steps({ LIST })
	local line = child.lua('return vim.api.nvim_get_current_line()')
	child.step('q')
	child.settle(100)
	local body = line:match('^fs1:([%w%+/=]+)') or ''
	local plain = child.lua('local ok, b = pcall(vim.base64.decode, ...); return ok and b or ""', { body })
	local named = 0
	for _, f in ipairs({ 'a.txt', 'b.txt', 'c.txt', 'd.txt' }) do
		named = named + (plain:find(f, 1, true) and 1 or 0)
	end
	local asked = written_with(split, { line_from(one, '/elsewhere/project', 'elsewhere') }, {})
	eq({ named = named, input = #asked.input, confirm = #asked.confirm, n = #snapshots(split) }, { named = 0, input = 1, confirm = 1, n = 0 })
end

T['T855 [char] (M16) a line a change of cwd left behind still opens'] = function()
	local one, split = two_windows()
	child.steps({ LIST })
	local line = child.lua('return vim.api.nvim_get_current_line()')
	child.step('q')
	child.settle(100)
	child.lua('vim.fn.mkdir("sub", "p")')
	child.cmd('cd sub')
	child.settle()
	local asked = written_with(split, { line }, {})
	local got = snapshots(split)
	eq({ input = #asked.input, confirm = #asked.confirm, n = #got, slots = got[1] and got[1].slots },
		{ input = 0, confirm = 0, n = 1, slots = '⦉c⦊ [d] ⟦b⟧' })
end

T['T857 [char] (M16) another editor\'s line is tried under the cwd alone'] = function()
	local one = two_windows()
	local foreign = line_from(one, '/elsewhere/project', 'elsewhere')
	for _, dir in ipairs({ 'sub1', 'sub2' }) do
		child.lua('vim.fn.mkdir(..., "p")', { dir })
		child.cmd('cd ' .. dir)
		child.settle()
		child.lua('vim.api.nvim_set_current_win(...)', { one })
		child.steps({ LIST }) -- draws its lines under this directory
		child.step('q')
		child.settle(100)
	end
	local stretched = child.lua([[
		local crypto = require('frogman.domains.storage.crypto')
		local derive, n = crypto.derive_key, 0
		crypto.derive_key = function(...) n = n + 1; return derive(...) end
		require('frogman.domains.snapshots').list.decode(...)
		crypto.derive_key = derive
		return n
	]], { foreign })
	eq(stretched, 1)
end

T['T856 [char] (M16) the write asks for the directory again while lines are still shut'] = function()
	local one, split = two_windows()
	local first, second = line_from(one, '/elsewhere/first', 'first'), line_from(one, '/elsewhere/second', 'second')
	local asked = written_with(split, { first, second }, { '/elsewhere/first', '/elsewhere/second' })
	eq({ input = #asked.input, again = asked.input[2] ~= nil and asked.input[2]:find('1 snapshot line', 1, true) ~= nil,
		confirm = #asked.confirm, n = #snapshots(split) }, { input = 2, again = true, confirm = 0, n = 2 })
end

-- T818's route to window 1's list with window 1 gone, the list focused again.
local function list_without_its_window()
	local one, split = two_windows()
	child.steps({ LIST })
	local float = child.lua('return vim.api.nvim_get_current_win()')
	child.lua('vim.api.nvim_set_current_win(...)', { split })
	child.lua('vim.api.nvim_win_close(..., true)', { one })
	child.settle(100)
	child.lua('vim.api.nvim_set_current_win(...)', { float })
	child.settle()
	child.messages()
	return split, float
end

T['T836 [char] (M16) <CR> with the list\'s window gone opens the window picker'] = function()
	local split = list_without_its_window()
	child.lua([[
		package.loaded['window-picker'] = nil
		package.preload['window-picker'] = function()
			return { pick_window = function() _G.FRG_PICKED = (_G.FRG_PICKED or 0) + 1; return _G.FRG_PICK end }
		end
	]])
	child.step('<CR>')
	child.settle(100)
	local nothing = { asked = child.lua('return _G.FRG_PICKED or 0'), open = list() ~= vim.NIL }
	child.lua('_G.FRG_PICK = ...', { split })
	child.step('<CR>')
	child.settle(100)
	local told = #vim.tbl_filter(function(m)
		return m:find('the window this list was for is gone; pick a window to show the snapshot in.', 1, true) ~= nil
	end, said())
	eq({ nothing = nothing, told = told, shows = child.lua('return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(...)), ":t")', { split }),
		open = list() ~= vim.NIL }, { nothing = { asked = 1, open = true }, told = 2, shows = 'd.txt', open = false })
end

T['T837 [char] (M16) with nvim-window-picker not installed, <CR> with the list\'s window gone says so'] = function()
	list_without_its_window()
	child.lua("package.loaded['window-picker'] = nil; package.preload['window-picker'] = nil")
	child.step('<CR>')
	child.settle(100)
	local told = #vim.tbl_filter(function(m) return m:find('nvim-window-picker', 1, true) ~= nil end, said())
	eq({ told = told, open = list() ~= vim.NIL }, { told = 1, open = true })
end

T['T847 [char] (M16, A26) a window picker that raises leaves the list open'] = function()
	list_without_its_window()
	child.lua([[
		package.loaded['window-picker'] = nil
		package.preload['window-picker'] = function() return { pick_window = function() error('boom') end } end
	]])
	local before = child.dump_files()
	child.step('<CR>')
	child.settle(100)
	local told = #vim.tbl_filter(function(m) return m:find("nvim-window-picker's picker failed", 1, true) ~= nil end, said())
	eq({ told = told, dumped = child.dumped_since(before), open = list() ~= vim.NIL }, { told = 1, open = true })
end

T['T854 [char] (M15, M16) a tab that outlived a refused close isn\'t taken for a tab session\'s at its next'] = function()
	local s = S2.shared()
	tab_session(s)
	eq(S2.save(child), { true }) -- the whole editor's file, before t moves
	child.lua('vim.o.hidden = false')
	child.cmd('enew')
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })')
	eq(child.lua('return (pcall(vim.cmd, "tabclose"))'), false)
	child.settle()
	-- the edit let go without wiping its buffer, which would close the tab's only window and the tab with it
	child.lua('vim.bo.modified = false; vim.cmd("edit d.txt"); vim.o.hidden = true')
	child.settle()
	eq(S2.load_tab_session(child, 't'), { true }) -- the second tab keeps t_DETACHED
	child.cmd('tabnext 2')
	child.settle()
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', TAKE, ':e d' })
	child.cmd('tabclose')
	child.settle(500)
	eq(child.lua([[
		local saved = require('frogman.domains.storage.routines').read_session(vim.fn.getcwd(-1, -1), nil)
		for _, l in ipairs(saved.detached or {}) do
			if l.label == 't_DETACHED' then return #(l.snapshots or {}) end
		end
		return -1
	]]), 1)
end

T['T865 [char] (M16) a window that keeps its buffer can\'t show a snapshot'] = function()
	taken()
	child.steps({ ':e a' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.lua('vim.wo.winfixbuf = true')
	child.steps({ LIST })
	child.messages()
	child.step('<CR>')
	child.settle(100)
	local told = #vim.tbl_filter(function(m) return m:find("keeps its buffer ('winfixbuf')", 1, true) ~= nil end, said())
	eq({ told = told, showing = child.lua('return require("frogman.domains.snapshots.preview").active()'), open = list() ~= vim.NIL,
		shows = child.lua('return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(...)), ":t")', { win }) },
		{ told = 1, showing = false, open = true, shows = 'a.txt' })
end

T['T868 [char] (M16) the list reads the marks once a drawing'] = function()
	taken()
	child.steps({ ':e e', TAKE, LIST })
	local asked = child.lua([[
		local R = require('frogman.domains.marks.routines')
		local scope_key, n = R.scope_key, 0
		R.scope_key = function(...) n = n + 1; return scope_key(...) end
		vim.api.nvim_exec_autocmds('TextChanged', { buffer = vim.api.nvim_get_current_buf() })
		R.scope_key = scope_key
		return n
	]])
	eq(asked, 1)
end

T['T879 [char] (M16) the list seals a line once while it\'s open'] = function()
	taken()
	child.steps({ ':e e', TAKE, LIST })
	local sealed = child.lua([[
		local S = require('frogman.domains.storage.routines')
		local sealed_fn, n = S.sealed, 0
		S.sealed = function(...) n = n + 1; return sealed_fn(...) end
		vim.bo.modified = true
		vim.cmd('silent! write')
		S.sealed = sealed_fn
		return n
	]])
	eq(sealed, 0)
end

T['T874 [char] (M16) the list\'s write keeps a snapshot it didn\'t draw'] = function()
	taken()
	child.steps({ LIST })
	local second = child.lua([[
		local origin = require('frogman.domains.snapshots').list.origin()
		local R = require('frogman.domains.snapshots').routines
		vim.api.nvim_win_call(origin, function() R.take(origin) end)
		local own = R.of_window(origin)
		return own[#own].id
	]])
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, {})')
	child.cmd('silent! write')
	child.settle(100)
	local left = child.lua([[
		local origin = require('frogman.domains.snapshots').list.origin()
		return vim.tbl_map(function(s) return s.id end, require('frogman.domains.snapshots').routines.of_window(origin))
	]])
	eq(left, { second })
end

T['T869 [char] (M16) an answered directory lasts while its list is open'] = function()
	local one, split = two_windows()
	local first = written_with(split, { line_from(one, '/elsewhere/project', 'first') }, { '/elsewhere/project' })
	local again = written_with(split, { line_from(one, '/elsewhere/project', 'second') }, {})
	eq({ first = #first.input, again = #again.input }, { first = 1, again = 1 })
end

T['T859 [char] (M16, S1 Load) an entry\'s snapshot held over at a load isn\'t held over again at the next'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.cmd('tabnew')
	child.settle()
	child.steps({ ':e c', TAKE })
	child.cmd('split')
	child.settle()
	child.steps({ ':e d', TAKE })
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e x' })
	eq(S2.load_tab_session(child, 't'), { true }) -- a tab on d: the d entry taken, the c entry's held over
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local first = #held(id)
	eq(S2.load_tab_session(child, 't'), { true }) -- again, t open now
	eq({ first = first, again = #held(id) }, { first = 1, again = 1 })
end

T['T838 [char] (M16, M5) a detached list\'s tab closing writes the snapshots its closed windows held over'] = function()
	local s = S2.shared()
	tab_session(s)
	eq(S2.save(child), { true }) -- the whole editor's file, before t moves
	eq(S2.load_tab_session(child, 't'), { true }) -- the second tab keeps t_DETACHED
	child.cmd('tabnext 2')
	child.settle()
	child.steps({ ':e e', ':e d' })
	child.cmd('bdelete e.txt') -- e on the list, so the list goes into the file with what it holds
	child.settle()
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', TAKE, ':e d' })
	child.cmd('tabclose')
	child.settle(500)
	local got = child.lua([[
		local saved = require('frogman.domains.storage.routines').read_session(vim.fn.getcwd(-1, -1), nil)
		local on_entry = -1
		for _, l in ipairs(saved.detached or {}) do
			if l.label == 't_DETACHED' then on_entry = #(l.snapshots or {}) end
		end
		local D = require('frogman.domains.snapshots').data
		local held, own = 0, 0
		for _, list in pairs(D.held) do held = held + #list end
		for _, list in pairs(D.by_window) do own = own + #list end
		return { on_entry = on_entry, held = held, own = own, pending = #D.pending }
	]])
	eq(got, { on_entry = 1, held = 0, own = 0, pending = 0 })
end

-- The holders, one question asked one way (M2 Holders, review round 5's #2, #11, #16) ----------

T['T819 [char] (M16, S2 Closed-stack picker) the closed lists keep a text a snapshot holds'] = function()
	child.steps({ ':e a' })
	local n = S2.noname(child, { 'kept' })
	child.steps({ TAKE, ':e b' })
	child.cmd('bdelete! ' .. n)
	child.settle()
	child.answer('Keep')
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, S2.line_of(lines, '[No Name]'))
	S2.write_picker(child, p, lines)
	child.cmd('close')
	child.settle(100)
	local asked, on_list = #child.prompts(), texts_on_list()
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	eq({ asked = asked, on_list = on_list, shown = showing().lines }, { asked = 0, on_list = 0, shown = { 'kept' } })
end

T['T820 [char] (M2 Holders, M16) a path no holder takes is forgotten once the editor settles'] = function()
	local one, split = two_windows()
	local line = changed_line(one, [[d.editor = "another editor"; d.id = "elsewhere"
		for i, f in ipairs(d.files) do f.handle = 90000 + i end
		table.insert(d.files, { path = _G.FRG_TEST.root .. "/q.txt", handle = 99998 })
		table.insert(d.dtm, { d.c, #d.files, 0 })]])
	put_line(split, line)
	child.settle(100)
	eq({ n = #snapshots(split), q = child.lua([[
		local H = require('frogman.domains.history')
		return H.data.hash_filepath_registry.filepaths[H.routines.get_filehash(_G.FRG_TEST.root .. '/q.txt')] ~= nil
	]]) }, { n = 1, q = false })
end

T['T933 [char] (M16, DESK.md:754) a snapshot\'s notes let go of a file as it is let go'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.notes(), 'dtm{b>a} dsm{}')
	-- a closed first, so the order the snapshot keeps, the bufferline's, leaves it out: its notes alone name a
	child.cmd('bdelete a.txt')
	child.settle()
	child.steps({ TAKE })
	local a = child.lua('return require("frogman.domains.history").get_handle_from_filepath(_G.FRG_TEST.root .. "/a.txt")')
	local function naming()
		return child.lua([[
			local id, n = ..., 0
			for _, s in ipairs(require('frogman.domains.snapshots').routines.of_window(vim.api.nvim_get_current_win())) do
				for _, notes in ipairs({ s.dtm, s.dsm }) do
					for _, note in ipairs(notes) do
						if note.key == id or note.value == id then n = n + 1 end
					end
				end
			end
			return n
		]], { a })
	end
	local before = naming()
	local p = S2.picker(child)
	local lines = vim.deepcopy(p.lines)
	table.remove(lines, S2.line_of(lines, 'a.txt'))
	S2.write_picker(child, p, lines)
	child.cmd('close')
	child.settle(100)
	local let_go = child.lua('return require("frogman.domains.history").handles.get(...) == nil', { a })
	eq({ before = before, let_go = let_go, after = naming() }, { before = 1, let_go = true, after = 0 })
end

T['T884 [char] (M15, M16, DESK.md:1208) a window gone without its WinClosed in a tab session\'s tab is held over in that session\'s scope, under what it showed'] = function()
	local s = S2.shared()
	eq(S2.save_tab_session(child, s, 't'), { true })
	S2.start(child, s)
	child.steps({ ':e x', ':e t' })
	eq(S2.load_tab_session(child, 't'), { true })
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', "<M-'><M-'><M-a>", TAKE })
	child.cmd('noautocmd close')
	child.settle()
	child.lua('require("frogman.domains.history").routines.cleanup_system()')
	child.settle(100)
	eq(child.lua([[
		local id = ...
		local Mk, Sn = require('frogman.domains.marks'), require('frogman.domains.snapshots')
		local function groups(of)
			local n = 0
			for _, g in ipairs((Mk.data.scopes.session[of] or { groups = {} }).groups) do
				if g.held and g.name:match('^held over · window on c%.txt · ') then n = n + 1 end
			end
			return n
		end
		return { t = { groups = groups(id), snapshots = #Sn.routines.held_in(id) },
			editor = { groups = groups(''), snapshots = #Sn.routines.held_in('') } }
	]], { id }), { t = { groups = 1, snapshots = 1 }, editor = { groups = 0, snapshots = 0 } })
end

T['T821 [char] (M15, M16, DESK.md:1208) a window closed without its WinClosed has its marks and snapshots held over at the next cleanup pass, under what it showed'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', "<M-'><M-'><M-a>", TAKE })
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('noautocmd close')
	child.settle()
	child.lua('require("frogman.domains.history").routines.cleanup_system()')
	child.settle(100)
	eq(child.lua([[
		local split = ...
		local Mk, Sn = require('frogman.domains.marks'), require('frogman.domains.snapshots')
		local groups = (Mk.data.scopes.session[''] or { groups = {} }).groups
		local held_group = false
		for _, g in ipairs(groups) do
			if g.held and g.name:match('^held over · window on c%.txt · ') then held_group = true end
		end
		local held_snap = false
		for _, s in ipairs(Sn.routines.held_in('')) do
			if s.held:match('^held over · window on c%.txt · ') then held_snap = true end
		end
		return { marks = Mk.data.scopes.window[split] ~= nil, snaps = Sn.data.by_window[split] ~= nil, held_group = held_group, held_snap = held_snap }
	]], { split }), { marks = false, snaps = false, held_group = true, held_snap = true })
end

T['T831 [char] (M16, S1 Records) a held-over snapshot you delete stays deleted'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e d', ':e c', TAKE })
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	local before = #held('')
	child.steps({ LIST })
	child.lua([[
		local lines = vim.tbl_filter(function(l) return not l:match('^fs1:') end, vim.api.nvim_buf_get_lines(0, 0, -1, false))
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	]])
	child.step('q')
	child.settle(100)
	S2.start(child, s) -- the quit writes the records
	Misc.restore(child, { 'a', 'b' }, 'b')
	eq(S2.load(child), { true })
	child.settle(300)
	eq({ before = before, after = #held('') }, { before = 1, after = 0 })
end

-- Pile rounds 2 and 3: a tab session's load, and a detached list's copies (M16, 2026-11-03) ----------

-- A window's marks in its first group, alias -> file stem.
local function window_marks(win)
	return child.lua([[
		local M = require('frogman.domains.marks')
		local H = require('frogman.domains.history')
		local scope = M.data.scopes.window[...]
		local out = {}
		for alias, hid in pairs(scope and scope.groups[1] and scope.groups[1].marks or {}) do
			local h = H.handles.get(H.handles.resolve(hid))
			out[alias] = h and vim.fn.fnamemodify(H.get_filepath_from_hash(h.hash), ':t:r') or false
		end
		return out
	]], { win })
end


-- A window's groups: each one's name, whether it's held over, and its marks by file name.
local function window_groups(win)
	return child.lua([[
		local d = require('frogman.domains.marks').data
		local H = require('frogman.domains.history')
		local s = d.scopes.window[...]
		local out = {}
		for _, g in ipairs(s and s.groups or {}) do
			local marks = {}
			for alias, hid in pairs(g.marks) do
				local h = H.handles.get(H.handles.resolve(hid))
				marks[alias] = h and vim.fn.fnamemodify(H.get_filepath_from_hash(h.hash), ':t:r') or false
			end
			table.insert(out, { name = g.name, held = g.held == true, marks = marks })
		end
		return out
	]], { win })
end

T['T881 [char] (M15, S1 Load) a load under the pop-up\'s edits keeps both'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e c', "<M-'><M-'><M-s>", ':e a', TAKE })
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e b', "<M-'><M-'><M-a>", ':e a' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ "<M-'><M-e>" })
	child.lua('vim.api.nvim_buf_set_lines((require("frogman.domains.marks.popup").buffer() or -1), 0, -1, false, { "❖ main", "a -> b.txt", "d -> d.txt" })')
	child.lua('vim.api.nvim_set_current_win(...)', { win })
	child.settle()
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	child.lua('vim.api.nvim_set_current_win((require("frogman.domains.marks.popup").window() or -1))')
	child.cmd('silent! write')
	child.settle(100)
	local groups = window_groups(win)
	eq({ n = #groups, first = groups[1] and groups[1].marks, held = groups[2] and groups[2].held, marks = groups[2] and groups[2].marks,
		load = groups[2] and groups[2].name:find('t, loaded into tab 1', 1, true) ~= nil },
		{ n = 2, first = { a = 'b', d = 'd' }, held = true, marks = { s = 'c' }, load = true })
end

T['T827 [char] (M15, M16, S1 Load) a tab session\'s load holds a matched window\'s own marks and snapshots over'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e c', "<M-'><M-'><M-s>", ':e a', TAKE })
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	S2.start(child, s)
	child.steps({ ':e b', "<M-'><M-'><M-a>", ':e a', TAKE })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	eq(child.lua('return { pcall(require("frogman").load_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.settle(300)
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local groups = child.lua([[
		local d = require('frogman.domains.marks').data
		local H = require('frogman.domains.history')
		local out = {}
		for _, g in ipairs((d.scopes.session[...] or { groups = {} }).groups) do
			if g.held then
				local marks = {}
				for alias, hid in pairs(g.marks) do
					local h = H.handles.get(H.handles.resolve(hid))
					marks[alias] = h and vim.fn.fnamemodify(H.get_filepath_from_hash(h.hash), ':t:r') or false
				end
				table.insert(out, { marks = marks, load = g.name:find('t, loaded into tab 1', 1, true) ~= nil })
			end
		end
		return out
	]], { id })
	local h = held(id)
	eq({ marks = window_marks(win), own = #snapshots(win), groups = groups, held = #h,
		snap_load = h[1] and h[1].held:find('t, loaded into tab 1', 1, true) ~= nil },
		{ marks = { s = 'c' }, own = 1, groups = { { marks = { a = 'b' }, load = true } }, held = 1, snap_load = true })
end

-- T318's state, then in t's tab a split's snapshot held over as the split closes.
local function held_in_t(s)
	tab_session(s)
	child.cmd('split')
	child.settle()
	child.steps({ ':e c', TAKE, ':e d' })
	child.cmd('close')
	child.settle(300)
	return child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
end

T['T828 [char] (M16, M5) a detached list takes a copy of its session\'s held-over snapshots'] = function()
	local s = S2.shared()
	local t = held_in_t(s)
	local first = held(t)[1].id
	eq(S2.load_tab_session(child, 't'), { true })
	child.cmd('tabnext 2')
	child.settle()
	local detached = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	local copy = held(detached)
	child.steps({ LIST })
	local listed = snapshot_lines()
	eq({ detached = detached:match('DETACHED') ~= nil, copies = #copy, other = copy[1] and copy[1].id ~= first, t = #held(t),
		kept = held(t)[1] and held(t)[1].id == first, listed = listed },
		{ detached = true, copies = 1, other = true, t = 1, kept = true, listed = 1 })
end

T['T829 [char] (M16, S1) the detached list\'s held-over snapshots ride its entry'] = function()
	local s = S2.shared()
	held_in_t(s)
	eq(S2.save(child), { true }) -- the whole editor's file, before t moves
	eq(S2.load_tab_session(child, 't'), { true })
	eq(S2.save(child), { true })
	local on_entry = child.lua([[
		local saved = require('frogman.domains.storage.routines').read_session(vim.fn.getcwd(-1, -1), nil)
		for _, l in ipairs(saved.detached or {}) do
			if l.label == 't_DETACHED' then return #(l.snapshots or {}) end
		end
		return -1
	]])
	S2.start(child, s)
	S2.restore_tabs(child, { { files = { 'x', 't' }, shown = 't' }, { files = { 'c', 'd' }, shown = 'd' }, { files = { 'c', 'd' }, shown = 'd' } })
	eq(S2.load(child), { true })
	child.settle(300)
	child.cmd('tabnext 2')
	child.settle()
	local detached = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()] or ""')
	eq({ on_entry = on_entry, detached = detached:match('DETACHED') ~= nil, back = #held(detached) }, { on_entry = 1, detached = true, back = 1 })
end

-- b.txt moved over a.txt, a.txt's buffer wiped first, as T783 moves it
local function b_over_a()
	child.cmd('bwipeout a.txt')
	child.settle()
	child.lua([[
		local root = _G.FRG_TEST.root
		os.rename(root .. '/b.txt', root .. '/a.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/b.txt'), root .. '/a.txt')
	]])
	child.settle(300)
end

T['T902 [char] (M16, A20, DESK.md:1956) a rename onto a name a snapshot holds applies the live slots\' rule as it settles'] = function()
	child.steps({ ':e a', ':e b', '<M-f>', ':e a', TAKE, ':e c' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	b_over_a()
	local held = snapshots(win)[1]
	local saved = child.lua([[
		local s = require('frogman.domains.snapshots').routines.serialise_window(...)[1]
		return { current = s.current ~= nil, secondary = s.secondary or false, order = #s.order }
	]], { win })
	local cleared = child.lua([[
		for _, step in ipairs(require('frogman').ledger.trail()) do
			for _, m in ipairs(step.moves) do
				if m.kind == 'cleared' and m.name == 'a.txt' then return step.trigger end
			end
		end
		return false
	]])
	eq({ slots = held.slots, order = held.order, saved = saved, cleared = cleared ~= false },
		{ slots = '⦉-⦊ [a] ⟦-⟧', order = 'a', saved = { current = true, secondary = false, order = 1 }, cleared = true })
end

T['T903 [char] (M16, A20, DESK.md:1956) where the current doesn\'t hold the file, the slot the moved file was in keeps it'] = function()
	child.steps({ ':e a', ':e x', '<M-f>', ':e b', ':e x' })
	eq(child.slots(), '⦉b⦊ [x] ⟦a⟧')
	child.steps({ TAKE })
	b_over_a()
	eq(snapshots()[1].slots, '⦉a⦊ [x] ⟦-⟧')
end

T['T904 [char] (M16, S1 Load, DESK.md:1956) a saved snapshot holding one file twice gets the rule at its next load'] = function()
	local got = {}
	for _, twice in ipairs({ 'ternary', 'secondary' }) do
		local s = S2.shared()
		S2.start(child, s)
		child.steps({ ':e b', ':e a', '<M-f>', ':e c', ':e a' })
		eq(child.slots(), '⦉c⦊ [a] ⟦b⟧')
		child.steps({ TAKE })
		eq(S2.save(child), { true })
		S2.start(child, s)
		-- sealed again by hand: the ternary holds the secondary's file too, or the secondary the current's
		child.lua([[
			local twice = ...
			local crypto = require('frogman.domains.storage.crypto')
			local dir = vim.fn.getcwd(-1, -1)
			local path = require('frogman.configs').session_dir .. vim.fn.sha256(dir) -- a nameless save's file
			local fh = assert(io.open(path, 'rb')); local bytes = fh:read('*a'); fh:close()
			local salt = bytes:sub(5, 4 + crypto.salt_length)
			local data = require('frogman.domains.storage.routines').read_session(dir, nil)
			local snapshot = data.windows[1][11][1]
			if twice == 'ternary' then snapshot.ternary = snapshot.secondary else snapshot.secondary = snapshot.current end
			local header = "CDV1" .. salt
			local out = header .. crypto.seal(crypto.derive_key(dir, salt), vim.json.encode(data), header)
			fh = assert(io.open(path, 'wb')); fh:write(out); fh:close()
		]], { twice })
		Misc.restore(child, { 'a', 'b', 'c' }, 'a')
		eq(S2.load(child), { true })
		child.settle(300)
		got[twice] = snapshots()[1].slots
	end
	eq(got, { ternary = '⦉-⦊ [a] ⟦b⟧', secondary = '⦉c⦊ [a] ⟦-⟧' })
end

-- R9s: a snapshot taken in a tab session's tab after its last save, the tab closed with nothing saving at
-- the close: it goes onto its window's entry in t's file, and the next load gives it back to the window.
T['T1059 [char] (M16, DESK.md:1938, repro R9s) a snapshot taken after a tab session\'s last save comes back after its tab closes'] = function()
	local s = S2.shared()
	tab_session(s)
	local id = child.lua('return require("frogman.domains.history").data.tab_pools[vim.api.nvim_get_current_tabpage()]')
	eq(child.lua('return { pcall(require("frogman").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.steps({ ':e c', TAKE, ':e d' })
	child.cmd('tabclose')
	child.settle(300)
	eq(S2.load_tab_session(child, 't'), { true })
	eq(child.lua([[
		local R = require('frogman.domains.snapshots').routines
		return { own = #R.of_window(vim.api.nvim_get_current_win()), held = #R.held_in(...) }
	]], { id }), { own = 1, held = 0 })
end

-- A snapshot pasted into a window frogman never took in, not committed, goes with the window at its close.
T['T1063 [char] (M16, DESK.md:1936) a snapshot pasted into a window frogman never took in goes at its close'] = function()
	local one = two_windows()
	in_list(one, 'yy')
	child.cmd('help')
	child.settle()
	local help = child.lua('return vim.api.nvim_get_current_win()')
	in_list(help, 'p')
	local pasted = #snapshots(help)
	child.lua('vim.api.nvim_win_close(..., false)', { help })
	child.settle(300)
	eq({ pasted = pasted, held = #child.lua('return require("frogman.domains.snapshots").routines.held_in("")') }, { pasted = 1, held = 0 })
end

-- A window with snapshots and no marks, closed after a save: its snapshots go onto its entry as they stand, one
-- taken since the save among them, nothing held over; the entry, `[10]` null in the file, is known again as the
-- file holds it.
T['T1066 [char] (M16, DESK.md:1938) a window closed with a saved entry puts its snapshots onto it as they stand, nothing held over'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c', TAKE })
	eq(S2.save(child), { true })
	child.steps({ ':e d', TAKE })
	child.cmd('close')
	child.settle(1500) -- the close's write lands with the records
	eq(child.lua([[
		local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), nil) or {}
		local filed = {}
		for _, entry in ipairs(saved.windows or {}) do
			if type(entry) == 'table' and type(entry[11]) == 'table' then table.insert(filed, #entry[11]) end
		end
		return { held = #require('frogman.domains.snapshots').routines.held_in(''), filed = filed }
	]]), { held = 0, filed = { 2 } })
end


-- A switch with nothing wired to save at it: a snapshot taken since the session's last save, its window closed
-- by the switch's teardown with the load in the same call: the session left's file holds it on the window's
-- entry, none held over.
T['T1070 [char] (M16, DESK.md:1205) a switch keeps a window\'s snapshot taken since the last save on its entry in the session left\'s file'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', TAKE })
	eq(S2.save(child, 'left'), { true })
	child.steps({ ':e d', TAKE })
	local got = child.lua([[
		vim.api.nvim_win_close(..., true)
		return { pcall(require('frogman').load_session, 'next') }
	]], { split })
	child.settle(300)
	eq({ got = got, filed = child.lua([[
		local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), 'left') or {}
		local out = {}
		for _, entry in ipairs(saved.windows or {}) do
			if type(entry) == 'table' and type(entry[11]) == 'table' then table.insert(out, #entry[11]) end
		end
		return { windows = out, held = #(saved.snapshots or {}) }
	]]) }, { got = { true }, filed = { windows = { 2 }, held = 0 } })
end

-- A window the switch's teardown leaves standing: its snapshot taken since the session's last save goes onto its
-- entry in the session left's file as it stands, as a closed window's does.
T['T1086 [char] (M16, DESK.md:1205) a window the switch leaves standing keeps its snapshot taken since the last save on its entry'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c' })
	child.cmd('wincmd p')
	child.settle()
	child.steps({ TAKE })
	eq(S2.save(child, 'left'), { true })
	child.steps({ ':e d', TAKE })
	local got = child.lua([[
		vim.api.nvim_win_close(..., true)
		return { pcall(require('frogman').load_session, 'next') }
	]], { split })
	child.settle(300)
	eq({ got = got, filed = child.lua([[
		local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), 'left') or {}
		local out = {}
		for _, entry in ipairs(saved.windows or {}) do
			if type(entry) == 'table' and type(entry[11]) == 'table' then table.insert(out, #entry[11]) end
		end
		return out
	]]) }, { got = { true }, filed = { 2 } })
end

-- A switch whose teardown closes a window without its events (noautocmd), the load in the same call: the window's
-- snapshot taken since the session's last save goes onto its entry in the session left's file as a closed
-- window's does, none held over.
T['T1090 [char] (M16, DESK.md:1205, :1938) a switch keeps the snapshot of a window it closes without its events on its entry'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.settle()
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ ':e c', TAKE })
	eq(S2.save(child, 'left'), { true })
	child.steps({ ':e d', TAKE })
	local got = child.lua([[
		local split = ...
		vim.cmd('noautocmd call nvim_win_close(' .. split .. ', v:true)')
		return { pcall(require('frogman').load_session, 'next') }
	]], { split })
	child.settle(300)
	eq({ got = got, filed = child.lua([[
		local saved = require('frogman.domains.storage').routines.read_session(vim.fn.getcwd(-1, -1), 'left') or {}
		local out = {}
		for _, entry in ipairs(saved.windows or {}) do
			if type(entry) == 'table' and type(entry[11]) == 'table' then table.insert(out, #entry[11]) end
		end
		return { windows = out, held = #(saved.snapshots or {}) }
	]]) }, { got = { true }, filed = { windows = { 2 }, held = 0 } })
end


-- The list's guards (DESK.md:1941, :1733, :1739): a held-over header missing at the write refuses it, a pasted copy
-- of one stays and is asked about, the directory question stops once an answer opens nothing new, and with its
-- window gone q and <C-c> leave, the edits dropped.

T['T1138 [char] (M16, DESK.md:1941) a held-over header deleted and written on one command line refuses the write, the cursor on its first line'] = function()
	split_held_over()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ LIST })
	local drawn = list_lines()
	local h = held('')
	child.messages()
	local got = child.lua([[
		vim.cmd('1d|w')
		return { cursor = vim.api.nvim_win_get_cursor(0)[1], modified = vim.bo.modified }
	]])
	child.settle()
	local told = #vim.tbl_filter(function(m)
		return m == 'frogman: the header "' .. (h[1] and h[1].held or '?') .. '" is missing: put it back, or :q! to discard.'
	end, said())
	eq({ got = got, told = told, held = #held(''), own = #snapshots(win), lines = list_lines() },
		{ got = { cursor = 1, modified = true }, told = 1, held = 1, own = 0, lines = drawn })
end

T['T1139 [char] (M16, DESK.md:1941, :1733) a pasted copy of a held-over header is asked about at the write, and Yes leaves it out, the lines under it with the group above'] = function()
	split_held_over()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ TAKE })
	local own_id, held_id = snapshots(win)[1].id, held('')[1].id
	child.steps({ LIST })
	local drawn = list_lines() -- the window's own, the header, the held-over one
	keys('2G', 'yy', 'gg', 'P') -- the header's copy above the window's own line
	local kept = list_lines()
	child.answer('No')
	child.cmd('silent! write')
	child.settle(100)
	local prompt = child.prompts()
	local no = { prompts = #prompt, named = (prompt[1] or ''):find('a copy of a header', 1, true) ~= nil,
		modified = list().modified, cursor = child.lua('return vim.api.nvim_win_get_cursor(0)[1]') }
	child.answer('Yes')
	child.cmd('silent! write')
	child.settle(100)
	local own, h = snapshots(win), held('')
	eq({ kept = { n = #kept, copy = kept[1] == drawn[2] }, no = no,
		yes = { own = #own == 1 and own[1].id == own_id, held = #h == 1 and h[1].id == held_id, modified = list().modified } },
		{ kept = { n = #drawn + 1, copy = true }, no = { prompts = 1, named = true, modified = true, cursor = 1 },
			yes = { own = true, held = true, modified = false } })
end

T['T1140 [char] (M16, DESK.md:1739) q and <C-c> in the list with its window gone leave, the edits dropped, saying so'] = function()
	local got = {}
	for _, key in ipairs({ 'q', '<C-c>' }) do
		child.setup()
		local split, float = list_without_its_window()
		child.lua('vim.cmd("normal! yyp")')
		child.type_keys(key)
		child.settle(100)
		got[key] = { open = child.lua('return vim.api.nvim_win_is_valid(...)', { float }),
			told = #vim.tbl_filter(function(m) return m == 'frogman: the window these were for is gone: the edits are dropped.' end, said()),
			split = #snapshots(split), list = child.lua('return vim.fn.bufnr("frogman://snapshots")') }
	end
	local left = { open = false, told = 1, split = 0, list = -1 }
	eq(got, { q = left, ['<C-c>'] = left })
end

T['T1141 [char] (M16, DESK.md:1733) the directory question stops once an answer opens nothing new'] = function()
	local one, split = two_windows()
	local line = line_from(one, '/elsewhere/project', 'elsewhere')
	local asked = written_with(split, { line }, { '/nowhere/at/all', '/nowhere/again' })
	eq({ input = #asked.input, confirm = #asked.confirm, n = #snapshots(split) }, { input = 1, confirm = 1, n = 0 })
end

T['T1146 [char] (M16, DESK.md:1941) the one held-over header deleted with a copy of it below is taken back'] = function()
	split_held_over()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ LIST })
	keys('gg', 'yy', 'G', 'p') -- the header's copy below its held-over line
	local copied = list_lines()
	keys('gg', 'dd') -- the header it was drawn on
	local after = list_lines()
	child.answer('Yes')
	child.cmd('silent! write')
	child.settle(100)
	eq({ n = #copied, after = after, own = #snapshots(win), held = #held('') }, { n = 3, after = copied, own = 0, held = 1 })
end

T['T1148 [char] (M16, DESK.md:1941) keys typed ahead with the list\'s open key meet the header it drew: the header deleted past its copy refuses'] = function()
	split_held_over()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.messages()
	-- in one batch: the list opened, its one held-over header yanked and put below the held line, the header deleted,
	-- the write
	child.lua('vim.api.nvim_feedkeys(vim.keycode("<M-;>Sggyy2Gpggdd:w<CR>"), "tx", false)')
	child.settle(100)
	local told = #vim.tbl_filter(function(m) return m:find('is missing: put it back, or :q! to discard.', 1, true) ~= nil end, said())
	eq({ told = told, own = #snapshots(win), held = #held('') }, { told = 1, own = 0, held = 1 })
end

-- Snapshots' moves in the trail (DESK.md:1934) -------------------------------------------------------------------

-- Today's moves of a kind, each as its window, its words and its row's slots by file name.
local function moves_of(kind)
	return child.lua([[
		local kind = ...
		local L = require('frogman').ledger
		local H = require('frogman.domains.history')
		local function name(h) return h and vim.fn.fnamemodify(H.get_filepath_from_hash(h) or '', ':t:r') or '-' end
		local function slots(r) return r and ('⦉' .. name(r.t) .. '⦊ [' .. name(r.c) .. '] ⟦' .. name(r.s) .. '⟧') or nil end
		local out = {}
		for _, step in ipairs(L.trail(os.date('%Y-%m-%d'))) do
			for _, m in ipairs(step.moves) do
				if m.kind == kind then
					table.insert(out, { window = m.name, words = m.words, before = m.row and slots(m.row.before), after = m.row and slots(m.row.after) })
				end
			end
		end
		return out
	]], { kind })
end

T['T1154 [char] (M16, A27, DESK.md:1934) taking a snapshot is a move in the trail'] = function()
	taken()
	local trail = child.lua([[
		vim.cmd('FrogmanTrail')
		return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
	]])
	eq({ moves = moves_of('taken'), drawn = trail:find('⊡ win 1', 1, true) ~= nil and trail:find('snapshot taken', 1, true) ~= nil },
		{ moves = { { window = 'win 1', words = 'snapshot taken' } }, drawn = true })
end

T['T1155 [char] (M16, A27, DESK.md:1934) committing a snapshot is a move in the trail, the window\'s slots before and after'] = function()
	previewing()
	child.step('<M-v>')
	child.settle(100)
	eq(moves_of('committed'), { { window = 'win 1', words = 'snapshot committed', before = '⦉a⦊ [e] ⟦b⟧', after = '⦉c⦊ [d] ⟦b⟧' } })
end

-- The preview over a closed current, and the commit's way back (DESK.md:1946, :1948, :1950, :1952, :1955) --------

-- Whether a message since the last read says the cleanup healed a window.
local function healed()
	for _, m in ipairs(child.messages() or {}) do
		if (m.msg or ''):find('Healed the triquetra', 1, true) then return true end
	end
	return false
end

-- A window's note on one map for a file, by name, or false.
local function note(win, map, file)
	return child.lua([[
		local win, map, file = ...
		local t = require('frogman.domains.window').data.crux[win]
		local H = require('frogman.domains.history')
		local key = file:match('%-swap$') and (H.get_handle_from_filepath(_G.FRG_TEST.root .. '/' .. file:gsub('%-swap$', '') .. '.txt') .. '-swap')
			or H.get_handle_from_filepath(_G.FRG_TEST.root .. '/' .. file .. '.txt')
		local v = t[map][key]
		return v and vim.fn.fnamemodify(H.get_filepath_from_handle(v), ':t:r') or false
	]], { win, map, file })
end

T['T1156 [char] (M16, DESK.md:1946, :1948, repro R5) a preview leaves the slots alone when the window\'s current is closed'] = function()
	child.steps({ ':e a', ':e d', TAKE, ':e a' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	eq(child.slots(win), '⦉d⦊ [a] ⟦-⟧')
	child.lua('local b = vim.api.nvim_create_buf(false, true); vim.api.nvim_win_set_buf(..., b)', { win })
	child.settle()
	child.cmd('bdelete ' .. child.lua('return _G.FRG_TEST.root') .. '/a.txt')
	child.settle()
	child.messages()
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	local during = { slots = child.slots(win), shown = child.shown(win) }
	child.steps({ LIST })
	child.settle(100)
	eq({ during = during, after = child.slots(win), healed = healed() },
		{ during = { slots = '⦉d⦊ [a] ⟦-⟧', shown = 'd' }, after = '⦉d⦊ [a] ⟦-⟧', healed = false })
end

T['T1157 [char] (M16, DESK.md:1949, :1950, repro R6) a commit with the snapshot\'s current closed lands by the pick rules'] = function()
	taken()
	child.steps({ ':e a', ':e e' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	eq(child.slots(win), '⦉a⦊ [e] ⟦b⟧')
	child.cmd('bdelete ' .. child.lua('return _G.FRG_TEST.root') .. '/d.txt')
	child.settle()
	child.messages()
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	child.lua('vim.api.nvim_win_set_buf(..., vim.fn.bufnr(_G.FRG_TEST.root .. "/a.txt"))', { win })
	child.settle()
	child.step('<M-v>')
	child.settle(100)
	eq({ slots = child.slots(win), note = note(win, 'displacement_ternary_map', 'a'), healed = healed() },
		{ slots = '⦉c⦊ [a] ⟦b⟧', note = 'd', healed = false })
end

T['T1158 [char] (M16, DESK.md:1951, :1952) a commit onto the window\'s own current leaves swap notes for the arrangement it replaced'] = function()
	taken()
	child.steps({ ':e x', ':e e', ':e d' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.lua([[
		local H = require('frogman.domains.history')
		require('frogman.domains.window').data.crux[...]:update({ secondary_slot = H.get_handle_from_filepath(_G.FRG_TEST.root .. '/x.txt') })
	]], { win })
	eq(child.slots(win), '⦉e⦊ [d] ⟦x⟧')
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	child.step('<M-v>')
	child.settle(100)
	local committed = child.slots(win)
	child.steps({ '<M-;><M-r>' })
	local ternary = child.slots(win)
	child.steps({ '<M-;><M-t>' })
	eq({ committed = committed, ternary = ternary:match('^⦉(%a)⦊'), secondary = child.slots(win):match('⟦(%a)⟧$') },
		{ committed = '⦉c⦊ [d] ⟦b⟧', ternary = 'e', secondary = 'x' })
end

T['T1159 [char] (M16, DESK.md:1954, :1955, repro R7) in the window view the bufferline draws the laid-in order at the commit'] = function()
	child.lua('_G.FRG_TEST.setup({ bufferline = { history_view = "window" } })')
	taken()
	child.steps({ ':e a', ':e e' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e f' })
	child.cmd('wincmd p')
	child.settle()
	child.steps({ ':e x', ':e e' })
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	child.step('<M-v>')
	child.settle(100)
	eq({ win = child.lua('return vim.api.nvim_get_current_win()') == win, ordered = child.ordered() },
		{ win = true, ordered = 'd,c,b,a,e,x,f' })
end

-- :e during a preview, and what counts as an edit (DESK.md:1945, :1946, repros R8, P5) ----------------------------

-- A buffer's state by its number: whether it's there, loaded, listed and taken in.
local function buffer_state(bufnr)
	return child.lua([[
		local b = ...
		if not vim.api.nvim_buf_is_valid(b) then return { valid = false } end
		return { valid = true, loaded = vim.api.nvim_buf_is_loaded(b), listed = vim.bo[b].buflisted,
			taken = require('frogman.domains.history').get_hash_from_buffer(b) ~= nil }
	]], { bufnr })
end

T['T1160 [char] (M16, DESK.md:1945, :1946, repro R8) :e onto a closed file of the order borrows it, and a cancel gives it back'] = function()
	local win = shown_with_closed('c')
	child.cmd('edit c.txt')
	child.settle(100)
	local at, c = showing(), state('c')
	local bufnr = child.lua('return vim.api.nvim_get_current_buf()')
	child.steps({ LIST })
	child.settle(100)
	eq({ at = { name = at.name, taken = at.taken }, c = c, back = child.shown(win), after = buffer_state(bufnr), still = state('c') },
		{ at = { name = 'c.txt', taken = false }, c = { taken = false, listed = true }, back = 'e',
			after = { valid = true, loaded = false, listed = false, taken = false }, still = { taken = false, listed = true } })
end

T['T1161 [char] (M16, DESK.md:1945, :1946) :e onto a closed file outside the order borrows it too'] = function()
	taken()
	child.steps({ ':e a', ':e x', ':e e' })
	child.cmd('bdelete x.txt')
	child.settle()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	child.cmd('edit x.txt')
	child.settle(100)
	local at = showing()
	local bufnr = child.lua('return vim.api.nvim_get_current_buf()')
	child.steps({ LIST })
	child.settle(100)
	eq({ taken = at.taken, back = child.shown(win), after = buffer_state(bufnr), x = state('x') },
		{ taken = false, back = 'e', after = { valid = true, loaded = false, listed = false, taken = false }, x = { taken = false, listed = true } })
end

T['T1162 [char] (M16, DESK.md:1945) :e onto a file frogman never knew borrows it, and a cancel wipes what :e made'] = function()
	local win = shown_with_closed('c')
	child.cmd('edit t.txt')
	child.settle(100)
	local at = showing()
	local bufnr = child.lua('return vim.api.nvim_get_current_buf()')
	child.steps({ LIST })
	child.settle(100)
	eq({ name = at.name, taken = at.taken, back = child.shown(win), after = buffer_state(bufnr), known = state('t') },
		{ name = 't.txt', taken = false, back = 'e', after = { valid = false }, known = { taken = false, listed = false } })
end

T['T1163 [char] (M16, DESK.md:1945) <M-v> on a file :e borrowed opens it for real'] = function()
	local win = shown_with_closed('c')
	child.cmd('edit c.txt')
	child.settle(100)
	child.step('<M-v>')
	child.settle(100)
	eq({ c = state('c'), slots = child.slots(win) }, { c = { taken = true, listed = false }, slots = '⦉d⦊ [c] ⟦b⟧' })
end

T['T1164 [char] (M16, DESK.md:1945, :1946) :e onto a file gone from disk shows its placeholder, and <M-v> refuses there'] = function()
	local win = shown_with_closed('c')
	child.lua('os.remove(_G.FRG_TEST.root .. "/c.txt")')
	child.lua('require("frogman.domains.history").routines.cleanup_system()')
	child.settle()
	child.cmd('edit c.txt')
	child.settle(100)
	local at = showing()
	child.messages()
	child.step('<M-v>')
	child.settle()
	local refused = #vim.tbl_filter(function(m) return m:find("c.txt isn't on disk; step onto another file", 1, true) ~= nil end, said())
	eq({ full = at.full, lines = at.lines, refused = refused, still = child.lua('return require("frogman.domains.snapshots").preview.active()'),
		slots = child.slots(win) },
		{ full = 'frogman://gone/c.txt', lines = { '[This file has been deleted off the disk]' }, refused = 1, still = true, slots = '⦉a⦊ [e] ⟦b⟧' })
end

T['T1165 [char] (M16, DESK.md:1945, :1946, repro P5) a borrowed buffer whose lines are rewritten unchanged is given back'] = function()
	shown_with_closed('b')
	step_to('b.txt')
	local bufnr = child.lua([[
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
		vim.bo.modified = false
		return vim.api.nvim_get_current_buf()
	]])
	child.steps({ LIST })
	child.settle(100)
	eq({ b = state('b'), after = buffer_state(bufnr) }, { b = { taken = false, listed = true }, after = { valid = true, loaded = false, listed = false, taken = false } })
end

T['T1166 [char] (M16, DESK.md:1945, :1946, repro P5) a borrowed buffer reloaded with :e! is given back'] = function()
	shown_with_closed('b')
	step_to('b.txt')
	local bufnr = child.lua('return vim.api.nvim_get_current_buf()')
	child.cmd('edit!')
	child.settle(100)
	child.steps({ LIST })
	child.settle(100)
	eq({ b = state('b'), after = buffer_state(bufnr) }, { b = { taken = false, listed = true }, after = { valid = true, loaded = false, listed = false, taken = false } })
end

T['T1167 [char] (M16, DESK.md:1945, :1946) a borrowed buffer has a tab while it\'s borrowed, dimmed, and a closed file not stepped onto has none'] = function()
	taken()
	child.steps({ ':e a', ':e e' })
	child.cmd('bdelete b.txt')
	child.cmd('bdelete a.txt')
	child.settle()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(300)
	local function tab(stem)
		return child.lua([[
			local b = vim.fn.bufnr(_G.FRG_TEST.root .. '/' .. ... .. '.txt')
			if b == -1 then return { tab = false } end
			local bl = require('frogman').bufferline
			if not (bl.bufnr_is_displayed(b) and vim.bo[b].buflisted) then return { tab = false } end
			return { tab = true, dim = bl.get_theme_fg_color(b, false) == require('frogman.configs').colors.trail.dim }
		]], { stem })
	end
	local before = { b = tab('b'), a = tab('a') }
	step_to('b.txt')
	child.settle(300)
	local after = { b = tab('b'), a = tab('a'), d = tab('d') }
	child.steps({ LIST })
	child.settle(300)
	eq({ before = before, after = after, back = tab('b') },
		{ before = { b = { tab = false }, a = { tab = false } }, after = { b = { tab = true, dim = true }, a = { tab = false }, d = { tab = true, dim = false } },
			back = { tab = false } })
end

-- <M-,> and saves while a snapshot shows (DESK.md:1945, :1946) ---------------------------------------------------

T['T1168 [char] (M16, A17, DESK.md:1945, :1946) <M-,> while a snapshot shows leaves it and goes to the window before'] = function()
	taken()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('vsplit')
	child.settle()
	local other = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('wincmd p')
	child.settle()
	child.steps({ ':e a', ':e e' })
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	child.messages()
	child.step('<M-,>')
	child.settle(100)
	local refused = #vim.tbl_filter(function(m) return m:find('a snapshot is showing', 1, true) ~= nil end, said())
	eq({ active = child.lua('return require("frogman.domains.snapshots").preview.active()'),
		at = child.lua('return vim.api.nvim_get_current_win()') == other, shown = child.shown(win), slots = child.slots(win), refused = refused },
		{ active = false, at = true, shown = 'e', slots = '⦉a⦊ [e] ⟦b⟧', refused = 0 })
end

T['T1169 [char] (M16, S1, DESK.md:1945, :1946) a session save while a snapshot shows raises, so a session manager\'s save through it stops'] = function()
	local s = S2.shared()
	S2.start(child, s)
	previewing()
	local saved = S2.save(child)
	eq({ ok = saved[1], told = type(saved[2]) == 'string' and saved[2]:find("a snapshot is showing, so the session isn't saved", 1, true) ~= nil,
		file = S2.main_file(s.session_dir, S2.cwd(child)) ~= nil, active = child.lua('return require("frogman.domains.snapshots").preview.active()') },
		{ ok = false, told = true, file = false, active = true })
end

T['T1221 [char] (M16, S1, DESK.md:1945) cancel_preview leaves a snapshot showing as a cancel does, so a switch\'s save after it goes through'] = function()
	local s = S2.shared()
	S2.start(child, s)
	local win = previewing()
	child.lua('require("frogman").cancel_preview()')
	child.settle(100)
	local left = { active = child.lua('return require("frogman.domains.snapshots").preview.active()'), shown = child.shown(win), slots = child.slots(win) }
	-- with nothing showing, it does nothing
	local idle = child.lua('return { pcall(require("frogman").cancel_preview) }')
	local saved = S2.save(child)
	eq({ idle = idle, left = left, saved = saved, file = S2.main_file(s.session_dir, S2.cwd(child)) ~= nil },
		{ idle = { true }, left = { active = false, shown = 'e', slots = '⦉a⦊ [e] ⟦b⟧' }, saved = { true }, file = true })
end

T['T1223 [char] (M16, S1, DESK.md:1945) a snapshot showing in a tab that closes is left from TabClosedPre while its window still stands, and the tab closes clean'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.cmd('tabnew')
	local win = previewing()
	child.lua([[
		_G.seen = nil
		vim.api.nvim_create_autocmd('TabClosedPre', { once = true, callback = function()
			local ok, err = pcall(require('frogman').cancel_preview)
			_G.seen = { ok = ok, err = err, active = require('frogman.domains.snapshots').preview.active() }
		end })
	]])
	child.messages()
	child.cmd('tabclose')
	child.settle(100)
	local errors = #vim.tbl_filter(function(m) return m:find('E%d+:') ~= nil or m:find('rror') ~= nil end, said())
	eq({ seen = child.lua('return _G.seen'), tabs = child.lua('return #vim.api.nvim_list_tabpages()'), gone = child.lua('return not vim.api.nvim_win_is_valid(...)', { win }),
		errors = errors, active = child.lua('return require("frogman.domains.snapshots").preview.active()') },
		{ seen = { ok = true, active = false }, tabs = 1, gone = true, errors = 0, active = false })
end

T['T1170 [char] (M16, S1, DESK.md:1945) a save as the editor quits ends the snapshot showing first, then saves'] = function()
	local s = S2.shared()
	S2.start(child, s)
	local win = previewing()
	local at_save = child.lua([[
		local win = ...
		local seen
		vim.api.nvim_create_autocmd('VimLeavePre', { callback = function()
			local ok = pcall(require('frogman').save_session)
			seen = { ok = ok, active = require('frogman.domains.snapshots').preview.active(),
				shown = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)), ':t:r') }
		end })
		vim.api.nvim_exec_autocmds('VimLeavePre', {})
		return seen
	]], { win })
	eq({ at_save = at_save, file = S2.main_file(s.session_dir, S2.cwd(child)) ~= nil, slots = child.slots(win) },
		{ at_save = { ok = true, active = false, shown = 'e' }, file = true, slots = '⦉a⦊ [e] ⟦b⟧' })
end

T['T1171 [char] (M16, S1, DESK.md:1945) a session manager\'s save as the editor really quits, ahead of frogman\'s own quit handler, ends the snapshot showing first'] = function()
	local s = S2.shared()
	S2.start(child, s)
	local win = previewing()
	local marker = s.root .. '/quit-marker.json'
	child.lua([[
		local win, marker = ...
		-- frogman's own quit handler, which ends the preview first, is taken off: the save meets the preview itself
		vim.api.nvim_clear_autocmds({ group = 'frogman', event = 'VimLeavePre' })
		vim.api.nvim_create_autocmd('VimLeavePre', { callback = function()
			local ok = pcall(require('frogman').save_session)
			local f = io.open(marker, 'w')
			f:write(vim.json.encode({ exiting = vim.v.exiting ~= vim.NIL, ok = ok, active = require('frogman.domains.snapshots').preview.active(),
				shown = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)), ':t:r') }))
			f:close()
		end })
	]], { win, marker })
	pcall(child.api.nvim_input, ':qa!<CR>')
	vim.wait(5000, function() return vim.uv.fs_stat(marker) ~= nil end, 50)
	local f = io.open(marker, 'r')
	local seen = f and vim.json.decode(f:read('*a')) or {}
	if f then f:close() end
	eq({ seen = seen, file = S2.main_file(s.session_dir, s.root) ~= nil },
		{ seen = { exiting = true, ok = true, active = false, shown = 'e' }, file = true })
end

-- A preview's end when what it left can't come back, and at a load (DESK.md:1945, :1946, :1947, :1948) ------------

T['T1172 [char] (M16, DESK.md:1947, :1948) a cancel whose earlier buffer is gone shows the window\'s current slot, reopened'] = function()
	local win = previewing()
	child.cmd('bwipeout ' .. child.lua('return _G.FRG_TEST.root') .. '/e.txt')
	child.settle()
	child.steps({ LIST })
	child.settle(100)
	eq({ shown = child.shown(win), slots = child.slots(win), e = state('e'),
		active = child.lua('return require("frogman.domains.snapshots").preview.active()') },
		{ shown = 'e', slots = '⦉a⦊ [e] ⟦b⟧', e = { taken = true, listed = false }, active = false })
end

T['T1173 [char] (M16, DESK.md:1947, :1948) a cancel whose earlier buffer is gone, in a window with no slots, shows an empty buffer'] = function()
	split_held_over()
	child.cmd('help')
	child.settle()
	local help = child.lua('return vim.api.nvim_get_current_win()')
	local buf = child.lua('return vim.api.nvim_get_current_buf()')
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	child.lua('vim.api.nvim_buf_delete(..., { force = true })', { buf })
	child.settle()
	child.steps({ LIST })
	child.settle(100)
	eq(child.lua([[
		local w = ...
		local b = vim.api.nvim_win_get_buf(w)
		return { name = vim.api.nvim_buf_get_name(b), lines = vim.api.nvim_buf_get_lines(b, 0, -1, false), bt = vim.bo[b].buftype,
			active = require('frogman.domains.snapshots').preview.active() }
	]], { help }), { name = '', lines = { '' }, bt = '', active = false })
end

T['T1174 [char] (M16, S1 Load, DESK.md:1945, :1946) a tab session\'s load into the preview\'s tab opens a borrowed file you edited'] = function()
	shown_with_closed('b')
	step_to('b.txt')
	child.lua('vim.api.nvim_buf_set_lines(0, -1, -1, false, { "added" })')
	local tab = child.lua('return vim.api.nvim_get_current_tabpage()')
	child.messages()
	child.lua('require("frogman").load_session("u", { tab = ... })', { tab })
	child.settle(300)
	local told = #vim.tbl_filter(function(m) return m:find('b.txt was edited while the snapshot showed it', 1, true) ~= nil end, said())
	eq({ b = state('b'), told = told, active = child.lua('return require("frogman.domains.snapshots").preview.active()') },
		{ b = { taken = true, listed = false }, told = 1, active = false })
end

T['T1175 [char] (M16, S1 Load, DESK.md:1947, :1948) a whole-editor load puts the preview\'s window back on what it showed'] = function()
	local s = S2.shared()
	S2.start(child, s)
	taken()
	child.steps({ ':e a', ':e e' })
	eq(S2.save(child), { true })
	child.cmd('bdelete b.txt')
	child.settle()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	step_to('b.txt')
	local borrowed = child.lua('return vim.api.nvim_get_current_buf()')
	eq(S2.load(child), { true })
	child.settle(300)
	eq({ shown = child.shown(win), active = child.lua('return require("frogman.domains.snapshots").preview.active()'),
		borrowed = buffer_state(borrowed) },
		{ shown = 'e', active = false, borrowed = { valid = true, loaded = false, listed = false, taken = false } })
end

T['T1176 [char] (M16, S1 Load, DESK.md:1947, :1948) a whole-editor load from bare that starts fresh puts the preview\'s window back too'] = function()
	local win = previewing()
	child.lua('require("frogman").load_session("nothing-here")')
	child.settle(300)
	eq({ shown = child.shown(win), active = child.lua('return require("frogman.domains.snapshots").preview.active()') },
		{ shown = 'e', active = false })
end

T['T1177 [char] (M16, M5, DESK.md:1945, :1946) a borrowed No Name text whose read fails stays on the closed lists'] = function()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	local n = S2.noname(child, { 'draft' })
	child.cmd('buffer a.txt')
	child.settle()
	child.steps({ TAKE })
	child.cmd('bwipeout! ' .. n)
	child.settle(100)
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a' }, 'a')
	eq(S2.load(child), { true })
	child.settle(300)
	-- the text's own file gone: every file in the session's folder but its trail pages
	for _, dir in ipairs(vim.fn.globpath(s.session_dir, '*.d', true, true)) do
		for _, f in ipairs(vim.fn.globpath(dir, '*', true, true)) do
			if not f:match('%.trail$') then os.remove(f) end
		end
	end
	local before = texts_on_list()
	child.messages()
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	step_to('draft')
	local lost = #vim.tbl_filter(function(m) return m:find('so that text is lost', 1, true) ~= nil end, said())
	eq({ before = before, after = texts_on_list(), lost = lost }, { before = 1, after = 1, lost = 1 })
end

T['T1178 [char] (M16, M14, DESK.md:1945) :e onto a file gone from disk during a preview leaves nothing counting the file never written'] = function()
	shown_with_closed('c')
	child.lua('os.remove(_G.FRG_TEST.root .. "/c.txt")')
	child.lua('require("frogman.domains.history").routines.cleanup_system()')
	child.settle()
	child.cmd('edit c.txt')
	child.settle(100)
	child.steps({ LIST })
	child.settle(100)
	child.lua('local f = io.open(_G.FRG_TEST.root .. "/c.txt", "w"); f:write("back\\n"); f:close()')
	child.cmd('edit c.txt')
	child.settle(100)
	eq(child.lua([[
		local H = require('frogman.domains.history')
		local id = H.get_handle_from_filepath(_G.FRG_TEST.root .. '/c.txt')
		return { taken = H.get_buffer_from_handle(id) ~= nil, unwritten = H.handles.get(id).unwritten ~= nil }
	]]), { taken = true, unwritten = false })
end

-- The fresh check's findings (DESK.md:1945, :1947, :1948) -------------------------------------------------------

T['T1179 [char] (M16, DESK.md:1947, :1948) a cancel whose earlier buffer was deleted with :bdelete shows the current slot, reopened'] = function()
	local win = previewing()
	child.cmd('bdelete ' .. child.lua('return _G.FRG_TEST.root') .. '/e.txt')
	child.settle()
	child.steps({ LIST })
	child.settle(100)
	eq({ shown = child.shown(win), slots = child.slots(win), e = state('e') },
		{ shown = 'e', slots = '⦉a⦊ [e] ⟦b⟧', e = { taken = true, listed = false } })
end

T['T1180 [char] (M16, DESK.md:1947, :1948) a cancel by a window jump reopens the current slot with its visit in the preview\'s window'] = function()
	taken()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('vsplit')
	child.settle()
	local other = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('wincmd p')
	child.settle()
	child.steps({ ':e a', ':e e' })
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	child.cmd('bwipeout ' .. child.lua('return _G.FRG_TEST.root') .. '/e.txt')
	child.settle()
	child.lua('vim.api.nvim_set_current_win(...)', { other })
	child.settle(100)
	eq(child.lua([[
		local win, other = ...
		local H = require('frogman.domains.history')
		local e = H.get_handle_from_filepath(_G.FRG_TEST.root .. '/e.txt')
		return { shown = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)), ':t:r'),
			own = (H.data.crux_internals.window[win] or {})[e] ~= nil, other = (H.data.crux_internals.window[other] or {})[e] ~= nil }
	]], { win, other }), { shown = 'e', own = true, other = false })
end

T['T1181 [char] (M16, DESK.md:1945) a borrowed buffer another window still shows at the end goes back unlisted'] = function()
	shown_with_closed('b')
	step_to('b.txt')
	local bufnr = child.lua('return vim.api.nvim_get_current_buf()')
	child.cmd('split')
	child.settle(100)
	eq({ active = child.lua('return require("frogman.domains.snapshots").preview.active()'), b = state('b'), after = buffer_state(bufnr) },
		{ active = false, b = { taken = false, listed = true }, after = { valid = true, loaded = true, listed = false, taken = false } })
end

T['T1182 [char] (M16, DESK.md:1945) two :e in one batch during a preview borrow both, and the cancel gives both back'] = function()
	shown_with_closed('c')
	local c = child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/c.txt")')
	child.cmd('edit c.txt | edit t.txt')
	child.settle(100)
	local t = child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/t.txt")')
	child.steps({ LIST })
	child.settle(100)
	eq({ c = buffer_state(c), t = buffer_state(t), still = state('c') },
		{ c = { valid = true, loaded = false, listed = false, taken = false }, t = { valid = false }, still = { taken = false, listed = true } })
end

T['T1183 [char] (M16, S1 Load, DESK.md:1947, :1948) a whole-editor load whose preview\'s earlier buffer is gone puts the window on its current slot'] = function()
	local s = S2.shared()
	S2.start(child, s)
	taken()
	child.steps({ ':e a', ':e e' })
	eq(S2.save(child), { true })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	child.cmd('bwipeout ' .. child.lua('return _G.FRG_TEST.root') .. '/e.txt')
	child.settle()
	eq(S2.load(child), { true })
	child.settle(300)
	eq({ shown = child.shown(win), active = child.lua('return require("frogman.domains.snapshots").preview.active()') },
		{ shown = 'e', active = false })
end

T['T1198 [char] (M16, DESK.md:1947, :1948) a cancel whose earlier buffer is gone, the current slot borrowed, opens it for real'] = function()
	child.steps({ ':e a', ':e d', TAKE, ':e a' })
	local win = child.lua('return vim.api.nvim_get_current_win()')
	local scratch = child.lua('local b = vim.api.nvim_create_buf(false, true); vim.api.nvim_win_set_buf(..., b); return b', { win })
	child.settle()
	child.cmd('bdelete ' .. child.lua('return _G.FRG_TEST.root') .. '/a.txt')
	child.settle()
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	step_to('a.txt')
	child.lua('vim.api.nvim_buf_delete(..., { force = true })', { scratch })
	child.settle()
	child.messages()
	child.steps({ LIST })
	child.settle(100)
	local told = #vim.tbl_filter(function(m) return m:find('was edited while the snapshot showed it', 1, true) ~= nil end, said())
	eq({ shown = child.shown(win), a = state('a'), slots = child.slots(win), told = told },
		{ shown = 'a', a = { taken = true, listed = false }, slots = '⦉d⦊ [a] ⟦-⟧', told = 0 })
end

-- The list's row: the order by the snapshot's roles, and +N past the window's edge (DESK.md:1941, :1942, repro R19) -

-- The open list's first line as drawn: each chunk's text and highlight.
local function row_chunks()
	return child.lua([[
		local buf = vim.fn.bufnr('frogman://snapshots')
		local ns = vim.api.nvim_get_namespaces()['frogman_snapshots']
		for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { 0, 0 }, { 0, -1 }, { details = true })) do
			if m[4].virt_text then
				return vim.tbl_map(function(c) return { c[1], c[2] } end, m[4].virt_text)
			end
		end
		return {}
	]])
end

T['T1184 [char] (M16, DESK.md:1941, :1942) the list draws the stored order in the snapshot\'s own roles, the primary first as cokeline has it'] = function()
	child.lua('vim.o.columns = 200') -- room for the whole row
	taken()
	child.steps({ LIST })
	child.settle(100)
	local groups = {}
	for _, chunk in ipairs(row_chunks()) do
		local name = chunk[1]:match('(%a)%.txt')
		if name and chunk[1]:match('^  %d') then groups[name] = chunk[2] end
	end
	local defined = child.lua([[
		local out = {}
		for _, g in ipairs({ ... }) do out[g] = next(vim.api.nvim_get_hl(0, { name = g })) ~= nil end
		return out
	]], { groups.d, groups.c, groups.b, groups.a })
	eq({ groups = groups, defined = defined },
		{ groups = { d = 'FrogmanOrderPrimary', c = 'FrogmanOrderTernary', b = 'FrogmanOrderSecondary', a = 'FrogmanOrderOpen' },
			defined = { FrogmanOrderPrimary = true, FrogmanOrderTernary = true, FrogmanOrderSecondary = true, FrogmanOrderOpen = true } })
end

T['T1185 [char] (M16, DESK.md:1941, :1942, repro R19) a long row draws whole entries, then +N'] = function()
	child.lua([[
		for i = 1, 25 do
			local f = io.open(string.format('%s/f%02d.txt', _G.FRG_TEST.root, i), 'w'); f:write('x\n'); f:close()
		end
	]])
	for i = 1, 25 do
		child.cmd(string.format('edit f%02d.txt', i)) -- each settled, so each is a visit
		child.settle()
	end
	child.steps({ TAKE, LIST })
	child.settle(100)
	local text = table.concat(vim.tbl_map(function(c) return c[1] end, row_chunks()))
	local fit = child.lua([[
		local text = ...
		local win = vim.fn.bufwinid(vim.fn.bufnr('frogman://snapshots'))
		local info = vim.fn.getwininfo(win)[1]
		return vim.api.nvim_strwidth(text) <= info.width - info.textoff
	]], { text })
	local more = tonumber(text:match('  %+(%d+)$'))
	local whole = true
	for entry in text:gmatch('  %d+ ([^ ]+)') do
		if not entry:match('^f%d%d%.txt$') and not entry:match('^%a%.txt$') then whole = false end
	end
	eq({ fit = fit, more = more ~= nil and more > 0, whole = whole }, { fit = true, more = true, whole = true })
end

-- Copying between windows (DESK.md:1943, :1944, repro R20) --------------------------------------------------------

T['T1186 [char] (M16, DESK.md:1943, :1944) a window\'s own line moved under a held-over header is copied there, the original staying'] = function()
	split_held_over()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ TAKE })
	local own = snapshots(win)[1].id
	child.steps({ LIST })
	keys('gg', 'dd', 'G', 'p')
	child.step('q')
	child.settle(100)
	local got, h = snapshots(win), held('')
	local copied = 0
	for _, s in ipairs(h) do if s.id ~= own and s.slots == '⦉a⦊ [b] ⟦-⟧' then copied = copied + 1 end end
	eq({ own = #got, kept = got[1] and got[1].id == own, held = #h, copied = copied }, { own = 1, kept = true, held = 2, copied = 1 })
end

T['T1187 [char] (M16, DESK.md:1943, :1944) two entries of a rebuilt line that resolve to one file keep it once'] = function()
	local one, split = two_windows()
	local line = changed_line(one, 'd.editor = "another editor"; d.id = "elsewhere"; for i, f in ipairs(d.files) do f.handle = 90000 + i end; '
		.. 'table.insert(d.files, { path = d.files[d.c].path, handle = 99998 }); d.s = #d.files')
	put_line(split, line)
	local got = snapshots(split)
	eq({ n = #got, slots = got[1] and got[1].slots }, { n = 1, slots = '⦉c⦊ [d] ⟦-⟧' })
end

T['T1188 [char] (M16, M14, DESK.md:1943, :1944, repro R20) a rebuilt line naming a file not on disk tags it gone at once'] = function()
	local one, split = two_windows()
	local line = changed_line(one, 'd.editor = "another editor"; d.id = "elsewhere"; for i, f in ipairs(d.files) do f.handle = 90000 + i; '
		.. 'if f.path:match("/a%.txt$") then f.path = f.path:gsub("/a%.txt$", "/nowhere.txt") end end')
	put_line(split, line)
	eq(child.lua([[
		local H = require('frogman.domains.history')
		local id = H.get_handle_from_filepath(_G.FRG_TEST.root .. '/nowhere.txt')
		return { known = id ~= nil, tagged = id ~= nil and H.handles.get(id).tag ~= nil }
	]]), { known = true, tagged = true })
end

-- A snapshot whose current is gone falls back (DESK.md:1936, :1937) -----------------------------------------------

-- A saved session holding a snapshot whose current is a No Name text, ternary a; a fresh editor loads it, and the
-- text's file is deleted. Returns the shared project.
local function text_current_lost()
	local s = S2.shared()
	S2.start(child, s)
	child.steps({ ':e a' })
	S2.noname(child, { 'draft' })
	child.steps({ TAKE })
	local n = child.lua('return vim.api.nvim_get_current_buf()')
	child.cmd('buffer a.txt')
	child.settle()
	child.cmd('bwipeout! ' .. n)
	child.settle(100)
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a' }, 'a')
	eq(S2.load(child), { true })
	child.settle(300)
	for _, dir in ipairs(vim.fn.globpath(s.session_dir, '*.d', true, true)) do
		for _, f in ipairs(vim.fn.globpath(dir, '*', true, true)) do
			if not f:match('%.trail$') then os.remove(f) end
		end
	end
	return s
end

T['T1189 [char] (M16, DESK.md:1936, :1937) a preview of a snapshot whose current text is lost falls back to its ternary'] = function()
	text_current_lost()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ LIST })
	child.step('<CR>')
	child.settle(100)
	eq({ active = child.lua('return require("frogman.domains.snapshots").preview.active()'), shown = child.shown(win),
		slots = snapshots(win)[1].slots }, { active = true, shown = 'a', slots = '⦉-⦊ [a] ⟦-⟧' })
end

T['T1190 [char] (M16, S1, DESK.md:1936, :1937) a save keeps a snapshot whose current text is lost, its current fallen back'] = function()
	local s = text_current_lost()
	eq(S2.save(child), { true })
	S2.start(child, s)
	Misc.restore(child, { 'a' }, 'a')
	child.messages()
	eq(S2.load(child), { true })
	child.settle(300)
	local win = child.lua('return vim.api.nvim_get_current_win()')
	local got = snapshots(win)
	local broke = #vim.tbl_filter(function(m) return m.msg:find('broke its own rules', 1, true) ~= nil end, child.messages())
	eq({ n = #got, slots = got[1] and got[1].slots, broke = broke }, { n = 1, slots = '⦉-⦊ [a] ⟦-⟧', broke = 0 })
end

T['T1191 [char] (M16, S1 Load, DESK.md:1936, :1937) a file written elsewhere with a snapshot whose current names no path keeps it, fallen back, with no warning'] = function()
	local s = S2.shared()
	S2.start(child, s)
	taken()
	eq(Misc.save(child), { true })
	S2.start(child, s)
	child.lua([[
		local crypto = require('frogman.domains.storage.crypto')
		local dir, name = vim.fn.getcwd(-1, -1), vim.fn.getcwd()
		local path = require('frogman.configs').session_dir .. vim.fn.sha256(dir .. "\n" .. name)
		local fh = assert(io.open(path, 'rb')); local bytes = fh:read('*a'); fh:close()
		local salt = bytes:sub(5, 4 + crypto.salt_length)
		local data = require('frogman.domains.storage.routines').read_session(dir, name)
		for _, entry in ipairs(data.windows) do
			for _, saved in ipairs(type(entry[11]) == 'table' and entry[11] or {}) do
				saved.current = 'deadbeefdeadbeef' -- a current no path names
			end
		end
		local header = "CDV1" .. salt
		local out = header .. crypto.seal(crypto.derive_key(dir, salt), vim.json.encode(data), header)
		fh = assert(io.open(path, 'wb')); fh:write(out); fh:close()
	]])
	Misc.restore(child, { 'a', 'b', 'c', 'd' }, 'd')
	child.messages()
	eq(Misc.load(child), { true })
	child.settle(300)
	local win = child.lua('return vim.api.nvim_get_current_win()')
	local got = snapshots(win)
	local broke = #vim.tbl_filter(function(m) return m.msg:find('broke its own rules', 1, true) ~= nil end, child.messages())
	eq({ n = #got, slots = got[1] and got[1].slots, broke = broke }, { n = 1, slots = '⦉-⦊ [c] ⟦b⟧', broke = 0 })
end

T['T1199 [char] (M16, DESK.md:1941, :1942) the list draws the queue\'s head in the primary\'s colour with the switch off, as cokeline does'] = function()
	child.lua('vim.o.columns = 200')
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d', '<M-;><M-c>', '<M-;><M-x>' })
	eq(child.primary(), '[d]off')
	child.steps({ TAKE, LIST })
	child.settle(100)
	local d
	for _, chunk in ipairs(row_chunks()) do
		if chunk[1]:match('^  %d+ d%.txt') then d = chunk[2] end
	end
	eq(d, 'FrogmanOrderPrimary')
end

return T
