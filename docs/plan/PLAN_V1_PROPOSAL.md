# Plan v1 — proposed structure for the UI Lab (for owner review)

Status: **proposal only.** Nothing is built. No Plan prototype starts until this structure is reviewed.
Basis: `PLAN_CURRENT_UI_AUDIT.md` and the Home v2.3 design system (six themes, same components).

## 1. The idea in one line

**Show the week once, and let the selected day carry the detail** — instead of the same seven days appearing as a
ring, a timeline and a card list.

## 2. Proposed order (top to bottom)

| # | Section | What it shows | Replaces today |
|---|---|---|---|
| 1 | Header | "Plan", week range, previous / next week | Band A |
| 2 | Week summary line | One line: "3 of 4 sessions · 1h 57m of 5h 25m" with the small Consistency ring from Home; tap → weekly overview | Band B (ring card) |
| 3 | Attention row (only when needed) | One compact row at a time: "1 change needs your decision" (→ Coach proposal detail) or "Riding is 40 min over" (→ Fix plan) | Proposal strip + Fix row |
| 4 | Week strip | The Home v2.3 seven-day strip, slightly taller: one icon per session with the same state marks; the selected day is highlighted (today by default) | Band C (seven full rows) |
| 5 | Selected day | The day's sessions as cards: title, duration, state, the coach's reason in one line, and the primary action (Start / Resume / Open). Rest day and free day have their own quiet states; a free day offers "Add session" | Bands D and E (next-session card + seven day cards) |
| 6 | Session actions | On each session card: a single "Change" menu — Swap days · Edit · Replace session · Remove. All still go through the existing before / after review | The four buttons inside the session sheet (kept there too) |
| 7 | Your week | One row: the days you train and the time budgets, with the availability icons; tap → week editor | "Your week" in Manage plan |
| 8 | More | One compact row group: Plan changes · Routines · Log a session (quick or detailed) | Manage plan + toolbar menu |
| — | Floating dock | Unchanged from Home | — |

Result: the week is on screen once, the selected day replaces three repeated surfaces, and every tool appears once.

## 3. What stays exactly as it is (behaviour)

- All destinations: weekly overview, Day details, session screens, review sheet, versions with Undo, Fix plan, week editor, routines, logging.
- Edits are previewed before saving; nothing in the plan changes without approval.
- One data source with Home (same week ledger and overview).
- Missing data stays missing; no invented numbers; no judgement colours without a documented meaning.

## 4. What changes for the user

| Change | Reason (audit reference) |
|---|---|
| One week view instead of three | D1, C9 |
| No separate Next-session card; today is selected and its session carries Start | D2 |
| Same icons and state marks as Home v2.3 | C3 |
| Pending proposals open the Coach proposal detail (what / why / benefit / impact / decide) | D5 |
| "Move" → "Swap days", "Swap" → "Replace session" | C1 |
| Each tool listed once | D3, D4, C8 |
| Selecting a day shows its sessions in place; the separate read-only Day page is no longer needed from Plan | C2, C6 |
| One visual system, six themes | C7 |

## 5. States to design

Established week · new athlete with no plan yet · week before the plan started · rest day selected · free day selected ·
two sessions on one day · missed session · skipped session · coach-adjusted session · session in progress ·
pending proposal · budget conflict · next week · past week (read-only) · loading · long titles · small iPhone ·
large text · six themes.

## 6. Components

Reused from Home v2.3: header pattern, `CyCompactSchedule` / `CySessionMark` (taller variant with selection),
consistency ring, `CyWorkoutCard`, `CySheet`, `CoachProposalSheet`, `CyButton`, floating dock, empty and loading states.

New (small): week selector, attention row, selected-day panel, "Change" menu, "Your week" row.

## 7. Questions for the owner before any prototype

1. **One week view**: do you agree to drop the second list (day cards) and the separate Next-session card in favour of "week strip + selected day"?
2. **Week strip or seven rows?** The strip matches Home and is short. The current seven-row timeline shows durations for every day at once. I recommend the strip with durations shown for the selected day; the alternative is to keep rows and drop the cards.
3. **Day page**: may Plan stop pushing the separate read-only Day page (Home keeps it), since the selected-day panel shows the same sessions?
4. **Wording**: "Swap days" and "Replace session" — acceptable?
5. **Future weeks**: keep the one-week-ahead limit (with an explanation) or allow more?
6. **Pending proposals**: open the Coach proposal detail from Plan, so there is one review design?
7. **Logging**: is "Log a session" under More enough, or should logging be a visible button on a strength session card?

## 8. Not included

Training Hub, Progress, Profile, onboarding, hardware, any production change, any engine change, the Defect 6 work.
