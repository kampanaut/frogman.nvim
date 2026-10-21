#!/usr/bin/env python3
"""Ternary rewrite firings by arrival kind and outcome, summed over the given walk files. Usage: kt_bykind.py file...
Also: secondary-side firings by site and outcome (KT-s)."""
import json, sys, collections
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from importlib.machinery import SourceFileLoader
def arrival(a, pv, st, notes):
    if a.startswith("e"):
        f = a[1] + ".txt"
        if pv.get("s") == f: return ":e onto the secondary"
        if pv.get("t") == f: return ":e onto the ternary"
        return ":e (other)"
    if a in ("F", "J"):
        if "graduated" in notes: return "graduation"
        if a == "J" and st.get("c") != pv.get("c") and st.get("c") != pv.get("s"): return "primary jump"
        if pv.get("s") and st.get("c") == pv.get("s"): return "<M-f>" if a == "F" else "<M-;><M-f> falling back to <M-f>"
        return a
    if a.startswith("X"):
        if st.get("c") == pv.get("s"): return "pick of the secondary"
        if st.get("c") == pv.get("t"): return "pick of the ternary"
        return "pick of an outside buffer"
    return {"G": "<M-S-f>", "R": "<M-;><M-r>", "S": "<M-;><M-t>"}.get(a, a)
T = collections.defaultdict(collections.Counter); S = collections.defaultdict(collections.Counter)
for p in sys.argv[1:]:
    for line in open(p):
        w = json.loads(line)
        for i, s in enumerate(w["steps"]):
            st = s["st"]; pv = w["steps"][i-1]["st"] if i else {}
            notes = " ".join(n["m"] for n in s["notes"])
            for n in s["notes"]:
                m = n["m"]
                if m.startswith("KT-t "):
                    case = m.split(" ")[2]
                    note, new = m.split(" ", 3)[3].split(" => ")
                    out = "nothing" if new == "-" else ("unchanged" if new == note.split(">")[1] else ("the secondary" if new == (st.get("s") or "-").replace(".txt", "") else "a buffer"))
                    T[(arrival(s["a"], pv, st, notes), case)][out] += 1
                if m.startswith("KT-s "):
                    parts = m.split(" ")
                    S[(arrival(s["a"], pv, st, notes), parts[1])][parts[2]] += 1
if T:
    outs = ["a buffer", "the secondary", "nothing", "unchanged"]
    print("arrival | rule | " + " | ".join(outs) + " | total")
    tot = collections.Counter()
    for k, o in sorted(T.items(), key=lambda x: -sum(x[1].values())):
        tot.update(o); print(f"{k[0]} | {k[1]} | " + " | ".join(str(o[x]) for x in outs) + f" | {sum(o.values())}")
    print("all | | " + " | ".join(str(tot[x]) for x in outs) + f" | {sum(tot.values())}")
if S:
    print("\nsecondary side: arrival | site | rewrite | drop | total")
    tot = collections.Counter()
    for k, o in sorted(S.items(), key=lambda x: -sum(x[1].values())):
        tot.update(o); print(f"{k[0]} | {k[1]} | {o['rw']} | {o['drop']} | {sum(o.values())}")
    print(f"all | | {tot['rw']} | {tot['drop']} | {sum(tot.values())}")
