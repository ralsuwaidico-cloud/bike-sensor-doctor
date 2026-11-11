# Home v2.1 — screen map (prototype)

Order follows the owner's v2.1 hierarchy (12 Nov 2026). "Prototype behaviour" happens inside the UI Lab only.
Every interactive element has a local action; nothing is decorative.

| # | Section | Element | Type | Prototype behaviour | Later connects to (production) |
|---|---|---|---|---|---|
| 1 | Header | Date · athlete type (one small line) | Text | Sample values | Today's date; athlete type from the profile |
| 1 | Header | "SAMPLE" tag | Label | Lab only | Removed at integration |
| 1 | Header | Name (one line; wraps only at accessibility sizes) | Text (heading) | Sample name | First name from the profile |
| 1 | Header | Avatar | Button | Mock profile sheet → "Open Profile and UI Lab" | Profile |
| 2 | Indicators | Consistency (single gradient ring, percentage inside) | Button | Adherence sheet: ring, counts (planned to date, completed, missed, rescheduled, still to come, rest days), the week day by day | Week overview |
| 2 | Indicators | Training Mix (outer ring endurance, inner ring strength, "Mix" in the centre) | Button | Sheet: each discipline's completed vs planned with its own bar and percentage, explanations; inactive discipline shown as "not in your plan" | New: per-discipline plan progress (existing week totals) |
| 2 | Indicators | Recovery (three availability arcs + icon + word; no percentage) | Button | Sheet: each reading with value or "No reading", guidance, data source and freshness | Recovery page |
| 3 | Getting Started (required step open) | Next required step row with arrow | Button | Marks the step done locally (stand-in for opening it) | The step's destination |
| 3 | Getting Started | "All steps (n optional)" | Button | Expands the full list | Same |
| 3 | Getting Started | Step rows with Required / Optional tags | Buttons | Toggle done locally | Each step's destination |
| 4 | Schedule | Seven day cells (letter + session marks; today tinted) | 7 Buttons | Day sheet with that day's sessions and states | Day page |
| 5 | Sport cards | Endurance card (done / planned, thin bar, one metric) | Button | Sheet with totals and the 8-week history that left the card | Progress › Cycling |
| 5 | Sport cards | Strength card (sessions done / planned, thin bar, one metric) | Button | Sheet with totals and history | Progress › Strength |
| 6 | Sleep | Sleep bar (last night, bar = last night ÷ target, 7-day average, target) | Button (whole row) | Sleep sheet: last night, average, target and its source, recent nights, guidance, data source | Recovery › Sleep (existing sleep readings) |
| 7 | Coach | Sentence, "rules-based" tag | Text | Sample sentence | Current coach item |
| 7 | Coach | Review (primary, only when a decision is pending) | Button | Review sheet: Approve / Not now / Decline — three different outcomes | Review and approval |
| 7 | Coach | Not now (secondary text) | Button | Marks the suggestion "Postponed — still waiting"; Review stays available | Postpone (planned coach feature) |
| 7 | Coach | Why? (small) | Button | Explanation sheet | Why sheet |
| 8 | Trends | Info button | Button | "How Trends works" sheet (methodology moved off the chart) | Same |
| 8 | Trends | Range control: 7 days / 4 weeks | Segmented | Switches the sample dataset | Same |
| 8 | Trends | Chart (stacked training minutes; planned as a faint bar) | Touch / drag; VoiceOver adjustable | Selects a day: highlight band, bold label, tooltip | Same |
| 8 | Trends | Tooltip "Open day" | Button | Daily metrics sheet (only what the sample holds for that day) | Day page |
| 9 | Key metrics | Up to six tiles in two columns | Buttons | Metric sheet: value, comparison, 8-week history, explanation, source | Progress / Recovery detail pages |
| 10 | Setup complete | "Setup complete · n optional left" line | Button | Expands the step list | Same |
| — | Floating dock | Home, Plan, Progress, Profile | 4 Buttons | Sliding highlight; Home live, Plan and Progress mock destinations, Profile = mock profile with the UI Lab | Existing destinations |
| — | Floating dock | Centre "Train now" with today's session count | Button | Sample sheet listing today's sessions | Training Hub |
