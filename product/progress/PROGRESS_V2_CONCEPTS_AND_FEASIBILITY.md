# Progress v2.0 — Phase 2 preview: concept directions, landing architecture and Singularity feasibility

Status: **Current Draft** · Version 0.1 · 13 Nov 2026 · Level 3 (product specification)
Source: `docs/cyclift-governance`, `product/progress/PROGRESS_V2_CONCEPTS_AND_FEASIBILITY.md`
Images: `product/progress/concepts/PG1…PG3`.

**Static concept mock-ups with sample data, drawn with the existing six-theme UI Lab tokens only. Nothing was
built or run; no animation exists; no new colour token was introduced.** The generation, dates and figures in the
images are invented samples and describe no real athlete.

## 1. Proposed minimal landing architecture

| Order | Section | Content | Opens |
|---|---|---|---|
| A | **Athlete Singularity** | The singularity; "ATHLETE EVOLUTION"; generation; stage title; athletic profile; one line: evidence confidence · latest evaluation · Evolution details | Athlete Evolution Details |
| B | **Evolution** | Up to four compact rows, one per dimension: a direction in words and its confidence. No percentages, no composite | Dimension detail: the evidence, with dates and sources |
| D | **Next evolution** | One row: "2 of 4 kinds of evidence demonstrated" | What is demonstrated · what could improve · what evidence is needed · what Cyclift cannot yet measure. No dates promised |
| C | **Performance trends** | Entry row or one compact chart with a discipline and period control | Cycling, strength and hybrid analytics |
| E | **Records and history** | One entry row | Records (valid measurements only), milestones, training history |

"Next evolution" is placed above the trends because it answers two of the six questions in the brief; the order is
open to your review. The landing screen holds no checkpoint blocks, no empty-analytics cards and no history list.

**States every section must have:** insufficient evidence ("Establishing your baseline" — what is needed, and no
generation shown) · provisional · evidence-supported · not currently evaluated · loading · no power meter · no
strength detail · High Contrast · Reduce Motion · large text.

## 2. The three directions (PG1)

| | A · Cinematic Singularity | B · Minimal Technical Observatory | C · Athletic Evolution Timeline |
|---|---|---|---|
| Idea | The singularity fills the top of the page; identity sits on it | A small singularity beside a precise read-out; the page is an instrument panel | The singularity introduces a dated timeline from baseline to today |
| First screen answers | "Who am I as an athlete today?" | "What is the evidence?" | "How have I changed since I started?" |
| Information on the first screen | Least: identity, two dimensions, next evolution | Most: identity, four dimensions, a trend, next evolution | Identity and five to six dated events |
| Strength | Most recognisable; closest to the brief's signature | Densest and most analytical; the least scrolling | Makes the journey the product; history becomes meaningful |
| Weakness | The hero costs about 40 % of the screen; rendering cost is highest | The singularity becomes a badge; least distinctive | A new athlete has an almost empty timeline |
| Rendering cost | Highest (largest animated area) | Lowest | Low |

**Recommendation: A for the landing screen, with C as the Evolution Details page.** A carries the identity; C is
the natural place the hero opens into. B's dimension table is worth reusing inside the details page.

## 3. The singularity as one visual language (PG2, PG3)

- **Across themes:** the form is identical — dark event horizon, bright inner ring, a lensed arc over the top, a
  tilted disc crossing in front. Only the illumination follows the theme's accent and discipline tokens. On light
  themes the horizon stays dark and the disc is drawn in the theme's own darker colours.
- **High Contrast and the static fallback:** line and shape only — no glow, no gradient.
- **Between generations:** structure grows — further rings, a wider disc, finer detail. Brightness is not the
  variable, so a higher generation does not read as "healthier".
- **Never the only carrier of meaning:** generation, title, profile and confidence are always text beside it.

## 4. Technical feasibility of the animation

Assessed from documentation and general knowledge; **nothing was prototyped or measured.**

