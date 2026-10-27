BikeComputer firmware 0.7.3 - READ ME FIRST (27 Oct 2026)
=========================================================
What 0.7.3 is: the fix for the 0.7.2 crash loop (all Bluetooth work on one task), crash records kept on the board,
a RECOVERY screen instead of a reboot loop, and diagnostic reports that Cyclift collects by itself over Bluetooth.
App checksum (SHA-256): 181b2e5c751108679a2101bfb1c1942b0302fe537527ceaeba207c5256ea4da5 (1 830 352 bytes).
Nothing here has run on your board yet: it is tested on the PC only until you do TEST and DIAG-TEST below.

INSTALL (about 6 minutes)
1  Board on USB, battery unplugged. Close any other program that uses the board's port.
2  Double-click INSTALL-v0.7.3.bat. It checks every file, finds the board, then reads a COMPLETE backup of the board
   (16 MB, about 3 minutes) to backup-before-v073-<date-time>.bin and checks that backup before anything is written.
   It accepts a board running 0.7.2, 0.7.1, 0.7.0, 0.6.1, 0.6.0, 0.5.0 or 0.4.0.
3  Read the one line about the partition table (below) and type YES.
4  It writes the firmware, restarts the board and watches the first minute: wait for "RESULT: BOOTED OK".
5  Then TEST-v0.7.3.txt (stability) and DIAG-TEST-v0.7.3.txt (reports to Cyclift).

THE PARTITION TABLE CHANGE (only on the first install of 0.7.3)
- What changes: 64 KB at the end of the second firmware slot, which has never been used, becomes a "crash record" area.
- What does NOT move: your settings, profile, Wi-Fi networks, paired sensors, phone pairing, rides and ride history.
  They are not written at all.
- Risk 1 - power or USB lost during the write (about 20 seconds): the board may not start. Fix: run
  RESTORE-CHOSEN-BACKUP.bat and pick the backup-before-v073 file made a minute earlier - everything comes back exactly as it
  was. The start-up code of the board is never written, so the PC can always reach it (if the port does not appear, hold
  BOOT while plugging the USB cable in).
- Risk 2 - data: none from installing. Data is lost only if you later restore an OLDER backup: rides recorded after that
  backup would be gone. Always pick the newest backup-before-v073-<date-time>.bin.
- Going back: ROLLBACK-TO-v071.bat puts 0.7.1 back and KEEPS settings and rides; it works with the new table (0.7.1 simply
  does not use the crash-record area; reports 0.7.3 saved stay as harmless files). RESTORE-CHOSEN-BACKUP.bat puts back the
  whole board as it was, old table included. Do not use the older ROLLBACK-TO-v061/v050/v040 files for this.

FILES NEEDED FOR 0.7.3 (keep them together in this folder)
INSTALL-v0.7.3.bat, INSTALL-v0.7.3.ps1, fw-v0.7.3\ (4 .bin files + SHA256SUMS.txt), ROLLBACK-TO-v071.bat/.ps1 +
fw-v0.7.1\, RESTORE-CHOSEN-BACKUP.bat/.ps1, CAPTURE-CRASH.bat/.ps1, TEST-v0.7.3.txt, DIAG-TEST-v0.7.3.txt, this README.
Already in your PC kit folder from earlier installs (not downloaded again): esptool.exe and factory_backup_16MB.bin.
