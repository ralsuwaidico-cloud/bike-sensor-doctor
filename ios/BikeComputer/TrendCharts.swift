import SwiftUI
import Charts
import Accessibility

// MARK: - Health-style weekly charts (quality release): scrollable, tappable, readable.
// The maths (buckets, visible-range aggregate, labels, callout text) is pure and unit-tested (TrendChartMathTests);
// the view only draws it. Weekly values come from the one query layer (TrainingLedger), so they match Home and Plan.

struct WeekBucket: Identifiable, Equatable {
    var id: Date { start }
    /// Monday 00:00 of the week.
    let start: Date
    var minutes: Int
    var sessions: Int
    var km: Double = 0
    /// Completed sessions without a recorded duration (counted as sessions, add no minutes).
    var unknownDuration: Int = 0
}

enum ChartRange: String, CaseIterable, Identifiable {
    case w8 = "8 wk", w16 = "16 wk", y1 = "1 yr"
    var id: String { rawValue }
    var weeks: Int { switch self { case .w8: return 8; case .w16: return 16; case .y1: return 52 } }
    /// Label every n-th week so labels never overlap (doubled at accessibility text sizes).
    func labelStride(accessibility: Bool) -> Int {
        let base: Int
        switch self { case .w8: base = 2; case .w16: base = 4; case .y1: base = 13 }
        return accessibility ? base * 2 : base
    }
}

enum TrendChartMath {
    static let weekSeconds: TimeInterval = 7 * 86_400

    /// Mondays of the last `count` weeks ending with the week of `now`, oldest first.
    static func mondays(endingAt now: Date, count: Int, calendar cal: Calendar = .current) -> [Date] {
        let m = TrainingLedger.monday(of: now, calendar: cal)
        return (0..<max(1, count)).reversed().map { cal.date(byAdding: .day, value: -7 * $0, to: m)! }
    }

    /// Weekly buckets from the ledger. `riding` = rides (+ rides marked done); otherwise lifting sessions.
    static func buckets(_ ledger: TrainingLedger, riding: Bool, weeks: Int, now: Date, calendar cal: Calendar = .current) -> [WeekBucket] {
        mondays(endingAt: now, count: weeks, calendar: cal).map { m in
            let w = riding ? ledger.riding(weekOf: m) : ledger.lifting(weekOf: m)
            var km = 0.0
            if riding {
                let e = cal.date(byAdding: .day, value: 7, to: m)!
                km = Double(ledger.rides.filter { $0.start >= m && $0.start < e }.reduce(0) { $0 + $1.distanceM }) / 1000
            }
            return WeekBucket(start: m, minutes: w.minutes, sessions: w.completed, km: km, unknownDuration: w.unknownDuration)
        }
    }

    /// The buckets inside the visible window that starts at `scrollStart` and spans `weeks` weeks.
    static func visible(_ b: [WeekBucket], scrollStart: Date, weeks: Int, calendar cal: Calendar = .current) -> [WeekBucket] {
        let s = TrainingLedger.monday(of: scrollStart.addingTimeInterval(3 * 86_400), calendar: cal)   // nearest Monday
        let e = cal.date(byAdding: .day, value: 7 * weeks, to: s)!
        return b.filter { $0.start >= s && $0.start < e }
    }

    struct Summary: Equatable { var averageMinutes: Int; var totalMinutes: Int; var sessions: Int; var weeks: Int; var rangeText: String }
    static func summary(_ v: [WeekBucket], calendar cal: Calendar = .current) -> Summary {
        guard let first = v.first, let last = v.last else { return Summary(averageMinutes: 0, totalMinutes: 0, sessions: 0, weeks: 0, rangeText: "") }
        let total = v.reduce(0) { $0 + $1.minutes }
        let end = cal.date(byAdding: .day, value: 6, to: last.start)!
        return Summary(averageMinutes: Int((Double(total) / Double(v.count)).rounded()), totalMinutes: total, sessions: v.reduce(0) { $0 + $1.sessions }, weeks: v.count, rangeText: rangeText(first.start, end, calendar: cal))
    }

