import Foundation

// MARK: - Hybrid Athlete Mode (0.6.0 phase 1, 0.7.0 phase 2). Phone-side only: nothing here travels over the Link protocol.

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

/// Body region / routine type of a strength session as the rider LOGGED or PLANNED it. Only these labels are used for
/// region balance; muscle or movement coverage comes from detailed exercise logs alone (Strength.swift).
enum StrengthFocus: String, Codable, CaseIterable {
    case fullBody, upper, lower, push, pull, legs, custom
    /// Short label for pickers (fits a 3-column grid).
    var short: String { switch self { case .fullBody: return "Full Body"; case .upper: return "Upper"; case .lower: return "Lower"; case .push: return "Push"; case .pull: return "Pull"; case .legs: return "Legs"; case .custom: return "Custom" } }
    var title: String { switch self { case .fullBody: return "Full body"; case .upper: return "Upper body"; case .lower: return "Lower body"; case .push: return "Push"; case .pull: return "Pull"; case .legs: return "Legs"; case .custom: return "Custom routine" } }
    var icon: String { switch self { case .fullBody: return "figure.strengthtraining.traditional"; case .upper: return "figure.arms.open"; case .lower: return "figure.step.training"; case .push: return "arrow.up.circle"; case .pull: return "arrow.down.circle"; case .legs: return "figure.walk"; case .custom: return "square.and.pencil" } }
    /// A lower-body, legs or full-body session loads the legs; the planner keeps it away from hard rides when it can.
    var loadsLegs: Bool { self == .lower || self == .fullBody || self == .legs }
    var isUpperRegion: Bool { self == .upper || self == .push || self == .pull }
    /// The six quick-log choices (Legs is a planning type; quick logs use Lower).
    static let quickLog: [StrengthFocus] = [.fullBody, .upper, .lower, .push, .pull, .custom]
}

