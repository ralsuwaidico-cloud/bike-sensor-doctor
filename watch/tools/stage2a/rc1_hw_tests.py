# Cyclift Stage 1.3 RC1 — automated hardware diagnostics (owner-approved 11 Nov 2026 15:41). PC name: rc1_tests.py.
# SERIAL ONLY: never runs esptool, never reads or writes flash, never requests download mode. COM4 is opened with DTR/RTS
# released (no reset). The only state it changes is RAM (screens, demo data, language) and the clock chip time ('T', approved
# as time setting). Restarts use device_session.restart_and_confirm (EN pulse, IO0 high), as in B2/C2.
# Results: Documents\Cyclift_Stage2a\rc1_results\rc1_log.txt (serial text only; lines that could carry a hardware identifier
# are dropped).
import os, sys, time, datetime, re
T = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.path.join(os.path.expanduser('~'), 'Documents', 'Cyclift_Stage2a', 'tools')
sys.path.insert(0, T)
sys.modules.pop('device_session', None)
import device_session as ds
OUT = os.path.join(os.path.expanduser('~'), 'Documents', 'Cyclift_Stage2a', 'rc1_results')
os.makedirs(OUT, exist_ok=True)
LOG = os.path.join(OUT, 'rc1_log.txt')
TR = ds.RealTransport('COM4')
BANNER = 'Stage 1.3 RC1'
_PRIVATE = re.compile(r'MAC|mac:|[0-9a-f]{2}(:[0-9a-f]{2}){5}', re.I)


def log(*a):
    s = '%s %s' % (datetime.datetime.now().strftime('%H:%M:%S'), ' '.join(str(x) for x in a))
    if _PRIVATE.search(s):
        s = s[:9] + '[line withheld: possible hardware identifier]'
    print(s.encode('ascii', 'replace').decode())
    with open(LOG, 'a', encoding='utf-8', errors='replace') as f:
        f.write(s + '\n')


def _starts(txt):
    return txt.count('rst:0x') - txt.count('rst:0x5 ')


RESTARTS = [0]


def session(seconds, send=(), gap=1.5, label=''):
    """Open COM4 WITHOUT reset, send each item (gap seconds apart), listen `seconds`; log every line."""
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
        log('   | ' + l[:200])
    st = _starts(txt); RESTARTS[0] += st
    log('%s: %d s, %d bytes, %d unexpected restart(s)%s' % (label or 'session', seconds, len(buf), st, '' if not st else '  <<< UNEXPECTED RESTART'))
    return txt, st


def local_seconds(now=None):
    d = datetime.datetime.fromtimestamp(now if now is not None else time.time()).astimezone()
    return int(d.timestamp()) + int(d.utcoffset().total_seconds())


def _clock(txt):
    m = re.findall(r'(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d) local', txt)
    if not m:
        return None
    y, mo, d, h, mi, s = map(int, m[-1])
    return int((datetime.datetime(y, mo, d, h, mi, s) - datetime.datetime(1970, 1, 1)).total_seconds())


def alive():
    txt, st = session(4, send=['u'], gap=0.5, label='alive')
    return 'perf:' in txt and st == 0


def restart():
    S = ds.DeviceSession(TR, log=lambda m: log(m), boot_window=12)
    S.state = 'unknown'
    r = S.restart_and_confirm(expect=BANNER)
    for l in [l for l in r.text.splitlines() if 'Cyclift' in l][:2]:
        log('   | ' + l[:200])
    log('RESTART: %s (%s)' % ('confirmed' if r.confirmed else 'NOT CONFIRMED', r.reason))
    return r.confirmed


def auto(soak_minutes=30):
    """All serial-only checks, ~45 min. Safe to stop with Ctrl+C (the watch keeps running)."""
    log('=' * 20, 'RC1 automated diagnostics start', '=' * 20)
    R = {}
    R['alive'] = alive()
    if not R['alive']:
        log('STOP: the watch did not answer'); return R
    # A. start state, memory at the face
    session(6, send=['f', 'z', '?', 'M', 'u'], gap=1.0, label='A face: help, memory, perf')
    # B. clock: read, set from the PC clock, read back, then 70 s later (the chip must count)
    txt, _ = session(3, send=['R'], gap=0.5, label='B1 clock before setting')
    R['clock_before'] = 'no valid time' if 'no valid time' in txt else ('valid' if _clock(txt) else 'unknown')
    t = local_seconds()
    txt, _ = session(5, send=['T%d\n' % t, 'R'], gap=1.0, label='B2 set clock from the PC')
    c1 = _clock(txt); R['clock_set_error_s'] = None if c1 is None else c1 - local_seconds()
    time.sleep(70)
    txt, _ = session(3, send=['R'], gap=0.5, label='B3 clock after 70 s')
    c2 = _clock(txt); R['clock_run_error_s'] = None if (c1 is None or c2 is None) else (c2 - local_seconds())
    log('CLOCK: before=%s, set error %s s, after 70 s error %s s' % (R['clock_before'], R['clock_set_error_s'], R['clock_run_error_s']))
    # C. screen transitions the serial hooks can drive (each one is a full rebuild), English then Arabic
    seq = ['m', 'b'] * 4 + ['E', 'E', 'd', 'd', 't', 't', 'k', 'k']
    session(len(seq) * 2 + 6, send=['z'] + seq + ['h', 'u'], gap=2.0, label='C1 transitions EN')
    session(len(seq) * 2 + 8, send=['l', 'z'] + seq + ['h', 'u', 'l'], gap=2.0, label='C2 transitions AR')
    # D. ride EN 90 s, pause / resume, then ride AR 90 s
    session(100, send=['E', 'z', 'r'], gap=1.0, label='D1 ride EN (demo data on, simulated ride)')
    session(12, send=['p', 'p', 'h', 'u'], gap=2.0, label='D2 pause/resume + ride EN report')
    session(100, send=['l', 'z'], gap=1.0, label='D3 ride AR')
    session(8, send=['h', 'u', 'M', 'l'], gap=1.5, label='D4 ride AR report + memory')
    # E. soak: ride running, report every 5 min
    for i in range(max(1, soak_minutes // 5)):
        session(300, send=['u', 'M'] if i else ['z', 'u', 'M'], gap=2.0, label='E soak %d-%d min' % (5 * i, 5 * i + 5))
    session(8, send=['h', 'u', 'M'], gap=2.0, label='E soak end report')
    # F. two normal restarts
    R['restarts_confirmed'] = [restart(), restart()]
    session(8, send=['M', 'R'], gap=2.0, label='F after restarts: memory, clock')
    R['unexpected_restarts'] = RESTARTS[0]
    log('RESULT', R)
    log('=' * 20, 'RC1 automated diagnostics end', '=' * 20)
    return R


print('RC1 diagnostics loaded (serial only). auto() ~45 min · alive() · session(sec, send, gap, label) · restart()')
