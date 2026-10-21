#!/usr/bin/env python3
"""ALL copy of ex/ex_walk_rh.py (itself rt/rt_walk_b.py's generator, unchanged, plus the restore-heavy mix).
Output to spec/all/walks/, runner all/all_runseq.sh, jobs under spec/alljobs/.
Differences from the EX copy: the job dir is <variant>-<view>-<gen>-<seed>-<walk index>, so a re-run uses the same
paths (the file hashes depend on them); $ALL_TAG is appended to the output file name for repeat runs; $ALL_JOBPFX prefixes the job dirs (other paths, so other file hashes).
Usage: all_walk.py <n> <len> <seed> <variant[,variant]> <view> <gen: single|mw|mwy|rheavy>"""
import json, os, random, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
SPEC = "@RUNS@"
REPO = "@REPO@"
n, L, seed = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]); vs = sys.argv[4].split(","); view = sys.argv[5]
gen = sys.argv[6]
tag = os.environ.get("ALL_TAG", "")
assert view in ("global", "window") and gen in ("single", "mw", "mwy", "rheavy")
ACTS = ["ea", "eb", "ec", "ed", "ee"] * 2 + ["F"] * 4 + ["G"] * 3 + ["R", "S", "X1", "X2", "X3", "P", "J"]
MAXWIN = 3
rng = random.Random(seed)
if gen == "rheavy":  # the same keys with three more of each restore (R, S at 4/30 each instead of 1/24)
    ACTS2 = ACTS + ["R", "S"] * 3
    seqs = [["ea"] + [rng.choice(ACTS2) for _ in range(L - 1)] for _ in range(n)]
    seqlua = f"{SPEC}/ex/ex_seq.lua"
elif gen == "single":
    seqs = [["ea"] + [rng.choice(ACTS) for _ in range(L - 1)] for _ in range(n)]
    seqlua = f"{SPEC}/ex/ex_seq.lua"
else:
    EXTRA = ["SP"] * 2 + ["WP"] * 3 + ["CL"] + (["Y1", "Y2"] if gen == "mwy" else [])
    POOL = ACTS + EXTRA
    def one():
        seq, nw = ["ea"], 1
        while len(seq) < L:
            a = rng.choice(POOL)
            if a == "SP" and nw >= MAXWIN: continue
            if a in ("WP", "CL", "Y1", "Y2") and nw < 2: continue
            if a == "SP": nw += 1
            if a == "CL": nw -= 1
            seq.append(a)
        return seq
    seqs = [one() for _ in range(n)]
    seqlua = f"{SPEC}/ex/ex_seq_mw.lua"
def run(v, idx, seq):
    plugin = REPO if v == "today" else f"{SPEC}/variants/{v}"
    p = subprocess.run([f"{SPEC}/all/all_runseq.sh", os.environ.get("ALL_JOBPFX", "") + f"{v}-{view}-{gen}-{seed}-{idx}", plugin, " ".join(seq), view, seqlua], stdout=subprocess.PIPE, timeout=120)
    return [json.loads(l) for l in p.stdout.decode(errors="replace").splitlines() if l.startswith("{")]
for v in vs:
    with ThreadPoolExecutor(int(os.environ.get("ALL_THREADS", "12"))) as ex: res = list(ex.map(lambda a: run(v, *a), enumerate(seqs)))
    with open(f"{SPEC}/all/walks/{v}-{view}-{gen}-{n}-{L}-{seed}{tag}.jsonl", "w") as f:
        for seq, rs in zip(seqs, res): f.write(json.dumps({"seq": seq, "steps": rs}) + "\n")
    bad = sum(1 for seq, rs in zip(seqs, res) if len(rs) != len(seq))
    print(v, view, gen, seed, tag, "done, runfail", bad, flush=True)
