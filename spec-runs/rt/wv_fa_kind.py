#!/usr/bin/env python3
"""Sort fill asserts (or fills that would assert) by cause. Usage: wv_fa_kind.py <file.jsonl>
  tie:     the current buffer is tied for first in the ordered list's access times (window view rebuild)
  landing: after a cycle cancelled by a jump, the window landed in wasn't recorded (its buffer was the cycled-to one),
           and ordered[1] has stayed off the current since
  other:   anything else (prints the walk)"""
import json, sys, collections
c = collections.Counter(); ex = collections.defaultdict(list)
for wi, line in enumerate(open(sys.argv[1])):
    w = json.loads(line); steps = w["steps"]
    for i, s in enumerate(steps):
        err = s.get("err") or ""; notes = " | ".join(n["m"] for n in s["notes"])
        if not i or not (("populated from history" in notes) or ("WV-fill-assert" in err)): continue
        pv = steps[i-1]["st"]
        if (pv.get("ord") or "").split(",")[0] == pv.get("c"): continue
        tl = [(x.rsplit("=", 1)[0], int(x.rsplit("=", 1)[1])) for x in (pv.get("ordt") or "").split(",") if "=" in x]
        top = max(t for _, t in tl); tops = [n for n, t in tl if t == top]
        if len(tops) > 1 and pv.get("c") in tops: k = "tie"
        else:
            k = "other"
            for j in range(i - 1, -1, -1):
                sj = steps[j]["st"]
                if (sj.get("ord") or "").split(",")[0] == sj.get("c"): break
                if steps[j]["a"] in ("Y1", "Y2") and any(n["m"].startswith("WV-cancel") for n in steps[j]["notes"]): k = "landing"; break
                if steps[j]["a"] in ("Y1", "Y2") and sj.get("nav") == "cycling": k = "leak (cycle still open)"; break
        c[k] += 1
        ex[k].append((wi, i + 1, " ".join(w["seq"][:i + 1])))
print(dict(c))
for k, v in ex.items():
    if k not in ("tie", "landing"):
        for e in v[:5]: print("  ", k, e)
