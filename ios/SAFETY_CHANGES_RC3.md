# RC3 safety changes — APP-012 review (health check)

_1 Nov 2026 · owner decision (RC3 brief §2): remove the Health Check questionnaire from onboarding and ordinary navigation, keep essential protections, do not silently remove underlying safety controls._

APP-012 (the questionnaire *replacement* design) stays **NO-GO** — nothing here replaces the questionnaire with a new medical screen.

## Removed from the interface (UI work, separate worktree)

| What | Where it was | RC3 |
|---|---|---|
| 10-question health check step | Onboarding (after "About you") | Removed — new users never see it |
| Home "Health check needed — answer 10 questions" caution line | Home | Removed (engine no longer produces `HomeCaution.pending`) |
| Health check row | Profile › Training profile | Moved to Profile › Settings › Health & safety (review only) |

## Engine behaviour that changed (this branch, `CoachSafety.swift`, `HomeModel.swift`)

| Rule | Build 121 | RC3 |
|---|---|---|
| Health check never answered (or older than 12 months) | Easy-to-moderate only: rides ≤ zone 2 and ≤ 2 h, strength RPE ≤ 7, ≥ 8 reps, no load increases | **No restriction.** Planned like an athlete with all answers "no" |
| Home caution for an unanswered check | "Health check needed" line | None |

## Protections that remain (unchanged code paths)

| Protection | How it works | Code |
|---|---|---|
| Saved answers that need a doctor's clearance | Same caps as before (rides ≤ Z2, ≤ 2 h, strength RPE ≤ 6, no heavy reps) until a clearance is recorded | `HealthScreen.status`, `CoachReadiness` |
| Saved "stop" answers (chest pain, fainting, supervised-only) | No sessions planned; Home hold card | unchanged |
| Saved illness answer | Training paused until answered again | unchanged |
| **New: explicit pause** (`TrainingPause`: Unwell / Injured / Away) | No sessions planned while paused; Home shows "Training paused · Resume training"; paused weeks are excluded from checkpoints and adherence | `Store.pauseTraining`, `resumeTraining`, `CoachReadiness.userPaused`, `HomeHold.paused`, `TrainingPauseView` |
| Pain / discomfort reports | Stop progression for that area; advice to get persistent pain checked | `AdaptationEngine` (unchanged) |
| Return after a break (≥ 21 days) | Shorter, easier first sessions, loads restart lower | `ReturnPhase` M-02 (unchanged) |
| Load and progression limits | Double progression, smallest step, two sessions at top of range, deload weeks, recovery-capacity factors | `StrengthPlanner.prescribeLoad`, M-05/M-06 (unchanged) |
| Missing sensor data | Ride metrics show "no data"; no zone claimed from unverified power | Ride / coach (unchanged) |
| No invented targets | Unknown FTP → effort / heart-rate targets, never watts (new in RC3, ENG-E1/E3) | `RideSteps`, `RiderProfile.targetFTP` |

## Existing users

Answers saved by earlier builds are kept and keep their effect. An athlete whose saved answers still restrict training can review or update them from Profile › Settings › Health & safety (the existing form, unchanged). Nobody is stuck behind a screen they can't reach.

## Tests (Linux harness, local only — not simulator, not hardware)

`Rc3EngineTests.testUnansweredCheckNoLongerCapsAndPauseStopsPlanning`, `HomeBTests.testHealthHoldsTakePrecedence` (pause card + resume), `CoachRemediationTests` (restriction tests now use saved answers needing clearance), probes R5 / Q1 / S9 updated.
