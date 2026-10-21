#!/usr/bin/env python3
# Writes tests/REVIEW.md: one entry per test case, with its steps, its checks and the spec entry for the same ID.
# Run from anywhere: python3 scripts/make_review.py
import re, glob, os
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
spec = open('what-is-cavediver.md').read().split('\n')
specT = {}
for l in spec:
    m = re.match(r'^- (T\d+) \[([a-z]+)\]\s*(.*)', l)
    if m and m.group(1) not in specT:
        specT[m.group(1)] = (m.group(2), m.group(3))
CHANGED = {'T111': 'route changed so it fails for the right reason (the first route passed by luck)',
           'T128': 'walks raised to 100 so the break shows up (about 3% of walks break today)',
           'T129': ':enew and <M-.> doubled in the walk mix to reach the break more often',
           'T146': 'the split visits a file first, so the save reaches the oil case',
           'T242': 'wipes the window\'s current buffer: the bug only shows for that one',
           'T247': 'an acwrite window whose current file is :bdeleted from the focused window, to reach the healing branch',
           'T235': 'the save runs in pcall, since the hole makes the pop-up\'s redraw throw',
           'T212': 'the child\'s umask forced to 022, so the result doesn\'t depend on the runner'}
HAND_PAT = re.compile(r'set_note\(|X\.set\(|displacement_(ternary|secondary)_map\[|data\.crux\[|nvim_buf_set_name|register_buffer\(|track_buffer\(|rename_hash_in_triquetras|ordered\.crux\[|noautocmd')
WALK_PAT = re.compile(r'walk', re.I)

def strs(s):
    return re.findall(r"'((?:[^'\\]|\\.)*)'|\"((?:[^\"\\]|\\.)*)\"", s)

def flat(pairs):
    return [a or b for a, b in pairs]

def parse(path):
    whole = open(path).read()
    src = whole.split('\n')
    arrays = {}
    for am in re.finditer(r'local\s+([A-Za-z_][A-Za-z_0-9]*)\s*=\s*\{(.*?)\}', whole, re.S):
        vals = flat(strs(am.group(2)))
        if vals and all(v.startswith((':', '<')) for v in vals):
            arrays[am.group(1)] = vals
    cases = []
    i = 0
    while i < len(src):
        l = src[i]
        m = re.match(r"^T\[(['\"])(.*)\1\]\s*=\s*function", l)
        if not m:
            i += 1; continue
        name = m.group(2).replace("\\'", "'").replace('\\"', '"')
        if re.search(r'function\(\)\s.*\send\s*$', l):
            j = i
            body = [l.split('function()', 1)[1].rsplit('end', 1)[0]]
        else:
            j = i + 1
            while j < len(src) and src[j] != 'end':
                j += 1
            body = src[i + 1:j]
        text = '\n'.join(body)
        steps = []
        for sm in re.finditer(r'child\.steps\((\{(.*?)\}|[A-Za-z_][A-Za-z_0-9]*)\)', text, re.S):
            if sm.group(2) is not None:
                steps += flat(strs(sm.group(2)))
            elif sm.group(1) in arrays:
                steps += arrays[sm.group(1)]
        for sm in re.finditer(r'child\.step\((["\'])(.*?)\1\)', text):
            steps.append(sm.group(2))
        for sm in re.finditer(r'child\.cmd\((["\'])(.*?)\1\)', text):
            steps.append(':' + sm.group(2))
        exp = []
        for bl in body:
            b = bl.strip()
            if b.startswith('eq(') or 'expect.' in b:
                mm = re.match(r"eq\(child\.(slots|notes|primary|shown|ordered|closed)\([^)]*\),\s*(.*)\)\s*$", b)
                if mm:
                    exp.append(f"{mm.group(1)} = {mm.group(2)}")
                else:
                    exp.append(b[:150])
        events = []
        for sm in re.finditer(r'child\.steps\((\{(.*?)\}|[A-Za-z_][A-Za-z_0-9]*)\)', text, re.S):
            vals = flat(strs(sm.group(2))) if sm.group(2) is not None else arrays.get(sm.group(1), [sm.group(1)])
            events.append((sm.start(), 'step', vals))
        for sm in re.finditer(r'child\.step\((["\'])(.*?)\1\)', text):
            events.append((sm.start(), 'step', [sm.group(2)]))
        for sm in re.finditer(r'child\.cmd\((["\'])(.*?)\1\)', text):
            events.append((sm.start(), 'step', [':' + sm.group(2)]))
        # keys pressed through a local wrapper, e.g. clean('<M-;><M-t>') or K.press_after(child, code, '<M-f>')
        for sm in re.finditer(r'([A-Za-z_][A-Za-z_0-9.]*)\(([^()]*?)(["\'])((?:<[A-Za-z0-9\-;,.]+>)+)\3', text):
            fn = sm.group(1)
            if fn in ('child.step', 'child.steps', 'child.cmd', 'eq', 'K.has', 'Extra.has', 'vim.fn.maparg', 'maparg', 'Helpers.expect.no_equality') or fn.endswith('.has') or fn.split('.')[-1] in ('has', 'find', 'join', 'ipairs', 'pairs', 'rep', 'format', 'match', 'gsub', 'insert', 'tostring', 'contains', 'tbl_contains'):
                continue
            events.append((sm.start(), 'step', [sm.group(4) + ' (via ' + fn + ')']))
        for sm in re.finditer(r'^[ \t]*(eq\(.*|.*expect\..*)$', text, re.M):
            ln = sm.group(1).strip()
            mm = re.match(r"eq\(child\.(slots|notes|primary|shown|ordered|closed)\([^)]*\),\s*(.*)\)\s*$", ln)
            events.append((sm.start(), 'exp', (mm.group(1) + ' = ' + mm.group(2)) if mm else ln[:150]))
        events.sort(key=lambda e: e[0])
        seq = []
        pend = []
        for _, kind, v in events:
            if kind == 'step':
                pend += v
            else:
                seq.append((pend, v)); pend = []
        if pend:
            seq.append((pend, None))
        comments = [bl.strip()[2:].strip() for bl in body if bl.strip().startswith('--')][:3]
        # also comments right above the case
        k = i - 1; above = []
        while k >= 0 and src[k].strip().startswith('--'):
            above.insert(0, src[k].strip()[2:].strip()); k -= 1
        tid = re.match(r'(T\d+|[DQA]\d+)', name)
        tid = tid.group(1) if tid else '?'
        tag = re.search(r'\[(char|today|target)\]', name)
        tag = tag.group(1) if tag else '?'
        flags = []
        if HAND_PAT.search(text): flags.append('state set by hand')
        if WALK_PAT.search(text) or WALK_PAT.search(name): flags.append('random walk')
        if tid in CHANGED: flags.append(CHANGED[tid])
        cases.append(dict(id=tid, tag=tag, name=name, steps=steps, exp=exp, seq=seq, notes=above + comments, flags=flags, line=i + 1))
        i = j + 1
    return cases

