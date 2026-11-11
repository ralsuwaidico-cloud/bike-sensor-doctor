# Home v2.1 — state matrix (prototype)

Lab scenarios (Profile tab › Home scenario): Established hybrid · New athlete · Loading · Cycling only · Strength
only · No planned sessions · No Apple Health / partial sensor data · Long name.

| Element | Normal | Empty / insufficient / not planned | Loading | Other states |
|---|---|---|---|---|
| Header | Date · athlete type; name on one line | No athlete type → date only | Skeleton for the name | Long name: one line, scaled then truncated; wraps to three lines at accessibility sizes |
| Consistency | Gradient arc + percentage; "n of m sessions" | Dashed ring + "Starts with your first session" / "Nothing planned" | Track + spinner | — |
| Training Mix | Two rings with separate values; "Ride x% · Lift y%" | One discipline not planned → its ring is a dashed inactive track and the caption says so; nothing planned → both inactive, "Nothing planned" | Tracks + spinner | Hybrid / cycling only / strength only |
| Recovery | Three solid arcs, filled heart, supported word | Awaiting data: three dashed arcs + hourglass | Arcs + spinner | Partial: some arcs dashed, outline heart, "Partial data"; Concern: warning icon + word (sample wording) |
| Getting Started | Required step open → card below the indicators with the next action | No steps → hidden | Hidden | Complete → one line at the bottom, expandable; Required / Optional tags |
| Schedule | Marks per day; today tinted | "No sessions planned this week" | Seven skeleton cells | Completed, planned, missed, rescheduled, rest, two sessions, nothing planned on a day |
| Endurance / Strength card | Done / planned, bar, one metric | "Not in your plan" · "No rides yet · 40m planned" · "Nothing planned this week" | Skeleton, same height | Pressed |
| Sleep bar | Last night, bar, 7-day average, target | "No sleep recorded", empty bar, "7-day average —", "No target set" | Skeleton | — |
| Coach | Sentence + Review + Not now + Why? | "Complete a session and the short check-in…" | Skeleton lines | Postponed (note, Review only) · Accepted (note, no actions) · Declined (note, no actions) · No proposal (Why? only) |
| Trends | Stacked bars, legend, range control, tooltip | "Your training appears here after your first session." / "Nothing planned or recorded this week." | Skeleton block | Selected day; day without data → "No data for this day."; 4-week range |
| Key metrics | Icon, name, value, unit, comparison | "—" and "No data" per tile (never zero) | Four skeleton tiles | One column at accessibility sizes |
| Floating dock | Sliding highlight on the selected destination | — | Badge hidden while loading | Centre action raised; no highlight pill under the centre |

Rules held in every state:
- Missing data is shown as missing; nothing is replaced by zero or an estimate.
- Recovery is a word and an icon; there is no recovery percentage and no "safe to train" wording.
- Training Mix never combines the two disciplines into one number.
- The sleep target is labelled as a sample; the bar always means last night ÷ target.
- No biological-age, fitness-age or readiness score appears anywhere.
- Colour never carries meaning alone: session state is also a shape (filled, outline, dashed + slash, arrow).
