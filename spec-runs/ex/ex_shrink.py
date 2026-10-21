#!/usr/bin/env python3
"""EX: greedy shrink of a walk while I23 is violated after its last step (and no step errors).
Usage: ex_shrink.py <variant|today> "<seq>" <view> <single|mw> [ter|sec|any|fire:<outcome>|dupcs]
  fire:<outcome>: instead, the last step fires the check at <M-;><M-t>'s exchange with that outcome (outside, secondary, nothing, guard)."""
import json, subprocess, sys, os
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from ex_scan import violations, windows
SPEC = "@RUNS@"
REPO = "@REPO@"
v, seq, view, gen = sys.argv[1], sys.argv[2].split(), sys.argv[3], sys.argv[4]
kind = sys.argv[5] if len(sys.argv) > 5 else "any"
plugin = REPO if v == "today" else f"{SPEC}/variants/{v}"
seqlua = f"{SPEC}/ex/ex_seq.lua" if gen == "single" else f"{SPEC}/ex/ex_seq_mw.lua"
n = [0]
def run(sq):
    n[0] += 1
    p = subprocess.run([f"{SPEC}/ex/ex_runseq.sh", f"exshrink-{os.getpid()}-{n[0]}", plugin, " ".join(sq), view, seqlua],
                       stdout=subprocess.PIPE, timeout=120)
    return [json.loads(l) for l in p.stdout.decode(errors="replace").splitlines() if l.startswith("{")]
def ok(sq):
    rs = run(sq)
    if len(rs) != len(sq) or any(r.get("err") for r in rs): return False
    if kind == "dupcs":  # the current window's current buffer is also its secondary
        st = rs[-1]["st"]
        return st.get("c") not in (None, "-") and st.get("c") == st.get("s")
    if kind.startswith("fire:"):
        return any(n["m"].startswith("EX-t S-exch") and n["m"].endswith(" " + kind[5:]) for n in rs[-1]["notes"])
    vs = set()
    for _, w in windows(rs[-1]["st"]): vs |= violations(w)
    return bool(vs) if kind == "any" else (kind in vs)
assert ok(seq), "original does not satisfy the predicate"
changed = True
while changed:
    changed = False
    for i in range(1, len(seq)):
        c = seq[:i] + seq[i + 1:]
        if ok(c): seq = c; changed = True; break
print(" ".join(seq))
