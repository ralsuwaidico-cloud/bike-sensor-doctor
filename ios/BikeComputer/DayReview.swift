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
// WHEN A CHANGE IS CALLED FAVOURABLE (green) OR UNFAVOURABLE (red) — audited 24 Nov 2026 (owner, 23:51).
// A bigger number is not automatically better, and where improvement or decline cannot be established the result is
// NEUTRAL (grey). A verdict needs like-for-like conditions:
//   Strength exercise   the SAME exercise, the SAME number of completed sets, and then either
//                         · a higher top load with total reps not lower            → favourable
//                         · the same top load with more reps                       → favourable
//                         · a lower top load with reps not higher / fewer reps at the same load → unfavourable
//                       Anything else — a different number of sets, load and reps moving in opposite directions,
//                       a load the coach lowered for a return after a break, or a reported effort (RPE) two or more
//                       points higher for a "better" result / lower for a "worse" one — is NOT COMPARABLE.
//   Session volume      judged only when every shared exercise has the same number of sets in both sessions.
//   Cycling             judged only between two rides of the SAME planned session type, of similar length (within a
//                       quarter), whose reported effort — where both were reviewed — is within one point. Then:
//                         · more average power with heart rate not higher, or less heart rate at no less power → favourable
//                         · less power with heart rate not lower, or more heart rate at no more power → unfavourable
//                       Power or heart rate missing in either ride → not comparable.
//   Sets, duration, distance, cadence and time in zones are shown and never judged.
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
    /// 4 — fixed sentences built from the figures above (the full reasoning, shown under Details).
    var analysis: String
    /// 4 — the one short sentence the card shows (owner, 25 Nov 2026: shorter explanation, no technical wording).
    var short: String = ""
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
    static func exercise(planned: ExerciseEntry?, current: ExerciseEntry?, previous: ExerciseEntry?, effortDelta: Int? = nil, units u: AppSettings.Units) -> DayExercise {
        let name = current?.name ?? planned?.name ?? previous?.name ?? ""
        let id = current?.exerciseId ?? planned?.exerciseId ?? previous?.exerciseId ?? name
        let pText = planned.map { plannedText($0, u) }
        func text(_ e: ExerciseEntry?) -> String? { e.flatMap { $0.doneSets.isEmpty ? nil : $0.summary(units: u) } }
        var metrics: [DayMetric] = []
        let cTop = current.flatMap(topLoad), pTop = previous.flatMap(topLoad)
        let cVol = current?.tonnageKg, pVol = previous?.tonnageKg
        let cReps = current.map(\.totalReps), pReps = previous.map(\.totalReps)
        let cSets = current.map { $0.doneSets.count }, pSets = previous.map { $0.doneSets.count }

        let done = current.map { !$0.doneSets.isEmpty } ?? false
        let had = previous.map { !$0.doneSets.isEmpty } ?? false
        func missing() -> String { !done ? "Not done yet" : "No previous record" }

        // the exercise as a whole — like for like, or neutral
        let loadDelta: Double? = done && had ? (cTop != nil && pTop != nil ? cTop! - pTop! : nil) : nil
        let volDelta: Double? = done && had ? (cVol != nil && pVol != nil ? cVol! - pVol! : nil) : nil
        let repsDelta = (cReps ?? 0) - (pReps ?? 0), setsSame = cSets == pSets
        var v: DayVerdict = .notComparable, change = missing()
        if done && had {
            if current?.returnMark != nil { change = "Load lowered by the coach for a return — not compared" }
            else if !setsSame { change = "Different number of sets — not comparable" }
            else if let ld = loadDelta {
                let up = ld > 0.05, down = ld < -0.05
                if up && repsDelta >= 0 { v = .better; change = "Top load \(signedKg(ld, u))" }
                else if down && repsDelta <= 0 { v = .worse; change = "Top load \(signedKg(ld, u))" }
                else if !up && !down { v = repsDelta == 0 ? .same : repsDelta > 0 ? .better : .worse; change = repsDelta == 0 ? "Unchanged" : "\(signed(repsDelta, "reps")) at the same load" }
                else { change = "Load \(signedKg(ld, u)), reps \(repsDelta > 0 ? "+" : "−")\(abs(repsDelta)) — not comparable" }
            } else if cTop == nil && pTop == nil {
                v = repsDelta == 0 ? .same : repsDelta > 0 ? .better : .worse; change = repsDelta == 0 ? "Unchanged" : signed(repsDelta, "reps")
            } else { change = "Load recorded in only one session — not comparable" }
            // reported effort: a result bought with clearly more effort, or lost at clearly less, is not established
            if let e = effortDelta, (v == .better && e >= 2) || (v == .worse && e <= -2) {
                v = .notComparable; change += e > 0 ? " · at a higher reported effort — not comparable" : " · at a lower reported effort — not comparable"
            }
        } else if done { change = "No previous record of this exercise" }
        /// a figure's own colour follows the exercise: it is green or red only when the exercise as a whole is
        func part(_ d: Double?, tol: Double) -> DayVerdict {
            guard done && had, let d else { return .notComparable }
            if abs(d) <= tol { return .same }
            return d > 0 ? (v == .better ? .better : .notComparable) : (v == .worse ? .worse : .notComparable)
        }
        metrics.append(DayMetric(id: "\(id)-sets", name: "Sets", planned: planned.map { "\($0.sets.count)" }, previous: had ? pSets.map(String.init) : nil, current: done ? cSets.map(String.init) : nil,
                                 change: done && had ? signed((cSets ?? 0) - (pSets ?? 0), "set" + (abs((cSets ?? 0) - (pSets ?? 0)) == 1 ? "" : "s")) : missing(),
                                 verdict: done && had && setsSame ? .same : .notComparable))
        metrics.append(DayMetric(id: "\(id)-reps", name: "Reps", planned: planned.map { "\($0.sets.reduce(0) { $0 + $1.reps })" }, previous: had ? pReps.map(String.init) : nil, current: done ? cReps.map(String.init) : nil,
                                 change: done && had ? signed(repsDelta, "reps") : missing(), verdict: part(Double(repsDelta), tol: 0)))
        metrics.append(DayMetric(id: "\(id)-load", name: "Top load", planned: planned.flatMap(plannedTop).map { WeightFmt.text($0, u) }, previous: had ? pTop.map { WeightFmt.text($0, u) } : nil, current: done ? cTop.map { WeightFmt.text($0, u) } : nil,
                                 change: done && had ? (loadDelta.map { signedKg($0, u) } ?? "No load recorded") : missing(), verdict: part(loadDelta, tol: 0.05)))
        metrics.append(DayMetric(id: "\(id)-volume", name: "Volume", previous: had ? pVol.map { WeightFmt.text($0, u) } : nil, current: done ? cVol.map { WeightFmt.text($0, u) } : nil,
                                 change: done && had ? (volDelta.map { signedKg($0, u) } ?? "No load recorded") : missing(), verdict: part(volDelta, tol: volTol)))
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
                // judged only when every shared exercise was itself comparable and none moved the other way
                let vs = both.map(\.verdict)
                let like = !vs.contains(.notComparable) && !(vs.contains(.better) && vs.contains(.worse))
                m.append(DayMetric(id: "s-volume", name: "Volume", previous: WeightFmt.text(pv, u), current: WeightFmt.text(cv, u), change: signedKg(d, u),
                                   verdict: abs(d) <= volTol ? .same : !like ? .notComparable : d > 0 ? .better : .worse))
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
        if !mixed.isEmpty { parts.append("\(list(mixed)) could not be compared like for like") }
        s.append(parts.isEmpty ? "none of these exercises was recorded in both sessions." : parts.joined(separator: "; ") + ".")
        if let v = metrics.first(where: { $0.id == "s-volume" }), let a = v.previous, let b = v.current {
            s.append(v.verdict == .same ? "Volume over the shared exercises was the same (\(b))." : "Volume over the shared exercises went from \(a) to \(b).")
        }
        return s.joined(separator: " ")
    }

    /// One short sentence for the card. Names what changed; states no figure the comparison rows do not show.
    static func strengthShort(completed: Bool, previous: DayPrevious?, exercises: [DayExercise], calendar cal: Calendar) -> String {
        guard let p = previous else { return completed ? "First recorded session with these exercises — nothing to compare yet." : "Not done yet. No earlier session to compare." }
        guard completed else { return "Not done yet. Last comparable session: \(dateText(p.date, calendar: cal))." }
        func names(_ v: DayVerdict) -> [String] { exercises.filter { $0.verdict == v && $0.current != nil && $0.previous != nil }.map { $0.name.lowercased() } }
        var parts: [String] = []
        if !names(.better).isEmpty { parts.append("\(list(names(.better))) up") }
        if !names(.worse).isEmpty { parts.append("\(list(names(.worse))) down") }
        if !names(.same).isEmpty { parts.append("\(list(names(.same))) unchanged") }
        if !names(.notComparable).isEmpty { parts.append("\(list(names(.notComparable))) not comparable") }
        return parts.isEmpty ? "None of these exercises was recorded on \(dateText(p.date, calendar: cal))." : "Since \(dateText(p.date, calendar: cal)): \(parts.joined(separator: ", "))."
    }
    static func rideShort(current c: RideRecord?, previous p: DayPrevious?, metrics: [DayMetric], barrier: String?, calendar cal: Calendar) -> String {
        guard let p else { return c == nil ? "Not done yet. No earlier ride to compare." : "First recorded ride of this kind — nothing to compare yet." }
        let when = dateText(p.date, calendar: cal)
        guard c != nil else { return "Not done yet. Last comparable ride: \(when)." }
        if let b = barrier {
            let why = b.contains("session type") ? "it was a different kind of ride" : b.contains("length") ? "the two rides differ too much in length" : "your reported effort was clearly different"
            return "Not comparable with \(when): \(why)."
        }
        let pw = metrics.first { $0.id == "r-power" }, h = metrics.first { $0.id == "r-hr" }
        let hasP = pw?.previous != nil && pw?.current != nil, hasH = h?.previous != nil && h?.current != nil
        guard hasP || hasH else { return "Only time and distance were recorded in both rides." }
        guard hasP else { return "Power was not measured in both rides — not comparable with \(when)." }
        guard hasH else { return "Heart rate was not measured in both rides — not comparable with \(when)." }
        switch (pw!.verdict, h!.verdict) {
        case (.better, _): return "More power at a similar or lower heart rate than \(when)."
        case (_, .better): return "A lower heart rate at the same or more power than \(when)."
        case (.worse, _): return "Less power at a similar or higher heart rate than \(when)."
        case (_, .worse): return "A higher heart rate at the same or less power than \(when)."
        case (.same, .same): return "Power and heart rate were about the same as \(when)."
        default: return "Power and heart rate moved the same way since \(when) — not comparable."
        }
    }

    // MARK: cycling

    /// Why two rides cannot be judged against each other; nil = they can.
    static func rideBarrier(current c: RideRecord?, previous p: RideRecord?, sameType: Bool, effortDelta: Int?) -> String? {
        guard let c, let p else { return nil }
        if !sameType { return "The two rides were not the same planned session type, so no change is called better or worse." }
        let a = max(1, c.durationS / 60), b = max(1, p.durationS / 60)
        if abs(a - b) * 4 > max(a, b) { return "The two rides differ in length by more than a quarter, so no change is called better or worse." }
        if let e = effortDelta, abs(e) >= 2 { return "You reported a clearly \(e > 0 ? "higher" : "lower") effort this time, so no change is called better or worse." }
        return nil
    }

    static func rideMetrics(current c: RideRecord?, planned: Workout?, previous p: RideRecord?, comparable: Bool = true, units u: AppSettings.Units) -> [DayMetric] {
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
            else if !comparable { pv = !pUp && !pDown ? .same : .notComparable; hv = !hUp && !hDown ? .same : .notComparable }
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

    static func rideAnalysis(current c: RideRecord?, previous p: DayPrevious?, metrics: [DayMetric], barrier: String? = nil, calendar cal: Calendar) -> String {
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
            if let b = barrier { return s + " " + b }
            switch (pw.verdict, h.verdict) {
            case (.better, _), (_, .better): s += " More power for no more heart rate, or the same power for less, is the favourable direction."
            case (.worse, _), (_, .worse): s += " Less power for no less heart rate is the unfavourable direction."
            case (.same, .same): break
            default: s += " Power and heart rate moved the same way, so the two rides are not directly comparable."
            }
        } else if let h = hr, h.previous != nil, h.current != nil {
            s += "power was not measured in both rides, so only time, distance and heart rate can be set side by side. Heart rate alone does not show whether the ride went better."
        } else if let pw = power, pw.previous != nil, pw.current != nil {
            s += "heart rate was not measured in both rides, so the change in average power (\(pw.change)) cannot be called better or worse."
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
                func effort(_ r: RideRecord?) -> Int? { r?.review?.effort ?? r?.checkIn?.effort }
                let eDelta: Int? = effort(cur) != nil && effort(prev) != nil ? effort(cur)! - effort(prev)! : nil
                let barrier = DayReviewModel.rideBarrier(current: cur, previous: prev, sameType: kind != nil && prev.map { kindOf[$0.id] == kind } == true, effortDelta: eDelta)
                let metrics = DayReviewModel.rideMetrics(current: cur, planned: w, previous: prev, comparable: barrier == nil, units: u)
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
                    analysis: DayReviewModel.rideAnalysis(current: cur, previous: dp, metrics: metrics, barrier: barrier, calendar: cal), history: hist))
                sessions[sessions.count - 1].short = DayReviewModel.rideShort(current: cur, previous: dp, metrics: metrics, barrier: barrier, calendar: cal)
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
                // reported effort of the two sessions, where both state it (session RPE)
                let eDelta: Int? = completed && cur?.rpe != nil && prev?.rpe != nil ? cur!.rpe! - prev!.rpe! : nil
                let exercises = list.map { e in
                    DayReviewModel.exercise(planned: planEntries.first { $0.exerciseId == e.exerciseId }, current: completed ? e : nil,
                                            previous: prev?.exercises?.first { $0.exerciseId == e.exerciseId }, effortDelta: eDelta, units: u)
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
                sessions[sessions.count - 1].short = ids.isEmpty ? "Recorded without exercise details — nothing to compare." : DayReviewModel.strengthShort(completed: completed, previous: dp, exercises: exercises, calendar: cal)
            }
        }
        // a missed or skipped session was not "not done yet": it has no recording, and says so
        for k in sessions.indices {
            let st = sessions[k].item.statusText
            guard st == "Missed" || st == "Skipped" else { continue }
            for m in sessions[k].metrics.indices where sessions[k].metrics[m].change == "Not done yet" { sessions[k].metrics[m].change = "Not recorded" }
            for e in sessions[k].exercises.indices {
                if sessions[k].exercises[e].change == "Not done yet" { sessions[k].exercises[e].change = "Not recorded" }
                for m in sessions[k].exercises[e].metrics.indices where sessions[k].exercises[e].metrics[m].change == "Not done yet" { sessions[k].exercises[e].metrics[m].change = "Not recorded" }
            }
            sessions[k].short = "\(st) — nothing was recorded."
            sessions[k].analysis = "This session was \(st.lowercased()), so nothing was recorded to compare." + (sessions[k].previous.map { " The figures under Previous are from \(DayReviewModel.dateText($0.date, calendar: cal))." } ?? "")
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
