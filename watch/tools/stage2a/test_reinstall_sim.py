#!/usr/bin/env python3
"""End-to-end simulation (no hardware) of the real PC runners on a modelled 8 MB flash:
first install (cy_install) -> Recovery B (cy_recover_b) -> RE-installation (cy_reinstall, B1).
The fake watch boots from whatever the flash selects (factory app0 or Cyclift app1), bumps the factory boot counter in the
NVS partition its table calls "nvs", boot-loops if the 4 MB bootloader sees partitions above 4 MB, and stays in download mode
after every esptool command until the session restarts it."""
import os, re, sys, tempfile, shutil, hashlib, struct
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
shutil.copy(os.path.join(HERE, 'pc_update_s11_runner.py'), os.path.join(T, 'cy_update_s11.py'))
shutil.copy(os.path.join(HERE, 'pc_update_s12_runner.py'), os.path.join(T, 'cy_update_s12.py'))
shutil.copy(os.path.join(HERE, 'pc_update_s13_runner.py'), os.path.join(T, 'cy_update_s13.py'))
shutil.copy(os.path.join(HERE, 'pc_update_rc2_runner.py'), os.path.join(T, 'cy_update_rc2.py'))
shutil.copy(os.path.join(HERE, 'pc_update_s14_runner.py'), os.path.join(T, 'cy_update_s14.py'))

backup = bytearray(tic.backup_like())
bl = fp.image_len(backup, 0x1000); hdr = bytearray(backup[0x1000:0x1000 + bl]); hdr[2] = 2; hdr[3] = 0x20
hdr[-32:] = hashlib.sha256(bytes(hdr[:-32])).digest(); backup[0x1000:0x1000 + bl] = hdr
backup = bytes(backup)
fw = tfp.esp_image(983360, mode=2, size_code=3, seed=4)
fwpath = os.path.join(FWD, 'cyclift-stage1-v3poc-T-Watch-2021-V1_1.bin')
fw11 = tfp.esp_image(951296, mode=2, size_code=3, seed=11)          # Stage 1.1 stand-in, shorter than Stage 1 (tests the padding)
fw11path = os.path.join(FWD, 'cyclift-stage1.1-v3poc-T-Watch-2021-V1_1.bin'); open(fw11path, 'wb').write(fw11)
fw12 = tfp.esp_image(1015808, mode=2, size_code=3, seed=12)         # Stage 1.2 stand-in, LONGER than Stage 1.1 (span grows)
fw12path = os.path.join(FWD, 'cyclift-stage1.2-v3poc-T-Watch-2021-V1_1.bin'); open(fw12path, 'wb').write(fw12)
fw13 = tfp.esp_image(1048576, mode=2, size_code=3, seed=13)         # Stage 1.3 RC1 stand-in, longer again (span 0x100000)
fw13path = os.path.join(FWD, 'cyclift-stage1.3-rc1-v3poc-T-Watch-2021-V1_1.bin'); open(fw13path, 'wb').write(fw13)
fwr2 = tfp.esp_image(1052672, mode=2, size_code=3, seed=23)        # Stage 1.3 RC2 stand-in, slightly longer (span 0x101000)
fwr2path = os.path.join(FWD, 'cyclift-stage1.3-rc2-v3poc-T-Watch-2021-V1_1.bin'); open(fwr2path, 'wb').write(fwr2)
fw14 = tfp.esp_image(1060864, mode=2, size_code=3, seed=14)        # Stage 1.4 RC1 stand-in, longer again (span 0x103000)
fw14path = os.path.join(FWD, 'cyclift-stage1.4-rc1-v3poc-T-Watch-2021-V1_1.bin'); open(fw14path, 'wb').write(fw14)
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
        if bytes(FL[0x400000:0x400000 + len(fw14)]) == fw14:
            return BANNER + 'reset reason: power-on (code 1) \xb7 start 1 since power-on\r\nCyclift v3 proof of concept \xb7 Stage 1.4 RC1 (button system; local screens; IRAM rendering off) \xb7 simulated data \xb7 first frame after 440 ms\r\n'
        if bytes(FL[0x400000:0x400000 + len(fwr2)]) == fwr2:
            return BANNER + 'reset reason: power-on (code 1) \xb7 start 1 since power-on\r\nCyclift v3 proof of concept \xb7 Stage 1.3 RC2 (local screens; IRAM rendering off) \xb7 simulated data \xb7 first frame after 430 ms\r\n'
        if bytes(FL[0x400000:0x400000 + len(fw13)]) == fw13:
            return BANNER + 'Cyclift v3 proof of concept · Stage 1.3 RC1 (local screens; IRAM rendering off) · simulated data · first frame after 430 ms\r\n'
        if bytes(FL[0x400000:0x400000 + len(fw12)]) == fw12:
            return BANNER + 'Cyclift v3 proof of concept · Stage 1.2 (diagnostics; IRAM rendering off) · first frame after 420 ms\r\n'
        if bytes(FL[0x400000:0x400000 + len(fw11)]) == fw11:
            return BANNER + 'Cyclift v3 proof of concept · Stage 1.1 (rendering optimisation) · first frame after 400 ms\r\n'
        if bytes(FL[0x400000:0x400000 + len(fw)]) != fw:
            return BANNER + 'E: invalid app image in ota_1, falling back\r\n'       # not reached in these tests
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


