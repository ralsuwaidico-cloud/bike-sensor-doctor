# Cyclift — Onboarding v3.3 — experience refinement

**Version:** 0.1 · 15 Nov 2026 · **Status:** Recommended design direction — **Pending Owner Visual Approval**. **Implementation NOT AUTHORIZED.** Static drawings only: nothing implemented, compiled, run or tested; no prototype. **ILLUSTRATIVE DESIGN — NOT IMPLEMENTED.**

**Owner direction recorded (15 Nov):** v3.2 is a better functional foundation than v3.1; its visual experience is **not approved**. Keep the v3.2 functional improvements; reconsider the visual and interaction design. v3.2 and earlier documents are kept unchanged.
Companion document: `ONBOARDING_V33_INTEGRATION_CONTRACTS.md`.
Sources reviewed: the five v3.2 sheets; build 216 onboarding source (read-only, not run); Training Hub v1.1 §6 and registry, v1.4 baseline; Progress v2 framework and v2.3 refinement; Profile v2.0; Plan v2.0 decisions in the conflict register; Coach auto-adjust audit and correction proposal.

## 1. Audit of v3.2
| v3.2 element | Decision | Evidence |
|---|---|---|
| Six pages plus review; adaptive questions; fixed explanation line above the button | KEEP | Stable controls; one place to read consequences |
| Goal cells, ★ main goal, rule text | KEEP | Matches build 216; all goals visible at once |
| Day editor of fixed height, per-day minutes, total, dot for changed days, Undo, existing warnings | KEEP | Replaces hidden tap-to-cycle; nothing moves |
| Honest capability wording | KEEP | Registry: running, swimming and all recovery entries have no recorder |
| Progress bar of six plain segments | REDESIGN | Carries no information and no identity; replaced by the blueprint rail |
| Sports as one flat list with check rings | REDESIGN | Chosen sports look like unchosen ones; no main sport, although Training Hub v1.1 §6 expects "which is primary" |
| Goals page order (level rows first) | REFINE | Three segmented rows sat above the goals and competed with them |
| Selected goal vs main goal (outline vs small ★) | REFINE | Difference too weak; main goal is now a solid cell |
| Week: one "ride" and one "lift" kind | REFINE | Could not express road vs indoor, or an optional recovery reminder |
| Weekly total as rides · lifts | REFINE | Now by sport, with session count |
| Page 6 mixing Evolution and the first week | REDESIGN | Two subjects on one page; Evolution was a small block |
| Page 7 as a twelve-row list | REDESIGN | A settings receipt; declared answers, the proposal and evidence were not told apart |
| "Baseline pending" | REFINE | Progress v2.3 wording is "Establishing your baseline" |
| Separate provenance wording per page | REFINE | One set of three marks on every page |
| Search field at the top of sports | REMOVE | Becomes one "More · search" chip |
| "General" heading over a single goal | REMOVE | One cell does not need a heading |

## 2. The visual language
1. **Blueprint rail.** The top of every page is six small slots. A finished page leaves its mark — initial, main-sport symbols, ★ in the goal's colour, a seven-bar week, connection count, a ring. It is the progress indicator, a summary and the way back (tap a mark). On page 7 the rail has become the blueprint.
2. **Three provenance marks, everywhere:** ● declared by you · ◆ Coach's proposal (rules-based) · ▲ measured evidence.
3. **Solid means main; outline means chosen; dashed means interest only.** The same rule for sports, goals and days. Never colour alone.
4. **Discipline colour** (endurance, strength, recovery tokens) appears only on things the athlete chose.
5. **Typography:** numbered overline ("02 · SPORTS"), one large title, no decorative subtitle.
6. **Coach line:** a fixed three-line zone above the button states what the last tap changed in the plan. It never moves.
7. **Movement (specified in words; not drawn or tested):** a rail slot fills as its page completes; a chosen sport appears in the line-up; a cell fills when it becomes main; day tiles cross-fade on change. All under 250 ms; with Reduce Motion, cross-fades only.
No dials, wheels or novel controls are used: chips, cells, segmented controls, steppers and fields.

