#!/usr/bin/env python3
"""Factory-preserving installation plan for the Cyclift watch (Stage 2a analysis — NOTHING here talks to the watch).

Pure file operations on 8 MB flash images:
  * build the proposed partition table from the factory one (factory entries kept byte-for-byte, only the factory
    settings partition is relabelled `nvs` -> `nvs_fac`; three Cyclift entries appended in the empty upper 4 MB);
  * build the OTA-data record that selects the new slot;
  * optionally patch the factory bootloader's flash-size field (4 MB -> 8 MB) and its appended SHA-256;
  * apply the plan to a copy of an image, list exactly which 4 KB sectors differ, and roll back from the original.

Used offline on the owner's PC against the private backup, and in CI against synthetic / emulated images.
"""
import hashlib
import struct
import zlib

FLASH = 0x800000
SECTOR = 0x1000
BL_OFF, PT_OFF, PT_LEN = 0x1000, 0x8000, 0xC00
OTADATA_OFF = 0xE000

# Cyclift partitions appended in the never-used upper 4 MB (name, type, subtype, offset, size)
CYCLIFT_PARTS = [
    ("app1", 0x00, 0x11, 0x400000, 0x300000),     # ota_1: Cyclift firmware (3 MB; v3poc 0.98 MB, full app 2.27 MB)
    ("nvs", 0x01, 0x02, 0x700000, 0x6000),        # Cyclift settings / Bluetooth bonds (24 KB)
    ("littlefs", 0x01, 0x82, 0x706000, 0xFA000),  # Cyclift files (1000 KB) -> ends exactly at 8 MB
]
FACTORY_NVS_NEW_LABEL = "nvs_fac"


def image_len(data, off=0):
    """Length of the ESP image starting at `off` (incl. checksum and appended SHA-256)."""
    if data[off] != 0xE9:
        raise ValueError("no ESP image at 0x%x" % off)
    n, pos = data[off + 1], off + 24
    for _ in range(n):
        ln = struct.unpack("<I", data[pos + 4:pos + 8])[0]
        pos += 8 + ln
    pos += 15 - ((pos - off) % 16) + 1
    if data[off + 23] == 1:
        pos += 32
    return pos - off


def patch_flash_size(img, size_code):
    """Return a copy of bootloader image `img` with the flash-size nibble set (3 = 8 MB) and the SHA-256 recomputed."""
    img = bytearray(img)
    img[3] = (size_code << 4) | (img[3] & 0x0F)
    if img[23] == 1:
        n = len(img) - 32
        img[n:] = hashlib.sha256(bytes(img[:n])).digest()
    return bytes(img)


def normalized_bootloader_sha(img):
    """Hash of a bootloader ignoring the flash mode/size/speed bytes and the appended hash (which esptool patches)."""
    body = img[:2] + b"\0\0" + img[4:len(img) - (32 if img[23] == 1 else 0)]
    return hashlib.sha256(body).hexdigest()


def parse_pt(pt):
    out = []
    for i in range(0, len(pt), 32):
        e = pt[i:i + 32]
        if e[:2] != b"\xaa\x50":
            break
        off, size = struct.unpack("<II", e[4:12])
        out.append(dict(raw=bytes(e), label=e[12:28].split(b"\0")[0].decode(), type=e[2], subtype=e[3], offset=off, size=size))
    return out


def entry(label, t, st, off, size, flags=0):
    return b"\xaa\x50" + bytes([t, st]) + struct.pack("<II", off, size) + label.encode().ljust(16, b"\0") + struct.pack("<I", flags)


def build_pt(entries_raw):
    body = b"".join(entries_raw)
    t = body + b"\xeb\xeb" + b"\xff" * 14 + hashlib.md5(body).digest()
    return t + b"\xff" * (PT_LEN - len(t))


def proposed_pt(factory_pt):
    """Factory entries kept byte-for-byte (only `nvs` relabelled), then the Cyclift entries."""
    raw = []
    for p in parse_pt(factory_pt):
        e = bytearray(p["raw"])
        if p["label"] == "nvs":
            e[12:28] = FACTORY_NVS_NEW_LABEL.encode().ljust(16, b"\0")
        raw.append(bytes(e))
    raw += [entry(*c) for c in CYCLIFT_PARTS]
    return build_pt(raw)


