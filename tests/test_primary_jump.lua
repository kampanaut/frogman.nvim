-- <M-;><M-f>, jump_to_primary (A8). IDs are the spec's (what-is-frogman.md, section 7).
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

-- Run the same setup twice, once with each key, and return what each left.
local function both(setup, key_a, key_b, presses)
	local out = {}
	for i, key in ipairs({ key_a, key_b }) do
		child.setup()
		child.steps(setup)
		child.messages()
		out[i] = {}
		for p = 1, presses or 1 do
			child.steps({ key })
			out[i][p] = K.state(child)
		end
	end
	return out[1], out[2]
end

T['T50 [char] {c=e s=d t=b p=[x]on}, jump shows x, {c=x s=d t=e}, dtm{e-swap→b}'] = function()
	child.steps({ ':e x', '<M-;><M-c>', ':e d', ':e b', '<M-f>', ':e e' })
	eq(child.slots(), '⦉b⦊ [e] ⟦d⟧')
	eq(child.primary(), '[x]on')
	child.steps({ '<M-;><M-f>' })
	eq(child.shown(), 'x')
	eq(child.slots(), '⦉e⦊ [x] ⟦d⟧')
	eq(K.note(child, 'dtm', 'e-swap'), 'b')
end

T["T51 [char] when the primary is the ternary, the result equals <M-S-f>'s"] = function()
	local setup = { ':e a', ':e b', '<M-;><M-c>', ':e c' }
	child.steps(setup)
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	eq(child.primary(), '[b]on')
	local jump, swap = both(setup, '<M-;><M-f>', '<M-S-f>')
	eq(jump, swap)
	eq(jump[1].slots, '⦉c⦊ [b] ⟦-⟧')
end

T['T52 [char] on the primary already: "Already in primary buffer, no displacement performed." and no change'] = function()
	child.steps({ ':e a', ':e b', '<M-;><M-c>' })
	local before = { child.slots(), child.notes(), child.shown(), child.primary() }
	eq(before[1], '⦉a⦊ [b] ⟦-⟧')
	child.messages()
	child.steps({ '<M-;><M-f>' })
	eq(K.has(K.messages(child), 'Already in primary buffer, no displacement performed.'), true)
	eq({ child.slots(), child.notes(), child.shown(), child.primary() }, before)
end

T['T53 [char] with an empty queue it acts as <M-f>'] = function()
	local setup = { ':e a', ':e b', ':e c' }
	local jump, swap = both(setup, '<M-;><M-f>', '<M-f>', 2)
	eq(jump, swap)
	-- Graduation, then the swap.
	eq(jump[1].slots, '⦉-⦊ [c] ⟦b⟧')
	eq(jump[2].slots, '⦉-⦊ [b] ⟦c⟧')
	eq(jump[2].primary, '[]off')
end

T['T54 [char] with a disabled primary it acts as <M-f>'] = function()
	-- x is the primary, switched off, and in no slot.
	local setup = { ':e x', '<M-;><M-x>', '<M-;><M-x>', ':e a', ':e b', ':e c' }
	child.steps(setup)
	eq(child.primary(), '[x]off')
	local jump, swap = both(setup, '<M-;><M-f>', '<M-f>', 2)
	eq(jump, swap)
	eq(jump[1].slots, '⦉-⦊ [c] ⟦b⟧')
	eq(jump[2].slots, '⦉-⦊ [b] ⟦c⟧')
end

T['T55 [char] while cycling away from the start, it returns to the start, keeps navigation cycling, and changes no slot'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-n>' })
	no_eq(child.shown(), 'c')
	eq(K.nav(child), 'cycling')
	local slots, notes = child.slots(), child.notes()
	eq(slots, '⦉b⦊ [c] ⟦-⟧')
	child.steps({ '<M-;><M-f>' })
	eq(child.shown(), 'c')
	eq(K.nav(child), 'cycling')
	eq(child.slots(), slots)
	eq(child.notes(), notes)
end

T['T56 [char] with a closed primary, the jump reopens it'] = function()
	-- The ternary b stays open; the closed primary stays in the queue (I4).
	child.steps({ ':e a', '<M-;><M-c>', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	child.cmd('bdelete a.txt')
	child.settle()
	child.steps({ '<M-;><M-f>' })
	eq(child.shown(), 'a')
	eq(child.slots(), '⦉c⦊ [a] ⟦-⟧')
	eq(child.primary(), '[a]on')
	eq(vim.tbl_contains(vim.split(child.closed(), ','), 'a'), false)
end

-- The primary a closed and kept in the queue (I4).
local function closed_primary()
	child.steps({ ':e a', '<M-;><M-c>', ':e b', ':e c', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦-⟧')
	child.cmd('bdelete c.txt')
	child.settle()
	child.cmd('bdelete a.txt')
	child.settle()
	eq(child.primary(), '[a]on')
	child.messages()
end

T['T57 [char] with the primary file deleted on disk, a cleanup pass keeps it in the queue, and the jump says so'] = function()
	closed_primary()
	child.lua(K.rm_code('a'))
	child.lua('require("frogman.domains.history").cleanup_system()')
	child.settle()
	eq(child.primary(), '[a]on')
	local ok, err = child.step('<M-;><M-f>')
	eq({ ok, err }, { true, nil })
	eq(K.has(K.messages(child), "isn't on disk right now"), true)
	eq({ slots = child.slots(), primary = child.primary() }, { slots = '⦉c⦊ [d] ⟦-⟧', primary = '[a]on' })
end

T['T58 [char] with the primary file deleted on disk, it says so and keeps the pointer'] = function()
	closed_primary()
	local ok, err = K.press_after(child, K.rm_code('a'), '<M-;><M-f>')
	eq({ ok, err }, { true, nil })
	local msgs = K.messages(child)
	eq(K.hook_failures(msgs), {})
	no_eq(K.warnings(msgs), {})
	eq(child.primary(), '[a]on')
end

T['T153 [char] Q6 on the fallback: primary disabled, {c=A s=S t=T}, dtm[T] = S; <M-;><M-f> rewrites dtm[T] to A before the swap'] = function()
	-- x is the primary, switched off; then T150's first seven keys give {c=c s=a t=b}, dtm[b] = a.
	child.steps({ ':e x', '<M-;><M-x>', '<M-;><M-x>' })
	eq(child.primary(), '[x]off')
	child.steps({ ':e a', ':e b', ':e c', ':e b', '<M-f>', ':e a', '<M-f>' })
	eq(child.slots(), '⦉b⦊ [c] ⟦a⟧')
	eq(K.note(child, 'dtm', 'b'), 'a')
	child.steps({ '<M-;><M-f>' })
	eq(child.slots(), '⦉b⦊ [a] ⟦c⟧')
	eq(K.note(child, 'dtm', 'b'), 'c')
end

return T
