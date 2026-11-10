# Home v2 — Stage A: inventory and implementation map (no code changed)

**Spec:** "CYCLIFT — HOME v2 — Final UI/UX Design & Implementation Specification" (owner, 10 Nov 2026).
**Baseline:** TestFlight 216 (`fb52ae27`), `impl/checkpoint-f-ride`. **Status:** pre‑implementation deliverables only —
coding starts when the owner confirms the scope below (spec §18).

## 1. Current Home component inventory (what exists today)

| Spec section | Today's component | File · symbol | Data source | Reuse / modify / new |
|---|---|---|---|---|
| §3 header | Three‑line header (date, greeting, context "Hybrid · week 1 · lift today") + avatar → Profile | `HomeDashboardView.header`, `HomeDashboard.Header` (`HomeDashboardModel.swift`) | profile name, `Date()`, plan mode/week | **Modify**: drop the context line, two compact lines, keep `homeAvatar` |
| §4 circles | One weekly‑completion ring card ("3 of 5 sessions") → week overview | `ringCard`, `HomeDashboard.Ring`, `CyDesign.ringFraction` | `homeWeekOverview` (done / planned / missed / skipped, plan start, rest days) | **Replace** by three rings; the Ring's adherence rules become **Consistency** |
| §4.3 Load Balance | nothing on Home; engine has acute/chronic load + ACWR | `TrainingAnalysis.acuteLoad / chronicWeeklyLoad / acwr` (`AdaptationEngine.swift`), `AdaptiveModels.acuteLoad/chronicLoad`, ride TSS (`PlanView` Timeline), strength volume (`ProgressAnalytics`) | sessions of the last 35 days, ratings, HR, verified power | **New derived status** (documented in §3 below), **reusing** the engine's numbers — no second calculation |
| §4.4 Recovery | Recovery card in the lower grid (advice title + 3 readings + freshness) → Recovery page | `recoveryCard`, `HomeDashboard.Recovery`, `RecoveryAnalysis.advice` (`RecoveryModel.swift`) | `Store.recoveryLog` (sleep / RHR / HRV / weight from Health) | **Reuse** engine and page; **new** ring presentation of the existing advice word |
| §5 schedule strip | Week card with 7 day cells + legend → Day page | `weekCard`, `legend`, `HomeDashboard.days: [CyDay]`, `CyDayStatus`, `CyDaySport` (`PureDesign.swift`) | plan + ledger | **Modify**: slim strip, icons per sport, multi‑session day, drop the legend; keep `homeDay-<n>` destinations and the Plan‑timeline accessibility lessons (day = real Button, no nested hit targets) |
| §6 training cards | Two sport tiles "Cycling" / "Strength" (value, unit, sub, source tag, 8‑week sparkline, "Weekly chart after 2 we…") → Progress | `sportTiles`, `miniChart`, `HomeDashboard.Tile` | `homeWeekOverview`, `ProgressAnalytics` | **Modify**: rename Endurance / Strength Load, one primary number, planned context, no clipped captions, sparkline only with ≥ 2 real weeks |
| §7 coach | Coach card (finding, action, Why?, Accept / Not now) | `coachCard`, `HomeCoachItem` (`HomeModel.swift`), `HomeWhySheet` | AdaptationEngine / HybridCoach proposals, applied changes | **Modify** into a one‑row insight; same item, same Why?, same actions behind it |
| §8 chart | none (Progress has trend charts; Recovery page has 28‑day bars) | `CyCharts.swift` (`CyBarChart`, trend charts), `LiveGraphView` | — | **New** combined chart component built on `CyCharts` |
| §10 checklist | Dynamic Getting‑started list (plan approved, first session, HR optional, Health optional) shown above everything; disappears when required steps done | `HomeSetupChecklist` (`HomeDetailPages.swift`), `HomeSetupItem` (`HomeSummaries.swift`) | plan, recordings, connections, Health setting | **Modify**: compact "n of m" header + expandable list, placement rule (top while essential incomplete, bottom after), "Setup complete" collapsed state; same items and completion logic |
| §11 themes | Light/dark neutral tokens + sport identities | `CyTheme` (`DesignSystem/CyTheme.swift`: canvas, card, card2, line, ink, ink2, ink3, identities cycling/strength/recovery/goal), `Theme.swift` (BC.*), `AppSettings.appearance` (system/light/dark) | — | **New** six themes as token sets over the existing `CyTheme` names; selector in Profile › Settings › Appearance |
| Lower grid extras | Goal card (→ Goal page), Reminder card ("Strength · 30 min · Open the Training Hub") | `goalCard`, `reminderCard` | goals, today's plan | **Keep destinations**, present inside the schedule/cards per §2 ("secondary information stays reachable"); reminder folds into the Coach row / hub |

