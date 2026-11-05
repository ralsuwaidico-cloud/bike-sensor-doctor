import XCTest
@testable import BikeComputer

/// Checkpoint C: the Home dashboard's numbers come from records, never estimates; the calendar's day states; the hub state.
final class HomeDashboardTests: XCTestCase {
    private let cal = Calendar.current
    private func store() -> Store {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("hd-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return Store(directory: d, generatePlan: false)
    }
    private func day(_ sport: DayAssignment.Sport?, _ minutes: Int = 0) -> DayAvailability {
        guard let s = sport else { return DayAvailability(activity: .rest, minutes: 0) }
        return DayAvailability(assignments: [DayAssignment(sport: s, minutes: minutes)])
    }
    private func hybrid(_ s: Store) {
        var p = RiderProfile.screened(); p.name = "Rashed"; p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = 3; p.liftingHoursPerWeek = 1
        p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 2; p.weekIsExplicit = true; p.goal = .endurance; p.goals = [.endurance, .strength]; p.primaryGoal = .endurance
        s.profile = p
        s.availability = WeeklyAvailability(days: [day(.strength, 30), day(.cycling, 60), day(.strength, 30), day(.cycling, 60), day(nil), day(.cycling, 60), day(nil)])
    }
    /// The week under test is NEXT week (regenerate never writes into days before the real today); "now" inside the tests
    /// is that week's Wednesday 12:00.
    private var monday: Date { cal.date(byAdding: .day, value: 7, to: TrainingLedger.monday(of: Date()))! }
    private var wed: Date { cal.date(byAdding: .hour, value: 12, to: cal.date(byAdding: .day, value: 2, to: monday)!)! }
    private func ride(on d: Date, minutes: Int, km: Double) -> RideRecord {
        RideRecord(start: d, durationS: minutes * 60, distanceM: Int(km * 1000), recorder: .phone, sources: ["Phone GPS"])
    }

    // MARK: header

    func testGreetingFollowsTheClockAndTheName() {
        XCTAssertEqual(HomeDashboardModel.greeting(hour: 8, name: "Rashed"), "Good morning, Rashed")
        XCTAssertEqual(HomeDashboardModel.greeting(hour: 14, name: "Rashed"), "Good afternoon, Rashed")
        XCTAssertEqual(HomeDashboardModel.greeting(hour: 20, name: " "), "Good evening")
    }

    func testContextLineNamesModeWeekAndToday() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let d = s.homeDashboard(now: wed)
        XCTAssertTrue(d.header.context.hasPrefix("Hybrid · week 1"), d.header.context)
        XCTAssertTrue(d.header.context.hasSuffix("lift today"), d.header.context)
        XCTAssertEqual(d.header.greeting, "Good afternoon, Rashed")
    }

    // MARK: ring — planned ÷ done from the ledger; the W12 window note when the plan started after Monday

