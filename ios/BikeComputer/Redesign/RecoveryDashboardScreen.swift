import SwiftUI

// Recovery dashboard — the page the third Home circle opens (owner's shared design direction, 23 Nov 2026, 19:55; final
// visual sign-off pending). The readings that exist — sleep, resting heart rate, heart-rate variability — one metric at
// a time on its own scale, each with its source and time. THERE IS NO RECOVERY SCORE and nothing here says a reading
// proves readiness. Every figure comes from `RecoveryDashboard`; this file only draws it. The existing Recovery page
// stays as the detail view ("View recovery details").

struct RecoveryDashboardView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme
    var open: (HomeRoute) -> Void
    @State private var mode = 0                     // 0 = Weeks, 1 = Days
    @State private var metric = 0                   // index into RecoveryDashboard.kinds
    @State private var selectedWeek: Int? = nil
    @State private var inspected: Int? = nil
    @State private var row: String? = nil
    @State private var detailsOpen = false

    private var kind: HealthSample.Kind { RecoveryDashboard.kinds[min(max(metric, 0), RecoveryDashboard.kinds.count - 1)] }

    var body: some View {
        let d = store.recoveryDashboard(metric: kind, selectedWeek: selectedWeek)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary(d)
                graphCard(d)
                if let i = inspected, let p = points(d).first(where: { $0.id == i }) { inspection(p) }
                DashInsight(id: "recInsight", text: coachText(d))
                rowsSection(d)
                details(d)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 130)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Recovery").navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recoveryDashboard")
    }

    private func points(_ d: RecoveryDashboard) -> [RecoveryPoint] { mode == 0 ? d.weeks : d.days }
    private func coachText(_ d: RecoveryDashboard) -> String {
        if !d.hasAny { return "There are no recovery measurements yet, so there is nothing to describe." }
        if mode == 1, let i = inspected, let day = d.days.first(where: { $0.id == i }) { return RecoveryDashModel.dayInsight(day: day) }
        return d.weekInsight
    }
    private func unit(_ k: HealthSample.Kind) -> String { switch k { case .sleep: return "hours"; case .restingHR: return "bpm"; case .hrv: return "ms"; case .weight: return "kg" } }

    // MARK: compact summary — the latest reading of each indicator that exists; no score

    private func summary(_ d: RecoveryDashboard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(d.periodTitle).font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                .accessibilityIdentifier("recPeriod")
            Text(d.hasAny ? "Latest readings" : "No recovery measurements")
                .font(CyFont.title).foregroundStyle(theme.textPrimary)
                .accessibilityIdentifier("recSummaryLine")
            if d.hasAny {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(d.rows) { r in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.name).font(CyFont.caption).foregroundStyle(theme.textSecondary)
                            Text(r.latest ?? "No reading").font(r.latest != nil ? CyFont.metricSmall : CyFont.caption)
                                .foregroundStyle(r.latest != nil ? theme.textPrimary : theme.textTertiary).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("recSummary-\(r.kind.rawValue)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recSummary")
    }

    // MARK: graph — one metric, its own scale

    private func column(_ p: RecoveryPoint, scale: (low: Double, high: Double)?) -> DashColumn {
        let f = DateFormatter()
        f.dateFormat = mode == 0 ? "d" : "EEE"; let top = f.string(from: p.start)
        f.dateFormat = mode == 0 ? "MMM" : "d"; let bottom = f.string(from: p.start)
        var anchor: Double? = nil
        if let s = scale, let v = p.reading.value, s.high > s.low { anchor = (v - s.low) / (s.high - s.low) }
        return DashColumn(id: p.id, top: top, bottom: bottom, spoken: p.spoken, tip: p.tooltip, anchor: anchor)
    }
    private func graphCard(_ d: RecoveryDashboard) -> some View {
        let ps = points(d), scale = RecoveryDashboard.scale(ps)
        let cols = ps.map { column($0, scale: scale) }
        let axis: [String] = scale.map { s in [RecoveryDashboard.axis(kind, s.high), RecoveryDashboard.axis(kind, (s.high + s.low) / 2), RecoveryDashboard.axis(kind, s.low)] } ?? ["", "", ""]
        let noun = RecoveryDashModel.noun(kind)
        return DashCard {
            VStack(alignment: .leading, spacing: 10) {
                DashSegments(prefix: "recMode", titles: ["Weeks", "Days"], ids: ["weeks", "days"], selected: mode) { m in mode = m; inspected = nil }
                DashSegments(prefix: "recMetric", titles: RecoveryDashboard.kinds.map(RecoveryDashboard.name), ids: RecoveryDashboard.kinds.map(\.rawValue), selected: metric) { m in metric = m }
                Text(mode == 0 ? "\(RecoveryDashboard.name(kind)) · weekly average, in \(unit(kind)) · last \(ConsistencyDashboard.weekCount) weeks" : "\(RecoveryDashboard.name(kind)) in \(unit(kind)) · \(d.week.title)")
                    .font(CyFont.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("recGraphCaption")
                DashChart(prefix: "rec", columns: cols, axis: axis, left: 34, selected: inspected, placement: .rule,
                          empty: scale == nil ? (d.metricHasData ? "No \(noun) reading in this period." : "No \(noun) readings yet.") : nil,
                          onTap: { i in tap(i) }, onDrag: { i in select(i) }) { geo in
                    line(cols, geo)
                    ForEach(cols) { c in dot(c, ps.first { $0.id == c.id }, geo) }
                }
                HStack(spacing: 12) {
                    HStack(spacing: 4) { Circle().fill(theme.accent).frame(width: 8, height: 8); Text("Reading") }
                    HStack(spacing: 4) { Capsule().fill(theme.textTertiary).frame(width: 10, height: 2); Text("No reading") }
                }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(theme.textSecondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("recLegend")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recGraph")
    }
    /// Joins neighbouring periods that both have a reading; a period without one leaves a gap.
    private func line(_ cols: [DashColumn], _ geo: DashGeo) -> some View {
        Path { p in
            for i in 1..<max(cols.count, 1) {
                guard let a = cols[i - 1].anchor, let b = cols[i].anchor else { continue }
                p.move(to: CGPoint(x: geo.x(cols[i - 1].id), y: geo.y(a))); p.addLine(to: CGPoint(x: geo.x(cols[i].id), y: geo.y(b)))
            }
        }
        .stroke(theme.textSecondary.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }
    @ViewBuilder private func dot(_ c: DashColumn, _ p: RecoveryPoint?, _ geo: DashGeo) -> some View {
        let on = inspected == c.id
        if let a = c.anchor {
            Circle().fill(theme.accent).frame(width: on ? 14 : 11, height: on ? 14 : 11)
                .overlay(Circle().strokeBorder(theme.textPrimary, lineWidth: 1.5).frame(width: 23, height: 23).opacity(on ? 1 : 0))
                .position(x: geo.x(c.id), y: geo.y(a))
        } else if p?.kind == .upcoming {
            Image(systemName: "circle.dotted").font(.system(size: 12)).foregroundStyle(theme.textSecondary).position(x: geo.x(c.id), y: geo.base - 2)
        } else {
            Capsule().fill(theme.textTertiary).frame(width: 10, height: 2).position(x: geo.x(c.id), y: geo.base - 2)
        }
    }
    private func tap(_ i: Int) { if inspected == i { inspected = nil } else { select(i) } }
    private func select(_ i: Int) { inspected = i; if mode == 0 { selectedWeek = i } }

    // MARK: inspection card — every indicator recorded for the chosen period

    private func readingLine(_ r: RecoveryReading, week: Bool) -> String {
        let name = RecoveryDashboard.name(r.kind)
        guard r.value != nil else { return "\(name) — no reading" }
        if week { return "\(name) — average \(r.text) · \(r.count) of 7 \(RecoveryPoint.unit(r.kind, 7)) · \(r.source ?? "Apple Health")" }
        return "\(name) — \(r.text) · \(r.source ?? "Apple Health") · \(RecoveryPoint.time(r.date))"
    }
    private func inspection(_ p: RecoveryPoint) -> some View {
        DashCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(p.headline).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("recInspectionTitle")
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(p.all) { r in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: r.value != nil ? "circle.fill" : "minus").font(.system(size: 7)).foregroundStyle(r.value != nil ? theme.accent : theme.textTertiary).accessibilityHidden(true)
                            Text(readingLine(r, week: p.isWeek)).font(CyFont.footnote).foregroundStyle(r.value != nil ? theme.textPrimary : theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("recInspection-\(r.kind.rawValue)")
                    }
                }
                DashLink(title: "View recovery details", id: "recViewDetails") { open(.recovery) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recInspection")
    }

    // MARK: recovery measures — rows in the dashboards' row style, adapted: availability, not a progress bar

    private func rowsSection(_ d: RecoveryDashboard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recovery measures").font(CyFont.headline).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("recRowsTitle")
            ForEach(d.rows) { r in
                VStack(alignment: .leading, spacing: 0) {
                    measureRow(r)
                    if row == r.id { measureDetail(r) }
                }
                .background(row == r.id ? theme.selectedFill : theme.surface, in: RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recRows")
    }
    private func measureRow(_ r: RecoveryRow) -> some View {
        Button { row = row == r.id ? nil : r.id } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: r.icon).font(.body).foregroundStyle(theme.textPrimary).frame(width: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(CyFont.label).foregroundStyle(theme.textPrimary)
                        Text(r.latest != nil ? r.trend : (r.enabled ? "Turned on · waiting for a reading" : "Not connected")).font(CyFont.caption).foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Text(r.latest ?? "No reading").font(r.latest != nil ? CyFont.metricSmall : CyFont.caption).foregroundStyle(r.latest != nil ? theme.textPrimary : theme.textSecondary)
                    Image(systemName: row == r.id ? "chevron.up" : "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary)
                }
                // the last 14 days: a filled mark where a reading exists
                HStack(spacing: 3) {
                    ForEach(Array(r.availability.enumerated()), id: \.offset) { _, has in
                        Capsule().fill(has ? theme.accent : theme.ringTrack).frame(height: 6).frame(maxWidth: .infinity)
                    }
                }
                Text(r.latest != nil ? r.source : "No reading in the last 14 days").font(CyFont.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(r.spoken)
        .accessibilityHint("Shows the recent readings")
        .accessibilityAddTraits(row == r.id ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("recRow-\(r.id)")
    }
    private func measureDetail(_ r: RecoveryRow) -> some View {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM, HH:mm"
        return VStack(alignment: .leading, spacing: 5) {
            Text(r.recent.isEmpty ? "No \(RecoveryDashModel.noun(r.kind)) reading is stored. \(r.enabled ? "It is turned on and no reading has arrived yet." : "It is not connected.")"
                 : "The \(r.recent.count) most recent readings, each with its source:")
                .font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("recRowDetailLine")
            ForEach(Array(r.recent.enumerated()), id: \.element.id) { k, e in
                (Text(f.string(from: e.date)).foregroundColor(theme.textSecondary) + Text(" · \(RecoveryAnalysis.valueText(r.kind, e.value))").foregroundColor(theme.textPrimary)
                 + Text(" · \(e.source ?? "Apple Health")").foregroundColor(theme.textSecondary))
                    .font(CyFont.footnote).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("recRowReading-\(k)")
            }
            DashLink(title: "Open recovery details", id: "recOpenDetails") { open(.recovery) }
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recRowDetail")
    }

    // MARK: readings and sources (closed until asked for)

    private func sourceLine(_ k: HealthSample.Kind) -> String {
        let xs = store.recoveryLog.entries(k)
        guard !xs.isEmpty else { return "\(RecoveryDashboard.name(k)): no reading stored." }
        let sources = Array(Set(xs.map { $0.source ?? "Apple Health" })).sorted().joined(separator: ", ")
        let fresh = RecoveryFreshness.of(xs.map(\.date).max(), now: Date())
        return "\(RecoveryDashboard.name(k)): \(xs.count) reading\(xs.count == 1 ? "" : "s") stored · source: \(sources) · latest is \(fresh.word)."
    }
    private func details(_ d: RecoveryDashboard) -> some View {
        DashCard {
            VStack(alignment: .leading, spacing: 8) {
                DashDisclosure(title: "Readings and sources", caption: d.hasAny ? "What is stored, and where it came from" : "Nothing is stored yet", open: detailsOpen, id: "recDetailsToggle") { detailsOpen.toggle() }
                if detailsOpen {
                    ForEach(RecoveryDashboard.kinds, id: \.rawValue) { k in
                        Text(sourceLine(k)).font(CyFont.footnote).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("recSource-\(k.rawValue)")
                    }
                    Text("Each reading is one value per day, kept for \(RecoveryLog.keepDays) days with the source it was read from and the time it was taken. Cyclift estimates none of them, and it calculates no recovery score.")
                        .font(CyFont.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("recSourceNote")
                    DashLink(title: "Open recovery details", id: "recOpenDetailsAll") { open(.recovery) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recDetails")
    }
}
