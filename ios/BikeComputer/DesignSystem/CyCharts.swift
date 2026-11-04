import SwiftUI

// MARK: - Cyclift design system: rings, charts, calendars

/// Progress ring (done ÷ planned). Animates the fill unless Reduce Motion is on.
struct CyProgressRing<Label: View>: View {
    let fraction: Double
    var size: CGFloat = 76
    var lineWidth: CGFloat = 9
    var tint: Color = CyTheme.recovery.tint
    var track: Color = CyTheme.recovery.soft
    @ViewBuilder var label: Label
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown: Double = 0

    var body: some View {
        let f = CyDesign.clampFraction(fraction)
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle().trim(from: 0, to: shown)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(CyMotion.animation(CyTheme.motionFill, reduce: reduce)) { shown = f } }
        .onChange(of: fraction) { _, new in withAnimation(CyMotion.animation(CyTheme.motionFill, reduce: reduce)) { shown = CyDesign.clampFraction(new) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue(CyDesign.percentText(f))
    }
}

extension CyProgressRing where Label == EmptyView {
    init(fraction: Double, size: CGFloat = 76, lineWidth: CGFloat = 9, tint: Color = CyTheme.recovery.tint, track: Color = CyTheme.recovery.soft) {
        self.init(fraction: fraction, size: size, lineWidth: lineWidth, tint: tint, track: track) { EmptyView() }
    }
}

/// Ring with the percent and a small caption inside ("60%" / "3 of 5").
struct CyRingLabel: View {
    let fraction: Double
    var caption: String? = nil
    var tint: Color = CyTheme.recovery.tint
    var body: some View {
        VStack(spacing: 0) {
            Text(CyDesign.percentText(fraction)).font(CyType.numeralSmall).monospacedDigit().foregroundStyle(tint)
            if let c = caption { Text(c).font(CyType.captionSmall).foregroundStyle(tint.opacity(0.85)) }
        }
        .accessibilityHidden(true)
    }
}

/// Sparkline over a series (no axes). Draws nothing meaningful with fewer than 2 points — callers gate on data first.
struct CySparkline: View {
    let values: [Double]
    var tint: Color = CyTheme.cycling.tint
    var fill: Color? = nil
    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if let f = fill, pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }.fill(f.opacity(0.35))
                }
                Path { p in
                    guard pts.count > 1 else { return }
                    p.move(to: pts[0])
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = pts.last { Circle().fill(tint).frame(width: 6, height: 6).position(last) }
            }
        }
        .accessibilityHidden(true)
    }
    private func points(in size: CGSize) -> [CGPoint] {
        let v = values.filter { $0.isFinite }
        guard v.count > 1 else { return [] }
        let lo = v.min() ?? 0, hi = v.max() ?? 1
        let span = max(hi - lo, 0.0001)
        let stepX = size.width / CGFloat(v.count - 1)
        let inset: CGFloat = 3
        return v.enumerated().map { i, y in
            CGPoint(x: CGFloat(i) * stepX, y: inset + (size.height - 2 * inset) * CGFloat(1 - (y - lo) / span))
        }
    }
}

