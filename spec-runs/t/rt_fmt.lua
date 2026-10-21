-- RT rows: t/fmt.lua, plus the C3 sandbox's partner store (pt{…}) when a variant has one.
dofile(os.getenv("CDV_SPEC") .. "/t/fmt.lua")
local base_tq = TQ
function TQ(winid)
	local s = base_tq(winid)
	local t = W.data.crux[winid or vim.api.nvim_get_current_win()]
	if t and t.rt_partner then
		local ks = {}
		for k, v in pairs(t.rt_partner) do table.insert(ks, (NAME(k):gsub("%.txt", "")) .. ">" .. (NAME(v):gsub("%.txt", ""))) end
		table.sort(ks)
		s = s .. " pt{" .. table.concat(ks, " ") .. "}"
	end
	return s
end
E = function(f) return function() vim.cmd("edit " .. f .. ".txt") end end
F = function() CDV.toggle_secondary() end
G = function() CDV.toggle_ternary() end
RT = function() CDV.restore_ternary() end
RS = function() CDV.restore_secondary() end
J = function() CDV.jump_to_primary() end
-- the rows' header: which plugin ran
local p = os.getenv("CDV_PLUGIN") or ""
local v = p:match("variants/([^/]+)$") or "today"
table.insert(ROWS, "-- plugin: " .. v)
