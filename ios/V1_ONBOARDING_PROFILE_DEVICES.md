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

## The 10-step journey (owner, 2 Nov) — `JourneyTests`, one run per persona

Personas: `testCyclingJourney` (Lina, cycling, endurance, no devices) · `testStrengthJourney` (Omar, strength, strength goal, no devices) · `testHybridJourney` (Sara, hybrid, endurance). The same ten steps, every assertion on data the screen shows.

| # | Step | Screen | Data assertion |
|---|---|---|---|
| 1 | Install, start onboarding | Welcome | `BC_UITEST_RESET` fresh store; `onboardingContinue` exists; **0 text fields** on Welcome |
| 2 | Personal details once | Stage A | exactly one field whose id contains "name"; DOB row says "not set"; no "Height"; Continue disabled until name + type |
| 3 | Type, experience, goals | Stage A → B | `onbMode-<type>` tapped; experience chip (2nd option) selected (`isSelected`); hybrid shows `onbPriority`; goal `goal-<id>` becomes "main goal"; `onbGoalEffect` shown; every `onb*`/`goal*` button changes the screen (sweep) |
| 4 | Availability and preferences | Stage C | coach proposal (`onbWeekCounts`) + `onbFeasibility`; tapping `cyDay-3` changes its label; ride/lift stepper changes the row; equipment chip selects; `onbPlanPreview` present; the 7 day sports are captured |
| 5 | Connect or skip | Stage D | a `deviceState-*` badge exists; **0 switches**; Skip proceeds |
| 6 | Personalised plan | Stage E | `onbStat-rides` / `onbStat-lifts` present only for the persona's sports; `onbStat-planned` non-empty; `cyDay-i` sports **equal the week built on C**; `onbFirst` names a session; `onbWhy` present |
| 7 | Approve → useful Home | Home | `homeWeek` present; no `onboardingContinue`, no `homeCaution`; `homeWeekDay-i` sports equal Stage E; today card; `homeFirstWeek` block with `cyHeroRing`, `homeGoal-<goal>`, `homeStartFirst` |
| 8 | Profile keeps every answer | Profile | header contains the name; `profileType` contains the type; `profileGoal` contains the main goal; `profileWeek` shows "N days" = training days from E; `profileEquipment` (lifters); `profileFTP` contains "Unknown" (riders); Type editor shows the stored type selected and **no name field** |
| 9 | Plan shows the approved schedule | Plan | `planDay-<weekday>` sports (Monday first) equal Stage E |
| 10 | Close and reopen | relaunch | no onboarding; Home week, Profile name + week, Plan week all equal the approved ones |

Recording: `ios/ci/build.sh` `record_journey <persona>` — `xcrun simctl io <sim> recordVideo --codec h264` runs around `JourneyTests` (filtered by `BC_JOURNEY_PERSONA`), ffmpeg downscales to 960 px / 20 fps when present, and the publish job copies `journey-<persona>.mp4` (< 15 MB) into `ci-logs/ios/run-N/`. The quick check records the hybrid journey; the full smoke job records all three and reports `RESULT journey (recorded)` (release-blocking).

## Answer → purpose (why each question exists)

| Answer | Stored field | Used by | Shown where |
|---|---|---|---|
| Name | `profile.name` | greeting, Watch/board rider label | Home header, Profile header, Stage E |
| Training type | `profile.trainingMode` | planner (which sessions exist), Progress tabs, which questions follow | Profile › Type & experience, Stage E counts |
| Cycling experience | `profile.level` | ride intensity distribution, starting ride structure | Profile › Type & experience |
| Strength experience | `strengthPrefs.experience` | exercise difficulty cap, rep ranges, first-session load discovery | Profile › Type & experience |
| Priority (hybrid) | `profile.priority` | which sport yields when time or recovery conflicts | Profile › Type & experience, Coach "why" |
| Date of birth | `profile.dateOfBirth` (+ `birthYear`) | max HR → HR zones (nil → effort targets) | Profile › Personal (with source + date), ride targets |
| Weight | `profile.weightKg` + provenance | W/kg, bodyweight-based loads (nil → discovery) | Profile › Personal, ride summary |
| Goals + main goal | `profile.goals`, `primaryGoal` | quality-ride type, rep ranges, goal indicators in Progress | Stage E, Home goals row, Profile › Goals, Progress › Goals |
| Week (days + sport) | `availability`, `preferredDays`, counts | planner day assignment (never overridden silently) | Stage C/E strips, Home week, Plan, Profile › Your week |
| Ride / lift length | `cyclingSessionMinutes` / `strengthSessionMinutes` | firm maxima for every session and ride step fitting | Stage E "planned", Plan sessions, Profile › Your week |
| Two-a-day | `availability` (two assignments) | lift-before-ride ordering, interference spacing | Stage C, Plan |
| Equipment preset | `equipment` | exercise selection (provisional bodyweight until confirmed) | Profile › Equipment, strength sessions |
| Supersets | `strengthPrefs.prefersSupersets` | session structure and time estimate | Profile › Preferences, strength session |
| FTP (+ source) | `profile.ftp*` via `setFTP` | watt targets only when known; board/Watch get 0 when Unknown | Profile › FTP, ride targets |
| Devices (Stage D) | nothing stored by the cards themselves; pairing goes through the real link flows | live data sources | Devices & sensors, Home "Getting started" |

