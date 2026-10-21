-- EX: the cleanup re-point. The current buffer's file is deleted on disk (the sandbox's run copy only), then a
-- cleanup pass runs, as the BufEnter hook, the cleanup timer or the bufferline's cache rebuild run it.
-- The ternary is moved into the current slot; the secondary stays.
dofile(os.getenv("CDV_SPEC") .. "/t/ex_fmt.lua")
local p = os.getenv("CDV_PLUGIN") or ""
table.insert(ROWS, "-- plugin: " .. (p:match("variants/([^/]+)$") or "today"))
local SEQ = vim.split(os.getenv("EX_SEQ") or "ea eb F F F ex", " ", { trimempty = true })
local acts = { F = { "<M-f>", function() CDV.toggle_secondary() end }, G = { "<M-S-f>", function() CDV.toggle_ternary() end },
	R = { "<M-;><M-r>", function() CDV.restore_ternary() end }, S = { "<M-;><M-t>", function() CDV.restore_secondary() end } }
for _, a in ipairs(SEQ) do
	if a:sub(1, 1) == "e" then ROW(":e " .. a:sub(2), function() vim.cmd("edit " .. a:sub(2) .. ".txt") end)
	else ROW(acts[a][1], acts[a][2]) end
end
local victim = vim.fn.expand("%:p")
ROW("(" .. vim.fn.fnamemodify(victim, ":t:r") .. " deleted on disk) cleanup", function()
	assert(vim.startswith(victim, os.getenv("CDV_SPEC")), "not in the sandbox")
	os.remove(victim)
	require('cavediver.domains.window.routines').cleanup_triquetras()
end)
ROW("<M-;><M-t>", function() CDV.restore_secondary() end)
ROW("<M-;><M-r>", function() CDV.restore_ternary() end)
ROWS_DONE()
