#!/usr/bin/env python3
"""List the walk steps behind WV's counts. Usage: wv_find.py <file.jsonl> <what> [max]
what: would (fills that would assert), fa (fill asserts), dup (first duplicate slot per walk), self (first self-naming note
per walk), err (other errors), tt / ts (restore throws). Prints walk index, step, the walk prefix up to that step, and the state."""
import json, sys
path, what = sys.argv[1], sys.argv[2]; mx = int(sys.argv[3]) if len(sys.argv) > 3 else 20
k = 0
def wins_of(st):
    if "wins" in st: return {a: b for a, b in st["wins"].items() if isinstance(b, dict) and not b.get("none")}
    return {"win1": st}
for wi, line in enumerate(open(path)):
    w = json.loads(line); steps = w["steps"]
    for i, s in enumerate(steps):
        st = s["st"]; err = s.get("err") or ""; pv = steps[i-1]["st"] if i else {}
        notes = " | ".join(n["m"] for n in s["notes"])
        hit = None
        if what == "would" and ("populated from history" in notes or "WV-fill-assert" in err) and (pv.get("ord") or "").split(",")[0] != pv.get("c"):
            hit = f"ord before {pv.get('ord')} current {pv.get('c')} in {pv.get('w')}"
        elif what == "fa" and "WV-fill-assert" in err: hit = err[-90:]
        elif what == "err" and err and "is the same as current" not in err and "WV-fill-assert" not in err: hit = err[-90:]
        elif what in ("tt", "ts") and ("is the same as current " + ("ternary" if what == "tt" else "secondary")) in err: hit = err[-60:]
        elif what in ("dup", "self"):
            for lab, t in wins_of(st).items():
                c, tt, ss = t.get("c"), t.get("t"), t.get("s")
                if what == "dup" and ((c not in (None, "-") and (c == tt or c == ss)) or (tt not in (None, "-") and tt == ss)):
                    hit = f"{lab}: c={c} s={ss} t={tt}"
                if what == "self":
                    for mk in ("dtm", "dsm"):
                        if isinstance(t.get(mk), dict):
                            for a, b in t[mk].items():
                                if a.replace("-swap", "") == b: hit = f"{lab}: {mk} {a}>{b}"
        if hit:
            print(f"walk {wi} step {i+1}: {' '.join(w['seq'][:i+1])}\n    {hit}")
            k += 1
            if what in ("dup", "self"): break
        if k >= mx: sys.exit()
