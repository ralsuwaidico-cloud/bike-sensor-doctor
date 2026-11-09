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
    hits = glob.glob(os.path.expanduser('~/.platformio/packages/framework-arduinoespressif32-esp32-libs/esp32/ld/memory.ld'))
    if not hits: return None, {}
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
    for arg in sys.argv[1:]:
        label, elf = arg.split('=', 1)
        if not os.path.exists(elf): print('| %s | (not built) |' % label); continue
        s = sections(elf); g = lambda k: s.get(k, (0, 0))[0]
        iram = g('.iram0.vectors') + g('.iram0.text') + g('.iram0.text_end') + g('.iram0.data') + g('.iram0.bss')
        dst = g('.dram0.data') + g('.dram0.bss') + g('.noinit')
        print('| %s | %d | %d | %d / %s | %s | %d | %d | %d / %s | %d | %d |' % (label, g('.iram0.vectors'), g('.iram0.text'), iram,
              iram_len, (iram_len - iram) if iram_len else '?', g('.dram0.data'), g('.dram0.bss'), dst, dram_len, g('.flash.text'), g('.flash.rodata')))
    core = glob.glob(os.path.expanduser('~/.platformio/packages/framework-arduinoespressif32/cores/esp32/esp32-hal-misc.c'))
    if core:
        t = open(core[0]).read()
        print('\nArduino core (%s): releases the Bluetooth controller memory when Bluetooth is unused: %s' % (core[0], 'esp_bt_controller_mem_release' in t and 'btInUse' in t))


if __name__ == '__main__':
    main()
