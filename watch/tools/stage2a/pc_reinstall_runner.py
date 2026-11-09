# Cyclift Stage 1 — RE-installation runner (B1, owner-approved 9 Nov 2026 21:24). PC name: cy_reinstall.py.
# Uses the CI-tested installer (cy_install.py, device_session) unchanged; adds only a pre-check for the CURRENT state:
# after Recovery B the first 4 MB are factory again, but the upper flash still holds the approved Stage 1 image at 0x400000
# and the Cyclift settings area 0x700000 written by the factory app during the first install (C3).
# Phases: phase('precheck_re'), then p1, p2, p3, p4, post — one at a time. No erase, no eFuse, no new firmware.
import os, sys, shutil
_INST = os.environ.get('CY_INSTALLER') or os.path.join(os.path.expanduser('~'), 'Documents', 'Cyclift_Stage2a', 'tools', 'cy_install.py')
exec(open(_INST, encoding='utf-8').read())

ARCHIVE = os.path.join(D, 'first_install_20261109')
FIRST_FILES = ('pre_install.bin', 'c1_nvs.bin', 'c2_nvs.bin', 'c3_cyclift_nvs.bin', 'c3_nvs_fac.bin', 'post_install.bin',
               'after_recovery_b_first4MB.bin')
APP1_END = 0x700000


def _archive_first_install():
    """Copy (never move or delete) the first installation's private records before this run writes new ones."""
    if os.path.isdir(ARCHIVE):
        log('first-install records already archived in', os.path.basename(ARCHIVE))
        return
    os.makedirs(ARCHIVE)
    for n in FIRST_FILES:
        p = os.path.join(D, n)
        if os.path.exists(p):
            shutil.copy2(p, os.path.join(ARCHIVE, n))
            must(sha_file(p) == sha_file(os.path.join(ARCHIVE, n)), 'archived copy of %s identical' % n)


