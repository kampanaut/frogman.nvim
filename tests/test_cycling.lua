-- Cycling: <M-n>, <M-m>, <M-v> and cancelling (A12-A14), with the flight
-- recorder tests the spec files here (A26). IDs are the spec's
-- (what-is-cavediver.md, section 7).
--
-- The cokeline stub steps through cavediver's ordered history, index 1 the
-- newest: <M-n> is by_step(-1), toward newer (wrapping from the newest to the
-- oldest), <M-m> is by_step(1), toward older.
local Helpers = dofile('tests/helpers.lua')
local Extra = dofile('tests/helpers_cycling.lua')
local Misc = dofile('tests/helpers_misc.lua')
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

-- The flight recorder (A26). Its dumps go under stdpath('state')/cavediver/.

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

-- A dump's text, decrypted as :CavediverDump reads it: the file is sealed.
local function read_file(path)
	return child.lua('return vim.split(require("cavediver.domains.ledger.dump").read(...) or "", "\\n", { plain = true })', { path })
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

T['T200 [char] the restore assertion dumps the last steps to a file and a scratch buffer'] = function()
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
T['T203 [char] a planted rule break dumps at the next step'] = function()
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

T['T204 [char] a session load and a cleanup re-point appear in the dump, tagged load and timer'] = function()
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
		vim.cmd.cd(root) -- the session's directory keys its file
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
		local text = other.lua('return require("cavediver.domains.ledger.dump").read(...) or ""', { f })
		if text:find('%f[%w]load%f[%W]') and text:find('%f[%w]timer%f[%W]') then tagged = true end
	end
	eq(tagged, true)
end

T['T205 [char] a failure that repeats gives one dump, and the dump window is nofile, unlisted, untracked and unrecorded'] = function()
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
-- once the editor settles; and files are named by their full path and hash, in
-- the file and in the scratch buffer alike: the file is sealed.
T['T333 [char] a dump opens after the editor settles, and names files by their paths'] = function()
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
	local c = child.hash_of('c')
	for _, text in ipairs(texts) do
		eq({ path = text:find(root .. '/c.txt', 1, true) ~= nil, hash = text:find(c, 1, true) ~= nil }, { path = true, hash = true })
	end
end


