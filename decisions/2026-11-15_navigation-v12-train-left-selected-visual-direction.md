# Decision — Navigation v1.2: Train ball at the left is the Selected Visual Direction

**Date:** 15 Nov 2026 · **Decided by:** owner (instruction "Navigation v1.2 Finalization Instructions") · **Recorded by:** Claude

## Decision
1. Navigation v1.2 — Train ball at the physical left, Home / Plan / Progress in one sculpted capsule with the medium cradle and softened shoulder — is the **Selected Visual Direction — Pending Final Design Validation**.
2. Also selected: time only inside the ball while a session is active; small-iPhone tab regions of 85 × 48 pt with a 72 pt ball; adaptive text with fixed touch regions (the 17 pt cap is removed as a general rule); VoiceOver order Home, Plan, Progress, Train; Arabic keeps Train on the physical left.

## What this supersedes — and only this
It supersedes **point 1's placement clause** in `decisions/2026-11-14_navigation-decision-d-three-tabs-train-right-profile-via-avatar.md` ("Train … at the far right"). Everything else in Decision D stands: three tabs, no Profile tab, Profile from the Home avatar, the five Profile sections. It does **not** replace any Profile or Training Hub decision. Decision D's file, Navigation v1.0 and v1.1 are preserved unedited as historical records.

## Status set by this decision
| Item | Status |
|---|---|
| Navigation v1.2 visual direction | Selected Visual Direction |
| Refined drawings (final specification rev 1.0) | Pending Final Review |
| Train emblem | Pending Selection |
| Training Hub v1.4 | Current Approved — Design Baseline; Implementation Not Authorised |
| Cycling minimisation | Blocked Pending Safety Gate |
| Production navigation | Unchanged |

## Not authorised
Implementation, production navigation or route changes, release-branch changes, onboarding / Home / Plan / Progress / Profile / Training Hub implementation, database, persistence, BLE or firmware changes, TestFlight, merging docs or UI Lab into production, changing or weakening tests, a functional UI Lab prototype.

## Documents
`product/profile/nav-v12/final/NAVIGATION_V12_FINAL_VISUAL_SPECIFICATION.md` (rev 1.0) · `…/NAVIGATION_V12_TECHNICAL_IMPACT_REGISTER.md` (rev 1.0) · `…/final/sheets/` · earlier exploration: `product/profile/nav-v12/NAVIGATION_V12_LEFT_TRAIN_CRADLE.md` (v0.1).


---
## Addendum — Final design decision (owner, 15 Nov 2026, later the same day)
Added below the original record; the text above is unchanged and describes the earlier "Selected Visual Direction" step.

The owner reviewed the Final Design Review Package and **accepted Navigation v1.2** with these final decisions: Train at the far left; Home, Plan, Progress in the connected sculpted capsule; softened medium cradle with tapered arms, 72 pt ball, 33 % embrace, 5 pt ring gap; silhouette height accepted at the measured 90.2 pt; timer MM:SS under one hour and 1h04 style beyond, exact seconds in the recorder; at accessibility sizes the selected label fits within its own region (20 pt alternative, not the overhanging 26 pt); 85 pt tab regions on the small iPhone, subject to future running-device validation; Train stays physically left in Arabic; six themes and existing accessibility and content-clearance requirements retained; the Train emblem remains unselected with a labelled placeholder.

| Item | Status now |
|---|---|
| Navigation v1.2 | **Current Approved — Visual Design Baseline; Implementation Not Authorized** |
| Specification | `product/profile/nav-v12/final/NAVIGATION_V12_FINAL_VISUAL_SPECIFICATION.md` rev 1.1 |
| Train emblem | Pending Selection |
| Training Hub v1.4 | Current Approved — Design Baseline; Implementation Not Authorized |
| Cycling minimisation | Blocked Pending Safety Gate |
| Production navigation | Unchanged |

**Unresolved technical dependencies kept open:** cycling minimisation; existing numbered navigation routes and hidden Ride page; the two open test failures (ride GPS-route samples, Plan edit-and-apply); uncertain-save behaviour; physical-device gesture testing.
**Not authorised:** any implementation, production code change, UI Lab prototype, onboarding change, firmware change, database migration or TestFlight build.
