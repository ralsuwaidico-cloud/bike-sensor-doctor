#!/usr/bin/env python3
"""Tests for stage2a_readonly.py on a computer, with no watch attached.
- the guard refuses every write, erase or eFuse-burning operation;
- a simulated watch (fake esptool runner over a synthetic flash image) goes through identify and backup;
- the backup refuses a flash size that the watch did not report, and refuses when the two reads differ;
- the firmware description parser agrees with esptool's own `image_info` on a synthetic app image;
- the eFuse parser reads the real output format of `espefuse --virt summary` (virtual chip, no hardware)."""
import argparse, hashlib, os, re, struct, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stage2a_readonly as s2

checks = fails = 0
def check(cond, what):
    global checks, fails
    checks += 1
    if not cond: fails += 1; print('FAIL', what)

CSV = os.path.join(os.path.dirname(__file__), '../../firmware/boards/partitions_8mb_ota.csv')

def encode_partition_table(rows):
    t = {'app': 0, 'data': 1}; sub = {**{v: k for k, v in s2.APP_SUB.items()}, **{v: k for k, v in s2.DATA_SUB.items()}}
    out = b''
    for name, ty, st, off, size in rows:
        out += struct.pack('<HBBII16sI', 0xAA50, t[ty], sub[st], off, size, name.encode(), 0)
    out += b'\xeb\xeb' + b'\xff' * 14 + hashlib.md5(out).digest()
    return out + b'\xff' * (s2.PT_SIZE - len(out))

def csv_rows():
    rows = []
    for line in open(CSV):
        line = line.split('#')[0].strip()
        if not line: continue
        f = [x.strip() for x in line.split(',')]
        rows.append((f[0], f[1], {'spiffs': 'spiffs'}.get(f[2], f[2]), int(f[3], 16), int(f[4], 16)))
    return rows

def app_image(project=b'cyclift-factory', version=b'1.2.3', date=b'Nov  9 2026', time_=b'10:09:00', idf=b'v4.4.7'):
    desc = struct.pack('<IIII32s32s16s16s32s32s80s', 0xABCD5432, 0, 0, 0, version, project, time_, date, idf, b'\0' * 32, b'\0' * 80)
    desc = desc[:256]
    hdr = struct.pack('<BBBBI', 0xE9, 1, 2, 0x20, 0x400D0018) + bytes([0xEE, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF]) + b'\0' * 6 + b'\0'
    seg = struct.pack('<II', 0x3F400020, len(desc)) + desc
    body = hdr + seg
    chk = 0xEF
    for b in desc: chk ^= b
    pad = (15 - (len(body) % 16))
    return body + b'\0' * pad + bytes([chk])

def synthetic_flash(mb):
    img = bytearray(b'\xff' * (mb * 1024 * 1024))
    img[0x1000] = 0xE9
    rows = [r for r in csv_rows() if r[3] + r[4] <= len(img)]
    img[s2.PT_OFFSET:s2.PT_OFFSET + s2.PT_SIZE] = encode_partition_table(rows)
    app = app_image(); img[0x10000:0x10000 + len(app)] = app
    return bytes(img), rows

FLASH_ID_SAMPLE = """esptool.py v4.8.1
Serial port PORT
Connecting....
Detecting chip type... Unsupported detection protocol, switching and trying again...
Connecting....
Detecting chip type... ESP32
Chip is ESP32-PICO-V3-02 (revision v3.0)
Features: WiFi, BT, Dual Core, 240MHz, Embedded Flash, Embedded PSRAM, VRef calibration in efuse, Coding Scheme None
Crystal is 40MHz
MAC: 00:11:22:33:44:55
Uploading stub...
Running stub...
Stub running...
Manufacturer: c8
Device: 4017
Detected flash size: {mb}MB
Flash voltage set by a strapping pin to 3.3V
Hard resetting via RTS pin...
"""   # format sample of esptool 4.x output (not from the real watch)

class FakeWatch:
    def __init__(self, flash, mb, corrupt_second_read=False):
        self.flash, self.mb, self.corrupt, self.calls, self.reads = flash, mb, corrupt_second_read, [], 0
    def __call__(self, cmd, capture_output=True, text=True):
        self.calls.append(cmd)
        sub = [c for c in cmd if c in ('flash_id', 'read_flash', 'summary')][0]
        out = ''
        if sub == 'flash_id': out = FLASH_ID_SAMPLE.format(mb=self.mb)
        elif sub == 'summary': out = 'FLASH_CRYPT_CNT (BLOCK0)  Flash encryption is enabled if ... = 0 R/W (0b0000000)\nABS_DONE_0 (BLOCK0)  Secure boot V1 ... = False R/W (0b0)\n'
        else:
            i = cmd.index('read_flash'); addr, size, path = int(cmd[i + 1], 16), int(cmd[i + 2], 16), cmd[i + 3]
            data = bytearray(self.flash[addr:addr + size])
            if size > 0x100000:
                self.reads += 1
                if self.corrupt and self.reads == 2: data[123456] ^= 0xFF
            open(path, 'wb').write(data)
        return subprocess.CompletedProcess(cmd, 0, out, '')

