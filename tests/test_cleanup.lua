-- Deletes, renames and cleanup (A19-A22). IDs are the spec's
-- (what-is-cavediver.md, section 7).
local Helpers = dofile('tests/helpers.lua')
local eq = Helpers.eq
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = child.stop,
	},
})

-- The current slot's name, from the slots row.
local function current() return child.slots():match('%[(.-)%]') end

-- A buffer of the temporary project, by file name: { valid, lines, registered, in history }.
local function buffer_state(file)
	return child.lua([[
		local H = require('frogman.domains.history')
		local b = vim.fn.bufnr(_G.FRG_TEST.root .. '/' .. ...)
		if b == -1 or not vim.api.nvim_buf_is_valid(b) then return { valid = false } end
		local h = H.get_hash_from_buffer(b)
		return {
			valid = true,
			lines = vim.api.nvim_buf_get_lines(b, 0, -1, false),
			registered = h ~= nil,
			in_history = h ~= nil and H.data.crux[h] ~= nil,
		}
	]], { file })
end

local function remove_on_disk(file)
	child.lua('os.remove(_G.FRG_TEST.root .. "/" .. ...)', { file })
end

T['T102 [char] :bdelete of the ternary keeps it as a closed hash'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	child.cmd('bdelete b.txt')
	child.settle()
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	eq(child.closed(), 'b')
end

T['T103 [char] :bdelete of the secondary keeps the secondary (I4)'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	child.cmd('bdelete b.txt')
	child.settle()
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	eq(child.closed(), 'b')
end

T['T104 [char] :bdelete of a primary entry keeps it in the queue (I4)'] = function()
	child.steps({ ':e a', '<M-;><M-c>', ':e b', ':e c' })
	eq(child.primary(), '[a]on')
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	child.cmd('bdelete a.txt')
	child.settle()
	eq(child.primary(), '[a]on')
end

T['T105 [char] closing an empty No Name buffer does not push it on the closed stack'] = function()
	child.steps({ ':e a', ':enew', '<M-.>' })
	eq(child.shown(), 'a')
	eq(child.closed(), '')
end

T['T106 [char] :file new.lua keeps unsaved edits'] = function()
	child.steps({ ':e a' })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "edited" })')
	child.cmd('file new.lua')
	child.settle(300)
	local st = buffer_state('new.lua')
	eq(st.valid, true)
	eq(st.lines, { 'edited' })
end

T['T106 [char] :saveas new.lua keeps unsaved edits'] = function()
	child.steps({ ':e a' })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "edited" })')
	child.cmd('saveas new.lua')
	child.settle(300)
	local st = buffer_state('new.lua')
	eq(st.valid, true)
	eq(st.lines, { 'edited' })
	eq(child.lua('return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t")'), 'new.lua')
end

-- b is the ternary, the primary and a note's key; it's moved on disk to g.txt
-- and renamed in place, the way LSP and oil renames do (nvim_buf_set_name).
T['T107 [char] a rename whose old file is gone moves every reference and pushes nothing'] = function()
	child.steps({ ':e a', ':e b', '<M-;><M-c>', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	eq(child.primary(), '[b]on')
	eq(child.notes(), 'dtm{b>a} dsm{}')
	child.lua([[
		local root = _G.FRG_TEST.root
		os.rename(root .. '/b.txt', root .. '/g.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/b.txt'), root .. '/g.txt')
	]])
	child.settle(300)
	eq(child.slots(), '⦉g⦊ [c] ⟦-⟧')
	eq(child.primary(), '[g]on')
	eq(child.notes(), 'dtm{g>a} dsm{}')
	eq(child.closed(), '')
end

-- How many loaded buffers hold a line that reads exactly `text`.
local function holding(text)
	return child.lua([[
		local n = 0
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(b) and vim.tbl_contains(vim.api.nvim_buf_get_lines(b, 0, -1, false), ...) then
				n = n + 1
			end
		end
		return n
	]], { text })
end

-- b.txt stays on disk, so taking b's name away is a copy: b is closed, and the
-- buffer goes on as a No Name buffer, the edit in it.
T['T481 [char] (A20, I12) :0file on a modified file keeps its edits through a close'] = function()
	child.steps({ ':e a', ':e b' })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "the edit" })')
	child.cmd('0file')
	child.settle(300)
	child.steps({ '<M-.>' })
	child.settle(300)
	child.steps({ '<M-S-w>' })
	child.settle(300)
	eq(holding('the edit'), 1)
