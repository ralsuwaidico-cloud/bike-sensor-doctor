import Foundation

// MARK: - Checkpoint C correction pass (owner 6 Nov): the Home cards' own destinations.
// Weekly Training Overview, Cycling Summary, Strength Summary, Day detail and the Getting-started checklist are read
// from existing records (plan, ledger, rides, strength logs, availability, device states). Nothing is estimated: a
// value that was not measured is nil and the page says so. Foundation only, so the Linux harness tests the numbers.

/// One planned or recorded item of a day, with the same status/action the Training Hub uses.
struct HomeDayItem: Equatable, Identifiable {
    enum Record: Equatable { case none, ride(UUID), strength(UUID) }
    var session: HomeSession?          // a planned session (nil for an unplanned record)
    var record: Record                 // the recorded ride / log behind it, if any
    var title: String
    var subtitle: String               // "40 min · Moderate" / "1 h 02 · 28 km"
    var statusText: String             // "Planned" / "Done" / "Missed" / "Skipped" / "In progress" / "Recorded"
    var id: String { session.map { $0.id.uuidString } ?? { if case .ride(let r) = record { return "ride-\(r)" }; if case .strength(let s) = record { return "log-\(s)" }; return UUID().uuidString }() }
    var isRide: Bool { session?.isRide ?? { if case .ride = record { return true }; return false }() }
}

struct HomeDayDetail: Equatable {
    enum Kind: Equatable { case beforePlan, rest, training, noPlan }
    var date: Date
    var kind: Kind
    var items: [HomeDayItem]
    var explanation: String            // the one line that says why the day looks the way it does
    var availabilityLine: String?      // "Your week: rest day" / "Your week: strength · 30 min"
}

struct HomeWeekOverview: Equatable {
    var monday: Date
    var rangeText: String              // "2 – 8 Nov"
    var planned: Int, done: Int, remaining: Int, missed: Int, skipped: Int, restDays: Int, daysBeforePlan: Int
    var fraction: Double { CyDesign.ringFraction(done: done, planned: planned) }
    var days: [HomeDayDetail]
    var countedFrom: Date?             // the plan's effective start when it falls inside this week
    var isCurrentWeek: Bool
    var explanation: String            // how the percentage was calculated
}

struct HomeCyclingSummary: Equatable {
    enum Period: String, CaseIterable, Equatable { case week = "This week", fourWeeks = "4 weeks", all = "All" }
    struct RideRow: Equatable, Identifiable { var id: UUID; var date: Date; var title: String; var line: String; var planned: Bool }
    var period: Period
    var rides: Int
    var minutes: Int
    var km: Double?                    // nil when no ride carried a distance
    var avgPower: Int?                 // duration-weighted over rides that measured power
    var avgHR: Int?
    var avgCadence: Int?
    var recent: [RideRow]              // newest first, at most 10 in the period
    var next: HomeSession?             // the next planned ride (today or later)
    var isEmpty: Bool { rides == 0 }
}

struct HomeStrengthSummary: Equatable {
    enum Period: String, CaseIterable, Equatable { case week = "This week", fourWeeks = "4 weeks", all = "All" }
    struct SessionRow: Equatable, Identifiable {
        var id: UUID; var date: Date; var title: String; var line: String
        var exercises: [String]        // "Back squat 3×6 @ 80 kg", "Bench press 2×8 @ 40 kg", "Plank 3×30 s"
        var supersets: Int             // groups present in the log
        var planned: Bool
    }
    var period: Period
    var sessions: Int
    var minutes: Int                   // recorded minutes only (sessions whose duration was recorded)
    var recent: [SessionRow]
    var next: HomeSession?
    var nextEntries: [String]          // the prescription lines with group letters, e.g. "A1 Back squat 3×6"
    var isEmpty: Bool { sessions == 0 }
}

struct HomeSetupItem: Equatable, Identifiable {
    enum Step: String { case planApproved, firstSession, heartRate, health }
    var id: Step
    var title: String
    var detail: String
    var done: Bool
    var required: Bool
    var cta: String?                   // "Open Plan" / "Open Connections" / nil when done
}

