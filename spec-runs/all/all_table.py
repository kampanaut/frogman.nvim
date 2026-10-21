#!/usr/bin/env python3
"""ALL: the numbers table over all/walks/*-1500-25-<seed>.jsonl (no repeat tags), plus totals.
Columns: I23 breaks at the current window / any window (ternary + secondary breaks, counted per step and map, as EX),
I1 steps with a buffer in two slots (current window / any window), fill assertions (fills that would assert, for today),
restore throws (ternary / secondary), "Duplicates detected", other errors, hook failures, cancels."""
import glob, os, sys, json, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from all_scan import scan
D = os.path.dirname(os.path.abspath(__file__)) + "/walks"
cache = D + "/.scan_cache.json"
C = json.load(open(cache)) if os.path.exists(cache) else {}
GEN = {"single": "one window", "mw": "several windows", "mwy": "cycles left open across a jump", "rheavy": "restore-heavy"}
GO = list(GEN); VO = ["all_fixed", "today"]; VN = {"all_fixed": "all fixes", "today": "today's code"}
rows = []
for f in sorted(glob.glob(D + "/*-1500-25-*.jsonl")):
    b = os.path.basename(f)
    if b.count(".") != 1: continue  # repeat runs carry a tag
    v, view, gen = b.split("-")[:3]; seed = int(b.split("-")[-1].split(".")[0])
    key = f"{b}:{os.path.getmtime(f)}"
    if key not in C:
        R, Cn, EX = scan(f); C[key] = dict(R=R, C=Cn); json.dump(C, open(cache, "w"))
    rows.append((GO.index(gen), seed, view, VO.index(v), v, gen, C[key]["R"]))
rows.sort()
K = ["steps", "i23_cur", "i23_any", "i1_cur_steps", "i1_any_steps", "fill_assert", "fill_would", "throw_ternary", "throw_secondary", "dupdet", "other", "hook", "cancel", "cancel_moved", "runfail", "self_any", "q9", "cycling"]
def cell(R, k): return R.get(k, 0)
print("| Walk set | Seed | View | Code | I23: current window / any window | I1: current window / any window | Fill assertions | Restore throws (ternary / secondary) | \"Duplicates detected\" | Other errors | Hook failures |")
print("|---|---|---|---|---|---|---|---|---|---|---|")
tot = collections.defaultdict(collections.Counter)
for _, seed, view, _, v, gen, R in rows:
    fa = f"{cell(R,'fill_assert')}" if v == "all_fixed" else f"– (would: {cell(R,'fill_would')})"
    print(f"| {GEN[gen]} | {seed} | {view} | {VN[v]} | {cell(R,'i23_cur'):,} / {cell(R,'i23_any'):,} | {cell(R,'i1_cur_steps'):,} / {cell(R,'i1_any_steps'):,} | {fa} | {cell(R,'throw_ternary'):,} / {cell(R,'throw_secondary'):,} | {cell(R,'dupdet')} | {cell(R,'other')} | {cell(R,'hook')} |")
    for k in K: tot[(v, view)][k] += cell(R, k); tot[(v, "both")][k] += cell(R, k)
print()
print("| Code | View | Steps | I23: current / any | I1: current / any | Fill assertions | Restore throws (ternary / secondary) | \"Duplicates detected\" | Other errors | Hook failures | Run failures |")
print("|---|---|---|---|---|---|---|---|---|---|---|")
for v in VO:
    for view in ("global", "window", "both"):
        t = tot[(v, view)]
        if not t: continue
        fa = f"{t['fill_assert']}" if v == "all_fixed" else f"– (would: {t['fill_would']})"
        print(f"| {VN[v]} | {view} | {t['steps']:,} | {t['i23_cur']:,} / {t['i23_any']:,} | {t['i1_cur_steps']:,} / {t['i1_any_steps']:,} | {fa} | {t['throw_ternary']:,} / {t['throw_secondary']:,} | {t['dupdet']} | {t['other']} | {t['hook']} | {t['runfail']} |")
print()
for v in VO:
    t = tot[(v, "both")]
    print(v, json.dumps({k: t[k] for k in K}))
