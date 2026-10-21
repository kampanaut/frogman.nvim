-- D14: a new, unsaved file gets wiped. Which triggers? No buffer content is printed: only validity, registration, line and window counts.
local orig = vim.cmd
vim.cmd = setmetatable({}, { __call = function(_, c)
  if type(c) == "string" and c:match("^bw") then
    local where = {}
    for l in debug.traceback("", 2):gmatch("cavediver/lua/cavediver/domains/([%w/%-_]+%.lua:%d+)") do table.insert(where, l) end
    P("  bw! called from", where[1] or "?")
  end
  return orig(c)
end, __index = orig })
local function flush_counts()
  local n = #NOTES; local first = NOTES[1] and NOTES[1].msg:gsub("\n.*", ""):gsub(os.getenv("CDV_PLUGIN"), "<plugin>"):sub(1, 150)
  if n > 0 then P("  notifications", n .. (first and (", first: " .. first) or "")) end
  NOTES = {}
end
local function info(label, nb)
  local valid = vim.api.nvim_buf_is_valid(nb)
  P(label, string.format("valid=%s lines=%s registered=%s shown=%s windows=%d",
    tostring(valid), valid and vim.api.nvim_buf_line_count(nb) or "-", tostring(H.get_hash_from_buffer(nb) ~= nil), SHOWN(), #vim.api.nvim_tabpage_list_wins(0)))
end
local function newfile(name)
  vim.cmd("e " .. name); vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x", "y", "z" })
  return vim.api.nvim_get_current_buf()
end
vim.cmd("e a.txt"); vim.cmd("e b.txt"); NOTES = {}

-- Route T: stay on the file, press nothing, wait one cleanup tick (4 s timer)
local n3 = newfile("new3.txt"); info("T  typed 3 lines in new3", n3)
vim.wait(4600, function() return false end)
info("T  after one tick, no keys", n3); flush_counts()

-- Route E1: :e to another file in the same window
local n1 = newfile("new1.txt"); info("E1 typed 3 lines in new1", n1)
vim.cmd("e a.txt"); info("E1 after :e a", n1); flush_counts()

-- Route E2: move to another window (BufEnter fires for that window's buffer)
vim.cmd("vsplit"); vim.cmd("e b.txt")
local n2 = newfile("new2.txt"); local w2 = vim.api.nvim_get_current_win(); info("E2 typed 3 lines in new2 (split)", n2)
vim.cmd("wincmd p"); info("E2 after <C-w>p to the other window", n2)
P("E2 split window still valid", tostring(vim.api.nvim_win_is_valid(w2)) .. ", triquetra kept for it: " .. tostring(W.data.crux[w2] ~= nil))
vim.cmd("e b.txt"); flush_counts()

-- Route D: a file on disk, deleted outside nvim (the sandbox copy), then :e elsewhere
vim.cmd("only"); vim.cmd("e d.txt"); local nd = vim.api.nvim_get_current_buf(); info("D  :e d (on disk)", nd)
os.remove(vim.fn.getcwd() .. "/d.txt"); vim.cmd("e a.txt"); info("D  d removed on disk, then :e a", nd); flush_counts()
DONE()
