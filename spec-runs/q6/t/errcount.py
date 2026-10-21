#!/usr/bin/env python3
"""Count errors per variant over the same random sequences as diff.py. Usage: errcount.py <n> <len> <seed> <variants>"""
import json, os, random, subprocess, sys, itertools, re, collections
from concurrent.futures import ThreadPoolExecutor
Q6 = "@RUNS@/q6"
n, L, seed = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]); vs = sys.argv[4].split(",")
ACTS = ["ea", "eb", "ec", "ed", "ee"] * 2 + ["F"] * 4 + ["G"] * 3 + ["R", "S", "X1", "X2", "X3", "P", "J"]
rng = random.Random(seed)
seqs = [["ea"] + [rng.choice(ACTS) for _ in range(L - 1)] for _ in range(n)]
cnt = itertools.count()
def run(v, seq):
    p = subprocess.run([f"{Q6}/t/runseq.sh", f"e{v}-{os.getpid()}-{next(cnt)}", f"{Q6}/variants/{v}", " ".join(seq)], stdout=subprocess.PIPE, timeout=120)
    return [json.loads(l) for l in p.stdout.decode(errors="replace").splitlines() if l.startswith("{")]
for v in vs:
    with ThreadPoolExecutor(16) as ex: res = list(ex.map(lambda s: run(v, s), seqs))
    c = collections.Counter(); seqs_with = collections.Counter()
    for rs in res:
        kinds = set()
        for r in rs:
            if r.get("err"):
                k = re.sub(r"^.*?:\d+: ", "", r["err"])[:70]; c[k] += 1; kinds.add(k)
        for k in kinds: seqs_with[k] += 1
    print(f"variant {v}:")
    for k, x in c.most_common(): print(f"   {x:4} errors in {seqs_with[k]:4} seqs  {k}")
