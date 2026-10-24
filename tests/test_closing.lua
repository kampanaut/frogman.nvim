-- Closing and reopening: <M-.> and <M-S-w> (A15, A16). IDs are the spec's
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

-- A No Name buffer with text, made current in the window.
local function noname(lines, filetype, cursor)
	child.cmd('enew')
	child.settle()
	child.lua([[
		local lines, ft, cursor = ...
		vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
		if ft ~= vim.NIL then vim.bo.filetype = ft end
		if cursor ~= vim.NIL then vim.api.nvim_win_set_cursor(0, cursor) end
	]], { lines, filetype or vim.NIL, cursor or vim.NIL })
	child.settle()
	return child.lua('return vim.api.nvim_get_current_buf()')
end

local function hash_of_buf(buf)
	return child.lua('return require("cavediver.domains.history").get_hash_from_buffer(...)', { buf })
end

local function buf_open(hash)
	return child.lua('return require("cavediver.domains.history").get_buffer_from_hash(...) ~= nil', { hash })
end

-- Everything <M-.> must leave alone when it refuses.
local function snapshot()
	return { slots = child.slots(), shown = child.shown(), ordered = child.ordered(), closed = child.closed() }
end

T['T80 [char] <M-.> on the newest lands on the next, closes it, and keeps it in the ternary'] = function()
	child.steps({ ':e d', ':e e', ':e f' })
	eq(child.ordered(), 'f,e,d')
	local f = child.hash_of('f')
	child.steps({ '<M-.>' })
	eq(child.shown(), 'e')
	eq(child.closed(), 'f')
	eq(child.slots(), '⦉f⦊ [e] ⟦-⟧')
	eq(buf_open(f), false)
end

-- The switch's arrival is slotted before the close, as navigation slots it, so cleanup
-- has nothing to heal and says nothing.
T['T336 [char] (A15, A1) <M-.> lands by navigation, before the close: no healing notice'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	child.messages()
	child.steps({ '<M-.>' })
	eq(child.slots(), '⦉c⦊ [b] ⟦-⟧')
	local healed = false
	for _, m in ipairs(child.messages()) do
		if (m.msg or ''):find('Healed the triquetra', 1, true) then healed = true end
	end
	eq(healed, false)
end

-- The window's buffer is entry i > 1 of the ordered list while cycling, which
-- freezes the order.
T['T81 [char] <M-.> on entry i > 1 lands on entry i + 1'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':e d', ':e e', ':e f' })
	eq(child.ordered(), 'f,e,d,c,b,a')
	child.steps({ '<M-m>' })
	eq(child.shown(), 'e')
	child.steps({ '<M-.>' })
	eq(child.shown(), 'd')
	eq(child.closed(), 'e')
end

T['T81 [char] <M-.> on the oldest entry lands on the newest'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':e d', ':e e', ':e f' })
	eq(child.ordered(), 'f,e,d,c,b,a')
	child.steps({ '<M-n>' })
	eq(child.shown(), 'a')
	child.steps({ '<M-.>' })
	eq(child.shown(), 'f')
	eq(child.closed(), 'a')
end

T['T82 [char] <M-.> refuses a modified named buffer'] = function()
	child.steps({ ':e a', ':e b' })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed" })')
	child.settle()
	local before = snapshot()
	child.messages()
	child.steps({ '<M-.>' })
	eq(Extra.has(child.messages(), 'Buffer has unsaved changes'), true)
	eq(snapshot(), before)
end

