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
                // Run 204: a Button whose label held the chip Buttons was not exposed as `planDay-<n>` (0 of 7 found on every
                // device). Owner 8 Nov 20:58: the day row AND each workout chip must be independently reachable by touch and
                // VoiceOver. Structure: a full-row tap target underneath (the `planDay-<n>` button: opens the Day page, its
                // label names the day and every session) and the chips on top, each its own Button (`planChip-<id>`: opens
                // that session). VoiceOver order: day, then its sessions.
                // (The tap layer is a background — not a ZStack sibling — so the flexible Color.clear cannot stretch the row
                // inside the scroll view; a background takes the row's own size.)
                // Run 206 (SE, AX3): a tap on the row's left edge did not open the Day page. The day is now a real Button
                // (the day-name column, full row height, no nested controls — so XCUITest and VoiceOver see a plain button),
                // and the rest of the row's empty space still opens the day through the background tap layer.
                row(d)
                    .background {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { onDay(d) }
                            .accessibilityHidden(true)   // the day Button carries the accessibility role
                    }
                    .background(d.isToday ? CyTheme.cycling.bg.opacity(0.45) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .contain)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planDayStrip")
    }

    private func row(_ d: PlanTimelineDay) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Button { onDay(d) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(d.shortName).font(.caption.weight(d.isToday ? .heavy : .semibold)).foregroundStyle(d.isToday ? CyTheme.cycling.tint : .secondary)
                    Text(d.date, format: .dateTime.day()).font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(width: 34, alignment: .leading)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(d.accessibilityLabel)
            .accessibilityHint(d.chips.isEmpty && !d.beforePlan ? "Adds a session" : "Opens the day")
            .accessibilityIdentifier("planDay-\(d.weekday)")
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
    }

    private func chipWidth(_ c: PlanChip, total: CGFloat, count: Int) -> CGFloat {
        let minW: CGFloat = 56, gap: CGFloat = 4
        let avail = max(minW, total - gap * CGFloat(count - 1))
        let proportional = avail * CGFloat(max(c.minutes, 15)) / CGFloat(maxMinutes)
        return min(avail - CGFloat(count - 1) * minW, max(minW, proportional))
    }
    private func quiet(_ t: String) -> some View {
        Text(t).font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false).accessibilityHidden(true)   // the day button underneath carries the tap and the label
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
