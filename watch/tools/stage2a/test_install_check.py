#!/usr/bin/env python3
"""Tests for install_check.py on synthetic watch-shaped images (no hardware, no backup contents)."""
import hashlib, os, struct, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fp_plan as fp, install_check as ic, test_fp_plan as t  # noqa: E401,E402
FAILS = []
def check(c, m):
    print(("PASS " if c else "FAIL ") + m)
    if not c: FAILS.append(m)
def nvs_entry(img, page, idx, ns, typ, key, data):
    off = 0x9000 + page * 0x1000
    img[off + 64 + idx * 32: off + 96 + idx * 32] = bytes([ns, typ, 1, 0xff]) + b"\0" * 4 + key.encode().ljust(16, b"\0") + data
    b = img[off + 32 + idx // 4]; img[off + 32 + idx // 4] = b & ~(1 << ((idx % 4) * 2)) & 0xFF   # 11 -> 10 written
def erase_entry(img, page, idx):
    off = 0x9000 + page * 0x1000; img[off + 32 + idx // 4] &= ~(3 << ((idx % 4) * 2)) & 0xFF
def backup_like():
    img = bytearray(t.factory_like())
    img[0x9000:0xE000] = b"\xff" * 0x5000
    img[0x9000:0x9004] = struct.pack("<I", 0xFFFFFFFE)
    nvs_entry(img, 0, 0, 0, 0x01, "osw-config", bytes([1]) + b"\xff" * 7)
    nvs_entry(img, 0, 1, 0, 0x01, "wifi-like", bytes([2]) + b"\xff" * 7)
    nvs_entry(img, 0, 2, 1, 0x14, "bct", struct.pack("<i", 7) + b"\xff" * 4)
    nvs_entry(img, 0, 3, 2, 0x21, "secret", b"\x05\x00\xff\xff" + b"\0" * 4)
    return bytes(img)
def main():
    backup = backup_like()
    app = t.esp_image(983200, seed=9)
    planned, _ = fp.apply_plan(backup, app, True)
    d = tempfile.mkdtemp(); man = []
    for s in ic.PLANNED:
        for tag, src in (("original", backup), ("planned", planned)):
            n = "%s_0x%06x.bin" % (tag, s); open(os.path.join(d, n), "wb").write(src[s:s + 0x1000]); man.append("%s %s" % (ic.sha(src[s:s + 0x1000]), n))
    open(os.path.join(d, "manifest_sha256.txt"), "w").write("\n".join(man) + "\n")
    check(ic.check_manifest(d) == [], "manifest verifies")
    pieces = ic.load_pieces(d)
    res, bad = ic.recovery_validate(backup, app, pieces)
    for r in res: print("     " + r)
    check(not bad, "recovery package validates (R-A, R-B, R-C, verifier self-check)")
    post = bytearray(ic.simulate_post_install(backup, app, pieces))
    erase_entry(post, 0, 2); nvs_entry(post, 0, 4, 1, 0x14, "bct", struct.pack("<i", 8) + b"\xff" * 4)  # factory boot counter drift
    rep, bad = ic.verify_after(backup, bytes(post), app, pieces)
    check(not bad, "post-install check accepts factory boot-counter drift (osw-config) %s" % bad)
    p2 = bytearray(post); erase_entry(p2, 0, 3); nvs_entry(p2, 0, 5, 2, 0x21, "secret", b"\x05\x00\xff\xff" + b"\0" * 4)
    _, bad = ic.verify_after(backup, bytes(p2), app, pieces)
    check(any("outside" in b for b in bad), "post-install check rejects a change to another factory settings namespace")
    for off, why in ((0x0, "ROM gap"), (0x3000, "bootloader middle"), (0xE010, "OTA sector 0"), (0x10050, "factory app"), (0x300000, "factory files"), (0x600000, "unused app1 tail")):
        p3 = bytearray(post); p3[off] ^= 0x10
        _, bad = ic.verify_after(backup, bytes(p3), app, pieces)
        check(bool(bad), "post-install check flags a change in the %s" % why)
    p4 = bytearray(post); p4[0x720000] = 0x00
    _, bad = ic.verify_after(backup, bytes(p4), app, pieces)
    check(not bad, "post-install check permits Cyclift's own data area to change")
    p5 = bytearray(post); p5[0x8000 + 40] ^= 1
    _, bad = ic.verify_after(backup, bytes(p5), app, pieces)
    check(bool(bad), "post-install check flags a wrong partition table")
    cmds = ic.commands(d, "backup.bin", "app.bin", "COM4")
    check(not any("erase_flash" in c or "erase-all" in c or "efuse" in c for c in cmds), "generated commands contain no erase / eFuse operation")
    check(all("keep" in c for c in cmds if "write_flash" in c), "every write keeps flash mode/size/speed")
    order = [c for c in cmds[:12] if "write_flash" in c]
    check(["0x400000" in order[0], "0x1000" in order[1], "0x8000" in order[2], "0xF000" in order[3]] == [True] * 4, "install order: app, bootloader, table, switch")
    print("install_check tests: %d failures" % len(FAILS))
    return 1 if FAILS else 0
if __name__ == "__main__":
    sys.exit(main())
