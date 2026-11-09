# Cyclift Stage 1.1 — app-slot update runner (PROPOSED, not approved; PC name: cy_update_s11.py).
# The watch already runs the factory-preserving layout with Stage 1 (faa2828f…) in app1 at 0x400000. Stage 1.1 replaces ONLY
# the app1 image; bootloader, partition table and OTA record are not written. If the write were interrupted, the bootloader
# finds no valid image in app1 and starts the factory app0 (emulator scenario S5).
# Phases: phase('s11_pre') -> phase('s11_write') -> phase('s11_post'). Rollback to Stage 1: phase('s11_rollback').
# Every phase ends with a restart + boot check (device_session). No erase command, no eFuse, no other flash range.
import os, sys
_INST = os.environ.get('CY_INSTALLER') or os.path.join(os.path.expanduser('~'), 'Documents', 'Cyclift_Stage2a', 'tools', 'cy_install.py')
exec(open(_INST, encoding='utf-8').read())

# Stage 1.1 lives in its own folder; the approved Stage 1 folder (FW) is never written to.
FW11 = os.environ.get('CY_FW11') or os.path.join(DOC, 'Cyclift_Stage2a', 'stage1_1_firmware', 'cyclift-stage1.1-v3poc-T-Watch-2021-V1_1.bin')
FW11_SHA = '3274b8877df0a23a5e5cb1364868322d79d643d29411b36782b6bfb34eb937ba'   # CI runs 42682987729 / 42685750132, owner-named 9 Nov 23:53
WRITE_ADDR, WRITE_LEN = 0x400000, 0xF7000           # app1 start; Stage 1.1 (1,009,632 B) padded to whole sectors: 0x400000-0x4F6FFF
STAGE11 = 'Stage 1.1'                             # boot banner marker of the new firmware
APP1, APP1_END = 0x400000, 0x700000


def padded(src, length, name):
    """The image padded with 0xFF to `length` (whole sectors): writing it also leaves the rest of the old image erased."""
    b = open(src, 'rb').read()
    out = os.path.join(D, name)
    with open(out, 'wb') as f:
        f.write(b + b'\xff' * (length - len(b)))
    return out


def _span():
    a, b = os.path.getsize(FW), os.path.getsize(FW11)
    span = (max(a, b) + 0xFFF) & ~0xFFF
    return span


def _s11_pre():
    rc, out = esptool(['flash_id'])
    must(rc == 0 and 'ESP32-PICO-V3-02' in out and 'Detected flash size: 8MB' in out, 'COM4 exclusive; ESP32-PICO-V3-02, 8 MB')
    must(sha_file(BACKUP) == BK_SHA, 'backup fingerprint 77ad7105…')
    must(ic.check_manifest(PD) == [], 'plan pieces match their manifest')
    must(sha_file(FW) == FW_SHA, 'approved Stage 1 file present for rollback (faa2828f…)')
    must(os.path.exists(FW11) and sha_file(FW11) == FW11_SHA, 'Stage 1.1 file fingerprint matches the approved candidate')
    import check_image_header as chk
    b11 = open(FW11, 'rb').read()
    mode, freq, size, probs = chk.parse_image(b11)
    must((mode, freq, size, probs) == ('DIO', '40m', '8MB', []), 'Stage 1.1 image valid, header DIO/40m/8MB')
    must(len(b11) <= APP1_END - APP1, 'Stage 1.1 fits app1 (%d B)' % len(b11))
    log('reading the whole flash (read-only) …')
    cur = read_region(0, 0x800000, 's11_pre.bin')
    pieces = ic.load_pieces(PD); B = open(BACKUP, 'rb').read(); fw = open(FW, 'rb').read()
    must(all(pieces[('planned', s)] == cur[s:s + 0x1000] for s in ic.PLANNED), 'installed layout in place (bootloader size field, table, OTA record = planned)')
    must(cur[APP1:APP1 + len(fw)] == fw, 'app1 holds exactly the approved Stage 1 (faa2828f…)')
    for nm, lo, hi in (('factory app', 0x10000, 0x210000), ('factory files', 0x210000, 0x400000)):
        must(cur[lo:hi] == B[lo:hi], '%s byte-identical to the backup' % nm)
    must(fp.selected_slot(cur, 2) == 1, 'OTA record selects app1')
    span = _span()
    must(span == WRITE_LEN and APP1 + span <= APP1_END, 'write plan: app1 only, 0x%06x-0x%06x (%d B = Stage 1.1 padded to whole sectors)' % (APP1, APP1 + span - 1, span))
    must(cur[APP1 + span:APP1_END] == b'\xff' * (APP1_END - APP1 - span), 'rest of app1 beyond the update span erased')
    padded(FW, span, 's11_rollback_stage1_padded.bin'); padded(FW11, span, 's11_stage11_padded.bin')
    txt, boots, r = serial_watch(12, expect=CYCLIFT, forbid=STAGE11)
    must(r.confirmed, 'baseline: Stage 1 running, one start (%s)' % r.reason)


