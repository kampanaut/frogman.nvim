#!/usr/bin/env python3
"""EX scan of walk files (ex/walks/*.jsonl), adapted from <scratchpad>/inv_scan.py, plus kt_stats.py's checks.
Usage: ex_scan.py [--json] file.jsonl ...
Per file:
  I23: after each step, for a window's current buffer x and each map, the note a restore would read is x's swap note
       when it's set and isn't the slot's occupant, otherwise x's plain note; a violation is that note naming the
       occupant (ternary for dtm, secondary for dsm).  'cur' = the current window, 'any' = every window (mw walks).
       'fresh' = a (window, map) violation that wasn't there at the previous step; attributed to that step's key.
  throws: restore errors "is the same as current"; other errors; hook failures ("Hook '", "Duplicates detected").
  dup: duplicate slots (c=s, c=t, s=t) and notes naming their own buffer, in any window.
  fire: EX-t firings by site and outcome; KT-s firings at EX sites.
  R/S outcomes: outside buffer / exchange with the other slot / none found / throw / other."""
import json, sys, collections, re

def none(x): return x in (None, "-")

def violations(w):
    """w: a triquetra snapshot {c,s,t,dtm,dsm}. Returns set of 'ter'/'sec'."""
    out = set()
    c = w.get("c")
    if none(c): return out
    for kind, slot, m in (("ter", w.get("t"), w.get("dtm")), ("sec", w.get("s"), w.get("dsm"))):
        if none(slot) or not isinstance(m, dict): continue
        p = m.get(c); sw = m.get(c + "-swap")
        r = sw if (sw is not None and sw != slot) else p
        if r == slot: out.add(kind)
    return out

def dups(w):
    out = []
    c, s, t = w.get("c"), w.get("s"), w.get("t")
    if not none(c) and c == s: out.append("c=s")
    if not none(c) and c == t: out.append("c=t")
    if not none(s) and s == t: out.append("s=t")
    for mk in ("dtm", "dsm"):
        m = w.get(mk)
        if isinstance(m, dict):
            for k, v in m.items():
                if k.replace("-swap", "") == v: out.append(mk + "-self")
    return out

def windows(st):
    """(label, snapshot) for every window with a triquetra."""
    if isinstance(st.get("wins"), dict):
        return [(k, v) for k, v in st["wins"].items() if isinstance(v, dict) and not v.get("none")]
    return [("cur", st)] if not st.get("none") else []

def cur(st):
    return st if not st.get("none") else None

def restore_outcome(a, s, pv):
    """Outcome of an R/S step, from its notes, error and the slots before it."""
    err = s.get("err") or ""
    if "is the same as current" in err: return "throw"
    if err: return "error"
    notes = " ".join(n["m"] for n in s["notes"])
    kind = "ternary" if a == "R" else "secondary"
    other = "s" if a == "R" else "t"
    if f"Restored {kind} slot" in notes:
        new = s["st"].get("t" if a == "R" else "s")
        return "exchange" if (pv and new == pv.get(other)) else "outside"
    if f"No {kind} relationship found" in notes: return "none"
    if "not found in filesystem" in notes: return "missing"
    return "other"

