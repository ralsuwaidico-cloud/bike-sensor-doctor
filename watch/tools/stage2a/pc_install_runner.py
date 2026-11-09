# Cyclift Stage 1 — first installation runner (owner-approved 9 Nov 2026 19:25, conditional; FIRST_INSTALL_PROCEDURE.md).
# One phase per call: phase('precheck'), phase('p1'), phase('p2'), phase('p3'), phase('p4'), phase('post'), phase('observe').
# Recovery only on explicit call: recovery('RA'|'RB'|'RC'). Every write: keep flags, then verify_flash. No erase, no eFuse.
# Revision 2 (9 Nov 2026, after the black-screen finding): all device access goes through device_session.DeviceSession.
# Every phase and every recovery ends with a restart into the firmware and a boot check; "flash verified" and
# "boot confirmed" are reported separately; serial monitoring without reset only runs once the firmware is confirmed running.
import os, sys, time, hashlib, datetime, struct
DOC = os.path.join(os.path.expanduser('~'), 'Documents')
T = os.environ.get('CY_TOOLS_DIR', os.path.join(DOC, 'Cyclift_Stage2a', 'tools'))
sys.path.insert(0, T); sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else T)
import fp_plan as fp, install_check as ic
import device_session as ds
D = os.environ.get('CY_PRIVATE_DIR') or os.path.join(os.environ.get('LOCALAPPDATA', os.path.expanduser('~')), 'Cyclift_Private', 'watch_backup_20261109')
PD = os.path.join(D, 'plan_pieces')
BACKUP = os.path.join(D, 'flash_8MB_read1.bin')
FW = os.path.join(DOC, 'Cyclift_Stage2a', 'stage1_firmware', 'cyclift-stage1-v3poc-T-Watch-2021-V1_1.bin')
FW_SHA = 'faa2828f8fd22d59877c4c9535eb09e1a15db3176f2b5cd1c438810aead5cba7'
BK_SHA = '77ad7105c68fb7de04e5717fca4e90b08bd9c32adeb5c098e3e00446d3767693'
PORT = 'COM4'
KEEP = ['--flash_mode', 'keep', '--flash_freq', 'keep', '--flash_size', 'keep']
LOG = os.path.join(D, 'install_log.txt')
piece = lambda tag, s: os.path.join(PD, '%s_0x%06x.bin' % (tag, s))


def log(*a):   # encoding-safe (serial output may contain non-ASCII bytes)
    s = '%s %s' % (datetime.datetime.now().strftime('%H:%M:%S'), ' '.join(str(x) for x in a))
    print(s.encode('ascii', 'replace').decode())
    with open(LOG, 'a', encoding='utf-8', errors='replace') as f:
        f.write(s + '\n')


class Stop(Exception):
    pass


S = ds.DeviceSession(ds.RealTransport(PORT), log=lambda m: log(m))
CYCLIFT = 'Cyclift v3 proof of concept'      # Stage 1 boot banner on serial


def esptool(args, **_ignored):
    """Every esptool command leaves the chip in download mode; the phase wrapper restarts it afterwards."""
    return S.esptool(args)


def must(ok, msg):
    log(('PASS ' if ok else 'FAIL ') + msg)
    if not ok:
        raise Stop(msg)


