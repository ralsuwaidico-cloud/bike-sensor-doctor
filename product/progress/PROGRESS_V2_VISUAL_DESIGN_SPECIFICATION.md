# Progress v2.0 — visual design specification (collapsing singularity and full landing page)

Status: **Current Draft — awaiting owner approval** · Version 0.2 · 13 Nov 2026 · Level 3
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
