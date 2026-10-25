import Foundation

// MARK: - Hybrid Athlete Mode (0.6.0, phase 1). Phone-side only: nothing here travels over the Link protocol.

enum TrainingMode: String, Codable, CaseIterable {
    case cycling, strength, hybrid
    var title: String { switch self { case .cycling: return "Cycling"; case .strength: return "Strength"; case .hybrid: return "Hybrid Athlete" } }
    var hint: String {
        switch self {
        case .cycling: return "rides and the occasional off-bike session"
        case .strength: return "lifting first; rides are optional conditioning"
        case .hybrid: return "one coach for your cycling and your lifting"
        }
    }
    var includesLifting: Bool { self != .cycling }
    var includesCycling: Bool { self != .strength }
}

enum TrainingPriority: String, Codable, CaseIterable {
    case cycling, strength, balanced
    var title: String { switch self { case .cycling: return "Cycling"; case .strength: return "Strength"; case .balanced: return "Balanced" } }
}

/// Body region of a strength session as the rider LOGGED it. Only these labels are ever used for balance; nothing
/// about muscles or movement patterns is inferred from them (that needs the detailed exercise log, phase 2).
enum StrengthFocus: String, Codable, CaseIterable {
    case fullBody, upper, lower, push, pull, custom
    var title: String { switch self { case .fullBody: return "Full body"; case .upper: return "Upper body"; case .lower: return "Lower body"; case .push: return "Push"; case .pull: return "Pull"; case .custom: return "Custom" } }
    var icon: String { switch self { case .fullBody: return "figure.strengthtraining.traditional"; case .upper: return "figure.arms.open"; case .lower: return "figure.step.training"; case .push: return "arrow.up.circle"; case .pull: return "arrow.down.circle"; case .custom: return "square.and.pencil" } }
    /// A lower-body or full-body session loads the legs; the planner keeps it away from hard rides when it can.
    var loadsLegs: Bool { self == .lower || self == .fullBody }
    var isUpperRegion: Bool { self == .upper || self == .push || self == .pull }
}

/// One strength session: a quick log (focus, duration, effort) or an Apple Health import. Detailed sets / reps /
/// weights / supersets / templates are phase 2 and have no fields here yet — nothing is pretended.
struct StrengthSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var minutes: Int
    var focus: StrengthFocus
    var customName: String = ""
    /// RPE 1–10 (easy ≈ 4, moderate ≈ 6, hard ≈ 8). nil = not stated (Health imports).
    var rpe: Int? = nil
    var notes: String = ""
    /// "manual" or "Apple Health"
    var source: String = "manual"
    var healthUUID: String? = nil

    init(id: UUID = UUID(), date: Date, minutes: Int, focus: StrengthFocus, customName: String = "", rpe: Int? = nil, notes: String = "", source: String = "manual", healthUUID: String? = nil) {
        self.id = id; self.date = date; self.minutes = minutes; self.focus = focus; self.customName = customName; self.rpe = rpe; self.notes = notes; self.source = source; self.healthUUID = healthUUID
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        focus = (try? c.decodeIfPresent(StrengthFocus.self, forKey: .focus)) ?? .custom
        customName = try c.decodeIfPresent(String.self, forKey: .customName) ?? ""
        rpe = try c.decodeIfPresent(Int.self, forKey: .rpe)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "manual"
        healthUUID = try c.decodeIfPresent(String.self, forKey: .healthUUID)
    }

    var title: String { focus == .custom ? (customName.isEmpty ? "Strength" : customName) : "Strength · \(focus.title)" }
    /// true when the rider named a body region; Health imports and custom names say nothing about regions.
    var regionKnown: Bool { focus != .custom }
    var effortLabel: String { guard let r = rpe else { return "effort not stated" }; return r <= 4 ? "easy (RPE \(r))" : r <= 7 ? "moderate (RPE \(r))" : "hard (RPE \(r))" }
    /// Same session logged twice (quick log + Health import, or two imports): start within ±2 min and durations close.
    static func sameSession(_ a: StrengthSession, _ b: StrengthSession) -> Bool {
        abs(a.date.timeIntervalSince(b.date)) <= 120 && abs(a.minutes - b.minutes) <= max(5, min(a.minutes, b.minutes) / 5)
    }
}

