#!/usr/bin/env python3
"""Run sequences under variants and print a compact trace. Usage: cmp.py "<seq>" [from_step] [variants]"""
import json, subprocess, sys, os
Q6 = "@RUNS@/q6"
seq = sys.argv[1]; frm = int(sys.argv[2]) if len(sys.argv) > 2 else 1
vs = sys.argv[3].split(",") if len(sys.argv) > 3 else ["A", "B", "C"]
def fmt(m):
    return ",".join(f"{k}>{v}" for k, v in sorted(m.items())).replace(".txt", "") if isinstance(m, dict) else ""
for v in vs:
    p = subprocess.run([f"{Q6}/t/runseq.sh", f"cmp-{v}-{os.getpid()}", f"{Q6}/variants/{v}", seq], stdout=subprocess.PIPE)
    print(f"--- variant {v}: {seq}")
    for l in p.stdout.decode().splitlines():
        if not l.startswith("{"): continue
        r = json.loads(l); st = r["st"]
        if r["i"] < frm: continue
        print(f"  {r['i']:2} {r['a']:3} c={st['c']} s={st['s']} t={st['t']} dtm={{{fmt(st['dtm'])}}} dsm={{{fmt(st['dsm'])}}}".replace(".txt", ""))
        for n in r["notes"]:
            if n.get("l") and n["l"] >= 3: print("        WARN", n["m"][:150])
            elif "Restored" in n["m"]: print("        INFO", n["m"][:20], "...", n["m"].split("(")[-1])
        if r.get("err"): print("        ERR", r["err"].split(": ", 1)[-1][:120])
