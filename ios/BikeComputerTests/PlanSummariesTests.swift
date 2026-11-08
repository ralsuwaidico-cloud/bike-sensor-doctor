import XCTest
@testable import BikeComputer

/// Checkpoint C2 — Plan / Orbit: the six-band Plan screen reads the SAME ledger as Home (ring, states, minutes), shows
/// the next unfinished session with Start / Resume only when the Training Hub would allow it, carries the coach's
/// stored reason, and counts pending proposals without mixing them into the week.
final class PlanSummariesTests: XCTestCase {
    private let cal = Calendar.current
    private func store() -> Store {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("ps-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return Store(directory: d, generatePlan: false)
    }
    private func day(_ sport: DayAssignment.Sport?, _ minutes: Int = 0) -> DayAvailability {
        guard let s = sport else { return DayAvailability(activity: .rest, minutes: 0) }
        return DayAvailability(assignments: [DayAssignment(sport: s, minutes: minutes)])
    }
    private func hybrid(_ s: Store) {
        var p = RiderProfile.screened(); p.name = "Rashed"; p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = 3; p.liftingHoursPerWeek = 1
        p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 2; p.weekIsExplicit = true; p.goal = .endurance; p.goals = [.endurance]; p.primaryGoal = .endurance
        s.profile = p; s.strengthPrefs.experience = .intermediate; s.equipment = EquipmentPreset.gym.apply(to: s.equipment)
        s.availability = WeeklyAvailability(days: [day(.strength, 30), day(.cycling, 60), day(.strength, 30), day(.cycling, 60), day(nil), day(.cycling, 60), day(nil)])
    }
    private var monday: Date { cal.date(byAdding: .day, value: 7, to: TrainingLedger.monday(of: Date()))! }
    private var wed: Date { cal.date(byAdding: .hour, value: 12, to: cal.date(byAdding: .day, value: 2, to: monday)!)! }
    private func d(_ i: Int) -> Date { cal.date(byAdding: .day, value: i, to: monday)! }

    func testRingMinutesAndTimelineComeFromTheSameLedgerAsHome() {
        let s = store(); hybrid(s); _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let tueRide = s.plan.first { cal.isDate($0.date, inSameDayAs: d(1)) && $0.kind.isRide }!
        var r = RideRecord(start: tueRide.date, durationS: 62 * 60, distanceM: 28_400, recorder: .phone, sources: ["Phone GPS"]); r.avgPower = 180; _ = s.addRide(r)
        var thu = s.plan.first { cal.isDate($0.date, inSameDayAs: d(3)) && $0.kind.isRide }!; thu.skipped = true; s.update(thu)
        let p = s.planWeekSummary(weekOf: wed, now: wed)
        let home = s.homeWeekOverview(weekOf: wed, now: wed)
        XCTAssertEqual(p.overview, home, "band B is Home's overview, not a second calculation")
        XCTAssertEqual(p.overview.done, 1); XCTAssertEqual(p.overview.planned, 4)
        XCTAssertEqual(p.recordedMinutes, 62, "feature A: recorded minutes come from the ride that was recorded")
        XCTAssertEqual(p.plannedMinutes, s.ledger.riding(weekOf: monday).plannedMinutes + s.ledger.lifting(weekOf: monday).plannedMinutes)
        XCTAssertTrue(p.minutesLine.hasPrefix("1 h 2 min recorded of"), p.minutesLine)   // Fmt.duration's established format
        XCTAssertEqual(p.timeline.count, 7); XCTAssertEqual(p.timeline.first?.shortName.count, 3)
        XCTAssertEqual(p.timeline[1].chips.first?.mark, .done); XCTAssertEqual(p.timeline[1].chips.first?.sport, .ride)
        XCTAssertEqual(p.timeline[0].chips.first?.mark, .missed, "Monday's lift is missed by Wednesday")
        XCTAssertEqual(p.timeline[3].chips.first?.mark, .skipped)
        XCTAssertTrue(p.timeline[4].rest && p.timeline[4].chips.isEmpty, "Friday is a rest day")
        XCTAssertTrue(p.timeline[2].isToday)
        XCTAssertEqual(p.timeline.map(\.weekday), (0..<7).map { cal.component(.weekday, from: d($0)) }, "planDay-<weekday> identifiers keep their meaning")
        XCTAssertTrue(p.timeline[0].accessibilityLabel.contains("missed"), p.timeline[0].accessibilityLabel)
    }

    func testNextSessionStartResumeOrOpenFollowsTheHubRules() {
        let s = store(); hybrid(s); _ = s.regenerate(weekOf: monday, replaceEdited: true)
        // Wednesday noon: today's lift is the next unfinished session → Start
        let p = s.planWeekSummary(weekOf: wed, now: wed)
        let n = try! XCTUnwrap(p.next)
        XCTAssertTrue(cal.isDate(s.plan.first { $0.id == n.workoutId }!.date, inSameDayAs: wed))
        XCTAssertEqual(n.button, .start); XCTAssertTrue(n.subtitle.hasPrefix("Today"), n.subtitle)
        // a recording in progress → Open (never a second session)
        XCTAssertEqual(s.planWeekSummary(weekOf: wed, now: wed, recorderActive: true).next?.button, .open)
        // looking at the week from Monday morning: Monday's lift is next
        let mon = cal.date(byAdding: .hour, value: 8, to: monday)!
        XCTAssertEqual(s.planWeekSummary(weekOf: mon, now: mon).next.map { n in cal.isDate(s.plan.first { w in w.id == n.workoutId }!.date, inSameDayAs: mon) }, true)
        // a week in the past has no next session
        let lastWeek = cal.date(byAdding: .day, value: -7, to: monday)!
        XCTAssertNil(s.planWeekSummary(weekOf: lastWeek, now: wed).next)
        // a health hold removes Start but keeps Open
        var hold = s.profile; var hs = HealthScreen(); hs.answeredAt = Date(); hs.chestPain = true; hold.healthScreen = hs; s.profile = hold
        if !s.profile.readiness.trainingAllowed { XCTAssertEqual(s.planWeekSummary(weekOf: wed, now: wed).next?.button, .open) }
    }

    func testWhyComesOnlyFromStoredRationale() {
        var w = Workout(date: Date(), kind: .strength, minutes: 30)
        XCTAssertNil(PlanSummaries.why(w), "no rationale stored → no invented reason")
        w.rationale = SessionRationale(generatedAt: Date(), goal: "Hypertrophy", notes: ["Full body because you lift twice a week"], exercises: [], deload: false)
        XCTAssertEqual(PlanSummaries.why(w), "Full body because you lift twice a week")
        w.rationale?.deload = true
        XCTAssertTrue(PlanSummaries.why(w)!.hasPrefix("Deload week"))
        w.rationale = SessionRationale(generatedAt: Date(), goal: "Endurance", notes: [], exercises: [], deload: false)
        XCTAssertEqual(PlanSummaries.why(w), "Endurance", "goal is the fallback when there are no notes")
    }

    func testPendingProposalsAreCountedNotMixedIntoTheWeek() {
        let s = store(); hybrid(s); _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let before = s.planWeekSummary(weekOf: wed, now: wed)
        XCTAssertEqual(before.pendingProposals, 0)
        let lift = s.plan.first { cal.isDate($0.date, inSameDayAs: d(2)) && $0.kind == .strength }!
        var req = lift; req.minutes = 20
        let outcome = s.requestEdit(req)
        if case .preview = outcome {
            let after = s.planWeekSummary(weekOf: wed, now: wed)
            XCTAssertEqual(after.pendingProposals, 1, "the strip counts the pending proposal")
            XCTAssertEqual(after.timeline, before.timeline, "the timeline still shows the approved plan — the proposal lives only in its strip and sheet")
        }
    }
}
