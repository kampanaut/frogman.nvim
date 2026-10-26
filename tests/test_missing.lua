-- Missing files tagged (what-is-frogman.md, M14, and section 7, "Missing
-- files tagged"). IDs are the spec's.
local Helpers = dofile('tests/helpers.lua')
local Misc = dofile('tests/helpers_misc.lua')
local S2 = dofile('tests/helpers_s2.lua')
local eq = Helpers.eq
local child = Helpers.new_child()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function() child.setup() end,
		post_once = child.stop,
	},
})

-- The project gets a planted .git/HEAD, no git binary. A FocusGained, one of
-- the settle points, makes frogman read the label and watch HEAD; a HEAD
-- written afterwards is seen through the watch.

local function plant_head(text)
	child.lua([[
		local root, text = _G.FRG_TEST.root, ...
		vim.fn.mkdir(root .. '/.git', 'p')
		vim.fn.writefile({ text }, root .. '/.git/HEAD')
	]], { text })
end

local function tag_of(stem)
	return child.lua([[
		local H = require('frogman.domains.history')
		local hash = H.get_hash_from_filepath(_G.FRG_TEST.root .. '/' .. ... .. '.txt')
		return H.data.missing[hash] or vim.NIL
	]], { stem })
end

-- b sits closed in the secondary when it goes missing with the switch.
T['T343 [char] files that go missing at a branch switch are tagged with the branch being left, shown in the winbar, and cleared when they come back'] = function()
	plant_head('ref: refs/heads/feature')
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	child.cmd('bdelete b.txt')
	child.settle()
	child.cmd('doautocmd FocusGained')
	child.settle()
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	child.lua('os.remove(_G.FRG_TEST.root .. "/b.txt")')
	plant_head('ref: refs/heads/main')
	child.settle(300)
	eq(tag_of('b'), 'feature')
	child.settle(300)
	eq(child.lua('return vim.wo.winbar'):find('⎇feature', 1, true) ~= nil, true)
	child.lua('vim.fn.writefile({ "b" }, _G.FRG_TEST.root .. "/b.txt")')
	child.lua('require("frogman.domains.history").cleanup_system()')
	child.settle(300)
	eq(tag_of('b'), vim.NIL)
	eq(child.lua('return vim.wo.winbar'):find('⎇', 1, true), nil)
end

T['T344 [char] with no label, a file that goes missing is tagged with the time'] = function()
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('bdelete b.txt')
	child.settle()
	child.lua('os.remove(_G.FRG_TEST.root .. "/b.txt")')
	child.lua('require("frogman.domains.history").cleanup_system()')
	local tag = tag_of('b')
	eq(type(tag) == 'string' and tag:match('^%d%d:%d%d$') ~= nil, true)
end

T['T345 [char] a label provider in config names the label'] = function()
	child.lua('_G.FRG_TEST.setup({ label_provider = function() return "jj:main" end })')
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('bdelete b.txt')
	child.settle()
	child.lua('os.remove(_G.FRG_TEST.root .. "/b.txt")')
	child.lua('require("frogman.domains.history").cleanup_system()')
	eq(tag_of('b'), 'jj:main')
end

T['T346 [char] disable() stops the HEAD watch'] = function()
	plant_head('ref: refs/heads/feature')
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('bdelete b.txt')
	child.settle()
	child.cmd('doautocmd FocusGained')
	child.settle()
	child.lua('require("frogman").disable()')
	child.lua('os.remove(_G.FRG_TEST.root .. "/b.txt")')
	plant_head('ref: refs/heads/main')
	child.settle(300)
	eq(tag_of('b'), vim.NIL)
end


-- A save runs a cleanup pass, which reads the label again; after disable() it
-- doesn't start the watch.
T['T346 [char] a save after disable() doesn\'t watch .git/HEAD again'] = function()
	plant_head('ref: refs/heads/feature')
	child.steps({ ':e a', ':e b', ':e c' })
	child.cmd('bdelete b.txt')
	child.settle()
	child.cmd('doautocmd FocusGained')
	child.settle()
	child.lua('require("frogman").disable()')
	eq(Misc.save(child), { true })
	child.lua('os.remove(_G.FRG_TEST.root .. "/b.txt")')
	plant_head('ref: refs/heads/main')
	child.settle(300)
	eq(tag_of('b'), vim.NIL)
