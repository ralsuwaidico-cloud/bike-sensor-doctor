# Checkpoint H — Appearance families and fixed performance grading (owner specification, 8 Nov 2026 13:54)

Status: **tracked enhancement, not started.** Scheduled after the Ride milestone build (Checkpoint F) is secured and
never on the Checkpoint F branch. Owner acceptance is the final gate; build 176 stays the accepted baseline until the
owner approves its replacement.

## A. Fixed performance grading (theme-independent)

Four semantic grading colours, **never** replaced by a theme accent:

| Grade | Meaning | Colour (light / dark canvas) | Text / icon indicator |
|---|---|---|---|
| Red | critical / significantly outside target | `#B91C1C` / `#FF5A5A` | "far off" · `exclamationmark.triangle.fill` |
| Yellow | caution / needs adjustment | `#9A5A00` / `#FFB64D` | "adjust" · `exclamationmark.circle` |
| Light blue | on target | `#0E6B8C` / `#5BD0F5` | "on target" · `checkmark.circle` |
| Green | excellent / goal achieved | `#1B7A3E` / `#56E08C` | "achieved" · `star.fill` |

Rules
- Grading is **metric-specific** — no universal numerical threshold. First set (to be reviewed with the owner before
  implementation; each rule lives next to the metric's own model and is unit-tested):
  - Power vs step target band (FTP known): inside band → light blue; within ±5 % of the band edge → yellow; further
    → red; last 30 s average inside the band for ≥ 90 % of the step → green at step end.
  - Heart rate vs zone band: same shape as power, using the zone bounds.
  - Cadence vs preferred range: inside → light blue; within 5 rpm → yellow; further → red; green not used (no "goal").
  - Interval done vs target (results page): completed in target → light blue; outside band → yellow; cut short → red;
    all steps in target → green summary.
  - Plan adherence (week): ≥ 90 % planned minutes → green; 70–89 % → light blue; 50–69 % → yellow; < 50 % → red.
  - Records: new record → green; within 2 % of the record → light blue; otherwise no grade (information, not failure).
- **Missing sensor data is never graded**: no colour, the plain "no power meter / no heart rate" statement stays.
- **Every graded state carries text or an icon** (above) so colour is never the only signal (accessibility).
- The grading tokens are defined once (`Grading.swift`) and are not part of any theme family.

## B. Six app appearances (three families × dark / light)

| Family | Dark variant | Light variant | Character |
|---|---|---|---|
| Cyclift (default brand) | Midnight Blue | Arctic | current look, refined |
| Sport | Graphite | Steel | bold, technical |
| Bloom | Plum | Rose | soft, elegant |

- Centralised design tokens per appearance: background, card, elevated card, text (primary / secondary / tertiary),
  border, button (filled / tinted / plain), accent, accent-on-text. `CyTheme` becomes appearance-driven; `BC.*` and
  `D7.*` read from it. No view hard-codes a colour.
- The four grading colours stay fixed across all six appearances (test: snapshot of the grading tokens per appearance
  is byte-identical).
- Contrast: every text token on its background ≥ 4.5:1, large text ≥ 3:1, each grading colour on both canvases
  ≥ 3:1 (icon) — enforced by a unit test over all six appearances.
- Ride display override (Night / Daylight / Auto) stays separate and keeps working in every family: Night = the
  family's dark cockpit, Daylight = the high-contrast light cockpit, Auto = the family's current variant.

## C. Onboarding Page 1

- Add a compact **Male / Female / Prefer not to say** question to page 1 (existing personal fields unchanged; no new
  page). Optional; default "Prefer not to say".
- Suggestion only: Male → Sport, Female → Bloom, skipped → Cyclift. The three families and **Dark / Light** are shown
  on the same page with an **immediate live preview**. Any family may be chosen regardless of gender; once the rider
  has chosen manually, a later gender change never overwrites the choice (`appearanceChosenByUser` flag).
- Gender is **never** used for training capacity, performance, health or coaching targets (unit test: the planner,
  engine and coach inputs contain no gender field).
- Theme and gender are editable later in Profile (Appearance page; gender under personal details).

## D. Compatibility and delivery

- Migration: existing settings decode unchanged; existing users default to **Cyclift** in their current light/dark
  preference; `rideDisplay` is preserved; `appearance` (system / light / dark) is preserved as the variant selector.
- Separate branch `impl/checkpoint-h-appearance`, its own CI runs and its own TestFlight build; never mixed into the
  Checkpoint F release.
- Tests to add: light/dark previews of every key screen in all six appearances (layout audit extension, screenshots
  kept as evidence); contrast tests (all tokens, all appearances); onboarding persistence tests (gender + appearance
  survive relaunch and migration; manual choice survives a gender change); grading-colour invariance across all six
  appearances; "missing data is not graded" tests per metric; VoiceOver labels carry the grade text.
- Blueprint milestone CP-H and app tracker rows APP-039…APP-042 track it.