CMDS = []                                 # every esptool command the runners issue (audit of what C1 would do)


class FlashTransport:
    def esptool(self, args, timeout=900):
        STATE['mode'] = 'download'
        CMDS.append(list(args))
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
    os.environ.update(CY_PRIVATE_DIR=D, CY_TOOLS_DIR=T, CY_INSTALLER=os.path.join(T, 'cy_install.py'), CY_FW11=fw11path, CY_FW12=fw12path, CY_FW13=fw13path, CY_FWR2=fwr2path, CY_FWS14=fw14path,
                      CY_UPDATE_S11=os.path.join(T, 'cy_update_s11.py'), CY_UPDATE_S13=os.path.join(T, 'cy_update_s13.py'))
    g = {'__file__': os.path.join(T, name), '__name__': name}
    src = open(os.path.join(T, name), encoding='utf-8').read()
    src = src.replace("FW_SHA = 'faa2828f8fd22d59877c4c9535eb09e1a15db3176f2b5cd1c438810aead5cba7'", 'FW_SHA = %r' % hashlib.sha256(fw).hexdigest())
    src = src.replace("BK_SHA = '77ad7105c68fb7de04e5717fca4e90b08bd9c32adeb5c098e3e00446d3767693'", 'BK_SHA = %r' % hashlib.sha256(backup).hexdigest())
    src = src.replace("FW11_SHA = '3274b8877df0a23a5e5cb1364868322d79d643d29411b36782b6bfb34eb937ba'", 'FW11_SHA = %r' % hashlib.sha256(fw11).hexdigest())
    src = re.sub(r"FW12_SHA = '[0-9a-f_A-Z]+'", 'FW12_SHA = %r' % hashlib.sha256(fw12).hexdigest(), src)
    src = re.sub(r"FW13_SHA = '[0-9a-f_A-Z]+'", 'FW13_SHA = %r' % hashlib.sha256(fw13).hexdigest(), src)
    src = re.sub(r"FWR2_SHA = '[0-9a-f_A-Z]+'", 'FWR2_SHA = %r' % hashlib.sha256(fwr2).hexdigest(), src)
    src = re.sub(r"FW14_SHA = '[0-9a-f_A-Z-]+'", 'FW14_SHA = %r' % hashlib.sha256(fw14).hexdigest(), src)
    exec(compile(src, name, 'exec'), g)
    return g


def patch(g):
    """Point the loaded runner at the modelled watch and the test firmware path."""
    g['S'] = g['ds'].DeviceSession(FlashTransport(), log=lambda m: g['log'](m), boot_window=6)
    g['FW'] = fwpath
    G.update(g)


