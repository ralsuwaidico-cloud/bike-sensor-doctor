#!/usr/bin/env python3
"""Tests for fp_plan.py on a synthetic image shaped like the owner's watch (no hardware, no backup contents)."""
import hashlib
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fp_plan as fp  # noqa: E402

FAILS = []


def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        FAILS.append(msg)


def esp_image(total_len, mode=2, size_code=2, seed=1):
    """Synthetic valid ESP image of exactly total_len bytes (hash appended)."""
    body_len = total_len - 24 - 8 - 32 - 16
    seg = bytes((i * seed + 7) & 0xFF for i in range(body_len))
    b = bytearray([0xE9, 1, mode, (size_code << 4)]) + struct.pack("<I", 0x40080000) + bytes(15) + b"\x01"
    b += struct.pack("<II", 0x3FFF0000, len(seg)) + seg
    ck = 0xEF
    for x in seg:
        ck ^= x
    b += bytes(15 - (len(b) % 16)) + bytes([ck])
    b += hashlib.sha256(b).digest()
    return bytes(b)


def factory_like():
    img = bytearray(b"\xff" * fp.FLASH)
    bl = esp_image(17088)
    img[0x1000:0x1000 + len(bl)] = bl
    pt = fp.build_pt([fp.entry("nvs", 1, 2, 0x9000, 0x5000), fp.entry("otadata", 1, 0, 0xE000, 0x2000),
                      fp.entry("app0", 0, 0x10, 0x10000, 0x200000), fp.entry("spiffs", 1, 0x82, 0x210000, 0x1F0000)])
    img[0x8000:0x8000 + len(pt)] = pt
    img[0x9000:0x9004] = struct.pack("<I", 0xFFFFFFFE)
    img[0x9100:0x9200] = os.urandom(256)                       # "settings"
    img[0xE000:0xE020] = fp.ota_entry(1)
    img[0xF000:0xF020] = fp.ota_entry(0)
    app = esp_image(1194096, seed=3)
    img[0x10000:0x10000 + len(app)] = app
    img[0x210000:0x210100] = os.urandom(256)                   # "file system"
    return bytes(img)


def main():
    orig = factory_like()
    check(fp.image_len(orig, 0x1000) == 17088, "bootloader length parsed (17 088 B, like the watch)")
    check(fp.selected_slot(orig, 1) == 0, "factory image: bootloader picks app0")
    pt = fp.proposed_pt(orig[0x8000:0x8C00])
    check(fp.check_layout(pt) == [], "proposed partition table: no overlap/alignment/size/label/MD5 problems %s" % fp.check_layout(pt))
    old, new = fp.parse_pt(orig[0x8000:0x8C00]), fp.parse_pt(pt)
    check([p["raw"] for p in new[1:4]] == [p["raw"] for p in old[1:4]], "otadata/app0/spiffs entries byte-identical to factory")
    check(new[0]["label"] == "nvs_fac" and (new[0]["offset"], new[0]["size"]) == (0x9000, 0x5000), "factory settings kept in place, relabelled nvs_fac")
    check([(p["label"], p["offset"]) for p in new if p["label"] == "nvs"] == [("nvs", 0x700000)], "default settings label 'nvs' now points to 0x700000 (isolated)")
    check(max(p["offset"] + p["size"] for p in new) == fp.FLASH, "layout ends exactly at 8 MB")
    for bad, why in ((fp.build_pt([fp.entry("a", 0, 0x10, 0x10000, 0x300000), fp.entry("b", 0, 0x11, 0x300000, 0x100000)]), "overlap"),
                     (fp.build_pt([fp.entry("nvs", 1, 2, 0x9000, 0x5000), fp.entry("a", 0, 0x10, 0x18000, 0x100000)]), "64 KB alignment"),
                     (fp.build_pt([fp.entry("nvs", 1, 2, 0x9000, 0x5000), fp.entry("a", 0, 0x10, 0x710000, 0x100000)]), "beyond 8 MB")):
        check(fp.check_layout(bad) != [], "layout checker rejects " + why)

    cyc = esp_image(983200, seed=5)
    planned, notes = fp.apply_plan(orig, cyc, patch_bootloader=True)
    check(fp.selected_slot(planned, 2) == 1, "planned image: bootloader picks ota_1 (app1)")
    check(fp.ota_seq(planned, 0) == fp.ota_seq(orig, 0), "OTA-data sector 0 (factory record) untouched")
    secs = fp.changed_sectors(orig, planned)
    rg = fp.ranges(secs)
    print("     changed ranges:", ", ".join("0x%06x-0x%06x" % r for r in rg))
    allowed = lambda o: o in (0x1000, 0x5000, 0x8000, 0xF000) or 0x400000 <= o < 0x700000
    check(all(allowed(o) for o in secs), "only bootloader sectors 0x1000/0x5000, table 0x8000, OTA 0xF000 and app1 change")
    for name, a, b in (("factory settings", 0x9000, 0xE000), ("factory app", 0x10000, 0x210000), ("factory files", 0x210000, 0x400000)):
        check(planned[a:b] == orig[a:b], name + " byte-identical after the plan")
    bl = planned[0x1000:0x1000 + 17088]
    check(bl[3] >> 4 == 3 and hashlib.sha256(bl[:-32]).digest() == bl[-32:], "patched bootloader says 8 MB and its SHA-256 is valid")
    check(fp.normalized_bootloader_sha(bl) == fp.normalized_bootloader_sha(orig[0x1000:0x1000 + 17088]), "bootloader code unchanged (normalized hash equal)")
    restored = fp.rollback(planned, orig, secs)
    check(hashlib.sha256(restored).digest() == hashlib.sha256(orig).digest(), "rollback of the listed sectors restores the original byte-for-byte")
    small = fp.rollback(planned, orig, [o for o in secs if o < 0x400000])
    check(small[:0x400000] == orig[:0x400000] and fp.selected_slot(small, 1) == 0, "small rollback (4 sectors) restores the first 4 MB and app0 selection")
    p2, _ = fp.apply_plan(orig, cyc, patch_bootloader=False)
    check(all(o not in (0x1000, 0x5000) for o in fp.changed_sectors(orig, p2)), "variant without bootloader change leaves the bootloader untouched")
    print("fp_plan tests: %d failures" % len(FAILS))
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
