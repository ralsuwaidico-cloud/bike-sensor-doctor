import Foundation
@testable import BikeComputer

// MARK: - Cyclift coach audit harness (commit 2b2c104). Drives the REAL engine code (Store, PlanEngine,
// StrengthPlanner, AdaptationEngine, HybridCoach) — nothing here re-implements a coaching rule. The harness only
// (1) sets up profiles, (2) plays a simulated athlete who performs / misses the planned sessions and rates them,
// (3) records what the engine generated and decided, (4) checks pre-declared acceptance criteria.

let cal = Calendar.current
let realNow = Date()
let today = cal.startOfDay(for: realNow)
func dayDate(_ offset: Int, hour: Int = 0, minute: Int = 0) -> Date {
    cal.date(byAdding: .minute, value: hour * 60 + minute, to: cal.date(byAdding: .day, value: offset, to: today)!)!
}
let thisMonday = TrainingLedger.monday(of: today)
let nextMonday = cal.date(byAdding: .day, value: 7, to: thisMonday)!
let df: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
func ds(_ d: Date) -> String { df.string(from: d) }

// MARK: simulated athlete behaviour
enum Sensor { case hrOnly, verifiedPower, unverifiedPower, gpsOnly, watchHR, none }

struct RideOutcome {
    var minutesFactor = 1.0
    var checkIn: CheckIn? = CheckIn(performance: 7, effort: 6)
    var hrBias = 0          // bpm added to the zone midpoint (drift / fatigue)
}
struct LiftOutcome {
    var repsDelta = 0
    var rpe: Int? = 7
    var weightFactor = 1.0
    var checkIn: CheckIn? = CheckIn(performance: 7, effort: 6)
    var detailed = true
}
enum Outcome { case miss, ride(RideOutcome), lift(LiftOutcome) }

/// Context handed to a scenario policy for one past planned session.
struct PolicyCtx {
    var workout: Workout
    var dayOffset: Int           // negative, relative to today
    var fromEnd: Int             // 0 = the last session of this sport in the simulated history
    var sport: String            // "ride" / "lift"
}

struct Case {
    var id: String
    var title: String
    var athleteType: String
    var profile: RiderProfile
    var equipment = EquipmentProfile()
    var prefs = StrengthPrefs()
    var availability: WeeklyAvailability? = nil
    var units: AppSettings.Units = .metric
    var sensor: Sensor = .hrOnly
    var historyDays = 28
    /// plan weeks generated for the history (week offsets relative to this week, e.g. [-4,-3,-2,-1]); nil = from historyDays
    var historyWeeks: [Int]? = nil
    var templates: [WorkoutTemplate] = []
    var weekdayRoutines: [Int: UUID] = [:]
    var autoAdapt = true
    var policy: (PolicyCtx) -> Outcome = { c in c.sport == "ride" ? .ride(RideOutcome()) : .lift(LiftOutcome()) }
    var feedbackText = "every session rated performance 7 / effort 6, lifts at RPE 7 with all reps"
    var expectations: [Expectation] = []
    var setup: ((Store) -> Void)? = nil
    var afterSim: ((Store) -> [String])? = nil
}

struct Expectation {
    var id: String
    var kind = "scenario"
    var text: String
    var check: (Report, Store, AdaptationResult) -> (Bool, String)
}

