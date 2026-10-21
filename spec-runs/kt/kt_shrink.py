#!/usr/bin/env python3
"""Greedy shrink of a walk under one variant while a named predicate holds on its steps.
Usage: kt_shrink.py <variant> "<seq>" <predicate>
Predicates:
  throw_t   the last step throws the ternary restore error, no earlier error
  tosec     a ternary rewrite named the secondary, and the last step (<M-;><M-r>) restores that secondary into the ternary
  secrw     a secondary rewrite (not a drop) fired, and the last step is <M-;><M-t>
  secgain   the last step (<M-;><M-t>) restores under this variant and finds nothing under kt_rewrite"""
import json, subprocess, sys, os
SPEC = "@RUNS@"
v, seq, pred = sys.argv[1], sys.argv[2].split(), sys.argv[3]
plugin = f"{SPEC}/variants/{v}"
n = [0]
def run(sq, pl=None):
    n[0] += 1
    p = subprocess.run([f"{SPEC}/rt/rt_runseq.sh", f"ktshrink-{os.getpid()}-{n[0]}", pl or plugin, " ".join(sq)], stdout=subprocess.PIPE, timeout=120)
    return [json.loads(l) for l in p.stdout.decode(errors="replace").splitlines() if l.startswith("{")]
def ok(sq):
    rs = run(sq)
    if len(rs) != len(sq) or any((r.get("err") or "") for r in rs[:-1]): return False
    if any(any("Cannot populate" in x["m"] or "No ternary buffer" in x["m"] for x in r["notes"]) for r in rs): return False
    last = rs[-1]; notes = " ".join(x["m"] for x in last["notes"])
    if pred == "throw_t":
        return "Remembered ternary is the same" in (last.get("err") or "")
    if pred == "tosec":
        if sq[-1] != "R" or "Restored ternary" not in notes: return False
        pv = rs[-2]["st"]
        y = pv.get("s")
        hit = any(any(x["m"].startswith("KT-t ") and x["m"].endswith("=> " + (r["st"].get("s") or "").replace(".txt", "")) for x in r["notes"]) for r in rs[:-1])
        return hit and last["st"].get("t") == y
    if pred == "secrw":
        return sq[-1] == "S" and any(any(x["m"].startswith("KT-s ") and " rw " in x["m"] for x in r["notes"]) for r in rs[:-1])
    if pred == "secgain":
        if sq[-1] != "S" or "Restored secondary" not in notes: return False
        other = run(sq, f"{SPEC}/variants/kt_rewrite")
        return len(other) == len(sq) and any("No secondary relationship" in x["m"] for x in other[-1]["notes"])
    raise SystemExit("unknown predicate")
assert ok(seq), "original does not satisfy the predicate"
changed = True
while changed:
    changed = False
    for i in range(1, len(seq) - 1):
        c = seq[:i] + seq[i+1:]
        if ok(c): seq = c; changed = True; break
print(" ".join(seq))