    /// "12–18 Oct", "28 Sep – 4 Oct", "29 Dec 2025 – 4 Jan 2026" (year only when the range crosses a year or is not this year).
    static func rangeText(_ a: Date, _ b: Date, now: Date = Date(), calendar cal: Calendar = .current) -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "en_GB"); df.calendar = cal; df.timeZone = cal.timeZone
        let ya = cal.component(.year, from: a), yb = cal.component(.year, from: b), yn = cal.component(.year, from: now)
        let sameMonth = cal.component(.month, from: a) == cal.component(.month, from: b) && ya == yb
        if ya != yb {
            df.dateFormat = "d MMM yyyy"; return "\(df.string(from: a)) – \(df.string(from: b))"
        }
        let year = ya != yn ? " \(ya)" : ""
        if sameMonth {
            df.dateFormat = "d"; let d1 = df.string(from: a); df.dateFormat = "d MMM"
            return "\(d1)–\(df.string(from: b))\(year)"
        }
        df.dateFormat = "d MMM"
        return "\(df.string(from: a)) – \(df.string(from: b))\(year)"
    }

    /// "12–18 Oct · 2 h 05 min · 3 rides"
    static func callout(_ b: WeekBucket, singular: String, plural: String, calendar cal: Calendar = .current, now: Date = Date()) -> String {
        let end = cal.date(byAdding: .day, value: 6, to: b.start)!
        var t = "\(rangeText(b.start, end, now: now, calendar: cal)) · \(clock(b.minutes)) · \(b.sessions) \(b.sessions == 1 ? singular : plural)"
        if b.unknownDuration > 0 { t += " (\(b.unknownDuration) without duration)" }
        return t
    }

    /// "2 h 05 min", "45 min", "0 min".
    static func clock(_ m: Int) -> String { m >= 60 ? String(format: "%d h %02d min", m / 60, m % 60) : "\(m) min" }

    /// The bucket whose week contains `d`.
    static func bucket(at d: Date?, in b: [WeekBucket], calendar cal: Calendar = .current) -> WeekBucket? {
        guard let d else { return nil }
        let m = TrainingLedger.monday(of: d, calendar: cal)
        return b.first { $0.start == m }
    }

    /// Where the chart opens: the window that ends with the most recent week.
    static func initialScrollStart(_ b: [WeekBucket], weeks: Int, calendar cal: Calendar = .current) -> Date {
        guard let last = b.last?.start else { return Date() }
        let s = cal.date(byAdding: .day, value: -7 * (weeks - 1), to: last)!
        return max(s, b.first?.start ?? s)
    }

    /// Axis label weeks: every n-th week, phased so that the OLDEST week of the window the chart opens on is labelled.
    /// The next label to the left is then a full stride away and never shows as a clipped fragment at the edge.
    static func labelDates(_ b: [WeekBucket], stride n: Int, visibleWeeks w: Int) -> [Date] {
        let starts = b.map { $0.start }
        guard !starts.isEmpty, n > 0 else { return [] }
        let phase = max(0, w - 1) % n
        return starts.enumerated().filter { (starts.count - 1 - $0.offset) % n == phase }.map { $0.element }
    }
    /// Labels sit under the middle of their bar (Thursday noon of the week).
    static let labelOffset: TimeInterval = 3.5 * 86_400
    /// Y grid in whole hours: about four lines whatever the range.
    static func yTicks(maxMinutes: Int) -> [Double] {
        let hours = max(1.0, Double(maxMinutes) / 60)
        let step = max(1, Int((hours / 4).rounded(.up)))
        return stride(from: 0, through: Double(Int(hours.rounded(.up)) + step), by: Double(step)).map { $0 * 60 }
    }
    /// The label stride actually drawn: the range's own stride, widened until two neighbouring labels are at least
    /// `minSpacing` points apart on a plot `plotWidth` points wide showing `weeks` weeks (RC2 owner report: overlapping
    /// dates). Pure, so every phone width and text size is unit-tested.
    static func drawnStride(base: Int, plotWidth: Double, weeks: Int, minSpacing: Double) -> Int {
        guard plotWidth > 0, weeks > 0 else { return max(1, base) }
        let perWeek = plotWidth / Double(weeks)
        var n = max(1, base)
        while Double(n) * perWeek < minSpacing && n < weeks { n += max(1, base) }
        return n
    }
    /// Bars cover the middle 70 % of their week; label, selection line and bar share the same centre (Thursday noon).
    static func barStart(_ monday: Date) -> Date { monday.addingTimeInterval(0.15 * weekSeconds) }
    static func barEnd(_ monday: Date) -> Date { monday.addingTimeInterval(0.85 * weekSeconds) }
    static func barMid(_ monday: Date) -> Date { monday.addingTimeInterval(0.5 * weekSeconds) }

    static func axisLabel(_ d: Date, calendar cal: Calendar = .current) -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "en_GB"); df.calendar = cal; df.timeZone = cal.timeZone; df.dateFormat = "d MMM"
        return df.string(from: d)
    }
}

