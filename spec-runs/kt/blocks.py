#!/usr/bin/env python3
"""Row blocks for KT.md: full rows for the first variant, then each other variant from its first differing row.
Usage: blocks.py <scenario> <variant[,variant...]>   (rows from kt/rows/<scenario>.<variant>.txt)"""
import re, sys
R = "@RUNS@/kt/rows"
LABEL = {"rt_c3kga": "secondary fix, no ternary rewrite [sim]", "rt_tb": "RT's drop [sim]", "kt_drop": "drop, same base [sim]",
         "kt_literal": "rewrite as worded [sim]", "kt_rewrite": "Keep the older one [sim]", "kt_rewrite_sec": "Keep the older one, both sides [sim]"}
def kt_t(m):
    note, new = m.group(2), m.group(3)
    n = note.split(">")[0]
    if m.group(1) == "drop": return f"«drop: {note}»"
    if new == "-": return f"«rewrite: {note}, no older note, so dropped»"
    if new == note.split(">")[1]: return f"«rewrite: {note} kept as is»"
    return f"«rewrite: {note} becomes {n}>{new}»"
def kt_s(m):
    out, note, new = m.group(1), m.group(2), m.group(3)
    n = note.split(">")[0]
    return f"«secondary note {note} becomes {n}>{new}»" if out == "rw" else f"«secondary note {note} dropped»"
def clean(l):
    l = re.sub(r"«KT-t \S+ (\S+) (\S+>\S+) => (\S+)»", kt_t, l)
    l = re.sub(r"«KT-s \S+ (\S+) (\S+>\S+) => (\S+) swap=\S+ prev=\S+»", kt_s, l)
    l = re.sub(r"«RT-bonus:[^»]*»", "«drop: note dropped»", l)
    l = re.sub(r"Restored (ternary|secondary) slot to: [0-9a-f]{16} \(([a-z])\.txt\)", r"Restored \1 slot to \2", l)
    l = l.replace("«Checkpoint saved: »", "").replace("  «", "  «")
    l = l.replace("Secondary buffer set to ternary slot. Ternary slot graduated.", "…graduated.")
    l = re.sub(r"«No ternary relationship found[^»]*»", "«No ternary relationship found…»", l)
    l = re.sub(r"«No secondary relationship found[^»]*»", "«No secondary relationship found…»", l)
    l = re.sub(r"«Avoided conflict of ternary's remembered relationship becoming current[^»]*»", "«Avoided conflict…»", l)
    l = re.sub(r"«The stored ternary of the new buffer is already the ternary[^»]*»", "«The stored ternary of the new buffer is already the ternary…»", l)
    l = re.sub(r"ERROR: This is impossible\. (Remembered \w+ is the same as current \w+)\..*$", r"ERROR: \1.", l)
    l = re.sub(r"  +$", "", l)
    l = re.sub(r"(\S)  +(«|ERROR)", r"\1  \2", l)
    return l.rstrip()
def rows(sc, v):
    return [clean(l) for l in open(f"{R}/{sc}.{v}.txt").read().splitlines() if not l.startswith("-- plugin")]
sc = sys.argv[1]; vs = sys.argv[2].split(",")
ref = rows(sc, vs[0])
out = [f"{LABEL.get(vs[0], vs[0])}:", "```"] + ref + ["```"]
for v in vs[1:]:
    r = rows(sc, v); i = 0
    while i < min(len(r), len(ref)) and r[i] == ref[i]: i += 1
    if i == len(r) == len(ref):
        out += [f"{LABEL.get(v, v)}: every row the same as {LABEL.get(vs[0], vs[0])}."]; continue
    out += [f"{LABEL.get(v, v)}: " + (f"the first {i} rows are the same as {LABEL.get(vs[0], vs[0])}; from there:" if i else "all rows:"), "```"] + r[i:] + ["```"]
print("\n".join(out))
