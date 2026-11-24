import Foundation

// Daily Training Overview — PROPOSED revision of the Day page (owner, 24 Nov 2026, 22:42; not approved).
// The page's main feature is the comparison of each session with the most relevant earlier RECORDED session:
//   current workout (prescription, and the recording if completed) · previous comparable workout · metric-by-metric
//   comparison · a short note built from those figures · the day's health readings.
// Everything here READS records. Nothing is written, nothing is estimated, and no figure is shown that is not stored.
//
// WHAT IS AVAILABLE TODAY (audit of the models, 24 Nov 2026):
//   Strength   per exercise: sets, reps, load per set, bodyweight / unilateral marks → top load and volume (load × reps).
//   Cycling    duration, distance, average / max heart rate, average / normalized power, average cadence, seconds in
//              each of seven zones — each only when the recording measured it.
//   Health     sleep, resting heart rate and HRV: one reading per day, read from Apple Health, with source and time.
//              Soreness: only what the athlete answered in a session review ("pain: soreness") — not a daily reading.
//   NOT STORED ANYWHERE: steps, water, daily energy; and no recording at all for running, swimming or any other
//              roster activity. Those are shown as truthful empty states, never as zero.
//
// WHEN A CHANGE IS CALLED FAVOURABLE (green) OR UNFAVOURABLE (red). A bigger number is not automatically better:
//   Strength exercise   volume up with top load not lower → favourable; volume down with top load not higher →
//                       unfavourable; top load and volume moving in opposite directions → not comparable (grey).
//                       Without load (bodyweight): total reps up / down.
//   Top load            higher favourable, lower unfavourable.       Reps: judged only at the same top load.
//   Sets, duration, distance, cadence, time in zones: shown, never judged — more is not better by itself.
//   Cycling power       higher average power with heart rate not higher → favourable; lower power with heart rate not
//                       lower → unfavourable; otherwise, or when either is not measured, not comparable.
//   Cycling heart rate  lower at the same or higher power → favourable; higher at the same or lower power →
//                       unfavourable; without power in both rides, not comparable.
//   "Same" means within a small tolerance: 2 W, 2 bpm, 0.5 kg of volume.
// These are display rules for this page. They are not training-load, fitness or physiological conclusions.

enum DayVerdict: String, Equatable { case better, worse, same, notComparable }

struct DayMetric: Equatable, Identifiable {
    var id: String
    var name: String
    var planned: String? = nil
    var previous: String? = nil
    var current: String? = nil
    var change: String
    var verdict: DayVerdict
    var spoken: String {
        "\(name). " + (planned.map { "Planned \($0). " } ?? "") + "Previous \(previous ?? "not recorded"). Now \(current ?? "not recorded"). \(change)."
    }
}

struct DayExercise: Equatable, Identifiable {
    var id: String
    var name: String
    var planned: String?
    var previous: String?
    var current: String?
    var change: String
    var verdict: DayVerdict
    var metrics: [DayMetric]
}

struct DayPrevious: Equatable {
    var date: Date
    var title: String
    var line: String
    var basis: String
    var record: HomeDayItem.Record
}

struct DayHistoryPoint: Equatable, Identifiable {
    var id: Int
    var date: Date
    var value: Double
    var text: String
    var record: HomeDayItem.Record
    var isCurrent: Bool
}
struct DayHistory: Equatable {
    var title: String
    var points: [DayHistoryPoint]
    var top: Double { max(1, (points.map(\.value).max() ?? 1) * 1.15) }
}

struct DaySessionReview: Equatable, Identifiable {
    enum Sport: Equatable { case cycling, strength }
    var id: String
    var item: HomeDayItem
    var sport: Sport
    /// 1 — the prescription, where the session was planned.
    var plannedLine: String?
    /// 1 — what was recorded, where the session is completed.
    var actualLine: String?
    /// 2 — the most relevant earlier recorded session; nil with `previousEmpty` saying why.
    var previous: DayPrevious?
    var previousEmpty: String
    /// 3 — session-level figures, then (strength) exercise by exercise.
    var metrics: [DayMetric]
    var exercises: [DayExercise]
    /// 4 — fixed sentences built from the figures above.
    var analysis: String
    var history: DayHistory?
    var completed: Bool { actualLine != nil }
}

struct DayHealthRow: Equatable, Identifiable {
    var id: String
    var name: String
    var icon: String
    var value: String?
    var detail: String
}

