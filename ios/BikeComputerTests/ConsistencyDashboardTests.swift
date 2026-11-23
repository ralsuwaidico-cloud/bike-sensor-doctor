import XCTest
@testable import BikeComputer

/// Consistency Dashboard (owner, 23 Nov 2026): one definition — completed eligible planned sessions ÷ eligible planned
/// sessions — read from the same ledger as the Home ring. No percentage without planned sessions; a rest day, a later
/// day and a roster sport Cyclift does not track are never shown as 0 %; unplanned recordings are never counted.
final class ConsistencyDashboardTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }
    /// Monday 2 Nov 2026; "now" is Thursday 5 Nov, 12:00.
    private var monday: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 2))! }
    private func at(_ day: Int, _ hour: Int = 7) -> Date { cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: day, to: monday)!)! }
    private var now: Date { at(3, 12) }
    private func ride(_ day: Int, _ hour: Int = 8) -> RideRecord { RideRecord(start: at(day, hour), durationS: 3600, distanceM: 20_000, recorder: .phone, sources: ["test"]) }
    private func build(_ plan: [Workout], rides: [RideRecord] = [], logs: [StrengthSession] = [], roster: [String] = ["roadCycling", "strength"], week: Int? = nil) -> ConsistencyDashboard {
        let l = TrainingLedger(plan: plan, strength: logs, rides: rides, calendar: cal)
        return ConsistencyModel.build(.init(plan: plan, ledger: l, roster: roster, planStart: plan.map(\.date).min(), title: { $0.kind.title }, now: now, calendar: cal), selectedWeek: week)
    }

    func testCurrentWeekCountsCompletedMissedSkippedAndNeverTurnsLaterSessionsIntoMissed() {
        var skipped = Workout(date: at(1), kind: .tempo, minutes: 60); skipped.skipped = true
        let plan = [Workout(date: at(0), kind: .endurance, minutes: 60),                      // done (ride recorded)
                    Workout(date: at(2), kind: .strength, minutes: 40, strengthFocus: .fullBody),   // missed
                    skipped,                                                                   // skipped: in neither number
                    Workout(date: at(3), kind: .endurance, minutes: 60),                      // today, open
                    Workout(date: at(5), kind: .long, minutes: 120)]                          // later
        let d = build(plan, rides: [ride(0), ride(1, 18)])
        let w = d.week
        XCTAssertEqual(w.count, ConsistencyCount(planned: 4, done: 1, missed: 1, skipped: 1))
        XCTAssertEqual(w.count.open, 2)
        XCTAssertEqual(w.kind, .inProgress); XCTAssertEqual(w.percent, 25); XCTAssertNil(w.band, "a week in progress carries no band")
        XCTAssertEqual(d.unplanned.count, 1, "the ride on the skipped day is listed, not counted")
        XCTAssertEqual(d.days.map(\.kind), [.evaluated, .rest, .evaluated, .inProgress, .rest, .upcoming, .rest])
        XCTAssertEqual(d.days[0].percent, 100); XCTAssertEqual(d.days[2].percent, 0); XCTAssertEqual(d.days[2].band, .low)
        XCTAssertNil(d.days[1].percent, "a skipped-only day has no percentage"); XCTAssertNil(d.days[4].percent, "a rest day is never 0 %")
        XCTAssertNil(d.days[5].percent, "a later day has no percentage"); XCTAssertEqual(d.days[5].count.missed, 0)
        XCTAssertTrue(d.overallInsight.contains("1 of 4"), d.overallInsight); XCTAssertTrue(d.overallInsight.contains("Missed: 1 strength session."), d.overallInsight)
    }

    func testTwoSessionsOnOneDayWithOneCompletedIsFiftyPercentAndOneRecordCompletesOneSession() {
        let plan = [Workout(date: at(1, 7), kind: .endurance, minutes: 60), Workout(date: at(1, 17), kind: .endurance, minutes: 45, sequence: 1),
                    Workout(date: at(2), kind: .strength, minutes: 40, strengthFocus: .fullBody)]
        let d = build(plan, rides: [ride(1)], logs: [StrengthSession(date: at(2, 18), minutes: 40, focus: .fullBody)])
        XCTAssertEqual(d.days[1].count, ConsistencyCount(planned: 2, done: 1, missed: 1, skipped: 0))
        XCTAssertEqual(d.days[1].percent, 50); XCTAssertEqual(d.days[1].band, .moderate)
        XCTAssertEqual(d.days[1].sessions.map(\.state), [.completed, .missed])
        XCTAssertEqual(d.days[2].percent, 100); XCTAssertEqual(d.days[2].band, .high)
    }

    func testEightWeeksEvaluatedBandsComparisonAndWeeksWithoutPlannedSessions() {
        var plan: [Workout] = [], rides: [RideRecord] = []
        // last week: 4 of 5 (80 %, high) · two weeks ago: 3 of 5 (60 %, moderate) · three weeks ago: 1 of 4 (25 %, low)
        for (weeksAgo, planned, done) in [(1, 5, 4), (2, 5, 3), (3, 4, 1)] {
            for k in 0..<planned {
                plan.append(Workout(date: at(-7 * weeksAgo + k), kind: .endurance, minutes: 60))
                if k < done { rides.append(ride(-7 * weeksAgo + k)) }
            }
        }
        let d = build(plan, rides: rides, week: 6)
        XCTAssertEqual(d.weeks.count, 8)
        XCTAssertEqual(d.weeks.suffix(4).map(\.percent), [25, 60, 80, nil])
        XCTAssertEqual(d.weeks.suffix(4).map(\.band), [.low, .moderate, .high, nil])
        XCTAssertEqual(d.weeks[7].kind, .noPlanned, "this week has no planned session: no percentage, not 0 %")
        XCTAssertEqual(d.weeks[0].kind, .beforePlan)
        XCTAssertTrue(d.overallInsight.contains("4 of 5") && d.overallInsight.contains("higher than the week before (60%)"), d.overallInsight)
        XCTAssertFalse(d.isCurrentWeek); XCTAssertEqual(d.days.filter { $0.kind == .evaluated }.count, 5)
    }

    func testSportRowsSeparateSportsAndNeverShowZeroForAnUntrackedSport() {
        let plan = [Workout(date: at(-7), kind: .endurance, minutes: 60), Workout(date: at(-6), kind: .endurance, minutes: 60),
                    Workout(date: at(-5), kind: .strength, minutes: 40, strengthFocus: .fullBody), Workout(date: at(-3), kind: .strength, minutes: 40, strengthFocus: .fullBody)]
        let d = build(plan, rides: [ride(-7), ride(-6)], logs: [StrengthSession(date: at(-5, 18), minutes: 40, focus: .fullBody)],
                      roster: ["roadCycling", "indoorCycling", "strength", "running", "swimming"], week: 6)
        XCTAssertEqual(d.sports.map(\.id), ["cycling", "strength", "running", "swimming"], "two cycling activities share the one planned sport")
        XCTAssertEqual(d.sports[0].percent, 100); XCTAssertEqual(d.sports[1].percent, 50); XCTAssertEqual(d.sports[1].count.missed, 1)
        XCTAssertFalse(d.sports[2].tracked); XCTAssertNil(d.sports[2].percent); XCTAssertEqual(d.sports[2].status, "Not tracked yet")
        XCTAssertTrue(d.sportInsight.contains("Cycling (100%) was more consistent than strength (50%)"), d.sportInsight)
        XCTAssertTrue(d.sportInsight.contains("\(d.sports[2].name) and \(d.sports[3].name) are in your roster"), d.sportInsight)
    }

    func testNoPlanHasNoPercentageAnywhere() {
        let d = build([], rides: [ride(1)], roster: ["running"])
        XCTAssertFalse(d.hasPlan)
        XCTAssertTrue(d.weeks.allSatisfy { $0.percent == nil && $0.band == nil })
        XCTAssertTrue(d.days.allSatisfy { $0.percent == nil })
        XCTAssertEqual(d.week.kind, .noPlanned); XCTAssertEqual(d.days[0].kind, .noPlanned)
        XCTAssertTrue(d.overallInsight.contains("no training plan yet"), d.overallInsight)
        XCTAssertEqual(d.sports.first?.status, "Not tracked yet")
        XCTAssertEqual(d.unplanned.count, 1)
    }

    func testAgreesWithTheHomeRingAndLeavesOtherKindsOut() {
        let plan = [Workout(date: at(0), kind: .endurance, minutes: 60), Workout(date: at(1), kind: .strength, minutes: 40, strengthFocus: .fullBody),
                    Workout(date: at(2), kind: .mobility, minutes: 30), Workout(date: at(5), kind: .long, minutes: 120)]
        let rides = [ride(0)]
        let d = build(plan, rides: rides)
        let l = TrainingLedger(plan: plan, strength: [], rides: rides, calendar: cal)
        let r = l.riding(weekOf: monday), s = l.lifting(weekOf: monday)
        XCTAssertEqual(d.week.count.planned, r.planned + s.planned); XCTAssertEqual(d.week.count.done, r.plannedDone + s.plannedDone)
        XCTAssertEqual(d.week.sessions.first { $0.workoutID == plan[2].id }?.state, .notCounted)
        XCTAssertEqual(ConsistencyBand.of(percent: 80), .high); XCTAssertEqual(ConsistencyBand.of(percent: 79), .moderate)
        XCTAssertEqual(ConsistencyBand.of(percent: 50), .moderate); XCTAssertEqual(ConsistencyBand.of(percent: 49), .low)
    }

    func testTooltipSaysTheFigureOrTheTruthfulStatusAndTheSummaryFollowsTheChosenDay() {
        var skipped = Workout(date: at(1), kind: .tempo, minutes: 60); skipped.skipped = true
        let plan = [Workout(date: at(0, 7), kind: .endurance, minutes: 60), Workout(date: at(0, 17), kind: .endurance, minutes: 45, sequence: 1), skipped,
                    Workout(date: at(3), kind: .endurance, minutes: 60), Workout(date: at(5), kind: .long, minutes: 120)]
        let d = build(plan, rides: [ride(0), ride(2)])
        XCTAssertEqual(d.days[0].tooltip, "50% · Mon")
        XCTAssertEqual(d.days[1].tooltip, "Skipped · Tue"); XCTAssertEqual(d.days[2].tooltip, "Nothing planned · Wed")
        XCTAssertEqual(d.days[3].tooltip, "In progress · 0%"); XCTAssertEqual(d.days[4].tooltip, "Rest day · Fri"); XCTAssertEqual(d.days[5].tooltip, "Upcoming · Sat")
        XCTAssertTrue(d.week.tooltip.hasPrefix("In progress · "))
        XCTAssertFalse(d.days.filter { $0.percent == nil }.contains { $0.tooltip.contains("%") }, "no figure is shown where none exists")
        let mon = ConsistencyModel.dayInsight(day: d.days[0], hasPlan: true, calendar: cal)
        XCTAssertTrue(mon.contains("1 of 2") && mon.contains("Monday") && mon.contains("Missed: Endurance."), mon)
        XCTAssertTrue(ConsistencyModel.dayInsight(day: d.days[2], hasPlan: true, calendar: cal).contains("outside the plan"))
        XCTAssertTrue(ConsistencyModel.dayInsight(day: d.days[5], hasPlan: true, calendar: cal).contains("Not due yet"))
        XCTAssertEqual(build([], roster: ["running"]).week.tooltip.prefix(7), "No plan")
    }

    func testTooltipStaysInsideTheChartAndNeverCoversAPoint() {
        let W = 300.0, H = 176.0, w = 96.0, h = 26.0
        // above when there is room
        var r = ConsistencyTooltip.place(px: 150, py: 100, w: w, h: h, width: W, height: H, others: [])
        XCTAssertEqual(r.side, .above); XCTAssertEqual(r.box.maxY, 100 - ConsistencyTooltip.gap, accuracy: 0.01)
        // at the left and right edges it stays inside
        for px in [10.0, 290.0] {
            r = ConsistencyTooltip.place(px: px, py: 100, w: w, h: h, width: W, height: H, others: [])
            XCTAssertGreaterThanOrEqual(r.box.minX, 0); XCTAssertLessThanOrEqual(r.box.maxX, W)
        }
        // a neighbour just above the label's place: it goes below instead
        r = ConsistencyTooltip.place(px: 150, py: 100, w: w, h: h, width: W, height: H, others: [(185, 76)])
        XCTAssertEqual(r.side, .below); XCTAssertFalse(r.box.covers(185, 76, margin: 5))
        // no room above (a point at the very top) and a neighbour below: beside, or the top strip — never outside, never on a point
        for py in stride(from: 4.0, through: 172.0, by: 12.0) {
            for px in stride(from: 18.0, through: 282.0, by: 37.0) {
                let others = [(px - 37, py + 20), (px + 37, py - 20), (px + 37, py + 30), (px - 37, py - 30)]
                let t = ConsistencyTooltip.place(px: px, py: py, w: w, h: h, width: W, height: H, others: others)
                XCTAssertTrue(t.box.minX >= 0 && t.box.maxX <= W && t.box.minY >= 0 && t.box.maxY <= H, "inside the chart at \(px), \(py): \(t)")
                if t.side != .top { XCTAssertFalse(t.box.covers(px, py, margin: 0), "never over the chosen point at \(px), \(py)") }
            }
        }
    }
}
