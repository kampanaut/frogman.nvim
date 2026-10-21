-- EX rows: t/fmt.lua, with the sandbox markers turned into short labels and hashes in messages turned into names.
dofile(os.getenv("CDV_SPEC") .. "/t/fmt.lua")
local base_row = ROW
local function nm(s) return (s:gsub("%.txt", "")) end
local function tidy(m, level)
	local site, mode, x, t, new, out = m:match("^EX%-t (%S+) (%S+) (%S+)>(%S+) => (%S+) (%S+)")
	if site then
		if new == "-" then return "ternary note " .. x .. ">" .. t .. " dropped" .. (out == "guard" and " (it would name " .. x .. " itself)" or "") end
		return "ternary note " .. x .. ">" .. t .. " becomes " .. x .. ">" .. new
	end
	local ssite, sout, sx, ss, snew = m:match("^KT%-s (%S+) (%S+) (%S+)>(%S+) => (%S+)")
	if ssite then
		if sout == "drop" then return "secondary note " .. sx .. ">" .. ss .. " dropped" end
		return "secondary note " .. sx .. ">" .. ss .. " becomes " .. sx .. ">" .. snew
	end
	local kx, kt, knew = m:match("^KT%-t %S+ %S+ (%S+)>(%S+) => (%S+)")
	if kx then
		if knew == "-" then return "ternary note " .. kx .. ">" .. kt .. " dropped" end
		return "ternary note " .. kx .. ">" .. kt .. " becomes " .. kx .. ">" .. knew
	end
	m = m:gsub("Restored (%a+) slot to: %x+ %(([^)]+)%)", function(k, f) return "Restored " .. k .. " slot to " .. nm(f) end)
	m = m:gsub("No ternary relationship found.*", "No ternary relationship found…")
	m = m:gsub("No secondary relationship found.*", "No secondary relationship found…")
	m = m:gsub("Secondary buffer set to ternary slot%. Ternary slot graduated%.", "…graduated.")
	m = m:gsub("^Avoided conflict.*", "Avoided conflict…")
	m = m:gsub("^The stored ternary of the new buffer is already the ternary.*", "The stored ternary of the new buffer is already the ternary…")
	return m
end
function ROW(action, f)
	local wrapped = f and function()
		f()
	end
	local ok, err = true, nil
	if wrapped then ok, err = pcall(wrapped) end
	vim.wait(150)
	local parts = {}
	for _, x in ipairs(NOTES) do
		if not x.msg:match("^Checkpoint saved") then table.insert(parts, "«" .. tidy(x.msg:gsub("\n.*", ""), x.level) .. "»") end
	end
	NOTES = {}
	local note = #parts > 0 and ("  " .. table.concat(parts, " ")) or ""
	if not ok then
		local e = tostring(err):gsub("^.-:%d+: ", "")
		e = e:gsub("This is impossible%. ", ""):gsub(" It should be different for flip flop%.", "")
		note = note .. "  ERROR: " .. e
	end
	table.insert(ROWS, string.format("%-34s %s%s", action, TQ(), note))
end
