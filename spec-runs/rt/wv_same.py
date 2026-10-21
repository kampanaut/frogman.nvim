#!/usr/bin/env python3
"""Step-by-step comparison of two walk files (same seqs), ignoring file hashes in messages and the 'view' field.
Usage: wv_same.py <a.jsonl> <b.jsonl>   Prints walks equal / total, steps equal / total, and the first few differences."""
import json, re, sys
def norm(x):
    x = json.loads(re.sub(r"[0-9a-f]{16}", "#", x))
    for s in x["steps"]:
        s["st"].pop("view", None)
    return x
A = [norm(l) for l in open(sys.argv[1])]; B = [norm(l) for l in open(sys.argv[2])]
assert [x["seq"] for x in A] == [x["seq"] for x in B], "different sequences"
we = sum(x == y for x, y in zip(A, B)); se = sum(s == t for x, y in zip(A, B) for s, t in zip(x["steps"], y["steps"]))
st = sum(max(len(x["steps"]), len(y["steps"])) for x, y in zip(A, B))
print(f"walks equal {we}/{len(A)}, steps equal {se}/{st}")
shown = 0
for wi, (x, y) in enumerate(zip(A, B)):
    for i, (s, t) in enumerate(zip(x["steps"], y["steps"])):
        if s != t:
            print("  first difference: walk", wi, "step", i + 1, x["seq"][i]); shown += 1; break
    if shown >= 5: break
