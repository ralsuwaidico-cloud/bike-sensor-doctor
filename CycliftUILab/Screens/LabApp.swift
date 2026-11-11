import SwiftUI

// Cyclift UI Lab — standalone prototype shell (Home v2.1). Mock navigation and local sheets only.
// Nothing here talks to the production app, Apple Health, sensors, accounts or any backend.

/// Launch options (environment variables) used by the prototype's own screenshot script.
enum LabConfig {
    static let env = ProcessInfo.processInfo.environment
    static var theme: CyThemeID? { env["LAB_THEME"].flatMap(CyThemeID.init(rawValue:)) }
    static var scenario: LabScenario? { env["LAB_SCENARIO"].flatMap(LabScenario.init(rawValue:)) }
    static var screen: String { env["LAB_SCREEN"] ?? "home" }          // home | lab | gallery | plan
    static var page: String? { env["LAB_PAGE"] }                        // gallery page id
    static var scroll: String? { env["LAB_SCROLL"] }                    // cards | coach | trends | metrics | bottom
    static var sheet: String? { env["LAB_SHEET"] }
    static var select: Int? { env["LAB_SELECT"].flatMap(Int.init) }     // chart day selected at launch
    static var render: Bool { env["LAB_RENDER"] == "1" }                // write a full-length Home image to Documents
    static var decision: String? { env["LAB_DECISION"] }
    static var metrics: CyMetricStyle? { env["LAB_METRICS"].flatMap(CyMetricStyle.init(rawValue:)) }                // accepted | declined | postponed
}

@main
struct CycliftUILabApp: App {
    var body: some Scene {
        WindowGroup { LabRoot() }
    }
}

enum LabSheet: Identifiable {
    case consistency, mix, recovery, sleep, coachWhy, review, trendsInfo, hub, profile
    case day(CyScheduleDay), sport(CySportCardModel), trendDay(CyTrendDay), metric(CyMetricTile)
    var id: String {
        switch self {
        case .consistency: return "consistency"
        case .mix: return "mix"
        case .recovery: return "recovery"
        case .sleep: return "sleep"
        case .coachWhy: return "coachWhy"
        case .review: return "review"
        case .trendsInfo: return "trendsInfo"
        case .hub: return "hub"
        case .profile: return "profile"
        case .day(let d): return "day-\(d.id)"
        case .sport(let s): return "sport-\(s.title)"
        case .trendDay(let d): return "trendDay-\(d.full)"
        case .metric(let m): return "metric-\(m.id)"
        }
    }
    var opensLarge: Bool {
        switch self {
        case .review, .sleep, .mix, .consistency: return true
        default: return false
        }
    }
}

struct LabRoot: View {
    @AppStorage("lab.theme") private var themeRaw: String = CyThemeID.obsidian.rawValue
    @AppStorage("lab.metrics") private var metricsRaw: String = CyMetricStyle.rows.rawValue
    @State private var scenario: LabScenario = LabConfig.scenario ?? .established
    @State private var data: Home21Data = Mock21.make(LabConfig.scenario ?? .established)
    @State private var tab: Int = LabRoot.initialTab
    @State private var sheet: LabSheet? = nil
    @State private var toast: String? = nil
    @State private var decision: CyCoachDecision = LabRoot.initialDecision

    private static var initialTab: Int {
        switch LabConfig.screen {
        case "home": return 0
        case "plan": return 1
        case "progress": return 3
        default: return 4
        }
    }
    private static var initialDecision: CyCoachDecision {
        switch LabConfig.decision {
        case "accepted": return .accepted
        case "declined": return .declined
        case "postponed": return .postponed
        default: return .none
        }
    }

    private var themeID: CyThemeID { LabConfig.theme ?? CyThemeID(rawValue: themeRaw) ?? .obsidian }
    private var theme: CyTheme { CyTheme.named(themeID) }
    private let dockHeight: CGFloat = 76