/// One weekly bar chart: range picker, AVERAGE header for the visible weeks (updates while scrolling), touch-and-hold
/// selection with a callout (exact value, week, sessions), readable axis, VoiceOver audio graph.
struct WeeklyTrendChart: View {
    let title: String
    let buckets: [WeekBucket]
    let color: Color
    let singular: String
    let plural: String
    /// Weekly target in minutes (dashed line), nil = none.
    var target: Int? = nil
    var targetLabel: String = "budget"
    var identifier: String = "trendChart"
    @Binding var range: ChartRange
    @State private var scrollStart: Date = Date()
    @State private var selected: Date? = nil
    @State private var positioned = false
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        let vis = TrendChartMath.visible(buckets, scrollStart: scrollStart, weeks: range.weeks)
        let sum = TrendChartMath.summary(vis)
        let sel = TrendChartMath.bucket(at: selected, in: buckets)
        VStack(alignment: .leading, spacing: DS.s) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(t: title)
                Spacer(minLength: DS.s)
            }
            Picker("Range", selection: $range) { ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).accessibilityIdentifier("\(identifier)-range")
            header(sum: sum, sel: sel)
            VStack(spacing: 2) { chart(sel: sel); labelRow }
            Text("Tap a bar for its week; swipe to see earlier weeks.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { if !positioned { positioned = true; scrollStart = TrendChartMath.initialScrollStart(buckets, weeks: range.weeks) } }
        .onChange(of: range) { _, r in selected = nil; scrollStart = TrendChartMath.initialScrollStart(buckets, weeks: r.weeks) }
    }

    @ViewBuilder private func header(sum: TrendChartMath.Summary, sel: WeekBucket?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let b = sel {
                Text("WEEK").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(TrendChartMath.clock(b.minutes)).font(DS.number).monospacedDigit()
                Text(TrendChartMath.callout(b, singular: singular, plural: plural)).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("AVERAGE PER WEEK").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(TrendChartMath.clock(sum.averageMinutes)).font(DS.number).monospacedDigit()
                Text("\(sum.rangeText) · total \(TrendChartMath.clock(sum.totalMinutes)) · \(sum.sessions) \(sum.sessions == 1 ? singular : plural)").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(identifier)-header")
    }

    struct XLabel: Equatable { var text: String; var x: Double }
    struct XLabelKey: PreferenceKey {
        static var defaultValue: [XLabel] = []
        static func reduce(value: inout [XLabel], nextValue: () -> [XLabel]) { value += nextValue() }
    }
    @State private var labels: [XLabel] = []
    /// Labels inside the visible plot, every n-th week (n widened until they cannot touch), at their bars' centres.
    private func xLabels(proxy: ChartProxy, geo: GeometryProxy) -> [XLabel] {
        guard let pf = proxy.plotFrame else { return [] }
        let plot = geo[pf]
        let n = TrendChartMath.drawnStride(base: range.labelStride(accessibility: dts.isAccessibilitySize), plotWidth: plot.width, weeks: range.weeks, minSpacing: minLabelSpacing)
        return TrendChartMath.labelDates(buckets, stride: n, visibleWeeks: range.weeks).compactMap { m in
            guard let x = proxy.position(forX: TrendChartMath.barMid(m)), x >= 0, x <= plot.width else { return nil }
            return XLabel(text: TrendChartMath.axisLabel(m), x: plot.minX + x)
        }
    }
    /// The date row under the plot: plain Text views (readable by VoiceOver users of the list below and by the layout audit).
    private var labelRow: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(labels, id: \.text) { l in
                Text(l.text).font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    .accessibilityIdentifier("\(identifier)-xlabel")
                    .position(x: l.x, y: 9)
            }
        }
        .frame(height: 18)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
    }

    /// Minimum distance between two date labels (points): a "28 Sep" label plus air, larger for large text.
    private var minLabelSpacing: Double { dts >= .xLarge ? 66 : 54 }

    private func chart(sel: WeekBucket?) -> some View {
        let maxY = max(buckets.map { $0.minutes }.max() ?? 0, target ?? 0, 60)
        let ticks = TrendChartMath.yTicks(maxMinutes: maxY)
        return Chart {
            ForEach(buckets) { b in
                // explicit week span (no calendar "weekOfYear" unit, whose week start depends on the locale): bar,
                // label and selection share one centre
                BarMark(xStart: .value("Week", TrendChartMath.barStart(b.start)), xEnd: .value("Week end", TrendChartMath.barEnd(b.start)), y: .value("Minutes", Double(b.minutes)))
                    .foregroundStyle(sel == nil || sel?.start == b.start ? color : color.opacity(0.35))
                    .cornerRadius(3)
                    .accessibilityLabel("Week of \(TrendChartMath.axisLabel(b.start))")
                    .accessibilityValue("\(TrendChartMath.clock(b.minutes)), \(b.sessions) \(b.sessions == 1 ? singular : plural)")
            }
            if let t = target, t > 0 {
                RuleMark(y: .value(targetLabel, Double(t))).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if let b = sel {
                RuleMark(x: .value("Selected", TrendChartMath.barMid(b.start)))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartYScale(domain: 0...max(Double(maxY) * 1.15, ticks.last ?? 60))
        // the date labels are drawn below the plot by the overlay (positions from the chart itself, spacing checked);
        // the built-in x axis only reserves no space
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: ticks) { v in
                AxisGridLine()
                AxisValueLabel { if let m = v.as(Double.self) { Text(m == 0 ? "0" : "\(Int(m / 60)) h").font(.caption) } }
            }
        }
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: TrendChartMath.weekSeconds * Double(range.weeks))
        .chartScrollPosition(x: $scrollStart)
        .chartXSelection(value: $selected)
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // a tap selects a week too (a second tap on it clears the selection), like the Health app
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { loc in
                            guard let pf = proxy.plotFrame else { return }
                            let x = loc.x - geo[pf].origin.x
                            guard let d: Date = proxy.value(atX: x) else { return }
                            let m = TrainingLedger.monday(of: d)
                            selected = selected.map { TrainingLedger.monday(of: $0) } == m ? nil : TrendChartMath.barMid(m)
                        }
                    // where each date label goes (centre of its bar, in this view's coordinates) → the label row below
                    Color.clear.preference(key: XLabelKey.self, value: xLabels(proxy: proxy, geo: geo))
                }
            }
        }
        .onPreferenceChange(XLabelKey.self) { labels = $0 }
        .frame(height: dts.isAccessibilitySize ? 260 : 200)
        // axis labels stop growing at xxLarge (like the Health app); the header above carries the large text
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityChartDescriptor(TrendChartDescriptor(title: title, buckets: buckets, singular: singular, plural: plural))
        .accessibilityIdentifier(identifier)
    }
}

/// VoiceOver audio graph / chart summary for a weekly chart.
struct TrendChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let buckets: [WeekBucket]
    let singular: String
    let plural: String
    func makeChartDescriptor() -> AXChartDescriptor {
        let labels = buckets.map { TrendChartMath.axisLabel($0.start) }
        let maxV = Double(max(60, buckets.map { $0.minutes }.max() ?? 0))
        let x = AXCategoricalDataAxisDescriptor(title: "Week starting", categoryOrder: labels)
        let y = AXNumericDataAxisDescriptor(title: "Time", range: 0...maxV, gridlinePositions: []) { TrendChartMath.clock(Int($0)) }
        let series = AXDataSeriesDescriptor(name: title, isContinuous: false, dataPoints: buckets.map { b in
            AXDataPoint(x: TrendChartMath.axisLabel(b.start), y: Double(b.minutes), additionalValues: [], label: "\(b.sessions) \(b.sessions == 1 ? singular : plural)")
        })
        let s = TrendChartMath.summary(buckets)
        return AXChartDescriptor(title: title, summary: "Average \(TrendChartMath.clock(s.averageMinutes)) per week over \(s.weeks) weeks, \(s.rangeText).", xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}
