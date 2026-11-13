# Progress v2.0 — visual design specification (collapsing singularity and full landing page)

Status: **Current Draft — awaiting owner visual review** · Version 0.3 · 13 Nov 2026 · Level 3
**v0.3 adds Part B (Progress v2.2, open-surface design).** Part B replaces the page layouts of sections 2, 5 and 6 and of the v2.1 images. Sections 3 and 4 (scroll interaction, rendering) and 7–9 remain in force.
**Design only.** Static concepts drawn as images. Nothing was built, run or measured on a device. No production code,
UI Lab code, renderer, database, firmware or TestFlight change was made. All figures in the images are **invented sample
data** and are labelled so. No advancement thresholds are defined anywhere in this document.

Approved direction this implements (owner, 13 Nov): Concept A (Cinematic Singularity) for the landing screen;
Concept C's timeline inside Athlete Evolution details; Concept B's density for performance drill-downs.
Related: `PROGRESS_V2_PHASE0_AUDIT.md`, `PROGRESS_V2_RESEARCH_AND_FRAMEWORK.md`, `PROGRESS_V2_CONCEPTS_AND_FEASIBILITY.md`.

## 1. Images

| File (`design-v02/`) | Shows | Deliverable |
|---|---|---|
| `PD1_collapsing_singularity_three_scroll_states.png` | Expanded, intermediate, collapsed header — Obsidian and Arctic | 2, 3 |
| `PD2_full_landing_page_standard_and_small.png` | Whole page top to bottom (standard and small width) and the first screen on both iPhone sizes | 1, 4 |
| `PD3_landing_six_themes.png` | Landing screen in Obsidian, Arctic, Ocean, Forest, Sandstone, High Contrast | Branding |
| `PD4_cycling_strength_and_timeline_details.png` | Cycling development, Strength development, Athlete Evolution timeline | 5, 6 |
| `PD5_first_time_missing_data_returning.png` | First-time athlete, no power meter, returning after a break | 7 |

The images are approximations of proportion and hierarchy, not pixel-accurate iOS rendering, and the singularity is a
2-D drawing standing in for the future 3-D object.

## 2. Landing page — content order

| | Section | What it holds | Opens |
|---|---|---|---|
| A | Athlete Singularity | Singularity, provisional generation (G0–G5), stage name, athletic profile, evidence confidence, date evaluated | Athlete Evolution details |
| B | Evolution since baseline | Four rows: endurance capability, strength capability, consistency & training maturity, hybrid development. Words, not scores; each row carries its own confidence | The matching detail |
| C | Performance development | Cycling / Strength / Hybrid selector; 4, 8, 12, 16-week ranges (a range is disabled when the data does not support it); one headline capability trend | Cycling / Strength / Hybrid development |
| D | Next evolution | The next stage and a count of what is demonstrated, what needs evidence, what cannot yet be measured | Requirement list in Athlete Evolution details |
| E | Evolution timeline | One-row entry with baseline date and counts | Timeline |
| F | Personal records & history | Secondary entry | Records and history |

Rules: the landing page shows summaries only; no rings, recovery cards or load dashboard (Home); no calendar or
scheduling (Plan); no level bar, no badges, no numeric "evolution score".

Space, measured on the drawings: on a standard iPhone the first screen shows A, all of B and the start of C; on a
small iPhone it shows A and all of B. Everything else is reached by scrolling.

## 3. The collapsing singularity — scroll interaction

One value, `p`, from 0 (page at top) to 1 (collapsed), is computed **only from scroll offset**:
`p = clamp(offset ÷ collapse distance, 0, 1)`. No timer drives it; if the finger stops, the transition stops; scrolling
up reverses it exactly.

| Property | p = 0 expanded | p ≈ 0.5 intermediate | p = 1 collapsed |
|---|---|---|---|
| Singularity size | Large hero | About half, moving up and toward the leading edge | Small symbol beside "Progress" |
| Visual effects (streaks, glow, particles) | Full | Reduced | Minimal: disc and ring only |
| Generation, stage name, profile | Full | Smaller and fading | Not shown |
| Confidence line | Shown | Fading (gone by about p = 0.6) | Not shown |
| Header | Large title | Large title | Compact bar with hairline; content scrolls beneath it |
| Motion of the disc itself | Slow rotation allowed | Slower | None |