enum HomeSummariesModel {
    static func statusText(_ s: HomeStatus) -> String {
        switch s {
        case .planned: return "Planned"
        case .inProgress: return "In progress"
        case .done: return "Done"
        case .marked: return "Marked done"
        case .imported: return "Imported"
        case .missed: return "Missed"
        case .skipped: return "Skipped"
        }
    }
    static func rideLine(_ r: RideRecord, units: AppSettings.Units) -> String {
        var parts = [Fmt.duration(minutes: max(1, r.durationS / 60))]
        if r.distanceM > 0 { parts.append(units == .imperial ? String(format: "%.1f mi", Double(r.distanceM) / 1609.344) : String(format: "%.1f km", Double(r.distanceM) / 1000)) }
        if let p = r.avgPower { parts.append("\(p) W") }
        if let h = r.avgHR { parts.append("\(h) bpm") }
        return parts.joined(separator: " · ")
    }
    static func exerciseLine(_ e: ExerciseEntry, units: AppSettings.Units) -> String {
        let done = e.sets.filter(\.done)
        guard !done.isEmpty else { return "\(e.name) · no set logged" }
        let reps = Set(done.map(\.reps))
        let repText = reps.count == 1 ? "\(done.count)×\(reps.first!)" : "\(done.count) sets · " + done.map { "\($0.reps)" }.joined(separator: "/")
        let weights = done.compactMap(\.weightKg)
        var s = "\(e.name) \(repText)"
        if !weights.isEmpty {
            let lo = weights.min()!, hi = weights.max()!
            s += " @ " + (lo == hi ? WeightFmt.text(hi, units) : "\(WeightFmt.number(lo, units))–\(WeightFmt.text(hi, units))")
        } else if done.contains(where: \.bodyweight) { s += " · bodyweight" }
        if let g = e.superset { s = "\(g) · " + s }
        return s
    }
    static func prescriptionLine(_ e: ExerciseEntry, index: Int, entries: [ExerciseEntry]) -> String {
        let sets = e.sets.count, reps = Set(e.sets.map(\.reps))
        let repText = reps.count == 1 ? "\(sets)×\(reps.first ?? 0)" : "\(sets) sets"
        if let g = e.superset {
            let n = entries.prefix(index + 1).filter { $0.superset == g }.count
            return "\(g)\(n) \(e.name) \(repText)"
        }
        return "\(e.name) \(repText)"
    }
}

extension Store {
    /// The same input `homeToday` uses, so every page shows the hub's statuses and actions.
    func homeInput(now: Date = Date(), recorderActive: Bool = false) -> HomeToday.Input {
        .init(plan: plan, ledger: ledger, readiness: profile.readiness, supervisedOnly: profile.healthScreen?.supervisedOnly ?? false,
              mode: profile.trainingMode, recorderActive: recorderActive, activeSession: activeSession,
              hasHistory: !rides.filter { !$0.demo }.isEmpty || !strength.isEmpty, routine: { [weak self] w in self?.routine(for: w) }, now: now)
    }
    func homeSession(for w: Workout, now: Date = Date(), recorderActive: Bool = false) -> HomeSession {
        HomeToday.session(w, homeInput(now: now, recorderActive: recorderActive), firstOpenRide: nil)
    }

    // MARK: day detail

