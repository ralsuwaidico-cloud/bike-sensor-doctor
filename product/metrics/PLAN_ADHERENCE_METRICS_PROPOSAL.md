# Plan and adherence metrics — proposed definitions

Status: **Current Draft (proposal)** · Version 0.1 · 12 Nov 2026 · Level 3 (product specification)
Source: `docs/cyclift-governance`, `product/metrics/PLAN_ADHERENCE_METRICS_PROPOSAL.md`
Basis: owner decisions of 12 Nov (Plan v0.2 review, decisions 1, 2 and 5); Master Project Instructions v2.0 §9.

**Definitions only. No metric calculation was implemented or altered.** Home's consistency figure, Progress and
every existing count in the production app work today exactly as before. Nothing here is approved until the owner
approves it, and nothing is a physiological score: every figure below is a count or a sum of recorded facts.

## 1. Why three measures

One number cannot answer three different questions truthfully.

| Measure | Question it answers | A session missed on Monday and done on Thursday |
|---|---|---|
| **Schedule adherence** | Did I train on the days I planned? | Not adherent |
| **Training fulfillment** | Did I do the training that was prescribed, whenever I did it? | Fulfilled, late |
| **Actual completed volume** | How much did I really train? | Counted once, on Thursday |

## 2. Terms

| Term | Meaning |
|---|---|
| **Prescribed occurrence** | One session the plan asked for, identified by its original scheduled date. A rescheduled or replacement session is **not** a new prescribed occurrence — it belongs to the original one through its link |
| **Linked session** | The session created when a missed session is rescheduled or replaced |
| **Completed record** | What was actually done: a recorded ride, a strength log, or a manual completion. Carries the actual duration and, where it exists, the workload |
| **Prescribed duration** | The minutes the original occurrence asked for. Kept unchanged when a replacement is shorter |
| **Actual duration** | The minutes in the completed record. For a manual completion with no duration stated, the duration is **not stated** — it is never filled in from the prescription |
| **Workload** | Session load = RPE × minutes, only where an RPE was recorded; otherwise **not available**. Never estimated |
| **Period** | A week, Monday to Sunday (Plan specification question Q4) |

## 3. The seven definitions

| # | Metric | Definition | Unit | Kind |
|---|---|---|---|---|
| 1 | **Schedule adherence** | Prescribed occurrences completed **on their scheduled date** ÷ prescribed occurrences scheduled in the period. "Scheduled date" is the date the occurrence had when its day began. A linked session never counts here; its original already counted as not adherent | sessions, "4 of 5" | Calculated from records |
| 2 | **Training fulfillment** | Prescribed occurrences that were done — on the day **or** through a completed linked session — ÷ prescribed occurrences of the period. Each occurrence counts at most once. A shortened replacement counts as *partially fulfilled*, shown separately. Alongside the count, a time view: for each occurrence, the smaller of actual and prescribed minutes, summed, ÷ prescribed minutes | sessions, "4 of 5, 1 partial"; minutes, "3 h 15 of 3 h 45" | Calculated from records |
| 3 | **Actual completed volume** | The sum of actual durations of all completed records dated in the period — planned, linked and unplanned alike — each record once, on the date it was done. Workload shown beside it where available | minutes (and load where recorded) | Measured / user-entered |
| 4 | **Rescheduled sessions** | Prescribed occurrences of the period whose resolution is "rescheduled" (missed, then given a new date). Sessions moved **before** their day are reported separately as "moved in advance" | sessions | Count |
| 5 | **Partially completed sessions** | Completed records whose actual duration is below the prescribed duration of the occurrence they belong to — including every shortened replacement. Shown as "30 of 45 min" | sessions, with minutes | Count |
| 6 | **Skipped sessions** | Prescribed occurrences of the period that the athlete marked Skipped | sessions | Count |
| 7 | **Removed future sessions** | Occurrences of the period the athlete removed before they were started | sessions | Count |

Missed and unresolved sessions need no new definition: they are prescribed occurrences with no completion, no skip
and no link.

## 4. How each case is counted

One prescribed occurrence of 45 minutes, scheduled on Monday.