    func testRingCountsPlannedDoneRemainingAndMissed() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let week = s.plan.filter { $0.date >= monday && $0.date < cal.date(byAdding: .day, value: 7, to: monday)! && HomeToday.isTraining($0) }
        XCTAssertEqual(week.count, 5)
        // Tuesday's ride recorded; Monday's lift not done (missed by Wednesday)
        let tue = week.first { cal.component(.weekday, from: $0.date) == 3 }!
        _ = s.addRide(ride(on: tue.date, minutes: 62, km: 28.4))
        let d = s.homeDashboard(now: wed)
        guard let r = d.ring else { return XCTFail("ring") }
        XCTAssertEqual(r.planned, 5); XCTAssertEqual(r.done, 1); XCTAssertEqual(r.missed, 1); XCTAssertEqual(r.remaining, 3)
        XCTAssertEqual(r.fraction, 0.2, accuracy: 0.001)
        XCTAssertNil(r.countedNote, "a plan that started on Monday needs no note")
        XCTAssertTrue(r.sub.hasPrefix("3 remaining · "), r.sub)
    }

    func testRingNoteWhenThePlanStartedMidWeek() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: wed, replaceEdited: true)
        s.dropUnapprovedSessions(before: wed)                  // approved on Wednesday: nothing stays in Mon/Tue (the approval path)
        let d = s.homeDashboard(now: wed)
        XCTAssertEqual(d.ring?.countedNote, "Counted from the day you approved the plan.")
        XCTAssertEqual(d.days[0].status, .beforePlan); XCTAssertEqual(d.days[1].status, .beforePlan)
        XCTAssertEqual(d.days[0].accessibilityLabel, "Monday, Before this plan started")
        XCTAssertEqual(d.ring?.missed, 0, "days before the plan are never missed")
    }

    // MARK: calendar states

    func testCalendarShowsDonePlannedMissedRestAndBothCorrectly() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let week = s.plan.filter { $0.date >= monday && HomeToday.isTraining($0) }
        let tue = week.first { cal.component(.weekday, from: $0.date) == 3 }!
        _ = s.addRide(ride(on: tue.date, minutes: 62, km: 28.4))
        let d = s.homeDashboard(now: wed)
        XCTAssertEqual(d.days.map(\.status), [.missed, .done, .planned, .planned, .none, .planned, .none])
        XCTAssertEqual(d.days.map(\.sport), [.strength, .cycling, .strength, .cycling, .rest, .cycling, .rest])
        XCTAssertTrue(d.days[2].isToday)
        XCTAssertEqual(d.days[2].accessibilityLabel, "Today, Wednesday, strength, planned")
        XCTAssertEqual(d.days[0].accessibilityLabel, "Monday, strength, missed")
    }

    func testTodayIsNeverMissedAndSkippedDaysAreNotMissed() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        var mon = s.plan.first { cal.isDate($0.date, inSameDayAs: monday) && $0.kind == .strength }!
        mon.skipped = true; s.update(mon)
        let d = s.homeDashboard(now: wed)
        XCTAssertEqual(d.days[0].status, .none, "a skipped session is not missed")
        XCTAssertEqual(d.days[2].status, .planned, "today's open session is planned, not missed")
        XCTAssertEqual(d.ring?.missed, 1, "only Tuesday's unrecorded ride is missed")
        XCTAssertEqual(d.ring?.skipped, 1)
        XCTAssertEqual(d.ring?.planned, 4, "a skipped session leaves the planned count")
    }

    // MARK: sport tiles — recorded values only

    func testCyclingTileUsesRecordedTimeAndDistance() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let before = s.homeDashboard(now: wed).cycling!
        XCTAssertEqual(before.value, "0 of 3"); XCTAssertEqual(before.tag, .needsData)
        XCTAssertTrue(before.sub.hasPrefix("rides · "), before.sub)
        let tue = s.plan.first { cal.component(.weekday, from: $0.date) == 3 && $0.kind.isRide }!
        _ = s.addRide(ride(on: tue.date, minutes: 62, km: 28.4))
        let after = s.homeDashboard(now: wed).cycling!
        XCTAssertEqual(after.value, Fmt.duration(minutes: 62))
        XCTAssertEqual(after.tag, .measured)
        XCTAssertTrue(after.sub.contains("1 ride") && after.sub.contains("28.4 km"), after.sub)
        XCTAssertEqual(after.series.count, 8)
        XCTAssertEqual(after.series.last ?? nil, 62, "this week's bucket is the recorded minutes")
        XCTAssertNil(after.series[6] ?? nil, "weeks before the first ride draw nothing")
    }

    func testStrengthTileCountsLoggedSessionsAgainstThePlan() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let t0 = s.homeDashboard(now: wed).strength!
        XCTAssertEqual(t0.value, "0 of 2"); XCTAssertEqual(t0.tag, .needsData)
        XCTAssertTrue(t0.sub.contains("first lift today"), t0.sub)
        let mon = s.plan.first { cal.isDate($0.date, inSameDayAs: monday) && $0.kind == .strength }!
        _ = s.addStrength(StrengthSession(date: mon.date, minutes: 31, focus: .fullBody, rpe: 7, exercises: [], workoutId: mon.id))
        let t1 = s.homeDashboard(now: wed).strength!
        XCTAssertEqual(t1.value, "1 of 2"); XCTAssertEqual(t1.tag, .logged)
        XCTAssertEqual(t1.series.last ?? nil, 1)
    }

    // MARK: recovery and goal — nothing invented

    func testRecoveryIsEmptyWithoutHealthReadsAndShowsDatedValuesWithThem() {
        let s = store(); hybrid(s)
        XCTAssertFalse(s.homeDashboard(now: wed).recovery.hasData)
        s.settings.healthReads.restingHR = true; s.settings.healthReads.sleep = true
        let t = cal.date(byAdding: .hour, value: -5, to: wed)!
        _ = s.applyHealthSamples([HealthSample(kind: .restingHR, value: 52, date: t), HealthSample(kind: .sleep, value: 7.4, date: t), HealthSample(kind: .hrv, value: 60, date: t)], now: wed)
        let r = s.homeDashboard(now: wed).recovery
        XCTAssertEqual(r.readings.map(\.title), ["Sleep", "Resting HR"], "only enabled reads; no HRV without permission")
        XCTAssertEqual(r.readings.first?.value, "7.4"); XCTAssertEqual(r.readings.last?.value, "52")
        XCTAssertEqual(r.readings.first?.date, t)
    }

    func testGoalCardMeasuresFromRecordsOnly() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let g0 = s.homeDashboard(now: wed).goal!
        XCTAssertEqual(g0.title, "Endurance"); XCTAssertTrue(g0.isMain)
        XCTAssertEqual(g0.measured, "Progress appears after your first logged ride.")
        XCTAssertEqual(g0.next, "Complete this week's 2 rides.")
        let tue = s.plan.first { cal.component(.weekday, from: $0.date) == 3 && $0.kind.isRide }!
        _ = s.addRide(ride(on: tue.date, minutes: 62, km: 28.4))
        let g1 = s.homeDashboard(now: wed).goal!
        XCTAssertTrue(g1.measured.hasPrefix("1 ride recorded"), g1.measured)
    }

    // MARK: reminder and hub state

    func testReminderAndHubStateFollowToday() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let d = s.homeDashboard(now: wed)
        XCTAssertEqual(d.hub, .pending)
        XCTAssertTrue(d.reminder?.title.hasPrefix("Strength · ") == true, d.reminder?.title ?? "")
        XCTAssertEqual(d.reminder?.sub, "Open the Training Hub to start")
        // done → completed, no reminder
        let w = s.plan.first { cal.isDate($0.date, inSameDayAs: wed) && $0.kind == .strength }!
        _ = s.addStrength(StrengthSession(date: wed, minutes: 30, focus: .fullBody, rpe: 7, exercises: [], workoutId: w.id))
        let done = s.homeDashboard(now: wed)
        XCTAssertEqual(done.hub, .completed); XCTAssertNil(done.reminder)
        // Friday (rest) with Monday missed → missed; Sunday with nothing missed in the window still reports the missed Monday
        let fri = cal.date(byAdding: .day, value: 2, to: wed)!
        XCTAssertEqual(s.homeDashboard(now: fri).hub, .missed)
        // first use: no plan
        let fresh = store(); hybrid(fresh)
        XCTAssertEqual(fresh.homeDashboard(now: wed).hub, .first)
        XCTAssertNil(fresh.homeDashboard(now: wed).ring)
    }

    func testHubStateMultipleAndActive() {
        let s = store(); hybrid(s)
        s.availability = WeeklyAvailability(days: [day(.strength, 30), day(.cycling, 60), DayAvailability(assignments: [DayAssignment(sport: .cycling, minutes: 60), DayAssignment(sport: .strength, minutes: 30)]), day(.cycling, 60), day(nil), day(.cycling, 60), day(nil)])
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let d = s.homeDashboard(now: wed)
        XCTAssertEqual(d.hub, .multiple, "\(d.days[2])")
        XCTAssertEqual(d.days[2].sport, .both)
        if let w = s.plan.first(where: { cal.isDate($0.date, inSameDayAs: wed) && $0.kind == .strength }) {
            XCTAssertTrue(s.startStrengthSession(for: w, template: nil, entries: s.plannedEntries(for: w), now: wed))
            XCTAssertEqual(s.homeDashboard(now: wed).hub, .active)
            XCTAssertEqual(s.homeDashboard(now: wed).reminder?.sub, "Open the Training Hub to resume")
        }
    }
}