Not on Home and **out of scope** (spec §1): Plan, Progress, Profile, Training Hub (`TrainingHubView` stays as is), live workout screens.

**Loss to record:** the earlier Checkpoint‑H appearance work (`impl/checkpoint-h-appearance`: six Cyclift/Sport/Bloom
families, grading rules, tests) existed only in the session's local workspace and was **lost when the platform replaced
the container on 10 Nov**; it was never pushed. The Home v2 spec names a different six (Obsidian, Arctic, Ocean, Forest,
Sandstone, High Contrast), so the theme layer is rebuilt to the new spec rather than recovered. **Conflict to resolve:**
the Watch design v2 documents (`watch/docs/*`, handover 04_) use the old six names; the new iPhone set should become the
shared identity (spec §11) and the watch design docs updated by the hardware‑design conversation — a documentation
change, no firmware.

## 2. Proposed Home component tree (v2)

```
HomeDashboardScreen (ScrollView, same ids where they exist)
├─ HomeHeaderCompact              "Tuesday, 10 Nov" / "Good afternoon, Rashed"   · homeAvatar → Profile
├─ HomeMetricRings (HStack)        Consistency 1.0 · Load Balance 1.15 · Recovery 1.0   (each a real Button)
│    ├─ CyMetricRing(value/status, label, fraction?, tint token)           ids: homeRingConsistency / homeRingLoad / homeRingRecovery
│    └─ destinations: homeWeekOverview · HomeLoadBalanceDetail (new, reuses adjustments + recovery sections) · homeRecoveryPage
├─ HomeSetupCompact (only while an essential step is open)                 id homeSetup → existing destinations
├─ HomeWeekStrip                   Mon…Sun icons (bike / dumbbell / moon, stacked when > 1), status dots, today ring
│    └─ 7 × Button homeDay-<weekday> → Day page (no nested hit targets)
├─ HomeSportCards (HStack, equal height)
│    ├─ Endurance card    "1 h 17 min" · "of 2 h planned" · "23.2 km" · sparkline if ≥ 2 real weeks   → Progress (cycling)
│    └─ Strength Load card "2 of 3" · "sessions completed" · volume as supporting line when present   → Progress (strength)
├─ HomeCoachRow                    "Cyclift Coach ✦ · one sentence · Why?"  → HomeWhySheet / Accept / Not now (existing)
├─ HomeTrendsChart "Training & Recovery"   7‑day default; 30‑day only with ≥ 30 days of plan history
│    ├─ Consistency: % per day‑to‑date (line, observed)
│    ├─ Load Balance: status band per day (categorical: below / balanced / elevated / needs data) — bands, not numbers
│    └─ Recovery: status marker per day (hold / as planned / watch / easier / no readings) — markers, not numbers
├─ HomeSetupCompact (bottom position once essential steps are done; collapsed "Setup complete")
└─ (goal, reminder: via Coach row and ring destinations; Goal page unchanged)
```

## 3. Data‑source and metric‑definition table

