-- Windows: <M-,> and the window-jump history (A3, A17). IDs are the spec's
-- (what-is-cavediver.md, section 7).
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

return T
