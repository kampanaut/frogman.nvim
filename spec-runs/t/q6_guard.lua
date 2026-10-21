-- the case the guard was written for: a cycle pick from outside the slots
local function show(label) vim.wait(150) print(string.format("  %-44s %s", label, T():gsub(" p=%[%]off", ""):gsub(" dsm={}", ""))) end
vim.cmd('edit a.txt') vim.cmd('edit x.txt') vim.cmd('edit t.txt') show(":e a, :e x, :e t")
vim.cmd('edit e.txt') show(":e e  (leave t: note t → x)")
local before = #NOTES
-- cycle to x (outside the slots) and pick it
CDV.cycle_left() vim.wait(100)
while vim.fn.expand('%:t') ~= 'x.txt' do CDV.cycle_left() vim.wait(80) end
show("<M-n> … until x is shown")
CDV.cycle_select() show("<M-v>  (pick x, outside the slots)")
for i = before + 1, #NOTES do if NOTES[i].level == vim.log.levels.WARN then print("    WARN: " .. NOTES[i].msg:sub(1, 90)) end end
CDV.toggle_ternary() show("<M-S-f>  (to t)")
local ok, err = pcall(CDV.restore_ternary) show("<M-;><M-r>  (restore on t)")
if not ok then print("    ERROR: " .. tostring(err):sub(1, 120)) end
vim.cmd('qa!')
