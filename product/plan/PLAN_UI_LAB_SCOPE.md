# Plan v2.0 — UI Lab implementation scope (for approval)

Status: **Pending Review** · Version 0.1 · 12 Nov 2026 · Level 3
Source: `docs/cyclift-governance`, `product/plan/PLAN_UI_LAB_SCOPE.md`
Specification: `product/plan/PLAN_V2_SPECIFICATION.md` v0.3.

**Nothing in this document has been started.** The owner's authorisation of 12 Nov is conditional: UI Lab work may
begin only after Plan v0.3 and its open questions have been reviewed. This is the scope that would then be built.

## 1. What a UI Lab prototype is — and is not

A separate sample-data app on the isolated branch `proto/ui-lab`, the same place and pipeline as the Home
prototype. It shows how Plan would look and respond. It contains **no planning engine, no real athlete data, no
metric calculation and no connection to the production app**. Every session, warning and suggestion in it is sample
data, labelled as such in the documentation.

## 2. In scope

| # | Item | Specification |
|---|---|---|
| 1 | Plan landing: header and More menu, one-line goal row, two-section selector | §5 |
| 2 | Weekly Calendar: week navigation, date jump, Today, seven-date selector with discipline marks, session rows with one status word, Add session | §6.1–6.2 |
| 3 | Session states: planned, in progress, done, missed, skipped; rest day; empty day; one, two and three sessions; long names | §6.2, §13 |
| 4 | Session planning detail sheet with the actions valid for each state | §6.3–6.4 |
| 5 | Add session sheet | §6.5 |
| 6 | Move to any day: destination choice, soft warnings with "Move anyway", hard blocks with a reason, preview, history entry, Undo | §6.6 |
| 7 | Missed session: Reschedule, Shorten or replace, Skip, Ask Coach (prepared options), Leave; linked pair shown on both dates; shortened replacement shown as "30 of 45 min prescribed" | §6.7 |
| 8 | Skip with Restore; Remove with Undo | §6.8 |
| 9 | Recurring Plan: seven rows, availability row, contextual warning on a row, weekday sheet with two scopes, preview | §7 |
| 10 | Availability & preferences screen (rows only; each row opens a placeholder titled with the name of the existing editor) | §7.3 |
| 11 | Routines list and one routine editing screen (static sample) | §9 |
| 12 | Goal & Program screen with existing-data content only | §8 |
| 13 | One planning-suggestion row opening the shared proposal detail already built for the Home prototype | §11 |
| 14 | Plan history list with Undo | §12 |
| 15 | Six themes; default and largest accessibility text sizes; small and standard simulators | §17–18 |

## 3. Out of scope

- Everything marked Future in the specification: events, named programs and phases, times and windows, date-range
  exceptions, saved endurance workouts, Weekly Planning Review, external calendars, free-text Coach.
- Any metric of the metrics proposal (no adherence, fulfillment or volume figure is shown anywhere on Plan).
- Any change to automatic adaptation.
- Train: the prototype shows "Start in Train" and "Log this session" as handover points that end on a labelled
  placeholder.
- Production code, the release branch, TestFlight, databases, migrations, Apple Watch, BikeComputer, detachable
  Watch and firmware.
- Changes to the frozen Home prototype screens.

## 4. Sample-data scenarios

Normal week · week with a missed session unresolved · week with a rescheduled pair · week with a completed shortened
replacement · week with a pending suggestion · empty plan with no goal · next week · recurring plan with one row
over its available time · recurring plan over the weekly budget · two sessions on one day.

## 5. Verification that would be reported

| Check | Method |
|---|---|
| Builds; contrast script passes for six themes | Pipeline |
| Interaction tests on a small and a standard simulator: section switch, date selection, each sheet opens and closes, each action appears only in its valid state, Move with a soft warning and with a hard block, missed-session choices, Skip and Restore, Remove and Undo, scope selection, rapid repeated taps on every sheet trigger | Automated UI tests; failures investigated, not relaxed |
| Layout: no element under the dock on the small simulator at default and largest text; Recurring Plan clearance measured in the running prototype, not estimated | Automated frame checks and screenshots |
| The acceptance criteria of the specification §19 that a sample-data prototype can show | Checked one by one; the rest listed as "needs production data" |

Evidence levels will be stated separately: designed · implemented in UI Lab · compiled · simulator-tested. A
prototype cannot be physical-device-tested by me; that needs your iPhone and is not claimed.

## 6. Deliverables

Screenshots for every scenario, theme and text size · an interaction-test report · a screen map and state matrix ·
a review tracker · a list of open defects · a statement of what the prototype does not prove.

## 7. Conditions before starting

1. Plan v0.3 reviewed, with answers (or accepted defaults) for questions Q1–Q9.
2. Home v2.3 prototype result reported and its branch state stable, since both prototypes share one app and pipeline.
3. Your explicit "start".

## 8. Stop points

After the first full run: report and wait. No promotion toward production follows from a prototype review; that is
a separate authorisation under the Project Instructions §12.

## Change log

| Version | Date | Change |
|---|---|---|
| 0.1 | 12 Nov 2026 | First scope for approval |
