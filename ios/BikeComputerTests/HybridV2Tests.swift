import XCTest
@testable import BikeComputer

/// 0.7.0 — budgets that can never be exceeded, per-day assignments (fixed / flexible), exercise catalogue, detailed
/// logs → coverage and progression, completed-only coaching, proposals with undo, weekly review, stable source ids.
final class HybridV2Tests: XCTestCase {
    private let cal = Calendar.current
    private var monday: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 19))! }
    private func hybridProfile(cycH: Int = 5, liftH: Int = 2) -> RiderProfile {
        var p = RiderProfile.screened(); p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = cycH; p.liftingHoursPerWeek = liftH
        p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 3; p.level = .intermediate; p.goal = .fitness
        return p
    }
    private func day(_ xs: [DayAssignment]) -> DayAvailability { DayAvailability(assignments: xs) }
    private func ride(_ t: CyclingType?, _ m: Int, fixed: Bool = false) -> DayAssignment { DayAssignment(sport: .cycling, cyclingType: t, minutes: m, fixed: fixed) }
    private func lift(_ t: StrengthFocus?, _ m: Int, fixed: Bool = false) -> DayAssignment { DayAssignment(sport: .strength, strengthType: t, minutes: m, fixed: fixed) }
    private var rest: DayAvailability { DayAvailability(activity: .rest, minutes: 0) }

    // MARK: P0 — budgets
    func testPlanNeverExceedsEitherBudgetByAMinute() {
        // 2 h 5 min of riding against a 2 h budget, 2 h 10 min lifting against 2 h: the brief's exact examples
        var p = hybridProfile(cycH: 2, liftH: 2); p.cyclingDaysPerWeek = 2; p.liftDaysPerWeek = 2
        var av = WeeklyAvailability(days: [rest, day([ride(nil, 65)]), day([lift(nil, 70)]), day([ride(nil, 60)]), rest, day([lift(nil, 60)]), rest])
        XCTAssertEqual(av.cycleMinutes, 125); XCTAssertEqual(av.liftMinutes, 130)
        let conflicts = av.conflicts(profile: p)
        XCTAssertEqual(conflicts.count, 2)
        XCTAssertEqual(conflicts.first { $0.sport == .cycling }?.overMinutes, 5)
        XCTAssertEqual(conflicts.first { $0.sport == .lifting }?.overMinutes, 10)
        XCTAssertTrue(conflicts.allSatisfy { $0.options.count >= 2 }, "every conflict offers ways to relax it")
        let w = PlanEngine.week(starting: monday, profile: p, availability: av)
        XCTAssertLessThanOrEqual(PlanEngine.rideMinutes(w), 120, "never 2 h 5 min against a 2 h cycling budget")
        XCTAssertLessThanOrEqual(PlanEngine.liftMinutes(w), 120, "never 2 h 10 min against a 2 h lifting budget")
        XCTAssertEqual(w.filter { $0.kind.isRide }.count, 2, "no day added or dropped")
        XCTAssertEqual(w.filter { $0.kind == .strength }.count, 2)
        // the trim is explained, not silent
        let fit = WeeklyAvailability.fit(av, profile: p)
        XCTAssertFalse(fit.trimmed.isEmpty); XCTAssertEqual(fit.availability.cycleMinutes, 120); XCTAssertEqual(fit.availability.liftMinutes, 120)
        // exactly at the limit → no conflict, nothing trimmed
        av.days[1].assignments[0].minutes = 60; av.days[2].assignments[0].minutes = 60
        XCTAssertTrue(av.conflicts(profile: p).isEmpty); XCTAssertTrue(WeeklyAvailability.fit(av, profile: p).trimmed.isEmpty)
    }

    func testFitTrimsFlexibleBeforeFixedAndKeepsTypes() {
        var p = hybridProfile(cycH: 3, liftH: 1); p.cyclingDaysPerWeek = 2; p.liftDaysPerWeek = 1
        let av = WeeklyAvailability(days: [rest, day([ride(.threshold, 90, fixed: true)]), rest, day([ride(.zone2, 120)]), rest, rest, day([lift(.lower, 45)])])
        let fit = WeeklyAvailability.fit(av, profile: p)
        XCTAssertEqual(fit.availability.days[1].assignments[0].minutes, 90, "fixed assignment untouched while a flexible one can give")
        XCTAssertEqual(fit.availability.days[3].assignments[0].minutes, 90, "flexible Zone 2 ride shortened to fit 3 h")
        XCTAssertEqual(fit.availability.cycleMinutes, 180)
        let w = PlanEngine.week(starting: monday, profile: p, availability: av)
        let tue = w.first { cal.isDate($0.date, inSameDayAs: cal.date(byAdding: .day, value: 1, to: monday)!) }!
        XCTAssertEqual(tue.kind, .threshold, "a typed assignment keeps its type"); XCTAssertTrue(tue.fixed)
        XCTAssertEqual(w.first { $0.kind == .strength }?.strengthFocus, .lower, "typed strength keeps its region")
    }

    // MARK: P1 — per-day assignments, migration
    func testLegacyAvailabilityMigratesWithoutLoss() throws {
        let json = """
        {"days":[{"activity":"rest","minutes":0},{"activity":"both","minutes":60,"liftMinutes":30},{"activity":"lift","minutes":45},{"activity":"cycle","minutes":75},{"activity":"rest","minutes":0},{"activity":"cycle","minutes":150},{"activity":"other","minutes":40}]}
        """
        let a = try JSONDecoder().decode(WeeklyAvailability.self, from: Data(json.utf8))
        XCTAssertEqual(a.days[1].mark, "Both"); XCTAssertEqual(a.days[1].cycleMinutes, 60); XCTAssertEqual(a.days[1].liftingMinutes, 30)
        XCTAssertEqual(a.days[2].mark, "Strength"); XCTAssertEqual(a.days[3].mark, "Cycling"); XCTAssertEqual(a.days[0].mark, "Rest")
        XCTAssertEqual(a.days[6].mark, "Other"); XCTAssertEqual(a.days[6].otherMinutes, 40)
        XCTAssertEqual(a.cycleMinutes, 285); XCTAssertEqual(a.liftMinutes, 75)
        XCTAssertNil(a.days[3].assignments[0].cyclingType, "legacy rides stay untyped so the coach still picks long / quality")
        // round trip keeps both the legacy summary and the assignments
        let d = try JSONEncoder().encode(a)
        let b = try JSONDecoder().decode(WeeklyAvailability.self, from: d)
        XCTAssertEqual(a, b)
        XCTAssertTrue(String(decoding: d, as: UTF8.self).contains("\"assignments\""))
        XCTAssertTrue(String(decoding: d, as: UTF8.self).contains("\"activity\""))
    }

    func testDayMarksAndFlexibleDays() {
        var d = DayAvailability(activity: .rest, minutes: 0); d.flexible = true
        XCTAssertEqual(d.mark, "Flexible")
        d.assignments = [ride(.zone2, 60)]; d.syncLegacy(); XCTAssertEqual(d.mark, "Cycling"); XCTAssertEqual(d.activity, .cycle)
        d.assignments.append(lift(.upper, 30, fixed: true)); d.syncLegacy(); XCTAssertEqual(d.mark, "Both"); XCTAssertEqual(d.activity, .both); XCTAssertEqual(d.liftMinutes, 30); XCTAssertEqual(d.fixedCount, 1)
        var p = hybridProfile(); p.cyclingDaysPerWeek = 2; p.liftDaysPerWeek = 3
        let a = WeeklyAvailability(days: [rest, d, rest, day([ride(nil, 60)]), rest, rest, rest])
        let issues = a.consistency(profile: p)
        XCTAssertTrue(issues.contains { $0.contains("3 lifts a week but assigned 1") })
        XCTAssertFalse(issues.contains { $0.contains("rides a week") })
    }

    func testSuggestedAvailabilityIsInsideBothBudgets() {
        for (h, l, rides, lifts) in [(5, 2, 3, 3), (3, 1, 2, 2), (10, 4, 5, 4), (2, 1, 1, 1)] {
            var p = hybridProfile(cycH: h, liftH: l); p.cyclingDaysPerWeek = rides; p.liftDaysPerWeek = lifts
            let a = WeeklyAvailability.suggested(for: p)
            XCTAssertLessThanOrEqual(a.cycleMinutes, h * 60, "suggestion over the cycling budget for \(h)h/\(rides)")
            XCTAssertLessThanOrEqual(a.liftMinutes, l * 60, "suggestion over the lifting budget for \(l)h/\(lifts)")
            XCTAssertEqual(a.cycleDays, rides); XCTAssertEqual(a.liftDays, lifts)
            let w = PlanEngine.week(starting: monday, profile: p, availability: a)
            XCTAssertLessThanOrEqual(PlanEngine.rideMinutes(w), h * 60); XCTAssertLessThanOrEqual(PlanEngine.liftMinutes(w), l * 60)
        }
    }

    // MARK: P1 — exercises, detailed logs, templates
    func testCatalogueLoadsAndSearchWorks() {
        let all = ExerciseCatalogue.builtIn
        XCTAssertGreaterThanOrEqual(all.count, 150)
        XCTAssertEqual(Set(all.map { $0.id }).count, all.count, "ids unique")
        XCTAssertTrue(ExerciseCatalogue.search("rdl", in: all).contains { $0.name == "Romanian deadlift" }, "alias search")
        XCTAssertTrue(ExerciseCatalogue.search("kettlebell", in: all).allSatisfy { $0.equipment.contains("kettlebell") || $0.name.lowercased().contains("kettlebell") })
        XCTAssertTrue(ExerciseCatalogue.search("", in: all, pattern: .singleLeg).allSatisfy { $0.pattern == .singleLeg })
        XCTAssertTrue(ExerciseCatalogue.search("glutes", in: all).count >= 5, "muscle search")
        XCTAssertEqual(ExerciseCatalogue.search("bench press", in: all).first?.name, "Bench press", "prefix match ranks first")
        for p in MovementPattern.coverage { XCTAssertGreaterThanOrEqual(all.filter { $0.pattern == p }.count, 10, "\(p) has enough exercises") }
    }

    private func detailed(_ dayOffset: Int, _ exercises: [(String, MovementPattern, [(Int, Double?)])], weekOffset: Int = 0, focus: StrengthFocus = .custom) -> StrengthSession {
        let ex = exercises.map { name, pat, sets in
            ExerciseEntry(exercise: Exercise(id: name.lowercased(), name: name, pattern: pat), sets: sets.map { SetEntry(reps: $0.0, weightKg: $0.1, bodyweight: $0.1 == nil) })
        }
        return StrengthSession(date: cal.date(byAdding: .day, value: dayOffset + 7 * weekOffset, to: monday)!.addingTimeInterval(18 * 3600), minutes: 50, focus: focus, rpe: 7, exercises: ex)
    }

    func testCoverageIsUnknownFromQuickLogsAndKnownFromDetailedOnes() {
        let since = cal.date(byAdding: .day, value: -28, to: monday)!
        let quick = [StrengthSession(date: monday, minutes: 40, focus: .fullBody, rpe: 7), StrengthSession(date: cal.date(byAdding: .day, value: 2, to: monday)!, minutes: 40, focus: .legs, rpe: 8)]
        let c0 = StrengthAnalysis.coverage(quick, since: since)
        XCTAssertFalse(c0.known); XCTAssertTrue(c0.missing.isEmpty, "unknown is not 'missing'"); XCTAssertEqual(c0.quickOnlySessions, 2)
        let det = [detailed(0, [("Back squat", .squat, [(5, 80), (5, 80), (5, 80)]), ("Bench press", .push, [(8, 60), (8, 60)]), ("Plank", .core, [(1, nil)])]),
                   detailed(3, [("Romanian deadlift", .hinge, [(8, 70), (8, 70)]), ("Pull-up", .pull, [(6, nil), (6, nil)])])]
        let c1 = StrengthAnalysis.coverage(det + quick, since: since)
        XCTAssertTrue(c1.known); XCTAssertEqual(c1.detailedSessions, 2); XCTAssertEqual(c1.quickOnlySessions, 2)
        XCTAssertEqual(c1.missing, [.singleLeg], "only what the detailed logs never contained is missing")
        XCTAssertEqual(c1.pushSets, 2); XCTAssertEqual(c1.pullSets, 2)
        // the coach wording follows the evidence
        let p = hybridProfile(); let a = WeeklyAvailability.suggested(for: p)
        let plan = PlanEngine.week(starting: monday, profile: p, availability: a)
        let now = cal.date(byAdding: .day, value: 4, to: monday)!.addingTimeInterval(10 * 3600)
        let x0 = HybridCoach.assess(profile: p, plan: plan, rides: [], strength: quick, availability: a, now: now, calendar: cal)
        XCTAssertTrue(x0.findings.contains { $0.id == "str-coverage" && $0.text.contains("not known from quick logs") && $0.evidence == "insufficient evidence" })
        let x1 = HybridCoach.assess(profile: p, plan: plan, rides: [], strength: det + quick, availability: a, now: now, calendar: cal)
        XCTAssertTrue(x1.findings.contains { $0.id == "str-coverage" && $0.text.contains("single-leg") && $0.severity == .gap })
        XCTAssertTrue(x1.findings.contains { $0.id == "str-coverage-partial" })
    }

    func testProgressionTrendNeedsFourLoadedSessions() {
        var sessions: [StrengthSession] = []
        for k in 0..<4 { sessions.append(detailed(0, [("Back squat", .squat, [(5, 80 + Double(k) * 5), (5, 80 + Double(k) * 5), (5, 80 + Double(k) * 5)])], weekOffset: k - 4)) }
        let prog = StrengthAnalysis.progression(sessions)
        XCTAssertEqual(prog.count, 1); XCTAssertEqual(prog[0].trend, .up)
        XCTAssertEqual(StrengthAnalysis.progression(Array(sessions.prefix(3)))[0].trend, .insufficient)
        var down = sessions; down[3].exercises![0].sets = [SetEntry(reps: 3, weightKg: 60)]
        XCTAssertEqual(StrengthAnalysis.progression(down)[0].trend, .down)
        // bodyweight-only sets never produce a tonnage trend
        let bw = (0..<4).map { k in detailed(0, [("Push-up", .push, [(20, nil), (20, nil)])], weekOffset: k - 4) }
        XCTAssertEqual(StrengthAnalysis.progression(bw)[0].trend, .insufficient)
    }

    func testTemplatePrefillsFromLastSession() {
        // the template was last edited before that session (an edit made AFTER the session wins — StrengthAuditTests)
        let t = WorkoutTemplate(name: "Lower A", focus: .lower, entries: [ExerciseEntry(exercise: Exercise(id: "sq", name: "Back squat", pattern: .squat), sets: [SetEntry(reps: 5, weightKg: 60)])], updatedAt: .distantPast)
        var last = detailed(0, [("Back squat", .squat, [(5, 90), (5, 90), (5, 90)])]); last.templateId = t.id
        last.exercises![0].exerciseId = "sq"
        let e = t.prefilled(from: last)
        XCTAssertEqual(e.count, 1); XCTAssertEqual(e[0].sets.count, 3); XCTAssertEqual(e[0].sets[0].weightKg, 90, "last session's values win")
        XCTAssertNotEqual(e[0].id, t.entries[0].id, "fresh ids for the new session")
        XCTAssertEqual(t.prefilled(from: nil)[0].sets[0].weightKg, 60, "template's own values without a previous session")
    }

    func testSetEntryTonnageAndText() {
        XCTAssertEqual(SetEntry(reps: 8, weightKg: 50).tonnageKg, 400)
        XCTAssertEqual(SetEntry(reps: 8, weightKg: 20, unilateral: true).tonnageKg, 320, "per-side reps count both sides")
        XCTAssertNil(SetEntry(reps: 12, bodyweight: true).tonnageKg)
        XCTAssertEqual(SetEntry(reps: 8, weightKg: 50, rpe: 8).text, "8 × 50 kg @8")
        XCTAssertEqual(SetEntry(reps: 10, weightKg: 12.5, unilateral: true).text, "10/side × 12.5 kg")
    }

    // MARK: P2 — coaching from completed sessions only, interference proposals with undo, weekly review
    private func phoneRide(_ dayOffset: Int, minutes: Int, hard: Bool = false) -> RideRecord {
        var r = RideRecord(start: cal.date(byAdding: .day, value: dayOffset, to: monday)!.addingTimeInterval(8 * 3600), durationS: minutes * 60, distanceM: minutes * 400, recorder: .phone, sources: ["Phone GPS"])
        r.zoneSeconds = hard ? [0, 0, minutes * 40, minutes * 20, 0, 0, 0] : [0, minutes * 60, 0, 0, 0, 0, 0]
        return r
    }

    func testPlannedSessionsAreNeverCountedAsCompleted() {
        let p = hybridProfile(); let a = WeeklyAvailability.suggested(for: p)
        var plan = PlanEngine.week(starting: monday, profile: p, availability: a)
        // mark every planned session done WITHOUT any ride or log existing
        for i in plan.indices { plan[i].done = true }
        let now = cal.date(byAdding: .day, value: 6, to: monday)!.addingTimeInterval(20 * 3600)
        let x = HybridCoach.assess(profile: p, plan: plan, rides: [], strength: [], availability: a, now: now, calendar: cal)
        XCTAssertEqual(x.cycling?.sessionsDone, 0); XCTAssertEqual(x.cycling?.minutesDone, 0)
        XCTAssertEqual(x.strength?.sessionsDone, 0); XCTAssertEqual(x.strength?.minutesDone, 0)
        XCTAssertTrue(x.findings.contains { $0.id == "cyc-freq" }); XCTAssertTrue(x.findings.contains { $0.id == "str-freq" })
    }

    func testCyclingTimeIsNeverLiftingVolume() {
        let p = hybridProfile(); let a = WeeklyAvailability.suggested(for: p)
        let plan = PlanEngine.week(starting: monday, profile: p, availability: a)
        let now = cal.date(byAdding: .day, value: 6, to: monday)!.addingTimeInterval(20 * 3600)
        let x = HybridCoach.assess(profile: p, plan: plan, rides: [phoneRide(1, minutes: 60), phoneRide(3, minutes: 90), phoneRide(5, minutes: 120)], strength: [], availability: a, now: now, calendar: cal)
        XCTAssertEqual(x.cycling?.minutesDone, 270); XCTAssertEqual(x.strength?.minutesDone, 0)
        XCTAssertEqual(x.combined, "strength behind")
    }

    func testInterferenceProposalRespectsFixedAndEditedAndCanBeUndone() {
        var p = hybridProfile(); p.cyclingDaysPerWeek = 2; p.liftDaysPerWeek = 2
        // review P3-14: a typed (flexible) threshold day now follows the goal, so this fixture uses a goal that plans
        // threshold (the test is about the interference proposal, not the intensity choice)
        p.goal = .stronger
        // Tue heavy legs (fixed), Wed threshold (flexible) → proposal to soften Wed; Fri threshold (fixed) after Thu legs → no proposal for Fri
        let av = WeeklyAvailability(days: [rest, day([lift(.lower, 45, fixed: true)]), day([ride(.threshold, 60)]), day([lift(.lower, 45)]), day([ride(.threshold, 60, fixed: true)]), rest, rest])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = Store(directory: dir, generatePlan: false)
        store.profile = p; store.availability = av
        store.plan = PlanEngine.week(starting: monday, profile: p, availability: av)
        let now = monday.addingTimeInterval(10 * 3600)
        let x = HybridCoach.assess(profile: p, plan: store.plan, rides: [], strength: [], availability: av, now: now, calendar: cal)
        let wed = store.plan.first { cal.isDate($0.date, inSameDayAs: cal.date(byAdding: .day, value: 2, to: monday)!) && $0.kind.isRide }!
        let fri = store.plan.first { cal.isDate($0.date, inSameDayAs: cal.date(byAdding: .day, value: 4, to: monday)!) && $0.kind.isRide }!
        XCTAssertTrue(x.findings.contains { $0.id.hasPrefix("interf") })
        XCTAssertTrue(x.proposals.contains { $0.change == .kind(workoutId: wed.id, to: .endurance) }, "flexible Wed ride gets a softer-ride proposal")
        XCTAssertFalse(x.proposals.contains { if case .kind(let id, _) = $0.change { return id == fri.id }; return false }, "a fixed ride is never proposed for change")
        XCTAssertFalse(x.proposals.contains { if case .focus(let id, _) = $0.change { return id == store.plan.first { $0.kind == .strength && $0.fixed }!.id }; return false }, "a fixed lift is never proposed for change")
        // accept → applied, kind changed; undo → restored
        let prop = x.proposals.first { $0.change == .kind(workoutId: wed.id, to: .endurance) }!
        XCTAssertTrue(store.apply(prop))
        XCTAssertEqual(store.plan.first { $0.id == wed.id }?.kind, .endurance)
        XCTAssertEqual(store.appliedProposals.count, 1)
        XCTAssertTrue(store.undoLastProposal())
        XCTAssertEqual(store.plan.first { $0.id == wed.id }?.kind, .threshold)
        // a hand-edited session is refused
        var e = store.plan.first { $0.id == wed.id }!; store.edit(e)
        XCTAssertFalse(store.apply(prop), "manual edits are never overwritten without explicit approval")
        e.edited = false; store.update(e)
        // a logged heavy leg session the day before also triggers (evidence, not plan)
        let heavy = StrengthSession(date: cal.date(byAdding: .day, value: 1, to: monday)!.addingTimeInterval(18 * 3600), minutes: 50, focus: .lower, rpe: 8)
        let y = HybridCoach.assess(profile: p, plan: store.plan.filter { !($0.kind == .strength && cal.isDate($0.date, inSameDayAs: heavy.date)) }, rides: [], strength: [heavy], availability: av, now: now, calendar: cal)
        XCTAssertTrue(y.findings.contains { $0.id.hasPrefix("interf") && $0.text.contains("(logged)") })
        try? FileManager.default.removeItem(at: dir)
    }

    func testWeeklyReviewComparesPlannedWithCompletedAndOffersRevision() {
        let p = hybridProfile(); let a = WeeklyAvailability.suggested(for: p)
        let now = cal.date(byAdding: .day, value: 7, to: monday)!.addingTimeInterval(9 * 3600)   // the Monday after
        let lastWeek = PlanEngine.week(starting: monday, profile: p, availability: a)
        let rideDays = lastWeek.filter { $0.kind.isRide }.map { cal.dateComponents([.day], from: monday, to: cal.startOfDay(for: $0.date)).day! }
        let r = HybridCoach.weeklyReview(profile: p, plan: lastWeek, rides: [phoneRide(rideDays[0], minutes: 60)], strength: [], now: now, calendar: cal)!
        XCTAssertEqual(r.ridesPlanned, 3); XCTAssertEqual(r.ridesDone, 1); XCTAssertEqual(r.liftsPlanned, 3); XCTAssertEqual(r.liftsDone, 0)
        XCTAssertEqual(r.missedWorkouts.count, 5); XCTAssertTrue(r.completionPct < 50)
        XCTAssertTrue(r.suggestion.contains("Half or more"))
        XCTAssertFalse(r.offerRevise, "one bad week alone does not trigger the offer")
        // two bad weeks → offer to revise availability
        let twoWeeksAgo = PlanEngine.week(starting: cal.date(byAdding: .day, value: -7, to: monday)!, profile: p, availability: a)
        let r2 = HybridCoach.weeklyReview(profile: p, plan: lastWeek + twoWeeksAgo, rides: [phoneRide(rideDays[0], minutes: 60)], strength: [], now: now, calendar: cal)!
        XCTAssertTrue(r2.offerRevise)
        // everything done → the positive suggestion, nothing missed
        let allRides = rideDays.map { phoneRide($0, minutes: 60) }
        let liftDays = lastWeek.filter { $0.kind == .strength }.map { cal.dateComponents([.day], from: monday, to: cal.startOfDay(for: $0.date)).day! }
        let lifts = liftDays.map { StrengthSession(date: cal.date(byAdding: .day, value: $0, to: monday)!.addingTimeInterval(18 * 3600), minutes: 40, focus: .fullBody, rpe: 6) }
        let r3 = HybridCoach.weeklyReview(profile: p, plan: lastWeek, rides: allRides, strength: lifts, now: now, calendar: cal)!
        XCTAssertTrue(r3.missedWorkouts.isEmpty); XCTAssertEqual(r3.completionPct, 100); XCTAssertTrue(r3.suggestion.contains("Everything planned"))
    }

    // MARK: history: stable source ids, imported status, dedupe
    func testStableSourceIdsAndImportedStatus() {
        var board = RideRecord(start: monday, durationS: 3600, distanceM: 30000, recorder: .board, sources: ["BikeComputer"]); board.boardId = "aa:bb"; board.boardRideId = 7
        var health = RideRecord(start: cal.date(byAdding: .day, value: 1, to: monday)!, durationS: 1800, distanceM: 10000, recorder: .health, sources: ["Apple Health"]); health.healthUUID = "H-1"
        XCTAssertEqual(board.sourceId, "board:aa:bb:7"); XCTAssertEqual(health.sourceId, "health:H-1")
        var dupHealth = health; dupHealth.id = UUID()
        XCTAssertEqual(Timeline.dedupe([board, health, dupHealth]).count, 2, "same Health UUID is one ride")
        let s = StrengthSession(date: monday, minutes: 30, focus: .custom, customName: "Strength training (Apple Health)", source: "Apple Health", healthUUID: "H-2")
        XCTAssertEqual(s.sourceId, "health:H-2")
        let tl = Timeline.build(rides: [board, health], plan: [], ftp: 200, strength: [s], now: cal.date(byAdding: .day, value: 3, to: monday)!, calendar: cal)
        XCTAssertEqual(tl.first { $0.rideId == health.id }?.status, .imported)
        XCTAssertEqual(tl.first { $0.rideId == board.id }?.status, .completed)
        XCTAssertEqual(tl.first { $0.strengthId == s.id }?.status, .imported)
        XCTAssertEqual(Set(tl.map { $0.id }).count, tl.count, "ids unique and stable")
    }

    func testStoreRoundTripKeepsTemplatesExercisesAndDetailedLogs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let s1 = Store(directory: dir, generatePlan: false)
        s1.addCustomExercise(Exercise(id: "", name: "Landmine row", pattern: .pull))
        let t = WorkoutTemplate(name: "Upper A", focus: .upper, entries: [ExerciseEntry(exercise: Exercise(id: "bp", name: "Bench press", pattern: .push), sets: [SetEntry(reps: 8, weightKg: 60)])])
        s1.saveTemplate(t)
        var sess = detailed(0, [("Bench press", .push, [(8, 60), (8, 60)])]); sess.templateId = t.id
        XCTAssertTrue(s1.addStrength(sess))
        XCTAssertEqual(s1.templates[0].lastUsed, sess.date, "using a template records it")
        let s2 = Store(directory: dir, generatePlan: false)
        XCTAssertEqual(s2.customExercises.count, 1); XCTAssertTrue(s2.customExercises[0].custom); XCTAssertTrue(s2.customExercises[0].id.hasPrefix("custom-"))
        XCTAssertEqual(s2.templates.count, 1); XCTAssertEqual(s2.strength.count, 1); XCTAssertEqual(s2.strength[0].exercises?.count, 1); XCTAssertEqual(s2.strength[0].setCount, 2)
        // a 0.6.0 strength log (no exercises key) still loads as a quick log
        let old = """
        {"id":"\(UUID().uuidString)","date":"2026-10-20T18:00:00Z","minutes":40,"focus":"upper","rpe":6,"notes":"","source":"manual"}
        """
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let q = try dec.decode(StrengthSession.self, from: Data(old.utf8))
        XCTAssertFalse(q.isDetailed); XCTAssertEqual(q.focus, .upper)
        try? FileManager.default.removeItem(at: dir)
    }

    func testFormatterAndShortLabels() {
        XCTAssertEqual(Fmt.duration(minutes: 100), "1 h 40 min"); XCTAssertEqual(Fmt.duration(minutes: 65), "1 h 5 min"); XCTAssertEqual(Fmt.duration(minutes: 120), "2 h"); XCTAssertEqual(Fmt.duration(minutes: 45), "45 min")
        for f in StrengthFocus.quickLog { XCTAssertLessThanOrEqual(f.short.count, 9, "\(f) label fits a 3-column grid") }
        XCTAssertEqual(StrengthFocus.quickLog.map { $0.short }, ["Full Body", "Upper", "Lower", "Push", "Pull", "Custom"])
        for t in CyclingType.allCases { XCTAssertLessThanOrEqual(t.short.count, 9) }
    }
}
