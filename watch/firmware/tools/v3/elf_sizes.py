#!/usr/bin/env python3
"""Static memory of a built ESP32 firmware image by section (compile-time facts, not run-time measurements).
Usage: elf_sizes.py path/to/firmware.elf   (finds the Xtensa `size` tool in ~/.platformio/packages)."""
import glob, os, subprocess, sys

def tool():
    for pat in ['~/.platformio/packages/toolchain-xtensa-esp*/bin/xtensa-esp32-elf-size', '~/.platformio/packages/toolchain-xtensa*/bin/xtensa-esp*-elf-size']:
        hits = glob.glob(os.path.expanduser(pat))
        if hits: return hits[0]
    return 'size'

def main(elf):
    out = subprocess.run([tool(), '-A', elf], capture_output=True, text=True, check=True).stdout
    sec = {}
    for line in out.splitlines()[2:]:
        p = line.split()
        if len(p) >= 2 and p[0].startswith('.') and p[1].isdigit(): sec[p[0]] = int(p[1])
    flash = sum(v for k, v in sec.items() if k.startswith('.flash')) + sec.get('.iram0.text', 0) + sec.get('.dram0.data', 0)
    dram = sec.get('.dram0.data', 0) + sec.get('.dram0.bss', 0) + sec.get('.noinit', 0)
    print('| Section | Bytes |\n| --- | --- |')
    for k in sorted(sec):
        if sec[k] and not k.startswith('.debug') and k not in ('.comment', '.xtensa.info'): print(f'| {k} | {sec[k]:,} |')
    print(f'| **Image in flash (approx.)** | **{flash:,}** |\n| **Static internal RAM (data + bss)** | **{dram:,}** |')

if __name__ == '__main__':
    main(sys.argv[1])
