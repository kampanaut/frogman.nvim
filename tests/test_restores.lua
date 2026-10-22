-- Restores and their notes: <M-;><M-r> restore_ternary, <M-;><M-t> restore_secondary (A11).
-- IDs are the spec's (what-is-cavediver.md, section 7).
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

T['T61 [char] at b with {c=b t=d} and dtm{b→a}: restore ternary gives t=a, dtm{b→d}; again t=d, dtm{b→a}'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':e d', ':e b' })
	eq(child.slots(), '⦉d⦊ [b] ⟦-⟧')
	eq(K.note(child, 'dtm', 'b'), 'a')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	eq(K.note(child, 'dtm', 'b'), 'd')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉d⦊ [b] ⟦-⟧')
	eq(K.note(child, 'dtm', 'b'), 'a')
end

T['T62 [char] restoring a ternary equal to the secondary swaps the secondary and ternary contents'] = function()
	-- :e b reaches the secondary by plain navigation; b's note b>a names the secondary.
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e a', ':e b' })
	eq(child.slots(), '⦉c⦊ [b] ⟦a⟧')
	eq(K.note(child, 'dtm', 'b'), 'a')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉a⦊ [b] ⟦c⟧')
end

T['T63 [char] restoring the secondary flip-flops, each press writing the replaced secondary into dsm[A]'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', '<M-f>' })
	eq(child.slots(), '⦉-⦊ [b] ⟦c⟧')
	eq(K.note(child, 'dsm', 'b'), 'a')
	child.steps({ '<M-;><M-t>' })
	eq(child.slots(), '⦉-⦊ [b] ⟦a⟧')
	eq(K.note(child, 'dsm', 'b'), 'c')
	child.steps({ '<M-;><M-t>' })
	eq(child.slots(), '⦉-⦊ [b] ⟦c⟧')
	eq(K.note(child, 'dsm', 'b'), 'a')
	child.steps({ '<M-;><M-t>' })
	eq(child.slots(), '⦉-⦊ [b] ⟦a⟧')
end

T['T64 [char] with no entry, it warns "No ternary relationship found for restoration."'] = function()
	child.steps({ ':e a', ':e b' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	child.messages()
	child.steps({ '<M-;><M-r>' })
	eq(K.has(K.messages(child), 'No ternary relationship found for restoration.'), true)
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
end

-- a ends up with the plain note a>b and the swap note a-swap>f, ternary d
-- (t/b6_rows.lua).
local function two_notes()
	child.steps({ ':e b', ':e a', ':e c', ':e f', ':e a', '<M-S-f>', ':e d', ':e a' })
	eq(child.slots(), '⦉d⦊ [a] ⟦-⟧')
	eq(K.notes_for(child, { 'a' }), 'dtm{a-swap>f a>b} dsm{}')
end

T['T65 [char] when dtm[A-swap] is set and differs from the ternary, the restore uses it instead of dtm[A]'] = function()
	two_notes()
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉f⦊ [a] ⟦-⟧')
end

T['T66 [char] with the maps set so the remembered value equals the slot, the restore throws "Remembered ternary is the same as current ternary"'] = function()
	child.steps({ ':e a', ':e b' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	K.set_note(child, 'dtm', 'b', 'a')
	local ok, err = child.step('<M-;><M-r>')
	eq(ok, false)
	no_eq(tostring(err):find('This is impossible. Remembered ternary is the same as current ternary.', 1, true), nil)
end

T['T67 [char] (D9) a -swap note at a closed file deleted on disk is skipped and kept: the plain note restores and flip-flops'] = function()
	two_notes()
	child.cmd('bdelete f.txt')
	child.lua(K.rm_code('f'))
	child.settle()
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉b⦊ [a] ⟦-⟧')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉d⦊ [a] ⟦-⟧')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉b⦊ [a] ⟦-⟧')
	eq(K.note(child, 'dtm', 'a-swap'), 'f')
end

T['T173 [char] (D9) a note at a file deleted on disk whose buffer is still open restores it and flip-flops with it'] = function()
	two_notes()
	child.lua(K.rm_code('f'))
	eq(child.lua([[return vim.fn.bufloaded('f.txt')]]), 1)
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉f⦊ [a] ⟦-⟧')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉d⦊ [a] ⟦-⟧')
	child.steps({ '<M-;><M-r>' })
	eq(child.slots(), '⦉f⦊ [a] ⟦-⟧')
end

T["T174 [char] (D9) when both of a buffer's notes point at closed files deleted on disk, the restore says so, changes no slot, keeps both notes"] = function()
	two_notes()
	child.cmd('bdelete f.txt')
	child.cmd('bdelete b.txt')
	child.lua(K.rm_code('f') .. '; ' .. K.rm_code('b'))
	child.settle()
	child.messages()
	local ok, err = child.step('<M-;><M-r>')
	eq({ ok, err }, { true, nil })
	no_eq(K.warnings(K.messages(child)), {})
	eq(child.slots(), '⦉d⦊ [a] ⟦-⟧')
	eq(K.notes_for(child, { 'a' }), 'dtm{a-swap>f a>b} dsm{}')
end

T["T68 [char] an unknown hash in a map doesn't make a restore throw"] = function()
	child.steps({ ':e a', ':e b' })
	-- A hash that no buffer or path has.
	K.set_note(child, 'dtm', 'b', '0123456789abcdef', true)
	child.messages()
	local ok, err = child.step('<M-;><M-r>')
	eq({ ok, err }, { true, nil })
	eq(K.hook_failures(K.messages(child)), {})
end

return T
