import SwiftUI

// MARK: - Design-system gallery (debug / UI-test builds only)
//
// Reached with the launch argument `-BC_DESIGN_GALLERY` (BikeComputerApp). Every component in every state with inputs
// that are clearly labelled DEMO — never used by production screens. The DesignSystemAudit UI test screenshots it in
// light/dark at L and AX3 on an iPhone SE and a standard iPhone and checks frames.

struct DesignSystemGallery: View {
    @State private var seg = 1
    @State private var tab = 0
    @State private var weight: Double = 24
    @State private var reps: Double = 10
    @State private var on = true
    @State private var strip: [CyDay] = DesignSystemGallery.demoWeek
    @Environment(\.dynamicTypeSize) private var type

    static let demoWeek: [CyDay] = [
        CyDay(id: 0, shortName: "Mon", longName: "Monday", sport: .strength, status: .done),
        CyDay(id: 1, shortName: "Tue", longName: "Tuesday", sport: .cycling, status: .done),
        CyDay(id: 2, shortName: "Wed", longName: "Wednesday", sport: .strength, status: .planned, isToday: true),
        CyDay(id: 3, shortName: "Thu", longName: "Thursday", sport: .rest, status: .none),
        CyDay(id: 4, shortName: "Fri", longName: "Friday", sport: .strength, status: .planned),
        CyDay(id: 5, shortName: "Sat", longName: "Saturday", sport: .cycling, status: .missed),
        CyDay(id: 6, shortName: "Sun", longName: "Sunday", sport: .both, status: .planned),
    ]

