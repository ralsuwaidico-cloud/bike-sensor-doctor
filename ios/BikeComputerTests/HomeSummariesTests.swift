import XCTest
@testable import BikeComputer

/// Checkpoint C correction pass (owner 6 Nov): the Home cards' destinations read records only. Weekly overview counts
/// (ledger + W12), day states (planned / done / missed / skipped / rest / before plan / multiple), cycling and strength
/// summaries (measured values or nil), the next planned session, and the Getting-started checklist's lifecycle.
final class HomeSummariesTests: XCTestCase {
    private let cal = Calendar.current
    private func store() -> Store {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("hs-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return Store(directory: d, generatePlan: false)
    }
    private func day(_ sport: DayAssignment.Sport?, _ minutes: Int = 0) -> DayAvailability {
        guard let s = sport else { return DayAvailability(activity: .rest, minutes: 0) }
        return DayAvailability(assignments: [DayAssignment(sport: s, minutes: minutes)])
    }
    private func hybrid(_ s: Store, supersets: Bool = true) {
        var p = RiderProfile.screened(); p.name = "Rashed"; p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = 3; p.liftingHoursPerWeek = 1
        p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 2; p.weekIsExplicit = true; p.goal = .endurance; p.goals = [.endurance]; p.primaryGoal = .endurance
        s.profile = p
        s.strengthPrefs.experience = .intermediate; s.strengthPrefs.prefersSupersets = supersets
        s.equipment = EquipmentPreset.gym.apply(to: s.equipment)
        s.availability = WeeklyAvailability(days: [day(.strength, 30), day(.cycling, 60), day(.strength, 30), day(.cycling, 60), day(nil), day(.cycling, 60), day(nil)])
    }
    /// NEXT week (regenerate never writes into days before the real today); "now" = that week's Wednesday 12:00.
    private var monday: Date { cal.date(byAdding: .day, value: 7, to: TrainingLedger.monday(of: Date()))! }
    private var wed: Date { cal.date(byAdding: .hour, value: 12, to: cal.date(byAdding: .day, value: 2, to: monday)!)! }
    private func d(_ i: Int) -> Date { cal.date(byAdding: .day, value: i, to: monday)! }
    private func ride(on d: Date, minutes: Int, km: Double, power: Int? = nil, hr: Int? = nil, cad: Int? = nil) -> RideRecord {
        var r = RideRecord(start: d, durationS: minutes * 60, distanceM: Int(km * 1000), recorder: .phone, sources: ["Phone GPS"])
        r.avgPower = power; r.avgHR = hr; r.avgCadence = cad
        return r
    }

    // MARK: 1 · weekly overview and ledger accuracy

    func testWeekOverviewCountsMatchTheLedgerAndExplainThePercentage() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let tueRide = s.plan.first { cal.isDate($0.date, inSameDayAs: d(1)) && $0.kind.isRide }!
        _ = s.addRide(ride(on: tueRide.date, minutes: 62, km: 28.4, power: 180, hr: 142))
        var thu = s.plan.first { cal.isDate($0.date, inSameDayAs: d(3)) && $0.kind.isRide }!; thu.skipped = true; s.update(thu)
        let o = s.homeWeekOverview(weekOf: wed, now: wed)
        XCTAssertEqual(o.planned, 4); XCTAssertEqual(o.done, 1); XCTAssertEqual(o.missed, 1, "Monday's lift"); XCTAssertEqual(o.remaining, 2); XCTAssertEqual(o.skipped, 1)
        XCTAssertEqual(o.restDays, 2); XCTAssertEqual(o.daysBeforePlan, 0)
        XCTAssertEqual(o.fraction, 0.25, accuracy: 0.001)
        XCTAssertTrue(o.explanation.hasPrefix("25% = 1 done ÷ 4 planned"), o.explanation)
        XCTAssertTrue(o.explanation.contains("Skipped sessions (1) are left out"), o.explanation)
        // the same numbers the ring shows
        let ring = s.homeDashboard(now: wed).ring!
        XCTAssertEqual([ring.planned, ring.done, ring.missed, ring.remaining], [o.planned, o.done, o.missed, o.remaining], "the ring and the overview count the same way")
        XCTAssertTrue(o.isCurrentWeek)
        XCTAssertEqual(o.days.count, 7)
        XCTAssertEqual(o.days.map(\.kind), [.training, .training, .training, .training, .rest, .training, .rest])
        XCTAssertEqual(o.days[1].items.first?.statusText, "Done")
        if case .ride = o.days[1].items.first!.record {} else { XCTFail("Tuesday's item carries its recording") }
        XCTAssertEqual(o.days[0].items.first?.statusText, "Missed")
        XCTAssertEqual(o.days[3].items.first?.statusText, "Skipped")
    }