Further rules:

- The compact header is a fixed bar inside the top safe area; content never sits under it unreadably, and the hero
  never overlaps the title or the "more" button.
- The symbol is decorative in the header (hidden from VoiceOver); the title "Progress" stays the heading. In the
  expanded state the singularity plus labels read as one element: "Athlete Evolution, G2, The Ascendant, Developing
  Hybrid, evidence-supported", with the hint "opens evolution details".
- Collapse distance is derived from the hero's actual height, so it remains correct at any text size.
- **Dynamic Type:** labels wrap under the singularity; at accessibility sizes the hero's disc is reduced so that the
  generation, name and profile stay fully visible, and the collapsed header keeps only the symbol and title.
- **Reduce Motion:** no spatial shrink. Two states only — expanded and compact — exchanged by a short crossfade at one
  scroll threshold, with a small gap between the "collapse" and "expand" thresholds so it cannot flicker.
- **Low Power Mode, thermal pressure, app in background, hero off-screen:** the singularity is a still image; the
  scroll-driven size change may remain because it costs almost nothing.
- **High Contrast:** line-and-shape form (ring outline and orbit lines), same geometry, same transition.

## 4. Rendering architecture — "never two black holes"

Three options were considered.

| Option | How | Risk |
|---|---|---|
| 1. One rendered view that moves | A single view, drawn once, scaled and repositioned by `p` from hero to header | Must live above the scroll content; needs careful layering. Lowest risk of visible duplication |
| 2. Hero and header views cross-faded | Two separate views; fade one out and one in | Both are visible together during the fade — exactly the "two competing black holes" to avoid; double GPU cost if both are live |
| 3. One source, two presentations | One renderer; the header symbol is a cached still taken from the same source (or the same shader at minimal detail), shown only once the hero has fully arrived | Small hand-over moment to hide |