/// Bar chart: 7/8 values, highlighted index, optional dashed plan line, values above the bars. Shows the
/// insufficient-data state when fewer than `minimumPoints` real values exist.
struct CyBarChart: View {
    let values: [Double?]
    var labels: [String] = []
    var highlighted: Int? = nil
    var planLine: Double? = nil
    var planLabel: String = "plan"
    var tint: Color = CyTheme.cycling.tint
    var soft: Color = CyTheme.cycling.soft
    var minimumPoints: Int = 3
    var unit: String = ""
    var valueText: (Double) -> String = { v in v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    var height: CGFloat = 96
    var missingUnit: String = "week"
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var grown = false

    var body: some View {
        if !CyDesign.hasEnoughData(values, minimum: minimumPoints) {
            CyInsufficientDataState(missing: minimumPoints - values.compactMap { $0 }.count, unit: missingUnit)
        } else {
            let norm = CyDesign.normalise(values, planLine: planLine)
            VStack(spacing: 4) {
                GeometryReader { geo in
                    let n = max(values.count, 1)
                    let gap: CGFloat = 6
                    let w = (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n)
                    let planNorm = planLine.flatMap { p -> Double? in
                        let top = max(values.compactMap { $0 }.max() ?? 0, p); return top > 0 ? p / top : nil
                    }
                    ZStack(alignment: .bottomLeading) {
                        if let pn = planNorm {
                            Path { p in
                                let y = geo.size.height * CGFloat(1 - pn)
                                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                            }
                            .stroke(CyTheme.ink3, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .accessibilityHidden(true)
                        }
                        HStack(alignment: .bottom, spacing: gap) {
                            ForEach(Array(norm.enumerated()), id: \.offset) { i, f in
                                VStack(spacing: 2) {
                                    if let v = values[i] { Text(valueText(v)).font(CyType.captionSmall).foregroundStyle(i == highlighted ? tint : CyTheme.ink3).lineLimit(1).minimumScaleFactor(0.6) }
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(f == nil ? CyTheme.line2 : (i == highlighted ? tint : soft))
                                        .frame(width: w, height: max(4, (geo.size.height - 16) * CGFloat(grown ? (f ?? 0.04) : 0.04)))
                                }
                                .frame(width: w)
                            }
                        }
                    }
                }
                .frame(height: height)
                if !labels.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(labels.enumerated()), id: \.offset) { i, l in
                            Text(l).font(CyType.captionSmall).foregroundStyle(i == highlighted ? CyTheme.ink : CyTheme.ink3).frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                }
            }
            .onAppear { withAnimation(CyMotion.animation(CyTheme.motionFill, reduce: reduce)) { grown = true } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bar chart")
            .accessibilityValue(summary)
        }
    }
    private var summary: String {
        let parts = values.enumerated().map { i, v -> String in
            let name = i < labels.count ? labels[i] : "\(i + 1)"
            return v.map { "\(name) \(valueText($0)) \(unit)" } ?? "\(name) no data"
        }
        return parts.joined(separator: ", ") + (planLine.map { ", \(planLabel) \(valueText($0)) \(unit)" } ?? "")
    }
}

/// Seven-day strip. Icons per sport, moon for rest, status dot; today is inverted. Tappable when `onTap` is set.
/// Caps at XL text so seven cells always fit an iPhone SE; VoiceOver labels carry the full day, sessions and status.
struct CyCalendarStrip: View {
    let days: [CyDay]
    var onTap: ((CyDay) -> Void)? = nil
    var body: some View {
        HStack(spacing: 5) {
            ForEach(days) { d in cell(d) }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cyWeekStrip")
    }
    private func cell(_ d: CyDay) -> some View {
        let content = VStack(spacing: 5) {
            Text(d.shortName).font(CyType.captionSmall).foregroundStyle(d.isToday ? CyTheme.canvas.opacity(0.8) : CyTheme.ink3)
            HStack(spacing: 1) {
                if d.status == .beforePlan {
                    // W12: a muted dash, not the rest moon
                    Text("—").font(.body.weight(.semibold)).foregroundStyle(CyTheme.ink3)
                } else {
                    ForEach(d.sport.icons, id: \.self) { i in
                        Image(systemName: i).font(d.sport == .both ? .caption : .body.weight(.semibold))
                            .foregroundStyle(iconColor(d, icon: i))
                    }
                }
            }
            .frame(height: 22)
            Circle()
                .fill(dotFill(d))
                .overlay(Circle().stroke(d.status == .planned ? (d.isToday ? CyTheme.canvas : CyTheme.ink3) : Color.clear, lineWidth: 1.5))
                .frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(d.isToday ? CyTheme.ink : CyTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        return Group {
            if let tap = onTap {
                Button { tap(d) } label: { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(d.accessibilityLabel)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .accessibilityIdentifier("cyDay-\(d.id)")
    }
    private func iconColor(_ d: CyDay, icon: String) -> Color {
        if d.isToday { return CyTheme.canvas }
        switch icon {
        case "bicycle": return CyTheme.cycling.tint
        case "dumbbell": return CyTheme.strength.tint
        default: return CyTheme.ink3
        }
    }
    private func dotFill(_ d: CyDay) -> Color {
        switch d.status {
        case .done: return CyTheme.recovery.mid
        case .missed: return CyTheme.bad
        case .planned, .none, .beforePlan: return .clear
        }
    }
}

/// Month calendar: day squares tinted by the sport done; planned days outlined; missed days ring-red; today inverted.
struct CyMonthCalendar: View {
    let cells: [CyMonthDay]
    var onTap: ((CyMonthDay) -> Void)? = nil
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    var body: some View {
        VStack(spacing: 4) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(CyDesign.weekdayShort, id: \.self) { Text(String($0.prefix(1))).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3) }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(cells) { c in cell(c) }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cyMonthCalendar")
    }
    private func cell(_ c: CyMonthDay) -> some View {
        let bg: Color = {
            if !c.inMonth { return .clear }
            if c.isToday { return CyTheme.ink }
            switch c.sport {
            case .cycling: return c.status == .done ? CyTheme.cycling.bg : CyTheme.card2
            case .strength: return c.status == .done ? CyTheme.strength.bg : CyTheme.card2
            case .both: return c.status == .done ? CyTheme.recovery.bg : CyTheme.card2
            case .rest: return CyTheme.card2
            }
        }()
        let content = VStack(spacing: 2) {
            if c.inMonth {
                Text("\(c.number)").font(CyType.captionSmall).foregroundStyle(c.isToday ? CyTheme.canvas : CyTheme.ink2)
                if c.sport != .rest {
                    HStack(spacing: 0) { ForEach(c.sport.icons, id: \.self) { Image(systemName: $0).font(.system(size: 9, weight: .semibold)) } }
                        .foregroundStyle(c.isToday ? CyTheme.canvas : (c.sport == .cycling ? CyTheme.cycling.tint : c.sport == .strength ? CyTheme.strength.tint : CyTheme.ink))
                        .frame(height: 10)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(c.status == .missed ? CyTheme.bad : (c.status == .planned && !c.isToday ? CyTheme.line : Color.clear), lineWidth: 1.5))
        .opacity(c.inMonth ? 1 : 0)
        return Group {
            if let tap = onTap, c.inMonth {
                Button { tap(c) } label: { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c.inMonth ? "\(c.number), \(c.sport.spoken)\(c.status.spoken.map { ", " + $0 } ?? "")\(c.isToday ? ", today" : "")" : "")
        .accessibilityHidden(!c.inMonth)
    }
}

/// Interval timeline: bar heights are intensity; past dimmed, current solid, future soft.
struct CyIntervalStep: Identifiable, Equatable {
    enum State: Equatable { case past, current, future }
    var id: Int
    var intensity: Double       // 0…1
    var duration: Double        // relative width
    var state: State
}

struct CyIntervalTimeline: View {
    let steps: [CyIntervalStep]
    var tint: Color = CyTheme.cycling.tint
    var mid: Color = CyTheme.cycling.mid
    var soft: Color = CyTheme.cycling.soft
    var height: CGFloat = 44
    var body: some View {
        GeometryReader { geo in
            let total = max(steps.reduce(0) { $0 + max($1.duration, 0) }, 0.0001)
            let gap: CGFloat = 2
            let usable = geo.size.width - gap * CGFloat(max(steps.count - 1, 0))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(steps) { s in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(s.state == .current ? tint : s.state == .past ? mid.opacity(0.55) : soft)
                        .frame(width: max(2, usable * CGFloat(max(s.duration, 0) / total)), height: CyDesign.barHeight(intensity: s.intensity, maxHeight: geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Interval timeline")
        .accessibilityValue("\(steps.count) steps, step \((steps.firstIndex { $0.state == .current } ?? -1) + 1) in progress")
    }
}

/// Rest timer ring: remaining ÷ total, mm:ss inside.
struct CyRestTimerRing: View {
    let remaining: Double
    let total: Double
    var tint: Color = CyTheme.strength.tint
    var size: CGFloat = 120
    var body: some View {
        CyProgressRing(fraction: CyDesign.timerFraction(remaining: remaining, total: total), size: size, lineWidth: 10, tint: tint, track: CyTheme.strength.soft) {
            VStack(spacing: 0) {
                Text(CyDesign.timerText(remaining)).font(CyType.numeral).monospacedDigit().foregroundStyle(CyTheme.ink)
                Text("rest").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3)
            }
            .accessibilityHidden(true)
        }
        .accessibilityLabel("Rest timer")
        .accessibilityValue("\(CyDesign.timerText(remaining)) remaining")
    }
}
