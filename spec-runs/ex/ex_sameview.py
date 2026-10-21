#!/usr/bin/env python3
"""EX: are the global-view and window-view walk files the same, step by step, once the 'view' field is stripped and file hashes in messages (which depend on the job's path) are masked?
Usage: ex_sameview.py <global.jsonl> <window.jsonl>"""
import json, sys, re
def strip(x):
    if isinstance(x, dict): return {k: strip(v) for k, v in x.items() if k != "view"}
    if isinstance(x, list): return [strip(v) for v in x]
    if isinstance(x, str): return re.sub(r"[0-9a-f]{16}", "#", x)
    return x
a, b = sys.argv[1], sys.argv[2]; nd = ns = 0
for la, lb in zip(open(a), open(b)):
    wa, wb = json.loads(la), json.loads(lb)
    for sa, sb in zip(wa["steps"], wb["steps"]):
        ns += 1
        if strip(sa) != strip(sb): nd += 1
print(b.split("/")[-1], "vs", a.split("/")[-1], ": steps", ns, "differing", nd)
