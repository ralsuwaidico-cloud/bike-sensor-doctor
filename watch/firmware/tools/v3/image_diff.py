#!/usr/bin/env python3
"""Compares two ESP32 application images segment by segment and lists differing byte runs (reproducible-build check).
usage: image_diff.py a.bin b.bin"""
import struct, sys


def segments(b):
    n = b[1]; off = 24; out = []
    for i in range(n):
        addr, ln = struct.unpack_from('<II', b, off); out.append((i, addr, off + 8, ln)); off += 8 + ln
    return out


def main():
    a, b = open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read()
    if a == b:
        print('identical: %d bytes' % len(a)); return 0
    print('DIFFERENT: sizes %d / %d' % (len(a), len(b)))
    if len(a) != len(b):
        return 1
    for i, addr, off, ln in segments(a):
        runs, j = [], off
        while j < off + ln:
            if a[j] != b[j]:
                k = j
                while k < off + ln and a[k] != b[k]: k += 1
                runs.append((j - off, k - j)); j = k
            else:
                j += 1
        if runs:
            print('  segment %d (load 0x%08x): %d differing bytes in %d runs: %s' % (i, addr, sum(r[1] for r in runs), len(runs),
                  ', '.join('+%d(%d)' % r for r in runs[:8])))
            for o, l in runs[:4]:
                ctx = a[off + max(0, o - 24):off + o + l + 24]
                print('    near +%d: %r' % (o, bytes(c if 32 <= c < 127 else 46 for c in ctx).decode()))
    tail_a, tail_b = a[-33:], b[-33:]
    if tail_a != tail_b: print('  trailing checksum / SHA-256 differ (follow from the above)')
    return 1


if __name__ == '__main__':
    sys.exit(main())
