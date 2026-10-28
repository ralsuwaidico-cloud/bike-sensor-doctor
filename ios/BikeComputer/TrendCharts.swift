import SwiftUI
import Charts
import Accessibility

// MARK: - Progress detailed chart (RC2-UX milestone 1, owner §5)
// One chart, one convention: solid bars = done, pale bars behind them = planned, the current (unfinished) week on the
// right, a dot at zero = sessions done without a recorded duration. Ranges 4 / 8 / 12 / 16 weeks (1 year when older
// data exists); the chart never scrolls sideways (no gesture fights the page's vertical scroll). Tap a bar: its week,
// exact value with unit, done vs planned and sessions appear in the header. Date labels are MEASURED and placed by
// TrendChartMath.axisLabels, so they cannot overlap at any width, range or text size. All maths: ProgressMetrics.swift.

struct WeeklyTrendChart: View {
    /// Full history (oldest first, the current week last), per metric.
    let riding: [WeekBucket]
    let lifting: [WeekBucket]
    /// The metrics this rider trains (one = no metric picker).
    let metrics: [TrendMetric]
    @Binding var metric: TrendMetric
    @Binding var range: ChartRange
    var identifier = "trendChart"
    @State private var selected: Int? = nil
    @State private var geom = AxisGeometry()
    @Environment(\.dynamicTypeSize) private var dts

    private var all: [WeekBucket] { metric == .riding ? riding : lifting }
    private var window: [WeekBucket] { TrendChartMath.window(all, weeks: range.weeks) }
    private var color: Color { metric == .riding ? BC.accent : BC.strength }
    private var ranges: [ChartRange] { ChartRange.available(all) }

