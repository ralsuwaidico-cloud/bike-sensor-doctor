# Targeted test matrix (owner, 2 Nov 22:31)

Run before any full release pipeline. A workflow change is not ready for `[testflight]` until every row that applies
to it is green in a targeted `[ci quick]` run on the same code (enforced by `quick_green_for_head` in `ios/ci/build.sh`).

| Dimension | What it proves | Where it runs | Tests |
|---|---|---|---|
| Small screen | Controls inside the window, ≥ 44 pt, nothing clipped | iPhone SE simulator | `LayoutAudit` (affected screens), `DesignSystemAudit` |
| Large text | Same at AX3; primary actions reachable without hidden scrolling | iPhone SE at AX3 | `LayoutAudit` at AX3 for the affected screens |
| Standard size | Baseline layout and the full workflow | iPhone 17 at L | same tests at L |
| Repeated rendering | Feasibility / preview computations never change stored state or evict pending actions | Linux harness | `EngineSideEffectTests`, `testFeasibleMinutesDryRunLeavesPendingProposalsAlone` |
| Persistence | Values survive relaunch and migration | Linux harness + simulator | `ProvenanceMigrationTests`, `JourneyTests` relaunch step (V1) |
| Undo | Applied change is a plan version; Undo targets that version only; never overwrites a later change; Cancel / failed validation leave the plan equal | Linux harness + simulator | `testAppliedSessionChangeIsAVersionAndUndoRestoresIt`, `testUndoNeverDiscardsALaterChange`, `LayoutAudit.testRC2OwnerScreens` (Fix-plan sequence) |
| Cancel / failed validation | Nothing saved | Linux harness | `testPhase1EditRebuildsTheSessionAndCancelLeavesItIdentical`, `EngineSideEffectTests` |

Rules
- New engine behaviour gets a Linux harness test first (minutes, not hours); the simulator run confirms the screen.
- A UI flow that has never executed in CI (e.g. a branch gated by demo data) is added to the targeted set the first time
  it becomes reachable — runs 131–137 were spent on one such flow.
- Simulator results are never reported as real-device results.
