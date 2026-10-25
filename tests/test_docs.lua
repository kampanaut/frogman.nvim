-- Doc checks: the settled doc and comment changes (what-is-cavediver.md,
-- section 7, "Doc checks"). Each reads the file and is named by the entry that
-- settled it (D, Q or A). Text is matched, never line numbers. Where the spec
-- gives the new wording, the new text must be there and the old text gone.
local Helpers = dofile('tests/helpers.lua')
local Misc = dofile('tests/helpers_misc.lua')
local eq = Helpers.eq

local T = MiniTest.new_set()

local function read(path) return Misc.read(path) end

-- Whitespace runs collapsed to one space, so wrapped lines still match.
local function flat(s) return (s:gsub('%s+', ' ')) end

-- Comment text: each line's leading comment marks dropped, then flattened.
local function comments(s)
	local out = {}
	for line in (s .. '\n'):gmatch('(.-)\n') do
		table.insert(out, (line:gsub('^%s*%-%-%-?%s?', '')))
	end
	return flat(table.concat(out, ' '))
end

-- The part of `text` from the line holding `heading` up to the next line that
-- starts with `stop` (default: any markdown heading).
local function section(text, heading, stop)
	local i = text:find(heading, 1, true)
	if not i then return '' end
	local rest = text:sub(i + #heading)
	local j = rest:find('\n' .. (stop or '#'), 1, true)
	return heading .. (j and rest:sub(1, j) or rest)
end

-- `key = value` with the comment and trailing comma dropped and spaces trimmed.
local function assignment(line)
	local code = line:gsub('%s*%-%-.*$', '')
	local key, value = code:match('^%s*([%w_]+)%s*=%s*(.-),?%s*$')
	if key and value ~= '' and value ~= '{' then return key .. ' = ' .. value end
end

local has = Misc.has
local README = 'README.md'

-- README --------------------------------------------------------------------

T['D1 [char] README has toggle_primary and set_primary the right way round'] = function()
	local r = read(README)
	eq({ has(r, 'toggle_primary = "<M-;><M-x>"'), has(r, 'set_primary = "<M-;><M-c>"') }, { true, true })
end

T['D2 [char] README\'s defaults block copies configs.lua, missing keys included'] = function()
	local readme = {}
	for _, line in ipairs(vim.fn.readfile(README)) do
		local a = assignment(line)
		if a then readme[a] = true end
	end
	local missing = {}
	local inside = false
	for _, line in ipairs(vim.fn.readfile('lua/cavediver/configs.lua')) do
		if line:find('^local defaults = {') then inside = true
		elseif line:find('^}') then inside = false
		elseif inside then
			local a = assignment(line)
			if a and not readme[a] then table.insert(missing, a) end
		end
	end
	eq(missing, {})
end

T['D2 [char] README\'s cleanup_interval says milliseconds'] = function()
	local found = false
	for _, line in ipairs(vim.fn.readfile(README)) do
		if line:find('cleanup_interval%s*=') and line:find('milliseconds', 1, true) then found = true end
	end
	eq(found, true)
end

T['D5 [char] README says a disabled primary makes <M-;><M-f> act like <M-f>'] = function()
	local r = read(README)
	local says = false
	for _, line in ipairs(vim.fn.readfile(README)) do
		local l = line:lower()
		if l:find('disable', 1, true) and l:gsub('<m%-;><m%-f>', ''):find('<m-f>', 1, true) then says = true end
	end
	eq({ has(r, "won't do anything at all"), says }, { false, true })
end

T['D6 [char] README says a pop-up save keeps the good lines and reports the bad ones'] = function()
	eq(has(read(README), 'nothing is saved'), false)
end

T['D26 [char] README\'s triquetra sentence follows the visiting rule, and "tiquetra" is fixed'] = function()
	local r = flat(read(README))
	local new = 'When a window switches to a non-regular buffer then it will keep the triquetra associated to that '
		.. 'window, and the current slot stays on the file you were on, so `<m-f>` brings you back to it. '
		.. 'The winbar shows it like `main.lua ← [help]`.'
	eq({ has(r, new), has(r, 'it will clean the triquetra'), has(r, 'tiquetra') }, { true, false, false })
end

T['D27 [char] README\'s requirements (D4, D27)'] = function()
	local req = section(read(README), '## Requirements')
	local items = {
		'- neovim 0.12+',
		'- nvim-cokeline',
		"- openssl 3 or 4 (system installed, its libcrypto is used for encrypting the session files. Hashing is done with neovim's built-in `vim.fn.sha256`. When cavediver can't find it, set `libcrypto_path` to its file. Windows is untested: there, set `libcrypto_path` to the DLL, such as `libcrypto-3-x64.dll`)",
		'- harpoon (optional, harpooned buffers are marked in the bufferline)',
		'- telescope.nvim (optional, used for adding files in the primary buffer pop-up)',
		'- a session manager (optional, resession.nvim is used in the examples below)',
	}
	local missing = {}
	for _, item in ipairs(items) do
		if not has(flat(req), item) then table.insert(missing, item) end
	end
	eq(missing, {})
end

T['D27 [char] README\'s lazy.nvim example depends on cokeline, not harpoon, with no comment'] = function()
	local block = section(read(README), '### lazy.nvim')
	eq({
		has(block, 'nvim-cokeline'),
		has(block, 'harpoon'),
		has(block, 'resession.nvim and nvim-cokeline, requires this plugin'),
	}, { true, false, false })
end

T['D27 [char] README\'s cokeline paragraph'] = function()
	local r = flat(read(README))
	local new = 'The cavediver plugin can work without the bufferline, but it reduces the experience a lot. '
		.. 'Cokeline is what lets you visualise the visit history of all your buffers, so that you can know how '
		.. 'you can end up to your current buffer.'
	eq({ has(r, new), has(r, 'visit history of all your browsers') }, { true, false })
end

T['D28 [char] README has "Session manager setup" with resession, native sessions and no manager'] = function()
	local r = read(README)
	local s = section(r, 'Session manager setup', '## ')
	eq({
		has(r, 'Session manager setup'),
		has(s, 'pre_load'),
		has(s, 'TabClosedPre'),
		has(s, 'SessionWritePost'),
		has(s, 'SessionLoadPost'),
		has(s, 'VimLeavePre'),
		has(r, 'save_session(vim.loop.cwd())'),
	}, { true, true, true, true, true, true, false })
end

-- Keymap and annotation text ------------------------------------------------

T['D3 [char] cycle_select\'s annotation copies "Select cycling buffer and attach history"'] = function()
	local c = read('lua/cavediver/configs.lua')
	eq(has(c, '---@field cycle_select string Select cycling buffer and attach history'), true)
end

-- Comments and docstrings ---------------------------------------------------

T['D15 [char] the checkpoint docstring says it is the live triquetra, not a copy'] = function()
	local c = comments(read('lua/cavediver/domains/history/routines.lua'))
	local new = "Mark the window's triquetra as the cycle's checkpoint. The checkpoint is the window's own triquetra, "
		.. "not a copy, so it always names the window's current slot."
	eq({ has(c, new), has(c, 'Stores a deep copy') }, { true, false })
end

T['D16 [char] the <M-.> branch comment says most recent relative to the one deleted'] = function()
	local c = read('lua/cavediver/domains/history/routines.lua')
	eq({
		has(c, '-- Otherwise go to most recent relative to the one deleted (next in list, wraps around)'),
		has(c, '-- Otherwise go to most recent (first in list)'),
	}, { true, false })
end

T['D17 [char] navigation/data.lua says one jump table across all tabs'] = function()
	local c = read('lua/cavediver/domains/navigation/data.lua')
	eq({
		has(c, 'Current window -> previous window mapping, one table across all tabs'),
		has(c, 'Per-tab, current window'),
	}, { true, false })
end

T['D18 [char] the saved window entry annotation has the six fields'] = function()
	local c = read('lua/cavediver/domains/storage/routines.lua')
	local class = section(c, '---@class WindowTriquetraSerialised', '---\n')
	eq({
		class:find('@field %[5%]') ~= nil,
		class:find('@field %[6%]') ~= nil,
		class:find('@field %[3%] string|vim%.NIL') ~= nil,
	}, { true, true, false })
end

T['D21 [char] navigation/states.lua says nothing enters file_picker yet'] = function()
	local line = ''
	for _, l in ipairs(vim.fn.readfile('lua/cavediver/domains/navigation/states.lua')) do
		if l:find('@field FILE_PICKER', 1, true) then line = l:lower() end
	end
	local says = has(line, 'nothing enters') or has(line, 'not entered') or has(line, 'never entered')
	eq({ says, has(line, 'where explorer controls navigation') }, { true, false })
end

T['D21 [char] the old spec marks file-picker mode as not built'] = function()
	local s = section(read('WINDOW_BUFFER_RELATIONSHIP_SPECIFICATION.md'), '#### File Picker Mode')
	eq(has(s:lower(), 'not built'), true)
end

T['D25 [char] the closed-stack comments say filehashes'] = function()
	local data = read('lua/cavediver/domains/history/data.lua')
	local init = read('lua/cavediver/domains/history/init.lua')
	eq({
		has(data, 'closed buffer filenames'),
		has(init, 'closed buffer filenames'),
		has(init, 'Stack of closed buffer filehashes that can be reopened'),
	}, { false, false, true })
end

T['D25 [char] the loop state annotation is SELF "self"'] = function()
	local c = read('lua/cavediver/domains/ui/states.lua')
	eq({
		has(c, '---@field SELF "self" Continuous update loop state for UI refresh'),
		has(c, 'UPDATING "updating"'),
	}, { true, false })
end

T['D29 [char] init.lua\'s header says encrypted session persistence, and the XOR docstrings are gone'] = function()
	local init = read('lua/cavediver/init.lua')
	local storage = read('lua/cavediver/domains/storage/routines.lua')
	eq({
		has(init, '---hash-based buffer tracking, and encrypted session persistence.'),
		has(init, 'XOR-obfuscated'),
		has(storage:lower(), 'one-pass xor'),
	}, { true, false, false })
end

T['A26 [char] README says how to read a replay\'s line'] = function()
	local r = read(README)
	eq({
		has(r, 'When it\'s done, it says what it did in one line, such as `cavediver: replayed 12 steps, 5 driven, 5 matching, 0 resynced`'),
		has(r, 'a resync is a step the replay first put back where the dump says it began'),
	}, { true, true })
end

-- The engine (Q20) ----------------------------------------------------------

T['Q20 [char] the engine says modes are shared by every machine'] = function()
	local factory = read('lua/cavediver/engine/init.lua')
	local helpers = read('lua/cavediver/engine/helpers.lua')
	local lines = vim.fn.readfile('lua/cavediver/engine/state-machine.lua')
	local declared = false
	for i, l in ipairs(lines) do
		if l:find('^%s*transition_modes%s*=') then
			local above = table.concat(vim.list_slice(lines, math.max(1, i - 3), i - 1), ' '):lower()
			declared = has(above, 'shared')
		end
	end
	eq({
		declared,
		has(factory, 'its own independent state, transitions, hooks, and history'),
		has(helpers, "This state machine doesn't have any transition modes registered"),
		has(helpers, 'not registered in this state machine'),
	}, { true, false, false, false })
end

T['Q5 [char] the meaningless 30 in math.max(#ordered, 30) is gone'] = function()
	local c = read('lua/cavediver/domains/ui/routines.lua')
	eq(c:find('math%.max%(%s*#history%.data%.ordered%.crux%s*,%s*30%s*%)') ~= nil, false)
end

-- The desk --------------------------------------------------------------------

T['A12 [char] the desk narrows the cokeline item and its Dropped line to the fallback'] = function()
	local desk = read('DESK.md')
	local dropped = section(desk, '## Dropped', '## ')
	local phrase = 'only a fallback when cokeline is missing'
	local _, n = desk:gsub(phrase:gsub('%p', '%%%0'), '')
	eq({ has(dropped, phrase), n >= 2 }, { true, true })
end

T['D14 [char] the desk\'s new-file wipe bug and its repro name the faster trigger'] = function()
	local desk = read('DESK.md')
	eq({ has(desk, 'Sooner still, the next `BufEnter` anywhere wipes it'), has(desk, 'Or skip the wait') }, { true, true })
end

return T
