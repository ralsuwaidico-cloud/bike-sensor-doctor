import SwiftUI

// Key Metrics — the hub, each metric's own page and "Choose four for Home" (owner's approved design direction, 27 Nov
// 2026, 11:40; FINAL VISUAL APPROVAL PENDING). Redesigned app only; reached from Home › Key metrics › See all.
// Every figure comes from KeyMetrics.swift; this file only draws it, with the dashboards' own pieces (DashKit): the
// card, the selector, the chart frame with its floating label, the one Coach summary and the disclosure rows.
// A metric with no source in the app has a page that says so. No score is drawn anywhere and no value is ever zero
// because it is missing.

// MARK: - hub

struct KeyMetricsHubView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    var open: (HomeRoute) -> Void
    @State private var refresh = 0

    var body: some View {
        let _ = refresh            // re-read when the page comes back from "Choose four for Home"
        let h = store.keyMetricsHub()
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                homeCard(h)
                if !h.hasAny { emptyCard }
                ForEach(h.sections) { s in section(s) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 130)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Key metrics").navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh += 1 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keyMetricsHub")
    }

    private func homeCard(_ h: KeyMetricsHub) -> some View {
        DashCard {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(h.home.count <= KeyMetricsPrefs.limit ? "ON HOME · \(h.home.count) OF \(KeyMetricsPrefs.limit)" : "ON HOME · \(h.home.count)").font(CyFont.overline).foregroundStyle(theme.textTertiary)
                    Text(h.home.map(\.name).joined(separator: " · ")).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("kmHomeList")
                }
                Spacer(minLength: 6)
                DashLink(title: "Edit", id: "kmEditHome") { open(.keyMetricsEdit) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kmHomeCard")
    }

    private var emptyCard: some View {
        DashCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing to show yet").font(CyFont.headline).foregroundStyle(theme.textPrimary)
                Text("Heart and sleep readings come from Apple Health once it is connected, and performance from the sessions you record. Until then every tile shows a dash — never zero.")
                    .font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                DashLink(title: "Open Connections", id: "kmHubConnections") { open(.menu(.connections)) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kmHubEmpty")
    }

    private func section(_ s: KeyMetricsHub.Section) -> some View {
        // not a lazy grid: every tile exists from the start, so the page reads the same to assistive technology and to checks
        let perRow = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: s.tiles.count, by: perRow).map { Array(s.tiles[$0..<min($0 + perRow, s.tiles.count)]) }
        let locked = s.category == .advanced
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.category.title).font(CyFont.headline).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 6)
                Text(s.count).font(CyFont.caption).foregroundStyle(theme.textTertiary)
                    .accessibilityIdentifier("kmCount-\(s.id)")
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) { ForEach(row) { t in tile(t) } }
                    .fixedSize(horizontal: false, vertical: true)
            }
            if locked {
                Text("Readiness, strain and recovery-vs-strain are not calculated: Cyclift shows no score it cannot stand behind. Personal baselines lists the ranges that already exist.")
                    .font(CyFont.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("kmAdvancedNote")
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kmSection-\(s.id)")
    }

    private func tile(_ t: KeyMetricTile) -> some View {
        let lineColor: Color = t.verdict == .better ? theme.success : t.verdict == .worse ? theme.danger : theme.textTertiary
        return Button { open(.keyMetric(t.metric.rawValue)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(t.metric.name).font(CyFont.caption).foregroundStyle(theme.textSecondary).lineLimit(2).minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.textTertiary)
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(t.value ?? "—").font(CyFont.value).foregroundStyle(t.value == nil ? theme.textTertiary : theme.textPrimary)
                    if t.value != nil, !t.unit.isEmpty { Text(t.unit).font(.caption2).foregroundStyle(theme.textSecondary) }
                    Spacer(minLength: 0)
                    if t.onHome {
                        Text("ON HOME").font(.system(size: 8.5, weight: .heavy)).tracking(0.4).foregroundStyle(theme.accent)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(theme.accent.opacity(0.45), lineWidth: 1))
                            .fixedSize()
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                Text(t.line).font(.caption2).foregroundStyle(lineColor).lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
            .contentShape(Rectangle())
        }
        .buttonStyle(CyCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t.spoken + (t.onHome ? ", on Home" : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens this metric")
        .accessibilityIdentifier("kmTile-\(t.id)")
    }
}

// MARK: - one metric's own page

struct KeyMetricDetailView: View {
    let metric: KeyMetricID
    var open: (HomeRoute) -> Void
    var body: some View {
        Group {
            if metric.healthKind != nil { KeyMetricHealthPage(metric: metric, open: open) }
            else if metric == .strength { KeyMetricStrengthPage() }
            else if metric == .baselines { KeyMetricBaselinesPage(open: open) }
            else if metric == .stressSoreness { KeyMetricSorenessPage() }
            else { KeyMetricUnavailablePage(metric: metric) }
        }
        .navigationTitle(metric.name).navigationBarTitleDisplayMode(.inline)
    }
}

/// The header every metric page starts with: the latest value, large, with its unit; where and when it came from; and
/// one line that compares it.
private struct KeyMetricHeader: View {
    @Environment(\.cyTheme) private var theme
    var value: String?
    var unit: String
    var right: [String]
    var line: String
    var lineColor: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Latest").font(CyFont.caption).foregroundStyle(theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value ?? "—").font(CyFont.display).monospacedDigit().foregroundStyle(value == nil ? theme.textTertiary : theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityIdentifier("kmLatestValue")
                if value != nil, !unit.isEmpty { Text(unit).font(CyFont.label).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7) }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    ForEach(Array(right.enumerated()), id: \.offset) { _, r in Text(r).font(CyFont.caption).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("kmLatestSource")
            }
            Text(line).font(CyFont.footnote).foregroundStyle(lineColor ?? theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("kmStanding")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kmHeader")
    }
}

private struct KeyMetricPage<Content: View>: View {
    @Environment(\.cyTheme) private var theme
    var id: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 130)
        }
        .background(theme.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

// MARK: resting heart rate · HRV · sleep duration

struct KeyMetricHealthPage: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme
    let metric: KeyMetricID
    var open: (HomeRoute) -> Void
    @State private var period = 1
    @State private var inspected: Int? = nil
    @State private var aboutOpen = false
    @State private var sourcesOpen = false

    var body: some View {
        KeyMetricPage(id: "keyMetricPage-\(metric.rawValue)") {
            if let d = store.keyMetricsHealth(metric, period: period) {
                KeyMetricHeader(value: d.latest, unit: d.unit, right: d.latest == nil ? ["No reading"] : [d.when, "Measured · \(d.source)"],
                                line: d.latest == nil ? (d.enabled ? "Turned on · waiting for a reading" : "Apple Health is not connected for this reading") : d.standingLine)
                graphCard(d)
                if let i = inspected, let p = d.points.first(where: { $0.id == i }) { inspection(p, d) }
                if !d.hasAny { noReadings(d) }
                DashInsight(id: "kmInsight", text: inspected.flatMap { i in d.points.first { $0.id == i } }.map { KeyMetricsModel.pointInsight($0, kind: d.kind) } ?? d.summary)
                rangeCard(d)
                about(d)
                sources(d)
            }
        }
    }

    private func column(_ p: KeyMetricPoint, _ d: KeyMetricHealthDetail) -> DashColumn {
        var anchor: Double? = nil
        if let v = p.value, let lo = d.low, let hi = d.high, hi > lo { anchor = (v - lo) / (hi - lo) }
        let text = p.value.map { RecoveryAnalysis.valueText(d.kind, $0) }
        let tip = text.map { p.isWeek ? "Avg \($0) · \(p.short)" : "\($0) · \(p.short)" } ?? "No reading · \(p.short)"
        let spoken = text.map { "\(p.title), \(p.isWeek ? "average " : "")\($0)" } ?? "\(p.title), no reading"
        return DashColumn(id: p.id, top: p.top, bottom: p.bottom, spoken: spoken, tip: [tip], anchor: anchor)
    }
    private func graphCard(_ d: KeyMetricHealthDetail) -> some View {
        let cols = d.points.map { column($0, d) }
        var axis = ["", "", ""]
        if let lo = d.low, let hi = d.high { axis = [KeyMetricsModel.axis(d.kind, hi), KeyMetricsModel.axis(d.kind, (hi + lo) / 2), KeyMetricsModel.axis(d.kind, lo)] }
        let noun = KeyMetricsModel.noun(d.kind)
        let small = d.points.count > 13
        let f = DateFormatter(); f.dateFormat = "d MMM"
        return DashCard {
            VStack(alignment: .leading, spacing: 10) {
                DashSegments(prefix: "kmPeriod", titles: KeyMetricsModel.periodTitles, ids: KeyMetricsModel.periodIDs, selected: period) { p in period = p; inspected = nil }
                Text(d.caption).font(CyFont.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("kmGraphCaption")
                DashChart(prefix: "km", columns: cols, axis: axis, left: 34, selected: inspected, placement: .rule,
                          empty: d.hasInPeriod ? nil : (d.hasAny ? "No \(noun) reading in this period." : "No \(noun) readings yet."),
                          onTap: { i in inspected = inspected == i ? nil : i }, onDrag: { i in inspected = i }) { geo in
                    if let lo = d.low, let hi = d.high, let bl = d.bandLow, let bh = d.bandHigh, hi > lo {
                        let top = geo.y((bh - lo) / (hi - lo)), bottom = geo.y((bl - lo) / (hi - lo))
                        Rectangle().fill(theme.accent.opacity(0.12)).frame(width: geo.width - geo.left, height: max(1, bottom - top))
                            .position(x: geo.left + (geo.width - geo.left) / 2, y: (top + bottom) / 2)
                            .accessibilityHidden(true)
                    }
                    Path { p in
                        for i in 1..<max(cols.count, 1) {
                            guard let a = cols[i - 1].anchor, let b = cols[i].anchor else { continue }
                            p.move(to: CGPoint(x: geo.x(cols[i - 1].id), y: geo.y(a))); p.addLine(to: CGPoint(x: geo.x(cols[i].id), y: geo.y(b)))
                        }
                    }
                    .stroke(theme.textSecondary.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    ForEach(cols) { c in dot(c, small: small, geo) }
                }
                if small, let a = d.points.first, let m = d.points.dropFirst(d.points.count / 2).first, let z = d.points.last {
                    HStack { Text(f.string(from: a.start)); Spacer(); Text(f.string(from: m.start)); Spacer(); Text(f.string(from: z.start)) }
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(theme.textSecondary).padding(.leading, 34).padding(.top, -22)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 12) {
                    HStack(spacing: 4) { Circle().fill(theme.accent).frame(width: 8, height: 8); Text("Reading") }
                    HStack(spacing: 4) { Capsule().fill(theme.textTertiary).frame(width: 10, height: 2); Text("No reading") }
                    if d.bandLow != nil { HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(theme.accent.opacity(0.25)).frame(width: 12, height: 8); Text("Your usual range") } }
                }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(theme.textSecondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("kmLegend")
                Text(period == 2 ? "Tap a point to see that week's readings" : "Tap a point to inspect that day").font(CyFont.caption).foregroundStyle(theme.textTertiary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kmGraph")
    }
    @ViewBuilder private func dot(_ c: DashColumn, small: Bool, _ geo: DashGeo) -> some View {
        let on = inspected == c.id
        if let a = c.anchor {
            let size: CGFloat = small ? (on ? 10 : 6) : (on ? 14 : 11)
            Circle().fill(theme.accent).frame(width: size, height: size)
                .overlay(Circle().strokeBorder(theme.textPrimary, lineWidth: 1.5).frame(width: size + 9, height: size + 9).opacity(on ? 1 : 0))
                .position(x: geo.x(c.id), y: geo.y(a))
        } else {
            Capsule().fill(theme.textTertiary).frame(width: small ? 5 : 10, height: 2).position(x: geo.x(c.id), y: geo.base - 2)
        }
    }

    private func row(_ name: String, _ value: String, _ detail: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value).font(CyFont.label).foregroundStyle(theme.textPrimary)
                if !detail.isEmpty { Text(detail).font(CyFont.caption).foregroundStyle(theme.textTertiary) }
            }
            .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
    private func inspection(_ p: KeyMetricPoint, _ d: KeyMetricHealthDetail) -> some View {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let wf = DateFormatter(); wf.dateFormat = "EEE d MMM, HH:mm"
        return DashCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(p.title).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("kmInspectionTitle")
                if let v = p.value {
                    if p.isWeek {
                        row("Weekly average", RecoveryAnalysis.valueText(d.kind, v), "from \(p.count) of 7 \(KeyMetricsModel.unitWord(d.kind, 7)) · \(p.source ?? "Apple Health")", id: "kmInspectionValue")
                        Text("THE READINGS BEHIND THIS AVERAGE").font(CyFont.overline).foregroundStyle(theme.textTertiary).padding(.top, 2)
                        ForEach(Array(p.records.enumerated()), id: \.element.id) { k, e in
                            (Text(wf.string(from: e.date)).foregroundColor(theme.textSecondary) + Text(" · \(RecoveryAnalysis.valueText(d.kind, e.value))").foregroundColor(theme.textPrimary)
                             + Text(" · \(e.source ?? "Apple Health")").foregroundColor(theme.textSecondary))
                                .font(CyFont.footnote).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("kmWeekRecord-\(k)")
                        }
                        if p.count < 7 {
                            Text("\(7 - p.count) day\(7 - p.count == 1 ? "" : "s") of this week \(7 - p.count == 1 ? "has" : "have") no reading and \(7 - p.count == 1 ? "is" : "are") not part of the average.")
                                .font(CyFont.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("kmWeekMissing")
                        }
                    } else {
                        row(d.kind.title, RecoveryAnalysis.valueText(d.kind, v), "Measured · \(p.source ?? "Apple Health")\(p.date.map { " · \(f.string(from: $0))" } ?? "")", id: "kmInspectionValue")
                        if let s = p.standing, let r = d.rangeText {
                            row("Compared with your usual range", "\(KeyMetricsModel.standingWord(s)) · \(r)", "", id: "kmInspectionStanding")
                        }
                    }
                } else {
                    Text("No reading").font(CyFont.footnote).foregroundStyle(theme.textSecondary).accessibilityIdentifier("kmInspectionValue")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kmInspection")
    }
    private func noReadings(_ d: KeyMetricHealthDetail) -> some View {
        DashCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("No readings yet").font(CyFont.headline).foregroundStyle(theme.textPrimary)
                Text(d.enabled ? "This reading is turned on and none has arrived from Apple Health yet. Nothing is estimated and it cannot be typed in."
                     : "Cyclift reads \(KeyMetricsModel.noun(d.kind)) from Apple Health once it is connected. Nothing is estimated and it cannot be typed in.")
                    .font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                if !d.enabled { DashLink(title: "Open Connections", id: "kmConnections") { open(.menu(.connections)) } }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kmNoReadings")
    }
    private func rangeCard(_ d: KeyMetricHealthDetail) -> some View {
        DashCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("COMPARED WITH YOUR USUAL").font(CyFont.overline).foregroundStyle(theme.textTertiary)
                Text(d.rangeText ?? "No usual range yet").font(d.rangeText != nil ? CyFont.metric : CyFont.headline)
                    .foregroundStyle(d.rangeText != nil ? theme.textPrimary : theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityIdentifier("kmRange")
                Text(d.rangeBasis).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                Text(d.kind == .sleep ? "Your own middle range, not a sleep recommendation." : "Your own middle range, not a medical reference.")
                    .font(CyFont.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kmRangeCard")
    }
    private func about(_ d: KeyMetricHealthDetail) -> some View {
        DashCard {
            VStack(alignment: .leading, spacing: 8) {
                DashDisclosure(title: "About this measure", caption: "What it is, and its limits", open: aboutOpen, id: "kmAboutToggle") { aboutOpen.toggle() }
                if aboutOpen {
                    Text(KeyMetricsModel.about(d.kind)).font(CyFont.footnote).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("kmAboutText")
                }
            }
        }
    }
    private func sources(_ d: KeyMetricHealthDetail) -> some View {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM, HH:mm"
        return DashCard {
            VStack(alignment: .leading, spacing: 8) {
                DashDisclosure(title: "Readings and sources", caption: d.hasAny ? "\(d.stored) stored · where each came from and when" : "Nothing is stored yet", open: sourcesOpen, id: "kmSourcesToggle") { sourcesOpen.toggle() }
                if sourcesOpen {
                    ForEach(Array(d.recent.enumerated()), id: \.element.id) { k, e in
                        (Text(f.string(from: e.date)).foregroundColor(theme.textSecondary) + Text(" · \(RecoveryAnalysis.valueText(d.kind, e.value))").foregroundColor(theme.textPrimary)
                         + Text(" · \(e.source ?? "Apple Health")").foregroundColor(theme.textSecondary))
                            .font(CyFont.footnote).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("kmReading-\(k)")
                    }
                    Text("One value a day, kept for \(RecoveryLog.keepDays) days with the source it was read from and the time it was taken. A day without a reading is left empty. Cyclift estimates none of them.")
                        .font(CyFont.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("kmSourceNote")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kmSources")
    }
}

// MARK: strength progression

struct KeyMetricStrengthPage: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme
    @State private var period = 2
    @State private var exercise: String? = nil
    @State private var measure = 0
    @State private var inspected: Int? = nil
    @State private var sessionsOpen = false
    @State private var rulesOpen = false

    private func color(_ v: DayVerdict) -> Color { v == .better ? theme.success : v == .worse ? theme.danger : theme.textSecondary }
    private func text(_ v: Double?, _ u: AppSettings.Units) -> String? {
        guard let v else { return nil }
        return measure == 0 || measure == 3 ? WeightFmt.text(v, u) : "\(Int(v))"
    }

    var body: some View {
        let u = store.settings.units
        let d = store.keyMetricsStrength(selected: exercise, period: period, measure: measure)
        let key = ["-load", "-reps", "-sets", "-volume"][measure]
        let m = d.comparison?.metrics.first { $0.id.hasSuffix(key) }
        let f = DateFormatter(); let _ = (f.dateFormat = "EEE d MMM")
        KeyMetricPage(id: "keyMetricPage-strength") {
            if d.hasAny {
                KeyMetricHeader(value: m?.current.flatMap { $0.split(separator: " ").first.map { String($0) } }, unit: measure == 0 || measure == 3 ? WeightFmt.unit(u) : StrengthProgress.measureTitles[measure].lowercased(),
                                right: ["\(d.name) · \(StrengthProgress.measureTitles[measure].lowercased())", d.latestDate.map { "\(f.string(from: $0)) · recorded in Cyclift" } ?? ""],
                                line: d.comparison.map { $0.previous == nil ? "One session so far — nothing to compare with yet" : "\($0.change) · against the session before" } ?? "",
                                lineColor: d.comparison.map { color($0.verdict) })
                graphCard(d, u)
                if let i = inspected, let p = d.points.first(where: { $0.id == i }) { inspection(p, u) }
                DashInsight(id: "kmInsight", text: d.summary)
                comparison(d)
                sessions(d)
                rules
            } else {
                KeyMetricHeader(value: nil, unit: "", right: ["No session"], line: "No strength session with exercises is recorded")
                DashCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No sessions yet").font(CyFont.headline).foregroundStyle(theme.textPrimary)
                        Text("Record a strength session with the Train button. Progress appears here exercise by exercise, and a comparison once the same exercise has been recorded twice.")
                            .font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("kmNoReadings")
                DashInsight(id: "kmInsight", text: d.summary)
            }
        }
    }

    private func graphCard(_ d: StrengthProgress, _ u: AppSettings.Units) -> some View {
        let vs = d.points.compactMap { d.value($0, measure: measure) }
        var lo = vs.min() ?? 0, hi = vs.max() ?? 1
        let step: Double = measure == 0 ? 5 : measure == 3 ? 100 : measure == 1 ? 5 : 1
        lo = max(0, (lo / step).rounded(.down) * step - (hi - lo < step ? step : 0)); hi = (hi / step).rounded(.up) * step
        if hi - lo < step * 2 { hi = lo + step * 2 }
        if Int(((hi - lo) / step).rounded()) % 2 != 0 { hi += step }
        let f = DateFormatter()
        let cols: [DashColumn] = d.points.map { p in
            let v = d.value(p, measure: measure)
            f.dateFormat = "d"; let top = f.string(from: p.date); f.dateFormat = "MMM"; let bottom = f.string(from: p.date); f.dateFormat = "EEE d MMM"; let day = f.string(from: p.date)
            let t = text(v, u)
            return DashColumn(id: p.id, top: top, bottom: bottom, spoken: "\(day), \(t ?? "not recorded")", tip: [t.map { "\($0) · \(day)" } ?? "Not recorded · \(day)"], anchor: v.map { ($0 - lo) / (hi - lo) })
        }
        func ax(_ v: Double) -> String { v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v) }
        let title = StrengthProgress.measureTitles[measure]
        return DashCard {
            VStack(alignment: .leading, spacing: 10) {
                DashSegments(prefix: "kmPeriod", titles: KeyMetricsModel.periodTitles, ids: KeyMetricsModel.periodIDs, selected: period) { p in period = p; inspected = nil }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(d.exercises.enumerated()), id: \.element.id) { k, e in
                            Button { exercise = e.id; inspected = nil } label: {
                                Text(e.name).font(CyFont.caption).foregroundStyle(d.selected == e.id ? theme.textPrimary : theme.textSecondary)
                                    .padding(.horizontal, 12).frame(minHeight: 32)
                                    .background(d.selected == e.id ? theme.selectedFill : theme.surface2, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(d.selected == e.id ? [.isButton, .isSelected] : [.isButton])
                            .accessibilityIdentifier("kmExercise-\(k)")
                        }
                    }
                }
                DashSegments(prefix: "kmMeasure", titles: StrengthProgress.measureTitles, ids: StrengthProgress.measures, selected: measure) { k in measure = k; inspected = nil }
                Text("\(d.name) · \(title.lowercased())\(measure == 0 || measure == 3 ? " in \(WeightFmt.unit(u))" : "") · one point per session")
                    .font(CyFont.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("kmGraphCaption")
                DashChart(prefix: "km", columns: cols, axis: vs.isEmpty ? ["", "", ""] : [ax(hi), ax((hi + lo) / 2), ax(lo)], left: 34, selected: inspected, placement: .rule,
                          empty: vs.isEmpty ? (d.points.isEmpty ? "No \(d.name) session in this period." : "No \(title.lowercased()) recorded in this period.") : nil,
                          onTap: { i in inspected = inspected == i ? nil : i }, onDrag: { i in inspected = i }) { geo in
                    Path { p in
                        for i in 1..<max(cols.count, 1) {
                            guard let a = cols[i - 1].anchor, let b = cols[i].anchor else { continue }
                            p.move(to: CGPoint(x: geo.x(cols[i - 1].id), y: geo.y(a))); p.addLine(to: CGPoint(x: geo.x(cols[i].id), y: geo.y(b)))
                        }
                    }
                    .stroke(theme.textSecondary.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    ForEach(cols) { c in
                        let on = inspected == c.id
                        if let a = c.anchor {
                            Circle().fill(theme.accent).frame(width: on ? 14 : 11, height: on ? 14 : 11)
                                .overlay(Circle().strokeBorder(theme.textPrimary, lineWidth: 1.5).frame(width: 23, height: 23).opacity(on ? 1 : 0))
                                .position(x: geo.x(c.id), y: geo.y(a))
                        } else {
                            Capsule().fill(theme.textTertiary).frame(width: 10, height: 2).position(x: geo.x(c.id), y: geo.base - 2)
                        }
                    }
                }
                Text("Tap a point to inspect that session").font(CyFont.caption).foregroundStyle(theme.textTertiary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kmGraph")
    }

    private func inspection(_ p: StrengthProgressPoint, _ u: AppSettings.Units) -> some View {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMM"
        let rows: [(String, String)] = [("Top load", p.top.map { WeightFmt.text($0, u) } ?? "No load recorded"), ("Reps", "\(p.reps)"), ("Sets", "\(p.sets)"), ("Volume", p.volume.map { WeightFmt.text($0, u) } ?? "No load recorded")]
        return DashCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(f.string(from: p.date)).font(CyFont.headline).foregroundStyle(theme.textPrimary).accessibilityIdentifier("kmInspectionTitle")
                Text(p.summary).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack { Text(r.0).font(CyFont.footnote).foregroundStyle(theme.textSecondary); Spacer(); Text(r.1).font(CyFont.label).foregroundStyle(theme.textPrimary) }
                        .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kmInspection")
    }

    private func comparison(_ d: StrengthProgress) -> some View {
        let f = DateFormatter(); f.dateFormat = "d MMM"
        let order = ["-load", "-reps", "-sets", "-volume"]
        let ms = order.compactMap { k in d.comparison?.metrics.first { $0.id.hasSuffix(k) } }
        return DashCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("PREVIOUS AND CURRENT").font(CyFont.overline).foregroundStyle(theme.textTertiary)
                HStack(spacing: 6) {
                    Text(d.name).font(CyFont.caption).foregroundStyle(theme.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
                    Text(d.previousDate.map { f.string(from: $0) } ?? "Previous").frame(width: 74, alignment: .trailing)
                    Text(d.latestDate.map { f.string(from: $0) } ?? "Current").frame(width: 74, alignment: .trailing)
                    Text("Change").frame(width: 78, alignment: .trailing)
                }
                .font(CyFont.caption).foregroundStyle(theme.textTertiary).lineLimit(1).minimumScaleFactor(0.7)
                ForEach(ms) { r in
                    HStack(spacing: 6) {
                        Text(r.name).font(CyFont.footnote).foregroundStyle(theme.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
                        Text(r.previous ?? "—").foregroundStyle(theme.textSecondary).frame(width: 74, alignment: .trailing)
                        Text(r.current ?? "—").foregroundStyle(theme.textPrimary).frame(width: 74, alignment: .trailing)
                        Text(r.previous == nil ? "—" : r.change).foregroundStyle(r.verdict == .better || r.verdict == .worse ? color(r.verdict) : theme.textSecondary).frame(width: 78, alignment: .trailing)
                    }
                    .font(CyFont.footnote).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(r.spoken)
                    .accessibilityValue(r.verdict.rawValue)
                    .accessibilityIdentifier("kmCompare\(r.id.suffix(from: r.id.lastIndex(of: "-") ?? r.id.startIndex))")
                }
                if let c = d.comparison {
                    Text(c.previous == nil ? "This exercise has been recorded once, so there is no earlier session to set it against." : c.change)
                        .font(CyFont.caption).foregroundStyle(color(c.verdict)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityValue(c.verdict.rawValue)
                        .accessibilityIdentifier("kmCompareVerdict")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kmCompare")
    }

    private func sessions(_ d: StrengthProgress) -> some View {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return DashCard {
            VStack(alignment: .leading, spacing: 8) {
                DashDisclosure(title: "Sessions", caption: "\(d.points.count) in this period · sets, reps and load", open: sessionsOpen, id: "kmSessionsToggle") { sessionsOpen.toggle() }
                if sessionsOpen {
                    ForEach(d.points.reversed()) { p in
                        (Text(f.string(from: p.date)).foregroundColor(theme.textSecondary) + Text(" · \(p.summary)").foregroundColor(theme.textPrimary))
                            .font(CyFont.footnote).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("kmSession-\(p.id)")
                    }
                }
            }
        }
    }
    private var rules: some View {
        DashCard {
            VStack(alignment: .leading, spacing: 8) {
                DashDisclosure(title: "How change is judged", caption: "The same rule as the Day page", open: rulesOpen, id: "kmRulesToggle") { rulesOpen.toggle() }
                if rulesOpen {
                    Text("Green: the top load is up and the reps are not lower, or the reps are up at the same load. Red: the reverse. Grey: unchanged, or not comparable — a different number of sets, load and reps moving in opposite directions, a load lowered for a return after a break, or a clearly different reported effort. A higher number alone is never called an improvement.")
                        .font(CyFont.footnote).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("kmRulesText")
                }
            }
        }
    }
}

// MARK: personal baselines — the three ranges that already exist

struct KeyMetricBaselinesPage: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme
    var open: (HomeRoute) -> Void

    private func metric(_ k: HealthSample.Kind) -> KeyMetricID { k == .sleep ? .sleepDuration : k == .restingHR ? .restingHR : .hrv }

    var body: some View {
        let rows = store.keyMetricsBaselines()
        let have = rows.filter { $0.trend.contains("your usual range") }.count
        let inside = rows.filter { $0.trend.hasPrefix("Inside") }.count
        KeyMetricPage(id: "keyMetricPage-baselines") {
            KeyMetricHeader(value: rows.contains { $0.latest != nil } ? "\(have) of \(rows.count)" : nil, unit: "ranges", right: ["Your own readings", "last \(RecoveryAnalysis.baselineDays) days"],
                            line: have == 0 ? "No usual range yet — each needs \(RecoveryAnalysis.minBaselineRecords) earlier readings" : "Each range comes only from your own earlier readings")
            ForEach(rows) { r in
                Button { open(.keyMetric(metric(r.kind).rawValue)) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: r.icon).font(.body).foregroundStyle(theme.textPrimary).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metric(r.kind).name).font(CyFont.label).foregroundStyle(theme.textPrimary)
                            Text(r.trend).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            Text(r.latest != nil ? "Latest \(r.latest!) · \(r.latestDay)" : (r.enabled ? "Turned on · waiting for a reading" : "Not connected")).font(CyFont.caption).foregroundStyle(theme.textTertiary)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
                    .contentShape(Rectangle())
                }
                .buttonStyle(CyCardButtonStyle())
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens this metric")
                .accessibilityIdentifier("kmBaseline-\(r.id)")
            }
            DashInsight(id: "kmInsight", text: have == 0 ? "There is no usual range yet, so there is nothing to compare your latest readings with."
                        : "\(inside) of your \(have) latest reading\(have == 1 ? "" : "s") with a usual range \(inside == 1 ? "is" : "are") inside it. This describes the readings only — it is not a readiness or health score.")
            DashCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HOW A USUAL RANGE IS WORKED OUT").font(CyFont.overline).foregroundStyle(theme.textTertiary)
                    Text("From your own readings in the \(RecoveryAnalysis.baselineDays) days before the latest one: the middle half of them, widened a little. It needs at least \(RecoveryAnalysis.minBaselineRecords) readings; with fewer, no range is shown. It is not a medical reference and the three ranges are never combined into one number.")
                        .font(CyFont.footnote).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("kmBaselineHow")
                }
            }
        }
    }
}

// MARK: stress & soreness — only the soreness answers that exist

struct KeyMetricSorenessPage: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme
    var body: some View {
        let s = store.keyMetricsSoreness()
        let f = DateFormatter(); let _ = (f.dateFormat = "EEE d MMM")
        KeyMetricPage(id: "keyMetricPage-stressSoreness") {
            KeyMetricHeader(value: s.answers.first?.answer, unit: "", right: s.answers.first.map { [f.string(from: $0.date), "Your answer · \($0.session)"] } ?? ["No answer"],
                            line: s.answers.isEmpty ? "No soreness answer in a session review yet" : "Soreness, as you answered it in a session review")
            DashInsight(id: "kmInsight", text: s.summary)
            DashCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SORENESS ANSWERS · LAST 90 DAYS").font(CyFont.overline).foregroundStyle(theme.textTertiary)
                    if s.answers.isEmpty {
                        Text("Nothing answered yet. The question is part of the review after a session.").font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("kmNoReadings")
                    }
                    ForEach(Array(s.answers.prefix(12).enumerated()), id: \.element.id) { k, a in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(f.string(from: a.date)) · \(a.session)").font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 6)
                            Text(a.answer).font(CyFont.label).foregroundStyle(theme.textPrimary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("kmSoreness-\(k)")
                    }
                }
            }
            DashCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stress is not collected").font(CyFont.headline).foregroundStyle(theme.textPrimary)
                    Text("Stress is something you would enter yourself in the Sleep & wellness journal, which is not available yet. There is no graph here because soreness is an answer after a session, not a daily measurement, and nothing is filled in for the days between.")
                        .font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("kmStressNote")
        }
    }
}

// MARK: a metric the app has no source for

struct KeyMetricUnavailablePage: View {
    @Environment(\.cyTheme) private var theme
    let metric: KeyMetricID
    var body: some View {
        let score = [KeyMetricID.readiness, .strain, .recoveryVsStrain].contains(metric)
        KeyMetricPage(id: "keyMetricPage-\(metric.rawValue)") {
            KeyMetricHeader(value: nil, unit: "", right: [score ? "Not available" : "No reading"], line: metric.unavailableLine ?? "Not available")
            DashCard {
                Text(score ? "No graph. Cyclift does not calculate this, so there is nothing to plot." : "No graph yet. There are no readings to plot.")
                    .font(CyFont.footnote).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .accessibilityIdentifier("kmGraphEmpty")
            }
            DashCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text(score ? "Why this is not available" : "Not collected yet").font(CyFont.headline).foregroundStyle(theme.textPrimary)
                    Text(metric.unavailableDetail).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("kmUnavailableText")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("kmUnavailable")
            DashInsight(id: "kmInsight", text: "There is nothing to describe.")
        }
    }
}

// MARK: - choose four for Home

struct KeyMetricsEditView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme
    @State private var chosen: [KeyMetricID] = []
    @State private var loaded = false
    @State private var note: String? = nil

    var body: some View {
        let h = store.keyMetricsHub()
        let extras = KeyMetricsPrefs.extras.map { store.keyMetricTile($0, home: chosen) }
        KeyMetricPage(id: "keyMetricsEdit") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Home shows up to four key metrics. Choose from the ones that have a value.").font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                Text("\(chosen.count) of \(KeyMetricsPrefs.limit) chosen").font(CyFont.headline).foregroundStyle(theme.textPrimary)
                    .accessibilityIdentifier("kmEditCount")
                Text("Your choice is kept with your Cyclift data, so it is in your backup and your export.").font(CyFont.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                if let n = note { Text(n).font(CyFont.caption).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("kmEditNote") }
            }
            ForEach(h.sections) { s in
                group(s.category.title, s.tiles)
            }
            group("Also available for Home", extras)
        }
        .navigationTitle("Choose four for Home").navigationBarTitleDisplayMode(.inline)
        .onAppear { if !loaded { chosen = store.keyMetricsHomeChoice().ids; loaded = true } }
    }

    private func group(_ title: String, _ tiles: [KeyMetricTile]) -> some View {
        DashCard {
            VStack(alignment: .leading, spacing: 0) {
                Text(title.uppercased()).font(CyFont.overline).foregroundStyle(theme.textTertiary).padding(.bottom, 4)
                ForEach(tiles) { t in row(t) }
            }
        }
    }
    private func row(_ t: KeyMetricTile) -> some View {
        let on = chosen.contains(t.metric)
        let can = t.measurable || on
        return Button { toggle(t) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.metric.name).font(CyFont.label).foregroundStyle(can ? theme.textPrimary : theme.textTertiary)
                    Text(t.value.map { [$0, t.unit].filter { !$0.isEmpty }.joined(separator: " ") } ?? t.line).font(CyFont.caption).foregroundStyle(theme.textTertiary).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 6)
                if can {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(on ? theme.accent : theme.textTertiary)
                } else {
                    Text(t.metric == .baselines ? "A list, not one value" : "No value").font(CyFont.caption).foregroundStyle(theme.textTertiary)
                }
            }
            .frame(minHeight: CyHit.min).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!can)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t.metric.name)
        .accessibilityValue(can ? (on ? "On Home" : "Not on Home") : "Cannot be chosen: no value")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("kmPick-\(t.id)")
    }
    private func toggle(_ t: KeyMetricTile) {
        var next = chosen
        if let i = next.firstIndex(of: t.metric) { next.remove(at: i) }
        else if next.count >= KeyMetricsPrefs.limit { note = "Four are chosen. Untick one to choose another."; return }
        else { next.append(t.metric) }
        // shown as chosen only once it is stored
        if store.setKeyMetricsHome(next) { chosen = store.keyMetricsHomeChoice().ids; note = nil }
        else { note = "Your choice could not be saved. Home is unchanged." }
    }
}
