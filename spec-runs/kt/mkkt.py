#!/usr/bin/env python3
"""KT: "Keep the older one", the ternary half (and the secondary half on the other arrivals).
Builds, as copies under spec/variants/ (never the repo):
  kt_literal     rt_c3kga + the stale-note check in navigation's rewrite on every arrival that skips it,
                 with navigation's two cases taken as worded (on arrivals that keep the ternary, case 2 is a no-op)
  kt_rewrite     the same, with the kept ternary's own plain note as the older one on arrivals that keep the ternary
  kt_drop        the same call sites, dropping the note instead (a drop on the same base, for comparison)
  kt_rewrite_sec kt_rewrite + the secondary side: rt_sec_check rewrites to dsm[x-swap] when that is an older partner,
                 and drops only when none is known
Every firing is counted through vim.notify (captured by the harness), marker "KT-t" / "KT-s"."""
import os, shutil, sys
ONLY = sys.argv[1:]  # build only these (default: all)
V = "@RUNS@/variants"
W = "/lua/cavediver/domains/window/"
def sub(p, old, new):
    s = open(p).read(); assert s.count(old) == 1, (p, old[:70], s.count(old)); open(p, "w").write(s.replace(old, new))

HELPER = '''-- KT (sandbox only): "Keep the older one" for the ternary memory, on every arrival that skips the stale-note
-- check in navigation (hooks.lua, displacement_mangement). N arrives, A is left, T0 is the ternary before the
-- arrival, T1 the ternary after it. When N's plain ternary note names T1, it is rewritten, after the arrival's
-- own writes (the order navigation uses):
--   T1 is A and N was the ternary -> dtm[A], the pre-jump stored ternary      (navigation's first case)
--   T1 is A and N was not         -> T0, the pre-jump ternary                 (navigation's second case)
--   T1 is T0 (the ternary stays)  -> "literal": T0 again (the second case as worded: no change)
--                                    "kept":    dtm[T0], the kept ternary's own plain note
-- KT_MODE "drop" drops the note on every one of these arrivals instead (the same-base comparison for dropping).
local KT_MODE = "%s"
local function kt_nm(h)
	if h == nil then return "-" end
	local n = _G.NAME and _G.NAME(h) or h:sub(1, 6)
	return (n:gsub("%%.txt", ""))
end
function M.kt_ter_rewrite(triquetra, kind, N, A, T0, T1)
	local dtm = triquetra.displacement_ternary_map
	if N == nil or T1 == nil or dtm[N] ~= T1 then return end
	local new, case
	if KT_MODE == "drop" then
		new, case = nil, "drop"
	elseif T1 == A then
		if N == T0 then new, case = dtm[A], "c1" else new, case = T0, "c2" end
	elseif KT_MODE == "literal" then
		new, case = T0, "c2="
	else
		new, case = dtm[T0], "kept"
	end
	dtm[N] = new
	vim.notify(string.format("KT-t %%s %%s %%s>%%s => %%s", kind, case, kt_nm(N), kt_nm(T1), kt_nm(new)), vim.log.levels.DEBUG)
end

'''

def build_ter(dst, mode):
    d = V + "/" + dst
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(V + "/rt_c3kga", d)
    r, h = d + W + "routines.lua", d + W + "hooks.lua"
    sub(r, "-- RT: drop the current buffer's plain secondary note when it names the window's secondary.\n",
        HELPER % mode + "-- RT: drop the current buffer's plain secondary note when it names the window's secondary.\n")
    # 1. reconcile_triquetra: <M-S-f>, <M-f> and its fallback, cycling picks. Capture at the top, rewrite at the end.
    sub(r, '''	if triquetra and triquetra.current_slot ~= new_filehash then
		M.rt_sec_check(''', '''	if triquetra and triquetra.current_slot ~= new_filehash then
		local kt_A, kt_T0, kt_S0 = triquetra.current_slot, triquetra.ternary_slot, triquetra.secondary_slot -- KT
		M.rt_sec_check(''')
    sub(r, '''					.. "]", vim.log.levels.WARN)
			end
			triquetra.current_slot = new_filehash
		end
	end
end''', '''					.. "]", vim.log.levels.WARN)
			end
			triquetra.current_slot = new_filehash
		end
		M.kt_ter_rewrite(triquetra, (new_filehash == kt_T0) and "ter" or ((new_filehash == kt_S0) and "sec" or "out"),
			new_filehash, kt_A, kt_T0, (new_filehash == kt_T0) and kt_A or kt_T0) -- KT
	end
end''')
    # 2. primary jump: its reconcile_triquetra call finds current already set, so it gets its own call.
    sub(r, '''	if triquetra.current_slot ~= triquetra.primary_buffer[1] then -- We only do displacment if we are not already in the primary buffer.
		triquetra.displacement_ternary_map[triquetra.current_slot .. "-swap"] = triquetra.ternary_slot''',
        '''	if triquetra.current_slot ~= triquetra.primary_buffer[1] then -- We only do displacment if we are not already in the primary buffer.
		local kt_A, kt_T0 = triquetra.current_slot, triquetra.ternary_slot -- KT
		triquetra.displacement_ternary_map[triquetra.current_slot .. "-swap"] = triquetra.ternary_slot''')
    sub(r, '''		triquetra.current_slot = triquetra.primary_buffer[1]
		M.rt_sec_check(triquetra, triquetra.current_slot, triquetra.secondary_slot) -- RT
''', '''		triquetra.current_slot = triquetra.primary_buffer[1]
		M.rt_sec_check(triquetra, triquetra.current_slot, triquetra.secondary_slot) -- RT
		M.kt_ter_rewrite(triquetra, "prim", triquetra.current_slot, kt_A, kt_T0, kt_A) -- KT
''')
    # 3. plain navigation onto the secondary: navigation's own check sits in the other branch.
    sub(h, '''	if triquetra.secondary_slot == new_filehash then
		routines.rt_secondary_notes(triquetra) -- RT: D8, the same notes as <M-f>''', '''	if triquetra.secondary_slot == new_filehash then
		local kt_A, kt_T0 = triquetra.current_slot, triquetra.ternary_slot -- KT
		routines.rt_secondary_notes(triquetra) -- RT: D8, the same notes as <M-f>''')
    sub(h, '''		triquetra.secondary_slot = triquetra.current_slot
		triquetra.current_slot = new_filehash
	elseif triquetra.current_slot ~= new_filehash then''', '''		triquetra.secondary_slot = triquetra.current_slot
		triquetra.current_slot = new_filehash
		routines.kt_ter_rewrite(triquetra, "e-sec", new_filehash, kt_A, kt_T0, kt_T0) -- KT
	elseif triquetra.current_slot ~= new_filehash then''')
    print("built", dst)

