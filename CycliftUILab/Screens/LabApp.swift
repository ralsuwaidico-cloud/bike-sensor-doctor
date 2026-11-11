import SwiftUI

// Cyclift UI Lab — standalone prototype shell. Mock navigation and local sheets only.
// Nothing here talks to the production app, Apple Health, sensors, accounts or any backend.

/// Launch options (environment variables) used by the prototype's own screenshot script.
enum LabConfig {
    static let env = ProcessInfo.processInfo.environment
    static var theme: CyThemeID? { env["LAB_THEME"].flatMap(CyThemeID.init(rawValue:)) }
    static var scenario: LabScenario? { env["LAB_SCENARIO"].flatMap(LabScenario.init(rawValue:)) }
    static var screen: String { env["LAB_SCREEN"] ?? "home" }          // home | lab | gallery
    static var page: String? { env["LAB_PAGE"] }                        // gallery page id
    static var scroll: String? { env["LAB_SCROLL"] }                    // "trends" | "bottom"
    static var sheet: String? { env["LAB_SHEET"] }                      // ringLoad | review | day | coachWhy | hub
}

@main
struct CycliftUILabApp: App {
    var body: some Scene {
        WindowGroup { LabRoot() }
    }
}

enum LabSheet: Identifiable {
    case ring(CyRingModel), day(CyDayModel), summary(CySummaryCardModel), coachWhy, review, hub, setup(CyChecklistItem)
    var id: String {
        switch self {
        case .ring(let r): return "ring-\(r.id)"
        case .day(let d): return "day-\(d.id)"
        case .summary(let s): return "summary-\(s.title)"
        case .coachWhy: return "coachWhy"
        case .review: return "review"
        case .hub: return "hub"
        case .setup(let i): return "setup-\(i.id)"
        }
    }
}

struct LabRoot: View {
    @AppStorage("lab.theme") private var themeRaw: String = CyThemeID.obsidian.rawValue
    @State private var scenario: LabScenario = LabConfig.scenario ?? .established
    @State private var data: HomeData = MockData.home(LabConfig.scenario ?? .established)
    @State private var tab: String = LabConfig.screen == "home" ? "home" : "lab"
    @State private var sheet: LabSheet? = nil
    @State private var toast: String? = nil

    private var themeID: CyThemeID { LabConfig.theme ?? CyThemeID(rawValue: themeRaw) ?? .obsidian }
    private var theme: CyTheme { CyTheme.named(themeID) }

    private let tabs = [
        CyTabItem(id: "home", title: "Home", icon: "house.fill"),
        CyTabItem(id: "plan", title: "Plan", icon: "calendar"),
        CyTabItem(id: "progress", title: "Progress", icon: "chart.line.uptrend.xyaxis"),
        CyTabItem(id: "lab", title: "Lab", icon: "paintpalette.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                content
                if let toast {
                    Text(toast).font(CyFont.caption).foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, CySpace.l).padding(.vertical, CySpace.m)
                        .background(Capsule().fill(theme.surface2))
                        .overlay(Capsule().strokeBorder(theme.border, lineWidth: theme.borderWidth))
                        .padding(.bottom, CySpace.m)
                        .transition(.opacity)
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            CyTabBar(items: tabs, selection: $tab, centreTitle: "Train now", centreBadge: data.sessionsToday) { sheet = .hub }
        }
        .background(theme.background.ignoresSafeArea())
        .environment(\.cyTheme, theme)
        .preferredColorScheme(theme.scheme)
        .tint(theme.accent)
        .sheet(item: $sheet) { s in
            sheetView(s)
                .environment(\.cyTheme, theme)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear(perform: applyLaunchSheet)
        .onChange(of: scenario) { _, new in data = MockData.home(new) }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case "home":
            HomeV2Screen(data: data, isLoading: scenario == .loading, scrollTo: LabConfig.scroll, actions: homeActions)
        case "lab":
            LabScreen(themeRaw: $themeRaw, scenario: $scenario, lockedTheme: LabConfig.theme)
        default:
            PlaceholderScreen(title: tabs.first { $0.id == tab }?.title ?? "")
        }
    }

    private var homeActions: HomeActions {
        HomeActions(
            onAvatar: { tab = "lab" },
            onRing: { sheet = .ring($0) },
            onSetupItem: { item in
                // Local mock interaction: marks the step done so the card's move from top to bottom can be reviewed.
                if let i = data.setup.firstIndex(where: { $0.id == item.id }) { withAnimation { data.setup[i].isDone.toggle() } }
            },
            onDay: { sheet = .day($0) },
            onEndurance: { sheet = .summary(data.endurance) },
            onStrength: { sheet = .summary(data.strength) },
            onCoachWhy: { sheet = .coachWhy },
            onCoachReview: { sheet = .review },
            onCoachNotNow: { say("Sample only — the suggestion would return at your next weekly review.") })
    }

