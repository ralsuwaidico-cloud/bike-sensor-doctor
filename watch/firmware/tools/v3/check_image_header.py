#!/usr/bin/env python3
"""Check that a PlatformIO build's image headers agree with the watch that was actually read (Stage 2a, 9 Nov 2026).

The owner's watch: ESP32-PICO-V3-02, 8 MB flash, factory bootloader in DIO mode at 40 MHz.
For each build directory this checks, offline (no hardware):
  * bootloader.bin and firmware.bin are valid ESP images (magic, checksum, appended SHA-256 if present);
  * both headers say flash mode DIO, 40 MHz, 8 MB;
  * partitions.bin is valid (MD5), every partition lies inside 8 MB, none overlap, the first starts after the table;
  * firmware.bin fits in every app slot.
Usage: check_image_header.py BUILD_DIR [BUILD_DIR ...]      (exit 1 on any problem)
       check_image_header.py --self-test
"""
import hashlib
import os
import struct
import sys

MODES = {0: "QIO", 1: "QOUT", 2: "DIO", 3: "DOUT"}
SIZES = {0: "1MB", 1: "2MB", 2: "4MB", 3: "8MB", 4: "16MB"}
FREQS = {0x0: "40m", 0x1: "26m", 0x2: "20m", 0xF: "80m"}
WANT = ("DIO", "40m", "8MB")
FLASH = 8 * 1024 * 1024


def parse_image(data):
    """Return (mode, freq, size, problems) for an ESP32 image in `data`."""
    problems = []
    if len(data) < 24 or data[0] != 0xE9:
        return None, None, None, ["not an ESP image (magic)"]
    n, mode, sf = data[1], data[2], data[3]
    hash_appended = data[23] == 1
    pos, ck = 24, 0xEF
    for _ in range(n):
        if pos + 8 > len(data):
            return None, None, None, ["truncated segment header"]
        _addr, ln = struct.unpack("<II", data[pos:pos + 8])
        pos += 8
        seg = data[pos:pos + ln]
        if len(seg) != ln:
            return None, None, None, ["truncated segment"]
        for b in seg:
            ck ^= b
        pos += ln
    pos += 15 - (pos % 16)
    if pos >= len(data) or data[pos] != ck:
        problems.append("checksum mismatch")
    pos += 1
    if hash_appended and hashlib.sha256(data[:pos]).digest() != data[pos:pos + 32]:
        problems.append("appended SHA-256 mismatch")
    return MODES.get(mode, "?%d" % mode), FREQS.get(sf & 0xF, "?"), SIZES.get(sf >> 4, "?"), problems


def parse_partitions(data):
    parts, problems, md5_seen = [], [], False
    for i in range(0, len(data), 32):
        e = data[i:i + 32]
        if e[:2] == b"\xaa\x50":
            off, size = struct.unpack("<II", e[4:12])
            parts.append((e[12:28].split(b"\0")[0].decode(), e[2], e[3], off, size))
        elif e[:2] == b"\xeb\xeb":
            md5_seen = True
            if hashlib.md5(data[:i]).digest() != e[16:32]:
                problems.append("partition table MD5 mismatch")
        else:
            break
    if not parts:
        problems.append("no partitions")
    if not md5_seen:
        problems.append("no MD5 entry")
    last_end = 0x9000
    for name, _t, _s, off, size in sorted(parts, key=lambda p: p[3]):
        if off < last_end:
            problems.append("%s at 0x%x overlaps previous / partition table" % (name, off))
        if off + size > FLASH:
            problems.append("%s ends at 0x%x, beyond 8 MB" % (name, off + size))
        last_end = off + size
    return parts, problems


