# Cyclift — Endurance Performance v1.0: approved UI design and outstanding requirements

**Status:** UI DESIGN APPROVED AND LOCKED by the owner on 28 Nov 2026 (01:27) — Option C, Revision 1.1, with eight refinements. **Not implemented.** The approval is of the UI design only; it is not approval of any unvalidated calculation or of production implementation.

**Approved reference:** the design mockups in `docs/design/assets/H09_ap_*.png` and `docs/design/proposals/endurance-performance-v1/Cyclift_Endurance_Performance_Approved_UI_Reference.pdf`. They are design mockups with illustrative demo data, not simulator screenshots. Supporting documentation (inventories, duplication review, both proposals, audit): `Cyclift_Endurance_Performance_OptionC_Rev1.1.pdf` in the same folder.

**Destination:** Home → Endurance card → Endurance Performance (replaces the page titled "Cycling summary" once implemented).

## Owner's decisions (28 Nov 2026, 01:27)

1. Plan completion on this page is endurance-only; strength stays excluded and the scope is clearly identified.
2. Consistency is the second graph view.
3. The proposed comparable-effort methodology is accepted as an initial candidate for testing and validation — not a final validated calculation.
4. The FTP history storage feasibility and compatibility review is authorised. No storage change is to be implemented yet.
5. Activity colours: blue cycling, teal running, violet swimming, pink rowing.
6. Long recording lists are grouped by month within the same page.
7. All analytical components stay self-contained; no links to previously approved analytical screens.
8. The Endurance Development card's default explanation is shortened; the detailed methodology stays reachable through its information control.

Standing principle (28 Nov 2026, 01:18): share the data and calculations, not unnecessary screen navigation.

## Approved page, top to bottom

Header and period (This week · 4 weeks · 12 weeks · 1 year · All) → Endurance development card → three figures, labelled "Endurance only · strength is not included" → history graph (Volume · Consistency · Training load · Fitness) → Planned and completed → Intensity distribution → Recovery response (each showing its final figure when closed and expanding in the page) → one Coach card → Your activities (one reusable card per roster endurance activity, expanding to sport-specific modules) → Next planned endurance activity → Recent endurance recordings (expands in the page, grouped by month).

Preserved operational navigation: Back, the approved dock, View workout, opening an individual recording. No new dedicated screen.

## Outstanding requirements — recorded separately from the UI approval

None of these is approved for implementation by the UI approval.

### Calculations
| Requirement | State |
|---|---|
| Comparable-effort efficiency (cycling power at comparable heart rate; equivalents for other sports) | Initial candidate method accepted for testing and validation only. Needs: logic tests on synthetic rides with known answers, review of each proposed number (20-minute steady block, ±5 bpm, 95% coverage, three efforts against the three before, 3% "similar"), then the owner's validation decision. Until then cards show "Establishing baseline" and no efficiency figure. |
| Power curve across rides | New roll-up of the existing per-ride best average power. Not built. |
| Aerobic decoupling | New calculation. Phase 2. Not built. |
| Prescribed versus actual intensity roll-up; interval completion | Partly existing per ride; period roll-up not built. |
| Intensity Factor, Training Stress | Not shown; need a verified FTP and a validated method. Phase 2. |
| Training load across sports | No approved method. The graph view stays "Not calculated". |
| Fitness, fatigue and form | No validated model. The graph view stays "Not assessed". Phase 3. |
| Endurance-only plan completion and weekly Consistency | Must reuse the one existing completion rule, filtered to endurance sessions. No second engine. |

### Storage
| Requirement | State |
|---|---|
| Dated FTP history (value, date, source, method, measured / estimated / entered, verification, linked ride, body weight on that date) | Feasibility and compatibility review AUTHORISED; implementation NOT authorised. No back-filling of earlier values. Today only the current FTP and how it was set are kept; a date exists only for an FTP estimated from a ride. |
| Downgrade risk (an older build, including 216, saving the record could drop new fields) | Existing release blocker; unchanged. |
| Recovery readings beyond 90 days | Not kept. The page states the 90-day coverage. No change proposed. |
| In-app restore from an export | Does not exist. |

### Sensors and measurements
| Requirement | State |
|---|---|
| Power-based modules | Need rides recorded with a power meter by the phone or BikeComputer; Apple Health imports carry no per-second samples. |
| Heart-rate zones for athletes without power | Need heart-rate zone settings. |
| Temperature | Not recorded, so heat cannot be controlled for in comparable efforts. |
| VO₂ max | Not read from Apple Health; a new permission is not authorised. |
| Cycling dynamics | Need a sensor that measures them. Phase 3. |

### Multisport functionality
| Requirement | State |
|---|---|
| Recording, importing and scheduling for running, swimming, rowing, hiking, walking and other endurance activities | Not built. Their cards remain in the approved design with truthful states and must not be presented as working. |
| Home Endurance card for running-based athletes | Missing today, so the page cannot be reached by them. Separate dependency; the approved Home is not changed. |
| Adding an activity after onboarding | No dedicated place besides Profile. Dependency recorded. |
| Thresholds per sport | Needed before zones or efficiency for any non-cycling activity. |

## Not verified
Nothing in this design has been built, compiled or run. Accessibility, other themes, the redesigned main app and a physical iPhone are all outstanding and begin with implementation in Cyclift Lab.
