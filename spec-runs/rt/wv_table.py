#!/usr/bin/env python3
"""WV numbers for walk files (single- or multi-window). Usage: wv_table.py <file.jsonl> [...] [-v]
Per file: ternary / secondary restore throws (walks), fill-assertion throws (walks), other errors, hook failures,
cancels fired, fills from history, fills that would assert (previous step's ordered[1] != current), duplicate slots and
self-naming notes in every window, run failures."""
import json, sys, collections, re
verbose = "-v" in sys.argv
files = [a for a in sys.argv[1:] if not a.startswith("-")]
def wins_of(st):
    if "wins" in st:
        return {k: v for k, v in st["wins"].items() if isinstance(v, dict) and not v.get("none")}
    return {"win1": st} if not st.get("none") else {}
print("file | ternary throws (walks) | secondary throws (walks) | fill asserts (walks) | other errors | hook failures | cancels | fills | fills that would assert (walks) [current tied for first / other] | fills with the current tied for first | duplicate slots | self-naming notes | windows max | runfail")
for path in files:
    c = collections.Counter(); W = collections.defaultdict(set); oerr = collections.Counter(); hook = collections.Counter()
    maxw = 1
    for wi, line in enumerate(open(path)):
        w = json.loads(line); steps = w["steps"]
        if len(steps) != len(w["seq"]): c["runfail"] += 1
        for i, s in enumerate(steps):
            st = s["st"]; err = s.get("err") or ""; pv = steps[i-1]["st"] if i else None
            maxw = max(maxw, st.get("nw", 1))
            notes = " | ".join(n["m"] for n in s["notes"])
            if "is the same as current ternary" in err: c["tt"] += 1; W["tt"].add(wi)
            elif "is the same as current secondary" in err: c["ts"] += 1; W["ts"].add(wi)
            elif "WV-fill-assert" in err: c["fa"] += 1; W["fa"].add(wi)
            elif err: c["oerr"] += 1; oerr[re.sub(r"[0-9a-f]{16}", "#", err)[:150]] += 1
            for n in s["notes"]:
                m = n["m"]
                if m.startswith("Hook '") or "Duplicates detected" in m: c["hook"] += 1; hook[re.sub(r"[0-9a-f]{16}", "#", m)[:150]] += 1
                if m.startswith("WV-cancel"): c["cancel"] += 1
            fill = "populated from history" in notes or "WV-fill-assert" in err
            if fill:
                c["fill"] += 1
                tie = False
                if pv is not None and pv.get("ordt"):
                    tl = [(x.rsplit("=", 1)[0], int(x.rsplit("=", 1)[1])) for x in pv["ordt"].split(",") if "=" in x]
                    top = max(t for _, t in tl); tops = [nm for nm, t in tl if t == top]
                    tie = len(tops) > 1 and pv.get("c") in tops
                    if tie: c["tie"] += 1
                if pv is not None and (pv.get("ord") or "").split(",")[0] != pv.get("c"):
                    c["would"] += 1; W["would"].add(wi)
                    c["would_tie" if tie else "would_other"] += 1
            for lab, t in wins_of(st).items():
                cc, tt, ss = t.get("c"), t.get("t"), t.get("s")
                if (cc not in (None, "-") and (cc == tt or cc == ss)) or (tt not in (None, "-") and tt == ss): c["dup"] += 1
                for mk in ("dtm", "dsm"):
                    if isinstance(t.get(mk), dict) and any(k.replace("-swap", "") == x for k, x in t[mk].items()): c["self"] += 1
    name = path.split("/")[-1].replace(".jsonl", "")
    print(f"{name} | {c['tt']} ({len(W['tt'])}) | {c['ts']} ({len(W['ts'])}) | {c['fa']} ({len(W['fa'])}) | {c['oerr']} | {c['hook']} | {c['cancel']} | {c['fill']} | {c['would']} ({len(W['would'])}) [tie {c['would_tie']}, other {c['would_other']}] | {c['tie']} | {c['dup']} | {c['self']} | {maxw} | {c['runfail']}")
    if verbose:
        for m, k in oerr.most_common(): print(f"    error x{k}: {m}")
        for m, k in hook.most_common(): print(f"    hook x{k}: {m}")