struct DayOverview: Equatable {
    var detail: HomeDayDetail
    var sessions: [DaySessionReview]
    /// True for a day today or later with nothing scheduled that is NOT a rest day of the recurring week.
    var freeDay: Bool
    /// One line where this day differs from the recurring week; nil when they agree or the day is past.
    var weekNote: String?
    var health: [DayHealthRow]
    /// Measures Cyclift does not collect at all.
    var uncollected: [String]
    /// Roster activities that cannot be recorded, so no comparison can exist for them.
    var unsupported: [String]
    var hasHealth: Bool { health.contains { $0.value != nil } }
}

enum DayReviewModel {
    static let wTol = 2, hrTol = 2
    static let volTol = 0.5

    static func dateText(_ d: Date, calendar cal: Calendar = .current) -> String {
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "EEE d MMM"; return f.string(from: d)
    }
    static func signed(_ v: Int, _ unit: String) -> String { v == 0 ? "No change" : (v > 0 ? "+" : "−") + "\(abs(v)) \(unit)" }
    static func signedKg(_ v: Double, _ u: AppSettings.Units) -> String { abs(v) < 0.05 ? "No change" : (v > 0 ? "+" : "−") + WeightFmt.text(abs(v), u) }
    static func distance(_ m: Int, _ u: AppSettings.Units) -> String { u == .imperial ? String(format: "%.1f mi", Double(m) / 1609.344) : String(format: "%.1f km", Double(m) / 1000) }
    static func list(_ n: [String]) -> String { n.count <= 1 ? (n.first ?? "") : n.dropLast().joined(separator: ", ") + " and " + n.last! }

    // MARK: strength

    static func topLoad(_ e: ExerciseEntry) -> Double? { e.doneSets.filter { !$0.bodyweight }.compactMap(\.weightKg).max() }
    static func plannedTop(_ e: ExerciseEntry) -> Double? { e.sets.filter { !$0.bodyweight }.compactMap(\.weightKg).max() }
    static func plannedText(_ e: ExerciseEntry, _ u: AppSettings.Units) -> String {
        guard let first = e.sets.first else { return "no sets" }
        let reps = Set(e.sets.map(\.reps)), lo = reps.min() ?? 0, hi = reps.max() ?? 0
        let load = first.seconds != nil ? "hold" : plannedTop(e).map { WeightFmt.text($0, u) } ?? (first.bodyweight ? "bodyweight" : "load not set")
        return "\(e.sets.count) × \(lo == hi ? "\(lo)" : "\(lo)–\(hi)") · \(load)"
    }

