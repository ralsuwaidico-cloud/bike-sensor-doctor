# Training Hub v1.4 — Technical impact

Status: **Current Draft — assessment only. No change made or authorised.** · Version 0.2 · 14 Nov 2026 · Level 3
Source read (read-only): release branch `ios/checkpoint-f-ride`, commit `4e2e9dc`.

## 1. What works today, and the evidence

Evidence run: iOS workflow run **43013897973**, 11 Nov 2026, commit `4e2e9dc`, simulator. Logic run **43013897750** (Linux) passed.

| Stage | Result |
|---|---|
| smoke | passed |
| unit | **failed — 1 test:** `RideRegressionTests.testGPSRecordingNeedsNoNetworkAndKeepsRouteSamples` |
| journeys (hybrid, cycling, strength) | passed |
| flows (hub tap reliability, strength session journey, Plan edit, Plan/Progress/Recovery screens, delete-all-data) | **failed — 1 test:** `PlanEditPreviewApplyTests.testEditDurationGoesThroughPreviewAndApply` |
| layout ×4, watch | passed |

Limits of this evidence: I read the run's failure list, not per-test pass lines; it is a simulator run; I did not re-run anything.

| Behaviour | Test (in the stage above, not among its failures) |
|---|---|
| No second strength session while one is in progress | RoutinesTests |
| A part-logged strength session survives a restart | RoutinesTests |
| Superset members alternate | SupersetPipelineTests |
| Athlete-modified and completed sessions are never rewritten | SupersetPipelineTests |
| Start → log every set → Finish → Save → check-in → history | StrengthSessionJourneyTests (flows) |
| Train button opens and closes reliably under rapid taps | HubTapReliabilityTests (flows) |
| Riding: Lap + Pause; paused: Resume + End | RideControlPlanTests |
| Lost BikeComputer link: pause, resume, end, review; the device's later copy refused | RideRecorderDisconnectTests |
| No heart rate invented without a source | RideRegressionTests |
| One Health export per ride | RideRegressionTests |
| Ride → results → check-in survives relaunch (a **saved** ride) | RideChainTests |

## 2. Existing components and who would be affected

| Component (as named in the code) | Role today | Touched by v1.4, if ever built |
|---|---|---|
| Root view (`ContentView`) | Tabs, dock, centre button; five presentation owners plus the hub overlay; removes the dock during a ride | Coordinator replaces the separate owners for Train; dock gains emblem states |
| `TrainingHubView` | Today's hub overlay | Becomes panel + Hub |
| `StrengthWorkoutScreen`, `StrengthSessionView`, next-set card | Strength screens | Replaced by the one-exercise recorder |
| Store: active strength session | Owns the session | Read and commanded; not replaced |
| `RideRecorder`, Ride tab, `RideControlPlan` | Ride recording and controls | **Not touched** until the safety gate passes |
| Check-in flow and model; adaptation engine | Ratings, pain; Coach rules | Review UI replaces the form; model and rules untouched unless separately approved |
| Health export; watch mirror | Health workout at Save; watch workout | Not touched |

Not affected: onboarding, Home, Plan, Progress, firmware, BikeComputer and LILYGO protocols.

## 3. Blocked and dependent capabilities

Blocked: ride minimising; in-progress ride storage; ride restoration. Dependent: save result reporting; recovery records;
rounds, skipped, new set forms; typing a value; Undo; optional ratings; Intensity; capability registry.

## 4. Migration risks (if storage ever changes — none proposed now)

| Change | Risk |
|---|---|
| Ratings become optional | Old builds and old records expect two numbers; an old record cannot say whether 7 and 6 were answers or untouched defaults — that ambiguity already exists and must not be "repaired" |
| Intensity added | New field ignored by old builds; must never be read as effort |
| "Skipped" set state | Old code reads a set as done or not done; a skipped set must not be counted as done |
| Rounds | Existing sessions have groups without rounds; they must display unchanged |
| In-progress ride file | A stale file after a crash must never be saved twice or mistaken for a finished ride |
| Any of the above | BikeComputer profile sync, data export and the "survives relaunch" tests must keep passing. (Correction 14 Nov: version 0.1 said "cloud sync"; the app has no cloud storage or accounts) |

## 5. Review compatibility assessment

| Topic | Finding |
|---|---|
| Scales | Effort and Performance stay 1–10 integers with today's meanings. The sliders produce only 1–10 |
| Historical records | Unchanged. No conversion |
| Missing ratings | Today both are required and pre-filled (7 and 6). Options: store a review only when both are answered (no storage change), or allow each to be unknown (storage change). Owner decision |
| Coach | Reads effort, performance, pain level, pain area; session load = effort × minutes; for strength, the effort from the Finish screen is used when there is no check-in. With no Effort on Finish and a skipped review, a strength session has no effort and no load. How the rules behave over several such sessions was not traced. No fallback is proposed |
| Intensity | Not read by anything. Stored only, if approved |
| Pain | The existing levels and areas are offered unchanged, so current rules work whenever a level is given |

## 6. Evidence needed before a prototype is trusted

1. Cause of the two failing tests on the release head.
2. A trace of Coach behaviour with unknown effort.
3. Whether a ride and a strength session can be active together today.
4. A device check that a strength session's time and rest stay correct through lock, background and a call.
5. Everything in the cycling safety gate.
