# Home v2 — screen map (prototype)

Order follows the approved hierarchy. "Prototype behaviour" is what happens in the UI Lab; nothing leaves the lab.

| # | Section | Element | Type | Prototype behaviour | Later connects to (production) |
|---|---|---|---|---|---|
| 1 | Header | Date line | Text | Sample date | Today's date |
| 1 | Header | "SAMPLE DATA" tag | Label | Shown in the lab only | Removed at integration |
| 1 | Header | Greeting | Text (heading) | Sample name "Alex" | Greeting + profile name |
| 1 | Header | Avatar | Button | Opens the Lab tab | Profile |
| 2 | Circles | Consistency ring | Button | Opens a sample detail sheet (how it is worked out, what it does not tell you) | Week overview |
| 2 | Circles | Load Balance ring | Button | Sample detail sheet, incl. "not a validated safe-training zone" and "not recovery" | Load Balance detail page (new) |
| 2 | Circles | Recovery ring | Button | Sample detail sheet | Recovery page |
| 3 | Getting Started | Header row (title, n of m, chevron) | Button | Expands / collapses the list | Same |
| 3 | Getting Started | Progress bar | Indicator | Reflects done / total | Same |
| 3 | Getting Started | Each step row | Button | Toggles done locally, so the card can be seen moving from below the circles to the bottom once both essential steps are done | The step's real destination |
| 4 | Seven-day strip | Seven day cells (weekday letter, sport icons, status icon; today outlined) | 7 Buttons | Each opens a sample day sheet | Day page |
| 5 | Sport cards | Endurance card | Button (whole card) | Sample detail sheet with weekly bars | Progress › Cycling |
| 5 | Sport cards | Strength Load card | Button (whole card) | Sample detail sheet with weekly bars | Progress › Strength |
| 6 | Coach | Coach row sentence | Text | Sample sentence | Current coach item |
| 6 | Coach | "Why?" | Button | Sample explanation sheet | Why sheet |
| 6 | Coach | "Review" (only when there is a proposal) | Button | Review sheet: Approve / Not now / Decline → sample toast | Review and approval |
| 6 | Coach | "Not now" (only when there is a proposal) | Button | Sample toast "postponed" | Postpone |
| 7 | Trends | Series chips (Consistency, Load Balance, Recovery) | 3 Buttons | Show / hide a series; one always stays on | Same |
| 7 | Trends | Line chart | Touch / drag | Selects a day; dashed marker and enlarged point | Same |
| 7 | Trends | Status rows (one cell per day) | 7 Buttons per row | Selects that day | Same |
| 7 | Trends | Readout | Text | Selected day's values and status words, "no data" where empty | Same |
| 7 | Trends | Footnote | Text | Explains percentage vs status words vs empty days | Same |
| 3′ | Getting Started (bottom position) | Collapsed "Setup complete" card | Button | Expands to the list | Same |
| — | Tab bar (navigation prototype) | Home, Plan, Progress, Lab | 4 Buttons | Home is live; Plan and Progress show "not prototyped yet"; Lab replaces Profile in the prototype | Home, Plan, Progress, Profile |
| — | Tab bar | Centre "Train now" with today's session count | Button | Sample sheet "Training Hub — not prototyped yet" | Training Hub |

Sheets opened from Home: ring detail (3), day detail, sport card detail (2), coach "Why?", review and approval,
Training Hub placeholder. Each has a Close button and can be dragged down.
