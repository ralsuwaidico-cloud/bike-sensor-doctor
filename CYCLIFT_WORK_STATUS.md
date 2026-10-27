# Cyclift / BikeComputer — work status (project dashboard)

Updated: 28 Oct 2026 03:10 (Dubai). Maintained by the project lead. Team protocol: coord/TEAM.md; task board: coord/TASKBOARD.md.

## Standing rules
- No App Store submission/release, no TestFlight upload, no firmware flashing, no board reset/erase/repair without the owner's approval.
- Simulator/CI/host results are never hardware verification. Preserve all user data and every flash backup.
- Repo is public: no names, emails, team IDs, keys or device addresses in commits/logs (tests use 02:00:00:c1:f7:01, "Rider A").

## Release candidates
| Item | Commit | Tests | Independent QA | Waiting for |
|---|---|---|---|---|
| Cyclift RC2 (UI/quality release + diag receiver + corrected coach) | ios/dev ed0ceeb (app code = ios/coach 26b926e) | CI run 89 rerun (attempt 2) + ios/dev run; Linux engine 201/0; 48-athlete harness s16 44/48 + 21/22 (documented conflicts only) | Pass 5: GO once CI is fully green | CI green → owner approval for TestFlight upload |
| Firmware 0.7.4-rc5 | fw/phonefirst 0d88933 (+32a35e7 housekeeping) | host suites 0 failed; simulator 339 screens/701 checks normal+ASan; blehost; idf build | RC5 review: GO for install + physical test; protocol v1.4 GO | Owner approval to install (kit on the PC, verified) |
| Cyclift Link 1.3 side (coach mirror, offline rides, storage screen) | ios/phonefirst-dev 37cdca9 | CI run 90 green (362 tests); 34-vector fixture cross-check | Protocol GO (rc5 review) | Not in RC2; next RC after the physical firmware test |

## Firmware investigation (owner brief 27 Oct 12:15)
- Crash: ESP_ERROR_CHECK(nimble_port_init) abort in app_main (confirmed from the board's own log + exact ELF rebuild).
  Cause of the init failure: internal-RAM shortage at Bluetooth start — STRONGLY INDICATED, NOT CONFIRMED. Only the first rc boot log
  (per-step return codes, heap, failed allocation) can confirm it; the read-only capture cannot.
- Logs not saved: FAT root directory erased (all 512 entries), not a full flash; dated 24–25 Oct, before 0.7.3; layout unchanged since 0.4.0.
- Reports: coord/reports/FW_STORAGE_MEMORY_REPORT.md; QA: /home/claude/qa-fw/FIRMWARE_REVIEW_RC{1,2,3,5}.md.
- Kit on PC (C:\Users\PC\Documents\BikeComputer): INSTALL-v0.7.4-rc5.bat, README/TEST-v0.7.4-rc5.txt, fw-v0.7.4-rc5\, ROLLBACK-TO-v072/v073,
  RESTORE-CHOSEN-BACKUP (old version kept as RESTORE-CHOSEN-BACKUP-v073-old.ps1), KIT-SHA256SUMS-v0.7.4-rc5.txt. All 17 files re-read and byte-verified.

## Coach remediation
- Owner brief 27 Oct 08:27. Five independent review passes (F-, N-, P3-, P4-, P5-). All P0/P1 fixed; known limitations in ios/ADAPTIVE_COACH.md
  (F-22 no automatic VO2 session; P4-03/04/07; P5-03/04 err on the safe side).

## Hardware verification
NOTHING of RC2, Link 1.3 or firmware 0.7.4 has been verified on the physical board, iPhone or Apple Watch.
