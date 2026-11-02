# V1 — Onboarding v3, Profile, Devices (Stage 2, branch `impl/v1`)

Status: implemented locally on top of S2-0 (`impl/s2` @ 9b57d26). Linux harness 287/0. **Not compiled for iOS yet; not simulator-tested; nothing hardware-tested.** Design: `/home/claude/gate1/v3` (owner-approved direction, 2 Nov).

## Flow and interaction count

| Stage | Screen | Interactions (typical) | Notes |
|---|---|---|---|
| Welcome | Brand, one line, *Get started* | 1 | No input anywhere (name is never asked here). |
| A · Who you are | Name (once) · three athlete-type cards · experience chips under the chosen type (cycling / strength kept separate) · hybrid priority · date of birth ("for heart-rate zones") · weight ("for loads and W/kg") | 3–7 | *Continue* waits for name + type. DOB/weight optional, start blank; Apple Health weight is **offered** only if already authorized, never applied silently. |
| B · Goals | Goal cards per sport + general; first tap = main goal; ★ moves it; effect line + emphasis bar for the main goal | 1–3 | *Continue* waits for one goal. |
| C · Your week | Coach's proposal from A+B; tap a day to cycle ride → lift → (both) → rest; ride/lift length steppers; two-a-day (hybrid); equipment chips; supersets; feasibility line; **live plan preview = `PlanEngine.week` dry run** | 0–3 | The proposal is never silently overridden; "Coach's proposal" restores it. *Continue* only blocked with no training day. |
| D · Ecosystem | Device cards from the real `SensorHub.deviceStates`; FTP *Don't know / I know it* | 1 (Skip) or 1 per device | Only supported actions: Apple Health → permission request; BikeComputer → `DeviceLink.connect()`; strap/power/cadence → the Bluetooth pairing sheet; Watch → its detail page. |
| E · Training system | Goal chips, week strip, rides/lifts/planned time, first workout card, three-line approach; *Edit week* / *Approve plan* | 1 | Approve = plan version 1 from the same inputs the preview used; Home and Plan read `store.plan`. |

Minimum 8 interactions (start, name, type, goal, accept week, skip, approve + nothing else), typical 10–13 → about 60–90 s. Resume: stages are stored as 101…105 (build-121 stages still map); answers already given are read back from the profile.

## Field → destination (one authoritative profile)

`OnboardingAnswers.apply(to: PlanInputs)` (OnboardingDraft.swift) is the only mapping; onboarding calls it on every change, the Profile editors call it inside `Store.changeTraining` (plan preview). A field left nil never writes a value.

| Answer | Destination | Missing → |
|---|---|---|
| Name | `profile.name` (trimmed) | "" (Continue blocked in onboarding) |
| Training type | `profile.trainingMode`; priority forced to cycling/strength for single-sport, `priority ?? .balanced` for hybrid | unchanged |
| Cycling experience | `profile.level` | the stored level (the chip shown is the answer) |
| Strength experience | `strengthPrefs.experience`, clears `confirmStrengthLevel` | nil → Beginner dose (never copied from cycling) |
| Priority | `profile.priority` | balanced |
| Date of birth | `profile.setDateOfBirth` (+ `birthYear` for the board), provenance `.entered` + date | nil → no HR zones (effort targets) |
| Weight | `profile.setWeight(source: .entered)` + date; Health sample keeps `.appleHealth` under the precedence rule | nil → no W/kg, no load from bodyweight |
| Goals + main goal | `profile.goals`, `profile.primaryGoal`, and the planner's `profile.goal` / `strengthPrefs.goal` kept in step | unchanged (Continue blocked) |
| Week | `availability` (one assignment per session at the session length), `weekIsExplicit = true`, `preferredDays`, `trainingDaysPerWeek`, `cyclingDaysPerWeek`, `liftDaysPerWeek`, `hoursPerWeek`, `liftingHoursPerWeek` | — |
| Ride / lift length | `cyclingSessionMinutes` / `strengthSessionMinutes` (firm maxima) | 60 / 30 only when a week is written without them |
| Equipment preset | `equipment` (gym kit / home kit / bodyweight confirmed / not sure = provisional) | provisional bodyweight plan |
| Supersets | `strengthPrefs.prefersSupersets` | nil |
| FTP | `profile.setFTP(w, .entered)` only with 50–600 W typed; *Don't know* → `setFTP(nil, .unknown)` | Unknown — never 200/225 W |

## What reuses what

- `AthleteTypeEditor` — onboarding Stage A; Profile › Personal (`[.name, .personal]`) and Profile › Type & experience (`[.type, .experience]`).
- `GoalCardsEditor` — Stage B; Profile › Goals.
- `WeekBuilder` — Stage C; Profile › Your week; Plan › Your week sheet and the hybrid editor's "days" sheet now open the same `WeekPage(asSheet:)` (the old `AvailabilityEditor` remains only inside the Fix-plan flow).
- `DeviceCardList` / `DeviceCards.build` (pure) — Stage D; Profile › Devices & sensors; Ride › Manage (`ConnectionsView` is now a thin wrapper around `DevicesScreen`). The old `DevicesConnectionsRows`, `ProfileHeaderRow`, `GoalPage`, `WeeklyTimePage` are removed (no duplicate settings pages).
- Device states come only from `SensorHub.deviceStates` (`DeviceStateRules`, S2-0): Not connected / Paired / Connected / Receiving live data / Problem. `DeviceState.cy` maps to the badge and falls back to "problem" for a case added later (e.g. `.stale`).
- Profile root: compact header card → Personal; Training & goals; Week & preferences (Your week, Equipment, FTP, Heart rate, Preferences); Devices & data; App (Health & safety, Settings). Units/appearance/notifications/Ride & coach/data export & delete/About live in Settings only.

## Tests

- Linux harness (`tools/coach-harness/test.sh`, +`OnboardingDraft.swift`, +`OnboardingDraftTests`): 287 tests, 0 failures — `OnboardingAnswersMappingTests` (every answer lands; no answer invents nothing; FTP stays Unknown without a valid number; equipment not-sure stays provisional; type switch keeps days), `OnboardingWeekTests` (proposal per type, tap cycle, feasibility never blocks an athlete's week, **the preview is the same deterministic planner run Approve saves**, goal info covers every goal), `DeviceCardsTests` (real states, only supported actions, strength-only hides the board).
- UI (CI simulator, not yet run): `OnboardingScreens.testOnboardingV3FiveStages` — welcome has no input; exactly one name field; Continue gating; goal effect; week strip + live preview + a day tap changes the day; Skip on D; Approve → Home shows the week, no health prompt, onboarding never reappears; **Plan contains the first workout shown on E**. `LaunchSmokeTests` (export/delete via Profile › Settings), `LayoutAudit` (Profile lower, Type & experience, Your week, Devices pages; BikeComputer page via Profile › Devices).

## Known gaps

- Not compiled for iOS here: first compile is the CI quick run. Risk spots: `WeekPage.body` (`let` + `if asSheet` in a ViewBuilder), `DeviceCardList.card` (`@ViewBuilder` with a local `let`), `AthleteTypeEditor.chips` generic helper, `CySegmentedControl` tuple literals, `@unknown default` on a same-module enum (warning).
- No UITestSupport seed for device states (cards are screenshot with the simulator's real states: Not connected / problem); the badge states themselves are covered by `DesignSystemAudit`.
- The hybrid editor (`HybridPlanEditor`) and Fix-plan still use the older `AvailabilityEditor` internally.
- Onboarding writes through the store on every keystroke (as before); plan version 1 is recorded on Approve with cause `.profile`.
