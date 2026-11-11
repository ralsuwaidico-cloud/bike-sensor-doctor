import SwiftUI
import Charts

// Charts: line / multi-series with series selection, point inspection, gaps for missing days, categorical status rows
// (words, never numbers), weekly bars, empty and loading states, and a spoken summary.

struct CyChip: View {
    let title: String
    let color: Color
    let isOn: Bool
    let action: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        Button(action: action) {
            HStack(spacing: CySpace.xs) {
                Circle().fill(isOn ? color : Color.clear).overlay(Circle().strokeBorder(color, lineWidth: 1.5)).frame(width: 10, height: 10)
                Text(title).font(CyFont.caption).foregroundStyle(isOn ? theme.textPrimary : theme.textTertiary)
            }
            .padding(.horizontal, CySpace.m)
            .frame(minHeight: 32)
            .background(Capsule().fill(isOn ? theme.surface2 : Color.clear))
            .overlay(Capsule().strokeBorder(theme.border, lineWidth: theme.borderWidth))
            .frame(minHeight: CyHit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "shown" : "hidden")
        .accessibilityHint("Shows or hides this series")
    }
}

struct CyTrendChart: View {
    let title: String
    let series: [CySeries]
    var statusRows: [CyStatusRow] = []
    var dayLabels: [String] = []
    var yDomain: ClosedRange<Double>? = nil
    var isLoading: Bool = false
    var emptyMessage: String? = nil
    var footnote: String? = nil
    @Environment(\.cyTheme) private var theme
    @State private var hidden: Set<String> = []
    @State private var selected: Int? = nil

    private var labels: [String] { dayLabels.isEmpty ? (series.first?.points.map(\.label) ?? []) : dayLabels }
    private var count: Int { max(series.first?.points.count ?? 0, statusRows.first?.cells.count ?? 0) }
    private var visible: [CySeries] { series.filter { !hidden.contains($0.id) } }
    private var visibleRows: [CyStatusRow] { statusRows.filter { !hidden.contains($0.id) } }
    private var hasAnyData: Bool {
        series.contains { $0.points.contains { $0.value != nil } } || statusRows.contains { $0.cells.contains { $0.word != nil } }
    }

