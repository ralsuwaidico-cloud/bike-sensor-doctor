import SwiftUI

// Training Mix dashboard — the page the second Home circle opens (owner's shared design direction, 23 Nov 2026, 19:55;
// final visual sign-off pending). A DISTRIBUTION of recorded training time between the athlete's sports, beside what was
// planned: sport colours tell the sports apart; nothing here is an adherence band or a judgement of balance.
// Every figure comes from `TrainingMixDashboard` (the Home ring's own minutes); this file only draws it.

struct TrainingMixDashboardView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme
    var open: (HomeRoute) -> Void
    @State private var mode = 0                     // 0 = Weeks, 1 = Days
    @State private var selectedWeek: Int? = nil
    @State private var inspected: Int? = nil
    @State private var sport: String? = nil
    @State private var detailsOpen = false
    @State private var prescription: Workout? = nil

    var body: some View {
        let d = store.trainingMixDashboard(selectedWeek: selectedWeek)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary(d)
                graphCard(d)
                if let i = inspected, let p = points(d).first(where: { $0.id == i }) { inspection(p) }
                DashInsight(id: "mixInsight", text: coachText(d))
                sportsSection(d)
                details(d)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 130)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Training Mix").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $prescription) { w in HomePrescriptionSheet(workout: w) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trainingMixDashboard")
    }

    private func points(_ d: TrainingMixDashboard) -> [MixPoint] { mode == 0 ? d.weeks : d.days }
    private func coachText(_ d: TrainingMixDashboard) -> String {
        if mode == 1, let i = inspected, let day = d.days.first(where: { $0.id == i }) { return TrainingMixModel.dayInsight(day: day) }
        return d.weekInsight
    }
    private func color(_ sport: String) -> Color { sport == "cycling" ? theme.endurance : sport == "strength" ? theme.strength : theme.textTertiary }

    // MARK: compact summary — no standalone ratio

    private func summary(_ d: TrainingMixDashboard) -> some View {
        let w = d.week
        var parts: [String] = []
        if w.cycling > 0 { parts.append("Cycling \(Fmt.duration(minutes: w.cycling)) (\(MixPoint.percent(w.cycling, of: w.total))%)") }
        if w.strength > 0 { parts.append("Strength \(Fmt.duration(minutes: w.strength)) (\(MixPoint.percent(w.strength, of: w.total))%)") }
        return VStack(alignment: .leading, spacing: 3) {
            Text(d.periodTitle + (w.inProgress ? " · In progress" : "")).font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                .accessibilityIdentifier("mixPeriod")
            Text(w.total > 0 ? "\(Fmt.duration(minutes: w.total)) recorded" : "No recorded training")
                .font(CyFont.title).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mixSummaryLine")
            if !parts.isEmpty {
                Text(parts.joined(separator: " · ")).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mixDistribution")
            }
            if w.planned > 0 {
                Text("Planned \(Fmt.duration(minutes: w.planned))").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("mixPlanned")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mixSummary")
    }

    // MARK: stacked duration graph

    private func hours(_ minutes: Int) -> String {
        if minutes == 0 { return "0" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : String(format: "%.1f h", Double(minutes) / 60)
    }
    private func column(_ p: MixPoint, scale: Int) -> DashColumn {
        let f = DateFormatter()
        f.dateFormat = mode == 0 ? "d" : "EEE"; let top = f.string(from: p.start)
        f.dateFormat = mode == 0 ? "MMM" : "d"; let bottom = mode == 0 && p.inProgress ? "now" : f.string(from: p.start)
        return DashColumn(id: p.id, top: top, bottom: bottom, spoken: p.spoken, tip: p.tooltip, anchor: p.total > 0 ? Double(p.total) / Double(scale) : nil)
    }
    private func graphCard(_ d: TrainingMixDashboard) -> some View {
        let ps = points(d), scale = TrainingMixDashboard.scale(ps)
        return DashCard {
            VStack(alignment: .leading, spacing: 10) {
                DashSegments(prefix: "mixMode", titles: ["Weeks", "Days"], ids: ["weeks", "days"], selected: mode) { m in mode = m; inspected = nil }
                Text(mode == 0 ? "Recorded time · last \(ConsistencyDashboard.weekCount) weeks" : "Recorded time · \(d.week.title)").font(CyFont.caption).foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("mixGraphCaption")
                DashChart(prefix: "mix", columns: ps.map { column($0, scale: scale) }, axis: [hours(scale), hours(scale / 2), "0"], left: 34,
                          selected: inspected, placement: .topStrip, onTap: { i in tap(i) }, onDrag: { i in select(i) }) { geo in
                    ForEach(ps) { p in bar(p, geo, scale: scale) }
                }
                legend
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mixGraph")
    }
    /// One period's bar: cycling at the bottom, strength above it, a short line at the planned total; a quiet mark where
    /// nothing is recorded.
    @ViewBuilder private func bar(_ p: MixPoint, _ geo: DashGeo, scale: Int) -> some View {
        let w = min(22, geo.cw * 0.5), x = geo.x(p.id)
        let yc = geo.y(Double(p.cycling) / Double(scale)), yt = geo.y(Double(p.total) / Double(scale))
        if p.cycling > 0 {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(theme.endurance)
                .frame(width: w, height: max(2, geo.base - yc)).position(x: x, y: (geo.base + yc) / 2)
        }
        if p.strength > 0 {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(theme.strength)
                .frame(width: w, height: max(2, yc - yt - (p.cycling > 0 ? 1.5 : 0))).position(x: x, y: (yc + yt - (p.cycling > 0 ? 1.5 : 0)) / 2)
        }
        if p.planned > 0 {
            Capsule().fill(theme.textPrimary.opacity(0.75)).frame(width: w + 10, height: 2).position(x: x, y: geo.y(Double(p.planned) / Double(scale)))
        }
        if p.total == 0 {
            if p.kind == .upcoming { Image(systemName: "circle.dotted").font(.system(size: 12)).foregroundStyle(theme.textSecondary).position(x: x, y: geo.base - 2) }
            else { Capsule().fill(theme.textTertiary).frame(width: 10, height: 2).position(x: x, y: geo.base - 2) }
        }
    }
    private var legend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(theme.endurance).frame(width: 9, height: 9); Text("Cycling") }
            HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(theme.strength).frame(width: 9, height: 9); Text("Strength") }
            HStack(spacing: 4) { Capsule().fill(theme.textPrimary.opacity(0.75)).frame(width: 12, height: 2); Text("Planned") }
        }
        .font(.system(size: 10, weight: .medium)).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mixLegend")
    }
    private func tap(_ i: Int) { if inspected == i { inspected = nil } else { select(i) } }
    private func select(_ i: Int) { inspected = i; if mode == 0 { selectedWeek = i } }

    // MARK: inspection card

    private func weekday(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "EEEE"; return f.string(from: d) }
    private func shortDay(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "EEE d"; return f.string(from: d) }
    private func sportLine(_ name: String, _ recorded: Int, _ planned: Int) -> String {
        "\(name) · \(recorded > 0 ? "\(Fmt.duration(minutes: recorded)) recorded" : "nothing recorded")" + (planned > 0 ? " · \(Fmt.duration(minutes: planned)) planned" : " · nothing planned")
    }
    private func inspection(_ p: MixPoint) -> some View {
        let shown = p.sessions.prefix(6)
        return DashCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(p.headline).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mixInspectionTitle")
                VStack(alignment: .leading, spacing: 3) {
                    if p.cycling > 0 || p.plannedCycling > 0 {
                        Text(sportLine("Cycling", p.cycling, p.plannedCycling)).accessibilityIdentifier("mixInspectionCycling")
                    }
                    if p.strength > 0 || p.plannedStrength > 0 {
                        Text(sportLine("Strength", p.strength, p.plannedStrength)).accessibilityIdentifier("mixInspectionStrength")
                    }
                    if p.total == 0 && p.planned == 0 { Text("Nothing was planned or recorded.").accessibilityIdentifier("mixInspectionNone") }
                }
                .font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                if !shown.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { k, s in
                            sessionLine(s, withDay: mode == 0).accessibilityIdentifier("mixInspectionSession-\(k)")
                        }
                        if p.sessions.count > shown.count {
                            Text("+ \(p.sessions.count - shown.count) more in Session details").font(CyFont.caption).foregroundStyle(theme.textTertiary)
                        }
                    }
                }
                DashLink(title: mode == 0 ? "View week" : "View \(weekday(p.start))", id: "mixViewDetails") { open(mode == 0 ? HomeRoute.weekOverview(p.start) : HomeRoute.day(p.start)) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mixInspection")
    }
    /// "Mon 16 · Endurance — 58 min recorded · 60 min planned", with the sport's colour mark.
    private func sessionLine(_ s: MixSession, withDay: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(s.recorded != nil ? color(s.base.sport) : Color.clear)
                .overlay(Circle().strokeBorder(color(s.base.sport), lineWidth: 1.5)).frame(width: 8, height: 8).accessibilityHidden(true)
            (Text((withDay ? shortDay(s.base.date) + " · " : "") + s.base.title).foregroundColor(theme.textPrimary) + Text(" — \(s.detail)").foregroundColor(theme.textSecondary))
                .font(CyFont.footnote).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
    private func sessionButton(_ s: MixSession, id: String) -> some View {
        Button {
            switch s.base.record {
            case .ride(let r): open(.ride(r))
            case .strength(let l): open(.log(l))
            case .none: if let wid = s.base.workoutID, let w = store.plan.first(where: { $0.id == wid }) { prescription = w }
            }
        } label: {
            HStack(spacing: 6) {
                sessionLine(s, withDay: true)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
            }
            .frame(minHeight: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(s.base.record == .none ? "Opens the planned session" : "Opens the recorded session")
        .accessibilityIdentifier(id)
    }

    // MARK: breakdown by sport

    private func sportsSection(_ d: TrainingMixDashboard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Training by sport").font(CyFont.headline).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("mixSportsTitle")
            if d.sports.isEmpty { Text("No sport is in your roster yet.").font(CyFont.footnote).foregroundStyle(theme.textSecondary) }
            ForEach(d.sports) { r in
                VStack(alignment: .leading, spacing: 0) {
                    sportRow(r)
                    if sport == r.id { sportDetail(r, d) }
                }
                .background(sport == r.id ? theme.selectedFill : theme.surface, in: RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mixSports")
    }
    private func sportRow(_ r: MixSportRow) -> some View {
        Button { sport = sport == r.id ? nil : r.id } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: r.icon).font(.body).foregroundStyle(theme.textPrimary).frame(width: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(CyFont.label).foregroundStyle(theme.textPrimary)
                        Text(r.detail).font(CyFont.caption).foregroundStyle(theme.textSecondary)
                    }
                    Spacer(minLength: 6)
                    Text(r.value).font(r.tracked ? CyFont.metricSmall : CyFont.caption).foregroundStyle(r.tracked ? theme.textPrimary : theme.textSecondary)
                    Image(systemName: sport == r.id ? "chevron.up" : "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        if !r.tracked {
                            Capsule().strokeBorder(theme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        } else {
                            Capsule().fill(theme.ringTrack)
                            Capsule().fill(color(r.id)).frame(width: max(6, g.size.width * CGFloat(r.share ?? 0) / 100)).opacity((r.share ?? 0) > 0 ? 1 : 0)
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
        .accessibilityHint("Shows the sessions of this sport")
        .accessibilityAddTraits(sport == r.id ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("mixSport-\(r.id)")
    }
    private func sportDetail(_ r: MixSportRow, _ d: TrainingMixDashboard) -> some View {
        let line: String
        if !r.tracked { line = "Cyclift does not record \(r.name.lowercased()) yet. It stays in your roster, and no time is shown for it." }
        else if r.sessions.isEmpty { line = "\(r.name) · \(d.week.title): nothing was planned or recorded." }
        else { line = "\(r.name) · \(d.week.title): \(Fmt.duration(minutes: r.minutes)) recorded" + (r.planned > 0 ? ", \(Fmt.duration(minutes: r.planned)) planned." : ".") }
        return VStack(alignment: .leading, spacing: 6) {
            Text(line).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mixSportDetailLine")
            ForEach(Array(r.sessions.enumerated()), id: \.element.id) { k, s in sessionButton(s, id: "mixSportSession-\(k)") }
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mixSportDetail")
    }

    // MARK: session details (closed until asked for)

    private func details(_ d: TrainingMixDashboard) -> some View {
        let chosen: Int? = mode == 1 ? inspected : nil
        let day: MixPoint? = chosen.flatMap { i in d.days.first(where: { $0.id == i }) }
        let scope: [MixSession] = day?.sessions ?? d.week.sessions
        let dayName: String = day.map { weekday($0.start) } ?? ""
        return DashCard {
            VStack(alignment: .leading, spacing: 8) {
                DashDisclosure(title: "Session details", caption: "\(day?.title ?? d.week.title) · \(scope.count) session\(scope.count == 1 ? "" : "s")", open: detailsOpen, id: "mixDetailsToggle") { detailsOpen.toggle() }
                if detailsOpen {
                    if scope.isEmpty { Text("No session in this period.").font(CyFont.footnote).foregroundStyle(theme.textSecondary) }
                    ForEach(Array(scope.enumerated()), id: \.element.id) { k, s in sessionButton(s, id: "mixDetail-\(k)") }
                    DashLink(title: day == nil ? "Open weekly overview" : "Open \(dayName)", id: "mixOpenOverview") {
                        open(day.map { HomeRoute.day($0.start) } ?? HomeRoute.weekOverview(d.week.start))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mixDetails")
    }
}
