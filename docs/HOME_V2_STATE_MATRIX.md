# Home v2 — state matrix (prototype)

Lab scenarios: **Established athlete**, **New user**, **Loading** (Lab tab › Home scenario).
"n/a" = the state does not exist for that element by design.

| Element | Normal | Empty / insufficient data | Loading | Disabled | Selected |
|---|---|---|---|---|---|
| Header greeting | Greeting text | n/a | Skeleton line | n/a | n/a |
| Avatar | Initial | n/a | Shown | n/a | n/a |
| Consistency ring | Arc + "80%" + "4 of 5 sessions" | Dashed ring, "?" and "Starts with your first session" | Track + spinner + "Loading" | Not tappable when no action is supplied (generic use) | n/a |
| Load Balance ring | Full ring, status icon + word ("Balanced" / "Elevated" / "Below target") — never a number | Dashed ring + "Needs 4 weeks of sessions" | as above | as above | n/a |
| Recovery ring | Status icon + word ("Train as planned" / "Watch" / "Take it easier") | Dashed ring + "No readings" | as above | as above | n/a |
| Getting Started | Expanded list while an essential step is open (below the circles) | n/a (hidden when there are no steps) | Hidden while loading | Checklist rows can be disabled (gallery) | Done rows: green tick + strikethrough; collapsed "Setup complete" at the bottom |
| Seven-day strip | Icons + status per day | "No plan for this week yet." | Seven skeleton cells | n/a | Today: outlined and tinted cell |
| Endurance card | Time, "of planned", bar, distance, sparkline | "No rides yet…"; without two weeks of data: "Trend appears after two weeks of sessions." | Skeleton | n/a | Pressed state |
| Strength Load card | "2 of 3", "sessions completed", bar, volume, sparkline | Shows "0 of 2" (a true count) and the trend note | Skeleton | n/a | Pressed state |
| Coach row | Sentence + Why? (+ Review, Not now when there is a proposal) | "Complete a session and answer the short check-in…" | Skeleton lines | n/a | n/a |
| Trends chart | Line + two status rows + chips + readout | "Trends appear once you have completed sessions. Nothing is estimated in the meantime." | Skeleton block | n/a | Selected day: marker, enlarged point, outlined cells; hidden series: hollow chip |
| Review sheet | Changes, why, benefit, impact, three buttons | "No changes to review." | n/a | Approve disabled with the reason shown (blocked case) | n/a |
| Confirm sheet | Message + Confirm / Cancel | n/a | Confirm shows a spinner, Cancel disabled | — | n/a |
| Buttons (all kinds) | ✓ | n/a | Spinner replaces the icon; taps ignored | Dimmed fill and text | Icon button: filled |
| Tab bar | ✓ | n/a | n/a | n/a | Accent colour + selected trait |

Rules held in every state:
- Missing data is shown as missing (dashed ring, "—", "no data", an empty day), never as zero or an estimate.
- Load Balance and Recovery are words with an icon; no number is attached to either.
- Colour never carries meaning alone: every status has an icon and a word; every category has an icon and a label.
