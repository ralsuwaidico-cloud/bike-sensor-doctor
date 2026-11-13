# Progress v2.0 — Phase 0: current Progress functionality and data audit

Status: **Current Draft** · Version 0.1 · 13 Nov 2026 · Level 3 (product specification)
Source: `docs/cyclift-governance`, `product/progress/PROGRESS_V2_PHASE0_AUDIT.md`
Basis: owner brief "Progress v2.0 — Athlete Singularity & Evolution System" (13 Nov 2026).

**Read-only audit. Nothing was changed.** The production source was read on the release branch
`ios/checkpoint-f-ride`, commit `4e2e9dc` (build 216 baseline). Nothing was compiled or run for this document, and
no real athlete data was examined. Statements about behaviour are readings of the code, with file and line.
**The screenshots mentioned in the brief were not attached to the message I received**; findings A–F below come
from the code alone and should be checked against those screenshots.

## 1. What Progress is today

| Part | File | What it shows |
|---|---|---|
| Progress tab | `ProgressView.swift` | Trend chart (weekly minutes or sessions against plan), a "glance" summary, checkpoints card, empty-state texts for FTP and strength, links to analytics and history |
| Analytics pages | `ProgressAnalyticsView.swift`, `ProgressAnalytics.swift` | Cycling and strength figures for a chosen period (30 / 90 days / year), zone distribution, personal records, comparison with the previous period |
| Trend maths | `ProgressMetrics.swift` | Weekly buckets, axis and range logic |
| Checkpoints | `Rc3Engine.swift` 291–, 601 | Reviews at 4, 8 and 12 weeks per sport: reached or not, what is missing, and a performance word (improved, flat, declined, not enough data) |
| Weekly counts | `WorkoutState.swift` 117– | One definition of planned, completed, minutes and "extra" used by every screen |

Progress today is a history and totals page. It has no notion of athlete level, baseline or development stage.

## 2. Data that exists today

| Data | Where | Kind | Notes |
|---|---|---|---|
| Ride duration, distance | `RideRecord` | Measured (phone GPS, BikeComputer) or imported (Apple Health) | No minimum duration to save |
| Average / max / normalised power, best 20-minute power, work (kJ), power-zone seconds, 1 Hz samples | `RideRecord` | Measured — **only when a power meter was connected** | Absent for most phone-only rides |
| Average / max heart rate, HR samples | `RideRecord` | Measured (Apple Watch or sensor) | Optional |
| Cadence | `RideRecord` | Measured when a sensor provides it | Optional |
| FTP and how it was obtained | Profile `ftpW`, `ftpHow` | assumed · from rides · entered · tested | An "assumed" FTP is treated as Unknown and never shown |
| Body weight, height, age or birth year | Profile | User-entered, optional | Needed for any relative (per-kg) or age-aware figure; may be empty |
| Strength sets: exercise, weight, reps, bodyweight flag | `StrengthSession` | User-entered | "Quick logs" hold no set detail |
| Estimated one-rep maximum | — | **Not stored.** An Epley estimate is used inside the planner only | Would need a disclosed method to be shown |
| Effort ratings (RPE) and check-ins | Check-in records | User-entered | Basis of session load (RPE × minutes) |
| Planned sessions, done, skipped, edited | `Workout` | Plan state | Reschedule links do not exist yet (Plan v2.0) |
| Training pauses (unwell, injured, away) | `TrainingPause` | User-entered | Already excluded from checkpoint weeks |
| Sleep, resting HR, HRV | Health reads | Imported, latest values and a per-day log | Not used for any score |
| VO₂ max | — | **Not read or stored** | — |
| Sex | — | **Not found in the profile fields read** | Needed for sex-aware references; to be confirmed |

## 3. Evidence by device (kept separate, as instructed)

| Surface | What the code or documents show | Status for Progress |
|---|---|---|
| **iPhone** | Records rides (GPS, optional sensors), strength logs, check-ins, plan; imports Health workouts | The only source this audit verified in code |
| **Apple Watch** | Heart rate reaches rides ("Apple Watch" listed as a source on phone rides); Health imports | Heart rate confirmed in code. Watch-side strength logging and anything else: **not verified in this audit** |
| **Waveshare BikeComputer** | Board-recorded rides are stored with a board ride id and de-duplicated against phone copies; FTP and profile are sent to the board | Board rides are a real data source in code. Sensor capability on hardware: **not verified here; see the hardware documents** |
| **LILYGO detachable Watch** | Design documents only | **No data source.** Nothing in Progress may assume it |

