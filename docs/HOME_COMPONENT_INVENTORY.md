# Cyclift UI Lab — component inventory (Home v2.1)

**Prototype only.** Standalone project on branch `proto/ui-lab`; no production code, data or engine is used.
Status of every item: **built in the prototype, awaiting the owner's review — nothing is approved.**

## Design system (`CycliftUILab/DesignSystem/Theme.swift`)

| Token group | Tokens |
|---|---|
| Backgrounds and surfaces | `background`, `surface`, `surface2` |
| Text | `textPrimary`, `textSecondary`, `textTertiary`, `textOnAccent` |
| Borders | `border`, `borderWidth`, `separator` |
| Accent | `accent`, `accentSubtle` |
| Training categories | `endurance`, `strength`, `recovery` (+ rest uses `textTertiary`) — each always with an icon and a label |
| Status | `success`, `warning`, `danger` — each always with an icon or a word |
| Charts and circular gauges | `ringConsistency`, `ringLoad`, `ringRecovery`, `ringTrack`, `chartGrid`, `chartAxis`, `ringLineWidthScale` |
| Interactive states | `pressedOverlay`, `disabledFill`, `disabledText`, `selectedFill`, `selectedBorder` |
| Layout and type | `CySpace` (4 / 8 / 12 / 16 / 24), `CyRadius` (10 / 16 / 22), `CyFont` (system text styles → Dynamic Type), `CyHit.min` 44 pt |

Themes: **Obsidian, Arctic, Ocean, Forest, Sandstone, High Contrast** (ids `obsidian`, `arctic`, `ocean`, `forest`,
`sandstone`, `highContrast`). Meaning is constant across themes: endurance is always the blue family, strength amber,
recovery green; success green, warning amber, danger red; the three ring identities teal, amber, violet. Only
lightness changes with the theme. No component contains a colour value; all read tokens from the environment.

## Components

| Group | Component | File | Inputs | Actions (callbacks) | States shown in the gallery |
|---|---|---|---|---|---|
| Buttons | `CyButton` (primary, secondary, destructive, compact) | Buttons.swift | title, icon, kind, isLoading | `action` | normal, pressed, disabled, loading, long text, large text |
| Buttons | `CyIconButton` | Buttons.swift | symbol, accessibility label, isSelected | `action` | normal, selected, disabled |
| Cards | `CyCard` (container) | Cards.swift | content, isSelected | — | normal, selected |
| Cards | `CyTrainingSummaryCard` | Cards.swift | `CySummaryCardModel?`, emptyMessage | `onOpen` | normal, empty, loading, large text |
| Cards | `CyWorkoutCard` | Cards.swift | `CyWorkoutModel?`, actionTitle, isActionEnabled | `onAction`, `onOpen` | normal, long text, disabled action, loading, large text |
| Cards | `CyRecoveryCard` | Cards.swift | `CyRecoveryModel?`, emptyMessage | `onOpen` | normal, no readings, loading |
| Cards | `CyCoachInsightCard` (card and compact row) | Cards.swift | `CyCoachModel?`, compact, emptyMessage | `onWhy`, `onAccept`, `onNotNow` | card, compact, no proposal, empty, loading |
| Cards | `CyEmptyStateCard` | Cards.swift | icon, title, message, actionTitle | `action` | normal |
| Cards | `CyGettingStartedCard` | Cards.swift | `[CyChecklistItem]` | `onItem` | in progress (expanded), complete (collapsed), expand / collapse |
| Cards | `CyMetricSummaryCard` | Cards.swift | `CyMetricModel?` | `onOpen` | normal, no data, loading |
| Circular | `CyRing`, `CyRingRow`, `CyRingListRow`, `CyRingGlyph` | Rings.swift | `CyRingModel` (fraction / status word / missing / loading) | `onTap` | Consistency, Load Balance, Recovery, generic 0 / 50 / 100 %, missing data, loading, long text, large text (list layout) |
| Charts | `CyTrendChart` | Charts.swift | series, status rows, day labels, isLoading, emptyMessage | (local selection) | line, multi-series, gaps, series selection, point inspection, empty, loading, large text, spoken summary |
| Charts | `CyWeeklyBars` | Charts.swift | points, unit, category | — | normal, insufficient data |
| Charts | `CyChip`, `CySparkline`, `CyProgressBar` | Charts.swift, Cards.swift | — | `action` (chip) | on / off |
| Other | `CyWeekStrip` | Controls.swift | `[CyDayModel]`, isLoading | `onDay` | normal, new user, empty, loading, large text |
| Other | `CyStatusBadge`, `CyStatusLegend` | Cards.swift, Controls.swift | `CySessionStatus` | — | done, today, planned, missed, skipped, rest |
| Other | `CyChecklist` | Controls.swift | `[CyChecklistItem]`, isEnabled | `onItem` | normal, done, optional, disabled |
| Other | `CySegmented` | Controls.swift | options, selection binding, isEnabled | (binding) | normal, selected, disabled, large text |
| Other | `CySelectionCard` | Controls.swift | title, subtitle, icon, isSelected, isEnabled | `action` | normal, selected, disabled, long text, large text |
| Other | `CySportPicker` | Controls.swift | `[CySportOption]`, selection binding | (binding) | selected, unselected, unavailable; support level always stated |
| Other | `CyFormField` | Controls.swift | label, text binding, placeholder, help, error, unit, isEnabled | (binding) | empty, filled, focused, error, disabled |
| Sheets | `CySheet` (chrome), `CyConfirmSheet` | Controls.swift | title, message, confirmTitle, isDestructive, isWorking | `onConfirm`, `onCancel` | normal, destructive, working |
| Sheets | `CyReviewSheet` | Controls.swift | title, reason, benefit, impact, `[CyChange]`, canApprove, blockedReason | `onApprove`, `onPostpone`, `onDecline` | normal, blocked (Approve disabled with the reason) |
| Navigation | `CyTabBar` | Controls.swift | `[CyTabItem]`, selection binding, centre title and badge | `onCentre` | selected tab, centre action with badge |
| Shared | `CyOverline`, `CySkeleton` | Cards.swift | — | — | used by every loading state |

