-- The primary queue window, <M-;>F (A18). IDs are the spec's
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
	local x_path = child.lua('return _G.FRG_TEST.root .. "/x.txt"')
	eq(child.lua('return vim.fn.bufnr(...)', { x_path }), -1)
	child.popup_set({ 'b.txt', 'a.txt', x_path })
	child.cmd('write')
	child.settle()
	eq(child.primary(w), '[b,a,x]on')
	eq(type(child.hash_of('x')), 'string')
	eq(child.closed(), 'x')
end

T['T99 [char] with a mix of valid and invalid lines, the save asks first, and Yes saves the valid ones'] = function()
	local w = queue_ba()
	open()
	child.messages()
	child.answer('Yes')
	child.popup_set({ 'a.txt', 'nonexistent.txt' })
	child.cmd('write')
	child.settle()
	local prompt = child.prompts()
	eq({
		primary = child.primary(w),
		prompts = #prompt,
		named = (prompt[1] or ''):find('nonexistent.txt', 1, true) ~= nil,
		errors = Extra.at_least(child.messages()),
	}, { primary = '[a]on', prompts = 1, named = true, errors = {} })
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

T['T678 [char] (A18) the save asks first about the lines it would leave out'] = function()
	local w = queue_ba()
	local pw = open()
	local lines = { 'a.txt', 'b.txt', 'missing.txt', 'a.txt' }
	child.answer('No')
	child.popup_set(lines)
	child.cmd('write')
	child.settle()
	local prompt = child.prompts()
	local no = {
		primary = child.primary(w),
		prompts = #prompt,
		named = (prompt[1] or ''):find('missing.txt', 1, true) ~= nil and (prompt[1] or ''):find('Repeated', 1, true) ~= nil,
		lines = child.popup_lines(),
		modified = child.lua('return vim.bo[vim.api.nvim_win_get_buf(...)].modified', { pw }),
		cursor = child.lua('return vim.api.nvim_win_get_cursor(...)[1]', { pw }),
	}
	child.answer('Yes')
	child.messages()
	child.cmd('write')
	child.settle()
	eq({ no, { primary = child.primary(w), errors = Extra.at_least(child.messages()) } }, {
		{ primary = '[b,a]on', prompts = 1, named = true, lines = lines, modified = true, cursor = 3 },
		{ primary = '[a,b]on', errors = {} },
	})
end

T['T679 [char] (A18) a save answered No changes nothing, and q stays open'] = function()
	local w = queue_ba()
	local pw = open()
	local x_path = child.lua('return _G.FRG_TEST.root .. "/x.txt"')
	eq(child.lua('return vim.fn.bufnr(...)', { x_path }), -1)
	child.answer('No')
	child.popup_set({ 'b.txt', 'a.txt', x_path, 'missing.txt' })
	child.steps({ 'q' })
	settle_close()
	local no = { open = child.popup() == pw, primary = child.primary(w), x = child.hash_of('x') ~= vim.NIL, closed = child.closed() }
	child.answer('Yes')
	child.steps({ 'q' })
	settle_close()
	eq({ no, { open = child.popup() ~= nil, primary = child.primary(w), closed = child.closed() } }, {
		{ open = true, primary = '[b,a]on', x = false, closed = '' },
		{ open = false, primary = '[b,a,x]on', closed = 'x' },
	})
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

-- Telescope stubbed, as far as the picker uses it: find_files picks what _G.FRG_PICKED names,
-- full paths, as its multi-selection.
local function stub_picker()
	child.lua([[
		for _, m in ipairs({ 'telescope.builtin', 'telescope.actions', 'telescope.actions.state' }) do
			package.loaded[m] = nil
		end
		local chosen
		package.preload['telescope.actions'] = function()
			return { select_default = { replace = function(_, fn) chosen = fn end }, close = function() end }
		end
		package.preload['telescope.actions.state'] = function()
			return {
				get_current_picker = function()
					return { get_multi_selection = function()
						return vim.tbl_map(function(p) return { path = p } end, _G.FRG_PICKED or {})
					end }
				end,
				get_selected_entry = function() return nil end,
			}
		end
		package.preload['telescope.builtin'] = function()
			return { find_files = function(opts) opts.attach_mappings(1); chosen() end }
		end
	]])