# the exec'd installer source of the reinstall runner must also see the patched constants -> patch cy_install on disk copy
for nm in ('cy_install.py', 'cy_update_s11.py'):
    p = os.path.join(T, nm); s = open(p, encoding='utf-8').read()
    s = s.replace("FW_SHA = 'faa2828f8fd22d59877c4c9535eb09e1a15db3176f2b5cd1c438810aead5cba7'", 'FW_SHA = %r' % hashlib.sha256(fw).hexdigest())
    s = s.replace("BK_SHA = '77ad7105c68fb7de04e5717fca4e90b08bd9c32adeb5c098e3e00446d3767693'", 'BK_SHA = %r' % hashlib.sha256(backup).hexdigest())
    s = s.replace("FW11_SHA = '3274b8877df0a23a5e5cb1364868322d79d643d29411b36782b6bfb34eb937ba'", 'FW11_SHA = %r' % hashlib.sha256(fw11).hexdigest())
    s = s.replace("WRITE_ADDR, WRITE_LEN = 0x400000, 0xF7000", "WRITE_ADDR, WRITE_LEN = 0x400000, %#x" % ((max(len(fw), len(fw11)) + 0xFFF) & ~0xFFF))
    open(p, 'w', encoding='utf-8').write(s)
p = os.path.join(T, 'cy_update_s13.py'); s = open(p, encoding='utf-8').read()     # exec'd by cy_update_rc2.py
open(p, 'w', encoding='utf-8').write(re.sub(r"FW13_SHA = '[0-9a-f_A-Z]+'", 'FW13_SHA = %r' % hashlib.sha256(fw13).hexdigest(), s))

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
AFTER_B1 = bytes(FL)
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

# 7. PROPOSED Stage 1.1 app-slot update on the B1 state, rollback to Stage 1, and a failure path ----------------------------------
SPAN = (max(len(fw), len(fw11)) + 0xFFF) & ~0xFFF
def load_s11():
    g = load('cy_update_s11.py'); patch(g); g['FW11'] = fw11path; g['WRITE_LEN'] = SPAN; return g
FL[:] = AFTER_B1
g = load_s11()
CMDS.clear()
res = [g['phase'](p) for p in ('s11_pre', 's11_write', 's11_post')]
check(res == [True, True, True], 'Stage 1.1 update: pre-check, app1 write + Stage 1.1 boot confirmed, post map (%s)' % res)
writes = [(c[0], [a for a in c[1:] if a.startswith('0x')]) for c in CMDS if c[0] not in ('flash_id', 'read_flash')]
wr = [c for c in CMDS if c[0] == 'write_flash']
check(len(wr) == 1 and [a for a in wr[0] if a.startswith('0x')] == ['0x400000'] and os.path.getsize(wr[0][-1]) == SPAN,
      'Stage 1.1 update issues exactly ONE write: 0x400000, %d B (no bootloader, table, OTA, factory or erase command)' % SPAN)
check(all(c[0] in ('flash_id', 'read_flash', 'write_flash', 'verify_flash') for c in CMDS) and all(a == '0x400000' for c in CMDS if c[0] == 'verify_flash' for a in c[1:] if a.startswith('0x')),
      'Stage 1.1 update: only flash_id, read_flash, one write_flash and verify_flash at 0x400000 are used (%s)' % sorted(set(c[0] for c in CMDS)))
check(bytes(FL[:0x400000]) == AFTER_B1[:0x400000], 'Stage 1.1 update: first 4 MB (factory app, files, settings, bootloader, table, OTA) untouched')
span = (max(len(fw), len(fw11)) + 0xFFF) & ~0xFFF
check(bytes(FL[0x400000:0x400000 + span]) == fw11 + b'\xff' * (span - len(fw11)), 'Stage 1.1 update: no remains of the longer Stage 1 image in app1')
AFTER_S11 = bytes(FL)
# existing recovery tools after a Stage 1.1 update: R-A (OTA record) and R-B (four sectors) must still work
gi = load('cy_install.py'); patch(gi)
check(gi['recovery']('RA') is True and fp.selected_slot(bytes(FL), 2) == 0, 'R-A after Stage 1.1: original OTA record written, factory app starts')
FL[:] = AFTER_S11
gb = load('cy_recover_b.py'); patch(gb)
ok = all(gb['phase'](p) for p in ('rb_precheck', 'rb_restore', 'rb_confirm'))
check(ok and bytes(FL[:0x400000])[0x10000:] == backup[0x10000:0x400000] and fp.parse_pt(bytes(FL[0x8000:0x8C00])) == fp.parse_pt(backup[0x8000:0x8C00]),
      'R-B after Stage 1.1: accepts Stage 1.1 in app1, restores the factory layout, factory starts')
