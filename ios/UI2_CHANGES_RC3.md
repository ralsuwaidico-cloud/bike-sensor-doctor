# RC3 UI part 2 — onboarding r7, Ride, Strength workout (Removed / Merged / Simplified / Fixed)

Local commit only; not compiled on iOS yet (the CI run is the first compile). Data contract: `ios/ENGINE_API_RC3.md` — no new model fields.

## Onboarding (OnboardingView.swift)
| Change | What | Why |
|---|---|---|
| Removed | Ten-step flow (mode, week, days editor, about you, sports & goal, HR & FTP, devices, Apple Health, ready) | Replaced by the approved r7 design: Welcome + five screens |
| Removed | Height, sports list, max/resting heart-rate fields, per-day editor sheet, optional "Hybrid plan" sheet | Not used by the plan (height) or moved to Profile; r7 asks only what changes the plan |
| Removed | Health questionnaire anywhere in onboarding | Owner decision rc3 (see SAFETY_CHANGES_RC3.md); saved restrictions are untouched |
| Merged | About you + training type + cycling level + strength level + priority → screen 1 | r7 NEW5-S1 |
| Simplified | Goals: chips per sport, multi-select, ★ = main goal; Endurance includes the former Aerobic fitness | r7 S2; written through `store.setGoals` |
| Simplified | Your week: 7 day icons (bicycle / dumbbell / moon), tap cycles the kinds allowed for the training type (+ Both with "Two a day"), ride and strength length steppers, equipment Gym / Home / Bodyweight / Not sure, supersets switch, counts and inline mismatch | r7 S3; writes `availability` (one assignment per session at the session length), `weekIsExplicit`, `preferredDays`, frequencies and budgets |
| Simplified | Connections: Apple Health connect, Apple Watch, BikeComputer connect, HR strap, power meter; FTP Don't know / Entered / Tested (`setFTP`), Skip on this screen only | r7 S4; "Don't know" keeps the FTP Unknown — no watts are invented |
| New | Your plan: week icons, 4 summary rows, "Why this plan" (≤ 3 points, each true for these answers), Create plan | r7 S5 |
| Fixed | Resume: r7 stages saved as 101–105; build-121 stages 1–9 map to the screen that now holds that question | REDESIGN_SPEC "Persistence and resume" |
| Kept | Existing users (`onboarded == true`) never see onboarding again | ONB-T71 |

Equipment presets map onto the one `EquipmentProfile` (Gym = every catalogue item; Home = dumbbell, bench, band, pull-up bar, kettlebell; Bodyweight = confirmed with nothing owned; Not sure = not set → provisional bodyweight plan). Equipment sits on Your week (as in the approved r7 design), not on Connections.

## Ride (RideView, RideDashboard, Ride/*)
| Change | What | Why |
|---|---|---|
| New | Current-step strip on the live screen: step name, time left (big), target, next step; "Pair a heart-rate strap…" when no HR | "What do I do right now?"; steps from `Workout.rideSteps` (add up to the session) |
| Fixed | Unknown FTP: no power zone, zone band, gauge target, zone tile or watt band; header says FTP UNKNOWN; the coach panel no longer quotes the assumed watts | ENG-E1/E3 (GR-10, CR-03) |
| Fixed | Analytics layout with Unknown FTP shows heart-rate zones instead of power zones | No zone claimed from an assumed FTP |
| Kept | Watch mirror: already sends no watt targets (checked) | |

## Strength workout (StrengthWorkout.swift, StrengthNextSet.swift)
| Change | What | Why |
|---|---|---|
| New | "Next set" card first: exercise, superset label (A1/A2), set n of m, target reps × weight, −/+ reps and weight, one-tap Log set, rest timer from the exercise's prescribed rest, working time against the session limit | "What's my next set?" |
| Simplified | Working-time / sets card and the "saved as you go" paragraph → one compact row (sets done, Pause/Resume, Discard) | Less text, less scrolling |
| New | Finish summary lists the top set per lift | Progress reads the same logged sets; no e1RM on this screen (ENG-D6) |
| New | "bodyweight · equipment not set" label on coach-built sessions while equipment is not set | ENG-H1 |
| Kept | Logging writes the same `StrengthSession.exercises[].sets[].done` as the set list; swap and edit go through the existing Phase 1 preview | Data integrity |

## Tests
- `OnboardingScreens.testOnboardingR7FiveScreens` now runs in every UI pass (one text size; both sizes in layout runs): step counter 1–5, no Height, Hybrid rows, week counts, Skip only on Connections, Why this plan, Create plan → Home without a health prompt.
- `RideViewsSmokeTests` (was RideLayoutsSmokeTests until build 176): step card present with an RPE target; new `testUnknownFTPRideShowsNoWatts`.
- `RideLayoutTests.testUnverifiedPowerAdviceIsProvisional`: expects the FTP UNKNOWN tag and no quoted assumed watts (was FTP PROVISIONAL).

## Checkpoint F — Ride milestone build (8 Nov 2026)
Slices 2 + 3 (Cockpit / Map / Performance, results page, ride history, one Apple Health workout per ride), the Daylight
ride display, APP-038 and APP-035. CI runs 190–194 on this tree: every test job green at least once each; the matrix
failures were one mini-map tap (fixed, 26c39353), weekend date edges in two tests, and three one-off simulator/XCUITest
flakes. Build 176 remains the accepted baseline until the owner approves this build after real-device testing.
