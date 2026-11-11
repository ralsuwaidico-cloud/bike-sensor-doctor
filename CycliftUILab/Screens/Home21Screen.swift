import SwiftUI

// Home v2.1 — owner revision of 12 Nov 2026 (isolated UI Lab only).
// Order: 1 compact header · 2 Consistency / Training Mix / Recovery · 3 Getting Started while a required step is open ·
// 4 compact schedule · 5 Endurance and Strength cards · 6 Sleep bar · 7 Coach · 8 Trends · 9 Key metrics ·
// 10 collapsed setup line. The screen receives data and reports taps; it owns no data, engine or navigation.

struct Home21Actions {
    var onAvatar: () -> Void = {}
    var onConsistency: () -> Void = {}
    var onMix: () -> Void = {}
    var onRecovery: () -> Void = {}
    var onStep: (CySetupStep) -> Void = { _ in }
    var onDay: (CyScheduleDay) -> Void = { _ in }
    var onEndurance: () -> Void = {}
    var onStrength: () -> Void = {}
    var onSleep: () -> Void = {}
    var onCoachWhy: () -> Void = {}
    var onCoachReview: () -> Void = {}
    var onCoachNotNow: () -> Void = {}
    var onTrendsInfo: () -> Void = {}
    var onTrendDay: (CyTrendDay) -> Void = { _ in }
    var onMetric: (CyMetricTile) -> Void = { _ in }
}

/// The Home content column (no scroll view), so it can also be rendered full-length for review.
struct Home21Content: View {
    let data: Home21Data
    var isLoading: Bool = false
    var showSampleTag: Bool = true
    var coachDecision: CyCoachDecision = .none
    var initialTrendSelection: Int? = nil
    var metricStyle: CyMetricStyle = .rows
    var actions = Home21Actions()
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header.id("top")
            CyIndicatorRow(consistency: (data.consistency.fraction, data.consistency.text, data.consistency.caption),
                           mix: data.mix, recovery: data.recovery, isLoading: isLoading,
                           onConsistency: actions.onConsistency, onMix: actions.onMix, onRecovery: actions.onRecovery)
            if data.requiredOpen && !isLoading { CySetupBanner(steps: data.steps, onStep: actions.onStep) }
            CyCompactSchedule(days: data.days, isLoading: isLoading, onDay: actions.onDay)
            sportCards.id("cards")
            CySleepBar(model: isLoading ? nil : data.sleep, onOpen: actions.onSleep)
            CyCoachBanner(model: isLoading ? nil : (data.coach ?? CyCoachBannerModel(sentence: "", why: "", hasProposal: false)),
                          emptyText: isLoading ? nil : (data.coach == nil ? data.coachEmpty : nil), decision: coachDecision,
                          onWhy: actions.onCoachWhy, onReview: actions.onCoachReview, onNotNow: actions.onCoachNotNow)
                .id("coach")
            CyTrendsModule(ranges: data.trends, isLoading: isLoading, emptyText: data.trendsEmpty, initialSelection: initialTrendSelection,
                           onInfo: actions.onTrendsInfo, onDay: actions.onTrendDay)
                .id("trends")
            CyMetricGrid(tiles: data.metrics, isLoading: isLoading, style: metricStyle, onTile: actions.onMetric)
                .id("metrics")
            if !data.requiredOpen && !isLoading { CySetupBanner(steps: data.steps, onStep: actions.onStep) }
            Color.clear.frame(height: 1).id("bottom")
        }
        .padding(.horizontal, 20)
        .padding(.top, CySpace.s)
    }

    // 1 — compact header: date (and athlete type) in one small line, the name on one line, avatar on the right
    private var header: some View {
        HStack(alignment: .center, spacing: CySpace.m) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(overline.uppercased()).font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1).minimumScaleFactor(0.8)
                    if showSampleTag {
                        Text("SAMPLE").font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(theme.warning)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .overlay(Capsule().strokeBorder(theme.warning.opacity(0.8), lineWidth: 1))
                            .accessibilityLabel("Sample data, not real measurements")
                    }
                }
                if isLoading { CySkeleton(height: 22, width: 140) }
                else {
                    Text(data.name).font(CyFont.name).foregroundStyle(theme.textPrimary)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1).minimumScaleFactor(0.75).truncationMode(.tail)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            Spacer(minLength: 0)
            Button(action: actions.onAvatar) {
                Text(data.initials).font(CyFont.label.weight(.semibold)).foregroundStyle(theme.accent)
                    .frame(width: CyHit.min, height: CyHit.min)
                    .background(Circle().fill(theme.accentSubtle))
                    .overlay(Circle().strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
            }
            .buttonStyle(CyRingButtonStyle())
            .accessibilityLabel("Profile")
        }
    }
    private var overline: String { [data.dateLine, data.athleteType ?? ""].filter { !$0.isEmpty }.joined(separator: " · ") }

    // 5 — compact sport cards, equal height; stacked at accessibility sizes
    @ViewBuilder private var sportCards: some View {
        let e = CyCompactSportCard(model: isLoading ? nil : data.endurance, onOpen: actions.onEndurance)
        let s = CyCompactSportCard(model: isLoading ? nil : data.strength, onOpen: actions.onStrength)
        if typeSize.isAccessibilitySize {
            VStack(spacing: CySpace.s) { e; s }
        } else {
            HStack(alignment: .top, spacing: CySpace.s) { e; s }.fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Home21Screen: View {
    let data: Home21Data
    var isLoading: Bool = false
    var coachDecision: CyCoachDecision = .none
    var scrollTo: String? = nil            // prototype screenshots only
    var initialTrendSelection: Int? = nil
    var bottomInset: CGFloat = 0           // room for the floating dock, so nothing is hidden beneath it
    var metricStyle: CyMetricStyle = .rows
    var actions = Home21Actions()
    @Environment(\.cyTheme) private var theme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Home21Content(data: data, isLoading: isLoading, coachDecision: coachDecision, initialTrendSelection: initialTrendSelection, metricStyle: metricStyle, actions: actions)
                    .padding(.bottom, bottomInset + CySpace.l)
            }
            .clipped()
            .background(theme.background.ignoresSafeArea())
            .onAppear {
                if let scrollTo {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo(scrollTo, anchor: .top) }
                }
            }
        }
    }
}