// MARK: - Evaluation: cycling and strength separately, then together
struct SportProgress: Equatable {
    var sessionsDone: Int
    var sessionsTarget: Int
    var minutesDone: Int
    var minutesTarget: Int
    var minutesPlanned: Int
    var note: String
    var ratio: Double { minutesTarget > 0 ? Double(minutesDone) / Double(minutesTarget) : 0 }
}

struct CoachFinding: Equatable, Identifiable {
    enum Severity: String { case ok, info, gap, conflict }
    var id: String
    var severity: Severity
    var text: String
}

struct HybridAssessment: Equatable {
    var cycling: SportProgress?
    var strength: SportProgress?
    var findings: [CoachFinding]
    var recommendation: String          // ONE line for the top of Home
    var next: Workout?                  // the session the line refers to (today's, or the first missing one)
    var why: [String]                   // plain-language reasons, only from available evidence
    var combined: String                // "on track" / "cycling behind" / …
}

enum HybridCoach {
    /// Evaluates the current week from real data only: rides, strength logs, the plan and the rider's stated targets.
    /// `now` and `calendar` are injectable for tests.
    static func assess(profile p: RiderProfile, plan: [Workout], rides: [RideRecord], strength: [StrengthSession], availability a: WeeklyAvailability, now: Date = Date(), calendar cal: Calendar = .current) -> HybridAssessment {
        let today = cal.startOfDay(for: now)
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: today)!
        let nextMonday = cal.date(byAdding: .day, value: 7, to: monday)!
        let week = plan.filter { $0.date >= monday && $0.date < nextMonday }
        let weekRides = rides.filter { $0.start >= monday && $0.start < nextMonday && !$0.demo }
        let weekLifts = strength.filter { $0.date >= monday && $0.date < nextMonday }
        var findings: [CoachFinding] = []
        var why: [String] = []

        // --- cycling
        var cyc: SportProgress? = nil
        if p.trainingMode.includesCycling {
            let done = weekRides.reduce(0) { $0 + $1.durationS } / 60
            let planned = week.filter { $0.kind.isRide && !$0.skipped }.reduce(0) { $0 + $1.minutes }
            let target = p.hoursPerWeek * 60
            let ridesTarget = max(p.cyclingDaysPerWeek, a.cycleDays)
            var note = "\(weekRides.count) of \(ridesTarget) rides · \(Fmt.duration(minutes: done)) of \(Fmt.duration(minutes: target))"
            // intensity mix from real zone data only
            let zs = weekRides.map { $0.zoneSeconds }.filter { $0.count == 7 && $0.reduce(0, +) > 0 }
            if !zs.isEmpty {
                let tot = zs.reduce(0) { $0 + $1.reduce(0, +) }
                let hard = zs.reduce(0) { $0 + $1[2...].reduce(0, +) }
                let pct = tot > 0 ? hard * 100 / tot : 0
                note += " · \(pct) % at Zone 3 or above"
                if pct > 50, weekRides.count >= 2 { findings.append(.init(id: "cyc-intensity", severity: .info, text: "More than half of this week's riding was Zone 3 or harder; the plan keeps the next ride easy.")) }
            } else if !weekRides.isEmpty { note += " · intensity unknown (no power zones recorded)" }
            cyc = SportProgress(sessionsDone: weekRides.count, sessionsTarget: ridesTarget, minutesDone: done, minutesTarget: target, minutesPlanned: planned, note: note)
            let daysLeft = 7 - wd
            let remainingPlanned = week.filter { $0.kind.isRide && !$0.skipped && !$0.done && cal.startOfDay(for: $0.date) >= today }.count
            if weekRides.count + remainingPlanned < ridesTarget {
                findings.append(.init(id: "cyc-freq", severity: .gap, text: "Cycling: \(weekRides.count) ride\(weekRides.count == 1 ? "" : "s") done and \(remainingPlanned) still planned against \(ridesTarget) per week — one ride is missing."))
            } else if weekRides.count >= ridesTarget { findings.append(.init(id: "cyc-ok", severity: .ok, text: "Cycling: \(weekRides.count) rides this week — frequency on target.")) }
            if planned > target { findings.append(.init(id: "cyc-over", severity: .conflict, text: "Planned riding (\(Fmt.duration(minutes: planned))) is over your \(p.hoursPerWeek) h cycling budget; see the Plan suggestions.")) }
            _ = daysLeft
        }

