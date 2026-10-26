-- The primary keys: <M-;><M-x> toggle_primary (A9) and <M-;><M-c> set_primary (A10).
-- IDs are the spec's (what-is-cavediver.md, section 7).
local Helpers = dofile('tests/helpers.lua')
local eq, no_eq = Helpers.eq, Helpers.expect.no_equality
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = child.stop,
	},
})

T['T59 [char] toggle_primary: empty queue gives [a]on, again [a]off, on another buffer [a]on with the queue unchanged'] = function()
	child.steps({ ':e a' })
	eq(child.primary(), '[]off')
	child.steps({ '<M-;><M-x>' })
	eq(child.primary(), '[a]on')
	child.steps({ '<M-;><M-x>' })
	eq(child.primary(), '[a]off')
	child.steps({ ':e b', '<M-;><M-x>' })
	eq(child.primary(), '[a]on')
end

T['T60 [char] set_primary: empty queue gives [a]on; on b [b,a]on; on b again [b,a]off; on a [a,b]on'] = function()
	child.steps({ ':e a', '<M-;><M-c>' })
	eq(child.primary(), '[a]on')
	child.steps({ ':e b', '<M-;><M-c>' })
	eq(child.primary(), '[b,a]on')
	child.steps({ '<M-;><M-c>' })
	eq(child.primary(), '[b,a]off')
	child.steps({ ':e a', '<M-;><M-c>' })
	eq(child.primary(), '[a,b]on')
end

T['T156 [char] the toggle_primary keymap description no longer reads "Toggle current buffer as primary"'] = function()
	local desc = child.lua([[return vim.fn.maparg('<M-;><M-x>', 'n', false, true).desc]])
	no_eq(desc, nil)
	no_eq(desc, 'Toggle current buffer as primary')
end


T['T451 [char] (A9, A10) the primary keys run no redraw!'] = function()
	child.steps({ ':e a', ':e b' })
	child.lua([[
		_G.CDV_CMDS = {}
		local real = vim.cmd
		_G.CDV_REAL_CMD = real
		-- every form: a string or a table, and vim.cmd.redraw({ bang = true }), recorded as it would be typed
		vim.cmd = setmetatable({}, {
			__call = function(_, c) table.insert(_G.CDV_CMDS, type(c) == 'string' and c or vim.inspect(c)); return real(c) end,
			__index = function(_, name)
				return function(arg, ...)
					table.insert(_G.CDV_CMDS, name .. ((type(arg) == 'table' and arg.bang) and '!' or '') .. ' ' .. vim.inspect(arg))
					return real[name](arg, ...)
				end
			end,
		})
	]])
	child.steps({ '<M-;><M-x>', '<M-;><M-x>', '<M-;><M-c>' })
	child.settle(100)
	local cmds = child.lua('vim.cmd = _G.CDV_REAL_CMD; return _G.CDV_CMDS')
	local bang, status, tabline = false, false, false
	for _, c in ipairs(cmds) do
		if c:find('redraw!', 1, true) then bang = true end
		if c:find('redrawstatus', 1, true) then status = true end
		if c:find('redrawtabline', 1, true) then tabline = true end
	end
	eq({ bang = bang, status = status, tabline = tabline }, { bang = false, status = true, tabline = true })
end

return T