/// One strength session: a quick log (focus, duration, effort), a detailed log (exercises, sets, supersets) or an
/// Apple Health import. `exercises == nil` means a quick log — nothing about movements is known from it.
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
    /// 0.7.0: detailed exercise log (nil = quick log) and the template it came from.
    var exercises: [ExerciseEntry]? = nil
    var templateId: UUID? = nil
    /// Set when this log was created for a planned session (so the plan entry is marked done, not duplicated).
    var workoutId: UUID? = nil
    /// 0.8.0 workout mode: when the session was started, when it was finished (nil while in progress), accumulated
    /// paused seconds and whether it is paused now. A session that is in progress lives in `Store.activeSession`,
    /// never in the completed list — a template or a started-but-unfinished session never counts as completed.
    var startedAt: Date? = nil
    var finishedAt: Date? = nil
    var pausedSeconds: Int = 0
    var pausedAt: Date? = nil
    /// Adaptive coach: the rider's post-session check-in (performance, effort, pain, note). nil = not given.
    var checkIn: CheckIn? = nil
    /// Quality release: true = the rider saved this as an extra session (never linked to a planned one); a record a
    /// migration could not vouch for waits for the rider's review (not counted until confirmed); what the migration
    /// changed, with the original values. All stored only when set, so older logs encode as before.
    var unplanned: Bool? = nil
    var needsReview: Bool? = nil
    var migrationNote: String? = nil
    var awaitingReview: Bool { needsReview == true }

    init(id: UUID = UUID(), date: Date, minutes: Int, focus: StrengthFocus, customName: String = "", rpe: Int? = nil, notes: String = "", source: String = "manual", healthUUID: String? = nil, exercises: [ExerciseEntry]? = nil, templateId: UUID? = nil, workoutId: UUID? = nil) {
        self.id = id; self.date = date; self.minutes = minutes; self.focus = focus; self.customName = customName; self.rpe = rpe; self.notes = notes; self.source = source; self.healthUUID = healthUUID
        self.exercises = exercises; self.templateId = templateId; self.workoutId = workoutId
    }
    var inProgress: Bool { startedAt != nil && finishedAt == nil }
    /// Elapsed working seconds (pauses excluded).
    func elapsedSeconds(now: Date = Date()) -> Int {
        guard let s = startedAt else { return 0 }
        let end = finishedAt ?? pausedAt ?? now
        return max(0, Int(end.timeIntervalSince(s)) - pausedSeconds)
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
        exercises = try? c.decodeIfPresent([ExerciseEntry].self, forKey: .exercises)
        templateId = try? c.decodeIfPresent(UUID.self, forKey: .templateId)
        workoutId = try? c.decodeIfPresent(UUID.self, forKey: .workoutId)
        startedAt = try? c.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try? c.decodeIfPresent(Date.self, forKey: .finishedAt)
        pausedSeconds = (try? c.decodeIfPresent(Int.self, forKey: .pausedSeconds)) ?? 0
        pausedAt = try? c.decodeIfPresent(Date.self, forKey: .pausedAt)
        checkIn = try? c.decodeIfPresent(CheckIn.self, forKey: .checkIn)
        unplanned = try? c.decodeIfPresent(Bool.self, forKey: .unplanned)
        needsReview = try? c.decodeIfPresent(Bool.self, forKey: .needsReview)
        migrationNote = try? c.decodeIfPresent(String.self, forKey: .migrationNote)
    }

    var isDetailed: Bool { !(exercises ?? []).isEmpty }
    var isImported: Bool { source != "manual" }
    /// Stable identity across devices and imports: the Health UUID when imported, else the local id.
    var sourceId: String { healthUUID.map { "health:\($0)" } ?? "local:\(id.uuidString)" }
    var title: String { focus == .custom ? (customName.isEmpty ? "Strength" : customName) : "Strength · \(focus.title)" }
    /// true when the rider named a body region; Health imports and custom names say nothing about regions.
    var regionKnown: Bool { focus != .custom }
    var effortLabel: String { guard let r = rpe else { return "effort not stated" }; return r <= 4 ? "easy (RPE \(r))" : r <= 7 ? "moderate (RPE \(r))" : "hard (RPE \(r))" }
    var exerciseCount: Int { exercises?.count ?? 0 }
    var setCount: Int { exercises?.reduce(0) { $0 + $1.doneSets.count } ?? 0 }
    /// Movement patterns actually trained (detailed logs only).
    var patterns: Set<MovementPattern> { Set((exercises ?? []).map { $0.pattern }) }
    /// Heavy leg loading from evidence: a detailed log with ≥ 6 loaded squat/hinge/single-leg sets, or a quick log
    /// labelled lower/legs/full body with RPE ≥ 7. Used only for the interference rule.
    var heavyLegs: Bool {
        if let ex = exercises, !ex.isEmpty {
            let legSets = ex.filter { [.squat, .hinge, .singleLeg].contains($0.pattern) }.reduce(0) { $0 + $1.doneSets.filter { $0.weightKg != nil && !$0.bodyweight }.count }
            return legSets >= 6
        }
        return focus.loadsLegs && (rpe ?? 0) >= 7
    }
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
    /// "estimate" / "insufficient evidence" / nil
    var evidence: String? = nil
}

/// A change the coach proposes. Applied only on Accept; every applied proposal can be undone.
struct CoachProposal: Equatable, Identifiable, Codable {
    enum Change: Equatable, Codable {
        case move(workoutId: UUID, to: Date)
        case kind(workoutId: UUID, to: WorkoutKind)
        case minutes(workoutId: UUID, to: Int)
        case focus(workoutId: UUID, to: StrengthFocus)
    }
    var id: String
    var text: String
    var why: String
    var change: Change
}

struct HybridAssessment: Equatable {
    var cycling: SportProgress?
    var strength: SportProgress?
    var findings: [CoachFinding]
    var recommendation: String          // ONE line for the top of Home
    var next: Workout?                  // the session the line refers to (today's, or the first missing one)
    var why: [String]                   // plain-language reasons, only from available evidence
    var combined: String                // "on track" / "cycling behind" / …
    var proposals: [CoachProposal] = []
    var coverage: CoverageReport? = nil
}