        // --- strength
        var str: SportProgress? = nil
        if p.trainingMode.includesLifting {
            let done = weekLifts.reduce(0) { $0 + $1.minutes }
            let planned = week.filter { $0.kind == .strength && !$0.skipped }.reduce(0) { $0 + $1.minutes }
            let target = p.liftingHoursPerWeek * 60
            let liftsTarget = max(p.liftDaysPerWeek, a.liftDays)
            var note = "\(weekLifts.count) of \(liftsTarget) sessions · \(Fmt.duration(minutes: done))" + (target > 0 ? " of \(Fmt.duration(minutes: target))" : "")
            let remainingPlanned = week.filter { $0.kind == .strength && !$0.skipped && !$0.done && cal.startOfDay(for: $0.date) >= today }.count
            if weekLifts.count + remainingPlanned < liftsTarget {
                findings.append(.init(id: "str-freq", severity: .gap, text: "Strength: \(weekLifts.count) session\(weekLifts.count == 1 ? "" : "s") done and \(remainingPlanned) still planned against \(liftsTarget) per week — a lift is missing."))
            } else if liftsTarget > 0, weekLifts.count >= liftsTarget { findings.append(.init(id: "str-ok", severity: .ok, text: "Strength: \(weekLifts.count) sessions this week — frequency on target.")) }
            if target > 0, planned > target { findings.append(.init(id: "str-over", severity: .conflict, text: "Planned lifting (\(Fmt.duration(minutes: planned))) is over your \(p.liftingHoursPerWeek) h lifting budget.")) }
            // push / pull balance — only from Push / Pull logs of the last 28 days
            let recent = strength.filter { $0.date >= cal.date(byAdding: .day, value: -28, to: today)! }
            let push = recent.filter { $0.focus == .push }.count, pull = recent.filter { $0.focus == .pull }.count
            if push + pull >= 3 {
                if push >= 2 * pull + 1 { findings.append(.init(id: "str-pushpull", severity: .gap, text: "Push/pull: \(push) push vs \(pull) pull sessions in 4 weeks — add a pull session.")) }
                else if pull >= 2 * push + 1 { findings.append(.init(id: "str-pushpull", severity: .gap, text: "Push/pull: \(pull) pull vs \(push) push sessions in 4 weeks — add a push session.")) }
                else { findings.append(.init(id: "str-pushpull-ok", severity: .ok, text: "Push/pull balance looks even (\(push) push, \(pull) pull in 4 weeks).")) }
                note += " · push \(push) / pull \(pull)"
            } else if recent.contains(where: { $0.regionKnown }) {
                let lower = recent.filter { $0.focus == .lower }.count, upper = recent.filter { $0.focus.isUpperRegion }.count, full = recent.filter { $0.focus == .fullBody }.count
                note += " · 4 wk: \(lower) lower, \(upper) upper, \(full) full body"
                if lower == 0, upper >= 2 { findings.append(.init(id: "str-lower", severity: .gap, text: "No lower-body session logged in 4 weeks (\(upper) upper-body); legs matter for riding too.")) }
            }
            findings.append(.init(id: "str-coverage", severity: .info, text: "Squat / hinge / single-leg / core coverage and exercise progression: not known from quick logs — detailed exercise logging arrives in a later build."))
            str = SportProgress(sessionsDone: weekLifts.count, sessionsTarget: liftsTarget, minutesDone: done, minutesTarget: target, minutesPlanned: planned, note: note)
        }

