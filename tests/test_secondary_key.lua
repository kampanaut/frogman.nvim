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

T['T44 [today] with the secondary closed and its file deleted, <M-f> warns "Removed secondary file not found in filesystem" and empties the slot'] = function()
	-- The ternary c is closed too; a closed secondary stays in its slot either way (I4).
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	child.cmd('bdelete c.txt')
	child.settle()
	child.cmd('bdelete b.txt')
	child.settle()
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	child.messages()
	-- Delete b.txt and press in one go, before any other history event.
	local ok, err = K.press_after(child, K.rm_code('b'), '<M-f>')
	eq({ ok, err }, { true, nil })
	eq(K.has(K.messages(child), 'Removed secondary file not found in filesystem'), true)
	eq(child.slots(), '⦉c⦊ [d] ⟦-⟧')
end

T['T45 [target] with the secondary file deleted on disk, the pointer is kept and <M-f> says the file is missing'] = function()
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

return T
