#!/usr/bin/env python3
"""KT numbers for one rt_walk JSONL file: throws, other errors, hook failures, rewrite firings and their outcomes,
duplicate slots and self-naming notes.  Usage: kt_stats.py <file.jsonl> [-v]"""
import json, sys, collections, re

path = sys.argv[1]; verbose = "-v" in sys.argv

def fix(st):
    for k in ("dsm", "dtm", "pt"):
        if not isinstance(st.get(k), dict): st[k] = {}
    return st

def arrival(a, pv, st, notes):
    """What kind of key/arrival a step is, from the walk letter and the slots before/after."""
    if a.startswith("e"):
        f = a[1] + ".txt"
        if pv.get("c") == f: return ":e (same)"
        if pv.get("s") == f: return ":e onto the secondary"
        if pv.get("t") == f: return ":e onto the ternary"
        return ":e (other)"
    if a in ("F", "J"):
        key = "<M-f>" if a == "F" else "<M-;><M-f>"
        if "graduated" in notes: return key + " graduation"
        if a == "J" and st.get("c") != pv.get("c") and st.get("c") != pv.get("s"): return "primary jump"
        if pv.get("s") and st.get("c") == pv.get("s"): return key + " swap" if a == "F" else "<M-;><M-f> falling back to <M-f>"
        return key + " (other)"
    if a.startswith("X"):
        if st.get("c") == pv.get("s"): return "pick of the secondary"
        if st.get("c") == pv.get("t"): return "pick of the ternary"
        if st.get("c") == pv.get("c"): return "pick of the same buffer"
        return "pick of an outside buffer"
    return {"G": "<M-S-f>", "R": "<M-;><M-r>", "S": "<M-;><M-t>", "P": "<M-;><M-c>"}.get(a, a)

T = collections.Counter(); walks = collections.defaultdict(set)
other_err = collections.Counter(); hookfail = collections.Counter()
ktt = collections.Counter(); kts = collections.Counter(); kts_prev = collections.Counter(); tbdrop = collections.Counter()
dup = collections.Counter(); selfnote = collections.Counter(); runfail = 0; nsteps = 0
used = collections.Counter(); ex = {}
for wi, line in enumerate(open(path)):
    w = json.loads(line); steps = w["steps"]
    if len(steps) != len(w["seq"]): runfail += 1
    alive = {}  # N -> (value, step) for ternary rewrites whose note is still in place
    prev_self = set(); prev_dup = set()
    for i, s in enumerate(steps):
        nsteps += 1
        st = fix(s["st"]); pv = fix(steps[i-1]["st"]) if i else {"dtm": {}, "dsm": {}}
        notes = " | ".join(n["m"] for n in s["notes"])
        kind = arrival(s["a"], pv, st, notes)
        err = s.get("err") or ""
        if "is the same as current" in err:
            typ = "secondary" if "secondary" in err else "ternary"
            T[typ] += 1; walks[typ].add(wi)
        elif err:
            other_err[re.sub(r"[0-9a-f]{16}", "#", err)[:120]] += 1
        for n in s["notes"]:
            m = n["m"]
            if m.startswith("Hook '") or "Duplicates detected" in m:
                hookfail[re.sub(r"[0-9a-f]{16}", "#", m)[:140]] += 1
            if m.startswith("KT-t "):
                _, k, case, rest = m.split(" ", 3)
                note, new = rest.split(" => ")
                N = note.split(">")[0]
                c = lambda x: (x or "-").replace(".txt", "")
                if new == "-": out = "nothing (dropped)"
                elif new == N: out = "the arriving buffer itself"
                elif new == c(st.get("s")): out = "the secondary"
                elif new == note.split(">")[1]: out = "unchanged (still stale)"
                else: out = "another buffer"
                ktt[(kind, case, out)] += 1
                alive[N] = (new, i, out)
                key = ("ktt", kind, case, out)
                if key not in ex or len(ex[key]) > i + 1: ex[key] = w["seq"][:i+1]
            if m.startswith("KT-s "):
                parts = m.split(" ")
                site, out = parts[1], parts[2]
                prev = parts[-1].split("=")[1]; sw = parts[-2].split("=")[1]
                kts[(kind, site, out)] += 1
                kts_prev[(site, out, "prev differs from the stale one" if prev not in ("-", parts[3].split(">")[1], parts[3].split(">")[0]) else "no other prev")] += 1
                key = ("kts", kind, site, out)
                if key not in ex or len(ex[key]) > i + 1: ex[key] = w["seq"][:i+1]
            if m.startswith("RT-bonus: dropped"):
                tbdrop[kind] += 1
        # did a <M-;><M-r> use a rewritten plain note that's still in place?
        if s["a"] == "R" and i:
            X = pv.get("c", "-").replace(".txt", "")
            swap = pv["dtm"].get(pv.get("c", "") + "-swap")
            if (swap is None or swap == pv.get("t")) and X in alive:
                v, at, o = alive[X]
                plain = pv["dtm"].get(pv.get("c"))
                if (plain or "-").replace(".txt", "") == v:
                    res = "restored" if "Restored ternary" in notes else ("threw" if err else ("no relationship" if "No ternary relationship" in notes else "other"))
                    used[(o, res)] += 1
                    key = ("used", o, res)
                    if key not in ex or len(ex[key]) > i + 1: ex[key] = w["seq"][:i+1]
        # rewritten notes that changed since are no longer "alive"
        for N in list(alive):
            v, at, o = alive[N]
            if at != i and (st["dtm"].get(N + ".txt") or "-").replace(".txt", "") != v: del alive[N]
        # duplicate slots and self-naming notes, counted when they first appear
        c, t, sc = st.get("c"), st.get("t"), st.get("s")
        d = set()
        if c not in (None, "-") and c == t: d.add("current = ternary")
        if c not in (None, "-") and c == sc: d.add("current = secondary")
        if t not in (None, "-") and t == sc: d.add("ternary = secondary")
        for x in d - prev_dup:
            dup[(x, kind)] += 1
            key = ("dup", x)
            if key not in ex or len(ex[key]) > i + 1: ex[key] = w["seq"][:i+1]
        prev_dup = d
        sn = set()
        for mk in ("dtm", "dsm"):
            for k, v in st[mk].items():
                if k.replace("-swap", "") == v: sn.add(mk + ("[x-swap]" if k.endswith("-swap") else "[x]") + " = x")
        for x in sn - prev_self:
            selfnote[(x, kind)] += 1
            key = ("self", x)
            if key not in ex or len(ex[key]) > i + 1: ex[key] = w["seq"][:i+1]
        prev_self = sn

