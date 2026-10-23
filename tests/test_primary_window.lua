-- The primary queue window, <M-;>F (A18). IDs are the spec's
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

-- Queue [b,a], switched on; returns the window it belongs to.
local function queue_ba()
	child.steps({ ':e a', '<M-;><M-c>', ':e b', '<M-;><M-c>' })
	eq(child.primary(), '[b,a]on')
	return child.win()
end

-- Open the window and check it's the one now focused.
local function open()
	child.steps({ '<M-;>F' })
	local w = child.popup()
	eq(w ~= nil, true)
	eq(child.win(), w)
	return w
end

-- Let close_window's deferred deletes run.
local function settle_close() child.settle(200) end

T['T95 [char] with an empty queue no window opens'] = function()
	child.steps({ ':e a' })
	child.messages()
	child.steps({ '<M-;>F' })
	eq(child.floats(), {})
	eq(child.popup(), nil)
	eq(Extra.has(child.messages(), 'No primary buffer history available.'), true)
end

T['T96 [char] reordering the lines and :w reorders the queue'] = function()
	local w = queue_ba()
	open()
	eq(child.popup_lines(), { 'b.txt', 'a.txt' })
	child.popup_set({ 'a.txt', 'b.txt' })
	child.cmd('write')
	child.settle()
	eq(child.primary(w), '[a,b]on')
end

T['T97 [char] <CR> on line 2 makes that file the primary and closes the window'] = function()
	local w = queue_ba()
	open()
	child.lua('vim.api.nvim_win_set_cursor(0, { 2, 0 })')
	child.steps({ '<CR>' })
	settle_close()
	eq(child.primary(w), '[a,b]on')
	eq(child.popup(), nil)
	eq(child.floats(), {})
	eq(child.win(), w)
end

T['T98 [char] a typed path to an unloaded readable file is registered, queued and pushed on the closed stack'] = function()
	local w = queue_ba()
	open()
	local x_path = child.lua('return _G.CDV_TEST.root .. "/x.txt"')
	eq(child.lua('return vim.fn.bufnr(...)', { x_path }), -1)
	child.popup_set({ 'b.txt', 'a.txt', x_path })
	child.cmd('write')
	child.settle()
	eq(child.primary(w), '[b,a,x]on')
	eq(type(child.hash_of('x')), 'string')
	eq(child.closed(), 'x')
end

T['T99 [char] valid lines are saved and invalid ones reported'] = function()
	local w = queue_ba()
	open()
	child.messages()
	child.popup_set({ 'a.txt', 'nonexistent.txt' })
	child.cmd('write')
	child.settle()
	eq(child.primary(w), '[a]on')
	local errors = Extra.at_least(child.messages())
	eq(#errors, 1)
	eq(errors[1]:find('File does not exist: nonexistent.txt', 1, true) ~= nil, true)
end

T['T100 [char] q saves, then closes the window'] = function()
	local w = queue_ba()
	open()
	child.popup_set({ 'a.txt', 'b.txt' })
	child.steps({ 'q' })
	settle_close()
	eq(child.primary(w), '[a,b]on')
	eq(child.popup(), nil)
	eq(child.win(), w)
end

T['T100 [char] <C-c> saves, then closes the window'] = function()
	local w = queue_ba()
	open()
	child.popup_set({ 'a.txt', 'b.txt' })
	child.steps({ '<C-c>' })
	settle_close()
	eq(child.primary(w), '[a,b]on')
	eq(child.popup(), nil)
	eq(child.win(), w)
end

T['T101 [today] saving with the first row unchanged re-enables a disabled primary'] = function()
	local w = queue_ba()
	child.steps({ '<M-;><M-x>' })
	eq(child.primary(), '[b,a]off')
	open()
	child.popup_set({ 'b.txt' })
	child.cmd('write')
	child.settle()
	eq(child.primary(w), '[b]on')
end

T['T158 [target] a save switches the primary on only when the first row changed'] = function()
	-- Each bullet starts from a fresh child.
	local function bullet(switch_off, lines)
		child.setup()
		local w = queue_ba()
		if switch_off then child.steps({ '<M-;><M-x>' }) end
		open()
		child.popup_set(lines)
		child.cmd('write')
		child.settle()
		return child.primary(w)
	end
	local got = {
		reorder_off = bullet(true, { 'a.txt', 'b.txt' }),
		drop_a_off = bullet(true, { 'b.txt' }),
		drop_a_on = bullet(false, { 'b.txt' }),
	}
	eq(got, { reorder_off = '[a,b]on', drop_a_off = '[b]off', drop_a_on = '[b]on' })
end

T['T160 [target] with no picker, <M-e> gives a message and changes no line'] = function()
	queue_ba()
	open()
	eq(child.lua('return pcall(require, "telescope")'), false)
	child.messages()
	local ok, err = child.step('<M-e>')
	eq({ ok, err }, { true, nil })
	eq(#child.messages() > 0, true)
	eq(child.popup_lines(), { 'b.txt', 'a.txt' })
end

T['T160 [target] <M-e> is not mapped outside the primary queue window'] = function()
	queue_ba()
	open()
	-- Mapped in the window...
	eq(child.lua('return vim.fn.maparg("<M-e>", "n", false, true).buffer'), 1)
	child.steps({ 'q' })
	settle_close()
	-- ...and nowhere else.
	eq(child.lua('return vim.fn.maparg("<M-e>", "n")'), '')
end

T['T161 [char] q and <C-c> are described as "Save and close"'] = function()
	queue_ba()
	open()
	eq(child.lua('return vim.fn.maparg("q", "n", false, true).desc'), 'Save and close')
	eq(child.lua('return vim.fn.maparg("<C-c>", "n", false, true).desc'), 'Save and close')
end

return T