def _precheck_re():
    _archive_first_install()
    rc, out = esptool(['flash_id'])
    must(rc == 0, 'COM4 opened exclusively and the watch answered (no other program is using COM4)')
    must('ESP32-PICO-V3-02' in out and 'revision v3.1' in out, 'chip ESP32-PICO-V3-02 rev v3.1')
    must('Detected flash size: 8MB' in out, 'flash 8 MB')
    must(sha_file(BACKUP) == BK_SHA, 'backup fingerprint 77ad7105…')
    must(ic.check_manifest(PD) == [], 'plan pieces match their manifest')
    must(os.path.exists(FW) and sha_file(FW) == FW_SHA, 'firmware file fingerprint faa2828f… (approved)')
    fwb = open(FW, 'rb').read()
    import check_image_header as chk
    mode, freq, size, probs = chk.parse_image(fwb)
    must((mode, freq, size, probs) == ('DIO', '40m', '8MB', []), 'firmware image valid, header DIO/40m/8MB')
    must(len(fwb) <= 0x300000, 'firmware fits app1 (%d B)' % len(fwb))
    log('reading the whole flash (read-only) …')
    pre = read_region(0, 0x800000, 'pre_install.bin')
    B = open(BACKUP, 'rb').read()
    diff = [s for s in range(0, 0x400000, 0x1000) if pre[s:s + 0x1000] != B[s:s + 0x1000]]
    must(all(0x9000 <= s < 0xE000 for s in diff), 'first 4 MB identical to the backup except factory settings sectors (%d differ)' % len(diff))
    ns = ic.nvs_namespaces_changed(B, pre)
    must(ns <= {'osw-config', '(page header)'}, 'factory settings changes limited to osw-config (%s)' % (sorted(ns) or 'none'))
    must(fp.parse_pt(pre[0x8000:0x8C00]) == fp.parse_pt(B[0x8000:0x8C00]) and fp.selected_slot(pre, 1) == 0, 'factory partition table active, factory app selected')
    pieces = ic.load_pieces(PD)
    must(all(pieces[('original', s)] == pre[s:s + 0x1000] for s in ic.PLANNED), 'original pieces equal the watch\'s current sectors 0x1000/0x5000/0x8000/0xF000')
    # upper 4 MB: exactly the approved image left by Recovery B, rest of app1 erased, Cyclift data area as left by the factory app
    must(pre[0x400000:0x400000 + len(fwb)] == fwb, 'upper flash 0x400000 holds exactly the approved Stage 1 image (left in place by Recovery B)')
    tail = (0x400000 + len(fwb) + 0xFFF) & ~0xFFF
    must(pre[0x400000 + len(fwb):tail] == b'\xff' * (tail - 0x400000 - len(fwb)) and pre[tail:APP1_END] == b'\xff' * (APP1_END - tail),
         'rest of the Cyclift program slot erased')
    used = [s for s in range(APP1_END, 0x800000, 0x1000) if pre[s:s + 0x1000] != b'\xff' * 0x1000]
    log('Cyclift data area 0x700000-0x7FFFFF: %d sector(s) in use (written by the factory app at C3 of the first install)' % len(used))
    sim = bytearray(pre)
    for s in ic.PLANNED:
        sim[s:s + 0x1000] = pieces[('planned', s)]
    sim[0x400000:0x400000 + len(fwb)] = fwb
    rep, bad = ic.verify_after(pre, bytes(sim), fwb, pieces)
    must(not bad, 'expected end state (offline) changes only the approved ranges: %s' % bad)
    for nm, lo, hi in (('factory app', 0x10000, 0x210000), ('factory files', 0x210000, 0x400000), ('factory settings', 0x9000, 0xE000)):
        must(sim[lo:hi] == pre[lo:hi], '%s not written by the plan' % nm)
    must(fp.selected_slot(bytes(sim), 2) == 1 and fp.check_layout(bytes(sim[0x8000:0x8C00])) == [], 'end state selects app1; partition table valid')
    for f in [piece('original', s) for s in ic.PLANNED] + [BACKUP, os.path.join(D, 'RECOVERY_AND_INSTALL_COMMANDS_NOT_RUN.txt')]:
        must(os.path.exists(f), 'recovery file present: ' + os.path.basename(f))
    res, bad = ic.recovery_validate(B, fwb, pieces)
    must(not bad, 'recovery package validated offline with the approved firmware')
    txt, boots, r = serial_watch(10, forbid=CYCLIFT)
    must(r.confirmed, 'baseline: factory firmware start confirmed, no reset loop (%s)' % r.reason)


def _p3():
    """As in cy_install, plus: the Cyclift data area already holds factory settings from the first install, so C3 must show
    the factory boot counter ADVANCING there (not merely present)."""
    ok, _ = verify([(0x400000, FW), (0x1000, piece('planned', 0x1000)), (0x5000, piece('planned', 0x5000))]); must(ok, 'pre-condition: Phases 1-2 in place')
    # snapshot of the factory settings taken right before the write (the phase-end restart of Phase 2 lets the factory app
    # run once more and advance its own counter, so the C2 file is not the right reference)
    fac_before = read_region(0x9000, 0x5000, 'c3_nvs_fac_before.bin')
    pr = [(0x8000, piece('planned', 0x8000))]
    ok, out = write(pr); must(ok, 'Phase 3 write partition table 0x8000')
    ok, out = verify(pr); must(ok, 'Phase 3 verify_flash 0x8000')
    cyc_before = bct(open(os.path.join(D, 'pre_install.bin'), 'rb').read()[0x700000:0x706000])
    _checkpoint(True, 'C3')
    cyc = read_region(0x700000, 0x6000, 'c3_cyclift_nvs.bin')
    after = bct(cyc)
    must(after is not None and (cyc_before is None or after > cyc_before), 'C3: factory app ran under the new table (its boot counter in the Cyclift area advanced: %s -> %s)' % (cyc_before, after))
    fac_after = read_region(0x9000, 0x5000, 'c3_nvs_fac.bin')
    must(fac_after == fac_before, 'C3: original factory settings (nvs_fac) unchanged')


AFTER['precheck_re'] = (None, CYCLIFT)
print('cy_reinstall loaded (B1). Run phase("precheck_re") first; then p1, p2, p3, p4, post — one at a time.')
