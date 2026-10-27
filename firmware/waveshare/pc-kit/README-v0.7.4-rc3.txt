BikeComputer firmware 0.7.4-rc3 - READ ME FIRST (27 Oct 2026)
==============================================================
What it is: the fix for the 0.7.3 start-up crash, third release candidate. rc3 = rc2 (QA: GO for the physical test) plus
QA's rc2 corrections and the new phone link with Cyclift (Link 1.3: coach on the board, offline rides, storage screen).
On your board 0.7.3 stopped every start when Bluetooth could not start ("hci inits failed" -> abort -> RECOVERY).
0.7.4-rc3:
- never stops because of Bluetooth: if it cannot start, the board keeps running and says "Bluetooth unavailable" and why;
  after 2 such starts in a row Bluetooth is switched off until you tap RETRY (Settings > Phone), so there is no loop;
- leaves more working memory free for the Bluetooth start than any earlier version (44.7 KB, 0.7.2 had 37.9 KB);
- records, step by step, what the Bluetooth start needed and got (memory figures) in the settings area (NVS). The
  installer also records the very first start of the new firmware on the PC (first-boot-v0.7.4-rc3-*.txt) - that file is
  the main evidence for the cause; please send it;
- shows the REAL storage problem: on your board the file area's directory is damaged ("dir corrupted"), it is not full.
  The firmware never formats, erases or writes into the damaged file area, never deletes anything on a file area whose
  allocation table is not consistent, and never erases the settings area on its own; repairs are separate steps you approve.
- with a Cyclift that speaks the new link: Cyclift's coach on the board (every ride screen design), the board keeps
  following the workout when the phone drops, rides recorded offline go to Cyclift and are deleted on the board only
  after Cyclift confirmed them, and Cyclift can show the board's storage. With the current Cyclift everything works as
  in rc2 (the new link is only used when the app asks for it).
App checksum (SHA-256): 10c9a7a79085c47a304a52789223368b61d8479c6c13ca71626396941585f306 (1875840 bytes).
Nothing here has run on your board yet: it is tested on the PC only (simulator + unit tests) until you do TEST-v0.7.4-rc3.txt.
It is NOT claimed to be fixed until your board shows it.

IMPORTANT ON YOUR BOARD (until the file area is repaired)
- Rides recorded on the board are NOT saved on the board. The screen says so: a red line on the ride result and, after
  SAVE, "NOT SAVED ON BOARD". The ride stays in the board's memory (up to 4) only until power-off, restart or deep
  sleep. If Bluetooth is working, open Cyclift while the board is on: once Cyclift has the ride, its memory place is
  freed. If Bluetooth is NOT working this start, the screen says the ride cannot reach Cyclift - it is lost at power-off.
- RESTART and DEEP SLEEP ask for a second confirmation (hold 3 s) while rides exist only in memory; automatic deep sleep
  does not happen then.
- Bluetooth: if it cannot start, the Phone screen shows "NO BLUETOOTH" with WHY? (the reason). After the second failed
  start in a row it is switched off and the Phone screen shows RETRY (tap it, then restart, to try again).
- "Power dips: N restarts - check battery" = the board restarted from low voltage (brownout). That is a power problem
  (battery / cable), not a firmware crash; it never sends the board to RECOVERY.
- If the settings area itself ever reports a problem, the board shows "Settings memory needs repair" and keeps running
  on default settings without saving anything. Nothing is erased; tell Claude.

INSTALL (about 6 minutes)
1  Board on USB, battery unplugged. Close any other program that uses the board's port.
2  Double-click INSTALL-v0.7.4-rc3.bat. It checks every file, finds the board, reads a COMPLETE backup (16 MB, ~3 minutes)
   to backup-before-v074-<date-time>.bin and checks that backup before anything is written. From the backup until the end
   the board is held in download mode (dark screen): the old firmware does not run again.
3  Type YES. Only the firmware (0x20000) and the start selector (0xf000) are written. Settings, sensor pairings, phone
   pairing and the file area are NOT written or erased. The partition table is NOT changed.
4  The window then starts the board itself and records its first 90 seconds (first-boot-v0.7.4-rc3-<date-time>.txt),
   and prints RESULT (BOOTED OK + Bluetooth started / unavailable + whether the Bluetooth start figures were recorded).
   If you type anything other than YES, or the script stops after the backup, unplug and replug the USB cable to start
   the board again (it waits in download mode).
5  Then TEST-v0.7.4-rc3.txt. Send first-boot-*.txt and install-*.txt to Claude in any case.

GOING BACK
- RESTORE-CHOSEN-BACKUP.bat: puts back the whole board exactly as in a backup you pick (the newest backup-before-v074 =
  as it was a minute before the install). This is THE way back.
- ROLLBACK-TO-v073.bat / ROLLBACK-TO-v072.bat: do NOT use them unless Claude asks. On your board 0.7.3 stops at every
  start and 0.7.2 crashed while connecting; the 0.7.3 script warns about this on screen.
- If a write is interrupted (USB unplugged): RESTORE-CHOSEN-BACKUP.bat with the backup just made. If the port does not
  appear, hold BOOT while plugging the USB cable in. The board's start-up code is never written.

FILES (keep together in your BikeComputer folder; esptool.exe and factory_backup_16MB.bin are already there)
INSTALL-v0.7.4-rc3.bat/.ps1, fw-v0.7.4-rc3\ (4 .bin + SHA256SUMS.txt), RESTORE-CHOSEN-BACKUP.bat/.ps1,
ROLLBACK-TO-v073.bat/.ps1 + fw-v0.7.3\, ROLLBACK-TO-v072.bat/.ps1 + fw-v0.7.2\, READ-BOARD-STATE.bat/.ps1 (read-only
evidence capture, never restarts the board - only when Claude asks), CAPTURE-CRASH.bat/.ps1, TEST-v0.7.4-rc3.txt,
this README, KIT-SHA256SUMS.txt. The rc2 files (INSTALL-v0.7.4-rc2, fw-v0.7.4-rc2\) are replaced by these.
