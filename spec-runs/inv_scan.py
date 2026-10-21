import json, sys, collections
for fn in sys.argv[1:]:
    plain = collections.Counter(); used = collections.Counter(); steps = 0; ex = {}
    for l in open(fn):
        w = json.loads(l)
        for s in w['steps']:
            st = s['st']; steps += 1
            c = st['c']
            if c in (None, '-'): continue
            for kind, slot, m in (('ter', st['t'], st['dtm']), ('sec', st['s'], st['dsm'])):
                if slot in (None, '-') or not isinstance(m, dict): continue
                p = m.get(c); sw = m.get(c + '-swap')
                if p == slot:
                    plain[(kind, s['a'])] += 1
                    ex.setdefault(('plain', kind), (w['seq'][:s['i']], st))
                # note the restore would read under the decided lookup (own slot)
                r = sw if (sw is not None and sw != slot) else p
                if r == slot:
                    used[(kind, s['a'])] += 1
                    ex.setdefault(('used', kind), (w['seq'][:s['i']], st))
    print(fn, 'steps', steps)
    print('  plain note == slot occupant:', sum(plain.values()), dict(plain))
    print('  note the restore would read == slot occupant:', sum(used.values()), dict(used))
    for k, v in ex.items(): print('  example', k, ' '.join(v[0]))
