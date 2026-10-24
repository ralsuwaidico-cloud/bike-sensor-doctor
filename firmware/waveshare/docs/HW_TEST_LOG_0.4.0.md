# Hardware test log — firmware 0.4.0 + iPhone build 14 (started 24 Oct 2026, 20:17 Dubai)

Real-hardware results only. Simulator results live in test/sim (`make run`: 114 screens, 125 checks) and are NOT repeated here.
Equipment: Waveshare ESP32-S3-Touch-LCD-1.28-B (MAC 8c:fd:49:9b:ef:40, 16 MB flash, COM3), XDS power meter, iPhone + TestFlight, Apple Watch, Windows PC.

| # | Step | Result | Notes |
|---|---|---|---|
| P1 | Board identity (1-CHECK-BOARD.bat) | PASS | ESP32-S3 rev 0.2, 16 MB quad flash, COM3. "Access is denied" line = Windows blocked re-writing the old log file; harmless |
| P2 | 0.3.0 rollback files present + checksums | PASS | verified by Claude from the PC copies before the install |
| P3 | Factory backup present (16 MB) | PASS | factory_backup_16MB.bin |
| P4 | Full pre-install backup read and verified | PASS | backup-before-v040-20261024-192438.bin: 16 MB, contains firmware 0.3.0 byte-identical to fw-v0.3.0, NVS + FAT present (verified by Claude from the PC copy) |
| P5 | Install 0.4.0 (4 regions, data kept) | PASS | installer run 19:24 (log install-v040-20261024-192438.txt): 4 × "Hash of data verified", exit 0. A second run at 20:18 correctly STOPPED (board already on 0.4.0); its backup holds 0.4.0 + current data and is kept as a second restore point |
| P6 | Install 0.5.0 via INSTALL-v0.5.0.bat (user-run) | PASS (reported by Rashed, 24 Oct 22:26) | Install log not yet reviewed by Claude; backup-before-v050-*.bin expected in Documents\BikeComputer. 0.5.0 features: see POWER-TEST-v0.5.0.txt, all NOT TESTED on hardware yet |
