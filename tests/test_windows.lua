-- Windows: <M-,> and the window-jump history (A3, A17). IDs are the spec's
-- (what-is-frogman.md, section 7).
local Helpers = dofile('tests/helpers.lua')
local Extra = dofile('tests/helpers_cycling.lua')
local eq = Helpers.eq
local child = Helpers.new_child()
Extra.attach(child)

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = child.stop,
	},
})

T['T92 [char] <M-,> toggles between the last two windows'] = function()
	child.steps({ ':e a' })
	local w1 = child.win()
	child.cmd('vsplit')
	child.steps({ ':e b' })
	local w2 = child.win()
	eq(w1 ~= w2, true)

	child.steps({ '<M-,>' })
	eq(child.win(), w1)
	child.steps({ '<M-,>' })
	eq(child.win(), w2)
	child.steps({ '<M-,>' })
	eq(child.win(), w1)
end

T['T93 [char] with no previous window <M-,> warns'] = function()
	child.steps({ ':e a' })
	local w = child.win()
	child.messages()
	child.steps({ '<M-,>' })
	eq(child.win(), w)
	local msgs = child.messages()
	eq(Extra.has(msgs, 'No valid previous window to toggle to.'), true)
end

T['T94 [char] <M-,> skips a previous window whose filetype is minimap'] = function()
	child.steps({ ':e a' })
	local w1 = child.win()
	child.cmd('vsplit')
	child.steps({ ':e b' })
	local w2 = child.win()
	-- The window <M-,> would go back to now shows a minimap.
	child.lua('vim.bo[vim.api.nvim_win_get_buf(...)].filetype = "minimap"', { w1 })
	child.messages()
	child.steps({ '<M-,>' })
	eq(child.win(), w2)
	eq(Extra.has(child.messages(), 'No valid previous window to toggle to.'), true)
end

T['T449 [char] (A17) <M-,>\'s skip list is configurable'] = function()
	child.lua('_G.FRG_TEST.setup({ toggle_window = { skip_filetypes = { "mything" } } })')
	child.steps({ ':e a' })
	local w1 = child.win()
	child.cmd('vsplit')
	child.steps({ ':e b' })
	local w2 = child.win()
	child.lua('vim.bo[vim.api.nvim_win_get_buf(...)].filetype = "mything"', { w1 })
	child.steps({ '<M-,>' })
	local skipped = child.win() == w2
	child.lua('vim.bo[vim.api.nvim_win_get_buf(...)].filetype = "minimap"', { w1 })
	child.steps({ '<M-,>' })
	eq({ skipped = skipped, went = child.win() == w1 }, { skipped = true, went = true })
end

T['T459 [char] (A3, M12) the command-line window is neither a visit nor a jump to record'] = function()
	child.steps({ ':e a', ':e b' })
	child.messages()
	child.type_keys('q:')
	child.lua('vim.wait(600)')
	local open = child.lua('return { vim.fn.getcmdwintype(), vim.wo.winbar }')
	child.type_keys('<C-c>')
	child.lua('vim.wait(300)')
	eq({ open = open, failures = Extra.at_least(child.messages()) }, { open = { ':', '' }, failures = {} })
end

T['T194 [char] one jump table serves every tab'] = function()
	-- Tab 1: a | b. Tab 2: c | d.
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.steps({ ':e b' })
	local tab1_win = child.win()
	child.cmd('tabnew')
	child.steps({ ':e c' })
	child.cmd('vsplit')
	child.steps({ ':e d' })
	local d_win = child.win()
	eq(child.shown(d_win), 'd')

	child.cmd('tabnext 1')
	child.settle()
	eq(child.win(), tab1_win)

	-- <M-,> goes to the window just left, d's window in tab 2.
	child.steps({ '<M-,>' })
	eq(child.win(), d_win)
	eq(child.lua('return vim.fn.tabpagenr()'), 2)

	-- And <M-,> there comes back.
	child.steps({ '<M-,>' })
	eq(child.win(), tab1_win)
	eq(child.lua('return vim.fn.tabpagenr()'), 1)
end


-- One batch: :edit b, a split on it, back to the first window, :edit c. The
-- split's only event, its WinEnter, comes while the batch is still running,
-- and the focus has left it by the time the batch settles; it's taken in all
-- the same, by what it shows, as when the commands are typed one by one.
T['T1268 [char] (P2, M11, review round 11) a split made and left inside one batch is taken in by what it shows'] = function()
	child.steps({ ':e a' })
	local first = child.lua('return vim.api.nvim_get_current_win()')
	child.lua([[pcall(vim.api.nvim_feedkeys, vim.api.nvim_replace_termcodes(':edit b.txt<CR>:vsplit<CR>:wincmd w<CR>:edit c.txt<CR>', true, false, true), 'x', false)]])
	child.settle(300)
	local split = child.lua([[
		local first = ...
		for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if w ~= first then return w end
		end
	]], { first })
	eq({ split = child.slots(split), shown = child.shown(split), registered = child.lua([[
		local H = require('frogman.domains.history')
		return H.get_hash_from_buffer(vim.fn.bufnr('b.txt')) ~= nil
	]]), first = child.slots(first) },
		{ split = '⦉-⦊ [b] ⟦-⟧', shown = 'b', registered = true, first = '⦉a⦊ [c] ⟦-⟧' })
