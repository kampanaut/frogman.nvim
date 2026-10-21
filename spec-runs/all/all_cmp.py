#!/usr/bin/env python3
"""ALL: compare two walk files step for step (same generator, same seed). File hashes in messages are masked.
Usage: all_cmp.py a.jsonl b.jsonl [--fields c,s,t,...] [--ignore view,...]   Prints: walks compared, walks that differ, first divergences."""
import json, re, sys
H = re.compile(r"[0-9a-f]{16}")
IGN = sys.argv[sys.argv.index("--ignore") + 1].split(",") if "--ignore" in sys.argv else []
def strip(x):
    if isinstance(x, dict): return {k: strip(v) for k, v in x.items() if k not in IGN}
    if isinstance(x, list): return [strip(v) for v in x]
    return x
def norm(x): return strip(json.loads(H.sub("#", json.dumps(x, sort_keys=True))))
a, b = sys.argv[1], sys.argv[2]
fields = None
if "--fields" in sys.argv: fields = sys.argv[sys.argv.index("--fields") + 1].split(",")
diff = []; n = 0
for wi, (la, lb) in enumerate(zip(open(a), open(b))):
    wa, wb = json.loads(la), json.loads(lb); n += 1
    assert wa["seq"] == wb["seq"], ("different walks", wi)
    for i, (sa, sb) in enumerate(zip(wa["steps"], wb["steps"])):
        if fields: sa = {k: sa["st"].get(k) for k in fields}; sb = {k: sb["st"].get(k) for k in fields}
        if norm(sa) != norm(sb):
            da, db = norm(sa), norm(sb)
            keys = sorted(set(da.get("st", da)) | set(db.get("st", db))) if not fields else fields
            sta, stb = da.get("st", da), db.get("st", db)
            what = [k for k in keys if sta.get(k) != stb.get(k)] + [k for k in ("notes", "err", "ok") if da.get(k) != db.get(k)]
            diff.append((wi, i, wa["seq"][i], what)); break
    if len(wa["steps"]) != len(wb["steps"]) and (not diff or diff[-1][0] != wi): diff.append((wi, -1, "len", []))
print(f"{a.split('/')[-1]} vs {b.split('/')[-1]}: {n} walks, {len(diff)} differ")
for d in diff[:8]: print("  walk", d[0], "step", d[1] + 1, "key", d[2], "differs in", d[3])
