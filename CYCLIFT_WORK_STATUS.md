# Cyclift / BikeComputer — work status (checkpoint)

Updated: 27 Oct 2026 01:40 (Dubai). Keep this file current; it is the source of truth for resuming work.

## Standing rules
- No App Store submission/release, no TestFlight upload, no firmware flashing, no board reboots without the owner's approval.
- Never claim simulator/CI results as hardware verification. Preserve all user data (rides, profile, pairings, NVS).
- Repo is public: no names, emails, team IDs or keys in commits/logs/screenshots.

## Branches and worktrees
| Work | Branch / worktree | Head | State |
|---|---|---|---|
| Integration line | `ios/dev` — /home/claude/bike-sensor-doctor | b485265 | Contains firmware 0.7.3 + iOS diag receiver + firmware-vector tests. Not uploaded to TestFlight. |
| Firmware 0.7.3 | `fix/073` — /home/claude/ws-073 | 092561b | Built, host+sim tests pass; not flashed. Kit in firmware/waveshare/pc-kit. |
| iOS diag receiver (Link 1.2.3) | `fix/iosdiag` — /home/claude/ws-iosdiag | 52915c0 | Merged into ios/dev; CI run #68 green. |
| Cyclift quality + coaching | `fix/quality` — /home/claude/ws-quality | 2b2c104 | In progress (WIP commits). CI compile checks on `ios-check/quality`. |
| 0.7.2 exact rebuild (crash decoding) | detached — /home/claude/ws-fw | ec0aad9 | Read-only; ELF for addr2line. |

## Owner instructions and status
1. **0.7.2 crash + firmware 0.7.3** (20:37, 20:55 briefs) — DONE (dev): 4 confirmed BLE defects fixed (D1–D4), defensive fixes D5–D9; crash root cause NOT confirmed (needs a crash log or a 0.7.3 crash report). Core-dump partition added (old data partitions unchanged; rollback to 0.7.1 kept).
2. **Cyclift UI / workout integrity / personalised strength / swap / Health-style charts / FTP labels** (21:11 brief + 22:39 "charts scrollable and tappable like the Health app") — IN PROGRESS on fix/quality. Root causes documented in ios/QUALITY_RELEASE.md.
3. **Diagnostic integration** (00:24 brief): MTU-based chunk size on both sides, cross-tests with firmware-generated vectors, verify 0.7.3 capabilities, ride-priority throttling, one physical test procedure — IN PROGRESS (firmware-generated vectors already decode in iOS: DiagFirmwareVectorTests). MTU fix NOT STARTED.
4. **Deliver 0.7.3 package to the PC** (00:28 brief) — NOT DONE. Target: C:\Users\PC\Documents\BikeComputer (PC linked). Deliver after the MTU fix so the delivered binary is final; verify every file on the PC.
5. **Coaching scientific audit** (00:28 attachment): CYCLIFT_COACH_SCIENTIFIC_AUDIT.md, _RULES.csv, _TEST_CASES.csv (≥20 profiles run through the real engine), _GAPS.md, executive summary — NOT STARTED. Audit baseline will be pinned to a fixed commit.

## Next actions
- Agent A (fix/quality): finish quality release, CI green, screenshots inspected.
- Agent B (audit, read-only worktree at pinned commit): coaching audit package.
- Agent C (fix/073 + fix/iosdiag): MTU-safe chunk sizing both sides, tests, rebuild 0.7.3, integrated physical test procedure.
- Main session: integration into ios/dev, deliver PC package and verify, keep this file updated.

## Test status
- Firmware 0.7.3: host 2,403 checks 0 failed (ASan/UBSan); sim 289 screens 0 issues; BLE stress 1,000 phone cycles pass; idf.py build OK.
- iOS diag receiver: CI #68 — 254 unit tests 0 failed, launch smoke pass.
- Quality branch: CI compile checks iter 9 green, iter 10 running.
- Hardware: NOTHING verified on the physical board or iPhone for 0.7.3 / quality release.
