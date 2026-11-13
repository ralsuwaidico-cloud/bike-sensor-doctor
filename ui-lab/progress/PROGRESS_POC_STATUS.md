# Progress UI Lab proof of concept — status

Status: **Current Draft** · Version 0.2 · 13 Nov 2026 · Level 3
Authorisation: `decisions/2026-11-13_progress-compact-hero-approved-and-poc-authorised.md`.

## 1. State of evidence

| Stage | State |
|---|---|
| Designed | Yes — approved baseline `0f38f06` |
| Implemented (prototype code written) | Yes — commit `3aa28d9` on `proto/ui-lab-progress` |
| Compiled | **Not yet known** — first run pending |
| Simulator-tested | **Not yet known** |
| Physical-device-tested | No |
| Released / user-accepted | No |

Nothing in this table may be upgraded without the run's output.

## 2. What was built (prototype only)

- `CycliftUILab/Screens/ProgressScreen.swift`: compact hero; one singularity view that follows its slot while the page
  scrolls, shrinks as a function of scroll position only, and stops in the header; Evolution Track as one button with
  six sample states (G0, G2, G2 provisional, G5, first-time, returning); a row layout at default text sizes and a
  stacked layout at accessibility sizes; Reduce Motion path with two states and no travelling or shrinking; a
  placeholder Athlete Evolution destination.
- The singularity is a **flat placeholder made of ordinary shapes**. No shader, no GPU rendering, no self-motion.
- The sections below the track are dashed placeholders that reserve the space of the approved v2.3 design.
- `UITests/ProgressInteractionTests.swift`: eight tests (layout and measurements; monotonic, reversible, jump-free
  transformation; whole-track navigation; single accessible element; special states; Dynamic Type; Reduce Motion;
  header hit testing and safe area).

## 3. Known before the first run

1. **Collapse distance is short.** Because the singularity moves with the content until it reaches the header, the
   whole transformation happens in roughly 100 pt of scrolling on a standard iPhone (not the ~250 pt estimated in the
   design note). To be judged from the screenshots and, properly, on a device.
2. Reduce Motion is exercised through a prototype switch that forces the same code path as the system setting; the
   system setting itself is not toggled by the tests.
3. The header title does not scale with Dynamic Type beyond the header's height (capped), like a system navigation bar.
4. At accessibility text sizes the track stacks vertically without connecting lines.
5. The dock remains visible over the placeholder details screen.
6. VoiceOver hints cannot be read by the automated tests; spoken output has not been listened to.
7. Frame rate, battery, GPU and thermal behaviour are **not** assessed and cannot be on a simulator.

## 4. First run — workflow 43472777501 (commit `3aa28d9`), 13 Nov 2026

Simulator results only (iPhone 17 and iPhone SE 3rd generation, iOS 26.5 simulators). Not device validation.
No changes were made after the run; corrections await the owner's review.

| | Result |
|---|---|
| Compiled | Yes. 7 warning lines in the build log, 0 in `ProgressScreen.swift` |
| Screens captured | 74 |
| Standard | 5 passed, 3 failed |
| Small | 6 passed, 2 failed |

Passed on both: expanded layout and measurements · scroll transformation monotonic, reversible, no content jump ·
whole-track navigation (centre, leading edge, trailing edge; scroll position kept) · six states · Dynamic Type.

Failed:

1. **Track is not one accessible element** (both simulators): "YOU ARE HERE" is exposed as separate text.
2. **Reduce Motion exposes two singularities at once** (both): the hero one and the header symbol are both present to
   accessibility. Whether both are ever visible together is not established by the test.
3. **Header hit testing** (standard only; passed on small): a tap on the header reached the track scrolled beneath it.

Measured against the approved baseline:

| | Approved | Standard measured | Small measured |
|---|---|---|---|
| Hero including track | 327 / 300 pt | 339.7 pt | 318.5 pt |
| Evolution Track | 70 / 66 pt | 79 pt | 80 pt |
| Collapse distance | — | about 99 pt | about 88 pt |
| Endurance key value above the dock | yes | yes, 122 pt clearance | yes, 12 pt clearance |

The standard simulator is 402 pt wide (iPhone 17), not the 393 pt of the drawings. At the largest accessibility text
size on the small phone the hero is about 999 pt tall and the track begins below the first screen.
Scroll steps recorded: singularity diameter falls evenly from 136 pt to 30 pt as the offset goes 0 → about 100 pt, and
returns to the same size and position when scrolled back.
