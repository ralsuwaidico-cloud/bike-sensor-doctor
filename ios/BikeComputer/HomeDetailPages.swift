import SwiftUI

// MARK: - Checkpoint C correction pass (owner 6 Nov): where the Home cards lead.
// Every page is backed by `HomeSummaries.swift` and the existing detail screens: a recorded ride opens `RideDetailView`,
// a strength log `StrengthSessionDetail`, a planned session its prescription (`StrengthWorkoutScreen` / `WorkoutDetail`,
// the screens Plan opens). Nothing here changes the plan: Start / Resume / Results go through `perform` as on the hub.

/// The pages reachable from Home, pushed on Home's own NavigationStack (back returns to the dashboard's scroll position).
enum HomeRoute: Hashable {
    case weekOverview(Date)
    case cycling
    case strength
    case day(Date)
    case ride(UUID)
    case log(UUID)
    case recovery
    case goal
    case menu(ProfileMenuDestination)     // Profile Quick Menu destinations (6 Nov addendum)
}

/// A session row shared by the overview, the day page and the summaries: title + status, the hub's one action, and a
/// tap that opens the real thing (recorded → details page; planned → prescription).
struct HomeItemRow: View {
    let item: HomeDayItem
    var elapsed: Int? = nil
    var identifier: String
    var perform: (HomeAction) -> Void
    var openRecord: (HomeDayItem.Record) -> Void
    var openPrescription: (Workout) -> Void
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        let tap = Button {
            switch item.record {
            case .none: if let w = item.session?.workout { openPrescription(w) }
            default: openRecord(item.record)
            }
        } label: {
            HStack(spacing: 10) {
                CyIconBox(systemName: item.isRide ? "bicycle" : "dumbbell.fill", sport: item.isRide ? .cycling : .strength)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    Text(item.subtitle).font(CyType.secondary).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    Text(item.statusText).font(CyType.captionSmall).foregroundStyle(statusColor).accessibilityIdentifier("\(identifier)-status")
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CyTheme.ink3).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: CyTheme.minTap, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.record == .none ? "Opens the session's prescription" : "Opens the recorded workout")
        .accessibilityIdentifier(identifier)
        Group {
            if let s = item.session, s.status != .skipped {
                let action = HomePrimaryButton(action: s.action, isRide: s.isRide, elapsed: elapsed, identifier: "\(identifier)-action", kind: .compact, perform: perform)
                if dts >= .xxLarge { VStack(alignment: .leading, spacing: 8) { tap; action } }
                else { HStack(alignment: .center, spacing: 8) { tap; action } }
            } else { tap }
        }
        .padding(.vertical, 4)
    }
    private var statusColor: Color {
        switch item.session?.status {
        case .done, .marked, .imported: return CyTheme.recovery.tint
        case .missed: return CyTheme.bad
        case .inProgress: return CyTheme.cycling.tint
        default: return item.record == .none ? CyTheme.ink3 : CyTheme.recovery.tint
        }
    }
}

/// Opening a prescription: the strength logger screen or the ride workout detail, the way Plan opens them.
struct HomePrescriptionSheet: View {
    let workout: Workout
    var body: some View {
        if workout.kind == .strength { StrengthWorkoutScreen(workoutId: workout.id) } else { WorkoutDetail(workout: workout) }
    }
}

// MARK: - A1 Weekly Training Overview