| Approach | What it is | For | Against |
|---|---|---|---|
| **SwiftUI with a Metal shader** (shader effects on a view, driven by a timeline) | One small fragment shader draws the whole object on the GPU | Least code; real-time; theme colours passed in as values; easy to pause; one shader also renders the static image | Needs iOS 17 or later; production's minimum iOS version must be confirmed |
| **Custom Metal view** | A hand-written renderer | Full control; works on older iOS | Most code to write and maintain |
| **RealityKit** | A true 3D scene | Real geometry and camera | Heavy for one object that needs no physics or scene; a black hole is an optical effect, better described by a shader than by a model |
| **SceneKit** | Older 3D framework | — | Apple describes it as soft-deprecated and unlikely to gain features (verified, Apple documentation, 2025). Not for new work |
| **Pre-rendered video or image sequence** | Played back, not rendered | No rendering risk | Not real-time; one asset per theme and per generation; large files; cannot follow a theme change |

**Recommendation to test first: the SwiftUI Metal shader**, with the custom Metal view as the fallback. "3D" would
mean a mathematically rendered, lit, perspective object — not a modelled scene.

### Safeguards the prototype must have

- Animation runs **only while the hero is on screen and the app is active**; it stops when scrolled away, when
  another tab is shown, and in the background.
- **Reduce Motion:** static image. **Low Power Mode:** static image. **Thermal state serious or worse:** static image.
- Frame rate capped (a slow orbit does not need 60 or 120 frames per second); option to settle to stillness after
  a short time.
- The advancement animation plays once, can be skipped, and can be switched off.
- The static image is produced by the same renderer, so the two can never disagree.

### What a simulator cannot prove

Battery use, heat and real frame times need a physical iPhone. A UI Lab run can show that the animation works and
that the safeguards switch; it cannot show that it is cheap. That measurement needs your device and will not be
claimed without it.

## 5. Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| A generation looks scientific | The brief forbids invented scientific justification | Call it a product milestone system everywhere, including in the app; publish every rule |
| Athletes without a power meter cannot show endurance capability | Unfair to limited-sensor athletes | Generation follows the best-supported dimension; missing data lowers confidence only; decide which non-power evidence is acceptable |
| Body weight is optional and has no history | Relative measures would be wrong | No relative figure without a current weight; propose weight history in Phase 4 |
| Sex is not stored; age is optional | No sex- or age-aware reference is possible today | References remain optional context until the data and sources exist |
| Demotion feels punitive | The brief forbids judgemental language | Highest achieved is permanent; silence is "not currently evaluated" |
| Invalid records (0-minute record, seconds-long "completed" ride) feed the system | Evidence would be false from day one | Fix record and completion validity first — a separately authorised production change |
| The hero's battery cost | A signature that drains the battery harms the product | Safeguards above; device measurement before any production proposal |
| Naming | "Specialist", "Integration", "Vanguard" conflict with the brief's own rules | Alternatives in the framework document §7 |
| Scope | Rating engine, persistence, sync and device display are large | Phases 3–5 stay separately authorised |

## 6. Unresolved questions

1. Generation naming: keep "G", or Stage / Orbit / E? Which title set?
2. Option 1, 2 or 3 for determining a generation?
3. Show both "highest achieved" and "current evaluation"?
4. Which evidence may count for endurance without a power meter (heart-rate-based, duration-based, none)?
5. May Cyclift ask for sex and keep a weight history, for optional reference context?
6. Landing direction: A, B or C — and is "Next evolution" above "Performance trends" acceptable?
7. Is iOS 17 the minimum version for production? It decides the rendering approach.
8. Should the validity fixes for records and ride completion be scheduled before Progress work continues?
9. Who provides the scientific review the brief requires before Phase 4?

## 7. Recommended priorities

1. Your decisions on questions 1–3 and 6.
2. Validity of records and completions (audit problems A and B) — small, and everything else depends on it.
3. Phase 1 completion: read the classification papers that could not be opened; verify the three unverified competitors.
4. Phase 2 proper: the chosen direction in all six themes, with every state of §1.
5. Phase 3 (isolated UI Lab), only after design approval and once the Plan prototype and the sheet diagnostics are settled, since all three share one prototype app and pipeline.

## Change log

| Version | Date | Change |
|---|---|---|
| 0.1 | 13 Nov 2026 | First concepts, architecture and feasibility assessment |