| Metric / element | Definition (reusing existing rules) | Source today | New code needed | Test plan |
|---|---|---|---|---|
| **Consistency** | completed eligible ÷ eligible planned this week × 100; eligible = training sessions dated ≥ plan start and ≤ today (rest days, beforePlan, future sessions excluded; skipped by the rider excluded from the denominator exactly as `homeWeekOverview` does). Denominator 0 → "No plan yet" / "Starts Mon" | `homeWeekOverview` (done, planned, missed, skipped), `CyDayStatus.beforePlan` | a `ConsistencyMetric` struct in `HomeDashboardModel` (pure) | HomeSummariesTests cases: before plan start, rest day, future session, missed, skipped, multiple sessions per day |
| **Load Balance** | status from the engine's numbers, documented: `acwr` (acute 7‑day ÷ chronic 4‑week mean) → *Below target* < 0.8 · *Balanced* 0.8–1.3 · *Elevated* > 1.3; **Needs data** when `chronicWeeklyLoad == nil` (< 3 weeks of history) or `usableRecent < 2`. Strength sessions enter the load as the engine already counts them (sessions with rating/HR); no new physiological claim. Thresholds live in one place and are shown on the detail page ("why Balanced") | `TrainingAnalysis.acwr`, `usableRecent` (AdaptationEngine), recovery advice as a second input only for the explanation text | `LoadBalanceMetric` (pure) over `TrainingAnalysis`; detail page reusing `AdjustmentsView` sections + recovery metric rows | AdaptationEngineTests: each band, insufficient data, strength‑only history, endurance‑only history |
| **Recovery** | the existing `RecoveryAdvice` word (hold / trainAsPlanned / watch / easier); ring fraction = none (status ring: full for as‑planned, partial for watch/easier, dashed for hold); **No readings** when `RecoveryAnalysis.metrics` has no fresh reading | `RecoveryAnalysis.advice`, `RecoveryFreshness` | presentation only | RecoveryAnalysisTests already cover the words; UI test for "No readings" |
| **Week strip** | `CyDay` per weekday; sport icons from `CyDaySport` (+ a `sessions: [CyDaySport]` extension for multi‑session days); statuses as today | `HomeDashboard.days` | small model extension | HomeDashboardTests: multi‑session day, rest, missed, today |
| **Endurance card** | completed endurance minutes this week ÷ planned endurance minutes; distance this week; sparkline = weekly minutes of the last 8 weeks only if ≥ 2 weeks have data | `homeWeekOverview`, ride history (`ProgressAnalytics`) | rename + planned‑minutes field | HomeSummariesTests: no history, 1 week, ≥ 2 weeks |
| **Strength Load card** | sessions completed of planned this week (primary); supporting: weekly volume (sets × reps × kg) when logged | `homeWeekOverview`, `ProgressAnalytics` strength volume | rename + supporting line | same |
| **Coach row** | the current `HomeCoachItem` (one at a time, engine‑chosen, no regeneration on Home open) | `HomeModel.coachItem` | layout only | existing CoachCore/Adaptation tests + HomeNavigation Why test |
| **Trends chart** | per day of the window: Consistency % to date (observed), Load Balance status (categorical band), Recovery advice (categorical marker); missing = gap; derived vs observed labelled in the accessibility value | the three metric structs computed per past day from the ledger and recovery log | `HomeTrendSeries` builder (pure) + `CyCombinedTrendChart` | unit: categorical never mapped to numbers; gaps preserved; UI: accessibility values |
| **Getting Started** | items and completion exactly as `HomeSetupItem` today; essential = planApproved, firstSession; optional = heartRate, health (+ Apple Watch, power meter, notifications as optional rows if their state is known to `Connections`) | `HomeSummaries.setupItems` | placement rule + compact/expanded views; persisted collapse state in `AppSettings` | LaunchSmoke seeds: incomplete / complete; relaunch keeps state |
| **Theme** | six token sets (§11) over the existing `CyTheme` names; `AppSettings.homeTheme: CyThemeID` (default `.obsidian` unless saved) | `CyTheme`, `AppSettings.appearance` | token sets, selector, previews | DesignSystemAudit per theme; contrast ≥ 4.5:1 check in DesignSystemPureTests |

## 4. Unsupported or insufficient‑data metrics (explicit)

- **Age reduction / biological age** — not computed, not shown (spec §9); the chart leaves room for a future series.
- **Load Balance** will read **Needs data** for every rider with < 3 weeks of usable history (the engine's chronic baseline
  rule) — i.e. for new users for their first three weeks. This is expected and must be shown honestly.
- **Recovery** reads **No readings** without Apple Health reads enabled and at least one fresh sample.
- **Strength Load** is a session count, labelled "sessions completed"; volume appears only when sets were logged with weights.
- **Endurance sparkline** needs ≥ 2 weeks with recorded rides; otherwise a one‑line empty state, no decorative chart.
- **30‑day chart view** only when the plan has ≥ 30 days of history; otherwise the selector is not shown.
- Steps, calories, HRV‑based stress, SpO₂ etc. are not Home v2 inputs (see the 102‑feature audit).

## 5. Theme‑token mapping

