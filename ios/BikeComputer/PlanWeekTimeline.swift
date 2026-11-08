import SwiftUI

// Checkpoint C2 — the weekly timeline (band C): one row per day, Monday first; chips sized by planned minutes with a
// minimum width that keeps them tappable; colour = sport identity (CyTheme), mark = state. Several sessions sit side by
// side and stack at accessibility sizes. No horizontal scrolling. Tapping a row opens the existing Day page.
struct PlanWeekTimeline: View {
    let days: [PlanTimelineDay]
    var onDay: (PlanTimelineDay) -> Void
    var onChip: (PlanChip) -> Void
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maxMinutes: Int { max(30, days.flatMap(\.chips).map(\.minutes).max() ?? 30) }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(days) { d in
                // Run 204: a Button whose label holds the chip Buttons was not exposed as `planDay-<n>` to XCUITest / assistive
                // tech (seven day buttons: 0 of 7 on every device). The row is a plain tappable view (the pattern used by
                // rideMiniMap); the chips keep their own Buttons and win the tap over the row. One accessibility element per
                // day: the row's label names every session; VoiceOver opens the Day page, where each session is reachable.
                row(d)
                    .onTapGesture { onDay(d) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(d.accessibilityLabel)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("planDay-\(d.weekday)")
                    .accessibilityAction { onDay(d) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planDayStrip")
    }

    private func row(_ d: PlanTimelineDay) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(d.shortName).font(.caption.weight(d.isToday ? .heavy : .semibold)).foregroundStyle(d.isToday ? CyTheme.cycling.tint : .secondary)
                Text(d.date, format: .dateTime.day()).font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(width: 34, alignment: .leading)
            GeometryReader { g in
                let stacked = dts.isAccessibilitySize
                let content = Group {
                    if d.beforePlan { quiet("Before this plan started") }
                    else if d.chips.isEmpty { quiet(d.rest ? "Rest day" : "Free · tap to add") }
                    else if stacked { VStack(alignment: .leading, spacing: 4) { ForEach(d.chips) { c in chip(c, width: g.size.width) } } }
                    else { HStack(spacing: 4) { ForEach(d.chips) { c in chip(c, width: chipWidth(c, total: g.size.width, count: d.chips.count)) } ; Spacer(minLength: 0) } }
                }
                content.frame(width: g.size.width, alignment: .leading)
            }
            .frame(minHeight: dts.isAccessibilitySize ? CGFloat(max(1, d.chips.count)) * 34 + 4 : 30)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: DS.minTap)
        .background(d.isToday ? CyTheme.cycling.bg.opacity(0.45) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    private func chipWidth(_ c: PlanChip, total: CGFloat, count: Int) -> CGFloat {
        let minW: CGFloat = 56, gap: CGFloat = 4
        let avail = max(minW, total - gap * CGFloat(count - 1))
        let proportional = avail * CGFloat(max(c.minutes, 15)) / CGFloat(maxMinutes)
        return min(avail - CGFloat(count - 1) * minW, max(minW, proportional))
    }
    private func quiet(_ t: String) -> some View {
        Text(t).font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func chip(_ c: PlanChip, width: CGFloat) -> some View {
        let id = identity(c.sport)
        return Button { onChip(c) } label: {
            HStack(spacing: 4) {
                Image(systemName: icon(c.sport)).font(.caption2.weight(.bold))
                Text(c.minutes > 0 ? Fmt.duration(minutes: c.minutes) : c.title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                if !c.mark.symbol.isEmpty { Text(c.mark.symbol).font(.caption.weight(.heavy)) }
            }
            .foregroundStyle(c.mark == .skipped ? Color.secondary : id.tint)
            .padding(.horizontal, 8).frame(width: width, height: 30, alignment: .leading)
            .background((c.mark == .skipped ? Color(.systemGray5) : id.bg), in: Capsule())
            .overlay(Capsule().stroke(c.mark == .missed ? BC.warn : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.accessibilityLabel)
        .accessibilityIdentifier("planChip-\(c.id)")
    }
    private func identity(_ s: PlanChip.Sport) -> CyTheme.Identity { switch s { case .ride: return CyTheme.cycling; case .strength: return CyTheme.strength; case .recovery: return CyTheme.recovery; case .other: return CyTheme.recovery } }
    private func icon(_ s: PlanChip.Sport) -> String { switch s { case .ride: return "bicycle"; case .strength: return "dumbbell.fill"; case .recovery: return "moon.fill"; case .other: return "figure.mixed.cardio" } }
}

/// Band B: the compact completion ring with a text equivalent — the same fraction as Home's ring (one ledger).
struct PlanCompactRing: View {
    let overview: HomeWeekOverview
    let minutesLine: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color(.systemGray5), lineWidth: 8)
                Circle().trim(from: 0, to: overview.fraction).stroke(CyTheme.cycling.tint, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: overview.fraction)
                Text(CyDesign.percentText(overview.fraction)).font(.caption.weight(.heavy)).monospacedDigit()
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(overview.planned == 0 ? "No sessions planned" : "\(overview.done) of \(overview.planned) sessions done").font(.subheadline.weight(.semibold))
                Text(minutesLine).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if overview.missed > 0 || overview.skipped > 0 {
                    Text([overview.missed > 0 ? "\(overview.missed) missed" : nil, overview.skipped > 0 ? "\(overview.skipped) skipped" : nil].compactMap { $0 }.joined(separator: " · ")).font(.caption2).foregroundStyle(overview.missed > 0 ? BC.warn : .secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: DS.minTap)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Week completion: \(overview.planned == 0 ? "no sessions planned" : "\(overview.done) of \(overview.planned) sessions done"). \(minutesLine). Opens the weekly overview")
        .accessibilityIdentifier("planRing")
    }
}
