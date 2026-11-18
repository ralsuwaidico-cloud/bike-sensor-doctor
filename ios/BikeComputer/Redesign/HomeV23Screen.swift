import SwiftUI

// Home v2.3 — the screen. PROVISIONAL design (owner's refinement of 12 Nov 2026; not yet visually approved).
// Brought over from the UI Lab prototype (branch proto/ui-lab, Screens/Home21Screen.swift) as shared code for both apps.
// Order, unchanged: 1 compact header · 2 Consistency / Training Mix / Recovery · 3 Getting Started while a required step
// is open · 4 compact schedule · 5 Endurance and Strength cards · 6 Sleep bar · 7 Coach · 8 Trends · 9 Key metrics ·
// 10 collapsed setup line. The screen receives data and reports taps; it owns no data, engine or navigation.
// Changes made for the app, and nothing else:
//  • no SAMPLE tag (the values are the athlete's own records; the Lab app labels its demo athlete in its own strip);
//  • the name carries the identifier the app's tests already use for Home ("homeGreeting");
//  • a discipline the athlete does not train has no card (cycling-only / strength-only), instead of an empty one;
//  • the Coach preview is named by the host, and a "Coach page" line can follow it (see HomeView: a suggestion that
//    opens its own sheet must not hide the way to the Coach page — audit of 16 Nov 2026).

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
    var onCoach: () -> Void = {}
    var onCoachPage: (() -> Void)? = nil          // nil = no separate "Coach page" line
    var onTrendsInfo: () -> Void = {}
    var onGraphDay: (CyGraphDate, [CyTrendDetailRow]) -> Void = { _, _ in }
    var onMetric: (CyHomeMetric) -> Void = { _ in }
}

/// What the host says about the Coach preview: which element it is and how it is announced.
struct Home21Coach {
    var model: CyCoachPreviewModel? = nil
    var identifier: String = "homeCoachQuiet"
    var spokenPrefix: String = ""
    var hint: String = "Opens the Coach page"
    var isShown: Bool = true
}

