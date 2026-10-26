-- <M-f>, toggle_secondary (A6). IDs are the spec's (what-is-cavediver.md, section 7).
local Helpers = dofile('tests/helpers.lua')
local K = dofile('tests/helpers_keys.lua')
local eq, no_eq = Helpers.eq, Helpers.expect.no_equality
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = child.stop,
	},
})

T['T36 [char] graduation: {c=c t=b}, dtm{b→a}, <M-f> gives {c=c s=b}, dsm{b→a}, same buffer, "Ternary slot graduated"'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	eq(K.note(child, 'dtm', 'b'), 'a')
	child.messages()
	child.steps({ '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	eq(K.note(child, 'dsm', 'b'), 'a')
	eq(child.shown(), 'c')
	eq(K.has(K.messages(child), 'Ternary slot graduated'), true)
end

T['T37 [char] with secondary and ternary empty and two buffers in history, <M-f> fills the secondary from ordered[2] without switching'] = function()
	-- A fresh split has an empty triquetra; history holds b, a.
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	eq(child.slots(), '⦉-⦊ [b] ⟦-⟧')
	local second = vim.split(child.ordered(), ',')[2]
	eq(second, 'a')
	child.messages()
	child.steps({ '<M-f>' })
	eq(child.slots(), '⦉-⦊ [b] ⟦' .. second .. '⟧')
	eq(child.shown(), 'b')
	eq(K.has(K.messages(child), 'Secondary buffer populated from history.'), true)
end

T['T38 [char] with one buffer in history, <M-f> warns "insufficent history"'] = function()
	child.steps({ ':e a' })
	child.messages()
	child.steps({ '<M-f>' })
	eq(child.slots(), '⦉-⦊ [a] ⟦-⟧')
	eq(K.has(K.messages(child), 'insufficent history'), true)
end

T['T39 [char] {c=c s=b}, <M-f> shows b, {c=b s=c}, dsm{c-swap→b}'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	child.steps({ '<M-f>' })
	eq(child.shown(), 'b')
	eq(child.slots(), '⦉-⦊ [b] ⟦c⟧')
	-- c is left by a swap, so its note is a swap note (T191).
	eq(child.notes(), 'dtm{b>a} dsm{b>a c-swap>b}')
end

T['T40 [char] with a ternary T, <M-f> writes dtm[A-swap] = T'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	child.steps({ '<M-f>' })
	eq(child.slots(), '⦉c⦊ [b] ⟦d⟧')
	eq(K.note(child, 'dtm', 'd-swap'), 'c')
end

T['T41 [char] when the window shows a buffer other than its current slot, <M-f> switches back to it and changes no slot'] = function()
	-- <M-n> starts a cycle and moves the window off its current slot c.
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', '<M-n>' })
	no_eq(child.shown(), 'c')
	local slots, notes = child.slots(), child.notes()
	eq(slots, '⦉-⦊ [c] ⟦b⟧')
	child.messages()
	child.steps({ '<M-f>' })
	eq(child.shown(), 'c')
	eq(child.slots(), slots)
	eq(child.notes(), notes)
	eq(K.has(K.messages(child), 'Jumped back to windows current buffer.'), true)
end

T['T42 [char] after :bdelete of the secondary and one more :e, the secondary keeps the closed hash, and <M-f> reopens it'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [c] ⟦b⟧')
	child.cmd('bdelete b.txt')
	child.settle()
	child.steps({ ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	eq(vim.tbl_contains(vim.split(child.closed(), ','), 'b'), true)
	child.steps({ '<M-f>' })
	eq(child.shown(), 'b')
	eq(child.slots(), '⦉c⦊ [b] ⟦d⟧')
	eq(vim.tbl_contains(vim.split(child.closed(), ','), 'b'), false)
end

T['T43 [char] after a cycle, <M-f> with secondary and ternary empty never puts the current buffer in the secondary'] = function()
	-- The other window cycles (history frozen at c,b,a), then <C-w>p into the
	-- fresh split showing b, whose slots are empty (t/pkB_d11_dup.lua).
	child.steps({ ':e a', ':e b' })
	child.cmd('vsplit')
	child.settle()
	child.cmd('wincmd p')
	child.settle()
	child.steps({ ':e c', '<M-n>' })
	child.cmd('wincmd p')
	child.settle()
	eq(child.slots(), '⦉-⦊ [b] ⟦-⟧')
	child.step('<M-f>')
	eq(K.duplicate(child), false)
end

T['T44 [char] with the secondary closed and its file deleted, a cleanup pass keeps the slot, and <M-f> says so'] = function()
	-- The ternary c is closed too; a closed secondary stays in its slot either way (I4).
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	child.cmd('bdelete c.txt')
	child.settle()
	child.cmd('bdelete b.txt')
	child.settle()
	child.lua(K.rm_code('b'))
	child.lua('require("cavediver.domains.history").cleanup_system()')
	child.settle()
	eq({ slots = child.slots(), closed = child.closed() }, { slots = '⦉c⦊ [d] ⟦b⟧', closed = 'c,b' })
	child.messages()
	local ok, err = child.step('<M-f>')
	eq({ ok, err }, { true, nil })
	eq(K.has(K.messages(child), "isn't on disk right now"), true)
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
end

T['T45 [char] with the secondary file deleted on disk, the pointer is kept and <M-f> says the file is missing'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	child.cmd('bdelete c.txt')
	child.settle()
	child.cmd('bdelete b.txt')
	child.settle()
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	child.messages()
	local ok, err = K.press_after(child, K.rm_code('b'), '<M-f>')
	eq({ ok, err }, { true, nil })
	local msgs = K.messages(child)
	eq(K.hook_failures(msgs), {})
	no_eq(K.warnings(msgs), {})
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
end

T["T150 [char] Q6's ten keys: the third <M-f> rewrites dtm[b] := c, and the restore gives {c=b s=a t=c}"] = function()
	child.steps({ ':e a', ':e b', ':e c', ':e b', '<M-f>', ':e a', '<M-f>' })
	eq(child.slots(), '⦉b⦊ [c] ⟦a⟧')
	eq(K.note(child, 'dtm', 'b'), 'a')
	child.messages()
	child.steps({ '<M-f>' })
	eq(K.note(child, 'dtm', 'b'), 'c')
	child.steps({ '<M-S-f>' })
	local ok, err = child.step('<M-;><M-r>')
	eq({ ok, err }, { true, nil })
	eq(K.hook_failures(K.messages(child)), {})
	eq(child.slots(), '⦉c⦊ [b] ⟦a⟧')
end

-- The user's function notes it ran, and inside what step.
T['T571 [char] (A25, M11) a key follows its export as reassigned'] = function()
	child.steps({ ':e a', ':e b' })
	child.lua([[
		require('cavediver').toggle_secondary = function()
			local step = require('cavediver').ledger.data.open
			_G.CDV_RAN = step and step.trigger or 'no step'
		end
	]])
	child.steps({ '<M-f>' })
	eq(child.lua('return _G.CDV_RAN or vim.NIL'), '<M-f>')
end

-- A No Name buffer N holding `lines`, made with :enew in the current window; returns its hash.
local function noname(lines)
	child.cmd('enew')
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, ...)', { lines })
	child.settle()
	return child.lua('return require("cavediver.domains.history").get_hash_from_buffer(vim.api.nvim_get_current_buf())')
end

-- N closed, then its text held as a text a load left unread whose read gives nothing, as one whose
-- file failed its check does.
local function lose(hash)
	child.cmd('bwipeout! ' .. child.lua('return require("cavediver.domains.history").get_buffer_from_hash(...)', { hash }))
	child.settle()
	child.lua([[require('cavediver.domains.history').data.noname_content[...] = { scratch = 'gone', read = function() return nil end }]], { hash })
end

-- ⦉a⦊ [N] ⟦-⟧, the window visiting a scratch buffer while N is closed and its text lost.
T['T621 [char] (A6, M5) a current slot that can\'t be reopened stops the key'] = function()
	child.steps({ ':e a' })
	local n = noname({ 'draft' })
	child.lua('vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, true))')
	child.settle()
	lose(n)
	local before = child.slots()
	child.messages()
	child.steps({ '<M-f>' })
	local msgs = K.messages(child)
	eq({ slots = child.slots(), said = K.has(msgs, "can't be reopened, so the window stays where it is."),
		graduated = K.has(msgs, 'Ternary slot graduated') }, { slots = before, said = true, graduated = false })
end

-- A history entry whose buffer isn't registered, ahead of the current one, as an undone arrival leaves it.
T['T622 [char] (A6, D11) a fill that finds nothing but the current buffer says the history is short'] = function()
	child.steps({ ':e a' })
	child.lua([[table.insert(require('cavediver.domains.history').data.ordered.crux, 1, { buf = vim.api.nvim_create_buf(true, true) })]])
	child.messages()
	child.steps({ '<M-f>' })
	local msgs = K.messages(child)
	eq({ slots = child.slots(), populated = K.has(msgs, 'populated from history'), short = K.has(msgs, 'insufficent history') },
		{ slots = '⦉-⦊ [a] ⟦-⟧', populated = false, short = true })
end

-- {c=a s=N t=t}, N closed and its text lost.
T['T623 [char] (A6, M7) a secondary that can\'t be reopened leaves the notes as they were'] = function()
	child.steps({ ':e a' })
	local n = noname({ 'n' })
	child.steps({ '<M-f>', '<M-f>', ':e t', ':e a' })
	eq(child.slots():match('^⦉t⦊ %[a%] ⟦(.-)⟧$') ~= '-', true)
	lose(n)
	local before = child.notes()
	child.messages()
	child.steps({ '<M-f>' })
	eq({ notes = child.notes(), slots = child.slots(), said = K.has(K.messages(child), 'Removed secondary file not found in filesystem') },
		{ notes = before, slots = '⦉t⦊ [a] ⟦-⟧', said = true })
end

return T
