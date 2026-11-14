# Navigation v1.2 — Technical Impact Register (read-only assessment)

**Revision:** 1.0 · 15 Nov 2026 · **Status:** Current Draft — for future engineering planning. **No code was changed, built or run.**
Basis: source read on branch `impl/checkpoint-f-ride`, commit `4e2e9dc` (`ios/BikeComputer`). "As read" means read in source, not re-verified by running. Last known simulator run 43013897973 (11 Nov) had two open failures (ride GPS-route samples; Plan edit-and-apply) — both remain open defects, not investigated.

| # | Area | Today (as read) | What v1.2 would require later | Risk / approval |
|---|---|---|---|---|
| 1 | Destinations | `ContentView.swift`: five numbered pages — Home 0, Plan 1, Ride 2 (hidden, reached by the centre button), Progress 3, Profile 4 — via `tabPage(i, tab)` | Three visible tabs plus Train. The numbers must not be assumed removable: page identifiers `tabPage-<i>` are used by tests and the layout audit; Ride (2) and Profile (4) still need owners | Implementation audit before any remap · engineering approval |
| 2 | Dock component | `CyLiquidDock` with a centre button (`centreButton`), state from `CyCentreState` and `RideTabBar.centreCopy` | New sculpted dock: left ball, three regions, ring/badge states, hit-testing that excludes the arms | New component; old one kept until replaced |
| 3 | Dock presentation | Bottom safe-area inset; removed (not hidden) while the Ride screen owns the bottom (RA-01) | Keep RA-01. Insets 128 / 110 pt applied to every page, including pages inside their own navigation stack (a past defect: Plan's last row under the dock) | Regression risk on scroll margins |
| 4 | Train tap routing | Centre tap opens the hub, or jumps to Ride (page 2) when recording | Ball tap → compact panel; with an active session → resume panel only; never a second session | Presenter ownership to be defined |
| 5 | Ride screen | Hidden page 2; while riding: Lap + Pause; paused: Resume + End (RA-20) | Unchanged. Ride minimisation stays **blocked** by the cycling safety gate (GPS-route integrity, interrupted-ride persistence) | Separate safety approval |
| 6 | Session state for the ball | Strength active session is saved and a second is refused (as read); a phone-recorded ride's in-progress state was not found to be saved | A single read-only source the ball can show (activity, elapsed, running/paused, pending save). No new guarantees implied | Depends on v1.4 pending items 2–3 |
| 7 | Profile | Profile tab (page 4) plus a Home quick menu; editors shared with onboarding | Profile opened from the Home avatar with Home still selected; quick-menu retirement is a separate decision (register 51). Onboarding editors untouched | Owner decision + engineering approval |
| 8 | Tests | Unit: `W12AndDockTests`, `DockCopyTests`, `ProfileMenuTests`. UI: `centreButton` is referenced 16 times across UI tests (e.g. `HubTapReliabilityTests`, `JourneyTests`, `HomeNavigationTests`, `LaunchSmokeTests`, `RideViewsSmokeTests`, `LayoutAudit`, `DesignSystemAudit`) | Tests must be **updated to the new behaviour, not weakened**: identifiers, page indices, layout audit bounds, tap reliability on the left edge, new accessibility-order and hit-region tests | Test plan needed before code |
| 9 | Accessibility | Existing identifiers and labels on the centre button | Order Home, Plan, Progress, Train; state-bearing Train label; icon-tab names; decorative parts hidden; large-content viewer | New accessibility tests |
| 10 | Right-to-left | No Arabic in the app | Fixed-left layout that opts out of automatic mirroring for the dock while page content mirrors | Only when Arabic is scheduled |
| 11 | Keyboard | Dock is a safe-area inset | Confirm the dock sits beneath the keyboard and returns intact; no floating control | Verify on device |
| 12 | System gestures | Centre button, no edge conflict | Left ball beside the swipe-back edge: **physical-device test required** | Cannot be settled in drawings or simulator alone |
| 13 | Watch / hardware / data | — | None. No database, BLE, firmware or sync change is implied | — |

**Not assessed:** effort, performance, and any behaviour that would need the app to be run.
