import Foundation
@testable import BikeComputer

// MARK: rule probes — single-rule checks on the real functions (edge cases the profiles cannot isolate)
struct Probe: Codable { var id: String; var rule: String; var input: String; var observed: String; var expected: String; var pass: Bool; var codeRef: String }
var probes: [Probe] = []
func probe(_ id: String, _ rule: String, _ input: String, _ observed: String, _ expected: String, _ pass: Bool, _ ref: String) { probes.append(Probe(id: id, rule: rule, input: input, observed: observed, expected: expected, pass: pass, codeRef: ref)) }

let cat = ExerciseCatalogue.builtIn
let backSquat = cat.first { $0.id == "ex-001" }!
func log(_ daysAgo: Int, _ ex: Exercise, sets n: Int, reps: Int, kg: Double?, rpe: Int?) -> StrengthSession {
    var s = StrengthSession(date: dayDate(-daysAgo, hour: 18), minutes: 45, focus: .fullBody, rpe: rpe, exercises: [ExerciseEntry(exercise: ex, sets: (0..<n).map { _ in SetEntry(reps: reps, weightKg: kg, bodyweight: kg == nil, rpe: rpe) })])
    s.source = "manual"; return s
}
func pctx(_ logs: [StrengthSession], exp: StrengthPrefs.Experience = .intermediate) -> PlannerContext {
    var p = RiderProfile(); p.trainingMode = .hybrid; p.strengthSplit = .fullBody
    if HarnessFixtures.screened { var sc = HealthScreen(); sc.answeredAt = Date(timeIntervalSince1970: 1_790_000_000); p.healthScreen = sc }
    var pr = StrengthPrefs(); pr.experience = exp
    return PlannerContext(profile: p, prefs: pr, equipment: fullGym, catalogue: cat, logs: logs, now: realNow)
}
let m0 = ExerciseLibrary.meta(backSquat)
do {
    var w = 40.0; var trail: [String] = []
    var logs: [StrengthSession] = []
    for k in 0..<6 { logs.append(log(30 - k * 4, backSquat, sets: 3, reps: 10, kg: w, rpe: 7)); let l = StrengthPlanner.prescribeLoad(backSquat, meta: m0, reps: 6...10, sets: 3, painBlocked: false, ctx: pctx(logs)); trail.append("\(WeightFmt.number(l.weight ?? 0, .metric))×\(l.reps)"); w = l.weight ?? w }
    probe("X01", "Planner double progression: load step must be ≤ 5 % of the load", "Back squat logged 3×10 @ 40 kg RPE 7 (top of 6–10 range), six sessions in a row", "next prescriptions: " + trail.joined(separator: ", "), "load rises at some point (2.5 kg = 6.25 % of 40 kg)", trail.contains { !$0.hasPrefix("40×") }, "StrengthPlanner.swift:624-632 (prescribeLoad: `step <= w * 0.05`)")
}
do {
    let l = StrengthPlanner.prescribeLoad(backSquat, meta: m0, reps: 6...10, sets: 3, painBlocked: false, ctx: pctx([log(3, backSquat, sets: 3, reps: 10, kg: 60, rpe: 8)]))
    probe("X02", "Planner progression evidence", "ONE logged session: Back squat 3×10 @ 60 kg RPE 8", "next: \(WeightFmt.number(l.weight ?? 0, .metric)) kg × \(l.reps) (progressed=\(l.progressed))", "two consecutive sessions above target before a load increase (ACSM 2009 '2-for-2'; the app's own doc: 'never react to one workout')", !l.progressed, "StrengthPlanner.swift:603-633 (uses `hist.first` only)")
}
do {
    let logs = [log(7, backSquat, sets: 3, reps: 4, kg: 60, rpe: 10), log(3, backSquat, sets: 3, reps: 4, kg: 60, rpe: 10)]
    let l = StrengthPlanner.prescribeLoad(backSquat, meta: m0, reps: 6...10, sets: 3, painBlocked: false, ctx: pctx(logs))
    probe("X03", "Planner response to repeated failure", "Back squat 3×4 @ 60 kg at RPE 10 twice (range 6–10)", "next: \(WeightFmt.number(l.weight ?? 0, .metric)) kg × \(l.reps)", "load reduced after repeated failure at RPE 10", (l.weight ?? 60) < 60, "StrengthPlanner.swift:634-636 (missed → same weight)")
}
do {
    let l = StrengthPlanner.prescribeLoad(backSquat, meta: m0, reps: 6...10, sets: 3, painBlocked: false, ctx: pctx([log(3, backSquat, sets: 3, reps: 10, kg: 80, rpe: nil)]))
    probe("X04", "Unknown RPE handling (planner)", "Back squat 3×10 @ 80 kg, no RPE recorded", "next: \(WeightFmt.number(l.weight ?? 0, .metric)) kg × \(l.reps) (progressed=\(l.progressed))", "unknown effort treated as not proven (as AdaptationEngine.strengthDecision does)", !l.progressed, "StrengthPlanner.swift:624 (`(rpe ?? 8) <= 8`) vs AdaptationEngine.swift:614 (`($0 ?? 99) <= 8`)")
}
do {
    let seq2 = StrengthSplit.sessions(split: .pushPullLegs, slots: [], count: 2).map { $0.title }
    let seq4 = StrengthSplit.sessions(split: .pushPullLegs, slots: [], count: 4).map { $0.title }
    let ul3 = StrengthSplit.sessions(split: .upperLower, slots: [], count: 3).map { $0.title }
    var p = hybridProfile { $0.strengthSplit = .pushPullLegs; $0.liftDaysPerWeek = 2 }; p.liftingHoursPerWeek = 2
    let a = WeeklyAvailability.suggested(for: p)
    let wk1 = PlanEngine.week(starting: nextMonday, profile: p, availability: a).filter { $0.kind == .strength }.map { $0.strengthFocus?.rawValue ?? "-" }
    let wk2 = PlanEngine.week(starting: cal.date(byAdding: .day, value: 7, to: nextMonday)!, profile: p, availability: a).filter { $0.kind == .strength }.map { $0.strengthFocus?.rawValue ?? "-" }
    probe("X05", "Split rotation across weeks", "PPL with 2 lifts/week; PPL ×4; Upper/Lower ×3", "PPL×2 week1 \(wk1) week2 \(wk2); PPL×4 \(seq4); U/L×3 \(ul3); PPL×2 sequence \(seq2)", "the rotation continues across weeks so every session type recurs (legs trained)", wk1 != wk2 || wk1.contains("legs"), "AdaptiveModels.swift:85-101 + Planning.swift:331-334 (sequence restarts every week)")
}
do {
    let th = Workout(date: nextMonday, kind: .threshold, minutes: 70)
    // remediation copy: the live coach (RideCoach.intervalPlan(for:), SwiftUI file, not compiled on Linux) returns
    // Workout.liveIntervalPlan unchanged — compared here with the plan's own structure (same criterion)
    let lp = th.liveIntervalPlan
    let ok06 = lp.map { $0.repeats == (th.effectiveIntervalReps ?? 0) && $0.workSec == th.kind.intervalWorkMinutes * 60 && $0.restSec == th.kind.intervalRestMinutes * 60 } ?? false
    probe("X06", "Threshold interval structure: plan vs live ride coach", "Threshold session, 70 min, not adjusted", "plan/steps: \(th.effectiveIntervalReps ?? 0) × \(th.kind.intervalWorkMinutes) min, \(th.kind.intervalRestMinutes) min easy; live plan: \(lp.map { "\($0.repeats) × \($0.workSec / 60) min / \($0.restSec / 60) min" } ?? "none")", "the ride coach executes the planned structure", ok06, "Models.swift Workout.liveIntervalPlan; RideDashboard.swift RideCoach.intervalPlan(for:)")
    let fitsV = AdaptiveRules.intervalsFit(kind: .vo2, reps: 6, minutes: 60), fitsT = AdaptiveRules.intervalsFit(kind: .threshold, reps: 4, minutes: 70), fitsT5 = AdaptiveRules.intervalsFit(kind: .threshold, reps: 5, minutes: 70)
    probe("X07", "Interval progression must fit the planned minutes", "default VO2 60 min (5×3/3), threshold 70 min (3×8/3)", "VO2 6 reps fits=\(fitsV); threshold 4 reps fits=\(fitsT); 5 reps fits=\(fitsT5)", "documented behaviour (+1 interval only inside the minutes)", true, "AdaptationEngine.swift:96-98, 524-526")
}
do {
    var p = RiderProfile(); p.age = 35
    let z = p.hrZones.map { "\($0.lo)-\($0.hi.map(String.init) ?? "max")" }.joined(separator: ", ")
    var q = p; q.hrZoneMethod = .lthr; q.lthr = 170
    let zl = q.hrZones.map { "\($0.lo)-\($0.hi.map(String.init) ?? "max")" }.joined(separator: ", ")
    var o = p; o.age = 62
    probe("X08", "HR zones", "age 35 (max HR est.), LTHR 170, age 62", "maxHR(35)=\(p.estimatedMaxHR): \(z) | LTHR 170: \(zl) | maxHR(62)=\(o.estimatedMaxHR)", "Tanaka 208−0.7·age; 5 zones at 60/70/80/90 % HRmax or 85/89/94/100 % LTHR", p.estimatedMaxHR == 184 && o.estimatedMaxHR == 165, "Models.swift:82-99")
}
do {
    var p = RiderProfile(); p.weightKg = 75; p.level = .beginner; p.ftpHow = .assumed; p.refreshAssumption()
    var u = RiderProfile(); u.ftpW = 300; u.ftpHow = .entered
    probe("X09", "FTP estimation and confidence", "assumed FTP 75 kg beginner; best 20-min 260 W; entered 300 W (no test)", "assumed \(p.ftpW) W (\(p.ftpConfidence.rawValue)); proposed from 260 W best-20 = \(Store.proposedFTP(best20: 260)) W; entered 300 W → confidence \(u.ftpConfidence.rawValue), prescription FTP \(u.prescriptionFTP) W", "95 % of 20-min (Allen & Coggan); unverified FTP → targets 5 % lower", Store.proposedFTP(best20: 260) == 247 && u.prescriptionFTP == 285, "Models.swift:100, 1069; DesignSystem.swift:166-189")
}
do {
    var p = RiderProfile(); p.age = 35
    let zs = [120, 135, 150, 160, 175].map { "\($0) bpm→Z\(TrainingAnalyzer.hrZone($0, profile: p)) (CR-10 \(Int(TrainingAnalyzer.hrZoneEffort[TrainingAnalyzer.hrZone($0, profile: p) - 1])))" }
    probe("X10", "Ride load without a rating (average HR → CR-10 anchor × minutes)", "age 35, average HR of a ride", zs.joined(separator: "; "), "labelled estimate, used for load only", true, "AdaptationEngine.swift:203-204, 230, 386-389")
    let ifs = [0.6, 0.8, 0.9, 1.0, 1.1].map { "IF \($0)→\(Int(TrainingAnalyzer.effort(intensityFactor: $0)))" }
    probe("X11", "Ride load from VERIFIED power (IF → CR-10)", "IF = NP/FTP", ifs.joined(separator: "; "), "only when powerVerified == true", true, "AdaptationEngine.swift:205-206, 229")
}
do {
    let e = TrainingAnalyzer.e1RM(weightKg: 100, reps: 5)
    probe("X12", "Estimated 1RM (Epley)", "100 kg × 5", String(format: "%.1f kg", e), "100 × (1 + 5/30) = 116.7", abs(e - 116.67) < 0.1, "AdaptationEngine.swift:208")
}
do {
    var p = hybridProfile { $0.strengthSplit = .fullBody }; p.liftDaysPerWeek = 2
    let monday = nextMonday
    let lifts = (1...12).map { k -> StrengthSession in var s = log(0, backSquat, sets: 3, reps: 8, kg: 60, rpe: 7); s.date = cal.date(byAdding: .day, value: -7 * k + 2, to: monday)!; return s }
    func deload(_ weeks: Int) -> Bool {
        let w = Workout(date: cal.date(byAdding: .day, value: 1, to: monday)!, kind: .strength, minutes: 45, strengthFocus: .fullBody)
        let logs = lifts.filter { $0.date >= cal.date(byAdding: .day, value: -7 * weeks, to: monday)! && $0.date < monday }
        var c = pctx(logs); c.plan = [w]; c.profile = p
        return StrengthPlanner.weekContext(for: w, ctx: c).deload
    }
    let res = (1...9).map { "\($0) wk→\(deload($0) ? "DELOAD" : "-")" }
    probe("X13", "Planned deload cadence", "consecutive weeks with detailed logs before the session's week", res.joined(separator: ", "), "a lighter week after 3 loading weeks (3:1), repeating", true, "StrengthPlanner.swift:438-446")
}
do {
    let s = Workout(date: nextMonday, kind: .strength, minutes: 45, strengthFocus: .lower)
    let r = Workout(date: cal.date(byAdding: .day, value: 1, to: nextMonday)!, kind: .endurance, minutes: 120)
    let r2 = Workout(date: cal.date(byAdding: .day, value: 1, to: nextMonday)!, kind: .endurance, minutes: 90)
    probe("X14", "Key-ride definition for interference", "Zone 2 endurance 120 min vs 90 min the day after a leg session", "120 min key=\(StrengthPlanner.isKeyRide(r)); 90 min key=\(StrengthPlanner.isKeyRide(r2)); lower focus loadsLegs=\(s.strengthFocus!.loadsLegs)", "hard (Z≥3), long-kind or ≥ 120 min rides are protected", StrengthPlanner.isKeyRide(r) && !StrengthPlanner.isKeyRide(r2), "StrengthPlanner.swift:412")
}
do {
    let c = CheckIn(performance: 14, effort: -3)
    probe("X15", "Check-in input validation", "performance 14, effort −3", "stored performance \(c.performance), effort \(c.effort)", "clamped to 1…10", c.performance == 10 && c.effort == 1, "AdaptiveModels.swift:45-48")
}
do {
    let ws = (0..<4).map { k in StrengthPlanner.weeklySets(region: "lower", ctx: { var c = pctx([], exp: [.beginner, .intermediate, .advanced, .advanced][k]); c.profile.priority = [.balanced, .balanced, .cycling, .strength][k]; return c }(), week: StrengthPlanner.WeekContext(hardRideNext: nil, hardRideSameDayAfter: nil, hardRideBefore: nil, highCyclingLoad: false, highLoadReason: nil, deload: false, deloadReason: nil, sessionIndex: 0, sessionsHitting: [:])) }
    probe("X16", "Weekly lower-body set target (before session share)", "beginner/balanced, intermediate/balanced, advanced/cycling, advanced/strength", ws.map { String(format: "%.1f", $0) }.joined(separator: ", "), "documented scaling (8/12/16 × priority 0.5–1.0)", true, "StrengthPlanner.swift:475-488")
}