struct HomeWeekOverviewView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    @State var weekOf: Date
    var perform: (HomeAction) -> Void
    var open: (HomeRoute) -> Void
    @State private var prescription: Workout? = nil
    private let cal = Calendar.current

    var body: some View {
        let o = store.homeWeekOverview(weekOf: weekOf, recorderActive: recorder.isActive)
        ScrollView {
            VStack(alignment: .leading, spacing: CyTheme.sp3) {
                weekPicker(o)
                counts(o)
                Text(o.explanation).font(CyType.secondary).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).cyCard()
                    .accessibilityIdentifier("weekOverviewExplanation")
                ForEach(Array(o.days.enumerated()), id: \.offset) { i, d in dayCard(d, index: i) }
                Text("Weekly trend charts arrive with Progress analytics (Checkpoint D).").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).padding(.horizontal, 4)
            }
            .padding(.horizontal, CyTheme.margin).padding(.vertical, CyTheme.sp3).padding(.bottom, CyTheme.dockClearance)
        }
        .background(CyTheme.canvas)
        .navigationTitle("Weekly overview").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $prescription) { w in HomePrescriptionSheet(workout: w) }
        .accessibilityIdentifier("homeWeekOverview")
    }

    private func weekPicker(_ o: HomeWeekOverview) -> some View {
        HStack {
            Button { weekOf = cal.date(byAdding: .day, value: -7, to: weekOf)! } label: { Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: CyTheme.minTap, height: CyTheme.minTap).contentShape(Rectangle()) }
                .buttonStyle(.plain).foregroundStyle(CyTheme.ink).accessibilityLabel("Previous week").accessibilityIdentifier("weekOverviewPrev")
            Spacer()
            VStack(spacing: 2) {
                Text(o.isCurrentWeek ? "This week" : "Week of \(o.rangeText)").font(CyType.section).foregroundStyle(CyTheme.ink)
                Text(o.isCurrentWeek ? o.rangeText : "").font(CyType.caption).foregroundStyle(CyTheme.ink3)
            }
            .accessibilityElement(children: .combine).accessibilityIdentifier("weekOverviewTitle")
            Spacer()
            let canNext = weekOf < cal.date(byAdding: .day, value: 7, to: Date())!
            Button { weekOf = cal.date(byAdding: .day, value: 7, to: weekOf)! } label: { Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: CyTheme.minTap, height: CyTheme.minTap).contentShape(Rectangle()) }
                .buttonStyle(.plain).foregroundStyle(canNext ? CyTheme.ink : CyTheme.ink3).disabled(!canNext).accessibilityLabel("Next week").accessibilityIdentifier("weekOverviewNext")
        }
    }

    private func counts(_ o: HomeWeekOverview) -> some View {
        let id = CyTheme.recovery
        let cells: [(String, Int)] = [("planned", o.planned), ("done", o.done), ("remaining", o.remaining), ("missed", o.missed), ("skipped", o.skipped), ("rest days", o.restDays)] + (o.daysBeforePlan > 0 ? [("before plan", o.daysBeforePlan)] : [])
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                CyProgressRing(fraction: o.fraction, size: 64, lineWidth: 8, tint: id.tint, track: id.soft) { CyRingLabel(fraction: o.fraction, caption: nil, tint: id.tint) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.planned == 0 ? "Nothing planned" : "\(o.done) of \(o.planned) sessions done").font(CyType.bodyStrong).foregroundStyle(CyTheme.ink)
                    if let c = o.countedFrom { Text("Counted from \(c.dayAndDate), the day the plan became effective.").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).fixedSize(horizontal: false, vertical: true) }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(cells.indices, id: \.self) { k in
                    let c = cells[k]
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(c.1)").font(CyType.numeralSmall).monospacedDigit().foregroundStyle(c.0 == "missed" && c.1 > 0 ? CyTheme.bad : CyTheme.ink)
                        Text(c.0).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3)
                    }
                    .accessibilityElement(children: .combine).accessibilityIdentifier("weekOverview-\(c.0.replacingOccurrences(of: " ", with: "-"))")
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cyCard(tinted: id.bg)
    }

    @ViewBuilder private func dayCard(_ d: HomeDayDetail, index: Int) -> some View {
        let f = DateFormatter(); let _ = f.dateFormat = "EEEE d MMM"
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(f.string(from: d.date)).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink)
                if cal.isDateInToday(d.date) { Text("Today").font(CyType.captionSmall).foregroundStyle(CyTheme.cta).padding(.horizontal, 6).padding(.vertical, 2).background(CyTheme.cta.opacity(0.12), in: Capsule()) }
                Spacer()
                Button { open(.day(d.date)) } label: { Text(d.kind == .training ? "Day" : d.kind == .beforePlan ? "Before plan" : d.kind == .rest ? "Rest" : "No plan").font(CyType.captionSmall.weight(.semibold)).foregroundStyle(CyTheme.ink2).cyMinTap() }
                    .buttonStyle(.plain).accessibilityLabel("Open day details").accessibilityIdentifier("weekOverviewDay-\(index)")
            }
            if d.items.isEmpty {
                Text(d.kind == .beforePlan ? "Before this plan started" : d.kind == .rest ? "Rest day" : "Nothing planned").font(CyType.secondary).foregroundStyle(CyTheme.ink3)
            } else {
                ForEach(Array(d.items.enumerated()), id: \.element.id) { j, item in
                    if j > 0 { CyDivider() }
                    HomeItemRow(item: item, elapsed: recorder.elapsedS, identifier: "weekOverviewItem-\(index)-\(j)", perform: perform, openRecord: openRecord, openPrescription: { prescription = $0 })
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).cyCard()
    }
    private func openRecord(_ r: HomeDayItem.Record) {
        switch r { case .ride(let id): open(.ride(id)); case .strength(let id): open(.log(id)); case .none: break }
    }
}

