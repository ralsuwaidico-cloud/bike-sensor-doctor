# Navigation v1.2 — Final Visual Specification

**Revision:** 1.1 · 15 Nov 2026 (supersedes rev 1.0 of this same file; rev 1.0 is in the branch history at commit 7cea4de0) · finalisation of `../NAVIGATION_V12_LEFT_TRAIN_CRADLE.md` (v0.1, kept unchanged as the exploration record)
**Status:** Navigation v1.2 — **Current Approved — Visual Design Baseline; Implementation Not Authorized** (owner's final design decision, 15 Nov 2026).
**Implementation: NOT STARTED and NOT AUTHORISED.** Designed only. Nothing here was implemented, compiled, simulator-tested or device-tested. All figures are **drawing targets**, not measurements from running software. **ILLUSTRATIVE DESIGN — NOT IMPLEMENTED.**

Related status (unchanged by this document): Train emblem — Pending Selection · Training Hub v1.4 — Current Approved, Design Baseline, Implementation Not Authorised · Cycling minimisation — Blocked Pending Safety Gate · Production navigation — Unchanged · v1.0 and v1.1 — historical design records, preserved.
Decision record: `decisions/2026-11-15_navigation-v12-train-left-selected-visual-direction.md`. Technical impact: `NAVIGATION_V12_TECHNICAL_IMPACT_REGISTER.md`.

## 1. Architecture
Three navigation tabs and one primary control, left to right: **Train ball — Home — Plan — Progress**. Train is not a fourth tab. Home, Plan and Progress share one sculpted capsule ending at the left in a concave cradle that embraces about one-third of the ball. The ball is an independent circular touch target; the cradle arms are decorative and take no touches. No floating label, rectangular connector or fifth destination. Profile has no tab: the Home avatar opens the single Profile experience, Home stays the selected tab while Profile is shown, and returning preserves Home's position where supported. Plan remains the intended owner of schedules, goals, equipment and routines (subject to its own approvals). Retiring the Home quick menu is a separate change (conflict register 51) and is not decided here.

## 2. Geometry (points)
| Element | Standard 402 | Small 375 | Owner target |
|---|---|---|---|
| Train ball (true circle) | 72 | 72 | 72 |
| Capsule height | 56 | 56 | 56 |
| Total silhouette height | **90.2** | 90.2 | accepted by the owner at 90.2 (not to be altered to reach 91–92) |
| Ball embraced | 33 % | 33 % | ≈ 33 % |
| Ring gap | 5 | 5 | 5 |
| Ball to nearest tab region | 15 | 15 | ≥ 15 |
| Tab touch regions | 3 × 93.67 × 48 | 3 × 84.67 × 48 | 94 × 48 / 85 × 48 (rounded); small-iPhone width accepted **subject to future running-device validation** |
| Side margins / capsule end inset | 14 / 6 | 14 / 6 | — |
| Ball bottom / capsule bottom above screen bottom | 34 / 42 | 16 / 24 | — |
| Capsule top / ball top / badge top | 98 / 106 / 109 | 80 / 88 / 91 | — |
| Highest visual element (arm tips) | 115.1 | 97.1 | — |
| Scrolling inset | 128 | 110 | ≈ 128 / ≈ 110 |
| Clearance at end of scroll | 12.9 | 12.9 | — |

Width budget: 14 + 72 + 15 + 3 × region + 6 + 14 = 402 (281 for tabs) and 375 (254 for tabs). Regions share edges; no overlap with each other, the ball (15 pt) or the screen edges (20 pt).

**Cradle construction (final refinement):** shoulder = one eased cubic curve from the capsule edge (starting 104 pt from the ball end) into the arm, replacing the single 24 pt arc of the previous v1.2; arms taper from 9.6 pt at the root to 6.8 pt at the tip (outer arc radius 46.3 pt, centre offset 5 pt toward the capsule); tips are half-round; inner edge concentric with the ball at 41 pt. The state ring (radius 38.7 pt, 2.6 pt line) lies wholly inside the 5 pt gap. Depth and ball size were not increased. Sheet F1 overlays final against previous.

## 3. Typography and selection
Inter. Tab words 13.5 pt medium; selected = semibold + a 14 × 2.5 pt bar beneath. One selection indicator only; no filled rectangles, no tab icons at normal sizes. No tab is selected while the expanded hub is open.

## 4. Train ball states
Position and size never change. States differ by ring construction and badge in the ordinary text colour; never by colour or animation alone. The badge sits at the ball's outer top-left.
| State | In ball | Ring | Badge | Status |
|---|---|---|---|---|
| Idle | temporary placeholder (dashed ring) | none | none | selected |
| Compact panel open | placeholder; ball drawn as an outline | none | none | selected |
| Strength recording, minimised | time only | segmented | dot | selected; not implemented |
| Endurance recording, minimised | time only | solid | dot | **Blocked Pending Safety Gate** |
| Paused | time only (static) | split in two | pause bars | selected |
| Completion pending | placeholder | three-quarter | "…" | as v1.2; depends on v1.4 pending items |
| Save unsuccessful / uncertain | placeholder | dotted | "!" | **design issue** — no confirmation behaviour promised |
| Interrupted / restored | time only | split | "↺" | **design issue** — no persistence guarantee made |

**Timer (approved):** under one hour MM:SS; from one hour the “1h04” style (hours, small “h”, minutes). Both at 16.5 pt; the text never shrinks. Measured in the drawings: 14:06 and 59:59 are 45 pt wide, 1h04 is 40 pt, 10h12 is 50 pt, in a 72 pt ball. Exact seconds remain inside the recorder. The timer is never the only running/paused signal. Legibility judged from drawings only.

## 5. Dynamic Type and accessibility
- Touch regions never move or resize with text size or selection.
- Normal: words. Larger: words grow in place to 19 pt (standard) / 17 pt (small). Accessibility sizes: selected destination keeps its word at **20 pt (standard) / 18 pt (small)**, always inside its own region; unselected show icons with full accessible names. No truncation. The 17 pt cap is removed as a general rule.
- Widest word: "Progress" measures 86 pt at 20 pt in a 93.7 pt region, and 78 pt at 18 pt in an 84.7 pt region. Nothing overhangs a neighbouring region (the 26 pt overhanging version of rev 1.0 is withdrawn by owner decision).
- **Design issue:** the selected word at accessibility sizes is smaller than the system's largest text; the large-label preview covers the rest. The timer does not scale; the spoken name carries it.
- **VoiceOver order:** Home, Plan, Progress, Train (both languages). Tabs: trait tab + selected. Train: button whose name carries the state (e.g. "Train, no active session"; "Strength workout recording, 14 minutes elapsed"; "Workout paused, 14 minutes elapsed"; "Workout finished, awaiting save confirmation" — illustrative; final wording must match supported states). Cradle, arms, ring, badge and bar are not accessibility elements.
- **Voice Control:** four names. **Switch Control:** four stops, one group. **Large-label preview** on long-press. **Reduce Motion:** fades and instant swaps; rings never animate.
- **High Contrast:** shape and line carry every state.

## 6. Arabic / RTL
Train stays on the physical left; the silhouette is not mirrored. Destinations read right to left (Home far right, Progress beside the ball); selection bar follows the destination; accessibility order unchanged. Arabic labels are illustrative, not approved translations.

## 7. Content clearance, keyboard, safe areas
Scrolling insets 128 pt (home-indicator phones) and 110 pt (no home indicator), rechecked against the final geometry: highest element 115.1 / 97.1 pt, clearance 12.9 pt. Content may pass behind the dock while scrolling; every interactive item can scroll clear. F7 shows top, part-way and end for all three tabs on both sizes. **Keyboard:** covers the dock; no floating control over the keyboard; an active session is recovered by dismissing the keyboard, which returns the dock unchanged; page inset follows the keyboard. **Design issue:** no visible active-session sign while typing. Dock geometry does not change with text size, so insets do not change.

## 8. Themes
One path for Obsidian, Arctic, Ocean, Forest, Sandstone, High Contrast. Tokens used: surface-2 (silhouette), border, text primary/secondary, accent (ball), background (text on ball). No new colours, glow or gradients; one soft shadow under the shape.

## 9. Interaction (F9, `interaction_flow.mmd`)
Home / Plan / Progress → Train → Compact Panel → Expanded Hub → Preparation → Recording → Minimised → Resumed → Finish → Save → Optional Review. One active session at a time; resuming never creates a second session; a ride must be paused before Finish; ride minimisation blocked; save-uncertain and restored paths are pending. The current app uses numbered destinations and a hidden Ride screen; these are not assumed removable (see the technical impact register). The left-edge placement is flagged for physical-device swipe-back testing. The Train control must never take a tap meant for Home or a system gesture.

## 10. Acceptance criteria (proposed design acceptance checklist)
**Geometry** — G1 ball 72 pt and circular · G2 capsule 56 pt · G3 silhouette 90.2 pt (± 0.5) · G4 embrace 31–35 % · G5 ring gap 5 pt, ring unobstructed · G6 one continuous outline, no visible joint, tips rounded, no hook · G7 no depth or ball increase versus v1.2.
**Touch** — T1 three equal tab regions, 93.7 × 48 (standard) and 84.7 × 48 (small) · T2 ≥ 15 pt ball-to-region · T3 no overlap between regions, ball or edges · T4 arms take no touches · T5 regions identical at all text sizes and selections.
**States** — S1 ball position identical in every state · S2 each state distinguishable in greyscale and High Contrast · S3 active shows time only; idle shows no timer or badge · S4 timer 16.5 pt in both formats: MM:SS under an hour, 1h04 style from one hour · S5 uncertain save never resembles saved.
**Accessibility** — A1 order Home, Plan, Progress, Train · A2 names present for icon tabs · A3 no truncation at any size; the selected word never leaves its own region · A4 decorative parts hidden from assistive technology · A5 Reduce Motion behaviour as specified · A6 Voice Control and Switch Control reach four targets.
**Clearance** — C1 last interactive item on Home, Plan, Progress clears the arms at end of scroll (≥ 12 pt) on both sizes · C2 insets 128 / 110 pt · C3 nothing floats over the keyboard; dock returns intact.
**Language and theme** — L1 Arabic keeps the ball left, order adapted, indicator aligned · L2 six themes share one geometry, existing tokens only.
**Safety and scope** — X1 one session at a time; resume never duplicates · X2 ride Finish only after Pause · X3 cycling minimisation shown as blocked · X4 no emblem presented as approved · X5 production navigation unchanged.
**For later, on real hardware (cannot be passed from drawings):** swipe-back at the left edge, timer legibility in use, thumb reach, mis-taps between ball and Home.
Self-assessment from the drawings: all met. Open design issues remain in sections 4, 5 and 7, and the hardware-only checks above are outstanding.

## 11. Decision ledger
**Approved by the owner (final design decision, 15 Nov):** Train at the physical far left · Home, Plan, Progress in the connected sculpted capsule · softened medium cradle with tapered arms, 72 pt ball, 33 % embrace, 5 pt ring gap · silhouette 90.2 pt as measured · timer MM:SS under one hour and 1h04 style beyond · selected label at accessibility sizes fits its own region (20 / 18 pt) · 85 pt tab regions on the small iPhone, subject to running-device validation · Train stays left in Arabic with text direction and reading order adapted · six themes, accessibility and content-clearance requirements retained · emblem remains unselected, labelled placeholder.
**Still pending owner decision:** Train emblem · Arabic translations · retiring the Home quick menu (conflict register 51) · whether any active-session sign should show while the keyboard is up.
**Unresolved technical dependencies (kept visible; none is resolved by this approval):**
1. **Cycling minimisation** — Blocked Pending Safety Gate (GPS-route integrity, interrupted-ride persistence).
2. **Existing numbered navigation routes** — five numbered pages with a hidden Ride page; tests bound to them; not assumed removable (conflict register 57).
3. **Two open test failures** — ride GPS-route samples and Plan edit-and-apply, from simulator run 43013897973; open defects, not investigated.
4. **Uncertain-save behaviour** — the state is drawn; no confirmation or recovery behaviour exists or is promised.
5. **Physical-device gesture testing** — swipe-back at the left edge beside the ball; also thumb reach, mis-taps beside Home, timer legibility, and the 85 pt small-iPhone regions.
6. Interrupted-session persistence; save-result handling; the other Training Hub v1.4 pending items.
**Requires future engineering approval:** any implementation, route or presenter change, test change, UI Lab prototype.

## 11a. Changes in revision 1.1
Accessibility selected word 26 / 23 pt → 20 / 18 pt, fitted inside its region (overhang and off-centre Plan icon removed) · timer card shows the approved rule only (1h04, 2h30, 10h12; the two rejected alternatives removed) · silhouette height recorded as accepted · sheet status line updated · drawing corrections: duplicate frame codes on F7 (Plan and Progress rows) renamed PL / PR; the Progress "part-way" frame on F7 showed an impossible over-scrolled position and now shows the true midpoint; a dimension label on F2 that sat on the home-indicator line was moved and a redundant "6" marker removed (the 6 pt figure remains in the width budget). No other visual changes.

## 12. Sheets (`sheets/`)
F1 final cradle and comparison with previous v1.2 · F2 small iPhone and dimension overlays · F3 six themes · F4 states and timer · F5 Dynamic Type and accessibility · F6 English and Arabic · F7a/F7b content clearance, keyboard, large text · F8 comparison with the right-hand navigation · F9 interaction diagram.
