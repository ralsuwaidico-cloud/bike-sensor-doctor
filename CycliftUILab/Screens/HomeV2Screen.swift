import SwiftUI

// Home v2 — approved information hierarchy (owner, 10 Nov 2026):
//   1 compact header · 2 three circles · 3 Getting Started (below the circles while an essential step is open,
//   at the bottom once complete) · 4 seven-day strip · 5 Endurance and Strength Load cards · 6 Coach · 7 combined trends.
// The screen receives data and reports taps through HomeActions. It owns no data, engine or navigation.

struct HomeActions {
    var onAvatar: () -> Void = {}
    var onRing: (CyRingModel) -> Void = { _ in }
    var onSetupItem: (CyChecklistItem) -> Void = { _ in }
    var onDay: (CyDayModel) -> Void = { _ in }
    var onEndurance: () -> Void = {}
    var onStrength: () -> Void = {}
    var onCoachWhy: () -> Void = {}
    var onCoachReview: () -> Void = {}
    var onCoachNotNow: () -> Void = {}
}

struct HomeV2Screen: View {
    let data: HomeData
    var isLoading: Bool = false
    var showSampleBadge: Bool = true
    var scrollTo: String? = nil            // prototype screenshots only: "trends" scrolls to the lower half
    var actions = HomeActions()
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: CySpace.m) {
                    header.id("top")
                    rings
                    if data.essentialsOpen && !isLoading { setup }
                    CyWeekStrip(days: data.days, isLoading: isLoading, onDay: actions.onDay)
                    sportCards
                    coach
                    trends.id("trends")
                    if !data.essentialsOpen && !isLoading { setup }
                    Color.clear.frame(height: CySpace.s).id("bottom")
                }
                .padding(.horizontal, CySpace.l)
                .padding(.top, CySpace.s)
            }
            .background(theme.background.ignoresSafeArea())
            .onAppear {
                if let scrollTo {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { proxy.scrollTo(scrollTo, anchor: .top) }
                }
            }
        }
    }

    // 1 — compact header
    private var header: some View {
        HStack(alignment: .center, spacing: CySpace.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: CySpace.s) {
                    Text(data.dateLine.uppercased()).font(CyFont.overline).tracking(0.6).foregroundStyle(theme.textSecondary)
                    if showSampleBadge {
                        Text("SAMPLE DATA").font(.caption2.weight(.bold)).foregroundStyle(theme.warning)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(theme.warning, lineWidth: 1))
                            .accessibilityLabel("Sample data, not real measurements")
                    }
                }
                if isLoading { CySkeleton(height: 24, width: 200) }
                else {
                    Text(data.greeting).font(CyFont.display).foregroundStyle(theme.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            Spacer(minLength: 0)
            Button(action: actions.onAvatar) {
                Text(data.initials).font(CyFont.headline).foregroundStyle(theme.accent)
                    .frame(width: CyHit.min, height: CyHit.min)
                    .background(Circle().fill(theme.accentSubtle))
                    .overlay(Circle().strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
            }
            .buttonStyle(CyRingButtonStyle())
            .accessibilityLabel("Profile")
        }
    }

    // 2 — circles
    private var rings: some View {
        CyCard(padding: CySpace.m) {
            if isLoading {
                CyRingRow(rings: data.rings.map { CyRingModel(id: $0.id, title: $0.title, kind: $0.kind, display: .loading) }, onTap: { _ in })
            } else {
                CyRingRow(rings: data.rings, onTap: actions.onRing)
            }
        }
    }

    // 3 — Getting Started (placement decided by the caller's data: essentials open → top, otherwise bottom)
    private var setup: some View {
        CyGettingStartedCard(items: data.setup, onItem: actions.onSetupItem)
    }

    // 5 — sport cards (side by side; stacked at accessibility text sizes)
    @ViewBuilder private var sportCards: some View {
        let endurance = CyTrainingSummaryCard(model: isLoading ? nil : data.endurance, emptyMessage: data.enduranceEmpty, onOpen: actions.onEndurance)
        let strength = CyTrainingSummaryCard(model: isLoading ? nil : data.strength, emptyMessage: data.strengthEmpty, onOpen: actions.onStrength)
        if typeSize.isAccessibilitySize {
            VStack(spacing: CySpace.m) { endurance; strength }
        } else {
            HStack(alignment: .top, spacing: CySpace.m) { endurance; strength }
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // 6 — coach (compact row)
    private var coach: some View {
        CyCoachInsightCard(model: isLoading ? nil : data.coach, compact: true, emptyMessage: isLoading ? nil : data.coachEmpty,
                           onWhy: actions.onCoachWhy, onAccept: actions.onCoachReview, onNotNow: actions.onCoachNotNow)
    }

    // 7 — combined trends
    private var trends: some View {
        CyTrendChart(title: "Training & Recovery", series: data.trendSeries, statusRows: data.trendRows, dayLabels: data.trendLabels,
                     yDomain: 0...105, isLoading: isLoading, emptyMessage: data.trendEmpty,
                     footnote: "Consistency is a percentage of planned sessions completed. Load Balance and Recovery are status words, not scores. Days without data are left empty.")
    }
}
