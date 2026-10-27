#!/usr/bin/env python3
# Usage: python3 -I tools/storage_audit.py <full-16MB-backup.bin> <label>   (read-only; prints JSON; file names, sizes and dates only,
# never file contents). Used for docs/FW_STORAGE_MEMORY_REPORT.md. Needs nothing but the Python standard library.
"""Read-only audit of a BikeComputer full-flash backup: partition table, WL state, de-WL'd FAT12, directory tree,
raw scan for directory-like sectors. Prints no personal data (file names only; no file contents)."""
import struct, sys, zlib, hashlib, json

SS = 4096


def crc_wl(b):
    # ESP-IDF WL: crc32_le(UINT32_MAX, data) (ROM crc32_le == ~zlib.crc32 variants); try both and report which matched
    return [zlib.crc32(b) , zlib.crc32(b, 0xFFFFFFFF) ^ 0xFFFFFFFF, (~zlib.crc32(b)) & 0xFFFFFFFF, zlib.crc32(b, 0xFFFFFFFF)]


def parts(img):
    d = img[0x8000:0x9000]
    out = []
    for i in range(0, 0xC00, 32):
        e = d[i:i + 32]
        if e[:2] != b'\xaa\x50':
            break
        off, sz = struct.unpack('<II', e[4:12])
        out.append(dict(name=e[12:28].rstrip(b'\0').decode(), type=e[2], sub=e[3], off=off, size=sz))
    return out


def wl_state(st):
    n = len(st) // SS
    cfg = st[-SS:]
    c = struct.unpack('<8I', cfg[:32])
    cfg_crc = struct.unpack('<I', cfg[32:36])[0]
    state_size = ((64 + 16 * n) + SS - 1) // SS * SS
    a1 = len(st) - SS - 2 * state_size
    a2 = a1 + state_size
    res = {}
    for k, a in (('s1', a1), ('s2', a2)):
        h = st[a:a + 64]
        f = struct.unpack('<8I', h[:32])
        crc = struct.unpack('<I', h[60:64])[0]
        recs = 0
        for i in range(n):
            r = st[a + 64 + 16 * i:a + 80 + 16 * i]
            if r == b'\xff' * 16:
                break
            recs += 1
        res[k] = dict(pos_hdr=f[0], max_pos=f[1], move_count=f[2], access_count=f[3], max_count=f[4], block_size=f[5],
                      version=f[6], crc_ok=crc in crc_wl(h[:60]), records=recs)
    res['cfg'] = dict(start=c[0], full=c[1], page=c[2], sector=c[3], updaterate=c[4], wr=c[5], version=c[6], tmp=c[7],
                      crc_ok=cfg_crc in crc_wl(cfg[:32]))
    res['state_size'] = state_size
    res['n_logical'] = (len(st) - SS - 2 * state_size) // SS - 1
    return res


def dewl(st, w, which='s1'):
    n_phys = w['n_logical'] + 1
    data = st[:n_phys * SS]
    pos = w[which]['records']
    mc = w[which]['move_count']
    nod = data[:pos * SS] + data[(pos + 1) * SS:]
    N = w['n_logical']
    mc %= N
    log = nod[-mc * SS:] + nod[:-mc * SS] if mc else nod
    return log, pos, mc


def phys_of_logical(a, pos, mc, N):
    r = (a - mc) % N
    return r if r < pos else r + 1


def fat_info(fs):
    bs = fs[:512]
    bps, spc, rsv, nfat, rootent, tot16, media, fatsz = struct.unpack('<HBHBHHBH', bs[11:24])
    tot32 = struct.unpack('<I', bs[32:36])[0]
    tot = tot16 or tot32
    rootsecs = (rootent * 32 + bps - 1) // bps
    first_data = rsv + nfat * fatsz + rootsecs
    clusters = (tot - first_data) // spc
    return dict(bps=bps, spc=spc, rsv=rsv, nfat=nfat, rootent=rootent, tot=tot, fatsz=fatsz, rootsecs=rootsecs,
                first_data=first_data, clusters=clusters, sig=bs[510:512] == b'\x55\xaa', oem=bs[3:11].decode('latin1'),
                fstype=bs[54:62].decode('latin1').strip(), label=bs[43:54].decode('latin1').strip())


