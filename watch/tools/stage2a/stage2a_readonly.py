#!/usr/bin/env python3
"""Cyclift Watch — Stage 2a: identify the watch and back up its flash. READ ONLY.

Nothing in this tool can write, erase or reconfigure the watch: every device command goes through `run_device()`, which
accepts only these read-only operations and refuses anything else:
    esptool  --chip esp32 ... flash_id                     chip, features (embedded flash / PSRAM), flash size
    esptool  --chip esp32 ... read_flash <addr> <size> <f> copies flash into a file on the computer
    espefuse --chip esp32 ... summary                      reads the eFuses (flash encryption / secure boot state)
esptool loads a small helper ("stub") into the chip's RAM to read faster; RAM is cleared on reset, flash is untouched.
The watch is reset into its download mode and back; that is a restart, not a write.

    python stage2a_readonly.py identify --port PORT [--out DIR]
        Step 1. Chip, flash size, PSRAM indication, eFuse security state, the current partition table and the
        firmware descriptions found in it. Writes DIR/identification.json. The watch's hardware address is kept in the
        local file only and is never printed in the summary.
    python stage2a_readonly.py backup --port PORT --flash-mb N --confirm "READ ONLY BACKUP" [--out DIR]
        Step 2 (only after step 1 and the owner's approval). N must equal the size found in step 1 — no size is assumed.
        Reads the whole flash twice and keeps the copy only if both reads are identical (SHA-256).
    python stage2a_readonly.py inspect FILE.bin [--flash-mb N]
        Offline: checks a backup file (size, bootloader, partition table, firmware descriptions). No watch needed.

Requirements on the computer: Python 3.9+, `pip install esptool==4.8.1 "bitstring<4.3"`, the T-U2T (CH9102) driver if
the operating system does not have it. Keep the output folder out of the public repository.
"""
import argparse, hashlib, json, os, re, struct, subprocess, sys, time

SAFE = {('esptool', 'flash_id'), ('esptool', 'read_flash'), ('espefuse', 'summary')}
PT_OFFSET, PT_SIZE = 0x8000, 0xC00
CONFIRM = 'READ ONLY BACKUP'


class Refused(Exception):
    pass


# ------------------------------------------------------------------------------------------------ device access (guarded)
def run_device(tool, command, port, args=(), runner=subprocess.run):
    """The only path to the watch. Refuses every operation that is not read-only."""
    if (tool, command) not in SAFE:
        raise Refused(f'{tool} {command} is not a read-only operation; this tool will not run it')
    for a in args:
        if str(a).startswith('-') and str(a) not in ('--no-progress',):
            raise Refused(f'option {a} is not allowed')
    cmd = [sys.executable, '-m', tool, '--chip', 'esp32', '--port', port]
    if tool == 'esptool':
        cmd += ['--before', 'default_reset', '--after', 'hard_reset']
    cmd += [command, *map(str, args)]
    res = runner(cmd, capture_output=True, text=True)
    out = (res.stdout or '') + (res.stderr or '')
    if res.returncode != 0:
        raise RuntimeError(f'{tool} {command} failed (exit {res.returncode}):\n{out[-2000:]}')
    return out


# ------------------------------------------------------------------------------------------------ parsing
def parse_flash_id(text):
    """Parses esptool 4.x `flash_id` output."""
    g = lambda pat: (re.search(pat, text) or [None, None])[1]
    feats = g(r'Features:\s*(.+)') or ''
    size = g(r'Detected flash size:\s*(\d+)\s*MB')
    return {
        'chip': g(r'Chip is (.+)'),
        'features': [f.strip() for f in feats.split(',') if f.strip()],
        'embedded_psram': 'Embedded PSRAM' in feats,
        'embedded_flash': 'Embedded Flash' in feats,
        'crystal': g(r'Crystal is (\S+)'),
        'flash_manufacturer': g(r'Manufacturer:\s*(\w+)'),
        'flash_device': g(r'Device:\s*(\w+)'),
        'flash_mb': int(size) if size else None,
        'mac_private': g(r'MAC:\s*([0-9a-fA-F:]{17})'),
    }


def parse_efuse_summary(text):
    cnt = re.search(r'FLASH_CRYPT_CNT\b.*?=\s*(\d+)', text)
    sb = re.search(r'ABS_DONE_0\b.*?=\s*(True|False)', text)
    c = int(cnt.group(1)) if cnt else None
    return {
        'flash_crypt_cnt': c,
        'flash_encryption_enabled': (bin(c).count('1') % 2 == 1) if c is not None else None,
        'secure_boot_v1_enabled': (sb.group(1) == 'True') if sb else None,
    }


TYPES = {0: 'app', 1: 'data'}
APP_SUB = {0x00: 'factory', 0x20: 'test', **{0x10 + i: f'ota_{i}' for i in range(16)}}
DATA_SUB = {0x00: 'ota', 0x01: 'phy', 0x02: 'nvs', 0x03: 'coredump', 0x04: 'nvs_keys', 0x05: 'efuse', 0x80: 'esphttpd', 0x81: 'fat', 0x82: 'spiffs', 0x83: 'littlefs'}


