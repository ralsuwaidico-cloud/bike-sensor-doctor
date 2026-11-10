#!/usr/bin/env python3
"""Instruction counts per frame (callgrind, computer proxy for ESP32 CPU work) for one or more builds of v3_perf, with the
same scenarios: avg / p50 / p99 / max per scenario group and frame kind. Not watch time; flash-vs-IRAM effects are invisible
here by construction (the computer has no flash cache).
usage: perf_compare.py NAME=path/to/v3_perf [NAME=...] [--json out.json]"""
import os, sys, json, tempfile, subprocess, collections
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import perf_analyze as pa


def collect(exe):
    with tempfile.TemporaryDirectory() as d:
        subprocess.run(['valgrind', '--tool=callgrind', '--collect-atstart=no', '--instr-atstart=no', exe, 'f.csv'], cwd=d, check=True, capture_output=True)
        files = [os.path.join(d, x) for x in os.listdir(d) if x.startswith('callgrind.out')]
        pa.FN_NAMES.clear(); pa.load_names(files)
        fr = collections.defaultdict(lambda: dict(t=0, kind='idle'))
        for p in files:
            name, total, _ = pa.parse(p)
            if not name or name.count('#') != 3: continue
            scen, idx, kind, phase = name.split('#'); e = fr[(scen, idx)]; e['t'] += total
            if kind == 'rebuild' or (kind == 'update' and e['kind'] == 'idle'): e['kind'] = kind
    g = collections.defaultdict(list)
    for (scen, _), e in fr.items(): g['%s/%s' % (scen.split('_')[0], e['kind'])].append(e['t'])
    out = {}
    for k, v in g.items():
        v.sort(); n = len(v)
        out[k] = dict(n=n, avg=sum(v) / n, p50=v[n // 2], p99=v[min(n - 1, (n * 99 + 99) // 100 - 1)], max=v[-1])
    return out


if __name__ == '__main__':
    runs = {a.split('=', 1)[0]: collect(a.split('=', 1)[1]) for a in sys.argv[1:] if '=' in a}
    names = list(runs)
    keys = sorted(set().union(*[set(r) for r in runs.values()]))
    print('| group/kind | ' + ' | '.join('%s avg / p99 / max (M instr)' % n for n in names) + ' |')
    print('|---|' + '---|' * len(names))
    for k in keys:
        print('| %s | ' % k + ' | '.join(('%.2f / %.2f / %.2f (%d)' % (r[k]['avg'] / 1e6, r[k]['p99'] / 1e6, r[k]['max'] / 1e6, r[k]['n'])) if k in r else '—' for r in runs.values()) + ' |')
    if '--json' in sys.argv: json.dump(runs, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1)
