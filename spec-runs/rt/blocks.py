#!/usr/bin/env python3
"""Row blocks for the packet: full rows for the first variant, then each other variant from its first differing row.
Usage: blocks.py <scenario> <variant[,variant...]>"""
import re, sys
R = "@RUNS@/rt/rows"
LABEL = {"today": "today", "rt_base": "decided [sim]", "rt_c1": "TK-as-is [sim]", "rt_c1s": "TK [sim]", "rt_c2a": "SK [sim]",
         "rt_c2b": "SC, Option 3 [sim]", "rt_c3": "PC [sim]", "rt_c3k": "PCd [sim]", "rt_c1sg": "TK+G, Option 2 [sim]", "rt_c3kg": "PCd+G, Option 1 [sim]",
         "rt_c1sga": "TK+G+W [sim]", "rt_c3kga": "PCd+G+W [sim]", "rt_c2bga": "SC+W [sim]",
         "plain": "swaps write plain ternary notes [sim]", "rt_q6": "Q6 on all four routes [sim]", "rt_tb": "Q6 plus the bonus check [sim]"}
import glob
HMAP = {}
for _f in glob.glob(R + "/*.txt"):
    for _m in re.finditer(r"([0-9a-f]{16}) \(([a-z])\.txt\)", open(_f).read()):
        HMAP[_m.group(1)] = _m.group(2)
def clean(l):
    l = re.sub(r"([0-9a-f]{16}) \(/[^»]*»", lambda m: HMAP.get(m.group(1), "?") + " (closed)»", l)
    l = re.sub(r"[0-9a-f]{16} \(([a-z])\.txt\)", r"\1", l)
    l = l.replace(". It should be different for flip flop.", ".").replace(". It should", ".").replace(". It sh", ".")
    l = l.replace(" It means you hadn't d»", "»").replace(" It means you hadn't dis»", "»")
    l = l.replace("Secondary buffer set to ternary slot. Ternary slot graduated.", "…graduated.")
    l = l.replace("No secondary relationship found for restoration.", "No secondary relationship found…")
    l = l.replace("No ternary relationship found for restoration.", "No ternary relationship found…")
    l = l.replace("ERROR: This is impossible. ", "ERROR: ")
    l = re.sub(r"«RT-bonus:[^»]*»", "«bonus check: note dropped»", l)
    l = l.replace("«Checkpoint saved: »", "")
    return l.rstrip()
def rows(sc, v):
    ls = open(f"{R}/{sc}.{v}.txt").read().splitlines()
    return [clean(l) for l in ls if not l.startswith("-- plugin")]
sc = sys.argv[1]; vs = sys.argv[2].split(",")
ref = rows(sc, vs[0])
out = [f"{LABEL.get(vs[0], vs[0])}:", "```"] + ref + ["```"]
for v in vs[1:]:
    r = rows(sc, v)
    i = 0
    while i < min(len(r), len(ref)) and r[i] == ref[i]: i += 1
    if i == len(r) == len(ref):
        out += [f"{LABEL.get(v, v)}: every row the same as {LABEL.get(vs[0], vs[0])}."]
        continue
    out += [f"{LABEL.get(v, v)}: " + (f"the first {i} rows are the same as {LABEL.get(vs[0], vs[0])}; from there:" if i else "all rows:"), "```"] + r[i:] + ["```"]
print("\n".join(out))