    private func say(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { if toast == text { toast = nil } } }
    }

    private func applyLaunchSheet() {
        guard let s = LabConfig.sheet else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            switch s {
            case "ringConsistency": sheet = .ring(data.rings[0])
            case "ringLoad": sheet = .ring(data.rings[1])
            case "ringRecovery": sheet = .ring(data.rings[2])
            case "review": sheet = .review
            case "coachWhy": sheet = .coachWhy
            case "day": sheet = .day(data.days[2])
            case "hub": sheet = .hub
            default: break
            }
        }
    }

    @ViewBuilder private func sheetView(_ s: LabSheet) -> some View {
        switch s {
        case .ring(let r): RingDetailSheet(model: r) { sheet = nil }
        case .day(let d): DayDetailSheet(day: d, onClose: { sheet = nil }, onAction: { say("Sample only — a session would start in the real app.") })
        case .summary(let m): SummaryDetailSheet(model: m) { sheet = nil }
        case .coachWhy:
            CySheet(title: "Why this suggestion?", onClose: { sheet = nil }) {
                Text(data.coach?.why ?? "No suggestion at the moment.").font(CyFont.body).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text("The coach is rules-based. Sample text for layout review.").font(.caption2).foregroundStyle(theme.textTertiary)
            }
        case .review:
            CyReviewSheet(title: "Review the suggestion",
                          reason: "Two sessions in a row reached the top of the rep range at a reported effort of 7 out of 10.",
                          benefit: "A small step keeps the work challenging without changing the session.",
                          impact: "The last sets may feel harder for a week or two. You can undo this at any time.",
                          changes: MockData.changes,
                          onApprove: { sheet = nil; say("Sample only — nothing was changed.") },
                          onPostpone: { sheet = nil; say("Sample only — postponed, not counted as declined.") },
                          onDecline: { sheet = nil; say("Sample only — declined.") })
        case .hub:
            CySheet(title: "Training Hub", onClose: { sheet = nil }) {
                Text("Not prototyped yet. The Training Hub is reviewed after Home and Plan are approved.").font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                CyWorkoutCard(model: MockData.workout, onAction: { say("Sample only.") }, onOpen: {})
            }
        case .setup(let item):
            CySheet(title: item.title, onClose: { sheet = nil }) {
                Text(item.detail ?? "").font(CyFont.body).foregroundStyle(theme.textSecondary)
            }
        }
    }
}

struct PlaceholderScreen: View {
    let title: String
    @Environment(\.cyTheme) private var theme
    var body: some View {
        VStack(spacing: CySpace.l) {
            Spacer()
            CyEmptyStateCard(icon: "hammer", title: "\(title) is not prototyped yet",
                             message: "Screens are built one at a time. This one starts after Home has been reviewed and approved.")
            Spacer()
        }
        .padding(CySpace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
    }
}

// MARK: Local mock detail sheets

struct RingDetailSheet: View {
    let model: CyRingModel
    let onClose: () -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        CySheet(title: model.title, onClose: onClose) {
            HStack(spacing: CySpace.l) {
                CyRingGlyph(model: model, diameter: 72)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(CyFont.title).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text(sub).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            block("How this is worked out", how)
            block("What it does not tell you", limits)
            Text("Sample content for layout review. Wording is reviewed with the real detail pages at integration.").font(.caption2).foregroundStyle(theme.textTertiary)
        }
    }
    private func block(_ head: String, _ body: String) -> some View {
        CyCard(padding: CySpace.m) {
            VStack(alignment: .leading, spacing: CySpace.xs) {
                CyOverline(text: head)
                Text(body).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var headline: String {
        switch model.display {
        case .fraction(_, let t, _): return t
        case .status(let w, _, _): return w
        case .missing(let r): return r
        case .loading: return "Loading"
        }
    }
    private var sub: String {
        switch model.display {
        case .fraction(_, _, let c): return c
        case .status: return "A status word, not a score"
        case .missing: return "Shown honestly instead of an estimate"
        case .loading: return ""
        }
    }
    private var how: String {
        switch model.kind {
        case .consistency: return "Planned sessions you completed this week, divided by the planned sessions up to today. Rest days and future sessions are not counted."
        case .loadBalance: return "Your last 7 days of training load compared with your own average of the previous 4 weeks. It needs at least 4 weeks of sessions with an effort rating or heart rate."
        case .recovery: return "One word from your own recent sleep and resting heart-rate readings compared with your usual range. Without readings it says so."
        case .generic: return "A plain proportion of a target."
        }
    }
    private var limits: String {
        switch model.kind {
        case .consistency: return "It does not judge how hard or how good the sessions were."
        case .loadBalance: return "The bands are a guide for wording, not a validated safe-training zone, and this is not a measure of recovery."
        case .recovery: return "It is general wellness guidance, not medical advice, and it is separate from Load Balance."
        case .generic: return "Nothing beyond the proportion shown."
        }
    }
}

struct DayDetailSheet: View {
    let day: CyDayModel
    let onClose: () -> Void
    let onAction: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        CySheet(title: "\(day.weekday) \(day.dayNumber)", onClose: onClose) {
            if day.sessions.isEmpty {
                CyEmptyStateCard(icon: "moon.fill", title: "Rest day", message: day.detail)
            } else {
                ForEach(Array(day.sessions.enumerated()), id: \.offset) { i, s in
                    CyWorkoutCard(model: CyWorkoutModel(category: s, title: s == .endurance ? "Endurance ride" : "Strength session",
                                                         detail: "Sample session \(i + 1)", status: day.status),
                                  actionTitle: day.status == .done ? "Results" : "Start",
                                  isActionEnabled: day.status == .today || day.status == .done,
                                  onAction: onAction, onOpen: {})
                }
            }
        }
    }
}

struct SummaryDetailSheet: View {
    let model: CySummaryCardModel
    let onClose: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        CySheet(title: model.title, onClose: onClose) {
            HStack(spacing: CySpace.m) {
                CyMetricSummaryCard(model: CyMetricModel(label: "This week", value: model.primary, unit: nil, delta: model.secondary, deltaLevel: .neutral))
                CyMetricSummaryCard(model: CyMetricModel(label: "Also", value: model.supporting, unit: nil, delta: nil, deltaLevel: .neutral))
            }
            CyWeeklyBars(title: model.trendCaption ?? "Weekly trend",
                         points: (model.trend ?? []).enumerated().map { CySeriesPoint(id: $0.offset, label: "W\($0.offset + 1)", value: $0.element) },
                         unit: "", category: model.category)
        }
    }
}