end
local function pick(files, row)
	child.lua('_G.FRG_PICKED = vim.tbl_map(function(f) return _G.FRG_TEST.root .. "/" .. f end, ...)', { files })
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
		local root = _G.FRG_TEST.root
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
		local H = require('frogman.domains.history')
		local t = require('frogman.domains.window').data.crux[...]
		return vim.tbl_map(function(h) return vim.fn.fnamemodify(H.get_filepath_from_handle(h), ':.') end, t.primary_buffer)
	]], { w })
	eq({ shown = shown, picked = picked, queue = queue },
		{ shown = { 'init.lua' }, picked = { 'init.lua', './init.lua' }, queue = { 'sub/init.lua', 'init.lua' } })
end

T['T583 [char] two queued files of one name keep their own lines'] = function()
	child.lua([[
		local root = _G.FRG_TEST.root
		for _, d in ipairs({ 'a', 'b' }) do
			vim.fn.mkdir(root .. '/' .. d, 'p')
			vim.fn.writefile({ d }, root .. '/' .. d .. '/foo.lua')
		end
	]])
	child.steps({ ':e a/foo.lua', '<M-;><M-c>', ':e b/foo.lua', '<M-;><M-c>', ':e c' })
	child.cmd('bwipeout a/foo.lua')
	child.cmd('bwipeout b/foo.lua')
	child.settle()
	local w = child.win()
	local function queue()
		return child.lua([[
			local H = require('frogman.domains.history')
			local t = require('frogman.domains.window').data.crux[...]
			return vim.tbl_map(function(h) return vim.fn.fnamemodify(H.get_filepath_from_handle(h), ':.') end, t.primary_buffer)
		]], { w })
	end
	eq(queue(), { 'b/foo.lua', 'a/foo.lua' })
	open()
	child.popup_set(child.popup_lines())
	child.messages()
	child.cmd('write')
	child.settle()
	eq({ queue = queue(), errors = Extra.at_least(child.messages()) }, { queue = { 'b/foo.lua', 'a/foo.lua' }, errors = {} })
end

T['T584 [char] a picked file keeps its line through a second write'] = function()
	stub_picker()
	child.lua([[
		local root = _G.FRG_TEST.root
		vim.fn.mkdir(root .. '/sub', 'p')
		vim.fn.writefile({ 'sub' }, root .. '/sub/init.lua')
		vim.fn.writefile({ 'root' }, root .. '/init.lua')
		vim.cmd.edit(vim.fn.fnameescape(root .. '/sub/init.lua'))
	]])
	child.settle()
	child.steps({ '<M-;><M-c>' })
	local w = child.win()
	open()
	pick({ 'init.lua' }, 1)
	child.cmd('write')
	child.settle()
	local lines = child.popup_lines()
	child.popup_set({ lines[2], lines[1] })
	child.messages()
	child.cmd('write')
	child.settle()
	local queue = child.lua([[
		local H = require('frogman.domains.history')
		local t = require('frogman.domains.window').data.crux[...]
		return vim.tbl_map(function(h) return vim.fn.fnamemodify(H.get_filepath_from_handle(h), ':.') end, t.primary_buffer)
	]], { w })
	eq({ queue = queue, errors = Extra.at_least(child.messages()) }, { queue = { 'init.lua', 'sub/init.lua' }, errors = {} })
end