FL[:] = AFTER_S11
check(g['phase']('s11_rollback') is True and bytes(FL[0x400000:0x400000 + len(fw)]) == fw, 'rollback to the approved Stage 1: written, verified, Stage 1 boot confirmed')
check(g['phase']('s11_pre') is True, 'after rollback the watch is again in the exact B1 state (pre-check passes)')
STATE['verify_fault'] = 0x400000
check(g['phase']('s11_write') is False and STATE['mode'] == 'running', 'Stage 1.1 update with a verify failure: phase fails, watch restarted')
STATE['verify_fault'] = None
g2 = load_s11(); g2['FW11_SHA'] = '0' * 64
FL[:] = AFTER_B1
check(g2['phase']('s11_pre') is False, 'Stage 1.1 pre-check refuses a file whose fingerprint is not the approved one')

# 9. PROPOSED Stage 1.2 app-slot update on the installed Stage 1.1 state (as after C1), rollbacks, failure paths ----------------
def load_s12():
    g = load('cy_update_s12.py'); patch(g); g['FW11'] = fw11path; g['FW12'] = fw12path; return g
FL[:] = AFTER_S11
g = load_s12()
CMDS.clear()
res = [g['phase'](p) for p in ('s12_pre', 's12_write', 's12_post')]
check(res == [True, True, True], 'Stage 1.2 update: pre-check, app1 write + Stage 1.2 boot confirmed, post map (%s)' % res)
SPAN12 = (max(len(fw11), len(fw12), SPAN) + 0xFFF) & ~0xFFF
wr = [c for c in CMDS if c[0] == 'write_flash']
check(len(wr) == 1 and [a for a in wr[0] if a.startswith('0x')] == ['0x400000'] and os.path.getsize(wr[0][-1]) == SPAN12,
      'Stage 1.2 update issues exactly ONE write: 0x400000, %d B' % SPAN12)
check(all(c[0] in ('flash_id', 'read_flash', 'write_flash', 'verify_flash') for c in CMDS), 'Stage 1.2 update: only flash_id, read_flash, write_flash, verify_flash')
check(bytes(FL[:0x400000]) == AFTER_S11[:0x400000], 'Stage 1.2 update: first 4 MB (factory app, files, settings, bootloader, table, OTA) untouched')
check(bytes(FL[0x400000:0x400000 + SPAN12]) == fw12 + b'\xff' * (SPAN12 - len(fw12)) and bytes(FL[0x400000 + SPAN12:0x700000]) == b'\xff' * (0x300000 - SPAN12),
      'Stage 1.2 update: app1 = Stage 1.2 + erased padding, rest of app1 erased')
AFTER_S12 = bytes(FL)
gi = load('cy_install.py'); patch(gi)
check(gi['recovery']('RA') is True and fp.selected_slot(bytes(FL), 2) == 0, 'R-A after Stage 1.2: original OTA record written, factory app starts')
FL[:] = AFTER_S12
gb = load('cy_recover_b.py'); patch(gb)
ok = all(gb['phase'](p) for p in ('rb_precheck', 'rb_restore', 'rb_confirm'))
check(ok and fp.parse_pt(bytes(FL[0x8000:0x8C00])) == fp.parse_pt(backup[0x8000:0x8C00]), 'R-B after Stage 1.2: accepts Stage 1.2 in app1, restores the factory layout, factory starts')
FL[:] = AFTER_S12
check(g['phase']('s12_rollback') is True and bytes(FL[0x400000:0x400000 + SPAN12]) == fw11 + b'\xff' * (SPAN12 - len(fw11)),
      'rollback R-S11 to the installed Stage 1.1: written, verified, Stage 1.1 boot confirmed, no Stage 1.2 remains')
