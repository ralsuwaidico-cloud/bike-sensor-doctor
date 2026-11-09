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
# Flash size is NOT assumed: LILYGO's product page says 4 MB, the repo docs say 8 MB. Read what the chip reports.
SIZE_MB=$(grep -Eo "Detected flash size: [0-9]+MB" "$OUT/flash_id.txt" | grep -Eo "[0-9]+" || true)
if [ -z "$SIZE_MB" ]; then echo "Could not read the flash size; stopping (nothing was written)."; exit 1; fi
BYTES=$(printf '0x%X' $((SIZE_MB * 1024 * 1024)))
echo "2/3 full ${SIZE_MB} MB flash dump → $OUT/factory-${SIZE_MB}mb.bin (read only; a few minutes at 921600)"
esptool.py --port "$PORT" --baud 921600 read_flash 0x0 "$BYTES" "$OUT/factory-${SIZE_MB}mb.bin"
echo "3/3 checksum"
shasum -a 256 "$OUT/factory-${SIZE_MB}mb.bin" | tee "$OUT/SHA256.txt"
echo "Backup complete. Keep this folder off the public repository: chip_id.txt contains the watch's hardware address."
echo "Restore (ONLY with the owner's explicit approval): esptool.py --port $PORT --baud 921600 write_flash 0x0 $OUT/factory-${SIZE_MB}mb.bin"
