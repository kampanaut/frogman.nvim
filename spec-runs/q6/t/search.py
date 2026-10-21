#!/usr/bin/env python3
"""BFS over real key sequences, deduping prefixes that reach the same observable state.

Usage: search.py <variant> <maxdepth> <actions> [files]
  actions: comma list from F,G,R,S,X1,X2,X3,P,J ; edits are always included (files a..d by default)
Reports, per depth, sequences where a toggle_secondary (F) / jump_to_primary (J) / cycle pick of the
secondary (X*) step emits the "Avoided conflict" WARN.
"""
import json, os, subprocess, sys, itertools
from concurrent.futures import ThreadPoolExecutor

Q6 = "@RUNS@/q6"
variant = sys.argv[1]
maxdepth = int(sys.argv[2])
acts = sys.argv[3].split(",") if len(sys.argv) > 3 and sys.argv[3] else []
files = list(sys.argv[4]) if len(sys.argv) > 4 else list("abcd")
plugin = os.path.join(Q6, "variants", variant)
counter = itertools.count()


def run(seq):
    jid = f"{variant}-{os.getpid()}-{next(counter)}"
    p = subprocess.run([os.path.join(Q6, "t", "runseq.sh"), jid, plugin, " ".join(seq)],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    lines = [json.loads(l) for l in p.stdout.decode(errors="replace").splitlines() if l.startswith("{")]
    return lines


def sig(st):
    return json.dumps(st, sort_keys=True)


def expansions(seq, st):
    used = []
    for a in seq:
        if a.startswith("e") and len(a) == 2 and a[1] not in used:
            used.append(a[1])
    out = []
    for f in files:
        if f in used:
            if st.get("shown") != f + ".txt":
                out.append("e" + f)
        elif len(used) < len(files) and f == files[len(used)]:
            out.append("e" + f)  # canonical: only the lowest unused file is opened new
    if seq:
        out += acts
    return out


def is_hit(parent, step):
    if not any("Avoided conflict" in n["m"] for n in step["notes"]):
        return None
    a = step["a"]
    if a == "F":
        return "F"
    if a == "J":
        return "J"
    if a.startswith("X"):
        if parent and parent.get("s") == step["st"].get("c"):
            return "pick-secondary"
        return "pick-outside"
    return "other:" + a


def main():
    seen = {}
    frontier = [([], {})]
    hits = []
    for depth in range(1, maxdepth + 1):
        cands = []
        for seq, st in frontier:
            for a in expansions(seq, st):
                cands.append((seq + [a], st))
        with ThreadPoolExecutor(16) as ex:
            results = list(ex.map(lambda c: (c, run(c[0])), cands))
        nf = []
        for (seq, parent), lines in results:
            if len(lines) != len(seq):
                print("RUNFAIL", " ".join(seq), file=sys.stderr)
                continue
            step = lines[-1]
            h = is_hit(parent, step)
            if h:
                hits.append((depth, h, seq))
            s = sig(step["st"])
            if s not in seen:
                seen[s] = seq
                nf.append((seq, step["st"]))
        frontier = nf
        kinds = {}
        for d, h, s in hits:
            if d == depth:
                kinds.setdefault(h, []).append(" ".join(s))
        print(f"depth {depth}: ran {len(cands)}, new states {len(nf)}, hits {{" +
              ", ".join(f"{k}: {len(v)}" for k, v in kinds.items()) + "}", flush=True)
        for k, v in kinds.items():
            for s in v[:5]:
                print(f"   {k}: {s}", flush=True)
    json.dump([{"depth": d, "kind": h, "seq": s} for d, h, s in hits],
              open(os.path.join(Q6, f"hits-{variant}-{maxdepth}-{'_'.join(acts) or 'none'}.json"), "w"))


if __name__ == "__main__":
    main()
