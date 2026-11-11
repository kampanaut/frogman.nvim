---Editable views.
---
---The floats frogman opens on a buffer you edit and then write: the marks pop-up and the snapshot
---list. `open` makes the view's `acwrite` buffer, with a name of its own, written by its own write, drawn
---again at every change, and wiped with its window, however that window closes, as the snapshot list's
---is; `float` opens the float on a buffer its caller keeps, as the marks pop-up keeps one per scope.

local M = {}

---Open an editable view.
---
---The buffer is made and named, `fill` puts its lines in, and only then is its filetype set, so the
---keys its filetype maps find it drawn; a `fill` that raises, or a window that can't open, takes the
---buffer with it, so its name is free for the next open. A write runs `write` when the buffer was edited, and every change runs
---`changed` with the event's name. The window closing takes the buffer with it, then runs `closed`.
---
---@param opts {name: string, filetype: string, title: string, size: table, fill: fun(buf: Bufnr), write: fun(), changed: fun(event: string), closed: fun(buf: Bufnr), events: string[]|nil, window: table|nil} The view's options
---@return Bufnr buf
---@return WinId win
function M.open(opts)
	local buf = vim.api.nvim_create_buf(false, false)
	vim.bo[buf].modifiable = true -- an editable view: on, whatever a new buffer takes from a global nomodifiable
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].swapfile = false
	vim.bo[buf].bufhidden = "wipe"
	vim.api.nvim_buf_set_name(buf, opts.name)
	local filled, problem = pcall(opts.fill, buf)
	if not filled then
		vim.api.nvim_buf_delete(buf, { force = true }) -- shown nowhere yet, so no wipe would take it
		error(problem, 0)
	end
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
	local opened, win = pcall(M.float, buf, {
		title = opts.title, size = opts.size, window = opts.window,
		closed = function()
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
			opts.closed(buf)
		end,
	})
	if not opened then
		vim.api.nvim_buf_delete(buf, { force = true }) -- shown nowhere, as when fill raises
		opts.closed(buf)
		error(win, 0)
	end
	return buf, win
end

---Mark a window as one of frogman's editable floats, so what guards them finds it by the window, whatever
---its buffer is named since.
---
---@param win WinId The float
---@return nil
function M.own(win)
	vim.w[win].frogman_float = true
end

---Tell whether a window is one of frogman's editable floats.
---
---@param win WinId The window to check
---@return boolean own True for a float `own` marked
function M.is_own(win)
	return vim.api.nvim_win_is_valid(win) and vim.w[win].frogman_float == true
end

---Open a float on a buffer its caller keeps: when the float closes, `closed` runs, the buffer staying or going
---as its 'bufhidden' says.
---
---@param buf Bufnr The buffer to show, kept by the caller
---@param opts {title: string, size: table, closed: fun(), window: table|nil} The float's options
---@return WinId win
function M.float(buf, opts)
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
			opts.closed()
		end,
	})
	M.own(win)
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	for option, value in pairs(opts.window or {}) do
		vim.wo[win][option] = value
	end
	return win
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
---@param win WinId|nil The view's window (nothing happens when it's nil or gone)
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
---@param buf Bufnr The view's buffer
---@param win WinId|nil The view's window to close (nil when there's none)
---@param write fun(): boolean The view's write, false when it was refused or answered No
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