    func homeDayDetail(_ date: Date, now: Date = Date(), recorderActive: Bool = false, calendar cal: Calendar = .current) -> HomeDayDetail {
        let day = cal.startOfDay(for: date)
        let input = homeInput(now: now, recorderActive: recorderActive)
        let sessions = plan.filter { cal.isDate($0.date, inSameDayAs: day) && HomeToday.isTraining($0) }.sorted { ($0.date, $0.sequence) < ($1.date, $1.sequence) }
        var items: [HomeDayItem] = []
        var usedRides = Set<UUID>(), usedLogs = Set<UUID>()
        for w in sessions {
            let s = HomeToday.session(w, input, firstOpenRide: nil)
            var rec: HomeDayItem.Record = .none
            if w.kind.isRide, let r = ledger.ride(for: w) { rec = .ride(r.id); usedRides.insert(r.id) }
            else if let l = ledger.log(for: w) { rec = .strength(l.id); usedLogs.insert(l.id) }
            // owner 6 Nov (1): a recorded session shows what was RECORDED, with the prescription named as such
            var sub = s.subtitle
            switch rec {
            case .ride(let id): if let r = rides.first(where: { $0.id == id }) { sub = "Recorded " + HomeSummariesModel.rideLine(r, units: settings.units) + " · planned \(Fmt.duration(minutes: w.minutes))" }
            case .strength(let id):
                if let l = strength.first(where: { $0.id == id }) {
                    let n = (l.exercises ?? []).filter { $0.sets.contains(where: \.done) }.count
                    sub = "Recorded " + (l.minutes > 0 ? Fmt.duration(minutes: l.minutes) : "duration not recorded") + " · \(n) exercise\(n == 1 ? "" : "s") · planned \(Fmt.duration(minutes: w.minutes))"
                }
            case .none: if s.status == .marked || s.status == .imported { sub = HomeSummariesModel.statusText(s.status) + " · no recording on the phone · planned \(Fmt.duration(minutes: w.minutes))" } else { sub = "Planned " + s.subtitle }
            }
            items.append(HomeDayItem(session: s, record: rec, title: s.title, subtitle: sub, statusText: HomeSummariesModel.statusText(s.status)))
        }
        // unplanned records of the day (a free ride, a logged lift)
        for r in rides.filter({ !$0.demo && cal.isDate($0.start, inSameDayAs: day) && !usedRides.contains($0.id) }).sorted(by: { $0.start < $1.start }) {
            items.append(HomeDayItem(session: nil, record: .ride(r.id), title: "Ride", subtitle: HomeSummariesModel.rideLine(r, units: settings.units), statusText: "Recorded"))
        }
        for l in strength.filter({ cal.isDate($0.date, inSameDayAs: day) && !usedLogs.contains($0.id) }).sorted(by: { $0.date < $1.date }) {
            items.append(HomeDayItem(session: nil, record: .strength(l.id), title: l.title, subtitle: l.minutes > 0 ? Fmt.duration(minutes: l.minutes) : "duration not recorded", statusText: "Recorded"))
        }
        let idx = (cal.component(.weekday, from: day) + 5) % 7
        let avail = effectiveAvailability.days[idx]
        // owner 6 Nov (2): "Your week" is today's setup — it describes today and later days only, never the past
        let isPast = day < cal.startOfDay(for: now)
        let availLine: String? = isPast ? nil : avail.activity == .rest ? "Your week: rest day" : "Your week: " + avail.assignments.map { "\($0.sport == .strength ? "strength" : $0.sport == .cycling ? "ride" : "session") · \(Fmt.duration(minutes: $0.minutes))" }.joined(separator: " + ")
        let kind: HomeDayDetail.Kind
        let explanation: String
        if items.isEmpty, CyPlanStart.isBeforePlan(day, effectiveStart: planEffectiveStart, hasRecord: hasRecord(on: day, calendar: cal), calendar: cal) {
            kind = .beforePlan
            let f = DateFormatter(); f.dateFormat = "EEEE d MMM"
            explanation = "Before this plan started. Your plan became effective on \(planEffectiveStart.map { f.string(from: $0) } ?? "its approval day"); earlier days are not counted as rest, missed or done."
        } else if items.isEmpty, plan.isEmpty {
            kind = .noPlan; explanation = "No plan yet. Approve a plan to see sessions here."
        } else if items.isEmpty {
            kind = .rest
            explanation = isPast ? "No session was planned for this day." : avail.activity == .rest ? "Rest day — set as a rest day in Your week. Recovery is part of the plan; nothing is expected today." : "Nothing planned for this day. The coach left it free this week."
        } else {
            kind = .training
            let open = items.filter { $0.session?.status == .planned }.count
            explanation = items.count == 1 ? "" : "\(items.count) sessions this day" + (open > 0 ? " · \(open) still to do" : "")
        }
        return HomeDayDetail(date: day, kind: kind, items: items, explanation: explanation, availabilityLine: availLine)
    }

    // MARK: weekly overview

