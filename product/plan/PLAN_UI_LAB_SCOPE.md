# Plan v2.0 — focused UI Lab implementation plan (for approval)

Status: **Pending Review** · Version 0.3 · 12 Nov 2026 · Level 3
Source: `docs/cyclift-governance`, `product/plan/PLAN_UI_LAB_SCOPE.md`
Specification: `product/plan/PLAN_V2_SPECIFICATION.md` v0.6 · visual direction B — Athletic Dynamic (approved 12 Nov).

**Nothing in this plan has been started. No UI Lab code was written.** It replaces scope v0.1, which predates the
visual direction.

## 1. What will be built — and what it is

A sample-data prototype of Plan inside the existing UI Lab app on the isolated branch `proto/ui-lab`. It shows how
Plan looks and responds. It contains no planning engine, no real athlete data, no metric calculation, and no
connection to the production app. Production, firmware, databases, Home and TestFlight are not touched.

## 2. Preconditions

| # | Condition | State on 12 Nov |
|---|---|---|
| 1 | UI Lab pipeline free | **Free** — no run in progress (last run 43221125374 finished 14:43 UTC) |
| 2 | Home v2.3 verification result known | **Known: not a clean pass** — 27 of 31 interaction tests passed on each simulator (§3) |
| 3 | Sheet-presentation defect understood | **Open.** Plan depends on sheets more than Home does; see §3 |
| 4 | Your explicit "start" | Awaited |

## 3. Home v2.3 result and what it means for Plan

Run 43221125374, commit `6454a13`: contrast check passed (six themes, 294 pairs) · build passed · screenshots
produced (123 screens, 22 full-length) · interaction tests **27 passed, 4 failed on each of the two simulators**.

| Test | Standard | Small | Reading |
|---|---|---|---|
| T29 rapid double tap opens one sheet | failed | failed | Reproducible on both: after two fast taps **no** sheet opened. A defect in the presentation guard |
| T30 sheet requested while another is closing (with guard) | failed, 5 of 6 shown | failed, 4 of 6 shown | Reproducible: a requested sheet sometimes never appears |
| T23 Coach conversation history | failed | failed | Same on both: the history lists 4 entries where the test expects 3. Either the screen or the test is wrong; not yet examined |
| T01 each indicator opens its sheet | failed | passed | "No sheet opened" — consistent with the same sheet defect |
| T09 Coach postpone | passed | failed | "Proposal sheet stayed on screen" — the same family |

The tests' own observation: without any guard, plain SwiftUI also lost a sheet requested 0–50 ms into a dismissal
on one simulator. So this is a real presentation problem, not timing noise, and the guard written for v2.3 does not
solve it. **Home v2.3 is therefore not ready for owner sign-off.** No test was changed or relaxed.

Consequence: step 1 of this plan repairs sheet presentation in the shared layer before any Plan screen is built on
it. That step changes UI Lab code used by Home; it needs your approval like the rest.

## 4. Work order

| Step | Content | Evidence to report |
|---|---|---|
| 1 | **Shared sheet presentation** — one presenter for the whole lab app that serialises requests (a request during a dismissal is held until the dismissal completes; a double tap yields exactly one sheet). Examine T23 and correct whichever of screen or test is wrong, stating which | Home tests T01, T09, T23, T27–T31 on both simulators, unmodified in what they expect |
| 2 | **Plan landing shell** — header and More menu; program header with primary objective, one description line and Add a goal; two-section selector; B backgrounds from theme tokens | Screens in six themes; contrast script |
| 3 | **Circular date scroller** — week paging with snap, edge days dimmed, ‹ › buttons, tap to select, selection kept across section switch; horizontal-only gesture (the UIKit technique used for the Home graph) so vertical scrolling is never trapped; Reduce Motion cross-fade; VoiceOver labels; text cap | Tests: tap each day · swipe to next and previous week · Today · vertical swipe starting on the scroller scrolls the page · selection survives section switch · labels |
| 4 | **Session cards** — discipline wash and badge; states planned, done, missed, rescheduled (link line), skipped; structure bar only when the sample prescription has steps or exercises; one, two, three sessions, long names, rest day, empty day | Screens per state; test that a session without structure shows no bar |
| 5 | **Coach row** — present only with an actionable proposal, specific summary, 44 pt; opens the shared proposal detail already in the lab (reason, alternatives, preview, approve, decline) | Tests: absent with no proposal and no gap left · opens detail · approve and decline update the row |
| 6 | **Recurring Plan** — seven rows with Mon–Sun pills, availability row, contextual warning naming the exceeded constraint; weekday sheet with two scopes and a preview; Availability & preferences screen as rows | Tests: each weekday opens its sheet · warning text matches the sample constraint · scopes |
| 7 | **Existing actions as prototype sheets** — session detail, Add session with the circular type carousel, Move with soft warning and hard block, missed-session choices, Skip and Restore, Remove and Undo, Routines list and one routine screen | One test per action; rapid-tap test on every sheet trigger |
| 8 | **Add a goal** — sheet listing the existing goal types only. Future types on a separate gallery page titled "Demonstration — not a working feature" | Screens |
| 9 | **Small iPhone and accessibility** — layout checks at default and largest text: nothing under the dock; last card scrolls fully clear; Recurring Plan clearance measured in the running prototype | Frame assertions and screenshots |
| 10 | Full run, documents (screen map, state matrix, review tracker, open defects, what the prototype does not prove), report, stop | — |

