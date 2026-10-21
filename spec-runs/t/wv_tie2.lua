-- WV: the fill route under the window view, with the ordered list's access times after each key.
local v = os.getenv("CDV_VIEW"); if v and v ~= "" then require("cavediver.configs").bufferline.history_view = v end
dofile(os.getenv("CDV_SPEC") .. "/t/fmt.lua")
local function nm(b) return (vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t"):gsub("%.txt", "")) end
local function times()
	local o = {}
	for _, e in ipairs(H.data.ordered.crux) do table.insert(o, nm(e.buf) .. "=" .. e.time) end
	local c = {}
	for h, t in pairs(H.data.crux) do table.insert(c, { n = (NAME(h):gsub("%.txt", "")), t = t }) end
	table.sort(c, function(x, y) return x.t > y.t end)
	local cs = {} for _, e in ipairs(c) do table.insert(cs, e.n .. "=" .. e.t) end
	return "ordered " .. table.concat(o, " ") .. "   (crux " .. table.concat(cs, " ") .. ", next " .. H.data.history_index .. ")"
end
local WINS = {}
local function label(w) for i, x in ipairs(WINS) do if x == w then return "win" .. i end end table.insert(WINS, w) return "win" .. #WINS end
label(vim.api.nvim_get_current_win())
local function o(l, f)
	local ok, err = pcall(f)
	local ids = vim.api.nvim_tabpage_list_wins(0) table.sort(ids) for _, w in ipairs(ids) do label(w) end
	table.insert(ROWS, string.format("%-10s %-5s %s %s%s", l, label(vim.api.nvim_get_current_win()), TQ(), times(), ok and "" or ("  ERROR: " .. tostring(err):gsub("^.-:%d+: ", ""))))
	NOTES = {}
end
table.insert(ROWS, "-- " .. require("cavediver.configs").bufferline.history_view .. " view")
o(":e a", function() vim.cmd("edit a.txt") end)
o(":e b", function() vim.cmd("edit b.txt") end)
o(":vsplit", function() vim.cmd("vsplit") end)
o("<C-w>p", function() vim.cmd("wincmd p") end)
o(":e c", function() vim.cmd("edit c.txt") end)
o(":vsplit", function() vim.cmd("vsplit") end)
o("<M-f>", function() CDV.toggle_secondary() end)
ROWS_DONE()