check(g['phase']('s12_pre') is True, 'after rollback the watch is again in the Stage 1.1 state (Stage 1.2 pre-check passes)')
FL[:] = AFTER_S12
check(g['phase']('s11_rollback') is True and bytes(FL[0x400000:0x400000 + len(fw)]) == fw, 'from Stage 1.2 the further rollback to Stage 1 (s11_rollback) still works')
FL[:] = AFTER_S11
STATE['verify_fault'] = 0x400000
g['phase']('s12_pre')
check(g['phase']('s12_write') is False and STATE['mode'] == 'running', 'Stage 1.2 update with a verify failure: phase fails, watch restarted')
STATE['verify_fault'] = None
FL[:] = AFTER_S11
g2 = load_s12(); g2['FW12_SHA'] = '0' * 64
check(g2['phase']('s12_pre') is False, 'Stage 1.2 pre-check refuses a file whose fingerprint is not the approved one')
FL[:] = AFTER_B1
check(load_s12()['phase']('s12_pre') is False, 'Stage 1.2 pre-check refuses a watch that does not run Stage 1.1')

# 10. PROPOSED Stage 1.3 RC1 app-slot update on the installed Stage 1.1 state, rollbacks, failure paths ----------------------
def load_s13():
    g = load('cy_update_s13.py'); patch(g); g['FW11'] = fw11path; g['FW13'] = fw13path; return g
FL[:] = AFTER_S11
g = load_s13()
CMDS.clear()
res = [g['phase'](p) for p in ('s13_pre', 's13_write', 's13_post')]
check(res == [True, True, True], 'Stage 1.3 RC1 update: pre-check, app1 write + boot confirmed, post map (%s)' % res)
SPAN13 = (max(len(fw11), len(fw13), SPAN) + 0xFFF) & ~0xFFF
wr = [c for c in CMDS if c[0] == 'write_flash']
check(len(wr) == 1 and [a for a in wr[0] if a.startswith('0x')] == ['0x400000'] and os.path.getsize(wr[0][-1]) == SPAN13,
      'Stage 1.3 RC1 update issues exactly ONE write: 0x400000, %d B' % SPAN13)
check(all(c[0] in ('flash_id', 'read_flash', 'write_flash', 'verify_flash') for c in CMDS), 'Stage 1.3 RC1 update: only flash_id, read_flash, write_flash, verify_flash')
check(bytes(FL[:0x400000]) == AFTER_S11[:0x400000], 'Stage 1.3 RC1 update: first 4 MB (factory app, files, settings, bootloader, table, OTA) untouched')
check(bytes(FL[0x400000:0x400000 + SPAN13]) == fw13 + b'\xff' * (SPAN13 - len(fw13)) and bytes(FL[0x400000 + SPAN13:0x700000]) == b'\xff' * (0x300000 - SPAN13),
      'Stage 1.3 RC1 update: app1 = RC1 + erased padding, rest of app1 erased')
AFTER_S13 = bytes(FL)
gi = load('cy_install.py'); patch(gi)
check(gi['recovery']('RA') is True and fp.selected_slot(bytes(FL), 2) == 0, 'R-A after Stage 1.3 RC1: original OTA record written, factory app starts')
FL[:] = AFTER_S13
gb = load('cy_recover_b.py'); patch(gb)
ok = all(gb['phase'](p) for p in ('rb_precheck', 'rb_restore', 'rb_confirm'))
check(ok and fp.parse_pt(bytes(FL[0x8000:0x8C00])) == fp.parse_pt(backup[0x8000:0x8C00]), 'R-B after Stage 1.3 RC1: accepts RC1 in app1, restores the factory layout, factory starts')
FL[:] = AFTER_S13
check(g['phase']('s13_rollback') is True and bytes(FL[0x400000:0x400000 + SPAN13]) == fw11 + b'\xff' * (SPAN13 - len(fw11)),
      'rollback R-S11 from RC1 to the installed Stage 1.1: written, verified, Stage 1.1 boot confirmed, no RC1 remains')