do {
    var p = hybridProfile { $0.strengthSplit = .fullBody }; p.trainingMode = .cycling
    func acwr(startDaysAgo n: Int) -> (Double?, [String]) {
        var rides: [RideRecord] = []
        for k in 1...n { var r = RideRecord(start: dayDate(-k, hour: 7), durationS: 3600, distanceM: 27000, recorder: .phone, sources: []); r.checkIn = CheckIn(performance: 7, effort: 5, at: dayDate(-k, hour: 8)); rides.append(r) }
        let inp = AdaptationInput(profile: p, plan: [], rides: rides, strength: [], availability: WeeklyAvailability.suggested(for: p), now: realNow, calendar: cal)
        let a = TrainingAnalyzer.analyze(inp)
        return (a.acwr, a.fatigue.map { $0.id })
    }
    let res = [22, 24, 26, 28, 35].map { n -> String in let (r, f) = acwr(startDaysAgo: n); return "\(n) days: ACWR \(r.map { String(format: "%.2f", $0) } ?? "n/a") flags \(f)" }
    let ratios = [22, 24, 26, 28, 35].compactMap { acwr(startDaysAgo: $0).0 }
    probe("X17", "Acute:chronic load ratio with identical daily load", "one 60-min ride rated effort 5 EVERY day, history of 22–35 days", res.joined(separator: "; "), "ACWR within 0.9–1.1 for perfectly constant load (no artefact)", ratios.allSatisfy { $0 >= 0.9 && $0 <= 1.1 }, "AdaptationEngine.swift:249-255 (acute = today + 6 days; chronic = sum of days 7–34 ÷ 4 even when only ~2–3 weeks exist), 324-327")
    // X19: a realistic, perfectly repeated weekly pattern (Tue ride 86 min, Wed + Thu lift 60 min, Sat ride 128 min, Sun ride 86 min, all effort 6)
    func pattern(startDaysAgo n: Int, evalOffset e: Int) -> (Double?, [String]) {
        var rides: [RideRecord] = [], lifts: [StrengthSession] = []
        let evalNow = dayDate(-e, hour: 21)
        for k in (e + 1)...n {
            let d = dayDate(-k, hour: 7); let wd = (cal.component(.weekday, from: d) + 5) % 7
            if [1, 5, 6].contains(wd) { var r = RideRecord(start: d, durationS: (wd == 5 ? 128 : 86) * 60, distanceM: 30000, recorder: .phone, sources: []); r.checkIn = CheckIn(performance: 7, effort: 6, at: d); rides.append(r) }
            if [2, 3].contains(wd) { var l = StrengthSession(date: dayDate(-k, hour: 18), minutes: 60, focus: .fullBody, rpe: 7); l.checkIn = CheckIn(performance: 7, effort: 6, at: l.date); lifts.append(l) }
        }
        let inp = AdaptationInput(profile: p, plan: [], rides: rides, strength: lifts, availability: WeeklyAvailability.suggested(for: p), now: evalNow, calendar: cal)
        let a = TrainingAnalyzer.analyze(inp); return (a.acwr, a.fatigue.map { $0.id })
    }
    var flagged: [String] = []
    for start in 21...30 { for e in 0...6 { let (r, f) = pattern(startDaysAgo: start + e, evalOffset: e); if f.contains("load-spike") { flagged.append("history \(start) d, evaluated \(e) d ago: ACWR \(r.map { String(format: "%.2f", $0) } ?? "-")") } } }
    probe("X19", "Load-spike flag for a perfectly repeated week (new user)", "3 rides + 2 lifts in the same weekly pattern, all rated effort 6, history 21–30 days, evaluated on each weekday", flagged.isEmpty ? "never flagged" : "flagged \(flagged.count) of 70 evaluations, e.g. " + flagged.prefix(4).joined(separator: "; "), "a perfectly repeated week is never a 'load spike'", flagged.isEmpty, "AdaptationEngine.swift:249-255, 324-327")
}
do {
    let bp = cat.first { $0.id == "ex-056" }!
    let t = WorkoutTemplate(name: "Push", focus: .push, entries: [ExerciseEntry(exercise: bp, sets: (0..<3).map { _ in SetEntry(reps: 8, weightKg: 60) })], updatedAt: Date(timeIntervalSince1970: 0))
    var w = Workout(date: dayDate(2, hour: 8), kind: .strength, minutes: 45, strengthFocus: .push); w.templateId = t.id
    func dec(_ n: Int) -> String {
        let logs = [3, 6].map { d -> StrengthSession in var l = log(d, bp, sets: n, reps: 8, kg: 60, rpe: 7); l.templateId = t.id; return l }
        var p = hybridProfile { _ in }; p.strengthSplit = nil
        let inp = AdaptationInput(profile: p, plan: [w], rides: [], strength: logs, availability: WeeklyAvailability.suggested(for: p), equipment: fullGym, catalogue: cat, templates: [t], originalEntries: [w.id: t.prefilled(from: logs.first)], now: realNow, calendar: cal)
        return AdaptationEngine.strengthDecision(t.prefilled(from: logs.first)[0], session: w, input: inp).map { $0.summary } ?? "no change"
    }
    let full = dec(3), cut = dec(2)
    probe("X18", "Routine progression after a coach-imposed set cut", "routine Bench press 3×8 @ 60 kg; last two sessions done as 3×8 vs 2×8 (the coach had removed a set), RPE 7", "3×8 → \(full); 2×8 (coach cut) → \(cut)", "doing exactly what the coach asked should not count as an incomplete session", cut != "no change", "AdaptationEngine.swift:603-607 (target = the routine's own sets)")
    // X18-b (remediation probe, X18 kept unchanged): X18's logs carry no record that the coach removed the set (no link
    // to the planned session), so the engine cannot tell a coach cut from an unfinished session. Here the same two
    // 2×8 logs are linked to their planned sessions, whose planned entries were cut to 2 sets by the coach (F-21 / G-12);
    // a genuinely unfinished session (planned 3 sets, done 2) must still not progress.
    func decLinked(plannedSets: Int) -> String {
        var past: [Workout] = []; var logs: [StrengthSession] = []
        for d in [3, 6] {
            var pw = Workout(date: dayDate(-d, hour: 8), kind: .strength, minutes: 45, strengthFocus: .push); pw.templateId = t.id
            pw.plannedEntries = [ExerciseEntry(exercise: bp, sets: (0..<plannedSets).map { _ in SetEntry(reps: 8, weightKg: 60) })]
            past.append(pw)
            var l = log(d, bp, sets: 2, reps: 8, kg: 60, rpe: 7); l.templateId = t.id; l.workoutId = pw.id; logs.append(l)
        }
        var p = hybridProfile { _ in }; p.strengthSplit = nil
        if HarnessFixtures.screened { var sc = HealthScreen(); sc.answeredAt = Date(timeIntervalSince1970: 1_790_000_000); p.healthScreen = sc }
        let inp = AdaptationInput(profile: p, plan: past + [w], rides: [], strength: logs, availability: WeeklyAvailability.suggested(for: p), equipment: fullGym, catalogue: cat, templates: [t], originalEntries: [w.id: t.prefilled(from: logs.first)], now: realNow, calendar: cal)
        return AdaptationEngine.strengthDecision(t.prefilled(from: logs.first)[0], session: w, input: inp).map { $0.summary } ?? "no change"
    }
    // X21 (remediation probe, added after run s10): a routine's load goes up only after TWO sessions at the current
    // weight (as the planner, G-02) — not after every session because the previous one was also completed at a lower weight
    func decWeights(_ kgs: [Double]) -> String {
        let logs = zip([3, 6], kgs).map { (d, kg) -> StrengthSession in var l = log(d, bp, sets: 3, reps: 8, kg: kg, rpe: 7); l.templateId = t.id; return l }
        var p = hybridProfile { _ in }; p.strengthSplit = nil
        if HarnessFixtures.screened { var sc = HealthScreen(); sc.answeredAt = Date(timeIntervalSince1970: 1_790_000_000); p.healthScreen = sc }
        let inp = AdaptationInput(profile: p, plan: [w], rides: [], strength: logs, availability: WeeklyAvailability.suggested(for: p), equipment: fullGym, catalogue: cat, templates: [t], originalEntries: [w.id: t.prefilled(from: logs.first)], now: realNow, calendar: cal)
        return AdaptationEngine.strengthDecision(t.prefilled(from: logs.first)[0], session: w, input: inp).map { $0.summary } ?? "no change"
    }
    let oneAt = decWeights([62.5, 60]), twoAt = decWeights([62.5, 62.5])
    probe("X21", "Routine load progression needs two sessions at the current weight (remediation probe)", "routine Bench press 3×8; last two sessions 3×8 RPE 7 at 60 then 62.5 kg vs 62.5 and 62.5 kg", "60 → 62.5 kg: \(oneAt); 62.5 twice: \(twoAt)", "no increase after a single session at the new weight; one step after two", oneAt == "no change" && twoAt != "no change", "AdaptationEngine.strengthDecision (atCurrent)")
    let cutLinked = decLinked(plannedSets: 2), unfinished = decLinked(plannedSets: 3)
    probe("X18-b", "Routine progression after a coach-imposed set cut, logs linked to their planned sessions (remediation probe; X18 kept)", "routine Bench press 3×8 @ 60 kg; last two sessions logged 2×8 RPE 7 and linked to planned sessions the coach had cut to 2 sets; control: planned 3 sets, done 2", "coach cut → \(cutLinked); unfinished (planned 3, done 2) → \(unfinished)", "the coach-cut sessions count as complete (progression); an unfinished session does not", cutLinked != "no change" && unfinished == "no change", "AdaptationEngine.strengthDecision complete() (F-21: linked logs judged against their planned sets)")
}