    var body: some View {
        CyCard {
            VStack(alignment: .leading, spacing: CySpace.m) {
                CyOverline(text: title, icon: "chart.xyaxis.line")
                if isLoading {
                    CySkeleton(height: 120); CySkeleton(height: 12, width: 180)
                } else if let emptyMessage {
                    emptyView(emptyMessage)
                } else if !hasAnyData {
                    emptyView("Nothing to chart yet.")
                } else {
                    chips
                    if !visible.isEmpty { chart }
                    ForEach(visibleRows) { row in statusRow(row) }
                    readout
                    if let footnote { Text(footnote).font(.caption2).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true) }
                }
            }
        }
    }

    private func emptyView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            Image(systemName: "chart.line.flattrend.xyaxis").font(.title2).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
            Text(message).font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CySpace.s) {
                ForEach(series) { s in
                    CyChip(title: s.name, color: s.colorKey.color(theme), isOn: !hidden.contains(s.id)) { toggle(s.id) }
                }
                ForEach(statusRows) { r in
                    CyChip(title: r.name, color: r.colorKey.color(theme), isOn: !hidden.contains(r.id)) { toggle(r.id) }
                }
            }
        }
    }
    private func toggle(_ id: String) {
        let total = series.count + statusRows.count
        if hidden.contains(id) { hidden.remove(id) } else if hidden.count < total - 1 { hidden.insert(id) }   // one always stays
    }

    /// Consecutive non-nil points share a segment, so a missing day leaves a gap instead of a joined line.
    private func segments(_ s: CySeries) -> [(key: String, point: CySeriesPoint)] {
        var out: [(key: String, point: CySeriesPoint)] = []
        var seg = 0
        var previousWasNil = false
        for p in s.points {
            if p.value == nil { previousWasNil = true; continue }
            if previousWasNil { seg += 1; previousWasNil = false }
            out.append((key: "\(s.id)-\(seg)", point: p))
        }
        return out
    }

    private var chart: some View {
        Chart {
            ForEach(visible) { s in
                let color = s.colorKey.color(theme)
                ForEach(segments(s), id: \.point.id) { item in
                    LineMark(x: .value("Day", Double(item.point.id)), y: .value(s.name, item.point.value ?? 0), series: .value("Series", item.key))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    PointMark(x: .value("Day", Double(item.point.id)), y: .value(s.name, item.point.value ?? 0))
                        .foregroundStyle(color)
                        .symbolSize(selected == item.point.id ? 90 : 28)
                }
            }
            if let sel = selected {
                RuleMark(x: .value("Day", Double(sel)))
                    .foregroundStyle(theme.textSecondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: -0.5...(Double(max(count - 1, 1)) + 0.9))   // room for the last day label
        .chartYScale(domain: yDomain ?? autoDomain)
        .chartXAxis {
            AxisMarks(values: (0..<count).map { Double($0) }) { value in
                AxisGridLine().foregroundStyle(theme.chartGrid)
                AxisValueLabel {
                    if let d = value.as(Double.self), Int(d) >= 0, Int(d) < labels.count {
                        Text(labels[Int(d)]).font(.caption2).foregroundStyle(theme.chartAxis)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(theme.chartGrid)
                AxisValueLabel().font(.caption2).foregroundStyle(theme.chartAxis)
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        let origin = geo[proxy.plotAreaFrame].origin
                        if let x: Double = proxy.value(atX: g.location.x - origin.x) {
                            selected = min(max(Int(x.rounded()), 0), max(count - 1, 0))
                        }
                    })
            }
        }
        .frame(height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) chart")
        .accessibilityValue(summary)
    }

    private var autoDomain: ClosedRange<Double> {
        let vals = visible.flatMap { $0.points.compactMap(\.value) }
        guard let lo = vals.min(), let hi = vals.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.15, 1)
        return (lo - pad)...(hi + pad)
    }

    private func statusRow(_ row: CyStatusRow) -> some View {
        VStack(alignment: .leading, spacing: CySpace.xs) {
            Text(row.name).font(.caption2.weight(.semibold)).foregroundStyle(theme.textSecondary)
            HStack(spacing: 4) {
                ForEach(row.cells) { cell in
                    Button(action: { selected = cell.id }) {
                        ZStack {
                            if cell.word == nil {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(theme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                            } else {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(cell.level.color(theme).opacity(selected == cell.id ? 0.45 : 0.22))
                                Image(systemName: cell.level.icon).font(.caption2).foregroundStyle(cell.level.color(theme))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(selected == cell.id ? theme.textPrimary : Color.clear, lineWidth: 1.5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(row.name), \(cell.id < labels.count ? labels[cell.id] : "day \(cell.id + 1)")")
                    .accessibilityValue(cell.word ?? "No data")
                }
            }
        }
    }

    @ViewBuilder private var readout: some View {
        if let sel = selected, sel < count {
            let day = sel < labels.count ? labels[sel] : "Day \(sel + 1)"
            VStack(alignment: .leading, spacing: 2) {
                Text(day).font(CyFont.caption).foregroundStyle(theme.textPrimary)
                ForEach(visible) { s in
                    let v = s.points.first { $0.id == sel }?.value
                    Text("\(s.name): \(v.map { "\(Int($0.rounded()))\(s.unit)" } ?? "no data")").font(.caption2).foregroundStyle(theme.textSecondary)
                }
                ForEach(visibleRows) { r in
                    Text("\(r.name): \(r.cells.first { $0.id == sel }?.word ?? "no data")").font(.caption2).foregroundStyle(theme.textSecondary)
                }
            }
            .padding(CySpace.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).fill(theme.surface2))
            .accessibilityElement(children: .combine)
        } else {
            Text("Touch the chart or a day to inspect it.").font(.caption2).foregroundStyle(theme.textTertiary)
        }
    }

    /// Spoken summary: first, last, lowest and highest value of each visible series, and the latest status words.
    var summary: String {
        var parts: [String] = []
        for s in visible {
            let vals = s.points.compactMap { p in p.value.map { (p.label, $0) } }
            guard let first = vals.first, let last = vals.last else { parts.append("\(s.name): no data"); continue }
            let lo = vals.min { $0.1 < $1.1 }!, hi = vals.max { $0.1 < $1.1 }!
            parts.append("\(s.name) from \(Int(first.1.rounded()))\(s.unit) on \(first.0) to \(Int(last.1.rounded()))\(s.unit) on \(last.0), lowest \(Int(lo.1.rounded())), highest \(Int(hi.1.rounded()))")
        }
        for r in visibleRows {
            if let latest = r.cells.last(where: { $0.word != nil })?.word { parts.append("\(r.name) latest: \(latest)") } else { parts.append("\(r.name): no data") }
        }
        return parts.joined(separator: ". ")
    }
}

/// Weekly totals as bars, with a spoken summary and an empty state.
struct CyWeeklyBars: View {
    let title: String
    let points: [CySeriesPoint]
    let unit: String
    let category: CyCategory
    var emptyText: String = "Weekly trend appears after two weeks of sessions."
    @Environment(\.cyTheme) private var theme

    var body: some View {
        CyCard {
            VStack(alignment: .leading, spacing: CySpace.m) {
                CyOverline(text: title, icon: category.icon, tint: category.color(theme))
                if points.compactMap(\.value).count < 2 {
                    Text(emptyText).font(CyFont.callout).foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                } else {
                    Chart(points) { p in
                        BarMark(x: .value("Week", p.label), y: .value(unit, p.value ?? 0))
                            .foregroundStyle(category.color(theme))
                            .cornerRadius(4)
                    }
                    .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.caption2).foregroundStyle(theme.chartAxis) } }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine().foregroundStyle(theme.chartGrid)
                            AxisValueLabel().font(.caption2).foregroundStyle(theme.chartAxis)
                        }
                    }
                    .frame(height: 120)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(title) chart")
                    .accessibilityValue(points.map { "\($0.label): \($0.value.map { "\(Int($0.rounded())) \(unit)" } ?? "no data")" }.joined(separator: ", "))
                }
            }
        }
    }
}
