#!/usr/bin/env python3
"""For each walk with a problem (duplicate slot, self-naming note, error, hook failure): is it after a fill whose
ordered[1] wasn't the current buffer, in the same walk? Usage: wv_downstream.py <file.jsonl>"""
import json, sys, collections
def wins_of(st):
    if "wins" in st: return {a: b for a, b in st["wins"].items() if isinstance(b, dict) and not b.get("none")}
    return {"win1": st}
c = collections.Counter(); ex = []
for wi, line in enumerate(open(sys.argv[1])):
    w = json.loads(line); steps = w["steps"]; first_bad_fill = None; first_prob = None
    for i, s in enumerate(steps):
        st = s["st"]; pv = steps[i-1]["st"] if i else {}; err = s.get("err") or ""
        notes = " | ".join(n["m"] for n in s["notes"])
        if first_bad_fill is None and ("populated from history" in notes or "WV-fill-assert" in err) and (pv.get("ord") or "").split(",")[0] != pv.get("c"):
            first_bad_fill = i
        prob = bool(err) or any(n["m"].startswith("Hook '") for n in s["notes"])
        for t in wins_of(st).values():
            cc, tt, ss = t.get("c"), t.get("t"), t.get("s")
            if (cc not in (None, "-") and (cc == tt or cc == ss)) or (tt not in (None, "-") and tt == ss): prob = True
            for mk in ("dtm", "dsm"):
                if isinstance(t.get(mk), dict) and any(k.replace("-swap", "") == x for k, x in t[mk].items()): prob = True
        if prob and first_prob is None: first_prob = i
    if first_prob is not None:
        k = "after a bad fill" if (first_bad_fill is not None and first_bad_fill <= first_prob) else "no bad fill before it"
        c[k] += 1
        if k != "after a bad fill": ex.append((wi, first_prob + 1, " ".join(w["seq"][:first_prob + 1])))
print(dict(c))
for e in ex[:10]: print("  ", e)
