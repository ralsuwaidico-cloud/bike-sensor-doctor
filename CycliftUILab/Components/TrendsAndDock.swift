import SwiftUI
import Charts

// Home v2.1: trends module (one chart, one unit), metrics dashboard, floating dock.

// MARK: Trends module

/// One chart, one labelled unit (training minutes): endurance and strength stacked per day, planned time as a
/// faint outline. Touch a day to inspect it; the tooltip lists only what the sample data holds for that day.
/// No recovery or stress score is drawn; no status rows are repeated from the indicators.
struct CyTrendsModule: View {
    let ranges: [CyTrendRange]       // first = default (7 days)
    var isLoading: Bool = false
    var emptyText: String? = nil
    var initialSelection: Int? = nil
    let onInfo: () -> Void
    let onDay: (CyTrendDay) -> Void  // "Open day" from the tooltip
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var rangeIndex = 0
    @State private var selected: Int? = nil
    @State private var didApplyInitial = false

    private var range: CyTrendRange? { ranges.indices.contains(rangeIndex) ? ranges[rangeIndex] : ranges.first }
    private var days: [CyTrendDay] { range?.days ?? [] }
    private var hasData: Bool { days.contains { $0.hasData } }

    var body: some View {
        VStack(alignment: .leading, spacing: CySpace.m) {
            HStack(spacing: CySpace.s) {
                Text("Trends").font(CyFont.title).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: onInfo) {
                    Image(systemName: "info.circle").font(.body).foregroundStyle(theme.textSecondary)
                        .frame(width: CyHit.min, height: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(CyRingButtonStyle())
                .accessibilityLabel("How this chart works")
            }
            if isLoading {
                CySkeleton(height: 130)
            } else if let emptyText {
                empty(emptyText)
            } else if !hasData {
                empty("Nothing recorded in this period.")
            } else {
                if ranges.count > 1 {
                    CySegmented(options: ranges.map(\.title), selection: Binding(get: { rangeIndex }, set: { rangeIndex = $0; selected = nil }))
                }
                legend
                chart
                tooltip
            }
        }
        .onAppear {
            if !didApplyInitial { didApplyInitial = true; selected = initialSelection }
        }
    }

    private func empty(_ text: String) -> some View {
        HStack(alignment: .top, spacing: CySpace.m) {
            Image(systemName: "chart.bar").font(.title3).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
            Text(text).font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    }

    private var legend: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: CySpace.l))
        return layout {
            key("Endurance", theme.endurance, filled: true)
            key("Strength", theme.strength, filled: true)
            key("Planned", theme.textTertiary, filled: false)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(range?.unit ?? "").font(.caption2).foregroundStyle(theme.textTertiary)
        }
        .accessibilityHidden(true)
    }
    private func key(_ name: String, _ color: Color, filled: Bool) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(filled ? color : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: filled ? [] : [2, 2])))
                .frame(width: 10, height: 10)
            Text(name).font(.caption2).foregroundStyle(theme.textSecondary).lineLimit(1)
        }
    }

    private var chart: some View {
        let big = typeSize.isAccessibilitySize
        return Chart {
            ForEach(days) { d in
                if let sel = selected, sel == d.id {
                    RectangleMark(x: .value("Day", d.label))
                        .foregroundStyle(theme.textPrimary.opacity(theme.id == .highContrast ? 0.22 : 0.07))
                }
                if let e = d.endurance, e > 0 {
                    BarMark(x: .value("Day", d.label), y: .value("Minutes", e), width: .ratio(0.5))
                        .foregroundStyle(theme.gradient(theme.endurance))
                        .cornerRadius(3)
                }
                if let s = d.strength, s > 0 {
                    BarMark(x: .value("Day", d.label), y: .value("Minutes", s), width: .ratio(0.5))
                        .foregroundStyle(theme.gradient(theme.strength))
                        .cornerRadius(3)
                }
                if let p = d.planned, p > 0 {
                    BarMark(x: .value("Day", d.label), y: .value("Minutes", p), width: .ratio(0.5))
                        .foregroundStyle(theme.textTertiary.opacity(theme.id == .highContrast ? 0.55 : 0.28))
                        .cornerRadius(3)
                }
                if !d.hasData {
                    PointMark(x: .value("Day", d.label), y: .value("Minutes", 0))
                        .symbolSize(0)
                }
            }
        }
        .chartXScale(domain: days.map(\.label))
        .chartXAxis {
            AxisMarks(values: days.map(\.label)) { value in
                AxisValueLabel {
                    if let l = value.as(String.self), let d = days.first(where: { $0.label == l }) {
                        Text(big ? d.short : d.label)
                            .font(.caption2.weight(selected == d.id ? .bold : .regular))
                            .foregroundStyle(selected == d.id ? theme.textPrimary : theme.chartAxis)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(theme.chartGrid)
                AxisValueLabel().font(.caption2).foregroundStyle(theme.chartAxis)
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        let origin = geo[proxy.plotAreaFrame].origin
                        if let label: String = proxy.value(atX: g.location.x - origin.x), let d = days.first(where: { $0.label == label }) {
                            selected = d.id
                        }
                    })
            }
        }
        .frame(height: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training minutes, \(range?.title ?? "")")
        .accessibilityValue(summary)
        .accessibilityAdjustableAction { direction in
            let ids = days.map(\.id)
            guard !ids.isEmpty else { return }
            let current = selected.flatMap { ids.firstIndex(of: $0) }
            switch direction {
            case .increment: selected = ids[min((current ?? -1) + 1, ids.count - 1)]
            case .decrement: selected = ids[max((current ?? ids.count) - 1, 0)]
            @unknown default: break
            }
        }
    }

    @ViewBuilder private var tooltip: some View {
        if let sel = selected, let d = days.first(where: { $0.id == sel }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(d.full).font(CyFont.label).foregroundStyle(theme.textPrimary)
                    Spacer(minLength: 0)
                    Button(action: { onDay(d) }) {
                        HStack(spacing: 2) { Text("Open day"); Image(systemName: "chevron.right").font(.caption2.weight(.semibold)) }
                            .font(CyFont.caption).foregroundStyle(theme.accent)
                            .frame(minHeight: CyHit.min).contentShape(Rectangle())
                    }
                    .buttonStyle(CyRingButtonStyle())
                }
                if d.rows.isEmpty {
                    Text("No data for this day.").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                } else {
                    ForEach(d.rows) { r in
                        HStack(alignment: .firstTextBaseline) {
                            Text(r.label).font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                            Spacer(minLength: CySpace.m)
                            Text(r.value).font(CyFont.footnote.weight(.semibold)).foregroundStyle(theme.textPrimary).multilineTextAlignment(.trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(CySpace.m)
            .background(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
        } else {
            Text("Touch a day to see its details.").font(.caption2).foregroundStyle(theme.textTertiary)
        }
    }

    var summary: String {
        let parts = days.map { d -> String in
            guard d.hasData else { return "\(d.full): no data" }
            var bits: [String] = []
            if let e = d.endurance, e > 0 { bits.append("endurance \(Int(e)) minutes") }
            if let s = d.strength, s > 0 { bits.append("strength \(Int(s)) minutes") }
            if let p = d.planned, p > 0 { bits.append("\(Int(p)) minutes planned") }
            return "\(d.full): \(bits.isEmpty ? "rest" : bits.joined(separator: ", "))"
        }
        let chosen = selected.flatMap { s in days.first { $0.id == s } }.map { "Selected: \($0.full). " } ?? ""
        return chosen + parts.joined(separator: ". ")
    }
}

// MARK: Metrics dashboard

struct CyMetricGrid: View {
    let tiles: [CyMetricTile]
    var isLoading: Bool = false
    var style: CyMetricStyle = .rows
    let onTile: (CyMetricTile) -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let cols = typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: CySpace.s), GridItem(.flexible(), spacing: CySpace.s)]
        VStack(alignment: .leading, spacing: CySpace.m) {
            Text("Key metrics").font(CyFont.title).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
            if style == .rows { rows } else {
            LazyVGrid(columns: cols, spacing: CySpace.s) {
                if isLoading {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 6) { CySkeleton(height: 10, width: 80); CySkeleton(height: 18, width: 70); CySkeleton(height: 8, width: 90) }
                            .padding(CySpace.m).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
                    }
                } else {
                    ForEach(tiles) { t in tile(t) }
                }
            }
            }
        }
    }

    /// Dashboard rows: icon and name on the left, value on the right with the athlete's own comparison value beneath
    /// and a neutral direction marker. One grouped surface with hairlines instead of a border per row.
    private var rows: some View {
        VStack(spacing: 0) {
            if isLoading {
                ForEach(0..<4, id: \.self) { _ in
                    HStack { CySkeleton(height: 12, width: 130); Spacer(); CySkeleton(height: 18, width: 50) }.padding(.horizontal, CySpace.m).frame(minHeight: 54)
                }
            } else {
                ForEach(tiles) { t in
                    Button(action: { onTile(t) }) {
                        HStack(spacing: CySpace.m) {
                            Image(systemName: t.icon).font(.footnote.weight(.semibold)).foregroundStyle(theme.textSecondary).frame(width: 22)
                            Text(t.name.uppercased()).font(.caption.weight(.semibold)).tracking(0.7).foregroundStyle(theme.textPrimary)
                                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1).minimumScaleFactor(0.8)
                            Spacer(minLength: CySpace.s)
                            VStack(alignment: .trailing, spacing: 0) {
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(t.value ?? "—").font(CyFont.value).foregroundStyle(t.value == nil ? theme.textTertiary : theme.textPrimary)
                                    if t.value != nil { Text(t.unit).font(.caption2).foregroundStyle(theme.textSecondary) }
                                }
                                Text(t.value == nil ? "No data" : (t.baseline ?? t.trend ?? " ")).font(.caption2).foregroundStyle(theme.textSecondary)
                            }
                            .lineLimit(1)
                            Group {
                                if let sym = t.direction.symbol, t.value != nil {
                                    Image(systemName: sym).font(.system(size: t.direction == .flat ? 6 : 8)).foregroundStyle(theme.textSecondary)
                                } else { Color.clear }
                            }
                            .frame(width: 10)
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.textTertiary)
                        }
                        .padding(.horizontal, CySpace.m)
                        .frame(minHeight: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CyRingButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(t.name)
                    .accessibilityValue(t.value.map { "\($0) \(t.unit)\(t.baseline.map { ", \($0)" } ?? "")\(t.direction == .none ? "" : ", \(t.direction.spoken)")" } ?? "No data")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens details")
                    .accessibilityIdentifier("metricRow-\(t.id)")
                    if t.id != tiles.last?.id { Rectangle().fill(theme.separator.opacity(0.6)).frame(height: 0.5).padding(.leading, CySpace.m + 22 + CySpace.m) }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
    }

    private func tile(_ t: CyMetricTile) -> some View {
        Button(action: { onTile(t) }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: t.icon).font(.caption.weight(.semibold)).foregroundStyle(theme.textSecondary).frame(width: 16)
                    Text(t.name).font(.caption.weight(.medium)).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(t.value ?? "—").font(CyFont.value).foregroundStyle(t.value == nil ? theme.textTertiary : theme.textPrimary)
                    if t.value != nil { Text(t.unit).font(.caption2).foregroundStyle(theme.textSecondary) }
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                Text(t.value == nil ? "No data" : (t.trend ?? " ")).font(.caption2)
                    .foregroundStyle(t.value == nil ? theme.textTertiary : t.trendLevel.color(theme)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(CySpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
        }
        .buttonStyle(CyCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t.name)
        .accessibilityValue(t.value.map { "\($0) \(t.unit)\(t.trend.map { ", \($0)" } ?? "")" } ?? "No data")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens details")
    }
}

// MARK: Floating dock (original Cyclift navigation: floating capsule, sliding highlight, raised centre action)

struct CyDockItem: Identifiable, Equatable {
    let id: Int                      // slot 0, 1, 3, 4 (2 is the centre action)
    let title: String
    let icon: String
}

struct CyFloatingDock: View {
    @Binding var selection: Int
    let items: [CyDockItem]          // four destinations; with the centre action that makes five
    let centreTitle: String
    let centreIcon: String
    var centreBadge: Int? = nil
    let onCentre: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stretch = false

    var body: some View {
        GeometryReader { geo in
            let slotW = geo.size.width / 5
            ZStack(alignment: .leading) {
                Capsule().fill(theme.id == .highContrast ? AnyShapeStyle(theme.surface) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(Capsule().fill(theme.surface.opacity(theme.id == .highContrast ? 0 : 0.55)))
                    .overlay(Capsule().strokeBorder(theme.id == .highContrast ? theme.border : theme.border.opacity(theme.isDark ? 0.6 : 0.9), lineWidth: theme.borderWidth))
                    .shadow(color: Color.black.opacity(theme.isDark ? 0.45 : 0.14), radius: 16, y: 8)
                if selection != 2 {
                    Capsule().fill(theme.highlightSurface)
                        .overlay(Capsule().fill(theme.selectedFill))
                        .overlay(Capsule().strokeBorder(theme.id == .highContrast ? theme.accent : Color.clear, lineWidth: 1.5))
                        .frame(width: slotW - 10, height: 48)
                        .scaleEffect(x: stretch ? 1.18 : 1, y: 1)
                        .offset(x: CGFloat(selection) * slotW + 5)
                        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.72), value: selection)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 0) {
                    ForEach(items.prefix(2)) { tab($0) }
                    centre.frame(width: slotW)
                    ForEach(items.suffix(2)) { tab($0) }
                }
            }
        }
        .frame(height: 64)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .contain)
    }

    private func select(_ id: Int) {
        guard id != selection else { return }
        if !reduceMotion { stretch = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { stretch = false } }
        selection = id
    }

    private func tab(_ item: CyDockItem) -> some View {
        let on = selection == item.id
        return Button(action: { select(item.id) }) {
            VStack(spacing: 3) {
                Image(systemName: item.icon).font(.system(size: 18, weight: .semibold))
                Text(item.title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? theme.accent : theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("dock-\(item.id)")
    }

    private var centre: some View {
        Button(action: onCentre) {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: centreIcon).font(.system(size: 22, weight: .bold)).foregroundStyle(theme.textOnAccent)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(theme.accent))
                        .overlay(Circle().strokeBorder(theme.background, lineWidth: 3))
                        .shadow(color: theme.accent.opacity(theme.usesGradients ? 0.35 : 0), radius: 8, y: 3)
                    if let b = centreBadge, b > 0 {
                        Text("\(b)").font(.caption2.weight(.bold)).foregroundStyle(theme.textPrimary)
                            .frame(minWidth: 18, minHeight: 18).background(Circle().fill(theme.surface2))
                            .overlay(Circle().strokeBorder(theme.border, lineWidth: 1))
                    }
                }
                .offset(y: -14)
                Text(centreTitle).font(.caption2.weight(.bold)).foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.8).offset(y: -14)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(CyRingButtonStyle())
        .accessibilityLabel(centreBadge.map { "\(centreTitle), \($0) sessions today" } ?? centreTitle)
        .accessibilityIdentifier("dockCentre")
    }
}
