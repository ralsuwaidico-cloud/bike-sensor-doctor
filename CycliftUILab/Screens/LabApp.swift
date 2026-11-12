import SwiftUI

// Cyclift UI Lab — standalone prototype shell (Home v2.3). Mock navigation and local sheets only.
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
    static var stress: String? { env["LAB_STRESS"] }                    // queued | direct — sheet transition self-test
    static var graphMode: String? { env["LAB_GRAPH_MODE"] }             // recovery | activity | trends
    static var graphRange: String? { env["LAB_GRAPH_RANGE"] }           // 7d | 4w                // accepted | declined | postponed
}

@main
struct CycliftUILabApp: App {
    var body: some Scene {
        WindowGroup { LabRoot() }
    }
}

enum LabSheet: Identifiable {
    case consistency, mix, recovery, sleep, trendsInfo, hub, profile
    case day(CyScheduleDay), sport(CySportCardModel), graphDay(CyGraphDate, [CyTrendDetailRow]), metric(CyMetricTile)
    var id: String {
        switch self {
        case .consistency: return "consistency"
        case .mix: return "mix"
        case .recovery: return "recovery"
        case .sleep: return "sleep"
        case .trendsInfo: return "trendsInfo"
        case .hub: return "hub"
        case .profile: return "profile"
        case .day(let d): return "day-\(d.id)"
        case .sport(let s): return "sport-\(s.title)"
        case .graphDay(let d, _): return "graphDay-\(d.full)"
        case .metric(let m): return "metric-\(m.id)"
        }
    }
    var opensLarge: Bool {
        switch self {
        case .sleep, .mix, .consistency: return true
        default: return false
        }
    }
}

struct LabRoot: View {
    @AppStorage("lab.theme") private var themeRaw: String = CyThemeID.obsidian.rawValue
    @State private var scenario: LabScenario = LabConfig.scenario ?? .established
    @State private var data: Home21Data = Mock21.make(LabConfig.scenario ?? .established)
    @State private var tab: Int = LabRoot.initialTab
    @State private var sheet: LabSheet? = nil
    // Sheet presentation guard (v2.3). SwiftUI can drop a sheet that is requested while the previous one is still
    // animating away, leaving the state set with nothing on screen. Requests made in that window are queued and
    // presented when the dismissal has finished; a request made while a sheet is already up is ignored.
    @State private var sheetBusy = false
    @State private var pendingSheet: LabSheet? = nil
    @State private var visibleSheet: String? = nil
    @State private var stressResult: String? = nil
    @State private var toast: String? = nil
    @State private var conversation: CyCoachConversation = LabRoot.initialConversation
    @State private var showCoach: Bool = LabConfig.screen == "coach"

