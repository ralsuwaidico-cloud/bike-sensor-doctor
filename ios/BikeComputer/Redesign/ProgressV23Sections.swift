import SwiftUI

// Progress v2.3 — the open sections under the compact hero (sheet PH4, "AFTER"), in the sheet's order:
// Your development · Endurance development · Strength development · Training consistency · Time in zones ·
// Next evolution · Performance analysis · Evolution timeline · Records & history.
// The sections sit directly on the page (no cards), each with one large figure, one line saying what it is, and a small
// drawing. Everything shown comes from ProgressDevelopment (the athlete's own records). Each development section opens
// its own page (Redesign/ProgressDetailV2.swift).
//
// STAGES: the criteria are not approved (baseline register, Progress row). "Next evolution" and "Evolution timeline"
// therefore show the baseline state only: no stage name, no requirement, no dated stage event. The sheet's "Since
// baseline", "Improving" and "Developing Hybrid" wording is not used either: there is no approved baseline date or
// trend-label method. The page says what was measured and against what.

struct ProgressV23Sections: View {
    let model: ProgressDevelopment
    var units: AppSettings.Units
    var showAnalytics = true
    var onAnalytics: () -> Void
    var onHistory: () -> Void
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.progressOpen) private var open

    private var showRiding: Bool { store.profile.trainingMode.includesCycling || !store.rides.isEmpty }
    private var showLifting: Bool { store.profile.trainingMode.includesLifting || !store.strength.isEmpty }
    /// Samples first (the host's figure), then the zone totals saved with the rides, else exactly what is missing.
    private var zoneState: (zones: ProgressDevelopment.Zones?, unavailable: ProgressDevelopment.ZonesUnavailable?) {
        guard showRiding else { return (nil, nil) }
        return ProgressDevelopment.zonesResolved(sampled: model.zones, rides: store.rides, ftpKnown: store.profile.ftpKnown, hrZonesKnown: store.profile.hrZonesKnown)
    }
    private var nothingRecorded: Bool { model.isEmpty && store.rides.isEmpty && store.strength.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            intro
            development
            zonesSection
            nextEvolution
            if showAnalytics {
                VStack(alignment: .leading, spacing: 4) {
                    overline("PERFORMANCE ANALYSIS")
                    row("Detailed analytics", analyticsSub, id: "progressOpenAnalytics", onAnalytics)
                }
            }
            evolutionTimeline
            row("Records & history", "Every recorded ride and logged session", id: "progressOpenHistory", onHistory)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progressV23")
    }

    private var analyticsSub: String {
        let parts = (showRiding ? ["Endurance"] : []) + (showLifting ? ["Strength"] : []) + ["Records", "Checkpoints"]
        return parts.joined(separator: " · ")
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                overline("YOUR DEVELOPMENT")
                Spacer(minLength: CySpace.s)
                Text("From your records").font(.caption.weight(.semibold)).foregroundStyle(theme.textPrimary)
            }
            Text(nothingRecorded ? "Nothing recorded yet. Your development appears here after your first sessions."
                                 : "Measured from your recorded rides and logged strength sessions. No stage is evaluated.")
                .font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("progressDevelopmentIntro")
        }
    }

    @ViewBuilder private var development: some View {
        if let e = model.endurance {
            opens(ProgressRoute.endurance, id: "progressEndurance") { endurance(e) }
        }
        if let s = model.strength {
            opens(ProgressRoute.strength, id: "progressStrengthDevelopment") { strength(s) }
        } else if showLifting, let pending = ProgressDevelopment.strengthPending(lifts: store.liftSummaries(), sessions: store.strength.count) {
            opens(ProgressRoute.strength, id: "progressStrengthPending") {
                VStack(alignment: .leading, spacing: 4) {
                    title("Strength development", chevron: true)
                    Text(pending).font(.system(.footnote)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        if let c = model.consistency {
            opens(ProgressRoute.consistency, id: "progressConsistency") { consistency(c) }
        }
    }

    @ViewBuilder private var zonesSection: some View {
        let state = zoneState
        if let z = state.zones {
            opens(ProgressRoute.zones, id: "progressZones") { zones(z) }
        } else if let why = state.unavailable {
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    title("Time in zones")
                    Text("Not shown. \(why.text)").font(.system(.footnote)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine).accessibilityIdentifier("progressZonesMissing")
                if !why.settings.isEmpty { PgZoneSettingsRows(only: why.settings) }
            }
        }
    }

    // MARK: stages — baseline state only (criteria not approved)

    private var nextEvolution: some View {
        VStack(alignment: .leading, spacing: 6) {
            overline("NEXT EVOLUTION")
            Text("Stage criteria are not set yet")
                .font(.system(.title3, design: .rounded).weight(.heavy)).foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Cyclift does not evaluate stages in this version, so there is no next stage and nothing to qualify for yet.")
                .font(.system(.subheadline)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            Text("The evidence each stage needs has not been defined and approved.")
                .font(.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progressNextEvolution")
    }

    private var evolutionTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            overline("EVOLUTION TIMELINE")
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).stroke(theme.textSecondary, lineWidth: 1.6).frame(width: 11, height: 11)
                Line().stroke(theme.textSecondary.opacity(0.8), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [1.5, 5])).frame(height: 1)
                Circle().fill(theme.accent).frame(width: 11, height: 11)
            }
            .accessibilityHidden(true)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Baseline").font(.caption.weight(.semibold)).foregroundStyle(theme.textPrimary)
                    Text("being established").font(.caption2).foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Now").font(.caption.weight(.semibold)).foregroundStyle(theme.textPrimary)
                    Text(Date().formatted(.dateTime.day().month(.abbreviated))).font(.caption2).foregroundStyle(theme.textSecondary)
                }
            }
            Text("No stage events yet.").font(.caption).foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progressEvolutionTimeline")
    }

    /// A development section that opens its page. The section's own text is one VoiceOver element and one button.
    private func opens<V: View>(_ route: ProgressRoute, id: String, @ViewBuilder _ content: () -> V) -> some View {
        let label = content()
        return Button { open(route) } label: {
            label.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityHint("Opens the details")
    }

    // MARK: pieces

    private func overline(_ t: String) -> some View {
        Text(t).font(CyFont.overline).tracking(1.4).foregroundStyle(theme.textSecondary).accessibilityAddTraits(.isHeader)
    }
    private func title(_ t: String, chevron: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(t).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            if chevron { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(theme.textTertiary).accessibilityHidden(true) }
        }
    }
    private func figure(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).font(.system(.subheadline).weight(.semibold)).foregroundStyle(theme.textSecondary)
        }
    }
    private func line(_ d: ProgressDevelopment.Direction?, _ what: String, _ rest: String) -> some View {
        (Text(d.map { Image(systemName: $0.symbol) } ?? Image(systemName: "minus")).font(.caption2.weight(.bold))
         + Text(" " + (d?.text(what) ?? "Not enough weeks to compare yet")).font(.system(.footnote).weight(.semibold))
         + Text(" · " + rest).font(.system(.footnote)))
            .foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
    }
    private func ends(_ a: String, _ b: String, middle: String? = nil) -> some View {
        HStack {
            Text(a); Spacer(minLength: 4)
            if let m = middle { Text(m); Spacer(minLength: 4) }
            Text(b)
        }
        .font(.caption2).foregroundStyle(theme.textTertiary)
    }
    private func row(_ t: String, _ sub: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CySpace.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t).font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(theme.textPrimary)
                    Text(sub).font(.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: CySpace.s)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
            }
            .frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    // MARK: Endurance development — riding time per week

    private func endurance(_ e: ProgressDevelopment.Endurance) -> some View {
        let h = e.averageMinutes / 60, m = e.averageMinutes % 60
        return VStack(alignment: .leading, spacing: 6) {
            title("Endurance development", chevron: true)
            figure(h > 0 ? "\(h) h \(String(format: "%02d", m))" : "\(m)", "min a week")
            line(e.direction, "\(e.fullWeeks) weeks", "Cycling · riding time · average of the last \(e.fullWeeks) full week\(e.fullWeeks == 1 ? "" : "s")")
            if let p = e.powerLine { Text(p).font(.system(.footnote)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true) }
            WeekLine(values: e.weeks, color: theme.endurance, mark: theme.background, rule: theme.separator)
                .frame(height: 76).padding(.top, 6).accessibilityHidden(true)
            ends(e.firstLabel, e.lastLabel, middle: "this week is not finished")
        }
        .accessibilityElement(children: .combine)       // the identifier is on the button that wraps this section
    }

    // MARK: Strength development — one lift, as logged

    private func strength(_ s: ProgressDevelopment.Strength) -> some View {
        let shown = units == .imperial ? s.latestKg * 2.20462 : s.latestKg
        return VStack(alignment: .leading, spacing: 6) {
            title("Strength development", chevron: true)
            figure(shown == shown.rounded() ? String(format: "%.0f", shown) : String(format: "%.1f", shown), units == .imperial ? "lb" : "kg")
            line(s.direction, "2 sessions", "\(s.liftName) · recorded top set \(s.latestText) · \(s.sessions) sessions")
            ForEach(Array(s.ranges.enumerated()), id: \.offset) { _, r in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.title).font(.caption.weight(.semibold)).foregroundStyle(theme.textPrimary)
                        Spacer(minLength: 6)
                        Text(r.note).font(.caption2).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    RangeBar(from: r.from, to: r.to, fromText: r.fromText, toText: r.toText, color: theme.strength, track: theme.separator, text: theme.textPrimary, hole: theme.background)
                        .frame(height: 22)
                }
                .padding(.top, 6)
            }
            Text("One lift, not your whole strength.").font(.caption).foregroundStyle(theme.textSecondary).padding(.top, 4)
        }
        .accessibilityElement(children: .combine)       // the identifier is on the button that wraps this section
    }

    // MARK: Training consistency — weeks with at least one session

    private func consistency(_ c: ProgressDevelopment.Consistency) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            title("Training consistency", chevron: true)
            figure("\(c.active)", "of \(c.total) weeks")
            Text("Weeks with at least one session. Participation, not performance.").font(.system(.footnote)).foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(c.weeks.enumerated()), id: \.offset) { _, w in
                    VStack(spacing: 3) {
                        if w.rides + w.lifts == 0 { Text("·").font(.caption).foregroundStyle(theme.textTertiary).frame(height: 9) }
                        ForEach(0..<min(w.rides, 4), id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill(theme.endurance).frame(width: 9, height: 9) }
                        ForEach(0..<min(w.lifts, 4), id: \.self) { _ in RoundedRectangle(cornerRadius: 2).strokeBorder(theme.strength, lineWidth: 1.6).frame(width: 9, height: 9) }
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(minHeight: 62, alignment: .bottom).padding(.top, 6).accessibilityHidden(true)
            ends("week of \(c.firstLabel)", c.lastLabel)
            HStack(spacing: CySpace.m) {
                HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(theme.endurance).frame(width: 8, height: 8); Text("endurance session") }
                HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).strokeBorder(theme.strength, lineWidth: 1.5).frame(width: 8, height: 8); Text("strength session") }
            }
            .font(.caption2).foregroundStyle(theme.textSecondary).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)       // the identifier is on the button that wraps this section
    }

    // MARK: Time in zones — measured time only

    private func zones(_ z: ProgressDevelopment.Zones) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            title(z.title, chevron: true)
            figure("\(z.easyPercent)", "%")
            Text("in zones 1–2 · \(z.hours) recorded · \(z.basis)").font(.system(.footnote)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(Array(z.shares.enumerated()), id: \.offset) { i, s in
                        if s > 0 {
                            RoundedRectangle(cornerRadius: 3).fill(theme.endurance.opacity(0.35 + 0.65 * Double(i) / Double(max(z.shares.count - 1, 1))))
                                .frame(width: max(3, (g.size.width - CGFloat(z.shares.count - 1) * 2) * CGFloat(s) / 100))
                        }
                    }
                }
            }
            .frame(height: 12).padding(.top, 6).accessibilityHidden(true)
            let cols = dts.isAccessibilitySize ? 2 : min(z.shares.count, 7)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .leading), count: cols), alignment: .leading, spacing: 4) {
                ForEach(Array(z.shares.enumerated()), id: \.offset) { i, s in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(theme.endurance.opacity(0.35 + 0.65 * Double(i) / Double(max(z.shares.count - 1, 1)))).frame(width: 7, height: 7)
                            Text("Z\(i + 1)").font(.caption2.weight(.semibold)).foregroundStyle(theme.textSecondary)
                        }
                        Text("\(s)%").font(.caption2.weight(.bold)).monospacedDigit().foregroundStyle(theme.textPrimary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)       // the identifier is on the button that wraps this section
    }
}

