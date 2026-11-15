# Onboarding v3.3 — integration contracts

**Version:** 0.1 · 15 Nov 2026 · **Status:** Current Draft — proposal for review. Nothing implemented; no storage, schema or production behaviour changed; **no migration attempted or tested.** "Today" = as read in build 216 source, not run.

## 1. Onboarding → Profile
| Answer | Stored field today | New? | Edited later in (Profile v2.0) |
|---|---|---|---|
| Name, date of birth, weight | profile | no | Athlete Profile |
| Units | settings | no | App Preferences |
| Chosen sports | `sports` | identifiers for activities not yet listed | Training Setup |
| Main sport per domain | — | **yes** (flag) | Training Setup |
| Planned disciplines | `trainingMode` (derived: any cycling + any strength = hybrid) | no | Training Setup |
| Priority, level | `priority`, `level`, strength experience | no | Training Setup |
| Goals, main goal | goals, primary goal | no | Training Setup |
| Equipment | equipment | no | Training Setup |
| FTP | profile, source "entered" | no | Performance Settings |
| Connections | settings | no | Devices & Connections |
| Plan-change preference | `autoAdapt` | no (meaning must change, §7) | App Preferences |
Rule kept from today: every answer is written to the one authoritative profile; Profile edits the same fields; nothing is copied. A blank stays unknown — no default is invented.

## 2. Onboarding → Plan
| Input | Effect |
|---|---|
| Planned disciplines, level, priority | The proposed week (existing planner proposal rules) |
| Each day's sessions and minutes | Stored availability; one tile session = one planned session |
| Modality of a session (road / indoor / …) | **New field.** Until it exists the planner plans "cycling"; the label would be display-only |
| Main goal | Session mix (existing rule text); one effective goal per sport, as today |
| Equipment | Exercises offered |
| Approve | Plan version 1 for this week and next, from the same inputs the preview used (as today) |
| Optional recovery reminder | **New field.** Not a session; never counted in adherence |
Nothing is scheduled before approval. Warnings are the existing feasibility checks and never block, except a week with no training day (and, for hybrid, no ride or no strength day).

## 3. Onboarding → Home
Home reads the approved plan only: today's session, the week strip, and a rules-based Coach note. Before approval Home has no plan. No onboarding answer is shown on Home as a score.

## 4. Onboarding → Training Hub
Per Training Hub v1.1 §6 the hub reads athlete type, selected activities and which is primary. "Your activities" = selected ∩ selectable in the registry. A chosen activity with no recorder is offered only as the registry allows (interest / log-only when that exists); it is never shown as recordable. Until the selection is stored, the hub derives its default from `trainingMode`, as today.

## 5. Onboarding → Coach
The Coach receives goals, level, priority, availability, equipment, FTP state and the plan-change preference. It is rules-based. Onboarding shows Coach text only as (a) the proposed week and (b) one-line consequences of an answer, each from an existing rule.

## 6. Recorded evidence → Progress
Only recorded training reaches Progress. Declared level, sports, goals, body measurements and FTP typed by the athlete are **not** evidence and never set a stage. Goals pass their measure to Progress (for example weekly riding time, top sets, tested FTP). With insufficient evidence Progress shows "Establishing your baseline"; onboarding repeats that state and never computes a stage. Recovery entries are never evidence.

## 7. Known contradictions and limits
| Topic | Today | Owner decision / design | Needed before the page is true |
|---|---|---|---|
| Coach auto-adjustment | `autoAdapt` on by default applies small progressions (weight step, +1 rep, +1 set, +1 interval, longer ride) without approval | Increases in load, volume or frequency need approval; protective changes may stay automatic (12 Nov) | The correction in `product/coach/AUTOADAPT_CORRECTION_PROPOSAL.md`, with its tests |
| Activity capability | Records: cycling (road, indoor, mountain bike, commuting share one recorder), strength. Not supported: running, swimming, walking, all recovery entries | Shown as "interest only" | A recorder, timer or log per activity before any other label |
| Unknown baselines | Weight, date of birth and FTP may be absent | Shown as unknown; rides use heart rate and effort; no watts guessed | Nothing — existing behaviour |
| Stage rules | Not approved | No stage shown; names only | Owner decision on Progress criteria |
| Per-day lengths; modality | Minutes per day exist; modality does not | Drawn | Planner verification; additive field with impact assessment |

## 8. Profile migration (existing athletes)
Proposal only. Existing athletes are not sent through onboarding. Stored values map without loss: `trainingMode` → planned disciplines; existing `sports` → chosen sports; main sport defaults to the first planned sport per domain and is shown for confirmation, not assumed silently; goals, week, equipment, FTP and devices are unchanged. New fields are optional and absent means "not set". No plan or history record is rewritten. A reopened setup shows current values, and approval is asked only if the week or goals change.

## 9. Interrupted onboarding
Today each answer is written as it is made and the page reached is stored (`onboardingStage` 101–105); reopening resumes there. v3.3 keeps this: seven pages need stage values for seven steps and a mapping from the five old values (old A → page 1, with type → page 2; B → 3; C → 4; D → 5; E → 7), to be designed with the migration and tested. Sessions created before approval never become history (existing rule). The rail shows what is complete; the Coach line says the answers were kept.
