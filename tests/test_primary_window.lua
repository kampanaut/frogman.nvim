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

T['T101 [char] saving with the first row unchanged leaves a disabled primary off'] = function()
	local w = queue_ba()
	child.steps({ '<M-;><M-x>' })
	eq(child.primary(), '[b,a]off')
	open()
	child.popup_set({ 'b.txt' })
	child.cmd('write')
	child.settle()
	eq(child.primary(w), '[b]off')
end

T['T158 [char] a save switches the primary on only when the first row changed'] = function()
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

-- The picker stubbed: it picks what _G.CDV_PICKED names, full paths.
local function stub_picker()
	child.lua([[_G.CDV_TEST.setup({ primary_picker = function(add) add(_G.CDV_PICKED) end })]])
end
local function pick(files, row)
	child.lua('_G.CDV_PICKED = vim.tbl_map(function(f) return _G.CDV_TEST.root .. "/" .. f end, ...)', { files })
	child.lua('vim.api.nvim_win_set_cursor(0, { ..., 0 })', { row })
	child.steps({ '<M-e>' })
end

T['T159 [char] <M-e> adds the picked files to the pop-up, and only :w saves them'] = function()
	stub_picker()
	local w = queue_ba()
	open()
	child.popup_set({ 'b.txt', 'a.txt', '' })
	pick({ 'c.txt' }, 3)
	local empty_line = child.popup_lines()
	child.popup_set({ 'b.txt', 'a.txt' })
	pick({ 'c.txt' }, 1)
	local after_line = child.popup_lines()
	local unsaved = child.primary(w)
	child.popup_set({ 'b.txt', 'a.txt' })
	pick({ 'c.txt', 'd.txt' }, 1)
	local two = child.popup_lines()
	child.popup_set({ 'b.txt', 'c.txt', 'a.txt' })
	child.cmd('write')
	child.settle()
	eq({ empty_line = empty_line, after_line = after_line, unsaved = unsaved, two = two, saved = child.primary(w) }, {
		empty_line = { 'b.txt', 'a.txt', 'c.txt' },
		after_line = { 'b.txt', 'c.txt', 'a.txt' },
		unsaved = '[b,a]on',
		two = { 'b.txt', 'c.txt', 'd.txt', 'a.txt' },
		saved = '[b,c,a]on',
	})
end

-- The root's init.lua picked while a sub/init.lua is queued and shown by its short name, init.lua.
T['T553 [char] a picked file whose path reads like another entry\'s short name goes in as its own'] = function()
	stub_picker()
	child.lua([[
		local root = _G.CDV_TEST.root
		vim.fn.mkdir(root .. '/sub', 'p')
		vim.fn.writefile({ 'sub' }, root .. '/sub/init.lua')
		vim.fn.writefile({ 'root' }, root .. '/init.lua')
		vim.cmd.edit(vim.fn.fnameescape(root .. '/sub/init.lua'))
	]])
	child.settle()
	child.steps({ '<M-;><M-c>' })
	local w = child.win()
	open()
	local shown = child.popup_lines()
	pick({ 'init.lua' }, 1)
	local picked = child.popup_lines()
	child.cmd('write')
	child.settle()
	local queue = child.lua([[
		local H = require('cavediver.domains.history')
		local t = require('cavediver.domains.window').data.crux[...]
		return vim.tbl_map(function(h) return vim.fn.fnamemodify(H.get_filepath_from_hash(h), ':.') end, t.primary_buffer)
	]], { w })
	eq({ shown = shown, picked = picked, queue = queue },
		{ shown = { 'init.lua' }, picked = { 'init.lua', './init.lua' }, queue = { 'sub/init.lua', 'init.lua' } })
end

