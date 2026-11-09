#!/usr/bin/env python3
"""Stage 2a install / recovery checks for the factory-preserving layout — OFFLINE FILE CHECKS ONLY.

Nothing here talks to the watch. Three commands:

  verify-after BACKUP AFTER APP PIECES_DIR
      Classify every 4 KB sector of a post-install full read (AFTER) against the backup:
        planned      0x1000, 0x5000, 0x8000, 0xF000 must equal the planned pieces
        app          0x400000 .. +len(APP) must equal APP; rest of app1 must still be erased
        cyclift-data 0x700000 .. 0x7FFFFF may differ (Cyclift settings/files written at run time)
        factory-nvs  0x9000 .. 0xDFFF may differ ONLY by entries of namespace osw-config (factory boot counter)
        everything else must be byte-identical -> otherwise UNEXPECTED (fail)

  recovery-validate BACKUP APP PIECES_DIR
      Build the post-install image offline (backup + planned pieces + APP + simulated Cyclift data + simulated factory
      boot-counter drift), apply recovery levels R-A, R-B, R-C to it, and check each result.

  commands PIECES_DIR BACKUP APP PORT
      Print the exact esptool commands for install phases and recovery levels (for the approval document; not run).
"""
import hashlib
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fp_plan as fp  # noqa: E402

PLANNED = (0x1000, 0x5000, 0x8000, 0xF000)
APP1, APP1_END, CYC_DATA, FLASH = 0x400000, 0x700000, 0x700000, 0x800000
NVS_FAC = (0x9000, 0xE000)
KEEP = "--flash_mode keep --flash_freq keep --flash_size keep"


def sha(b):
    return hashlib.sha256(b).hexdigest()


def load_pieces(d):
    out = {}
    for tag in ("original", "planned"):
        for s in PLANNED:
            p = os.path.join(d, "%s_0x%06x.bin" % (tag, s))
            if os.path.exists(p):
                out[(tag, s)] = open(p, "rb").read()
    return out


def check_manifest(d):
    problems = []
    man = os.path.join(d, "manifest_sha256.txt")
    if not os.path.exists(man):
        return ["manifest_sha256.txt missing"]
    for line in open(man).read().split("\n"):
        if line.strip():
            h, name = line.split()
            p = os.path.join(d, name)
            if not os.path.exists(p):
                problems.append("missing " + name)
            elif sha(open(p, "rb").read()) != h:
                problems.append("hash mismatch " + name)
    return problems