// MARK: - A4 Day detail (multiple sessions, rest, before plan)

struct HomeDayDetailView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    let date: Date
    var perform: (HomeAction) -> Void
    var open: (HomeRoute) -> Void
    @State private var prescription: Workout? = nil
    var body: some View {
        let d = store.homeDayDetail(date, recorderActive: recorder.isActive)
        let f = DateFormatter(); let _ = f.dateFormat = "EEEE d MMMM"
        ScrollView {
            VStack(alignment: .leading, spacing: CyTheme.sp3) {
                if !d.items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        if !d.explanation.isEmpty { Text(d.explanation).font(CyType.secondary).foregroundStyle(CyTheme.ink2) }
                        ForEach(Array(d.items.enumerated()), id: \.element.id) { j, item in
                            if j > 0 { CyDivider() }
                            HomeItemRow(item: item, elapsed: recorder.elapsedS, identifier: "dayItem-\(j)", perform: perform,
                                        openRecord: { r in switch r { case .ride(let id): open(.ride(id)); case .strength(let id): open(.log(id)); case .none: break } },
                                        openPrescription: { prescription = $0 })
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).cyCard()
                } else {
                    CyEmptyState(systemImage: d.kind == .beforePlan ? "calendar.badge.minus" : d.kind == .rest ? "moon.zzz.fill" : "calendar", title: d.kind == .beforePlan ? "Before this plan started" : d.kind == .rest ? "Rest day" : "Nothing planned", line: d.explanation)
                        .accessibilityIdentifier("dayEmpty")
                }
                if let a = d.availabilityLine { Text(a).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).padding(.horizontal, 4).accessibilityIdentifier("dayAvailability") }
                Text("Changing a session (move, skip, swap) happens on the session itself — opening this page never changes the plan.").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).padding(.horizontal, 4)
            }
            .padding(.horizontal, CyTheme.margin).padding(.vertical, CyTheme.sp3).padding(.bottom, CyTheme.dockClearance)
        }
        .background(CyTheme.canvas)
        .navigationTitle(f.string(from: date)).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $prescription) { w in HomePrescriptionSheet(workout: w) }
        .accessibilityIdentifier("homeDayDetail")
    }
}

// MARK: - A2 Cycling Summary

