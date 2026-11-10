# Cyclift Stage 1.3 RC1 — app-slot update runner (PROPOSED, not approved; PC name: cy_update_s13.py).
# Same procedure as the reviewed Stage 1.2 runner (pc_update_s12_runner.py, kept unchanged); only the image differs.
# The watch runs the factory-preserving layout with Stage 1.1 (3274b887…) in app1 at 0x400000 (installed 10 Nov, C1).
# Stage 1.3 RC1 replaces ONLY the app1 image, exactly like the Stage 1.1 update; bootloader, partition table and OTA record are
# not written. If the write were interrupted, the bootloader finds no valid image in app1 and starts the factory app0
# (emulator S10, run against Stage 1.1 → Stage 1.3 RC1 in CI).
# Phases: phase('s13_pre') -> phase('s13_write') -> phase('s13_post'). Rollback to Stage 1.1: phase('s13_rollback').
# Rollback further to Stage 1 stays available: phase('s11_rollback') from cy_update_s11.py (loaded below).
# Every phase ends with a restart + boot check (device_session). No erase command, no eFuse, no other flash range.
import os, sys
_S11 = os.environ.get('CY_UPDATE_S11') or os.path.join(os.path.expanduser('~'), 'Documents', 'Cyclift_Stage2a', 'tools', 'cy_update_s11.py')
exec(open(_S11, encoding='utf-8').read())          # cy_install + Stage 1.1 constants (FW, FW11, …) and its phases

FW13 = os.environ.get('CY_FW13') or os.path.join(DOC, 'Cyclift_Stage2a', 'stage1_3_firmware', 'cyclift-stage1.3-rc1-v3poc-T-Watch-2021-V1_1.bin')
FW13_SHA = '4ea0ea90da5061859019c7b6f94c1eaea409c362d94a07e058d7755feda50c19'   # CI 42916312090 (commit 6854b9b); install needs the owner's approval naming it
STAGE13 = 'Stage 1.3'                             # boot banner marker of the new firmware


def _span13():
    """Bytes written: the larger of Stage 1.1 and Stage 1.3 RC1, rounded up to whole 4 KB sectors (also covers the rollback)."""
    a, b = os.path.getsize(FW11), os.path.getsize(FW13)
    return (max(a, b, WRITE_LEN) + 0xFFF) & ~0xFFF


def _s13_pre():
    rc, out = esptool(['flash_id'])
    must(rc == 0 and 'ESP32-PICO-V3-02' in out and 'Detected flash size: 8MB' in out, 'COM4 exclusive; ESP32-PICO-V3-02, 8 MB')
    must(sha_file(BACKUP) == BK_SHA, 'backup fingerprint 77ad7105…')
    must(ic.check_manifest(PD) == [], 'plan pieces match their manifest')
    must(sha_file(FW) == FW_SHA, 'approved Stage 1 file present (faa2828f…)')
    must(os.path.exists(FW11) and sha_file(FW11) == FW11_SHA, 'installed Stage 1.1 file present for rollback (3274b887…)')
    must(os.path.exists(FW13) and sha_file(FW13) == FW13_SHA, 'Stage 1.3 RC1 file fingerprint matches the approved candidate')
    import check_image_header as chk
    b13 = open(FW13, 'rb').read()
    mode, freq, size, probs = chk.parse_image(b13)
    must((mode, freq, size, probs) == ('DIO', '40m', '8MB', []), 'Stage 1.3 RC1 image valid, header DIO/40m/8MB')
    must(len(b13) <= APP1_END - APP1, 'Stage 1.3 RC1 fits app1 (%d B)' % len(b13))
    log('reading the whole flash (read-only) …')
    cur = read_region(0, 0x800000, 's13_pre.bin')
    pieces = ic.load_pieces(PD); B = open(BACKUP, 'rb').read(); fw11 = open(FW11, 'rb').read()
    must(all(pieces[('planned', s)] == cur[s:s + 0x1000] for s in ic.PLANNED), 'installed layout in place (bootloader size field, table, OTA record = planned)')
    must(cur[APP1:APP1 + len(fw11)] == fw11, 'app1 holds exactly the installed Stage 1.1 (3274b887…)')
    for nm, lo, hi in (('factory app', 0x10000, 0x210000), ('factory files', 0x210000, 0x400000)):
        must(cur[lo:hi] == B[lo:hi], '%s byte-identical to the backup' % nm)
    must(fp.selected_slot(cur, 2) == 1, 'OTA record selects app1')
    span = _span13()
    must(APP1 + span <= APP1_END, 'write plan: app1 only, 0x%06x-0x%06x (%d B = larger image padded to whole sectors)' % (APP1, APP1 + span - 1, span))
    must(cur[APP1 + len(fw11):APP1_END] == b'\xff' * (APP1_END - APP1 - len(fw11)), 'rest of app1 after Stage 1.1 erased')
    padded(FW11, span, 's13_rollback_stage11_padded.bin'); padded(FW13, span, 's13_stage12_padded.bin')
    txt, boots, r = serial_watch(12, expect=STAGE11, forbid=STAGE13)
    must(r.confirmed, 'baseline: Stage 1.1 running, one start (%s)' % r.reason)


