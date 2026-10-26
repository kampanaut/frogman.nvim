-- Triquetra lifecycle (M6, A2-A5). IDs are the spec's (what-is-frogman.md,
-- section 7).
local Helpers = dofile('tests/helpers.lua')
local X = dofile('tests/helpers_engine_nav.lua')
local eq = Helpers.eq
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.setup()
			X.load(child)
		end,
		post_once = child.stop,
	},
})

-- An acwrite buffer with a :// name, the way oil's look; buftype is set
-- before the name so frogman never sees it as a plain file.
local function enter_acwrite()
	child.lua([[
		local buf = vim.api.nvim_create_buf(true, false)
		vim.bo[buf].buftype = 'acwrite'
		vim.api.nvim_buf_set_name(buf, 'acw://scratch')
		vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = buf, callback = function() end })
		vim.api.nvim_set_current_buf(buf)
	]])
	child.settle(200)
end

T['T21 [char] a first :e x in a fresh window gives {c=x}'] = function()
	child.steps({ ':e x' })
	eq(child.slots(), '⦉-⦊ [x] ⟦-⟧')
	eq(child.notes(), 'dtm{} dsm{}')
	eq(child.primary(), '[]off')
end

T['T22 [char] :vsplit gives the new window a fresh {c=<shown>}, not a copy'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d', '<M-;><M-c>' })
	local w1 = X.win(child)
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	eq(child.primary(), '[d]on')
	local w1_notes = child.notes()
	child.cmd('vsplit')
	child.settle()
	local w2 = X.win(child)
	Helpers.expect.no_equality(w2, w1)
	eq(child.slots(w2), '⦉-⦊ [d] ⟦-⟧')
	eq(child.notes(w2), 'dtm{} dsm{}')
	eq(child.primary(w2), '[]off')
	-- the old window is untouched
	eq(child.slots(w1), '⦉c⦊ [d] ⟦b⟧')
	eq(child.notes(w1), w1_notes)
	eq(child.primary(w1), '[d]on')
end

T['T23 [char] a float never gets a triquetra'] = function()
	child.steps({ ':e a', ':e b' })
	local float = child.lua([[
		local buf = vim.fn.bufnr('a.txt')
		return vim.api.nvim_open_win(buf, true, { relative = 'editor', row = 1, col = 1, width = 30, height = 5 })
	]])
	child.settle(200)
	eq(child.slots(float), 'no triquetra')
	-- a visit inside the float doesn't give it one either
	child.steps({ ':e c' })
	child.settle(200)
	eq(child.lua('return vim.api.nvim_get_current_win()'), float)
	eq(child.slots(float), 'no triquetra')
end

T['T24 [char] an acwrite buffer shown in the window keeps the triquetra'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	enter_acwrite()
	eq(child.lua('return vim.bo.buftype'), 'acwrite')
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
end

T['T25 [char] closing a window drops its triquetra and its UI cache'] = function()
	child.steps({ ':e a' })
	child.cmd('vsplit')
	child.steps({ ':e b' })
	local w2 = X.win(child)
	local state = function()
		return child.lua([[
			local w = ...
			return {
				triquetra = require('frogman.domains.window').data.crux[w] ~= nil,
				ui_cache = require('frogman.domains.ui.data').window_display_cache[w] ~= nil,
			}
		]], { w2 })
	end
	eq(state(), { triquetra = true, ui_cache = true })
	child.cmd('close')
	child.settle(200)
	eq(state(), { triquetra = false, ui_cache = false })
end

T['T26 [char] :terminal in a window with {c=c s=b} keeps its triquetra, and the terminal stays untracked (the visiting rule)'] = function()
	child.lua([[vim.o.shell = 'sh']])
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	child.cmd('terminal')
	child.settle(300)
	eq(child.lua('return vim.bo.buftype'), 'terminal')
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	eq(child.lua('return require("frogman.domains.history").get_hash_from_buffer(vim.api.nvim_get_current_buf()) == nil'), true)
end

T['T27 [char] the window keeps {c=c s=b} while it shows a terminal, and :e c returns to it intact'] = function()
	child.lua([[vim.o.shell = 'sh']])
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	child.cmd('terminal')
	child.settle(300)
	eq(child.lua('return vim.bo.buftype'), 'terminal')
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	child.steps({ ':e c' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
end


-- Windows A (a), C (c) and D (d, then f), entered D, then C, then A, so C's jump points at D.
-- :bdelete c.txt in A closes C, and the view is rebuilt for a window: A's, not D's.
T['T513 [char] (M6) under the window view, closing a window rebuilds the view for the window you\'re in'] = function()
	child.setup({ history_view = 'window' })
	child.steps({ ':e a' })
	local a = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('vsplit')
	child.steps({ ':e c' })
	local c = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('vsplit')
	child.steps({ ':e d', ':e f' })
	child.lua('vim.api.nvim_set_current_win(...)', { c })
	child.settle()
	child.lua('vim.api.nvim_set_current_win(...)', { a })
	child.settle()
	child.cmd('bdelete ' .. child.lua('return vim.fn.bufnr(_G.FRG_TEST.root .. "/c.txt")'))
	child.settle(300)
	local dumps = child.dump_files()
	local ok = child.lua([[return { pcall(require('frogman').toggle_secondary) }]])
	child.settle(200)
	eq({ ok = ok[1], dump = child.dumped_since(dumps) }, { ok = true, dump = nil })
end

-- Windows first (b) and second (b), first entered, then a float showing a.txt, then second, which closes.
T['T619 [char] (M6, M10) a window closed hands the view to a window with a triquetra, never a float'] = function()
	child.steps({ ':e a', ':e b' })
	local first = child.lua('return vim.api.nvim_get_current_win()')
	child.cmd('split')
	child.settle()
	local second = child.lua('return vim.api.nvim_get_current_win()')
	child.lua('vim.api.nvim_set_current_win(...)', { first })
	child.settle()
	child.lua([[vim.api.nvim_open_win(vim.fn.bufnr(_G.FRG_TEST.root .. '/a.txt'), true,
		{ relative = 'editor', row = 1, col = 1, width = 20, height = 3 })]])
	child.settle()
	child.lua('vim.api.nvim_set_current_win(...)', { second })
	child.settle()
	local got = child.lua([[
		vim.cmd('close')
		return require('frogman.domains.window').data.last_valid_window
	]])
	eq(got, first)
end

T['T620 [char] (M6) window 0 is the current window'] = function()
	child.steps({ ':e a' })
	eq(child.lua([[
		local t = require('frogman').get_window_triquetra(0)
		local crux = require('frogman.domains.window').data.crux
		return { zero = crux[0] ~= nil, same = t == crux[vim.api.nvim_get_current_win()] }
	]]), { zero = false, same = true })
end

-- P arrives in W, the queue is switched off, and W is left and entered again on P.
T['T514 [char] (M6, I10) entering the current buffer again keeps the last arrival'] = function()
	child.steps({ ':e a', '<M-;><M-c>', ':e b' })
	child.cmd('enew')
	child.settle()
	child.steps({ '<M-;><M-x>' })
	child.cmd('vsplit')
	child.steps({ ':e d' })
	child.cmd('wincmd p')
	child.settle()
	child.cmd('setlocal buftype=nofile')
	child.settle(300)
	eq({ slots = child.slots(), primary = child.primary() }, { slots = '⦉-⦊ [b] ⟦-⟧', primary = '[a]off' })
end

-- Two loads of sessions with no file, the second with a help window focused: each is a fresh start.
T['T515 [char] (M6) a fresh start leaves a window in last_valid_window'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	child.lua('require("frogman").load_session("fresh-1")')
	child.settle(100)
	child.cmd('help')
	child.settle()
	child.lua('require("frogman").load_session("fresh-2")')
	child.settle(200)
	eq(child.lua([[
		local W = require('frogman.domains.window').data
		local w = W.last_valid_window
		return { valid = w ~= nil and vim.api.nvim_win_is_valid(w), tracked = w ~= nil and W.crux[w] ~= nil }
	]]), { valid = true, tracked = true })
end

T['T624 [char] (M6) a fresh start gives a float no triquetra'] = function()
	child.steps({ ':e a', ':e b' })
	local float = child.lua([[return vim.api.nvim_open_win(vim.fn.bufnr(_G.FRG_TEST.root .. '/a.txt'), false,
		{ relative = 'editor', row = 1, col = 1, width = 20, height = 3 })]])
	child.lua('require("frogman").load_session("fresh-1")')
	child.settle(200)
	eq(child.lua('return require("frogman.domains.window").data.crux[...] ~= nil', { float }), false)
end

-- A split's winbar drawn, then frogman off, the split closed, frogman set up again and a load: the
-- first from bare, a fresh start, and the second from idle, which tears down first.
T['T626 [char] (M6, S1) a load lets go what the UI kept of a window closed while frogman was off'] = function()
	local SEGMENT = 'return require("frogman.domains.ui.routines").winbar_segment(...) ~= ""'
	local function closed_while_off(session)
		child.cmd('vsplit')
		child.steps({ ':e b' })
		local split = child.lua('return vim.api.nvim_get_current_win()')
		child.settle(300)
		local before = child.lua(SEGMENT, { split })
		child.lua('require("frogman").disable()')
		child.cmd('close')
		child.lua('_G.FRG_TEST.setup()')
		local from = child.lua('return require("frogman.domains.storage.sm"):state()')
		child.lua('require("frogman").load_session(...)', { session })
		child.settle(200)
		return { from = from, before = before, after = child.lua(SEGMENT, { split }) }
	end
	child.steps({ ':e a' })
	eq({ closed_while_off('fresh-1'), closed_while_off('fresh-2') }, {
		{ from = 'bare', before = true, after = false },
		{ from = 'idle', before = true, after = false },
	})
end

return T