end

-- The session is saved on feature; HEAD moves to main and b.txt goes while no
-- editor is open, so the next load is the first to see either.
T['T347 [char] the label at a save is the one being left at the next load: a file gone while no editor was open is tagged with the branch the session was saved on'] = function()
	local s = S2.shared()
	S2.start(child, s)
	plant_head('ref: refs/heads/feature')
	child.steps({ ':e a', ':e b', ':e c', '<M-f>', ':e d' })
	child.cmd('bdelete b.txt')
	child.settle()
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	eq(Misc.save(child), { true })

	S2.start(child, s)
	-- after the start: a child's setup writes the project's files again
	plant_head('ref: refs/heads/main')
	os.remove(s.root .. '/b.txt')
	Misc.restore(child, { 'a', 'c', 'd' }, 'd')
	eq(Misc.load(child), { true })
	child.settle(300)
	eq(child.slots(), '⦉c⦊ [d] ⟦b⟧')
	eq(tag_of('b'), 'feature')
end

T['T348 [char] a file that was never written isn\'t tagged; once written and deleted, it is'] = function()
	child.steps({ ':e a', ':e brandnew.txt' })
	child.lua('vim.api.nvim_buf_set_lines(0, 0, -1, false, { "new" })')
	child.lua('require("frogman.domains.history").cleanup_system()')
	child.settle(300)
	eq({ tag = tag_of('brandnew'), winbar = child.lua('return vim.wo.winbar'):find('⎇', 1, true) ~= nil },
		{ tag = vim.NIL, winbar = false })
	child.cmd('write')
	child.lua('require("frogman.domains.history").cleanup_system()')
	child.lua('os.remove(_G.FRG_TEST.root .. "/brandnew.txt")')
	child.lua('require("frogman.domains.history").cleanup_system()')
	eq(type(tag_of('brandnew')), 'string')
end

-- vim.fn.filereadable and vim.fs.find counted in the child while each runs.
T['T564 [char] a tick checks each file against the disk once, and finds .git once'] = function()
	plant_head('ref: refs/heads/main')
	child.steps({ ':e a', ':e b', ':e c', ':e d' })
	child.cmd('bdelete d.txt')
	-- the label is read once first: a change of label would check every file again, as it should
	child.lua('require("frogman.domains.history").routines.refresh_label()')
	local counts = child.lua([[
		local H = require('frogman.domains.history')
		local readable, find = vim.fn.filereadable, vim.fs.find
		local reads, finds = {}, 0
		vim.fn.filereadable = function(path)
			local stem = vim.fn.fnamemodify(path, ':t:r')
			reads[stem] = (reads[stem] or 0) + 1
			return readable(path)
		end
		vim.fs.find = function(names, opts)
			if names == '.git' then finds = finds + 1 end
			return find(names, opts)
		end
		local ok = pcall(H.routines.mark_missing, nil, 500)
		local ok2 = pcall(H.routines.refresh_label)
		vim.fn.filereadable, vim.fs.find = readable, find
		return { ok = ok and ok2, reads = reads, finds = finds }
	]])
	eq(counts, { ok = true, reads = { a = 1, b = 1, c = 1, d = 1 }, finds = 1 })
end

T['T524 [char] a check before a new file is taken in keeps its mark'] = function()
	child.steps({ ':e a' })
	-- the check comes between BufNewFile and the arrival, which waits for the editor to settle
	child.lua([[
		vim.cmd('edit brandnew.txt')
		require('frogman.domains.history').routines.mark_missing()
	]])
	child.settle(300)
	local taken = child.lua('return require("frogman.domains.history").get_hash_from_buffer(vim.api.nvim_get_current_buf()) ~= nil')
	child.lua('require("frogman.domains.history").routines.mark_missing()')
	eq({ taken = taken, tag = tag_of('brandnew') }, { taken = true, tag = vim.NIL })
end

return T