    private static var initialTab: Int {
        switch LabConfig.screen {
        case "home", "coach": return 0
        case "plan": return 1
        case "progress": return 3
        default: return 4
        }
    }
    /// Sample conversation; LAB_DECISION pre-applies a decision to the open proposal (screenshots only).
    private static var initialConversation: CyCoachConversation {
        let sc = LabConfig.scenario ?? .established
        var c = Mock21.conversation(sc, Mock21.make(sc))
        switch LabConfig.decision {
        case "accepted": c.decide("load", .accepted, day: Mock21.today, time: "12:30")
        case "declined": c.decide("load", .declined, day: Mock21.today, time: "12:30")
        case "postponed": c.decide("load", .postponed, day: Mock21.today, time: "12:30")
        default: break
        }
        return c
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
                if let stressResult {
                    Text(stressResult).font(.caption2).foregroundStyle(theme.textPrimary).padding(8).background(theme.surface2)
                        .accessibilityIdentifier("stressResult")
                }
                if let toast {
                    Text(toast).font(CyFont.caption).foregroundStyle(theme.textPrimary).multilineTextAlignment(.center)
                        .padding(.horizontal, CySpace.l).padding(.vertical, CySpace.m)
                        .background(Capsule().fill(theme.surface2))
                        .overlay(Capsule().strokeBorder(theme.border, lineWidth: theme.borderWidth))
                        .padding(.horizontal, CySpace.l)
                        .transition(.opacity)
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityIdentifier("toast")
                }
                CyFloatingDock(selection: $tab, items: dockItems, centreTitle: "Train now", centreIcon: "figure.mixed.cardio",
                               centreBadge: scenario == .loading ? nil : data.sessionsToday) { present(.hub) }
            }
        }
        .background(theme.background.ignoresSafeArea())
        .environment(\.cyTheme, theme)
        .preferredColorScheme(theme.scheme)
        .tint(theme.accent)
        .sheet(item: $sheet, onDismiss: sheetDismissed) { s in
            sheetView(s)
                .onAppear { visibleSheet = s.id }
                .onDisappear { if visibleSheet == s.id { visibleSheet = nil } }
                .environment(\.cyTheme, theme)
                .presentationDetents(s.opensLarge ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showCoach) {
            CoachConversationScreen(conversation: $conversation, today: Mock21.today,
                                    initialProposal: LabConfig.sheet == "proposal" ? "load" : (LabConfig.sheet == "proposalClosed" ? "ride" : nil),
                                    startAtTop: LabConfig.scroll == "top",
                                    onClose: { showCoach = false })
                .environment(\.cyTheme, theme)
        }
        .onAppear {
            applyLaunchSheet()
            if LabConfig.stress != nil { Task { await runStress() } }
            if LabConfig.render { Task { @MainActor in try? await Task.sleep(nanoseconds: 1_200_000_000); renderFullLength() } }
        }
        .onChange(of: scenario) { _, new in data = Mock21.make(new); conversation = Mock21.conversation(new, data) }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case 0:
            Home21Screen(data: data, isLoading: scenario == .loading, coachPreview: conversation.preview, scrollTo: LabConfig.scroll,
                         initialTrendSelection: LabConfig.select, bottomInset: dockHeight,
                         initialGraphMode: LabConfig.graphMode, initialGraphRange: LabConfig.graphRange,
                         metricStyle: .rows, actions: homeActions)
        case 4:
            LabScreen(themeRaw: $themeRaw, scenario: $scenario, lockedTheme: LabConfig.theme, bottomInset: dockHeight)
        default:
            PlaceholderScreen(title: dockItems.first { $0.id == tab }?.title ?? "", bottomInset: dockHeight)
        }
    }

    private var homeActions: Home21Actions {
        Home21Actions(
            onAvatar: { present(.profile) },
            onConsistency: { present(.consistency) },
            onMix: { present(.mix) },
            onRecovery: { present(.recovery) },
            onStep: { step in
                // Local mock: marks the step done, so the move from "below the indicators" to the bottom can be reviewed.
                if let i = data.steps.firstIndex(where: { $0.id == step.id }) { withAnimation { data.steps[i].isDone.toggle() } }
            },
            onDay: { present(.day($0)) },
            onEndurance: { present(.sport(data.endurance)) },
            onStrength: { present(.sport(data.strength)) },
            onSleep: { present(.sleep) },
            onCoach: { showCoach = true },
            onTrendsInfo: { present(.trendsInfo) },
            onGraphDay: { d, rows in present(.graphDay(d, rows)) },
            onMetric: { present(.metric($0)) })
    }

    /// The only way Home opens a sheet.
    private func present(_ s: LabSheet) {
        if sheet != nil { return }                       // a sheet is already up (e.g. the second tap of a double tap)
        if sheetBusy && LabConfig.stress != "direct" {   // the previous sheet is still animating away: queue the request
            pendingSheet = s
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {   // safety net if the dismissal callback never arrives
                if let p = pendingSheet, sheet == nil { pendingSheet = nil; sheetBusy = true; sheet = p }
            }
            return
        }
        sheetBusy = true
        sheet = s
    }
    private func sheetDismissed() {
        sheetBusy = false
        if let p = pendingSheet { pendingSheet = nil; present(p) }
    }

    /// Prototype self-test (LAB_STRESS = queued | direct): closes a sheet and requests the next one after 0–450 ms,
    /// i.e. during the closing animation, which a UI test cannot time reliably. "direct" bypasses the queue to show
    /// what plain SwiftUI does. The outcome is shown as text for the interaction test to read.
    @MainActor private func runStress() async {
        let delays: [UInt64] = [0, 50, 100, 200, 300, 450]
        var shown = 0
        var log: [String] = []
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        for d in delays {
            present(.mix)
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            sheet = nil
            try? await Task.sleep(nanoseconds: d * 1_000_000)
            present(.recovery)
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            let ok = visibleSheet == "recovery"
            if ok { shown += 1 }
            log.append("\(d)ms:\(ok ? "shown" : (sheet == nil ? "not requested" : "state set but nothing on screen"))")
            sheet = nil; pendingSheet = nil
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            sheetBusy = false
        }
        stressResult = "\(LabConfig.stress ?? "") \(shown) of \(delays.count) shown · " + log.joined(separator: ", ")
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
            case "trendsInfo": sheet = .trendsInfo
            case "hub": sheet = .hub
            case "profile": sheet = .profile
            case "day": if data.days.count > 2 { sheet = .day(data.days[2]) }
            case "endurance": sheet = .sport(data.endurance)
            case "strength": sheet = .sport(data.strength)
            case "trendDay": if let r = data.graph.first, r.dates.count > 2 { sheet = .graphDay(r.dates[2], [CyTrendDetailRow(id: "sample", label: "Opened from launch option", value: "see the graph panel")]) }
            case "metric": if let m = data.metrics.first { sheet = .metric(m) }
            default: break
            }
        }
    }

    /// Review aid only: renders the whole Home column to one tall image in the prototype's own Documents folder.
    @MainActor func renderFullLength() {
        let width: CGFloat = UIScreen.main.bounds.width
        let view = Home21Content(data: data, isLoading: scenario == .loading, coachPreview: conversation.preview, initialTrendSelection: LabConfig.select,
                                 initialGraphMode: LabConfig.graphMode, initialGraphRange: LabConfig.graphRange,
                                 metricStyle: .rows)
            .padding(.vertical, CySpace.l)
            .frame(width: width)
            .background(theme.background)
            .environment(\.cyTheme, theme)
            .environment(\.colorScheme, theme.scheme)
            .environment(\.cyStaticRender, true)
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
        case .sleep:
            SleepSheet(model: data.sleep, onClose: close) { minutes in
                // local mock of the athlete's own setting; nothing is recommended or calculated
                data.sleep.target = minutes
                data.sleep.targetLabel = "Your target"
                data.sleep.targetSource = minutes == nil ? "no target set" : "chosen by the athlete (sample)"
            }
        case .day(let d): DaySheet(day: d, onClose: close) { say("Sample only — the session would open in the app.") }
        case .sport(let m): SportSheet(model: m, onClose: close)
        case .graphDay(let d, let rows): GraphDaySheet(date: d, rows: rows, onClose: close)
        case .metric(let m): MetricSheet(tile: m, onClose: close)
        case .trendsInfo:
            CySheet(title: "How Trends works", onClose: close) {
                InfoBlock(head: "Three views", text: "Training & Recovery: training load (session effort × minutes) on the left scale and recovery on the right scale. Activity: endurance, strength and planned minutes on one scale. Recovery trends: resting heart rate, HRV or sleep — one at a time, because their units differ.")
                InfoBlock(head: "Scales", text: "Each scale is labelled with its metric and unit. Two different units are never drawn on one unlabelled axis.")
                InfoBlock(head: "Ranges", text: "7 days is the latest seven days including today. In 4 weeks, training load and minutes are 7-day rolling totals (marked /7d) so rest days do not turn the line into a sawtooth; recovery, resting heart rate, HRV and sleep stay daily.")
                InfoBlock(head: "No cause and effect", text: "Load and recovery are drawn together for comparison only. The graph does not claim that one explains the other.")
                InfoBlock(head: "Missing days", text: "A day without a measurement is a gap: the line stops and no point is drawn. Nothing is interpolated or estimated.")
                InfoBlock(head: "Recovery percentage", text: "In this prototype the recovery percentage is sample data only. Cyclift has no approved numerical recovery model; until one exists the app would show a status word instead of a number. It is never a medical clearance.")
                InfoBlock(head: "Sources (sample)", text: (data.graph.first?.modes.flatMap(\.series) ?? []).map { "\($0.name): \($0.source) — \($0.provenance.rawValue.lowercased())" }.joined(separator: "\n"))
            }
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