def parse_partition_table(blob):
    """ESP-IDF partition table: 32-byte entries (magic 0xAA50), optional MD5 entry (0xEBEB), 0xFF padding."""
    parts, md5_ok = [], None
    for i in range(0, len(blob) - 31, 32):
        e = blob[i:i + 32]
        magic = struct.unpack_from('<H', e)[0]
        if magic == 0xAA50:
            t, st, off, size = e[2], e[3], *struct.unpack_from('<II', e, 4)
            label = e[12:28].split(b'\0')[0].decode('ascii', 'replace')
            sub = APP_SUB.get(st) if t == 0 else DATA_SUB.get(st)
            parts.append({'label': label, 'type': TYPES.get(t, hex(t)), 'subtype': sub or hex(st), 'offset': off, 'size': size})
        elif magic == 0xEBEB:
            md5_ok = hashlib.md5(blob[:i]).digest() == e[16:32]
            break
        elif e == b'\xff' * 32:
            break
        else:
            return {'valid': False, 'partitions': parts, 'md5_ok': None, 'error': f'unexpected entry at +0x{i:X}'}
    return {'valid': bool(parts), 'partitions': parts, 'md5_ok': md5_ok}


def parse_app_desc(img):
    """App image: 0xE9 header (24 bytes) + first segment header (8 bytes) + esp_app_desc_t (magic 0xABCD5432)."""
    if len(img) < 0x20 + 256 or img[0] != 0xE9:
        return None
    d = img[0x20:0x20 + 256]
    if struct.unpack_from('<I', d)[0] != 0xABCD5432:
        return {'image': True, 'descriptor': False}
    s = lambda a, n: d[a:a + n].split(b'\0')[0].decode('utf-8', 'replace')
    return {'image': True, 'descriptor': True, 'version': s(16, 32), 'project': s(48, 32), 'time': s(80, 16), 'date': s(96, 16), 'idf': s(112, 32)}


