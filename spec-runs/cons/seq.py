#!/usr/bin/env python3
# Usage: seq.py <variant|today> "<seq>"  -> rows, via rt_runseq.sh in its own job dir
import json, subprocess, sys, os
SPEC = os.path.dirname(os.path.abspath(__file__)) + "/../spec"
REPO = os.environ["CDV_REPO"]
v, seq = sys.argv[1], sys.argv[2]
plugin = REPO if v == "today" else f"{SPEC}/variants/{v}"
p = subprocess.run([f"{SPEC}/rt/rt_runseq.sh", f"cons-{v}-{os.getpid()}", plugin, seq], stdout=subprocess.PIPE, timeout=120)
names = {"F": "<M-f>", "G": "<M-S-f>", "R": "<M-;><M-r>", "S": "<M-;><M-t>", "P": "<M-;><M-c>", "J": "<M-;><M-f>",
         "X1": "<M-m> <M-v>", "X2": "<M-n> <M-v>", "X3": "<M-m> <M-m> <M-v>"}
def n(x): return "-" if x in (None, "-") else x.replace(".txt", "")
def m(d):
    if not isinstance(d, dict): return ""
    return " ".join(sorted(f"{n(k)}>{n(v)}" for k, v in d.items()))
for l in p.stdout.decode(errors="replace").splitlines():
    if not l.startswith("{"): continue
    s = json.loads(l); st = s["st"]; a = s["a"]
    lab = (":e " + a[1]) if (a[0] == "e" and len(a) == 2) else names.get(a, a)
    msg = ""
    if not s["ok"]: msg = "  ERROR: " + (s.get("err") or "")[:90]
    elif s["notes"]: msg = "  «" + "; ".join(x["m"][:70] for x in s["notes"] if x.get("l", 0) >= 2) + "»"
    pe = f" p=[{','.join(n(x) for x in st.get('p', []))}]{'on' if st.get('pe') else 'off'}" if st.get('p') else ""
    print(f"{lab:<20} ⦉{n(st.get('t'))}⦊ [{n(st.get('c'))}] ⟦{n(st.get('s'))}⟧{pe}   dtm{{{m(st.get('dtm'))}}} dsm{{{m(st.get('dsm'))}}}{msg if msg != '  «»' else ''}")