/// Last week compared with its plan (completed sessions only), with one suggested adjustment for the coming week.
struct WeeklyReview: Equatable {
    var monday: Date
    var ridesPlanned: Int, ridesDone: Int, rideMinutesPlanned: Int, rideMinutesDone: Int
    var liftsPlanned: Int, liftsDone: Int, liftMinutesPlanned: Int, liftMinutesDone: Int
    var missedWorkouts: [Workout]
    var suggestion: String
    /// true when two or more recent weeks missed half or more of their sessions → offer to revise availability.
    var offerRevise: Bool
    var completionPct: Int { let p = ridesPlanned + liftsPlanned; return p > 0 ? (ridesDone + liftsDone) * 100 / p : 100 }
}

enum HybridCoach {
    /// Wording of the weekly frequency gap (owner 28 Oct: wording only, the same condition and numbers as before). The
    /// three terms Home's week card uses too: done (completed this week), still to come (scheduled from today on), target
    /// (sessions per week from the profile). One sentence, so Home's coach card shows it whole.
    static func frequencyGapText(sport: String, done: Int, toCome: Int, target: Int, unit: (String, String)) -> String {
        let short = max(1, target - done - toCome)
        return "\(sport) this week: \(done) done and \(toCome) still to come, \(short) short of your target of \(target) \(target == 1 ? unit.0 : unit.1) a week."
    }

    /// Evaluates the current week from real data only: rides, strength logs, the plan and the rider's stated targets.
    /// Planned sessions are NEVER counted as done. `now` and `calendar` are injectable for tests.
    static func assess(profile p: RiderProfile, plan: [Workout], rides: [RideRecord], strength: [StrengthSession], availability a: WeeklyAvailability, now: Date = Date(), calendar cal: Calendar = .current) -> HybridAssessment {
        let today = cal.startOfDay(for: now)
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: today)!
        let nextMonday = cal.date(byAdding: .day, value: 7, to: monday)!
        let week = plan.filter { $0.date >= monday && $0.date < nextMonday }
        let weekRides = rides.filter { $0.start >= monday && $0.start < nextMonday && !$0.demo }
        // quality release: counts come from the one query layer (the same numbers as Plan, Progress and History)
        let ledger = TrainingLedger(plan: plan, strength: strength, rides: rides, calendar: cal)
        let rideWeek = ledger.riding(weekOf: monday), liftWeek = ledger.lifting(weekOf: monday)
        var findings: [CoachFinding] = []
        var why: [String] = []
        var proposals: [CoachProposal] = []

        // --- cycling (completed rides only)
        var cyc: SportProgress? = nil
        if p.trainingMode.includesCycling {
            let done = rideWeek.minutes
            let planned = week.filter { $0.kind.isRide && !$0.skipped }.reduce(0) { $0 + $1.minutes }
            let target = p.hoursPerWeek * 60
            let ridesTarget = max(p.cyclingDaysPerWeek, a.cycleDays)
            var note = "\(rideWeek.completed) of \(ridesTarget) rides · \(Fmt.duration(minutes: done)) of \(Fmt.duration(minutes: target))"
            let zs = weekRides.map { $0.zoneSeconds }.filter { $0.count == 7 && $0.reduce(0, +) > 0 }
            if !zs.isEmpty {
                let tot = zs.reduce(0) { $0 + $1.reduce(0, +) }
                let hard = zs.reduce(0) { $0 + $1[2...].reduce(0, +) }
                let pct = tot > 0 ? hard * 100 / tot : 0
                note += " · \(pct) % at Zone 3 or above"
                if pct > 50, weekRides.count >= 2 { findings.append(.init(id: "cyc-intensity", severity: .info, text: "More than half of this week's riding was Zone 3 or harder; the plan keeps the next ride easy.")) }
            } else if !weekRides.isEmpty { note += " · intensity unknown (no power zones recorded)"; findings.append(.init(id: "cyc-zones", severity: .info, text: "Intensity distribution: not known — no power or heart-rate zones were recorded this week.", evidence: "insufficient evidence")) }
            let hrRides = weekRides.filter { $0.avgHR != nil }.count, pwRides = weekRides.filter { $0.avgPower != nil }.count
            if !weekRides.isEmpty { note += " · power on \(pwRides), HR on \(hrRides) ride\(weekRides.count == 1 ? "" : "s")" }
            cyc = SportProgress(sessionsDone: rideWeek.completed, sessionsTarget: ridesTarget, minutesDone: done, minutesTarget: target, minutesPlanned: planned, note: note)
            let remainingPlanned = week.filter { $0.kind.isRide && !$0.skipped && !ledger.status($0).isCompleted && cal.startOfDay(for: $0.date) >= today }.count
            if rideWeek.completed + remainingPlanned < ridesTarget {
                findings.append(.init(id: "cyc-freq", severity: .gap, text: HybridCoach.frequencyGapText(sport: "Rides", done: rideWeek.completed, toCome: remainingPlanned, target: ridesTarget, unit: ("ride", "rides"))))
            } else if rideWeek.completed >= ridesTarget { findings.append(.init(id: "cyc-ok", severity: .ok, text: "Cycling: \(rideWeek.completed) rides this week — frequency on target.")) }
            if planned > target { findings.append(.init(id: "cyc-over", severity: .conflict, text: "Planned riding (\(Fmt.duration(minutes: planned))) is over your \(p.hoursPerWeek) h cycling budget; see Fix plan.")) }
        }