    /// One exercise, now against the same exercise in the previous session. `current` nil = not done yet.
    static func exercise(planned: ExerciseEntry?, current: ExerciseEntry?, previous: ExerciseEntry?, units u: AppSettings.Units) -> DayExercise {
        let name = current?.name ?? planned?.name ?? previous?.name ?? ""
        let id = current?.exerciseId ?? planned?.exerciseId ?? previous?.exerciseId ?? name
        let pText = planned.map { plannedText($0, u) }
        func text(_ e: ExerciseEntry?) -> String? { e.flatMap { $0.doneSets.isEmpty ? nil : $0.summary(units: u) } }
        var metrics: [DayMetric] = []
        let cTop = current.flatMap(topLoad), pTop = previous.flatMap(topLoad)
        let cVol = current?.tonnageKg, pVol = previous?.tonnageKg
        let cReps = current.map(\.totalReps), pReps = previous.map(\.totalReps)
        let cSets = current.map { $0.doneSets.count }, pSets = previous.map { $0.doneSets.count }
        func verdict(_ d: Double?, tol: Double) -> DayVerdict { guard let d else { return .notComparable }; return abs(d) <= tol ? .same : d > 0 ? .better : .worse }

        let done = current.map { !$0.doneSets.isEmpty } ?? false
        let had = previous.map { !$0.doneSets.isEmpty } ?? false
        func missing() -> String { !done ? "Not done yet" : "No previous record" }

        // sets — shown, never judged
        metrics.append(DayMetric(id: "\(id)-sets", name: "Sets", planned: planned.map { "\($0.sets.count)" }, previous: had ? pSets.map(String.init) : nil, current: done ? cSets.map(String.init) : nil,
                                 change: done && had ? signed((cSets ?? 0) - (pSets ?? 0), "set" + (abs((cSets ?? 0) - (pSets ?? 0)) == 1 ? "" : "s")) : missing(),
                                 verdict: done && had && cSets == pSets ? .same : .notComparable))
        // reps — judged only at the same top load
        let sameLoad = cTop != nil && pTop != nil && abs((cTop ?? 0) - (pTop ?? 0)) < 0.05 || (cTop == nil && pTop == nil)
        metrics.append(DayMetric(id: "\(id)-reps", name: "Reps", planned: planned.map { "\($0.sets.reduce(0) { $0 + $1.reps })" }, previous: had ? pReps.map(String.init) : nil, current: done ? cReps.map(String.init) : nil,
                                 change: done && had ? signed((cReps ?? 0) - (pReps ?? 0), "reps") : missing(),
                                 verdict: done && had ? (sameLoad ? verdict(Double((cReps ?? 0) - (pReps ?? 0)), tol: 0) : .notComparable) : .notComparable))
        // top load
        let loadDelta: Double? = done && had ? (cTop != nil && pTop != nil ? cTop! - pTop! : nil) : nil
        metrics.append(DayMetric(id: "\(id)-load", name: "Top load", planned: planned.flatMap(plannedTop).map { WeightFmt.text($0, u) }, previous: had ? pTop.map { WeightFmt.text($0, u) } : nil, current: done ? cTop.map { WeightFmt.text($0, u) } : nil,
                                 change: done && had ? (loadDelta.map { signedKg($0, u) } ?? "No load recorded") : missing(), verdict: verdict(loadDelta, tol: 0.05)))
        // volume
        let volDelta: Double? = done && had ? (cVol != nil && pVol != nil ? cVol! - pVol! : nil) : nil
        metrics.append(DayMetric(id: "\(id)-volume", name: "Volume", previous: had ? pVol.map { WeightFmt.text($0, u) } : nil, current: done ? cVol.map { WeightFmt.text($0, u) } : nil,
                                 change: done && had ? (volDelta.map { signedKg($0, u) } ?? "No load recorded") : missing(), verdict: verdict(volDelta, tol: volTol)))

        // the exercise as a whole
        var v: DayVerdict = .notComparable, change = missing()
        if done && had {
            if let vd = volDelta, let ld = loadDelta {
                let vv = verdict(vd, tol: volTol), lv = verdict(ld, tol: 0.05)
                if vv == .same && lv == .same { v = .same; change = "Unchanged" }
                else if vv != .worse && lv != .worse { v = .better; change = lv == .better ? "Top load \(signedKg(ld, u))" : "Volume \(signedKg(vd, u))" }
                else if vv != .better && lv != .better { v = .worse; change = lv == .worse ? "Top load \(signedKg(ld, u))" : "Volume \(signedKg(vd, u))" }
                else { v = .notComparable; change = "Load \(signedKg(ld, u)), volume \(signedKg(vd, u)) — not comparable" }
            } else {
                let d = (cReps ?? 0) - (pReps ?? 0)
                v = d == 0 ? .same : d > 0 ? .better : .worse; change = d == 0 ? "Unchanged" : signed(d, "reps")
            }
        } else if done { change = "No previous record of this exercise" }
        return DayExercise(id: id, name: name, planned: pText, previous: had ? text(previous) : nil, current: done ? text(current) : nil, change: change, verdict: v, metrics: metrics)
    }

    /// The most relevant earlier detailed log: same focus with an exercise in common, else any with an exercise in common.
    static func previousLog(for ids: Set<String>, focus: StrengthFocus?, before: Date, excluding: UUID?, in logs: [StrengthSession]) -> (log: StrengthSession, basis: String)? {
        let earlier = logs.filter { $0.id != excluding && $0.date < before && $0.isDetailed && !Set(($0.exercises ?? []).filter { !$0.doneSets.isEmpty }.map(\.exerciseId)).isDisjoint(with: ids) }
            .sorted { $0.date > $1.date }
        func common(_ l: StrengthSession) -> Int { Set((l.exercises ?? []).map(\.exerciseId)).intersection(ids).count }
        if let f = focus, let l = earlier.first(where: { $0.focus == f }) { return (l, "Most recent \(f.title.lowercased()) session with \(common(l)) of these exercises") }
        if let l = earlier.first { return (l, "Most recent session with \(common(l)) of these exercises") }
        return nil
    }