def inspect_bytes(data, flash_mb=None):
    rep = {'size_bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    rep['size_matches'] = (flash_mb is None) or len(data) == flash_mb * 1024 * 1024
    rep['bootloader_at_0x1000'] = len(data) > 0x1000 and data[0x1000] == 0xE9
    rep['blank'] = data.count(0xFF) == len(data)
    pt = parse_partition_table(data[PT_OFFSET:PT_OFFSET + PT_SIZE]) if len(data) >= PT_OFFSET + PT_SIZE else {'valid': False, 'partitions': []}
    rep['partition_table'] = pt
    apps = []
    for p in pt.get('partitions', []):
        if p['type'] == 'app' and p['offset'] + 0x200 <= len(data):
            apps.append({'label': p['label'], **(parse_app_desc(data[p['offset']:p['offset'] + 0x200]) or {'image': False})})
    rep['apps'] = apps
    end = max((p['offset'] + p['size'] for p in pt.get('partitions', [])), default=0)
    rep['partitions_fit_in_file'] = end <= len(data)
    return rep


# ------------------------------------------------------------------------------------------------ commands
def summary_lines(ident):
    f = ident['flash']; e = ident.get('efuse', {})
    yield f"Chip:              {f['chip']}"
    yield f"Flash size:        {f['flash_mb']} MB (manufacturer {f['flash_manufacturer']}, device {f['flash_device']})"
    yield f"PSRAM:             {'embedded PSRAM reported by the chip' if f['embedded_psram'] else 'not reported by the chip (an external PSRAM would show only at start-up)'}"
    yield f"Flash encryption:  {'ON — a backup is only restorable to this same watch' if e.get('flash_encryption_enabled') else 'off' if e.get('flash_encryption_enabled') is False else 'unknown'}"
    yield f"Secure boot (v1):  {'ON' if e.get('secure_boot_v1_enabled') else 'off' if e.get('secure_boot_v1_enabled') is False else 'unknown'}"
    pt = ident.get('partition_table', {})
    yield f"Partition table:   {'found' if pt.get('valid') else 'not found'}" + (f", {len(pt['partitions'])} partitions" if pt.get('valid') else '')
    for p in pt.get('partitions', []):
        yield f"  {p['label']:<10} {p['type']:<4} {p['subtype']:<8} 0x{p['offset']:06X}  {p['size'] // 1024} KB"
    for a in ident.get('apps', []):
        yield f"  firmware in {a['label']}: " + (f"{a.get('project')} {a.get('version')} built {a.get('date')} {a.get('time')} (IDF {a.get('idf')})" if a.get('descriptor') else 'image without description' if a.get('image') else 'empty')
    yield "Hardware address:  stored in the local identification.json only"


def cmd_identify(a, runner=subprocess.run):
    os.makedirs(a.out, exist_ok=True)
    ident = {'tool': 'stage2a_readonly.py', 'time': time.strftime('%Y-%m-%d %H:%M:%S'), 'port': a.port}
    raw = run_device('esptool', 'flash_id', a.port, runner=runner)
    ident['flash'] = parse_flash_id(raw)
    if not ident['flash']['flash_mb'] or not ident['flash']['chip']:
        raise RuntimeError('esptool did not report the chip or the flash size; stop and check the connection')
    ident['efuse'] = parse_efuse_summary(run_device('espefuse', 'summary', a.port, runner=runner))
    pt_file = os.path.join(a.out, 'partition-table.bin')
    run_device('esptool', 'read_flash', a.port, [hex(PT_OFFSET), hex(PT_SIZE), pt_file], runner=runner)
    with open(pt_file, 'rb') as fh:
        ident['partition_table'] = parse_partition_table(fh.read())
    ident['apps'] = []
    for p in ident['partition_table'].get('partitions', []):
        if p['type'] == 'app':
            f = os.path.join(a.out, f"app-header-{p['label']}.bin")
            run_device('esptool', 'read_flash', a.port, [hex(p['offset']), '0x200', f], runner=runner)
            with open(f, 'rb') as fh:
                ident['apps'].append({'label': p['label'], **(parse_app_desc(fh.read()) or {'image': False})})
    with open(os.path.join(a.out, 'identification.json'), 'w') as fh:
        json.dump(ident, fh, indent=1)
    print('\n'.join(summary_lines(ident)))
    print(f"\nSaved: {os.path.join(a.out, 'identification.json')}. Nothing was written to the watch.")
    return ident


def cmd_backup(a, runner=subprocess.run):
    if a.confirm != CONFIRM:
        raise Refused(f'type --confirm "{CONFIRM}" to start the read-only backup')
    idf = os.path.join(a.out, 'identification.json')
    if not os.path.exists(idf):
        raise Refused('run "identify" first: the flash size must come from the watch, not from a document')
    ident = json.load(open(idf))
    if ident['flash']['flash_mb'] != a.flash_mb:
        raise Refused(f"--flash-mb {a.flash_mb} does not match the {ident['flash']['flash_mb']} MB the watch reported")
    size = a.flash_mb * 1024 * 1024
    files = [os.path.join(a.out, f'flash-read-{k}.bin') for k in (1, 2)]
    for f in files:
        print(f'Reading {a.flash_mb} MB (read only) → {f}')
        run_device('esptool', 'read_flash', a.port, ['0x0', hex(size), f], runner=runner)
    h = [hashlib.sha256(open(f, 'rb').read()).hexdigest() for f in files]
    if h[0] != h[1]:
        raise RuntimeError(f'the two reads differ ({h[0][:12]} vs {h[1][:12]}); keep both files, do not continue, report this')
    final = os.path.join(a.out, f'factory-{a.flash_mb}mb.bin')
    os.replace(files[0], final); os.remove(files[1])
    rep = inspect_bytes(open(final, 'rb').read(), a.flash_mb)
    with open(final + '.sha256', 'w') as fh:
        fh.write(f"{rep['sha256']}  {os.path.basename(final)}\n")
    with open(os.path.join(a.out, 'backup-report.json'), 'w') as fh:
        json.dump(rep, fh, indent=1)
    ok = rep['size_matches'] and rep['bootloader_at_0x1000'] and rep['partition_table']['valid'] and not rep['blank'] and rep['partitions_fit_in_file']
    print(f"Two reads identical. SHA-256 {rep['sha256']}")
    print('Backup checks:', 'PASSED' if ok else 'FAILED — do not continue to Stage 2b', json.dumps({k: rep[k] for k in ('size_matches', 'bootloader_at_0x1000', 'blank', 'partitions_fit_in_file')}))
    return rep, ok


def cmd_inspect(a):
    rep = inspect_bytes(open(a.file, 'rb').read(), a.flash_mb)
    print(json.dumps(rep, indent=1))
    return rep


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = p.add_subparsers(dest='cmd', required=True)
    i = sp.add_parser('identify'); i.add_argument('--port', required=True); i.add_argument('--out', default='cyclift-watch-stage2a')
    b = sp.add_parser('backup'); b.add_argument('--port', required=True); b.add_argument('--flash-mb', type=int, required=True)
    b.add_argument('--confirm', default=''); b.add_argument('--out', default='cyclift-watch-stage2a')
    n = sp.add_parser('inspect'); n.add_argument('file'); n.add_argument('--flash-mb', type=int)
    a = p.parse_args(argv)
    try:
        if a.cmd == 'identify': cmd_identify(a)
        elif a.cmd == 'backup': return 0 if cmd_backup(a)[1] else 2
        else: cmd_inspect(a)
    except Refused as e:
        print('REFUSED:', e); return 3
    return 0


if __name__ == '__main__':
    sys.exit(main())
