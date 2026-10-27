#!/usr/bin/env python3
"""Criterion-level comparison of harness runs. Usage: compare.py <final dirs, later overrides earlier, comma-sep> <out csv> <run dir>...
Every run dir is read as {case: {criterion: (pass, detail)}} plus probes; the final result merges the final dirs."""
import json, glob, os, sys, csv

def load(d):
    out = {}
    for f in sorted(glob.glob(os.path.join(d, '[PN][0-9]*.json'))):
        r = json.load(open(f))
        out[r['id']] = {c['id']: (c['pass'], c['kind'], c.get('detail', ''), c.get('text', '')) for c in r['criteria']}
    p = os.path.join(d, 'probes.json')
    if os.path.exists(p):
        for x in json.load(open(p)):
            out[x['id']] = {x['id']: (x['pass'], 'probe', x['observed'], x['rule'])}
    return out

final_dirs = sys.argv[1].split(','); out_csv = sys.argv[2]; runs = sys.argv[3:]
final = {}
for d in final_dirs:
    final.update(load(d))
data = {os.path.basename(d.rstrip('/')): load(d) for d in runs}
names = list(data)
def res(v): return '' if v is None else ('PASS' if v[0] else 'FAIL')
rows = []
for case in sorted(final, key=lambda k: (k[0] != 'P', k[0] != 'N', k)):
    for cid, v in final[case].items():
        hist = [res(data[n].get(case, {}).get(cid)) or 'n/a' for n in names]
        rows.append((case, cid, v[1], v[3], hist, res(v), v[2]))
w = csv.writer(open(out_csv, 'w', newline=''))
w.writerow(['case', 'criterion', 'kind', 'criterion_text'] + [f'{n}_result' for n in names] + ['final_result', 'evidence'])
for r in rows:
    w.writerow([r[0], r[1], r[2], r[3]] + r[4] + [r[5], r[6]])
# summary
def tot(dd):
    prof = [k for k in dd if k[0] in 'PN' and k[1:].isdigit()]
    pr = [k for k in dd if k[0] == 'X']
    pp = sum(all(v[0] or v[1] == 'science-advisory' for v in dd[k].values()) for k in prof)
    return f'profiles {pp}/{len(prof)}, probes {sum(all(v[0] for v in dd[k].values()) for k in pr)}/{len(pr)}'
for n in names: print(n, tot(data[n]))
print('final', tot(final))
for r in rows:
    if r[5] == 'FAIL' and r[2] != 'science-advisory': print('FAIL', r[0], r[1], r[2], r[4], r[6][:200])
    elif any(h == 'PASS' for h in r[4]) and r[5] == 'FAIL': print('REGRESSION', r[0], r[1], r[4])