    func testWeekOverviewPreStartDaysAreNeitherRestNorMissed() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: wed, replaceEdited: true)
        s.dropUnapprovedSessions(before: wed)
        let o = s.homeWeekOverview(weekOf: wed, now: wed)
        XCTAssertEqual(o.daysBeforePlan, 2); XCTAssertEqual(o.missed, 0)
        XCTAssertEqual(o.days[0].kind, .beforePlan)
        XCTAssertTrue(o.days[0].explanation.hasPrefix("Before this plan started."), o.days[0].explanation)
        XCTAssertNotNil(o.countedFrom)
        XCTAssertTrue(o.explanation.contains("Days before the plan became effective are not counted."))
    }

    func testWeekOverviewPreviousWeekWithNothingPlannedHasNoPercentage() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let o = s.homeWeekOverview(weekOf: cal.date(byAdding: .day, value: -7, to: monday)!, now: wed)
        XCTAssertEqual(o.planned, 0); XCTAssertFalse(o.isCurrentWeek)
        XCTAssertEqual(o.explanation, "No sessions are planned in this week, so there is no percentage.")
    }

    // MARK: 4–6 · calendar day → the right thing; multiple sessions; rest / missed / skipped / before plan

    func testDayDetailStatesAndMultipleSessions() {
        let s = store(); hybrid(s)
        s.availability = WeeklyAvailability(days: [day(.strength, 30), day(.cycling, 60), DayAvailability(assignments: [DayAssignment(sport: .cycling, minutes: 60), DayAssignment(sport: .strength, minutes: 30)]), day(.cycling, 60), day(nil), day(.cycling, 60), day(nil)])
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let wedDay = s.homeDayDetail(d(2), now: wed)
        XCTAssertEqual(wedDay.kind, .training)
        XCTAssertEqual(wedDay.items.count, 2, "both sessions individually listed")
        XCTAssertTrue(wedDay.explanation.hasPrefix("2 sessions this day"), wedDay.explanation)
        XCTAssertEqual(wedDay.availabilityLine, "Your week: ride · 1 h + strength · 30 min")
        let rest = s.homeDayDetail(d(4), now: wed)
        XCTAssertEqual(rest.kind, .rest); XCTAssertTrue(rest.items.isEmpty)
        XCTAssertTrue(rest.explanation.hasPrefix("Rest day — set as a rest day in Your week."), rest.explanation)
        XCTAssertEqual(rest.availabilityLine, "Your week: rest day")
        let mon = s.homeDayDetail(d(0), now: wed)
        XCTAssertEqual(mon.items.first?.statusText, "Missed")
        XCTAssertEqual(mon.items.first?.session?.action, .reschedule(mon.items.first!.session!.workout.id))
        // an unplanned ride on the rest day shows as a recorded item, never changes the plan
        _ = s.addRide(ride(on: cal.date(byAdding: .hour, value: 9, to: d(4))!, minutes: 40, km: 15))
        let restAfter = s.homeDayDetail(d(4), now: cal.date(byAdding: .day, value: 2, to: wed)!)
        XCTAssertEqual(restAfter.kind, .training); XCTAssertEqual(restAfter.items.count, 1)
        XCTAssertNil(restAfter.items.first?.session); XCTAssertEqual(restAfter.items.first?.statusText, "Recorded")
        XCTAssertEqual(s.plan.filter { HomeToday.isTraining($0) }.count, 6, "opening days never changed the plan")
    }

    func testDayDetailNoPlan() {
        let s = store(); hybrid(s)
        let dd = s.homeDayDetail(d(0), now: wed)
        XCTAssertEqual(dd.kind, .noPlan)
    }

    // MARK: 2 · cycling summary from recorded rides

    func testCyclingSummaryUsesMeasuredValuesOrNil() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        XCTAssertTrue(s.homeCyclingSummary(.week, now: wed).isEmpty)
        XCTAssertNotNil(s.homeCyclingSummary(.week, now: wed).next, "the next planned ride is shown even before the first ride")
        let tue = s.plan.first { cal.isDate($0.date, inSameDayAs: d(1)) && $0.kind.isRide }!
        _ = s.addRide(ride(on: tue.date, minutes: 60, km: 30, power: 200, hr: 140))
        _ = s.addRide(ride(on: cal.date(byAdding: .hour, value: 8, to: d(2))!, minutes: 30, km: 10, hr: 150, cad: 85))   // unplanned, no power
        let c = s.homeCyclingSummary(.week, now: wed)
        XCTAssertEqual(c.rides, 2); XCTAssertEqual(c.minutes, 90); XCTAssertEqual(c.km ?? 0, 40, accuracy: 0.01)
        XCTAssertEqual(c.avgPower, 200, "only the ride that measured power")
        XCTAssertEqual(c.avgHR, 143, "duration-weighted: (140·60 + 150·30) / 90")
        XCTAssertEqual(c.avgCadence, 85)
        XCTAssertEqual(c.recent.count, 2); XCTAssertTrue(c.recent[0].date > c.recent[1].date, "newest first")
        XCTAssertFalse(c.recent[0].planned); XCTAssertTrue(c.recent[1].planned)
        XCTAssertTrue(c.recent[1].line.contains("30.0 km") && c.recent[1].line.contains("200 W"), c.recent[1].line)
        XCTAssertEqual(c.next?.workout.kind.isRide, true); XCTAssertTrue(c.next!.workout.date > tue.date)
        // a ride without distance or sensors reports nil, never an estimate
        let s2 = store(); hybrid(s2)
        _ = s2.addRide(ride(on: cal.date(byAdding: .hour, value: 8, to: d(0))!, minutes: 45, km: 0))
        let c2 = s2.homeCyclingSummary(.all, now: wed)
        XCTAssertNil(c2.km); XCTAssertNil(c2.avgPower); XCTAssertNil(c2.avgHR); XCTAssertNil(c2.avgCadence); XCTAssertEqual(c2.minutes, 45)
        XCTAssertNil(c2.next)
    }

    func testCyclingSummaryPeriods() {
        let s = store(); hybrid(s)
        _ = s.addRide(ride(on: cal.date(byAdding: .day, value: -30, to: wed)!, minutes: 60, km: 20))
        _ = s.addRide(ride(on: cal.date(byAdding: .day, value: -10, to: wed)!, minutes: 60, km: 20))
        _ = s.addRide(ride(on: cal.date(byAdding: .hour, value: -3, to: wed)!, minutes: 60, km: 20))
        XCTAssertEqual(s.homeCyclingSummary(.week, now: wed).rides, 1)
        XCTAssertEqual(s.homeCyclingSummary(.fourWeeks, now: wed).rides, 2)
        XCTAssertEqual(s.homeCyclingSummary(.all, now: wed).rides, 3)
    }

    // MARK: 3 · strength summary from logs, supersets shown, next prescription with group letters

    func testStrengthSummaryShowsLoggedSetsAndTheNextPrescription() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let e0 = s.homeStrengthSummary(.week, now: wed)
        XCTAssertTrue(e0.isEmpty)
        XCTAssertNotNil(e0.next); XCTAssertFalse(e0.nextEntries.isEmpty, "the next prescription's lines")
        XCTAssertTrue(e0.nextEntries.contains { $0.hasPrefix("A1 ") } && e0.nextEntries.contains { $0.hasPrefix("A2 ") }, "superset group letters: \(e0.nextEntries)")
        // log Monday's session through the real lifecycle, with weights
        let mon = s.plan.first { cal.isDate($0.date, inSameDayAs: d(0)) && $0.kind == .strength }!
        var w = mon; w.date = cal.date(byAdding: .hour, value: 7, to: d(0))!; s.update(w)
        XCTAssertTrue(s.startStrengthSession(for: w, template: nil, entries: s.plannedEntries(for: w), now: w.date))
        s.updateActiveSession { ses in
            for i in ses.exercises!.indices { for j in ses.exercises![i].sets.indices { ses.exercises![i].sets[j].done = true; ses.exercises![i].sets[j].weightKg = i == 0 ? 80 : nil } }
        }
        let saved = s.finishActiveSession(rpe: 7, notes: "", now: w.date.addingTimeInterval(1800))!
        let st = s.homeStrengthSummary(.week, now: wed)
        XCTAssertEqual(st.sessions, 1); XCTAssertEqual(st.minutes, 30)
        XCTAssertEqual(st.recent.count, 1)
        let row = st.recent[0]
        XCTAssertEqual(row.id, saved.id); XCTAssertTrue(row.planned)
        XCTAssertGreaterThan(row.supersets, 0, "the logged superset groups are reported")
        XCTAssertTrue(row.line.contains("superset"), row.line)
        XCTAssertTrue(row.exercises[0].contains("@ 80 kg"), row.exercises[0])
        XCTAssertTrue(row.exercises[0].hasPrefix("A · "), "group letter on the logged exercise: \(row.exercises[0])")
        XCTAssertTrue(row.exercises.allSatisfy { !$0.contains("no set logged") })
        XCTAssertEqual(st.next?.workout.id != mon.id, true, "the next workout is the following planned one")
    }

    func testExerciseLineNeverInventsWeights() {
        let s = store(); hybrid(s)
        let cat = s.allExercises
        let sq = cat.first { ExerciseLibrary.meta($0).slot == .squat }!
        var e = ExerciseEntry(exercise: sq, sets: [SetEntry(reps: 6, done: true), SetEntry(reps: 6, done: true), SetEntry(reps: 6, done: false)])
        XCTAssertEqual(HomeSummariesModel.exerciseLine(e, units: .metric), "\(sq.name) 2×6")
        e.sets[0].weightKg = 60; e.sets[1].weightKg = 62.5
        XCTAssertEqual(HomeSummariesModel.exerciseLine(e, units: .metric), "\(sq.name) 2×6 @ 60–62.5 kg")
        e.sets[0].weightKg = nil; e.sets[1].weightKg = nil; e.sets[0].bodyweight = true
        XCTAssertEqual(HomeSummariesModel.exerciseLine(e, units: .metric), "\(sq.name) 2×6 · bodyweight")
        var none = e; none.sets = none.sets.map { var x = $0; x.done = false; return x }
        XCTAssertEqual(HomeSummariesModel.exerciseLine(none, units: .metric), "\(sq.name) · no set logged")
    }

    // MARK: 8 · getting started lifecycle; B4 · the plan-approved line counts this week's sessions like the ring

    func testSetupChecklistCountsLikeTheRingAndDisappearsWhenRequiredStepsAreDone() {
        let s = store(); hybrid(s)
        XCTAssertTrue(s.homeSetupItems(hrConnected: false, now: wed).isEmpty, "no plan, no checklist")
        _ = s.regenerate(weekOf: wed, replaceEdited: true)
        s.dropUnapprovedSessions(before: wed)                       // approved on Wednesday
        _ = s.regenerate(weekOf: cal.date(byAdding: .day, value: 7, to: monday)!, replaceEdited: true)   // next week exists too
        let items = s.homeSetupItems(hrConnected: false, now: wed)
        XCTAssertEqual(items.map(\.id), [.planApproved, .firstSession, .heartRate, .health])
        let ring = s.homeDashboard(now: wed).ring!
        XCTAssertEqual(items[0].detail, "Starts \(wed.dayAndDate) · \(ring.planned) session\(ring.planned == 1 ? "" : "s") this week · 5 next week", "B4: the same window as the ring, next week named separately")
        XCTAssertFalse(items[1].done); XCTAssertEqual(items[1].cta, "Open Plan")
        XCTAssertFalse(items[2].done); XCTAssertFalse(items[2].required); XCTAssertEqual(items[2].cta, "Open Connections")
        XCTAssertFalse(items[3].done); XCTAssertFalse(items[3].required)
        // heart rate connected → done, no CTA, no nagging
        let hr = s.homeSetupItems(hrConnected: true, now: wed)
        XCTAssertTrue(hr[2].done); XCTAssertNil(hr[2].cta); XCTAssertTrue(hr[2].detail.hasPrefix("Connected"))
        // first session recorded → the required steps are done → the checklist leaves Home
        _ = s.addRide(ride(on: wed, minutes: 40, km: 12))
        XCTAssertTrue(s.homeSetupItems(hrConnected: false, now: wed).isEmpty, "optional steps never keep the checklist on Home")
    }

    // MARK: 9 · empty versus recorded

    func testEmptyStatesAreExplicit() {
        let s = store(); hybrid(s)
        XCTAssertTrue(s.homeCyclingSummary(.all, now: wed).isEmpty)
        XCTAssertTrue(s.homeStrengthSummary(.all, now: wed).isEmpty)
        XCTAssertNil(s.homeStrengthSummary(.all, now: wed).next)
        XCTAssertTrue(s.homeStrengthSummary(.all, now: wed).nextEntries.isEmpty)
    }
}
