# Progress v2.3 — compact hero (proportional refinement)

Status: **Current Draft — awaiting owner approval** · Version 0.1 · 13 Nov 2026 · Level 3
**Design only.** Static drawings, illustrative sample data. Nothing built, run or tested; no production, UI Lab,
renderer, scoring, database, firmware or TestFlight change.
Refines `PROGRESS_V23_VISUAL_REFINEMENT.md` v0.1 (commit `92f6260`), which is left unchanged. Only the hero and the
Evolution Track proportions differ; charts, data, wording, sections, states and themes are as in v2.3.

## 1. Images (`design-v23-compact/`)

| File | Shows |
|---|---|
| `PH1_first_screen_before_after.png` | First screen, v2.3 beside compact hero, same scale — standard and small, Obsidian and Arctic |
| `PH2_scroll_states.png` | Expanded, intermediate, collapsed — standard (Obsidian) and small (Arctic) |
| `PH3_track_states_and_themes.png` | Track at G0, provisional, G5, insufficient evidence, returning; pressed state; Ocean, Forest, Sandstone, High Contrast |
| `PH4_full_length_before_after.png` | Whole landing page, before and after |

## 2. Measurements (from the drawings, in points)

"Black hole" is measured two ways because the brief's figure fits the bright lensed body, not the dark centre alone.

| | v2.3 standard | Compact standard | Target | v2.3 small | Compact small | Target |
|---|---|---|---|---|---|---|
| Dark centre (shadow) diameter | 116 | 86 | — | 100 | 72 | — |
| Black hole incl. lensing ring | about 185 | **about 137** | 125–145 | about 159 | **about 115** | 105–120 |
| Accretion disc width (G2) | about 298 | **about 180** | about 190 max | about 257 | about 150 | — |
| Glow radius | about 267 | about 76 | — | about 230 | about 66 | — |
| Identity block (hole to evidence line) | 362 | 257 | — | 306 | 233 | — |
| Evolution Track height | 119 | **70** | 55–65 | 114 | 66 | — |
| **Hero total, incl. track, excl. status bar and title** | 481 | **327** | 285–325 | 420 | 300 | — |
| Reduction of hero total | | **32 %** | 30–35 % | | 29 % | |
| Endurance key value, top edge from top of screen | 743 | **577** | on first screen | 654 | 522 | where feasible |
| Whole page height | 2,286 | 2,119 | — | — | 2,075 | — |

Disc width grows slightly with generation (about 168 pt at G0 to about 198 pt at G5), as before.
Two figures sit just outside the hypotheses: hero total 327 against 325, and track 70 against 65. See §5.

First screen, standard iPhone: header, compact singularity, G2 and stage, full Evolution Track, "Your development",
the hybrid sentence, **Endurance 221 W and its caption**, and about three quarters of the trend above the dock.
Small iPhone: full hero and track, the hybrid sentence and **the 221 W value** above the dock; the trend begins under
the dock.

## 3. What changed

- Singularity drawn smaller with the same construction: shadow, photon ring, lensed halo, tilted disc in front and
  behind, theme lighting. Streak count is unchanged, so detail density is higher, not lower.
- The wide ambient glow is cut to a tight halo; the dark gradient panel behind the hero is gone.
- Identity sits **under** the singularity instead of over its lower half, with tighter line spacing.
- The small "ATHLETE EVOLUTION" label above the generation was removed (it was 10 pt and repeated the page's subject).
- Confidence and date are one line, now 12 pt (was 11 pt).
- Track: the centre label is "G2" and "YOU ARE HERE"; the stage name under the centre marker was dropped because it
  duplicated "THE ASCENDANT" printed directly above. Side markers keep their names.

## 4. Evolution Track — legibility and access

| Item | Value |
|---|---|
| Height | 70 pt standard, 66 pt small — one touch target, full width, above the 44 pt minimum |
| Current marker | 26 pt across (ring), 16 pt solid centre |
| Previous / next markers | 10 pt solid dot / 16 pt outline — unchanged from v2.3 |
| Text | "G2" 18 pt; side generations 13.5 pt; stage names 11.5 pt; "YOU ARE HERE" 11 pt, letter-spaced, accent colour. No track text is below 11 pt on either phone |
| Marker sizes versus v2.3 | Within 1 pt; the saving came from removing one text line and spacing, not from shrinking markers |
| States | All v2.3 states redrawn at this size (PH3). Provisional adds a third line, "PROVISIONAL", and is 14 pt taller |
| High Contrast | Small solid, large solid in ring, empty outline; solid and dotted line; white text |

Not tested: tap accuracy, VoiceOver, large text.

## 5. Trade-offs and remaining concerns

1. **Less spectacle.** The singularity now occupies about 40 % of the screen width instead of about 75 %. It still
   reads as a three-dimensional object in the drawing, but the real judgement needs the eventual 3-D render at this
   size on a phone.
2. **Glow.** Cutting the glow removes the "atmosphere" of v2.3. A middle setting is possible at no cost in height.
3. **Hero 327 pt and track 70 pt** are 2 pt and 5 pt over the stated hypotheses. Reaching them would mean track text
   under 11 pt or tighter identity spacing; I stopped where text stayed at accessible sizes.
4. **"ATHLETE EVOLUTION" label removed** — say if you want it back (about 14 pt).
5. **Centre stage name removed from the track** — on Athlete Evolution details the full names remain.
6. **G5 and returning states** have long labels that sit close to their neighbours; they fit at default text size and
   will need the stacked layout sooner at large text sizes.
7. **Small iPhone:** the trend line is not visible on the first screen; only the value is.
8. **Collapse:** with a smaller hero the scroll distance of the transition is shorter (roughly 250 pt instead of 360),
   so the shrink will feel quicker. Behaviour rules are unchanged; feel can only be judged in a prototype.
9. Large-text layouts are still described only, not drawn.