    private let dockItems = [
        CyDockItem(id: 0, title: "Home", icon: "house.fill"),
        CyDockItem(id: 1, title: "Plan", icon: "calendar"),
        CyDockItem(id: 3, title: "Progress", icon: "chart.xyaxis.line"),
        CyDockItem(id: 4, title: "Profile", icon: "person.crop.circle"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            LinearGradient(colors: [theme.background.opacity(0), theme.background.opacity(0.92), theme.background], startPoint: .top, endPoint: .bottom)
                .frame(height: dockHeight + 34).ignoresSafeArea(edges: .bottom).allowsHitTesting(false).accessibilityHidden(true)
            VStack(spacing: CySpace.s) {
                if let toast {
                    Text(toast).font(CyFont.caption).foregroundStyle(theme.textPrimary).multilineTextAlignment(.center)
                        .padding(.horizontal, CySpace.l).padding(.vertical, CySpace.m)
                        .background(Capsule().fill(theme.surface2))
                        .overlay(Capsule().strokeBorder(theme.border, lineWidth: theme.borderWidth))
                        .padding(.horizontal, CySpace.l)
                        .transition(.opacity)
                        .accessibilityAddTraits(.isStaticText)
                }
                CyFloatingDock(selection: $tab, items: dockItems, centreTitle: "Train now", centreIcon: "figure.mixed.cardio",
                               centreBadge: scenario == .loading ? nil : data.sessionsToday) { sheet = .hub }
            }
        }
        .background(theme.background.ignoresSafeArea())
        .environment(\.cyTheme, theme)
        .preferredColorScheme(theme.scheme)
        .tint(theme.accent)
        .sheet(item: $sheet) { s in
            sheetView(s)
                .environment(\.cyTheme, theme)
                .presentationDetents(s.opensLarge ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            applyLaunchSheet()
            if LabConfig.render { Task { @MainActor in try? await Task.sleep(nanoseconds: 1_200_000_000); renderFullLength() } }
        }
        .onChange(of: scenario) { _, new in data = Mock21.make(new); decision = .none }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case 0:
            Home21Screen(data: data, isLoading: scenario == .loading, coachDecision: decision, scrollTo: LabConfig.scroll,
                         initialTrendSelection: LabConfig.select, bottomInset: dockHeight,
                         metricStyle: LabConfig.metrics ?? CyMetricStyle(rawValue: metricsRaw) ?? .rows, actions: homeActions)
        case 4:
            LabScreen(themeRaw: $themeRaw, scenario: $scenario, lockedTheme: LabConfig.theme, bottomInset: dockHeight)
        default:
            PlaceholderScreen(title: dockItems.first { $0.id == tab }?.title ?? "", bottomInset: dockHeight)
        }
    }

    private var homeActions: Home21Actions {
        Home21Actions(
            onAvatar: { sheet = .profile },
            onConsistency: { sheet = .consistency },
            onMix: { sheet = .mix },
            onRecovery: { sheet = .recovery },
            onStep: { step in
                // Local mock: marks the step done, so the move from "below the indicators" to the bottom can be reviewed.
                if let i = data.steps.firstIndex(where: { $0.id == step.id }) { withAnimation { data.steps[i].isDone.toggle() } }
            },
            onDay: { sheet = .day($0) },
            onEndurance: { sheet = .sport(data.endurance) },
            onStrength: { sheet = .sport(data.strength) },
            onSleep: { sheet = .sleep },
            onCoachWhy: { sheet = .coachWhy },
            onCoachReview: { sheet = .review },
            onCoachNotNow: { decision = .postponed; say("Postponed. This is not a decline — it stays open.") },
            onTrendsInfo: { sheet = .trendsInfo },
            onTrendDay: { sheet = .trendDay($0) },
            onMetric: { sheet = .metric($0) })
    }