// MARK: output records
struct SetOut: Codable { var reps: Int; var kg: Double?; var bw: Bool }
struct EntryOut: Codable {
    var name: String; var exerciseId: String; var pattern: String; var slot: String; var equipment: [String]; var difficulty: Int
    var sets: [SetOut]; var role: String?; var dose: String?; var load: String?; var cycling: String?; var targetRPE: Int?
}
struct WorkoutOut: Codable {
    var date: String; var kind: String; var title: String; var minutes: Int; var fixed: Bool; var done: Bool; var skipped: Bool
    var intervalReps: Int?; var coachAdjusted: Bool; var original: String?; var templateId: String?
    var entries: [EntryOut]; var notes: [String]
}
struct AdjOut: Codable { var date: String; var workout: String; var change: String; var category: String; var summary: String; var why: String }
struct PropOut: Codable { var reason: String; var text: String; var why: String; var adjustments: [String] }
struct EventOut: Codable { var date: String; var sport: String; var performed: String; var checkIn: String; var adjustmentsInForce: [String]; var proposals: [String]; var confidence: String }
struct CriterionOut: Codable { var id: String; var kind: String; var text: String; var pass: Bool; var detail: String }
struct Report: Codable {
    var id: String; var title: String; var athleteType: String
    var auditedCommit = "2b2c104"; var runAt: String
    var inputs: [String: String]
    var availability: [String]
    var consistency: [String]
    var trimmed: [String]
    var nextWeek: [WorkoutOut]
    var thisWeekRemaining: [WorkoutOut]
    var simulatedHistory: [String]
    var feedback: String
    var events: [EventOut]
    var finalAdjustments: [AdjOut]
    var finalProposals: [PropOut]
    var confidence: String
    var findings: [String]
    var feedbackRequest: String?
    var painAdvice: String?
    var acuteLoad: Int?; var chronicLoad: Int?
    var hybridFindingsNextWeek: [String]
    var hybridProposalsNextWeek: [String]
    var extra: [String]
    var criteria: [CriterionOut]
    var pass: Bool
}

// MARK: helpers
func startKg(_ e: Exercise, exp: StrengthPrefs.Experience) -> Double {
    let eq = Set(e.equipment.map(EquipmentProfile.normalised))
    let m = ExerciseLibrary.meta(e)
    let f: Double = exp == .beginner ? 0.6 : exp == .intermediate ? 1.0 : 1.4
    var base: Double
    let barbell = eq.contains("barbell") || eq.contains("trap bar")
    if barbell {
        switch m.slot { case .squat: base = 60; case .hinge: base = 80; case .horizontalPush: base = 50; case .verticalPush: base = 35; case .horizontalPull: base = 50; case .lunge: base = 30; default: base = 30 }
        return max(20, ((base * f) / 2.5).rounded() * 2.5)
    }
    if eq.contains("machine") || eq.contains("cable") { base = m.slot.isLower ? 60 : 35; return ((base * f) / 2.5).rounded() * 2.5 }
    switch m.slot { case .squat: base = 20; case .hinge: base = 22; case .horizontalPush, .verticalPush: base = 16; case .horizontalPull, .verticalPull: base = 18; case .lunge: base = 12; case .carry: base = 24; case .arms: base = 10; case .core: base = 8; default: base = 8 }
    return max(2, (base * f).rounded())
}

