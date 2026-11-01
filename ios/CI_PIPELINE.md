# iOS CI pipeline (from 1 Nov 2026)

Approved by the owner on 1 Nov 2026 (CI speed-up items 1–5 and 7). Quality gates are unchanged: every unit, smoke and
layout test still has to pass before anything is archived for upload.

## Two scopes

| | Quick check | Full validation |
|---|---|---|
| Start | head commit message contains `[ci quick]` (or Run workflow → scope = quick) | any other push to `ios/**` (or scope = full) |
| What runs | compile (Debug + Release), all unit tests, LayoutAudit `testKeyScreensAtTextSizes` + `testHomeStates` and the onboarding test on iPhone SE at AX3 and a standard iPhone at L (`QUICK_UI` picks other test methods) | unit · smoke · layout on 4 iPhones · watch screenshots, **in parallel jobs**; then release |
| Archive / upload | never | only when every test job passed and the commit says `[testflight]` (or upload = true) |
| Evidence | "QUICK CHECK — not release evidence" | release evidence |
| Expected time | ~20–30 min | ~45–60 min to upload, then Apple processing |

## Jobs (full)
- `apple` (Linux): bundle IDs, HealthKit, app record, TestFlight groups "Rashed devices" (unchanged) and "Internal QA" (new, no testers added automatically).
- `mode` (Linux): picks the scope from the commit message / inputs.
- `test` (macOS matrix, `fail-fast: false`): `unit`, `smoke`, `layout-small`, `layout-standard`, `layout-promax`, `layout-owner`, `watch`. Each job runs `ios/ci/build.sh` with `STAGE=…`: it builds once (`build-for-testing`) and runs its tests with `test-without-building` on the same binaries. Watch screenshots stay a soft check.
- `release` (macOS): only if every `test` job succeeded (`needs.test.result == 'success'`, and `TESTS_OK=success` is re-checked inside the script before upload). Archive, App Store signing, signature/entitlement verification, upload.
- `testflight` (Linux, after an upload): waits up to 40 min for Apple's processing, reports `RESULT testflight: … VALID — installable by internal testers` (or the state it is stuck in), and sets What to Test to `INTERNAL TEST BUILD <n> — not an approved release. Commit <sha>.` plus `ios/TESTFLIGHT_NOTES.txt` if that file exists.
- `publish` (Linux, always): one combined `summary.txt` (sections per job, same `RESULT` lines as before, with durations), all logs and screenshots → branch `ci-logs`, `ios/run-N/`, in a single push (no push races between jobs).

## Caching
- Swift packages: `ios/build/spm` (`-clonedSourcePackagesDirPath`), cached with `actions/cache`, key = hash of `ios/project.yml`.
- DerivedData is **not** cached across runs (deferred): a stale incremental build could hide a compile problem, and a clean compile is only ~5 min.
- No signing material is ever cached; the App Store Connect key still lives only in a 0600 temp file during the release job.

## Builds per run
Before: 7 compiles in one 116-min job. Now: each test job compiles once (Debug for unit; Release for smoke/layout), in parallel; release compiles the device archive.

**Deferred: building once and sharing the products across runners.** Passing the build products between macOS runners as an artifact (`.xctestrun` + products) depends on identical Xcode/simulator runtimes on every runner and is a larger change. Correctness came first, so each parallel job compiles its own copy (~5–8 min).

## Internal testing vs approved releases
- Every uploaded build is an **internal test build**: its What to Test text says so, and it reaches only internal TestFlight groups ("Rashed devices", "Internal QA").
- A build becomes a **release candidate** only when the owner approves it. Nothing in CI submits for review or to external testers.

## UI tests: identifiers, not positions
`BikeComputerUITests/UITestWaits.swift` adds `waitUntilSettled`, `tapWhenSettled`, `waitUntilGone`, `waitForScreen` and `settleForScreenshot`. Menu items (Plan › Log strength › Quick log, Home › More › Move) are found by identifier/label and tapped only once their frame is real and has stopped moving. This fixes the run-123 crash, where XCUI tapped a point with no frame.

Fixed waits that remain, and why:
- Pre-screenshot pauses in LayoutAudit, OnboardingScreens and StoreScreenshots let animations and charts finish so screenshots are complete; they don't affect pass/fail.
- Some coordinate taps remain. They still target an identified element, at a position inside it:
  - LayoutAudit: tomorrow's day card (XCUI reports "not hittable" on a fully visible card, run 117).
  - LayoutAudit: selecting a point on the progress chart (a chart point has no element of its own).
  - LayoutAudit: the drag-to-scroll helper (a gesture, not a tap).
  - LayoutAudit: tapping at an offset inside a custom control.

## Local checks before pushing (no Mac here)
1. Linux engine harness: `tools/coach-harness/test.sh <checkout>` (training engine, ~1 min).
2. `swiftc -parse` on every changed Swift file (syntax only).
3. Then push with `[ci quick]` for compile + unit + main-screen layout; push without it for full validation.