check(g['phase']('s13_pre') is True, 'after rollback the watch is again in the Stage 1.1 state (RC1 pre-check passes)')
FL[:] = AFTER_S13
check(g['phase']('s11_rollback') is True and bytes(FL[0x400000:0x400000 + len(fw)]) == fw, 'from RC1 the further rollback to Stage 1 (s11_rollback) still works')
FL[:] = AFTER_S11
STATE['verify_fault'] = 0x400000
g['phase']('s13_pre')
check(g['phase']('s13_write') is False and STATE['mode'] == 'running', 'RC1 update with a verify failure: phase fails, watch restarted')
STATE['verify_fault'] = None
FL[:] = AFTER_S11
g2 = load_s13(); g2['FW13_SHA'] = '0' * 64
check(g2['phase']('s13_pre') is False, 'RC1 pre-check refuses a file whose fingerprint is not the pinned one')
FL[:] = AFTER_S11
os.environ['CY_FW13'] = fw13path
g3 = load('cy_update_s13.py'); patch(g3); g3['FW11'] = fw11path; g3['FW13'] = fw13path; g3['FW13_SHA'] = 'NOT_PINNED'
check(g3['phase']('s13_pre') is False, 'RC1 pre-check refuses everything while the tool is not pinned (NOT_PINNED)')
FL[:] = AFTER_B1
check(load_s13()['phase']('s13_pre') is False, 'RC1 pre-check refuses a watch that does not run Stage 1.1')

# 11. PROPOSED RC2 app-slot update on the installed RC1 state, rollbacks, failure paths -----------------------------
FL[:] = AFTER_S13
def load_r2():
    g = load('cy_update_rc2.py'); patch(g); g['FW11'] = fw11path; g['FW13'] = fw13path; g['FWR2'] = fwr2path; return g
g = load_r2()
CMDS.clear()
res = [g['phase'](p) for p in ('r2_pre', 'r2_write', 'r2_post')]
check(res == [True, True, True], 'RC2 update: pre-check, app1 write + boot confirmed, post map (%s)' % res)
SPANR2 = (max(len(fw13), len(fwr2), SPAN) + 0xFFF) & ~0xFFF
wr = [c for c in CMDS if c[0] == 'write_flash']
check(len(wr) == 1 and [a for a in wr[0] if a.startswith('0x')] == ['0x400000'] and os.path.getsize(wr[0][-1]) == SPANR2,
      'RC2 update issues exactly ONE write: 0x400000, %d B' % SPANR2)
check(all(c[0] in ('flash_id', 'read_flash', 'write_flash', 'verify_flash') for c in CMDS), 'RC2 update: only flash_id, read_flash, write_flash, verify_flash')
check(bytes(FL[:0x400000]) == AFTER_S13[:0x400000], 'RC2 update: first 4 MB untouched')
check(bytes(FL[0x400000:0x400000 + SPANR2]) == fwr2 + b'\xff' * (SPANR2 - len(fwr2)), 'RC2 update: app1 = RC2 + erased padding')
AFTER_R2 = bytes(FL)
check(g['phase']('r2_rollback') is True and bytes(FL[0x400000:0x400000 + SPANR2]) == fw13 + b'\xff' * (SPANR2 - len(fw13)),
      'rollback from RC2 to the installed RC1: written, verified, RC1 boot confirmed')