**Proposal:** Option 1 for the whole travel, with the detail level also driven by `p`; at p = 1 the live rendering is
replaced by a still of itself in the same place and size (Option 3's hand-over, invisible because nothing moves), so the
header costs nothing while the athlete reads the page. Under Reduce Motion, Option 2's crossfade is used deliberately,
but between two **stills**, never two live renderings.

This is a proposal on paper. Whether a single view can be layered above a scrolling page without touch, clipping or
safe-area problems is unproven and must be the first thing tested in the UI Lab, before any 3-D work.
Rendering technology itself is unchanged from the feasibility document (SwiftUI with a Metal shader first; not started).

## 5. Detail screens

- **Cycling / Strength development** — time-range chips; one chart of a named capability measure with the number of
  comparable efforts and the source; a "Capability — since baseline" table; **training volume in its own block, titled
  "not capability"**; optional reference context in a separate, labelled block that never sets the stage. Rows without
  enough evidence say why ("needs more comparable rides", "bodyweight: no load estimate") rather than showing a number.
  Estimated values (estimated 1RM) are always labelled as estimates with the method.
- **Athlete Evolution timeline** — "Current evaluation" and "Highest achieved" side by side; chronological list of stage
  transitions, milestones, reduced-training periods and the baseline; filter chips. A pause never deletes or lowers a
  past achievement.

## 6. Missing data, first-time and returning athletes

| Situation | What is shown |
|---|---|
| No supportable stage | "Establishing your baseline", a quiet singularity, **no generation**, and a plain list of what builds the baseline (in words — no counts or thresholds are promised) |
| No power meter | Endurance capability "Not measurable yet"; stage may still be shown as Provisional if another dimension supports it |
| One discipline only | Profile says so (for example Strength-Focused); the missing side is "Insufficient evidence", never zero |
| Returning after a break | "Highest achieved" kept with its date; "Not currently evaluated"; rows explain what is missing |
| Body weight missing or old | Per-kg figures and reference context are not shown |

## 7. Dependencies

| # | Dependency | Why it matters |
|---|---|---|
| D1 | **Completed-ride problem** — a recorded ride of any length marks the day's planned ride done (`Store.addRide`; `RideRecorder.end()` saves any elapsed time) | Consistency and training maturity would be overstated. Must be resolved before any rating engine |
| D2 | **Zero-minute personal record** — "Longest time" accepts any duration above 0 seconds and displays whole minutes | Records feeding capability evidence must be valid efforts. Must be resolved before any rating engine |
| D3 | An approved Athlete Evolution methodology (dimensions, evidence rules, thresholds, confidence) | **Not authorised**; nothing here defines it |
| D4 | Definition of a "comparable effort" (cycling) and of a valid strength log | Needed for every "since baseline" figure |
| D5 | Stored history that does not exist today: body-weight history, VO₂ max, evaluation history / highest achieved | Schema change — needs an impact assessment |
| D6 | Checkpoints card and current Progress sections | Decide what is kept, moved or retired |
| D7 | Brand Book v0.2 tokens; the six themes are prototype tokens, not validated production themes | Theme support must be validated |
| D8 | Naming set (Initiate … Apex) and G0–G5 numbering are provisional | Owner approval |

D1 and D2 are recorded as dependencies only. Production was not changed.

## 8. Risks

| Risk | Mitigation |
|---|---|
| The page looks more certain than the evidence | Confidence on every row; "Establishing your baseline"; no number without a named source |
| Reads as a game level | No bars, points or badges; stage changes are rare and explained |
| Athletes take the stage as a scientific classification | Describe it as a Cyclift milestone system; reference context is optional and labelled |
| Demotion feels punishing | Highest achieved is permanent; current evaluation is separate |
| Scroll transition stutters or duplicates the object | Single-view approach; prove it with a flat placeholder before 3-D |
| Battery and heat | Still image by default off-screen, in Low Power and under thermal pressure; cannot be judged on a simulator |
| Small screens and large text | Hero shrinks before labels truncate; verified per size class in UI Lab |
| Light themes weaken a "black hole" | Shown in Arctic and Sandstone; needs review on a real display |
| The design promises data the app does not hold | Each element maps to the audit's "available today / later" list before UI Lab scope is set |

## 9. Acceptance criteria (for a future UI Lab prototype — not yet authorised)

1. `p` depends only on scroll offset; stopping the scroll stops the transition; reversing the scroll reverses it.
2. At no scroll position are two singularities visible (checked frame by frame in a recording).
3. In the collapsed state the header shows the symbol and "Progress" only; no stage labels.
4. The header never overlaps content or the status area on standard and small iPhones.
5. At the largest accessibility text size, generation, stage name and profile are fully readable when expanded, and
   nothing is truncated in sections B–F.
6. With Reduce Motion on, there is no size or position animation — only a crossfade between two states.
7. With Low Power Mode on, the singularity does not animate.
8. All six themes pass the contrast checks used for Home and Plan; High Contrast uses line and shape only.
9. An athlete with no supportable stage sees "Establishing your baseline" and no generation anywhere on the page.
10. Every figure on screen states whether it is recorded, entered, calculated or estimated; volume and capability are in
    separate, titled blocks.
11. Every interactive element is at least 44 pt and has an accessibility label.
12. VoiceOver reads the hero as one element and skips the header symbol.
13. Sample data is labelled on every screen while the prototype uses it.
14. Frame rate and energy are measured on a physical device before any claim about them is made.

## 10. Open questions for the owner

1. Is the collapsed symbol tappable (scroll back to top) or purely decorative? Proposed: decorative.
2. Next evolution: show counts on the landing page as drawn, or words only?
3. Hybrid development detail screen was not drawn in this round (cycling and strength were requested). Draw it next?
4. May the stage be shown as Provisional from a single discipline (as in the no-power-meter example)?

## 11. Limits

Drawings, not software. No timing, smoothness, battery, accessibility or small-screen behaviour has been verified.
The Progress screenshots mentioned in the original brief were not received.


---

# Part B — Progress v2.2: open-surface design

Design only; static drawings; illustrative sample data, identical in both variants. Nothing built or run.
**Not received:** the new WHOOP screenshots did not arrive with the message (text only). Part B follows the qualities
the brief lists (negative space, large values, full-width visuals, few colours, calm rhythm), not the images.

## B1. Images (`design-v22/`)

| File | Shows |
|---|---|
| `PF1_landing_variant_A_and_B.png` | Full-length landing page, Variant A and Variant B, Obsidian and Arctic |
| `PF2_expanded_collapsed_and_small_iphone.png` | Expanded and collapsed singularity on standard and small iPhone; small-iPhone page at full length (A and B) |
| `PF3_detail_screens_variant_A.png` | Hybrid, Endurance, Strength development — Variant A, Obsidian and Arctic |
| `PF4_detail_screens_variant_B.png` | The same three screens — Variant B |
| `PF5_drilldowns_and_discipline_adaptation.png` | Exercise detail, Athlete Evolution details, endurance-only and strength-only landing pages |
| `PF6_remaining_four_themes.png` | Ocean, Forest, Sandstone, High Contrast — both variants |

## B2. The two treatments

| | A — Open Editorial | B — Refined Technical |
|---|---|---|
| Surface | Page background only; no lines between metrics | Page background; a hairline between metrics; a faint full-width band behind section titles |
| Key value | 42 pt | 32 pt |
| Status | Inside the sentence under the value | Right-aligned beside the metric name |
| Charts | Line and end values only | Light grid, axis values, every point labelled, "no training" period shaded |
| Extra figures | None | A three-figure line under the endurance chart (baseline · recent repeatable · best verified) |

Neither variant has a card around any metric.

## B3. Landing page

A Singularity (unchanged) → B **Your development** → C Performance trends (one entry) → D Next evolution (name and
one sentence) → E Evolution timeline (one line with the stage transitions) → F Athlete Evolution details and
Records & history (two quiet rows).

Your development, for a Hybrid athlete — five sections, each with a different kind of picture because each shows a
different kind of quantity:

| Section | Headline | Picture | What every mark means |
|---|---|---|---|
| Endurance | 221 W, 20-minute power | Trend line on a true time axis with a dashed baseline | Each point is one comparable effort; the dashed line is the baseline value |
| Strength | 104 kg, squat estimated 1RM | Baseline-to-now comparison of three lifts on one kilogram scale | Hollow dot = baseline, filled dot = now; all in kg |
| Training consistency | 12 of 14 weeks | Weekly timeline, one mark per session | Filled square = endurance session, outlined square = strength session, dashes = no training recorded |
| Intensity distribution | 71 % of heart-rate time in zones 1–2 | One horizontal bar divided by zone | Segment length = share of recorded heart-rate time |
| Hybrid development | "Both progressing" (status, no number) | Two separate small trends on the same dates | Each keeps its own unit; nothing is merged |

Single-discipline athletes get only their own sections (PF5): the endurance-only example shows endurance, consistency,
intensity and a one-sentence "not enough comparable rides" state; the strength-only example shows strength, bodyweight
progression, consistency and muscle-group coverage. Insufficient evidence is a sentence, never an empty chart.

Controls: the three discipline names are plain text tabs (shown only when the athlete has more than one view); one
period control per screen ("Since baseline" on the landing page, "12 weeks ⌄" on detail screens). Each metric section is
tappable as a whole; there is no button or chevron beside it.

## B4. Detail screens

- **Hybrid development** — Endurance (trend + two lines), Strength (four-lift comparison + pull-up line), training
  maturity (weekly timeline), changes since the previous evaluation (three lines), then "More".
- **Endurance development** — Performance (wide 20-minute power trend; longest steady ride as a then/now pair) ·
  Training distribution (zone bar; riding time per week) · Supporting context (three plain lines) · More.
- **Strength development** — Progression (squat: estimated 1RM line with recorded top sets as separate marks) ·
  All lifts (baseline-to-now comparison; bodyweight pull-up in reps) · Coverage (muscle groups; movement patterns as
  one line) · More.

## B5. Removed, preserved, relocated

**Removed (chrome):** every rounded card and border around metrics; filter pills for range (five per screen) and for
discipline; status pills; a chevron on every row; repeated tags ("Capability", "Exposure — not capability",
"Supporting evidence") on each block; per-row miniature charts; most explanatory footnotes.

**Preserved:** the singularity and its collapse; sections A–F; Hybrid / Endurance / Strength adapting to the profile;
every metric and comparison of v2.1; estimate versus recorded; exposure kept apart from capability (now by section
title: "Training distribution", "Training maturity", "Supporting context"); "Not enough evidence" states; sample-data
label; current evaluation versus highest achieved.

**Relocated (nothing deleted):**

| v2.1 location | v2.2 location |
|---|---|
| Recorded bests list on Strength | Strength › More › Recorded bests |
| Sets per week, sessions, quick-log count on Strength | Strength › More › Training volume / Sessions |
| Session-by-session sets and the Epley explanation | Exercise detail (tap a lift) |
| Movement-pattern grid | One line under Coverage; grid in its drill-down |
| List of efforts used / left out; long-term trend; "why it says Improving" | Endurance › More › All efforts and long-term trend (metric detail) |
| "Best verified vs recent repeatable" bars | One line (A) or three-figure line (B) under the trend |
| Verified milestones list on Hybrid | Hybrid › More › Verified milestones |
| Evidence ladder and "what is missing" | Athlete Evolution details |
| Range choices 4 / 8 / 12 / 16 / All | Inside the single period control |
| "Next evolution" counts row | One sentence |

## B6. Measured comparison with v2.1 (from the drawing files, standard width)

| | v2.1 landing | v2.2 A landing | v2.2 B landing | v2.1 Strength | v2.2 A Strength |
|---|---|---|---|---|---|
| Bordered containers | 5 or more | 0 | 0 | 5 or more | 0 |
| Pills and chips | 10 | 0 | 0 | 12 | 0 |
| Smallest text | 10 pt | 11 pt in new content (hero label unchanged at 10 pt) | same | 9.5 pt | 11 pt |
| Words per 1,000 pt of height | about 136 | about 94 | about 113 | about 184 | about 114 |
| Page height | about 1,200 pt | about 2,630 pt | about 2,790 pt | about 1,510 pt | about 1,790 pt |

Counts come from an automated pass over the drawings and are approximate. **The landing page is now more than twice as
long** (about three screens instead of one and a half). That is the cost of five full-width sections; see B8.

Hierarchy: v2.1 gave every row the same weight inside equal cards. v2.2 has three levels only — section title (small
capitals), key value (largest text on the page after the stage), supporting sentence and picture.

## B7. Accessibility and High Contrast

- No information depends on colour alone: endurance marks are filled, strength marks are outlined; baseline is hollow,
  now is filled; status is written as a word.
- High Contrast: line-and-shape singularity; zone segments solid with gaps and written percentages instead of tints;
  secondary text at full strength; separators drawn at full contrast in Variant B.
- Text was not reduced to make space; new content is 11 pt or larger and key values are 32–42 pt. At large Dynamic Type
  sizes the key value and its unit wrap onto their own lines and charts keep their full width; three-figure lines (B)
  stack vertically.
- A whole metric section is one touch target and one VoiceOver element ("Endurance, 20-minute power, 221 watts,
  improving, up from 208 at baseline; opens Endurance development"). Charts need a spoken summary, not point-by-point
  reading.
- With chevrons removed from metric sections, tappability relies on the pressed state and the VoiceOver hint; this must
  be checked with real users in the UI Lab.
- None of this has been tested; the small-iPhone drawings show fit at default text size only.

## B8. Open points

1. **Length.** If three screens is too long, the cleanest reduction is four sections: fold "Hybrid development" into
   the sentence under the stage name, or move "Intensity distribution" to Endurance only.
2. Choice of A or B, or A for the landing page with B for detail screens.
3. Is a status word acceptable on "Hybrid development" with no number? (No number exists that would be honest.)
4. Variation bands and minimum evidence behind each status word are still undefined (v2.1 dependency E3).
