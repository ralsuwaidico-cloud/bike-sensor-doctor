import SwiftUI

// Consistency Dashboard — the page the Home Consistency ring opens (owner's design direction, 23 Nov 2026, 11:59;
// final visual approval pending). Order: period · compact summary · interactive graph (Weeks / Days) with an inspection
// card · overall summary from the records · Consistency by sport · sport summary · expandable session details.
// Every figure comes from `ConsistencyDashboard` (the Home ring's own definition); this file only draws it. The older
// Weekly overview and Day pages stay as the drill-downs ("View week", "View Thursday"); nothing here changes a record.

struct ConsistencyDashboardView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme
    var open: (HomeRoute) -> Void
    @State private var mode = 0                     // 0 = Weeks, 1 = Days
    @State private var selectedWeek: Int? = nil     // nil = the current week
    @State private var inspected: Int? = nil        // a point of the graph in the current mode
    @State private var sport: String? = nil
    @State private var detailsOpen = false
    @State private var prescription: Workout? = nil

    var body: some View {
        let d = store.consistencyDashboard(selectedWeek: selectedWeek)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary(d)
                graphCard(d)
                if let i = inspected, let p = points(d).first(where: { $0.id == i }) { inspection(p, d) }
                // ONE summary from the records (owner, 23 Nov 2026, 14:04): it follows the chosen day, otherwise the chosen week
                insight("consistencyInsightOverall", coachText(d))
                sportsSection(d)
                details(d)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 130)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Consistency").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $prescription) { w in HomePrescriptionSheet(workout: w) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("consistencyDashboard")
    }

    private func points(_ d: ConsistencyDashboard) -> [ConsistencyPoint] { mode == 0 ? d.weeks : d.days }
    private func coachText(_ d: ConsistencyDashboard) -> String {
        if mode == 1, let i = inspected, let day = d.days.first(where: { $0.id == i }) { return ConsistencyModel.dayInsight(day: day, hasPlan: d.hasPlan) }
        return d.overallInsight
    }

    // MARK: colours and marks — a band is always a colour, a shape and its range in words

    private func color(_ b: ConsistencyBand?) -> Color {
        switch b { case .high?: return theme.success; case .moderate?: return theme.endurance; case .low?: return theme.danger; case nil: return theme.textSecondary }
    }
    @ViewBuilder private func mark(_ b: ConsistencyBand?, size: CGFloat) -> some View {
        switch b {
        case .high?: Circle().fill(color(b)).frame(width: size, height: size)
        case .moderate?: Rectangle().fill(color(b)).frame(width: size * 0.8, height: size * 0.8).rotationEffect(.degrees(45))
        case .low?: CyTriangle().fill(color(b)).frame(width: size, height: size)
        case nil: Circle().strokeBorder(theme.textSecondary, lineWidth: 2).frame(width: size, height: size)
        }
    }
    private func card<V: View>(@ViewBuilder _ v: () -> V) -> some View {
        v().padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
    }

    // MARK: B · compact summary

    private func summary(_ d: ConsistencyDashboard) -> some View {
        // No headline percentage (owner, 23 Nov 2026, 14:04): the graph is the page's main element. The period, the count
        // and the summary counts stay, compactly.
        let w = d.week, c = w.count
        return VStack(alignment: .leading, spacing: 3) {
            Text(d.periodTitle + (w.kind == .inProgress ? " · In progress" : "")).font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                .accessibilityIdentifier("consistencyPeriod")
            Text(c.planned > 0 ? "\(c.ratio) planned sessions completed" : d.hasPlan ? "No planned sessions" : "No training plan yet")
                .font(CyFont.title).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("consistencySummaryLine")
            if c.planned > 0 || c.skipped > 0 {
                Text("Missed \(c.missed)" + (c.skipped > 0 ? " · Skipped \(c.skipped)" : "") + (c.open > 0 ? " · To come \(c.open)" : ""))
                    .font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("consistencyMissed")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("consistencySummary")
    }

    // MARK: C · interactive graph

    private func graphCard(_ d: ConsistencyDashboard) -> some View {
        let ps = points(d)
        return card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    modeButton("Weeks", 0); modeButton("Days", 1)
                }
                .padding(3).background(theme.surface2, in: Capsule())
                Text(mode == 0 ? "Last \(ConsistencyDashboard.weekCount) weeks" : d.week.title).font(CyFont.caption).foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("consistencyGraphCaption")
                VStack(spacing: 4) {
                    plot(ps).frame(height: Self.plotHeight)
                    HStack(spacing: 0) {
                        ForEach(ps) { p in
                            VStack(spacing: 0) {
                                Text(axisTop(p)).font(.system(size: 11, weight: inspected == p.id ? .bold : .medium)).foregroundStyle(inspected == p.id ? theme.textPrimary : theme.textSecondary)
                                Text(axisBottom(p)).font(.system(size: 9, weight: .medium)).foregroundStyle(theme.textTertiary)
                            }
                            .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.leading, Self.axisWidth)
                    .accessibilityHidden(true)
                }
                legend
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("consistencyGraph")
    }
    private func axisTop(_ p: ConsistencyPoint) -> String {
        let f = DateFormatter(); f.dateFormat = mode == 0 ? "d" : "EEE"; return f.string(from: p.start)
    }
    private func axisBottom(_ p: ConsistencyPoint) -> String {
        if mode == 0, p.kind == .inProgress { return "now" }
        let f = DateFormatter(); f.dateFormat = mode == 0 ? "MMM" : "d"; return f.string(from: p.start)
    }
    private func modeButton(_ title: String, _ m: Int) -> some View {
        Button { if mode != m { mode = m; inspected = nil } } label: {
            Text(title).font(CyFont.caption).foregroundStyle(mode == m ? theme.textPrimary : theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(mode == m ? theme.background : Color.clear, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == m ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("consistencyMode-\(title.lowercased())")
    }
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach([ConsistencyBand.high, .moderate, .low], id: \.rawValue) { b in
                HStack(spacing: 4) { mark(b, size: 8); Text(b.range) }
            }
            HStack(spacing: 4) { mark(nil, size: 8); Text("In progress") }
        }
        .font(.system(size: 10, weight: .medium)).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("consistencyLegend")
    }

    private static let plotHeight: CGFloat = 178
    private static let axisWidth: CGFloat = 26
    /// The top of the chart is kept clear above the 100 % line, so the floating label of even the highest point has room.
    private static let topInset: CGFloat = 40
    private static let bottomInset: CGFloat = 10

    private func plot(_ ps: [ConsistencyPoint]) -> some View {
        GeometryReader { g in
            let n = max(ps.count, 1), left = Self.axisWidth, cw = (g.size.width - left) / CGFloat(n), h = g.size.height
            let y: (Int) -> CGFloat = { p in Self.topInset + (h - Self.topInset - Self.bottomInset) * (1 - CGFloat(p) / 100) }
            let x: (Int) -> CGFloat = { i in left + cw * (CGFloat(i) + 0.5) }
            let py: (ConsistencyPoint) -> CGFloat = { p in p.percent.map(y) ?? y(0) - 2 }
            ZStack(alignment: .topLeading) {
                ForEach([0, 50, 100], id: \.self) { v in
                    Path { p in p.move(to: CGPoint(x: left, y: y(v))); p.addLine(to: CGPoint(x: g.size.width, y: y(v))) }
                        .stroke(theme.chartGrid, style: StrokeStyle(lineWidth: 1, dash: v == 50 ? [3, 4] : []))
                    Text("\(v)").font(.system(size: 10, weight: .medium)).foregroundStyle(theme.textTertiary)
                        .frame(width: left - 6, alignment: .trailing).position(x: (left - 6) / 2, y: y(v))
                        .accessibilityHidden(true)
                }
                if let i = inspected, i < ps.count {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.selectedFill)
                        .frame(width: cw - 4, height: h - Self.topInset + 14).offset(x: left + cw * CGFloat(i) + 2, y: Self.topInset - 14)
                }
                // the line joins neighbouring periods that both have a figure; a period without one leaves a gap
                Path { p in
                    for i in 1..<max(ps.count, 1) {
                        guard let a = ps[i - 1].percent, let b = ps[i].percent, ps[i].kind == .evaluated, ps[i - 1].kind == .evaluated else { continue }
                        p.move(to: CGPoint(x: x(i - 1), y: y(a))); p.addLine(to: CGPoint(x: x(i), y: y(b)))
                    }
                }
                .stroke(theme.textSecondary.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                Path { p in
                    for i in 1..<max(ps.count, 1) {
                        guard let a = ps[i - 1].percent, let b = ps[i].percent, ps[i].kind == .inProgress || ps[i - 1].kind == .inProgress else { continue }
                        p.move(to: CGPoint(x: x(i - 1), y: y(a))); p.addLine(to: CGPoint(x: x(i), y: y(b)))
                    }
                }
                .stroke(theme.textSecondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 4]))
                ForEach(ps) { p in
                    pointMark(p).position(x: x(p.id), y: py(p))
                }
                HStack(spacing: 0) {
                    ForEach(ps) { p in
                        Button { tap(p) } label: { Color.clear.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(p.spoken)
                            .accessibilityHint("Shows the sessions of this period")
                            .accessibilityAddTraits(inspected == p.id ? [.isButton, .isSelected] : [.isButton])
                            .accessibilityIdentifier("consistencyPoint-\(p.id)")
                    }
                }
                .padding(.leading, left)
                if let i = inspected, let p = ps.first(where: { $0.id == i }) {
                    let others: [(Double, Double)] = ps.filter { $0.id != i }.map { (Double(x($0.id)), Double(py($0))) }
                    // The label's width is only ESTIMATED for choosing its side (check 59: a measured width did not reach this
                    // layout, and a long label left the chart). Staying inside the chart does not depend on the estimate: the
                    // label is laid out in a box that ends at the chart's edges and shrinks its text before it would leave it.
                    let est = Double(p.tooltip.count) * 6.9 + (p.kind == .evaluated ? 32 : 20)
                    let place = ConsistencyTooltip.place(px: Double(x(i)), py: Double(py(p)), w: est, h: Double(Self.tipHeight),
                                                         width: Double(g.size.width), height: Double(h), others: others)
                    let slot = tipSlot(centre: CGFloat(place.box.x), width: g.size.width)
                    tooltip(p)
                        .frame(width: slot.width, height: Self.tipHeight, alignment: slot.alignment)
                        .offset(x: slot.x, y: CGFloat(place.box.y) - Self.tipHeight / 2)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 14).onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                let i = min(max(Int((v.location.x - left) / cw), 0), ps.count - 1)
                if inspected != i { select(ps[i]) }
            })
        }
    }
    private static let tipHeight: CGFloat = 26
    /// The horizontal box the floating label is laid out in: centred where the placement rule put it, and no wider than
    /// the distance to the nearer edge allows — so the label is where the rule checked it to be clear of other points
    /// (check 60: an edge-aligned box put the label over a neighbouring point), and it cannot leave the chart.
    private func tipSlot(centre bx: CGFloat, width W: CGFloat) -> (x: CGFloat, width: CGFloat, alignment: Alignment) {
        let half = max(20, min(bx, W - bx))
        return (bx - half, half * 2, .center)
    }
    /// The floating label of the chosen point: its figure and period, or the truthful status where there is no figure.
    private func tooltip(_ p: ConsistencyPoint) -> some View {
        HStack(spacing: 5) {
            if p.kind == .evaluated { mark(p.band, size: 8) }
            Text(p.tooltip).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityIdentifier("consistencyTooltip")
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(theme.surface2, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.textPrimary.opacity(0.35), lineWidth: 1))
    }
    @ViewBuilder private func pointMark(_ p: ConsistencyPoint) -> some View {
        let on = inspected == p.id
        switch p.kind {
        case .evaluated:
            mark(p.band, size: on ? 15 : 12)
                .background(Circle().fill(theme.surface).frame(width: 20, height: 20).opacity(on ? 1 : 0))
                .overlay(Circle().strokeBorder(theme.textPrimary, lineWidth: 1.5).frame(width: 24, height: 24).opacity(on ? 1 : 0))
        case .inProgress:
            Circle().fill(theme.surface).frame(width: on ? 15 : 12, height: on ? 15 : 12)
                .overlay(Circle().strokeBorder(theme.textPrimary.opacity(0.85), lineWidth: 2))
                .overlay(Circle().strokeBorder(theme.textPrimary, lineWidth: 1.5).frame(width: 24, height: 24).opacity(on ? 1 : 0))
        case .rest:
            Image(systemName: p.count.skipped > 0 ? "minus.circle" : p.sessions.isEmpty ? "moon.fill" : "plus.circle").font(.system(size: 10)).foregroundStyle(theme.textTertiary)
        case .upcoming:
            Image(systemName: "circle.dotted").font(.system(size: 12)).foregroundStyle(theme.textSecondary)
        case .noPlanned, .beforePlan:
            Capsule().fill(theme.textTertiary).frame(width: 10, height: 2)
        }
    }
    private func tap(_ p: ConsistencyPoint) {
        if inspected == p.id { inspected = nil } else { select(p) }
    }
    private func select(_ p: ConsistencyPoint) {
        inspected = p.id
        if mode == 0 { selectedWeek = p.id }
    }

    // MARK: inspection card (below the graph; replaced in place when another point is chosen)

    private func inspection(_ p: ConsistencyPoint, _ d: ConsistencyDashboard) -> some View {
        let shown = p.sessions.prefix(6)
        return card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if p.kind == .evaluated { mark(p.band, size: 10) }
                    Text(p.headline).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("consistencyInspectionTitle")
                }
                Text(p.line).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("consistencyInspectionLine")
                if p.count.planned + p.count.skipped > 0 {
                    Text("Completed \(p.count.done) · Planned \(p.count.planned) · Missed \(p.count.missed) · Skipped \(p.count.skipped)")
                        .font(CyFont.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("consistencyInspectionCounts")
                }
                if !shown.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { k, s in
                            stateLine(s, withDay: mode == 0).accessibilityIdentifier("consistencyInspectionSession-\(k)")
                        }
                        if p.sessions.count > shown.count {
                            Text("+ \(p.sessions.count - shown.count) more in Session details").font(CyFont.caption).foregroundStyle(theme.textTertiary)
                        }
                    }
                }
                Button { open(mode == 0 ? .weekOverview(p.start) : .day(p.start)) } label: {
                    HStack(spacing: 4) {
                        Text(mode == 0 ? "View week" : "View \(weekday(p.start))").font(CyFont.label)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(theme.accent).frame(minHeight: CyHit.min, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(mode == 0 ? "Opens the weekly overview" : "Opens the day")
                .accessibilityIdentifier("consistencyViewDetails")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("consistencyInspection")
    }
    private func weekday(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "EEEE"; return f.string(from: d) }
    private func shortDay(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "EEE d"; return f.string(from: d) }

    private func stateIcon(_ s: ConsistencySession.State) -> (String, Color) {
        switch s {
        case .completed: return ("checkmark.circle.fill", theme.success)
        case .missed: return ("xmark.circle.fill", theme.danger)
        case .skipped: return ("minus.circle", theme.textSecondary)
        case .inProgress: return ("circle.lefthalf.filled", theme.textPrimary)
        case .today, .upcoming: return ("circle", theme.textSecondary)
        case .recorded: return ("plus.circle", theme.textSecondary)
        case .notCounted: return ("circle.slash", theme.textTertiary)
        }
    }
    /// "Strength · Full body — Completed", with its symbol; the state is always written, never colour alone.
    private func stateLine(_ s: ConsistencySession, withDay: Bool) -> some View {
        let i = stateIcon(s.state)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: i.0).font(.caption).foregroundStyle(i.1).accessibilityHidden(true)
            (Text((withDay ? shortDay(s.date) + " · " : "") + s.title).foregroundColor(theme.textPrimary) + Text(" — \(s.state.rawValue)").foregroundColor(theme.textSecondary))
                .font(CyFont.footnote).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: D / F · the two summaries (fixed sentences from the records; no AI model writes them)

    private func insight(_ id: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle").font(.footnote.weight(.semibold)).foregroundStyle(theme.accent).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("COACH · FROM YOUR RECORDS").font(CyFont.overline).foregroundStyle(theme.textTertiary)
                Text(text).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(id + "Text")
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.highlightSurface, in: RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    // MARK: E · consistency by sport

    private func sportsSection(_ d: ConsistencyDashboard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Consistency by sport").font(CyFont.headline).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("consistencySportsTitle")
            if d.sports.isEmpty {
                Text("No sport is in your roster yet.").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
            }
            ForEach(d.sports) { r in
                VStack(alignment: .leading, spacing: 0) {
                    sportRow(r)
                    if sport == r.id { sportDetail(r, d) }
                }
                .background(sport == r.id ? theme.selectedFill : theme.surface, in: RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("consistencySports")
    }
    private func sportRow(_ r: ConsistencySportRow) -> some View {
        Button { sport = sport == r.id ? nil : r.id } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: r.icon).font(.body).foregroundStyle(theme.textPrimary).frame(width: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(CyFont.label).foregroundStyle(theme.textPrimary)
                        Text(r.detail).font(CyFont.caption).foregroundStyle(theme.textSecondary)
                    }
                    Spacer(minLength: 6)
                    if r.percent != nil { mark(r.band, size: 9) }
                    Text(r.status).font(r.percent != nil ? CyFont.metricSmall : CyFont.caption).foregroundStyle(r.percent != nil ? theme.textPrimary : theme.textSecondary)
                    Image(systemName: sport == r.id ? "chevron.up" : "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        if r.percent == nil {
                            Capsule().strokeBorder(theme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        } else {
                            Capsule().fill(theme.ringTrack)
                            Capsule().fill(color(r.band)).frame(width: max(6, g.size.width * CGFloat(r.count.fraction ?? 0)))
                                .opacity((r.count.fraction ?? 0) > 0 ? 1 : 0)
                        }
                    }
                }
                .frame(height: 6)
            }
            .padding(12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(r.spoken)
        .accessibilityHint("Shows the sessions counted for this sport")
        .accessibilityAddTraits(sport == r.id ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("consistencySport-\(r.id)")
    }
    private func sportDetail(_ r: ConsistencySportRow, _ d: ConsistencyDashboard) -> some View {
        let line: String
        if !r.tracked { line = "Cyclift does not plan or record \(r.name.lowercased()) yet. It stays in your roster and nothing is counted for it." }
        else if r.count.planned == 0 { line = "\(r.name) · \(d.week.title): nothing was planned." }
        else { line = "\(r.name) · \(d.week.title): \(r.count.ratio) planned sessions completed" + (r.inProgress ? " so far." : ".") }
        return VStack(alignment: .leading, spacing: 6) {
            Text(line)
                .font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("consistencySportDetailLine")
            ForEach(Array(r.sessions.enumerated()), id: \.element.id) { k, s in sessionButton(s, id: "consistencySportSession-\(k)") }
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("consistencySportDetail")
    }
    /// A session that opens what the app already has for it: the recorded ride or strength session, or the planned
    /// session's own page.
    private func sessionButton(_ s: ConsistencySession, id: String) -> some View {
        Button {
            switch s.record {
            case .ride(let r): open(.ride(r))
            case .strength(let l): open(.log(l))
            case .none: if let wid = s.workoutID, let w = store.plan.first(where: { $0.id == wid }) { prescription = w }
            }
        } label: {
            HStack(spacing: 6) {
                stateLine(s, withDay: true)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
            }
            .frame(minHeight: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(s.record == .none ? "Opens the planned session" : "Opens the recorded session")
        .accessibilityIdentifier(id)
    }

    // MARK: G · session details (closed until asked for)

    private func details(_ d: ConsistencyDashboard) -> some View {
        let chosen: Int? = mode == 1 ? inspected : nil
        let day: ConsistencyPoint? = chosen.flatMap { i in d.days.first(where: { $0.id == i }) }
        let scope: [ConsistencySession] = day?.sessions ?? d.week.sessions
        let dayName: String = day.map { weekday($0.start) } ?? ""
        return card {
            VStack(alignment: .leading, spacing: 8) {
                Button { detailsOpen.toggle() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Session details").font(CyFont.headline).foregroundStyle(theme.textPrimary)
                            Text("\(day?.title ?? d.week.title) · \(scope.count) session\(scope.count == 1 ? "" : "s")").font(CyFont.caption).foregroundStyle(theme.textSecondary)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: detailsOpen ? "chevron.up" : "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(theme.textSecondary)
                    }
                    .frame(minHeight: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(detailsOpen ? "Open" : "Closed")
                .accessibilityIdentifier("consistencyDetailsToggle")
                if detailsOpen {
                    if scope.isEmpty {
                        Text("No session in this period.").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                    }
                    ForEach(Array(scope.enumerated()), id: \.element.id) { k, s in sessionButton(s, id: "consistencyDetail-\(k)") }
                    Button { open(day.map { HomeRoute.day($0.start) } ?? HomeRoute.weekOverview(d.week.start)) } label: {
                        HStack(spacing: 4) {
                            Text(day == nil ? "Open weekly overview" : "Open \(dayName)").font(CyFont.label)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(theme.accent).frame(minHeight: CyHit.min, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("consistencyOpenOverview")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("consistencyDetails")
    }
}

private struct CyTriangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
        return p
    }
}
