import SwiftUI

// Shared pieces of the Home-circle dashboards (owner, 23 Nov 2026, 19:55): Training Mix and Recovery are drawn with the
// approved Consistency Dashboard's own measures — the same card, selector, chart frame, floating label, summary card and
// row typography — so the three read as one family. The Consistency screen itself is approved and locked and keeps its
// own file untouched; this file repeats its values rather than changing it.

struct DashColumn: Identifiable {
    var id: Int
    var top: String
    var bottom: String
    var spoken: String
    /// One or two lines for the floating label.
    var tip: [String]
    /// Height of the mark's top on the chart's scale, 0…1; nil = it sits on the baseline.
    var anchor: Double?
}

struct DashGeo {
    var left: CGFloat, cw: CGFloat, width: CGFloat, height: CGFloat, top: CGFloat, bottom: CGFloat
    func x(_ i: Int) -> CGFloat { left + cw * (CGFloat(i) + 0.5) }
    func y(_ f: Double) -> CGFloat { top + (height - top - bottom) * (1 - CGFloat(min(max(f, 0), 1))) }
    var base: CGFloat { y(0) }
}

enum DashTipPlacement { case rule, topStrip }

/// The chart frame: axis labels, grid, one pressable column per period, the highlight of the chosen column and its
/// floating label. What is plotted is supplied by the page.
struct DashChart<Marks: View>: View {
    @Environment(\.cyTheme) private var theme
    var prefix: String
    var columns: [DashColumn]
    /// Top, middle and bottom labels of the scale.
    var axis: [String]
    var left: CGFloat = 26
    var selected: Int?
    var placement: DashTipPlacement
    /// Shown in the plot when there is nothing to draw.
    var empty: String? = nil
    var onTap: (Int) -> Void
    var onDrag: (Int) -> Void
    @ViewBuilder var marks: (DashGeo) -> Marks

    static var plotHeight: CGFloat { 192 }
    /// Room kept clear above the scale's top line for the floating label: two lines in the strip, or one label above the
    /// highest point.
    private var topInset: CGFloat { placement == .topStrip ? 54 : 46 }
    private static var bottomInset: CGFloat { 10 }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let n = max(columns.count, 1)
                let geo = DashGeo(left: left, cw: (g.size.width - left) / CGFloat(n), width: g.size.width, height: g.size.height, top: topInset, bottom: Self.bottomInset)
                ZStack(alignment: .topLeading) {
                    ForEach(0..<3, id: \.self) { k in
                        let f = 1 - Double(k) / 2
                        Path { p in p.move(to: CGPoint(x: left, y: geo.y(f))); p.addLine(to: CGPoint(x: g.size.width, y: geo.y(f))) }
                            .stroke(theme.chartGrid, style: StrokeStyle(lineWidth: 1, dash: k == 1 ? [3, 4] : []))
                        Text(k < axis.count ? axis[k] : "").font(.system(size: 10, weight: .medium)).foregroundStyle(theme.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(width: left - 6, alignment: .trailing).position(x: (left - 6) / 2, y: geo.y(f))
                            .accessibilityHidden(true)
                    }
                    if let i = selected, i < columns.count {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.selectedFill)
                            .frame(width: geo.cw - 4, height: geo.height - topInset + 14).offset(x: left + geo.cw * CGFloat(i) + 2, y: topInset - 14)
                    }
                    marks(geo)
                    if let e = empty {
                        Text(e).font(CyFont.footnote).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
                            .frame(width: g.size.width - left - 16).position(x: left + (g.size.width - left) / 2, y: geo.y(0.5))
                            .accessibilityIdentifier("\(prefix)Empty")
                    }
                    HStack(spacing: 0) {
                        ForEach(columns) { c in
                            Button { onTap(c.id) } label: { Color.clear.contentShape(Rectangle()) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(c.spoken)
                                .accessibilityHint("Shows this period")
                                .accessibilityAddTraits(selected == c.id ? [.isButton, .isSelected] : [.isButton])
                                .accessibilityIdentifier("\(prefix)Point-\(c.id)")
                        }
                    }
                    .padding(.leading, left)
                    if let i = selected, let c = columns.first(where: { $0.id == i }) {
                        let box = tipBox(c, geo)
                        let half = max(20, min(CGFloat(box.x), geo.width - CGFloat(box.x)))
                        tooltip(c)
                            .frame(width: half * 2, height: CGFloat(box.h), alignment: .center)
                            .offset(x: CGFloat(box.x) - half, y: CGFloat(box.y - box.h / 2))
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 14).onChanged { v in
                    guard abs(v.translation.width) > abs(v.translation.height), !columns.isEmpty else { return }
                    let i = min(max(Int((v.location.x - left) / geo.cw), 0), columns.count - 1)
                    if selected != columns[i].id { onDrag(columns[i].id) }
                })
            }
            .frame(height: Self.plotHeight)
            HStack(spacing: 0) {
                ForEach(columns) { c in
                    VStack(spacing: 0) {
                        Text(c.top).font(.system(size: 11, weight: selected == c.id ? .bold : .medium)).foregroundStyle(selected == c.id ? theme.textPrimary : theme.textSecondary)
                        Text(c.bottom).font(.system(size: 9, weight: .medium)).foregroundStyle(theme.textTertiary)
                    }
                    .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                }
            }
            .padding(.leading, left)
            .accessibilityHidden(true)
        }
    }

    /// Where the floating label goes. Its width is estimated only to choose the place; it is then laid out in a box that
    /// cannot leave the chart (the Consistency Dashboard's rule, checks 59–61).
    private func tipBox(_ c: DashColumn, _ geo: DashGeo) -> ConsistencyTooltip.Box {
        let lines = c.tip.filter { !$0.isEmpty }
        let h: Double = lines.count > 1 ? 42 : 26
        let w = Double(lines.map(\.count).max() ?? 8) * 6.9 + 22
        let px = Double(geo.x(c.id)), W = Double(geo.width)
        func py(_ col: DashColumn) -> Double { Double(col.anchor.map(geo.y) ?? geo.base - 2) }
        switch placement {
        case .topStrip:
            return .init(x: min(max(px, w / 2 + 2), max(w / 2 + 2, W - w / 2 - 2)), y: h / 2 + 1, w: w, h: h)
        case .rule:
            let others = columns.filter { $0.id != c.id }.map { (Double(geo.x($0.id)), py($0)) }
            return ConsistencyTooltip.place(px: px, py: py(c), w: w, h: h, width: W, height: Double(geo.height), others: others).box
        }
    }
    private func tooltip(_ c: DashColumn) -> some View {
        let lines = c.tip.filter { !$0.isEmpty }
        return VStack(spacing: 1) {
            Text(lines.first ?? "").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(theme.textPrimary)
                .accessibilityIdentifier("\(prefix)Tooltip")
            if lines.count > 1 {
                Text(lines[1]).font(.system(size: 10.5, weight: .medium)).foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("\(prefix)TooltipDetail")
            }
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(theme.surface2, in: RoundedRectangle(cornerRadius: lines.count > 1 ? 12 : 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: lines.count > 1 ? 12 : 13, style: .continuous).strokeBorder(theme.textPrimary.opacity(0.35), lineWidth: 1))
    }
}

