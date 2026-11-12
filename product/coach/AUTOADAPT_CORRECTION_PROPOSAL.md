# Automatic adaptation — implementation correction proposal

Status: **Pending Review** · Version 0.1 · 12 Nov 2026 · Level 3
Source: `docs/cyclift-governance`, `product/coach/AUTOADAPT_CORRECTION_PROPOSAL.md`
Builds on: `product/coach/AUTOADAPT_AUDIT_AND_CORRECTION_PLAN.md` v0.1 (kept unchanged as the earlier audit).

**Proposal only. No algorithm, production code, test, setting or stored data was changed.**
Evidence: the production source was **read** on the release branch `ios/checkpoint-f-ride`, commit `4e2e9dc`.
Nothing was compiled or run for this document; every statement about behaviour is a reading of the code, with the
file and line given so it can be checked.

Owner decisions served (12 Nov): future increases in load, volume or frequency need approval · increases already
applied are **not** reversed · automatic protective reductions are audited separately, distinguishing advice from
changes to scheduled workouts · the algorithms are not modified yet.

## 1. Summary

1. Automatic increases reach scheduled sessions through **two separate code paths**, not one. The earlier audit
   described only the first.
2. Path A (the adaptation engine) obeys the setting "Adjust future sessions automatically", which is on by default.
3. **Path B (the strength planner) does not look at that setting at all.** Each time coach-built strength sessions
   are rebuilt, the next weight, reps or hold time is written into the scheduled session directly.
4. Protective reductions also arrive through several paths. Some are advice only; several change scheduled
   workouts without asking. They are listed in §5 for your decision.

## 2. Affected functions

| Function | File · line | Role |
|---|---|---|
| `AppSettings.autoAdapt` | `Models.swift` 651, 682 | The setting. Default on; a stored file without the key decodes as on |
| `Store.runAdaptation(now:)` | `AdaptiveStore.swift` 42 | Runs the engine and applies the result |
| `Store.applyAdaptation(_:now:)` | `AdaptiveStore.swift` 60–63 | **The selection rule of Path A:** with the setting on, every adjustment is applied; with it off, only approved ones |
| `AdaptationEngine.run(_:)` | `AdaptationEngine.swift` 521 | Decides adjustments (applied) and proposals (wait for OK) |
| `AdaptationEngine.strengthDecision(_:session:input:)` | `AdaptationEngine.swift` 736–812 | Strength progression (weight, reps, sets) and one reduction (one rep fewer) |
| Cycling progression block | `AdaptationEngine.swift` about 650–700 | One more interval repetition; longer endurance ride |
| Major-load gate | `AdaptationEngine.swift` about 700–715 | A week's progressions adding more than 10 % of that week's planned load become one proposal |
| `Store.acceptAdaptiveProposal`, `dismissAdaptiveProposal` | `AdaptiveStore.swift` 202, 213 | The existing approval path |
| `Store.undoAdaptation`, `restoreOriginalPlan`, `undoCheckInRebuild` | `AdaptiveStore.swift` 172, 187, 140 | The existing ways back |
| `StrengthPlanner.prescribeLoad(…)` | `StrengthPlanner.swift` 701–822 | **Path B:** next load and reps from logged sets ("double progression") |
| `Store.refreshGeneratedSessions(now:)` | `StrengthPlanner.swift` 946 | **Path B's writer:** rebuilds open coach-built strength sessions and stores the result |
| `Store.refreshRideSafety(now:)` | `CoachSafety.swift` 377 | Health-check and return-from-break caps on rides |
| `AdjustmentsView` toggle | `AdaptiveViews.swift` 145–150 | The setting's switch; changing it re-runs adaptation |

Triggers of Path A found: both check-in recorders, "pain is gone", accepting a proposal, the setting's switch, the
availability editor, a rebuild from the hybrid questions, and one further call in `AdaptiveStore.swift` (line 257).
Triggers of Path B found: `runAdaptation` itself (line 36), both check-in recorders, a store migration, the hybrid
set-up, a strength-preferences change and the end of a strength workout. **The trigger lists were found by search
and not traced exhaustively.**

## 3. Current automatic-increase conditions

### Path A — adaptation engine (applied when the setting is on)

No progression of any kind is produced while fatigue is flagged or adherence is blocked, or with fewer than two
usable recent sessions.

| Increase | Conditions read in the code | Size |
|---|---|---|
| Strength: more weight | Every planned set completed at RPE ≤ 8 on the two most recent sessions at the current weight and reps; health check allows vigorous training; no pain on that movement; only the next session of that exercise within 14 days; the equipment is owned | One step, at most 2.5 kg |
| Strength: one more rep per set | The same evidence, when a weight step is not available | +1, below 20 reps |
| Strength: one more set | The same, when reps cannot rise | +1, below 5 sets; if the session would exceed its time, it becomes a proposal instead |
| Cycling: one more interval repetition | Cycling flagged as improving; no pain; health check allows vigorous training; not in a return phase; the intervals still fit the session | +1 on the next threshold or VO2 session |
| Cycling: longer endurance or long ride | The same flag, when intervals are not raised; inside the weekly budget and the day's time, otherwise a proposal | +10 %, rounded to 5 min |
| Week-level guard | If the week's progressions together add more than 10 % of that week's planned load, all become one proposal | — |