T['T82 [char] <M-.> refuses a buffer shown in two windows'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	local before = snapshot()
	child.messages()
	child.steps({ '<M-.>' })
	eq(Extra.has(child.messages(), "Can't delete buffer because it's shown in another window."), true)
	eq(snapshot(), before)
	eq(#child.lua('return vim.api.nvim_list_wins()'), 2)
end

T['T82 [char] <M-.> refuses the only entry'] = function()
	child.steps({ ':e a' })
	local before = snapshot()
	child.messages()
	child.steps({ '<M-.>' })
	eq(Extra.has(child.messages(), "Can't delete buffer because it's the only one left"), true)
	eq(snapshot(), before)
end

-- b is closed first, so a is the only open file; a split and its close then
-- rebuild the history view, which keeps b's history (a closed file stays known).
T['T497 [char] (A15) <M-.> refuses the last open buffer after a window switch'] = function()
	child.steps({ ':e a', ':e b', '<M-.>' })
	child.cmd('split')
	child.cmd('close')
	child.settle()
	child.messages()
	child.steps({ '<M-.>' })
	eq({ refused = Extra.has(child.messages(), "Can't delete buffer because it's the only one left"), shown = child.shown() },
		{ refused = true, shown = 'a' })
end

-- <M-.> on c and :e c.txt in one batch, as a macro or a mapping gives them: the close's delete
-- waits for the editor to settle, by which time :e has brought c back.
T['T507 [char] (A15, P2) the close key\'s delete leaves a buffer a later command brought back'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	child.lua([[pcall(vim.api.nvim_feedkeys, vim.api.nvim_replace_termcodes('<M-.>:e c.txt<CR>', true, false, true), 'x', false)]])
	child.settle(300)
	eq({ shown = child.shown(), slots = child.slots(), closed = child.closed() }, { shown = 'c', slots = '⦉b⦊ [c] ⟦-⟧', closed = '' })
end

-- delete_buffer keeps the cursor before it switches the window away (history/routines.lua:709),
-- so the cache doesn't fall back to {1,0}.
T['T83 [char] <M-.> on a modified No Name buffer closes it and caches its lines, filetype and cursor'] = function()
	child.steps({ ':e a' })
	local buf = noname({ 'one', 'two', 'three' }, 'lua', { 2, 1 })
	local h = hash_of_buf(buf)
	eq(type(h), 'string')
	eq(child.lua('return vim.bo.modified'), true)
	eq(child.lua('return vim.api.nvim_win_get_cursor(0)'), { 2, 1 })

	child.steps({ '<M-.>' })
	eq(child.lua('return vim.api.nvim_buf_is_valid(...)', { buf }), false)
	eq(child.lua('return require("cavediver.domains.history").data.closed_buffers'), { h })
	eq(
		child.lua('return require("cavediver.domains.history").data.noname_content[...]', { h }),
		{ lines = { 'one', 'two', 'three' }, filetype = 'lua', cursor = { 2, 1 } }
	)
end

T['T84 [char] <M-.> in :help does not throw'] = function()
	child.steps({ ':e a', ':e b' })
	child.cmd('help')
	child.settle()
	eq(child.lua('return vim.bo.buftype'), 'help')
	child.messages()
	local ok, err = child.step('<M-.>')
	eq({ ok, err }, { true, nil })
	eq(Extra.at_least(child.messages()), {})
end

T['T85 [char] <M-.> on a file keeps its marks for when it is reopened'] = function()
	child.steps({ ':e a', ':e b' })
	child.lua('vim.api.nvim_buf_set_mark(0, "k", 1, 0, {})')
	eq(child.lua('return vim.api.nvim_buf_get_mark(0, "k")'), { 1, 0 })
	child.steps({ '<M-.>' })
	eq(child.shown(), 'a')
	child.steps({ '<M-S-w>' })
	eq(child.shown(), 'b')
	eq(child.lua('return vim.api.nvim_buf_get_mark(0, "k")'), { 1, 0 })
end

T['T86 [char] <M-S-w> reopens the newest closed buffer as current, the old current in the ternary'] = function()
	child.steps({ ':e d', ':e e', ':e f', '<M-.>' })
	eq(child.shown(), 'e')
	eq(child.closed(), 'f')
	child.steps({ '<M-S-w>' })
	eq(child.shown(), 'f')
	eq(child.slots(), '⦉e⦊ [f] ⟦-⟧')
	eq(child.closed(), '')
end

T['T87 [char] <M-S-w> with an empty closed stack warns'] = function()
	child.steps({ ':e a' })
	child.messages()
	child.steps({ '<M-S-w>' })
	local msgs = child.messages()
	eq(Extra.has(msgs, 'No closed buffers to reopen.'), true)
	eq(Extra.at_least(msgs, vim.log.levels.WARN), { 'No closed buffers to reopen.' })
	eq(child.shown(), 'a')
end

T['T88 [char] a No Name buffer closed with text comes back with the same lines and filetype'] = function()
	child.steps({ ':e a' })
	noname({ 'first line', 'second line' }, 'markdown')
	child.steps({ '<M-.>' })
	eq(child.shown(), 'a')
	child.steps({ '<M-S-w>' })
	eq(child.lua('return vim.api.nvim_buf_get_name(0)'), '')
	eq(child.lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'first line', 'second line' })
	eq(child.lua('return vim.bo.filetype'), 'markdown')
end

T['T89 [char] <M-S-w> on a missing file says so and leaves the entry on the stack'] = function()
	child.steps({ ':e d', ':e e', ':e f', '<M-.>' })
	eq(child.closed(), 'f')
	child.lua('os.remove(_G.CDV_TEST.root .. "/f.txt")')
	child.messages()
	local ok, err = child.step('<M-S-w>')
	eq({ ok, err }, { true, nil })
	local said = false
	for _, m in ipairs(Extra.at_least(child.messages(), vim.log.levels.WARN)) do
		if m:find('f.txt', 1, true) then said = true end
	end
	eq(said, true)
	eq(child.closed(), 'f')
end

T['T90 [char] a reopened No Name buffer gets its cursor in its own window'] = function()
	child.steps({ ':e a' })
	-- Cursor on line 3; a.txt, where <M-.> lands, has one line.
	noname({ 'one', 'two', 'three' }, nil, { 3, 2 })
	child.steps({ '<M-.>' })
	eq(child.shown(), 'a')
	child.messages()
	local ok, err = child.step('<M-S-w>')
	eq({ ok, err }, { true, nil })
	eq(Extra.at_least(child.messages()), {})
	eq(child.lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'one', 'two', 'three' })
	eq(child.lua('return vim.api.nvim_win_get_cursor(0)'), { 3, 2 })
end

T['T91 [char] after a No Name buffer is reopened, its old hash is renamed everywhere'] = function()
	-- b is left while the No Name buffer is its ternary, so dtm[b] names it;
	-- then the No Name buffer is closed from c, where it lands in the ternary.
	child.steps({ ':e a' })
	local buf = noname({ 'scratch text' })
	child.steps({ ':e b', ':e c' })
	child.cmd('buffer ' .. buf)
	child.settle()
	local old = hash_of_buf(buf)
	child.steps({ '<M-.>' })
	eq(child.shown(), 'c')
	eq(child.lua('return require("cavediver.domains.window").data.crux[vim.api.nvim_get_current_win()].ternary_slot'), old)
	eq(child.lua('return require("cavediver.domains.window").data.crux[vim.api.nvim_get_current_win()].displacement_ternary_map[...]', { child.hash_of('b') }), old)

	child.steps({ '<M-S-w>' })
	eq(child.lua('return vim.api.nvim_buf_get_lines(0, 0, -1, false)'), { 'scratch text' })
	local new = hash_of_buf(child.lua('return vim.api.nvim_get_current_buf()'))
	eq(new ~= old, true)
	eq(child.refs(old), {})
	eq(child.lua('return require("cavediver.domains.window").data.crux[vim.api.nvim_get_current_win()].displacement_ternary_map[...]', { child.hash_of('b') }), new)
end

T['T162 [char] pushing a hash already on the closed stack keeps one copy, as the newest'] = function()
	child.steps({ ':e a' })
	local got = child.lua([[
		local H = require('cavediver.domains.history')
		local root = _G.CDV_TEST.root
		H.register_filepath(root .. '/x.txt')
		H.register_filepath(root .. '/t.txt')
		local x = H.get_hash_from_filepath(root .. '/x.txt')
		local t = H.get_hash_from_filepath(root .. '/t.txt')
		H.routines.track_closing_filehash_force(x)
		H.routines.track_closing_filehash_force(t)
		H.routines.track_closing_filehash_force(x)
		return true
	]])
	eq(got, true)
	eq(child.closed(), 't,x')
end

T['T164 [char] <M-.> in a window visiting an untracked buffer closes it and lands on the current slot'] = function()
	child.steps({ ':e b', ':e a', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [a] ⟦b⟧')
	-- Visit a nofile scratch in the same window.
	local scratch = child.lua([[
		local buf = vim.api.nvim_create_buf(true, true)
		vim.api.nvim_win_set_buf(0, buf)
		return buf
	]])
	child.settle()
	eq(child.lua('return vim.bo.buftype'), 'nofile')
	child.messages()
	local ok, err = child.step('<M-.>')
	eq({ ok, err }, { true, nil })
	eq(Extra.at_least(child.messages()), {})
	eq(child.lua('return vim.api.nvim_buf_is_loaded(...)', { scratch }), false)
	eq(child.shown(), 'a')
	eq(child.slots(), '⦉-⦊ [a] ⟦b⟧')
end

T['T165 [char] <M-.> in a help window closes the help buffer and leaves a alone'] = function()
	child.steps({ ':e a' })
	local a_win = child.win()
	child.cmd('help')
	child.settle()
	local help_buf = child.lua('return vim.api.nvim_get_current_buf()')
	eq(child.lua('return vim.bo.buftype'), 'help')
	child.messages()
	local ok, err = child.step('<M-.>')
	eq({ ok, err }, { true, nil })
	eq(Extra.at_least(child.messages()), {})
	eq(child.lua('return vim.api.nvim_buf_is_loaded(...)', { help_buf }), false)
	eq(child.lua('return vim.api.nvim_list_wins()'), { a_win })
	eq(child.shown(a_win), 'a')
	eq(child.slots(a_win), '⦉-⦊ [a] ⟦-⟧')
end

T['T166 [char] <M-.> on help in the only window closes the help buffer'] = function()
	child.cmd('help')
	child.cmd('only')
	child.settle()
	local help_buf = child.lua('return vim.api.nvim_get_current_buf()')
	eq(child.lua('return vim.bo.buftype'), 'help')
	child.messages()
	local ok, err = child.step('<M-.>')
	eq({ ok, err }, { true, nil })
	eq(child.lua('return vim.api.nvim_buf_is_loaded(...)', { help_buf }), false)
	eq(#child.lua('return vim.api.nvim_list_wins()'), 1)
	eq(Extra.at_least(child.messages()), {})
end

T['T167 [char] <M-.> on a running terminal refuses with a message'] = function()
	child.steps({ ':e a', ':e b' })
	child.lua('vim.o.shell = "sh"')
	child.cmd('terminal sleep 1000')
	child.settle(100)
	local term = child.lua('return vim.api.nvim_get_current_buf()')
	eq(child.lua('return vim.bo.buftype'), 'terminal')
	eq(child.lua('return vim.fn.jobwait({ vim.bo.channel }, 0)[1]'), -1)
	child.messages()
	local ok, err = child.step('<M-.>')
	eq({ ok, err }, { true, nil })
	eq(#Extra.at_least(child.messages(), vim.log.levels.WARN) > 0, true)
	eq(child.lua('return vim.api.nvim_buf_is_valid(...) and vim.api.nvim_get_current_buf() == ...', { term }), true)
end

return T
