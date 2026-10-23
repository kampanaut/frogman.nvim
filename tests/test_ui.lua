-- UI (M12): the winbar, the bufferline callbacks and the keymap descriptions.
-- IDs are the spec's (what-is-cavediver.md, section 7).
local Helpers = dofile('tests/helpers.lua')
local eq = Helpers.eq
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = child.stop,
	},
})

local function bufnr(file) return child.lua('return vim.fn.bufnr(_G.CDV_TEST.root .. "/" .. ...)', { file }) end

-- The current window's winbar, after the UI has caught up.
local function winbar()
	child.settle(300)
	return child.lua('return vim.wo.winbar')
end

-- Whether `pieces` appear in `s` in that order, each taken literally.
local function in_order(s, pieces)
	local from = 1
	for _, p in ipairs(pieces) do
		local i, j = s:find(p, from, true)
		if not i then return false, p end
		from = j + 1
	end
	return true
end

-- The winbar's ternary part: everything before the current slot's number.
local function ternary_part(s)
	return s:sub(1, (s:find('%#WinbarBufnrCurrent#', 1, true) or 1) - 1)
end

T['T115 [char] the winbar holds the slots in order, with their highlights'] = function()
	child.steps({ ':e c', ':e d', '<M-f>', ':e e' })
	eq(child.slots(), '⦉d⦊ [e] ⟦c⟧')
	local d, e, c = bufnr('d.txt'), bufnr('e.txt'), bufnr('c.txt')
	eq({ in_order(winbar(), {
		'%#WinbarBufnrTernary#⦉' .. d .. '⦊ ',
		'%#WinbarBufnrCurrent#[' .. e .. '] ',
		'%#WinbarFilenameCurrent#e.txt',
		'%#WinbarBufnrSecondary#⟦' .. c .. '⟧ ',
		'%#WinbarFilenameSecondary#c.txt',
	}) }, { true })
end

-- <M-.> on c lands on b and leaves c in the ternary as a closed hash (T80).
T['T116 [char] a closed ternary shows as ⦉ … name ⦊ with no buffer number'] = function()
	child.steps({ ':e a', ':e b', ':e c', '<M-.>' })
	eq(child.slots(), '⦉c⦊ [b] ⟦-⟧')
	eq(child.closed(), 'c')
	local part = ternary_part(winbar())
	local inner = part:match('⦉(.-)⦊')
	eq(inner ~= nil, true)
	eq(inner:find('c.txt', 1, true) ~= nil, true)
	eq(inner:find('%d'), nil)
end

T['T117 [char] the current buffer as the primary shows as ⦉N⦊ in WinbarBufnrPrimary'] = function()
	child.steps({ ':e a', '<M-;><M-c>' })
	eq(child.primary(), '[a]on')
	eq(in_order(winbar(), { '%#WinbarBufnrPrimary#⦉' .. bufnr('a.txt') .. '⦊ ' }), true)
end