        // --- strength (logged sessions only)
        var str: SportProgress? = nil
        var coverage: CoverageReport? = nil
        if p.trainingMode.includesLifting {
            let done = liftWeek.minutes
            let planned = week.filter { $0.kind == .strength && !$0.skipped }.reduce(0) { $0 + $1.minutes }
            let target = p.liftingHoursPerWeek * 60
            let liftsTarget = max(p.liftDaysPerWeek, a.liftDays)
            var note = "\(liftWeek.completed) of \(liftsTarget) sessions · \(Fmt.duration(minutes: done))" + (target > 0 ? " of \(Fmt.duration(minutes: target))" : "")
            if liftWeek.unknownDuration > 0 { note += " (\(liftWeek.unknownDuration) without a recorded duration)" }
            let remainingPlanned = week.filter { $0.kind == .strength && !$0.skipped && !ledger.status($0).isCompleted && cal.startOfDay(for: $0.date) >= today }.count
            if liftWeek.completed + remainingPlanned < liftsTarget {
                findings.append(.init(id: "str-freq", severity: .gap, text: HybridCoach.frequencyGapText(sport: "Lifts", done: liftWeek.completed, toCome: remainingPlanned, target: liftsTarget, unit: ("lift", "lifts"))))
            } else if liftsTarget > 0, liftWeek.completed >= liftsTarget { findings.append(.init(id: "str-ok", severity: .ok, text: "Strength: \(liftWeek.completed) sessions this week — frequency on target.")) }
            if target > 0, planned > target { findings.append(.init(id: "str-over", severity: .conflict, text: "Planned lifting (\(Fmt.duration(minutes: planned))) is over your \(p.liftingHoursPerWeek) h lifting budget.")) }
            // region balance — only from Push / Pull labelled logs of the last 28 days
            let since = cal.date(byAdding: .day, value: -28, to: today)!
            let recent = strength.filter { $0.date >= since }
            let push = recent.filter { $0.focus == .push }.count, pull = recent.filter { $0.focus == .pull }.count
            if push + pull >= 3 {
                if push >= 2 * pull + 1 { findings.append(.init(id: "str-pushpull", severity: .gap, text: "Push/pull: \(push) push vs \(pull) pull sessions in 4 weeks — add a pull session.")) }
                else if pull >= 2 * push + 1 { findings.append(.init(id: "str-pushpull", severity: .gap, text: "Push/pull: \(pull) pull vs \(push) push sessions in 4 weeks — add a push session.")) }
                else { findings.append(.init(id: "str-pushpull-ok", severity: .ok, text: "Push/pull balance looks even (\(push) push, \(pull) pull in 4 weeks).")) }
                note += " · push \(push) / pull \(pull)"
            } else if recent.contains(where: { $0.regionKnown }) {
                let lower = recent.filter { $0.focus == .lower || $0.focus == .legs }.count, upper = recent.filter { $0.focus.isUpperRegion }.count, full = recent.filter { $0.focus == .fullBody }.count
                note += " · 4 wk: \(lower) lower, \(upper) upper, \(full) full body"
                if lower == 0, upper >= 2 { findings.append(.init(id: "str-lower", severity: .gap, text: "No lower-body session logged in 4 weeks (\(upper) upper-body); legs matter for riding too.")) }
            }
            // movement coverage and progression — detailed logs only
            let cov = StrengthAnalysis.coverage(strength, since: since)
            coverage = cov
            if cov.known {
                if cov.missing.isEmpty { findings.append(.init(id: "str-coverage-ok", severity: .ok, text: "Movement coverage in 4 weeks: squat, hinge, single-leg, core, push and pull all trained (\(cov.detailedSessions) detailed log\(cov.detailedSessions == 1 ? "" : "s")).")) }
                else { findings.append(.init(id: "str-coverage", severity: .gap, text: "Not trained in 4 weeks of detailed logs: \(cov.missing.map { $0.title.lowercased() }.joined(separator: ", ")).")) }
                if cov.quickOnlySessions > 0 { findings.append(.init(id: "str-coverage-partial", severity: .info, text: "\(cov.quickOnlySessions) quick log\(cov.quickOnlySessions == 1 ? "" : "s") in that window carry no exercises, so coverage is known only from the detailed ones.", evidence: "insufficient evidence")) }
                if cov.pushSets + cov.pullSets >= 12 {
                    if cov.pushSets >= cov.pullSets * 2 { findings.append(.init(id: "str-sets-pushpull", severity: .gap, text: "Sets in 4 weeks: \(cov.pushSets) push vs \(cov.pullSets) pull — add pulling work.")) }
                    else if cov.pullSets >= cov.pushSets * 2 { findings.append(.init(id: "str-sets-pushpull", severity: .gap, text: "Sets in 4 weeks: \(cov.pullSets) pull vs \(cov.pushSets) push — add pushing work.")) }
                }
                let prog = StrengthAnalysis.progression(strength)
                let down = prog.filter { $0.trend == .down }, up = prog.filter { $0.trend == .up }
                if !up.isEmpty { findings.append(.init(id: "str-prog-up", severity: .ok, text: "Progressing: \(up.prefix(3).map { $0.name }.joined(separator: ", ")) (load × reps rising).")) }
                if !down.isEmpty { findings.append(.init(id: "str-prog-down", severity: .info, text: "Load × reps fell over the last sessions of \(down.prefix(3).map { $0.name }.joined(separator: ", ")); worth a look (fatigue, or a deliberate deload?).", evidence: "estimate")) }
                if prog.allSatisfy({ $0.trend == .insufficient }) { findings.append(.init(id: "str-prog-none", severity: .info, text: "Exercise progression: not enough repeated exercises yet (needs 4 logs of the same lift with weights).", evidence: "insufficient evidence")) }
            } else {
                findings.append(.init(id: "str-coverage", severity: .info, text: "Squat / hinge / single-leg / core coverage and exercise progression: not known from quick logs — log exercises in a detailed session and the coach checks them.", evidence: "insufficient evidence"))
            }
            str = SportProgress(sessionsDone: liftWeek.completed, sessionsTarget: liftsTarget, minutesDone: done, minutesTarget: target, minutesPlanned: planned, note: note)
        }