func entryOut(_ e: ExerciseEntry, _ w: Workout, catalogue: [Exercise]) -> EntryOut {
    let ex = catalogue.first { $0.id == e.exerciseId } ?? Exercise(id: e.exerciseId, name: e.name, pattern: e.pattern)
    let m = ExerciseLibrary.meta(ex)
    let r = w.rationale?.exercise(e.exerciseId)
    return EntryOut(name: e.name, exerciseId: e.exerciseId, pattern: e.pattern.rawValue, slot: m.slot.rawValue, equipment: ex.equipment, difficulty: m.difficulty,
                    sets: e.sets.map { SetOut(reps: $0.reps, kg: $0.weightKg, bw: $0.bodyweight) }, role: r?.role, dose: r?.dose, load: r?.load, cycling: r?.cycling, targetRPE: r?.targetRPE)
}
func workoutOut(_ w: Workout, store s: Store) -> WorkoutOut {
    let entries = w.kind == .strength ? s.plannedEntries(for: w) : []
    var orig: String? = nil
    if let o = w.coachOriginal { orig = "\(o.kind.rawValue) \(o.minutes) min" + (o.intervalReps.map { " reps \($0)" } ?? "") + (o.plannedEntries.map { " entries: " + $0.map { "\($0.name) \($0.sets.count)x\($0.sets.first?.reps ?? 0)@\($0.sets.first?.weightKg.map { String($0) } ?? "-")" }.joined(separator: "; ") } ?? "") }
    return WorkoutOut(date: ds(w.date), kind: w.kind.rawValue, title: w.displayTitle, minutes: w.minutes, fixed: w.fixed, done: w.done, skipped: w.skipped,
                      intervalReps: w.effectiveIntervalReps, coachAdjusted: w.coachAdjusted, original: orig, templateId: w.templateId?.uuidString,
                      entries: entries.map { entryOut($0, w, catalogue: s.allExercises) }, notes: (w.rationale?.notes ?? []) + (w.note.isEmpty ? [] : ["Plan note: " + w.note]))
}
func changeText(_ c: PlanAdjustment.Change) -> String {
    switch c {
    case .reps(let e, let d): return "reps \(e) \(d > 0 ? "+" : "")\(d)"
    case .weight(let e, let k): return "weight \(e) \(k > 0 ? "+" : "")\(k) kg"
    case .sets(let e, let d): return "sets \(e) \(d > 0 ? "+" : "")\(d)"
    case .kind(let k): return "kind -> \(k.rawValue)"
    case .intervalReps(let d): return "interval reps \(d > 0 ? "+" : "")\(d)"
    case .minutes(let d): return "minutes \(d > 0 ? "+" : "")\(d)"
    case .replace(let e, let n, let name, _): return "replace \(e) -> \(n) (\(name))"
    }
}
func adjOut(_ a: PlanAdjustment, _ s: Store) -> AdjOut {
    let w = s.plan.first { $0.id == a.workoutId }
    return AdjOut(date: w.map { ds($0.date) } ?? "?", workout: w?.restoredOriginal.displayTitle ?? "?", change: changeText(a.change), category: a.category.rawValue, summary: a.summary, why: a.why)
}
func propOut(_ p: AdaptiveProposal) -> PropOut { PropOut(reason: p.reason.rawValue, text: p.text, why: p.why, adjustments: p.adjustments.map { changeText($0.change) }) }
func ci(_ c: CheckIn?) -> String { guard let c else { return "none" }; return "perf \(c.performance) / effort \(c.effort)" + (c.pain == .noPain ? "" : " / pain \(c.pain.rawValue)\(c.painArea.map { " (\($0.rawValue))" } ?? "")") }

func hrFor(zone z: Int, profile p: RiderProfile) -> Int {
    let zs = p.hrZones
    let i = max(0, min(4, z - 1))
    let lo = zs[i].lo == 0 ? Int(Double(p.estimatedMaxHR) * 0.5) : zs[i].lo
    let hi = zs[i].hi ?? p.estimatedMaxHR
    return (lo + hi) / 2
}
func powerFor(zone z: Int, ftp: Int) -> Int {
    let mid: [Double] = [0.5, 0.68, 0.83, 0.98, 1.12]
    return Int(Double(ftp) * mid[max(0, min(4, z - 1))])
}

// MARK: the simulation
final class Runner {
    let c: Case
    let s: Store
    var history: [String] = []
    var events: [EventOut] = []
    var extra: [String] = []
    init(_ c: Case) {
        self.c = c
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cyclift-audit-\(c.id)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        s = Store(directory: dir, generatePlan: false)
    }