files = sorted(glob.glob('tests/test_*.lua'))
order = ['tests/test_keep_older.lua'] + [f for f in files if f != 'tests/test_keep_older.lua']
allc = {f: parse(f) for f in order}
total = sum(len(v) for v in allc.values())
out = []
w = out.append
w('# Test review sheet')
w('')
w(f'{total} cases in {len(order)} files, generated from `tests/` and `what-is-cavediver.md`. For each case: is the route how you\'d really use cavediver, is the expected result what you want, is the tag right?')
w('')
w('- **[char]**: intended, and true today. **[today]**: today\'s behaviour, expected to flip when its fix lands. **[target]**: decided, not built; fails until its fix lands.')
w('- Slots read `⦉ternary⦊ [current] ⟦secondary⟧`. Notes read `dtm{…}` (what `<M-;><M-r>` restores) and `dsm{…}` (what `<M-;><M-t>` restores); `b>a` is b\'s note, `b-swap>a` its swap note.')
w('- Each line reads steps → what is checked after them. `:e a` opens a.txt; `<M-f>` and the like press the mapped key; other `:` lines are Ex commands. Steps run in the order shown.')
w('- "spec" quotes the spec\'s entry for the same ID, so you can see the test says what the spec says.')
w('')
w('## Look at these first')
w('')
for label in ['state set by hand', 'random walk']:
    ids = [(f, c) for f in order for c in allc[f] if label in c['flags']]
    w(f'**{label.capitalize()}** ({len(ids)}): ' + ', '.join(f"{c['id']} ({os.path.basename(f)[5:-4]})" for f, c in ids))
    w('')
seen=set(); ch=[]
for f in order:
    for c in allc[f]:
        if c['id'] in CHANGED and c['id'] not in seen:
            seen.add(c['id']); ch.append((f, c))
w('**Routes changed by the porting agents** so a target fails for the right reason:')
for f, c in ch:
    w(f"- {c['id']} ({os.path.basename(f)}): {CHANGED[c['id']]}")
w('')
w('**Doc checks**: everything in `tests/test_docs.lua` (README and comment wording).')
w('')
for f in order:
    cs = allc[f]
    tags = {}
    for c in cs: tags[c['tag']] = tags.get(c['tag'], 0) + 1
    w(f"## {f} ({len(cs)} cases: " + ', '.join(f"{n} {t}" for t, n in sorted(tags.items())) + ')')
    w('')
    for c in cs:
        flag = (' ⚑ ' + '; '.join(c['flags'])) if c['flags'] else ''
        title = re.sub(r'^\S+\s+\[[a-z]+\]\s*', '', c['name'])
        w(f"**{c['id']} [{c['tag']}]** {title}{flag}  ")
        shown = 0
        for st, e in c['seq']:
            if shown >= 8:
                w(f'… and {len(c["seq"]) - 8} more  '); break
            left = ('`' + '`, `'.join(st[:20]) + '`' + (' …' if len(st) > 20 else '')) if st else ''
            right = ('`' + e.replace('`', "'") + '`') if e else ''
            if left and right: w(f'{left} → {right}  ')
            elif left: w(f'{left}  ')
            elif right: w(f'→ {right}  ')
            shown += 1
        if c['notes']:
            w('note: ' + ' '.join(c['notes'])[:300] + '  ')
        st = specT.get(c['id'])
        if st:
            mark = '' if st[0] == c['tag'] else f' (spec tag: [{st[0]}])'
            w(f"spec: {st[1][:280]}{'…' if len(st[1]) > 280 else ''}{mark}  ")
        w(f"`{f}:{c['line']}`")
        w('')
open('tests/REVIEW.md', 'w').write('\n'.join(out) + '\n')
print(total, 'cases;', len(out), 'lines')
