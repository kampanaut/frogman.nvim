local data = require('cavediver.domains.ledger.data')
local routines = require('cavediver.domains.ledger.routines')

---Ledger domain initialization and API layer.
---
---The ledger domain records what set things off (steps) and what cavediver did then (moves).
---It's read two ways, as the ring of the last steps and as the trail of each day's moves. This
---module provides the API layer and the autocmds that begin steps.
local M = {}

M.data = data
M.routines = routines

M.begin = routines.begin

---Run a key's job as a step of its own.
---
---What's still queued to settle runs first, so it lands on the step it belongs to, as if the key
---had been typed by hand. Then the key's step begins, about the window given, and the job runs
---through the settle lock, a cycle still running in another window cancelled first.
---
---@param lhs string The key, as the step's trigger
---@param winid integer The window the step is about
---@param fn function The key's job
---@return any ... What the job returns
function M.run_key(lhs, winid, fn)
	local settle = require('cavediver.settle')
	settle.drain()
	routines.begin("keymap", lhs, winid)
	return settle.now(function()
		require('cavediver.domains.navigation').cancel_cycle_elsewhere()
		return fn()
	end)
end
M.within = routines.within
M.move = routines.move
M.step_fields = routines.step_fields
M.tell = routines.tell
M.drop_batch = routines.drop_batch
M.name_of = routines.name_of
M.steps = routines.steps
M.trail = routines.trail
M.trail_days = routines.trail_days
M.now = routines.now
M.slot_name = routines.slot_name
M.draw_row = routines.draw_row
M.slots = routines.slots
M.window_name = routines.window_name
M.note = routines.note
M.slots_moved = routines.slots_moved
M.open_step = routines.open_step
M.session_of = routines.session_of
M.claim = routines.claim
M.set_session = routines.set_session

---Raise an error for something that shouldn't happen, dumping the steps that led there first.
---
---Every "this is impossible" in cavediver goes through here. The dump is written once per
---distinct message while dumps are on, then the error is raised as `error()` would have raised
---it at the caller.
---
---@param message string What shouldn't have happened
function M.never(message)
	pcall(require('cavediver.domains.ledger.dump').never, message)
	error(message, 2)
end

---Check if a buffer is the flight recorder's dump, which the ledger records nothing about.
---
---@param bufnr Bufnr Buffer number
---@return boolean dump True if the buffer is a dump's
local function is_dump(bufnr)
	return vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].cavediver_dump == true
end

---Create the ledger's autocmds in cavediver's augroup.
---
---They're created before the other domains' in setup(), so a step has begun by the time their
---handlers act on the same event. This also hooks the dump into the engine's catch, so a hook
---that fails is dumped.
---
---@param group integer The cavediver augroup
---@return nil
function M.init_autocmds(group)
	require('cavediver.engine.helpers').on_failure = function(name, err)
		require('cavediver.domains.ledger.dump').hook_failed(name, err)
	end

	-- a command line entered is a step under its text, never the keys that typed it.
	vim.api.nvim_create_autocmd("CmdlineLeave", {
		group = group,
		callback = function()
			local event = vim.v.event
			if event.cmdtype ~= ":" or event.abort or is_dump(vim.api.nvim_get_current_buf()) then
				return
			end
			local line = vim.fn.getcmdline()
			if line ~= "" then
				local typed = line
				-- a path typed in it is kept as its last part, as every other trigger names files
				line = line:gsub("%S+", function(word)
					if word:match("^[/~.]") or vim.fn.filereadable(word) == 1 or vim.fn.isdirectory(word) == 1 then
						return vim.fs.basename(word)
					end
				end)
				local step = routines.begin("command", ":" .. line, vim.api.nvim_get_current_win())
				step.cut = line ~= typed or nil -- a replay can't run a line it no longer has whole
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "BufEnter", "BufDelete", "BufWritePost", "BufFilePost" }, {
		group = group,
		callback = function(args)
			if is_dump(args.buf) then
				return
			end
			routines.begin("event", args.event .. " " .. routines.buffer_label(args.buf), vim.api.nvim_get_current_win())
		end,
	})

	vim.api.nvim_create_autocmd("WinEnter", {
		group = group,
		callback = function()
			local winid = vim.api.nvim_get_current_win()
			if is_dump(vim.api.nvim_win_get_buf(winid)) then
				return
			end
			routines.begin("event", "WinEnter win " .. vim.api.nvim_win_get_number(winid), winid)
		end,
	})

	vim.api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = "buftype",
		callback = function()
			if is_dump(vim.api.nvim_get_current_buf()) then
				return
			end
			routines.begin("event", "OptionSet buftype", vim.api.nvim_get_current_win())
		end,
	})

	vim.api.nvim_create_autocmd("TabClosed", {
		group = group,
		callback = function(args)
			routines.begin("event", "TabClosed tab " .. args.file, vim.api.nvim_get_current_win())
		end,
	})
end

return M
