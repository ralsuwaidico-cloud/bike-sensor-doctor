#!/usr/bin/env python3
"""Analyse the callgrind dumps of perf_main (one dump per working frame): instructions per frame (distribution per scenario
and frame kind) and where they go (self cost grouped into categories). Computer instruction counts are a proxy for ESP32
CPU work; they are not watch frame times.
usage: perf_analyze.py <dump dir> [out.json]"""
import os, re, sys, json, collections

CATS = [
    ('arabic shaping / bidi', r'_lv_txt_ap|lv_txt_ap|_lv_bidi|bidi'),
    ('glyph decode (compressed fonts)', r'decompress|rle_|bits_write|line_|get_bits'),
    ('glyph lookup / font', r'lv_font_|get_glyph|unicode_list|kern|cmap|lv_font_get'),
    ('letter drawing', r'draw_letter|lv_draw_sw_letter|lv_draw_letter'),
    ('arc / circle masks', r'mask|arc|circ|lv_sqrt|lv_atan|lv_trigo|angle'),
    ('pixel blending / fill', r'blend|fill_|map_normal|lv_color_mix|lv_memset|lv_memcpy|lv_color_fill'),
    ('text layout / measuring', r'_lv_txt_|lv_txt_|lv_label_|get_next_line|txt_'),
    ('object tree / style / layout', r'lv_obj_|_lv_obj|style|lv_style|layout|lv_event|_lv_ll|lv_ll'),
    ('invalidation / refresh', r'_lv_inv|lv_refr|refr_|lv_area|_lv_area|lv_timer|lv_disp'),
    ('memory', r'lv_mem|malloc|free|realloc|tlsf|operator new|operator delete|memmove|memcpy|memset|strlen|strcmp'),
    ('Cyclift UI code', r'cyw::'),
]


FN_NAMES = {}          # callgrind compresses function names across the dumps of one run: ids are global


def load_names(paths):
    for path in paths:
        with open(path, errors='replace') as f:
            for line in f:
                if line.startswith(('fn=(', 'cfn=(')):
                    m = re.match(r'c?fn=\((\d+)\) (.+)', line.strip())
                    if m: FN_NAMES[m.group(1)] = m.group(2)


def parse(path):
    name, total, self_cost = None, 0, collections.Counter()
    fn_names = FN_NAMES
    cur = None; skip_next = False
    with open(path, errors='replace') as f:
        for line in f:
            if line.startswith('desc: Trigger:'):
                m = re.search(r'Client Request: (.*)$', line.strip()); name = m.group(1) if m else None
            elif line.startswith('summary:') or line.startswith('totals:'):
                total = int(line.split()[1])
            elif line.startswith('fn='):
                m = re.match(r'fn=\((\d+)\)(?: (.*))?', line.strip())
                if m:
                    if m.group(2): fn_names[m.group(1)] = m.group(2)
                    cur = fn_names.get(m.group(1), m.group(1))
                skip_next = False
            elif line.startswith('calls='):
                skip_next = True
            elif line and (line[0].isdigit() or line[0] in '+-*'):
                if skip_next:
                    skip_next = False; continue
                parts = line.split()
                if len(parts) >= 2 and cur:
                    try: self_cost[cur] += int(parts[1])
                    except ValueError: pass
            elif line.startswith(('cfn=', 'cfi=', 'cob=', 'fl=', 'fi=', 'fe=', 'ob=')):
                if line.startswith(('fl=', 'fi=', 'fe=')) and False: pass
    return name, total, self_cost


def cat_of(fn):
    for c, rx in CATS:
        if re.search(rx, fn): return c
    return 'other'


def pct(v, p):
    v = sorted(v); k = (len(v) - 1) * p / 100.0; lo = int(k); hi = min(lo + 1, len(v) - 1)
    return v[lo] + (v[hi] - v[lo]) * (k - lo)


def main():
    d = sys.argv[1]; out = sys.argv[2] if len(sys.argv) > 2 else None
    files = [os.path.join(d, x) for x in os.listdir(d) if x.startswith('callgrind.out')]
    load_names(files)
    fr = collections.defaultdict(lambda: dict(ui=0, draw=0, kind='idle'))
    cats = collections.defaultdict(collections.Counter)
    for p in files:
        name, total, sc = parse(p)
        if not name or name.count('#') != 3: continue
        scen, idx, kind, phase = name.split('#')
        e = fr[(scen, int(idx))]; e[phase] += total
        if kind == 'rebuild' or (kind == 'update' and e['kind'] == 'idle'): e['kind'] = kind
        for f, c in sc.items(): cats[(scen, kind, phase)][cat_of(f)] += c
    groups = collections.defaultdict(list)
    for (scen, idx), e in fr.items(): groups[(scen, e['kind'])].append(e)
    rep = {}
    for key in sorted(groups):
        v = [e['ui'] + e['draw'] for e in groups[key]]; ui = [e['ui'] for e in groups[key]]; dr = [e['draw'] for e in groups[key]]
        rep['%s/%s' % key] = dict(n=len(v), avg=sum(v) / len(v), p50=pct(v, 50), p95=pct(v, 95), p99=pct(v, 99), max=max(v),
                                  ui_avg=sum(ui) / len(ui), draw_avg=sum(dr) / len(dr))
    for k, r in rep.items():
        print('%-24s n=%4d  avg %9.0f  p95 %9.0f  p99 %9.0f  max %9.0f   ui %8.0f  draw %8.0f' % (k, r['n'], r['avg'], r['p95'], r['p99'], r['max'], r['ui_avg'], r['draw_avg']))
    if out:
        json.dump(dict(frames=rep, categories={'/'.join(k): dict(c) for k, c in cats.items()}), open(out, 'w'), indent=1)


if __name__ == '__main__':
    main()