def _s13_write():
    src = os.path.join(D, 's13_stage12_padded.bin'); span = _span13()
    must(os.path.exists(src) and open(src, 'rb').read().startswith(open(FW13, 'rb').read()) and os.path.getsize(src) == span and sha_file(FW13) == FW13_SHA,
         'padded Stage 1.3 RC1 image prepared by s13_pre (%d B for 0x%06x)' % (span, APP1))
    ok, _ = write([(APP1, src)]); must(ok, 'write Stage 1.3 RC1 -> app1 0x400000 (%d B incl. erased padding)' % span)
    ok, _ = verify([(APP1, src)]); must(ok, 'verify_flash app1')
    txt, boots, r = serial_watch(15, expect=STAGE13)
    for l in [l for l in txt.splitlines() if l.strip()][:8]:
        log('   | ' + l[:150])
    must(r.confirmed, 'Stage 1.3 RC1 start confirmed: one start, banner (%s)' % r.reason)


def _s13_post():
    after = read_region(0, 0x800000, 's13_post.bin')
    pre = open(os.path.join(D, 's13_pre.bin'), 'rb').read()
    span = _span13()
    diff = [s for s in range(0, 0x800000, 0x1000) if after[s:s + 0x1000] != pre[s:s + 0x1000]]
    outside = [hex(s) for s in diff if not (APP1 <= s < APP1 + span or s >= 0x700000)]
    log('changed sectors:', len(diff), '; outside app1 span and Cyclift data area:', outside or 'none')
    must(not outside, 'only the app1 update span (and the Cyclift data area) changed')
    must(after[APP1:APP1 + span] == open(os.path.join(D, 's13_stage12_padded.bin'), 'rb').read(), 'app1 = Stage 1.3 RC1 image + erased padding')


def _s13_rollback():
    """Reviewed rollback to the installed Stage 1.1: write 3274b887… (padded over the same span) back into app1."""
    src = os.path.join(D, 's13_rollback_stage11_padded.bin')
    must(os.path.exists(src) and open(src, 'rb').read().startswith(open(FW11, 'rb').read()) and sha_file(FW11) == FW11_SHA, 'padded Stage 1.1 image ready')
    ok, _ = write([(APP1, src)]); must(ok, 'rollback write Stage 1.1 -> app1')
    ok, _ = verify([(APP1, src)]); must(ok, 'rollback verify_flash app1')
    txt, boots, r = serial_watch(15, expect=STAGE11, forbid=STAGE13)
    must(r.confirmed, 'Stage 1.1 start confirmed after rollback (%s)' % r.reason)


AFTER.update({'s13_pre': (STAGE11, STAGE13), 's13_write': (STAGE13, None), 's13_post': (STAGE13, None), 's13_rollback': (STAGE11, STAGE13)})
print('cy_update_s13 loaded (PROPOSED). phase("s13_pre"), phase("s13_write"), phase("s13_post"); rollback: phase("s13_rollback")')