def check_dir(d):
    out, bad = [], []
    files = {k: os.path.join(d, k + ".bin") for k in ("bootloader", "firmware", "partitions")}
    for k, f in files.items():
        if not os.path.exists(f):
            bad.append("%s: missing %s" % (d, os.path.basename(f)))
    if bad:
        return out, bad
    fw = open(files["firmware"], "rb").read()
    for k in ("bootloader", "firmware"):
        mode, freq, size, probs = parse_image(open(files[k], "rb").read())
        out.append("%s %s: mode=%s freq=%s size=%s %s" % (os.path.basename(d.rstrip("/")), k, mode, freq, size, "OK" if not probs else probs))
        bad += ["%s %s: %s" % (d, k, p) for p in probs]
        if (mode, freq, size) != WANT:
            bad.append("%s %s header is %s/%s/%s, expected %s/%s/%s" % ((d, k, mode, freq, size) + WANT))
    parts, probs = parse_partitions(open(files["partitions"], "rb").read())
    bad += ["%s partitions: %s" % (d, p) for p in probs]
    for name, t, _s, _off, size in parts:
        if t == 0 and len(fw) > size:
            bad.append("%s: firmware.bin (%d B) does not fit app slot %s (%d B)" % (d, len(fw), name, size))
    apps = [p for p in parts if p[1] == 0]
    out.append("  partitions: " + ", ".join("%s@0x%x+0x%x" % (p[0], p[3], p[4]) for p in parts))
    out.append("  firmware.bin %d B; smallest app slot %d B" % (len(fw), min(p[4] for p in apps) if apps else 0))
    return out, bad


def _image(mode, sf, segs=(b"\x01" * 37, b"\x02" * 100), hashed=True):
    b = bytearray([0xE9, len(segs), mode, sf]) + struct.pack("<I", 0x40080000) + bytes(15) + bytes([1 if hashed else 0])
    ck = 0xEF
    for s in segs:
        b += struct.pack("<II", 0x3FFB0000, len(s)) + s
        for x in s:
            ck ^= x
    b += bytes(15 - (len(b) % 16)) + bytes([ck])
    if hashed:
        b += hashlib.sha256(b).digest()
    return bytes(b)


def _table(entries):
    t = b"".join(b"\xaa\x50" + bytes([ty, st]) + struct.pack("<II", o, s) + n.encode().ljust(16, b"\0") + bytes(4)
                 for n, ty, st, o, s in entries)
    return t + b"\xeb\xeb" + b"\xff" * 14 + hashlib.md5(t).digest() + b"\xff" * 32


def self_test():
    import tempfile
    good = [("nvs", 1, 2, 0x9000, 0x5000), ("otadata", 1, 0, 0xE000, 0x2000), ("app0", 0, 0x10, 0x10000, 0x300000),
            ("app1", 0, 0x11, 0x310000, 0x300000), ("littlefs", 1, 0x82, 0x610000, 0x1F0000)]
    cases = [
        ("correct DIO/40m/8MB", _image(2, 0x30), _image(2, 0x30), good, True),
        ("4 MB header (the bug Stage 2a found)", _image(2, 0x20), _image(2, 0x20), good, False),
        ("QIO 80 MHz", _image(0, 0x3F), _image(0, 0x3F), good, False),
        ("partition beyond 8 MB", _image(2, 0x30), _image(2, 0x30), good[:-1] + [("littlefs", 1, 0x82, 0x610000, 0x200000)], False),
        ("overlapping partitions", _image(2, 0x30), _image(2, 0x30), good[:3] + [("app1", 0, 0x11, 0x300000, 0x300000)], False),
    ]
    fails = 0
    for name, bl, fw, table, expect_ok in cases:
        d = tempfile.mkdtemp()
        for k, v in (("bootloader", bl), ("firmware", fw), ("partitions", _table(table))):
            open(os.path.join(d, k + ".bin"), "wb").write(v)
        _out, bad = check_dir(d)
        ok = not bad
        fails += ok != expect_ok
        print("%s: %s (%s)" % ("PASS" if ok == expect_ok else "FAIL", name, "accepted" if ok else "rejected"))
    corrupt = bytearray(_image(2, 0x30))
    corrupt[40] ^= 1
    probs = parse_image(bytes(corrupt))[3]
    fails += not probs
    print("%s: corrupted image detected (%s)" % ("PASS" if probs else "FAIL", probs))
    print("self-test failures:", fails)
    return fails


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(1 if self_test() else 0)
    all_bad = []
    for d in sys.argv[1:]:
        out, bad = check_dir(d)
        print("\n".join(out))
        all_bad += bad
    for b in all_bad:
        print("PROBLEM:", b)
    print("image header check:", "PASS" if not all_bad else "FAIL (%d)" % len(all_bad))
    sys.exit(1 if all_bad else 0)
