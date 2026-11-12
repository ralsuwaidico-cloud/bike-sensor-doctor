# Cyclift RC1 — continuous serial monitor for the restart investigation (owner-approved 11 Nov 2026 20:51).
# PC name: rc1_monitor.py. Runs as its OWN background process (started from IDLE with start_monitor()), so it keeps
# recording when IDLE loses focus or another command runs. READ-ONLY: opens COM4 with DTR/RTS released (no reset),
# never runs esptool, never touches flash. The only bytes it sends are the existing read-only report commands
# 'u' (perf + heap, every 30 s) and 'M' (memory + stacks, every 5 min).
# Output (Documents\Cyclift_Stage2a\rc1_results): monitor_<time>.txt (every line, timestamped) and monitor_status.txt
# (heartbeat every 2 s: alive, bytes received, boots seen, last reset reason, last heap). Stops when the file STOP
# exists in that folder, or after the time limit (default 240 minutes).
import os, sys, time, datetime, re, json, subprocess
OUT = os.path.join(os.path.expanduser('~'), 'Documents', 'Cyclift_Stage2a', 'rc1_results')
TOOLS = os.path.join(os.path.expanduser('~'), 'Documents', 'Cyclift_Stage2a', 'tools')
STOP = os.path.join(OUT, 'STOP')
STATUS = os.path.join(OUT, 'monitor_status.txt')
_PRIVATE = re.compile(r'MAC|mac:|[0-9a-f]{2}(:[0-9a-f]{2}){5}', re.I)
EVENTS = re.compile(r'rst:0x|Brownout|brownout|Guru Meditation|Backtrace|abort\(\)|panic|watchdog|wdt|Stack canary|'
                    r'LoadProhibited|StoreProhibited|IllegalInstruction|assert|Cyclift v3|key1|key2|lap|ride|swipe|tap', re.I)
MAX_MIN = 240


def now():
    return datetime.datetime.now().strftime('%H:%M:%S.%f')[:-3]


def run(minutes=MAX_MIN):
    os.makedirs(OUT, exist_ok=True)
    if os.path.exists(STOP):
        os.remove(STOP)
    sys.path.insert(0, TOOLS)
    import device_session as ds
    tr = ds.RealTransport('COM4')
    path = os.path.join(OUT, 'monitor_%s.txt' % datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
    f = open(path, 'a', encoding='utf-8', errors='replace')
    st = {'file': os.path.basename(path), 'started': now(), 'limit_min': minutes, 'alive': True, 'bytes': 0, 'lines': 0, 'boots': 0,
          'reset_lines': [], 'events': [], 'last_rx': None, 'last_heap': None, 'port_errors': 0, 'state': 'opening'}

    def w(line):
        if _PRIVATE.search(line):
            line = '[line withheld: possible hardware identifier]'
        f.write('%s %s\n' % (now(), line)); f.flush()

    def status():
        st['heartbeat'] = now()
        with open(STATUS + '.tmp', 'w', encoding='utf-8') as g:
            json.dump(st, g, indent=1)
        os.replace(STATUS + '.tmp', STATUS)

    w('=== monitor start (read-only; DTR/RTS released; sends only u every 30 s and M every 5 min) ===')
    t0 = time.time(); s = None; buf = b''; next_u = t0 + 3; next_m = t0 + 10; next_st = 0
    while not os.path.exists(STOP) and time.time() - t0 < minutes * 60:
        try:
            if s is None:
                s = tr.open_serial(); s.dtr = False; s.rts = False
                st['state'] = 'recording'; w('--- COM4 open ---')
            chunk = s.read(4096)
            if chunk:
                st['bytes'] += len(chunk); st['last_rx'] = now(); buf += chunk
                while b'\n' in buf:
                    raw, buf = buf.split(b'\n', 1)
                    line = raw.decode('utf-8', 'replace').rstrip('\r')
                    if not line.strip():
                        continue
                    st['lines'] += 1; w(line)
                    if 'rst:0x' in line:
                        st['reset_lines'].append(now() + ' ' + line.strip()[:120])
                    if 'Cyclift v3 proof of concept' in line:
                        st['boots'] += 1
                    m = re.search(r'heap free (\d+), min (\d+)', line)
                    if m:
                        st['last_heap'] = [int(m.group(1)), int(m.group(2))]
                    if EVENTS.search(line) and not line.startswith('perf:'):
                        st['events'] = (st['events'] + [now() + ' ' + line.strip()[:120]])[-40:]
            t = time.time()
            if t >= next_u:
                s.write(b'u'); next_u = t + 30
            if t >= next_m:
                s.write(b'M'); next_m = t + 300
        except Exception as e:      # USB re-enumeration or a busy port: record it, close, retry every 2 s
            st['port_errors'] += 1; st['state'] = 'port error, retrying'; w('--- port error: %s ---' % str(e)[:160])
            try:
                if s:
                    s.close()
            except Exception:
                pass
            s = None; time.sleep(2)
        if time.time() >= next_st:
            status(); next_st = time.time() + 2
    w('=== monitor stop (%s) ===' % ('STOP file' if os.path.exists(STOP) else 'time limit'))
    try:
        if s:
            s.close()
    except Exception:
        pass
    st['alive'] = False; st['state'] = 'stopped'; status(); f.close()


def start_monitor(minutes=MAX_MIN):
    """From IDLE: starts this file as a separate background process and returns at once."""
    os.makedirs(OUT, exist_ok=True)
    exe = sys.executable
    flags = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
    p = subprocess.Popen([exe, os.path.join(TOOLS, 'rc1_monitor.py'), 'run', str(int(minutes))], creationflags=flags,
                         stdout=subprocess.DEVNULL, stderr=open(os.path.join(OUT, 'monitor_errors.txt'), 'a'))
    print('monitor started, process', p.pid, '- status file:', STATUS)
    return p


def stop_monitor():
    open(STOP, 'w').close(); print('stop requested')


if __name__ == '__main__' and len(sys.argv) > 1 and sys.argv[1] == 'run':
    run(int(sys.argv[2]) if len(sys.argv) > 2 else MAX_MIN)
