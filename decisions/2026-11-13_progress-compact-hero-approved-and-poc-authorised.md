# Decision record — Progress compact hero approved; Progress UI Lab proof of concept authorised

Date: 13 Nov 2026 (owner message 21:17 Dubai) · Recorded by Claude · Level 2 (decision record)

## 1. Approved

The compact hero documented in `product/progress/PROGRESS_V23_COMPACT_HERO.md` v0.1 (commit `0f38f06`) is the
**approved visual baseline for Progress**. This is design approval only — not production approval and not approval of
any scoring engine.

Reference measurements (not hard-coded universal dimensions):

| | Standard iPhone | Small iPhone |
|---|---|---|
| Black hole including lensing ring | about 137 pt | about 115 pt |
| Accretion-disc width | about 180 pt | — |
| Hero including Evolution Track | about 327 pt | about 300 pt |
| Evolution Track at default text size | about 70 pt | about 66 pt |

The track and its text are not to be reduced further to reach the earlier numerical targets.

## 2. Final refinements (owner)

1. A very subtle, localised atmospheric halo is restored around the singularity in Obsidian, without changing layout
   or measured height and without overpowering the object. Static illustration:
   `product/progress/design-v23-compact/PH5_subtle_halo_before_after.png` (hero height measured unchanged: 327 / 300 pt).
2. The Evolution Track may grow vertically for Dynamic Type, provisional, G5 and returning-athlete states. Essential
   generation information is never truncated and accessible text sizes are never reduced to hold a fixed height.
3. Black hole, generation and stage name stay visually unified. The "Athlete Evolution" label is not reintroduced and
   no decorative container is added.
4. The track stays directly beneath the identity, as one whole-track navigation action, with previous / current / next.
5. Scroll-linked collapse into the header is kept: no blank spacer, no duplicate singularity, no floating track, no
   content jump.

## 3. Authorised next step — isolated Progress UI Lab proof of concept

Limited to: the compact hero and its layout · the singularity-to-header scroll transformation · the Evolution Track and
its special states · a **flat/static placeholder** before any GPU rendering · Obsidian and Arctic · standard and small
iPhone simulators · Dynamic Type, Reduce Motion and safe-area verification.

Conditions: no 3-D shader first; establish scrolling, layout, hit testing, navigation and accessibility. The approved
v2.3 analytical sections remain the design reference and are not redesigned. The work is independent of the Plan and
Home presenter diagnostics (separate branch, test identifiers and output artifacts).

Not authorised: production changes, scoring algorithms, database migrations, firmware, TestFlight, changes to Home,
Plan or Coach, the real-time black-hole renderer, full Progress implementation.

Required evidence: compilation and warnings · screenshots at expanded, intermediate and collapsed · measured hero
dimensions and first-metric visibility · scroll reversibility and absence of content jumps · track tap/navigation ·
accessibility and Dynamic Type · Reduce Motion · known defects and limitations. Simulator results are not evidence of
battery, GPU or thermal behaviour. Stop after the proof of concept for approval.

## 4. Where the work lives

Branch `proto/ui-lab-progress` (from the common UI Lab base `6454a13`) · workflow "UI Lab Progress proof of concept" ·
test class `ProgressInteractionTests` · output branch `proto/ui-lab-progress-out`. Status is tracked in
`ui-lab/progress/PROGRESS_POC_STATUS.md`.
