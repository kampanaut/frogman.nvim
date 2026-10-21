-- Test harness for cavediver behaviour checks. Loaded with :luafile before each scenario.
local SPEC = os.getenv("CDV_SPEC")
assert(SPEC and vim.startswith(vim.fn.stdpath("data"), SPEC), "stdpath data not in scratch")
assert(vim.startswith(vim.fn.getcwd(), SPEC), "cwd not in scratch")
vim.opt.rtp:prepend(os.getenv("CDV_PLUGIN"))
package.preload['harpoon'] = function()
	return { list = function() return { display = function() return {} end } end }
end
-- cokeline stub: by_step("focus", step) moves through cavediver's ordered history (index 1 = most recent).
package.preload['cokeline.mappings'] = function()
	return {
		by_step = function(_, step)
			local ord = require('cavediver.domains.history').get_ordered_buffers()
			local cur = vim.api.nvim_get_current_buf()
			local idx = 1
			for i, e in ipairs(ord) do if e.buf == cur then idx = i end end
			local n = #ord
			local nxt = ((idx - 1 + step) % n) + 1
			vim.api.nvim_set_current_buf(ord[nxt].buf)
		end,
		is_picking_focus = function() return false end,
		is_picking_close = function() return false end,
	}
end

NOTES = {}
vim.notify = function(msg, level) table.insert(NOTES, { msg = tostring(msg), level = level }) end

CDV = require('cavediver')
CDV.setup({ session_dir = SPEC .. "/xdg/data/cavediver/sessions/" })
H = require('cavediver.domains.history')
W = require('cavediver.domains.window')
N = require('cavediver.domains.navigation')

local function name(hash)
	if hash == nil then return "-" end
	local base = hash:gsub("%-swap$", "")
	local p = H.get_filepath_from_hash(base)
	local n = p and vim.fn.fnamemodify(p, ":t") or ("?" .. base:sub(1, 6))
	if hash:match("%-swap$") then n = n .. "-swap" end
	return n
end
NAME = name

function T(winid)
	winid = winid or vim.api.nvim_get_current_win()
	local t = W.data.crux[winid]
	if not t then return "no-triquetra" end
	local p = {}
	for _, h in ipairs(t.primary_buffer or {}) do table.insert(p, name(h)) end
	local function map(m)
		local keys = {}
		for k, v in pairs(m or {}) do table.insert(keys, name(k) .. ">" .. name(v)) end
		table.sort(keys)
		return "{" .. table.concat(keys, ",") .. "}"
	end
	return string.format("c=%s s=%s t=%s p=[%s]%s dtm=%s dsm=%s",
		name(t.current_slot), name(t.secondary_slot), name(t.ternary_slot), table.concat(p, ","),
		t.primary_enabled and "on" or "off", map(t.displacement_ternary_map), map(t.displacement_secondary_map))
end

function SHOWN(winid)
	return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(winid or 0)), ":t")
end

function ORD()
	local out = {}
	for _, e in ipairs(H.data.ordered.crux) do table.insert(out, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(e.buf), ":t")) end
	return table.concat(out, ",")
end

function CLOSED()
	local out = {}
	for _, h in ipairs(H.data.closed_buffers) do table.insert(out, name(h)) end
	return table.concat(out, ",")
end

LOG = {}
function P(label, s) table.insert(LOG, label .. ": " .. tostring(s)) end
function STATE(label) P(label, "shown=" .. SHOWN() .. " " .. T() .. " nav=" .. N.sm:state() .. " hist=" .. H.sm:state()) end
function FLUSH()
	for _, n in ipairs(NOTES) do table.insert(LOG, "  [notify " .. tostring(n.level) .. "] " .. n.msg:gsub("\n", " | "):sub(1, 220)) end
	NOTES = {}
end
function DONE()
	FLUSH()
	io.stdout:write(table.concat(LOG, "\n") .. "\n")
	vim.cmd("qa!")
end
function TRY(label, f)
	local ok, err = pcall(f)
	if not ok then P(label .. " ERROR", tostring(err):gsub(os.getenv("CDV_PLUGIN"), "<plugin>")) end
	FLUSH()
end
