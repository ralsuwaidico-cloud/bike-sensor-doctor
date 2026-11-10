#!/usr/bin/env python3
"""Static memory map of built ESP32 images against the linker's memory regions (compile-time facts; run-time heap and
stack are measured on the watch). Usage: mem_report.py LABEL=path/firmware.elf ...
Reads section sizes with the Xtensa `size` tool and the region limits from the framework's memory.ld (the same linker
script the build used), and reports the Arduino core's Bluetooth-memory handling from its source."""
import glob, os, re, subprocess, sys


def tool():
    for pat in ['~/.platformio/packages/toolchain-xtensa-esp*/bin/xtensa-esp32-elf-size']:
        h = glob.glob(os.path.expanduser(pat))
        if h: return h[0]
    return 'size'


def nm_tool():
    t = tool()
    return t[:-len('size')] + 'nm' if t.endswith('-size') else 'nm'


def symbols(elf):
    """(name, address, size) of every sized symbol, demangled."""
    out = subprocess.run([nm_tool(), '-S', '-C', elf], capture_output=True, text=True, check=True).stdout
    res = []
    for line in out.splitlines():
        p = line.split(None, 3)
        if len(p) == 4 and all(c in '0123456789abcdef' for c in p[0] + p[1]): res.append((p[3], int(p[0], 16), int(p[1], 16)))
    return res


# LVGL functions that dominate the drawing work in the computer profile (callgrind, test/v3): the candidate set for a small
# selective IRAM placement. Static helpers of these files are included by file-local naming below.
HOT = re.compile(r'^(lv_draw_sw_blend_basic|fill_normal|fill_set_px|map_normal|map_set_px|lv_draw_mask_radius|lv_draw_mask_apply|'
                 r'lv_draw_mask_apply_ids|lv_draw_mask_line|lv_draw_mask_angle|lv_memcpy|lv_memset|lv_memset_00|lv_memset_ff|lv_color_fill|'
                 r'lv_color_mix_premult|draw_letter_normal|sw_color_to_rgb565|lv_draw_sw_letter)$')


def iram_lvgl(label, elf):
    syms = [(n, a, z) for n, a, z in symbols(elf) if 0x40080000 <= a < 0x400A0000 and z]
    lv = [(n, z) for n, a, z in syms if n.startswith(('lv_', '_lv_')) or HOT.match(n.split('(')[0])]
    hot = [(n, z) for n, z in lv if HOT.match(n.split('(')[0])]
    print('\n%s: %d LVGL functions in IRAM, %d B; hot set (computer profile) %d functions, %d B:' % (label, len(lv), sum(z for _, z in lv), len(hot), sum(z for _, z in hot)))
    for n, z in sorted(hot, key=lambda x: -x[1]): print('    %6d  %s' % (z, n))


def dram_symbols(label, elf, pattern):
    rx = re.compile(pattern)
    hits = [(n, z) for n, a, z in symbols(elf) if 0x3FFB0000 <= a < 0x40000000 and z and rx.search(n)]
    print('\n%s: static RAM symbols matching %r: %d B' % (label, pattern, sum(z for _, z in hits)))
    for n, z in sorted(hits, key=lambda x: -x[1])[:12]: print('    %6d  %s' % (z, n))


def sections(elf):
    out = subprocess.run([tool(), '-A', elf], capture_output=True, text=True, check=True).stdout
    s = {}
    for line in out.splitlines()[2:]:
        p = line.split()
        if len(p) >= 3 and p[0].startswith('.') and p[1].isdigit(): s[p[0]] = (int(p[1]), int(p[2]))
    return s


def ev(expr):
    expr = expr.strip()
    if not re.fullmatch(r'[0-9a-fA-Fx+\-*() ]+', expr): return None
    return eval(expr)


