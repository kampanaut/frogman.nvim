-- Snapshots (M16). IDs are the spec's (what-is-frogman.md, section 7).
local Helpers = dofile('tests/helpers.lua')
local S2 = dofile('tests/helpers_s2.lua')
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

T['T764 [char] (M16) the list draws each snapshot over its concealed identity'] = function()
	taken()
	child.steps({ ':e e', TAKE, LIST })
	local l = list()
	local ok_ids = l ~= vim.NIL and l.lines[1]:match('^snap:%d+$') ~= nil and l.lines[2]:match('^snap:%d+$') ~= nil
	local older = l ~= vim.NIL and l.drawn[2] or {}
	child.lua('vim.cmd("redraw")')
	local shot = tostring(child.get_screenshot())
	local screen = { drawn = shot:find('⦉c.txt⦊ [d.txt] ⟦b.txt⟧', 1, true) ~= nil, hidden = shot:find('snap:', 1, true) == nil }
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

T['T768 [char] (M16, S1) a whole-editor load from idle starts with no snapshot'] = function()
	taken()
	eq(S2.save(child), { true })
	eq(S2.load(child), { true })
	child.settle(300)
	eq(child.lua('return next(require("frogman.domains.snapshots").data.by_window) == nil'), true)
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

T['T771 [char] (M16) a window\'s snapshots go with it'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('split')
	child.settle()
	child.steps({ ':e x', TAKE, ':e b' })
	local split = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('close')
	child.settle(300)
	local left = child.lua([[
		local H = require('frogman.domains.history')
		local h = H.handles.of_hash(H.routines.get_filehash(_G.FRG_TEST.root .. '/x.txt'))
		local snap = false
		for place, _ in pairs(h and h.holders or {}) do
			if place:match('^snap:') then snap = true end
		end
		return { snapshots = require('frogman.domains.snapshots').data.by_window[...] ~= nil, x = snap }
	]], { split })
	eq(left, { snapshots = false, x = false })
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
		return vim.tbl_map(function(h) return vim.fn.fnamemodify(H.get_filepath_from_hash(h), ':t:r') end, t.primary_buffer)[1] .. (t.primary_enabled and 'on' or 'off')
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

T['T781 [char] (M16) a snapshot whose current is closed isn\'t shown yet'] = function()
	taken()
	child.steps({ ':e a' })
	child.cmd('bdelete d.txt')
	child.settle()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	child.steps({ LIST })
	child.messages()
	child.step('<CR>')
	child.settle()
	eq({ said = vim.tbl_map(function(m) return m.msg end, child.messages()), shown = child.shown(win),
		detached = child.lua('return require("frogman.domains.history").is_detached()') },
		{ said = { 'frogman: d.txt is closed; showing a closed file comes with borrowing.' }, shown = 'a', detached = false })
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
		for h, t in pairs(own) do table.insert(items, { vim.fn.fnamemodify(H.get_filepath_from_hash(h) or h, ':t:r'), t }) end
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
		local a = H.routines.get_filehash(_G.FRG_TEST.root .. '/a.txt')
		local v = t.displacement_ternary_map[a]
		return v and vim.fn.fnamemodify(H.get_filepath_from_hash(v), ':t:r') or false
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

return T
