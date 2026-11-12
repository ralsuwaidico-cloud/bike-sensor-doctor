# Cyclift Brand Book

Status: **Current Draft** · Version 0.1 · 12 Nov 2026 · Level 2 (below the Project Instructions, above product specifications)
Source: `docs/cyclift-governance` branch, `brand/CYCLIFT_BRAND_BOOK.md`

How to read this book: every rule is marked **[Instructions]** (taken from the Master Project Instructions v2.0),
**[Decision]** (dated owner decision), **[Production]** (extracted from the app's code as it is today),
**[Prototype]** (exists only in the UI Lab), **[Watch design]** (hardware-design documents) or **[Proposed]** (new in
this draft, awaiting approval). No token value in this book was invented: each table names the file it was read from.

---

## 1. Identity and mission

**Cyclift is a premium, intelligent hybrid-athlete training ecosystem.** [Instructions §1]

It helps athletes set meaningful goals, build achievable schedules, stay consistent, adapt intelligently and measure
progress, by connecting:

**Goals → Training Plan → Personal Schedule → Execution → Feedback and Adaptation**

Public name: **Cyclift**. Earlier names (Bike Sensor Doctor, Bike Computer, Athletics) and internal code names
(`BikeComputer` app target, `BC` prefixes) are historical and stay in the code. [Decision, register 10]

Character: premium · calm · intelligent · athletic · modern · precise · trustworthy · efficient. Gender-neutral. [Instructions §8]

## 2. Product principles

| Principle | Meaning in practice | Source |
|---|---|---|
| Training fits the athlete's life | Availability and commitments shape the plan; the plan never assumes unlimited time | Instructions §1, §6 |
| Consistency without guilt | A missed session leads to useful options, never punishment language or badges of failure | Instructions §1, §7 |
| The athlete decides | Meaningful plan changes are explained, previewed and approved. Increases are never applied automatically | Instructions §6; Coach Decision 1 (11 Nov) |
| Actionable, not decorative | Every element earns its place; no repeated statistics | Instructions §1, §8 |
| Simple surface, serious engine | A minimal interface does not mean simple logic underneath | Instructions §1 |
| Never fabricate | No invented scores, outcomes or scientific claims; missing data is shown as missing | Instructions §1, §9 |
| Hybrid by design | Cycling and strength are equal citizens; other disciplines can be added without redesign | Instructions §1 |
| Each destination has one job | Home understand · Plan decide · Train execute · Progress evaluate · Profile configure | Instructions §5 |

## 3. Voice and wording

- Plain, calm, specific. Say what happened, why, and what the athlete can do.
- The feature is called **Coach**. Its present logic is **rules-based** and is described that way. Generative AI
  coaching and advanced adaptive planning are future capabilities and are never implied. [Decision, register 3]
- Coach pattern: **Observation → Interpretation → Recommendation → User decision.** [Instructions §7]
- Never medical. Recovery and health text is training context, not clearance or diagnosis.
- Name the kind of every number: measured · entered by you · calculated · estimated · sample · missing · experimental. [Instructions §9]
- Do not claim event-specific tapering, calendar access, adaptive scheduling or any capability before it is implemented and verified. [Instructions §6]

## 4. Themes

### 4.1 Status in one table

| Surface | What exists today | Evidence |
|---|---|---|
| iPhone app (production) | **Two palettes: light and dark** (`CyTheme`), plus the older `BC` colours still used on several screens | Code on the release branch |
| iPhone UI Lab (prototype) | **Six themes: Obsidian, Arctic, Ocean, Forest, Sandstone, High Contrast** | Prototype code; contrast script 294 pairs, 0 failures, lowest text ratio 4.79; simulator screenshots only |
| Detachable Watch (design) | Six theme **names** approved for iPhone and Watch (10 Nov). The documented token values are still the earlier three families (Midnight Blue / Arctic, Graphite / Steel, Plum / Rose) | Hardware handover `04_UI_UX_DESIGN_SYSTEM.md` |
| Waveshare BikeComputer (firmware) | Its own round-screen visual system | Firmware documents |
| Apple Watch app | Not documented as a themed surface | — |

The six themes are the **approved direction** [Decision 10 Nov]. They are **not in the production app**. Theme support
must be validated, not assumed [Instructions §8].

### 4.2 Production tokens (iPhone) — `ios/BikeComputer/DesignSystem/CyTheme.swift`

| Token | Light | Dark |
|---|---|---|
| canvas | #F4F1EC | #151A21 |
| card / card2 | #FFFFFF / #F8F6F2 | #1E242C / #252C35 |
| line / line2 | #E7E2DA / #EFEBE5 | #2F3741 / #28303A |
| ink / ink2 / ink3 | #1F2328 / #5A6068 / #6E747C | #EEF1F4 / #AEB6C0 / #8C95A0 |
| cycling tint · bg | #3550B5 · #E4EAFC | #A9BAF5 · #232B42 |
| strength tint · bg | #A3324F · #FCE5EA | #F2A9BB · #3A2430 |
| recovery tint · bg | #1C6B4E · #DCF2E7 | #8FD8B5 · #1C3329 |
| goal tint · bg | #855400 · #FDF1D3 | #F3D088 · #3A3122 |
| insight tint · bg | #5A44A8 · #ECE7FB | #C7B9F4 · #2C2742 |
| warn · bad | #9A4B00 · #B42318 | #F5B97A · #F59A90 |
| nav · cta | #1F2328 · #1F2328 | #2A313B · #EEF1F4 |

Older set still in use (`ios/BikeComputer/Theme.swift`, `BC`): accent teal, live green, stale amber, warn red,
strength purple, seven zone colours.

### 4.3 Prototype tokens (UI Lab) — `CycliftUILab/DesignSystem/Theme.swift` on `proto/ui-lab`

| Token | Obsidian | Arctic | Ocean | Forest | Sandstone | High Contrast |
|---|---|---|---|---|---|---|
| background | #0B0D10 | #F3F6FA | #071726 | #0C1512 | #F5F0E8 | #000000 |
| surface | #15181D | #FFFFFF | #0E2236 | #14201B | #FFFDF9 | #000000 |
| surface2 | #1F242B | #E9EEF4 | #17304A | #1D2D26 | #ECE4D8 | #1C1C1E |
| textPrimary | #F2F4F7 | #111820 | #EAF3FB | #EEF5F0 | #221C16 | #FFFFFF |
| textSecondary | #A9B0BB | #465261 | #A3B9CC | #A8BBAF | #574C40 | #E5E5EA |
| textTertiary | #8A93A0 | #5D6978 | #8AA2B8 | #8CA195 | #6B5F52 | #C7C7CC |
| border | #2E343D | #D3DBE5 | #27496A | #2D4238 | #DBCFBF | #FFFFFF (1.5 pt) |
| accent | #9CC2EE | #1B63C2 | #48D6CF | #9AD6A8 | #A6482A | #FFD60A |
| endurance | #58C4F6 | #0A6FA8 | #6CCBFA | #6CC6F2 | #0F6C9C | #64D2FF |
| strength | #FFB25B | #A35400 | #FFB866 | #F9B466 | #9C5300 | #FF9F0A |
| recovery | #7EDC9A | #1A7F45 | #86E0A4 | #86DDA0 | #24773F | #30D158 |
| success | #5BD68A | #1A7F45 | #66DB95 | #6BD893 | #24773F | #30D158 |
| warning | #F5C04A | #8F5F00 | #F7C75A | #F2C458 | #855B00 | #FFD60A |
| danger | #FF8077 | #C2302A | #FF8C84 | #FF8A80 | #B93026 | #FF6961 |
| ring: consistency | #5FD3C4 | #0B7F74 | #5FD9CB | #62D2C3 | #0F7A70 | #66E5D6 |
| ring: load | #F5B85C | #A35F00 | #F7BE68 | #F2B962 | #9C5C00 | #FFB340 |
| ring: recovery | #A99BFF | #5F4BD0 | #B0A4FF | #ADA0FF | #5B49C4 | #BFB5FF |

**These are prototype values.** They become brand tokens only when the owner approves the theme set for production.

### 4.4 Open theme conflicts (see the conflict register)

- **Discipline colours disagree** between the three iPhone sets: strength is purple (`BC`), rose (`CyTheme`) and amber
  (UI Lab); cycling is teal-accented (`BC`), indigo-blue (`CyTheme`) and blue (UI Lab). Register 12 — unresolved.
- **The six themes have no Watch token values** yet. Register 13 — unresolved.

### 4.5 Rules that hold in every theme

- A colour's **meaning never changes with the theme**; only lightness does. [Prototype; Watch design V5]
- Accent is restrained and never reduces metric readability or status meaning. [Watch design V4]
- No theme is recommended by gender. [Watch design V3]
- High Contrast uses borders instead of shadows and flat fills instead of gradients. [Prototype]
- Gradients are subtle, derived from the theme's own tokens, and used only on selected surfaces. [Home v2.1–v2.3 instructions]

## 5. Colour meaning and grading

Semantic colours kept: **discipline** (endurance / cycling, strength, recovery), **status** (success, warning, danger),
and **honesty tags** (measured, logged, estimated, unknown, needs data — `CyTheme.tagColors`). [Production]

**Grading rule (revised).** A colour may express a judgement only when it stands for a **documented, meaningful state
or a validated threshold**. Green and red are not applied automatically to performance or adherence. Status is never
colour alone: it always carries a word, icon or shape. Missing data is never graded. [Decision, register 2]

Thresholds found in earlier documents and **flagged for review — not approved for use**
(`ios/APPEARANCE_AND_GRADING.md` §A; nothing in code or algorithms was changed):

| Earlier rule | Why it needs review |
|---|---|
| Plan adherence: ≥ 90 % green · 70–89 % light blue · 50–69 % yellow · < 50 % red | Judges adherence by colour with unsupported cut-offs |
| Power / heart rate vs target band: inside light blue · within ±5 % yellow · further red · ≥ 90 % of step in band green | The ±5 % and 90 % figures have no documented basis |
| Cadence vs preferred range: within 5 rpm yellow · further red | Same |
| Interval completion: in target light blue · outside yellow · cut short red | Judges a cut-short interval as failure |
| Records: new record green · within 2 % light blue | The 2 % figure has no documented basis |

## 6. Typography

| Surface | Rule | Source |
|---|---|---|
| iPhone | System font through iOS text styles, so everything follows Dynamic Type. Numerals are rounded and tabular (`CyType.numeral…`, `.title` rounded bold; sections `.headline` semibold; body `.body`) | Production `CyTheme.swift` |
| iPhone prototype | Same approach: `CyFont` — display `.title` rounded bold · name `.title2` rounded semibold · value `.title3` rounded semibold tabular · label `.subheadline` medium · caption `.caption` medium · overline `.caption2` semibold | Prototype |
| Detachable Watch | Inter — **provisional** (memory, licence and rendering to be verified). Western digits by default, Arabic-Indic optional. Lead number 58 px wrist, 76 px bike, stepping down so the whole number fits the round screen | Watch design V6, V10 |
| Waveshare BikeComputer | Bitmap fonts: numerals 80 / 60 / 44, bold 22 / 16 | Firmware documents |

Rules: no fixed point sizes for text on iPhone; no meaning carried by size alone; long names truncate or wrap by design, never clip.

## 7. Spacing, radii, touch

| Token | Production (`CyTheme`) | Prototype (`CySpace` / `CyRadius`) |
|---|---|---|
| Spacing scale | 4 · 8 · 12 · 16 · 20 · 24 | 4 · 8 · 12 · 16 · 24 |
| Screen margin | 16 (max content width 430) | 20 on Home |
| Radii | hero 28 · card 22 · field 16 · chip 12 (older `DS.corner` 14) | 22 · 16 · 10 |
| Minimum touch target | 44 pt | 44 pt |
| Dock clearance | 128 pt at the bottom of every scrolling page | Content inset by the dock height |

The two scales are close but not identical; they are to be unified when themes reach production. [Proposed]

## 8. Components and patterns

| Pattern | Rule | Source |
|---|---|---|
| Cards | Used when they group or enable interaction; no cards inside cards; no large empty surfaces; borders light or absent except High Contrast | Instructions §8; Plan v2.0 brief |
| Rows | Preferred for sessions, routines, settings and metrics: icon, name, value with unit, one line of support | Home v2.2 (rows approved over a grid) |
| Rings | One meaning per ring; a number in the centre has a stated definition; an empty or dashed ring means "no value", never zero | Home v2.1–v2.3 |
| Charts and graphs | Lines with a point per real measurement; a missing day is a gap — never interpolated; different units never share an unlabelled scale; a selected day shows exact date and values | Home v2.2–v2.3; Instructions §9 |
| States | Every component has normal, loading, empty, partial-data and error states with truthful wording | Instructions §8 |
| Sample data | Marked "sample" wherever it appears | Instructions §9 |
| Sheets | Short tasks in sheets; complex workflows on their own screen; a consequential change is previewed before it is saved | Plan v2.0 brief; existing review flow |
| Motion | Purposeful only; all animation off under Reduce Motion | Production `CyMotion` |

## 9. Navigation

Five destinations, each with one purpose: **Home** (understand today) · **Plan** (decide and organise) · **Train**
(execute) · **Progress** (evaluate) · **Profile** (configure). [Instructions §5]

The floating dock with its sliding highlight and raised centre action is Cyclift's navigation signature and is not
replaced by a generic tab bar. [Production `CyFloatingTabBar`; Home v2.1–v2.3]
Content always scrolls clear of the dock.

## 10. Accessibility

- Dynamic Type everywhere; layouts restack at accessibility sizes.
- Text contrast at least WCAG AA; High Contrast theme for stronger needs.
- Colour is never the only signal.
- Touch targets at least 44 pt.
- Smallest supported iPhone is a design target, not an afterthought.
- Every control has an accessible name and value.
- Evidence rule: a simulator screenshot or simulator test is not physical-device or VoiceOver evidence. [Instructions §11]

## 11. One ecosystem, several surfaces

| Surface | Role | Shared with iPhone | Adapts | Status |
|---|---|---|---|---|
| iPhone app | Central authority for plans, coaching, recording, data | — | — | Released builds exist; current baseline build 216 |
| Apple Watch app | Companion for workout interaction and live measurements | Discipline identity, state wording | Glanceable layouts | Implemented; see architecture index |
| **LILYGO detachable Cyclift Watch** | Wrist / bike / gym display and interaction | Theme names, state meaning, honesty rules | 240 × 240 round screen, keys, densities | Design approved in part; firmware separately authorised; **nothing hardware-verified is assumed** |
| **Waveshare BikeComputer** | Bike-mounted computer | State meaning, coach wording | Round 1.28-inch screen, its own protocol | Firmware 0.4–0.7.x history; its own evidence levels |

The two hardware lines are **separate workstreams in one ecosystem**. Their firmware and communication protocols are
not interchangeable and must not be assumed to be. [Decision, register 1]

Cross-surface constants: discipline icons (bicycle, dumbbell, moon), state words, "missing is missing", approval
before plan changes, and the evidence labels.

## 12. Metrics and scientific integrity

- Every metric has a definition, a unit and a calculation window.
- Session load is **RPE × minutes** where it is expressed that way; it is not replaced by unexplained points.
- **No numerical recovery score in production** until an approved, documented, validated method exists. Until then:
  status words or the underlying measurements. The percentage ring is the intended future design; prototype numbers are
  sample data. [Instructions §9; register 8]
- No biological age, physiological age, stress score or proprietary-style metric is invented.
- Load and recovery shown together are a comparison, not a claimed cause and effect.

## 13. Evidence and promotion

Report separately: designed · implemented · compiled · unit-tested · simulator-tested · physical-device-tested ·
released · user-accepted. [Instructions §11]

A UI Lab prototype moves toward production only after design review, acceptance, open-defect list, integration-impact
review, testing and explicit authorisation. Prototype approval does not mean the underlying feature works. [Instructions §12]

## 14. Reference policy

Other products (WHOOP, Garmin, RestorTrain) may be studied for interaction patterns. Their scoring methods, visual
identity and interfaces are not copied. No claim of superiority without evidence. [Instructions §8]

## 15. What this draft does not settle

1. Discipline colours for production (register 12).
2. Watch token values for the six themes (register 13).
3. Which grading rules, if any, are approved (section 5).
4. One spacing and radius scale for production (section 7).
5. A logo, wordmark and app-icon specification — **no source document was found**; not invented here.
