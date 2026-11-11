# Cyclift UI Lab — component inventory (Home v2 milestone)

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

## Screens

| Screen | File | Status |
|---|---|---|
| Home v2 | Screens/HomeV2Screen.swift | Prototype built, awaiting review |
| Lab (theme and scenario switches, gallery index) | Screens/Gallery.swift | Prototype tool, not a product screen |
| Component gallery (6 pages) | Screens/Gallery.swift | Prototype tool |
| Plan, Training Hub, Progress, Profile, Onboarding | — | **Not started** (each waits for the previous approval) |
