#!/usr/bin/env python3
"""Classify restore throws in rt_walk JSONL files by (what wrote the stale note, how the window arrived).
Usage: rt_classify.py <file.jsonl> [own_slot]   own_slot: the restore skips a swap note equal to its own slot (C1s)."""
import json, sys, collections
path = sys.argv[1]; own = "own" in sys.argv[2:]; d8 = "d8" in sys.argv[2:]
def lab(steps, k):
    a = steps[k]["a"]; st = steps[k]["st"]; pv = steps[k-1]["st"] if k > 0 else {}
    notes = " ".join(n["m"] for n in steps[k]["notes"])
    if a.startswith("e"):
        f = a[1] + ".txt"
        if pv.get("s") == f: return "e-onto-sec"
        if pv.get("t") == f: return "e-onto-ter"
        return "e-other"
    if a in ("F", "J"):
        if "graduated" in notes: return a + "-grad"
        if "populated from history" in notes: return a + "-hist"
        if pv.get("s") and st.get("c") == pv.get("s"): return a + "-swap"
        if a == "J" and st.get("c") != pv.get("c"): return "J-primary"
        return a + "-other"
    if a.startswith("X"):
        if st.get("c") == pv.get("s"): return "pick-sec"
        if st.get("c") == pv.get("t"): return "pick-ter"
        return "pick-out"
    return a
res = {"secondary": collections.Counter(), "ternary": collections.Counter()}
ex = {}
nseq = {"secondary": set(), "ternary": set()}
def fix(st):
    for k in ("dsm", "dtm", "pt"):
        if not isinstance(st.get(k), dict): st[k] = {}
    return st
for wi, line in enumerate(open(path)):
    w = json.loads(line); steps = w["steps"]
    for s0 in steps: fix(s0["st"])
    for i, s in enumerate(steps):
        err = s.get("err") or ""
        if "is the same as current" not in err: continue
        typ = "secondary" if "secondary" in err else "ternary"
        st = s["st"]; X = st["c"]
        m = st["dsm"] if typ == "secondary" else st["dtm"]
        slot = st["s"] if typ == "secondary" else st["t"]
        skip = slot if (own and typ == "secondary") else st["t"]
        rem = m.get(X + "-swap"); key = X + "-swap"
        if rem is None or rem == skip: rem = m.get(X); key = X
        mk = "dsm" if typ == "secondary" else "dtm"
        j = max([j for j in range(i) if steps[j]["st"][mk].get(key) == rem and (j == 0 or steps[j-1]["st"][mk].get(key) != rem)], default=-1)
        if typ == "secondary" and not key.endswith("-swap") and "nocredit" not in sys.argv[2:]:
            # a swap-out of X onto Y rewrites the same value: credit the last such swap-out after the last change
            jj = [q for q in range(max(j, 0), i) if q > 0 and steps[q-1]["st"].get("c") == X and steps[q]["st"].get("c") == rem and steps[q]["st"].get("s") == X and (steps[q]["a"] in ("F", "J") or (d8 and steps[q]["a"].startswith("e")))]
            if jj and (j < 0 or jj[-1] > j): j = jj[-1]
        sk = "s" if typ == "secondary" else "t"
        k = max([k for k in range(i) if (steps[k]["st"]["c"], steps[k]["st"][sk]) == (X, slot) and (k == 0 or (steps[k-1]["st"]["c"], steps[k-1]["st"][sk]) != (X, slot))], default=-1)
        cls = ("note" + ("(swap key)" if key.endswith("-swap") else "") + " by " + (lab(steps, j) if j >= 0 else "?"), "arrived by " + (lab(steps, k) if k >= 0 else "?"))
        res[typ][cls] += 1; nseq[typ].add(wi)
        seq = [x["a"] for x in steps[:i+1]]
        if cls not in ex or len(seq) < len(ex[cls]): ex[cls] = seq
for typ in ("secondary", "ternary"):
    print(f"{typ} restore throws: {sum(res[typ].values())} in {len(nseq[typ])} walks")
    for cls, c in res[typ].most_common():
        print(f"  {c:4}  {cls[0]:28} {cls[1]:22} shortest: {' '.join(ex[cls])}")
