#!/usr/bin/env python3
"""ALL: fill spec/all/report/ALL.tmpl.md with the report parts in spec/all/report/ and the generated table, into packets/ALL.md."""
S = "@RUNS@"
r = f"{S}/spec/all/report/"
t = open(f"{S}/spec/all/report/ALL.tmpl.md").read()
table = open(r + "table.txt").read().split("\n\n")
main, tots = table[0].strip(), table[1].strip()
main = main.replace("| all fixes |", "| every fix |").replace("| today's code |", "| today |")
tots = tots.replace("| all fixes |", "| every fix |").replace("| today's code |", "| today |").replace("| both |", "| both views |")
num = open(r + "numbers.md").read().replace("{{TABLE}}", main).replace("{{TOTALS}}", tots)
oneline = open(r + "oneline.md").read().strip()
parts = dict(ONELINE=oneline, SHORT=open(r + "short.md").read().strip(), CODE=open(r + "code.md").read().strip(),
             CHECKS=open(r + "checks.md").read().strip(), NUMBERS=num.strip(), REPEAT=open(r + "repeat.md").read().strip(),
             TODAY=open(r + "today.md").read().strip(), LEFT=open(r + "left.md").read().strip() + "\n\n" + oneline, RUNS=open(r + "runs.md").read().strip())
for k, v in parts.items(): t = t.replace("{{" + k + "}}", v)
assert "{{" not in t
open(f"{S}/packets/ALL.md", "w").write(t)
print(len(t))
