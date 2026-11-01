# RC3 engine API for the screens (onboarding r7, Profile, Plan, Progress, Ride, pause)

Branch `impl/rc3`. All engine code is in `Rc3Engine.swift` unless noted. Linux harness: 241 tests, 0 failures (local only).

## 1. Profile fields (`RiderProfile`, Models.swift) — all optional, build-121 files load unchanged

| Field | Type | Use |
|---|---|---|
| `dateOfBirth` | `Date?` | r7 S1. When set, also set `birthYear` (the board still receives the year). `ageFromBirth: Int?` |
| `goals` / `primaryGoal` | `[GoalID]` / `GoalID?` | r7 S2. Write through `store.setGoals(_:primary:) -> PlanInputs` (keeps `goal` and `strengthPrefs.goal` in step), then propose (§3) |
| `legacyGoal` | `String?` | Read-only: original value a merge replaced ("aerobicFitness" → Endurance) |
| `weekIsExplicit` | `Bool?` | Set `true` when "Your week" saves per-day minutes: those minutes are firm (no weekly-hours trimming) |
| `confirmSessionLength` / `confirmStrengthLevel` | `Bool?` | Migration flags: ask once in Profile › Training, then set to nil |
| `trainingPause` / `pauseHistory` | `TrainingPause?` / `[DateInterval]` | Use `store.pauseTraining(reason:)` / `store.resumeTraining()` |
| existing: `cyclingSessionMinutes`, `strengthSessionMinutes`, `preferredDays`, `trainingMode`, `priority`, `level` (cycling) | | r7 S1/S3 |

Other inputs: `store.strengthPrefs.experience` (**strength level**; nil = Beginner dose, never copied from cycling), `store.strengthPrefs.prefersSupersets: Bool?`, `store.equipment` (`EquipmentProfile(owned:excluded:confirmed:)`; `confirmed: true` with empty `owned` = "Bodyweight only"; not set = "Not sure yet" → `isProvisional`, bodyweight plan), `store.availability` (`WeeklyAvailability`, 7 days Monday first; one `DayAssignment(sport: .cycling/.strength, minutes:)` per session; two on a day = Both).

`GoalID`: `.endurance .power .sprint .climbing .event` (cycling) · `.muscle .strength .stamina .maintain` (strength) · `.fitness`. `title`, `sport`.

## 2. FTP (ENG-E1)

```swift
profile.ftpSource      // FTPSource: .unknown / .entered / .estimated / .tested
profile.ftpKnown       // false for the build-121 assumption
profile.ftpValue       // Int? — nil when unknown
profile.ftpDisplay     // "250 W" or "Unknown"
profile.targetFTP      // Int? for watt targets (nil = no watts anywhere)
profile.setFTP(_ watts: Int?, source: FTPSource)   // "I don't know" = setFTP(nil, source: .unknown)
```
`ftpLabel` / `ftpBadge` return "Unknown"/"unknown" for the assumption. **Do not show `ftpW` directly** when `!ftpKnown`.

Known UI spots still reading `ftpW` (UI fork): `ProfileView` (rows 22/32/247), `ProgressView` (60/106/265), `OnboardingView` (old FTP step), `Ride/RideLive.swift:44/123` (Zone tile from power uses `ftpW` — should hide the power zone when `!ftpKnown`), `RideDashboard.swift:153/172` (live coach bands — pass `targetFTP ?? 0` and treat 0 as no power band).

## 3. Plan changes (ENG-J2/J3) — every change to planning inputs goes through a preview

```swift
// returns nil when nothing that affects the plan changed (then it was saved directly)
let id: UUID? = store.proposePlanChange(cause: .days) { inputs in inputs.availability = newWeek; inputs.profile.weekIsExplicit = true }
if let id { sheet = PreviewRef(id: id) }            // present PlanChangeSheet(proposalId: id) { onApplied }
store.pendingPlanChanges[id]                        // PlanChangeProposal: before / after / kept / summary / changesSessions
store.applyPlanChange(id) -> Bool                   // false = stale (a session in scope changed) → nothing saved
store.discardPlanChange(id)
store.planVersions                                   // [PlanVersion], append-only (cause, createdAt, effectiveDate, before, after, summary)
store.proposeUndo(version:) -> UUID?                 // Undo is a new previewed proposal
```
Causes: `.edit .equipment .days .minutes .goal .priority .split .strengthLevel .ftp .coach .profile .migration .undo`.
Views ready in `SessionChangePreview.swift`: `PlanChangeSheet(proposalId:onApplied:)`, `PlanChangeContent`, `PlanVersionsView()` (Plan › Plan changes, read-only + Undo), `PlanVersionDetail`.
Scope: today's unfinished sessions and future open sessions; a day with a done / started / logged / hand-edited / fixed session is kept (listed under "Kept as they are"). Completed workouts and logs are never touched.

