BikeComputer firmware 0.7.4-rc2 - READ ME FIRST (27 Oct 2026)
==============================================================
What it is: the fix for the 0.7.3 start-up crash, second release candidate (rc1 was reviewed by QA and never installed).
On your board 0.7.3 stopped every start when Bluetooth could not start ("hci inits failed" -> abort -> RECOVERY).
0.7.4-rc2:
- never stops because of Bluetooth: if it cannot start, the board keeps running and says "Bluetooth unavailable" and why;
  after 2 such starts in a row Bluetooth is switched off until you tap RETRY (Settings > Phone), so there is no loop;
- records, step by step, what the Bluetooth start needed and got (memory figures) in the settings area (NVS); the last
  real Bluetooth start is kept there even after many restarts. The installer also records the very first start of the
  new firmware on the PC (first-boot-v0.7.4-rc2-*.txt) - that file is the main evidence for the cause; please send it;
- shows the REAL storage problem: on your board the file area's directory is damaged ("dir corrupted"), it is not full.
  The firmware never formats, erases or writes into the damaged file area, and never erases the settings area on its
  own; repairing either is a separate step you approve later.
App checksum (SHA-256): a495bfde97986f2ba207d50ab92ea8bc1fa75fa45935a5513f23f73ed55ee9d9 (1846752 bytes).
Nothing here has run on your board yet: it is tested on the PC only (simulator + unit tests) until you do TEST-v0.7.4-rc2.txt.
It is NOT claimed to be fixed until your board shows it.

IMPORTANT ON YOUR BOARD (until the file area is repaired)
- Rides recorded on the board are NOT saved on the board. rc2 says so on the screen: a red line on the ride result
  ("Board storage damaged: this ride is kept in memory until power-off only") and, after SAVE, "NOT SAVED ON BOARD".
  The ride stays in the board's memory (up to 4 rides) until it is switched off or restarted; open Cyclift while the
  board is on to try to copy it. Do not rely on board-recorded rides until the repair.
- Bluetooth: if it cannot start, the Phone screen shows "NO BLUETOOTH" with WHY? (the reason). After the second failed
  start in a row it is switched off and the Phone screen shows RETRY (tap it, then restart, to try again).
- If the settings area itself ever reports a problem, the board shows "Settings memory needs repair" and keeps running
  on default settings without saving anything. Nothing is erased; tell Claude.

INSTALL (about 6 minutes)
1  Board on USB, battery unplugged. Close any other program that uses the board's port.
2  Double-click INSTALL-v0.7.4-rc2.bat. It checks every file, finds the board, reads a COMPLETE backup (16 MB, ~3 minutes)
   to backup-before-v074-<date-time>.bin and checks that backup before anything is written. From the backup until the end
   the board is held in download mode (dark screen): the old firmware does not run again.
3  Type YES. Only the firmware (0x20000) and the start selector (0xf000) are written. Settings, sensor pairings, phone
   pairing and the file area are NOT written or erased. The partition table is NOT changed (your board already has the
   0.7.3 table).
4  The window then starts the board itself and records its first 90 seconds (first-boot-v0.7.4-rc2-<date-time>.txt),
   and prints RESULT (BOOTED OK + Bluetooth started / unavailable + whether the Bluetooth start figures were recorded).
   If you type anything other than YES, or the script stops after the backup, unplug and replug the USB cable to start
   the board again (it waits in download mode).
5  Then TEST-v0.7.4-rc2.txt. Send first-boot-*.txt and install-*.txt to Claude in any case.

GOING BACK
- RESTORE-CHOSEN-BACKUP.bat: puts back the whole board exactly as in a backup you pick (the newest backup-before-v074 =
  as it was a minute before the install). This is THE way back.
- ROLLBACK-TO-v073.bat / ROLLBACK-TO-v072.bat: do NOT use them unless Claude asks. On your board 0.7.3 stops at every
  start and 0.7.2 crashed while connecting; the 0.7.3 script now warns about this on screen.
- If a write is interrupted (USB unplugged): RESTORE-CHOSEN-BACKUP.bat with the backup just made. If the port does not
  appear, hold BOOT while plugging the USB cable in. The board's start-up code is never written.

FILES (keep together in your BikeComputer folder; esptool.exe and factory_backup_16MB.bin are already there)
INSTALL-v0.7.4-rc2.bat/.ps1, fw-v0.7.4-rc2\ (4 .bin + SHA256SUMS.txt), RESTORE-CHOSEN-BACKUP.bat/.ps1,
ROLLBACK-TO-v073.bat/.ps1 + fw-v0.7.3\, ROLLBACK-TO-v072.bat/.ps1 + fw-v0.7.2\, READ-BOARD-STATE.bat/.ps1 (read-only
evidence capture, never restarts the board - only when Claude asks), CAPTURE-CRASH.bat/.ps1, TEST-v0.7.4-rc2.txt,
this README, KIT-SHA256SUMS.txt. The rc1 files (INSTALL-v0.7.4, fw-v0.7.4\) are replaced by these; do not use them.
