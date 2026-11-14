# Navigation v1.2 — Left-Mounted Train Ball and Sculpted Cradle

**Status:** Current Draft — design exploration, pending owner approval · **Version:** 0.1 · 15 Nov 2026
**Implementation status: NOT STARTED.** Designed only. Not implemented, compiled, simulator-tested or device-tested. **ILLUSTRATIVE DESIGN — NOT IMPLEMENTED.**
**Earlier records unchanged:** `../nav-v11/NAVIGATION_V11_SCULPTED_CRADLE.md`, `../PROFILE_AND_NAVIGATION_V1_DESIGN.md`, Decision D of 14 Nov and Training Hub v1.4 are not edited or superseded by this draft.

## 1. Objective and owner direction
Owner brief "Navigation v1.2" (15 Nov): Option A — the round Train control at the far **left**, with Home, Plan and Progress extending to its right in one capsule that ends in a sculpted concave cradle holding the ball. Medium cradle from v1.1 is the starting reference; no new depth round. Design package only.

**Conflict noted:** Decision D (14 Nov) records "Train at the far right". v1.2 explores the left. If v1.2 is approved, a new decision record is needed (conflict register item 54).

## 2. v1.1 versus v1.2
| | v1.1 | v1.2 |
|---|---|---|
| Train ball | far right | far left |
| Tab next to the ball | Progress | Home |
| Cradle | medium, 16 pt shoulder, 8 pt arms | medium, mirrored, **24 pt shoulder, 7 pt arms** (softened) |
| State badge | ball's top-right | ball's top-left (outer side, clear of the arms) |
| Time in the ball | emblem + time, 11.5 pt | tested; **time only, 16.5 pt, suggested** while active |
| Large text | capped at 17 pt | adaptive layout (section 6) |
| Page content in drawings | overlapped the cradle | stops above the dock; clearance tested at end of scroll |

Untouched: ball 72 pt; capsule 56 pt; one-third embrace; 5 pt ring gap; 15 pt ball-to-tab clearance; order Home, Plan, Progress; no Profile tab; Profile from the Home avatar; Training Hub v1.4 behaviour; cycling safety restrictions; no emblem approved.

## 3. Geometry (points; from the drawing geometry)
| | Standard 402 | Small 375 | Reference |
|---|---|---|---|
| Ball diameter | 72 | 72 | 72 |
| Capsule height | 56 | 56 | — |
| Shape height | 91 | 91 | 92 (**deviation −1**, softened shoulder) |
| Embrace | 33 % | 33 % | ≈33 % |
| Ring gap | 5 | 5 | 5 |
| Side margins | 14 | 14 | — |
| Ball bottom / capsule bottom above screen bottom | 34 / 42 | 16 / 24 | — |
| Top of capsule / ball / badge | 98 / 106 / 109 | 80 / 88 / 91 | — |
| Highest visual element (cradle arms) | 115 | 97 | — |
| Required scrolling inset (highest + 12) | 128 | 110 | 128 initial |
| Tab touch areas | 3 × 94 × 48 | 3 × **85** × 48 | ≥ 94 × 48 where geometry permits |
| Ball edge to nearest tab touch area | 15 | 15 | ≥ 15 |
| Train touch area | 72 circle; arms not touchable | same | — |

**Compromise — 375 pt conflict (design issue):** a 72 pt ball, 15 pt clearance, 14 pt margins and three 94 pt tabs need 396 pt. On the small iPhone tabs are 85 × 48 pt. Alternatives: (a) accept 85 pt — suggested; (b) 8 pt margins → 89 pt; (c) 64 pt ball on small phones → 87 pt; (d) no margins → 94 pt, shape touches the screen edges.
**Correction:** the v1.1 sheet stated 78 pt small-iPhone tabs; its own geometry gives 85 pt. The v1.1 record is left as written.

## 4. Interaction
Source: `interaction_state.mmd` (rendered: `sheets/interaction_state.png`). Idle → tap Train → compact panel → expand → Training Hub; Start → dedicated full-screen recording; minimise → back in the app with the session continuing where supported; tap Train → resume panel → Resume. A second session cannot be started. Nothing here changes the current implementation.
**Cycling:** the Ride screen owns the bottom of the display while recording; minimising a ride is drawn as intent and **blocked for implementation** by the cycling safety gate (GPS-route integrity, interrupted-ride persistence). A ride must be paused before Finish is available — unchanged.

## 5. Train ball states
The ball never moves or resizes. Every state has a distinct ring shape and badge in the ordinary text colour; none relies on colour or animation.
| State | Ring | Badge | In ball | Spoken name (proposed) | Note |
|---|---|---|---|---|---|
| Idle | none | none | emblem | "Train" | |
| Compact panel open | none; ball outlined | none | emblem | "Train, panel open" | |
| Strength recording, minimised | segmented | dot | time | "Strength workout, recording, 14 minutes" | |
| Endurance recording, minimised | solid | dot | time | "Ride, recording, 24 minutes" | **Blocked** — safety gate |
| Paused | split in two | pause bars | time | "Workout paused at 14 minutes" | |
| Completion pending | three-quarter | "…" | emblem | "Workout finished, not yet saved" | persists until saved/discarded |
| Save unsuccessful or uncertain | dotted | "!" | emblem | "Workout not confirmed saved. Open to resolve" | **Design issue** — depends on the pending save-result decision; never shows success |
| Returned after interruption | split | "↺" | time | "Workout restored, paused at 14 minutes" | **Design issue** — strength only (saved in-progress session exists as read in code, not re-verified); rides not restored today |

