#!/usr/bin/env bash
# Cyclift Watch — W0: NON-DESTRUCTIVE full-flash backup of the factory firmware (read only; nothing is written).
# Needs: the LILYGO T-U2T USB-to-serial dongle plugged into the watch's USB-C port, then into the computer (the watch
# has no USB-serial chip of its own — the supplied cable alone only charges), and `pip install esptool`.
# Usage: ./backup_factory_firmware.sh /dev/cu.usbserial-XXXX   (macOS)   or   COM5 (Windows, via python -m esptool)
set -euo pipefail
PORT=${1:?serial port of the T-U2T}
OUT="factory-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
echo "1/3 chip identification (read only)"
esptool.py --port "$PORT" chip_id | tee "$OUT/chip_id.txt"
esptool.py --port "$PORT" flash_id | tee "$OUT/flash_id.txt"
echo "2/3 full 8 MB flash dump → $OUT/factory-8mb.bin (takes ~3 min at 921600)"
esptool.py --port "$PORT" --baud 921600 read_flash 0x0 0x800000 "$OUT/factory-8mb.bin"
echo "3/3 checksum"
shasum -a 256 "$OUT/factory-8mb.bin" | tee "$OUT/SHA256.txt"
echo "Backup complete. Restore (ONLY with the owner's explicit approval): esptool.py --port $PORT --baud 921600 write_flash 0x0 $OUT/factory-8mb.bin"
