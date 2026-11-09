# Cyclift Stage 2a — A1 factory-firmware validation (owner-approved 9 Nov 2026, A1 only).
# READ-ONLY: esptool flash_id and read_flash only; restarts are normal EN resets (IO0 high). No write, erase, eFuse or
# partition command exists in this file. Every step ends with a restart + boot check through device_session.run_phase.
import os, sys, datetime
T = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.path.join(os.path.expanduser('~'), 'Documents', 'Cyclift_Stage2a', 'tools')
sys.path.insert(0, T)
for m in ('device_session', 'fp_plan'):
    sys.modules.pop(m, None)
import device_session as ds, fp_plan as fp
D = os.path.join(os.environ['LOCALAPPDATA'], 'Cyclift_Private', 'watch_backup_20261109')
LOG = os.path.join(D, 'a1_log.txt')
CYCLIFT = 'Cyclift v3 proof of concept'
READ_ONLY = {'flash_id', 'read_flash'}


def log(*a):
    s = '%s %s' % (datetime.datetime.now().strftime('%H:%M:%S'), ' '.join(str(x) for x in a))
    print(s.encode('ascii', 'replace').decode())
    with open(LOG, 'a', encoding='utf-8', errors='replace') as f:
        f.write(s + '\n')


class ReadOnlyTransport(ds.RealTransport):
    def esptool(self, args, timeout=900):
        if args[0] not in READ_ONLY:
            raise RuntimeError('refused: %s is not read-only' % args[0])
        return ds.RealTransport.esptool(self, args, timeout)


class Stop(Exception):
    pass


def must(ok, msg):
    log(('PASS ' if ok else 'FAIL ') + msg)
    if not ok:
        raise Stop(msg)


def session():
    return ds.DeviceSession(ReadOnlyTransport('COM4'), log=lambda m: log(m), boot_window=12)


def a1_identify():
    """Read-only: chip check, factory partition table and factory app selection; then restart + boot check."""
    S = session()

    def work():
        rc, out = S.esptool(['flash_id'])
        must(rc == 0 and 'ESP32-PICO-V3-02' in out and 'Detected flash size: 8MB' in out, 'chip ESP32-PICO-V3-02, 8 MB (read-only)')
        pt = S.read(0x8000, 0xC00, os.path.join(D, 'a1_pt.bin'))
        ota = S.read(0xE000, 0x2000, os.path.join(D, 'a1_ota.bin'))
        pre = open(os.path.join(D, 'pre_install.bin'), 'rb').read()
        must(fp.parse_pt(pt) == fp.parse_pt(pre[0x8000:0x8C00]), 'partition table = factory table (as before the install)')
        img = bytearray(0x10000); img[0x8000:0x8C00] = pt; img[0xE000:0x10000] = ota
        must(fp.selected_slot(bytes(img), 1) == 0, 'OTA record selects the factory app (app0)')
    r = ds.run_phase(S, 'A1-identify', work, forbid=CYCLIFT, stop_exc=(Stop,))
    return r.ok


def a1_restart(n=3):
    """Normal restarts only; each must give exactly one flash boot of the factory firmware."""
    res = []
    for i in range(n):
        S = session()
        b = S.restart_and_confirm(forbid=CYCLIFT)
        res.append(b.confirmed)
        log('restart %d/%d: %s' % (i + 1, n, 'BOOT CONFIRMED' if b.confirmed else 'BOOT NOT CONFIRMED - ' + b.reason))
        if not b.confirmed:
            log('STOP: reconnect USB and report what the screen shows')
            break
    return res


def a1_listen(seconds=60):
    """Restart, confirm, then listen without reset; reports any further restart."""
    S = session()
    b = S.restart_and_confirm(forbid=CYCLIFT)
    if not b.confirmed:
        log('STOP: boot not confirmed - ' + b.reason); return False
    txt = S.listen(seconds)
    extra = txt.count('rst:0x') - txt.count('rst:0x5 ')
    log('listen %d s after confirmed boot: %d bytes, %d unexpected restart(s)' % (seconds, len(txt), extra))
    return extra == 0


def a1_banner():
    """Show the boot text of one restart (for the log)."""
    S = session()
    b = S.restart_and_confirm(forbid=CYCLIFT)
    for l in [l for l in b.text.splitlines() if l.strip()][:12]:
        log('   | ' + l[:150])
    return b.confirmed


print('A1 tests loaded (read-only). Functions: a1_identify(), a1_restart(3), a1_banner(), a1_listen(60)')