    static func strengthMetrics(current: StrengthSession?, planned: Workout?, previous: StrengthSession?, exercises: [DayExercise], units u: AppSettings.Units) -> [DayMetric] {
        let both = exercises.filter { $0.current != nil && $0.previous != nil }
        var m: [DayMetric] = []
        // total volume over the exercises recorded in BOTH sessions, so a dropped or added exercise does not distort it
        if let c = current, let p = previous {
            let ids = Set(both.map(\.id))
            let cv = (c.exercises ?? []).filter { ids.contains($0.exerciseId) }.compactMap(\.tonnageKg).reduce(0, +)
            let pv = (p.exercises ?? []).filter { ids.contains($0.exerciseId) }.compactMap(\.tonnageKg).reduce(0, +)
            if cv > 0 || pv > 0 {
                let d = cv - pv
                m.append(DayMetric(id: "s-volume", name: "Volume, shared exercises", previous: WeightFmt.text(pv, u), current: WeightFmt.text(cv, u), change: signedKg(d, u),
                                   verdict: abs(d) <= volTol ? .same : d > 0 ? .better : .worse))
            }
        }
        func count(_ l: StrengthSession?) -> Int? { l.map { ($0.exercises ?? []).filter { !$0.doneSets.isEmpty }.count } }
        func sets(_ l: StrengthSession?) -> Int? { l.map { ($0.exercises ?? []).reduce(0) { $0 + $1.doneSets.count } } }
        let ce = count(current), pe = count(previous)
        m.append(DayMetric(id: "s-exercises", name: "Exercises", previous: pe.map(String.init), current: ce.map(String.init),
                           change: ce != nil && pe != nil ? signed(ce! - pe!, "") .trimmingCharacters(in: .whitespaces) : (ce == nil ? "Not done yet" : "No previous record"), verdict: ce != nil && ce == pe ? .same : .notComparable))
        let cs = sets(current), ps = sets(previous)
        m.append(DayMetric(id: "s-sets", name: "Sets completed", previous: ps.map(String.init), current: cs.map(String.init),
                           change: cs != nil && ps != nil ? signed(cs! - ps!, "").trimmingCharacters(in: .whitespaces) : (cs == nil ? "Not done yet" : "No previous record"), verdict: cs != nil && cs == ps ? .same : .notComparable))
        func mins(_ l: StrengthSession?) -> Int? { l.flatMap { $0.minutes > 0 ? $0.minutes : nil } }
        let cm = mins(current), pm = mins(previous)
        m.append(DayMetric(id: "s-duration", name: "Duration", planned: planned.map { Fmt.duration(minutes: $0.minutes) }, previous: pm.map { Fmt.duration(minutes: $0) }, current: cm.map { Fmt.duration(minutes: $0) },
                           change: cm != nil && pm != nil ? signed(cm! - pm!, "min") : (current == nil ? "Not done yet" : "Not recorded"), verdict: cm != nil && cm == pm ? .same : .notComparable))
        return m
    }

    static func strengthAnalysis(completed: Bool, previous: DayPrevious?, exercises: [DayExercise], metrics: [DayMetric], calendar cal: Calendar) -> String {
        guard let p = previous else {
            return completed ? "No earlier session with these exercises is recorded, so there is nothing to compare yet. This session becomes the reference for the next one."
                             : "Not done yet, and no earlier session with these exercises is recorded. There is nothing to compare."
        }
        guard completed else { return "Not done yet. The figures under Previous are from \(dateText(p.date, calendar: cal)); the comparison appears once this session is recorded." }
        let up = exercises.filter { $0.verdict == .better }.map(\.name), down = exercises.filter { $0.verdict == .worse }.map(\.name)
        let same = exercises.filter { $0.verdict == .same }.map(\.name), mixed = exercises.filter { $0.verdict == .notComparable && $0.current != nil && $0.previous != nil }.map(\.name)
        var s: [String] = ["Compared with \(dateText(p.date, calendar: cal)):"]
        var parts: [String] = []
        if !up.isEmpty { parts.append("\(list(up)) went up") }
        if !down.isEmpty { parts.append("\(list(down)) went down") }
        if !same.isEmpty { parts.append("\(list(same)) \(same.count == 1 ? "was" : "were") unchanged") }
        if !mixed.isEmpty { parts.append("\(list(mixed)) changed load and volume in opposite directions") }
        s.append(parts.isEmpty ? "none of these exercises was recorded in both sessions." : parts.joined(separator: "; ") + ".")
        if let v = metrics.first(where: { $0.id == "s-volume" }), let a = v.previous, let b = v.current {
            s.append(v.verdict == .same ? "Volume over the shared exercises was the same (\(b))." : "Volume over the shared exercises went from \(a) to \(b).")
        }
        return s.joined(separator: " ")
    }