check(g['phase']('r2_pre') is True, 'after rollback the watch is again in the RC1 state (RC2 pre-check passes)')
FL[:] = AFTER_R2
gb = load('cy_recover_b.py'); patch(gb)
ok = all(gb['phase'](p) for p in ('rb_precheck', 'rb_restore', 'rb_confirm'))
check(ok and fp.parse_pt(bytes(FL[0x8000:0x8C00])) == fp.parse_pt(backup[0x8000:0x8C00]), 'R-B after RC2: accepts RC2 in app1, restores the factory layout')
FL[:] = AFTER_S13
STATE['verify_fault'] = 0x400000
g = load_r2(); g['phase']('r2_pre')
check(g['phase']('r2_write') is False and STATE['mode'] == 'running', 'RC2 update with a verify failure: phase fails, watch restarted')
STATE['verify_fault'] = None
FL[:] = AFTER_S13
g3 = load_r2(); g3['FWR2_SHA'] = 'NOT_PINNED'
check(g3['phase']('r2_pre') is False, 'RC2 pre-check refuses everything while the tool is not pinned')
FL[:] = AFTER_S11
check(load_r2()['phase']('r2_pre') is False, 'RC2 pre-check refuses a watch that does not run RC1')

# 12. PROPOSED Stage 1.4 RC1 (button system) app-slot update on the installed RC1 state, rollback, failure paths ----------
FL[:] = AFTER_S13
def load_s14():
    g = load('cy_update_s14.py'); patch(g); g['FW11'] = fw11path; g['FW13'] = fw13path; g['FW14'] = fw14path; return g
g = load_s14()
CMDS.clear()
res = [g['phase'](p) for p in ('s14_pre', 's14_write', 's14_post')]
check(res == [True, True, True], 'Stage 1.4 update: pre-check, app1 write + boot confirmed, post map (%s)' % res)
SPAN14 = (max(len(fw13), len(fw14), SPAN) + 0xFFF) & ~0xFFF
wr = [c for c in CMDS if c[0] == 'write_flash']
check(len(wr) == 1 and [a for a in wr[0] if a.startswith('0x')] == ['0x400000'] and os.path.getsize(wr[0][-1]) == SPAN14,
      'Stage 1.4 update issues exactly ONE write: 0x400000, %d B' % SPAN14)
check(all(c[0] in ('flash_id', 'read_flash', 'write_flash', 'verify_flash') for c in CMDS), 'Stage 1.4 update: only flash_id, read_flash, write_flash, verify_flash')
check(bytes(FL[:0x400000]) == AFTER_S13[:0x400000], 'Stage 1.4 update: first 4 MB (bootloader, table, OTA record, factory app and files) untouched')
check(bytes(FL[0x400000:0x400000 + SPAN14]) == fw14 + b'\xff' * (SPAN14 - len(fw14)), 'Stage 1.4 update: app1 = Stage 1.4 + erased padding')
AFTER_14 = bytes(FL)
check(g['phase']('s14_rollback') is True and bytes(FL[0x400000:0x400000 + SPAN14]) == fw13 + b'\xff' * (SPAN14 - len(fw13)),
      'rollback from Stage 1.4 to the installed RC1: written, verified, RC1 boot confirmed')
check(g['phase']('s14_pre') is True, 'after rollback the watch is again in the RC1 state (Stage 1.4 pre-check passes)')
FL[:] = AFTER_14
gb = load('cy_recover_b.py'); patch(gb)
ok = all(gb['phase'](p) for p in ('rb_precheck', 'rb_restore', 'rb_confirm'))
check(ok and fp.parse_pt(bytes(FL[0x8000:0x8C00])) == fp.parse_pt(backup[0x8000:0x8C00]), 'R-B after Stage 1.4: accepts it in app1, restores the factory layout')
FL[:] = AFTER_S13
STATE['verify_fault'] = 0x400000
g = load_s14(); g['phase']('s14_pre')
check(g['phase']('s14_write') is False and STATE['mode'] == 'running', 'Stage 1.4 update with a verify failure: phase fails, watch restarted')
STATE['verify_fault'] = None
FL[:] = AFTER_S13
g3 = load_s14(); g3['FW14_SHA'] = '0' * 64
check(g3['phase']('s14_pre') is False, 'Stage 1.4 pre-check refuses a file whose fingerprint is not the pinned one')
FL[:] = AFTER_S11
check(load_s14()['phase']('s14_pre') is False, 'Stage 1.4 pre-check refuses a watch that does not run RC1')
src14 = open(os.path.join(HERE, 'pc_update_s14_runner.py'), encoding='utf-8').read()
PIN14 = open(os.path.join(HERE, '..', '..', 'firmware', 'releases', 'stage1.4-rc1.sha256')).read().strip()
check("FW14_SHA = '%s'" % PIN14 in src14 and "FW14_SHA = '%s'" % PIN14 in open(os.path.join(HERE, 'pc_recovery_b_runner.py'), encoding='utf-8').read(),
      'Stage 1.4 runner and Recovery B pinned to releases/stage1.4-rc1.sha256 (%s…)' % PIN14[:8])