def _s11_write():
    src = os.path.join(D, 's11_stage11_padded.bin')
    must(os.path.exists(src) and open(src, 'rb').read().startswith(open(FW11, 'rb').read()) and os.path.getsize(src) == WRITE_LEN and APP1 == WRITE_ADDR,
         'padded Stage 1.1 image prepared by s11_pre (%d B for 0x%06x)' % (WRITE_LEN, WRITE_ADDR))
    ok, _ = write([(APP1, src)]); must(ok, 'write Stage 1.1 -> app1 0x400000 (%d B incl. erased padding)' % os.path.getsize(src))
    ok, _ = verify([(APP1, src)]); must(ok, 'verify_flash app1')
    txt, boots, r = serial_watch(15, expect=STAGE11)
    for l in [l for l in txt.splitlines() if l.strip()][:8]:
        log('   | ' + l[:150])
    must(r.confirmed, 'Stage 1.1 start confirmed: one start, banner (%s)' % r.reason)


def _s11_post():
    after = read_region(0, 0x800000, 's11_post.bin')
    pre = open(os.path.join(D, 's11_pre.bin'), 'rb').read()
    span = _span()
    diff = [s for s in range(0, 0x800000, 0x1000) if after[s:s + 0x1000] != pre[s:s + 0x1000]]
    outside = [hex(s) for s in diff if not (APP1 <= s < APP1 + span or s >= 0x700000)]
    log('changed sectors:', len(diff), '; outside app1 span and Cyclift data area:', outside or 'none')
    must(not outside, 'only the app1 update span (and the Cyclift data area) changed')
    must(after[APP1:APP1 + span] == open(os.path.join(D, 's11_stage11_padded.bin'), 'rb').read(), 'app1 = Stage 1.1 image + erased padding')


def _s11_rollback():
    """Reviewed rollback to the approved Stage 1: write faa2828f… (padded) back into app1."""
    src = os.path.join(D, 's11_rollback_stage1_padded.bin')
    must(os.path.exists(src) and open(src, 'rb').read().startswith(open(FW, 'rb').read()) and sha_file(FW) == FW_SHA, 'padded approved Stage 1 image ready')
    ok, _ = write([(APP1, src)]); must(ok, 'rollback write Stage 1 -> app1')
    ok, _ = verify([(APP1, src)]); must(ok, 'rollback verify_flash app1')
    txt, boots, r = serial_watch(15, expect=CYCLIFT, forbid=STAGE11)
    must(r.confirmed, 'Stage 1 start confirmed after rollback (%s)' % r.reason)


AFTER.update({'s11_pre': (CYCLIFT, STAGE11), 's11_write': (STAGE11, None), 's11_post': (STAGE11, None), 's11_rollback': (CYCLIFT, STAGE11)})
print('cy_update_s11 loaded (PROPOSED). phase("s11_pre"), phase("s11_write"), phase("s11_post"); rollback: phase("s11_rollback")')