    // MARK: cycling

    static func rideMetrics(current c: RideRecord?, planned: Workout?, previous p: RideRecord?, units u: AppSettings.Units) -> [DayMetric] {
        func miss() -> String { c == nil ? "Not done yet" : p == nil ? "No previous record" : "Not measured" }
        var m: [DayMetric] = []
        let cm = c.map { max(1, $0.durationS / 60) }, pm = p.map { max(1, $0.durationS / 60) }
        m.append(DayMetric(id: "r-duration", name: "Duration", planned: planned.map { Fmt.duration(minutes: $0.minutes) }, previous: pm.map { Fmt.duration(minutes: $0) }, current: cm.map { Fmt.duration(minutes: $0) },
                           change: cm != nil && pm != nil ? signed(cm! - pm!, "min") : miss(), verdict: cm != nil && cm == pm ? .same : .notComparable))
        let cd = c.flatMap { $0.distanceM > 0 ? $0.distanceM : nil }, pd = p.flatMap { $0.distanceM > 0 ? $0.distanceM : nil }
        m.append(DayMetric(id: "r-distance", name: "Distance", previous: pd.map { distance($0, u) }, current: cd.map { distance($0, u) },
                           change: cd != nil && pd != nil ? (abs(cd! - pd!) < 100 ? "No change" : (cd! > pd! ? "+" : "−") + distance(abs(cd! - pd!), u)) : miss(), verdict: cd != nil && pd != nil && abs(cd! - pd!) < 100 ? .same : .notComparable))
        // power and heart rate are judged TOGETHER — neither alone says the ride went better
        let cp = c?.avgPower, pp = p?.avgPower, ch = c?.avgHR, ph = p?.avgHR
        let dp = cp != nil && pp != nil ? cp! - pp! : nil, dh = ch != nil && ph != nil ? ch! - ph! : nil
        var pv: DayVerdict = .notComparable, hv: DayVerdict = .notComparable
        if let dp, let dh {
            let pUp = dp > wTol, pDown = dp < -wTol, hUp = dh > hrTol, hDown = dh < -hrTol
            if !pUp && !pDown && !hUp && !hDown { pv = .same; hv = .same }
            else {
                pv = pUp && !hUp ? .better : pDown && !hDown ? .worse : (!pUp && !pDown ? .same : .notComparable)
                hv = hDown && !pDown ? .better : hUp && !pUp ? .worse : (!hUp && !hDown ? .same : .notComparable)
            }
        }
        m.append(DayMetric(id: "r-power", name: "Average power", previous: pp.map { "\($0) W" }, current: cp.map { "\($0) W" }, change: dp.map { signed($0, "W") } ?? miss(), verdict: pv))
        m.append(DayMetric(id: "r-hr", name: "Average heart rate", previous: ph.map { "\($0) bpm" }, current: ch.map { "\($0) bpm" }, change: dh.map { signed($0, "bpm") } ?? miss(), verdict: hv))
        let cc = c?.avgCadence, pc = p?.avgCadence
        m.append(DayMetric(id: "r-cadence", name: "Average cadence", previous: pc.map { "\($0) rpm" }, current: cc.map { "\($0) rpm" },
                           change: cc != nil && pc != nil ? signed(cc! - pc!, "rpm") : miss(), verdict: cc != nil && cc == pc ? .same : .notComparable))
        // time in zones — shown, never judged
        for z in 0..<7 {
            let cz = c.map { $0.zoneSeconds.count > z ? $0.zoneSeconds[z] / 60 : 0 }, pz = p.map { $0.zoneSeconds.count > z ? $0.zoneSeconds[z] / 60 : 0 }
            guard (cz ?? 0) > 0 || (pz ?? 0) > 0 else { continue }
            m.append(DayMetric(id: "r-zone\(z + 1)", name: "Time in zone \(z + 1)", planned: planned.flatMap { $0.kind.zone == z + 1 ? "target zone" : nil },
                               previous: pz.map { Fmt.duration(minutes: $0) }, current: cz.map { Fmt.duration(minutes: $0) },
                               change: cz != nil && pz != nil ? signed(cz! - pz!, "min") : miss(), verdict: cz != nil && cz == pz ? .same : .notComparable))
        }
        return m
    }

