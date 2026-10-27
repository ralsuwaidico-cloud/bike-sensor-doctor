BikeComputer firmware 0.7.4-rc1 - READ ME FIRST (27 Oct 2026)
==============================================================
What it is: the fix for the 0.7.3 start-up crash. On your board 0.7.3 stopped every start when Bluetooth could not start
("hci inits failed" -> abort -> RECOVERY). 0.7.4-rc1:
- never stops because of Bluetooth: if it cannot start, the board keeps running and says "Bluetooth unavailable" and why;
  after 2 such starts in a row Bluetooth is switched off until you tap RETRY (Settings > Phone), so there is no loop;
- starts Bluetooth earlier (before the screens take their memory, as 0.7.2 did) and records, step by step, what the
  Bluetooth start needed and got (memory figures) - in the settings area (NVS), so it survives a restart even though
  the file area is damaged;
- shows the REAL storage problem: on your board the file area's directory is damaged ("dir corrupted"), it is not full.
  The firmware never formats or writes into the damaged file area; repairing it is a separate step you approve later.
App checksum (SHA-256): 30f8f37c7bf67c3d30c2534a5666065fc15321ddbdf535fb7eaa5b509d6ba02e (1841232 bytes).
Nothing here has run on your board yet: it is tested on the PC only until you do TEST-v0.7.4.txt.

INSTALL (about 6 minutes)
1  Board on USB, battery unplugged. Close any other program that uses the board's port.
2  Double-click INSTALL-v0.7.4.bat. It checks every file, finds the board, reads a COMPLETE backup (16 MB, ~3 minutes) to
   backup-before-v074-<date-time>.bin and checks that backup before anything is written.
3  Type YES. Only the firmware (0x20000) and the start selector (0xf000) are written. Settings, sensor pairings, phone
   pairing and the file area are NOT written or erased. The partition table is NOT changed (your board already has the
   0.7.3 table; only a board still on the pre-0.7.3 table gets the same documented 0.7.3 change).
4  The board restarts; the window watches 90 seconds and prints RESULT (BOOTED OK + Bluetooth started / unavailable).
5  Then TEST-v0.7.4.txt.

GOING BACK
- RESTORE-CHOSEN-BACKUP.bat: puts back the whole board exactly as in a backup you pick (newest backup-before-v074 = as it
  was a minute before the install). Safest way back.
- ROLLBACK-TO-v073.bat / ROLLBACK-TO-v072.bat: firmware only, settings kept. Note: on your board BOTH crashed (0.7.3 at
  every start, 0.7.2 while connecting) - use them only if Claude asks. ROLLBACK-TO-v071.bat (from the 0.7.3 kit) also works.
- If a write is interrupted (USB unplugged): RESTORE-CHOSEN-BACKUP.bat with the backup just made. If the port does not
  appear, hold BOOT while plugging the USB cable in. The board's start-up code is never written.

FILES (keep together in your BikeComputer folder; esptool.exe and factory_backup_16MB.bin are already there)
INSTALL-v0.7.4.bat/.ps1, fw-v0.7.4\ (4 .bin + SHA256SUMS.txt), ROLLBACK-TO-v073.bat/.ps1 + fw-v0.7.3\,
ROLLBACK-TO-v072.bat/.ps1 + fw-v0.7.2\, RESTORE-CHOSEN-BACKUP.bat/.ps1, READ-BOARD-STATE.bat/.ps1 (read-only evidence
capture - only when Claude asks), CAPTURE-CRASH.bat/.ps1, TEST-v0.7.4.txt, this README, KIT-SHA256SUMS.txt.
