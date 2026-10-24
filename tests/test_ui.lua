-- UI (M12): the winbar, the bufferline callbacks and the keymap descriptions.
-- IDs are the spec's (what-is-cavediver.md, section 7).
local Helpers = dofile('tests/helpers.lua')
local S2 = dofile('tests/helpers_s2.lua')
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

T['T119 [char] get_buffer_relationships does not throw when current = primary, or it is gone (Q16)'] = function()
	child.steps({ ':e a', '<M-;><M-c>' })
	child.settle(300)
	local got = child.lua([[
		local f = require('cavediver').bufferline.get_buffer_relationships
		if f == nil then return { true } end
		local ok, err = pcall(f, vim.api.nvim_get_current_buf())
		return { ok, (not ok) and tostring(err) or nil } -- on success, err is what it returns
	]])
	eq(got, { true })
end

T['T120 [char] get_smart_basename is a function'] = function()
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

T['T123 [char] hide_bufferline() and show_bufferline() do not throw'] = function()
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

T['T170 [char] the engine has no machine named window (D25)'] = function()
	local got = child.lua('local l = require("cavediver.engine"):list(); table.sort(l); return l')
	eq(got, { 'history', 'navigation', 'storage', 'ui_bufferline', 'ui_indicators', 'ui_loop', 'ui_winbar' })
end

