# Home v2.2 — screen map (prototype)

Order follows the owner's v2.2 instruction (12 Nov 2026). "Prototype behaviour" happens inside the UI Lab only, on
sample data. Every interactive element has a local action; nothing is decorative. The last column names the
interaction test that exercises the element (see `HOME_REVIEW_TRACKER.md` for results).

| # | Section | Element | Type | Prototype behaviour | Later connects to (production) | Test |
|---|---|---|---|---|---|---|
| 1 | Header | Date · athlete type; name on one line | Text | Sample values | Date; profile | — |
| 1 | Header | Avatar | Button | Mock profile sheet | Profile | T18 |
| 2 | Indicators | Consistency (single ring, percentage inside) | Button | Adherence sheet | Week overview | T01 |
| 2 | Indicators | Training Mix (outer ring endurance, inner ring strength, **ratio of completed time in the centre**) | Button | Sheet: completed ratio, planned ratio, minutes, what the centre means, what the rings mean, each discipline's progress | Week totals per discipline (existing) | T01–T03 |
| 2 | Indicators | Recovery (single ring; **sample percentage** or a status icon; no heart, no arcs) | Button | Sheet: headline, SAMPLE SCORE tag when numeric, readings, missing inputs, guidance, "About the number", "Not medical advice", source | Recovery page (words exist; a percentage needs an approved method) | T01, T04–T06 |
| 3 | Getting Started (only while a required step is open) | Next required step | Button | Completes the step locally; card leaves the top | The step's destination | T20 |
| 4 | Schedule | Seven day cells — one icon per session with a state mark beneath (dot, hollow dot, cross, arrow) | 7 Buttons | Day sheet for that date | Day page | T07 |
| 5 | Sport cards | Endurance, Strength | 2 Buttons | Discipline sheet with history | Progress | — (screenshots) |
| 6 | Sleep | Sleep bar: last night, bar, 7-day average, target (labelled) | Button | Sleep sheet; explains last night / average / target / recommendation | Recovery › Sleep | T08 |
| 7 | Coach | Observation → recommendation; "rules-based" tag | Text | Sample | Coach item | — |
| 7 | Coach | Review · Not now · Why? | 3 Buttons | Review sheet (Approve / Not now / Decline) · postpone · explanation | Review flow; Why sheet | T09, T10 |
| 8 | Trends | View picker: Training & Recovery · Activity · Recovery trends | 3 Buttons | Switches the series set | Same | T14 |
| 8 | Trends | Range: 7 days · 4 weeks | 2 Buttons | Switches the range and clears the selection | Same | T15 |
| 8 | Trends | Series chips | Buttons | Show / hide (or choose one metric in Recovery trends) | Same | T14 |
| 8 | Trends | Line graph with points | Tap, drag; one accessible element per day | Selects the day: vertical guide, larger points, value panel | Same | T11–T13 |
| 8 | Trends | Value panel › Open day | Button | Daily sheet for the selected date | Day page | T11 |
| 8 | Trends | Info | Button | "How Trends works" | Same | T16 |
| 9 | Key metrics | Up to six rows (icon, name, value, unit, baseline, direction marker, chevron) | Buttons | Metric sheet | Progress / Recovery detail | T17 |
| 10 | Setup complete (after required steps) | "Setup complete · n optional left" | Button | Expands the list | Same | T20 |
| — | Floating dock | Home, Plan, Progress, Profile; centre "Train now" | 5 Buttons | Home live; Plan and Progress mock destinations; Profile = UI Lab; centre opens a sample sheet | Existing destinations | T18, T19 |