def scan(path):
    R = dict(path=path, steps=0, walks=0, runfail=0, cur=collections.Counter(), any=collections.Counter(),
             any_steps=0, cur_steps=0, fresh=collections.Counter(), throws=collections.Counter(), throw_walks={"ternary": set(), "secondary": set()},
             other_err=collections.Counter(), hookfail=collections.Counter(), dup=collections.Counter(),
             ext=collections.Counter(), ext_out=collections.Counter(), kts_ex=collections.Counter(),
             R=collections.Counter(), S=collections.Counter(), examples={})
    for wi, line in enumerate(open(path)):
        w = json.loads(line); steps = w["steps"]; R["walks"] += 1
        if len(steps) != len(w["seq"]): R["runfail"] += 1
        prev_v = {}
        for i, s in enumerate(steps):
            R["steps"] += 1
            st = s["st"]; a = s["a"]
            pv = steps[i - 1]["st"] if i else None
            # I23
            c = cur(st)
            cv = violations(c) if c else set()
            for k in cv: R["cur"][k] += 1
            if cv: R["cur_steps"] += 1
            anyv = False
            now_v = {}
            for lab, ws in windows(st):
                vs = violations(ws)
                now_v[lab] = vs
                for k in vs:
                    R["any"][k] += 1; anyv = True
                    if k not in prev_v.get(lab, set()):
                        R["fresh"][(k, a)] += 1
                        R["examples"].setdefault((k, a), (wi, " ".join(w["seq"][:i + 1])))
                for d in dups(ws): R["dup"][d] += 1
            if anyv: R["any_steps"] += 1
            prev_v = now_v
            # errors
            err = s.get("err") or ""
            if "is the same as current" in err:
                typ = "secondary" if "secondary" in err else "ternary"
                R["throws"][typ] += 1; R["throw_walks"][typ].add(wi)
            elif err:
                R["other_err"][re.sub(r"[0-9a-f]{16}", "#", err)[:120]] += 1
            for n in s["notes"]:
                m = n["m"]
                if m.startswith("Hook '") or "Duplicates detected" in m:
                    R["hookfail"][re.sub(r"[0-9a-f]{16}", "#", m)[:140]] += 1
                if m.startswith("EX-t "):
                    parts = m.split()
                    R["ext"][parts[1]] += 1; R["ext_out"][(parts[1], parts[-1])] += 1
                if m.startswith("KT-s ex-") or m.startswith("KT-s ter-restore") or m.startswith("KT-s grad"):
                    R["kts_ex"][(m.split()[1], m.split()[2])] += 1
            if a in ("R", "S"):
                pvc = cur(pv) if pv else None
                R[a][restore_outcome(a, s, pvc)] += 1
    R["throw_walks"] = {k: len(v) for k, v in R["throw_walks"].items()}
    return R

def show(R):
    print(f"== {R['path'].split('/')[-1]}  walks {R['walks']} steps {R['steps']} runfail {R['runfail']}")
    print(f"  I23 current window: {sum(R['cur'].values())} ({dict(R['cur'])}) in {R['cur_steps']} steps;"
          f" any window: {sum(R['any'].values())} ({dict(R['any'])}) in {R['any_steps']} steps")
    if R["fresh"]: print("  fresh violations by key:", dict(R["fresh"]))
    print(f"  restore throws: {dict(R['throws'])} walks {R['throw_walks']}; other errors {sum(R['other_err'].values())}; hook failures {sum(R['hookfail'].values())}; dup/self {dict(R['dup'])}")
    for k, v in R["other_err"].items(): print("    other:", v, k)
    for k, v in R["hookfail"].items(): print("    hook:", v, k)
    if R["ext"]: print("  EX-t by site:", dict(R["ext"]), " outcomes:", {f"{a}/{b}": n for (a, b), n in R["ext_out"].items()})
    if R["kts_ex"]: print("  secondary check at slot changes (site/outcome):", {f"{a}/{b}": n for (a, b), n in R["kts_ex"].items()})
    print("  R outcomes:", dict(R["R"]), " S outcomes:", dict(R["S"]))
    for k, v in list(R["examples"].items())[:6]: print("  example", k, "walk", v[0], ":", v[1])

if __name__ == "__main__":
    js = "--json" in sys.argv
    for p in [x for x in sys.argv[1:] if not x.startswith("--")]:
        R = scan(p)
        if js:
            R2 = {k: ({(" ".join(kk) if isinstance(kk, tuple) else kk): vv for kk, vv in v.items()} if isinstance(v, dict) else v) for k, v in R.items()}
            print(json.dumps(R2))
        else:
            show(R)