/// Weekly values as one line; the last point (the unfinished week) is drawn hollow and joined with a dashed segment.
private struct WeekLine: View {
    let values: [Int]
    let color: Color
    let mark: Color
    let rule: Color
    var body: some View {
        GeometryReader { g in
            let n = values.count, top = CGFloat(max(values.max() ?? 1, 1))
            let pts: [CGPoint] = values.enumerated().map { i, v in
                CGPoint(x: n > 1 ? g.size.width * CGFloat(i) / CGFloat(n - 1) : g.size.width / 2,
                        y: 6 + (g.size.height - 12) * (1 - CGFloat(v) / top))
            }
            ZStack {
                Path { p in p.move(to: CGPoint(x: 0, y: g.size.height - 1)); p.addLine(to: CGPoint(x: g.size.width, y: g.size.height - 1)) }
                    .stroke(rule, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                if n > 2 {
                    Path { p in p.move(to: pts[0]); for q in pts.dropFirst().dropLast() { p.addLine(to: q) } }
                        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                if n > 1 {
                    Path { p in p.move(to: pts[n - 2]); p.addLine(to: pts[n - 1]) }
                        .stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4]))
                    Circle().fill(color).frame(width: 8, height: 8).position(pts[n - 2])
                    Circle().fill(mark).frame(width: 8, height: 8).overlay(Circle().strokeBorder(color, lineWidth: 2)).position(pts[n - 1])
                }
            }
        }
    }
}

