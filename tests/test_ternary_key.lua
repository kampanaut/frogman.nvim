-- <M-S-f>, toggle_ternary (A7). IDs are the spec's (what-is-frogman.md, section 7).
local Helpers = dofile('tests/helpers.lua')
local K = dofile('tests/helpers_keys.lua')
local eq = Helpers.eq
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = child.stop,
	},
})

T['T46 [char] {c=d s=b t=c}, <M-S-f> shows c, {c=c s=b t=d}, dtm{d-swap→c}'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	child.steps({ '<M-S-f>' })
	eq(child.shown(), 'c')
	eq(child.slots(), '⦉d⦊ [c] ⟦b⟧')
	eq(K.note(child, 'dtm', 'd-swap'), 'c')
end

T['T47 [char] with no ternary, it warns "No ternary buffer to swap with." and nothing changes'] = function()
	child.steps({ ':e a', ':e b', '<M-f>' })
	local before = { child.slots(), child.notes(), child.shown() }
	eq(before[1], '⦉-⦊ [b] ⟦a⟧')
	child.messages()
	child.steps({ '<M-S-f>' })
	eq(K.has(K.messages(child), 'No ternary buffer to swap with.'), true)
	eq({ child.slots(), child.notes(), child.shown() }, before)
end

T['T48 [char] a ternary closed with <M-.> is reopened by <M-S-f> and taken off the closed stack'] = function()
	-- <M-.> on c lands on b (ordered[2]); c stays in the ternary, closed.
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	eq(child.slots(), '⦉c⦊ [b] ⟦-⟧')
	eq(child.closed(), 'c')
	child.steps({ '<M-S-f>' })
	eq(child.shown(), 'c')
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	eq(child.closed(), '')
end

T["T49 [char] the desk's sequence (:e, :e, <M-n>, :bdelete, <M-S-f>, <M-S-f>) throws nothing and leaves no duplicate slot"] = function()
	-- The desk's 1.txt and 2.txt are a and b here.
	child.steps({ ':e a', ':e b', '<M-n>' })
	child.cmd('bdelete')
	child.settle()
	child.messages()
	for _ = 1, 2 do
		local ok, err = child.step('<M-S-f>')
		eq({ ok, err }, { true, nil })
		eq(K.hook_failures(K.messages(child)), {})
		eq(K.duplicate(child), false)
	end
end

-- T49's old route, planted: the slot cleared right after the reopen, as the cleanup cleared the ternary
-- once before the swap's rename of it ran (the nil rename).
T["T896 [char] (A7, DESK.md:2390) a ternary cleared while <M-S-f> reopens it throws nothing and leaves no duplicate slot"] = function()
	child.steps({ ':e a', ':e b', '<M-n>' })
	child.cmd('bdelete')
	child.settle()
	child.messages()
	child.lua([[
		local H = require('frogman.domains.history')
		local reopen = H.reopen_handle
		H.reopen_handle = function(...)
			local bufnr, reason = reopen(...)
			local t = require('frogman.domains.window').data.crux[vim.api.nvim_get_current_win()]
			if t then t:set('ternary_slot', nil) end
			return bufnr, reason
		end
	]])
	for _ = 1, 2 do
		local ok, err = child.step('<M-S-f>')
		eq({ ok, err }, { true, nil })
		eq(K.hook_failures(K.messages(child)), {})
		eq(K.duplicate(child), false)
	end
end

return T