# 1 the guard
for tool, sub in [('esptool', 'write_flash'), ('esptool', 'erase_flash'), ('esptool', 'erase_region'), ('esptool', 'merge_bin'), ('espefuse', 'burn_efuse'),
                  ('espefuse', 'burn_key'), ('espefuse', 'set_flash_voltage'), ('espefuse', 'write_protect_efuse'), ('esptool', 'write_mem'), ('esptool', 'load_ram')]:
    try: s2.run_device(tool, sub, 'PORT', runner=lambda *a, **k: (_ for _ in ()).throw(AssertionError('ran')))
    except s2.Refused: check(True, '')
    else: check(False, f'{tool} {sub} was not refused')
try: s2.run_device('esptool', 'read_flash', 'PORT', ['--erase-all'], runner=lambda *a, **k: None)
except s2.Refused: check(True, '')
else: check(False, 'extra option not refused')

# 2 simulated 4 MB watch: identify, wrong-size backup refused, correct backup passes
for mb in (4, 8):
    flash, rows = synthetic_flash(mb)
    with tempfile.TemporaryDirectory() as d:
        w = FakeWatch(flash, mb)
        ident = s2.cmd_identify(argparse.Namespace(port='PORT', out=d), runner=w)
        check(ident['flash']['flash_mb'] == mb and ident['flash']['embedded_psram'] and ident['flash']['chip'].startswith('ESP32-PICO-V3-02'), 'identify parse')
        check(ident['efuse']['flash_encryption_enabled'] is False and ident['efuse']['secure_boot_v1_enabled'] is False, 'efuse parse')
        check([p['label'] for p in ident['partition_table']['partitions']] == [r[0] for r in rows] and ident['partition_table']['md5_ok'], 'partition table')
        check(ident['apps'][0].get('project') == 'cyclift-factory' and ident['apps'][0].get('version') == '1.2.3', 'app description')
        wrong = 8 if mb == 4 else 4
        try: s2.cmd_backup(argparse.Namespace(port='PORT', out=d, flash_mb=wrong, confirm=s2.CONFIRM), runner=w)
        except s2.Refused: check(True, '')
        else: check(False, 'wrong flash size accepted')
        try: s2.cmd_backup(argparse.Namespace(port='PORT', out=d, flash_mb=mb, confirm='yes'), runner=w)
        except s2.Refused: check(True, '')
        else: check(False, 'backup without confirmation accepted')
        rep, ok = s2.cmd_backup(argparse.Namespace(port='PORT', out=d, flash_mb=mb, confirm=s2.CONFIRM), runner=w)
        check(ok and rep['sha256'] == hashlib.sha256(flash).hexdigest(), f'{mb} MB backup')
        check(open(os.path.join(d, f'factory-{mb}mb.bin'), 'rb').read() == flash, 'backup equals flash')
        allowed = {'flash_id', 'read_flash', 'summary'}
        check(all(any(c in allowed for c in call) and not any(re.match(r'(write|erase|burn|load_ram|merge)', c) for c in call) for call in w.calls), 'only read-only calls')
        check(all('--after' not in c or c[c.index('--after') + 1] == 'hard_reset' for c in w.calls), 'plain reset after each call')

# 3 the two reads must agree
flash, _ = synthetic_flash(4)
with tempfile.TemporaryDirectory() as d:
    w = FakeWatch(flash, 4, corrupt_second_read=True)
    s2.cmd_identify(argparse.Namespace(port='PORT', out=d), runner=w)
    try: s2.cmd_backup(argparse.Namespace(port='PORT', out=d, flash_mb=4, confirm=s2.CONFIRM), runner=w); check(False, 'differing reads accepted')
    except RuntimeError as e: check('differ' in str(e), 'differing reads reported')

# 4 descriptor parser agrees with esptool image_info
with tempfile.TemporaryDirectory() as d:
    p = os.path.join(d, 'app.bin'); open(p, 'wb').write(app_image())
    out = subprocess.run([sys.executable, '-m', 'esptool', '--chip', 'esp32', 'image_info', '--version', '2', p], capture_output=True, text=True)
    txt = out.stdout + out.stderr
    mine = s2.parse_app_desc(app_image())
    check(out.returncode == 0, 'esptool accepts the synthetic image: ' + txt[-300:])
    check(('Project name: ' + mine['project']) in txt and ('App version: ' + mine['version']) in txt, 'esptool and parser agree on the description')

# 5 eFuse parser on the real espefuse output format (virtual chip)
out = subprocess.run([sys.executable, '-m', 'espefuse', '--chip', 'esp32', '--virt', 'summary'], capture_output=True, text=True)
e = s2.parse_efuse_summary(out.stdout + out.stderr)
check(out.returncode == 0 and e['flash_crypt_cnt'] == 0 and e['flash_encryption_enabled'] is False and e['secure_boot_v1_enabled'] is False, 'espefuse virtual summary parsed')

# 6 an empty or wrong file is rejected by inspect
rep = s2.inspect_bytes(b'\xff' * (4 * 1024 * 1024), 4)
check(rep['blank'] and not rep['partition_table']['valid'], 'blank image detected')
check(not s2.inspect_bytes(flash[:1024 * 1024], 4)['size_matches'], 'short file detected')

print(f'stage2a tool: {checks} checks, {fails} failures')
sys.exit(1 if fails else 0)
