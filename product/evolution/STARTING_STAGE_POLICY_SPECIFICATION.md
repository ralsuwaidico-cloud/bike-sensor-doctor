# Athlete Evolution — starting-stage policy specification (proposed)

**Status: PROPOSED POLICY SPECIFICATION. Automatic stage calculation is NOT enabled.**
Part A records the owner's decisions of 22 Nov 2026 (18:47). Parts B, C and D are Claude's proposals requested in the same message and await approval.
Every athlete's status in the app remains "Starting stage not yet assessed".

Nothing here is a scientifically validated threshold. The stage ranges are product conventions set by the owner; the definitions in Part C are plain-language self-descriptions, not performance standards.

---

## Part A — Decided by the owner (22 Nov 2026, 18:47)

| # | Decision |
|---|---|
| 1 | Self-reported estimates are capped at G2. |
| 2 | Provisional mappings: Beginner G0–G1 · Intermediate G1–G2 · Advanced G2. |
| 3 | The main sport determines the overall estimate; other sports are evaluated separately. |
| 4 | Reliable training history can refine estimates; self-reports alone do not verify performance. |
| 5 | If the main sport has no assessment data, show "Not assessed". |
| 6 | All selected sports eventually need their own experience assessment. Locked onboarding pages are not changed without approval. |
| 7 | Planned training is not completed training history. |
| 8 | An untested FTP is not verified evidence. |
| 9 | G0–G5 verification thresholds need separate sport-specific research and approval. |
| 10 | Any policy for lowering verified stages needs separate approval. |
| 11 | Progress and onboarding must use the same assessment source, clearly distinguishing Estimated and Verified. |

Consequences that follow directly:

- An estimate is always labelled "Estimated · based on your answers" and can be G0, G1 or G2 only.
- G3, G4 and G5 exist only as verified stages, and none can be awarded until decision 9 is completed.
- A weaker or stronger second sport does not move the overall estimate; it has its own line.

## Part B — Missing experience questions

What onboarding asks today, and what is missing for decision 6.

| Sport family | Experience asked today? | Missing |
|---|---|---|
| Cycling (all disciplines) | Yes — one level for all cycling, asked when cycling is planned | A level per discipline is not asked (road, indoor, mountain, gravel, commuting share one answer) |
| Strength — gym, free weights, machines | Yes — asked when strength is planned | — |
| Strength — bodyweight, calisthenics | **No** | Experience level |
| Running (road, trail, treadmill) | **No** | Experience level |
| Swimming (pool, open water) | **No** | Experience level |
| Walking and hiking | **No** | Experience level |
| Mobility, stretching, recovery | **No** | Experience level — and whether a stage applies to these at all |

Missing for every sport (needed for decision 4):

| Question | Purpose | Proposed answer choices (product convention, for approval) |
|---|---|---|
| How long have you trained in this sport regularly? | Position within the range | Not yet regularly · Under 6 months · 6 months to 2 years · More than 2 years |
| How often do you train in it in a typical recent week? | Position within the range | Less than once · 1–2 times · 3 or more times |
| Have you had a break of more than three months recently? | Caution after a lay-off | Yes · No |

Where these would go is not decided. The existing level menus sit on Screen 4 (Goals), which is locked; adding questions there, or on a new page, needs your approval. Nothing has been changed.

## Part C — Proposed operational definitions

**C1. Experience levels (the same three statements for every sport, worded for the sport).** The athlete picks the statement that describes them. These are self-descriptions, not tests.

| Level | Statement | Example — running | Example — swimming |
|---|---|---|---|
| Beginner | New to the sport, or returning after a long break; not yet training in it regularly. | "I'm new to running or just getting back to it." | "I'm new to swimming for fitness or just getting back to it." |
| Intermediate | Trains in the sport regularly and is comfortable completing its usual sessions without guidance. | "I run regularly and can complete my usual runs comfortably." | "I swim regularly and can complete continuous sessions comfortably." |
| Advanced | Has trained in the sport for a long time in a structured way, using different session types on purpose; may compete. | "I've followed structured running training for a long time." | "I've followed structured swim training for a long time." |

