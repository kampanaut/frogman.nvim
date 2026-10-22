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
T['T107 [target] a rename whose old file is gone moves every reference and pushes nothing'] = function()
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

T['T114 [target] a closed entry whose file is gone from disk stays on the stack'] = function()
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
