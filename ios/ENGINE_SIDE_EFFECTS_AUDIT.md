# Engine side-effects audit (owner, 2 Nov 2026)

Rule under audit: **a feasibility check must not change the athlete's training state.** The approved shape is
evaluate → preview → apply after confirmation → save a plan version → Undo restores the previous approved version.
For each operation: when it runs, what it writes, and whether Cancel, repeated rendering, background refresh and failed
validation leave the approved plan and the athlete's pending actions untouched. Evidence = test names (Linux harness
unless marked). Build: impl/v1 after the merge of impl/s2 (`fac399b`).

## Summary

| # | Operation | Entry point | Runs on | Writes | Side-effect safe? | Verdict |
|---|---|---|---|---|---|---|
| 1 | Session change evaluation | `Store.evaluateSessionChange` (SessionRebuild.swift) | feasibility, previews | nothing | yes | **FIXED now** — split out of `proposeSessionChange`; `proposeSessionChange` = evaluate + `register` |
| 2 | Fix plan shorten feasibility | `Store.shortestFeasibleMinutes` ← `BudgetFix.report` from `FixPlanSheet.body` | every render | nothing (cache only, not persisted) | yes | **FIXED now** (run 135 defect: evicted the athlete's preview) |
| 3 | Proposal registration / pruning | `Store.register` | user action, coach, Home swap | `pendingProposals` | now protects `lastProposalId`; bound 20 / 1 h applies to the rest | **FIXED now** |
| 4 | Single-session edit (Phase 1) | `Store.edit` → `commit(proposalId:)` | user action | plan entry, `trash` (Undo), `undoToast` | Cancel = `discardProposal` only; blocked proposal cannot commit; stale fingerprint refused | OK (`testPhase1EditRebuildsTheSessionAndCancelLeavesItIdentical`, `testCancelAndBlockedValidationLeavePlanEqual`) |
| 5 | Coach change preview / accept | `coachChangePreview` → `commitCoachChange` | user action (card tap) | registers one proposal; commit records coach undo | Cancel discards; cannot evict the athlete's preview (3) | OK (`testPendingPreviewSurvivesOtherProposals`) |
| 6 | Legacy mismatch proposals | `legacyMismatchProposals` | no caller today | was registering | now evaluates only | **FIXED now** (dead path made pure) |
| 7 | Plan-input change (goals, days, minutes, equipment, levels) | `proposePlanChange` / `proposeOrApplyPlanChange` / `applyPlanChange` | user action from Profile editors / Week page | `pendingPlanChanges` (unbounded), then on Apply: inputs + plan + `planVersions` | Cancel = `discardPlanChange`; stale scope refused; no session changed → applied directly WITH a plan version (contract W2) | OK; **DEFERRED D-SE-1**: `pendingPlanChanges` has no bound/expiry (grows with abandoned previews until relaunch); not persisted, so harmless but untidy |
| 8 | Equipment editor `onDisappear` proposal | `ProfileScreens.proposeEquipment` | leaving the Equipment page | restores `equipment` to the opened value, then proposes | one proposal per page visit (`equipmentAtOpen` reset); Cancel in preview discards and the edit is lost (contract deviation) | **DEFERRED D-SE-2** (V2: propose on Save, not on disappear; keep the draft on Cancel) |
| 9 | Strength prefs pickers (experience, goal) | `StrengthCoachViews` Programming pickers | user action | writes `strengthPrefs` then `refreshGeneratedSessions()` directly — no preview | not previewed | **DEFERRED D-SE-3** (V2: route through `proposePlanChange(cause: .strengthLevel/.goal)` like Profile › Training does; the Profile path already previews) |
| 10 | Generated-session refresh | `refreshGeneratedSessions` | after logs, migration, pain cleared, settings; background | plan entries of coach-built, open, un-edited sessions only | skips done / skipped / hand-edited / legacy-edited / routine / active sessions; blocked rebuilds are skipped; never touches `planVersions` | OK (`testBackgroundRefreshLeavesAthleteSessionsAndVersionsAlone`) |
| 11 | Adaptation (load adjustments) | `runAdaptation` → `applyAdaptation` | check-in, pain, settings, Fix-plan save, background | recomputes open future un-edited sessions from their ORIGINAL values (no stacking); `adaptations` | edited / skipped sessions listed, never recomputed; automatic only when `settings.autoAdapt` (default true) | OK for the approved Phase 1 scope; **DEFERRED D-SE-4**: with `autoAdapt` on, adjustments apply without a preview (approved behaviour from the coach remediation; V2 should surface them as proposals under the Coach C1 design) |
| 12 | Missed-session reschedule / Move to today | `HomeModel.reschedule`, `WorkoutState.moveToToday` | user action | plan date (+ hand-edit flag), `trash` + `undoToast` (reschedule) | refuses completed sessions and days outside this week; Undo via trash | OK by design (a date move is the athlete's own hand edit; no rebuild). `moveToToday` has no Undo toast — **DEFERRED D-SE-5** (small) |
| 13 | Week regenerate (Fix plan "raise budget", editor rebuild) | `regenerate(weekOf:replaceEdited:)` | user action | plan weeks, `replaceEdited: false` keeps edited sessions | direct write without preview (contract deviation already recorded, W4 "raise budget") | **DEFERRED D-SE-6** (listed in IMPLEMENTATION_PLAN V2) |
| 14 | Health import | `importHealthRide` | background sync | `rides` (insert) | dedupe by UUID and by start±2 min / duration±10 % → idempotent | OK (`testHealthImportIsIdempotent`) |
| 15 | Migration | `StoreFile.migrate` | launch | profile provenance, energy records, `migrationLog`; never plan/logs | idempotent | OK (`testMigrationIsIdempotentAndRoundTrips`, `testMigrationLeavesPlanAndLogsUntouched`) |
| 16 | Undo | `undoDelete`, `undoLastProposal`, `proposeUndo(version:)` | user action | plan (compare-and-swap), trash | refused when the plan moved on; undo of a plan version is itself a previewed proposal | OK (`testAT_J3_3_UndoIsANewProposalAndTheLogGrows`) |

## Findings

| Id | Severity | Finding | Status |
|---|---|---|---|
| SE-1 | S1 | `proposeSessionChange` registered every evaluation; a render-time feasibility check evicted the athlete's preview (run 135). | Fixed: pure `evaluateSessionChange`; `proposeSessionChange` wraps it. `testEvaluateSessionChangeLeavesPersistedStateIdentical`, `testFixPlanReportIsRenderSafe`. |
| SE-2 | S2 | `register` pruning could evict the athlete's own preview under pressure from coach / background proposals (bound 20, 1 h). | Fixed: `lastProposalId` is never pruned. `testPendingPreviewSurvivesOtherProposals` (50 proposals, > 1 h spread). |
| SE-3 | S3 | `legacyMismatchProposals` registered proposals although nothing shows them. | Fixed: evaluates only; a future screen must register before offering Apply. |
| D-SE-1 | S3 | `pendingPlanChanges` unbounded in memory. | Deferred (V2). |
| D-SE-2 | S2 | Equipment edit proposed on page disappear; Cancel loses the edit. | Deferred (V2, already in KNOWN_ISSUES #4). |
| D-SE-3 | S2 | StrengthCoachViews pickers write prefs and refresh without a preview. | Deferred (V2); Profile › Training path is previewed and is the one onboarding/Profile use. |
| D-SE-4 | S2 | Automatic adaptation applies without a preview when `autoAdapt` is on. | Deferred (Coach C1 design: adjustments become proposals). |
| D-SE-5 | S3 | `moveToToday` has no Undo toast (reschedule has one). | Deferred (small, V2). |
| D-SE-6 | S2 | `regenerate` from Fix plan "raise budget" writes without a preview. | Deferred (V2; contract W4). |

## Rules now pinned by tests

1. Evaluation writes nothing persisted (`snapshot` equal before/after) and registers nothing.
2. The athlete's pending preview survives any number of other proposals and the hour limit.
3. Cancel and a blocked proposal leave `plan`, `planVersions` and `trash` equal.
4. Background refresh / adaptation never touch hand-edited, completed or fixed sessions and never add a plan version.
5. Health import is idempotent by UUID and by start/duration.
6. A Fix-plan report can be rebuilt any number of times without changing state.