T['T585 [char] the pop-up opened again while it\'s open opens once'] = function()
	local w = queue_ba()
	open()
	child.lua('vim.api.nvim_set_current_win(...)', { w })
	child.messages()
	local ok, err = child.step('<M-;>F')
	local count = child.lua([[
		local n = 0
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.bo[b].filetype == 'frogman-primary-buffer-history' then n = n + 1 end
		end
		return n
	]])
	eq({ ok = ok, err = err, count = count, shown = child.popup() ~= nil }, { ok = true, err = nil, count = 1, shown = true })
	child.popup_set({ 'a.txt', 'b.txt' })
	child.lua('vim.api.nvim_set_current_win(...)', { w })
	child.messages()
	child.step('<M-;>F')
	local warned = false
	for _, m in ipairs(child.messages()) do
		if m.msg:find('edits not written yet', 1, true) then warned = true end
	end
	eq({ lines = child.popup_lines(), focused = child.win() == child.popup(), warned = warned },
		{ lines = { 'a.txt', 'b.txt' }, focused = true, warned = true })
end

T['T160 [char] with no picker, <M-e> gives a message and changes no line'] = function()
	queue_ba()
	open()
	eq(child.lua('return pcall(require, "telescope")'), false)
	child.messages()
	local ok, err = child.step('<M-e>')
	eq({ ok, err }, { true, nil })
	local named = false
	for _, m in ipairs(child.messages()) do
		if (m.msg or ''):find('telescope.nvim', 1, true) then named = true end
	end
	eq(named, true)
	eq(child.popup_lines(), { 'b.txt', 'a.txt' })
end

T['T680 [char] (A18) a config that sets primary_picker is told it\'s gone, and the picker is telescope\'s'] = function()
	child.messages()
	child.lua([[_G.FRG_TEST.setup({ primary_picker = function(add) _G.FRG_OWN_PICKER = true; add({}) end })]])
	local warned = 0
	for _, m in ipairs(child.messages()) do
		if (m.msg or ''):find('primary_picker', 1, true) and m.level == vim.log.levels.WARN then warned = warned + 1 end
	end
	stub_picker()
	queue_ba()
	open()
	child.popup_set({ 'b.txt', 'a.txt', '' })
	pick({ 'c.txt' }, 3)
	eq({ warned = warned, lines = child.popup_lines(), own = child.lua('return _G.FRG_OWN_PICKER == true') },
		{ warned = 1, lines = { 'b.txt', 'a.txt', 'c.txt' }, own = false })
end

T['T681 [char] (A18) gf answered No keeps the cursor on the first line it would leave out'] = function()
	local w = queue_ba()
	local pw = open()
	child.answer('No')
	child.popup_set({ 'a.txt', 'missing.txt', 'b.txt' })
	child.lua('vim.api.nvim_win_set_cursor(0, { 3, 0 })')
	child.steps({ 'gf' })
	eq({
		lines = child.popup_lines(),
		primary = child.primary(w),
		cursor = child.lua('return vim.api.nvim_win_get_cursor(...)[1]', { pw }),
	}, { lines = { 'b.txt', 'a.txt', 'missing.txt' }, primary = '[b,a]on', cursor = 3 })
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
local ns = vim.api.nvim_create_namespace('frogman_primary_popup')
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
		os.remove(_G.FRG_TEST.root .. '/b.txt')
		local H = require('frogman.domains.history')
		H.handles.set_tag(H.get_handle_from_filepath(_G.FRG_TEST.root .. '/b.txt'), 'feature')
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
	child.lua('_G.FRG_TEST.setup({ glyphs = { set = "ascii" } })')
	open()
	local ascii = table.concat(child.lua(DECORATION), '') .. table.concat(child.popup_lines(), '')
	eq({ lines = lines, on = on[1]:find('primary · on', 1, true) ~= nil, tag = on[1]:find('⎇feature', 1, true) ~= nil,
		closed = on[2]:find('↓', 1, true) ~= nil, off = off:find('primary · off', 1, true) ~= nil, ascii = ascii:find('[\128-\255]') == nil },
		{ lines = { 'b.txt', 'a.txt' }, on = true, tag = true, closed = true, off = true, ascii = true })
