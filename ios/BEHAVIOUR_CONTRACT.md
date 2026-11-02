# Cyclift — behaviour contract (approved design, Stage 2)

Owner instruction, 2 Nov 2026 14:11: one approved behaviour per critical workflow. Tests verify THIS contract, not whatever the
code happened to do before. Where the code or a test deviates, it is listed here as a deviation or an outdated-test candidate —
nothing is changed by this document.

Sources of truth: the owner's decisions (1 Nov: plan changes touch only the current unfinished and future sessions, after a
before/after preview and Apply; completed history is immutable; plan versions are kept with Undo; top set primary, estimated
1RM secondary; checkpoints count from the first logged session. 2 Nov: weekly completion on Home; unknown stays unknown;
provenance on every measurement; device states incl. stale), `/home/claude/gate1/v3/SCREENS.md`, `WORKFLOW.md`,
`IMPLEMENTATION_PLAN.md` (D1–D9, V1–V10), `ios/S20_DATA_INTEGRITY.md`, `ios/V1_ONBOARDING_PROFILE_DEVICES.md`.

Test levels: **Host** = Linux harness (`tools/coach-harness/test.sh`, pure engine); **Unit-sim** = `BikeComputerTests` on the CI
simulator; **UI-sim** = `BikeComputerUITests` on the CI simulator; **Device** = real iPhone / Watch / BikeComputer (none yet).
Evidence is only the test level named; nothing below is hardware-tested.

Persistence: everything the app keeps is one `StoreFile` (schema 4) written by `Store.persist()`; keys named below are its
properties (`profile`, `plan`, `rides`, `strength`, `availability`, `equipment`, `strengthPrefs`, `planVersions`,
`pendingProposals` are never persisted, `settings`, `onboarded`, `onboardingStage`, `healthReads`, `trash`).

---

## W1 · First launch and onboarding

