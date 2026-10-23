-- Cycling: <M-n>, <M-m>, <M-v> and cancelling (A12-A14), with the flight
-- recorder tests the spec files here (A26). IDs are the spec's
-- (what-is-cavediver.md, section 7).
--
-- The cokeline stub steps through cavediver's ordered history, index 1 the
-- newest: <M-n> is by_step(-1), toward newer (wrapping from the newest to the
-- oldest), <M-m> is by_step(1), toward older.
local Helpers = dofile('tests/helpers.lua')
local Extra = dofile('tests/helpers_cycling.lua')
local eq = Helpers.eq
local child = Helpers.new_child()
Extra.attach(child)
-- A second child, for T204's session load.
local other = Helpers.new_child()
Extra.attach(other)

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = function()
			child.stop()
			other.stop()
		end,
	},
})

local CYCLING = { nav = 'cycling', hist = 'detached' }
local NORMAL = { nav = 'normal', hist = 'attached' }

-- {c=e s=c t=d}, with order e,d,c,b,a.
local function ecd()
	child.steps({ ':e a', ':e b', ':e c', ':e d', '<M-f>', ':e e' })
	eq(child.slots(), '⦉d⦊ [e] ⟦c⟧')
	eq(child.ordered(), 'e,d,c,b,a')
end

-- D15's and P18's setup: ⦉d⦊ [c] ⟦b⟧, with b's note b>a.
local function dcb()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d', ':e c' })
	eq(child.slots(), '⦉d⦊ [c] ⟦b⟧')
	eq(child.note('dtm', 'b'), 'a')
end

local function no_errors()
	eq(Extra.at_least(child.messages()), {})
end

