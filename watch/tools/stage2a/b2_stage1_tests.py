# Cyclift Stage 1 — B2 hands-on validation helper (owner-approved 9 Nov 2026 21:53, B2 only). PC name: b2_tests.py.
# SERIAL ONLY: this file never runs esptool, never reads or writes flash and never requests download mode.
# Restarts are normal EN resets with IO0 high (device_session.restart_and_confirm). Listening opens COM4 with DTR/RTS released.
# Serial test hooks of Stage 1 (single characters): m Key1 · b Key2 · f face · r ride · p pause/resume · d density · t text size
# · l language · s sensors · u performance report.
import os, sys, time, datetime
T = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.path.join(os.path.expanduser('~'), 'Documents', 'Cyclift_Stage2a', 'tools')
sys.path.insert(0, T)
sys.modules.pop('device_session', None)
import device_session as ds
D = os.path.join(os.environ['LOCALAPPDATA'], 'Cyclift_Private', 'watch_backup_20261109')
LOG = os.path.join(D, 'b2_log.txt')
CYCLIFT = 'Cyclift v3 proof of concept'
TR = ds.RealTransport('COM4')


def log(*a):
    s = '%s %s' % (datetime.datetime.now().strftime('%H:%M:%S'), ' '.join(str(x) for x in a))
    print(s.encode('ascii', 'replace').decode())
    with open(LOG, 'a', encoding='utf-8', errors='replace') as f:
        f.write(s + '\n')


def _starts(txt):
    return txt.count('rst:0x') - txt.count('rst:0x5 ')


def b2_session(seconds, send='', gap=1.5, label=''):
    """Open COM4 WITHOUT reset, optionally send hook characters (gap seconds apart), listen `seconds`; log every line.
    Returns (text, unexpected_starts)."""
    s = TR.open_serial()
    buf = b''
    try:
        s.dtr = False; s.rts = False
        t0 = time.time(); i = 0; nxt = t0 + 1.0
        while time.time() - t0 < seconds:
            if i < len(send) and time.time() >= nxt:
                s.write(send[i].encode()); log('  >> sent %r' % send[i]); i += 1; nxt = time.time() + gap
            buf += s.read(4096)
    finally:
        s.close()
    txt = buf.decode('utf-8', 'replace')
    for l in [l for l in txt.splitlines() if l.strip()]:
        log('   | ' + l[:170])
    st = _starts(txt)
    log('%s: %d s listened, %d bytes, %d unexpected restart(s)%s' % (label or 'session', seconds, len(buf), st, '' if not st else '  <<< STOP'))
    return txt, st


def b2_alive():
    """Firmware running? Sends 'u' (performance report) without any reset and waits for the reply."""
    txt, st = b2_session(4, send='u', gap=0.5, label='alive check')
    ok = 'perf:' in txt and st == 0
    log('ALIVE: %s' % ('YES - Cyclift answered without reset' if ok else 'NO ANSWER - stop'))
    return ok


def b2_restart():
    """Normal restart (EN pulse, IO0 high) + boot confirmation of Cyclift."""
    S = ds.DeviceSession(TR, log=lambda m: log(m), boot_window=12)
    S.state = 'unknown'
    r = S.restart_and_confirm(expect=CYCLIFT)
    for l in [l for l in r.text.splitlines() if 'Cyclift' in l or 'rst:' in l][:4]:
        log('   | ' + l[:170])
    if not r.confirmed:
        log('STOP: Cyclift start NOT confirmed - ' + r.reason)
    return r.confirmed


print('B2 helper loaded (serial only, no esptool). b2_alive(), b2_session(sec, send, gap, label), b2_restart()')