Never changed by Path A: sessions that are done, skipped, fixed or edited by the athlete; strength sessions with
entries the athlete typed. Frequency (sessions per week) is already proposal-only.

### Path B — strength planner (applied on every rebuild; the setting is not consulted)

Applies to open, coach-built strength sessions (no routine attached, not hand-edited, today or later).

| Increase | Conditions read in the code | Size |
|---|---|---|
| More weight | Two logged sessions in a row with every set at the top of the rep range, at this weight, at a known effort ≤ RPE 8; no hold (pain, deload, missed sessions, health check) | The smallest step available for the equipment |
| One more rep per set | Last session logged with a known effort below 9 and no set short of the range; no hold | +1, up to the top of the range |
| Longer isometric hold | Last hold logged with a known effort ≤ 8; no hold | +5 s, up to 60 s |

An unrated session is not treated as evidence; nothing increases without a logged effort.
**Not established by reading alone:** how Paths A and B combine on the same session (whether both can raise one
exercise after one check-in). This must be answered with a test before any change is designed in detail.

## 4. Future approval workflow (proposed)

Rule: **an increase never reaches a scheduled session until the athlete approves it.** An increase is any change
that raises weight, reps, sets, hold time, interval repetitions, session duration or sessions per week.

```
evidence met ─► PROPOSED INCREASE (stored, not applied) ─► shown: Plan suggestion row · Coach conversation
      athlete: Approve ─► applied to the named session(s) · history entry · Undo
      athlete: Not now ─► stays pending; the session runs as scheduled
      athlete: Decline ─► closed; not offered again for the same evidence
      session's day arrives while pending ─► the proposal expires; nothing was changed
```

| Element | Proposal |
|---|---|
| What a proposal states | What would change (before → after), on which session, the evidence in plain words ("every set of 8 at RPE 7 on your last two sessions"), and that the Coach is rules-based |
| Grouping | The increases of one session form one proposal, so the athlete is not asked exercise by exercise |
| Path A | Adjustments of category `progression` are routed to the existing approval path instead of being applied; the selection rule applies automatically only what §5 leaves automatic |
| Path B | The planner still **computes** the next load, but a rebuilt session keeps the athlete's last approved prescription until the increase is approved. The "Why" text continues to explain the evidence |
| The setting | The stored key is kept (no migration). Its meaning narrows to the protective changes you decide in §5; its label changes to match. An opt-in for automatic progression is a possible later feature and is not proposed here |
| Volume of proposals | Limited by grouping and by the existing week-level guard; exact limits to be set with Coach Decision 6 |

## 5. Protective-reduction behaviour — separate audit

"Advice" means words only; the scheduled workout is untouched. "Changes the schedule" means the stored session is
altered. All of the following happen today without an approval step unless stated.

| # | Behaviour | Trigger | Advice or change | Path | Recommendation |
|---|---|---|---|---|---|
| P1 | Next hard ride within 7 days made one zone step easier (to endurance when fatigue is severe) | Fatigue from check-ins | **Changes the schedule** | A, obeys the setting | Keep automatic, always listed with reason and Undo — or make it a proposal: your decision |
| P2 | Next steady ride 10 % shorter | Severe fatigue | **Changes the schedule** | A | As P1 |
| P3 | Next strength session one set fewer on up to four exercises, or 10 % shorter | Fatigue (leg exercises only when the fatigue comes from cycling) | **Changes the schedule** | A | As P1 |
| P4 | Next hard ride eased; long rides 10 % shorter | Pain reported that affects cycling | **Changes the schedule** | A | As P1 |
| P5 | One rep fewer per set on an exercise | Two sessions short of the target at RPE ≥ 9 | **Changes the schedule** | A | As P1 |
| P6 | Any of P1–P5 on a day the athlete marked fixed | — | **Proposal** (already asks) | A | Keep |
| P7 | A sharp rise in load against the recent baseline | Load ratio above the engine's limit | **Proposal** only (already asks) | A | Keep; the ratio is a heuristic and must not be worded as a medical limit |
| P8 | Weight lowered on an exercise | Two logged sessions in a row short of the range at RPE ≥ 9 | **Changes the schedule** | B, setting not consulted | Needs the same decision as P5; today it cannot be switched off |
| P9 | Loads and reps held (no increase) | Pain, deload week, missed sessions, health check not cleared | Withholds an increase; changes nothing downward | B | Keep automatic — a hold is the absence of an increase |
| P10 | Restart below the last load after three or more weeks without that exercise | Time since last log | **Changes the schedule** | B | Your decision; it applies when a session is built, before the athlete has seen a higher value |
| P11 | Exercises that load a painful area left out | Pain reported | **Changes the schedule** | B | Your decision |
| P12 | Deload week (reduced strength work every fourth training week, or on fatigue signals) | Week count or check-ins | **Changes the schedule** (shapes the generated week) | Planner | Part of the program's structure rather than a reaction; propose to keep and to show it on Goal & Program |
| P13 | Rides capped or sessions paused after a health-check answer, and rides capped while returning from a break | Health check; break | **Changes the schedule**; the original is stored and restored afterwards | `refreshRideSafety` | **Not proposed for change.** It is the app's existing safety behaviour |
| P14 | Text advice (rest, see a professional, pain guidance) | Check-ins | **Advice only** | Explainer | Keep |

