---Editable views.
---
---The floats frogman opens on a buffer you edit and then write: the marks pop-up and the snapshot
---list. Each is an `acwrite` buffer with a name of its own, written by its own write, drawn again at
---every change, and wiped with its window, however that window closes.

local M = {}

---Open an editable view.
---
---The buffer is made and named, `fill` puts its lines in, and only then is its filetype set, so the
---keys its filetype maps find it drawn. A write runs `write` when the buffer was edited, and every
---change runs `changed` with the event's name. The window closing takes the buffer with it, then
---runs `closed`.
---
---@param opts {name: string, filetype: string, title: string, size: table, fill: fun(buf: Bufnr), write: fun(), changed: fun(event: string), closed: fun(buf: Bufnr), events: string[]|nil, window: table|nil}
---@return Bufnr buf
---@return WinId win
function M.open(opts)
	local buf = vim.api.nvim_create_buf(false, false)
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].swapfile = false
	vim.bo[buf].bufhidden = "wipe"
	vim.api.nvim_buf_set_name(buf, opts.name)
	opts.fill(buf)
	vim.bo[buf].filetype = opts.filetype
	vim.api.nvim_create_autocmd(opts.events or { "TextChanged", "TextChangedI" }, {
		buffer = buf,
		callback = function(ev)
			opts.changed(ev.event)
		end,
		desc = "Draw " .. opts.title .. " again",
	})
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			if vim.bo[buf].modified then
				opts.write()
			end
		end,
		desc = "Write " .. opts.title,
	})
	local width, height, col, row = require('frogman.domains.ui').routines.resolve_float_geometry(opts.size)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor", width = width, height = height, col = col, row = row,
		style = "minimal", border = "rounded", title = " " .. opts.title .. " ", title_pos = "center",
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = "frogman",
		pattern = tostring(win),
		once = true,
		callback = function()
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
			opts.closed(buf)
		end,
	})
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	for option, value in pairs(opts.window or {}) do
		vim.wo[win][option] = value
	end
	return buf, win
end

---Keep a view that holds edits not written yet: focus it, and say so.
---
---@param buf Bufnr|nil The view's buffer, when one is open
---@param win WinId|nil Its window
---@param message string What to say
---@return boolean kept Whether it held edits, and so was kept
function M.keep_if_dirty(buf, win, message)
	if not (buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified) then
		return false
	end
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
	vim.notify(message, vim.log.levels.WARN)
	return true
end

---Show the line drawn above a view's first line: a window shows a line above its top one only when
---told to.
---
---@param win WinId|nil
---@return nil
function M.show_top(win)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_call(win, function()
			vim.fn.winrestview({ topline = 1, topfill = 1 })
		end)
	end
end

---Write a view when it was edited, then close it. A write that's refused or answered No leaves it
---open, its lines as typed.
---
---@param buf Bufnr
---@param win WinId|nil
---@param write fun(): boolean
---@return nil
function M.leave(buf, win, write)
	if vim.bo[buf].modified and not write() then
		return
	end
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
end

return M
