# Progress v2.3 — final visual refinement: Evolution Track and reduced landing page

Status: **Current Draft — awaiting owner visual review** · Version 0.1 · 13 Nov 2026 · Level 3
**Design only.** Static drawings with illustrative sample data and illustrative wording. Nothing was built, run or
tested. No production code, UI Lab, renderer, rating engine, database, migration, firmware or TestFlight change.

Source references (not modified by this document):
`PROGRESS_V2_VISUAL_DESIGN_SPECIFICATION.md` v0.3 (commit `80da51e`) — scroll interaction and rendering (§3–4), v2.2 Part B ·
`PROGRESS_V21_ARCHITECTURE_AND_AUDIT.md` v0.1 and `PROGRESS_V21_METRIC_REGISTRY.md` v0.1 (commit `78c6567`) ·
`PROGRESS_V2_PHASE0_AUDIT.md`, `PROGRESS_V2_RESEARCH_AND_FRAMEWORK.md` v0.1 (commit `453f1ef`).
Where this document differs from v2.2 Part B on page layout, this is the later proposal; the earlier text is left as written.

Owner decisions recorded (13 Nov): Variant A — Open Editorial is the visual direction; Variant B features may be used
selectively on detail screens; no further variants.

## 1. Images (`design-v23/`)

| File | Shows | Deliverable |
|---|---|---|
| `PG1_landing_obsidian_arctic_standard_small.png` | Full-length landing page, Obsidian and Arctic, standard and small iPhone | 1, 2, 6 |
| `PG2_evolution_track_states.png` | Track at G0, G2, G2 provisional, G5, insufficient evidence, returning athlete, pressed state | 3, 4 |
| `PG3_scroll_states_with_track.png` | Expanded, intermediate, collapsed — standard and small | 5, 6 |
| `PG4_six_themes.png` | Landing page in all six themes | 7 |
| `PG5_detail_screens.png` | Athlete Evolution details, Endurance, Strength, Hybrid, Metric detail | 8 |
| `PG6_before_after_v22_v23.png` | v2.2 Variant A beside v2.3, same scale | 9 |

## 2. Landing page order

A Athlete Singularity → **B Evolution Track** → C Your development (up to four) → **D Next evolution** →
E Performance analysis (one entry) → F Evolution timeline (one line) → G Records & history (one quiet row).

## 3. Evolution Track

A sequence of stages under the athlete's identity. It answers: where was I, where am I, what comes next.

| Marker | Drawing | Meaning |
|---|---|---|
| Previous | Small solid dot | A stage already achieved |
| Current | Large solid dot inside a ring, bold label, "YOU ARE HERE" | The current supported evaluation |
| Next | Empty outlined circle | The next stage — not achieved |
| Line, previous → current | Thin solid | Achieved |
| Line, current → next | Thin dotted, **never filled** | Not a measure of progress |

It is not a progress bar: no fill, no percentage, no forecast. The three positions are fixed; nothing moves between them.
No background, no card. The whole track is one touch target that opens Athlete Evolution details; there is no separate
button. Pressed state: a faint full-width tint (PG2, last frame).

VoiceOver (one element): "Evolution track. Current generation G2, The Ascendant, evidence-supported. Highest achieved
G2. Previous G1, The Builder. Next G3, The Proven. Opens Athlete Evolution details."

States:

| State | What is shown |
|---|---|
| G0 | Current and next only. The left position is empty — no earlier stage is invented |
| G1–G4 | Previous, current, next |
| G5 | G4 and G5; the right position carries only the words "Highest generation · development continues". No G6 |
| Provisional | Current marker is hollow with a dashed ring; label "YOU ARE HERE · PROVISIONAL"; no solid fill, no glow |
| Insufficient evidence | One square baseline marker, "Baseline · being established"; no generation shown or highlighted; headline "Establishing your baseline" |
| Returning athlete | Headline "Not currently evaluated". The highest achieved stage sits in the centre in a neutral colour, labelled "HIGHEST ACHIEVED" — not "You are here", and no accent colour. Nothing is demoted |

## 4. Scrolling

Unchanged rules from the specification §3–4 (one scroll-driven value; one singularity; Reduce Motion crossfade; still
image in Low Power). Additions:

- The Evolution Track is ordinary page content. It scrolls away with the page and is never pinned or floated.
- Intermediate: the singularity is smaller, the stage text fades, the track moves up with the content.
- Collapsed: small symbol, "Progress", and a small text "· G2". No stage title, no track, no second singularity.
  When there is no current evaluation the header shows no generation text.
- The page must not jump: the content's scroll position is preserved as the hero shrinks; the header sits inside the
  safe area.

## 5. Your development — four sections (Hybrid athlete)

| | Headline | Picture |
|---|---|---|
| Endurance development | 221 W · cycling, 20-minute power · 208 W at baseline | Trend of comparable efforts with a dashed baseline. **The line is broken across the training pause**; only the first and last points are labelled |
| Strength development | 104 kg · squat, estimated 1RM · 92 kg at baseline | Two rows on one kilogram scale: estimated 1RM, and the recorded top set. Caption: "One lift, not your whole strength." |
| Training consistency | 12 of 14 weeks · "Participation, not performance" | Weekly timeline, one mark per session, the pause shown as a pause |
| Supporting (chosen by relevance) | 71 % of heart-rate time in zones 1–2 | One bar divided by zone |

Hybrid development is now one sentence at the top of the section: "Developing Hybrid — both disciplines show measurable
progress." It appears only when both disciplines have supporting evidence. The discipline tabs were removed from the
landing page; the three views are reached through Performance analysis.

