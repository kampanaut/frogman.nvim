#!/usr/bin/env python3
"""Greedy shrink of a (multi-window) walk: drop steps while the last step still throws an error containing <needle>,
no earlier step errs, and the window keys stay valid (<C-w>p, :close, Y only with 2+ windows; at most 3 windows).
Usage: wv_shrink.py <variant> <view> "<seq>" <needle>"""
import json, subprocess, sys, os
SPEC = "@RUNS@"
REPO = "@REPO@"
v, view, seq, needle = sys.argv[1], sys.argv[2], sys.argv[3].split(), sys.argv[4]
plugin = REPO if v == "today" else f"{SPEC}/variants/{v}"
n = [0]
def valid(sq):
    nw = 1
    for a in sq:
        if a == "SP":
            if nw >= 3: return False
            nw += 1
        if a in ("WP", "CL", "Y1", "Y2") and nw < 2: return False
        if a == "CL": nw -= 1
    return True
def run(sq):
    n[0] += 1
    p = subprocess.run([f"{SPEC}/rt/rt_runseq_b.sh", f"wvshrink-{os.getpid()}-{n[0]}", plugin, " ".join(sq), view, f"{SPEC}/rt/rt_seq_mw.lua"], stdout=subprocess.PIPE, timeout=120)
    return [json.loads(l) for l in p.stdout.decode(errors="replace").splitlines() if l.startswith("{")]
def ok(sq):
    if not valid(sq): return False
    rs = run(sq)
    if len(rs) != len(sq) or any((r.get("err") or "") for r in rs[:-1]): return False
    return needle in (rs[-1].get("err") or "")
assert ok(seq), "original does not throw"
changed = True
while changed:
    changed = False
    for i in range(1, len(seq) - 1):
        c = seq[:i] + seq[i+1:]
        if ok(c): seq = c; changed = True; break
print(" ".join(seq))
