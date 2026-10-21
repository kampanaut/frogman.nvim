#!/usr/bin/env python3
"""EX branch test: at every firing of the check at <M-;><M-t>'s exchange (EX-t S-exch) in the given ex_c walk files,
replay the walk up to that key, then press TAIL (default "R R S") under each variant, and classify each added key.
Usage: ex_branch.py [--tail "R R S"] ex_c-<view>-<gen>-....jsonl ...
Prints per variant: outcome of each added key (outside / exchange / none / throw ...), and whether I23 holds after."""
import json, subprocess, sys, os, collections, itertools
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from ex_scan import restore_outcome, cur, violations, windows
SPEC = "@RUNS@"
args = sys.argv[1:]
tail = "R R S".split()
if args and args[0] == "--tail": tail = args[1].split(); args = args[2:]
VS = ["kt_rewrite_sec", "ex_a", "ex_b", "ex_c"]
cases = []
for f in args:
    base = f.split("/")[-1]
    _, view, gen = base.split("-")[:3]
    for line in open(f):
        w = json.loads(line)
        for i, s in enumerate(w["steps"]):
            if any(n["m"].startswith("EX-t S-exch") for n in s["notes"]):
                pv = w["steps"][i - 1]["st"]; c = pv.get("c")
                sw = (pv.get("dtm") or {}).get(c + "-swap") if c else None
                hidden = sw is not None and sw != s["st"].get("t")  # the restore reads a valid swap note, not the plain note
                cases.append((view, gen, w["seq"][:i + 1], hidden))
cnt = itertools.count()
def run(v, view, gen, seq):
    seqlua = f"{SPEC}/ex/ex_seq.lua" if gen in ("single", "rheavy") else f"{SPEC}/ex/ex_seq_mw.lua"
    p = subprocess.run([f"{SPEC}/ex/ex_runseq.sh", f"exbr-{os.getpid()}-{next(cnt)}", f"{SPEC}/variants/{v}", " ".join(seq), view, seqlua],
                       stdout=subprocess.PIPE, timeout=120)
    return [json.loads(l) for l in p.stdout.decode(errors="replace").splitlines() if l.startswith("{")]
jobs = [(v, c) for c in cases for v in VS]
with ThreadPoolExecutor(int(os.environ.get("EX_THREADS", "6"))) as ex:
    res = list(ex.map(lambda j: run(j[0], j[1][0], j[1][1], j[1][2] + tail), jobs))
out = {v: collections.Counter() for v in VS}; i23 = collections.Counter(); seqs = collections.defaultdict(list)
for (v, c), rs in zip(jobs, res):
    n0 = len(c[2])
    if len(rs) != n0 + len(tail): out[v][("runfail",)] += 1; continue
    keys = []
    for k in range(len(tail)):
        s = rs[n0 + k]; pv = cur(rs[n0 + k - 1]["st"])
        keys.append(restore_outcome(s["a"], s, pv) if s["a"] in ("R", "S") else ("ok" if s["ok"] else "error"))
    out[v][("hidden" if c[3] else "read",) + tuple(keys)] += 1
    vs = set()
    for _, w in windows(rs[-1]["st"]): vs |= violations(w)
    if vs: i23[v] += 1
    seqs[(v, tuple(keys))].append(" ".join(c[2]))
byc = collections.defaultdict(dict)
for (v, c), rs in zip(jobs, res):
    n0 = len(c[2])
    if len(rs) == n0 + len(tail):
        s = rs[n0]; byc[id(c)][v] = restore_outcome(s["a"], s, cur(rs[n0 - 1]["st"])) if s["a"] in ("R", "S") else "-"
    byc[id(c)]["hidden"] = c[3]
pair = collections.Counter()
for d in byc.values():
    for v in ("kt_rewrite_sec", "ex_a", "ex_b"):
        pair[(v, "hidden" if d["hidden"] else "read", d.get(v), d.get("ex_c"))] += 1
print(f"{len(cases)} firings ({sum(1 for c in cases if c[3])} behind a valid swap note); first added key {tail[0]}, paired with ex_c:")
for k, n in sorted(pair.items()): print(f"    {k[0]:<15} {k[1]:<6} {k[2]:<9} vs drop {k[3]:<9} {n}")
print(f"added keys: {' '.join(tail)}")
for v in VS:
    print(f"  {v}: " + "; ".join(f"{'/'.join(k)} x{n}" for k, n in out[v].most_common()) + f"   I23 broken after: {i23[v]}")
for (v, k), ss in sorted(seqs.items()):
    print("  e.g.", v, "/".join(k), ":", ss[0])
