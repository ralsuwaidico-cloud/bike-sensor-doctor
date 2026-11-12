# Home v2.2 — state matrix (prototype)

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
| Sleep bar | Last night, bar, 7-day average, labelled target | "No sleep recorded", "—", "Not set" | Skeleton | — |
| Coach | Observation, recommendation, Review, Not now, Why? | Explanatory text | Skeleton | Postponed · Accepted · Declined · No proposal |
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
