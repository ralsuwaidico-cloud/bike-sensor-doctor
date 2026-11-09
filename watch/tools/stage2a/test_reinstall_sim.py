#!/usr/bin/env python3
"""End-to-end simulation (no hardware) of the real PC runners on a modelled 8 MB flash:
first install (cy_install) -> Recovery B (cy_recover_b) -> RE-installation (cy_reinstall, B1).
The fake watch boots from whatever the flash selects (factory app0 or Cyclift app1), bumps the factory boot counter in the
NVS partition its table calls "nvs", boot-loops if the 4 MB bootloader sees partitions above 4 MB, and stays in download mode
after every esptool command until the session restarts it."""
import os, sys, tempfile, shutil, hashlib, struct
HERE = os.path.dirname(os.path.abspath(__file__))
FW_TOOLS = os.path.join(HERE, '..', '..', 'firmware', 'tools', 'v3')
sys.path.insert(0, HERE); sys.path.insert(0, FW_TOOLS)
import fp_plan as fp, install_check as ic, test_install_check as tic, test_fp_plan as tfp
import device_session as ds

FAILS = []


def check(c, m):
    print(('ok   ' if c else 'FAIL ') + m)
    if not c:
        FAILS.append(m)


home = tempfile.mkdtemp()
D = os.path.join(home, 'priv'); PD = os.path.join(D, 'plan_pieces'); T = os.path.join(home, 'tools'); FWD = os.path.join(home, 'fw')
for p in (PD, T, FWD):
    os.makedirs(p)
for f in ('fp_plan.py', 'install_check.py', 'device_session.py'):
    shutil.copy(os.path.join(HERE, f), T)
shutil.copy(os.path.join(FW_TOOLS, 'check_image_header.py'), T)
shutil.copy(os.path.join(HERE, 'pc_install_runner.py'), os.path.join(T, 'cy_install.py'))
shutil.copy(os.path.join(HERE, 'pc_recovery_b_runner.py'), os.path.join(T, 'cy_recover_b.py'))
shutil.copy(os.path.join(HERE, 'pc_reinstall_runner.py'), os.path.join(T, 'cy_reinstall.py'))

backup = bytearray(tic.backup_like())
bl = fp.image_len(backup, 0x1000); hdr = bytearray(backup[0x1000:0x1000 + bl]); hdr[2] = 2; hdr[3] = 0x20
hdr[-32:] = hashlib.sha256(bytes(hdr[:-32])).digest(); backup[0x1000:0x1000 + bl] = hdr
backup = bytes(backup)
fw = tfp.esp_image(983360, mode=2, size_code=3, seed=4)
fwpath = os.path.join(FWD, 'cyclift-stage1-v3poc-T-Watch-2021-V1_1.bin')
open(os.path.join(D, 'flash_8MB_read1.bin'), 'wb').write(backup); open(fwpath, 'wb').write(fw)
planned, _ = fp.apply_plan(backup, b'', True); man = []
for s in ic.PLANNED:
    for tag, src in (('original', backup), ('planned', planned)):
        n = '%s_0x%06x.bin' % (tag, s); open(os.path.join(PD, n), 'wb').write(src[s:s + 4096])
        man.append('%s %s' % (hashlib.sha256(src[s:s + 4096]).hexdigest(), n))
open(os.path.join(PD, 'manifest_sha256.txt'), 'w').write('\n'.join(man) + '\n')
open(os.path.join(D, 'RECOVERY_AND_INSTALL_COMMANDS_NOT_RUN.txt'), 'w').write('x')

FL = bytearray(backup)
STATE = {'mode': 'running', 'verify_fault': None}
BANNER = 'ets Jul 29 2019 12:21:46\r\n\r\nrst:0x1 (POWERON_RESET),boot:0x13 (SPI_FAST_FLASH_BOOT)\r\n'
G = {}


