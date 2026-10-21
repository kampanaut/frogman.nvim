#!/usr/bin/env python3
"""Fills KT.tmpl.md into ../packets/KT.md from the walk files and the rendered row blocks."""
import subprocess, re
SPEC = "@RUNS@"
def sh(*a): return subprocess.run(a, capture_output=True, text=True, cwd=SPEC, check=True).stdout
t = open(f"{SPEC}/kt/KT.tmpl.md").read()
# numbers table
rows = []
for line in sh("python3", "kt/kt_table.py", "rt_c3kga,rt_tb,kt_literal,kt_rewrite,kt_drop,kt_rewrite_sec", "7,11").splitlines()[1:]:
    f = [x.strip() for x in line.split("|")]
    v, sd, tt, ts, oerr, hook, kt, ks, tb, dup, self_ = f[:11]
    assert "RUNFAIL" not in line and dup == "0" and self_ == "0", line
    tot, buf, sec, nil, same = [x.strip() for x in kt.split("/")]
    rw, dr = [x.strip() for x in ks.split("/")]
    oe = int(oerr) + int(hook)
    if v == "rt_tb": fired, cols = f"{tb} (drops)", ["–"] * 4
    elif v == "rt_c3kga": fired, cols = "–", ["–"] * 4
    elif v == "kt_drop": fired, cols = f"{tot} (drops)", ["–", "–", tot, "–"]
    else: fired, cols = tot, [buf, sec, nil, same]
    secc = f"{rw} / {dr}" if v == "kt_rewrite_sec" else "not counted (drops)" if v in ("rt_c3kga", "kt_rewrite", "kt_literal", "kt_drop") else "–"
    tt2 = tt.replace(" (", " (").replace(")", ")")
    rows.append(f"| `{v}` | {sd} | {tt} | {ts} | {oe} | {fired} | " + " | ".join(cols) + f" | {secc} |")
t = t.replace("{{table}}", "\n".join(rows))
# by kind
bk = sh("python3", "kt/kt_bykind.py", "rt/walks/kt_rewrite-1500-25-7.jsonl", "rt/walks/kt_rewrite-1500-25-11.jsonl").splitlines()
out = []
for line in bk[1:]:
    f = [x.strip() for x in line.split("|")]
    if f[0] == "all": out.append(f"| **all** | | **{f[2]}** | **{f[3]}** | **{f[4]}** | **{f[6]}** |"); continue
    assert f[5] == "0"
    name = f[0] if f[0].startswith("<") is False else f[0]
    name = re.sub(r"(<[^ ]+>(?:<[^ ]+>)?)", r"`\1`", name).replace(":e ", "plain `:e` ") if not f[0].startswith(":e") else "plain `:e` onto the secondary"
    rule = {"c1": "navigation's first case", "c2": "navigation's second case", "kept": "the kept ternary's own note"}[f[1]]
    out.append(f"| {name} | {rule} | {f[2]} | {f[3]} | {f[4]} | {f[6]} |")
t = t.replace("{{bykind}}", "\n".join(out))
# secondary by kind
sb = sh("python3", "kt/kt_bykind.py", "rt/walks/kt_rewrite_sec-1500-25-7.jsonl", "rt/walks/kt_rewrite_sec-1500-25-11.jsonl")
sb = sb.split("secondary side:")[1].splitlines()[1:]
out = []
for line in sb:
    f = [x.strip() for x in line.split("|")]
    if len(f) < 5: continue
    if f[0] == "all": out.append(f"| **all** | **{f[2]}** | **{f[3]}** |"); continue
    name = {":e (other)": "plain `:e` to another buffer", ":e onto the ternary": "plain `:e` onto the ternary", "<M-;><M-r>": "`<M-;><M-r>` exchanging the ternary with the secondary", "graduation": "graduation (`<M-f>` or `<M-;><M-f>` on an empty secondary)"}.get(f[0], f[0])
    name = re.sub(r"(?<!`)(<M-S-f>)", r"`\1`", name)
    out.append(f"| {name} | {f[2]} | {f[3]} |")
t = t.replace("{{secbykind}}", "\n".join(out))
for b in ("bonus1", "bonus2", "bonus2nav", "pickout", "tosec", "secgain"):
    t = t.replace("{{b_" + b + "}}", open(f"{SPEC}/kt/b_{b}.md").read().rstrip())
again = sh("python3", "kt/blocks.py", "rt_bonus1_again", "kt_rewrite").splitlines()
t = t.replace("{{again}}", again[-2])
assert "{{" not in t
open(f"{SPEC}/../packets/KT.md", "w").write(t)
print("written", len(t.splitlines()), "lines")
