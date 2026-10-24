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
		local H = require('cavediver.domains.history')
		local b = vim.fn.bufnr(_G.CDV_TEST.root .. '/' .. ...)
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
	child.lua('os.remove(_G.CDV_TEST.root .. "/" .. ...)', { file })
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
		local root = _G.CDV_TEST.root
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
			local b = vim.fn.bufadd(_G.CDV_TEST.root .. '/' .. f)
			vim.bo[b].buflisted = true
			vim.fn.bufload(b)
			vim.api.nvim_buf_set_lines(b, 0, -1, false, { 'edited ' .. f })
		end
	]])
	child.cmd('wall')
	child.settle(300)
	local registered = child.lua([[
		local H = require('cavediver.domains.history')
		local out = {}
		for _, f in ipairs({ 'c.txt', 'd.txt' }) do
			table.insert(out, H.get_hash_from_buffer(vim.fn.bufnr(_G.CDV_TEST.root .. '/' .. f)) ~= nil)
		end
		return out
	]])
	eq({ slots = child.slots(), registered = registered }, { slots = '⦉a⦊ [b] ⟦-⟧', registered = { true, true } })
end

-- a's buffer is wiped, so the ternary holds a closed; b.txt then goes over
-- a.txt on disk and b's buffer takes a's name, as an LSP or oil rename does.
T['T483 [char] (A20, I1) a move onto a file the ternary holds leaves no file in two slots'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('bwipeout ' .. child.lua('return vim.fn.bufnr(_G.CDV_TEST.root .. "/a.txt")'))
	child.settle(300)
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	local dumps = child.dump_files()
	child.lua([[
		local root = _G.CDV_TEST.root
		os.rename(root .. '/b.txt', root .. '/a.txt')
		vim.api.nvim_buf_set_name(vim.fn.bufnr(root .. '/b.txt'), root .. '/a.txt')
	]])
	child.settle(300)
	eq({ slots = child.slots(), dump = child.dumped_since(dumps) }, { slots = '⦉-⦊ [a] ⟦-⟧', dump = nil })
end

-- new.txt isn't on disk, so a rename of it would be a move; its own name again
-- is no rename at all. It's hidden by then, out of every slot, kept known by
-- its history alone, so no arrival takes it in again after the rename.
T['T484 [char] (A20, I2) a rename to the same name renames nothing'] = function()
	child.steps({ ':e a', ':e new.txt', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	child.lua('local b = vim.fn.bufnr(_G.CDV_TEST.root .. "/new.txt"); vim.api.nvim_buf_set_name(b, vim.api.nvim_buf_get_name(b))')
	child.settle(300)
	local kept = child.lua([[
		local H = require('cavediver.domains.history')
		local h = H.get_hash_from_buffer(vim.fn.bufnr(_G.CDV_TEST.root .. '/new.txt'))
		return { history = h ~= nil and H.data.crux_internals.global[h] ~= nil, path = h ~= nil and H.get_filepath_from_hash(h) ~= nil }
	]])
	eq(kept, { history = true, path = true })
	child.messages()
	local dumps = child.dump_files()
	child.cmd('bdelete! ' .. child.lua('return vim.fn.bufnr(_G.CDV_TEST.root .. "/new.txt")'))
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
		local H = require('cavediver.domains.history')
		local out = {}
		for _, t in pairs(require('cavediver.domains.window').data.crux) do
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
		local H = require('cavediver.domains.history')
		local path = _G.CDV_TEST.root .. '/b.txt'
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
	child.lua('require("cavediver.domains.history").cleanup_system()')
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

return T