struct HomeCyclingSummaryView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    var perform: (HomeAction) -> Void
    var open: (HomeRoute) -> Void
    @State private var period: HomeCyclingSummary.Period = .fourWeeks
    @State private var prescription: Workout? = nil
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        let s = store.homeCyclingSummary(period)
        let id = CyTheme.cycling
        ScrollView {
            VStack(alignment: .leading, spacing: CyTheme.sp3) {
                Picker("Period", selection: $period) { ForEach(HomeCyclingSummary.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).accessibilityIdentifier("cyclingPeriod")
                if s.isEmpty {
                    CyEmptyState(systemImage: "bicycle", title: "No rides recorded", line: period == .all ? "Recorded rides appear here with their time, distance and measured power or heart rate. Start one from the Ride tab or the Training Hub." : "No ride recorded in this period. Change the period, or start one from the Ride tab or the Training Hub.")
                        .accessibilityIdentifier("cyclingEmpty")
                } else {
                    let tiles: [(String, String?, String?)] = [
                        ("Rides", "\(s.rides)", nil), ("Time", Fmt.duration(minutes: s.minutes), nil),
                        ("Distance", s.km.map { store.settings.units == .imperial ? String(format: "%.1f", $0 / 1.609344) : String(format: "%.1f", $0) }, store.settings.units == .imperial ? "mi" : "km"),
                        ("Avg power", s.avgPower.map { "\($0)" }, "W"), ("Avg heart rate", s.avgHR.map { "\($0)" }, "bpm"), ("Avg cadence", s.avgCadence.map { "\($0)" }, "rpm")]
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: CyTheme.sp3), GridItem(.flexible(), spacing: CyTheme.sp3)], spacing: CyTheme.sp3) {
                        ForEach(tiles.indices, id: \.self) { k in
                            let t = tiles[k]
                            CyMetricTile(title: t.0, sport: .cycling, value: t.1, unit: t.1 == nil ? nil : t.2, sub: t.1 == nil ? "not measured in this period" : (t.0 == "Avg power" || t.0 == "Avg heart rate" || t.0 == "Avg cadence" ? "rides that measured it" : "recorded"), tag: t.1 == nil ? .needsData : .measured)
                                .accessibilityIdentifier("cyclingTile-\(t.0.replacingOccurrences(of: " ", with: "-"))")
                        }
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                if let n = s.next {
                    VStack(alignment: .leading, spacing: 8) {
                        CyCaption(text: "Next planned ride", color: id.tint)
                        HomeItemRow(item: HomeDayItem(session: n, record: .none, title: n.title, subtitle: "\(n.workout.date.dayAndDate) · \(n.subtitle)", statusText: HomeSummariesModel.statusText(n.status)), elapsed: recorder.elapsedS, identifier: "cyclingNext", perform: perform, openRecord: { _ in }, openPrescription: { prescription = $0 })
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).cyCard(tinted: id.bg)
                } else {
                    Text("No ride planned from today — the Plan tab shows the week.").font(CyType.secondary).foregroundStyle(CyTheme.ink2).padding(14).frame(maxWidth: .infinity, alignment: .leading).cyCard()
                        .accessibilityIdentifier("cyclingNoNext")
                }
                if !s.recent.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        CyCaption(text: "Recent rides", color: CyTheme.ink3)
                        ForEach(Array(s.recent.enumerated()), id: \.element.id) { j, r in
                            if j > 0 { CyDivider() }
                            Button { open(.ride(r.id)) } label: {
                                HStack(spacing: 10) {
                                    CyIconBox(systemName: "bicycle", sport: .cycling)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(r.date.dayAndDate) · \(r.title)").font(CyType.bodyStrong).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                                        Text(r.line + (r.planned ? "" : " · unplanned")).font(CyType.secondary).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CyTheme.ink3).accessibilityHidden(true)
                                }
                                .frame(maxWidth: .infinity, minHeight: CyTheme.minTap, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityHint("Opens the ride details").accessibilityIdentifier("cyclingRide-\(j)")
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).cyCard()
                }
                Text("FTP development, power zones, training load and trend charts arrive with Progress analytics (Checkpoint D). Nothing here is estimated.").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).padding(.horizontal, 4)
            }
            .padding(.horizontal, CyTheme.margin).padding(.vertical, CyTheme.sp3).padding(.bottom, CyTheme.dockClearance)
        }
        .background(CyTheme.canvas)
        .navigationTitle("Cycling summary").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $prescription) { w in HomePrescriptionSheet(workout: w) }
        .accessibilityIdentifier("homeCyclingSummary")
    }
}

// MARK: - A3 Strength Summary