## 4. The six reported problems — cause as read in the code

| # | Problem | Cause found | Confidence |
|---|---|---|---|
| A | Completed ride with no duration or distance | A phone ride can be ended at any moment: `RideRecorder.end()` (line ~204) saves whatever has elapsed, with no minimum. `Store.addRide` (`Models.swift` 1356–1363) then marks the day's first open planned ride as **done**. A ride ended after a few seconds is therefore saved with 0 minutes shown, no distance, and completes the planned session. It is a legitimate but meaningless record, not corrupted data | High (code); to be matched to the actual record |
| B | Personal record "Longest time: 0 min" | `ProgressAnalytics.swift` line 126: the record is eligible when `durationS > 0` — **seconds** — but it is displayed in whole **minutes** (`durationS / 60`). Any ride shorter than a minute qualifies and prints as 0 min. "Longest ride" is protected by `distanceM > 0` and "fastest speed" by a 10-minute minimum; "longest time" has no meaningful minimum | High |
| C | Weeks 4, 8 and 12 all say "Not enough evidence yet" | `CheckpointsCard` (`ProgressView.swift` 188–219) always lists all three reviews for each sport and prints the same sentence for each one not reached | High |
| D | Large empty cards for FTP, power, heart rate, strength | The analytics and Progress views render a full card with a "Not enough data yet…" sentence for each missing input (`ProgressView.swift` 117, 148) | High |
| E | History dominates | Layout: trend chart, checkpoints and history occupy the page; nothing sits above them | High (by reading the view) |
| F | Totals that seem to contradict each other | Three different things are counted, by design, and shown close together: **completed sessions** (include manual "mark done", quick logs and imports), **minutes** (only recorded or typed durations — a session without a duration adds none, `WorkoutState.swift` 124–126), and **planned minutes**. Two further effects: each ride's minutes are rounded down separately before summing (`ProgressAnalytics.swift` line 99), and a ride of any length completes a planned session (problem A). So "3 sessions done" beside "0 h 45 min" can be true to the data and still look wrong | Medium–high; the exact contradiction in the screenshots was not seen |

**No production correction is proposed for implementation here.** Possible corrections, for a later separately
authorised change: a minimum duration for a ride to complete a planned session or count as a record; record
eligibility in the same unit as its display; and labelling minutes as "recorded".

## 5. What can be calculated today, and what cannot

| Capability | Today | Missing |
|---|---|---|
| Weekly training time and sessions, by discipline | ✓ | — |
| Weeks trained, consecutive active weeks, pauses respected | ✓ | — |
| Best 20-minute power and its change over time | ✓ **when rides have power** | A power meter; without one, nothing |
| FTP with provenance (tested / entered / from rides) | ✓ | Athletes without power have none |
| Power relative to body mass | ✓ **only if weight is entered and current** | Weight history is not kept |
| Time in power or HR zones | ✓ when samples exist | — |
| Heart-rate-to-power relationship over comparable rides | Possible from samples; **not implemented** | A definition of "comparable" |
| Heaviest set per exercise; tonnage; sets per muscle group | ✓ from detailed logs | Quick logs carry nothing |
| Estimated 1RM per exercise over time | Possible from sets; **not implemented or stored** | A disclosed formula and rep-range limits |
| Relative strength (per kg body mass) | Possible if weight entered | Weight history |
| Schedule adherence, training fulfillment | Proposed only (`product/metrics/`) | Reschedule links (Plan v2.0) |
| Session load (RPE × minutes) | ✓ where an RPE was given | — |
| VO₂ max, lactate thresholds, lean mass | ✗ | Not measured by Cyclift |
| Age- or sex-referenced comparison | ✗ | Sex not stored; reference data not chosen |
| Any stage, generation or level | ✗ | The whole framework (Phase 1 proposal) |

## 6. Limits

Read from source; not run; no data inspected; the brief's screenshots not seen. Line numbers are those of commit
`4e2e9dc`. Apple Watch, Waveshare and LILYGO capabilities are stated only as far as the iPhone code shows them.

## Change log

| Version | Date | Change |
|---|---|---|
| 0.1 | 13 Nov 2026 | First audit |