end

-- c.txt and d.txt are loaded and edited the way a workspace edit does it,
-- without being entered, then written together.
T['T482 [char] (A20, M3) a write of buffers never entered moves no window\'s slots'] = function()
	child.steps({ ':e a', ':e b' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	child.lua([[
		for _, f in ipairs({ 'c.txt', 'd.txt' }) do
			local b = vim.fn.bufadd(_G.FRG_TEST.root .. '/' .. f)
			vim.bo[b].buflisted = true
			vim.fn.bufload(b)
			vim.api.nvim_buf_set_lines(b, 0, -1, false, { 'edited ' .. f })
		end
	]])
	child.cmd('wall')
	child.settle(300)
	local registered = child.lua([[
		local H = require('frogman.domains.history')
		local out = {}
		for _, f in ipairs({ 'c.txt', 'd.txt' }) do
			table.insert(out, H.get_hash_from_buffer(vim.fn.bufnr(_G.FRG_TEST.root .. '/' .. f)) ~= nil)
		end
		return out
	]])
	eq({ slots = child.slots(), registered = registered }, { slots = '⦉a⦊ [b] ⟦-⟧', registered = { true, true } })
end

-- a's buffer is wiped, so the ternary holds a closed; b.txt then goes over
-- a.txt on disk and b's buffer takes a's name, as an LSP or oil rename does.
T['T483 [char] (A20, I1) a move onto a file the ternary holds leaves no file in two slots'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('bwipeout ' .. child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/a.txt")'))
	child.settle(300)
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	local dumps = child.dump_files()
	child.lua([[
		local root = _G.FRG_TEST.root
		os.rename(root .. '/b.txt', root .. '/a.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/b.txt'), root .. '/a.txt')
	]])
	child.settle(300)
	eq({ slots = child.slots(), dump = child.dumped_since(dumps) }, { slots = '⦉-⦊ [a] ⟦-⟧', dump = nil })
end

-- b is typed into the pop-up, so it's queued with no buffer; then a.txt is moved onto b.txt on
-- disk, as a file manager moves it, and a's buffer takes b's name.
T['T554 [char] (A20, I18) a move onto a file the primary queue holds keeps it there once'] = function()
	child.steps({ ':e a', '<M-;><M-c>' })
	child.lua([[
		require('frogman').open_primary_buffer_history()
		vim.api.nvim_buf_set_lines(0, 1, 1, false, { 'b.txt' })
		vim.cmd('write')
		vim.cmd('close')
	]])
	child.settle(300)
	eq(child.primary(), '[a,b]on')
	child.lua([[
		local H = require('frogman.domains.history')
		local t = require('frogman.domains.window').data.crux[vim.api.nvim_get_current_win()]
		t.displacement_ternary_map[t.current_slot] = H.get_hash_from_filepath(_G.FRG_TEST.root .. '/b.txt')
		os.rename(_G.FRG_TEST.root .. '/a.txt', _G.FRG_TEST.root .. '/b.txt')
		vim.cmd('file ' .. vim.fn.fnameescape(_G.FRG_TEST.root .. '/b.txt'))
	]])
	child.settle(300)
	local self_notes = child.lua([[
		local t = require('frogman.domains.window').data.crux[vim.api.nvim_get_current_win()]
		local n = 0
		for _, map in ipairs({ t.displacement_ternary_map, t.displacement_secondary_map }) do
			for key, value in pairs(map) do
				if key:gsub('%-swap$', '') == value then n = n + 1 end
			end
		end
		return n
	]])
	eq({ queue = child.primary(), self_notes = self_notes }, { queue = '[b]on', self_notes = 0 })
end

-- new.txt isn't on disk, so a rename of it would be a move; its own name again
-- is no rename at all. It's hidden by then, out of every slot, kept known by
-- its history alone, so no arrival takes it in again after the rename.
T['T484 [char] (A20, I2) a rename to the same name renames nothing'] = function()
	child.steps({ ':e a', ':e new.txt', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	child.lua('local b = vim.fn.bufnr(_G.FRG_TEST.root .. "/new.txt"); vim.api.nvim_buf_set_name(b, vim.api.nvim_buf_get_name(b))')
	child.settle(300)
	local kept = child.lua([[
		local H = require('frogman.domains.history')
		local h = H.get_hash_from_buffer(vim.fn.bufnr(_G.FRG_TEST.root .. '/new.txt'))
		return { history = h ~= nil and H.data.crux_internals.global[h] ~= nil, path = h ~= nil and H.get_filepath_from_hash(h) ~= nil }
	]])
	eq(kept, { history = true, path = true })
	child.messages()
	local dumps = child.dump_files()
	child.cmd('bdelete! ' .. child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/new.txt")'))
	child.settle(300)
	local errors = vim.tbl_filter(function(m) return m.level == 4 end, child.messages())
	eq({ errors = errors, dump = child.dumped_since(dumps) }, { errors = {}, dump = nil })
end

-- brandnew.txt was never written, so taking its name away is a move: every
-- reference follows to the No Name buffer the buffer now is.
T['T485 [char] (A20, I2) :0file on a file never written moves it to a No Name buffer, its references with it'] = function()
	child.steps({ ':e a' })
	child.cmd('edit brandnew.txt')
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unwritten line" })')
	child.settle()
	child.messages()
	child.cmd('0file')
	child.settle(300)
	local healed = vim.tbl_filter(function(m) return m.msg:find('Healed', 1, true) ~= nil end, child.messages())
	local pathless = child.lua([[
		local H = require('frogman.domains.history')
		local out = {}
		for _, t in pairs(require('frogman.domains.window').data.crux) do
			for _, h in ipairs({ t.current_slot, t.secondary_slot, t.ternary_slot }) do
				if h and not H.get_filepath_from_hash(h) then table.insert(out, h) end
			end
		end
		return out
	]])
	eq({ healed = #healed, pathless = pathless }, { healed = 0, pathless = {} })
	child.steps({ '<M-.>' })
	child.settle(300)
	child.steps({ '<M-S-w>' })
	child.settle(300)
	eq(holding('unwritten line'), 1)
end

-- The window is put on a without a BufEnter, then c's buffer goes: cleanup
-- finds the current slot's buffer gone and the window showing a.
T['T108 [char] cleanup re-points the current slot to the registered buffer the window shows'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	child.cmd('noautocmd buffer a.txt')
	child.cmd('bwipeout c.txt')
	child.settle()
	eq(current(), 'a')
end

T['T109 [char] a new unsaved file keeps its buffer, text and tracking after :e a (I12)'] = function()
	child.cmd('edit brandnew.txt')
	child.settle()
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello" })')
	child.steps({ ':e a' })
	child.settle(300)
	eq(buffer_state('brandnew.txt'), { valid = true, lines = { 'hello' }, registered = true, in_history = true })
end

T['T110 [char] a file deleted on disk while shown stays shown and tracked after 4.6 s'] = function()
	child.steps({ ':e a', ':e b' })
	remove_on_disk('b.txt')
	for _ = 1, 10 do child.settle(460) end
	eq(child.shown(), 'b')
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	local st = buffer_state('b.txt')
	eq({ st.valid, st.registered, st.in_history }, { true, true, true })
end

-- The ternary restore puts b in the ternary while the buffer last left is d,
-- which is where Neovim's own pick (the jumplist) goes. Neovim closes any other
-- window that shows the deleted buffer, so this is the one-window case.
T['T111 [char] :bdelete of the shown buffer lands the window on its ternary'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':e d', ':e c', '<M-;><M-r>' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	child.cmd('bdelete c.txt')
	child.settle(300)
	eq(child.shown(), 'b')
end

T['T112 [char] opening a closed file again with :e takes it off the closed stack'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('bdelete b.txt')
	child.settle()
	eq(child.closed(), 'b')
	child.steps({ ':e b' })
	eq(child.closed(), '')
end

-- b's buffer is wiped without events and a copy of b.txt loaded the same way,
-- so the registry still holds the old buffer number. Then the timer's pass.
T['T113 [char] a stale registration re-points to a copy reloaded under noautocmd and wipes nothing'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	local got = child.lua([[
		local H = require('frogman.domains.history')
		local path = _G.FRG_TEST.root .. '/b.txt'
		local old = vim.fn.bufnr(path)
		local hash = H.get_hash_from_buffer(old)
		vim.cmd('noautocmd bwipeout! ' .. old)
		local copy = vim.fn.bufadd(path)
		vim.cmd('noautocmd call bufload(' .. copy .. ')')
		vim.bo[copy].buflisted = true
		H.cleanup_system()
		return {
			copy_open = vim.api.nvim_buf_is_valid(copy) and vim.api.nvim_buf_is_loaded(copy),
			points_at_copy = H.data.hash_buffer_registry.buffers[hash] == copy,
		}
	]])
	eq(got, { copy_open = true, points_at_copy = true })
end

T['T114 [char] a closed entry whose file is gone from disk stays on the stack'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('bdelete b.txt')
	child.settle()
	eq(child.closed(), 'b')
	remove_on_disk('b.txt')
	child.lua('require("frogman.domains.history").cleanup_system()')
	child.settle()
	eq(child.closed(), 'b')
end

-- {c=A s=S t=T} is {c=a s=b t=c}; X is d, outside the slots. The window is put
-- on d without a BufEnter, then a's buffer is wiped (A21 step 1 re-points).
T['T163 [char] a re-point to the shown buffer moves the old current into the ternary (Q18)'] = function()
	child.steps({ ':e d', ':e b', ':e c', '<M-f>', ':e a' })
	eq(child.slots(), '⦉c⦊ [a] ⟦b⟧')
	child.cmd('noautocmd buffer d.txt')
	child.cmd('bwipeout a.txt')
	child.settle()
	eq(child.slots(), '⦉a⦊ [d] ⟦b⟧')
end

T['T523 [char] (A21, M5) the first :e after the start buffer was taken in leaves that buffer in no slot'] = function()
	-- as a config that calls setup() at startup has it: the start buffer entered once frogman is set up
	child.cmd('doautocmd BufEnter')
	child.settle(200)
	local taken = child.lua('return require("frogman.domains.history").data.hash_buffer_registry.hashes[vim.api.nvim_get_current_buf()] ~= nil')
	child.messages()
	child.steps({ ':e a' })
	child.settle(300)
	local slots = child.slots()
	local healed = false
	for _, m in ipairs(child.messages()) do
		if m.msg:find('Healed the triquetra', 1, true) then healed = true end
	end
	child.step('<M-S-f>')
	local said = {}
	for _, m in ipairs(child.messages()) do table.insert(said, m.msg) end
	eq({ taken = taken, slots = slots, healed = healed, said = said },
		{ taken = true, slots = '⦉-⦊ [a] ⟦-⟧', healed = false, said = { 'No ternary buffer to swap with.' } })
end

-- An oil listing unlists its buffer as it reads it; this acwrite buffer's read
-- does what oil's does. :edit reuses the empty buffer for it, with the delete
-- events of a buffer going, though the window still shows the same number.
T['T575 [char] (A19, A21) an :edit that reuses the empty buffer for a listing that unlists itself isn\'t a delete'] = function()
	child.steps({ ':e a' })
	child.cmd('enew')
	child.settle()
	local win = child.lua('return vim.api.nvim_get_current_win()')
	eq(child.slots(win):match('^⦉a⦊ %[NONAME_%d+%] ⟦%-⟧$') ~= nil, true)
	child.lua([[
		vim.api.nvim_create_autocmd('BufReadCmd', { pattern = 'oilish://*', callback = function(args)
			vim.bo[args.buf].buftype = 'acwrite'
			vim.bo[args.buf].buflisted = false
			vim.bo[args.buf].bufhidden = 'hide'
			vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, { 'a.txt' })
			vim.bo[args.buf].modified = false
		end })
		vim.api.nvim_create_autocmd('BufWriteCmd', { pattern = 'oilish://*', callback = function() end })
	]])
	child.cmd('edit oilish://' .. child.lua('return _G.FRG_TEST.root') .. '/')
	child.settle(300)
	local shown = child.lua('return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(...))', { win })
	eq({ shown = shown:match('^oilish://') ~= nil, slots = child.slots(win) }, { shown = true, slots = '⦉-⦊ [a] ⟦-⟧' })
end

-- b's buffer is unlisted without events, as a plugin doing it with noautocmd
-- leaves it: still registered, no longer trackable. The split visits an acwrite
-- buffer, so N's wipe from the first window goes to the heal.
T['T576 [char] (A21) the heal leaves a slot that isn\'t open in its place'] = function()
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.steps({ ':e b' })
	child.cmd('enew')
	child.settle()
	local noname = child.lua('return vim.api.nvim_get_current_buf()')
	local w2 = child.lua('return vim.api.nvim_get_current_win()')
	eq(child.slots(w2):match('^⦉b⦊ %[NONAME_%d+%] ⟦%-⟧$') ~= nil, true)
	child.lua([[
		local buf = vim.api.nvim_create_buf(true, false)
		vim.bo[buf].buftype = 'acwrite'
		vim.api.nvim_buf_set_name(buf, 'acw://scratch')
		vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = buf, callback = function() end })
		vim.api.nvim_set_current_buf(buf)
	]])
	child.settle(200)
	child.lua([[vim.cmd('noautocmd lua vim.bo[vim.fn.bufnr(_G.FRG_TEST.root .. "/b.txt")].buflisted = false')]])
	child.cmd('wincmd p')
	child.settle()
	child.cmd('bwipeout ' .. noname)
	child.settle(300)
	eq(child.slots(w2), '⦉b⦊ [a] ⟦-⟧')
end

-- The switch-then-delete of bufremove-style helpers: a new listed buffer into
-- the window, then the old one deleted, in one call, so the new one's arrival
-- hasn't settled when the delete runs.
T['T577 [char] (A21) a delete helper that switches the window first doesn\'t lose the slots'] = function()
	child.steps({ ':e a', ':e b', '<M-;><M-c>' })
	child.cmd('enew')
	child.settle()
	child.cmd('bdelete a.txt')
	child.cmd('bdelete b.txt')
	child.settle()
	local before = child.slots()
	eq({ before:match('^⦉b⦊ %[NONAME_%d+%] ⟦%-⟧$') ~= nil, child.primary() }, { true, '[b]on' })
	child.lua([[
		local old = vim.api.nvim_get_current_buf()
		vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(true, false))
		vim.cmd('bdelete ' .. old)
	]])
	child.settle(300)
	local after = child.slots()
	eq({ kept = after:match('^⦉b⦊ %[NONAME_%d+%] ⟦%-⟧$') ~= nil, new = after ~= before, primary = child.primary() },
		{ kept = true, new = true, primary = '[b]on' })
end

-- b.txt deleted from disk, then its buffer given a name frogman doesn't track, as a plugin's scratch takes one.
T['T635 [char] (A20) a rename to a name frogman doesn\'t track closes the old name, and claims no copy'] = function()
	child.steps({ ':e a', ':e b' })
	child.lua([[
		local root = _G.FRG_TEST.root
		os.remove(root .. '/b.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/b.txt'), 'scratch://b')
	]])
	child.settle(300)
	local kinds = child.lua([[
		local out = {}
		for _, step in ipairs(require('frogman').ledger.trail()) do
			for _, m in ipairs(step.moves) do
				if m.name == 'b.txt' then out[m.kind] = true end
			end
		end
		return out
	]])
	eq({ copied = kinds.copied == true, closed = kinds.closed == true, list = vim.tbl_contains(vim.split(child.closed(), ','), 'b') },
		{ copied = false, closed = true, list = true })
end

-- b.txt shown in the first tab; from a second tab its buffer takes the name g.txt, b.txt still on disk.
T['T636 [char] (A20) a copy\'s arrival lands in the window that shows it, in another tab too'] = function()
	child.steps({ ':e a', ':e b' })
	local w1 = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('tabnew')
	child.steps({ ':e c' })
	child.lua('vim.api.nvim_buf_set_name(vim.fn.bufnr(_G.FRG_TEST.root .. "/b.txt"), _G.FRG_TEST.root .. "/g.txt")')
	child.settle(300)
	-- an arrival records the visit in the window's own history, as a heal doesn't (T558)
	local visited = child.lua([[
		local H = require('frogman.domains.history')
		local g = H.get_hash_from_buffer(vim.fn.bufnr(_G.FRG_TEST.root .. '/g.txt'))
		return H.data.crux_internals.window[...][g] ~= nil
	]], { w1 })
	eq({ current = child.slots(w1):match('%[(.-)%]'), visited = visited }, { current = 'g', visited = true })
end

-- b visited first, closed, and c, visited after a, then moved over b.txt on disk with no window
-- showing it, its buffer given b's name, as a file manager's move does.
T['T637 [char] (A20) a move onto a closed name takes it off the lists and keeps the newer visit'] = function()
	child.steps({ ':e b', ':e a', ':e c' })
	child.cmd('bdelete ' .. child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/b.txt")'))
	child.steps({ ':e d' })
	eq(vim.tbl_contains(vim.split(child.closed(), ','), 'b'), true)
	local c_visits = child.lua([[
		local H = require('frogman.domains.history')
		local c = H.get_hash_from_buffer(vim.fn.bufnr(_G.FRG_TEST.root .. '/c.txt'))
		return { global = H.data.crux_internals.global[c], window = H.data.crux_internals.window[vim.api.nvim_get_current_win()][c] }
	]])
	child.lua([[
		local root = _G.FRG_TEST.root
		os.rename(root .. '/c.txt', root .. '/b.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/c.txt'), root .. '/b.txt')
	]])
	child.settle(300)
	local b_visits = child.lua([[
		local H = require('frogman.domains.history')
		local b = H.get_hash_from_buffer(vim.fn.bufnr(_G.FRG_TEST.root .. '/b.txt'))
		return { global = H.data.crux_internals.global[b], window = H.data.crux_internals.window[vim.api.nvim_get_current_win()][b] }
	]])
	eq({ closed = vim.tbl_contains(vim.split(child.closed(), ','), 'b'), visits = b_visits }, { closed = false, visits = c_visits })
end

-- :e from an empty No Name buffer, which Neovim deletes, and a refresh at once, before c's arrival
-- settles: the current slot names the forgotten No Name buffer while the window shows c.
T['T647 [char] (A21, M12) a refresh before a window\'s arrival settles finds nothing impossible'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('enew')
	child.settle()
	local dumps = child.dump_files()
	child.lua([[
		vim.cmd('edit ' .. _G.FRG_TEST.root .. '/c.txt')
		local ui = require('frogman.domains.ui')
		ui.sm.loop:to(ui.states.LOOP.SELF)
	]])
	child.settle(300)
	eq({ dump = child.dumped_since(dumps), current = child.slots():match('%[(.-)%]') }, { dump = nil, current = 'c' })
end

-- d's arrival is followed by <M-;><M-c>, so the window's triquetra has changed
-- since and the undo takes the next slot in line instead of the one from before.
T['T578 [char] (I10) an arrival undone takes the next open slot'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d', '<M-;><M-c>' })
	child.cmd('bdelete c.txt')
	child.settle()
	eq({ child.slots(), child.closed() }, { '⦉c⦊ [d] ⟦b⟧', 'c' })
	child.cmd('setlocal buftype=nofile')
	child.settle(300)
	eq(child.slots(), '⦉c⦊ [b] ⟦-⟧')
end

return T
