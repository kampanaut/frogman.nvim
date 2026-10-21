#!/usr/bin/env python3
"""EX: the numbers table over every finished walk file in ex/walks (markdown), plus totals per variant.
Usage: ex_table.py [gen ...]   (default: single mw)"""
import glob, os, sys, collections, json
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from ex_scan import scan
D = __file__.rsplit("/", 1)[0] + "/walks"
gens = sys.argv[1:] or ["single", "mw"]
ORDER = ["today", "kt_rewrite_sec", "ex_a", "ex_b", "ex_c"]
rows = []; tot = collections.defaultdict(lambda: collections.Counter()); outc = collections.defaultdict(collections.Counter)
cache = D + "/.scan_cache.json"
C = json.load(open(cache)) if os.path.exists(cache) else {}
for f in sorted(glob.glob(D + "/*-1500-25-*.jsonl")):
    b = os.path.basename(f)
    v, view, gen = b.split("-")[:3]; seed = b.split("-")[-1].split(".")[0]
    if gen not in gens: continue
    key = f"{b}:{os.path.getmtime(f)}"
    if key not in C:
        R = scan(f)
        C[key] = dict(steps=R["steps"], runfail=R["runfail"], cur=sum(R["cur"].values()), cur_ter=R["cur"]["ter"], cur_sec=R["cur"]["sec"],
                      any=sum(R["any"].values()), any_ter=R["any"]["ter"], any_sec=R["any"]["sec"],
                      thr_t=R["throws"]["ternary"], thr_s=R["throws"]["secondary"], other=sum(R["other_err"].values()),
                      hook=sum(R["hookfail"].values()), dup=sum(R["dup"].values()),
                      ext={f"{a}/{o}": n for (a, o), n in R["ext_out"].items()},
                      fresh={f"{k}/{a}": n for (k, a), n in R["fresh"].items()})
        json.dump(C, open(cache, "w"))
    r = C[key]
    rows.append((ORDER.index(v) if v in ORDER else 9, gen, view, seed, v, r))
rows.sort(key=lambda x: (x[1], x[2], int(x[3]), x[0]))
print("| Walks | View | Seed | Variant | I23, current window (ternary / secondary) | I23, any window | Restore throws (ternary / secondary) | Other errors | Hook failures | Duplicate slots, self-naming notes | Check at `<M-;><M-t>`'s exchange: fired → outcome |")
print("|---|---|---|---|---|---|---|---|---|---|---|")
for _, gen, view, seed, v, r in rows:
    ex = ", ".join(f"{k.split('/')[1] if k.startswith('S-exch') else k} {n}" for k, n in sorted(r["ext"].items())) if r["ext"] else "–"
    nfire = sum(r["ext"].values())
    anyc = f"{r['any']} ({r['any_ter']} / {r['any_sec']})" if gen != "single" else "same"
    print(f"| {gen} | {view} | {seed} | `{v}` | {r['cur']} ({r['cur_ter']} / {r['cur_sec']}) | {anyc} | {r['thr_t']} / {r['thr_s']} | {r['other']} | {r['hook']} | {r['dup']} | {nfire if r['ext'] else '–'}{(' → ' + ex) if r['ext'] else ''} |")
    for k in ("steps", "cur", "any", "thr_t", "thr_s", "other", "hook", "dup", "runfail"): tot[v][k] += r[k]
    for k, n in r["ext"].items(): outc[v][k] += n
print()
print("| Variant | Steps | I23, current window | I23, any window | Restore throws (ternary / secondary) | Other errors | Hook failures | Duplicates | Run failures | Firings → outcome |")
print("|---|---|---|---|---|---|---|---|---|---|")
for v in ORDER:
    if v not in tot: continue
    t = tot[v]
    ex = ", ".join(f"{k.split('/')[1]} {n}" for k, n in sorted(outc[v].items())) or "–"
    print(f"| `{v}` | {t['steps']:,} | {t['cur']} | {t['any']} | {t['thr_t']} / {t['thr_s']} | {t['other']} | {t['hook']} | {t['dup']} | {t['runfail']} | {sum(outc[v].values())} → {ex} |")
