import SwiftUI
import Charts

// Home v2.2 — interactive multi-series trend graph (replaces the v2.1 bar chart on Home).
//
// • Lines with point markers. Monotone interpolation: smooth between real points, never overshooting them.
// • A missing day is a GAP: the line is split there and no point is drawn. Nothing is interpolated across it.
// • Up to two labelled scales (left and right) when units differ; each series is drawn against its own scale and the
//   axis labels carry the unit. A single-selection mode shows one metric at a time on its own scale.
// • Tap a day or drag across the plot to select: vertical guide, enlarged points, date and exact values in the panel.
// • Each day is also an accessibility element (and a test target) positioned over its column.

struct CyTrendsGraph: View {
    let ranges: [CyGraphRange]       // first = default (7 days)
    var isLoading: Bool = false
    var emptyText: String? = nil
    var initialMode: String? = nil
    var initialRange: String? = nil
    var initialSelection: Int? = nil
    let onInfo: () -> Void
    let onDay: (CyGraphDate, [CyTrendDetailRow]) -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.cyStaticRender) private var staticRender
    @State private var rangeIndex = 0
    @State private var modeIndex = 0
    @State private var hidden: Set<String> = []          // multi-selection modes: hidden series ids
    @State private var single: [String: String] = [:]    // single-selection modes: mode id → chosen series id
    @State private var selected: Int? = nil
    @State private var didInit = false

    private var range: CyGraphRange? { ranges.indices.contains(rangeIndex) ? ranges[rangeIndex] : ranges.first }
    private var mode: CyGraphMode? {
        guard let r = range else { return nil }
        return r.modes.indices.contains(modeIndex) ? r.modes[modeIndex] : r.modes.first
    }
    private var dates: [CyGraphDate] { range?.dates ?? [] }
    private var visible: [CyGraphSeries] {
        guard let m = mode else { return [] }
        if m.singleSelection {
            let chosen = single[m.id] ?? m.series.first?.id
            return m.series.filter { $0.id == chosen }
        }
        return m.series.filter { !hidden.contains($0.id) }
    }
    private var hasData: Bool { (mode?.series ?? []).contains { $0.values.contains { $0 != nil } } }

    var body: some View {
        VStack(alignment: .leading, spacing: CySpace.m) {
            HStack(spacing: CySpace.s) {
                Text("Trends").font(CyFont.title).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
                Text("SAMPLE").font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(theme.warning)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .overlay(Capsule().strokeBorder(theme.warning.opacity(0.8), lineWidth: 1))
                    .accessibilityLabel("Sample data")
                Spacer(minLength: 0)
                Button(action: onInfo) {
                    Image(systemName: "info.circle").font(.body).foregroundStyle(theme.textSecondary)
                        .frame(width: CyHit.min, height: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(CyRingButtonStyle())
                .accessibilityLabel("How this graph works")
                .accessibilityIdentifier("trendsInfo")
            }
            if isLoading {
                CySkeleton(height: 36); CySkeleton(height: 150)
            } else if let emptyText {
                empty(emptyText)
            } else if ranges.isEmpty || !hasData && (range?.modes.count ?? 0) <= 1 {
                empty("Nothing recorded in this period.")
            } else {
                modePicker
                HStack(spacing: CySpace.s) {
                    rangePicker
                    Spacer(minLength: 0)
                }
                chips
                if visible.contains(where: { $0.values.contains { $0 != nil } }) {
                    axisTitles
                    chart
                } else {
                    empty("No data for this metric in this period.")
                }
                panel
                if let note = mode?.note { Text(note).font(.caption2).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .onAppear {
            guard !didInit else { return }
            didInit = true
            if let r = initialRange, let i = ranges.firstIndex(where: { $0.id == r }) { rangeIndex = i }
            if let m = initialMode, let i = range?.modes.firstIndex(where: { $0.id == m }) { modeIndex = i }
            selected = initialSelection
        }
    }

    private func empty(_ text: String) -> some View {
        HStack(alignment: .top, spacing: CySpace.m) {
            Image(systemName: "chart.xyaxis.line").font(.title3).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
            Text(text).font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trendsEmpty")
    }

    // MARK: controls

    private var modePicker: some View {
        let modes = range?.modes ?? []
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            ForEach(Array(modes.enumerated()), id: \.element.id) { i, m in
                let on = i == modeIndex
                Button(action: { modeIndex = i; selected = nil }) {
                    Text(m.title).font(CyFont.caption).foregroundStyle(on ? theme.textOnAccent : theme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .padding(.horizontal, CySpace.s)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Capsule().fill(on ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.surface)))
                        .overlay(Capsule().strokeBorder(on ? Color.clear : theme.cardStroke, lineWidth: theme.borderWidth))
                        .frame(minHeight: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(CyRingButtonStyle())
                .accessibilityLabel(m.title)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("trendsMode-\(m.id)")
            }
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 2) {
            ForEach(Array(ranges.enumerated()), id: \.element.id) { i, r in
                let on = i == rangeIndex
                Button(action: { rangeIndex = i; selected = nil }) {
                    Text(r.title).font(CyFont.caption).foregroundStyle(on ? theme.textPrimary : theme.textSecondary)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, CySpace.m).frame(minHeight: 30)
                        .background(Capsule().fill(on ? theme.selectedFill : Color.clear))
                        .overlay(Capsule().strokeBorder(on && theme.id == .highContrast ? theme.accent : Color.clear, lineWidth: 1.5))
                        .frame(minHeight: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(CyRingButtonStyle())
                .accessibilityLabel(r.title)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("trendsRange-\(r.id)")
            }
        }
    }

    /// Series switches. Multi-selection: show / hide (one always stays on). Single-selection: choose one metric.
    private var chips: some View {
        let m = mode
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: CySpace.s))
        return layout {
            ForEach(m?.series ?? []) { s in
                let on = visible.contains { $0.id == s.id }
                Button(action: { toggle(s) }) {
                    HStack(spacing: 5) {
                        ZStack {
                            Capsule().fill(on ? s.color.color(theme) : Color.clear).frame(width: 14, height: 3)
                            if !on || s.dashed { Capsule().strokeBorder(s.color.color(theme), style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 14, height: 4) }
                            if on { Circle().fill(s.color.color(theme)).frame(width: 6, height: 6) }
                        }
                        .frame(width: 16)
                        Text(s.name).font(CyFont.caption).foregroundStyle(on ? theme.textPrimary : theme.textTertiary).lineLimit(1)
                    }
                    .frame(minHeight: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(CyRingButtonStyle())
                .accessibilityLabel(s.name)
                .accessibilityValue(on ? "shown" : "hidden")
                .accessibilityHint(m?.singleSelection == true ? "Shows this metric" : "Shows or hides this series")
                .accessibilityIdentifier("trendsSeries-\(s.id)")
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
    }
    private func toggle(_ s: CyGraphSeries) {
        guard let m = mode else { return }
        if m.singleSelection { single[m.id] = s.id; return }
        if hidden.contains(s.id) { hidden.remove(s.id) }
        else if m.series.filter({ !hidden.contains($0.id) }).count > 1 { hidden.insert(s.id) }   // one always stays
    }

    // MARK: scales

    private func domain(_ axis: CyGraphAxis) -> ClosedRange<Double>? {
        let list = visible.filter { $0.axis == axis }
        guard !list.isEmpty else { return nil }
        if let fixed = list.compactMap(\.fixedDomain).first { return fixed }
        let vals = list.flatMap { $0.values.compactMap { $0 } }
        guard let lo = vals.min(), let hi = vals.max() else { return nil }
        if lo >= 0 && lo < (hi - lo) * 1.5 { return 0...CyTrendsGraph.nice(hi) }      // quantities that start near zero
        let pad = max((hi - lo) * 0.25, 1)
        return (lo - pad).rounded(.down)...(hi + pad).rounded(.up)
    }
    static func nice(_ v: Double) -> Double {
        guard v > 0 else { return 1 }
        let mag = pow(10, floor(log10(v)))
        for step in [1.0, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10] where step * mag >= v { return step * mag }
        return 10 * mag
    }
    private func norm(_ v: Double, _ s: CyGraphSeries) -> Double {
        guard let d = domain(s.axis), d.upperBound > d.lowerBound else { return 0 }
        return (v - d.lowerBound) / (d.upperBound - d.lowerBound)
    }
    private func axisText(_ t: Double, _ axis: CyGraphAxis) -> String {
        guard let d = domain(axis) else { return "" }
        let v = d.lowerBound + t * (d.upperBound - d.lowerBound)
        return abs(v) >= 100 || v == v.rounded() ? "\(Int(v.rounded()))" : String(format: "%.1f", v)
    }
    private func unitTitle(_ axis: CyGraphAxis) -> (text: String, color: Color)? {
        let list = visible.filter { $0.axis == axis }
        guard let first = list.first else { return nil }
        let units = Array(Set(list.map(\.unit))).sorted().joined(separator: " / ")
        let sample = list.contains { $0.isSampleScore } ? " · sample" : ""
        return (list.count == 1 ? "\(first.name) (\(units))\(sample)" : "\(units)\(sample)", list.count == 1 ? first.color.color(theme) : theme.chartAxis)
    }

    private var axisTitles: some View {
        let big = typeSize.isAccessibilitySize
        let layout = big ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            if let l = unitTitle(.leading) { Text(big ? "Left: \(l.text)" : l.text).font(.caption2.weight(.semibold)).foregroundStyle(l.color).lineLimit(big ? 2 : 1).minimumScaleFactor(0.8) }
            if !big { Spacer(minLength: CySpace.s) }
            if let r = unitTitle(.trailing) { Text(big ? "Right: \(r.text)" : r.text).font(.caption2.weight(.semibold)).foregroundStyle(r.color).lineLimit(big ? 2 : 1).minimumScaleFactor(0.8) }
        }
        .accessibilityHidden(true)
    }

    // MARK: chart

    /// Consecutive measured days share a segment; a missing day ends it, so the line breaks instead of bridging the gap.
    private func segments(_ s: CyGraphSeries) -> [(key: String, index: Int, value: Double)] {
        var out: [(key: String, index: Int, value: Double)] = []
        var seg = 0
        var gap = false
        for (i, v) in s.values.enumerated() {
            guard let v else { gap = true; continue }
            if gap { seg += 1; gap = false }
            out.append((key: "\(s.id)-\(seg)", index: i, value: v))
        }
        return out
    }

    private var chart: some View {
        let big = typeSize.isAccessibilitySize
        let count = dates.count
        let hasTrailing = domain(.trailing) != nil
        return Chart {
            if let sel = selected {
                RuleMark(x: .value("Day", Double(sel)))
                    .foregroundStyle(theme.textSecondary.opacity(theme.id == .highContrast ? 1 : 0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(visible) { s in
                let color = s.color.color(theme)
                ForEach(segments(s), id: \.index) { p in
                    LineMark(x: .value("Day", Double(p.index)), y: .value("Value", norm(p.value, s)), series: .value("Series", p.key))
                        .foregroundStyle(color)
                        .interpolationMethod(count > 10 ? .linear : .monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round, dash: s.dashed ? [5, 4] : []))
                    PointMark(x: .value("Day", Double(p.index)), y: .value("Value", norm(p.value, s)))
                        .foregroundStyle(color)
                        .symbolSize(selected == p.index ? 110 : (count > 10 ? 14 : 36))
                }
            }
        }
        .chartXScale(domain: 0...Double(max(count - 1, 1)), range: .plotDimension(padding: 18))
        .chartYScale(domain: -0.06...1.08)
        .chartXAxis(.hidden)     // day labels are drawn by the overlay so the first and last label are never clipped
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(theme.chartGrid)
                AxisValueLabel {
                    if let t = value.as(Double.self) { Text(axisText(t, .leading)).font(.caption2).foregroundStyle(unitTitle(.leading)?.color ?? theme.chartAxis) }
                }
            }
            AxisMarks(position: .trailing, values: [0, 0.5, 1]) { value in
                AxisValueLabel {
                    if hasTrailing, let t = value.as(Double.self) { Text(axisText(t, .trailing)).font(.caption2).foregroundStyle(unitTitle(.trailing)?.color ?? theme.chartAxis) }
                }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = geo[proxy.plotAreaFrame]
                ZStack(alignment: .topLeading) {
                    // A tap selects a day and a horizontal drag scrubs. The touch layer only claims drags that start
                    // horizontally, so a vertical swipe that starts on the graph scrolls the page as usual.
                    if !staticRender { GraphTouchLayer { px in
                        if let x: Double = proxy.value(atX: px - plot.origin.x) {
                            let i = min(max(Int(x.rounded()), 0), max(count - 1, 0))
                            if selected != i { selected = i }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .accessibilityHidden(true) }
                    ForEach(dates) { d in
                        if let px = proxy.position(forX: Double(d.id)), let text = (big && count <= 7 ? Optional(d.short) : d.axisLabel) {
                            Text(text)
                                .font(.caption2.weight(selected == d.id ? .bold : .regular))
                                .foregroundStyle(selected == d.id ? theme.textPrimary : theme.chartAxis)
                                .lineLimit(1).fixedSize()
                                .position(x: plot.origin.x + px, y: plot.maxY + (big ? 16 : 11))
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    // one accessible element per day, over its column (VoiceOver target and interaction-test target)
                    ForEach(dates) { d in
                        if let px = proxy.position(forX: Double(d.id)) {
                            let w = max(plot.width / CGFloat(max(count, 1)), 6)
                            Color.clear
                                .frame(width: w, height: plot.height)
                                .position(x: plot.origin.x + px, y: plot.origin.y + plot.height / 2)
                                .allowsHitTesting(false)
                                .accessibilityElement()
                                .accessibilityLabel(d.full)
                                .accessibilityValue(spoken(d.id))
                                .accessibilityAddTraits(selected == d.id ? [.isButton, .isSelected] : .isButton)
                                .accessibilityAction { selected = d.id }
                                .accessibilityIdentifier("trendsDay-\(d.id)")
                        }
                    }
                }
            }
        }
        .frame(height: 168)
        .padding(.bottom, big ? 30 : 20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(mode?.title ?? "Trends"), \(range?.title ?? "")")
        .accessibilityIdentifier("trendsChart")
    }

    private func spoken(_ i: Int) -> String {
        visible.map { s in "\(s.name) \(i < s.values.count ? s.text(s.values[i]) : "No data")" }.joined(separator: ", ")
    }

    // MARK: selection panel

    private func rows(_ i: Int) -> [CyTrendDetailRow] {
        (mode?.series ?? []).map { s in
            CyTrendDetailRow(id: s.id, label: s.isSampleScore ? "\(s.name) (sample)" : s.name, value: i < s.values.count ? s.text(s.values[i]) : "No data")
        }
    }

    @ViewBuilder private var panel: some View {
        if let sel = selected, let d = dates.first(where: { $0.id == sel }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(d.full).font(CyFont.label).foregroundStyle(theme.textPrimary)
                        .accessibilityIdentifier("trendsPanelDate")
                    Spacer(minLength: 0)
                    Button(action: { onDay(d, rows(sel)) }) {
                        HStack(spacing: 2) { Text("Open day"); Image(systemName: "chevron.right").font(.caption2.weight(.semibold)) }
                            .font(CyFont.caption).foregroundStyle(theme.accent)
                            .frame(minHeight: CyHit.min).contentShape(Rectangle())
                    }
                    .buttonStyle(CyRingButtonStyle())
                    .accessibilityIdentifier("trendsOpenDay")
                }
                ForEach(visible) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle().fill(s.color.color(theme)).frame(width: 7, height: 7)
                        Text(s.isSampleScore ? "\(s.name) (sample)" : s.name).font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                        Spacer(minLength: CySpace.m)
                        Text(sel < s.values.count ? s.text(s.values[sel]) : "No data").font(CyFont.footnote.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(sel < s.values.count && s.values[sel] != nil ? theme.textPrimary : theme.textTertiary)
                            .accessibilityIdentifier("trendsValue-\(s.id)")
                    }
                }
            }
            .padding(CySpace.m)
            .background(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
        } else {
            Text("Touch or drag across the graph to inspect a day.").font(.caption2).foregroundStyle(theme.textTertiary)
                .accessibilityIdentifier("trendsHint")
        }
    }
}

/// Touch handling for the graph. UIKit recognisers are used on purpose: a horizontal-only pan is the standard way to
/// scrub inside a vertically scrolling page without ever trapping the scroll.
private struct GraphTouchLayer: UIViewRepresentable {
    let onPick: (CGFloat) -> Void            // x position inside the layer

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isAccessibilityElement = false
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        v.addGestureRecognizer(pan)
        v.addGestureRecognizer(tap)
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.onPick = onPick }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onPick: (CGFloat) -> Void
        init(onPick: @escaping (CGFloat) -> Void) { self.onPick = onPick }
        @objc func pan(_ g: UIPanGestureRecognizer) {
            if g.state == .began || g.state == .changed { onPick(g.location(in: g.view).x) }
        }
        @objc func tap(_ g: UITapGestureRecognizer) {
            if g.state == .ended { onPick(g.location(in: g.view).x) }
        }
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = g as? UIPanGestureRecognizer else { return true }
            let v = p.velocity(in: p.view)
            return abs(v.x) > abs(v.y)       // vertical movement is left to the page scroll
        }
    }
}

/// True only while the Lab renders the full-length review image (the image renderer cannot draw UIKit views).
private struct CyStaticRenderKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var cyStaticRender: Bool {
        get { self[CyStaticRenderKey.self] }
        set { self[CyStaticRenderKey.self] = newValue }
    }
}
