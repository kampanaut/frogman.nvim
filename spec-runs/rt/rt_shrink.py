#!/usr/bin/env python3
"""Greedy shrink: drop steps while the last step still throws the same restore error and a predicate holds.
Usage: rt_shrink.py <variant> "<seq>" [must-contain-action]"""
import json, subprocess, sys, os
SPEC = "@RUNS@"
REPO = "@REPO@"
v = sys.argv[1]; seq = sys.argv[2].split(); must = sys.argv[3] if len(sys.argv) > 3 else None
plugin = REPO if v == "today" else f"{SPEC}/variants/{v}"
n = [0]
def throws(sq):
    n[0] += 1
    p = subprocess.run([f"{SPEC}/rt/rt_runseq.sh", f"shrink-{os.getpid()}-{n[0]}", plugin, " ".join(sq)], stdout=subprocess.PIPE, timeout=120)
    rs = [json.loads(l) for l in p.stdout.decode(errors="replace").splitlines() if l.startswith("{")]
    if len(rs) != len(sq): return False
    if os.environ.get("NOTES_OK") is None and any(any("No ternary buffer" in n["m"] or "Cannot populate" in n["m"] for n in r["notes"]) for r in rs): return False
    e = rs[-1].get("err") or ""
    kind = "secondary" if sq[-1] == "S" else "ternary"
    return f"Remembered {kind} is the same" in e and not any((r.get("err") or "") for r in rs[:-1])
assert throws(seq), "original does not throw"
changed = True
while changed:
    changed = False
    for i in range(1, len(seq) - 1):
        c = seq[:i] + seq[i+1:]
        if must and must not in c[:-1]: continue
        if throws(c): seq = c; changed = True; break
print(" ".join(seq))