## What reuses what

- `AthleteTypeEditor` — onboarding Stage A; Profile › Personal (`[.name, .personal]`) and Profile › Type & experience (`[.type, .experience]`).
- `GoalCardsEditor` — Stage B; Profile › Goals.
- `WeekBuilder` — Stage C; Profile › Your week; Plan › Your week sheet and the hybrid editor's "days" sheet now open the same `WeekPage(asSheet:)` (the old `AvailabilityEditor` remains only inside the Fix-plan flow).
- `DeviceCardList` / `DeviceCards.build` (pure) — Stage D; Profile › Devices & sensors; Ride › Manage (`ConnectionsView` is now a thin wrapper around `DevicesScreen`). The old `DevicesConnectionsRows`, `ProfileHeaderRow`, `GoalPage`, `WeeklyTimePage` are removed (no duplicate settings pages).
- Device states come only from `SensorHub.deviceStates` (`DeviceStateRules`, S2-0): Not connected / Paired / Connected / Receiving live data / Problem. `DeviceState.cy` maps to the badge and falls back to "problem" for a case added later (e.g. `.stale`).
- Profile root: compact header card → Personal; Training & goals; Week & preferences (Your week, Equipment, FTP, Heart rate, Preferences); Devices & data; App (Health & safety, Settings). Units/appearance/notifications/Ride & coach/data export & delete/About live in Settings only.

## Tests

- Linux harness (`tools/coach-harness/test.sh`, +`OnboardingDraft.swift`, +`OnboardingDraftTests`): 287 tests, 0 failures — `OnboardingAnswersMappingTests` (every answer lands; no answer invents nothing; FTP stays Unknown without a valid number; equipment not-sure stays provisional; type switch keeps days), `OnboardingWeekTests` (proposal per type, tap cycle, feasibility never blocks an athlete's week, **the preview is the same deterministic planner run Approve saves**, goal info covers every goal), `DeviceCardsTests` (real states, only supported actions, strength-only hides the board).
- UI (CI simulator, not yet run): `JourneyTests` (three personas, the 10-step table above, recorded) and `OnboardingScreens.testOnboardingV3FiveStages` — welcome has no input; exactly one name field; Continue gating; goal effect; week strip + live preview + a day tap changes the day; Skip on D; Approve → Home shows the week, no health prompt, onboarding never reappears; **Plan contains the first workout shown on E**. `LaunchSmokeTests` (export/delete via Profile › Settings), `LayoutAudit` (Profile lower, Type & experience, Your week, Devices pages; BikeComputer page via Profile › Devices).

## Known gaps

- Home's first-week block (`HomeFirstWeek.swift`) covers the first week only (plan counts, goals with "progress appears after your first logged session", next steps); the full Home dashboard is V3. "Add heart rate" opens the Profile tab (Devices is one tap further) — a direct deep link comes with V3.
- The `JourneyTests` button sweep taps up to 12 `onb*`/`goal*` buttons per stage and requires a visible change; it is a no-op detector, not a semantic test of each control.
- Recording depends on the runner: `simctl io recordVideo` and (optionally) ffmpeg; if ffmpeg is absent the raw file is kept and may exceed the 15 MB publish cap, in which case the artifact still holds it.

- Not compiled for iOS here: first compile is the CI quick run. Risk spots: `WeekPage.body` (`let` + `if asSheet` in a ViewBuilder), `DeviceCardList.card` (`@ViewBuilder` with a local `let`), `AthleteTypeEditor.chips` generic helper, `CySegmentedControl` tuple literals, `@unknown default` on a same-module enum (warning).
- No UITestSupport seed for device states (cards are screenshot with the simulator's real states: Not connected / problem); the badge states themselves are covered by `DesignSystemAudit`.
- The hybrid editor (`HybridPlanEditor`) and Fix-plan still use the older `AvailabilityEditor` internally.
- Onboarding writes through the store on every keystroke (as before); plan version 1 is recorded on Approve with cause `.profile`.