    var body: some View {
        let v = window
        VStack(alignment: .leading, spacing: DS.s) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(t: "Trends")
                Spacer(minLength: DS.s)
                InfoButton(title: "How sessions are counted", text: Self.countingHelp)
            }
            if metrics.count > 1 { metricPicker }
            rangePicker
            Text(metric.question).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if TrendChartMath.isEmpty(v) {
                emptyState
            } else {
                header(v)
                VStack(spacing: 2) { chart(v); labelRow(v) }
                legend(v)
            }
        }
        .onChange(of: range) { _, _ in selected = nil }
        .onChange(of: metric) { _, _ in selected = nil; if !ranges.contains(range) { range = .w8 } }
    }

    // MARK: pickers: segmented, their text capped at xxLarge (five segments stay readable on a 320-pt-wide card; the
    // header and detail text below carry the large sizes, like the Health app)
    private var metricPicker: some View {
        Picker("Show", selection: $metric) { ForEach(metrics) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityIdentifier("\(identifier)-metric")
    }
    private var rangePicker: some View {
        Picker("Range", selection: $range) { ForEach(ranges) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityIdentifier("\(identifier)-range")
    }

    // MARK: header: the selected week, or the range summary
    @ViewBuilder private func header(_ v: [WeekBucket]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let i = selected, v.indices.contains(i) {
                let d = TrendChartMath.detail(v[i], metric: metric)
                Text(d.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(d.value).font(DS.number).monospacedDigit()
                Text(d.done).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Text(d.planned).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let n = d.note { Text(n).font(.footnote).foregroundStyle(BC.stale).fixedSize(horizontal: false, vertical: true) }
            } else {
                let s = TrendChartMath.rangeSummary(v, metric: metric)
                Text(s.title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(s.value).font(DS.number).monospacedDigit()
                Text(s.line).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(identifier)-header")
    }

    // MARK: the plot
    struct AxisGeometry: Equatable { var plotMinX: Double = 0; var plotWidth: Double = 0; var totalWidth: Double = 0 }
    struct AxisKey: PreferenceKey {
        static var defaultValue = AxisGeometry()
        static func reduce(value: inout AxisGeometry, nextValue: () -> AxisGeometry) { let n = nextValue(); if n.plotWidth > 0 { value = n } }
    }

    private func chart(_ v: [WeekBucket]) -> some View {
        let maxV = max(v.map { metric.value($0) }.max() ?? 0, v.map { metric.planned($0) }.max() ?? 0)
        let ticks = metric.ticks(max: maxV)
        let marks = weekMarks(v)
        return Chart {
            ForEach(marks) { m in plannedBar(m) }
            ForEach(marks) { m in doneBar(m) }
            ForEach(marks.filter { $0.noDuration }) { m in noDurationDot(m) }
            if let s = selected { selectionRule(s) }
        }
        .chartXScale(domain: -0.5...(Double(v.count) - 0.5))
        .chartYScale(domain: 0...(ticks.last ?? 1))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: ticks) { value in
                AxisGridLine()
                AxisValueLabel { if let d = value.as(Double.self) { Text(metric.axisText(d)).font(.caption) } }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { loc in select(at: loc, proxy: proxy, geo: geo, count: v.count) }
                    Color.clear.preference(key: AxisKey.self, value: axisGeometry(proxy: proxy, geo: geo))
                }
            }
        }
        .onPreferenceChange(AxisKey.self) { geom = $0 }
        .frame(height: dts.isAccessibilitySize ? 240 : 190)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityChartDescriptor(TrendChartDescriptor(metric: metric, buckets: v))
        .accessibilityIdentifier(identifier)
    }

    /// One week's marks, precomputed (plain values keep the chart builder simple for the compiler).
    struct WeekMark: Identifiable {
        let id: Int
        let x0: Double, x1: Double
        let planned: Double, done: Double
        let dim: Bool
        let label: String, value: String
        let noDuration: Bool
    }
    // one small function per mark type, every value explicitly typed (run 96/97: the type checker gave up on inline marks);
    // bars are RectangleMarks (explicit x and y ranges: never stacked, and BarMark has no xStart/xEnd/yStart/yEnd form)
    private func plannedBar(_ m: WeekMark) -> some ChartContent {
        let x0: PlottableValue<Double> = .value("Week", m.x0), x1: PlottableValue<Double> = .value("Week end", m.x1)
        let y0: PlottableValue<Double> = .value("Zero", 0), y1: PlottableValue<Double> = .value("Planned", m.planned)
        let fill: Color = color.opacity(m.dim ? 0.10 : 0.22)
        return RectangleMark(xStart: x0, xEnd: x1, yStart: y0, yEnd: y1).foregroundStyle(fill).cornerRadius(3)
    }
    private func doneBar(_ m: WeekMark) -> some ChartContent {
        let x0: PlottableValue<Double> = .value("Week", m.x0), x1: PlottableValue<Double> = .value("Week end", m.x1)
        let y0: PlottableValue<Double> = .value("Zero", 0), y1: PlottableValue<Double> = .value("Done", m.done)
        let fill: Color = m.dim ? color.opacity(0.4) : color
        let label: Text = Text(m.label), value: Text = Text(m.value)
        return RectangleMark(xStart: x0, xEnd: x1, yStart: y0, yEnd: y1).foregroundStyle(fill).cornerRadius(3).accessibilityLabel(label).accessibilityValue(value)
    }
    private func selectionRule(_ i: Int) -> some ChartContent {
        let x: PlottableValue<Double> = .value("Selected", Double(i))
        let line: Color = Color.secondary.opacity(0.6)
        return RuleMark(x: x).foregroundStyle(line).lineStyle(StrokeStyle(lineWidth: 1))
    }
    private func noDurationDot(_ m: WeekMark) -> some ChartContent {
        let x: PlottableValue<Double> = .value("Week", Double(m.id)), y: PlottableValue<Double> = .value("Zero", 0)
        let fill: Color = color
        return PointMark(x: x, y: y).symbol(.circle).symbolSize(36).foregroundStyle(fill)
    }
    private func weekMarks(_ v: [WeekBucket]) -> [WeekMark] {
        var out: [WeekMark] = []
        for (i, b) in v.enumerated() {
            let doneText: String = metric == .riding ? Fmt.duration(minutes: b.minutes) : "\(b.sessions) sessions"
            let plannedText: String = metric == .riding ? Fmt.duration(minutes: b.plannedMinutes) : "\(b.plannedSessions) sessions"
            let dim: Bool = selected != nil && selected != i
            out.append(WeekMark(id: i, x0: Double(i) - 0.34, x1: Double(i) + 0.34, planned: metric.planned(b), done: metric.value(b), dim: dim,
                                label: "Week of " + TrendChartMath.axisLabel(b.start), value: "done " + doneText + ", planned " + plannedText,
                                noDuration: metric == .riding && b.unknownDuration > 0 && b.minutes == 0))
        }
        return out
    }

    private func axisGeometry(proxy: ChartProxy, geo: GeometryProxy) -> AxisGeometry {
        guard let pf = proxy.plotFrame else { return AxisGeometry() }
        let plot = geo[pf]
        return AxisGeometry(plotMinX: plot.minX, plotWidth: plot.width, totalWidth: geo.size.width)
    }

    /// A tap selects the week under the finger; a second tap on it clears the selection.
    private func select(at loc: CGPoint, proxy: ChartProxy, geo: GeometryProxy, count: Int) {
        guard let pf = proxy.plotFrame, count > 0 else { return }
        let plot = geo[pf]
        let x = loc.x - plot.minX
        guard x >= 0, x <= plot.width else { return }
        let i = min(count - 1, max(0, Int(x / (plot.width / CGFloat(count)))))
        selected = selected == i ? nil : i
    }

    // MARK: date labels (plain Text, measured, never overlapping)
    private func labelRow(_ v: [WeekBucket]) -> some View {
        let labels = TrendChartMath.axisLabels(v.map { $0.start }, plotWidth: geom.plotWidth, gap: 8, leftRoom: geom.plotMinX,
                                               rightRoom: max(0, geom.totalWidth - geom.plotMinX - geom.plotWidth), width: measure)
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(labels, id: \.index) { l in
                Text(l.text).font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    .accessibilityIdentifier("\(identifier)-xlabel")
                    .position(x: geom.plotMinX + l.centre, y: labelHeight / 2)
            }
        }
        .frame(height: labelHeight)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
    }
    private var labelSize: DynamicTypeSize { min(dts, .xxLarge) }
    private var labelFont: UIFont {
        let cat: UIContentSizeCategory
        switch labelSize {
        case .xSmall: cat = .extraSmall
        case .small: cat = .small
        case .medium: cat = .medium
        case .large: cat = .large
        case .xLarge: cat = .extraLarge
        default: cat = .extraExtraLarge
        }
        return UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: UITraitCollection(preferredContentSizeCategory: cat))
    }
    private var labelHeight: CGFloat { ceil(labelFont.lineHeight) + 2 }
    /// The label's real width in the font it is drawn with (plus a point of rounding).
    private func measure(_ s: String) -> Double { Double(ceil((s as NSString).size(withAttributes: [.font: labelFont]).width)) + 1 }

    // MARK: legend, empty state
    private func legend(_ v: [WeekBucket]) -> some View {
        FlowRow(spacing: DS.m) {
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 12); Text("done").font(.caption) }
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.22)).frame(width: 12, height: 12); Text("planned").font(.caption) }
            if metric == .riding && v.contains(where: { $0.unknownDuration > 0 && $0.minutes == 0 }) {
                HStack(spacing: 4) { Circle().fill(color).frame(width: 8, height: 8); Text("done, no duration").font(.caption) }
            }
            Text(selected == nil ? "Tap a bar for its week." : "Tap the bar again to clear.").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            Text(metric == .riding ? "No riding in the last \(range.weeks) weeks" : "No strength sessions in the last \(range.weeks) weeks")
                .font(.headline).foregroundStyle(BC.stale).fixedSize(horizontal: false, vertical: true)
            Text(metric == .riding
                 ? "Nothing was planned or recorded in this period. Record a ride, import one from Apple Health, or choose a longer range. The chart only shows real sessions."
                 : "Nothing was planned or logged in this period. Log a session from Home or Plan, or choose a longer range. The chart only shows real sessions.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(identifier)-empty")
    }

    static let countingHelp = """
    Done (solid bars): rides recorded in Cyclift or imported from Apple Health, planned rides you marked done; strength logs, quick logs, sessions marked done and Apple Health imports.

    Time adds only measured or typed durations. A session marked done without a duration counts as a session and adds no time (a dot at zero on the riding chart).

    Planned (pale bars): the week's planned sessions that were not skipped — the same figures as "Planned this week" on Plan.

    Weeks run Monday to Sunday. The current week is still running, so averages use full weeks only.
    """
}

