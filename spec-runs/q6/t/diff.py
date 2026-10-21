#!/usr/bin/env python3
"""Differential run: random sequences under two variants, compare every step's state, error and notes.
Usage: diff.py <varA> <varB> <n> <len> [seed]"""
import json, os, random, subprocess, sys, itertools
from concurrent.futures import ThreadPoolExecutor
Q6 = "@RUNS@/q6"
va, vb, n, L = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
seed = int(sys.argv[5]) if len(sys.argv) > 5 else 1
ACTS = ["ea", "eb", "ec", "ed", "ee"] * 2 + ["F"] * 4 + ["G"] * 3 + ["R", "S", "X1", "X2", "X3", "P", "J"]
cnt = itertools.count()
def run(v, seq):
    p = subprocess.run([f"{Q6}/t/runseq.sh", f"d{v}-{os.getpid()}-{next(cnt)}", f"{Q6}/variants/{v}", " ".join(seq)], stdout=subprocess.PIPE, timeout=120)
    return [json.loads(l) for l in p.stdout.decode(errors="replace").splitlines() if l.startswith("{")]
def norm(r):
    import re
    notes = [re.sub(r"[0-9a-f]{16}", "<h>", x["m"]) for x in r["notes"] if "Avoided conflict" not in x["m"]]
    err = re.sub(r":\d+:", ":N:", (r.get("err") or "").split("/lua/", 1)[-1])
    return json.dumps([r["st"], err, notes], sort_keys=True)
rng = random.Random(seed)
seqs = [["ea"] + [rng.choice(ACTS) for _ in range(L - 1)] for _ in range(n)]
def job(seq):
    a, b = run(va, seq), run(vb, seq)
    if len(a) != len(seq) or len(b) != len(seq): return ("runfail", seq, None)
    warnsec = sum(1 for i, r in enumerate(a) if any("Avoided conflict" in x["m"] for x in r["notes"]) and (r["a"] in ("F", "J") or (r["a"].startswith("X") and i > 0 and a[i-1]["st"].get("s") == r["st"].get("c"))))
    for i, (x, y) in enumerate(zip(a, b)):
        if norm(x) != norm(y): return ("diff", seq, i, warnsec)
    return ("same", seq, None, warnsec)
with ThreadPoolExecutor(16) as ex: res = list(ex.map(job, seqs))
import collections
c = collections.Counter(r[0] for r in res)
print(f"{va} vs {vb}: {dict(c)}; sequences where the secondary fall-through warned in {va}: {sum(1 for r in res if r[0] != 'runfail' and r[3])}, total such warnings {sum(r[3] for r in res if r[0] != 'runfail')}")
for r in res:
    if r[0] == "diff":
        print("  first diff at step", r[2] + 1, ":", " ".join(r[1]))
        break
