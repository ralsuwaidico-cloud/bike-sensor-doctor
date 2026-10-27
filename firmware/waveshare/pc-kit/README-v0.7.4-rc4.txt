BikeComputer firmware 0.7.4-rc4 - READ ME FIRST (28 Oct 2026)
==============================================================
What it is: the fix for the 0.7.3 start-up crash, fourth release candidate. rc4 = rc3 (QA: GO for installation, with
conditions) plus QA's rc3 corrections:
- the first ride page (designs A and B) always fits inside the round screen, also for long coach instructions and
  4-digit targets (short words such as "HR HIGH"; anything longer is made smaller or shortened with "..");
- a few crashes days apart no longer add up: the crash counter is cleared by a night in deep sleep or by 10 minutes of
  normal running, so only crashes in a row lead to RECOVERY (rc3 could count 4 crashes over several days);
- Cyclift can ask the board again for one particular ride (needed by the next Cyclift to confirm rides, see below);
- the coach from Cyclift: a restarted Cyclift app is followed again at once; short "still here" messages keep the
  targets on screen; a ride is marked "safely in Cyclift" only when number, content and start time all match.
On your board 0.7.3 stopped every start when Bluetooth could not start ("hci inits failed" -> abort -> RECOVERY).
Unchanged from rc3:
- never stops because of Bluetooth: if it cannot start, the board keeps running and says "Bluetooth unavailable" and why;
  after 2 such starts in a row Bluetooth is switched off until you tap RETRY (Settings > Phone), so there is no loop;
- leaves more working memory free for the Bluetooth start than 0.7.2/0.7.3 (44.6 KB; 0.7.2 had 37.9 KB);
- records, step by step, what the Bluetooth start needed and got (memory figures) in the settings area (NVS). The
  installer also records the very first start of the new firmware on the PC (first-boot-v0.7.4-rc4-*.txt) - that file is
  the main evidence for the cause; please send it;
- shows the REAL storage problem: on your board the file area's directory is damaged ("dir corrupted"), it is not full.
  The firmware never formats, erases or writes into the damaged file area, never deletes anything on a file area whose
  allocation table is not consistent, and never erases the settings area on its own; repairs are separate steps you approve.
- with a Cyclift that speaks the new link: Cyclift's coach on the board (every ride screen design), the board keeps
  following the workout when the phone drops, rides recorded offline go to Cyclift and are deleted on the board only
  after Cyclift confirmed them, and Cyclift can show the board's storage. With the current Cyclift everything works as
  in rc2/rc3 (the new link is only used when the app asks for it).
App checksum (SHA-256): 2530042f9f44e9fa57fa804f640c36c6d2759d143a3438552734b72be3fa11e6 (1877632 bytes).
Nothing here has run on your board yet: it is tested on the PC only (simulator + unit tests) until you do TEST-v0.7.4-rc4.txt.
It is NOT claimed to be fixed until your board shows it.

IMPORTANT ON YOUR BOARD (until the file area is repaired)
- Rides recorded on the board are NOT saved on the board. The screen says so: a red line on the ride result and, after
  SAVE, "NOT SAVED ON BOARD". If Bluetooth is NOT working this start, the screen says the ride cannot reach Cyclift.
- HOW THE 4 MEMORY PLACES WORK (please read). Every ride on your board is kept only in the board's memory, in one of 4
  places, until power-off, restart or deep sleep (then all 4 are empty again). A place is freed only when Cyclift has
  told the board "I have this ride". With the Cyclift you have now, that happens in one way only:
    1. Cyclift connects to the board and syncs automatically (rides sync only when Cyclift connects - there is no
       pull-to-refresh); it receives the ride;
    2. at the NEXT connection Cyclift tells the board which rides it has - only then is the place freed.
  The place is NOT freed if Cyclift was already connected during the ride, or if Cyclift got the ride before that
  automatic sync: Cyclift has the ride, but the board does not know it. So after 4 rides in one power cycle the 5th ride
  says "RIDE NOT SAVED" - it is not kept anywhere, even though Cyclift probably has the earlier 4. To avoid this: after
  a ride, with the board on, let Cyclift connect twice (iPhone Settings > Bluetooth off, wait 10 s, on, wait until
  Cyclift shows the board connected; do that two times), or switch the board off and on
  (this empties the 4 places - only do it when Cyclift shows the rides in its history).
  The next Cyclift (with its RC3-01 fix) asks this firmware for the ride by number and confirms it; then the place is
  freed as soon as Cyclift has stored the ride. Until both are installed, the rule above applies.
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
2  Double-click INSTALL-v0.7.4-rc4.bat. It checks every file, finds the board, reads a COMPLETE backup (16 MB, ~3 minutes)
   to backup-before-v074-<date-time>.bin and checks that backup before anything is written. From the backup until the end
   the board is held in download mode (dark screen): the old firmware does not run again.
3  Type YES. Only the firmware (0x20000) and the start selector (0xf000) are written. Settings, sensor pairings, phone
   pairing and the file area are NOT written or erased. The partition table is NOT changed.
4  The window then starts the board itself and records its first 90 seconds (first-boot-v0.7.4-rc4-<date-time>.txt),
   and prints RESULT (BOOTED OK + Bluetooth started / unavailable + whether the Bluetooth start figures were recorded).
   If you type anything other than YES, or the script stops after the backup, unplug and replug the USB cable to start
   the board again (it waits in download mode).
5  Then TEST-v0.7.4-rc4.txt. Send first-boot-*.txt and install-*.txt to Claude in any case.

GOING BACK
- RESTORE-CHOSEN-BACKUP.bat: puts back the whole board exactly as in a backup you pick (the newest backup-before-v074 =
  as it was a minute before the install). This is THE way back.
- ROLLBACK-TO-v073.bat / ROLLBACK-TO-v072.bat: do NOT use them unless Claude asks. On your board 0.7.3 stops at every
  start and 0.7.2 crashed while connecting; the 0.7.3 script warns about this on screen.
- If a write is interrupted (USB unplugged): RESTORE-CHOSEN-BACKUP.bat with the backup just made. If the port does not
  appear, hold BOOT while plugging the USB cable in. The board's start-up code is never written.

FILES (keep together in your BikeComputer folder; esptool.exe and factory_backup_16MB.bin are already there)
INSTALL-v0.7.4-rc4.bat/.ps1, fw-v0.7.4-rc4\ (4 .bin + SHA256SUMS.txt), RESTORE-CHOSEN-BACKUP.bat/.ps1,
ROLLBACK-TO-v073.bat/.ps1 + fw-v0.7.3\, ROLLBACK-TO-v072.bat/.ps1 + fw-v0.7.2\, READ-BOARD-STATE.bat/.ps1 (read-only
evidence capture, never restarts the board - only when Claude asks), CAPTURE-CRASH.bat/.ps1, TEST-v0.7.4-rc4.txt,
this README, KIT-SHA256SUMS.txt. The rc3 files (INSTALL-v0.7.4-rc3, fw-v0.7.4-rc3\) are replaced by these; if you already
installed rc3, install rc4 over it the same way (the backup step and RESTORE-CHOSEN-BACKUP work the same).
