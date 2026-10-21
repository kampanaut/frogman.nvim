#!/usr/bin/env python3
"""EX: restores under a variant against the drop (ex_c), on the same walks (same seed, view, generator).
Usage: ex_pair.py <variant-file.jsonl> <ex_c-file.jsonl>
For every <M-;><M-r> (R) and <M-;><M-t> (S) step whose outcome differs between the two:
  'same slots before' = the current window and its (current, secondary, ternary) were the same before the key,
  so the difference comes from the notes alone; otherwise the walks had already diverged.
Outcomes: outside (restores a buffer from outside the slots), exchange (with the other slot), none ("No ... found"),
throw, error, other.  Also: walks whose states ever differ, and the first EX-t firing that made them differ."""
import json, sys, collections
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from ex_scan import restore_outcome, cur

fa, fc = sys.argv[1], sys.argv[2]
same = collections.Counter(); div = collections.Counter(); differ_walks = 0; first_site = collections.Counter()
ex = {}
for la, lc in zip(open(fa), open(fc)):
    wa, wc = json.loads(la), json.loads(lc)
    assert wa["seq"] == wc["seq"]
    sa, sc = wa["steps"], wc["steps"]
    seen = False
    for i in range(min(len(sa), len(sc))):
        a = sa[i]["a"]
        if not seen and json.dumps(sa[i]["st"], sort_keys=True) != json.dumps(sc[i]["st"], sort_keys=True):
            seen = True; differ_walks += 1
            sites = [n["m"].split()[1] for n in sa[i]["notes"] if n["m"].startswith("EX-t ")] + \
                    [n["m"].split()[1] for n in sc[i]["notes"] if n["m"].startswith("EX-t ")]
            first_site[(a, ",".join(sorted(set(sites))) or "-")] += 1
        if a not in ("R", "S"): continue
        pa = cur(sa[i - 1]["st"]) if i else None; pc = cur(sc[i - 1]["st"]) if i else None
        oa, oc = restore_outcome(a, sa[i], pa), restore_outcome(a, sc[i], pc)
        if oa == oc: continue
        key = lambda p: (p.get("w"), p.get("c"), p.get("s"), p.get("t")) if p else None
        if key(pa) == key(pc):
            same[(a, oa, oc)] += 1
            ex.setdefault((a, oa, oc), " ".join(wa["seq"][:i + 1]))
        else:
            div[(a, oa, oc)] += 1
print(f"== {fa.split('/')[-1]} vs {fc.split('/')[-1]}: walks whose states differ: {differ_walks}")
print("  first difference at (key, EX-t sites):", dict(first_site))
print("  same slots before, outcome differs (key, variant, drop):")
for k, v in sorted(same.items(), key=lambda x: -x[1]): print(f"    {k[0]}  {k[1]:<9} vs {k[2]:<9} {v}   e.g. {ex[k]}")
print("  already diverged, outcome differs:")
for k, v in sorted(div.items(), key=lambda x: -x[1]): print(f"    {k[0]}  {k[1]:<9} vs {k[2]:<9} {v}")