T['T69 [char] <M-m> from normal starts cycling and leaves the current slot'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	child.messages()
	child.steps({ '<M-m>' })
	eq(child.state(), CYCLING)
	eq(Extra.has(child.messages(), 'Checkpoint saved'), true)
	eq(child.shown(), 'b')
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
end

T['T70 [char] further steps change neither the slots nor the history order'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-m>' })
	local slots, notes, ordered = child.slots(), child.notes(), child.ordered()
	for _, key in ipairs({ '<M-m>', '<M-m>', '<M-n>', '<M-n>', '<M-n>' }) do
		child.steps({ key })
		eq({ child.slots(), child.notes(), child.ordered() }, { slots, notes, ordered })
	end
	eq(child.state(), CYCLING)
end

T['T71 [char] with one buffer in history, <M-m> enters cycling without moving'] = function()
	child.steps({ ':e a' })
	child.steps({ '<M-m>' })
	eq(child.state(), CYCLING)
	eq(child.shown(), 'a')
	eq(child.slots(), '⦉-⦊ [a] ⟦-⟧')
end

T['T72 [char] a pick of an outside buffer: the start leaves, the ternary stays'] = function()
	ecd()
	child.steps({ '<M-n>', '<M-n>' })
	eq(child.shown(), 'b')
	child.steps({ '<M-v>' })
	eq(child.slots(), '⦉d⦊ [b] ⟦c⟧')
	eq(child.state(), NORMAL)
end

T['T73 [char] a pick of the secondary swaps them, with no map writes'] = function()
	ecd()
	local notes = child.notes()
	child.steps({ '<M-m>', '<M-m>' })
	eq(child.shown(), 'c')
	child.steps({ '<M-v>' })
	eq(child.slots(), '⦉d⦊ [c] ⟦e⟧')
	eq(child.notes(), notes)
end

T['T74 [char] a pick of the ternary swaps them, with the start\'s swap note'] = function()
	ecd()
	child.steps({ '<M-m>' })
	eq(child.shown(), 'd')
	child.steps({ '<M-v>' })
	eq(child.slots(), '⦉e⦊ [d] ⟦c⟧')
	eq(child.note('dtm', 'e-swap'), 'd')
end

T['T75 [char] <M-v> on the start changes no slot and ends the cycle'] = function()
	ecd()
	child.steps({ '<M-m>', '<M-n>' })
	eq(child.shown(), 'e')
	child.steps({ '<M-v>' })
	eq(child.slots(), '⦉d⦊ [e] ⟦c⟧')
	eq(child.state(), NORMAL)
end

T['T76 [char] <M-v> in normal mode does nothing'] = function()
	ecd()
	local before = { child.slots(), child.notes(), child.shown(), child.ordered() }
	child.messages()
	child.steps({ '<M-v>' })
	eq({ child.slots(), child.notes(), child.shown(), child.ordered() }, before)
	eq(child.state(), NORMAL)
	no_errors()
end

T['T77 [char] <M-f> while cycled away switches back to the start and stays cycling'] = function()
	ecd()
	child.steps({ '<M-m>' })
	eq(child.shown(), 'd')
	child.steps({ '<M-f>' })
	eq(child.shown(), 'e')
	eq(child.slots(), '⦉d⦊ [e] ⟦c⟧')
	eq(child.state(), CYCLING)
end

T['T78 [char] <M-S-f> while cycling, on the current slot, swaps the ternary and stays cycling'] = function()
	ecd()
	-- Cycle away, then <M-f> back onto the current slot.
	child.steps({ '<M-m>', '<M-f>' })
	eq(child.shown(), 'e')
	child.steps({ '<M-S-f>' })
	eq(child.slots(), '⦉e⦊ [d] ⟦c⟧')
	eq(child.note('dtm', 'e-swap'), 'd')
	eq(child.shown(), 'd')
	eq(child.state(), CYCLING)
end

T['T195 [char] the cycle\'s start is the window\'s current slot, live'] = function()
	dcb()
	child.steps({ '<M-n>', '<M-S-f>' })
	eq(child.shown(), 'c')
	child.steps({ '<M-S-f>' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	child.steps({ '<M-n>' })
	eq(child.shown() ~= 'd', true)
	child.steps({ '<M-;><M-f>' })
	eq(child.shown(), 'd')
	eq(child.state(), CYCLING)
end

T['T196 [char] while cycling, on the current slot, <M-f> and <M-;><M-r> do their normal job'] = function()
	dcb()
	child.steps({ '<M-n>' })
	eq(child.state(), CYCLING)
	child.steps({ '<M-f>' })
	eq(child.shown(), 'c')
	eq(child.slots(), '⦉d⦊ [c] ⟦b⟧')
	eq(child.state(), CYCLING)
	child.steps({ '<M-f>' })
	eq(child.slots(), '⦉d⦊ [b] ⟦c⟧')
	-- c's secondary note names b: <M-f> writes the swap note (D8, T191).
	eq(child.note('dsm', 'c-swap'), 'b')
	eq(child.state(), CYCLING)
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉a⦊ [b] ⟦c⟧')
	eq(child.state(), CYCLING)
end

T['T175 [char] jumping to another window cancels the cycle'] = function()
	-- win1: ⦉b⦊ [c] ⟦-⟧; win2: ⦉b⦊ [x] ⟦-⟧.
	child.steps({ ':e a', ':e b' })
	local win1 = child.win()
	child.cmd('vsplit')
	child.steps({ ':e x' })
	local win2 = child.win()
	child.cmd('wincmd p')
	child.steps({ ':e c' })
	eq(child.slots(win1), '⦉b⦊ [c] ⟦-⟧')
	eq(child.slots(win2), '⦉b⦊ [x] ⟦-⟧')
	eq(child.ordered(), 'c,b,x,a')

	child.steps({ '<M-n>' })
	eq(child.shown(win1), 'a')
	child.messages()
	child.cmd('wincmd p')
	child.settle(200)
	eq(child.win(), win2)
	no_errors()
	eq(child.shown(win1), 'c')
	eq(child.slots(win1), '⦉b⦊ [c] ⟦-⟧')
	eq(child.state(), NORMAL)
	-- Nothing was recorded for a, the cycled-to buffer: it's still the oldest.
	eq(child.ordered():match('[^,]*$'), 'a')

	child.steps({ ':e d' })
	eq(child.slots(win2), '⦉x⦊ [d] ⟦-⟧')
	eq(child.ordered():match('^[^,]*'), 'd')
end

T['T176 [char] <M-f> fills an empty secondary from the ordered list, asserting its first entry'] = function()
	-- A fresh split: an empty secondary and no ternary.
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	eq(child.slots(), '⦉-⦊ [b] ⟦-⟧')
	eq(child.ordered(), 'b,a')
	child.steps({ '<M-f>' })
	eq(child.slots(), '⦉-⦊ [b] ⟦a⟧')

	-- Again from a fresh split, with the ordered list's first two entries
	-- swapped by hand, so its first entry isn't the window's current buffer.
	child.setup()
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	local res = child.lua([[
		local ord = require('cavediver.domains.history').data.ordered.crux
		ord[1], ord[2] = ord[2], ord[1]
		return { _G.CDV_TEST.press('<M-f>') }
	]])
	eq(res[1], false)
end

T['T197 [char] under the window view the ordered list never ties after two splits'] = function()
	local runs = {}
	for i = 1, 10 do
		child.setup({ history_view = 'window' })
		child.steps({ ':e a', ':e b' })
		child.cmd('vsplit')
		child.cmd('wincmd p')
		child.settle()
		child.steps({ ':e c' })
		child.cmd('vsplit')
		child.settle()
		local first = child.ordered():match('^[^,]*')
		child.messages()
		local ok, err = child.step('<M-f>')
		local errors = Extra.at_least(child.messages())
		local slots = child.slots()
		local c, s = slots:match('%[(.-)%] ⟦(.-)⟧')
		runs[i] = {
			first_is_shown = first == child.shown(),
			ok = ok,
			err = err,
			errors = errors,
			distinct = c ~= s,
		}
	end
	for i = 1, 10 do
		eq(runs[i], { first_is_shown = true, ok = true, errors = {}, distinct = true })
	end
end

T['T198 [char] a jump away from a cycle records the landing, and <M-f> there fills'] = function()
	child.steps({ ':e a' })
	local win1 = child.win()
	child.cmd('vsplit')
	child.steps({ ':e c' })
	local win2 = child.win()
	eq(child.slots(win2), '⦉a⦊ [c] ⟦-⟧')
	child.steps({ '<M-m>' })
	eq(child.shown(win2), 'a')
	child.messages()
	child.cmd('wincmd p')
	child.settle(200)
	eq(child.win(), win1)
	-- The cycle in the second window is cancelled.
	eq(child.shown(win2), 'c')
	eq(child.state(), NORMAL)
	-- The landing in the first window is recorded.
	eq(child.ordered():match('^[^,]*'), 'a')
	local ok, err = child.step('<M-f>')
	eq({ ok, err }, { true, nil })
	no_errors()
	eq(child.slots(win1), '⦉-⦊ [a] ⟦c⟧')
end

T['T206 [char] the secondary restore\'s exchange rewrites b\'s stale note to e\'s own note'] = function()
	child.steps({
		':e a', ':e e', ':e d', '<M-S-f>', ':e b', ':e d',
		'<M-n>', '<M-v>', '<M-f>', ':e b', '<M-f>', ':e e',
		'<M-m>', '<M-m>', '<M-v>',
	})
	eq(child.slots(), '⦉a⦊ [b] ⟦e⟧')
	child.steps({ '<M-;><M-t>' })
	eq(child.slots(), '⦉e⦊ [b] ⟦a⟧')
	eq(child.note('dtm', 'e'), 'd')
	eq(child.note('dtm', 'b'), 'd')
	local ok, err = child.step('<M-;><M-r>')
	eq({ ok, err }, { true, nil })
	eq(child.slots(), '⦉d⦊ [b] ⟦a⟧')
	ok, err = child.step('<M-;><M-r>')
	eq({ ok, err }, { true, nil })
	eq(child.slots(), '⦉e⦊ [b] ⟦a⟧')
end

-- The keys, the window's shown buffer after each, and the slots after the pick.
local function cycle_walk()
	child.steps({ ':e a', ':e b', ':e c', ':e d' })
	local shown = {}
	for _, key in ipairs({ '<M-m>', '<M-m>', '<M-n>' }) do
		child.steps({ key })
		table.insert(shown, child.shown())
	end
	child.steps({ '<M-v>' })
	return { shown = shown, slots = child.slots(), state = child.state() }
end

T['T171 [char] with no cokeline, <M-n> and <M-m> step through the ordered history as with it'] = function()
	local with_cokeline = cycle_walk()
	-- d,c,b,a: <M-m> twice to b, <M-n> back to c, then <M-v> picks c, the ternary.
	eq(with_cokeline.shown, { 'c', 'b', 'c' })
	eq(with_cokeline.slots, '⦉d⦊ [c] ⟦-⟧')
	eq(with_cokeline.state, NORMAL)

	child.setup({ no_cokeline = true })
	eq(child.lua('return (pcall(require, "cokeline.mappings"))'), false)
	eq(cycle_walk(), with_cokeline)
end

T['T79 [char] <M-n> steps left, toward newer buffers, and <M-m> right, toward older'] = function()
	-- Runs against the stub, not the real cokeline: checks the step each key
	-- asks cokeline for, and that cavediver's bufferline order puts the newer
	-- buffer on the left.
	child.steps({ ':e a', ':e b', ':e c' })
	child.settle(300)
	local bufs = child.lua([[
		local out = {}
		for _, s in ipairs({ 'a', 'b', 'c' }) do out[s] = vim.fn.bufnr(_G.CDV_TEST.root .. '/' .. s .. '.txt') end
		return out
	]])
	local cmp = child.lua([[
		local cmp = require('cavediver').bufferline.compare_buffers
		local b = ...
		return { c_before_b = cmp(b.c, b.b), b_before_a = cmp(b.b, b.a), a_before_c = cmp(b.a, b.c) }
	]], { bufs })
	eq(cmp, { c_before_b = true, b_before_a = true, a_before_c = false })

	child.lua([[
		local m = require('cokeline.mappings')
		local orig = m.by_step
		_G.CDV_STEPS = {}
		m.by_step = function(kind, step)
			table.insert(_G.CDV_STEPS, step)
			return orig(kind, step)
		end
	]])
	child.steps({ '<M-m>' })
	eq(child.shown(), 'b')
	child.steps({ '<M-m>' })
	eq(child.shown(), 'a')
	child.steps({ '<M-n>' })
	eq(child.shown(), 'b')
	eq(child.lua('return _G.CDV_STEPS'), { 1, 1, -1 })
end

T['T152 [char] a cycling pick of the secondary rewrites the ternary\'s note to the start'] = function()
	-- {c=c s=a t=b} with dtm[b] = a.
	child.steps({ ':e a', ':e b', ':e c', ':e b', '<M-f>', ':e a', '<M-f>' })
	eq(child.slots(), '⦉b⦊ [c] ⟦a⟧')
	eq(child.note('dtm', 'b'), 'a')
	child.steps({ '<M-m>' })
	eq(child.shown(), 'a')
	child.messages()
	child.steps({ '<M-v>' })
	eq(child.slots(), '⦉b⦊ [a] ⟦c⟧')
	eq(child.note('dtm', 'b'), 'c')
end

T['T172 [char] a pick of an outside buffer writes its plain note and clears its swap note'] = function()
	child.steps({ ':e a', ':e b', '<M-S-f>' })
	eq(child.note('dtm', 'b-swap'), 'a')
	child.steps({ ':e c', ':e d', ':e e' })
	eq(child.slots(), '⦉d⦊ [e] ⟦-⟧')
	child.steps({ '<M-n>' })
	eq(child.shown(), 'b')
	child.steps({ '<M-v>' })
	eq(child.slots(), '⦉d⦊ [b] ⟦-⟧')
	eq(child.note('dtm', 'b'), 'e')
	eq(child.note('dtm', 'b-swap'), '-')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉e⦊ [b] ⟦-⟧')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉d⦊ [b] ⟦-⟧')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉e⦊ [b] ⟦-⟧')
end

T['T155 [char] a pick of an outside buffer notes the start, and <M-;><M-r> brings it back'] = function()
	ecd()
	eq(child.note('dtm', 'b-swap'), '-')
	child.steps({ '<M-n>', '<M-n>' })
	eq(child.shown(), 'b')
	child.steps({ '<M-v>' })
	eq(child.slots(), '⦉d⦊ [b] ⟦c⟧')
	eq(child.note('dtm', 'b'), 'e')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉e⦊ [b] ⟦c⟧')
	eq(child.note('dtm', 'b'), 'd')
end

-- The flight recorder (A26). It isn't built; its dumps go under
-- stdpath('state')/cavediver/.

-- Buffers open now.
local function bufs()
	return child.lua('return vim.api.nvim_list_bufs()')
end

local function new_items(before, after)
	local seen, out = {}, {}
	for _, x in ipairs(before) do seen[x] = true end
	for _, x in ipairs(after) do if not seen[x] then table.insert(out, x) end end
	return out
end

local function read_file(path)
	return child.lua('return vim.fn.readfile(...)', { path })
end

-- Make the current buffer's secondary note name the window's secondary, so
-- the next <M-;><M-t> fires the restore assertion. Set by hand, so the trigger
-- doesn't depend on which route still reaches that state once the restore
-- fixes land (the assertion itself stays).
local function stale_secondary_note(c)
	c.lua([[
		local t = require('cavediver.domains.window').data.crux[vim.api.nvim_get_current_win()]
		t.displacement_secondary_map[t.current_slot .. '-swap'] = nil
		t.displacement_secondary_map[t.current_slot] = t.secondary_slot
	]])
end

-- The last line holding a slot row.
local function last_row(lines)
	local last
	for _, l in ipairs(lines) do
		if l:find('⦉', 1, true) then last = l end
	end
	return last
end

-- N, the ring's length, is ledger.ring (A26, A27); set to 5 here, so ten actions overflow it.
T['T199 [char] with no assertion, the recorder writes no file and opens no buffer, and the ring never holds more than N steps'] = function()
	child.lua('require("cavediver").setup({ ledger = { ring = 5 } })')
	child.steps({ ':e a', ':e b', ':e c', ':e d' })
	local files_before, bufs_before = child.dumps(), bufs()
	child.steps({ '<M-f>', '<M-f>', '<M-S-f>', ':e a', '<M-;><M-r>', '<M-f>', ':e b', '<M-S-f>', '<M-f>', ':e c' })
	child.settle(200)
	eq({
		files = Extra.new_files(files_before, child.dumps()),
		bufs = new_items(bufs_before, bufs()),
		ring = child.lua('return #require("cavediver").ledger.steps()'),
	}, { files = {}, bufs = {}, ring = 5 })
end

T['T200 [target] the restore assertion dumps the last steps to a file and a scratch buffer'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	stale_secondary_note(child)
	local files_before, bufs_before = child.dumps(), bufs()
	local ok, err = child.step('<M-;><M-t>')
	eq(ok, false)
	eq(err:find('Remembered secondary is the same as current secondary', 1, true) ~= nil, true)
	child.settle(200)

	-- A file whose last row is the failing step, on c's slots.
	local files = Extra.new_files(files_before, child.dumps())
	eq(#files > 0, true)
	local row
	for _, f in ipairs(files) do
		local r = last_row(read_file(f))
		if r and r:find('⦉-⦊ [c] ⟦b⟧', 1, true)
			and (r:find('<M-;><M-t>', 1, true) or r:find('restore_secondary', 1, true)) then
			row = r
		end
	end
	eq(row ~= nil, true)

	-- A scratch buffer holds the same rows.
	local scratch = new_items(bufs_before, bufs())
	local found = false
	for _, b in ipairs(scratch) do
		local lines = child.lua('return vim.api.nvim_buf_get_lines(..., 0, -1, false)', { b })
		if last_row(lines) == row then found = true end
	end
	eq(found, true)
end

-- A planted stale note, not a real route: every real route into a rule break is one
-- the decided fixes remove, so the recorder is tested on its own. The note is planted
-- in the other window, so the step taken in this window can't repair it first.
T['T203 [target] a planted rule break dumps at the next step'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	local win1 = child.win()
	eq(child.slots(win1), '⦉b⦊ [c] ⟦-⟧')
	child.cmd('vsplit')
	child.steps({ ':e d', ':e e' })
	-- Plant in the first window: c's ternary note names b, which is already c's ternary.
	child.lua('require("cavediver.domains.window").data.crux[...].displacement_ternary_map[select(2, ...)] = select(3, ...)',
		{ win1, child.hash_of('c'), child.hash_of('b') })
	local before = child.dumps()
	child.steps({ ':e x' })
	child.settle(200)
	eq(#Extra.new_files(before, child.dumps()), 1)
end

T['T204 [target] a session load and a cleanup re-point appear in the dump, tagged load and timer'] = function()
	-- Save a session from this child...
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	local root = child.lua('return _G.CDV_TEST.root')
	child.lua('require("cavediver").save_session(...)', { root })

	-- ...and load it in a second one, with the files open as a session
	-- manager would leave them.
	other.setup()
	other.lua([[
		local root = ...
		require('cavediver.configs').session_dir = root .. '/state/sessions/'
		for _, s in ipairs({ 'a', 'b', 'c' }) do
			local b = vim.fn.bufadd(root .. '/' .. s .. '.txt')
			vim.fn.bufload(b)
			vim.bo[b].buflisted = true
		end
		vim.cmd('noautocmd edit ' .. vim.fn.fnameescape(root .. '/c.txt'))
	]], { root })
	local before = other.dumps()
	other.lua('require("cavediver").load_session(...)', { root })
	other.settle()
	local win1 = other.win()
	eq(other.slots(), '⦉-⦊ [c] ⟦b⟧')

	-- A split on x whose buffer goes away with no events, while the split
	-- shows c: the cleanup timer re-points the split's current slot to c.
	other.cmd('vsplit')
	other.lua('vim.cmd("edit " .. vim.fn.fnameescape(... .. "/x.txt"))', { root })
	other.settle()
	local win2 = other.win()
	eq(other.slots(win2), '⦉c⦊ [x] ⟦-⟧')
	other.lua([[
		local root = ...
		local x = vim.fn.bufnr(root .. '/x.txt')
		vim.cmd('noautocmd buffer ' .. vim.fn.bufnr(root .. '/c.txt'))
		vim.cmd('noautocmd bwipeout ' .. x)
	]], { root })
	for _ = 1, 24 do
		other.settle(250)
		if other.slots(win2) ~= '⦉c⦊ [x] ⟦-⟧' then break end
	end
	eq(other.slots(win2):match('%[(.-)%]'), 'c')

	-- Back in the first window, fire the restore assertion.
	other.cmd('wincmd p')
	other.settle()
	eq(other.win(), win1)
	stale_secondary_note(other)
	local ok = other.step('<M-;><M-t>')
	eq(ok, false)
	other.settle(200)

	local tagged = false
	for _, f in ipairs(Extra.new_files(before, other.dumps())) do
		local text = table.concat(other.lua('return vim.fn.readfile(...)', { f }), '\n')
		if text:find('%f[%w]load%f[%W]') and text:find('%f[%w]timer%f[%W]') then tagged = true end
	end
	eq(tagged, true)
end

T['T205 [target] a failure that repeats gives one dump, and the dump window is nofile, unlisted, untracked and unrecorded'] = function()
	-- Nothing tracked yet, so the bufferline's colour callback throws on every
	-- call, as it would on every redraw.
	local files_before, bufs_before = child.dumps(), bufs()
	local errs = child.lua([[
		local fg = require('cavediver').bufferline.get_theme_bg_color
		local n = 0
		for _ = 1, 10 do
			if not pcall(fg, true) then n = n + 1 end
		end
		return n
	]])
	eq(errs, 10)
	child.settle(300)
	eq(#Extra.new_files(files_before, child.dumps()), 1)

	local scratch = new_items(bufs_before, bufs())
	eq(#scratch > 0, true)
	local dump_wins, dump_names = {}, {}
	for _, b in ipairs(scratch) do
		eq(child.lua('return { vim.bo[...].buftype, vim.bo[...].buflisted }', { b, b }), { 'nofile', false })
		eq(child.lua('return require("cavediver.domains.history").get_hash_from_buffer(...)', { b }), vim.NIL)
		local name = child.lua('return vim.api.nvim_buf_get_name(...)', { b })
		if name ~= '' then table.insert(dump_names, name) end
		local wins = child.lua('return vim.fn.win_findbuf(...)', { b })
		for _, w in ipairs(wins) do
			eq(child.lua('return require("cavediver.domains.window").data.crux[...] == nil', { w }), true)
			table.insert(dump_wins, w)
		end
	end
	eq(child.ordered(), '')

	-- Entering the dump window isn't recorded: after a visit there, a second,
	-- different failure (a hook bound by hand to fail, as in T275) dumps
	-- steps that never name that window or its buffer. Matched by whole word,
	-- since the dump's format is open.
	for _, w in ipairs(dump_wins) do
		child.lua('vim.api.nvim_set_current_win(...)', { w })
		child.settle()
		child.cmd('wincmd p')
		child.settle()
	end
	child.lua([[
		require('cavediver.domains.history').sm:on('attached', 'attached', 't205_breaks', function() error('planted') end, 5, true)
	]])
	local files_mid = child.dumps()
	child.steps({ ':e a', ':e b' })
	child.settle(300)
	local second = Extra.new_files(files_mid, child.dumps())
	eq(#second > 0, true)
	for _, f in ipairs(second) do
		local text = table.concat(read_file(f), '\n')
		for _, w in ipairs(dump_wins) do
			eq(text:find('%f[%w]' .. w .. '%f[%W]') == nil, true)
		end
		for _, name in ipairs(dump_names) do
			eq(text:find(name, 1, true) == nil, true)
		end
	end
end

-- T200's route. The scratch buffer isn't opened inside the failing call, only
-- once the editor settles; and files are named by alias and basename, never by
-- their full path, in the file and in the scratch buffer alike.
T['T333 [target] a dump opens after the editor settles, and names files by alias and basename, never by full path'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	stale_secondary_note(child)
	local files_before, bufs_before = child.dumps(), bufs()
	local during = child.lua([[
		local ok = _G.CDV_TEST.press('<M-;><M-t>')
		return { ok = ok, bufs = vim.api.nvim_list_bufs() }
	]])
	eq(during.ok, false)
	eq(new_items(bufs_before, during.bufs), {})
	child.settle(300)
	local scratch = new_items(bufs_before, bufs())
	eq(#scratch > 0, true)

	local root = child.lua('return _G.CDV_TEST.root')
	local files = Extra.new_files(files_before, child.dumps())
	eq(#files > 0, true)
	local texts = {}
	for _, f in ipairs(files) do table.insert(texts, table.concat(read_file(f), '\n')) end
	for _, b in ipairs(scratch) do
		table.insert(texts, table.concat(child.lua('return vim.api.nvim_buf_get_lines(..., 0, -1, false)', { b }), '\n'))
	end
	for _, text in ipairs(texts) do
		eq(text:find(root, 1, true) == nil, true)
		eq(text:find('c.txt', 1, true) ~= nil, true)
	end
end

return T