do {
    func top(_ slot: MovementSlot, exp: StrengthPrefs.Experience, eq: EquipmentProfile, goal: StrengthPrefs.Goal = .general) -> [String] {
        var c = pctx([], exp: exp); c.equipment = eq; c.prefs.goal = goal
        var used = Set<String>(); var out: [String] = []
        for _ in 0..<4 { if let e = StrengthPlanner.pick(.init(slot: slot, role: .main), ctx: c, used: used) { out.append(e.name); used.insert(e.id) } }
        return out
    }
    let txt = "squat/beginner/full gym: \(top(.squat, exp: .beginner, eq: fullGym)); squat/intermediate/full gym: \(top(.squat, exp: .intermediate, eq: fullGym)); hinge/intermediate/full gym: \(top(.hinge, exp: .intermediate, eq: fullGym)); hinge/intermediate/dumbbells+bench: \(top(.hinge, exp: .intermediate, eq: EquipmentProfile(owned: ["dumbbell", "bench"]))); squat/advanced/strength goal: \(top(.squat, exp: .advanced, eq: fullGym, goal: .strength))"
    probe("X20", "Main-lift choice order (score, ties broken by name)", "no favourites, routines or history; main-lift slot", txt, "informational: shows which exercise wins each slot", true, "StrengthPlanner.swift:320-363 (sorted by score, then name)")
}

