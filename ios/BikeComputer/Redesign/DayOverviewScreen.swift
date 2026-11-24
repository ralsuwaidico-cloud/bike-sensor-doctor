import SwiftUI

// Daily Training Overview — PROPOSED revision of the Day page (owner, 24 Nov 2026, 22:42; NOT approved).
// One calm card per session, in the owner's order: current workout · previous comparable workout · performance
// comparison · Coach's note from the records · and, below all sessions, the day's health readings.
// Detail is behind disclosures: exercises, time in zones and the history graph open on request.
// Start, Results, Move and the session's own page work exactly as on the earlier Day page (same buttons, same actions,
// same identifiers). This page reads records only — opening it never changes the plan.
// Every figure comes from `DayOverview`; this file only draws it. Shown only in the redesigned app.

struct DayOverviewView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    @Environment(\.cyTheme) private var theme
    let date: Date
    var perform: (HomeAction) -> Void
    var open: (HomeRoute) -> Void
    @State private var prescription: Workout? = nil
    @State private var detailOpen: Set<String> = []      // "<session>-exercises" / "-zones" / "-history"
    @State private var exerciseOpen: String? = nil        // "<session>|<exercise>"
    @State private var historyPoint: [String: Int] = [:]

    var body: some View {
        let o = store.dayOverview(date, recorderActive: recorder.isActive)
        let f = DateFormatter(); let _ = f.dateFormat = "EEEE d MMMM"
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if o.sessions.isEmpty { emptyCard(o) }
                else {
                    if !o.detail.explanation.isEmpty {
                        Text(o.detail.explanation).font(CyFont.footnote).foregroundStyle(theme.textSecondary).padding(.horizontal, 2)
                            .accessibilityIdentifier("daySummaryLine")
                    }
                    ForEach(Array(o.sessions.enumerated()), id: \.element.id) { j, s in sessionCard(s, index: j) }
                }
                if let n = o.weekNote {
                    Text(n).font(CyFont.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
                        .accessibilityIdentifier("dayWeekNote")
                }
                healthCard(o)
                if !o.unsupported.isEmpty {
                    Text("\(DayReviewModel.list(o.unsupported)) cannot be recorded yet, so no comparison exists for \(o.unsupported.count == 1 ? "it" : "them").")
                        .font(CyFont.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
                        .accessibilityIdentifier("dayUnsupported")
                }
                Text("Opening this page never changes your plan. Move, skip or swap a session on the session itself.")
                    .font(CyFont.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 130)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(f.string(from: date)).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $prescription) { w in HomePrescriptionSheet(workout: w) }
        .accessibilityIdentifier("homeDayDetail")
    }

    // MARK: empty days — a rest day is not a free day

    private func emptyCard(_ o: DayOverview) -> some View {
        let k = o.detail.kind
        let title = k == .beforePlan ? "Before this plan started" : k == .noPlan ? "No plan yet" : o.freeDay ? "Free day" : "Rest day"
        let icon = k == .beforePlan ? "calendar.badge.minus" : k == .noPlan ? "calendar" : o.freeDay ? "calendar.badge.plus" : "moon.zzz.fill"
        let line = o.freeDay ? "Nothing is scheduled for this day. It is not a rest day of your recurring week." : o.detail.explanation
        return DashCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(theme.textSecondary).frame(width: 30).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(CyFont.headline).foregroundStyle(theme.textPrimary).accessibilityIdentifier("dayEmptyTitle")
                    Text(line).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dayEmpty")
    }

    // MARK: one session

    private func color(_ v: DayVerdict) -> Color { v == .better ? theme.success : v == .worse ? theme.danger : theme.textSecondary }
    private func symbol(_ v: DayVerdict) -> String { v == .better ? "arrow.up.right" : v == .worse ? "arrow.down.right" : v == .same ? "equal" : "minus" }
    private func statusColor(_ s: String) -> Color { s == "Done" || s == "Recorded" || s == "Imported" ? theme.success : s == "Missed" ? theme.danger : theme.textSecondary }

    private func sessionCard(_ s: DaySessionReview, index j: Int) -> some View {
        DashCard {
            VStack(alignment: .leading, spacing: 12) {
                header(s, index: j)
                step("1", "Current workout") {
                    VStack(alignment: .leading, spacing: 3) {
                        pair("Planned", s.plannedLine ?? "Not planned — recorded outside the plan", id: "daySession-\(j)-planned")
                        pair("Recorded", actualText(s), id: "daySession-\(j)-actual")
                    }
                }
                step("2", "Previous comparable workout") {
                    if let p = s.previous {
                        Button { openRecord(p.record) } label: {
                            HStack(alignment: .top, spacing: 6) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(DayReviewModel.dateText(p.date)) · \(p.title)").font(CyFont.label).foregroundStyle(theme.textPrimary)
                                    Text(p.line).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                                    Text(p.basis).font(CyFont.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(theme.textTertiary).padding(.top, 3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Opens that recorded session")
                        .accessibilityIdentifier("daySession-\(j)-previous")
                    } else {
                        Text(s.previousEmpty).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("daySession-\(j)-noPrevious")
                    }
                }
                step("3", "Performance comparison") { comparison(s, index: j) }
                step("4", "Coach's analysis") {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("FROM YOUR RECORDS · NOT WRITTEN BY AN AI MODEL").font(CyFont.overline).foregroundStyle(theme.textTertiary)
                        Text(s.analysis).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("daySession-\(j)-analysis")
                    }
                }
                if let h = s.history { history(h, s, index: j) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daySession-\(j)")
    }

    private func actualText(_ s: DaySessionReview) -> String {
        if let a = s.actualLine { return a }
        if s.item.statusText == "Missed" { return "Not recorded — missed" }
        if s.item.statusText == "Skipped" { return "Not recorded — skipped" }
        return "Not done yet"
    }

    /// Title, status and the same action button as before; the title opens the record or the session's own page.
    private func header(_ s: DaySessionReview, index j: Int) -> some View {
        let item = s.item
        return HStack(alignment: .center, spacing: 10) {
            Button {
                switch item.record {
                case .none: if let w = item.session?.workout { prescription = w }
                default: openRecord(item.record)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: s.sport == .cycling ? "bicycle" : "dumbbell.fill").font(.body)
                        .foregroundStyle(s.sport == .cycling ? theme.endurance : theme.strength).frame(width: 30, height: 30)
                        .background((s.sport == .cycling ? theme.endurance : theme.strength).opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                        Text(item.statusText).font(CyFont.caption).foregroundStyle(statusColor(item.statusText)).accessibilityIdentifier("dayItem-\(j)-status")
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
                }
                .frame(minHeight: CyHit.min).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(item.record == .none ? "Opens the session's details" : "Opens the recorded workout")
            .accessibilityIdentifier("dayItem-\(j)")
            if let h = item.session, h.status != .skipped {
                HomePrimaryButton(action: h.action, isRide: h.isRide, elapsed: recorder.elapsedS, identifier: "dayItem-\(j)-action", kind: .compact, perform: perform)
            }
        }
    }

    private func step<C: View>(_ n: String, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(theme.cardStroke).frame(height: 1).accessibilityHidden(true)
            Text(title.uppercased()).font(CyFont.overline).foregroundStyle(theme.textTertiary).accessibilityAddTraits(.isHeader)
            content()
        }
    }
    private func pair(_ name: String, _ value: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).font(CyFont.footnote).foregroundStyle(theme.textSecondary).frame(width: 72, alignment: .leading)
            Text(value).font(CyFont.footnote).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("\(name): \(value)").accessibilityIdentifier(id)
    }

    // MARK: 3 — comparison

    @ViewBuilder private func comparison(_ s: DaySessionReview, index j: Int) -> some View {
        let main = s.metrics.filter { !$0.id.hasPrefix("r-zone") }, zones = s.metrics.filter { $0.id.hasPrefix("r-zone") }
        VStack(alignment: .leading, spacing: 8) {
            if s.sport == .strength && s.completed && s.previous != nil { tally(s, index: j) }
            if s.metrics.isEmpty && s.exercises.isEmpty {
                Text("No measurements to set side by side.").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
            }
            ForEach(main) { m in metricRow(m, id: "daySession-\(j)-metric-\(m.id)") }
            if !s.exercises.isEmpty {
                let key = "\(s.id)-exercises", isOpen = detailOpen.contains(key)
                toggle("Exercise by exercise", "\(s.exercises.count) exercise\(s.exercises.count == 1 ? "" : "s") · sets, reps, load and volume", isOpen, id: "daySession-\(j)-exercisesToggle") { flip(key) }
                if isOpen { ForEach(Array(s.exercises.enumerated()), id: \.element.id) { k, e in exerciseRow(e, session: s, id: "daySession-\(j)-exercise-\(k)") } }
            }
            if !zones.isEmpty {
                let key = "\(s.id)-zones", isOpen = detailOpen.contains(key)
                toggle("Time in zones", "Shown as recorded; not judged", isOpen, id: "daySession-\(j)-zonesToggle") { flip(key) }
                if isOpen { ForEach(zones) { m in metricRow(m, id: "daySession-\(j)-metric-\(m.id)") } }
            }
        }
    }
    /// "1 up · 1 down · 1 unchanged" — colour, a symbol and a word each.
    private func tally(_ s: DaySessionReview, index j: Int) -> some View {
        let up = s.exercises.filter { $0.verdict == .better }.count, down = s.exercises.filter { $0.verdict == .worse }.count
        let same = s.exercises.filter { $0.verdict == .same }.count, na = s.exercises.count - up - down - same
        return HStack(spacing: 12) {
            if up > 0 { chip("\(up) up", .better) }
            if down > 0 { chip("\(down) down", .worse) }
            if same > 0 { chip("\(same) unchanged", .same) }
            if na > 0 { chip("\(na) not comparable", .notComparable) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("daySession-\(j)-tally")
    }
    private func chip(_ text: String, _ v: DayVerdict) -> some View {
        HStack(spacing: 4) { Image(systemName: symbol(v)).font(.caption2.weight(.bold)); Text(text).font(CyFont.caption) }.foregroundStyle(color(v))
    }
    private func metricRow(_ m: DayMetric, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(m.name).font(CyFont.label).foregroundStyle(theme.textPrimary)
                Spacer(minLength: 6)
                HStack(spacing: 4) { Image(systemName: symbol(m.verdict)).font(.caption2.weight(.bold)); Text(m.change).font(CyFont.footnote) }.foregroundStyle(color(m.verdict))
            }
            Text((m.planned.map { "Planned \($0) · " } ?? "") + "Previous \(m.previous ?? "—") · Now \(m.current ?? "—")")
                .font(CyFont.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(m.spoken)
        .accessibilityValue(m.verdict.rawValue)
        .accessibilityIdentifier(id)
    }
    private func exerciseRow(_ e: DayExercise, session s: DaySessionReview, id: String) -> some View {
        let key = "\(s.id)|\(e.id)", isOpen = exerciseOpen == key
        return VStack(alignment: .leading, spacing: 6) {
            Button { exerciseOpen = isOpen ? nil : key } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(e.name).font(CyFont.label).foregroundStyle(theme.textPrimary).multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary)
                    }
                    HStack(spacing: 4) { Image(systemName: symbol(e.verdict)).font(.caption2.weight(.bold)); Text(e.change).font(CyFont.footnote) }.foregroundStyle(color(e.verdict))
                    Text((e.planned.map { "Planned \($0) · " } ?? "") + "Previous \(e.previous ?? "—") · Now \(e.current ?? "—")")
                        .font(CyFont.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(e.name). \(e.change). Previous \(e.previous ?? "not recorded"). Now \(e.current ?? "not recorded").")
            .accessibilityValue(e.verdict.rawValue)
            .accessibilityIdentifier(id)
            if isOpen { ForEach(e.metrics) { m in metricRow(m, id: "\(id)-\(m.name.replacingOccurrences(of: " ", with: ""))").padding(.leading, 12) } }
        }
        .padding(10).background(theme.selectedFill.opacity(isOpen ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    private func toggle(_ title: String, _ caption: String, _ isOpen: Bool, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(CyFont.label).foregroundStyle(theme.accent)
                    Text(caption).font(CyFont.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 6)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(theme.textSecondary)
            }
            .frame(minHeight: CyHit.min).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOpen ? "Open" : "Closed")
        .accessibilityIdentifier(id)
    }
    private func flip(_ key: String) { if detailOpen.contains(key) { detailOpen.remove(key) } else { detailOpen.insert(key) } }

    // MARK: history graph — only when at least three comparable records exist

    @ViewBuilder private func history(_ h: DayHistory, _ s: DaySessionReview, index j: Int) -> some View {
        let key = "\(s.id)-history", isOpen = detailOpen.contains(key), sel = historyPoint[s.id]
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(theme.cardStroke).frame(height: 1).accessibilityHidden(true)
            toggle("Performance history", "\(h.title) · \(h.points.count) sessions", isOpen, id: "daySession-\(j)-historyToggle") { flip(key) }
            if isOpen {
                let f = DateFormatter(); let _ = f.dateFormat = "d"; let g = DateFormatter(); let _ = g.dateFormat = "MMM"
                DashChart(prefix: "dayHistory\(j)", columns: h.points.map { p in
                              DashColumn(id: p.id, top: f.string(from: p.date), bottom: p.isCurrent ? "this" : g.string(from: p.date),
                                         spoken: "\(DayReviewModel.dateText(p.date)), \(p.text)", tip: ["\(p.text) · \(DayReviewModel.dateText(p.date))"], anchor: p.value / h.top) },
                          axis: [axis(h.top), axis(h.top / 2), "0"], left: 38, selected: sel, placement: .rule,
                          onTap: { i in historyPoint[s.id] = sel == i ? nil : i }, onDrag: { i in historyPoint[s.id] = i }) { geo in
                    Path { path in
                        for (k, p) in h.points.enumerated() {
                            let pt = CGPoint(x: geo.x(p.id), y: geo.y(p.value / h.top)); if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                        }
                    }
                    .stroke(theme.textSecondary.opacity(0.6), lineWidth: 1.5)
                    ForEach(h.points) { p in
                        Circle().fill(p.isCurrent ? theme.accent : theme.textPrimary).frame(width: p.isCurrent ? 10 : 8, height: p.isCurrent ? 10 : 8)
                            .position(x: geo.x(p.id), y: geo.y(p.value / h.top))
                    }
                }
                if let i = sel, let p = h.points.first(where: { $0.id == i }) {
                    Button { openRecord(p.record) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(DayReviewModel.dateText(p.date)) · \(p.text)").font(CyFont.label).foregroundStyle(theme.textPrimary)
                                Text(p.isCurrent ? "This session" : "Open that session").font(CyFont.caption).foregroundStyle(theme.accent)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(theme.textTertiary)
                        }
                        .frame(minHeight: CyHit.min).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("daySession-\(j)-historyOpen")
                }
            }
        }
    }
    private func axis(_ v: Double) -> String { v >= 1000 ? String(format: "%.1fk", v / 1000) : "\(Int(v.rounded()))" }

    // MARK: health — below the workouts; only what is stored

    private func healthCard(_ o: DayOverview) -> some View {
        DashCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Health this day").font(CyFont.headline).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
                if !o.hasHealth {
                    Text("No health readings for this day.").font(CyFont.footnote).foregroundStyle(theme.textSecondary).accessibilityIdentifier("dayHealthEmpty")
                }
                ForEach(o.health) { r in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: r.icon).font(.footnote).foregroundStyle(theme.textSecondary).frame(width: 20).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.name).font(CyFont.label).foregroundStyle(theme.textPrimary)
                            Text(r.detail).font(CyFont.caption).foregroundStyle(theme.textSecondary)
                        }
                        Spacer(minLength: 6)
                        Text(r.value ?? "—").font(r.value == nil ? CyFont.footnote : CyFont.metricSmall).foregroundStyle(r.value == nil ? theme.textTertiary : theme.textPrimary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(r.name): \(r.value ?? "no reading"). \(r.detail)")
                    .accessibilityIdentifier("dayHealth-\(r.id)")
                }
                Text("\(DayReviewModel.list(o.uncollected)) are not collected by Cyclift yet. No health score is calculated.")
                    .font(CyFont.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dayHealthUncollected")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dayHealth")
    }

    private func openRecord(_ r: HomeDayItem.Record) {
        switch r { case .ride(let id): open(.ride(id)); case .strength(let id): open(.log(id)); case .none: break }
    }
}
