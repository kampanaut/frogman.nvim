#!/usr/bin/env python3
import re, subprocess, sys
P = "@RUNS@/packets"
B = "@RUNS@/rt/blocks.py"
t = open("@RUNS@/rt/RT.tmpl.md").read()
def rep(m):
    return subprocess.run(["python3", B, m.group(1), m.group(2)], stdout=subprocess.PIPE, check=True).stdout.decode().rstrip()
open(P + "/RT.md", "w").write(re.sub(r"\{\{B (\S+) (\S+)\}\}", rep, t))
print("ok")