    func run() -> (Report, AdaptationResult) {
        s.profile = c.profile
        s.equipment = c.equipment
        s.strengthPrefs = c.prefs
        if let a = c.availability { s.availability = a }
        s.settings.units = c.units
        s.settings.autoAdapt = c.autoAdapt
        for t in c.templates { s.saveTemplate(t) }
        s.weekdayRoutines = c.weekdayRoutines
        c.setup?(s)
        // plan: history weeks and this week + next week (ensurePlan only generates weeks that have no entries)
        let weeks = c.historyWeeks ?? (c.historyDays > 0 ? Array(stride(from: -((c.historyDays + 6) / 7), to: 0, by: 1)) : [])
        for wk in weeks.sorted() { s.ensurePlan(now: cal.date(byAdding: .day, value: 7 * wk, to: thisMonday)!) }
        s.ensurePlan(now: realNow)
        // simulate the athlete on every past day of the history window
        let past = s.plan.filter { cal.startOfDay(for: $0.date) < today && cal.startOfDay(for: $0.date) >= cal.date(byAdding: .day, value: -c.historyDays, to: today)! && ($0.kind.isRide || $0.kind == .strength) }
            .sorted { ($0.date, $0.sequence) < ($1.date, $1.sequence) }
        let rideIds = past.filter { $0.kind.isRide }.map { $0.id }, liftIds = past.filter { $0.kind == .strength }.map { $0.id }
        for w0 in past {
            guard let w = s.plan.first(where: { $0.id == w0.id }), !w.done else { continue }
            let off = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: w.date)).day ?? 0
            let isRide = w.kind.isRide
            let list = isRide ? rideIds : liftIds
            let fromEnd = list.count - 1 - (list.firstIndex(of: w.id) ?? 0)
            let o = c.policy(PolicyCtx(workout: w, dayOffset: off, fromEnd: fromEnd, sport: isRide ? "ride" : "lift"))
            switch o {
            case .miss: history.append("\(ds(w.date)) \(w.displayTitle) (\(w.minutes) min): MISSED")
            case .ride(let ro): performRide(w, ro, off)
            case .lift(let lo): performLift(w, lo, off)
            }
        }
        // final state at the real "now": the app refreshes coach-built sessions and runs the coach
        s.refreshGeneratedSessions(now: realNow)
        let r = s.runAdaptation(now: realNow)
        return (report(r), r)
    }

    func performRide(_ w: Workout, _ o: RideOutcome, _ off: Int) {
        let start = cal.date(byAdding: .hour, value: 7, to: cal.startOfDay(for: w.date))!.addingTimeInterval(TimeInterval(w.sequence * 60))
        let mins = max(5, Int((Double(w.minutes) * o.minutesFactor).rounded()))
        var r = RideRecord(start: start, durationS: mins * 60, distanceM: mins * 450, recorder: .phone, sources: ["Phone GPS"])
        let p = s.profile
        var sensors: [String] = []
        switch c.sensor {
        case .hrOnly, .watchHR: r.avgHR = hrFor(zone: w.kind.zone, profile: p) + o.hrBias; sensors.append(c.sensor == .watchHR ? "Apple Watch HR" : "HR strap")
        case .verifiedPower: r.avgHR = hrFor(zone: w.kind.zone, profile: p) + o.hrBias; r.avgPower = powerFor(zone: w.kind.zone, ftp: p.ftpW); r.normalizedPower = r.avgPower; r.powerVerified = true; sensors += ["HR", "verified power"]
        case .unverifiedPower: r.avgPower = powerFor(zone: w.kind.zone, ftp: p.ftpW); r.normalizedPower = r.avgPower; sensors.append("unverified power (no HR)")
        case .gpsOnly: sensors.append("GPS only")
        case .none: sensors.append("no sensors")
        }
        if c.sensor == .gpsOnly || c.sensor == .none { r.recorder = .phone }
        r.checkIn = nil
        s.rides.insert(r, at: 0)
        if let i = s.plan.firstIndex(where: { $0.id == w.id }) { s.plan[i].done = true; s.plan[i].completion = .recorded; s.plan[i].completedAt = start }
        history.append("\(ds(w.date)) \(w.kind.title)\(w.effectiveIntervalReps.map { " \($0) reps" } ?? "") planned \(w.minutes) min → rode \(mins) min [\(sensors.joined(separator: ", "))\(r.avgHR.map { ", avg HR \($0)" } ?? "")\(r.avgPower.map { ", avg \($0) W" } ?? "")]; check-in \(ci(o.checkIn))")
        if let cIn = o.checkIn {
            var cc = cIn; cc.at = start.addingTimeInterval(TimeInterval(mins * 60 + 300))
            let res = s.recordCheckIn(cc, rideId: r.id, now: cc.at)
            log(res, date: w.date, sport: "ride", performed: "\(w.kind.title) \(mins) min", c: cc)
        }
    }

    func performLift(_ w: Workout, _ o: LiftOutcome, _ off: Int) {
        let at = cal.date(byAdding: .hour, value: 18, to: cal.startOfDay(for: w.date))!.addingTimeInterval(TimeInterval(w.sequence * 60))
        let planned = s.plannedEntries(for: w)
        var log: StrengthSession
        var desc: String
        if planned.isEmpty || !o.detailed {
            log = StrengthSession(date: at, minutes: w.minutes, focus: w.strengthFocus ?? .fullBody, rpe: o.rpe, workoutId: w.id)
            desc = "quick log (no exercise list planned\(planned.isEmpty ? "" : " / not detailed")), \(w.minutes) min, RPE \(o.rpe.map(String.init) ?? "-")"
        } else {
            let exp = PlannerContext(profile: s.profile, prefs: s.strengthPrefs).experience
            let entries = planned.map { e -> ExerciseEntry in
                var x = e; x.id = UUID()
                let ex = s.allExercises.first { $0.id == e.exerciseId } ?? Exercise(id: e.exerciseId, name: e.name, pattern: e.pattern)
                x.sets = e.sets.map { st in
                    var y = st; y.id = UUID(); y.done = true
                    y.reps = max(1, st.reps + o.repsDelta)
                    if !st.bodyweight { let base = st.weightKg ?? startKg(ex, exp: exp); y.weightKg = ((base * o.weightFactor) * 2).rounded() / 2 }
                    y.rpe = o.rpe
                    return y
                }
                return x
            }
            log = StrengthSession(date: at, minutes: w.minutes, focus: w.strengthFocus ?? .fullBody, rpe: o.rpe, exercises: entries, templateId: w.templateId, workoutId: w.id)
            desc = entries.map { e in "\(e.name) \(e.sets.count)x\(e.sets.first?.reps ?? 0)\(e.sets.first?.weightKg.map { "@\(WeightFmt.number($0, .metric))kg" } ?? "BW")" }.joined(separator: ", ") + " RPE \(o.rpe.map(String.init) ?? "-")"
        }
        _ = s.addStrength(log)
        history.append("\(ds(w.date)) \(w.displayTitle) → \(desc); check-in \(ci(o.checkIn))")
        if let cIn = o.checkIn {
            var cc = cIn; cc.at = at.addingTimeInterval(TimeInterval(w.minutes * 60 + 300))
            let res = s.recordCheckIn(cc, strengthId: log.id, now: cc.at)
            self.log(res, date: w.date, sport: "lift", performed: w.displayTitle, c: cc)
        }
    }

    func log(_ r: AdaptationResult?, date: Date, sport: String, performed: String, c: CheckIn) {
        guard let r else { return }
        events.append(EventOut(date: ds(date), sport: sport, performed: performed, checkIn: ci(c), adjustmentsInForce: s.activeAdaptations.map { "\(adjOut($0, s).date): \($0.summary)" }, proposals: s.adaptiveProposals.map { "\($0.reason.rawValue): \($0.text)" }, confidence: r.summary.confidence.rawValue))
    }

    func report(_ r: AdaptationResult) -> Report {
        let p = s.profile
        let a = s.effectiveAvailability
        var inputs: [String: String] = [
            "trainingMode": p.trainingMode.rawValue, "priority": p.priority.rawValue, "hybridGoal": p.hybridGoal?.rawValue ?? "nil",
            "level": p.level.rawValue, "goal(cycling)": p.goal.rawValue, "cyclingSessions": "\(p.cyclingDaysPerWeek)", "liftSessions": "\(p.liftDaysPerWeek)",
            "trainingDaysPerWeek": p.trainingDaysPerWeek.map(String.init) ?? "nil", "cyclingBudget_h": "\(p.hoursPerWeek)", "liftingBudget_h": "\(p.liftingHoursPerWeek)",
            "strengthSplit": p.strengthSplit?.rawValue ?? "nil (Coach decides)", "cyclingSessionMinutes": p.cyclingSessionMinutes.map(String.init) ?? "nil",
            "strengthSessionMinutes": p.strengthSessionMinutes.map(String.init) ?? "nil", "age": "\(p.effectiveAge)", "ftp": "\(p.ftpW) W (\(p.ftpHow.rawValue), confidence \(p.ftpConfidence.rawValue))",
            "maxHR(est)": "\(p.estimatedMaxHR)", "equipment": c.equipment.isSet ? c.equipment.owned.sorted().joined(separator: ",") : "not set (everything allowed)",
            "excluded": c.equipment.excluded.sorted().joined(separator: ","), "strengthExperience(pref)": c.prefs.experience?.rawValue ?? "nil (from cycling level)",
            "strengthGoal(pref)": c.prefs.goal?.rawValue ?? "nil (derived)", "sensor": "\(c.sensor)", "units": c.units.rawValue, "autoAdapt": "\(c.autoAdapt)",
            "historyDays": "\(c.historyDays)", "preferredDays": p.preferredDays.map(String.init).joined(separator: ",")
        ]
        let ctx = s.plannerContext(now: realNow)
        inputs["planner.experience(effective)"] = ctx.experience.rawValue
        inputs["planner.goal(effective)"] = ctx.goal.rawValue
        inputs["planner.priority(effective)"] = ctx.priority.rawValue
        let avail = a.days.enumerated().map { i, d in "\(WeeklyAvailability.dayNames[i]): " + (d.isRest ? "rest" : d.assignments.map { "\($0.sport.rawValue)\($0.cyclingType.map { "/" + $0.rawValue } ?? "")\($0.strengthType.map { "/" + $0.rawValue } ?? "") \($0.minutes)m\($0.fixed ? " FIXED" : "")" }.joined(separator: " + ")) }
        let fit = s.fitReport
        let nw = s.plan.filter { $0.date >= nextMonday && $0.date < cal.date(byAdding: .day, value: 7, to: nextMonday)! }.sorted { ($0.date, $0.sequence) < ($1.date, $1.sequence) }
        let tw = s.plan.filter { cal.startOfDay(for: $0.date) >= today && $0.date < nextMonday }.sorted { ($0.date, $0.sequence) < ($1.date, $1.sequence) }
        let ass = HybridCoach.assess(profile: p, plan: s.plan, rides: s.rides, strength: s.strength, availability: a, now: nextMonday)
        let consist = a.consistency(profile: p) + fit.conflicts.map { $0.text }
        var rep = Report(id: c.id, title: c.title, athleteType: c.athleteType, runAt: ISO8601DateFormatter().string(from: realNow), inputs: inputs, availability: avail,
                         consistency: Array(Set(consist)).sorted(), trimmed: fit.trimmed, nextWeek: nw.map { workoutOut($0, store: s) }, thisWeekRemaining: tw.map { workoutOut($0, store: s) },
                         simulatedHistory: history, feedback: c.feedbackText, events: events,
                         finalAdjustments: r.adjustments.map { adjOut($0, s) }, finalProposals: r.proposals.map(propOut), confidence: r.summary.confidence.rawValue,
                         findings: r.summary.findings, feedbackRequest: r.summary.feedbackRequest, painAdvice: r.summary.painAdvice, acuteLoad: r.summary.acuteLoad, chronicLoad: r.summary.chronicLoad,
                         hybridFindingsNextWeek: ass.findings.filter { $0.severity == .conflict || $0.severity == .gap }.map { "[\($0.severity.rawValue)] \($0.text)" },
                         hybridProposalsNextWeek: ass.proposals.map { $0.text }, extra: extra, criteria: [], pass: true)
        if let f = c.afterSim { rep.extra += f(s) }
        var crit = Criteria.generic(rep, s, r, c)
        for e in c.expectations { let (ok, d) = e.check(rep, s, r); crit.append(CriterionOut(id: e.id, kind: e.kind, text: e.text, pass: ok, detail: d)) }
        rep.criteria = crit
        rep.pass = crit.filter { $0.kind != "science-advisory" }.allSatisfy { $0.pass }
        return rep
    }
}