| | Contract |
|---|---|
| User sees | Welcome (brand, one line, *Get started*; no input) → A *Who you are* (name once; three athlete-type cards; experience chips for the chosen type; hybrid priority; optional date of birth and weight with a one-line reason, blank until typed/picked) → B *Goals* (cards; first tap = main goal, ★ moves it; effect line + emphasis bar) → C *Your week* (coach's proposal; tap a day to cycle ride → lift → both → rest; ride/lift length; two-a-day; equipment; supersets; feasibility line; live plan preview) → D *Connect* (device cards with real state; Skip) → E *Your training system* (goals, week strip, counts, planned time, first workout, three-line approach; *Edit week* / *Approve plan*). |
| Interaction → result | Every answer is written through `OnboardingAnswers.apply(to:)` (`OnboardingDraft.swift`) — the only mapping. Nothing left blank writes a value (no 35 y, 75 kg, 200/225 W). *Approve* generates this week and next from exactly the inputs the Stage E preview used, records plan version 1 (`cause: .profile`), sets `onboarded = true`, `onboardingStage = 0`. Resume: stages 101–105 restore the screen and read answers back from the profile. An onboarded user never sees onboarding again. A denied permission on D never blocks Continue. |
| Data changed | `profile.name`, `trainingMode`, `level`, `strengthPrefs.experience`, `priority`, `dateOfBirth`/`birthYear` (+provenance `.entered`+date), `weightKg` (+provenance), `goals`/`primaryGoal` (+ planner `goal`), `availability` (one assignment per session at the session length), `weekIsExplicit`, `preferredDays`, day counts, `cyclingSessionMinutes`/`strengthSessionMinutes`, `equipment` (not sure = provisional), `strengthPrefs.prefersSupersets`, FTP via `setFTP` (typed 50–600 W → `.entered`; *Don't know* → `.unknown`). |
| Saved where | `profile`, `availability`, `equipment`, `strengthPrefs`, `plan` (on Approve), `planVersions[0]`, `onboarded`, `onboardingStage`. |
| Screens / devices updated | Home (first-week block, week strip, today card), Plan (same `store.plan`), Profile (every row reads the same fields), Coach "why". BikeComputer gets `PROFILE_SET` on the next sync with 0 for every unknown; the Watch gets the rider label; neither receives a derived number. |
| Verifying tests | Host: `OnboardingAnswersMappingTests` (`testNoAnswersChangeNothingAndInventNothing`, `testEveryAnswerLandsInItsField`, `testModeSetsPriorityAndNeverTouchesOtherSports`, `testFTPStaysUnknownWithoutAValidNumber`, `testEquipmentNotSureStaysProvisional`, `testSwitchingTypeKeepsTheDays`), `OnboardingWeekTests` (`testProposalIsRealisticForEachType`, `testTapCycleAndFeasibility`, `testPreviewIsTheSamePlannerRunApproveSaves`), `NoFabricatedDefaultsTests.testFreshProfileHasNoSampleValues`. UI-sim: `JourneyTests.testCyclingJourney/testStrengthJourney/testHybridJourney` (10 steps incl. relaunch), `OnboardingScreens.testOnboardingV3FiveStages`, `LaunchSmokeTests.testFreshInstallShowsWelcome`. Device: none. |
| Known deviations today | `OnboardingView.approve()` (`OnboardingView.swift:344`) regenerates and appends the version itself instead of going through `proposePlanChange` — acceptable for the first plan (nothing to preview) but it is a second code path; onboarding writes the profile on every keystroke (not a draft) — an abandoned onboarding leaves partial answers, which the resume rule reads back (intended). |

## W0 · Evaluation is pure (owner, 2 Nov — applies to every workflow below)

- Any computation that only needs an answer (feasibility, "what would happen", a preview being built) goes through
  `Store.evaluateSessionChange` / a pure report and writes **nothing**: no `pendingProposals`, `lastProposalId`, `plan`,
  `trash`, `undoToast`, `planVersions`, no persistence. Only a user action registers a proposal (`proposeSessionChange`,
  `proposePlanChange`), and only Apply changes the plan.
- The athlete's own pending preview (`lastProposalId`) is never evicted by other proposals (coach, Home swap, background)
  or by the hour limit; the table bound of 20 applies to the rest.
- Cancel and a blocked validation leave `plan`, `planVersions` and `trash` equal; background refreshes never touch
  hand-edited, completed or fixed sessions and never add a plan version; Health import is idempotent.
- Verifying tests: `EngineSideEffectTests` (6), `testFeasibleMinutesDryRunLeavesPendingProposalsAlone`. Audit and deferred
  items (D-SE-1…6): `ios/ENGINE_SIDE_EFFECTS_AUDIT.md`.

## W2 · Profile edits

| | Contract |
|---|---|
| User sees | Compact header card → grouped rows with the current value → a focused editor per row (the same editors as onboarding: `AthleteTypeEditor`, `GoalCardsEditor`, `WeekBuilder`). Personal: name, date of birth (age · source · date), weight (value · source · date; manual override; which value wins), FTP (value · source or "Unknown"), heart rate. No long form of segmented controls. |
| Interaction → result | Save in an editor → `Store.changeTraining(cause:)` → `proposeOrApplyPlanChange`: if nothing planning-related changed, saved directly; if inputs changed but no planned session changes, saved with a plan version and no extra screen; if planned sessions change → `PlanChangeSheet` before/after preview; Apply saves inputs + sessions together; Cancel saves nothing. Name, units, appearance, notifications never trigger a preview. |
| Data changed | The same fields as W1 via the same mapping; FTP/weight/DOB carry provenance `.entered` + date (Apple Health weight keeps `.appleHealth` under the precedence rule, W9). |
| Saved where | `profile`, `availability`, `equipment`, `strengthPrefs`; `plan` + `planVersions` only through Apply. |
| Screens / devices updated | Home, Plan, Progress read the store; BikeComputer `PROFILE_SET` on next sync (unknown → 0). |
| Verifying tests | Host: `Rc3EngineTests.testProposeOrApply_NonPlanningChangeSavesDirectly`, `testProposeOrApply_SessionChangeNeedsPreview`, `testAT_H1_2_J2_1_EquipmentChangeIsAPreviewedProposal`, `testAT_A1_1_StrengthLevelIsItsOwnAnswer`, `S20 ProfileApplyRecordsSourceAndDate`. UI-sim: `JourneyTests` step 8 (every answer retained; Type editor shows the stored type, no name field), `LayoutAudit.testKeyScreensAtTextSizes` (Profile pages), `LaunchSmokeTests.testUpgradeFromBuild40YourDataExportAndDeleteCancelKeepsData`. **MISSING**: a UI-sim test that edits a plan-affecting setting from Profile, sees the preview, applies, and checks Plan + a new plan version. |
| Known deviations today | Equipment is proposed when the Equipment page closes (`ProfileScreens.swift:158`) — cancelling the preview discards the edit silently (known issue 4). "Add heart rate" on Home opens the Profile tab, not Devices. |

## W3 · Plan: single-session edit (Phase 1 rebuild fix)

| | Contract |
|---|---|
| User sees | Session detail → Edit (type, duration, focus, supersets) → *Review the change* sheet: title, time line (limit, estimated, sets), "Please check" items, After, Before, "This week" consequences, Why; Cancel / Apply. A blocked change shows the conflict and real alternatives (keep as planned, allow N min, set equipment, rebuild without routine) — never a relabel, never a different split. |
| Interaction → result | `Store.requestEdit(w)` → `.saved` (insignificant change), `.preview(id)` (significant: propose → validate → preview), `.refused(text)` (already logged). Apply = `commit(proposalId:confirmed:)` with compare-and-swap on the session fingerprint and context hash: `.applied`, `.stale` (re-proposed, nothing saved), `.blocked`. Cancel = `discardProposal` — the session is byte-identical to before. Apply records a plan version (`cause: .edit`); logged sets are kept exactly. |
| Data changed | `plan[i]` (entries, minutes, kind/focus, `riderChoice`, `entriesHandEdited`), `planVersions += 1`. Never `strength` logs. |
| Saved where | `plan`, `planVersions`. |
| Screens / devices updated | Plan, Home today card, Strength workout screen, Progress planned counts. Watch mirror of the day's session (when it exists) on next sync; board planned ride re-send is **not implemented** (CR-09, firmware spec). |
| Verifying tests | Host: `Rc3EngineTests.testPhase1EditRebuildsTheSessionAndCancelLeavesItIdentical`, `testStaleProposalIsRefused`, `RebuildValidatorTests` (Phase 1 suite), `testAT_J2_4_HandEditedSessionKept`. UI-sim: `LayoutAudit.testKeyScreensAtTextSizes` opens the detail; **MISSING**: a UI-sim test that opens the preview (`changePreview`), taps `changeCancel` and asserts the session unchanged, then `changeApply` and asserts the new prescription on Plan and the version in Plan changes. |
| Known deviations today | none known in the engine; UI evidence is screenshot-only. |

## W4 · Plan: week / availability change and Fix plan

| | Contract |
|---|---|
| User sees | Plan › *Your week* → the same `WeekBuilder` as onboarding (sheet) → Save → preview if planned sessions change. Plan › *Fix plan* (only when a budget is exceeded): per conflict, actions that really change something — shorten a remaining session, skip it, raise the budget, edit days, keep. |
| Interaction → result | Week save → `changeTraining(cause: .days)` → preview → Apply (W2 rule). Fix plan: **shorten** a strength session = a rebuild (`requestEdit`) → preview → Apply (never a relabel); **skip** = hand edit with Undo (trash record, `setSkipped`); **raise budget** = profile change → **contract: previewed like any planning input** (D-decision: every plan-affecting change is previewed) ; "Undo" on the Fix-plan sheet reverts only direct hand edits (skip); a previewed change is undone from *Plan changes* (W3 Undo). |
| Data changed | `availability`, `profile.hoursPerWeek`/`liftingHoursPerWeek`, `plan` (future open sessions only), `planVersions`, `trash` (skip). |
| Saved where | as listed; `pendingPlanChanges` never persisted. |
| Screens / devices updated | Plan, Home week strip, Profile › Your week, Progress planned counts. |
| Verifying tests | Host: `Rc3EngineTests.testAT_J2_1_DaysMoveTuesdayToThursday`, `testAT_C1_1_CyclingOnlyUsesMarkedDays`, `testAT_C1_2_NoSessionOnARestDay`, `testAT_C2_2_PerDayOverrideKept`, `ModelTests.testWeekIsBuiltAroundAvailability`, `testOverHoursSuggestsAdjustmentsInsteadOfCutting`. UI-sim: `LayoutAudit.testRC2OwnerScreens` (Fix plan — see outdated candidate), `LaunchSmokeTests.testUpgradeFromBuild33OpensHybridSheetsAtLargeText` (opens the week editor). **MISSING**: UI-sim test of Fix plan → shorten → preview → Apply → Plan shows the shorter rebuilt session and a version entry. |
| Known deviations today | `FixPlanSheet.apply(.raiseBudget)` and the "Raise the budget" button save directly without a preview (`AvailabilityEditor.swift:60-61, ~262, ~290`; known issue 2); Fix plan still uses the old `AvailabilityEditor` for "Edit my training days" instead of `WeekPage`. |

## W5 · Missed session handling

| | Contract |
|---|---|
| User sees | Home shows the most recent missed session (+ "n more in Plan") with *Move* and *More* (skip); a rest day with a missed session offers *Move to today*. Move targets: today, or a later day THIS week with no open training session; each target shows what is already there and a warning ("two on one day", "next to another hard ride"). |
| Interaction → result | `reschedule(id, to:)` — hand edit, keeps time of day, refused for completed sessions or days outside the week, Undo toast restores exactly (trash record). `setSkipped` likewise. Nothing is crammed automatically; the coach never moves sessions on its own. Last week's missed sessions still count as "a plan exists" on Monday (GR-54 fix). |
| Data changed | `plan[i].date` / `.skipped`, `riderEdited`, `trash`, `undoToast` (transient). |
| Saved where | `plan`, `trash`. |
| Screens / devices updated | Home, Plan, Progress adherence (a moved session counts on its new day; a skipped one is not planned). |
| Verifying tests | Host: `HomeBTests.testFirstMultiMissedAndFree`, `testRescheduleToAFreeDayWithUndo`, `testSkipFromMoreHasUndoAndIsARiderEdit`, `testWeekCountsAgreeOnHomePlanAndProgress`, `AdaptationEngineTests` (missed-session adaptation). UI-sim: `LayoutAudit.testHomeStates` (missed state screenshot + controls). **MISSING**: UI-sim test that moves a missed session and asserts Home, Plan and Progress agree (owner Example 3). |
| Known deviations today | No cross-week carry-over (a missed session is not offered into next week — by design for now). Recovery warning is heuristic (zone ≥ 4 neighbours). |

## W6 · Train now: ride

| | Contract |
|---|---|
| User sees | Pre-ride: device cards with real state, today's ride with targets. Targets follow the FTP source: Entered/Tested/Estimated → watts (tagged); Unknown → heart-rate zones if max HR known, else RPE only ("Pair a heart-rate strap…"). Live: current step, target, time left, next step, HR + zone, power only with a real source, cadence, time/speed/distance; connection and data-quality status; sensor lost / Watch lost / board lost / offline states; pause/stop. Summary: time, distance, HR, energy with its real unit and source. |
| Interaction → result | Start → `RideRecorder.start()` (phone) or board control; a board ride cannot be started over by the phone; stop → `RideRecord` → `addRide` (dedupe by board ride id / record id), closes the first open planned ride of the day; `considerFTP` may create an **FTP proposal** (never auto-applied, < 2 % ignored). Disconnect: recording continues on the device that records; reconnection merges once. |
| Data changed | `rides += 1`, `plan[i].done/completion`, `ftpSuggestion` (proposal), `profile.ftp*` only when the athlete applies. |
| Saved where | `rides`, `plan`, `ftpSuggestion`, `profile`. |
| Screens / devices updated | Home (ride done), Plan, Progress (riding time, FTP tag, checkpoints), Watch mirror (never carries watts), board `PROFILE_SET` only after an applied FTP (unknown → 0). |
| Verifying tests | Host/Unit-sim: `Rc3EngineTests.testAT_E1_1_UnknownFTPHasNoWatts`, `testAT_E1_3_EnteredFTPGivesTaggedWatts`, `testAT_E3_1_UnknownFTPTempoTargetsEffortAndHR`, `testAT_E5_*` (steps fit), `S20 testRideTargetsAreEffortOnlyWithoutFTPOrMaxHR`, `testBoardMessageSendsZeroForUnknowns`, `ModelTests.testFTPIsProposedNeverAutoApplied`, `testNoDuplicateRidesAndSingleOwner`, `testPhoneRideCannotStartOverBoardRideAndOwnerIsFixed`, `testImportBoardRideMergesMirrorAndDedupes`, `testSuspensionBecomesGapNotInterpolation`, `SyncMergeTests`, `BCLinkTests`, `WatchMessageTests`, `EnergyUnitTests`. UI-sim: `RideLayoutsSmokeTests.testSwitchThroughAllRideLayouts`, `testUnknownFTPRideShowsNoWatts`. Device: **none** (HR strap, power meter, Watch, board all untested on hardware). |
| Known deviations today | BikeComputer firmware ≤ 0.7.x invents its own starting FTP from a known weight and auto-applies 0.95 × best 20 min (CR-04/05; firmware correction spec, not flashed); planned rides are not sent to the board (CR-09); the pause state is not sent (GR-13). |

## W7 · Train now: strength

| | Contract |
|---|---|
| User sees | Exercise-by-exercise: name, short instruction, set n of m, target reps/load where justified (first session = discovery, no invented load), log actual weight × reps in one tap with compact steppers, rest timer, superset A1/A2, skip / replace / modify (replace → W3 preview), complete → summary (per-lift top set vs last time, volume). No estimated 1RM on the workout screen. |
| Interaction → result | Start → `startStrengthSession` (refused if another is active, the session is done, or it is planned for a later day). Log set → `activeSession` (transient until finish). Finish → `finishActiveSession(rpe:notes:)` keeps only done sets, drops empty exercises, saves `StrengthSession` with `workoutId`, marks the planned session done. Finishing nothing saves nothing. A completed session is immutable afterwards (edit → refused with "add a new session"). |
| Data changed | `activeSession` → `strength += 1`, `plan[i].done`. |
| Saved where | `strength`, `plan`, `activeSession` (so an interrupted session resumes). |
| Screens / devices updated | Home (lift done), Plan, Progress (sessions, top set per lift, est. 1RM where reliable), Coach (coverage, progression). Watch: not implemented (GR-14). |
| Verifying tests | Host: `StrengthAuditTests`, `RoutinesTests`, `Rc3EngineTests.testAT_J2_2_J3_2_CompletedSessionsAndLogsUntouched`, `testAT_D6_TopSetAndE1RM`, `AuditFixTests`, `QualityReleaseTests` (later-day start refused). UI-sim: `LaunchSmokeTests.testUpgradeFromBuild36CentreButtonOpensStrengthWorkout`, `AdaptiveSmokeTests.testQuickStrengthLogShowsCheckInThenAdjustments`, `LayoutAudit.testKeyScreensAtTextSizes` (strength screens). **MISSING**: UI-sim test that logs two sets, finishes, and asserts the summary, Plan done state and Progress top set (owner Example 1). |
| Known deviations today | Two estimated-1RM formulas exist (coach: Epley without an effort rule; Progress: Brzycki with RPE ≥ 8) — contract: one formula, the Progress rule (GR-46/known issue). |

## W8 · Progress and goals

| | Contract |
|---|---|
| User sees | Adherence first (done vs planned per sport, this week + trend; paused weeks excluded, hatched), then performance only with evidence: cycling (riding time trend; FTP value with its source tag or "Unknown — no watts are guessed"; FTP trend only from two verified values), strength (top working set per lift from logged sets; *Est. 1RM* optional, labelled, only when the rule holds and ≥ 3 qualifying sessions), hybrid balance vs priority, 4/8/12-week checkpoints that say what evidence is missing. Different layout per athlete type. |
| Interaction → result | Read-only views; period segmented control; Est. 1RM toggle; checkpoint detail. |
| Data changed | none. |
| Saved where | n/a (`settings` may keep the toggle). |
| Screens / devices updated | n/a. |
| Verifying tests | Host: `Rc3EngineTests.testAT_D6_TopSetAndE1RM`, `testAT_K1_CheckpointsNeedTimeAndSessions`, `testGlanceShowsUnknownFTP`, `ProgressMetricsTests`, `HomeBTests.testWeekCountsAgreeOnHomePlanAndProgress`, `WeekTotals` tests. UI-sim: `LayoutAudit.testRC2OwnerScreens` (Progress pages), `JourneyTests` (goals on Home). **MISSING**: a data-level UI-sim assertion that a logged session changes Progress counts and the top set (owner step "recorded results update Progress"). |
| Known deviations today | Progress weekly cards still count paused weeks (known issue 3); goal-specific indicators are V6 work (not yet on the Progress screen; Home first-week goals row shows the selected goals only). |

## W9 · Devices and Apple Health

| | Contract |
|---|---|
| User sees | One Devices & sensors screen: Apple Health, Apple Watch, BikeComputer, HR strap, power meter, cadence/speed — each with a state badge (**Not connected / Paired / Connected / Receiving live data / Connected · no recent data (stale) / Connection problem**), last synced, what it provides, one action (pair / connect / forget / manage). Apple Health page: workouts import plus optional reads (weight, resting HR, HRV, sleep) with value · source · date and "No data". |
| Interaction → result | Actions call the real flows (`DeviceLink.connect`, BLE pairing sheet, Watch page, HealthKit authorization). States come only from `SensorHub.deviceStates` via `DeviceStateRules` (fresh window 10 s; Health 60 s). Reads happen only for enabled kinds; precedence: the newer of manual entry and Health sample wins; undated manual stays; unknown/legacy never beats a dated sample. No readiness score, diagnosis or training conclusion. |
| Data changed | `profile.weightKg/restHR/hrv/sleep` (+provenance `.appleHealth` + sample date), `healthReads` settings, paired-sensor records. |
| Saved where | `profile`, `settings`/`healthReads`, sensor records in `settings`/`Connections`. |
| Screens / devices updated | Devices, Profile › Personal (weight source), Home "Getting started", ride pre-flight. |
| Verifying tests | Host: `DeviceStateTests` (`testBoardStates`, `testWatchStates`, `testBLESensorStates`, `testBoardSensorAndHealthStates`, `testStaleIsItsOwnState`, `testColoursFollowTheConnectionsRule`), `HealthPrecedenceTests` (`testNewerWins`, `testUnknownAndLegacyNeverBeatASample`, `testUndatedManualEntryIsKept`, `testProfileApplyRecordsSourceAndDate`, `testStoreAppliesOnlyEnabledKinds`), `DeviceCardsTests` (only supported actions), `PairingTests`. UI-sim: `DesignSystemAudit` (badge states), `JourneyTests` step 5 (badge present, no switches), `LayoutAudit` (Devices page). Device: **none** — live HealthKit reads, BLE pairing, Watch session and board link are unverified on hardware. |
| Known deviations today | No UITestSupport seed for device states (cards show the simulator's real states only). Weight from Apple Health is read, not yet shown as the offered prefill on Stage A unless already authorized. |

## W10 · Health and safety

| | Contract |
|---|---|
| User sees | Profile › Health & safety: *Pause training* (unwell / injured / away) with Resume; a saved restriction from an earlier version (clearance needed / stop / supervised) shown with *Review*, which opens the unchanged questionnaire. No questionnaire in onboarding or normal navigation. Home shows "Training paused · Resume training" while paused. |
| Interaction → result | `pauseTraining(reason:)` / `resumeTraining()` → `profile.trainingPause`, `pauseHistory`; paused weeks (≥ 4 days) are excluded from checkpoints and adherence. An unanswered health check restricts nothing; saved answers keep their rules until the athlete reviews them. Load limits, pain adaptations (`AdaptationEngine`), return-after-break ramp and missing-sensor handling stay in force. APP-012 NO-GO unchanged. |
| Data changed | `profile.trainingPause`, `pauseHistory`, `healthScreen` (only through the old form). |
| Saved where | `profile`. |
| Screens / devices updated | Home hold state, Plan, Progress (excluded weeks), Coach. BikeComputer / Watch pause message: **not implemented** (GR-13/14; firmware spec). |
| Verifying tests | Host: `Rc3EngineTests.testUnansweredCheckNoLongerCapsAndPauseStopsPlanning`, `HomeBTests.testHealthHoldsTakePrecedence`, `CoachSafety`/`CoachRemediation*` suites (caps, clearance rules), `AdaptationEngineTests` (pain). UI-sim: `LayoutAudit.testHomeStates` (paused/clearance states), `OnboardingScreens` (no health prompt after onboarding). **MISSING**: UI-sim test pause → Home hold → resume → Progress excludes the week. |
| Known deviations today | A pause created by an old saved illness answer is not excluded from checkpoints/adherence (known issue 24). |

## W11 · Migration (schema → 4)

| | Contract |
|---|---|
| User sees | Nothing changes in their plan, logs or rides. Values of unknown provenance show "From an earlier version — please confirm". Old fabricated defaults (75 kg untouched, age 35 without a date, FTP `assumed`) show as Not set / Unknown. |
| Interaction → result | `StoreFile.migrate` on load, idempotent; migration log lines kept. |
| Data changed | `profile.provenance[*]`, `weightKg`/`age`/`ftpW` only for the fabricated cases, `rides[*].energy` (kcal vs kJ relabel), `schema`. Never `plan`, `strength`, `availability`, `templates`, `customExercises`, `appliedProposals`, `settings`, `planVersions`. |
| Saved where | the same `StoreFile`. |
| Screens / devices updated | Profile (confirm prompts), ride summaries (energy label), board gets 0 for anything now unknown. |
| Verifying tests | Host + Unit-sim: `ProvenanceMigrationTests.testBuild121DefaultsBecomeUnknown`, `testBuild127TypedValuesAreKeptAsUnverifiedLegacy`, `testMigrationIsIdempotentAndRoundTrips`, `testMigrationLeavesPlanAndLogsUntouched` (field by field, value equality), `testAgeMovedOnTheOldSliderIsKept`, `Rc3EngineTests.testMigrationV3KeepsEverythingAndMapsFields`, `ModelTests.testStoreRoundTripSurvivesRelaunch`, `testStoreFileDecodesV1JSONWithoutNewKeys`, `RulesTests.testOldProfileAndSettingsJSONLoad`. UI-sim: `LaunchSmokeTests.testUpgradeFromBuild24/30/33/36/40…` (old stores open and every tab works). Device: a real build-121 phone upgrade is **untested**. |
| Known deviations today | none known. |

---

## Outdated-test candidates (expectations that contradict this contract — listed, NOT changed)

| Test | Level | Contradiction | What the contract-conformant test would assert |
|---|---|---|---|
| `LayoutAudit.testRC2OwnerScreens` — "'…' did something (Undo offered)" (`LayoutAudit.swift:379-387`) | UI-sim | Taps the first `fixPlan-*` action and demands an immediate `fixPlanUndo`. For *shorten* the contract (W3/W4) is a before/after preview first — the preview sheet appears instead of Undo, so the assertion fails exactly when the app behaves correctly. (Run 131, owner iPhone: this failure.) | shorten → `changePreview` visible → `changeCancel` leaves the session identical → tap again → `changeApply` → Plan shows the shorter rebuilt session and *Plan changes* has one more entry; skip → `fixPlanUndo`; raise budget → preview (once the W4 deviation is fixed). |
| `LaunchSmokeTests.testUpgradeFromBuild33OpensHybridSheetsAtLargeText` (`:264` waits for navigation bar "Training days") | UI-sim | On impl/v1 Plan › *Your week* opens `WeekPage` titled "Your week" (the one week editor, W4); "Training days" is the old `AvailabilityEditor` title, now only inside Fix plan. | wait for `navigationBars["Your week"]` (and `cyDay-*` cells) then Cancel. |
| `RulesTests.testSkippedOnboardingValuesStayUnknown` | Unit-sim/Host | Already updated to "Unknown" (S2-0) — consistent now; listed because the old expectation ("Provisional estimate") was the run-123 failure pattern this process is meant to catch. | — |
| `HomeBTests.testFirstMultiMissedAndFree` | Host | Was date-dependent (failed on Mondays); the engine was fixed (GR-54), the test now matches W5. | — |
| `LayoutAudit.testRC2OwnerScreens` — "weekly totals are not repeated on Plan" (`:374`) | UI-sim | Consistent with the 2 Nov decision (weekly completion on Home, not duplicated on Plan). Not outdated; recorded so nobody "fixes" it the other way. | — |

Tests marked **MISSING** above are the next additions (owner Examples 1–5); they are written against this contract, with data
assertions, before any further screen work.
