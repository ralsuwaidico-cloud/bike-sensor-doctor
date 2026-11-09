#!/usr/bin/env python3
"""Stage 2a boot simulation in Espressif's ESP32 emulator (QEMU) — CI only, never touches the watch or its backup.

Builds synthetic 8 MB flash images shaped exactly like the owner's watch (same factory partition table, same OTA-data
state, factory-equivalent bootloader in DIO / 40 MHz / 4 MB), applies the factory-preserving plan from fp_plan.py, boots
each image in QEMU and records which program the bootloader actually started. Scenarios:

  S0 original layout                                   -> expect the factory stand-in (app0)
  S1 plan (bootloader header 8 MB)                     -> expect Cyclift (app1), default nvs at 0x700000, factory regions unchanged
  S2 plan but bootloader header left at 4 MB           -> records whether the size field change is really needed
  S3 plan, app1 image corrupted                        -> does the bootloader fall back to app0?
  S4 plan, app1 erased                                 -> does the bootloader fall back to app0?
  S5 plan, app1 valid but crashes at start             -> does anything fall back? (expected: no — boot loop)
  S6 S1 after running, then the small rollback         -> first 4 MB byte-identical to the original, factory boots
  S7 S1 after running, only OTA-data sector restored   -> factory app runs under the new table (with its own data isolated)

Usage: boot_sim.py --qemu QEMU --bootloader BL.bin [--bootloader-note TEXT] --app-a A.bin --app-b B.bin --app-crash C.bin --out DIR
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fp_plan as fp  # noqa: E402

FACTORY_ENTRIES = [("nvs", 1, 2, 0x9000, 0x5000), ("otadata", 1, 0, 0xE000, 0x2000),
                   ("app0", 0, 0x10, 0x10000, 0x200000), ("spiffs", 1, 0x82, 0x210000, 0x1F0000)]


def set_header(img, mode, size_code, freq):
    img = bytearray(img)
    img[2] = mode
    img[3] = (size_code << 4) | freq
    if img[23] == 1:
        n = fp.image_len(bytes(img), 0) - 32
        img[n:n + 32] = hashlib.sha256(bytes(img[:n])).digest()
    return bytes(img)


def original_image(bootloader, app_a):
    img = bytearray(b"\xff" * fp.FLASH)
    bl = set_header(bootloader[:fp.image_len(bootloader, 0)], 2, 2, 0)    # as on the watch: DIO, 4 MB, 40 MHz
    img[0x1000:0x1000 + len(bl)] = bl
    pt = fp.build_pt([fp.entry(*e) for e in FACTORY_ENTRIES])
    img[0x8000:0x8000 + len(pt)] = pt
    img[0xE000:0xE020] = fp.ota_entry(1)                                    # as on the watch: seq 1 / seq 0
    img[0xF000:0xF020] = fp.ota_entry(0)
    img[0x10000:0x10000 + len(app_a)] = app_a
    return bytes(img)


def run_qemu(qemu, image, seconds, workdir, name):
    path = os.path.join(workdir, name + ".bin")
    open(path, "wb").write(image)
    cmd = [qemu, "-nographic", "-machine", "esp32", "-m", "4M", "-drive", "file=%s,if=mtd,format=raw" % path,
           "-global", "driver=timer.esp32.timg,property=wdt_disable,value=true"]
    t = time.time()
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    try:
        out, _ = p.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        p.kill()
        out, _ = p.communicate()
    log = out.decode("utf-8", "replace")
    open(os.path.join(workdir, name + ".log"), "w").write(log)
    return log, open(path, "rb").read(), time.time() - t


def probes(log):
    roles = re.findall(r"BOOTPROBE role=(\S+) running=(\S+) addr=(0x[0-9a-f]+)", log)
    nvs = re.findall(r"BOOTPROBE default_nvs=(0x[0-9a-f]+)", log)
    return dict(boots=len(roles), roles=sorted(set(r[0] for r in roles)), running=sorted(set(r[1] + "@" + r[2] for r in roles)),
                default_nvs=sorted(set(nvs)), nvs_write="BOOTPROBE nvs_write_ok" in log,
                littlefs_write="BOOTPROBE littlefs_write_ok" in log, done="BOOTPROBE done" in log,
                rom_boot_lines=len(re.findall(r"rst:0x", log)))


def same(a, b, lo, hi):
    return a[lo:hi] == b[lo:hi]


def main():
    ap = argparse.ArgumentParser()
    for k in ("qemu", "bootloader", "app-a", "app-b", "app-crash", "out"):
        ap.add_argument("--" + k, required=True)
    ap.add_argument("--bootloader-note", default="")
    ap.add_argument("--app-stage1", default="", help="real Stage 1 (v3poc) firmware.bin, booted from app1 as S8")
    ap.add_argument("--seconds", type=float, default=25)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    bl = open(a.bootloader, "rb").read()
    app_a, app_b, app_c = (open(x, "rb").read() for x in (a.app_a, a.app_b, a.app_crash))
    orig = original_image(bl, app_a)
    planned, notes = fp.apply_plan(orig, app_b, patch_bootloader=True)
    plan_4mb, _ = fp.apply_plan(orig, app_b, patch_bootloader=False)
    corrupt = bytearray(planned)
    corrupt[0x400000 + 0x2000] ^= 0xFF
    erased = bytearray(planned)
    erased[0x400000:0x700000] = b"\xff" * 0x300000
    crash, _ = fp.apply_plan(orig, app_c, patch_bootloader=True)

    results, fails = {}, []

    def expect(cond, msg):
        print(("PASS " if cond else "FAIL ") + msg)
        if not cond:
            fails.append(msg)

    def scenario(name, image, seconds=None):
        log, after, dt = run_qemu(a.qemu, image, seconds or a.seconds, a.out, name)
        r = probes(log)
        r["seconds"] = round(dt, 1)
        results[name] = r
        print("%s: %s" % (name, json.dumps(r)))
        return r, after

    r, _ = scenario("S0_original", orig)
    expect(r["roles"] == ["FACTORY_STANDIN"] and r["running"] == ["app0@0x010000"], "S0 original layout boots the factory stand-in from app0")
    r, s1_after = scenario("S1_plan", planned)
    expect(r["roles"] == ["CYCLIFT"] and r["running"] == ["app1@0x400000"], "S1 plan boots Cyclift from app1 (0x400000)")
    expect(r["default_nvs"] == ["0x700000"] and r["nvs_write"], "S1 Cyclift settings go to its own nvs at 0x700000")
    for nm, lo, hi in (("factory settings", 0x9000, 0xE000), ("OTA-data sector 0", 0xE000, 0xF000),
                       ("factory app", 0x10000, 0x210000), ("factory files", 0x210000, 0x400000), ("bootloader+table", 0x1000, 0x9000)):
        expect(same(s1_after, planned, lo, hi), "S1 %s unchanged after Cyclift ran" % nm)
    print("     S1 sectors Cyclift itself changed while running:",
          ", ".join("0x%06x-0x%06x" % x for x in fp.ranges(fp.changed_sectors(planned, s1_after))) or "none")
    r, _ = scenario("S2_plan_bootloader_4MB", plan_4mb)
    results["S2_plan_bootloader_4MB"]["interpretation"] = (
        "4 MB header still boots app1 - size-field change NOT required" if r["roles"] == ["CYCLIFT"] else
        "4 MB header does not boot app1 - size-field change IS required" if r["roles"] == ["FACTORY_STANDIN"] else "no program started")
    print("     S2:", results["S2_plan_bootloader_4MB"]["interpretation"])
    r, _ = scenario("S3_app1_corrupted", bytes(corrupt))
    results["S3_app1_corrupted"]["fallback_to_factory"] = r["roles"] == ["FACTORY_STANDIN"]
    print("     S3 automatic fallback on a corrupted image:", r["roles"] == ["FACTORY_STANDIN"])
    r, _ = scenario("S4_app1_erased", bytes(erased))
    results["S4_app1_erased"]["fallback_to_factory"] = r["roles"] == ["FACTORY_STANDIN"]
    print("     S4 automatic fallback on an empty slot:", r["roles"] == ["FACTORY_STANDIN"])
    r, _ = scenario("S5_app1_crashes", crash)
    results["S5_app1_crashes"]["fallback_to_factory"] = "FACTORY_STANDIN" in r["roles"]
    print("     S5 automatic fallback when Cyclift crashes at start:", "FACTORY_STANDIN" in r["roles"],
          "(Cyclift started %d times)" % r["boots"])
    secs = fp.changed_sectors(orig, planned)
    small = [s for s in secs if s < 0x400000]
    rolled = fp.rollback(s1_after, orig, small)
    expect(same(rolled, orig, 0, 0x400000), "S6 small rollback (%d sectors) makes the first 4 MB byte-identical to the original" % len(small))
    full = fp.rollback(s1_after, orig, fp.changed_sectors(orig, s1_after))
    expect(full == orig, "S6 full rollback of every changed sector restores the whole image byte-for-byte")
    r, _ = scenario("S6_after_small_rollback", rolled)
    expect(r["roles"] == ["FACTORY_STANDIN"] and r["running"] == ["app0@0x010000"], "S6 factory stand-in boots after the small rollback")
    ota_only = fp.rollback(s1_after, orig, [0xF000])
    r, after7 = scenario("S7_only_otadata_restored", ota_only)
    expect(r["roles"] == ["FACTORY_STANDIN"], "S7 restoring only the OTA-data sector switches back to the factory app")
    expect(r["default_nvs"] == ["0x700000"] and same(after7, ota_only, 0x9000, 0xE000),
           "S7 factory app under the new table uses the Cyclift nvs; original factory settings stay untouched")

    # Install checkpoints: the watch must still boot the factory app after every intermediate step (switch is last).
    step1 = bytearray(orig); step1[0x400000:0x400000 + len(app_b)] = app_b
    step2 = bytearray(step1); bl_len = fp.image_len(orig, 0x1000)
    step2[0x1000:0x1000 + bl_len] = planned[0x1000:0x1000 + bl_len]
    step3 = bytearray(step2); step3[0x8000:0x8C00] = planned[0x8000:0x8C00]
    no_bl = bytearray(step1); no_bl[0x8000:0x8C00] = planned[0x8000:0x8C00]
    expect(bytes(step3[:0xF000]) == planned[:0xF000] and step3[0x10000:] == planned[0x10000:], "checkpoint images are consistent with the plan")
    for nm, img, want in (("C1_after_app_write", step1, "FACTORY_STANDIN"), ("C2_after_bootloader_patch", step2, "FACTORY_STANDIN"),
                          ("C3_after_table_write", step3, "FACTORY_STANDIN"), ("C2x_table_without_bootloader_patch", no_bl, None)):
        r, _ = scenario(nm, bytes(img))
        if want:
            expect(r["roles"] == [want] and r["running"] == ["app0@0x010000"], "%s: factory app still starts" % nm)
        else:
            print("     %s (informational): roles=%s restarts=%d" % (nm, r["roles"], r["rom_boot_lines"]))

    if a.app_stage1:
        st1 = open(a.app_stage1, "rb").read()
        for tag, patch in (("8MB_header", True), ("original_bootloader", False)):
            img, _ = fp.apply_plan(orig, st1, patch_bootloader=patch)
            log, after, dt = run_qemu(a.qemu, img, max(a.seconds, 40), a.out, "S8_stage1_" + tag)
            started = "Cyclift v3 proof of concept" in log
            lines = [l for l in log.splitlines() if l.strip()][:25]
            results["S8_stage1_" + tag] = dict(stage1_banner=started, rom_boot_lines=len(re.findall(r"rst:0x", log)),
                                              factory_regions_unchanged=all(same(after, img, lo, hi) for lo, hi in
                                                  ((0x9000, 0xE000), (0x10000, 0x210000), (0x210000, 0x400000))),
                                              first_lines=lines, seconds=round(dt, 1))
            print("S8 Stage 1 firmware from app1 (%s): banner printed=%s, rom boots=%d" % (tag, started, results["S8_stage1_" + tag]["rom_boot_lines"]))
            for l in lines[:12]:
                print("     | " + l[:160])

    summary = dict(bootloader=os.path.basename(a.bootloader), bootloader_note=a.bootloader_note,
                   bootloader_normalized_sha256=fp.normalized_bootloader_sha(bl[:fp.image_len(bl, 0)]),
                   plan_notes=notes, planned_changed_ranges=["0x%06x-0x%06x" % x for x in fp.ranges(secs)],
                   scenarios=results, failures=fails)
    json.dump(summary, open(os.path.join(a.out, "boot_sim_summary.json"), "w"), indent=1)
    print("boot simulation: %d failures" % len(fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