    static func rideAnalysis(current c: RideRecord?, previous p: DayPrevious?, metrics: [DayMetric], calendar cal: Calendar) -> String {
        guard let p else {
            return c == nil ? "Not done yet, and no earlier comparable ride is recorded. There is nothing to compare."
                            : "No earlier comparable ride is recorded, so there is nothing to compare yet. This ride becomes the reference for the next one."
        }
        guard c != nil else { return "Not done yet. The figures under Previous are from \(dateText(p.date, calendar: cal)); the comparison appears once this ride is recorded." }
        let power = metrics.first { $0.id == "r-power" }, hr = metrics.first { $0.id == "r-hr" }
        var s = "Compared with \(dateText(p.date, calendar: cal)): "
        if let pw = power, pw.previous != nil, pw.current != nil, let h = hr, h.previous != nil, h.current != nil {
            func word(_ m: DayMetric, _ noun: String) -> String { m.change == "No change" ? "\(noun) was the same" : "\(noun) was \(m.change.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "−", with: "")) \(m.change.hasPrefix("+") ? "higher" : "lower")" }
            s += "\(word(pw, "average power")) and \(word(h, "average heart rate"))."
            switch (pw.verdict, h.verdict) {
            case (.better, _), (_, .better): s += " More power for no more heart rate, or the same power for less, is the favourable direction."
            case (.worse, _), (_, .worse): s += " Less power for no less heart rate is the unfavourable direction."
            case (.same, .same): break
            default: s += " Power and heart rate moved the same way, so the two rides are not directly comparable."
            }
        } else if let h = hr, h.previous != nil, h.current != nil {
            s += "power was not measured in both rides, so only time, distance and heart rate can be set side by side. Heart rate alone does not show whether the ride went better."
        } else {
            s += "neither power nor heart rate was measured in both rides, so only time and distance can be set side by side."
        }
        return s
    }

    // MARK: health

    static func health(day: Date, log: RecoveryLog, enabled: Set<HealthSample.Kind>, soreness: [String], future: Bool, calendar cal: Calendar) -> [DayHealthRow] {
        let key = RecoveryLog.dayKey(day, calendar: cal)
        let tf = DateFormatter(); tf.calendar = cal; tf.timeZone = cal.timeZone; tf.dateFormat = "HH:mm"
        var rows: [DayHealthRow] = []
        for (k, name, icon) in [(HealthSample.Kind.sleep, "Sleep", "moon.fill"), (.restingHR, "Resting heart rate", "heart.fill"), (.hrv, "HRV", "waveform.path.ecg")] {
            if let e = log.entries.first(where: { $0.kind == k && RecoveryLog.dayKey($0.date, calendar: cal) == key }) {
                rows.append(DayHealthRow(id: k.rawValue, name: name, icon: icon, value: RecoveryAnalysis.valueText(k, e.value), detail: "\(e.source ?? "Apple Health") · \(tf.string(from: e.date))"))
            } else {
                rows.append(DayHealthRow(id: k.rawValue, name: name, icon: icon, value: nil, detail: future ? "Not yet" : enabled.contains(k) ? "No reading this day" : "Not connected"))
            }
        }
        rows.append(DayHealthRow(id: "soreness", name: "Soreness", icon: "figure.cooldown", value: soreness.isEmpty ? nil : soreness.joined(separator: " · "),
                                 detail: soreness.isEmpty ? "Not answered in a session review" : "From your session review"))
        return rows
    }
}