    func homeWeekOverview(weekOf date: Date = Date(), now: Date = Date(), recorderActive: Bool = false, calendar cal: Calendar = .current) -> HomeWeekOverview {
        let monday = TrainingLedger.monday(of: date, calendar: cal)
        let today = cal.startOfDay(for: now)
        let days = (0..<7).map { homeDayDetail(cal.date(byAdding: .day, value: $0, to: monday)!, now: now, recorderActive: recorderActive, calendar: cal) }
        let sessions = days.flatMap(\.items).compactMap(\.session)
        let active = sessions.filter { $0.status != .skipped }
        let planned = active.count
        let done = active.filter { [.done, .marked, .imported].contains($0.status) }.count
        let missed = active.filter { $0.status == .missed }.count
        let skipped = sessions.count - planned
        let remaining = max(0, planned - done - missed)
        let start = planEffectiveStart.map { cal.startOfDay(for: $0) }
        let countedFrom = start.flatMap { $0 > monday && $0 <= cal.date(byAdding: .day, value: 6, to: monday)! ? $0 : nil }
        let pct = CyDesign.percentText(CyDesign.ringFraction(done: done, planned: planned))
        var expl = planned == 0 ? "No sessions are planned in this week, so there is no percentage." : "\(pct) = \(done) done ÷ \(planned) planned. Planned counts every session of the week that was not skipped; done counts recorded, imported and marked-done sessions."
        if countedFrom != nil { expl += " Days before the plan became effective are not counted." }
        if missed > 0 { expl += " Missed sessions stay in the denominator until they are moved or skipped." }
        if skipped > 0 { expl += " Skipped sessions (\(skipped)) are left out of both numbers." }
        return HomeWeekOverview(monday: monday, rangeText: HomeDashboardModel.weekRange(monday: monday, calendar: cal), planned: planned, done: done, remaining: remaining, missed: missed, skipped: skipped,
                                restDays: days.filter { $0.kind == .rest }.count, daysBeforePlan: days.filter { $0.kind == .beforePlan }.count, days: days, countedFrom: countedFrom,
                                isCurrentWeek: monday == TrainingLedger.monday(of: today, calendar: cal), explanation: expl)
    }

    // MARK: cycling summary

    func homeCyclingSummary(_ period: HomeCyclingSummary.Period = .week, now: Date = Date(), calendar cal: Calendar = .current) -> HomeCyclingSummary {
        let monday = TrainingLedger.monday(of: now, calendar: cal)
        let from: Date? = period == .week ? monday : period == .fourWeeks ? cal.date(byAdding: .day, value: -21, to: monday) : nil
        let limit = now.addingTimeInterval(86400)
        let rs = rides.filter { r in !r.demo && (from == nil || r.start >= from!) && r.start <= limit }.sorted { $0.start > $1.start }
        let minutes = rs.reduce(0) { $0 + $1.durationS / 60 }
        let km: Double? = rs.contains { $0.distanceM > 0 } ? Double(rs.reduce(0) { $0 + $1.distanceM }) / 1000 : nil
        func weighted(_ f: (RideRecord) -> Int?) -> Int? {
            let withV = rs.compactMap { r in f(r).map { (Double($0), Double(r.durationS)) } }
            guard !withV.isEmpty else { return nil }
            let w = withV.reduce(0.0) { $0 + $1.1 }
            return w > 0 ? Int((withV.reduce(0.0) { $0 + $1.0 * $1.1 } / w).rounded()) : nil
        }
        let input = homeInput(now: now)
        let recent = rs.prefix(10).map { r -> HomeCyclingSummary.RideRow in
            let w = plan.first { ledger.ride(for: $0)?.id == r.id }
            return .init(id: r.id, date: r.start, title: w.map { HomeText.title($0, routine: nil) } ?? "Ride", line: HomeSummariesModel.rideLine(r, units: settings.units), planned: w != nil)
        }
        let today = cal.startOfDay(for: now)
        let nextW = plan.filter { w in w.kind.isRide && !w.skipped && cal.startOfDay(for: w.date) >= today && !ledger.status(w).isCompleted }
            .sorted { ($0.date, $0.sequence) < ($1.date, $1.sequence) }.first
        let next: HomeSession? = nextW.map { HomeToday.session($0, input, firstOpenRide: nil) }
        return HomeCyclingSummary(period: period, rides: rs.count, minutes: minutes, km: km, avgPower: weighted(\.avgPower), avgHR: weighted(\.avgHR), avgCadence: weighted(\.avgCadence), recent: Array(recent), next: next)
    }

    // MARK: strength summary