## 3. The seven pages
| # | Page | What is new in v3.3 | Maps to |
|---|---|---|---|
| 1 | About you | Name as the page's hero; fields unchanged | Profile › Athlete Profile |
| 2 | What do you train? | Fixed-height **line-up** of chosen sports (main large, interests dashed) above a chip library in three domains. First planned sport per domain becomes main; tap another in the line-up to move it | Planned disciplines; Training Hub "your activities" and primary |
| 3 | What are you aiming for? | Goals first; main goal solid. Then "When time is short, protect". Level last, marked ● declared | Session mix; Progress measure; proposed week |
| 4 | Build your week | Tiles list each session with sport symbol and minutes; editor offers the athlete's planned sports and Rest, up to two sessions (strength first); optional recovery reminder on a rest day; total by sport | One tile session = one planned session |
| 5 | Connect and calibrate | Layout kept; groups carry ▲ ● ◆ | Devices; FTP (declared, not tested); Coach preference |
| 6 | Athlete Evolution | A page of its own: Singularity, six stages, a square "you" marker outside the track, and three separate lines — declared, measured, stage | Nothing stored |
| 7 | Athletic Blueprint | Name, line-up and main goal; ◆ the proposed week and approach; ● what was declared; ▲ what is measured. Any band opens its page and returns | Approval creates plan version 1 |

Adaptive: endurance-only and strength-only athletes see only their goals, one level row, their own sports in the day editor, and no priority; strength-only see no FTP or bike devices (sheet Y6).

## 4. States drawn
Empty (pages 1, 2, 3) · selected · changed (main sport, main goal, priority, modality, length, second session) · invalid (weight, FTP, week with no training day, only unsupported sports) · unavailable (interest as main sport; Apple Health on this device) · interrupted and reopened · returning athlete (prefilled sports, real evidence, plan unchanged).

## 5. v3.2 → v3.3
| Aspect | v3.2 | v3.3 | Why better | Trade-off |
|---|---|---|---|---|
| Identity | Plain progress segments | Blueprint rail and three provenance marks | Recognisable; every page shows what has been built | Six small marks need a 44 pt tap area each; marks must be learned (the legend appears once on page 2) |
| Sports | Flat list | Line-up + chip library | Main sports are unmistakable; five or more sports fit without a longer list | Chips show less text than rows: capability is carried by solid/dashed plus one legend line |
| Main sport | None | One per domain | Training Hub expects it; the coach has a default modality | One new stored flag |
| Goals | Level first | Goals first, main solid | Focus on the decision that changes the plan | Level rows are lower and slightly smaller |
| Week | Ride / lift | Named sports, two sessions, recovery reminder | Says what will actually be planned | Modality per session and the reminder are new stored fields; tiles are denser |
| Page 6 | Evolution + week | Evolution only | Room to separate declared, measured and stage | More whitespace; little to do on the page |
| Page 7 | List of twelve rows | Blueprint in three marked bands | Reads as a plan, shows provenance | Denser than a list; scrolls on a small iPhone |
| Wording | "Baseline pending" | "Establishing your baseline" | Matches Progress | — |
Unchanged from v3.2: questions asked, validation rules, warnings, the Coach preference, the approval gate.

## 6. Not verified, not decided
1. **Coach auto-adjustment (register 26 / 69).** Page 5 says increases always need approval; build 216 applies small progressions automatically by default. The page is untrue until the correction is implemented.
2. **Stage rules (register 74)** are not approved. Stage names shown follow Progress framework set 1 (Origin … Mastery); confirm they are the approved names.
3. **New stored fields (additive, none exist today):** main-sport flag; sport modality per planned session; optional recovery reminder on a rest day; identifiers for activities not yet in the list. The planner today knows only "cycling" and "strength".
4. **Per-day lengths:** storage holds minutes per day; planner behaviour with unequal lengths has not been run.
5. **Two sessions a day** follow the existing rule (one ride and one strength session, strength first). Two endurance sessions in one day are not offered.
6. **Small iPhone:** pages 2–7 scroll; the Coach line and button stay fixed.
7. **Returning athletes:** how setup is reopened (from Profile) is a proposal.
8. Motion is described, not drawn. Forest and Sandstone, Arabic, the date picker, search results and loading or error states are not drawn.

## 7. Sheets (`sheets/`)
Y1 v3.2 and v3.3, all seven pages · Y2 sports · Y3 goals · Y4 weekly schedule · Y5 Evolution, Blueprint, approval · Y6 journeys and states · Y7 small iPhone, large text, themes (Arctic, Ocean, High Contrast).