/// The Home content column (no scroll view).
struct Home21Content: View {
    let data: Home21Data
    var isLoading: Bool = false
    var showSampleTag: Bool = false
    var coach = Home21Coach()
    var metricStyle: CyMetricStyle = .rows
    /// false when the host pins the header above the scroll view (the app does: the avatar is the only way to Profile).
    var showsHeader: Bool = true
    var actions = Home21Actions()
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: CySpace.xl) {
            if showsHeader { Home21Header(data: data, isLoading: isLoading, showSampleTag: showSampleTag, onAvatar: actions.onAvatar).id("top") }
            CyIndicatorRow(consistency: (data.consistency.fraction, data.consistency.text, data.consistency.caption),
                           mix: data.mix, recovery: data.recovery, isLoading: isLoading,
                           onConsistency: actions.onConsistency, onMix: actions.onMix, onRecovery: actions.onRecovery)
            if data.requiredOpen && !isLoading { CySetupBanner(steps: data.steps, onStep: actions.onStep) }
            CyCompactSchedule(days: data.days, isLoading: isLoading, onDay: actions.onDay)
            sportCards.id("cards")
            CySleepBar(model: isLoading ? nil : data.sleep, onOpen: actions.onSleep)
            if coach.isShown {
                VStack(alignment: .trailing, spacing: 0) {
                    CyCoachPreview(model: isLoading ? nil : coach.model, emptyText: data.coachEmpty, isLoading: isLoading,
                                   identifier: coach.identifier, spokenPrefix: coach.spokenPrefix, hint: coach.hint, onOpen: actions.onCoach)
                    if let open = actions.onCoachPage {
                        Button(action: open) {
                            HStack(spacing: 4) { Text("Coach page"); Image(systemName: "chevron.right").font(.caption2.weight(.semibold)) }
                                .font(CyFont.caption).foregroundStyle(theme.accent)
                                .frame(minHeight: CyHit.min).contentShape(Rectangle())
                        }
                        .buttonStyle(CyRingButtonStyle())
                        .accessibilityHint("Opens the Coach's notes and conversation")
                        .accessibilityIdentifier("homeCoachOpen")
                    }
                }
                .id("coach")
            }
            CyTrendsGraph(ranges: data.graph, isLoading: isLoading, emptyText: data.graph.isEmpty ? (data.trendsEmpty ?? "Nothing recorded yet.") : nil,
                          isSample: showSampleTag, onInfo: actions.onTrendsInfo, onDay: actions.onGraphDay)
                .id("trends")
            CyMetricGrid(tiles: data.metrics, isLoading: isLoading, style: metricStyle, onTile: actions.onMetric)
                .id("metrics")
            if !data.requiredOpen && !isLoading { CySetupBanner(steps: data.steps, onStep: actions.onStep) }
        }
        .padding(.horizontal, 20)
        .padding(.top, CySpace.s)
    }

    // 5 — compact sport cards, equal height; stacked at accessibility sizes. A discipline that is not trained has no card.
    @ViewBuilder private var sportCards: some View {
        let showE = isLoading || data.endurance != nil, showS = isLoading || data.strength != nil
        if showE || showS {
            if typeSize.isAccessibilitySize {
                VStack(spacing: CySpace.s) {
                    if showE { CyCompactSportCard(model: isLoading ? nil : data.endurance, onOpen: actions.onEndurance) }
                    if showS { CyCompactSportCard(model: isLoading ? nil : data.strength, onOpen: actions.onStrength) }
                }
            } else {
                HStack(alignment: .top, spacing: CySpace.s) {
                    if showE { CyCompactSportCard(model: isLoading ? nil : data.endurance, onOpen: actions.onEndurance) }
                    if showS { CyCompactSportCard(model: isLoading ? nil : data.strength, onOpen: actions.onStrength) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 1 — compact header: date (and athlete type) in one small line, the name on one line, avatar on the right.
struct Home21Header: View {
    let data: Home21Data
    var isLoading: Bool = false
    var showSampleTag: Bool = false
    var onAvatar: () -> Void = {}
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: CySpace.m) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(overline.uppercased()).font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("homeDate")
                    if showSampleTag {
                        Text("SAMPLE").font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(theme.warning)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .overlay(Capsule().strokeBorder(theme.warning.opacity(0.8), lineWidth: 1))
                            .accessibilityLabel("Sample data, not real measurements")
                    }
                }
                if isLoading { CySkeleton(height: 22, width: 140) }
                else {
                    Text(data.name.isEmpty ? "Home" : data.name).font(CyFont.name).foregroundStyle(theme.textPrimary)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1).minimumScaleFactor(0.75).truncationMode(.tail)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("homeGreeting")
                }
            }
            Spacer(minLength: 0)
            Button(action: onAvatar) {
                Group {
                    if data.initials.isEmpty { Image(systemName: "person.fill").font(.footnote.weight(.semibold)) }
                    else { Text(data.initials).font(CyFont.label.weight(.semibold)) }
                }
                .foregroundStyle(theme.accent)
                .frame(width: CyHit.min, height: CyHit.min)
                .background(Circle().fill(theme.accentSubtle))
                .overlay(Circle().strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
            }
            .buttonStyle(CyRingButtonStyle())
            .accessibilityLabel("Profile")
            .accessibilityIdentifier("homeAvatar")
        }
    }
    private var overline: String { [data.dateLine, data.athleteType ?? ""].filter { !$0.isEmpty }.joined(separator: " · ") }
}

/// "How this graph works" — what each line is and where it comes from. Text only; nothing here changes anything.
struct HomeTrendsInfoSheet: View {
    var close: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: CySpace.l) {
            HStack {
                Text("How Trends works").font(CyFont.title).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button("Close", action: close).font(CyFont.label).foregroundStyle(theme.accent)
                    .frame(minWidth: CyHit.min, minHeight: CyHit.min).accessibilityIdentifier("homeSheetClose")
            }
            row("Activity", "Minutes per day from your recorded rides and logged strength sessions, with your plan's minutes as a dashed line. In the 4-week view each point is the total of that day and the six days before it.")
            row("Recovery trends", "Resting heart rate, HRV and sleep as Apple Health recorded them, one at a time because their units differ. A day without a reading is a gap in the line — nothing is filled in.")
            row("What is not shown", "Cyclift has no recovery score. Nothing on this graph is a percentage of readiness, and none of it is medical advice.")
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeTrendsInfo")
    }
    private func row(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(CyFont.headline).foregroundStyle(theme.textPrimary)
            Text(text).font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