/// First → latest on one scale: a hollow dot where it started, a filled dot where it is now.
private struct RangeBar: View {
    let from: Double
    let to: Double
    let fromText: String
    let toText: String
    let color: Color
    let track: Color
    let text: Color
    let hole: Color
    var body: some View {
        GeometryReader { g in
            let lo = min(from, to), hi = max(from, to)
            let pad = max((hi - lo) * 0.6, hi * 0.08, 1)
            let a = lo - pad, b = hi + pad
            let inset: CGFloat = 46
            let w = max(g.size.width - inset * 2, 1)
            let x: (Double) -> CGFloat = { v in inset + w * CGFloat((v - a) / (b - a)) }
            let y = g.size.height / 2
            ZStack {
                Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y)) }.stroke(track, lineWidth: 1)
                Path { p in p.move(to: CGPoint(x: x(from), y: y)); p.addLine(to: CGPoint(x: x(to), y: y)) }.stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                // unchanged from first to latest (Lab 39: both labels were drawn on top of each other): one mark, one label
                if from != to {
                    Circle().fill(hole).frame(width: 9, height: 9).overlay(Circle().strokeBorder(color, lineWidth: 2)).position(x: x(from), y: y)
                    Text(fromText).font(.caption2).monospacedDigit().foregroundStyle(text.opacity(0.7)).fixedSize()
                        .position(x: from <= to ? x(from) - 26 : x(from) + 26, y: y)
                }
                Circle().fill(color).frame(width: 10, height: 10).position(x: x(to), y: y)
                Text(toText).font(.caption2.weight(.bold)).monospacedDigit().foregroundStyle(text).fixedSize()
                    .position(x: from <= to ? x(to) + 26 : x(to) - 26, y: y)
            }
        }
    }
}

/// A horizontal rule as a shape (so it can be dashed).
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