T['T169 [char] the mapped keys have their own descriptions (D3)'] = function()
	local got = child.lua([[
		local keymaps = require('cavediver.configs').keymaps
		local desc = {}
		for action, lhs in pairs(keymaps) do
			if type(lhs) == 'string' then -- keymaps.views holds the keys inside cavediver's views, mapped per buffer
				desc[action] = vim.fn.maparg(lhs, 'n', false, true).desc
			end
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
T['T168 [char] the pick letter takes its colour from the config (D2)'] = function()
	child.steps({ ':e a', ':e b' })
	child.settle(300)
	eq(child.lua('return require("cavediver.configs").colors.cokeline.is_picking_focus'), '#4385BE')
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


-- The index the bufferline draws for a buffer, through cavediver's own components.
local INDEX = [==[
package.loaded['cokeline.hlgroups'] = package.loaded['cokeline.hlgroups'] or { get_hl_attr = function() return '#000000' end }
local comps = require('cavediver').bufferline.cokeline.create_buffer_components()
return comps[4].text({ number = ..., index = 1, is_focused = true }) -- the index, fourth in the order they're drawn
]==]

T['T446 [char] (M12) the toggles\' commands, with no keymap'] = function()
	child.steps({ ':e a', ':e b' })
	child.settle(300)
	local b = bufnr('b.txt')
	local wb = {}
	child.cmd('CavediverWinbar off')
	wb.off = winbar()
	child.cmd('CavediverWinbar on')
	wb.on = winbar() ~= ''
	child.cmd('CavediverWinbar')
	wb.toggled = winbar()
	child.cmd('CavediverWinbar toggle')
	wb.back = winbar() ~= ''
	local marks = { on = child.lua(INDEX, { b }) }
	child.cmd('CavediverIndicators off')
	child.settle(300)
	marks.off = child.lua(INDEX, { b })
	child.cmd('CavediverIndicators on')
	child.settle(300)
	marks.again = child.lua(INDEX, { b })
	local shown = {}
	child.cmd('CavediverBufferline off')
	shown.off = not not child.lua('return require("cavediver").bufferline.bufnr_is_displayed(...)', { b })
	child.cmd('CavediverBufferline on')
	shown.on = not not child.lua('return require("cavediver").bufferline.bufnr_is_displayed(...)', { b })
	local keyed = child.lua([[
		local out = {}
		for name, _ in pairs(require('cavediver.configs').keymaps) do
			if name:find('winbar') or name:find('indicator') or name:find('bufferline') then table.insert(out, name) end
		end
		return out
	]])
	eq({ wb = wb, marks = marks, shown = shown, keyed = keyed }, {
		wb = { off = '', on = true, toggled = '', back = true },
		marks = { on = '[' .. b .. ']  ', off = ' ', again = '[' .. b .. ']  ' },
		shown = { off = false, on = true },
		keyed = {},
	})
end

T['T447 [char] (M12) with winbar.own off, cavediver writes no winbar, and offers its segment'] = function()
	child.lua('require("cavediver").setup({ winbar = { own = false } })')
	child.steps({ ':e a', ':e b' })
	child.lua('vim.wo.winbar = "MINE"')
	child.settle(300)
	local refreshed = child.lua('return vim.wo.winbar')
	local cwd = S2.cwd(child)
	eq(S2.save(child, cwd), { true })
	eq(S2.load(child, cwd), { true })
	child.settle(300)
	local loaded = child.lua('return vim.wo.winbar')
	local segment = child.lua('return require("cavediver").winbar_segment()')
	local b = bufnr('b.txt')
	eq({ refreshed = refreshed, loaded = loaded, current = segment:find('[' .. b .. ']', 1, true) ~= nil,
		name = segment:find('b.txt', 1, true) ~= nil, rule = segment:find('──────', 1, true) ~= nil },
		{ refreshed = 'MINE', loaded = 'MINE', current = true, name = true, rule = false })
end

T['T448 [char] (M12) the winbar\'s skip list is configurable, and replaces the default one'] = function()
	child.steps({ ':e a', ':e b' })
	child.lua('vim.bo.filetype = "skipme"')
	local default = winbar() ~= ''
	child.lua('require("cavediver").setup({ winbar = { skip_filetypes = { "skipme" } } })')
	child.lua('vim.wo.winbar = ""')
	local skipped = winbar()
	child.lua('vim.bo.filetype = "neo-tree"')
	local replaced = winbar() ~= ''
	eq({ default = default, skipped = skipped, replaced = replaced }, { default = true, skipped = '', replaced = true })
end

T['T450 [char] (M12, P26) marked buffers come from the provider'] = function()
	child.lua([[
		local root = _G.CDV_TEST.root
		require('cavediver').setup({ marks_provider = function() return { root .. '/b.txt' } end })
	]])
	child.steps({ ':e a', ':e b', ':e c' })
	child.settle(300)
	local bl = 'local bl = require("cavediver").bufferline; local b = ...; return { bl.is_harpooned(b), bl.get_harpoon_index(b) }'
	local marked = { a = child.lua(bl, { bufnr('a.txt') })[1], b = child.lua(bl, { bufnr('b.txt') }), c = child.lua(bl, { bufnr('c.txt') })[1] }
	child.lua([[
		package.loaded['harpoon'] = { list = function() return { display = function() return { 'b.txt' } end } end }
		require('cavediver').setup({ marks_provider = false })
	]])
	child.steps({ ':e a' })
	child.settle(300)
	local off = child.lua(bl, { bufnr('b.txt') })[1]
	eq({ marked = marked, off = off }, { marked = { a = false, b = { true, 1 }, c = false }, off = false })
end


-- The filename the bufferline draws for a buffer, seventh in the components' order.
local FILENAME = [==[
package.loaded['cokeline.hlgroups'] = package.loaded['cokeline.hlgroups'] or { get_hl_attr = function() return '#000000' end }
local comps = require('cavediver').bufferline.cokeline.create_buffer_components()
return comps[7].text({ number = ..., filename = 'b.txt', index = 1, is_focused = true })
]==]

T['T456 [char] (M12) the indicators by kind'] = function()
	child.lua([[
		local root = _G.CDV_TEST.root
		require('cavediver').setup({ marks_provider = function() return { root .. '/b.txt' } end })
	]])
	child.steps({ ':e a', ':e b' })
	child.settle(300)
	local b = bufnr('b.txt')
	local function drawn()
		child.settle(300)
		return { child.lua(INDEX, { b }), child.lua(FILENAME, { b }) }
	end
	local got = { on = drawn() }
	child.cmd('CavediverIndicators roles off')
	got.roles_off = drawn()
	child.cmd('CavediverIndicators roles on')
	child.cmd('CavediverIndicators harpoon off')
	got.harpoon_off = drawn()
	child.cmd('CavediverIndicators off')
	got.off = drawn()
	child.cmd('CavediverIndicators on')
	got.again = drawn()
	eq(got, {
		on = { '[' .. b .. '] 󰛢  ', 'b.txt ⥤ {1}' },
		roles_off = { '󰛢  ', 'b.txt ⥤ {1}' },
		harpoon_off = { '[' .. b .. ']  ', 'b.txt' },
		off = { ' ', 'b.txt' },
		again = { '[' .. b .. '] 󰛢  ', 'b.txt ⥤ {1}' },
	})
end

T['T457 [char] (M12) a window with no current slot shows its visit alone'] = function()
	child.steps({ ':e a' })
	child.cmd('help')
	child.settle(300)
	local hw, hb = child.lua('return vim.api.nvim_get_current_win()'), child.lua('return vim.api.nvim_get_current_buf()')
	local focused = child.lua('return vim.wo[...].winbar', { hw })
	child.cmd('wincmd p')
	child.settle(300)
	local unfocused = child.lua('return vim.wo[...].winbar', { hw })
	-- a split with a winbar of its own keeps it
	child.cmd('split | terminal')
	child.settle(300)
	local tw = child.lua('return vim.api.nvim_get_current_win()')
	child.lua('vim.wo[...].winbar = "MINE"', { tw })
	child.settle(300)
	local mine = child.lua('return vim.wo[...].winbar', { tw })
	-- the help split stops qualifying: a skip-list filetype; its bar goes
	child.lua('vim.bo[...].filetype = "neo-tree"', { hb })
	child.settle(300)
	local gone = child.lua('return vim.wo[...].winbar', { hw })
	local piece = '[' .. hb .. ' help]'
	local left, right = focused:match('^(.-)' .. vim.pesc(piece) .. '(.*)$')
	local function rules(s) return select(2, (s or ''):gsub('─', '')) end
	eq({ piece = left ~= nil, group = focused:find('%#WinbarVisit#', 1, true) ~= nil,
		centred = left ~= nil and math.abs(rules(left) - rules(right)) <= 1,
		nc = unfocused:find('%#WinbarVisitNC#', 1, true) ~= nil and unfocused:find(piece, 1, true) ~= nil, mine = mine, gone = gone },
		{ piece = true, group = true, centred = true, nc = true, mine = 'MINE', gone = '' })
	-- not owned: none drawn
	child.setup()
	child.lua('require("cavediver").setup({ winbar = { own = false } })')
	child.steps({ ':e a' })
	child.cmd('help')
	child.settle(300)
	eq(child.lua('return vim.wo.winbar'), '')
end

return T
