#!/usr/bin/env python3
"""EX copy of rt/rt_walk_b.py (the WV runs' generator, unchanged); output to spec/ex/walks/, runner ex/ex_runseq.sh: same generator for 'single' (RT's, same RNG call order), plus multi-window ones.
Usage: rt_walk_b.py <n> <len> <seed> <variant[,variant]> <view> [gen]
  variant 'today' = the repo, else spec/variants/<name>;  view = global | window
  gen: single (RT's walks, run by rt/rt_seq_b.lua: rt_seq.lua plus the view in each snapshot)
       mw     (RT's keys plus :vsplit, <C-w>p, :close; run by rt/rt_seq_mw.lua)
       mwy    (mw plus "cycle one step, then <C-w>p": a cycle left open across a window jump)
Output: spec/rt/walks_b/<variant>-<view>-<gen>-<n>-<len>-<seed>.jsonl"""
import json, os, random, subprocess, sys, itertools
from concurrent.futures import ThreadPoolExecutor
SPEC = "@RUNS@"
REPO = "@REPO@"
n, L, seed = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]); vs = sys.argv[4].split(","); view = sys.argv[5]
gen = sys.argv[6] if len(sys.argv) > 6 else "single"
assert view in ("global", "window") and gen in ("single", "mw", "mwy", "rheavy")
ACTS = ["ea", "eb", "ec", "ed", "ee"] * 2 + ["F"] * 4 + ["G"] * 3 + ["R", "S", "X1", "X2", "X3", "P", "J"]
MAXWIN = 3
rng = random.Random(seed)
if gen == "rheavy":  # EX supplementary: the same keys with three more of each restore (R, S at 4/30 each instead of 1/24)
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
cnt = itertools.count()
def run(v, seq):
    plugin = REPO if v == "today" else f"{SPEC}/variants/{v}"
    p = subprocess.run([f"{SPEC}/ex/ex_runseq.sh", f"{v}-{view}-{os.getpid()}-{next(cnt)}", plugin, " ".join(seq), view, seqlua], stdout=subprocess.PIPE, timeout=120)
    return [json.loads(l) for l in p.stdout.decode(errors="replace").splitlines() if l.startswith("{")]
os.makedirs(f"{SPEC}/ex/walks", exist_ok=True)
for v in vs:
    with ThreadPoolExecutor(int(os.environ.get("EX_THREADS", "7"))) as ex: res = list(ex.map(lambda s: run(v, s), seqs))
    with open(f"{SPEC}/ex/walks/{v}-{view}-{gen}-{n}-{L}-{seed}.jsonl", "w") as f:
        for seq, rs in zip(seqs, res): f.write(json.dumps({"seq": seq, "steps": rs}) + "\n")
    bad = sum(1 for seq, rs in zip(seqs, res) if len(rs) != len(seq))
    print(v, view, gen, seed, "done, runfail", bad, flush=True)
