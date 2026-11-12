# Home v2.3 — state and interaction matrix (prototype)

Lab scenarios (Profile tab › Home scenario): Established hybrid (recovery % = sample) · Hybrid with recovery as a
status word · New athlete · Loading · Cycling only · Strength only · No planned sessions · No recovery data ·
No Apple Health / partial sensor data · No sleep source · Long name. Plus small iPhone and large text.

| Element | Normal | Empty / insufficient | Loading | Other states |
|---|---|---|---|---|
| Consistency | Arc + percentage | Dashed ring + reason | Track, no value | — |
| Training Mix — rings | Each discipline completed ÷ planned | Discipline not planned → inactive dashed ring | Tracks | — |
| Training Mix — centre | Completed-time ratio "66:34" | No completed time → "—" and "No training time yet" / "Nothing planned" | Empty | Cycling only "100:0" · Strength only "0:100" |
| Recovery | **Numeric sample**: ring + "68%" + "Sample score" | **Awaiting**: dashed ring, dash, "Awaiting data" | Track, no value | **Qualitative**: plain ring, text icon, status word, no % · **Partial**: dashed ring, "Partial data", no % |
| Getting Started | Required step open → card under the indicators | No steps → hidden | Hidden | Complete → one line at the bottom |
| Schedule | One icon per session + state mark; today tinted | "No sessions planned this week" | Seven skeleton cells | Completed · planned · missed · rescheduled · rest · two sessions |
| Sport cards | Done / planned, bar, one metric | "Not in your plan" / "No … yet" | Skeleton | — |
| Sleep bar | Last night, bar, 7-day average, "Your target" | "No record", "—", **"Target not set · Set"** | Skeleton | Target set / changed / removed in the Sleep sheet |
| Coach preview (Home) | Latest relevant insight, two lines | Explanatory text for a new athlete | Skeleton, not tappable | "Needs your decision" marker while a proposal is pending or postponed; after a decision it shows the newest advice, never the decision message |
| Coach conversation | Timeline by date, newest at the bottom | "No coach notes yet" | — | Proposal pending · postponed (still decidable) · accepted · declined (read-only, history kept) |
| Trends graph | Lines + points, two labelled scales where units differ | "Your training appears here after your first session." / "No data for this metric in this period." | Skeleton | Selected day · scrubbing · hidden series · 7 days / 4 weeks · missing days as gaps · recovery score absent (status-word scenarios) |
| Key metrics | Row with value, unit, baseline, marker | "—" / "No data" | Skeleton rows | Stacks at large text |
| Dock | Highlight on the destination | — | Badge hidden | — |

Rules held in every state:
- Missing data is shown as missing; nothing becomes zero, an estimate or an interpolated line.
- The recovery percentage exists only as marked sample data. Three of the four recovery states show no number.
- The Mix centre uses minutes only. Rings and centre are explained as different measurements.
- Weekly load keeps its unit (session effort × minutes, "RPE×min").
- Two different units never share one unlabelled axis.
- No stress, strain, readiness, fitness-age or biological-age score appears anywhere.
- Session state is never colour alone (dot, hollow dot, cross, arrow, moon).

## Interaction matrix (v2.3)

| Interaction | Expected | Test |
|---|---|---|
| Tap each indicator | Its own sheet | T01 |
| Tap each of the seven days | That day's sheet | T07 |
| Tap Endurance / Strength card | Its sheet | T25 |
| Tap Sleep; set and remove a target | Sheet; Home line updates | T08, T24 |
| Tap Coach preview | Conversation opens; no decision buttons on Home | T09 |
| Scroll the conversation back | Oldest message reachable; decided proposal keeps its history | T23 |
| Approve / Not now / Decline in the proposal detail | Status, decision and outcome appear in the timeline; Home updates | T09, T10 |
| Tap / drag on the graph; vertical swipe over it | Day selected / scrubbed; page still scrolls | T11–T13 |
| Series, view and range switching | Correct series and units | T14, T15 |
| Tap each metric row | Its sheet | T17 |
| Dock | Switches destination; never covers the last rows | T18, T19 |
| Complete the required setup step | Card moves from under the indicators to the bottom | T20 |
| Open a sheet as soon as the previous one has closed (12 times) | Opens every time | T27 |
| Tap the next control with no wait after Close (6 times) | Honoured or ignored, never stuck; outcome recorded | T28 |
| Rapid double tap on four controls | Exactly one sheet or page; one close is enough | T29 |
| Sheet requested 0–450 ms after Close, from inside the app | Shown every time (with the guard) | T30 |
| The same without the guard (plain SwiftUI) | Observation only, recorded | T31 |
| Six themes | Each launches and responds | T26 |
| Large text; loading; new athlete | Usable; no values; truthful empty states | T21, T22, T03, T16, T23 |
