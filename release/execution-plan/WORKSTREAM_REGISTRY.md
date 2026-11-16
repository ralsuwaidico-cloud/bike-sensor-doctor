# Cyclift — workstream ownership and interface registry

Status: **Live** · started 16 Nov 2026 (owner authorization "Parallel development authorization and execution controls").
Purpose: three workstreams run in parallel. This page says who may change what, what they share, and the order of merging.
Nothing here authorizes a merge, an upload, an AI activation or a firmware change.

## 1. Branches

| Workstream | Branch | Starts from | May be merged into | Status |
|---|---|---|---|---|
| E1 safety (release gate) | `ios/e1-safety` | build 216 line | a protected branch, only with owner approval after the E1 evidence report | In progress |
| UX1 theme, navigation, shared components | `ios/ux1-foundation` | E1 commit `3edad7ed` | nothing until Checkpoint 1 passes; then rebased on the verified E1 commit | Started 16 Nov |
| Coach foundation (shadow mode) | `ios/c0-coach` | E1 commit `3edad7ed` | nothing until Checkpoint 1 passes; integration is a separate reviewed change | Started 16 Nov |
| Protected reference points | `baseline/build-216` (`fb52ae27`), `baseline/e1-run-235` (`a017ed6d`) | — | never changed | Preserved |

`3edad7ed` is the newest E1 commit, **not a verified one**. UX1 and Coach add new files only, so they do not depend on its
unverified parts; both are rebased when E1 has a verified commit.

## 2. File ownership

| Files | Owner | Others may |
|---|---|---|
| `Models.swift`, `StoreRecovery.swift`, `RideRecorder.swift`, `Ride/**`, `ProfileScreens.swift` delete-all path, all `E1*` tests, `ios/ci/build.sh`, `.github/workflows/**` | E1 | read only |
| `ContentView.swift`, tab bar and dock (`DesignSystem/CyLiquidDock.swift`), existing screens | E1 until Checkpoint 1, then UX1 | read only |
| `DesignSystem/ThemeTokens.swift`, later `DesignSystem/Theme*.swift`, `ThemeTokensTests.swift` | UX1 | read only |
| `Theme.swift` (`BC`), `DesignSystem/CyTheme.swift` (existing colour systems) | UX1, **only after Checkpoint 1**, one screen group per change | read only |
| `CoachShadow.swift`, later `CoachShadow*.swift`, `CoachShadowTests.swift` | Coach | read only |
| Existing coach engine (`CoachSafety.swift`, `AdaptationEngine.swift`, `AdaptiveStore.swift`, `Shared/CoachCore.swift`) | E1 (holds stay as approved on 15 Nov) | read only |
| `tools/coach-harness/test.sh` (list of files in the Linux tests) | **Shared.** Each workstream adds only its own file names | — |

## 3. Shared data contracts

| Contract | Owner | Rule |
|---|---|---|
| Athlete record `store.json` and its schema | E1 | UX1 and Coach do not add, remove or rename a field. Any change needs an impact assessment and a rollback plan |
| Theme choice | UX1 | Stored under its own preference key `cyclift.theme.preference.v1`, outside `store.json` |
| Coach history | Coach | Stored in its own file `coach-shadow.json`. The Coach reads the athlete record through `ShadowAthleteSnapshot(reading:)` and has no way to write it |
| Training status (allowed / on hold / unknown) | E1 (`Store.trainingAuthority`) | Coach reads it; it never computes its own |
| "Delete all data" (owner decision 16 Nov) | E1 | Returns the app to a fresh install. It must also remove the Coach history file and the theme choice; each workstream registers its own clean-up through the existing delete-all hook at integration. "Delete workout history" is a different action and keeps app preferences. Partial failure must be reported, never shown as success. **Not yet implemented or tested for interruption and failure** |
| Existing appearance setting (`system` / `light` / `dark`) | E1 | UX1 reads it once to choose a returning athlete's first theme; it is not removed |

## 4. Integration dependencies and merge order

1. **E1** reaches a verified commit (Checkpoint 1). Nothing else merges before this.
2. **Theme foundation** (tokens, preference, later the SwiftUI bridge): new files, no behaviour change until a screen uses them.
3. **Theme migration, one screen group at a time**, each with before/after screenshots; colour values only after owner approval.
4. **Navigation v1.2 rev 1.1**, then onboarding and Profile (Checkpoint 2).
5. **Coach foundation** files (still shadow mode, still unable to change the plan).
6. **Coach integration**: a separate reviewed change that connects proposals to the plan-change preview. Needs approved limits and allowlist.

## 5. Regression test ownership

| Tests | Owner | Runs where |
|---|---|---|
| All existing unit, smoke, flow, journey and layout tests | E1 | Full iOS run (about 1 h 30 min) and Linux logic run (about 3 min) |
| `ThemeTokensTests` | UX1 | Linux logic run; iOS unit job once the branch has an iOS run |
| `CoachShadowTests` | Coach | Linux logic run; iOS unit job once the branch has an iOS run |
| Theme screenshot comparisons (six themes × key screens × text sizes) | UX1 | iOS layout job, when the first screens are themed |

## 6. CI rule while runner capacity is limited

- `ios/e1-safety` has priority on the macOS runners. One full run at a time; no push while a relevant run is in progress.
- UX1 and Coach pure-logic commits are pushed **without** starting an iOS run, and checked by starting only the Linux
  logic run on their branch. This proves the logic on Linux; it does **not** prove the files compile in the iOS app.
- Each of those branches gets one quick-scope iOS run (compile + unit tests) when E1 is not running, before anything is
  called "compiled in the app".
