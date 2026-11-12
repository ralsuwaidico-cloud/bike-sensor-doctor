# Automatic coach adjustments (`autoAdapt`) — audit and safe-correction plan

Status: **Current Draft** · Version 0.1 · 12 Nov 2026 · Level 3
**Read-only audit and a plan. No production code, test, setting or data was changed.**
Source read: release branch `ios/checkpoint-f-ride`, commit `4e2e9dc` — `AdaptiveStore.swift`, `AdaptiveModels.swift`,
`AdaptationEngine.swift` (the parts cited), `AdaptiveViews.swift`, `Models.swift`, `AdaptationEngineTests.swift`.
Nothing was run.

Decision being served (owner, 12 Nov; Coach Decision 1 of 11 Nov): **automatic increases in training load, volume or
frequency must require approval.** Protective changes may stay automatic.

## 1. What happens today

| Fact | Where |
|---|---|
| The setting `autoAdapt` is **on by default**, including for stores that never had it | `AppSettings` (`var autoAdapt = true`; decoding falls back to `true`) |
| After a check-in (and at other triggers) the coach engine produces **adjustments** and **proposals** | `runAdaptation` → `AdaptationEngine.run` |
| With the setting on, **every adjustment is applied** to open future sessions; with it off, only approved ones | `applyAdaptation`: `wanted = settings.autoAdapt ? r.adjustments : approved only` |
| Each adjustment has a category: **progression**, **reduction**, **recovery** or **substitution** | `PlanAdjustment.Category` |
| Proposals (fixed day, session count, split, saved exercise, time budget, **major** load increase) always wait for "OK" | `AdaptiveProposal` |
| The athlete sees applied changes under "Changed automatically", can undo the changes of the latest check-in, can "Restore original plan", and can switch the setting off | Coach adjustments screen |
| Sessions the athlete edited, skipped, fixed or completed are never changed | `applyAdaptation`, engine eligibility |

### Increases that are applied without approval today (category "progression")

| Increase | Size | Dimension |
|---|---|---|
| Strength: more weight on an exercise | one step | Load |
| Strength: one more rep per set | +1 | Volume |
| Strength: one more set | +1 | Volume |
| Cycling: one more interval repetition in a threshold or VO2 session | +1 | Load / volume |
| Cycling: a longer endurance or long ride | a fixed fraction of the session, rounded to 5 min, within the weekly budget and the day's time | Volume |

Guards already present: increases are small and bounded; intervals are not added without a cleared health check or
while returning from a break; duration stays inside the weekly budget and the day's available time; larger increases
become proposals. **Frequency** (sessions per week) is already proposal-only.

So the gap against the decision is: **small progressions in load and volume are applied automatically by default.**

## 2. What must stay automatic

Reductions and recovery changes (fewer reps, easier session type, shorter session after fatigue, pain holds) protect
the athlete and should keep applying at once — Coach Decision 1: "protective holds automatic". Substitutions are
already approval-only.

## 3. Correction — design

| Category | Today (setting on) | After correction |
|---|---|---|
| progression | Applied automatically | **Becomes a proposal**: shown under "Needs your OK" (and in the Coach conversation's proposal detail when that exists); applied only on approval |
| reduction, recovery | Applied automatically | Unchanged |
| substitution | Approval only | Unchanged |
| proposals (major load, frequency, …) | Approval only | Unchanged |

The rule becomes: an adjustment is applied without approval **only if its category is reduction or recovery**.

The setting: keep the stored key (no data migration), change its meaning and label to "Apply protective changes
automatically". A future, separate **opt-in** for automatic progression (Coach Decision 1) is not part of this
correction.

## 4. Safe order of work (when authorised)

1. **Engine-level tests first** (Linux harness): for every progression kind in §1, assert it is *not* applied without
   approval and *is* applied after approval; assert reductions and recovery changes still apply at once.
2. Change the single selection rule in `applyAdaptation`; route progressions into the existing approval path
   (`approvedAdaptations`), reusing the proposal screen.
3. **Existing data:** progressions already applied before the update stay as they are and remain listed with
   "Restore original plan"; nothing is silently reverted. On first launch after the update, one notice explains the
   new rule. (Alternative for your decision: convert them back to pending.)
4. Update the tests that encode today's behaviour deliberately and visibly — at least the test that asserts
   "automatic changes default on" and the tests that expect a progression to appear after a check-in. These are
   behaviour changes, not weakened tests; each changed assertion is listed in the change record.
5. Copy: "Changed automatically" section text; the toggle label and footnote; onboarding or help text that promises
   automatic progression.
6. Check side effects: the "coach-adjusted" marker on sessions; the Plan timeline mark; the check-in result screen
   ("Changed after this check-in" + Undo); pending-proposal counts on Plan and Home.
7. Simulator journeys for a strength check-in and a ride check-in; then a physical-device pass.

## 5. Risks

| Risk | Mitigation |
|---|---|
| Athletes who relied on automatic progression stop progressing if they never open proposals | The pending proposal is surfaced on Home's coach preview and Plan's suggestion row |
| Too many small proposals | Group progressions of one session into one proposal; respect the limits of Coach Decision 6 |
| A test is "fixed" by loosening it | Every changed assertion states the old and new expected behaviour |
| Stored plans change on update | No migration; applied changes are kept; only future decisions follow the new rule |

## 6. Open points

1. Already-applied progressions at update: keep (proposed) or return to pending?
2. Should several small progressions for the same session be one proposal or separate ones?
3. Is the duration increase for endurance rides (inside budget and day limit) also "volume requiring approval"? Proposed: yes.

## 7. Limits

Based on reading the cited files, not on running the app or its tests. Other triggers of `runAdaptation` than
check-ins were not traced exhaustively.