T['T118 [char] a slot closed with :bdelete shows its basename, not its full path'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('bdelete b.txt')
	child.settle()
	eq(child.slots(), '⦉b⦊ [c] ⟦-⟧')
	local part = ternary_part(winbar())
	eq(part:find('# b.txt ⦊', 1, true) ~= nil, true)
end

T['T119 [target] get_buffer_relationships does not throw when current = primary, or it is gone (Q16)'] = function()
	child.steps({ ':e a', '<M-;><M-c>' })
	child.settle(300)
	local got = child.lua([[
		local f = require('cavediver').bufferline.get_buffer_relationships
		if f == nil then return { true } end
		local ok, err = pcall(f, vim.api.nvim_get_current_buf())
		return { ok, err and tostring(err) or nil }
	]])
	eq(got, { true })
end

T['T120 [target] get_smart_basename is a function'] = function()
	eq(child.lua('return type(require("cavediver").get_smart_basename)'), 'function')
end

T['T121 [char] compare_buffers ranks by recency; bufnr_is_displayed is true for tracked, false for help'] = function()
	child.steps({ ':e a', ':e b' })
	child.settle(300)
	local a, b = bufnr('a.txt'), bufnr('b.txt')
	local got = child.lua([[
		local a, b = ...
		local bl = require('cavediver').bufferline
		return { bl.compare_buffers(b, a), bl.compare_buffers(a, b) }
	]], { a, b })
	eq(got, { true, false })
	child.cmd('help')
	child.settle(300)
	got = child.lua([[
		local a = ...
		local bl = require('cavediver').bufferline
		return { not not bl.bufnr_is_displayed(a), not not bl.bufnr_is_displayed(vim.api.nvim_get_current_buf()) }
	]], { a })
	eq(got, { true, false })
end

T['T122 [char] with 40 tracked buffers, bufnr_is_displayed is true for all 40 (Q5)'] = function()
	local got = child.lua([[
		local root = _G.CDV_TEST.root
		for i = 1, 40 do
			local p = string.format('%s/n%02d.txt', root, i)
			vim.fn.writefile({ 'x' }, p)
			vim.cmd('edit ' .. vim.fn.fnameescape(p))
			vim.wait(10) -- each visit settles, as when they're opened one by one
		end
		vim.wait(300)
		local bl = require('cavediver').bufferline
		local shown = 0
		for i = 1, 40 do
			if bl.bufnr_is_displayed(vim.fn.bufnr(string.format('%s/n%02d.txt', root, i))) then shown = shown + 1 end
		end
		return { #require('cavediver.domains.history').data.ordered.crux, shown }
	]])
	eq(got, { 40, 40 })
end

T['T123 [target] hide_bufferline() and show_bufferline() do not throw'] = function()
	local got = child.lua([[
		local ui = require('cavediver').ui
		local ok1, err1 = pcall(ui.hide_bufferline)
		local ok2, err2 = pcall(ui.show_bufferline)
		return { ok1, ok2, err1 and tostring(err1) or nil, err2 and tostring(err2) or nil }
	]])
	eq(got, { true, true })
end

T['T124 [char] while cycling, get_theme_bg_color(true) is the detached focused colour'] = function()
	child.steps({ ':e a', ':e b', '<M-m>' })
	child.settle(300)
	local got = child.lua([[
		local cfg = require('cavediver.configs')
		return {
			require('cavediver').get_navigation_state(),
			require('cavediver').bufferline.get_theme_bg_color(true) == cfg.colors.cokeline.bg.detached.focused,
		}
	]])
	eq(got, { 'cycling', true })
end

T['T170 [target] the engine has no machine named window (D25)'] = function()
	local got = child.lua('local l = require("cavediver.engine"):list(); table.sort(l); return l')
	eq(got, { 'history', 'navigation', 'storage', 'ui_bufferline', 'ui_indicators', 'ui_loop' })
end

T['T169 [target] the mapped keys have their own descriptions (D3)'] = function()
	local got = child.lua([[
		local keymaps = require('cavediver.configs').keymaps
		local desc = {}
		for action, lhs in pairs(keymaps) do
			desc[action] = vim.fn.maparg(lhs, 'n', false, true).desc
		end
		local seen, shared = {}, {}
		for action, d in pairs(desc) do
			if seen[d] then table.insert(shared, d) end
			seen[d] = true
		end
		return {
			toggle_primary = desc.toggle_primary,
			close_buffer = desc.close_buffer,
			open_primary_buffer_history = desc.open_primary_buffer_history,
			shared = shared,
		}
	]])
	eq(got, {
		toggle_primary = 'Switch the primary on or off',
		close_buffer = 'Close the current buffer',
		open_primary_buffer_history = 'Open the primary queue',
		shared = {},
	})
end

-- cokeline is stubbed: the picking state comes from _G.CDV_PICK, and the pick
-- letter's component is the one whose text is the letter while picking.
T['T168 [target] the pick letter takes its colour from the config (D2)'] = function()
	child.steps({ ':e a', ':e b' })
	child.settle(300)
	child.lua([[
		local real = require('cokeline.mappings')
		_G.CDV_PICK = { close = false, focus = false }
		package.loaded['cokeline.mappings'] = setmetatable({
			is_picking_close = function() return _G.CDV_PICK.close end,
			is_picking_focus = function() return _G.CDV_PICK.focus end,
		}, { __index = real })
		package.loaded['cokeline.hlgroups'] = { get_hl_attr = function() return '#000000' end }
	]])
	local function pick_colours(close_col, focus_col)
		return child.lua([[
			local close_col, focus_col = ...
			local colors = require('cavediver.configs').colors
			colors.cokeline.is_picking_close = close_col
			colors.cokeline.is_picking_focus = focus_col
			local comps = require('cavediver').bufferline.cokeline.create_buffer_components()
			local buffer = {
				number = vim.api.nvim_get_current_buf(), pick_letter = 'q', devicon = { icon = 'i' },
				index = 1, is_focused = true,
			}
			local pick
			_G.CDV_PICK.close = true
			for _, c in ipairs(comps) do
				if type(c.text) == 'function' then
					local ok, t = pcall(c.text, buffer)
					if ok and t == 'q ' then pick = c end
				end
			end
			local out = {}
			out.close = pick.fg(buffer)
			_G.CDV_PICK.close, _G.CDV_PICK.focus = false, true
			out.focus = pick.fg(buffer)
			_G.CDV_PICK.focus = false
			return out
		]], { close_col, focus_col })
	end
	eq(pick_colours('#111111', '#222222'), { close = '#111111', focus = '#222222' })
	eq(pick_colours('#333333', '#444444'), { close = '#333333', focus = '#444444' })
end

return T