        // --- scheduling conflicts (two hard days back to back) from the plan
        let hardDays = week.filter { !$0.skipped && (($0.kind.zone >= 3 && $0.kind.isRide) || ($0.kind == .strength && ($0.strengthFocus?.loadsLegs ?? false))) }.map { cal.startOfDay(for: $0.date) }
        let sortedHard = Array(Set(hardDays)).sorted()
        for i in 1..<max(1, sortedHard.count) where cal.dateComponents([.day], from: sortedHard[i - 1], to: sortedHard[i]).day == 1 {
            findings.append(.init(id: "sched-\(i)", severity: .conflict, text: "\(sortedHard[i - 1].shortDay) and \(sortedHard[i].shortDay) are both hard days (hard ride or leg session back to back). Move one if you can."))
            break
        }

        // --- recommendation: today's session first; otherwise what is missing
        let todays = week.filter { cal.isDate($0.date, inSameDayAs: today) && !$0.done && !$0.skipped }.sorted { $0.sequence < $1.sequence }
        var next: Workout? = todays.first
        var line: String
        if let t = next {
            line = Coach.todayLine(t)
            if todays.count > 1 { line += " Then \(todays[1].displayTitle.lowercased()) (\(Fmt.duration(minutes: todays[1].minutes)))." }
            why.append(t.why)
        } else if let t = week.first(where: { cal.isDate($0.date, inSameDayAs: today) }), t.done {
            line = "Today: done — \(t.displayTitle.lowercased()) completed."
            why.append("Today's session is already recorded; the rest is recovery.")
        } else {
            line = "Today: nothing planned."
            why.append("No session is planned for today.")
        }
        if let g = findings.first(where: { $0.severity == .gap }) {
            why.append(g.text)
            if next == nil || next?.kind == .rest {
                // suggest the missing sport on the next free day
                if g.id.hasPrefix("str"), let free = week.first(where: { $0.kind == .rest && cal.startOfDay(for: $0.date) >= today }) {
                    next = Workout(date: free.date, kind: .strength, minutes: 30, strengthFocus: g.id == "str-lower" ? .lower : .fullBody)
                    line = "Next: a 30 min \(next!.strengthFocus!.title.lowercased()) strength session on \(free.date.shortDay) — a lift is missing this week."
                } else if g.id.hasPrefix("cyc"), let free = week.first(where: { $0.kind == .rest && cal.startOfDay(for: $0.date) >= today }) {
                    next = Workout(date: free.date, kind: .endurance, minutes: 45)
                    line = "Next: a 45 min endurance ride on \(free.date.shortDay) — a ride is missing this week."
                }
            }
        }
        if let c = cyc { why.append("Cycling this week: \(c.note).") }
        if let s = str { why.append("Strength this week: \(s.note).") }
        why.append("Priority: \(p.priority.title.lowercased()); mode: \(p.trainingMode.title.lowercased()).")
        if p.trainingMode.includesLifting { why.append("Hard rides and leg sessions are kept on separate days when your availability allows it.") }
        why.append("No sleep, HRV or recovery source is connected, so recovery is not part of this recommendation.")

        let gaps = findings.filter { $0.severity == .gap }
        let combined: String
        if gaps.isEmpty { combined = findings.contains { $0.severity == .conflict } ? "on track · check the schedule" : "on track" }
        else if gaps.allSatisfy({ $0.id.hasPrefix("cyc") }) { combined = "cycling behind" }
        else if gaps.allSatisfy({ $0.id.hasPrefix("str") }) { combined = "strength behind" }
        else { combined = "both behind" }
        return HybridAssessment(cycling: cyc, strength: str, findings: findings, recommendation: line, next: next, why: why, combined: combined)
    }
}
