#!/usr/bin/env python3
"""rt_c1sga / rt_c3kga: the guard variants plus the same check on every other arrival and on every change of the
secondary under the current buffer (picks, navigation, <M-S-f>, primary jump, graduation, ternary restore)."""
import os, shutil
V = "@RUNS@/variants"
W = "/lua/cavediver/domains/window/"
def sub(p, old, new):
    s = open(p).read(); assert s.count(old) == 1, (p, old[:50], s.count(old)); open(p, "w").write(s.replace(old, new))
for src, dst in (("rt_c2b", "rt_c2bga"),):
    d = V + "/" + dst
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(V + "/" + src, d)
    r, h = d + W + "routines.lua", d + W + "hooks.lua"
    sub(r, "function M.rt_secondary_notes(triquetra)", '''-- RT: drop the current buffer's plain secondary note when it names the window's secondary.
function M.rt_sec_check(triquetra, x, s)
	local dsm = triquetra.displacement_secondary_map
	if x and s and dsm[x] == s then dsm[x] = nil end
end
function M.rt_secondary_notes(triquetra)''')
    # reconcile: every arrival through it (picks, <M-S-f>, <M-f>); the secondary after the arrival
    sub(r, '''	if triquetra and triquetra.current_slot ~= new_filehash then
		-- Reconcile the triquetra slots if we selected a buffer part of the relationship
''', '''	if triquetra and triquetra.current_slot ~= new_filehash then
		M.rt_sec_check(triquetra, new_filehash, (triquetra.secondary_slot == new_filehash) and triquetra.current_slot or triquetra.secondary_slot) -- RT
		-- Reconcile the triquetra slots if we selected a buffer part of the relationship
''')
    # graduation
    sub(r, '''			triquetra.ternary_slot = nil
			vim.notify("Secondary buffer set to ternary slot. Ternary slot graduated.", vim.log.levels.INFO)''', '''			triquetra.ternary_slot = nil
			M.rt_sec_check(triquetra, triquetra.current_slot, triquetra.secondary_slot) -- RT
			vim.notify("Secondary buffer set to ternary slot. Ternary slot graduated.", vim.log.levels.INFO)''')
    # primary jump
    sub(r, '''		triquetra.current_slot = triquetra.primary_buffer[1]
	else''', '''		triquetra.current_slot = triquetra.primary_buffer[1]
		M.rt_sec_check(triquetra, triquetra.current_slot, triquetra.secondary_slot) -- RT
	else''')
    # ternary restore moving the ternary into the secondary
    sub(r, '''				triquetra.secondary_slot = triquetra.ternary_slot
				triquetra.ternary_slot = remembered_relationship''', '''				triquetra.secondary_slot = triquetra.ternary_slot
				triquetra.ternary_slot = remembered_relationship
				M.rt_sec_check(triquetra, triquetra.current_slot, triquetra.secondary_slot) -- RT''')
    # navigation (not onto the secondary)
    sub(h, '''		triquetra.ternary_slot = triquetra.current_slot
		triquetra.current_slot = new_filehash
	end
end, 2, true, history.states.mode.UPDATE)''', '''		triquetra.ternary_slot = triquetra.current_slot
		triquetra.current_slot = new_filehash
		routines.rt_sec_check(triquetra, new_filehash, triquetra.secondary_slot) -- RT
	end
end, 2, true, history.states.mode.UPDATE)''')
    print("built", dst)