| What happened | Schedule adherence | Training fulfillment | Actual volume | Other counts |
|---|---|---|---|---|
| Done on Monday, 45 min | 1 of 1 | 1 of 1 | 45 min, Monday | — |
| Done on Monday, stopped at 30 min | 1 of 1 | partial (30 of 45 min) | 30 min, Monday | Partial 1 |
| Missed, rescheduled, done on Thursday, 45 min | 0 of 1 | 1 of 1 (late) | 45 min, Thursday | Rescheduled 1 |
| Missed, replaced by a 30-min version, done on Thursday | 0 of 1 | partial (30 of 45 min) | 30 min, Thursday | Rescheduled 1 · Partial 1 |
| Missed, rescheduled, the new session also missed | 0 of 1 | 0 of 1 | 0 | Rescheduled 1 |
| Skipped | 0 of 1 | 0 of 1 | 0 | Skipped 1 |
| Missed, left unresolved | 0 of 1 | 0 of 1 | 0 | — |
| Moved on Sunday to Wednesday (before its day), done on Wednesday | 1 of 1 — measured against Wednesday *(proposed, question A)* | 1 of 1 | 45 min, Wednesday | Moved in advance 1 |
| Removed before its day | not in the denominator *(proposed, question B)* | 0 of 1 if it came from the program; not counted if the athlete had added it | 0 | Removed 1 |
| Extra session the athlete added and did, 20 min | not counted (it was not prescribed) | not counted | 20 min | — |
| Done, marked manually with no duration | 1 of 1 | 1 of 1 by count; time view "not stated" | not stated | — |

### No double counting — the rules

1. An original and its linked session are **one** prescribed occurrence. The linked session is never added to any
   denominator.
2. A completed linked session produces **one** completed record. Its minutes enter actual volume once, on the date
   it was done, and enter fulfillment once, for the original occurrence.
3. A chain (rescheduled twice) is still one occurrence; only the last link can fulfil it.
4. In the time view, each occurrence is capped at its prescribed minutes, so a long session cannot hide a missed one.
5. One completed record can fulfil only one occurrence.
6. A period that a fulfillment arrives in late: the fulfillment belongs to the **original** occurrence's week and is
   labelled "late"; the volume belongs to the week it was done *(proposed, question C)*.

## 5. Questions for the owner

| # | Question | Recommended default |
|---|---|---|
| A | A session moved **before** its day: is adherence measured against the new date? | Yes. Planning ahead is not a miss. The count "moved in advance" keeps it visible |
| B | Do removed sessions leave the adherence denominator? | Yes for schedule adherence; they stay in fulfillment when they came from the program. "Removed" is always shown as a count, so a percentage cannot be raised unseen |
| C | A late fulfillment: which week does it belong to? | The original week, labelled "late". The consequence is that a past week's fulfillment can rise after the fact; the underlying records do not change |
| D | Is there a point at which a shortened session counts as "done" rather than "partial" in the session count? | No threshold is proposed as fact. Suggested for discussion: treat a session as complete when at least 90 % of the prescribed minutes were done — **an unvalidated convenience rule, not a training claim**. Until you decide, every shorter session is shown as partial with its minutes |
| E | For strength sessions, is "partial" judged by minutes, or by planned sets completed? | Minutes for now (available for every session); sets completed as a later refinement |
| F | Which of these appear in the interface, and where? | None on Plan. Home's consistency and Progress are separate designs; this document only fixes what the words mean |

## 6. Data these definitions need (not implemented)

Original scheduled date kept on every occurrence · link from a rescheduled or replacement session to its original ·
resolution on a missed occurrence · prescribed duration retained beside the replacement's actual duration · a
removal record · a "moved in advance" marker. These are items 1–3 and 12–14 of the Plan specification §15.

## 7. Relation to what exists today

The production app derives session status per session (planned, started, in progress, completed with a log,
completed manually, skipped, imported from Health) and shows sessions done against a weekly target on Home and
Progress. None of that distinguishes a rescheduled session, because the link does not exist yet. How today's
consistency figure maps onto the three measures above was **not** analysed in this document and must be, before any
calculation changes.

## 8. Limits

Proposal written from the Plan specification and a reading of the status and completion types in the production
source (`ios/checkpoint-f-ride`, commit `4e2e9dc`). Nothing was run; no figure was computed from real data.

## Change log

| Version | Date | Change |
|---|---|---|
| 0.1 | 12 Nov 2026 | First proposal |
