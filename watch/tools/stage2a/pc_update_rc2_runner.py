# Cyclift Stage 1.3 RC2 — app-slot update runner (PROPOSED, not approved; PC name: cy_update_rc2.py).
# The watch runs the factory-preserving layout with Stage 1.3 RC1 (4ea0ea90…) in app1 at 0x400000 (installed 11 Nov 15:53).
# RC2 replaces ONLY the app1 image, exactly like the reviewed RC1 update (cy_update_s13.py, loaded below and unchanged);
# bootloader, partition table and OTA record are not written. An interrupted write → the bootloader finds no valid image in
# app1 and starts the factory app0 (emulator S10, run against RC1 → RC2 in CI).
# Phases: phase('r2_pre') -> phase('r2_write') -> phase('r2_post'). Rollback to RC1: phase('r2_rollback').
# Further rollbacks stay available: phase('s13_rollback') → Stage 1.1, phase('s11_rollback') → Stage 1.
import os, sys
_S13 = os.environ.get('CY_UPDATE_S13') or os.path.join(os.path.expanduser('~'), 'Documents', 'Cyclift_Stage2a', 'tools', 'cy_update_s13.py')
exec(open(_S13, encoding='utf-8').read())          # cy_install + Stage 1.1 / RC1 constants and phases

FWR2 = os.environ.get('CY_FWR2') or os.path.join(DOC, 'Cyclift_Stage2a', 'stage1_3_firmware', 'cyclift-stage1.3-rc2-v3poc-T-Watch-2021-V1_1.bin')
FWR2_SHA = '82500ce2a2531271573489c9080d7372e0ee97c330e44cbb85f2f3a2040da461'   # CI 43064696858 (commit 6c07f69); install needs the owner's approval naming it
RC1 = 'Stage 1.3 RC1'                             # boot banner marker of the installed firmware
RC2 = 'Stage 1.3 RC2'                             # boot banner marker of the new firmware


def _span_r2():
    """Bytes written: the larger of RC1 and RC2, rounded up to whole 4 KB sectors (also covers the rollback)."""
    return (max(os.path.getsize(FW13), os.path.getsize(FWR2), WRITE_LEN) + 0xFFF) & ~0xFFF


def _r2_pre():
    rc, out = esptool(['flash_id'])
    must(rc == 0 and 'ESP32-PICO-V3-02' in out and 'Detected flash size: 8MB' in out, 'COM4 exclusive; ESP32-PICO-V3-02, 8 MB')
    must(sha_file(BACKUP) == BK_SHA, 'backup fingerprint 77ad7105…')
    must(ic.check_manifest(PD) == [], 'plan pieces match their manifest')
    must(sha_file(FW) == FW_SHA, 'approved Stage 1 file present (faa2828f…)')
    must(os.path.exists(FW11) and sha_file(FW11) == FW11_SHA, 'Stage 1.1 file present (3274b887…)')
    must(os.path.exists(FW13) and sha_file(FW13) == FW13_SHA, 'installed RC1 file present for rollback (4ea0ea90…)')
    must(os.path.exists(FWR2) and sha_file(FWR2) == FWR2_SHA, 'Stage 1.3 RC2 file fingerprint matches the approved candidate')
    import check_image_header as chk
    b = open(FWR2, 'rb').read()
    mode, freq, size, probs = chk.parse_image(b)
    must((mode, freq, size, probs) == ('DIO', '40m', '8MB', []), 'RC2 image valid, header DIO/40m/8MB')
    must(len(b) <= APP1_END - APP1, 'RC2 fits app1 (%d B)' % len(b))
    log('reading the whole flash (read-only) …')
    cur = read_region(0, 0x800000, 'r2_pre.bin')
    pieces = ic.load_pieces(PD); B = open(BACKUP, 'rb').read(); rc1 = open(FW13, 'rb').read()
    must(all(pieces[('planned', s)] == cur[s:s + 0x1000] for s in ic.PLANNED), 'installed layout in place (bootloader size field, table, OTA record = planned)')
    must(cur[APP1:APP1 + len(rc1)] == rc1, 'app1 holds exactly the installed RC1 (4ea0ea90…)')
    for nm, lo, hi in (('factory app', 0x10000, 0x210000), ('factory files', 0x210000, 0x400000)):
        must(cur[lo:hi] == B[lo:hi], '%s byte-identical to the backup' % nm)
    must(fp.selected_slot(cur, 2) == 1, 'OTA record selects app1')
    span = _span_r2()
    must(APP1 + span <= APP1_END, 'write plan: app1 only, 0x%06x-0x%06x (%d B = larger image padded to whole sectors)' % (APP1, APP1 + span - 1, span))
    must(cur[APP1 + len(rc1):APP1_END] == b'\xff' * (APP1_END - APP1 - len(rc1)), 'rest of app1 after RC1 erased')
    padded(FW13, span, 'r2_rollback_rc1_padded.bin'); padded(FWR2, span, 'r2_rc2_padded.bin')
    txt, boots, r = serial_watch(12, expect=RC1, forbid=RC2)
    must(r.confirmed, 'baseline: RC1 running, one start (%s)' % r.reason)