**Time legibility finding (drawings only):** emblem + time at 11.5 pt is weak at a glance and cannot scale; time only at 16.5 pt is clear (13.5 pt over one hour). Suggested: time only while active. Owner decision.

## 6. Accessibility
- **Text size (no cap):** labels grow in place to 19 pt (standard) / 17 pt (small) — measured so the widest word, "Progress", keeps 4 pt each side. At accessibility sizes the layout adapts: the selected destination shows its word at 28 pt; the other two show icons in 56 × 48 pt touch areas. Silhouette, ball and order unchanged. Nothing is truncated or ellipsised; all three keep spoken names and focus order; long-press shows the system large-label preview.
- **Design issues:** icon tabs shift slightly when selection changes; time in the ball cannot scale (spoken name carries it); no active-session indicator while the keyboard covers the dock.
- **Reduce Motion:** fades instead of movement; rings are always still shapes.
- **High Contrast:** selected = heavier word + bar; states = ring shape + badge glyph.
- **Focus order (proposed):** Home, Plan, Progress, Train. Touch expansion of the ball outward only, never toward Home.

## 7. Left-side ergonomics (reasoned; not user- or device-tested)
Left placement is not better or worse overall: it swaps thumb-side convenience by handedness, puts the most-visited tab (Home) beside the ball, and places the ball on the iOS swipe-back edge (**design issue to verify on a device**). A mis-tap on the ball is cheap in both versions (dismissible panel, or Resume only). Home indicator is clear. The case for the left is visual and brand.

## 8. Themes
One drawing path for Obsidian, Arctic, Ocean, Forest, Sandstone and High Contrast; existing tokens only (surface, border, text, accent). No new palette.

## 9. Arabic / right-to-left — two alternatives, no choice made
**A · Fixed left:** ball stays left; tabs read right to left (Home far right, Progress beside the ball). One geometry; identical muscle memory across languages; clear of the Arabic swipe-back edge (right).
**B · Mirrored right:** ball moves right; Home beside the ball; follows the iOS mirroring convention; two geometries to maintain; the primary action changes side for bilingual users. The app has no Arabic today.

## 10. Dependencies
Training Hub v1.4 pending items (emblem; cycling minimise/resume safety gate; save-result handling and recovery; review values/Intensity storage; new capabilities; session/rest rules) · open defects: ride GPS-route test and Plan edit-and-apply test (not investigated) · production navigation today is five numbered pages with a centre button and a Profile tab; Home is frozen at v2.3 Pending Review · Profile IA under review — untouched here.

## 11. Risks and unresolved decisions
1. Left versus right (supersedes Decision D if approved). 2. Softened shoulder (B) versus exact mirror (A). 3. Time only / emblem + time / emblem only in the ball. 4. Small-iPhone tab width (85 pt or an alternative). 5. Accessibility adaptive layout. 6. Arabic A or B. 7. VoiceOver order (Train last or first). 8. Swipe-back edge behaviour — needs a device. 9. Keyboard hides the active-session ball. 10. Save-uncertain and restored states depend on pending technical decisions. 11. Emblem.

## 12. Acceptance criteria — self-assessment for design review
| # | Criterion | Assessment |
|---|---|---|
| 1 | Train at the physical left (English) | Met in drawings |
| 2 | Home, Plan, Progress in order | Met |
| 3 | One sculpted silhouette | Met in drawings — owner's eye decides |
| 4 | Ball stays circular | Met |
| 5 | Medium cradle recognisable and balanced | Met in drawings — owner's eye decides |
| 6 | Touch clearance | Met on standard; **design issue** on small (85 pt tabs) |
| 7 | Selected tab identifiable | Met |
| 8 | Ball fixed across states | Met (same position measured on all state drawings) |
| 9 | Active vs paused without colour | Met |
| 10 | Real-size small-iPhone layouts | Included |
| 11 | No silent truncation | Met in drawings (labels measured, none overflow); adaptive layout is a **proposal** |
| 12 | No interactive content permanently obscured | Met in representative drawings; real pages must apply the inset |
| 13 | Six themes, same geometry | Met |
| 14 | No emblem shown as approved | Met — placeholder labelled |
| 15 | Training Hub and cycling restrictions unchanged | Met |

## 13. Sheets
`sheets/N1_left_cradle_main.png` · `N2_before_after.png` · `N3_six_themes.png` · `N4_train_button_states.png` · `N5_interaction_journey.png` · `N6_small_iphone_accessibility.png` · `N7_arabic_alternatives.png` · `N8a_measurements_handoff.png` · `N8b_content_clearance.png` · `interaction_state.png`
