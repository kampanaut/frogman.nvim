-- D17: the window-jump history with two tabs. Window ids are printed as labels (w1..w4) with their tab.
local labels, n = {}, 0
local function L(w) if not w then return "nil" end if not labels[w] then n = n + 1; labels[w] = "w" .. n end
  local ok, tp = pcall(vim.api.nvim_win_get_tabpage, w); return labels[w] .. (ok and ("(tab" .. vim.api.nvim_tabpage_get_number(tp) .. ")") or "(closed)") end
local J = N.data.window_jump_history
local function where(label) P(label, "now in " .. L(vim.api.nvim_get_current_win()) .. "  winnr('#')=" .. vim.fn.winnr("#")) end
local function dump(label)
  local out = {}
  for to, from in pairs(J) do table.insert(out, L(to) .. "<-" .. L(from)) end
  table.sort(out); P(label, "jump table: " .. table.concat(out, " ") .. "  (entries: " .. vim.tbl_count(J) .. ")")
end
local function M_comma(label) TRY(label, function() CDV.toggle_window() end); vim.wait(50); where(label) end

vim.cmd("e a.txt"); L(vim.api.nvim_get_current_win())
local SEEN = {}
vim.api.nvim_create_autocmd("WinEnter", { callback = function()
  table.insert(SEEN, "WinEnter " .. L(vim.api.nvim_get_current_win()) .. ": winnr('#')=" .. vim.fn.winnr("#") .. ", last_valid_window=" .. L(W.data.last_valid_window))
end })
local function seen() for _, x in ipairs(SEEN) do P("    seen", x) end SEEN = {} end
vim.cmd("vsplit"); vim.cmd("e b.txt"); where("tab1 :vsplit, :e b")
SEEN = {}; vim.cmd("tabnew"); seen(); vim.cmd("e c.txt"); where("tabnew, :e c"); dump("after tabnew")
M_comma("<M-,> in the new tab's first window")
vim.cmd("tabnext 2"); vim.cmd("vsplit"); vim.cmd("e d.txt"); where("tab2 :vsplit, :e d"); dump("tab2 split")
vim.cmd("tabnext 1"); seen(); where("gt to tab1"); dump("after switching to tab1")
P("  Vim's own <C-w>p would go to", L(vim.fn.win_getid(vim.fn.winnr("#"))))
M_comma("<M-,> in tab1")
vim.cmd("tabnext 2"); where("gt to tab2")
M_comma("<M-,> in tab2")
M_comma("<M-,> again")
-- close a tab and see what stays
vim.cmd("tabclose"); where("tabclose tab2"); dump("after tabclose")
DONE()
