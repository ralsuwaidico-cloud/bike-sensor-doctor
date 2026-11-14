# Decision — Training Hub v1.4 approved as the design and UX architecture baseline

Date: 14 Nov 2026 · Decided by: owner · Recorded by: Claude · Level 1 (decision record)

## Decision
Training Hub v1.4 (`product/train/v14/`) is **Current Approved — Design Baseline**, on the basis of the submitted review package.
Design refinement is complete; no further Training Hub redesign round is to be started.

## What the approval covers
- Compact Train panel followed by an expanded Training Hub.
- Dedicated full-screen workout recording.
- A unified session lifecycle with minimise, resume, finish and save.
- Activity-specific endurance interfaces.
- Refined strength recording, superset journeys and rest management.
- Recovery activity interface concepts.
- Optional post-session review using Intensity, Performance and Effort.
- The v1.4 visual direction, six-theme support and accessibility requirements.

## What it does not do
**It does not authorise implementation.** No application code, database, firmware, onboarding, production branch,
TestFlight build or UI Lab build.

## Explicitly pending
| # | Matter | Where it is described |
|---|---|---|
| 1 | Final Train emblem selection | Design document §4; conflict register 49 |
| 2 | Cycling minimise / resume safety gate, including GPS recording and in-progress persistence | `TRAINING_HUB_V14_CYCLING_SAFETY_GATE.md` |
| 3 | Session save-result handling and recovery | Design §2 E; technical impact §3 |
| 4 | Unanswered review values, Intensity storage, Coach compatibility | Technical impact §5 |
| 5 | New exercise and recovery data capabilities | Technical impact §3–4 |
| 6 | Unresolved session-behaviour and rest-rule decisions | Design §5 and §9 |

## Open defects — not resolved by this approval
| Defect | Evidence | Status |
|---|---|---|
| Ride GPS route samples: `RideRegressionTests.testGPSRecordingNeedsNoNetworkAndKeepsRouteSamples` fails | iOS run 43013897973, commit `4e2e9dc`, 11 Nov 2026, unit stage | **Open — not investigated** |
| Plan edit and apply: `PlanEditPreviewApplyTests.testEditDurationGoesThroughPreviewAndApply` fails | Same run, flows stage | **Open — not investigated** |

## Earlier rounds
v1.0, v1.1, v1.2 and v1.3 are preserved unchanged as historical documentation.

## Next workstream
Profile tab — read-only audit and proposed information architecture first (`product/profile/`).
