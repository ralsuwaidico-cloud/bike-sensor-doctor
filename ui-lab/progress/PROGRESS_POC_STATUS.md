# Progress UI Lab proof of concept — status

Status: **Current Draft** · Version 0.1 · 13 Nov 2026 · Level 3
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
