#!/usr/bin/env python3
"""Compare two variants' walks on the same sequences: for each restore step (<M-;><M-r> = R, <M-;><M-t> = S),
pair the two outcomes, and count walks whose states diverge at all.  Usage: kt_diff.py <A.jsonl> <B.jsonl> [R|S] [-v]"""
import json, sys, collections
a_path, b_path = sys.argv[1], sys.argv[2]
keys = [k for k in sys.argv[3:] if k in ("R", "S")] or ["R", "S"]
verbose = "-v" in sys.argv

def fix(st):
    for k in ("dsm", "dtm", "pt"):
        if not isinstance(st.get(k), dict): st[k] = {}
    return st

def outcome(s):
    st = fix(s["st"]); err = s.get("err") or ""
    notes = " ".join(n["m"] for n in s["notes"])
    if "is the same as current" in err: return "throws"
    if err: return "error"
    if "No ternary relationship" in notes or "No secondary relationship" in notes: return "nothing to restore"
    if "Restored" in notes:
        slot = "t" if s["a"] == "R" else "s"
        return "restores " + st[slot].replace(".txt", "")
    return "other"

pairs = collections.Counter(); ex = {}; diverge = 0; first_div = collections.Counter()
for wi, (la, lb) in enumerate(zip(open(a_path), open(b_path))):
    A, B = json.loads(la), json.loads(lb)
    assert A["seq"] == B["seq"]
    d = False
    for i, (sa, sb) in enumerate(zip(A["steps"], B["steps"])):
        fa, fb = fix(sa["st"]), fix(sb["st"])
        same = all(fa.get(k) == fb.get(k) for k in ("c", "s", "t", "dtm", "dsm"))
        if not same and not d:
            d = True; first_div[sa["a"]] += 1
        if sa["a"] in keys:
            oa, ob = outcome(sa), outcome(sb)
            if oa != ob:
                k = (sa["a"], oa.split(" ")[0] if oa.startswith("restores") else oa, ob.split(" ")[0] if ob.startswith("restores") else ob)
                pairs[k] += 1
                if k not in ex or len(ex[k][0]) > i + 1: ex[k] = (A["seq"][:i+1], oa, ob)
    diverge += d
print(f"{a_path.split('/')[-1]} vs {b_path.split('/')[-1]}: walks whose slots or notes diverge: {diverge}; first divergence at key: {dict(first_div)}")
for k, c in pairs.most_common():
    print(f"  {c:5}  {k[0]}: A {k[1]:20} B {k[2]:20}" + (f"   e.g. {' '.join(ex[k][0])}  ({ex[k][1]} / {ex[k][2]})" if verbose else ""))
