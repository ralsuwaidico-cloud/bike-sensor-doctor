# Cyclift UI Lab — isolated prototype (currently Home v2.2)

An isolated SwiftUI prototype of the Cyclift interface library and the Home v2 screen.

**This is not the Cyclift app.** It shares no code with it, uses a different bundle id (`lab.cyclift.uilab`),
is never signed or uploaded, and shows synthetic sample data only. This branch (`proto/ui-lab`) has no history in
common with the app's branches and contains only its own build workflow.

- `CycliftUILab/DesignSystem` — six themes and tokens
- `CycliftUILab/Components` — reusable components (data in, callbacks out)
- `CycliftUILab/Mock` — sample data
- `CycliftUILab/Screens` — Home v2 prototype, Lab screen, component gallery
- `tools/` — contrast check, build and screenshot script
- `docs/` — review documents and tracker

## Branch proto/ui-lab-progress — Progress proof of concept (13 Nov 2026)

Scope authorised by the owner: compact hero and layout, singularity-to-header scroll transformation, Evolution Track and
its states, **flat static placeholder** instead of any GPU rendering, Obsidian and Arctic, standard and small simulators,
Dynamic Type, Reduce Motion and safe-area checks. Sample data only; no scoring engine; analytical sections are space
placeholders for the approved v2.3 design. Independent of `proto/ui-lab` (sheet diagnostics) and `proto/ui-lab-plan`:
own workflow ("UI Lab Progress proof of concept"), own test class (`ProgressInteractionTests`), own output branch
(`proto/ui-lab-progress-out`). Launch options: `LAB_SCREEN=progress`, `LAB_PROGRESS=g0|g2|g2prov|g5|first|returning`,
`LAB_PSCROLL=expanded|mid|collapsed`, `LAB_REDUCE_MOTION=1` (prototype override), `LAB_PROBE=1` (test read-out).
