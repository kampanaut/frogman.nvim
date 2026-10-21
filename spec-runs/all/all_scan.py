#!/usr/bin/env python3
"""ALL scan of walk files (all/walks/*.jsonl). Reuses ex/ex_scan.py's I23 lookup (violations) and restore classification.
Per file:
  I23: as ex_scan: the note a restore would read (swap note when set and not the slot's occupant, else the plain note)
       names that slot's occupant. Counted per (step, map) at the current window ('cur') and over every window ('any'),
       plus the steps with at least one.
  I1:  a buffer in two slots (c=s, c=t, s=t), at the current window and in any window; steps with one.
  self: notes naming their own buffer (kept apart from I1).
  fill: fill-assertion firings ("ALL-fill-assert"); 'would' = fills from history (or firings) whose ordered list before
        the key didn't start with the window's current buffer (the same test, computed for code without the assertion).
  throws: restore throws, ternary / secondary ("is the same as current").
  dupdet: "Duplicates detected" (thrown, or inside a hook failure).
  other: any other error; hook: any other hook failure.
  cancel: window-jump cancels; cancel_moved: a reconcile that moved a slot during a cancel; q9: Q9 pick notes;
  cycling: steps that end with navigation still cycling."""
import json, sys, re, collections
sys.path.insert(0, "@RUNS@/ex")
from ex_scan import violations, windows, cur, none

def slotdups(w):
    c, s, t = w.get("c"), w.get("s"), w.get("t")
    out = []
    if not none(c) and c == s: out.append("c=s")
    if not none(c) and c == t: out.append("c=t")
    if not none(s) and s == t: out.append("s=t")
    return out

def selfnotes(w):
    out = []
    for mk in ("dtm", "dsm"):
        m = w.get(mk)
        if isinstance(m, dict):
            for k, v in m.items():
                if k.replace("-swap", "") == v: out.append(mk)
    return out

H = re.compile(r"[0-9a-f]{16}")
def clean(m): return H.sub("#", re.sub(r"^.*?/lua/cavediver/", "", m))

def scan(path):
    R = collections.defaultdict(int)
    C = {k: collections.Counter() for k in ("other", "hook", "dupdet", "i23cur", "i23any", "i1cur", "i1any")}
    EX = collections.defaultdict(list)  # kind -> [(walk, step)]
    for wi, line in enumerate(open(path)):
        w = json.loads(line); steps = w["steps"]; R["walks"] += 1
        if len(steps) != len(w["seq"]): R["runfail"] += 1
        for i, s in enumerate(steps):
            R["steps"] += 1
            st = s["st"]; a = s["a"]; pv = steps[i - 1]["st"] if i else None
            c = cur(st)
            cv = violations(c) if c else set()
            for k in cv: R["i23_cur"] += 1; C["i23cur"][k] += 1
            if cv: R["i23_cur_steps"] += 1; EX["i23cur"].append((wi, i))
            anyv = 0; anyd = 0
            for lab, ws in windows(st):
                vs = violations(ws)
                for k in vs: R["i23_any"] += 1; C["i23any"][k] += 1; anyv = 1
                d = slotdups(ws)
                for k in d: C["i1any"][k] += 1; anyd = 1
                if selfnotes(ws): R["self_any"] += 1
            if anyv: R["i23_any_steps"] += 1; EX["i23any"].append((wi, i))
            cd = slotdups(c) if c else []
            for k in cd: C["i1cur"][k] += 1
            if cd: R["i1_cur_steps"] += 1; EX["i1cur"].append((wi, i))
            if anyd: R["i1_any_steps"] += 1; EX["i1any"].append((wi, i))
            err = s.get("err") or ""
            notes = [n["m"] for n in s["notes"]]
            filled = any("Secondary buffer populated from history." in m for m in notes)
            if "ALL-fill-assert" in err:
                R["fill_assert"] += 1; EX["fill"].append((wi, i))
            if filled or "ALL-fill-assert" in err:
                R["fills"] += 1
                if pv and not pv.get("none"):
                    o = (pv.get("ord") or "").split(",")
                    if o and o[0] and o[0] != pv.get("c"): R["fill_would"] += 1; EX["would"].append((wi, i))
            if "is the same as current" in err:
                typ = "secondary" if "secondary" in err else "ternary"
                R["throw_" + typ] += 1; EX["throw_" + typ].append((wi, i))
            elif "Duplicates detected" in err:
                R["dupdet"] += 1; C["dupdet"]["thrown: " + clean(err)[:100]] += 1; EX["dupdet"].append((wi, i))
            elif "ALL-fill-assert" in err:
                pass
            elif err:
                R["other"] += 1; C["other"][clean(err)[:110]] += 1; EX["other"].append((wi, i))
            for m in notes:
                if "Duplicates detected" in m:
                    R["dupdet"] += 1; C["dupdet"]["hook: " + clean(m)[:120]] += 1; EX["dupdet"].append((wi, i))
                elif m.startswith("Hook '"):
                    R["hook"] += 1; C["hook"][clean(m)[:140]] += 1; EX["hook"].append((wi, i))
                if m.startswith("WV-cancel"): R["cancel"] += 1
                if m.startswith("ALL-cancel-reconcile-moved"): R["cancel_moved"] += 1; EX["cancel_moved"].append((wi, i))
                if m.startswith("ALL-q9"): R["q9"] += 1
                if m.startswith("EX-t "): R["ext"] += 1
            if st.get("nav") == "cycling": R["cycling"] += 1
    return dict(R), {k: dict(v) for k, v in C.items()}, {k: v for k, v in EX.items()}

if __name__ == "__main__":
    for p in sys.argv[1:]:
        R, C, EX = scan(p)
        print("==", p.split("/")[-1]); print(" ", json.dumps(R)); 
        for k, v in C.items():
            if v: print("  ", k, json.dumps(v))
        for k, v in EX.items(): print("   ex", k, v[:5])