extension Store {
    /// The Daily Training Overview of one day. Reads only.
    func dayOverview(_ date: Date, now: Date = Date(), recorderActive: Bool = false, calendar cal: Calendar = .current) -> DayOverview {
        let d = homeDayDetail(date, now: now, recorderActive: recorderActive, calendar: cal)
        let day = cal.startOfDay(for: date), today = cal.startOfDay(for: now)
        let u = settings.units, led = ledger
        // rides that completed a planned session, by that session's kind
        var kindOf: [UUID: WorkoutKind] = [:]
        for w in plan where w.kind.isRide { if let r = led.ride(for: w) { kindOf[r.id] = w.kind } }
        let realRides = rides.filter { !$0.demo }
        var sessions: [DaySessionReview] = []
        for item in d.items {
            let w = item.session?.workout
            if item.isRide {
                var cur: RideRecord? = nil
                if case .ride(let id) = item.record { cur = rides.first { $0.id == id } }
                let before = cur?.start ?? w?.date ?? day
                let kind = w?.kind ?? cur.flatMap { kindOf[$0.id] }
                let earlier = realRides.filter { $0.id != cur?.id && $0.start < before }.sorted { $0.start > $1.start }
                let minutes = cur.map { $0.durationS / 60 } ?? w?.minutes ?? 0
                var prev: RideRecord? = nil, basis = "", family: [RideRecord] = []
                if let k = kind, let r = earlier.first(where: { kindOf[$0.id] == k }) {
                    prev = r; basis = "Most recent recorded \(k.title.lowercased()) session"; family = earlier.filter { kindOf[$0.id] == k }
                } else if minutes > 0, let r = earlier.first(where: { abs($0.durationS / 60 - minutes) * 4 <= minutes }) {
                    prev = r; basis = "Most recent ride of similar length (within a quarter)"; family = earlier.filter { abs($0.durationS / 60 - minutes) * 4 <= minutes }
                }
                let dp = prev.map { DayPrevious(date: $0.start, title: kindOf[$0.id]?.title ?? "Ride", line: HomeSummariesModel.rideLine($0, units: u), basis: basis, record: .ride($0.id)) }
                let metrics = DayReviewModel.rideMetrics(current: cur, planned: w, previous: prev, units: u)
                // history: average power when at least three comparable rides measured it, else average heart rate
                var hist: DayHistory? = nil
                let chain = (family.prefix(7).reversed() + (cur.map { [$0] } ?? []))
                for (title, unit, get) in [("Average power", "W", { (r: RideRecord) in r.avgPower }), ("Average heart rate", "bpm", { (r: RideRecord) in r.avgHR })] {
                    let pts = chain.compactMap { r in get(r).map { (r, $0) } }
                    if pts.count >= 3 {
                        hist = DayHistory(title: "\(title) · comparable rides", points: pts.enumerated().map { i, p in
                            DayHistoryPoint(id: i, date: p.0.start, value: Double(p.1), text: "\(p.1) \(unit)", record: .ride(p.0.id), isCurrent: p.0.id == cur?.id) })
                        break
                    }
                }
                sessions.append(DaySessionReview(id: item.id, item: item, sport: .cycling,
                    plannedLine: w.map { "\(Fmt.duration(minutes: $0.minutes)) · \($0.kind.subtitle)" }, actualLine: cur.map { HomeSummariesModel.rideLine($0, units: u) },
                    previous: dp, previousEmpty: "No earlier comparable ride is recorded.", metrics: metrics, exercises: [],
                    analysis: DayReviewModel.rideAnalysis(current: cur, previous: dp, metrics: metrics, calendar: cal), history: hist))
            } else {
                var cur: StrengthSession? = nil
                if case .strength(let id) = item.record { cur = strength.first { $0.id == id } }
                let planEntries: [ExerciseEntry] = w.map { self.plannedEntries(for: $0) } ?? []
                let done = (cur?.exercises ?? []).filter { !$0.doneSets.isEmpty }
                let completed = !done.isEmpty
                let list = completed ? done : planEntries
                let ids = Set(list.map(\.exerciseId))
                let before = cur?.date ?? w?.date ?? day
                let pick = ids.isEmpty ? nil : DayReviewModel.previousLog(for: ids, focus: cur?.focus ?? w?.strengthFocus, before: before, excluding: cur?.id, in: strength)
                let prev = pick?.log
                let exercises = list.map { e in
                    DayReviewModel.exercise(planned: planEntries.first { $0.exerciseId == e.exerciseId }, current: completed ? e : nil,
                                            previous: prev?.exercises?.first { $0.exerciseId == e.exerciseId }, units: u)
                }
                // a record without exercise details has nothing to set side by side
                let metrics = ids.isEmpty ? [] : DayReviewModel.strengthMetrics(current: completed ? cur : nil, planned: w, previous: prev, exercises: exercises, units: u)
                let dp = prev.map { l in DayPrevious(date: l.date, title: l.title, line: "\((l.exercises ?? []).filter { !$0.doneSets.isEmpty }.count) exercises" + (l.minutes > 0 ? " · \(Fmt.duration(minutes: l.minutes))" : ""), basis: pick?.basis ?? "", record: .strength(l.id)) }
                // history: session volume over these exercises, across the earlier sessions that hold any of them
                var hist: DayHistory? = nil
                if !ids.isEmpty {
                    let chain = strength.filter { $0.id != cur?.id && $0.date < before && $0.isDetailed }.sorted { $0.date < $1.date }.suffix(7) + (completed ? [cur!] : [])
                    let pts = chain.compactMap { l -> (StrengthSession, Double)? in
                        let v = (l.exercises ?? []).filter { ids.contains($0.exerciseId) }.compactMap(\.tonnageKg).reduce(0, +); return v > 0 ? (l, v) : nil }
                    if pts.count >= 3 {
                        hist = DayHistory(title: "Volume of these exercises · earlier sessions", points: pts.enumerated().map { i, p in
                            DayHistoryPoint(id: i, date: p.0.date, value: p.1, text: WeightFmt.text(p.1, u), record: .strength(p.0.id), isCurrent: p.0.id == cur?.id) })
                    }
                }
                let actual: String? = completed ? "\(done.count) exercise\(done.count == 1 ? "" : "s") · \(done.reduce(0) { $0 + $1.doneSets.count }) sets" + ((cur?.minutes ?? 0) > 0 ? " · \(Fmt.duration(minutes: cur!.minutes))" : "") : nil
                sessions.append(DaySessionReview(id: item.id, item: item, sport: .strength,
                    plannedLine: w.map { "\(Fmt.duration(minutes: $0.minutes))" + (planEntries.isEmpty ? "" : " · \(planEntries.count) exercises") },
                    actualLine: actual ?? (cur != nil ? "Recorded without exercise details" : nil),
                    previous: dp, previousEmpty: ids.isEmpty ? "This session has no exercise details to compare." : "No earlier session with these exercises is recorded.",
                    metrics: metrics, exercises: exercises,
                    analysis: ids.isEmpty ? "This session was recorded without exercise details, so sets, reps and load cannot be compared." : DayReviewModel.strengthAnalysis(completed: completed, previous: dp, exercises: exercises, metrics: metrics, calendar: cal),
                    history: hist))
            }
        }
        // the recurring week beside this day — said only where the two differ, today and later
        let isPast = day < today
        let avail = effectiveAvailability.days[(cal.component(.weekday, from: day) + 5) % 7]
        let wf = DateFormatter(); wf.calendar = cal; wf.dateFormat = "EEEE"
        let weekday = wf.string(from: day)
        func words(_ a: [DayAssignment]) -> String { a.map { "\($0.sport == .strength ? "strength" : "ride") · \(Fmt.duration(minutes: $0.minutes))" }.joined(separator: " + ") }
        let plannedHere = d.items.compactMap { $0.session?.workout }
        var note: String? = nil, free = false
        if !isPast {
            let recurring = avail.activity == .rest ? [] : avail.assignments
            let same = recurring.count == plannedHere.count && zip(recurring.sorted { $0.sport.rawValue < $1.sport.rawValue }, plannedHere.sorted { ($0.kind == .strength ? "strength" : "cycling") < ($1.kind == .strength ? "strength" : "cycling") })
                .allSatisfy { ($0.sport == .strength) == ($1.kind == .strength) && $0.minutes == $1.minutes }
            if d.items.isEmpty && d.kind == .rest {
                free = avail.activity != .rest
                if free && !recurring.isEmpty { note = "Your recurring \(weekday) has \(words(recurring)); nothing is scheduled this week." }
            } else if !plannedHere.isEmpty && !same {
                note = recurring.isEmpty ? "Your recurring \(weekday) is a rest day; this week's plan differs." : "Your recurring \(weekday) has \(words(recurring)); this week's plan differs."
            }
        }
        // soreness: only what was answered in a review of a session of this day
        var sore: [String] = []
        for r in rides where cal.isDate(r.start, inSameDayAs: day) { if let p = r.review?.pain ?? r.checkIn?.pain { sore.append(p.title) } }
        for l in strength where cal.isDate(l.date, inSameDayAs: day) { if let p = l.review?.pain ?? l.checkIn?.pain { sore.append(p.title) } }
        let roster = AthleticRoster.unique(AthleticRoster.roster(of: profile)).compactMap { AthleticRoster.activity($0) }
        return DayOverview(detail: d, sessions: sessions, freeDay: free, weekNote: note,
                           health: DayReviewModel.health(day: day, log: recoveryLog, enabled: Set(enabledHealthReads), soreness: sore, future: day > today, calendar: cal),
                           uncollected: ["Steps", "Water", "Energy"],
                           unsupported: roster.filter { $0.recording == nil && TrainingType.of($0) != nil }.map(\.title))
    }
}