def nvs_namespaces_changed(a, b):
    """Namespaces whose entries differ between two copies of the factory NVS area (names only, never values)."""
    def ns_map(img):
        m = {}
        for off in range(*NVS_FAC, 0x1000):
            for i in range(126):
                st = (img[off + 32 + i // 4] >> ((i % 4) * 2)) & 3
                e = img[off + 64 + i * 32: off + 96 + i * 32]
                if st == 2 and e[0] == 0 and e[1] == 0x01:
                    m[e[24]] = e[8:24].split(b"\0")[0].decode(errors="replace")
        return m
    names = {**ns_map(a), **ns_map(b)}
    changed = set()
    for off in range(*NVS_FAC, 0x1000):
        if a[off:off + 0x1000] == b[off:off + 0x1000]:
            continue
        for i in range(126):
            ea, eb = a[off + 64 + i * 32: off + 96 + i * 32], b[off + 64 + i * 32: off + 96 + i * 32]
            sa = (a[off + 32 + i // 4] >> ((i % 4) * 2)) & 3
            sb = (b[off + 32 + i // 4] >> ((i % 4) * 2)) & 3
            if ea != eb or sa != sb:
                # an entry slot that was written (and possibly superseded) since: take whichever side holds content
                e = eb if eb[:24] != b"\xff" * 24 else ea
                if e[:24] == b"\xff" * 24:
                    continue
                changed.add(names.get(e[0], "#%d" % e[0]) if e[0] else "(namespace record)")
        if a[off:off + 32] != b[off:off + 32]:
            changed.add("(page header)")
    return changed


def verify_after(backup, after, app, pieces, allow_factory_ns=("osw-config", "(page header)")):
    rep, bad = [], []
    if len(after) != FLASH:
        return ["size %d != 8 MB" % len(after)], ["wrong size"]
    app_end = APP1 + len(app)
    app_end_sector = (app_end + 0xFFF) & ~0xFFF
    for s in range(0, FLASH, 0x1000):
        a, b = backup[s:s + 0x1000], after[s:s + 0x1000]
        if s in PLANNED:
            want = pieces.get(("planned", s))
            if want is None or b != want:
                bad.append("planned sector 0x%06x does not match the planned piece" % s)
        elif APP1 <= s < app_end_sector:
            lo, hi = s, min(s + 0x1000, app_end)
            if after[lo:hi] != app[lo - APP1:hi - APP1] or (hi < s + 0x1000 and after[hi:s + 0x1000] != b"\xff" * (s + 0x1000 - hi)):
                bad.append("app sector 0x%06x does not match the Cyclift image" % s)
        elif app_end_sector <= s < APP1_END:
            if b != b"\xff" * 0x1000:
                bad.append("unused part of app1 at 0x%06x is not erased" % s)
        elif CYC_DATA <= s < FLASH:
            pass
        elif NVS_FAC[0] <= s < NVS_FAC[1]:
            pass
        elif a != b:
            bad.append("UNEXPECTED change at 0x%06x" % s)
    ns = nvs_namespaces_changed(backup, after)
    extra = sorted(n for n in ns if n not in allow_factory_ns)
    rep.append("factory settings: changed namespaces = %s" % (sorted(ns) or "none"))
    if extra:
        bad.append("factory settings changed outside %s: %s" % (list(allow_factory_ns), extra))
    used = [s for s in range(CYC_DATA, FLASH, 0x1000) if after[s:s + 0x1000] != b"\xff" * 0x1000]
    rep.append("Cyclift data sectors in use: %d" % len(used))
    rep.append("planned sectors ok: %s" % all(pieces.get(("planned", s)) == after[s:s + 0x1000] for s in PLANNED))
    for nm, lo, hi in (("factory app", 0x10000, 0x210000), ("factory files", 0x210000, 0x400000), ("OTA sector 0", 0xE000, 0xF000)):
        rep.append("%s byte-identical: %s" % (nm, after[lo:hi] == backup[lo:hi]))
    return rep, bad


def simulate_post_install(backup, app, pieces):
    img = bytearray(backup)
    for s in PLANNED:
        img[s:s + 0x1000] = pieces[("planned", s)]
    img[APP1:APP1 + len(app)] = app
    img[0x700000:0x701000] = bytes((i * 13 + 5) & 0xFF for i in range(0x1000))     # Cyclift settings written at run time
    img[0x706000:0x708000] = bytes((i * 7 + 1) & 0xFF for i in range(0x2000))     # Cyclift files
    return bytes(img)


def recovery_validate(backup, app, pieces):
    res, bad = [], []
    post = simulate_post_install(backup, app, pieces)
    n_ota_new = sum(1 for p in fp.parse_pt(post[0x8000:0x8C00]) if p["type"] == 0)
    res.append("post-install image: selected slot %s of %d (1 = Cyclift)" % (fp.selected_slot(post, n_ota_new), n_ota_new))
    if fp.selected_slot(post, n_ota_new) != 1:
        bad.append("simulated install does not select Cyclift")
    # R-A: OTA record only
    ra = bytearray(post); ra[0xF000:0x10000] = pieces[("original", 0xF000)]
    ok = fp.selected_slot(bytes(ra), n_ota_new) == 0
    res.append("R-A (write original 0xF000): factory app selected = %s" % ok)
    if not ok:
        bad.append("R-A does not select the factory app")
    # R-B: four sectors in reverse install order
    rb = bytearray(post)
    for s in (0xF000, 0x8000, 0x1000, 0x5000):
        rb[s:s + 0x1000] = pieces[("original", s)]
    ok = bytes(rb[:0x400000]) == backup[:0x400000]
    res.append("R-B (originals @0xF000, 0x8000, 0x1000, 0x5000): first 4 MB byte-identical to backup = %s" % ok)
    if not ok:
        bad.append("R-B does not restore the first 4 MB")
    pt_ok = fp.parse_pt(rb[0x8000:0x8C00]) == fp.parse_pt(backup[0x8000:0x8C00]) and fp.selected_slot(bytes(rb), 1) == 0
    res.append("R-B: factory partition table and factory selection restored = %s" % pt_ok)
    # R-C: full image
    rc = bytes(backup)
    ok = sha(rc) == sha(backup)
    res.append("R-C (write full backup at 0x0): SHA-256 equals backup = %s" % ok)
    # every original piece really is the backup's bytes
    for s in PLANNED:
        if pieces[("original", s)] != backup[s:s + 0x1000]:
            bad.append("original piece 0x%06x differs from the backup" % s)
    res.append("original pieces equal the backup's sectors: %s" % all(pieces[("original", s)] == backup[s:s + 0x1000] for s in PLANNED))
    # the post-install verifier accepts the simulated install and rejects a tampered one
    rep, b2 = verify_after(backup, post, app, pieces)
    res.append("post-install verifier accepts the simulated install: %s" % (not b2))
    tampered = bytearray(post); tampered[0x150000] ^= 0x01
    _, b3 = verify_after(backup, bytes(tampered), app, pieces)
    res.append("post-install verifier rejects a 1-bit change in the factory app: %s" % bool(b3))
    if b2 or not b3:
        bad.append("post-install verifier self-check failed")
    return res, bad


def commands(pieces_dir, backup, app, port):
    E = "python -m esptool --chip esp32 --port %s --baud 921600" % port
    pc = lambda tag, s: os.path.join(pieces_dir, "%s_0x%06x.bin" % (tag, s))
    out = ["# INSTALL (approval-gated; order is safety-critical)",
           "%s --after hard_reset write_flash %s 0x400000 %s" % (E, KEEP, app),
           "%s verify_flash 0x400000 %s" % (E, app),
           "%s --after no_reset write_flash %s 0x1000 %s 0x5000 %s" % (E, KEEP, pc("planned", 0x1000), pc("planned", 0x5000)),
           "%s verify_flash 0x1000 %s 0x5000 %s" % (E, pc("planned", 0x1000), pc("planned", 0x5000)),
           "%s run" % E,
           "%s --after no_reset write_flash %s 0x8000 %s" % (E, KEEP, pc("planned", 0x8000)),
           "%s verify_flash 0x8000 %s" % (E, pc("planned", 0x8000)),
           "%s run" % E,
           "%s --after no_reset write_flash %s 0xF000 %s" % (E, KEEP, pc("planned", 0xF000)),
           "%s verify_flash 0xF000 %s" % (E, pc("planned", 0xF000)),
           "%s run" % E,
           "",
           "# RECOVERY R-A (back to the factory app)",
           "%s --after no_reset write_flash %s 0xF000 %s" % (E, KEEP, pc("original", 0xF000)),
           "%s verify_flash 0xF000 %s" % (E, pc("original", 0xF000)),
           "%s run" % E,
           "",
           "# RECOVERY R-B (first 4 MB exactly as the factory had it; reverse order)",
           "%s --after no_reset write_flash %s 0xF000 %s" % (E, KEEP, pc("original", 0xF000)),
           "%s --after no_reset write_flash %s 0x8000 %s" % (E, KEEP, pc("original", 0x8000)),
           "%s --after no_reset write_flash %s 0x1000 %s 0x5000 %s" % (E, KEEP, pc("original", 0x1000), pc("original", 0x5000)),
           "%s verify_flash 0xF000 %s 0x8000 %s 0x1000 %s 0x5000 %s" % (E, pc("original", 0xF000), pc("original", 0x8000),
                                                                      pc("original", 0x1000), pc("original", 0x5000)),
           "%s run" % E,
           "",
           "# RECOVERY R-C (complete 8 MB restore)",
           "%s --after no_reset write_flash %s 0x0 %s" % (E, KEEP, backup),
           "%s verify_flash 0x0 %s" % (E, backup),
           "%s run" % E]
    return out


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    cmd = argv[0]
    if cmd == "verify-after":
        backup, after, app = (open(p, "rb").read() for p in argv[1:4])
        pieces = load_pieces(argv[4])
        rep, bad = verify_after(backup, after, app, pieces)
        print("\n".join(rep + ["PROBLEM: " + b for b in bad] + ["post-install verification: " + ("PASS" if not bad else "FAIL")]))
        return 1 if bad else 0
    if cmd == "recovery-validate":
        backup, app = open(argv[1], "rb").read(), open(argv[2], "rb").read()
        probs = check_manifest(argv[3])
        pieces = load_pieces(argv[3])
        res, bad = recovery_validate(backup, app, pieces)
        print("manifest:", "OK" if not probs else probs)
        print("\n".join(res + ["PROBLEM: " + b for b in bad] + ["recovery package (offline): " + ("PASS" if not (bad or probs) else "FAIL")]))
        return 1 if (bad or probs) else 0
    if cmd == "commands":
        print("\n".join(commands(*argv[1:5])))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
