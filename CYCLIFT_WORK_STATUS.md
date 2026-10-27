# Cyclift / BikeComputer — work status (checkpoint)

Updated: 27 Oct 2026 08:25 (Dubai). Source of truth for resuming work — update at every stage.

## Standing rules
- No App Store submission/release, no TestFlight upload, no firmware flashing, no board reboots without the owner's approval.
- Never claim simulator/CI results as hardware verification. Preserve all user data (rides, profile, pairings, NVS).
- Repo is public: no names, emails, team IDs or keys in commits/logs/screenshots.
- Report after each stage; no long silent runs; cancel and re-run stuck CI (normal run ≈ 25–35 min).

## Branches
| Work | Branch / worktree | Head | State |
|---|---|---|---|
| Integration line | `ios/dev` — /home/claude/bike-sensor-doctor | cf43ac4 (+ this file) | firmware 0.7.3 final + iOS diag receiver (MTU-exact) merged |
| Firmware 0.7.3 final | `fix/073` — /home/claude/ws-073 | 1cf8cf0 | DONE, delivered to PC, not flashed |
| iOS diag receiver | `fix/iosdiag` → `ios/diag-receiver` — /home/claude/ws-iosdiag | 7ab3c92 | DONE, CI run 69 green (275 tests) |
| Cyclift quality + coach fixes | `fix/quality` → `ios/quality` — /home/claude/ws-quality | 32a0676 | code complete; final CI run 73 (attempt 2) running |
| Coach audit baseline | detached — /home/claude/ws-audit | 2b2c104 | frozen, read-only |

## Workstreams
1. **Firmware 0.7.3** — DONE. App SHA-256 181b2e5c751108679a2101bfb1c1942b0302fe537527ceaeba207c5256ea4da5 (1,830,352 B).
   Delivered 27 Oct 01:5x to C:\Users\PC\Documents\BikeComputer, 18 files re-read from the PC and hash-verified:
   INSTALL-v0.7.3.bat/.ps1, README-v0.7.3.txt, TEST-v0.7.3.txt, DIAG-TEST-v0.7.3.txt, RESTORE-CHOSEN-BACKUP.bat/.ps1,
   ROLLBACK-TO-v071.bat/.ps1, CAPTURE-CRASH.bat/.ps1, fw-v0.7.3\ (app, bootloader, otadata, partitions, SHA256SUMS),
   fw-v0.7.1\ (BC071-app.bin, BC071-otadata.bin). Partition change: 64 KB coredump carved from the never-used ota_1; data partitions unchanged.
   Crash root cause of 0.7.2: NOT confirmed (no crash log). 4 confirmed defects fixed (D1–D4).
2. **Diagnostic integration (Link 1.2.3)** — DONE (PC/CI only). Chunk data = min(phone max_len, 155, ATT_MTU−3−25).
   Firmware cross-test fixture (7,301-byte real report, MTU 23/100/185/247/517) decoded by iOS. LIVE priority gating measured.
   Safe report: board Settings › Diagnostics › HOLD: SAVE REPORT. Physical test: DIAG-TEST-v0.7.3.txt.
3. **Coach audit (commit 2b2c104)** — DONE. Files in /home/claude/coach-audit (sent to owner as zip):
   CYCLIFT_COACH_SCIENTIFIC_AUDIT.md, _RULES.csv (40 rules), _TEST_CASES.csv (34 athletes 27 pass / 7 fail; 20 rule checks 11/9),
   _GAPS.md, EXECUTIVE_SUMMARY.md, harness/ (Linux Swift 5.10.1 at /opt/swiftx). Verdict: not ready for public release.
4. **Cyclift quality release** — code complete on fix/quality (21 commits since b485265). Includes audit fixes G-01..G-09, G-11, G-21
   (harness 38/54 → 51/54 on the new code). Run 72: 317 unit tests 0 failed, 74 layout screenshots ok, archive/sign ok;
   1 UI smoke flake ("Quick log" not hittable yet) — fixed in 32a0676; run 73 stuck 1 h 24 min on GitHub → cancelled, re-run.

## Next stages
- A. Run 73 green → merge fix/quality into ios/dev → full CI on ios/dev (no upload) = TestFlight release candidate, awaiting approval.
- B. One physical test sheet for the owner's 8 checks (meter→board, board→phone, watch→phone, phone→board HR, diag transfer,
  strength logging/edit/delete/swap, coach adjustment, data preservation/reconnect/crash recovery).
- C. Owner approvals needed: install firmware 0.7.3; TestFlight upload of the release candidate.
- Remaining audit gaps not yet fixed: see ios/QUALITY_RELEASE.md "Audit findings addressed".

## Hardware verification
NOTHING of 0.7.3 or the quality release has been verified on the physical board, iPhone or Apple Watch.