Semantic tokens (new names, mapped onto today's `CyTheme` so other screens keep working unchanged):

| Semantic token (§11.1) | Today | Obsidian | Arctic | Ocean | Forest | Sandstone | High Contrast |
|---|---|---|---|---|---|---|---|
| background | `canvas` | near‑black | light cool white | deep navy | dark evergreen | warm off‑white | black / white (system contrast) |
| surface, surface2 | `card`, `card2` | dark grey steps | white / cool grey | navy steps | green‑grey steps | warm greys | pure surfaces, strong separation |
| textPrimary / textSecondary | `ink`, `ink2` | — | — | — | — | — | maximum contrast pairs |
| accent (interactive) | per‑sport identity tints | cool steel accent | cool blue | teal | muted green | terracotta | system blue / yellow |
| separator, border | `line`, `line2` | — | — | — | — | — | visible 1 pt |
| selected / inactive | new | — | — | — | — | — | — |
| ring tracks + fills (consistency / load / recovery) | new (identities) | — | — | — | — | — | hatched fills + labels (never colour alone) |
| chart background / gridlines | new | — | — | — | — | — | — |
| empty state / warning | `recovery`/`goal` identities, `BC.stale` | — | — | — | — | — | — |

Exact hex values are chosen in Stage D with the contrast validator (`DesignSystemPureTests` WCAG check) — not invented here.
Training‑zone, completion and warning meanings keep their shapes/labels in every theme (§11.2). Theme ids are stable strings
(`obsidian`, `arctic`, `ocean`, `forest`, `sandstone`, `highContrast`) for the future watch mapping; no BLE/firmware change.

## 6. Implementation sequence and affected files

| Stage | Work | Files | Gate |
|---|---|---|---|
| **B1** header + rings | `HomeHeaderCompact`, `CyMetricRing`, `HomeMetricRings`, `ConsistencyMetric`, `LoadBalanceMetric`, `HomeLoadBalanceDetail` | `HomeDashboardView.swift`, `HomeDashboardModel.swift`, `DesignSystem/CyPrimitives.swift` (ring), new `HomeMetrics.swift`, `HomeDetailPages.swift` | unit tests for both metrics on the Linux harness; HomeNavigationTests ring destinations |
| **B2** strip + cards + coach row | `HomeWeekStrip`, `HomeSportCards`, `HomeCoachRow` | `HomeDashboardView.swift`, `HomeDashboardModel.swift`, `HomeSummaries.swift` (planned minutes, volume) | LayoutAudit on 4 sizes incl. AX3; HomeNavigationTests; Journey Home steps |
| **C1** trends chart | `HomeTrendSeries`, `CyCombinedTrendChart` | new `HomeTrends.swift`, `DesignSystem/CyCharts.swift` | unit: categorical never numeric, gaps; UI: accessibility values |
| **C2** Getting Started | compact/expanded, placement rule, persisted collapse | `HomeDetailPages.swift` (HomeSetupChecklist), `HomeSummaries.swift`, `Models.swift` (one `AppSettings` field) | LaunchSmoke incomplete/complete seeds + relaunch |
| **D** themes | `CyThemeID`, token sets, selector with previews in Profile › Settings › Appearance | `DesignSystem/CyTheme.swift`, `Models.swift` (`AppSettings.homeTheme`), `ProfileScreens.swift` | DesignSystemAudit `-BC_THEME <id>` × 6, contrast tests |
| **E** validation | all 18 acceptance scenarios (spec §16) as seeds; screenshots per theme, SE at AX3; before/after | `LayoutAudit.swift` seeds, `HomeNavigationTests`, new `HomeV2Tests` | full matrix green incl. flows; then TestFlight |

Branch: `impl/home-v2` from the build‑216 tree; merged to the release line only after Stage E. The current release process
(ios/checkpoint-f-ride, build 216) is untouched meanwhile.

## 7. Regression risks and how they are held

| Risk | Hold |
|---|---|
| Home identifiers used by 9 HomeNavigationTests, LayoutAudit, Journeys (`homeAvatar`, `homeDay-<n>`, `homeRecovery`, `homeWeekPlan`, `homeCoachAction`, `homeGoal`, `homeStrength`, `homeCycling`, `planRing`) | keep every existing id on its successor control; add new ids, never rename silently |
| Ring semantics: today's ring is "sessions done of planned" and the C2 Plan ring reuses the same numbers | Consistency uses the same `homeWeekOverview` numbers — no second adherence rule |
| Load Balance seen as a medical/validated measure | status words + explanation page listing inputs and thresholds; "Needs data" by default for new riders |
| Removing the legend and week card changes VoiceOver order | explicit `accessibilitySortPriority` and the Plan‑timeline pattern (real buttons, no nested targets); VoiceOver run on the owner's iPhone |
| Theme tokens leaking into other screens | tokens map onto existing `CyTheme` names; other screens read the same names so they stay coherent but are not redesigned (§11.5) |
| Getting Started state reset by the UI change | completion derived from plan/recording state as today; only the collapse flag is new |
| Chart implies continuous values for categorical data | bands/markers only; unit test asserts no numeric mapping of Load/Recovery |
| Schedule pressure on the release line | Home v2 on its own branch; build 216 line receives only defect fixes |

**Awaiting owner confirmation** of: this scope; the Load Balance thresholds (0.8 / 1.3, engine ACWR); the six new theme
names replacing the earlier six for the shared identity; default theme Obsidian for existing users.
