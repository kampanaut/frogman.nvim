-- Triquetra lifecycle (M6, A2-A5). IDs are the spec's (what-is-cavediver.md,
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
-- before the name so cavediver never sees it as a plain file.
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
				triquetra = require('cavediver.domains.window').data.crux[w] ~= nil,
				ui_cache = require('cavediver.domains.ui.data').window_display_cache[w] ~= nil,
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
	eq(child.lua('return require("cavediver.domains.history").get_hash_from_buffer(vim.api.nvim_get_current_buf()) == nil'), true)
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

return T