def fat12(fat, n):
    out = []
    for c in range(n + 2):
        o = c * 3 // 2
        v = fat[o] | (fat[o + 1] << 8)
        out.append(v >> 4 if c & 1 else v & 0xFFF)
    return out


def dirents(buf):
    out = []
    lfn = []
    for i in range(0, len(buf), 32):
        e = buf[i:i + 32]
        b0 = e[0]
        if b0 == 0:
            out.append(('END', i // 32))
            break
        if b0 == 0xE5:
            out.append(('DEL', e[:11]))
            lfn = []
            continue
        attr = e[11]
        if attr == 0x0F:
            lfn.append(e)
            continue
        if b0 == 0xFF and e[:11] == b'\xff' * 11:
            out.append(('FF', None))
            continue
        name = e[:8].decode('latin1').rstrip() + ('.' + e[8:11].decode('latin1').rstrip() if e[8:11].strip() else '')
        size = struct.unpack('<I', e[28:32])[0]
        clus = struct.unpack('<H', e[26:28])[0]
        wdate, wtime = struct.unpack('<HH', e[24:26] + e[22:24])
        long = ''
        if lfn:
            parts_ = []
            for le in reversed(lfn):
                s = le[1:11] + le[14:26] + le[28:32]
                parts_.append(s.decode('utf-16le', 'replace').split('\x00')[0].replace('￿', ''))
            long = ''.join(parts_)
        lfn = []
        out.append(('ENT', dict(name=long or name, attr=attr, size=size, clus=clus,
                               date='%04d-%02d-%02d %02d:%02d' % (1980 + (wdate >> 9), (wdate >> 5) & 15, wdate & 31, wtime >> 11, (wtime >> 5) & 63))))
    return out


def looks_like_dir_sector(sec):
    # at least 2 plausible 8.3 entries (printable upper-case name, attr in {0x10,0x20,0x01,0x08}) or '.' + '..'
    good = 0
    for i in range(0, SS, 32):
        e = sec[i:i + 32]
        if e[0] in (0, 0xFF):
            continue
        nm = e[:11]
        if all((0x20 <= ch < 0x7F and not (0x61 <= ch <= 0x7A)) or ch == 0xE5 for ch in nm) and e[11] in (0x10, 0x20, 0x08, 0x01, 0x21, 0x30):
            good += 1
        elif e[11] == 0x0F and e[12] == 0 and e[26:28] == b'\0\0':
            good += 1
    return good


def main(path, label):
    img = open(path, 'rb').read()
    rep = dict(file=label, size=len(img), sha256_16=hashlib.sha256(img).hexdigest()[:16])
    P = parts(img)
    rep['partitions'] = [(p['name'], hex(p['off']), hex(p['size'])) for p in P]
    stp = [p for p in P if p['sub'] == 0x81]
    if not stp:
        print(json.dumps(rep, indent=1)); return
    stp = stp[0]
    st = img[stp['off']:stp['off'] + stp['size']]
    nsec = len(st) // SS
    erased = sum(1 for i in range(nsec) if st[i * SS:(i + 1) * SS] == b'\xff' * SS)
    rep['storage_raw'] = dict(sectors=nsec, erased=erased, with_data=nsec - erased)
    w = wl_state(st)
    rep['wl'] = w
    for which in ('s1', 's2'):
        log, pos, mc = dewl(st, w, which)
        fi = fat_info(log)
        r = dict(pos=pos, move_count=mc, fat=fi)
        if fi['sig'] and fi['bps'] == SS:
            f1 = log[fi['rsv'] * SS:(fi['rsv'] + fi['fatsz']) * SS]
            f2 = log[(fi['rsv'] + fi['fatsz']) * SS:(fi['rsv'] + 2 * fi['fatsz']) * SS] if fi['nfat'] > 1 else f1
            ft = fat12(f1, fi['clusters'])
            free = sum(1 for v in ft[2:] if v == 0)
            eoc = sum(1 for v in ft[2:] if v >= 0xFF8)
            bad = sum(1 for v in ft[2:] if v == 0xFF7)
            used_chain = sum(1 for v in ft[2:] if 2 <= v < 0xFF0)
            r['fat_stats'] = dict(free=free, eoc=eoc, chained=used_chain, bad=bad, fat1_eq_fat2=f1 == f2,
                                  fat0=hex(ft[0]), fat1=hex(ft[1]), free_kb=free * fi['spc'] * SS // 1024,
                                  total_kb=fi['clusters'] * fi['spc'] * SS // 1024)
            rd0 = (fi['rsv'] + fi['nfat'] * fi['fatsz'])
            root = log[rd0 * SS:(rd0 + fi['rootsecs']) * SS]
            rsec = []
            for k in range(fi['rootsecs']):
                s = root[k * SS:(k + 1) * SS]
                rsec.append(dict(logical=rd0 + k, phys=phys_of_logical(rd0 + k, pos, mc, w['n_logical']),
                                 erased=s == b'\xff' * SS, zero=s == b'\0' * SS, first=s[:1].hex()))
            r['root_sectors'] = rsec
            ents = dirents(root)
            r['root_entries'] = dict(FF=sum(1 for e in ents if e[0] == 'FF'), DEL=sum(1 for e in ents if e[0] == 'DEL'),
                                     files=[e[1] for e in ents if e[0] == 'ENT'], end=[e[1] for e in ents if e[0] == 'END'])

            def walk(clus, depth, prefix):
                out = []
                seen = 0
                buf = b''
                c = clus
                while 2 <= c < 0xFF0 and seen < 64:
                    o = (fi['first_data'] + (c - 2) * fi['spc']) * SS
                    buf += log[o:o + fi['spc'] * SS]
                    c = ft[c]
                    seen += 1
                for e in dirents(buf):
                    if e[0] != 'ENT':
                        continue
                    d = e[1]
                    if d['name'] in ('.', '..'):
                        continue
                    out.append(dict(path=prefix + d['name'], size=d['size'], attr=d['attr'], date=d['date']))
                    if d['attr'] & 0x10 and depth < 4:
                        out += walk(d['clus'], depth + 1, prefix + d['name'] + '/')
                return out
            tree = []
            for d in r['root_entries']['files']:
                tree.append(dict(path=d['name'], size=d['size'], attr=d['attr'], date=d['date']))
                if d['attr'] & 0x10:
                    tree += walk(d['clus'], 1, d['name'] + '/')
            r['tree'] = tree
            # orphan directory clusters: data clusters that look like a directory (start with '.' and '..')
            orph = []
            for c in range(2, fi['clusters'] + 2):
                o = (fi['first_data'] + (c - 2) * fi['spc']) * SS
                s = log[o:o + 64]
                if s[:11] == b'.          ' and s[32:43] == b'..         ':
                    ents = [e[1] for e in dirents(log[o:o + SS]) if e[0] == 'ENT' and e[1]['name'] not in ('.', '..')]
                    orph.append(dict(cluster=c, fat=hex(ft[c]), n=len(ents), names=[(e['name'], e['size'], e['date']) for e in ents][:40]))
            r['dir_clusters'] = orph
        rep['dewl_' + which] = r
        if which == 's1' and w['s1']['records'] == w['s2']['records'] and w['s1']['move_count'] == w['s2']['move_count']:
            break
    # raw scan: physical sectors that look like directory sectors
    raw = []
    for i in range(nsec):
        s = st[i * SS:(i + 1) * SS]
        g = looks_like_dir_sector(s)
        if g >= 2:
            raw.append((i, g))
    rep['raw_dir_like_sectors'] = raw[:50]
    print(json.dumps(rep, indent=1, default=str))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