REAL14 = 1253264; SPAN14R = (max(1194112, REAL14) + 0xFFF) & ~0xFFF
check(SPAN14R == 1253376 and 0x400000 + SPAN14R - 1 == 0x531FFF and 0x400000 + SPAN14R <= 0x700000,
      'real Stage 1.4 image: one write 0x400000–0x531FFF (1,253,376 B), ends below the Cyclift settings area 0x700000')

# 8. the real C1 numbers: Stage 1 (983,360 B) and Stage 1.1 (1,009,632 B) -> one write 0x400000-0x4F6FFF
real = (max(983360, 1009632) + 0xFFF) & ~0xFFF
src = open(os.path.join(HERE, 'pc_update_s11_runner.py'), encoding='utf-8').read()
check(real == 0xF7000 and 'WRITE_ADDR, WRITE_LEN = 0x400000, 0xF7000' in src,
      'C1 write plan with the real files: address 0x400000, %d B (0x%X), last byte 0x%06X — inside app1 (0x400000-0x6FFFFF)' % (real, real, 0x400000 + real - 1))

real12 = (max(1009632, 1016192, 0xF7000) + 0xFFF) & ~0xFFF
src12 = open(os.path.join(HERE, 'pc_update_s12_runner.py'), encoding='utf-8').read()
check(real12 == 0xF9000 and "FW12_SHA = '2760f5a7f4c4064e3dbbf70e9bd2af9c76be8a8e6f8ecc492cfc0e09f66ae75a'" in src12,
      'Stage 1.2 write plan with the real files: address 0x400000, %d B (0x%X), last byte 0x%06X — inside app1; tool pinned to 2760f5a7…' % (real12, real12, 0x400000 + real12 - 1))
real13 = (max(1009632, 1194112, 0xF7000) + 0xFFF) & ~0xFFF
src13 = open(os.path.join(HERE, 'pc_update_s13_runner.py'), encoding='utf-8').read()
pin13 = open(os.path.join(HERE, '..', '..', 'firmware', 'releases', 'stage1.3-rc1-installed', 'PIN.sha256')).read().strip()
check(real13 == 0x124000 and 0x400000 + real13 - 1 < 0x700000 and "FW13_SHA = '%s'" % pin13 in src13 and pin13 == '4ea0ea90da5061859019c7b6f94c1eaea409c362d94a07e058d7755feda50c19',
      'RC1 write plan with the real files: address 0x400000, %d B (0x%X), last byte 0x%06X — inside app1; tool pinned to 4ea0ea90… (same as releases/)' % (real13, real13, 0x400000 + real13 - 1))
realr2 = (max(1194112, 1197184, 0xF7000) + 0xFFF) & ~0xFFF
srcr2 = open(os.path.join(HERE, 'pc_update_rc2_runner.py'), encoding='utf-8').read()
pinr2 = open(os.path.join(HERE, '..', '..', 'firmware', 'releases', 'stage1.3-rc2.sha256')).read().strip()
check(realr2 == 0x125000 and 0x400000 + realr2 - 1 < 0x700000 and "FWR2_SHA = '%s'" % pinr2 in srcr2 and pinr2 == '82500ce2a2531271573489c9080d7372e0ee97c330e44cbb85f2f3a2040da461',
      'RC2 write plan with the real files: address 0x400000, %d B (0x%X), last byte 0x%06X — inside app1; tool pinned to 82500ce2… (same as releases/)' % (realr2, realr2, 0x400000 + realr2 - 1))
print('reinstall simulation: %d failures' % len(FAILS))
sys.exit(1 if FAILS else 0)
