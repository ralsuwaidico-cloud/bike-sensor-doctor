#!/usr/bin/env python3
"""Stage 1.1 rendering regression checks on a computer (CI job v3-stage1-host). Computer measurements only: they guard
against regressions; they do NOT prove frame times on the watch (those are measured on the ESP32 with the 'h' report).
  1 visual: every rendered state is byte-identical to the approved Stage 1 rendering (render_reference_sha256.txt)
  2 partial updates: the picture built from partial updates equals a full redraw (no stale pixels, no ghosting)
  3 redraw rate: a steady ride redraws about once per second in English AND Arabic (Arabic used to redraw ~33×/s)
  4 work budgets (--callgrind): instructions per frame stay within perf_budgets.json
usage: perf_check.py [--callgrind]   (run from test/v3 after `make render perf-link`)"""
import csv, collections, hashlib, json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FAILS = []


def check(ok, msg):
    print(('PASS ' if ok else 'FAIL ') + msg)
    if not ok:
        FAILS.append(msg)


def visual():
    ref = dict(reversed(l.split()) for l in open(os.path.join(HERE, 'render_reference_sha256.txt')) if l.strip())
    out = os.path.join(HERE, 'out')
    diff = [n for n, h in ref.items() if not os.path.exists(os.path.join(out, n)) or hashlib.sha256(open(os.path.join(out, n), 'rb').read()).hexdigest() != h]
    check(not diff, 'visual: %d rendered states byte-identical to the approved Stage 1 rendering%s' % (len(ref), (' — differ: %s' % diff[:8]) if diff else ''))


def partial_and_rate():
    exe = os.path.join(HERE, '.build', 'v3_perf')
    with tempfile.TemporaryDirectory() as d:
        r = subprocess.run([exe, os.path.join(d, 'v.csv'), '--verify'], capture_output=True, text=True)
        line = [l for l in r.stdout.splitlines() if l.startswith('partial-update check')]
        check(r.returncode == 0 and line and line[0].endswith(' 0 differ'), 'partial updates: ' + (line[0] if line else r.stdout[-300:]))
        subprocess.run([exe, os.path.join(d, 'w.csv')], check=True, capture_output=True)
        rows = list(csv.DictReader(open(os.path.join(d, 'w.csv'))))
    by = collections.defaultdict(list)
    for x in rows: by[x['scenario']].append(x)
    b = json.load(open(os.path.join(HERE, 'perf_budgets.json')))
    for scen in sorted(s for s in by if s.startswith('cockpit_')):
        steady = [x for x in by[scen] if int(x['frame']) >= 300 and int(x['px']) > 0]
        seconds = (max(int(x['frame']) for x in by[scen]) - 300) / 100.0
        rate = len(steady) / seconds
        check(rate <= b['redraws_per_second_max'], 'redraw rate %s: %.2f redraws/s (budget %.2f)' % (scen, rate, b['redraws_per_second_max']))
    px = max(int(x['px']) for x in by['cockpit_std_en'] if int(x['frame']) >= 300 and x['kind'] == 'update')
    check(px <= b['update_px_max_cockpit_std'], 'redrawn area per 1 Hz cockpit update: max %d px (budget %d)' % (px, b['update_px_max_cockpit_std']))


def callgrind():
    sys.path.insert(0, HERE); import perf_analyze as pa
    exe = os.path.join(HERE, '.build', 'v3_perf')
    b = json.load(open(os.path.join(HERE, 'perf_budgets.json')))['instructions']
    with tempfile.TemporaryDirectory() as d:
        subprocess.run(['valgrind', '--tool=callgrind', '--collect-atstart=no', '--instr-atstart=no', exe, 'f.csv'], cwd=d, check=True, capture_output=True)
        files = [os.path.join(d, x) for x in os.listdir(d) if x.startswith('callgrind.out')]
        pa.load_names(files)
        fr = collections.defaultdict(lambda: dict(t=0, kind='idle'))
        for p in files:
            name, total, _ = pa.parse(p)
            if not name or name.count('#') != 3: continue
            scen, idx, kind, phase = name.split('#'); e = fr[(scen, idx)]; e['t'] += total
            if kind == 'rebuild' or (kind == 'update' and e['kind'] == 'idle'): e['kind'] = kind
    g = collections.defaultdict(list)
    for (scen, _), e in fr.items(): g[(scen.split('_')[0], e['kind'])].append(e['t'])
    for (grp, kind), lim in ((k.split('/'), v) for k, v in b.items()):
        v = g.get((grp, kind), [])
        if not v: check(False, 'instructions %s/%s: no frames measured' % (grp, kind)); continue
        mx = max(v)
        check(mx <= lim, 'instructions %s/%s: max %.2f M per frame over %d frames (budget %.2f M)' % (grp, kind, mx / 1e6, len(v), lim / 1e6))


if __name__ == '__main__':
    visual(); partial_and_rate()
    if '--callgrind' in sys.argv: callgrind()
    print('perf check: %d failures' % len(FAILS))
    sys.exit(1 if FAILS else 0)
