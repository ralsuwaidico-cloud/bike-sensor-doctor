# Cyclift — Recovery Level B (owner-approved 9 Nov 2026 19:52). Reviewed procedure only:
# original sectors written back in reverse install order: 0xF000, 0x8000, then 0x1000 + 0x5000; keep flags; verify each.
# Cyclift firmware in the upper flash is left in place (not erased). No other writes.
import os, sys
for m in ('fp_plan', 'install_check', 'check_image_header'):
    sys.modules.pop(m, None)
exec(open(os.path.join(os.path.expanduser('~'), 'Documents', 'Cyclift_Stage2a', 'tools', 'cy_install.py'), encoding='utf-8').read())


def log(*a):   # encoding-safe logger (fix from the installation session)
    s = '%s %s' % (datetime.datetime.now().strftime('%H:%M:%S'), ' '.join(str(x) for x in a))
    print(s.encode('ascii', 'replace').decode()); open(LOG, 'a', encoding='utf-8', errors='replace').write(s + '\n')


ORDER = [[(0xF000, piece('original', 0xF000))], [(0x8000, piece('original', 0x8000))],
         [(0x1000, piece('original', 0x1000)), (0x5000, piece('original', 0x5000))]]


def _rb_precheck():
    must(sha_file(BACKUP) == BK_SHA, 'backup fingerprint 77ad7105...')
    must(ic.check_manifest(PD) == [], 'saved original/planned sector hashes match the manifest')
    B = open(BACKUP, 'rb').read()
    must(all(open(piece('original', s), 'rb').read() == B[s:s + 0x1000] for s in ic.PLANNED), 'original pieces equal the backup sectors')
    rc, out = esptool(['flash_id'])
    must(rc == 0 and 'ESP32-PICO-V3-02' in out and 'Detected flash size: 8MB' in out, 'COM4 exclusive; ESP32-PICO-V3-02, 8 MB')
    ok, _ = verify([(0x400000, FW)] + [(s, piece('planned', s)) for s in ic.PLANNED])
    must(ok, 'current flash = installed state (planned sectors + Cyclift firmware), read-only verify')
    log('recovery order:', ' -> '.join('+'.join(hex(o) for o, _ in step) for step in ORDER), '(reverse of install; matches FIRST_INSTALL_PROCEDURE R-B)')


def _rb_restore():
    for step in ORDER:
        ok, out = write(step); must(ok, 'R-B write ' + ', '.join(hex(o) for o, _ in step))
        ok, out = verify(step); must(ok, 'R-B verify (read back) ' + ', '.join(hex(o) for o, _ in step))


def _rb_confirm():
    txt, boots = serial_watch(15)
    for l in [l for l in txt.splitlines() if l.strip()][:14]:
        log('   | ' + l[:150])
    must(boots == 1, 'factory start: exactly one start, no reset loop')
    must('Cyclift v3' not in txt, 'Cyclift not running')
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
    ok, _ = verify([(0x400000, FW)]); must(ok, 'Cyclift firmware left in upper flash (not erased)')


print('cy_recover_b loaded: phase("rb_precheck"), then phase("rb_restore"), then phase("rb_confirm")')