    static var demoMonth: [CyMonthDay] {
        func sport(_ d: Int) -> CyDaySport {
            switch d % 7 {
            case 1, 4: return .strength
            case 2, 6: return .cycling
            default: return .rest
            }
        }
        func status(_ d: Int) -> CyDayStatus {
            if d == 8 { return .missed }
            return d < 10 ? .done : .planned
        }
        return CyDesign.monthGrid(year: 2026, month: 11, today: nil, sportFor: sport, statusFor: status)
    }
    static var demoIntervals: [CyIntervalStep] {
        let intensity: [Double] = [0.3, 0.3, 0.6, 0.4, 0.8, 0.4, 0.8, 0.4, 0.8, 0.4, 0.3, 0.2]
        var out: [CyIntervalStep] = []
        for i in 0..<intensity.count {
            let state: CyIntervalStep.State = i < 4 ? .past : (i == 4 ? .current : .future)
            out.append(CyIntervalStep(id: i, intensity: intensity[i], duration: i == 0 ? 2 : 1, state: state))
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CyBanner(kind: .info, text: "DEMO — design-system gallery. Every value below is a sample; nothing here is athlete data.", systemImage: "paintpalette")
                    .accessibilityIdentifier("galleryBanner")

                section("Tags") {
                    FlowRow(spacing: 6) { ForEach(SourceTag.allCases, id: \.self) { CySourceTagBadge(tag: $0) } }
                }
                section("Buttons") {
                    CyPrimaryButton(title: "Start workout", systemImage: "play.fill") {}
                        .accessibilityIdentifier("galleryPrimary")
                    CyPrimaryButton(title: "Start ride", systemImage: "play.fill", sport: .cycling) {}
                    CyPrimaryButton(title: "Disabled", isEnabled: false) {}
                    CySecondaryButton(title: "Choose another workout") {}
                        .accessibilityIdentifier("gallerySecondary")
                    HStack { CyTertiaryLink(title: "See Progress") {}; Spacer() }
                }
                section("Segmented control") {
                    CySegmentedControl(options: [(0, "Cycling"), (1, "Strength"), (2, "Hybrid")], selection: $seg)
                        .accessibilityIdentifier("gallerySegmented")
                    CySegmentedControl(options: [(0, "4 wk"), (1, "8 wk"), (2, "12 wk"), (3, "1 yr")], selection: $seg)
                }
                section("Chips") {
                    FlowRow(spacing: 6) {
                        CyChip(title: "Endurance", systemImage: "bicycle", selected: true, sport: .cycling, star: true) {}
                        CyChip(title: "Build muscle", systemImage: "dumbbell", selected: true, sport: .strength) {}
                        CyChip(title: "Climbing", systemImage: "bicycle") {}
                        CyChip(title: "Bodyweight", selected: true) {}
                    }
                }
                section("Rows") {
                    CyRowGroup {
                        CyListRow(title: "Goals", value: "Endurance +1", systemImage: "target", sport: .goal) {}
                        CyDivider()
                        CyListRow(title: "Your week", value: "5 days", systemImage: "calendar", sport: .cycling) {}
                        CyDivider()
                        CyListRow(title: "FTP", value: "Unknown", systemImage: "bolt", sport: .cycling) {}
                        CyDivider()
                        CyListRow(title: "Static row", value: "no action", systemImage: "info.circle")
                        CyDivider()
                        CySwitchRow(title: "Supersets", caption: "Pair exercises to save time", isOn: $on)
                    }
                }
                section("Steppers") {
                    HStack(spacing: 10) {
                        CyStepper(title: "Weight", value: $weight, step: 2, range: 0...300, unit: "kg")
                        CyStepper(title: "Reps", value: $reps, step: 1, range: 0...50, unit: "reps")
                    }
                }
                section("Hero ring") {
                    CyHeroRingCard(caption: "This week", title: "You're on track", done: 3, planned: 5, ridesDone: 1, ridesPlanned: 2, liftsDone: 2, liftsPlanned: 3)
                    CyHeroRingCard(caption: "This week", title: "Week 1 starts today", done: 0, planned: 4, ridesDone: 0, ridesPlanned: 2, liftsDone: 0, liftsPlanned: 2)
                }
                section("Metric tiles") {
                    tileGrid {
                        CyMetricTile(title: "Cycling", systemImage: "bicycle", sport: .cycling, value: "58", unit: "min", sub: "of 2h planned", tag: .measured) {
                            CySparkline(values: [40, 55, 48, 70, 62, 58], tint: CyTheme.cycling.tint, fill: CyTheme.cycling.soft).frame(height: 36)
                        }
                        CyMetricTile(title: "Strength", systemImage: "dumbbell", sport: .strength, value: "1", unit: "/ 3", sub: "sessions · 31m lifted", tag: .logged) {
                            CyBarChart(values: [2, 3, 2, 3, 1, 3, 2, 1], highlighted: 7, tint: CyTheme.strength.tint, soft: CyTheme.strength.soft, minimumPoints: 3, height: 36)
                        }
                    }
                    tileGrid {
                        CyMetricTile(title: "FTP", systemImage: "bolt", sport: .cycling, value: nil, sub: "No watts are guessed", tag: .unknown)
                        CyMetricTile(title: "Est. 1RM", systemImage: "dumbbell", sport: .strength, value: "32", unit: "kg", sub: "Brzycki · RPE ≥ 8", tag: .estimated)
                    }
                    tileGrid {
                        CyMetricTile(title: "Longest ride", value: "75", unit: "min", sub: "last 8 weeks", tag: .measured)
                        CyMetricTile(title: "Resting HR", value: nil, sub: "Needs Apple Health permission", tag: .needsData)
                    }
                }
                section("Bar chart") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Riding time per week").font(CyType.section).foregroundStyle(CyTheme.ink)
                        CyBarChart(values: [1.6, 2, 1.2, 2, 1.8, 2.1, 1.9, 1], labels: ["14", "21", "28", "5", "12", "19", "26", "now"], highlighted: 6, planLine: 2, unit: "h", valueText: { String(format: "%.1fh", $0) })
                        CyBarChart(values: [1.6, nil, nil, nil, nil, nil, nil, nil], labels: [], minimumPoints: 3)
                    }
                    .padding(16).cyCard()
                }
                section("Week strip") {
                    CyCalendarStrip(days: strip) { d in
                        if let i = strip.firstIndex(where: { $0.id == d.id }) { strip[i].sport = strip[i].sport.next(allowBoth: true) }
                    }
                    CyCalendarStrip(days: Self.demoWeek)
                }
                section("Month calendar") {
                    CyMonthCalendar(cells: Self.demoMonth)
                        .padding(12).cyCard()
                }
                section("Session cards") {
                    CySessionCard(sport: .strength, caption: "Today", title: "Full body B", meta: "30 min · Moderate · supersets", detail: "Strength day 2 of 3 — 48 h after Monday's lift", actionTitle: "Start workout", action: {}, onOpen: {})
                    CySessionCard(sport: .recovery, caption: "Today · rest", title: "Recover for Fri", meta: "Tomorrow: Full body C · 30 min")
                    CySessionCard(sport: .cycling, caption: "Missed · Sat", title: "Long ride", meta: "2 h · Easy · Zone 2", actionTitle: "Reschedule", action: {})
                }
                section("Goal indicator") {
                    CyGoalIndicatorCard(goal: "Endurance", isMain: true, indicator: "Weekly riding time", value: "1h 58m", sub: "4-week average · plan 2h", progress: 0.98, tag: .measured)
                    CyGoalIndicatorCard(goal: "Build muscle", indicator: "Working sets per week", value: nil, sub: "Needs 2 more logged sessions", tag: .needsData)
                }
                section("Coach") {
                    CyCoachCard(question: "Why today's workout?", answers: [
                        CyCoachAnswer(id: 1, text: "Strength day 2 of 3 — 48 h after Monday's lift.", source: "Planner rationale · days, session length"),
                        CyCoachAnswer(id: 2, text: "Supersets keep it to 30 min.", source: "Your week · supersets on", tag: .logged),
                        CyCoachAnswer(id: 3, text: "Tomorrow is rest, so Saturday's ride stays fresh.", source: "Recovery spacing rule"),
                    ])
                }
                section("Device states") {
                    FlowRow(spacing: 8) { ForEach(CyDeviceState.allCases, id: \.self) { CyDeviceStateBadge(state: $0, detail: $0 == .connected ? "Last synced 2 min ago" : nil) } }
                }
                section("Banners and states") {
                    CyBanner(kind: .warn, text: "Heart-rate strap lost — effort targets until it reconnects.")
                    CyBanner(kind: .bad, text: "BikeComputer connection problem. The ride keeps recording on the phone.")
                    CyBanner(kind: .success, text: "Plan approved — it's on Home and Plan.")
                    CyOfflineBanner()
                    CyEmptyState(systemImage: "chart.xyaxis.line", title: "No rides recorded yet", line: "Your first ride will appear here with heart rate or effort, never guessed watts.", actionTitle: "Start a ride", action: {})
                    CyInsufficientDataState(missing: 2, unit: "ride", detail: "FTP trends need two tests or 20-minute efforts with power.")
                }
                section("Live ride") {
                    tileGrid {
                        CyLiveMetric(title: "Heart rate", systemImage: "heart", value: "148", unit: "bpm", tag: .measured, hero: true, tint: CyTheme.strength.tint)
                        CyLiveMetric(title: "Power", systemImage: "bolt", value: nil, unit: "W", tag: .unknown)
                    }
                    CyIntervalTimeline(steps: Self.demoIntervals)
                        .padding(12).cyCard()
                }
                section("Rest timer") {
                    HStack { Spacer(); CyRestTimerRing(remaining: 48, total: 90); Spacer() }
                }
                section("Tab bar") {
                    CyFloatingTabBar(items: [CyTabItem(id: 0, title: "Home", systemImage: "house"), CyTabItem(id: 1, title: "Plan", systemImage: "calendar"), CyTabItem(id: 2, title: "Progress", systemImage: "chart.xyaxis.line"), CyTabItem(id: 3, title: "Profile", systemImage: "person")], selection: $tab) {}
                }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, CyTheme.margin)
            .padding(.top, 8)
            .frame(maxWidth: CyTheme.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(CyTheme.canvas.ignoresSafeArea())
        .navigationTitle("Design system")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("designGallery")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(CyType.section).foregroundStyle(CyTheme.ink).accessibilityAddTraits(.isHeader)
            content()
        }
    }
    /// Two columns normally, one column at accessibility sizes (so tiles never clip).
    @ViewBuilder private func tileGrid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if type.isAccessibilitySize {
            VStack(spacing: 10) { content() }
        } else {
            HStack(alignment: .top, spacing: 10) { content() }
        }
    }
}

/// Root used when the app is launched with `-BC_DESIGN_GALLERY`: the gallery with a scheme toggle.
struct DesignSystemGalleryRoot: View {
    @State private var dark: Bool
    init(dark: Bool) { _dark = State(initialValue: dark) }
    var body: some View {
        NavigationStack {
            DesignSystemGallery()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dark.toggle() } label: { Image(systemName: dark ? "sun.max" : "moon") }
                            .accessibilityLabel(dark ? "Light theme" : "Dark theme")
                            .accessibilityIdentifier("galleryTheme")
                    }
                }
        }
        .preferredColorScheme(dark ? .dark : .light)
    }
}