    func homeStrengthSummary(_ period: HomeStrengthSummary.Period = .week, now: Date = Date(), calendar cal: Calendar = .current) -> HomeStrengthSummary {
        let monday = TrainingLedger.monday(of: now, calendar: cal)
        let from: Date? = period == .week ? monday : period == .fourWeeks ? cal.date(byAdding: .day, value: -21, to: monday) : nil
        let limit = now.addingTimeInterval(86400)
        let ss = strength.filter { s in (from == nil || s.date >= from!) && s.date <= limit }.sorted { $0.date > $1.date }
        let recent = ss.prefix(10).map { s -> HomeStrengthSummary.SessionRow in
            let all: [ExerciseEntry] = s.exercises ?? []
            let ex = all.filter { e in e.sets.contains { $0.done } }
            let groups = Set(ex.compactMap(\.superset)).count
            var line = s.minutes > 0 ? Fmt.duration(minutes: s.minutes) : "duration not recorded"
            line += " · \(ex.count) exercise\(ex.count == 1 ? "" : "s")"
            if groups > 0 { line += " · \(groups) superset\(groups == 1 ? "" : "s")" }
            return .init(id: s.id, date: s.date, title: s.title, line: line, exercises: ex.map { HomeSummariesModel.exerciseLine($0, units: settings.units) }, supersets: groups, planned: s.workoutId != nil)
        }
        let input = homeInput(now: now)
        let today = cal.startOfDay(for: now)
        let nextW = plan.filter { w in w.kind == .strength && !w.skipped && cal.startOfDay(for: w.date) >= today && !ledger.status(w).isCompleted }
            .sorted { ($0.date, $0.sequence) < ($1.date, $1.sequence) }.first
        let next: HomeSession? = nextW.map { HomeToday.session($0, input, firstOpenRide: nil) }
        let entries = nextW.map { plannedEntries(for: $0) } ?? []
        return HomeStrengthSummary(period: period, sessions: ss.count, minutes: ss.reduce(0) { $0 + max(0, $1.minutes) }, recent: Array(recent), next: next,
                                   nextEntries: entries.enumerated().map { HomeSummariesModel.prescriptionLine($0.element, index: $0.offset, entries: entries) })
    }

    // MARK: getting started (dynamic; hidden once the required steps are done)

    func homeSetupItems(hrConnected: Bool, now: Date = Date(), calendar cal: Calendar = .current) -> [HomeSetupItem] {
        guard plan.contains(where: { HomeToday.isTraining($0) }) else { return [] }
        let recorded = !rides.filter { !$0.demo }.isEmpty || !strength.isEmpty
        let monday = TrainingLedger.monday(of: now, calendar: cal)
        let start = planEffectiveStart.map { cal.startOfDay(for: $0) } ?? monday
        let thisWeek = plan.filter { HomeToday.isTraining($0) && !$0.skipped && $0.date >= max(start, monday) && $0.date < cal.date(byAdding: .day, value: 7, to: monday)! }.count
        let nextWeek = plan.filter { HomeToday.isTraining($0) && !$0.skipped && $0.date >= cal.date(byAdding: .day, value: 7, to: monday)! && $0.date < cal.date(byAdding: .day, value: 14, to: monday)! }.count
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        var planLine = "\(thisWeek) session\(thisWeek == 1 ? "" : "s") this week"
        if start > monday { planLine = "Starts \(f.string(from: start)) · " + planLine }
        if nextWeek > 0 { planLine += " · \(nextWeek) next week" }
        let first = plan.filter { HomeToday.isTraining($0) && !$0.skipped && $0.date >= cal.startOfDay(for: now) }.sorted { ($0.date, $0.sequence) < ($1.date, $1.sequence) }.first
        let healthOn = settings.healthReads.anyEnabled
        var items: [HomeSetupItem] = [
            HomeSetupItem(id: .planApproved, title: "Plan approved", detail: planLine, done: true, required: true, cta: "Open Plan"),
            HomeSetupItem(id: .firstSession, title: first?.kind == .strength ? "Log your first session" : "Record your first ride",
                          detail: recorded ? "Done — your first session is recorded." : (first?.kind == .strength ? "The weights you log set your working loads." : "Rides use effort\(hrConnected ? " and heart-rate" : "") targets until an FTP is known."),
                          done: recorded, required: true, cta: recorded ? nil : "Open Plan"),
            HomeSetupItem(id: .heartRate, title: "Heart rate (optional)", detail: hrConnected ? "Connected — rides show heart-rate targets." : "Apple Watch or a strap adds heart-rate targets on rides.", done: hrConnected, required: false, cta: hrConnected ? nil : "Open Connections"),
            HomeSetupItem(id: .health, title: "Apple Health reads (optional)", detail: healthOn ? "On — the Recovery card shows your latest readings." : "Sleep, resting HR and HRV for the Recovery card.", done: healthOn, required: false, cta: healthOn ? nil : "Open Connections"),
        ]
        // once every required step is done the checklist leaves Home (the optional ones stay in Profile › Connections)
        if items.filter(\.required).allSatisfy(\.done) { items = [] }
        return items
    }
}
