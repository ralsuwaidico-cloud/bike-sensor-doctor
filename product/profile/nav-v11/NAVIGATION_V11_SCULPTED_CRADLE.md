# Navigation v1.1 — Sculpted Train Cradle

**Status:** Current Draft — Pending Owner Review · **Version:** 0.1 · 14 Nov 2026
**Scope:** design correction to sheet P1 of *Profile and Navigation v1.0* and its related navigation states. Static drawings only. **ILLUSTRATIVE DESIGN — NOT IMPLEMENTED.**
**Does not supersede** `PROFILE_AND_NAVIGATION_V1_DESIGN.md`; that document and its sheets are unchanged.

## Design authority
The owner's hand-drawn reference is the design authority for this correction. **The drawing did not reach the design session** — these sheets follow the owner's written description only and must be checked against the sketch before any approval.

## What the correction is
One connected silhouette: the capsule holding Home, Plan and Progress ends, at its right, in a smooth concave cradle that holds the circular Train button. The button stays a distinct circle with its own boundary. There is no label in the gap, no fourth conventional tab, no rectangular connector and no separate overlapping pill.

## Three measured depths (from the drawing geometry, standard iPhone 402 pt wide)
| | Shallow | Medium | Deep |
|---|---|---|---|
| Ball inside the cradle | 8 % | 33 % | 50 % |
| Overall height of the shape | 72 pt | 92 pt | 98 pt |
| Arm thickness | none | 8 pt, rounded tips | 8 pt, rounded tips |
| Scrolling content must end above (from bottom) | 118 pt | 128 pt | 131 pt |

Common to all three: capsule 56 pt high; ball 72 pt; 5 pt gap all round; three tab touch areas 94 × 48 pt (78 pt wide on the small iPhone); Train touch area is the 72 pt circle only — the arms are not touchable; nearest tab edge to the ball 15 pt; ball 34 pt above the bottom edge on the standard iPhone, 16 pt on the small iPhone.

## Suggested depth: Medium (owner decision)
- **Elegance:** reads as one instrument; the ball looks held, not caged.
- **Touch separation:** identical to the others (15 pt) — depth does not change the hit areas.
- **Balance:** 20 pt taller than shallow, 6 pt lower than deep; tips stay clear of the state badge.
- **Accessibility:** the ring in the gap has a visible home; in High Contrast the outline remains legible without the heaviness of the deep version.
Shallow is calmest but closest to "a pill beside a ball". Deep gives the strongest embrace but encloses the ball and crowds the badge.

## States
The cradle never changes size or position. State is shown by the ring in the 5 pt gap (segmented = strength, solid = endurance, split = paused, three-quarter = completion pending), a badge, and the elapsed time inside the ball. Endurance/cycling minimised is drawn as intent only — the Training Hub v1.4 cycling safety gate still blocks it.

## Compared with P1 of v1.0
**Changed:** one silhouette instead of pill + separate circle; the "Train" word and time label between them removed; elapsed time moves inside the ball; state ring sits in the cradle gap; soft shadow under the shape.
**Untouched:** Home, Plan, Progress, then Train at the far right; no Profile tab; Profile from the Home avatar; ball size and position; state language; Training Hub v1.4 behaviour and cycling safety restrictions; Profile's information architecture; no emblem approved (the symbol drawn is a placeholder).

## Open points for the owner
1. Check against the hand drawing (not received).
2. Depth: shallow, medium or deep.
3. Elapsed time inside the ball (10 pt digits) — acceptable, or state by ring and badge only.
4. Tab words stop growing at 17 pt at the largest text sizes so the shape stays fixed.
5. Arabic: mirrored layout (ball at far left) remains the owner's earlier open decision.
6. In the phone frames the placeholder Home cards run slightly under the cradle arms; real content would end above the stated clearance line.

## Not done
No production code, UI Lab prototype, build, navigation migration, onboarding or database change, or TestFlight. No emblem approved. No pending Training Hub technical decision resolved. Nothing was run on a simulator or device; hit areas are drawn, not measured in an app.

## Sheets
`sheets/N1a_cradle_three_depths.png` · `sheets/N1b_measured_studies_and_comparison.png` · `sheets/N2_medium_cradle_six_themes.png` · `sheets/N3_states_and_layouts.png`