print(f"file {path.split('/')[-1]}  walks {wi+1}  steps {nsteps}  runfail {runfail}")
for typ in ("ternary", "secondary"):
    print(f"  {typ} restore throws: {T[typ]} in {len(walks[typ])} walks")
print(f"  other errors: {sum(other_err.values())}"); [print(f"    {c:5} {m}") for m, c in other_err.most_common()]
print(f"  hook failures / duplicates detected: {sum(hookfail.values())}"); [print(f"    {c:5} {m}") for m, c in hookfail.most_common()]
print(f"  ternary rewrite fired: {sum(ktt.values())}")
for (k, case, out), c in sorted(ktt.items(), key=lambda x: -x[1]): print(f"    {c:5}  {k:34} {case:5} -> {out}" + (f"   e.g. {' '.join(ex[('ktt', k, case, out)])}" if verbose else ""))
print(f"  secondary check fired: {sum(kts.values())}")
for (k, site, out), c in sorted(kts.items(), key=lambda x: -x[1]): print(f"    {c:5}  {k:34} {site:12} {out}" + (f"   e.g. {' '.join(ex[('kts', k, site, out)])}" if verbose else ""))
for (site, out, pr), c in sorted(kts_prev.items(), key=lambda x: -x[1]): print(f"    {c:5}  prev-candidate: {site:12} {out:5} {pr}")
if tbdrop: print(f"  rt_tb drop fired: {sum(tbdrop.values())}"); [print(f"    {c:5}  {k}") for k, c in tbdrop.most_common()]
print(f"  <M-;><M-r> reading a rewritten plain note: {sum(used.values())}")
for (o, res), c in used.most_common(): print(f"    {c:5}  rewritten to {o}: {res}" + (f"   e.g. {' '.join(ex[('used', o, res)])}" if verbose else ""))
print(f"  duplicate slots (first appearance): {sum(dup.values())}")
for (x, k), c in dup.most_common(): print(f"    {c:5}  {x:22} after {k}" + (f"   e.g. {' '.join(ex[('dup', x)])}" if verbose else ""))
print(f"  self-naming notes (first appearance): {sum(selfnote.values())}")
for (x, k), c in selfnote.most_common(): print(f"    {c:5}  {x:16} after {k}" + (f"   e.g. {' '.join(ex[('self', x)])}" if verbose else ""))