T['T160 [char] with no picker, <M-e> gives a message and changes no line'] = function()
	queue_ba()
	open()
	eq(child.lua('return pcall(require, "telescope")'), false)
	child.messages()
	local ok, err = child.step('<M-e>')
	eq({ ok, err }, { true, nil })
	eq(#child.messages() > 0, true)
	eq(child.popup_lines(), { 'b.txt', 'a.txt' })
end

T['T160 [char] <M-e> is not mapped outside the primary queue window'] = function()
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


-- The virtual text drawn on each of the pop-up's lines, as one string per line.
local DECORATION = [==[
local ns = vim.api.nvim_create_namespace('cavediver_primary_popup')
local buf = vim.api.nvim_get_current_buf()
local out = {}
for i = 1, vim.api.nvim_buf_line_count(buf) do out[i] = '' end
for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
	for _, chunk in ipairs(m[4].virt_text or {}) do out[m[2] + 1] = out[m[2] + 1] .. chunk[1] end
end
return out
]==]

T['T452 [char] (A18, A27) the pop-up in the trail\'s language'] = function()
	queue_ba()
	child.cmd('bdelete ' .. 'a.txt')
	child.settle(100)
	child.lua([[
		-- b.txt gone from disk after the start (each start writes the project's files again), tagged by hand
		os.remove(_G.CDV_TEST.root .. '/b.txt')
		local hash = require('cavediver.domains.history').get_hash_from_filepath(_G.CDV_TEST.root .. '/b.txt')
		require('cavediver.domains.history').data.missing[hash] = 'feature'
	]])
	open()
	local lines, on = child.popup_lines(), child.lua(DECORATION)
	child.steps({ 'q' })
	settle_close()
	child.steps({ '<M-;><M-x>' })
	open()
	local off = child.lua(DECORATION)[1]
	child.steps({ 'q' })
	settle_close()
	child.lua('_G.CDV_TEST.setup({ glyphs = { set = "ascii" } })')
	open()
	local ascii = table.concat(child.lua(DECORATION), '') .. table.concat(child.popup_lines(), '')
	eq({ lines = lines, on = on[1]:find('primary · on', 1, true) ~= nil, tag = on[1]:find('⎇feature', 1, true) ~= nil,
		closed = on[2]:find('↓', 1, true) ~= nil, off = off:find('primary · off', 1, true) ~= nil, ascii = ascii:find('[\128-\255]') == nil },
		{ lines = { 'b.txt', 'a.txt' }, on = true, tag = true, closed = true, off = true, ascii = true })
end

T['T453 [char] (A18) the pop-up\'s keys are keymaps.views\''] = function()
	child.lua('_G.CDV_TEST.setup({ keymaps = { views = { leave = "Q" } } })')
	local w = queue_ba()
	open()
	child.popup_set({ 'b.txt', 'a.txt', 'c.txt' })
	child.steps({ 'Q' })
	settle_close()
	local closed = child.popup() == nil
	local saved = child.primary(w)
	open()
	child.lua('vim.api.nvim_win_set_cursor(0, { 2, 0 })')
	child.steps({ 'gf' })
	child.settle()
	eq({ closed = closed, saved = saved, primary = child.primary(w), stays = child.popup() ~= nil, lines = child.popup_lines() },
		{ closed = true, saved = '[b,a,c]on', primary = '[a,b,c]on', stays = true, lines = { 'a.txt', 'b.txt', 'c.txt' } })
end


-- A negative width, which the size reads as its size.
T['T568 [char] (A18, M13) opening the primary pop-up leaves its size setting as it is'] = function()
	child.lua('_G.CDV_TEST.setup({ primary_buffer_history_popup = { width = -0.5, height = 0.2 } })')
	queue_ba()
	open()
	local got = child.lua([[return { width = vim.api.nvim_win_get_width(0), columns = vim.o.columns,
		setting = require('cavediver.configs').primary_buffer_history_popup.width }]])
	eq({ half = got.width == math.floor(got.columns * 0.5), setting = got.setting }, { half = true, setting = -0.5 })
end

-- leave_too and pick set to false: the pop-up maps neither, as the closed lists and the trail don't.
T['T539 [char] (A18) a view key set to false isn\'t mapped in the pop-up'] = function()
	child.lua('_G.CDV_TEST.setup({ keymaps = { views = { leave_too = false, pick = false } } })')
	queue_ba()
	open()
	local mapped = child.lua([[
		local out = {}
		for _, lhs in ipairs({ "<C-c>", "<M-e>", "q" }) do
			out[lhs] = vim.fn.maparg(lhs, "n", false, true).buffer == 1
		end
		return out
	]])
	eq(mapped, { ["<C-c>"] = false, ["<M-e>"] = false, q = true })
end

T['T454 [char] (A18, P9) a save keeps a queue entry whose file is gone from disk'] = function()
	local w = queue_ba()
	child.lua('os.remove(_G.CDV_TEST.root .. "/b.txt")') -- after the start, which writes the project's files
	open()
	child.messages()
	child.popup_set({ 'a.txt', 'b.txt' })
	child.cmd('write')
	child.settle()
	eq({ primary = child.primary(w), errors = Extra.at_least(child.messages()) }, { primary = '[a,b]on', errors = {} })
end

-- idx.json is open and idx.js is only on disk: by pattern, idx.js names
-- idx.json's buffer too.
T['T495 [char] (A18) a path that a longer open buffer\'s name begins with is its own file in the pop-up'] = function()
	child.lua('for _, f in ipairs({ "idx.json", "idx.js" }) do vim.fn.writefile({ f }, _G.CDV_TEST.root .. "/" .. f) end')
	child.cmd('edit idx.json')
	child.settle()
	local w = queue_ba()
	open()
	child.messages()
	child.popup_set({ 'idx.js', 'b.txt', 'a.txt' })
	child.cmd('write')
	child.settle()
	local first = child.lua([[
		local t = require('cavediver.domains.window').data.crux[...]
		return vim.fs.basename(require('cavediver.domains.history').get_filepath_from_hash(t.primary_buffer[1]) or '')
	]], { w })
	eq({ primary = child.primary(w), first = first, errors = Extra.at_least(child.messages()) },
		{ primary = '[idx,b,a]on', first = 'idx.js', errors = {} })
end

-- a, in the queue, is closed with <M-.>: its buffer stays, unloaded, unlisted
-- and unregistered, as :bdelete leaves it.
T['T496 [char] (A18, I4) a queue entry closed with <M-.> survives the pop-up\'s save'] = function()
	local w = queue_ba()
	child.steps({ ':e a', '<M-.>' })
	open()
	child.messages()
	child.popup_set({ 'a.txt', 'b.txt' })
	child.cmd('write')
	child.settle()
	eq({ primary = child.primary(w), errors = Extra.at_least(child.messages()) }, { primary = '[a,b]on', errors = {} })
end

return T