## Added in Home v2.1 (owner revision, 12 Nov 2026) — all awaiting review

| Group | Component | File | Inputs | Actions (callbacks) | States shown in the gallery ("Home v2.1 components") |
|---|---|---|---|---|---|
| Tokens | `usesGradients`, `gradient(_:)`, `ringGradient(_:fraction:)`, `highlightSurface`, `cardStroke`; `CyFont.name / value / label` | Theme.swift | — | — | Gradients are derived from existing contrast-checked tokens (no new colour values); flat in High Contrast |
| Indicators | `CyIndicatorRow` | HomeV21Components.swift | consistency (fraction, text, caption), `CyMixModel`, `CyRecoveryIndicatorModel`, isLoading | `onConsistency`, `onMix`, `onRecovery` | hybrid, cycling only, strength only, partial recovery data, new athlete, nothing planned, recovery concern, loading, large text (list layout) |
| Indicators | `CyProgressRingGlyph` (gradient ring) | HomeV21Components.swift | fraction?, colour | — | value, no data (dashed) |
| Indicators | `CyMixRingGlyph` (double concentric ring) | HomeV21Components.swift | `CyMixModel?` | — | both rings, one ring inactive, both inactive, loading |
| Indicators | `CyRecoveryGlyph` (three availability arcs, no percentage) | HomeV21Components.swift | `CyRecoveryIndicatorModel?` | — | available, partial, awaiting, concern, loading |
| Schedule | `CyCompactSchedule`, `CySessionMark` | HomeV21Components.swift | `[CyScheduleDay]`, isLoading | `onDay` | completed (filled disc), planned (outline), missed (dashed outline + slash), rescheduled (outline + arrow), rest, two sessions, today, nothing planned, loading |
| Cards | `CyCompactSportCard`, `CyGradientBar` | HomeV21Components.swift | `CySportCardModel?` | `onOpen` | normal, not in the plan, no data yet, loading |
| Sleep | `CySleepBar` (borderless) | HomeV21Components.swift | `CySleepModel?` (last night, 7-day average, target, target source) | `onOpen` | normal, no data, loading |
| Coach | `CyCoachBanner` | HomeV21Components.swift | `CyCoachBannerModel?`, emptyText, `CyCoachDecision` | `onWhy`, `onReview`, `onNotNow` | pending, postponed, accepted, declined, no proposal, empty, loading |
| Setup | `CySetupBanner` | HomeV21Components.swift | `[CySetupStep]` (required / optional) | `onStep` | required step open (next action), all steps list, complete (one line), expand / collapse |
| Trends | `CyTrendsModule` | TrendsAndDock.swift | `[CyTrendRange]`, isLoading, emptyText | `onInfo`, `onDay` | 7 days, 4 weeks, selected day + tooltip, empty, loading, large text (single-letter labels) |
| Metrics | `CyMetricGrid` | TrendsAndDock.swift | `[CyMetricTile]`, isLoading | `onTile` | populated, missing ("—" / "No data"), loading, one column at large text |
| Navigation | `CyFloatingDock` | TrendsAndDock.swift | selection binding, four `CyDockItem`s, centre title / icon / badge | `onCentre` | floating capsule, sliding highlight, raised centre action, six themes |

Superseded on Home (kept in the library and gallery, not deleted): `CyRing` / `CyRingRow`, `CyWeekStrip`,
`CyTrainingSummaryCard`, `CyCoachInsightCard`, `CyGettingStartedCard`, `CyTrendChart`, `CyTabBar`.

## Screens

| Screen | File | Status |
|---|---|---|
| Home v2.1 | Screens/Home21Screen.swift (+ Sheets21.swift for the local detail sheets) | Prototype built, awaiting review. The v2 screen file was replaced; it remains in the branch history |
| Lab (theme and scenario switches, gallery index) | Screens/Gallery.swift | Prototype tool, not a product screen |
| Component gallery (7 pages, incl. "Home v2.1 components") | Screens/Gallery.swift | Prototype tool |
| Plan, Training Hub, Progress, Profile, Onboarding | — | **Not started** (each waits for the previous approval) |
