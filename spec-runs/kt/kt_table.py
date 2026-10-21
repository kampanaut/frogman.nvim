#!/usr/bin/env python3
"""One line per (variant, seed) with the KT numbers. Usage: kt_table.py variant[,variant...] seed[,seed...]"""
import json, sys, collections
W = "@RUNS@/rt/walks"
vs, seeds = sys.argv[1].split(","), sys.argv[2].split(",")
print("variant | seed | ternary throws (walks) | secondary throws (walks) | other errors | hook failures | ternary fires: total / to a buffer / to the secondary / to nothing / unchanged | secondary fires: rewrite / drop | RT drop fires | duplicate slots | self-naming notes")
for v in vs:
    for sd in seeds:
        c = collections.Counter(); wt = set(); ws = set()
        for wi, line in enumerate(open(f"{W}/{v}-1500-25-{sd}.jsonl")):
            w = json.loads(line)
            if len(w["steps"]) != len(w["seq"]): c["runfail"] += 1
            for i, s in enumerate(w["steps"]):
                st = s["st"]; err = s.get("err") or ""
                if "is the same as current ternary" in err: c["tt"] += 1; wt.add(wi)
                elif "is the same as current secondary" in err: c["ts"] += 1; ws.add(wi)
                elif err: c["oerr"] += 1
                for n in s["notes"]:
                    m = n["m"]
                    if m.startswith("Hook '") or "Duplicates detected" in m: c["hook"] += 1
                    if m.startswith("KT-t "):
                        c["kt"] += 1
                        note, new = m.split(" ", 3)[3].split(" => ")
                        if new == "-": c["kt_nil"] += 1
                        elif new == note.split(">")[1]: c["kt_same"] += 1
                        elif new == (st.get("s") or "-").replace(".txt", ""): c["kt_sec"] += 1
                        else: c["kt_buf"] += 1
                    if m.startswith("KT-s "): c["ks_" + m.split(" ")[2]] += 1
                    if m.startswith("RT-bonus: dropped"): c["tb"] += 1
                cc, t, s2 = st.get("c"), st.get("t"), st.get("s")
                if (cc not in (None, "-") and (cc == t or cc == s2)) or (t not in (None, "-") and t == s2): c["dup"] += 1
                for mk in ("dtm", "dsm"):
                    if isinstance(st.get(mk), dict) and any(k.replace("-swap", "") == x for k, x in st[mk].items()): c["self"] += 1
        print(f"{v} | {sd} | {c['tt']} ({len(wt)}) | {c['ts']} ({len(ws)}) | {c['oerr']} | {c['hook']} | {c['kt']} / {c['kt_buf']} / {c['kt_sec']} / {c['kt_nil']} / {c['kt_same']} | {c['ks_rw']} / {c['ks_drop']} | {c['tb']} | {c['dup']} | {c['self']}" + (f" | RUNFAIL {c['runfail']}" if c["runfail"] else ""))