    private func say(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { if toast == text { toast = nil } } }
    }

    private func applyLaunchSheet() {
        guard let s = LabConfig.sheet else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            switch s {
            case "consistency": sheet = .consistency
            case "mix": sheet = .mix
            case "recovery": sheet = .recovery
            case "sleep": sheet = .sleep
            case "review": sheet = .review
            case "coachWhy": sheet = .coachWhy
            case "trendsInfo": sheet = .trendsInfo
            case "hub": sheet = .hub
            case "profile": sheet = .profile
            case "day": if data.days.count > 2 { sheet = .day(data.days[2]) }
            case "endurance": sheet = .sport(data.endurance)
            case "strength": sheet = .sport(data.strength)
            case "trendDay": if let d = data.trends.first?.days.dropFirst(2).first { sheet = .trendDay(d) }
            case "metric": if let m = data.metrics.first { sheet = .metric(m) }
            default: break
            }
        }
    }

    /// Review aid only: renders the whole Home column to one tall image in the prototype's own Documents folder.
    @MainActor func renderFullLength() {
        let width: CGFloat = UIScreen.main.bounds.width
        let view = Home21Content(data: data, isLoading: scenario == .loading, coachDecision: decision, initialTrendSelection: LabConfig.select,
                                 metricStyle: LabConfig.metrics ?? CyMetricStyle(rawValue: metricsRaw) ?? .rows)
            .padding(.vertical, CySpace.l)
            .frame(width: width)
            .background(theme.background)
            .environment(\.cyTheme, theme)
            .environment(\.colorScheme, theme.scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        guard let image = renderer.uiImage, let png = image.pngData(),
              let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? png.write(to: dir.appendingPathComponent("home-full.png"))
    }

    @ViewBuilder private func sheetView(_ s: LabSheet) -> some View {
        let close: () -> Void = { sheet = nil }
        switch s {
        case .consistency: ConsistencySheet(model: data.consistency, days: data.days, onClose: close)
        case .mix: MixSheet(model: data.mix, endurance: data.endurance, strength: data.strength, onClose: close)
        case .recovery: RecoverySheet(model: data.recovery, onClose: close)
        case .sleep: SleepSheet(model: data.sleep, onClose: close)
        case .day(let d): DaySheet(day: d, onClose: close) { say("Sample only — the session would open in the app.") }
        case .sport(let m): SportSheet(model: m, onClose: close)
        case .trendDay(let d): TrendDaySheet(day: d, onClose: close)
        case .metric(let m): MetricSheet(tile: m, onClose: close)
        case .trendsInfo:
            CySheet(title: "How Trends works", onClose: close) {
                InfoBlock(head: "What the chart shows", text: "Recorded training minutes per day: endurance and strength, stacked. Time still planned is drawn as a faint bar. One unit, labelled on the chart.")
                InfoBlock(head: "What it does not show", text: "No recovery, stress or readiness score. Recovery and sleep for a day appear as words and durations when you touch that day — only when a reading exists.")
                InfoBlock(head: "Missing days", text: "A day with nothing recorded or planned is left empty and says \"No data\". Nothing is estimated.")
            }
        case .coachWhy:
            CySheet(title: "Why this suggestion?", onClose: close) {
                Text(data.coach?.why ?? "No suggestion at the moment.").font(CyFont.body).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text("The coach follows written rules. No generative AI model is used. Sample text for layout review.").font(.caption2).foregroundStyle(theme.textTertiary)
            }
        case .review:
            CyReviewSheet(title: "Review the suggestion",
                          reason: "Two sessions in a row reached the top of the rep range at a reported effort of 7 out of 10.",
                          benefit: "A small step keeps the work challenging without changing the session.",
                          impact: "The last sets may feel harder for a week or two. You can undo this at any time.",
                          changes: MockData.changes,
                          onApprove: { sheet = nil; decision = .accepted; say("Accepted (sample). Nothing real was changed.") },
                          onPostpone: { sheet = nil; decision = .postponed; say("Postponed. This is not a decline — it stays open.") },
                          onDecline: { sheet = nil; decision = .declined; say("Declined (sample). It will not be repeated.") })
        case .hub:
            CySheet(title: "Train now", onClose: close) {
                Text("Mock destination. The Training Hub is prototyped after Home and Plan are approved.").font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                ForEach(data.days.first { $0.isToday }?.sessions ?? []) { s in
                    CyWorkoutCard(model: CyWorkoutModel(category: s.category, title: s.title, detail: s.detail, status: s.state == .completed ? .done : .today),
                                  actionTitle: s.state == .completed ? "Results" : "Start", onAction: { say("Sample only.") }, onOpen: {})
                }
            }
        case .profile:
            CySheet(title: "Profile", onClose: close) {
                HStack(spacing: CySpace.m) {
                    Text(data.initials).font(CyFont.title).foregroundStyle(theme.accent).frame(width: 56, height: 56).background(Circle().fill(theme.accentSubtle))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(data.name).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        Text(data.athleteType ?? "Athlete").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                    }
                }
                Text("Mock profile. In the prototype the Profile tab holds the UI Lab: themes, scenarios and the component gallery.").font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                CyButton(title: "Open Profile and UI Lab", kind: .secondary) { sheet = nil; tab = 4 }
            }
        }
    }
}

struct PlaceholderScreen: View {
    let title: String
    var bottomInset: CGFloat = 0
    @Environment(\.cyTheme) private var theme
    var body: some View {
        VStack(spacing: CySpace.l) {
            Spacer()
            CyEmptyStateCard(icon: "hammer", title: "\(title) is not prototyped yet",
                             message: "Mock destination. Screens are built one at a time; this one starts after Home has been reviewed and approved.")
            Spacer()
        }
        .padding(CySpace.l)
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
    }
}
