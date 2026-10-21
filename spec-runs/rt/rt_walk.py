#!/usr/bin/env python3
"""Random walks, same generator as q6/t/errcount.py (n, len, seed, ACTS), saved per variant as JSONL.
Usage: rt_walk.py <n> <len> <seed> <variant[,variant]>   variant 'today' = the repo, else spec/variants/<name>."""
import json, os, random, subprocess, sys, itertools
from concurrent.futures import ThreadPoolExecutor
SPEC = "@RUNS@"
REPO = "@REPO@"
n, L, seed = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]); vs = sys.argv[4].split(",")
ACTS = ["ea", "eb", "ec", "ed", "ee"] * 2 + ["F"] * 4 + ["G"] * 3 + ["R", "S", "X1", "X2", "X3", "P", "J"]
rng = random.Random(seed)
seqs = [["ea"] + [rng.choice(ACTS) for _ in range(L - 1)] for _ in range(n)]
cnt = itertools.count()
def run(v, seq):
    plugin = REPO if v == "today" else f"{SPEC}/variants/{v}"
    p = subprocess.run([f"{SPEC}/rt/rt_runseq.sh", f"{v}-{os.getpid()}-{next(cnt)}", plugin, " ".join(seq)], stdout=subprocess.PIPE, timeout=120)
    return [json.loads(l) for l in p.stdout.decode(errors="replace").splitlines() if l.startswith("{")]
os.makedirs(f"{SPEC}/rt/walks", exist_ok=True)
for v in vs:
    with ThreadPoolExecutor(15) as ex: res = list(ex.map(lambda s: run(v, s), seqs))
    with open(f"{SPEC}/rt/walks/{v}-{n}-{L}-{seed}.jsonl", "w") as f:
        for seq, rs in zip(seqs, res): f.write(json.dumps({"seq": seq, "steps": rs}) + "\n")
    bad = sum(1 for seq, rs in zip(seqs, res) if len(rs) != len(seq))
    print(v, "done, runfail", bad, flush=True)