**C2. Position within the range.** Default is the lower end. The upper end needs supporting history.

| Declared level | Without history | With supporting history |
|---|---|---|
| Beginner | G0 | G1 |
| Intermediate | G1 | G2 |
| Advanced | G2 | G2 |

**C3. "Supporting history" (proposed).** Either of:

- **Recorded history** — completed sessions in that sport recorded in Cyclift or imported from a connected service. The amount required is to be set with decision 9's research; until then recorded history is shown as evidence but does not move the estimate.
- **Declared history** — the two history answers in Part B both in their top band ("More than 2 years" and "3 or more times"), with no recent long break. This moves the position within the range only; the result is still "Estimated".

**C4. What never counts toward the estimate.** The chosen week (decision 7); an entered, untested FTP (decision 8); goals; equipment; anything tapped on the Evolution rail.

**C5. Overall estimate.** The main sport's estimate. If the main sport has no experience answer, the overall status is "Not assessed" (decision 5), even when other sports have estimates; those are still shown on their own lines.

**C6. Two main sports (assumption to confirm).** The roster allows two main sports with a balance setting. Proposed: the overall estimate is the lower of the two, and both are shown.

**C7. One source (decision 11).** One shared assessment result feeds both onboarding and Progress, carrying the stage, whether it is Estimated or Verified, and the reason. Today Progress states that no stage is assigned; it would switch to the shared source only when the policy is activated.

## Part D — Worked examples

Using Part A's mappings and Part C's definitions. "History" means supporting history as in C3. Sports without an experience question today are shown as they would work **once that question exists**.

| # | Athlete | Per-sport reading | Overall | Label |
|---|---|---|---|---|
| 1 | **Running** (main), Beginner, no history | Running G0 | **G0** | Estimated |
| 2 | **Running** (main), Intermediate, declared history in the top bands | Running G2 | **G2** | Estimated |
| 3 | **Running** (main) today — no experience question exists | Running not assessed | **Not assessed** | — |
| 4 | **Strength** (main), Beginner, trains twice a week for four months | Strength G0 (history not in the top bands) | **G0** | Estimated |
| 5 | **Strength** (main), Advanced, no history given | Strength G2 | **G2** (cap) | Estimated |
| 6 | **Cycling** (main), Intermediate, no history; entered FTP, untested | Cycling G1 — the FTP does not count | **G1** | Estimated |
| 7 | **Cycling** (main), Advanced, years of structured training, races | Cycling G2 | **G2** (cap; higher only when verified) | Estimated |
| 8 | **Swimming** (main), Intermediate, returned last month after a year away | Swimming G1 (recent long break) | **G1** | Estimated |
| 9 | **Mixed:** Cycling (main) Intermediate with history + Strength Beginner | Cycling G2 · Strength G0 | **G2** | Estimated |
| 10 | **Mixed:** Strength (main) Beginner + Cycling Advanced | Strength G0 · Cycling G2 | **G0** | Estimated |
| 11 | **Mixed:** Running (main, no answer) + Cycling Intermediate | Running not assessed · Cycling G1 | **Not assessed** | — |
| 12 | **Mixed, two main sports:** Cycling Intermediate + Strength Beginner, no history | Cycling G1 · Strength G0 | **G0** (lower of the two — C6, to confirm) | Estimated |
| 13 | Any athlete who taps G5 on the rail | unchanged | unchanged | Previewing only |

Example 9 is your own case: intermediate cycling with beginner strength gives an estimated G1 or G2 depending on history, never G3.

## Open items for approval before activation

1. The three history questions and their answer choices (Part B).
2. The level statements (C1) and their wording per sport.
3. What counts as supporting history (C3).
4. The two-main-sports rule (C6).
5. Whether mobility and recovery activities carry a stage at all.
6. Where the new questions are asked (needs approval because onboarding pages are locked).

Separately gated and not part of activation of estimates: verification thresholds (decision 9) and any lowering policy (decision 10).
