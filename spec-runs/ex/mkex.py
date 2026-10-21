#!/usr/bin/env python3
"""EX: the stale-note check wherever a slot changes under the current buffer without a buffer becoming current.
Builds, as copies under spec/variants/ (never the repo), from kt_rewrite_sec:
  ex_a  a stale ternary note becomes the new ternary's own plain note       (EX_MODE "own")
  ex_b  ... becomes the buffer that just left the ternary (now the secondary) (EX_MODE "left")
  ex_c  ... is dropped                                                       (EX_MODE "drop")
The secondary map keeps the decided rule in all three (rt_sec_check: its swap note when older, else dropped).
Every firing is logged through vim.notify at DEBUG, marker "EX-t" (ternary map); the secondary map logs "KT-s ex-<site>"."""
import os, shutil, sys
V = "@RUNS@/variants"
W = "/lua/cavediver/domains/window/"
def sub(p, old, new):
    s = open(p).read(); assert s.count(old) == 1, (p, old[:70], s.count(old)); open(p, "w").write(s.replace(old, new))

HELPER = '''
-- EX (sandbox only): the stale-note check where a slot changes under the current buffer x without a buffer
-- becoming current (the restores, graduation, the history fill), and after a cleanup pass that moved a slot.
-- Ternary map: when x's plain note names the ternary, it becomes, by EX_MODE:
--   "own"  : the new ternary's own plain note dtm[T]                                    (a)
--   "left" : t_left, the buffer that just left the ternary (at <M-;><M-t>'s exchange, the new secondary)  (b)
--   "drop" : nothing                                                                    (c)
-- A result naming x itself or T is dropped instead ("guard"). mode_override forces a rule (cleanup arrivals use
-- "own", the decided rule where the ternary stays put).
-- Secondary map: the decided rule, rt_sec_check (x's swap note when older, else dropped), in every mode.
local EX_MODE = "%s"
function M.ex_slot_check(triquetra, site, t_left, s_left, mode_override)
	local x = triquetra.current_slot
	if x == nil then return end
	local dtm = triquetra.displacement_ternary_map
	local T = triquetra.ternary_slot
	if T ~= nil and dtm[x] == T then
		local mode = mode_override or EX_MODE
		local new
		if mode == "own" then new = dtm[T] elseif mode == "left" then new = t_left else new = nil end
		local out
		if new ~= nil and (new == x or new == T) then out = "guard"; new = nil end
		dtm[x] = new
		out = out or ((new == nil) and "nothing" or ((new == triquetra.secondary_slot) and "secondary" or "outside"))
		vim.notify(string.format("EX-t %%s %%s %%s>%%s => %%s %%s", site, mode, kt_nm(x), kt_nm(T), kt_nm(new), out), vim.log.levels.DEBUG)
	end
	M.rt_sec_check(triquetra, x, triquetra.secondary_slot, "ex-" .. site, s_left)
end
'''

def build(dst, mode):
    d = V + "/" + dst
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(V + "/kt_rewrite_sec", d)
    r = d + W + "routines.lua"
    # the helper, after rt_sec_check
    sub(r, '''			kt_nm(dsm[x]), kt_nm(older), kt_nm(s0)), vim.log.levels.DEBUG)
	end
end
''', '''			kt_nm(dsm[x]), kt_nm(older), kt_nm(s0)), vim.log.levels.DEBUG)
	end
end
''' + HELPER % mode)
    # 1. both restores, every successful branch (exchanges included): after the restore's own write (:759)
    sub(r, '''	else
		local ui_get_basename = require('cavediver.domains.ui').routines.get_smart_basename
		if type == "ternary" then''', '''	else
		local ex_t0, ex_s0 = triquetra.ternary_slot, triquetra.secondary_slot -- EX
		local ui_get_basename = require('cavediver.domains.ui').routines.get_smart_basename
		if type == "ternary" then''')
    sub(r, '''		triquetra["displacement_" .. type .. "_map"][triquetra.current_slot] = current_relationship
	end
	loop_sm:to(loop_states.SELF)''', '''		triquetra["displacement_" .. type .. "_map"][triquetra.current_slot] = current_relationship
		local ex_exch = (triquetra.ternary_slot ~= ex_t0) and (triquetra.secondary_slot ~= ex_s0) -- EX
		M.ex_slot_check(triquetra, (type == "ternary" and "R" or "S") .. (ex_exch and "-exch" or ""),
			(triquetra.ternary_slot ~= ex_t0) and ex_t0 or nil, (triquetra.secondary_slot ~= ex_s0) and ex_s0 or nil) -- EX
	end
	loop_sm:to(loop_states.SELF)''')
    # 2. graduation, and 3. the history fill of an empty secondary
    sub(r, '''			M.rt_sec_check(triquetra, triquetra.current_slot, triquetra.secondary_slot, "grad", nil) -- RT
''', '''			M.rt_sec_check(triquetra, triquetra.current_slot, triquetra.secondary_slot, "grad", nil) -- RT
			M.ex_slot_check(triquetra, "grad", triquetra.secondary_slot, nil) -- EX
''')
    sub(r, '''			triquetra.secondary_slot = history.get_hash_from_buffer(history.data.ordered.crux[2].buf)
			vim.notify("Secondary buffer populated from history.", vim.log.levels.INFO)''',
        '''			triquetra.secondary_slot = history.get_hash_from_buffer(history.data.ordered.crux[2].buf)
			M.ex_slot_check(triquetra, "hist-fill", nil, nil) -- EX
			vim.notify("Secondary buffer populated from history.", vim.log.levels.INFO)''')
    # 4. cleanup: for each window whose (current, secondary, ternary) the pass itself changed
    sub(r, '''function M.cleanup_triquetras(bufnr_ondelete)
	local set_cache_from_window_triquetra = require("cavediver").ui.routines.set_cache_from_window_triquetra
''', '''function M.cleanup_triquetras(bufnr_ondelete)
	local set_cache_from_window_triquetra = require("cavediver").ui.routines.set_cache_from_window_triquetra
	local ex_before = {} -- EX
	for w, t in pairs(data.crux) do ex_before[w] = { t.current_slot, t.secondary_slot, t.ternary_slot } end -- EX
''')
    sub(r, '''				data.unregister_triquetra(winid)
			end
		end

		set_cache_from_window_triquetra(winid)
		::continue::
	end
end
''', '''				data.unregister_triquetra(winid)
			end
		end

		set_cache_from_window_triquetra(winid)
		::continue::
	end
	for w, t in pairs(data.crux) do -- EX: only windows this pass moved
		local b = ex_before[w]
		if b and (b[1] ~= t.current_slot or b[2] ~= t.secondary_slot or b[3] ~= t.ternary_slot) then
			M.ex_slot_check(t, (b[1] ~= t.current_slot) and "cleanup-arrive" or "cleanup",
				(b[3] ~= t.ternary_slot) and b[3] or nil, (b[2] ~= t.secondary_slot) and b[2] or nil,
				(b[1] ~= t.current_slot) and "own" or nil)
		end
	end
end
''')

ONLY = sys.argv[1:]
for name, mode in (("ex_a", "own"), ("ex_b", "left"), ("ex_c", "drop")):
    if ONLY and name not in ONLY: continue
    build(name, mode); print("built", name, mode)