/// The dashboards' card.
struct DashCard<Content: View>: View {
    @Environment(\.cyTheme) private var theme
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
    }
}

/// A row of equal choices in a capsule: Weeks | Days, or the metric of the Recovery graph.
struct DashSegments: View {
    @Environment(\.cyTheme) private var theme
    var prefix: String
    var titles: [String]
    var ids: [String]
    var selected: Int
    var choose: (Int) -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { k, t in
                Button { if selected != k { choose(k) } } label: {
                    Text(t).font(CyFont.caption).foregroundStyle(selected == k ? theme.textPrimary : theme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(selected == k ? theme.background : Color.clear, in: Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == k ? [.isButton, .isSelected] : [.isButton])
                .accessibilityIdentifier("\(prefix)-\(k < ids.count ? ids[k] : "\(k)")")
            }
        }
        .padding(3).background(theme.surface2, in: Capsule())
    }
}

/// The ONE summary from the records: fixed sentences, labelled as such.
struct DashInsight: View {
    @Environment(\.cyTheme) private var theme
    var id: String
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle").font(.footnote.weight(.semibold)).foregroundStyle(theme.accent).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("COACH · FROM YOUR RECORDS").font(CyFont.overline).foregroundStyle(theme.textTertiary)
                Text(text).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.highlightSurface, in: RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/// "View week ›" — the text link of the dashboards.
struct DashLink: View {
    @Environment(\.cyTheme) private var theme
    var title: String
    var id: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(CyFont.label)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }
            .foregroundStyle(theme.accent).frame(minHeight: CyHit.min, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// The header of an expandable card: title, a caption, and the chevron.
struct DashDisclosure: View {
    @Environment(\.cyTheme) private var theme
    var title: String
    var caption: String
    var open: Bool
    var id: String
    var toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(CyFont.headline).foregroundStyle(theme.textPrimary)
                    Text(caption).font(CyFont.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: open ? "chevron.up" : "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(theme.textSecondary)
            }
            .frame(minHeight: CyHit.min).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(open ? "Open" : "Closed")
        .accessibilityIdentifier(id)
    }
}