T['T333 [char] a hook failure\'s dump, with a list named by the cwd, holds the hook and the session'] = function()
	child.steps({ ':e a', ':e b' })
	local root = child.lua('return _G.CDV_TEST.root')
	child.lua('require("cavediver").save_session(..., { tab = vim.api.nvim_get_current_tabpage() })', { root })
	child.lua([[
		require('cavediver.domains.history').sm:on('attached', 'attached', 't333_breaks', function() error('planted') end, 5, true)
	]])
	local files_before, bufs_before = child.dumps(), bufs()
	child.steps({ ':e c' })
	child.settle(300)
	local texts = {}
	for _, f in ipairs(Extra.new_files(files_before, child.dumps())) do table.insert(texts, table.concat(read_file(f), '\n')) end
	for _, b in ipairs(new_items(bufs_before, bufs())) do
		if child.lua('return vim.bo[...].buftype', { b }) == 'nofile' then -- the dump's, not c.txt's
			table.insert(texts, table.concat(child.lua('return vim.api.nvim_buf_get_lines(..., 0, -1, false)', { b }), '\n'))
		end
	end
	eq(#texts >= 2, true)
	for _, text in ipairs(texts) do
		eq({ session = text:find(root, 1, true) ~= nil, hook = text:find('t333_breaks', 1, true) ~= nil },
			{ session = true, hook = true })
	end
end

-- T200's route. The file on disk is sealed, and :CavediverDump opens it from the
-- directory it was written in only.
T['T460 [char] a dump is sealed, and :CavediverDump opens it from the directory it was written in'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	stale_secondary_note(child)
	local files_before = child.dumps()
	eq(child.step('<M-;><M-t>'), false)
	child.settle(300)
	local files = Extra.new_files(files_before, child.dumps())
	eq(#files, 1)
	eq(child.lua([[
		local f = io.open(..., "rb")
		local bytes = f:read("*a")
		f:close()
		return {
			head = bytes:sub(1, 4),
			clear = bytes:find("c.txt", 1, true) ~= nil or bytes:find("<M-;><M-t>", 1, true) ~= nil
				or bytes:find("cavediver:", 1, true) ~= nil,
		}
	]], { files[1] }), { head = 'CDV1', clear = false })

	child.cmd('CavediverDump ' .. vim.fn.fnameescape(files[1]))
	child.settle(200)
	local lines = child.lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)')
	eq(last_row(lines):find('<M-;><M-t>', 1, true) ~= nil, true)
	eq(vim.tbl_contains(lines, 'replay:'), true)
	child.type_keys('q')
	child.settle()

	child.lua('vim.fn.mkdir(_G.CDV_TEST.root .. "/sub", "p"); vim.cmd.cd(_G.CDV_TEST.root .. "/sub")')
	local bufs_before = bufs()
	child.messages()
	child.cmd('CavediverDump ' .. vim.fn.fnameescape(files[1]))
	child.settle(200)
	eq(new_items(bufs_before, bufs()), {})
	eq(Extra.has(child.messages(), "doesn't open here"), true)
end

-- T461 and T462's setup: the first window at ⦉a⦊ [b] ⟦-⟧ with p=[a]on, and a split,
-- focused, at ⦉b⦊ [c] ⟦-⟧, cycling there (<M-m>). Window numbers depend on 'splitright' (off
-- here, so the split opens on the left as window 1), so the cases read them from the windows.
local function cycling_in_split(splitright)
	child.lua('vim.o.splitright = ...', { splitright == true })
	child.steps({ ':e a', '<M-;><M-c>', ':e b' })
	local first = child.win()
	eq(child.slots(first), '⦉a⦊ [b] ⟦-⟧')
	child.cmd('vsplit')
	child.settle()
	child.steps({ ':e c' })
	local split = child.win()
	eq(child.slots(split), '⦉b⦊ [c] ⟦-⟧')
	child.steps({ '<M-m>' })
	eq(child.state(), CYCLING)
	return first, split
end

local function number(winid)
	return child.lua('return vim.api.nvim_win_get_number(...)', { winid })
end

-- Keys in one batch, as a macro or a mapping sends them: <M-;><M-f> reaches the first
-- window before the jump's cancel has settled. Once with 'splitright' off, once on.
local function key_before_cancel(splitright)
	child.setup()
	local first, split = cycling_in_split(splitright)
	local before = child.dumps()
	child.messages()
	-- a throw in the batch doesn't come back through feedkeys: the dump count is what shows one
	child.lua([[pcall(vim.api.nvim_feedkeys, vim.api.nvim_replace_termcodes('<C-w>w<M-;><M-f>', true, false, true), 'x', false)]])
	child.settle(200)
	eq({ dumps = #Extra.new_files(before, child.dumps()), nav = child.state().nav, split = child.shown(split) },
		{ dumps = 0, nav = 'normal', split = 'c' })
	-- said once: the cancel the jump scheduled finds the cycle over and does nothing
	local said = vim.tbl_filter(function(m)
		return m.msg == 'Cycling cancelled. Window ' .. number(split) .. ' returned to cycling origin buffer: c.txt'
	end, child.messages())
	eq(#said, 1)
	eq(child.slots(first), '⦉b⦊ [a] ⟦-⟧')
	-- the cancel is a move on the window jump's step, as typed by hand
	eq(child.lua([[
		for _, step in ipairs(require('cavediver').ledger.steps()) do
			for _, move in ipairs(step.moves) do
				if move.kind == 'cancelled' then return step.trigger end
			end
		end
	]]), 'WinEnter win ' .. number(first))
end

T['T461 [char] a key that comes before the cancel runs it first, then does its job'] = function()
	key_before_cancel(false)
	key_before_cancel(true)
end

-- Keys in one batch, through the settle queue (M11): each key first runs what's still queued.
local function batch(keys)
	child.lua([[pcall(vim.api.nvim_feedkeys, vim.api.nvim_replace_termcodes(..., true, false, true), 'x', false)]], { keys })
	child.settle(200)
end

-- From a fresh editor: the empty start buffer picked, then reused for b.txt, then a cycle.
T['T464 [char] a cycle started before its window\'s arrival has settled starts from it'] = function()
	local before = child.dumps()
	child.messages()
	batch('<M-m><M-m><M-v>:e b.txt<CR><M-m>')
	eq({ hooks = Extra.has(child.messages(), "Hook '"), dumps = #Extra.new_files(before, child.dumps()),
		nav = child.state().nav, current = child.slots():match('%[(.-)%]') }, { hooks = false, dumps = 0, nav = 'cycling', current = 'b' })
end

T['T465 [char] a key in a macro acts on the buffer the macro just opened'] = function()
	child.steps({ ':e a', ':e c' })
	eq(child.slots(), '⦉a⦊ [c] ⟦-⟧')
	batch(':e b.txt<CR><M-f>')
	eq({ shown = child.shown(), slots = child.slots() }, { shown = 'b', slots = '⦉-⦊ [b] ⟦c⟧' })
end

T['T466 [char] keys in one batch keep their order'] = function()
	child.steps({ ':e e', ':e a', '<M-f>', ':e c' })
	eq(child.slots(), '⦉a⦊ [c] ⟦e⟧')
	batch(':e b.txt<CR><M-f>:e d.txt<CR>')
	eq(child.slots(), '⦉e⦊ [d] ⟦b⟧')
end

T['T467 [char] a dump lists the settle work still queued'] = function()
	child.steps({ ':e a' })
	local before = child.dumps()
	child.lua([[
		vim.cmd('edit b.txt')
		pcall(require('cavediver.domains.ledger').never, 'planted for T467')
	]])
	child.settle(200)
	local files = Extra.new_files(before, child.dumps())
	eq(#files, 1)
	local text = child.lua('return require("cavediver.domains.ledger.dump").read(...) or ""', { files[1] })
	eq(text:match('\npending: ([^\n]*)'), 'arrival b.txt')
end

T['T510 [char] a cycle key in a window with no triquetra starts nothing'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('help')
	child.settle()
	child.messages()
	local dumps = child.dumps()
	child.steps({ '<M-m>' })
	local said = Extra.has(child.messages(), 'Window with unregistered buffer.')
	local state, help = child.state(), child.lua('return vim.bo.buftype')
	child.step('<M-;><M-f>')
	child.settle(200)
	eq({ said = said, state = state, help = help, dumps = #Extra.new_files(dumps, child.dumps()) },
		{ said = true, state = NORMAL, help = 'help', dumps = 0 })
end

T['T511 [char] the command-line window doesn\'t cancel a cycle'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-m>' })
	eq(child.state(), CYCLING)
	child.messages()
	child.type_keys('q:')
	child.lua('vim.wait(300)')
	child.type_keys('<C-c>')
	child.lua('vim.wait(300)')
	eq({ errors = Extra.at_least(child.messages()), state = child.state() }, { errors = {}, state = CYCLING })
end

T['T512 [char] a tab session\'s load into a tab cycling there ends the cycle'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.lua('return { pcall(require("cavediver").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.steps({ ':e d', '<M-n>' })
	eq(child.state(), CYCLING)
	child.lua('require("cavediver").load_session("t", { tab = vim.api.nvim_get_current_tabpage() })')
	child.settle(200)
	local state = child.state()
	local before = child.slots()
	child.steps({ '<M-n>' })
	eq({ state = state, slots = child.slots() }, { state = NORMAL, slots = before })
end

-- The cycle runs in the first tab, and the session loads into a second one from there.
T['T512 [char] a tab session\'s load into another tab ends a cycle running elsewhere'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.lua('return { pcall(require("cavediver").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	child.steps({ ':e d', '<M-n>' })
	eq(child.state(), CYCLING)
	child.lua([[
		local here = vim.api.nvim_get_current_win()
		vim.cmd('noautocmd tabnew')
		local tab = vim.api.nvim_get_current_tabpage()
		vim.cmd('noautocmd tabprevious')
		vim.api.nvim_set_current_win(here)
		require('cavediver').load_session('t', { tab = tab })
	]])
	child.settle(200)
	local state = child.state()
	local before = child.slots()
	child.steps({ '<M-n>' })
	eq({ state = state, slots = child.slots() }, { state = NORMAL, slots = before })
end

-- The replay (A26). A project made by the runner outlives the editors: one makes the dump,
-- a fresh one in the same project replays it, since a dump opens only from its directory.

-- Keys and a typed command line in one batch: the ledger records the command line as a step.
local function typed(keys)
	child.lua([[pcall(vim.api.nvim_feedkeys, vim.api.nvim_replace_termcodes(..., true, false, true), 'x', false)]], { keys })
	child.settle(200)
end

-- The one dump written since `before`.
local function the_dump(before)
	local files = Extra.new_files(before, child.dumps())
	eq(#files, 1)
	return files[1]
end

local function replay(path)
	return child.lua('return require("cavediver").replay_dump(...)', { path })
end

-- T200's route, the stale note planted by a typed :lua line and <M-;><M-t> in the same batch,
-- so the :lua step closes at once and the restore's assertion is the one dump.
local STALE = ":lua _G.CDV_PLANTED = true; local t = require('cavediver.domains.window').data.crux[vim.api.nvim_get_current_win()];"
	.. " t.displacement_secondary_map[t.current_slot .. '-swap'] = nil; t.displacement_secondary_map[t.current_slot] = t.secondary_slot<CR>"

T['T201 [char] a dumped file replays to the same assertion'] = function()
	local root = Misc.make_project()
	Misc.start(child, { root = root })
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	local before = child.dumps()
	typed(STALE .. '<M-;><M-t>')
	local path = the_dump(before)
	Misc.start(child, { root = root })
	local r = replay(path)
	eq({
		error = r.failure ~= nil and r.failure.error:find('Remembered secondary is the same as current secondary', 1, true) ~= nil,
		mismatches = #r.mismatches,
		resynced = r.resynced,
		ran = child.lua('return _G.CDV_PLANTED == true'),
	}, { error = true, mismatches = 0, resynced = 0, ran = false })
end

T['T202 [char] replaying the snapshot and the steps reproduces every driven step\'s row'] = function()
	local root = Misc.make_project()
	Misc.start(child, { root = root })
	child.steps({ ':e a', ':e b', ':e c' })
	local keys = {}
	for _ = 1, 110 do table.insert(keys, '<M-S-f>') end
	child.steps(keys)
	local before = child.dumps()
	child.lua([[pcall(require('cavediver.domains.ledger').never, 'planted for T202')]])
	child.settle(200)
	local path = the_dump(before)
	Misc.start(child, { root = root })
	local r = replay(path)
	eq({ snapshot = r.snapshot, enough = r.driven >= 50, matched = r.matched == r.driven, mismatches = #r.mismatches, resynced = r.resynced },
		{ snapshot = true, enough = true, matched = true, mismatches = 0, resynced = 0 })
end

T['T470 [char] a replay runs no code a command line chains or carries'] = function()
	local root = Misc.make_project()
	Misc.start(child, { root = root })
	child.steps({ ':e a' })
	typed(':e b.txt | lua _G.CDV_PLANTED = true<CR>')
	typed(':e +lua\\ _G.CDV_PLANTED=true c.txt<CR>')
	eq(child.lua('return _G.CDV_PLANTED'), true) -- they ran here, in the editor that made the dump
	local before = child.dumps()
	child.lua([[pcall(require('cavediver.domains.ledger').never, 'planted for T470')]])
	child.settle(200)
	local path = the_dump(before)
	Misc.start(child, { root = root })
	local r = replay(path)
	eq({ ran = child.lua('return _G.CDV_PLANTED == true'), failure = r.failure == nil }, { ran = false, failure = true })
end

T['T468 [char] a replay\'s editor isn\'t saved'] = function()
	local root = Misc.make_project()
	Misc.start(child, { root = root })
	child.steps({ ':e a' })
	local before = child.dumps()
	child.lua([[pcall(require('cavediver.domains.ledger').never, 'planted for T468')]])
	child.settle(200)
	local path = the_dump(before)
	Misc.start(child, { root = root })
	replay(path)
	local res = child.lua([[
		local ok, err = pcall(require('cavediver').save_session)
		return { ok = ok, err = tostring(err), files = #vim.fn.globpath(require('cavediver.configs').session_dir, '*', false, true) }
	]])
	eq({ ok = res.ok, said = res.err:find("this editor replayed a dump", 1, true) ~= nil, files = res.files },
		{ ok = false, said = true, files = 0 })
end

T['T471 [char] a replay goes into an editor that has taken in the empty buffer it started on'] = function()
	local root = Misc.make_project()
	Misc.start(child, { root = root })
	child.steps({ ':e a' })
	local before = child.dumps()
	child.lua([[pcall(require('cavediver.domains.ledger').never, 'planted for T471')]])
	child.settle(200)
	local path = the_dump(before)
	Misc.start(child, { root = root })
	-- as a config that calls setup() at startup has it: the start buffer entered once cavediver is set up
	child.cmd('doautocmd BufEnter')
	child.settle(200)
	local start = child.lua('return vim.api.nvim_get_current_buf()')
	eq({ registered = child.lua('return require("cavediver.domains.history").data.hash_buffer_registry.hashes[...] ~= nil', { start }),
		triquetras = child.lua('return vim.tbl_count(require("cavediver.domains.window").data.crux)') },
		{ registered = true, triquetras = 1 })
	child.messages()
	local r = replay(path)
	eq({
		replayed = type(r) == "table",
		refused = Extra.has(child.messages(), 'tracks buffers already'),
		start = child.lua('return require("cavediver.domains.history").data.hash_buffer_registry.hashes[...] ~= nil', { start }),
		shows = child.lua('return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")'),
	}, { replayed = true, refused = false, start = false, shows = 'a.txt' })
end

-- A dump made by `body`, in a fresh child in a fresh project, after a planted never; then a
-- fresh child in the same project, `before_replay` run in it, and the replay. Returns the result.
local function made_and_replayed(body, before_replay)
	local root = Misc.make_project()
	Misc.start(child, { root = root })
	body(root)
	local before = child.dumps()
	child.lua([[pcall(require('cavediver.domains.ledger').never, 'planted for the replay')]])
	child.settle(200)
	local path = the_dump(before)
	Misc.start(child, { root = root })
	if before_replay then before_replay(root) end
	return replay(path), root
end

T['T486 [char] a command line whose path the ledger cut is planted, not driven'] = function()
	local r, root = made_and_replayed(function(root)
		vim.fn.mkdir(root .. '/sub', 'p')
		vim.fn.writefile({ 'deep' }, root .. '/sub/deep.txt')
		child.steps({ ':e a' })
		typed(':e sub/deep.txt<CR>')
		child.steps({ ':e b' })
	end)
	eq({ mismatches = #r.mismatches, stray = child.lua('return vim.fn.bufnr(...)', { root .. '/deep.txt' }) },
		{ mismatches = 0, stray = -1 })
end

T['T487 [char] a command naming the original editor\'s buffers is planted'] = function()
	local r = made_and_replayed(function()
		child.steps({ ':e a', ':e b' })
		typed(':e #<CR>')
		typed(':b 1<CR>')
	end)
	eq({ mismatches = #r.mismatches, hash = child.lua([[return vim.fn.bufnr('^#$')]]) }, { mismatches = 0, hash = -1 })
end

for _, splitright in ipairs({ false, true }) do
	T['T488 [char] a split reaches the dump and replays, splitright ' .. tostring(splitright)] = function()
		local r = made_and_replayed(function()
			child.lua('vim.o.splitright = ...', { splitright })
			child.steps({ ':e a', ':e b' })
			typed(':vsplit<CR>')
			typed(':e c.txt<CR>')
			typed(':close<CR>')
			typed(':e d.txt<CR>')
		end)
		eq({ failure = r.failure, mismatches = #r.mismatches, enough = r.driven >= 4 }, { failure = nil, mismatches = 0, enough = true })
	end
end

T['T489 [char] a replay writes no dump of its own'] = function()
	local root = Misc.make_project()
	Misc.start(child, { root = root })
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	local before = child.dumps()
	typed(STALE .. '<M-;><M-t>')
	local path = the_dump(before)
	Misc.start(child, { root = root })
	local before_replay = child.dumps()
	local r = replay(path)
	child.settle(200)
	eq({ reproduced = r.failure ~= nil, new = #Extra.new_files(before_replay, child.dumps()) }, { reproduced = true, new = 0 })
end

-- The split's buffer x is wiped without events while c is shown in its place; the cleanup
-- tick's step re-points the split, a step with no window and no row of its own.
T['T490 [char] a cleanup tick\'s repair doesn\'t throw a replay off'] = function()
	local r = made_and_replayed(function()
		child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
		child.cmd('vsplit')
		child.steps({ ':e x' })
		child.cmd('noautocmd buffer ' .. child.lua('return vim.fn.bufnr(_G.CDV_TEST.root .. "/c.txt")'))
		child.cmd('noautocmd bwipeout ' .. child.lua('return vim.fn.bufnr(_G.CDV_TEST.root .. "/x.txt")'))
		child.lua([[require('cavediver.domains.ledger.routines').within('timer', 'cleanup', require('cavediver.domains.history').routines.cleanup_system, true)]])
		child.settle(200)
		child.steps({ '<M-S-f>' })
	end)
	eq({ mismatches = #r.mismatches, resynced = (r.resynced or 0) >= 1 }, { mismatches = 0, resynced = true })
end

T['T491 [char] a float in the replaying editor isn\'t one of its windows'] = function()
	local keys = {}
	for _ = 1, 110 do table.insert(keys, '<M-S-f>') end
	local r = made_and_replayed(function()
		child.steps({ ':e a', ':e b', ':e c' })
		child.cmd('vsplit')
		child.steps({ ':e d' })
		child.steps(keys)
	end, function()
		child.lua([[_G.CDV_FLOAT = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false,
			{ relative = 'editor', row = 1, col = 1, width = 10, height = 2 })]])
	end)
	eq({
		mismatches = #r.mismatches,
		float = child.lua('return require("cavediver.domains.window").data.crux[_G.CDV_FLOAT] ~= nil'),
		windows = child.lua([[return #vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative == '' end, vim.api.nvim_tabpage_list_wins(0))]]),
	}, { mismatches = 0, float = false, windows = 2 })
end

T['T492 [char] with a short ring the dump\'s snapshot and steps still meet'] = function()
	local function toggles(n)
		local keys = {}
		for _ = 1, n do table.insert(keys, '<M-S-f>') end
		return keys
	end
	local r = made_and_replayed(function()
		child.lua('require("cavediver.configs").ledger.ring = 20')
		child.steps({ ':e a', ':e b', ':e c' })
		child.steps(toggles(55))
		child.steps({ ':e d', ':e e', ':e f' })
		child.steps(toggles(57))
	end, function()
		child.lua('require("cavediver.configs").ledger.ring = 20')
	end)
	eq({ mismatches = #r.mismatches, driven = r.driven > 0 }, { mismatches = 0, driven = true })
end

T['T493 [char] a replayed editor writes no records as a tab session\'s tab closes'] = function()
	local root = Misc.make_project()
	Misc.start(child, { root = root })
	child.steps({ ':e a' })
	local before = child.dumps()
	child.lua([[pcall(require('cavediver.domains.ledger').never, 'planted for T493')]])
	child.settle(200)
	local path = the_dump(before)
	Misc.start(child, { root = root })
	child.steps({ ':e a' })
	child.cmd('tabnew')
	child.steps({ ':e b' })
	eq(child.lua('return { pcall(require("cavediver").save_session, "t", { tab = vim.api.nvim_get_current_tabpage() }) }'), { true })
	local main = child.lua([[
		local dir = require('cavediver.configs').session_dir
		local want = vim.fn.sha256(vim.fn.getcwd(-1, -1) .. '\n' .. 't')
		for _, f in ipairs(vim.fn.readdir(dir)) do
			if f:sub(1, #want) == want and not f:match('%.d$') then return dir .. f end
		end
	]])
	local function raw(file)
		local fh = assert(io.open(file, 'rb'))
		local out = fh:read('*a')
		fh:close()
		return out
	end
	Misc.start(child, { root = root })
	replay(path)
	local bytes = raw(main)
	child.cmd('tabnew')
	child.lua('require("cavediver").load_session("t", { tab = vim.api.nvim_get_current_tabpage() })')
	child.settle(200)
	child.steps({ ':e c' })
	child.cmd('tabclose')
	child.settle(300)
	eq(raw(main) == bytes, true)
end

-- T201's stale note planted by a typed :lua line held open on its own: its close finds I23
-- broken and dumps. The replay plants that row, so the rule is broken at its end.
T['T494 [char] a replay reports a slot rule its dump fired at'] = function()
	local root = Misc.make_project()
	Misc.start(child, { root = root })
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	local before = child.dumps()
	typed(STALE)
	child.settle(300)
	local path = the_dump(before)
	Misc.start(child, { root = root })
	local before_replay = child.dumps()
	local r = replay(path)
	child.settle(200)
	eq({ i23 = table.concat(r.fired or {}, '\n'):find('I23', 1, true) ~= nil, failure = r.failure, new = #Extra.new_files(before_replay, child.dumps()) },
		{ i23 = true, failure = nil, new = 0 })
end

T['T469 [char] a dump that spans more than one tab isn\'t replayed'] = function()
	local root = Misc.make_project()
	Misc.start(child, { root = root })
	child.steps({ ':e a' })
	child.cmd('tabnew')
	child.steps({ ':e b' })
	local before = child.dumps()
	child.lua([[pcall(require('cavediver.domains.ledger').never, 'planted for T469')]])
	child.settle(200)
	local path = the_dump(before)
	Misc.start(child, { root = root })
	child.messages()
	local r = replay(path)
	eq({ said = Extra.has(child.messages(), 'spans more than one tab'), windows = child.lua('return #vim.api.nvim_list_wins()'),
		triquetras = child.lua('return vim.tbl_count(require("cavediver.domains.window").data.crux)') },
		{ said = true, windows = 1, triquetras = 0 })
end

-- A user's own Lua mapping: a window jump and an export, in one function.
T['T463 [char] an export called from a user\'s mapping runs the cancel first too'] = function()
	local first, split = cycling_in_split()
	local before = child.dumps()
	local ok = child.lua([[return (pcall(function()
		vim.cmd.wincmd('w')
		require('cavediver').jump_to_primary()
	end))]])
	child.settle(200)
	eq({ ok = ok, dumps = #Extra.new_files(before, child.dumps()), split = child.shown(split), first = child.slots(first) },
		{ ok = true, dumps = 0, split = 'c', first = '⦉b⦊ [a] ⟦-⟧' })
end

T['T462 [char] a jump\'s cancel says so'] = function()
	local _, split = cycling_in_split()
	child.messages()
	child.cmd('wincmd w')
	child.settle(200)
	local said = vim.tbl_filter(function(m)
		return m.msg == 'Cycling cancelled. Window ' .. number(split) .. ' returned to cycling origin buffer: c.txt'
			and m.level == vim.log.levels.INFO
	end, child.messages())
	eq(#said, 1)
end

return T