struct HomeStrengthSummaryView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    var perform: (HomeAction) -> Void
    var open: (HomeRoute) -> Void
    @State private var period: HomeStrengthSummary.Period = .fourWeeks
    @State private var prescription: Workout? = nil
    @State private var expanded: Set<UUID> = []

    var body: some View {
        let s = store.homeStrengthSummary(period)
        let id = CyTheme.strength
        ScrollView {
            VStack(alignment: .leading, spacing: CyTheme.sp3) {
                Picker("Period", selection: $period) { ForEach(HomeStrengthSummary.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).accessibilityIdentifier("strengthPeriod")
                if s.isEmpty {
                    CyEmptyState(systemImage: "dumbbell.fill", title: "No strength session logged", line: period == .all ? "Logged sessions appear here with the exercises, sets, reps and weights you recorded. Start the next planned workout from the Training Hub." : "No session logged in this period. Change the period, or start the next planned workout from the Training Hub.")
                        .accessibilityIdentifier("strengthEmpty")
                } else {
                    HStack(spacing: CyTheme.sp3) {
                        CyMetricTile(title: "Sessions", sport: .strength, value: "\(s.sessions)", sub: "logged", tag: .logged).accessibilityIdentifier("strengthTile-Sessions")
                        CyMetricTile(title: "Time", sport: .strength, value: s.minutes > 0 ? Fmt.duration(minutes: s.minutes) : nil, sub: s.minutes > 0 ? "recorded duration" : "duration not recorded", tag: s.minutes > 0 ? .measured : .needsData).accessibilityIdentifier("strengthTile-Time")
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                if let n = s.next {
                    VStack(alignment: .leading, spacing: 8) {
                        CyCaption(text: "Next planned workout", color: id.tint)
                        HomeItemRow(item: HomeDayItem(session: n, record: .none, title: n.title, subtitle: "\(n.workout.date.dayAndDate) · \(n.subtitle)", statusText: HomeSummariesModel.statusText(n.status)), elapsed: recorder.elapsedS, identifier: "strengthNext", perform: perform, openRecord: { _ in }, openPrescription: { prescription = $0 })
                        if !s.nextEntries.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(Array(s.nextEntries.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(CyType.secondary).foregroundStyle(line.first.map { "ABCDEFG".contains($0) && line.dropFirst().first?.isNumber == true } == true ? id.tint : CyTheme.ink2)
                                }
                            }
                            .accessibilityElement(children: .combine).accessibilityIdentifier("strengthNextEntries")
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).cyCard(tinted: id.bg)
                } else {
                    Text("No strength workout planned from today — the Plan tab shows the week.").font(CyType.secondary).foregroundStyle(CyTheme.ink2).padding(14).frame(maxWidth: .infinity, alignment: .leading).cyCard()
                        .accessibilityIdentifier("strengthNoNext")
                }
                if !s.recent.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        CyCaption(text: "Recent workouts", color: CyTheme.ink3)
                        ForEach(Array(s.recent.enumerated()), id: \.element.id) { j, r in
                            if j > 0 { CyDivider() }
                            VStack(alignment: .leading, spacing: 6) {
                                Button { open(.log(r.id)) } label: {
                                    HStack(spacing: 10) {
                                        CyIconBox(systemName: "dumbbell.fill", sport: .strength)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(r.date.dayAndDate) · \(r.title)").font(CyType.bodyStrong).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                                            Text(r.line + (r.planned ? "" : " · unplanned")).font(CyType.secondary).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                                        }
                                        Spacer(minLength: 4)
                                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CyTheme.ink3).accessibilityHidden(true)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: CyTheme.minTap, alignment: .leading).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityHint("Opens the workout log").accessibilityIdentifier("strengthLog-\(j)")
                                if !r.exercises.isEmpty {
                                    Button { if expanded.contains(r.id) { expanded.remove(r.id) } else { expanded.insert(r.id) } } label: {
                                        HStack(spacing: 4) { Text(expanded.contains(r.id) ? "Hide exercises" : "\(r.exercises.count) exercise\(r.exercises.count == 1 ? "" : "s")"); Image(systemName: expanded.contains(r.id) ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold)) }
                                            .font(CyType.captionSmall.weight(.semibold)).foregroundStyle(id.tint).cyMinTap()
                                    }
                                    .buttonStyle(.plain).accessibilityIdentifier("strengthLogExpand-\(j)")
                                    if expanded.contains(r.id) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            ForEach(Array(r.exercises.enumerated()), id: \.offset) { _, line in Text(line).font(CyType.secondary).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true) }
                                        }
                                        .padding(.leading, 46).accessibilityIdentifier("strengthLogExercises-\(j)")
                                    }
                                }
                            }
                        }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).cyCard()
                }
                Text("Personal records, estimated 1RM trends and muscle-volume analysis arrive with Progress analytics (Checkpoint D). Only logged sets are shown.").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).padding(.horizontal, 4)
            }
            .padding(.horizontal, CyTheme.margin).padding(.vertical, CyTheme.sp3).padding(.bottom, CyTheme.dockClearance)
        }
        .background(CyTheme.canvas)
        .navigationTitle("Strength summary").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $prescription) { w in HomePrescriptionSheet(workout: w) }
        .accessibilityIdentifier("homeStrengthSummary")
    }
}

// MARK: - A6 Getting started (dynamic checklist)

struct HomeSetupChecklist: View {
    let items: [HomeSetupItem]
    var openPlan: () -> Void
    var openConnections: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { CyCaption(text: "Getting started", color: CyTheme.ink3); Spacer(); Text("\(items.filter(\.done).count) of \(items.count)").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3) }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                if i > 0 { CyDivider() }
                Button { if it.cta == "Open Connections" { openConnections() } else { openPlan() } } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: it.done ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(it.done ? CyTheme.recovery.tint : CyTheme.ink3).frame(width: 28).padding(.top, 2).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(it.title).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                                if !it.required { Text("optional").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).padding(.horizontal, 6).padding(.vertical, 2).background(CyTheme.line2, in: Capsule()) }
                            }
                            Text(it.detail).font(CyType.secondary).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                            if let c = it.cta { Text(c + " ›").font(CyType.captionSmall.weight(.semibold)).foregroundStyle(CyTheme.cta) }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: CyTheme.minTap, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(it.title), \(it.done ? "done" : "to do")\(it.required ? "" : ", optional"). \(it.detail)")
                .accessibilityIdentifier(it.id == .planApproved ? "homeStartPlan" : it.id == .firstSession ? "homeStartFirst" : it.id == .heartRate ? "homeStartHR" : "homeStartHealth")
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).cyCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeFirstWeek")
    }
}
