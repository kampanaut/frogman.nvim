-- Plain navigation (A1). IDs are the spec's (what-is-frogman.md, section 7).
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

T['T28 [char] {c=a}, :e b gives {c=b t=a} with no map entries'] = function()
	child.steps({ ':e a' })
	eq(child.slots(), '⦉-⦊ [a] ⟦-⟧')
	child.steps({ ':e b' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	eq(child.notes(), 'dtm{} dsm{}')
end

T['T29 [char] {c=b t=a}, :e c gives {c=c t=b} with dtm{b>a}'] = function()
	child.steps({ ':e a', ':e b' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	child.steps({ ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	eq(child.notes(), 'dtm{b>a} dsm{}')
end

T['T30 [char] :e onto the secondary swaps current and secondary and writes the swap notes <M-f> writes (D8)'] = function()
	-- <M-f> graduates b; then :e d gives ⦉c⦊ [d] ⟦b⟧, where dtm[c] is unset (≠ b)
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	eq(X.maps(child).dtm.c, nil)
	local before = child.notes()
	child.steps({ ':e b' })
	eq(child.slots(), '⦉c⦊ [b] ⟦d⟧')
	-- d is left by a swap onto the secondary, so it gets swap notes for its secondary and ternary.
	eq(before, 'dtm{b>a} dsm{b>a}')
	eq(child.notes(), 'dtm{b>a d-swap>c} dsm{b>a d-swap>b}')
end

T['T31 [char] :e onto the ternary swaps current and ternary and does not write dtm[current]'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	eq(child.notes(), 'dtm{b>a} dsm{}')
	child.steps({ ':e b' })
	eq(child.slots(), '⦉c⦊ [b] ⟦-⟧')
	eq(child.notes(), 'dtm{b>a} dsm{}')
end

T['T32 [char] a plain navigation that writes dtm[A] also deletes dtm[A-swap]'] = function()
	-- two <M-S-f> leave c with a swap note: ⦉b⦊ [c], dtm[c-swap] = b
	child.steps({ ':e a', ':e b', ':e c', '<M-S-f>', '<M-S-f>' })
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	eq(X.maps(child).dtm['c-swap'], 'b')
	child.steps({ ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦-⟧')
	local dtm = X.maps(child).dtm
	eq(dtm.c, 'b')
	eq(dtm['c-swap'], nil)
end

T['T33 [char] with dtm[X] = A and the ternary T ≠ X, :e X from A rewrites dtm[X] := T with the "pre-jump ternary" warning'] = function()
	-- :e c from b writes dtm[b] = a; back at a (ternary c), b's note names a,
	-- the buffer :e b is about to leave.
	child.steps({ ':e a', ':e b', ':e c', ':e a' })
	eq(child.slots(), '⦉c⦊ [a] ⟦-⟧')
	eq(X.maps(child).dtm.b, 'a')
	child.messages()
	child.steps({ ':e b' })
	eq(child.slots(), '⦉a⦊ [b] ⟦-⟧')
	eq(X.maps(child).dtm.b, 'c')
	local warns = X.messages_with(child, 'switching with the pre-jump ternary.')
	eq(#warns, 1)
	eq(warns[1].level, vim.log.levels.WARN)
end

T['T34 [char] navigation with secondary equal to ternary reports "Duplicates detected in current triquetra"'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':e d' })
	-- s = t can't be reached by keys here; set it directly, as run s18 does
	X.set(child, { secondary = 'c', ternary = 'c', dtm = {}, dsm = {} })
	eq(child.slots(), '⦉c⦊ [d] ⟦c⟧')
	child.messages()
	child.steps({ ':e a' })
	-- the flight recorder's notice of its dump is a message of its own (A26)
	local errs = vim.tbl_filter(function(m)
		return not m.msg:find("frogman: something that shouldn't happen did", 1, true)
	end, X.messages_with(child, 'Duplicates detected in current triquetra'))
	eq(#errs, 1)
	eq(errs[1].level, vim.log.levels.ERROR)
	-- the hook stops before any slot moves (A1)
	eq(child.shown(), 'a')
	eq(child.slots(), '⦉c⦊ [d] ⟦c⟧')
end

T['T35 [char] entering an untracked buffer the triquetra is kept for (acwrite) leaves the slots alone'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	local notes = child.notes()
	child.lua([[
		local buf = vim.api.nvim_create_buf(true, false)
		vim.bo[buf].buftype = 'acwrite'
		vim.api.nvim_buf_set_name(buf, 'acw://scratch')
		vim.api.nvim_create_autocmd('BufWriteCmd', { buffer = buf, callback = function() end })
		vim.api.nvim_set_current_buf(buf)
	]])
	child.settle(200)
	eq(child.lua('return vim.bo.buftype'), 'acwrite')
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	eq(child.notes(), notes)
end

T['T151 [char] Q6 on plain navigation: :e onto the secondary rewrites the ternary\'s note, and the restore then works'] = function()
	child.steps({ ':e a', ':e b', ':e c', ':e b', '<M-f>', ':e a', '<M-f>' })
	eq(child.slots(), '⦉b⦊ [c] ⟦a⟧')
	eq(X.maps(child).dtm.b, 'a')
	-- :e a reaches the secondary by plain navigation
	child.steps({ ':e a' })
	eq(child.slots(), '⦉b⦊ [a] ⟦c⟧')
	eq(X.maps(child).dtm.b, 'c')
	child.steps({ '<M-S-f>' })
	local ok, err = child.step('<M-;><M-r>')
	eq({ ok, err }, { true, nil })
	eq(child.slots(), '⦉c⦊ [b] ⟦a⟧')
end

-- From ⦉c⦊ [d] ⟦b⟧, both routes onto the secondary write the same notes.
local function round_setup()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
end

local function check_d_notes()
	eq(child.slots(), '⦉c⦊ [b] ⟦d⟧')
	local maps = X.maps(child)
	eq({ dsm_d_swap = maps.dsm['d-swap'], dtm_d_swap = maps.dtm['d-swap'], dsm_d = maps.dsm.d },
		{ dsm_d_swap = 'b', dtm_d_swap = 'c' })
end

T['T191 [char] (D8) plain navigation onto the secondary writes the swap notes dsm{d-swap>b} dtm{d-swap>c}, no dsm[d]'] = function()
	round_setup()
	child.steps({ ':e b' })
	check_d_notes()
end

T['T191 [char] (D8) <M-f> onto the secondary writes the swap notes dsm{d-swap>b} dtm{d-swap>c}, no dsm[d]'] = function()
	round_setup()
	child.steps({ '<M-f>' })
	check_d_notes()
end

return T