/// VoiceOver audio graph / chart summary for the detailed chart.
struct TrendChartDescriptor: AXChartDescriptorRepresentable {
    let metric: TrendMetric
    let buckets: [WeekBucket]
    func makeChartDescriptor() -> AXChartDescriptor {
        let labels = buckets.map { TrendChartMath.axisLabel($0.start) }
        let maxV = max(1, buckets.map { max(metric.value($0), metric.planned($0)) }.max() ?? 1)
        let x = AXCategoricalDataAxisDescriptor(title: "Week starting", categoryOrder: labels)
        let y = AXNumericDataAxisDescriptor(title: metric.unitName, range: 0...maxV, gridlinePositions: []) { metric.axisText($0) }
        let done = AXDataSeriesDescriptor(name: "Done", isContinuous: false, dataPoints: buckets.map { AXDataPoint(x: TrendChartMath.axisLabel($0.start), y: metric.value($0), additionalValues: [], label: nil) })
        let planned = AXDataSeriesDescriptor(name: "Planned", isContinuous: false, dataPoints: buckets.map { AXDataPoint(x: TrendChartMath.axisLabel($0.start), y: metric.planned($0), additionalValues: [], label: nil) })
        let s = TrendChartMath.rangeSummary(buckets, metric: metric)
        return AXChartDescriptor(title: metric.question, summary: "\(s.title): \(s.value). \(s.line)", xAxis: x, yAxis: y, additionalAxes: [], series: [done, planned])
    }
}