// MARK: run the profiles
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./out")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
var reports: [Report] = []
let probesOnly = CommandLine.arguments.contains("--probes-only")
let onlyCases = ProcessInfo.processInfo.environment["CASES"].map { Set($0.split(separator: ",").map(String.init)) }
for c in allCases() where !probesOnly && (onlyCases?.contains(c.id) ?? true) {
    let (rep, _) = Runner(c).run()
    reports.append(rep)
    try! enc.encode(rep).write(to: outDir.appendingPathComponent("\(c.id).json"))
    let failed = rep.criteria.filter { !$0.pass }
    print("\(c.id) \(rep.pass ? "PASS" : "FAIL") — \(c.title) — failed: \(failed.map { "\($0.id)[\($0.kind)]" }.joined(separator: ", "))")
}
try! enc.encode(probes).write(to: outDir.appendingPathComponent("probes.json"))
for p in probes { print("\(p.id) \(p.pass ? "PASS" : "FAIL") \(p.rule): \(p.observed)") }
print("profiles: \(reports.count), pass \(reports.filter { $0.pass }.count), fail \(reports.filter { !$0.pass }.count); probes \(probes.count), pass \(probes.filter { $0.pass }.count)")
print("run at \(ISO8601DateFormatter().string(from: realNow)) (today \(ds(today)), next Monday \(ds(nextMonday)))")
