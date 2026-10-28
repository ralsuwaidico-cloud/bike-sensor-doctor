# CI audit — 28 Oct 2026 (measured on run 105, combined build, 104 min)

## What exists
| Piece | Where | Runs on |
|---|---|---|
| iOS + Watch: generate, unit tests, Release UI tests ("launch smoke" = the whole UI-test bundle), layout audit on 4 iPhone sizes, Watch screenshots, archive, export, verify, optional TestFlight upload | .github/workflows/ios.yml → ios/ci/build.sh (one step) | every push to ios/** touching ios/** (macOS runner) |
| Logs + screenshots | ci-logs branch, ios/run-N/ | after each iOS run |
| Android APK (legacy app) | build-apk.yml | every push to ANY non-ios branch (incl. fw/*, fix/*) |
| Coach engine tests + 48-athlete harness | tools/coach-harness (Linux Swift) | only by hand in Claude's container |
| Firmware host tests, simulator, BLE harness, idf.py build | firmware/waveshare/test, Makefile | only by hand in Claude's container — no CI at all |
| BLE contract cross-tests | firmware fixtures + ios/BikeComputerTests (Link13FirmwareFixtureTests, DiagFirmwareFixture) | iOS side in CI; firmware side by hand |

## Measured bottlenecks (run 105)
| Stage | Time | Share |
|---|---|---|
| Layout audit — small iPhone (L, AX3) | 21.9 min | 21 % |
| Layout audit — owner size 393×852 (L, XXXL) | 19.7 min | 19 % |
| UI tests in Release ("launch smoke", whole UI bundle) | 13.6 min | 13 % |
| Layout audit — standard (L, XXXL) | 10.6 min | 10 % |
| Layout audit — Pro Max (L) | 6.9 min | 7 % |
| Unit tests (439) | 2.8 min | 3 % |
| Compiling (5 separate xcodebuild invocations), archive, export, verify, setup | ≈ 29 min | 28 % |
| **Total** | **104 min** | |

Other waste found:
- One step for everything: GitHub only shows the log at the end, so a failure at minute 5 is visible at minute 104 and nobody can see the current stage.
- Every UI fix re-runs unit tests, the full UI bundle, four layout devices and the archive (≈ 100 min) even when one screen on one device changed.
- The four layout devices run one after another; each is a separate `xcodebuild test` that rebuilds.
- Build APK runs (≈ 20 min each) on every firmware / coach branch push although no Android code changed.
- Claude polls for completion (watchers) instead of CI reporting a diagnosis.

## Three highest-value improvements
1. **Fast scope for UI fixes** (DONE 28 Oct, commit f425354): `workflow_dispatch` input `scope=ui` + `devices=…` runs only the layout audit on the chosen devices; never archives or uploads; every stage reports its duration and its first errors in summary.txt. Expected: a UI re-check on 2 devices ≈ 45 min instead of 104.
2. **Build once, test many, in parallel**: `xcodebuild build-for-testing` once, then `test-without-building` for unit tests, UI tests and each layout device, with the layout devices as parallel jobs (matrix) that share the build product. Expected full run ≈ 45–55 min. Each stage becomes its own visible GitHub step with its own duration.
3. **Fast checks on every push + firmware CI + one report**: a Linux job (≈ 2 min) runs the coach engine tests, Home/Progress logic tests and the BLE fixture checks before any macOS job starts; a firmware workflow (ESP-IDF 5.5.1 container: host tests, simulator, idf.py build, fixture regeneration check); every run writes one GitHub job summary (commit, branch, stage table, failures, artifacts, GO/NO-GO by fixed criteria). Build APK limited to android/** paths.

Safety: none of these changes the app, the coaching engine or the firmware; upload stays behind the explicit `upload` input / `[testflight]` and is impossible in `scope=ui`.