Fewer than four is correct when evidence is missing: the supporting section is omitted, and a discipline without
evidence shows one sentence (PG2, first-time and returning frames). The supporting metric is selected from the Metric
Registry by relevance and evidence quality; the selection rule itself is not yet written (dependency 6).

## 6. Next evolution

Placed directly after the four metrics. Large stage name ("G3 · The Proven"), one sentence of evidence still needed, and
a small line stating that the wording is illustrative. No percentage, no date, no workout creation. Tapping opens the
requirements in Athlete Evolution details. Scheduling stays in Plan.

## 7. Detail screens (PG5)

Open editorial base. Grid lines and axis values (Variant B) are used only on the main chart of Endurance, Strength and
Metric detail.

| Screen | Order of content |
|---|---|
| Athlete Evolution details | Full G0–G5 track · current evaluation and highest achieved · stage evidence · verified achievements · missing evidence ("does not lower your stage") · next generation · timeline |
| Endurance development | Performance · aerobic development · training distribution · long-term comparison · measurement (source, confidence) · more |
| Strength development | Progression (estimate and recorded marks) · all lifts · personal records · coverage (muscle groups, movement patterns) · training exposure ("not capability") · more |
| Hybrid development | One sentence (no combination, no required balance) · endurance · strength · since the previous evaluation · links to both |
| Metric detail | Trend · baseline and recent · how it is measured (what, source, included, left out, confidence, limits) · efforts |

## 8. Before and after (measured from the drawings, standard width, approximate)

| | v2.2 Variant A | v2.3 |
|---|---|---|
| Metric sections on the landing page | 5 | 4 |
| Charts on the landing page | 9 | 5 |
| Discipline tabs on the landing page | 1 row | none |
| Page height | about 2,630 pt | about 2,290 pt |
| Where "Next evolution" starts | about 2,150 pt down | about 1,730 pt down |
| Chevrons | 3 | 2 |
| Smallest text in new content | 11 pt | 11 pt |

The page is about 13 % shorter, not dramatically shorter: one metric and four charts were removed, while the Evolution
Track and a larger Next evolution were added. It is still roughly two and a half screens. A shorter page would need
three metrics or smaller charts; neither was done because they were not asked for.

## 9. Removed, simplified, retained

**Removed from the landing page:** the Hybrid development section and its two repeated trends; discipline tabs; the
"Athlete Evolution details" row (the track now opens it); labels on every chart point; the three-lift comparison (now
on Strength).

**Simplified:** strength shows one lift with estimate and recorded value; Next evolution is a name and one sentence;
trend lines no longer bridge the pause; consistency states plainly that it is participation.

**Retained:** singularity and collapse; open editorial surface; full-width charts with a different picture for each
kind of quantity; Endurance / Strength / Hybrid; every v2.1 and v2.2 metric and drill-down (moved, not deleted);
estimate versus recorded; "not enough evidence" as a sentence; current evaluation versus highest achieved; six themes;
the dock.

## 10. Accessibility, Dynamic Type, Reduce Motion

- **High Contrast:** the three track markers differ by size and form (small solid, large solid in a ring, empty
  outline), by line style (solid, dotted) and by text; no meaning rests on colour.
- **Static fallback:** the track is a still drawing already; with the singularity static, all information is unchanged.
- **Dynamic Type:** track labels may wrap to two lines; at accessibility sizes the stage names drop below the
  generation labels and, if needed, the track stacks as three rows (previous / current / next) with the same markers.
  Key values wrap with their units; charts keep full width. Not drawn in this round.
- **Reduce Motion:** as approved — a crossfade between expanded and compact header; the track is unaffected.
- **Touch and focus:** the track and each metric section are single targets of at least 44 pt with a visible pressed
  and focus state.
- None of this has been tested.

## 11. Remaining dependencies

1. Valid-session rule (seconds-long rides counted as completed) — audit finding, unresolved.
2. Valid-record rule (zero-minute personal record) — audit finding, unresolved.
3. Approved generation criteria, thresholds, confidence rules and transition review — **not authorised, not defined**.
4. Rule for returning athletes and for missing data (documented in principle; no engine).
5. Per-metric comparison rule, minimum evidence and normal-variation band behind "Improving".
6. Rule for choosing the supporting metric and each discipline's headline measure.
7. Recognised training pauses: how a pause is detected or declared.
8. Sport model for a broader Endurance discipline — separate engineering workstream; no production rename authorised.
9. Storage for evaluation history and highest achieved.
10. Next-evolution wording generated from approved criteria.
11. Single-view singularity transition proven in a prototype before any 3-D work.
12. Theme tokens are prototype tokens; no palette or token migration is approved.

## 12. Acceptance criteria for this design

1. The track sits directly under the identity and above the metrics, outside the singularity, with no background.
2. No part of the track is filled, sized or positioned by a calculated amount.
3. G0 shows no earlier stage; G5 shows no later stage.
4. Without a supported evaluation no generation is marked current; a returning athlete's highest stage stays visible.
5. Provisional is labelled in words and drawn without solid fill.
6. The track is one accessible target; no extra button exists for the same action.
7. The track is not present in the collapsed header and is never pinned.
8. At most four metric sections; fewer when evidence is missing; no section exists only for symmetry.
9. No trend line crosses a period without observations.
10. No endurance and strength chart is repeated lower on the landing page.
11. Next evolution appears before Performance analysis, Timeline and Records, with no percentage or date.
12. Every example sentence that would come from a rating engine is marked illustrative.
13. All six themes use the same track geometry; High Contrast distinguishes the markers without colour.
14. Small-iPhone layout shows the identity and the full track on the first screen.

## 13. Limits

Drawings only. Large-text layouts were described, not drawn. The WHOOP screenshots referred to in earlier briefs were
never received. Heights and counts were measured from the drawing files and are approximate.
