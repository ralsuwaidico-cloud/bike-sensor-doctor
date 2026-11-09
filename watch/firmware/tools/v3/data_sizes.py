#!/usr/bin/env python3
"""Font and icon data sizes of the v3 Stage 1 build, from the compiled host objects (test/v3/.build).
The glyph bitmaps and tables are the same constant data the watch build stores in flash; only a few pointers per font
differ in size between the computer (64-bit) and the ESP32 (32-bit), so the totals are accurate to well under 1 KB."""
import json, pathlib, subprocess, sys

def sections(obj):
    out = subprocess.run(['size', '-A', str(obj)], capture_output=True, text=True, check=True).stdout
    tot = {}
    for line in out.splitlines()[2:]:
        parts = line.split()
        if len(parts) >= 2 and parts[0].startswith('.') and parts[1].isdigit():
            key = 'rodata' if parts[0].startswith('.rodata') else 'data' if parts[0].startswith('.data') else 'bss' if parts[0].startswith('.bss') else None
            if key: tot[key] = tot.get(key, 0) + int(parts[1])
    return tot

def main(build):
    build = pathlib.Path(build); rows = {}
    for o in sorted((build / 'fonts').glob('*.o')): rows[o.stem] = sections(o)
    rows['cyv3_icons'] = sections(build / 'icons.o')
    groups = {'Inter digits (24/32/44/54/58 px, not compressed)': 'cyv3_digits', 'Inter text (11–20 px)': 'cyv3_inter', 'Noto Sans Arabic (11–17 px)': 'cyv3_noto', 'Icons (15, 8-bit alpha)': 'cyv3_icons'}
    report = {}
    for name, pre in groups.items():
        n = sum(v.get('rodata', 0) + v.get('data', 0) for k, v in rows.items() if k.startswith(pre))
        report[name] = n
    report['Total font + icon data'] = sum(report.values())
    for k, v in report.items(): print(f'{k:<52} {v:>9,} bytes')
    (build.parent / 'out').mkdir(exist_ok=True)
    (build.parent / 'out' / 'data_sizes.json').write_text(json.dumps({'groups': report, 'per_file': rows}, indent=1))

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.build')
