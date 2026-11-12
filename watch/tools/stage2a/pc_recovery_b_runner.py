# Cyclift — Recovery Level B (owner-approved 9 Nov 2026 19:52). Reviewed procedure only:
# original sectors written back in reverse install order: 0xF000, 0x8000, then 0x1000 + 0x5000; keep flags; verify each.
# Cyclift firmware in the upper flash is left in place (not erased). No other writes.
# Revision 2: reuses the installer's DeviceSession — every phase ends with a restart + boot check (see device_session.py).
import os, sys
for m in ('fp_plan', 'install_check', 'check_image_header', 'device_session'):
    sys.modules.pop(m, None)
_INST = os.environ.get('CY_INSTALLER') or os.path.join(os.path.expanduser('~'), 'Documents', 'Cyclift_Stage2a', 'tools', 'cy_install.py')
exec(open(_INST, encoding='utf-8').read())
AFTER.update({'rb_precheck': (CYCLIFT, None), 'rb_restore': (None, CYCLIFT), 'rb_confirm': (None, CYCLIFT)})


# Cyclift program in app1: the approved Stage 1, or — after a Stage 1.1 update — the approved Stage 1.1 (R-B never writes app1).
FW11 = os.environ.get('CY_FW11') or os.path.join(DOC, 'Cyclift_Stage2a', 'stage1_1_firmware', 'cyclift-stage1.1-v3poc-T-Watch-2021-V1_1.bin')
FW11_SHA = '3274b8877df0a23a5e5cb1364868322d79d643d29411b36782b6bfb34eb937ba'
FW12 = os.environ.get('CY_FW12') or os.path.join(DOC, 'Cyclift_Stage2a', 'stage1_2_firmware', 'cyclift-stage1.2-v3poc-T-Watch-2021-V1_1.bin')
FW12_SHA = '2760f5a7f4c4064e3dbbf70e9bd2af9c76be8a8e6f8ecc492cfc0e09f66ae75a'
FW13 = os.environ.get('CY_FW13') or os.path.join(DOC, 'Cyclift_Stage2a', 'stage1_3_firmware', 'cyclift-stage1.3-rc1-v3poc-T-Watch-2021-V1_1.bin')
FW13_SHA = '4ea0ea90da5061859019c7b6f94c1eaea409c362d94a07e058d7755feda50c19'   # Stage 1.3 RC1 (CI 42916312090); same pin as cy_update_s13.py
FWR2 = os.environ.get('CY_FWR2') or os.path.join(DOC, 'Cyclift_Stage2a', 'stage1_3_firmware', 'cyclift-stage1.3-rc2-v3poc-T-Watch-2021-V1_1.bin')
FWR2_SHA = '82500ce2a2531271573489c9080d7372e0ee97c330e44cbb85f2f3a2040da461'   # Stage 1.3 RC2 (CI 43064696858); same pin as cy_update_rc2.py
FW14 = os.environ.get('CY_FWS14') or os.path.join(DOC, 'Cyclift_Stage2a', 'stage1_4_firmware', 'cyclift-stage1.4-rc1-v3poc-T-Watch-2021-V1_1.bin')
FW14_SHA = 'PIN-AFTER-CI'   # Stage 1.4 RC1 (button system); same pin as cy_update_s14.py once CI has built it


def app1_program():
    """Which approved program app1 holds (Stage 1, 1.1, 1.2, 1.3 RC1, RC2 or 1.4 RC1; read-only verify_flash); None if none matches."""
    if verify([(0x400000, FW)])[0]:
        return FW
    if os.path.exists(FW11) and sha_file(FW11) == FW11_SHA and verify([(0x400000, FW11)])[0]:
        return FW11
    if os.path.exists(FW12) and sha_file(FW12) == FW12_SHA and verify([(0x400000, FW12)])[0]:
        return FW12
    if os.path.exists(FW13) and sha_file(FW13) == FW13_SHA and verify([(0x400000, FW13)])[0]:
        return FW13
    if os.path.exists(FWR2) and sha_file(FWR2) == FWR2_SHA and verify([(0x400000, FWR2)])[0]:
        return FWR2
    if os.path.exists(FW14) and sha_file(FW14) == FW14_SHA and verify([(0x400000, FW14)])[0]:
        return FW14
    return None


ORDER = [[(0xF000, piece('original', 0xF000))], [(0x8000, piece('original', 0x8000))],
         [(0x1000, piece('original', 0x1000)), (0x5000, piece('original', 0x5000))]]


def _rb_precheck():
    must(sha_file(BACKUP) == BK_SHA, 'backup fingerprint 77ad7105...')
    must(ic.check_manifest(PD) == [], 'saved original/planned sector hashes match the manifest')
    B = open(BACKUP, 'rb').read()
    must(all(open(piece('original', s), 'rb').read() == B[s:s + 0x1000] for s in ic.PLANNED), 'original pieces equal the backup sectors')
    rc, out = esptool(['flash_id'])
    must(rc == 0 and 'ESP32-PICO-V3-02' in out and 'Detected flash size: 8MB' in out, 'COM4 exclusive; ESP32-PICO-V3-02, 8 MB')
    ok, _ = verify([(s, piece('planned', s)) for s in ic.PLANNED])
    prog = app1_program()
    must(ok and prog is not None, 'current flash = installed state (planned sectors + approved Cyclift program %s), read-only verify' % (os.path.basename(prog) if prog else '?'))
    log('recovery order:', ' -> '.join('+'.join(hex(o) for o, _ in step) for step in ORDER), '(reverse of install; matches FIRST_INSTALL_PROCEDURE R-B)')


def _rb_restore():
    for step in ORDER:
        ok, out = write(step); must(ok, 'R-B write ' + ', '.join(hex(o) for o, _ in step))
        ok, out = verify(step); must(ok, 'R-B verify (read back) ' + ', '.join(hex(o) for o, _ in step))


def _rb_confirm():
    txt, boots, r = serial_watch(15, forbid=CYCLIFT)
    for l in [l for l in txt.splitlines() if l.strip()][:14]:
        log('   | ' + l[:150])
    must(r.confirmed, 'factory start confirmed: one start, no reset loop, Cyclift not running (%s)' % r.reason)
    fac_before = open(os.path.join(D, 'c3_nvs_fac.bin'), 'rb').read()
    first = read_region(0, 0x400000, 'after_recovery_b_first4MB.bin')
    pre = open(os.path.join(D, 'pre_install.bin'), 'rb').read()
    diff = [s for s in range(0, 0x400000, 0x1000) if first[s:s + 0x1000] != pre[s:s + 0x1000]]
    log('sectors differing from pre-install (first 4 MB):', [hex(s) for s in diff])
    must(all(0x9000 <= s < 0xE000 for s in diff), 'first 4 MB identical to pre-install except factory settings')
    ns = ic.nvs_namespaces_changed(pre, first)
    must(ns <= {'osw-config', '(page header)'}, 'factory settings: only the factory boot counter changed (%s)' % (sorted(ns) or 'none'))
    must(bct(first[0x9000:0xE000]) is not None and bct(first[0x9000:0xE000]) > bct(fac_before), 'factory app ran with its ORIGINAL settings (its boot counter advanced in 0x9000)')
    must(fp.selected_slot(first, 1) == 0 and fp.parse_pt(first[0x8000:0x8C00]) == fp.parse_pt(pre[0x8000:0x8C00]), 'factory partition table and factory selection restored')
    must(app1_program() is not None, 'Cyclift firmware left in upper flash (not erased)')


print('cy_recover_b loaded: phase("rb_precheck"), then phase("rb_restore"), then phase("rb_confirm")')
