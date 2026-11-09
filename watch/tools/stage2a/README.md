# Stage 2a — hardware identification and read-only backup

`stage2a_readonly.py` is the only tool used to talk to the watch in Stage 2a. It can run three read-only operations
(`esptool flash_id`, `esptool read_flash`, `espefuse summary`) and refuses everything else (write, erase, eFuse burning,
loading code). The full procedure, approval points and expected outputs are in the Stage 2a Hardware Identification and
Backup Readiness Report (CYCLIFT project).

1. `identify --port PORT` — chip, real flash size, PSRAM indication, flash-encryption state, partition table, firmware
   descriptions. Nothing else runs until its result is reviewed.
2. `backup --port PORT --flash-mb N --confirm "READ ONLY BACKUP"` — only after the owner approves; N must equal the
   size from step 1. Two full reads must be byte-identical (SHA-256) or the backup is rejected.
3. `inspect factory-Nmb.bin --flash-mb N` — offline check of a backup file.

Setup: Python 3.9+, `pip install esptool==4.8.1 "bitstring<4.3"`. Output folders contain the watch's hardware
address: keep them out of this public repository. Tests: `python3 test_stage2a.py` (simulated watch, no hardware).