def _r2_write():
    src = os.path.join(D, 'r2_rc2_padded.bin'); span = _span_r2()
    must(os.path.exists(src) and open(src, 'rb').read().startswith(open(FWR2, 'rb').read()) and os.path.getsize(src) == span and sha_file(FWR2) == FWR2_SHA,
         'padded RC2 image prepared by r2_pre (%d B for 0x%06x)' % (span, APP1))
    ok, _ = write([(APP1, src)]); must(ok, 'write RC2 -> app1 0x400000 (%d B incl. erased padding)' % span)
    ok, _ = verify([(APP1, src)]); must(ok, 'verify_flash app1')
    txt, boots, r = serial_watch(15, expect=RC2)
    for l in [l for l in txt.splitlines() if l.strip()][:8]:
        log('   | ' + l[:150])
    must(r.confirmed, 'RC2 start confirmed: one start, banner (%s)' % r.reason)


def _r2_post():
    after = read_region(0, 0x800000, 'r2_post.bin')
    pre = open(os.path.join(D, 'r2_pre.bin'), 'rb').read()
    span = _span_r2()
    diff = [s for s in range(0, 0x800000, 0x1000) if after[s:s + 0x1000] != pre[s:s + 0x1000]]
    outside = [hex(s) for s in diff if not (APP1 <= s < APP1 + span or s >= 0x700000)]
    log('changed sectors:', len(diff), '; outside app1 span and Cyclift data area:', outside or 'none')
    must(not outside, 'only the app1 update span (and the Cyclift data area) changed')
    must(after[APP1:APP1 + span] == open(os.path.join(D, 'r2_rc2_padded.bin'), 'rb').read(), 'app1 = RC2 image + erased padding')


def _r2_rollback():
    """Reviewed rollback to the installed RC1: write 4ea0ea90… (padded over the same span) back into app1."""
    src = os.path.join(D, 'r2_rollback_rc1_padded.bin')
    must(os.path.exists(src) and open(src, 'rb').read().startswith(open(FW13, 'rb').read()) and sha_file(FW13) == FW13_SHA, 'padded RC1 image ready')
    ok, _ = write([(APP1, src)]); must(ok, 'rollback write RC1 -> app1')
    ok, _ = verify([(APP1, src)]); must(ok, 'rollback verify_flash app1')
    txt, boots, r = serial_watch(15, expect=RC1, forbid=RC2)
    must(r.confirmed, 'RC1 start confirmed after rollback (%s)' % r.reason)


AFTER.update({'r2_pre': (RC1, RC2), 'r2_write': (RC2, None), 'r2_post': (RC2, None), 'r2_rollback': (RC1, RC2)})
print('cy_update_rc2 loaded (PROPOSED). phase("r2_pre"), phase("r2_write"), phase("r2_post"); rollback: phase("r2_rollback")')