def check_layout(pt):
    """Problems with a partition table: overlap, alignment, beyond 8 MB, duplicate labels, ota slots, nvs size."""
    parts, probs = parse_pt(pt), []
    seen, last_end = set(), PT_OFF + SECTOR
    for p in sorted(parts, key=lambda p: p["offset"]):
        if p["label"] in seen:
            probs.append("duplicate label " + p["label"])
        seen.add(p["label"])
        align = 0x10000 if p["type"] == 0 else SECTOR
        if p["offset"] % align or p["size"] % SECTOR:
            probs.append("%s not aligned (offset 0x%x, size 0x%x)" % (p["label"], p["offset"], p["size"]))
        if p["offset"] < last_end:
            probs.append("%s overlaps (0x%x < 0x%x)" % (p["label"], p["offset"], last_end))
        if p["offset"] + p["size"] > FLASH:
            probs.append("%s beyond 8 MB" % p["label"])
        if p["type"] == 1 and p["subtype"] == 2 and p["size"] < 0x3000:
            probs.append("%s NVS smaller than 3 pages" % p["label"])
        last_end = p["offset"] + p["size"]
    if [p["label"] for p in parts].count("nvs") != 1:
        probs.append("exactly one partition must be labelled nvs")
    ota = sorted(p["subtype"] for p in parts if p["type"] == 0 and 0x10 <= p["subtype"] < 0x20)
    if ota != list(range(0x10, 0x10 + len(ota))):
        probs.append("OTA app slots not consecutive from ota_0: %s" % ota)
    stored = pt[len(parts) * 32:len(parts) * 32 + 32]
    if stored[:2] != b"\xeb\xeb" or stored[16:32] != hashlib.md5(pt[:len(parts) * 32]).digest():
        probs.append("partition table MD5 missing or wrong")
    return probs


def ota_entry(seq, state=0xFFFFFFFF):
    """One OTA-data record (ESP-IDF esp_ota_select_entry_t): seq, 20-byte label, state, CRC32(seq)."""
    s = struct.pack("<I", seq)
    return s + b"\xff" * 20 + struct.pack("<I", state) + struct.pack("<I", zlib.crc32(s, 0xFFFFFFFF))


def ota_seq(image, sector_index):
    q = OTADATA_OFF + sector_index * SECTOR
    seq, crc = struct.unpack("<I", image[q:q + 4])[0], struct.unpack("<I", image[q + 28:q + 32])[0]
    valid = seq != 0xFFFFFFFF and zlib.crc32(image[q:q + 4], 0xFFFFFFFF) == crc
    return seq, valid


def selected_slot(image, n_ota):
    """Which OTA slot an ESP-IDF bootloader would pick from the two OTA-data sectors (None = no valid record)."""
    seqs = [s for s, ok in (ota_seq(image, 0), ota_seq(image, 1)) if ok]
    return None if not seqs else (max(seqs) - 1) % n_ota


def apply_plan(original, app_image, patch_bootloader=True):
    """Return (new_image, notes). Writes only: bootloader size field (+hash), partition table, the OTA-data sector holding
    the LOWER sequence number, and the Cyclift app in app1. Everything else is copied unchanged."""
    img = bytearray(original)
    notes = []
    if patch_bootloader:
        n = image_len(img, BL_OFF)
        img[BL_OFF:BL_OFF + n] = patch_flash_size(bytes(img[BL_OFF:BL_OFF + n]), 3)
        notes.append("bootloader flash-size field -> 8 MB, appended SHA-256 recomputed (%d B image)" % n)
    pt = proposed_pt(bytes(original[PT_OFF:PT_OFF + PT_LEN]))
    img[PT_OFF:PT_OFF + PT_LEN] = pt
    (s0, v0), (s1, v1) = ota_seq(original, 0), ota_seq(original, 1)
    cur = max([s for s, v in ((s0, v0), (s1, v1)) if v] or [0])
    new_seq = cur + 1 if (cur % 2) == 1 else cur + 2          # (seq-1) % 2 == 1  -> ota_1
    target = 1 if (not v1 or (v0 and s1 <= s0)) else 0          # overwrite the older record, keep the current one
    q = OTADATA_OFF + target * SECTOR
    img[q:q + SECTOR] = ota_entry(new_seq) + b"\xff" * (SECTOR - 32)
    notes.append("OTA-data sector %d (0x%x) -> seq %d (selects ota_1); other sector unchanged" % (target, q, new_seq))
    app1 = CYCLIFT_PARTS[0]
    if len(app_image) > app1[4]:
        raise ValueError("app does not fit app1")
    img[app1[3]:app1[3] + len(app_image)] = app_image
    return bytes(img), notes


def changed_sectors(a, b):
    return [o for o in range(0, len(a), SECTOR) if a[o:o + SECTOR] != b[o:o + SECTOR]]


def rollback(current, original, sectors):
    img = bytearray(current)
    for o in sectors:
        img[o:o + SECTOR] = original[o:o + SECTOR]
    return bytes(img)


def ranges(sectors):
    out, start, prev = [], None, None
    for s in sectors:
        if start is None:
            start = prev = s
        elif s == prev + SECTOR:
            prev = s
        else:
            out.append((start, prev + SECTOR))
            start = prev = s
    if start is not None:
        out.append((start, prev + SECTOR))
    return out