end

T['T453 [char] (A18) the pop-up\'s keys are keymaps.views\''] = function()
	child.lua('_G.FRG_TEST.setup({ keymaps = { views = { leave = "Q" } } })')
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
	child.lua('_G.FRG_TEST.setup({ primary_buffer_history_popup = { width = -0.5, height = 0.2 } })')
	queue_ba()
	open()
	local got = child.lua([[return { width = vim.api.nvim_win_get_width(0), columns = vim.o.columns,
		setting = require('frogman.configs').primary_buffer_history_popup.width }]])
	eq({ half = got.width == math.floor(got.columns * 0.5), setting = got.setting }, { half = true, setting = -0.5 })
end

-- leave_too and pick set to false: the pop-up maps neither, as the closed lists and the trail don't.
T['T539 [char] (A18) a view key set to false isn\'t mapped in the pop-up'] = function()
	child.lua('_G.FRG_TEST.setup({ keymaps = { views = { leave_too = false, pick = false } } })')
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

-- <CR> on line 2, once the pop-up's own opening step has closed.
T['T631 [char] (A18, A27) the pop-up\'s keys begin steps of their own'] = function()
	queue_ba()
	open()
	child.settle(300)
	child.lua('vim.api.nvim_win_set_cursor(0, { 2, 0 })')
	child.steps({ '<CR>' })
	settle_close()
	eq(child.lua([[
		for _, step in ipairs(require('frogman').ledger.steps()) do
			if step.cause == 'keymap' and step.trigger == '<CR>' then return true end
		end
		return false
	]]), true)
end