end


-- One batch: a split on the registered empty No Name buffer, :edit there
-- (Neovim reuses that buffer for the new name, deleting its No Name self),
-- then back to the first window. The split's first arrival comes while the
-- No Name buffer's close is still to settle; the close goes first, so the
-- split takes the buffer in under its new name, and no winbar draw meets a
-- current slot with no buffer.
T['T1269 [char] (P2, M11, review round 11) a batch that reuses an empty No Name buffer in a split and leaves it draws no corruption'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('enew')
	child.settle()
	local n = child.lua('return vim.api.nvim_get_current_buf()')
	child.steps({ ':bnext' })
	child.messages()
	local first = child.lua('return vim.api.nvim_get_current_win()')
	child.lua([[pcall(vim.api.nvim_feedkeys, vim.api.nvim_replace_termcodes(..., true, false, true), 'x', false)]],
		{ ':sbuffer ' .. n .. '<CR>:edit azz.txt<CR>:wincmd w<CR>' })
	local corrupt = 0
	for _ = 1, 4 do
		child.settle(250)
		for _, m in ipairs(child.messages()) do
			if m.msg:find('WINBAR STATE CORRUPTION', 1, true) then corrupt = corrupt + 1 end
		end
	end
	local split = child.lua([[
		local first = ...
		for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if w ~= first then return w end
		end
	]], { first })
	eq({ corrupt = corrupt, split = child.slots(split), drawn = child.lua('return vim.wo[...].winbar ~= ""', { split }) },
		{ corrupt = 0, split = '⦉-⦊ [azz] ⟦-⟧', drawn = true })
end

-- frogman off, the windows changed under it (the one it last knew closed), and on again: the next keys
-- draw no winbar corruption warning, the window you're in known from the setup.
T['T1285 [char] (M12, review round 11) after disable() and setup(), the window you are in is the one frogman knows'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':vsplit', ':e d', ':split', ':e e' })
	child.lua([[
		require('frogman').disable()
		vim.cmd('only'); vim.cmd('edit f.txt'); vim.cmd('bdelete! 2'); vim.cmd('vsplit x.txt'); vim.cmd('tabnew'); vim.cmd('edit a.txt')
	]])
	child.settle(300)
	child.lua('_G.FRG_TEST.setup()')
	child.settle(300)
	child.messages()
	for _, k in ipairs({ '<M-f>', '<M-S-f>', '<M-;><M-f>' }) do
		child.step(k)
	end
	child.settle(300)
	local corrupt = #vim.tbl_filter(function(m) return m.msg:find('WINBAR STATE CORRUPTION', 1, true) ~= nil end, child.messages())
	eq({ corrupt = corrupt, known = child.lua('return require("frogman.domains.window").data.current_window == vim.api.nvim_get_current_win()') },
		{ corrupt = 0, known = true })
end



-- A split on d turned into a float: a float holds no slots (I9), so it has none from then on, and a slot
-- key there says the window isn't one frogman tracks.
T['T1286 [char] (I9, review round 11) a window turned into a float loses its slots'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('vsplit')
	child.steps({ ':e d' })
	local before = child.slots()
	child.lua([[vim.api.nvim_win_set_config(0, { relative = 'editor', row = 2, col = 2, width = 30, height = 5 })]])
	child.settle()
	child.messages()
	local ok = child.step('<M-f>')
	eq({ before = before, ok = ok, after = child.slots(), said = #vim.tbl_filter(function(m) return m.msg:find('Window with unregistered buffer.', 1, true) ~= nil end, child.messages()) },
		{ before = '⦉c⦊ [d] ⟦-⟧', ok = true, after = 'no triquetra', said = 1 })
end


-- A split turned into a float, then a save before any key, and a cleanup tick: the save writes no entry
-- for it and nothing that shouldn't happen does, and the tick lets its slots go.
T['T1288 [char] (I9, S1 Save, review round 11) a window turned into a float is saved as no window, and the cleanup tick lets its slots go'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('vsplit')
	child.steps({ ':e d' })
	local float = child.lua('return vim.api.nvim_get_current_win()')
	child.lua([[vim.api.nvim_win_set_config(0, { relative = 'editor', row = 2, col = 2, width = 30, height = 5 })]])
	local dumps = child.dump_files()
	local saved = child.lua('return { pcall(require("frogman").save_session, vim.fn.getcwd()) }')
	child.lua('pcall(require("frogman.domains.history").routines.cleanup_system)')
	child.settle()
	eq({ saved = saved, dumped = child.dumped_since(dumps), held = child.lua('return require("frogman.domains.window").data.crux[...] ~= nil', { float }) },
		{ saved = { true }, held = false })
end

return T
