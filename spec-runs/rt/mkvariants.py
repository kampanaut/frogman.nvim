#!/usr/bin/env python3
"""Builds the RT variants from variant C (Q6's guard in reconcile_triquetra) under spec/variants/.
rt_base = Q6's guard on all four routes + D8 (plain navigation onto the secondary writes <M-f>'s notes).
rt_c1/c1s/c2a/c2b/c3 = rt_base plus one candidate each. Never touches the repo."""
import os, shutil, sys
SPEC = "@RUNS@"
V = SPEC + "/variants"
C = V + "/rt_C"
R = "/lua/cavediver/domains/window/routines.lua"
HK = "/lua/cavediver/domains/window/hooks.lua"

def sub(path, old, new, count=1):
    s = open(path).read()
    assert s.count(old) == count, (path, old[:60], s.count(old))
    open(path, "w").write(s.replace(old, new))

HELPER = '''
-- RT (sandbox only): the notes written before every swap onto the secondary:
-- <M-f>, its <M-;><M-f> fallback, and plain navigation onto the secondary (D8).
local RT_MODE = "%s"
local RT_OWN_SLOT = %s
function M.rt_secondary_notes(triquetra)
	local A, S, T = triquetra.current_slot, triquetra.secondary_slot, triquetra.ternary_slot
	local dsm = triquetra.displacement_secondary_map
	if RT_MODE == "base" then
		dsm[A] = S
	elseif RT_MODE == "c1" then -- two kinds: a swap note, like dtm's
		dsm[A .. "-swap"] = S
	elseif RT_MODE == "c2a" then -- skip the write on a pure toggle back
		if dsm[S] ~= A then dsm[A] = S end
	elseif RT_MODE == "c2b" then -- skip the write on a pure toggle back, and clear the partner's note
		if dsm[S] == A then dsm[S] = nil else dsm[A] = S end
	elseif RT_MODE == "c3k" then -- C3 kept in dsm: the swap note is the last partner; promote it on arrival when the partner changes
		local old = dsm[S .. "-swap"]
		dsm[A .. "-swap"] = S
		if old ~= nil and old ~= A then dsm[S] = old end
	elseif RT_MODE == "c1g" then -- C1 plus the secondary guard: S's plain note naming A is cleared
		dsm[A .. "-swap"] = S
		if dsm[S] == A then dsm[S] = nil end
	elseif RT_MODE == "c3kg" then -- C3 kept in dsm, plus the secondary guard
		local old = dsm[S .. "-swap"]
		dsm[A .. "-swap"] = S
		if old ~= nil and old ~= A then dsm[S] = old elseif dsm[S] == A then dsm[S] = nil end
	elseif RT_MODE == "c3" then -- note only when the arriving buffer's partner changes
		triquetra.rt_partner = triquetra.rt_partner or {}
		local p = triquetra.rt_partner
		p[A] = S
		local old = p[S]
		if old ~= nil and old ~= A then dsm[S] = old end
	end
	if T then
		triquetra.displacement_ternary_map[A .. "-swap"] = T
	end
end
'''

def build(name, mode, own_slot):
    d = V + "/" + name
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(C, d)
    r, h = d + R, d + HK
    sub(r, "local M = {}\n", "local M = {}\n" + HELPER % (mode, "true" if own_slot else "false"))
    sub(r, '''			triquetra.displacement_secondary_map[triquetra.current_slot] = triquetra.secondary_slot
			if triquetra.ternary_slot then
				triquetra.displacement_ternary_map[triquetra.current_slot .. "-swap"] = triquetra.ternary_slot
			end
''', '''			M.rt_secondary_notes(triquetra) -- RT
''')
    sub(r, '''	if remembered_relationship == nil or remembered_relationship == triquetra.ternary_slot then''',
        '''	local rt_skip = triquetra.ternary_slot
	if RT_OWN_SLOT then rt_skip = triquetra[type .. "_slot"] end -- RT: compare with the restored type's own slot
	if remembered_relationship == nil or remembered_relationship == rt_skip then''')
    sub(h, '''	if triquetra.secondary_slot == new_filehash then
		triquetra.secondary_slot = triquetra.current_slot
''', '''	if triquetra.secondary_slot == new_filehash then
		routines.rt_secondary_notes(triquetra) -- RT: D8, the same notes as <M-f>
		if triquetra.displacement_ternary_map[triquetra.ternary_slot] == new_filehash then -- RT: Q6's guard, before the swap
			triquetra.displacement_ternary_map[triquetra.ternary_slot] = triquetra.current_slot
			vim.notify("Avoided conflict of ternary's remembered relationship becoming current. (plain navigation onto the secondary)", vim.log.levels.WARN)
		end
		triquetra.secondary_slot = triquetra.current_slot
''')

only = sys.argv[1:] 
for name, mode, own in [("rt_base", "base", False), ("rt_c1", "c1", False), ("rt_c1s", "c1", True),
                        ("rt_c2a", "c2a", False), ("rt_c2b", "c2b", False), ("rt_c3", "c3", False), ("rt_c3k", "c3k", True), ("rt_c1sg", "c1g", True), ("rt_c3kg", "c3kg", True)]:
    if only and name not in only: continue
    build(name, mode, own)
    if mode in ("c1g", "c3kg"):  # the options: graduation also clears the graduated buffer's secondary swap note
        sub(V + "/" + name + R, """			triquetra.displacement_secondary_map[triquetra.secondary_slot] =
				triquetra.displacement_ternary_map[triquetra.secondary_slot]
""", """			triquetra.displacement_secondary_map[triquetra.secondary_slot] =
				triquetra.displacement_ternary_map[triquetra.secondary_slot]
			triquetra.displacement_secondary_map[triquetra.secondary_slot .. "-swap"] = nil -- RT: graduation clears the swap note
""")
    print("built", name)