def sha_file(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


def verify(pairs):
    return S.verify(pairs), ''


def write(pairs):
    return S.write(pairs), ''


def serial_watch(seconds=12, send=None, expect=None, forbid=None):
    """Restart the watch into its normal program (EN pulse, IO0 high) and confirm the boot. Read-only.
    Returns (text, starts, BootResult). `send` is written half-way through an extra listen window (no reset)."""
    r = S.restart_and_confirm(expect=expect, forbid=forbid, window=min(seconds, 15))
    txt = r.text
    if 'rst:0x5 ' in txt:
        log('note: %d deep-sleep wake-up(s) seen (normal power saving, not counted)' % txt.count('rst:0x5 '))
    if r.confirmed and seconds > 15:
        txt += S.listen(seconds - 15, send=send)
    return txt, r.starts, r


def read_region(off, size, name):
    f = os.path.join(D, name)
    try:
        return S.read(off, size, f)
    except ds.CommError as e:
        raise Stop('read failed at 0x%x (%s)' % (off, e))


def nvs_has_namespace(blob, name):
    for off in range(0, len(blob), 0x1000):
        for i in range(126):
            st = (blob[off + 32 + i // 4] >> ((i % 4) * 2)) & 3
            e = blob[off + 64 + i * 32: off + 96 + i * 32]
            if st == 2 and e[0] == 0 and e[1] == 1 and e[8:24].split(b'\0')[0] == name.encode():
                return True
    return False


def bct(blob):
    """Factory boot counter (osw-config/bct) from an NVS area; value used only to prove the factory app ran."""
    ns = None
    for off in range(0, len(blob), 0x1000):
        for i in range(126):
            st = (blob[off + 32 + i // 4] >> ((i % 4) * 2)) & 3
            e = blob[off + 64 + i * 32: off + 96 + i * 32]
            if st == 2 and e[0] == 0 and e[1] == 1 and e[8:24].split(b'\0')[0] == b'osw-config':
                ns = e[24]
    val = None
    for off in range(0, len(blob), 0x1000):
        for i in range(126):
            st = (blob[off + 32 + i // 4] >> ((i % 4) * 2)) & 3
            e = blob[off + 64 + i * 32: off + 96 + i * 32]
            if st == 2 and ns is not None and e[0] == ns and e[8:24].split(b'\0')[0] == b'bct':
                val = struct.unpack('<i', e[24:28])[0]
    return val


# Firmware expected after each phase's final restart (None = any firmware; only start/no-loop checked).
AFTER = {'precheck': (None, CYCLIFT), 'p1': (None, CYCLIFT), 'p2': (None, CYCLIFT), 'p3': (None, CYCLIFT),
         'p4': (CYCLIFT, None), 'post': (CYCLIFT, None), 'observe': (CYCLIFT, None)}


def phase(name):
    """Run one phase; ALWAYS ends with a restart attempt and a boot check. True only if the work passed AND the
    firmware start was confirmed. Unexpected errors are re-raised after the cleanup has been logged."""
    expect, forbid = AFTER.get(name, (None, None))
    r = ds.run_phase(S, name, globals()['_' + name], expect=expect, forbid=forbid, stop_exc=(Stop,))
    return r.ok


def _precheck():
    rc, out = esptool(['flash_id'], after='hard_reset')
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
    diff = [s for s in range(0, 0x800000, 0x1000) if pre[s:s + 0x1000] != B[s:s + 0x1000]]
    must(all(0x9000 <= s < 0xE000 for s in diff), 'watch identical to the backup except factory settings sectors (%d differ)' % len(diff))
    ns = ic.nvs_namespaces_changed(B, pre)
    must(ns <= {'osw-config'}, 'factory settings changes limited to osw-config (%s)' % (sorted(ns) or 'none'))
    pieces = ic.load_pieces(PD)
    must(all(pieces[('original', s)] == pre[s:s + 0x1000] for s in ic.PLANNED), 'original pieces equal the watch\'s current sectors 0x1000/0x5000/0x8000/0xF000')
    must(pre[0x400000:0x800000] == b'\xff' * 0x400000, 'upper 4 MB still fully erased')
    sim = bytearray(pre)
    for s in ic.PLANNED:
        sim[s:s + 0x1000] = pieces[('planned', s)]
    sim[0x400000:0x400000 + len(fwb)] = fwb
    rep, bad = ic.verify_after(pre, bytes(sim), fwb, pieces)
    must(not bad, 'expected end state (offline) changes only the approved ranges: %s' % bad)
    secs = fp.changed_sectors(pre, bytes(sim))
    log('approved changed ranges:', ', '.join('0x%06x-0x%06x' % r for r in fp.ranges(secs)))
    for nm, lo, hi in (('factory app', 0x10000, 0x210000), ('factory files', 0x210000, 0x400000), ('factory settings', 0x9000, 0xE000)):
        must(sim[lo:hi] == pre[lo:hi], '%s not written by the plan' % nm)
    must(fp.selected_slot(bytes(sim), 2) == 1 and fp.check_layout(bytes(sim[0x8000:0x8C00])) == [], 'end state selects app1; partition table valid')
    for f in [piece('original', s) for s in ic.PLANNED] + [BACKUP, os.path.join(D, 'RECOVERY_AND_INSTALL_COMMANDS_NOT_RUN.txt')]:
        must(os.path.exists(f), 'recovery file present: ' + os.path.basename(f))
    res, bad = ic.recovery_validate(B, fwb, pieces)
    must(not bad, 'recovery package validated offline with the approved firmware')
    txt, boots, r = serial_watch(10, forbid=CYCLIFT)
    must(r.confirmed, 'baseline: factory firmware start confirmed, no reset loop (%s)' % r.reason)


def _checkpoint(expect_factory, label):
    txt, boots, r = serial_watch(12, forbid=CYCLIFT if expect_factory else None)
    log('%s: serial shows %d start(s); Cyclift banner present: %s' % (label, boots, CYCLIFT in txt))
    must(r.confirmed, '%s: firmware start confirmed (%s)' % (label, r.reason))


def _p1():
    must(sha_file(FW) == FW_SHA, 'firmware fingerprint re-checked')
    pre = open(os.path.join(D, 'pre_install.bin'), 'rb').read()
    before = bct(pre[0x9000:0xE000])
    ok, out = write([(0x400000, FW)]); must(ok, 'Phase 1 write firmware -> 0x400000')
    ok, out = verify([(0x400000, FW)]); must(ok, 'Phase 1 verify_flash 0x400000')
    _checkpoint(True, 'C1')
    nv = read_region(0x9000, 0x5000, 'c1_nvs.bin')
    after = bct(nv)
    must(after is not None and before is not None and after > before, 'C1: factory app ran with its own settings (boot counter advanced)')


def _p2():
    ok, _ = verify([(0x400000, FW)]); must(ok, 'pre-condition: Phase 1 still in place')
    pr = [(0x1000, piece('planned', 0x1000)), (0x5000, piece('planned', 0x5000))]
    ok, out = write(pr); must(ok, 'Phase 2 write bootloader sectors 0x1000, 0x5000 (size field 8 MB, code unchanged)')
    ok, out = verify(pr); must(ok, 'Phase 2 verify_flash 0x1000, 0x5000')
    before = bct(open(os.path.join(D, 'c1_nvs.bin'), 'rb').read())
    _checkpoint(True, 'C2')
    after = bct(read_region(0x9000, 0x5000, 'c2_nvs.bin'))
    must(after is not None and after > before, 'C2: factory app ran with its own settings (boot counter advanced)')


def _p3():
    ok, _ = verify([(0x400000, FW), (0x1000, piece('planned', 0x1000)), (0x5000, piece('planned', 0x5000))]); must(ok, 'pre-condition: Phases 1-2 in place')
    pr = [(0x8000, piece('planned', 0x8000))]
    ok, out = write(pr); must(ok, 'Phase 3 write partition table 0x8000')
    ok, out = verify(pr); must(ok, 'Phase 3 verify_flash 0x8000')
    fac_before = open(os.path.join(D, 'c2_nvs.bin'), 'rb').read()
    _checkpoint(True, 'C3')
    cyc = read_region(0x700000, 0x6000, 'c3_cyclift_nvs.bin')
    must(nvs_has_namespace(cyc, 'osw-config'), 'C3: factory app ran under the new table (its settings now in the Cyclift area)')
    fac_after = read_region(0x9000, 0x5000, 'c3_nvs_fac.bin')
    must(fac_after == fac_before, 'C3: original factory settings (nvs_fac) unchanged')


def _p4():
    ok, _ = verify([(0x400000, FW), (0x1000, piece('planned', 0x1000)), (0x5000, piece('planned', 0x5000)), (0x8000, piece('planned', 0x8000))])
    must(ok, 'pre-condition: Phases 1-3 in place')
    pr = [(0xF000, piece('planned', 0xF000))]
    ok, out = write(pr); must(ok, 'Phase 4 write OTA record 0xF000 (the switch)')
    ok, out = verify(pr); must(ok, 'Phase 4 verify_flash 0xF000')
    txt, boots, r = serial_watch(15, expect=CYCLIFT)
    log('C4 serial (first lines):')
    for l in [l for l in txt.splitlines() if l.strip()][:14]:
        log('   | ' + l[:150])
    must(r.confirmed, 'C4: Cyclift Stage 1 start confirmed — one start, banner on serial (%s)' % r.reason)


def _observe():
    """Read-only: 60 s serial observation with a performance report; counts resets; records key/touch log lines."""
    txt, boots, r = serial_watch(60, send='u', expect=CYCLIFT)
    must(r.confirmed, 'Cyclift start confirmed before observing (%s)' % r.reason)
    lines = [l for l in txt.splitlines() if l.strip()]
    for l in lines[:40]:
        log('   | ' + l[:160])
    starts = txt.count('rst:0x') - txt.count('rst:0x5 ')
    log('observe: starts=%d (1 expected), perf line present=%s' % (starts, any(l.startswith('perf:') for l in lines)))
    must(starts == 1, 'no unexpected reset during 60 s')


def _post():
    after = read_region(0, 0x800000, 'post_install.bin')
    pre = open(os.path.join(D, 'pre_install.bin'), 'rb').read()
    fwb = open(FW, 'rb').read()
    rep, bad = ic.verify_after(pre, after, fwb, ic.load_pieces(PD))
    for r in rep: log('  ' + r)
    for b in bad: log('  PROBLEM ' + b)
    secs = fp.changed_sectors(pre, after)
    log('changed ranges vs pre-install:', ', '.join('0x%06x-0x%06x' % r for r in fp.ranges(secs)))
    must(not bad, 'post-install flash matches the approved changed-range map')


def recovery(level):
    """Reviewed recovery only (FIRST_INSTALL_PROCEDURE.md). Not run unless explicitly called.
    Ends with a restart and a boot check like every phase."""
    seq = {'RA': [[(0xF000, piece('original', 0xF000))]],
           'RB': [[(0xF000, piece('original', 0xF000))], [(0x8000, piece('original', 0x8000))],
                  [(0x1000, piece('original', 0x1000)), (0x5000, piece('original', 0x5000))]],
           'RC': [[(0x0, BACKUP)]]}[level]

    def _work():
        for pr in seq:
            ok, out = write(pr); must(ok, 'recovery write ' + ', '.join(hex(o) for o, _ in pr))
            ok, out = verify(pr); must(ok, 'recovery verify ' + ', '.join(hex(o) for o, _ in pr))
    r = ds.run_phase(S, 'RECOVERY ' + level, _work, forbid=CYCLIFT, stop_exc=(Stop,))
    return r.ok


print('cy_install loaded. Run phase("precheck") first.')
