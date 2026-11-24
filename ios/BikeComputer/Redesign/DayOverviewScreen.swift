import SwiftUI

// Daily Training Overview — PROPOSED revision of the Day page (owner, 24 Nov 2026, 22:42; NOT approved).
// One calm card per session, in the owner's order: current workout · previous comparable workout · performance
// comparison · Coach's note from the records · and, below all sessions, the day's health readings.
// Detail is behind disclosures: exercises, time in zones and the history graph open on request.
// PRESENTATION REFINED 25 Nov 2026 (owner, 01:41 — workflow approved, visual design pending): the card leads with the
// few results that matter (one line per exercise, or power and heart rate), everything else is under one "Details"
// disclosure that is closed by default, the Coach's explanation is one sentence, and health is one compact row.
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
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(theme.textTertiary).padding(.top, 3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("\(p.basis). Opens that recorded session")
                        .accessibilityIdentifier("daySession-\(j)-previous")
                    } else {
                        Text(s.previousEmpty).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("daySession-\(j)-noPrevious")
                    }
                }
                step("3", "Performance changes") { comparison(s, index: j) }
                step("4", "Coach's explanation · from your records") {
                    Text(s.short).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("daySession-\(j)-analysis")
                }
                if let h = s.history { history(h, s, index: j) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daySession-\(j)")
    }

    /// True when "Start" would not begin a recording: a planned session whose day has not come.
    static func viewOnly(_ h: HomeSession, now: Date = Date(), calendar cal: Calendar = .current) -> Bool {
        guard h.status == .planned, cal.startOfDay(for: h.workout.date) > cal.startOfDay(for: now) else { return false }
        switch h.action { case .startStrength, .openRideScreen: return true; default: return false }
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
                if DayOverviewView.viewOnly(h) {
                    // a session of a later day cannot be started today: the button says what it does (owner, 24 Nov 2026)
                    Button { prescription = h.workout } label: {
                        Text("View workout").font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(theme.textPrimary)
                            .padding(.horizontal, 14).frame(minHeight: 36).background(theme.selectedFill, in: Capsule())
                            .frame(minHeight: CyHit.min).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the session's details. It can be started on its day, or moved to today there.")
                    .accessibilityIdentifier("dayItem-\(j)-action")
                } else {
                    HomePrimaryButton(action: h.action, isRide: h.isRide, elapsed: recorder.elapsedS, identifier: "dayItem-\(j)-action", kind: .compact, perform: perform)
                }
            }
        }
    }

    /// A section of the card's fixed order: current · previous · changes · explanation. Plain labels, as on Home.
    private func stepTitle(_ n: String, _ title: String) -> some View {
        Text(title.uppercased()).font(CyFont.overline).foregroundStyle(theme.textTertiary).accessibilityAddTraits(.isHeader)
    }
    private func step<C: View>(_ n: String, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(theme.cardStroke).frame(height: 1).accessibilityHidden(true)
            stepTitle(n, title)
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

    /// The few results that matter first; every other figure under one disclosure, closed by default.
    @ViewBuilder private func comparison(_ s: DaySessionReview, index j: Int) -> some View {
        let keyIds: Set<String> = ["s-volume", "r-power", "r-hr"]
        let comparable = s.completed && s.previous != nil
        let key = s.metrics.filter { keyIds.contains($0.id) && $0.previous != nil && $0.current != nil }
        let rest = s.metrics.filter { m in !key.contains { $0.id == m.id } }
        let results = comparable ? s.exercises.filter { $0.current != nil } : []
        VStack(alignment: .leading, spacing: 8) {
            if results.isEmpty && key.isEmpty {
                Text(s.completed ? "Nothing to compare yet." : "Shown once this session is recorded.").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("daySession-\(j)-noChanges")
            }
            ForEach(Array(results.enumerated()), id: \.element.id) { k, e in resultRow(e.name, shortChange(e.change, e.verdict), e.verdict, id: "daySession-\(j)-result-\(k)") }
            ForEach(key) { m in resultRow(m.name, keyText(m), m.verdict, id: "daySession-\(j)-metric-\(m.id)") }
            if !rest.isEmpty || !s.exercises.isEmpty {
                let dk = "\(s.id)-details", isOpen = detailOpen.contains(dk)
                toggle("Details", s.exercises.isEmpty ? "All figures and time in zones" : "Exercise by exercise and all figures", isOpen, id: "daySession-\(j)-detailsToggle") { flip(dk) }
                if isOpen {
                    ForEach(Array(s.exercises.enumerated()), id: \.element.id) { k, e in exerciseRow(e, session: s, id: "daySession-\(j)-exercise-\(k)") }
                    ForEach(rest) { m in metricRow(m, id: "daySession-\(j)-metric-\(m.id)") }
                    Text(s.analysis).font(CyFont.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("daySession-\(j)-reasoning")
                }
            }
        }
    }
    /// What the card shows for a change: a judged result keeps its figure; anything else is said plainly.
    private func shortChange(_ change: String, _ v: DayVerdict) -> String {
        if v == .same { return change == "No change" || change == "Unchanged" ? "Unchanged" : "Similar (\(change))" }
        if v == .notComparable { return change.contains("not compar") ? "Not comparable" : change }
        return change
    }
    /// A key figure: both values, then the change — or "Not comparable" where the difference proves nothing.
    private func keyText(_ m: DayMetric) -> String { "\(m.previous ?? "—") → \(m.current ?? "—") · \(m.verdict == .notComparable ? "Not comparable" : shortChange(m.change, m.verdict))" }
    /// One result on one line: a symbol and colour only where the change is established, then the name and the change.
    private func resultRow(_ name: String, _ change: String, _ v: DayVerdict, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol(v)).font(.caption.weight(.bold)).foregroundStyle(color(v)).frame(width: 16).accessibilityHidden(true)
            Text(name).font(CyFont.label).foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            Text(change).font(CyFont.footnote).foregroundStyle(v == .better || v == .worse ? color(v) : theme.textSecondary).multilineTextAlignment(.trailing).lineLimit(2).minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(change)")
        .accessibilityValue(v.rawValue)
        .accessibilityIdentifier(id)
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
            toggle("History", h.title, isOpen, id: "daySession-\(j)-historyToggle") { flip(key) }
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
        let tiles = o.health.filter { $0.id != "soreness" }, sore = o.health.first { $0.id == "soreness" }
        return DashCard {
            VStack(alignment: .leading, spacing: 10) {
                stepTitle("5", "Daily health metrics")
                if !o.hasHealth {
                    Text("No health readings for this day.").font(CyFont.footnote).foregroundStyle(theme.textSecondary).accessibilityIdentifier("dayHealthEmpty")
                }
                HStack(alignment: .top, spacing: 8) {
                    ForEach(tiles) { r in healthTile(r) }
                }
                Text("Soreness: \(sore?.value ?? "not answered") · \(DayReviewModel.list(o.uncollected).lowercased()): not collected yet")
                    .font(CyFont.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dayHealthUncollected")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dayHealth")
    }
    private func healthTile(_ r: DayHealthRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(r.value ?? "—").font(CyFont.metricSmall).foregroundStyle(r.value == nil ? theme.textTertiary : theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            Text(r.id == "restingHR" ? "Resting HR" : r.name).font(CyFont.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
            if r.value == nil { Text(r.detail).font(CyFont.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.name): \(r.value ?? "no reading"). \(r.detail)")
        .accessibilityIdentifier("dayHealth-\(r.id)")
    }

    private func openRecord(_ r: HomeDayItem.Record) {
        switch r { case .ride(let id): open(.ride(id)); case .strength(let id): open(.log(id)); case .none: break }
    }
}