Points to note honestly:
- P1–P5 can be undone today ("Changed automatically", Undo, Restore original plan). I did not find an equivalent
  list for the Path B changes P8, P10 and P11; they are explained in the session's "Why" text.
- Several triggers rest on coaching heuristics (the code itself labels some factors as heuristics, not
  evidence-derived). They should be described to the athlete as the Coach's rule, not as physiology.
- If you decide that every change to a scheduled workout needs approval, P1–P5, P8, P10 and P11 become proposals
  and only P9, P13 and P14 stay automatic. If you keep protective changes automatic, the minimum correction is that
  each one is **listed with its reason and can be undone**, including those of Path B.

## 6. Existing-data compatibility

| Topic | Proposal |
|---|---|
| Increases already applied to scheduled sessions | **Kept exactly as they are** (decision R6). No session is rewritten at update. They stay listed, with the existing Undo and Restore |
| Stored setting `autoAdapt` | Key and value kept; no migration. Only its meaning for progressions changes |
| Stored approvals and dismissals | Kept; the approval path is reused |
| Stored "original" snapshots of sessions (`coachOriginal`) | Kept; they are what Undo and Restore rely on |
| Sessions generated before the update that already carry a planner-raised load (Path B) | Treated as the athlete's current prescription — not reversed. The first rebuild after the update must not lower them merely because approval is now required; this needs a recorded "accepted as of update" baseline, which is the one piece of new stored data. Its design needs an impact assessment (store file, cloud sync, Apple Watch, both hardware links) |
| Completed logs and ride history | Never touched (an existing test already asserts this) |
| First launch after the update | One plain notice: increases will now be suggested for approval; nothing already in the plan was changed |

## 7. Tests

Written **before** any behaviour change, at engine level, then store level:

1. For each increase of §3, Path A: not applied without approval; applied after approval; undone by Undo.
2. For each increase of §3, Path B: a rebuild leaves the scheduled prescription unchanged while a proposal is pending.
3. Interaction of A and B on one session after one check-in (the open point of §3) — first as a characterisation
   test of today's behaviour.
4. Each protective behaviour of §5 behaves as you decide, and is listed with a reason.
5. Already-applied increases survive the update unchanged (a stored file from before the change is loaded and its
   plan compared field by field).
6. A pending proposal expires when its session's day arrives; nothing changes.
7. Completed logs and ride history are byte-equal before and after.

Existing tests that deliberately encode today's behaviour will have to change, and each change will be listed with
the old and the new expected behaviour — for example `AdaptationEngineTests` (the assertion "automatic changes
default on", the test that improving strength performance progresses the load, the undo and restore test),
`CoachRemediationTests` (routine progression, no interval progression without clearance), `AuditFixTests`,
`StrengthAuditTests` and `QualityReleaseTests` (planner progression rules). These are changes of specified
behaviour, not relaxations: the evidence rules they check stay; what changes is that the result is proposed, not
applied. No test is removed to obtain a pass.

## 8. Rollback strategy

1. The work is done on its own branch from the release branch; build 216 stays the production baseline.
2. The change is made in two independent steps — Path A, then Path B — each of which can be reverted alone.
3. No destructive migration: stored keys are kept and the one new stored value is additive and optional, so an
   older build still reads a newer file. This is to be **proved by a test**, not assumed.
4. If the new behaviour must be withdrawn after release, reverting the code restores automatic application for
   future decisions; plans are not rewritten in either direction.
5. Nothing reaches TestFlight without your explicit approval.

## 9. Decisions needed from you

| # | Decision | Recommended default |
|---|---|---|
| 1 | Do protective changes P1–P5 keep applying automatically? | Yes, listed with reason and Undo |
| 2 | Do the planner's own reductions P8, P10, P11 get the same treatment and the same list? | Yes — same rule for both paths |
| 3 | Is a deload week (P12) part of the program, shown on Goal & Program, rather than a proposal each time? | Yes |
| 4 | One proposal per session, rather than per exercise? | Yes |
| 5 | A pending increase expires when the session's day arrives? | Yes |
| 6 | Order of work: Path A first, Path B second, each separately authorised? | Yes |

## 10. Limits

- Read from source; not compiled, not run, no test executed for this document.
- Line numbers are those of commit `4e2e9dc` and may differ on other branches.
- The interaction of the two paths, the complete trigger lists and the full set of planner holds were not
  established exhaustively.
- Routine-based strength sessions pass through `strengthDecision` (Path A); whether the planner path can also touch
  them was not confirmed.

## Change log

| Version | Date | Change |
|---|---|---|
| 0.1 | 12 Nov 2026 | First proposal |
