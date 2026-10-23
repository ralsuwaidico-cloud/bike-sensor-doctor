#!/usr/bin/env python3
"""Fail if a float conversion (%f %e %g, with any flags/width/precision) is passed to an LVGL *_fmt function.
LVGL's built-in printf is compiled without float support (LV_USE_FLOAT off); such a call desynchronises the variadic
arguments and crashed 0.1.0-diag in a reboot loop on 2026-10-23. Whole statements are checked, across line breaks."""
import re, sys, pathlib
call = re.compile(r'\blv_\w*_fmt\s*\(', re.S)
flt = re.compile(r'%[-+ 0#]*\d*(?:\.\d+)?[fFeEgG]')
bad = 0
for root in sys.argv[1:]:
    for p in pathlib.Path(root).rglob('*.c'):
        src = p.read_text(errors='replace')
        for m in call.finditer(src):
            end = src.find(';', m.end()); stmt = src[m.start():end]
            lits = ''.join(re.findall(r'"((?:[^"\\]|\\.)*)"', stmt))
            if flt.search(lits):
                bad += 1; print(f"FAIL {p}:{src.count(chr(10), 0, m.start()) + 1}: float format passed to {m.group(0)[:-1].strip()}")
print("lint OK: no float formats in LVGL _fmt calls" if not bad else f"{bad} problem(s)")
sys.exit(1 if bad else 0)