for _n, _m in (("kt_literal", "literal"), ("kt_rewrite", "kept"), ("kt_drop", "drop")):
    if not ONLY or _n in ONLY: build_ter(_n, _m)
if ONLY and "kt_rewrite_sec" not in ONLY: sys.exit(0)

# kt_rewrite_sec: the secondary side on the other arrivals rewrites instead of dropping, when an older partner is known.
d = V + "/kt_rewrite_sec"
if os.path.exists(d): shutil.rmtree(d)
shutil.copytree(V + "/kt_rewrite", d)
r, h = d + W + "routines.lua", d + W + "hooks.lua"
sub(r, '''function M.rt_sec_check(triquetra, x, s)
	local dsm = triquetra.displacement_secondary_map
	if x and s and dsm[x] == s then dsm[x] = nil end
end''', '''-- KT: "Keep the older one" for the secondary memory on the other arrivals: rewrite x's stale plain note to the
-- older partner when one is known (x's swap note, when it differs from the secondary), else drop it.
-- site: where it ran; s0: the secondary slot's occupant before this event (logged as a candidate only).
function M.rt_sec_check(triquetra, x, s, site, s0)
	local dsm = triquetra.displacement_secondary_map
	if x and s and dsm[x] == s then
		local older = dsm[x .. "-swap"]
		local out
		if older ~= nil and older ~= s and older ~= x then dsm[x] = older; out = "rw" else dsm[x] = nil; out = "drop" end
		vim.notify(string.format("KT-s %s %s %s>%s => %s swap=%s prev=%s", site or "?", out, kt_nm(x), kt_nm(s),
			kt_nm(dsm[x]), kt_nm(older), kt_nm(s0)), vim.log.levels.DEBUG)
	end
end''')
sub(r, '''		M.rt_sec_check(triquetra, new_filehash, (triquetra.secondary_slot == new_filehash) and triquetra.current_slot or triquetra.secondary_slot) -- RT''',
    '''		M.rt_sec_check(triquetra, new_filehash, (triquetra.secondary_slot == new_filehash) and triquetra.current_slot or triquetra.secondary_slot,
			(new_filehash == triquetra.ternary_slot) and "rec-ter" or ((new_filehash == triquetra.secondary_slot) and "rec-sec" or "rec-out"),
			triquetra.secondary_slot) -- RT''')
sub(r, '''			M.rt_sec_check(triquetra, triquetra.current_slot, triquetra.secondary_slot) -- RT
			vim.notify("Secondary buffer set to ternary slot. Ternary slot graduated.", vim.log.levels.INFO)''',
    '''			M.rt_sec_check(triquetra, triquetra.current_slot, triquetra.secondary_slot, "grad", nil) -- RT
			vim.notify("Secondary buffer set to ternary slot. Ternary slot graduated.", vim.log.levels.INFO)''')
sub(r, '''		M.rt_sec_check(triquetra, triquetra.current_slot, triquetra.secondary_slot) -- RT
		M.kt_ter_rewrite(''', '''		M.rt_sec_check(triquetra, triquetra.current_slot, triquetra.secondary_slot, "prim", triquetra.secondary_slot) -- RT
		M.kt_ter_rewrite(''')
sub(r, '''				M.rt_sec_check(triquetra, triquetra.current_slot, triquetra.secondary_slot) -- RT''',
    '''				M.rt_sec_check(triquetra, triquetra.current_slot, triquetra.secondary_slot, "ter-restore", triquetra.ternary_slot) -- RT''')
sub(h, '''		routines.rt_sec_check(triquetra, new_filehash, triquetra.secondary_slot) -- RT''',
    '''		routines.rt_sec_check(triquetra, new_filehash, triquetra.secondary_slot, "nav", triquetra.secondary_slot) -- RT''')
print("built kt_rewrite_sec")
