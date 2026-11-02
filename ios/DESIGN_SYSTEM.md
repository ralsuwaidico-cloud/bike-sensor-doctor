# Cyclift design system (SwiftUI) — S2-0

Branch `ui/design-system`, from build 127. Source of truth for the visuals: `/home/claude/gate1/v3/VISUAL_SYSTEM.md` and the v3 prototype. Status: **implemented locally, syntax-checked; not compiled for iOS, not simulator-tested** until the next CI run. Nothing in production screens uses it yet (S2-0 delivers the components; the vertical workflows wire them).

## Files

| File | What |
|---|---|
| `BikeComputer/DesignSystem/PureDesign.swift` | Foundation-only logic: `SourceTag`, `CySport`, `CyDaySport`, `CyDayStatus`, `CyDay`, `CyMonthDay`, `CyDeviceState`, `CyBannerKind`, `CyDesign` helpers (fractions, normalisation, insufficient-data wording, timers, month grid). Unit-tested on the Linux harness (`DesignSystemPureTests`, 9 tests, 9 pass) and on CI. |
| `BikeComputer/DesignSystem/CyTheme.swift` | Tokens: two deliberate palettes (light warm-grey / dark slate), sport identities (`cycling`, `strength`, `recovery`, `goal`, `insight`: tint, bg, mid, soft, onTint), status colours, nav/CTA, tag colours, spacing scale 4–24, margins 16, max content width 430, radii 28/22/16/12, min tap 44, motion durations; `CyType` (text styles, rounded tabular numerals); `CyMotion.animation(_:reduce:)` (nil under Reduce Motion); `.cyCard(tinted:radius:)`, `.cyMinTap()`. |
| `BikeComputer/DesignSystem/CyPrimitives.swift` | `CySourceTagBadge`, `CyIconBox`, `CyCaption`, `CyPrimaryButton`, `CySecondaryButton`, `CyTertiaryLink`, `CyChip`, `CySegmentedControl`, `CyListRow`, `CyRowGroup`, `CyDivider`, `CyStepper`, `CySwitchRow`, `CyBanner`, `CyOfflineBanner`, `CyEmptyState`, `CyInsufficientDataState`, `CyDeviceStateBadge`. |
| `BikeComputer/DesignSystem/CyCharts.swift` | `CyProgressRing`, `CyRingLabel`, `CySparkline`, `CyBarChart`, `CyCalendarStrip`, `CyMonthCalendar`, `CyIntervalStep` + `CyIntervalTimeline`, `CyRestTimerRing`. |
| `BikeComputer/DesignSystem/CyCards.swift` | `CyMetricTile`, `CyHeroRingCard`, `CySessionCard`, `CyCoachAnswer` + `CyCoachCard`, `CyGoalIndicatorCard`, `CyTabItem` + `CyFloatingTabBar`, `CyLiveMetric`. |
| `BikeComputer/DesignSystem/DesignSystemGallery.swift` | `DesignSystemGallery` + `DesignSystemGalleryRoot`: every component in every state with inputs labelled DEMO. |
| `BikeComputer/BikeComputerApp.swift` | Simulator-only hook: launch argument `-BC_DESIGN_GALLERY` (+ `-BC_DESIGN_GALLERY_DARK`) shows the gallery instead of the app. Ignored on a real device, like the UITestSupport hooks. |
| `BikeComputerUITests/DesignSystemAudit.swift` | Screenshots the gallery light + dark at each `LAYOUT_SIZES` size on each layout simulator; hard checks: every on-screen button/switch inside the window, ≥ 44 pt tall, with an accessible name; no text outside the window. Added to the CI layout default (`LayoutAudit DesignSystemAudit`) and to the quick set. |
| `BikeComputerTests/DesignSystemPureTests.swift` | Pure logic tests (harness + CI). |

## Honesty rules (owner §7)

- Every value-bearing component takes a `SourceTag` and renders it: **Measured** (sensor/recording), **Logged** (typed by the athlete), **Estimated** (formula with known error), **Unknown** (no value; nothing guessed), **Needs data** (not enough yet).
- `value == nil` renders "—" with the tag — a tile never invents a number.
- Charts take `[Double?]` and show `CyInsufficientDataState("Needs n more …")` below `minimumPoints` real values.
- `CyDeviceStateBadge` keeps **Paired**, **Connected** and **Receiving live data** distinct; paired-but-silent is never "receiving".
- Gallery inputs are demo values behind a simulator-only launch argument; production screens never read them.

## Accessibility and Dynamic Type

- All text uses iOS text styles (`CyType`), so it follows the user's size. Grids become one column at accessibility sizes (`dynamicTypeSize.isAccessibilitySize`); list rows move the value under the label.
- The week strip, month calendar and tab bar cap at XL (`.dynamicTypeSize(...xLarge)`) so seven cells always fit an iPhone SE; their VoiceOver labels carry the full day, sessions and status ("Today, Wednesday, strength, done").
- Every control is ≥ 44 pt (visually small controls extend their hit area with `cyMinTap()` / padding). Icons are `accessibilityHidden`; composite cards are single accessibility elements with a full label.
- Animations go through `CyMotion.animation`, which returns nil under Reduce Motion.

## Usage

```swift
CyMetricTile(title: "Cycling", systemImage: "bicycle", sport: .cycling, value: "58", unit: "min", sub: "of 2h planned", tag: .measured) {
    CySparkline(values: minutesPerWeek, tint: CyTheme.cycling.tint, fill: CyTheme.cycling.soft).frame(height: 36)
}
CyMetricTile(title: "FTP", sport: .cycling, value: nil, sub: "No watts are guessed", tag: .unknown)
CyHeroRingCard(caption: "This week", title: "You're on track", done: 3, planned: 5, ridesDone: 1, ridesPlanned: 2, liftsDone: 2, liftsPlanned: 3)
CyCalendarStrip(days: days) { day in open(day) }
CyBarChart(values: hoursPerWeek, labels: weekLabels, highlighted: 6, planLine: 2, unit: "h", missingUnit: "week")
```

## Remaining to wire (not in S2-0)

- Production screens (Home, Plan, Train now, Progress, Profile) still use the build-127 views; the vertical workflows replace them one at a time with data-backed instances of these components.
- `CyFloatingTabBar` is visual + callbacks; the root tab container switches to it with V3 Home.
- The month calendar takes a prepared `[CyMonthDay]`; the Plan workflow builds it from the plan versions.
- Chart data must come from the engine's provenance-aware values (parallel S2-0 data-layer work); the tag passed in must reflect the real provenance.