def regions():
    hits = sorted(glob.glob(os.path.expanduser('~/.platformio/packages/framework-arduinoespressif32*/**/esp32/ld/memory.ld'), recursive=True))
    if not hits:
        for root, dirs, files in os.walk(os.path.expanduser('~/.platformio')):
            if 'memory.ld' in files and (root.replace('\\', '/').endswith('/esp32/ld') or root.replace('\\', '/').endswith('-esp32-libs/ld')):
                hits.append(os.path.join(root, 'memory.ld'))
        hits.sort()
    if not hits:
        found = []
        for root, dirs, files in os.walk(os.path.expanduser('~/.platformio')):
            found += [os.path.join(root, f) for f in files if f == 'memory.ld']
        print('memory.ld candidates found: %s' % (found[:20] or 'none'))
        return None, {}
    txt = open(hits[0]).read()
    r = {}
    for m in re.finditer(r'(\w+_seg)\s*\([^)]*\)\s*:\s*org\s*=\s*([^,]+),\s*len\s*=\s*([^\n]+)', txt):
        r[m.group(1)] = (m.group(2).strip(), m.group(3).strip(), ev(m.group(2)), ev(m.group(3)))
    return hits[0], r


def main():
    path, reg = regions()
    print('Linker memory regions (%s):' % path)
    for k in ('iram0_0_seg', 'dram0_0_seg', 'iram0_2_seg', 'drom0_0_seg'):
        if k in reg:
            o, l, oe, le = reg[k]
            print('  %-12s org %-28s len %-28s = %s' % (k, o, l, ('%d B' % le) if le is not None else '?'))
    iram_len = reg.get('iram0_0_seg', (0, 0, None, None))[3]
    dram = reg.get('dram0_0_seg'); dram_len = dram[3] if dram else None
    if dram and dram[2] is not None:
        print('  dram0_0_seg starts 0x%X: %d B above 0x3FFB0000 are reserved for the Bluetooth controller (released to the heap at start-up when Bluetooth is not used)' % (dram[2], dram[2] - 0x3FFB0000))
    print()
    print('| Image | .iram0.vectors | .iram0.text | IRAM used / limit | IRAM free | .dram0.data | .dram0.bss | DRAM static / limit | .flash.text | .flash.rodata |')
    print('|---|---|---|---|---|---|---|---|---|---|')
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    for arg in args:
        label, elf = arg.split('=', 1)
        if not os.path.exists(elf): print('| %s | (not built) |' % label); continue
        s = sections(elf); g = lambda k: s.get(k, (0, 0))[0]
        iram = g('.iram0.vectors') + g('.iram0.text') + g('.iram0.text_end') + g('.iram0.data') + g('.iram0.bss')
        dst = g('.dram0.data') + g('.dram0.bss') + g('.noinit')
        print('| %s | %d | %d | %d / %s | %s | %d | %d | %d / %s | %d | %d |' % (label, g('.iram0.vectors'), g('.iram0.text'), iram,
              iram_len, (iram_len - iram) if iram_len else '?', g('.dram0.data'), g('.dram0.bss'), dst, dram_len, g('.flash.text'), g('.flash.rodata')))
    for a in sys.argv[1:]:
        if a.startswith('--iram-lvgl='):
            label = a.split('=', 1)[1]
            elf = dict(x.split('=', 1) for x in args).get(label)
            if elf and os.path.exists(elf): iram_lvgl(label, elf)
        if a.startswith('--dram-syms='):
            label, pat = a.split('=', 1)[1].split(':', 1)
            elf = dict(x.split('=', 1) for x in args).get(label)
            if elf and os.path.exists(elf): dram_symbols(label, elf, pat)
    core = glob.glob(os.path.expanduser('~/.platformio/packages/framework-arduinoespressif32/cores/esp32/esp32-hal-misc.c'))
    if core:
        t = open(core[0]).read()
        rel = ('btMemRelease' in t and 'bleInUse' in t) or ('esp_bt_controller_mem_release' in t and 'btInUse' in t)
        print('\nArduino core (%s): releases the Bluetooth controller memory at start-up when no Bluetooth library is linked: %s' % (core[0], rel))
        for line in t.splitlines():
            if 'MemRelease' in line or 'mem_release' in line: print('    ' + line.strip())


if __name__ == '__main__':
    main()
