-- Row format the author asked for: ternary, current, secondary, with the winbar/bufferline brackets.
-- ⦉t⦊ [c] ⟦s⟧, then the primary queue and the notes.
local function n(h) local s = NAME(h) return (s:gsub("%.txt", "")) end
function TQ(winid)
	winid = winid or vim.api.nvim_get_current_win()
	local t = W.data.crux[winid]
	if not t then return "no triquetra" end
	local function slot(h, l, r) return h and (l .. n(h) .. r) or (l .. "-" .. r) end
	local function map(m)
		local ks = {}
		for k, v in pairs(m or {}) do table.insert(ks, n(k) .. ">" .. n(v)) end
		table.sort(ks)
		return "{" .. table.concat(ks, " ") .. "}"
	end
	local p = {}
	for _, h in ipairs(t.primary_buffer or {}) do table.insert(p, n(h)) end
	local prim = #p > 0 and ("  p=[" .. table.concat(p, ",") .. "]" .. (t.primary_enabled and "on" or "off")) or ""
	return string.format("%s %s %s%s   dtm%s dsm%s", slot(t.ternary_slot, "⦉", "⦊"), slot(t.current_slot, "[", "]"),
		slot(t.secondary_slot, "⟦", "⟧"), prim, map(t.displacement_ternary_map), map(t.displacement_secondary_map))
end
ROWS = {}
function ROW(action, f)
	local ok, err = true, nil
	if f then ok, err = pcall(f) end
	vim.wait(150)
	local note = ""
	for _, x in ipairs(NOTES) do note = note .. "  «" .. x.msg:gsub("\n.*", ""):sub(1, 70) .. "»" end
	NOTES = {}
	if not ok then note = note .. "  ERROR: " .. tostring(err):gsub("^.-:%d+: ", ""):sub(1, 80) end
	table.insert(ROWS, string.format("%-34s %s%s", action, TQ(), note))
end
function ROWS_DONE() io.stdout:write(table.concat(ROWS, "\n") .. "\n") vim.cmd("qa!") end