Priority, as instructed: steps 2–6 (Weekly Calendar and Recurring Plan). Steps 7–8 follow only after those are
reviewed, if you prefer two rounds.

## 5. Explicitly not included

Goal engines and feasibility calculation · automatic training changes · event programming, phases, milestones ·
unsupported sports · metrics of the metrics proposal · any change to automatic adaptation · Train (handover points
end on a labelled placeholder) · production code, release branch, TestFlight, databases, migrations, Apple Watch,
BikeComputer, detachable Watch, firmware · the frozen Home screens other than the shared sheet presenter of step 1.

Existing scheduling, routine editing and training data in the production app are not affected: the prototype is a
separate app with its own sample data.

## 6. Sample data

One consistent sample athlete (specification §24.3), checked by a unit test in the lab: scheduled days ≤ available
days, scheduled minutes against the weekly budget, each day against its limit, and every warning shown derived from
those values rather than typed in. Scenarios: normal week · missed session unresolved · rescheduled pair · completed
shortened replacement · pending suggestion · no suggestion · no goal · next week · day-limit conflict · budget
conflict · two sessions on a day.

## 7. Verification and honesty

Evidence levels reported separately: designed · implemented in UI Lab · compiled · simulator-tested. Failures are
investigated, never relaxed. A simulator result is not a device result; physical-device testing needs your iPhone
and is not claimed. Per your preference, CI is checked once per run and reported with its workflow ID.

## 8. Stop points

After step 1 (sheet repair result) · after steps 2–6 (first full Plan run) · after steps 7–9. No promotion toward
production follows from any prototype review.

## 9. Unsaved-change safeguard for Plan editing sheets (approved to document 12 Nov; **not implemented**)

Separate from the Round 1 shared-presenter repair. Nothing here is built; it applies from the first Plan editing
sheet (step 7 onward) and needs its own approval before code.

**Finding (12 Nov):** no sheet in the prototype holds unsaved edits today, so nothing is bypassed. But the shared
presenter closes an open sheet unconditionally when a different sheet is requested; an editing sheet with unsaved
changes would be closed the same way.

**Rule.** An editing sheet tracks whether it has unsaved changes. While it has:

| Attempt to leave | Behaviour |
|---|---|
| Swipe down | Blocked; the confirmation is offered |
| Tap outside | Blocked; the confirmation is offered |
| Close button | The confirmation is offered |
| Request to open another sheet | The request is held, not dropped; the confirmation is offered |

The confirmation offers exactly three choices:

| Choice | Effect |
|---|---|
| **Save** | The save runs. Only when it has **completed successfully** does the sheet close and any held request proceed. If the save fails, the sheet stays open with its edits, the failure is stated, and the held request stays held |
| **Discard** | The changes are explicitly abandoned; the sheet closes; any held request proceeds |
| **Keep editing** | The confirmation closes; the sheet stays; **any held request is cancelled** |

With no unsaved changes, every way of leaving behaves as it does today.
All four ways of leaving go through one decision point in the presenter, so they cannot behave differently.
Repeated requests while the confirmation is showing do not stack: the latest replaces the held one.

**Tests required with the implementation**

1. No changes: swipe, outside tap, Close and another-sheet request all leave at once.
2. Unsaved changes: each of the four ways shows the confirmation and does not close the sheet.
3. Save succeeds: sheet closes, edits are stored, held request opens.
4. Save fails: sheet stays open with the edits intact, the failure is shown, held request not opened.
5. Discard: edits are gone, sheet closes, held request opens.
6. Keep editing: sheet and edits remain; held request is cancelled and does not open later.
7. Repeated navigation requests during the confirmation: one confirmation, the latest request held, none lost silently and none duplicated.
8. Rapid double tap on Save: one save.
9. The same on the small simulator and at the largest text size.

## Change log

| Version | Date | Change |
|---|---|---|
| 0.1 | 12 Nov 2026 | First scope for approval |
| 0.2 | 12 Nov 2026 | Rewritten for visual direction B; Home v2.3 result and sheet defect recorded; work order prioritising Weekly Calendar and Recurring Plan |
| 0.3 | 12 Nov 2026 | §9 added: unsaved-change safeguard for future Plan editing sheets (documented only) |
