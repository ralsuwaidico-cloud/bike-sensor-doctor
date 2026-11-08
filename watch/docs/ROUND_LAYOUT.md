# Round-screen layout system (W1) — rules, components, checks

Engine: `firmware/src/domain/round_layout.hpp` (pure, host-tested). Geometry: usable radius 114 px (120 − 6 px bezel
inset); the usable chord at height *y* is `2·√(114² − (y−120)²)`; every element is placed in a band whose corners are
inside that circle. Two 72-pt buttons fit side by side only from y ≈ 150 down to 204, so the control row is fixed at
y = 160…204 on every live screen.

Text: measured with a `TextMeasurer` (LVGL's `lv_txt_get_size` on the watch; a conservative per-glyph table on the
host — the host is the stricter of the two). Fitting steps the font down **only to the component's minimum** and adds
lines up to the component's maximum; otherwise the engine reports *does not fit* and the screen must page, open a
detail screen or show an explicit **More** control. Minimums: lead numbers 20 px · complication values 12 · body 13 ·
labels/units 11 · button labels 12. A word wider than its box never fits (no mid-word cut). An ellipsis is allowed
only on non-critical text **and** only where a More control or the containing list row exists; critical text (live
cue, exercise name header, controls) is never truncated — the coach protocol therefore limits the live cue to 44
characters at a word boundary (`CoachMessage::wristInstruction()`), the rest goes behind *Why?*.

Components (`Builder`): `text` (centred band), `textIn` (box), `textFirstFit` (drop the least important part),
`moreText` (fit or ellipsis + invisible More touch target), `metric` (label + number + unit, number ≥ 20 px),
`button` (≥ 44 × 44), `row` (list row, 44 tall, tappable), `arc`, `dot`, `panel`.

Checks (`layout_checks.hpp`, run by `test/host/gallery` on 17 screens × 6 appearances × 4 text variants = 408 scenes):
circle overflow · text/text overlap · button label inside its button · touch size ≥ 44 · a live screen has a critical
control · no critical truncation, no ellipsis without More · minimum font per role · contrast ≥ 4.5:1 (≥ 3:1 for
≥ 24 px bold) against the actual surface · grading colours ≥ 3:1 on the canvas and identical across appearances.
**Result 8 Nov: 408 scenes, 0 findings** (`gallery-out/REPORT.md`, SVG evidence per scene). A screen is not complete
until this stays at zero on the device-measured fonts too (W1 device pass).