        // --- interference: a heavy leg session (logged, from evidence) right before a demanding planned ride, or two
        //     hard planned days back to back. Proposals move only flexible, unedited, not-yet-done sessions.
        let hardPlanned = week.filter { !$0.skipped && !$0.done && $0.kind.isRide && $0.kind.zone >= 3 && cal.startOfDay(for: $0.date) >= today }
        for r in hardPlanned {
            let dayBefore = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: r.date))!
            let heavy = strength.first { $0.heavyLegs && cal.isDate($0.date, inSameDayAs: dayBefore) }
            let plannedLegs = week.first { $0.kind == .strength && !$0.skipped && ($0.strengthFocus?.loadsLegs ?? false) && cal.isDate($0.date, inSameDayAs: dayBefore) }
            if heavy != nil || plannedLegs != nil {
                findings.append(.init(id: "interf-\(r.id.uuidString.prefix(4))", severity: .conflict, text: "\(r.kind.title) on \(r.date.shortDay) follows a heavy leg session on \(dayBefore.shortDay)\(heavy != nil ? " (logged)" : " (planned)"). Legs may not be fresh for the quality ride."))
                if !r.fixed, !r.edited {
                    // softer ride instead of moving a fixed day
                    proposals.append(CoachProposal(id: "soften-\(r.id.uuidString)", text: "Make \(r.date.shortDay)'s \(r.kind.title.lowercased()) an endurance ride (same duration)", why: "A heavy leg session the day before means the quality intervals would likely be done tired. Keeping the ride but at Zone 2 preserves the hours without the interference. Your fixed days and manual edits are untouched.", change: .kind(workoutId: r.id, to: .endurance)))
                }
                if let l = plannedLegs, !l.fixed, !l.edited, !l.done {
                    proposals.append(CoachProposal(id: "upper-\(l.id.uuidString)", text: "Make \(l.date.shortDay)'s lift an upper-body session", why: "Keeps the lift on its day and your legs fresh for \(r.date.shortDay)'s \(r.kind.title.lowercased()). Only a proposal — nothing changes until you accept.", change: .focus(workoutId: l.id, to: .upper)))
                }
            }
        }
        let hardDays = week.filter { !$0.skipped && (($0.kind.zone >= 3 && $0.kind.isRide) || ($0.kind == .strength && ($0.strengthFocus?.loadsLegs ?? false))) }.map { cal.startOfDay(for: $0.date) }
        let sortedHard = Array(Set(hardDays)).sorted()
        for i in 1..<max(1, sortedHard.count) where cal.dateComponents([.day], from: sortedHard[i - 1], to: sortedHard[i]).day == 1 {
            if !findings.contains(where: { $0.id.hasPrefix("interf") }) { findings.append(.init(id: "sched-\(i)", severity: .conflict, text: "\(sortedHard[i - 1].shortDay) and \(sortedHard[i].shortDay) are both hard days (hard ride or leg session back to back). Move one if you can.")) }
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
                if g.id.hasPrefix("str"), let free = week.first(where: { $0.kind == .rest && cal.startOfDay(for: $0.date) >= today }) {
                    next = Workout(date: free.date, kind: .strength, minutes: 30, strengthFocus: g.id == "str-lower" ? .lower : .fullBody)
                    line = "Next: a 30 min \(next!.strengthFocus!.title.lowercased()) strength session on \(free.date.shortDay) — a lift is missing this week."
                } else if g.id.hasPrefix("cyc"), let free = week.first(where: { $0.kind == .rest && cal.startOfDay(for: $0.date) >= today }) {
                    next = Workout(date: free.date, kind: .endurance, minutes: 45)
                    line = "Next: a 45 min endurance ride on \(free.date.shortDay) — a ride is missing this week."
                }
            }
        }
        if let c = cyc { why.append("Cycling this week (completed rides only): \(c.note).") }
        if let s = str { why.append("Strength this week (logged sessions only): \(s.note).") }
        why.append("Priority: \(p.priority.title.lowercased()); mode: \(p.trainingMode.title.lowercased()). Planned sessions count only once they are recorded or logged.")
        if p.trainingMode.includesLifting { why.append("Hard rides and leg sessions are kept on separate days when your availability allows it; fixed days are never moved by the coach.") }
        why.append("No sleep, HRV or recovery source is connected, so recovery is not part of this recommendation.")

        let gaps = findings.filter { $0.severity == .gap }
        let combined: String
        if gaps.isEmpty { combined = findings.contains { $0.severity == .conflict } ? "on track · check the schedule" : "on track" }
        else if gaps.allSatisfy({ $0.id.hasPrefix("cyc") }) { combined = "cycling behind" }
        else if gaps.allSatisfy({ $0.id.hasPrefix("str") }) { combined = "strength behind" }
        else { combined = "both behind" }
        return HybridAssessment(cycling: cyc, strength: str, findings: findings, recommendation: line, next: next, why: why, combined: combined, proposals: proposals, coverage: coverage)
    }

    /// Review of the week before `now`'s week: planned vs completed per sport, the missed sessions, one suggestion.
    static func weeklyReview(profile p: RiderProfile, plan: [Workout], rides: [RideRecord], strength: [StrengthSession], now: Date = Date(), calendar cal: Calendar = .current) -> WeeklyReview? {
        let today = cal.startOfDay(for: now)
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let thisMonday = cal.date(byAdding: .day, value: -wd, to: today)!
        func stats(_ monday: Date) -> (plannedR: [Workout], plannedL: [Workout], rides: [RideRecord], lifts: [StrengthSession]) {
            let end = cal.date(byAdding: .day, value: 7, to: monday)!
            let w = plan.filter { $0.date >= monday && $0.date < end && !$0.skipped }
            return (w.filter { $0.kind.isRide }, w.filter { $0.kind == .strength }, rides.filter { $0.start >= monday && $0.start < end && !$0.demo }, strength.filter { $0.date >= monday && $0.date < end })
        }
        let last = cal.date(byAdding: .day, value: -7, to: thisMonday)!
        let s = stats(last)
        guard !s.plannedR.isEmpty || !s.plannedL.isEmpty || !s.rides.isEmpty || !s.lifts.isEmpty else { return nil }
        // a planned session counts as missed when the one query layer does not see it completed (no ride / log on its
        // day, not marked done) — the same definition as Home, Plan, Progress and History
        let ledger = TrainingLedger(plan: plan, strength: strength, rides: rides, calendar: cal)
        let missed = (s.plannedR + s.plannedL).filter { !ledger.status($0).isCompleted }.sorted { $0.date < $1.date }
        let rw = ledger.riding(weekOf: last), lw = ledger.lifting(weekOf: last)
        let ridesDone = min(s.plannedR.count, rw.completed), liftsDone = min(s.plannedL.count, lw.completed)
        var suggestion: String
        let totalPlanned = s.plannedR.count + s.plannedL.count
        let pct = totalPlanned > 0 ? (totalPlanned - missed.count) * 100 / totalPlanned : 100
        if totalPlanned == 0 { suggestion = "Nothing was planned last week; this week follows your days." }
        else if missed.isEmpty { suggestion = "Everything planned was done. If it felt comfortable, add 10 % to the long ride or one more set per exercise this week." }
        else if pct < 50 { suggestion = "Half or more of last week was missed. This week keeps the same days; if that is not realistic, change your training days (Plan › Days) rather than carrying the same plan again." }
        else { let m = missed[0]; suggestion = "\(missed.count) session\(missed.count == 1 ? "" : "s") missed, first on \(m.date.shortDay) (\(m.displayTitle.lowercased())). This week: keep the sessions, shorten \(m.date.shortDay)'s by a quarter if time was the problem." }
        // repeated misses over the last three completed weeks
        var badWeeks = 0
        for k in 1...3 {
            let m = cal.date(byAdding: .day, value: -7 * k, to: thisMonday)!
            let st = stats(m)
            let planned = st.plannedR.count + st.plannedL.count
            guard planned > 0 else { continue }
            let miss = (st.plannedR + st.plannedL).filter { !ledger.status($0).isCompleted }.count
            if miss * 2 >= planned { badWeeks += 1 }
        }
        return WeeklyReview(monday: last, ridesPlanned: s.plannedR.count, ridesDone: ridesDone, rideMinutesPlanned: s.plannedR.reduce(0) { $0 + $1.minutes }, rideMinutesDone: rw.minutes,
                            liftsPlanned: s.plannedL.count, liftsDone: liftsDone, liftMinutesPlanned: s.plannedL.reduce(0) { $0 + $1.minutes }, liftMinutesDone: lw.minutes,
                            missedWorkouts: missed, suggestion: suggestion, offerRevise: badWeeks >= 2)
    }
}