T['T632 [char] (A18, S2 Closed-stack picker) the views\' write key is keymaps.views.write, in both pop-ups'] = function()
	child.lua('_G.FRG_TEST.setup({ keymaps = { views = { write = "<M-w>" } } })')
	queue_ba()
	child.steps({ ':e c' })
	child.cmd('bdelete ' .. child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/c.txt")'))
	child.settle()
	open()
	local popup = child.lua([[return { mine = vim.fn.maparg('<M-w>', 'n', false, true).buffer == 1,
		default = vim.fn.maparg('<C-s>', 'n', false, true).buffer == 1 }]])
	child.steps({ 'q' })
	settle_close()
	child.cmd('FrogmanClosed')
	child.settle()
	local lists = child.lua([[return vim.bo.filetype == 'frogman-closed-lists' and vim.fn.maparg('<M-w>', 'n', false, true).buffer == 1]])
	eq({ popup = popup, lists = lists }, { popup = { mine = true, default = false }, lists = true })
end

-- * on c's line in the closed lists, then on a's line in the primary pop-up.
T['T633 [char] (A18, S2 Closed-stack picker, A27) * in either pop-up searches the trail for the file on the line'] = function()
	queue_ba()
	child.steps({ ':e c' })
	child.cmd('bdelete ' .. child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/c.txt")'))
	child.settle()
	local function searched(name)
		local got = child.lua([[return { ft = vim.bo.filetype, head = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] or '' }]])
		return got.ft == 'frogman-trail' and got.head:find('⌕', 1, true) ~= nil and got.head:find(name, 1, true) ~= nil
	end
	child.cmd('FrogmanClosed')
	child.settle()
	child.lua([[
		for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
			if l:find('c.txt', 1, true) then vim.api.nvim_win_set_cursor(0, { i, 0 }) end
		end
	]])
	child.steps({ '*' })
	local lists = searched('c.txt')
	child.lua([[
		for _, w in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_config(w).relative ~= '' then vim.api.nvim_win_close(w, true) end
		end
	]])
	child.settle(200)
	open()
	child.lua('vim.api.nvim_win_set_cursor(0, { 2, 0 })')
	child.steps({ '*' })
	eq({ lists = lists, popup = searched('a.txt') }, { lists = true, popup = true })
end

T['T454 [char] (A18, P9) a save keeps a queue entry whose file is gone from disk'] = function()
	local w = queue_ba()
	child.lua('os.remove(_G.FRG_TEST.root .. "/b.txt")') -- after the start, which writes the project's files
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
	child.lua('for _, f in ipairs({ "idx.json", "idx.js" }) do vim.fn.writefile({ f }, _G.FRG_TEST.root .. "/" .. f) end')
	child.cmd('edit idx.json')
	child.settle()
	local w = queue_ba()
	open()
	child.messages()
	child.popup_set({ 'idx.js', 'b.txt', 'a.txt' })
	child.cmd('write')
	child.settle()
	local first = child.lua([[
		local t = require('frogman.domains.window').data.crux[...]
		return vim.fs.basename(require('frogman.domains.history').get_filepath_from_handle(t.primary_buffer[1]) or '')
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


-- The queue is the new window's; the pop-up opens on it, and then that window
-- is closed. A write has no queue to go into: it's refused, the edits kept;
-- leaving drops them, saying so. Nothing that shouldn't happen does.
T['T1273 [char] (A18, review round 11) the primary pop-up whose window is gone refuses :w keeping the edits, and q leaves dropping them'] = function()
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.steps({ ':e b', '<M-;><M-c>' })
	local w = child.win()
	local pw = open()
	child.lua('vim.api.nvim_win_close(..., false)', { w })
	child.settle()
	child.lua('vim.api.nvim_set_current_win(...)', { pw })
	child.popup_set({ 'a.txt', 'b.txt' })
	child.messages()
	local dumps = child.dump_files()
	local wrote = child.lua('return { pcall(vim.cmd, "write") }')
	child.settle()
	local after_write = { modified = child.lua('return vim.bo.modified'), lines = child.popup_lines(),
		said = Extra.has(child.messages(), 'the window this queue was for is gone, so it isn\'t written.') }
	local ok = child.step('q')
	settle_close()
	eq({ wrote = wrote[1], after_write = after_write, ok = ok, open = child.popup() ~= nil,
		said = Extra.has(child.messages(), 'the window these were for is gone: the edits are dropped.'), dumped = child.dumped_since(dumps) },
		{ wrote = true, after_write = { modified = true, lines = { 'a.txt', 'b.txt' }, said = true }, ok = true, open = false, said = true })
end

-- A whole-editor load while the pop-up is open replaces its window's queue.
-- Unedited, the pop-up shows the loaded queue; edited, :w makes its lines the
-- queue and the loaded queue's other entries follow, none twice (a is in both).
T['T1274 [char] (A18, S1 Load, review round 11) the primary pop-up across a whole-editor load: unedited it\'s drawn again, edited :w puts its lines first'] = function()
	local w = queue_ba()
	eq(child.lua([[return { pcall(require('frogman').save_session, 'S1') }]]), { true })
	child.steps({ ':e c', '<M-;><M-c>' })
	eq(child.primary(w), '[c,b,a]on')
	local pw = open()
	-- the window shows b again first, as a session manager's restore would: the load matches it by that
	local function load_from_window()
		child.lua('vim.api.nvim_set_current_win(...)', { w })
		child.steps({ ':e b' })
		eq(child.lua([[return { pcall(require('frogman').load_session, 'S1') }]]), { true })
		child.settle(300)
		child.lua('vim.api.nvim_set_current_win(...)', { pw })
	end
	load_from_window()
	local unedited = { lines = child.popup_lines(), modified = child.lua('return vim.bo.modified') }
	child.lua('vim.api.nvim_win_close(..., true)', { pw })
	settle_close()
	child.lua('vim.api.nvim_set_current_win(...)', { w })
	child.steps({ ':e c', '<M-;><M-c>' })
	pw = open()
	child.popup_set({ 'd.txt', 'a.txt' })
	load_from_window()
	local edited = child.popup_lines()
	local wrote = child.lua('return { pcall(vim.cmd, "write") }')
	child.settle()
	eq({ unedited = unedited, edited = edited, wrote = wrote[1], queue = child.primary(w) },
		{ unedited = { lines = { 'b.txt', 'a.txt' }, modified = false }, edited = { 'd.txt', 'a.txt' }, wrote = true, queue = '[d,a,b]on' })
end

-- A file typed into the pop-up and written is drawn by its short name; * on
-- that line follows that file, not a file of that name where Neovim is.
T['T1275 [char] (A18, A27, review round 11) * in the primary pop-up on a line drawn by a write follows that line\'s file'] = function()
	child.lua([[
		vim.fn.mkdir(_G.FRG_TEST.root .. '/sub/dir', 'p')
		vim.fn.writefile({ 'foo' }, _G.FRG_TEST.root .. '/sub/dir/foo.txt')
	]])
	child.steps({ ':e a', '<M-;><M-c>' })
	open()
	child.popup_set({ 'a.txt', 'sub/dir/foo.txt' })
	child.cmd('write')
	child.settle()
	local drawn = child.popup_lines()
	child.lua([[
		_G.FRG_FOLLOWED = nil
		require('frogman.domains.ui.trail').follow = function(_, path) _G.FRG_FOLLOWED = path end
		vim.api.nvim_win_set_cursor(0, { 2, 0 })
	]])
	child.steps({ '*' })
	eq({ drawn = drawn, followed = child.lua('return _G.FRG_FOLLOWED and vim.fn.fnamemodify(_G.FRG_FOLLOWED, ":.")') },
		{ drawn = { 'a.txt', 'foo.txt' }, followed = 'sub/dir/foo.txt' })
end

-- The pop-up's buffer in a split of its own: <CR> there acts on the line under
-- that window's cursor.
T['T1276 [char] (A18, review round 11) <CR> in a split of the primary pop-up acts on the line under that split\'s cursor'] = function()
	child.steps({ ':e c', '<M-;><M-c>', ':e d', '<M-;><M-c>', ':e e', '<M-;><M-c>' })
	local w = child.win()
	eq(child.primary(w), '[e,d,c]on')
	open()
	child.cmd('split')
	child.settle()
	child.lua('vim.api.nvim_win_set_cursor(0, { 3, 0 })')
	child.steps({ '<CR>' })
	settle_close()
	eq(child.primary(w), '[c,e,d]on')
end


-- A tab session loaded into another tab leaves this window's queue as it was: the pop-up's edits, a.txt
-- deleted, are written as typed, nothing brought back after them.
T['T1287 [char] (A18, S1 Load, review round 11) a load that leaves the pop-up\'s window alone adds nothing to its edited write'] = function()
	child.cmd('tabnew')
	child.steps({ ':e c', ':e d' })
	eq(child.lua([[return { pcall(require('frogman').save_session, 't', { tab = vim.api.nvim_get_current_tabpage() }) }]]), { true })
	child.cmd('tabprevious')
	child.settle()
	local w = queue_ba()
	open()
	child.popup_set({ 'b.txt' })
	child.lua([[
		vim.cmd('noautocmd tabnew')
		vim.cmd('noautocmd edit d.txt')
		_G.FRG_T1287 = { pcall(require('frogman').load_session, 't', { tab = vim.api.nvim_get_current_tabpage() }) }
	]])
	child.settle(300)
	child.cmd('tabfirst')
	child.lua([[
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.api.nvim_win_get_config(win).relative ~= '' then vim.api.nvim_set_current_win(win) end
		end
	]])
	local wrote = child.lua('return { pcall(vim.cmd, "write") }')
	child.settle()
	eq({ loaded = child.lua('return _G.FRG_T1287'), wrote = wrote[1], queue = child.primary(w) },
		{ loaded = { true }, wrote = true, queue = '[b]on' })
end

return T