def _bct_bump(nv):
    blob = bytes(FL[nv:nv + 0x5000])
    if not ic_has_ns(blob):
        FL[nv:nv + 0x5000] = b'\xff' * 0x5000
        FL[nv:nv + 4] = struct.pack('<I', 0xFFFFFFFE)
        FL[nv + 64:nv + 96] = bytes([0, 1, 1, 0xff]) + b'\0' * 4 + b'osw-config'.ljust(16, b'\0') + bytes([1]) + b'\xff' * 7
        FL[nv + 32] &= 0xFC | 0x2
    v = G['bct'](bytes(FL[nv:nv + 0x5000]))
    for i in range(126):
        st = (FL[nv + 32 + i // 4] >> ((i % 4) * 2)) & 3; e = FL[nv + 64 + i * 32:nv + 96 + i * 32]
        if st == 2 and e[8:24].split(b'\0')[0] == b'bct':
            FL[nv + 32 + i // 4] &= ~(3 << ((i % 4) * 2)) & 0xFF
    for i in range(126):
        if (FL[nv + 32 + i // 4] >> ((i % 4) * 2)) & 3 == 3:
            FL[nv + 64 + i * 32:nv + 96 + i * 32] = bytes([1, 0x14, 1, 0xff]) + b'\0' * 4 + b'bct'.ljust(16, b'\0') + struct.pack('<i', (v or 0) + 1) + b'\xff' * 4
            FL[nv + 32 + i // 4] &= ~(1 << ((i % 4) * 2)) & 0xFF
            break


def ic_has_ns(blob):
    return G['nvs_has_namespace'](blob, 'osw-config')


def boot_text():
    img = bytes(FL); pts = fp.parse_pt(img[0x8000:0x8c00]); apps = [p for p in pts if p['type'] == 0]
    if img[0x1003] >> 4 == 2 and any(p['offset'] + p['size'] > 0x400000 for p in pts):
        return (BANNER + 'E: partition beyond flash size\r\n') * 4
    sel = fp.selected_slot(img, len(apps)) or 0; a = apps[sel]
    nv = [p for p in pts if p['label'] == 'nvs'][0]['offset']
    if a['offset'] == 0x400000:
        return BANNER + 'Cyclift v3 proof of concept · first frame after 565 ms\r\n'
    _bct_bump(nv)
    return BANNER + 'include/osw_config.h: Accessing key id c1\r\n'


class FlashSerial:
    def __init__(self):
        self._rts, self.dtr, self.out = False, False, b''

    @property
    def rts(self):
        return self._rts

    @rts.setter
    def rts(self, v):
        if self._rts and not v and not self.dtr:
            self.out += boot_text().encode(); STATE['mode'] = 'running'
        self._rts = v

    def read(self, n):
        CLOCK[0] += 0.5
        c, self.out = self.out[:n], self.out[n:]
        return c

    def write(self, b):
        pass

    def close(self):
        pass


CLOCK = [0.0]


class FlashTransport:
    def esptool(self, args, timeout=900):
        STATE['mode'] = 'download'
        c = args[0]
        if c == 'flash_id':
            return 0, 'Chip is ESP32-PICO-V3-02 (revision v3.1)\nDetected flash size: 8MB\n'
        if c == 'read_flash':
            o, n, f = int(args[1], 16), int(args[2], 16), args[3]; open(f, 'wb').write(bytes(FL[o:o + n])); return 0, 'read'
        if c == 'write_flash':
            a = args[1:]; assert a[:6] == ['--flash_mode', 'keep', '--flash_freq', 'keep', '--flash_size', 'keep'], a
            a = a[6:]
            for i in range(0, len(a), 2):
                o = int(a[i], 16); d = open(a[i + 1], 'rb').read(); s0 = o & ~0xFFF; e = (o + len(d) + 0xFFF) & ~0xFFF
                FL[s0:e] = b'\xff' * (e - s0); FL[o:o + len(d)] = d
            return 0, 'Hash of data verified.\n' * (len(a) // 2)
        if c == 'verify_flash':
            a = args[1:]; out = ''
            for i in range(0, len(a), 2):
                o = int(a[i], 16); d = open(a[i + 1], 'rb').read()
                out += '-- verify OK (digest matched)\n' if bytes(FL[o:o + len(d)]) == d and STATE['verify_fault'] != o else 'verify FAILED\n'
            return (0 if 'FAILED' not in out else 2), out
        raise AssertionError('refused command ' + c)

    def open_serial(self):
        return FlashSerial()

    def now(self):
        return CLOCK[0]

    def sleep(self, s):
        CLOCK[0] += s


def load(name):
    os.environ.update(CY_PRIVATE_DIR=D, CY_TOOLS_DIR=T, CY_INSTALLER=os.path.join(T, 'cy_install.py'))
    g = {'__file__': os.path.join(T, name), '__name__': name}
    src = open(os.path.join(T, name), encoding='utf-8').read()
    src = src.replace("FW_SHA = 'faa2828f8fd22d59877c4c9535eb09e1a15db3176f2b5cd1c438810aead5cba7'", 'FW_SHA = %r' % hashlib.sha256(fw).hexdigest())
    src = src.replace("BK_SHA = '77ad7105c68fb7de04e5717fca4e90b08bd9c32adeb5c098e3e00446d3767693'", 'BK_SHA = %r' % hashlib.sha256(backup).hexdigest())
    exec(compile(src, name, 'exec'), g)
    return g


def patch(g):
    """Point the loaded runner at the modelled watch and the test firmware path."""
    g['S'] = g['ds'].DeviceSession(FlashTransport(), log=lambda m: g['log'](m), boot_window=6)
    g['FW'] = fwpath
    G.update(g)


# the exec'd installer source of the reinstall runner must also see the patched constants -> patch cy_install on disk copy
for nm in ('cy_install.py',):
    p = os.path.join(T, nm); s = open(p, encoding='utf-8').read()
    s = s.replace("FW_SHA = 'faa2828f8fd22d59877c4c9535eb09e1a15db3176f2b5cd1c438810aead5cba7'", 'FW_SHA = %r' % hashlib.sha256(fw).hexdigest())
    s = s.replace("BK_SHA = '77ad7105c68fb7de04e5717fca4e90b08bd9c32adeb5c098e3e00446d3767693'", 'BK_SHA = %r' % hashlib.sha256(backup).hexdigest())
    open(p, 'w', encoding='utf-8').write(s)

# 1. first installation as on 9 Nov 19:35 ---------------------------------------------------------------------------------
g = load('cy_install.py'); patch(g)
ok = all(g['phase'](p) for p in ('precheck', 'p1', 'p2', 'p3', 'p4', 'post'))
check(ok and STATE['mode'] == 'running', 'first install (fixed runner): all phases pass, watch left running Cyclift')

# 2. Recovery B -----------------------------------------------------------------------------------------------------------
g = load('cy_recover_b.py'); patch(g)
ok = all(g['phase'](p) for p in ('rb_precheck', 'rb_restore', 'rb_confirm'))
check(ok and STATE['mode'] == 'running', 'Recovery B: all phases pass, factory app running')
check(FL[0x400000:0x400000 + len(fw)] == fw and any(FL[0x700000:0x701000] != b'\xff' * 0x1000 for _ in [0]),
      'state after Recovery B: Stage 1 image still at 0x400000, Cyclift data area in use')
AFTER_RB = bytes(FL)

# 3. the OLD pre-check refuses this state (why the re-install pre-check exists) ------------------------------------------------
g = load('cy_install.py'); patch(g)
check(g['phase']('precheck') is False and STATE['mode'] == 'running', 'old pre-check correctly refuses the post-recovery state (and restarts the watch)')

# 4. B1 re-installation -----------------------------------------------------------------------------------------------------
first_pre = open(os.path.join(D, 'pre_install.bin'), 'rb').read()
g = load('cy_reinstall.py'); patch(g)
results = {}
for p in ('precheck_re', 'p1', 'p2', 'p3', 'p4', 'post'):
    results[p] = g['phase'](p)
    if not results[p]:
        break
check(all(results.values()) and len(results) == 6, 'B1 re-install: precheck_re, p1-p4, post all pass (%s)' % results)
check(STATE['mode'] == 'running' and FL[0xF000:0x10000] == planned[0xF000:0x10000], 'B1: watch left running Cyclift from app1 (not in download mode)')
check(all(FL[lo:hi] == backup[lo:hi] for lo, hi in ((0x10000, 0x210000), (0x210000, 0x400000))), 'B1: factory app and factory files byte-identical to the backup')
arch = os.path.join(D, 'first_install_20261109')
check(os.path.isdir(arch) and open(os.path.join(arch, 'pre_install.bin'), 'rb').read() == first_pre, 'B1: first-install records archived (copied) before being replaced')
log_txt = open(os.path.join(D, 'install_log.txt'), encoding='utf-8').read()
check('C3: factory app ran under the new table (its boot counter in the Cyclift area advanced' in log_txt, 'B1: C3 requires the factory counter in the Cyclift area to advance')

# 5. B1 failure path: verify failure at Phase 2 -> stops, restarts, no later phase possible --------------------------------------
FL[:] = AFTER_RB
g = load('cy_reinstall.py'); patch(g)
assert g['phase']('precheck_re') and g['phase']('p1')
STATE['verify_fault'] = 0x1000
check(g['phase']('p2') is False and STATE['mode'] == 'running', 'B1 verify failure at Phase 2: phase fails, watch restarted (not left in download mode)')
STATE['verify_fault'] = None
check(fp.selected_slot(bytes(FL), 1) == 0 and fp.parse_pt(bytes(FL[0x8000:0x8C00])) == fp.parse_pt(backup[0x8000:0x8C00]),
      'after the Phase 2 failure the factory table and selection are still active')

# 6. the re-install pre-check refuses a wrong image in the upper flash ---------------------------------------------------------
FL[:] = AFTER_RB
FL[0x400100] ^= 0xFF
g = load('cy_reinstall.py'); patch(g)
check(g['phase']('precheck_re') is False, 're-install pre-check refuses an upper-flash image that differs from the approved file')
FL[0x400100] ^= 0xFF

print('reinstall simulation: %d failures' % len(FAILS))
sys.exit(1 if FAILS else 0)
