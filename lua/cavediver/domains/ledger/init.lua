local data = require('cavediver.domains.ledger.data')
local routines = require('cavediver.domains.ledger.routines')

---Ledger domain: one record of what set things off (steps) and what cavediver did then (moves),
---read two ways: the ring of the last steps, and the trail of the days' moves.
local M = {}

M.data = data
M.routines = routines

M.begin = routines.begin
M.within = routines.within
M.move = routines.move
M.tell = routines.tell
M.drop_batch = routines.drop_batch
M.name_of = routines.name_of
M.steps = routines.steps
M.trail = routines.trail
M.slots = routines.slots
M.window_name = routines.window_name
M.note = routines.note
M.slots_moved = routines.slots_moved
M.open_step = routines.open_step

---Create the ledger's autocmds in cavediver's augroup. setup() calls this before the other
---domains', so a step has begun by the time their handlers act on the same event.
---
---@param group integer The cavediver augroup
function M.init_autocmds(group)
	-- a command line entered is a step under its text, never the keys that typed it.
	vim.api.nvim_create_autocmd("CmdlineLeave", {
		group = group,
		callback = function()
			local event = vim.v.event
			if event.cmdtype ~= ":" or event.abort then
				return
			end
			local line = vim.fn.getcmdline()
			if line ~= "" then
				routines.begin("command", ":" .. line, vim.api.nvim_get_current_win())
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "BufEnter", "BufDelete", "BufWritePost", "BufFilePost" }, {
		group = group,
		callback = function(args)
			routines.begin("event", args.event .. " " .. routines.buffer_label(args.buf), vim.api.nvim_get_current_win())
		end,
	})

	vim.api.nvim_create_autocmd("WinEnter", {
		group = group,
		callback = function()
			local winid = vim.api.nvim_get_current_win()
			routines.begin("event", "WinEnter win " .. vim.api.nvim_win_get_number(winid), winid)
		end,
	})

	vim.api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = "buftype",
		callback = function()
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