Single-session edits keep the Phase 1 path: `store.requestEdit(w, prefersSupersets:) -> EditOutcome` (`.saved` / `.preview(id)` / `.refused(text)`) → `SessionChangeSheet(proposalId:)`.

## 4. Ride steps (ENG-E3/E5)

```swift
workout.rideSteps                     // [RideStep]: name, minutes, role (.warmUp .steady .work .recover .easy .coolDown .test), rpe, hrZone, powerFraction
step.targetText(ftp: profile.targetFTP, hrZones: hasHR ? profile.hrZones : nil)   // "214–229 W · RPE 5–6 · HR Z3 …" / "RPE 5–6"
step.watts(ftp: profile.targetFTP)    // nil when unknown
workout.steps(ftp: profile.targetFTP ?? 0, hrZones:)   // display rows (intervals collapsed), durations sum to minutes
workout.fittedIntervalReps            // reps that fit; liveIntervalPlan uses them
RideSteps.pairHRHint                  // "Pair a heart-rate strap for heart-rate targets"
```

## 5. Progress (ENG-D6 / K1)

```swift
store.liftSummaries(since:) -> [LiftSummary]   // per lift: topSets [LiftPoint(date, weightKg, reps, e1RM?)], latest, qualifyingSessions, e1RMTrendAvailable (≥ 3)
StrengthPerformance.e1RM(weightKg:reps:rpe:)    // Brzycki, r_eff = reps + (10 − RPE); nil unless RPE ≥ 8 and 1 ≤ r_eff ≤ 10; label "Est."
store.checkpoints(.cycling / .strength, now:) -> [Checkpoint]   // weeks 4/8/12: reached, countedWeeks, sessions, earliestDate, missing ("1 more ride · 2 more weeks"), performance (.improved .flat .declined .notEnoughData)
store.completedDates(.cycling/.strength)          // one source for "done" counts
Checkpoints.adherence(plan:completedIds:pausedWeeks:from:to:)   // done ÷ planned per week (plan version in force), paused weeks excluded
store.pausedWeeks(now:)
```
Rules: clock starts at the first completed session of that sport; a checkpoint needs N counted weeks AND N sessions; cycling performance needs two FTP values from FTP-test rides with verified power (entered values never count). Never show e1RM on the workout screen.

## 6. Health and pause

- An unanswered health check no longer restricts anything (`CoachReadiness.vigorousAllowed` true for `.notAnswered`). Saved answers keep their rules. See `SAFETY_CHANGES_RC3.md`.
- `store.pauseTraining(reason: .unwell/.injured/.away)`, `store.resumeTraining()`; Home shows `HomeHold.paused` ("Training paused · Resume training"). `TrainingPauseView()` (HomeSheets.swift) is the pause / resume form for Profile › Settings.
- Home's hold button still sends `.reviewHealth`; `HealthCheckSheet` shows the pause form when the athlete paused, the old form otherwise.

## 7. Cross-system (no firmware change)

- Board: `linkMessage` sends FTP 0 when unknown (how = assumed). **Known firmware-side conflict (CR-04):** the board then computes its own starting FTP from weight × experience and shows it as PROVISIONAL. Needs a firmware change (not made).
- Goal codes: Endurance ↔ link 1 ✓. **Known gap (CR-07):** the link has no FTP/power goal code; phone "Power"/"Sprint" are sent as Fitness (0).
- Board-guided rides with unknown FTP: no HR/effort step protocol exists in Link 1.2; the board's coach band uses its own FTP. Hardware gate (AT-E1-4, HW) — not tested.
- Watch mirror sends no watt targets (checked).
- Health pause / user pause are not sent to the Watch or board (GR-13/14, unchanged).
