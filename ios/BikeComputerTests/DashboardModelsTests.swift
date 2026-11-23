import XCTest
@testable import BikeComputer

/// Training Mix and Recovery dashboards (owner, 23 Nov 2026, 19:55). Training Mix is a distribution of RECORDED time
/// that agrees with the Home ring's own numbers; Recovery shows the readings that exist, one metric at a time on its own
/// scale, with no score. Neither produces a figure the records do not hold.
final class DashboardModelsTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }
    private var monday: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 2))! }
    private func at(_ day: Int, _ hour: Int = 7) -> Date { cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: day, to: monday)!)! }
    private var now: Date { at(3, 12) }                                   // Thursday 5 Nov, 12:00
    private func ride(_ day: Int, minutes: Int, hour: Int = 8) -> RideRecord { RideRecord(start: at(day, hour), durationS: minutes * 60, distanceM: 20_000, recorder: .phone, sources: ["test"]) }
    private func input(_ plan: [Workout], rides: [RideRecord] = [], logs: [StrengthSession] = [], roster: [String] = ["roadCycling", "strength"]) -> ConsistencyModel.Input {
        .init(plan: plan, ledger: TrainingLedger(plan: plan, strength: logs, rides: rides, calendar: cal), roster: roster, planStart: plan.map(\.date).min(),
              title: { $0.kind.title }, now: now, calendar: cal)
    }

    func testTrainingMixIsRecordedTimeBySportAndAgreesWithTheHomeRing() {
        var marked = Workout(date: at(-5), kind: .endurance, minutes: 60); marked.completion = .marked; marked.manualMinutes = 50
        let plan = [Workout(date: at(-7), kind: .endurance, minutes: 60), Workout(date: at(-6), kind: .strength, minutes: 40, strengthFocus: .fullBody), marked,
                    Workout(date: at(-4, 7), kind: .strength, minutes: 40, strengthFocus: .fullBody), Workout(date: at(-4, 17), kind: .endurance, minutes: 45, sequence: 1)]
        let rides = [ride(-7, minutes: 58), ride(-1, minutes: 35)]
        let logs = [StrengthSession(date: at(-6, 18), minutes: 42, focus: .fullBody), StrengthSession(date: at(-4, 18), minutes: 38, focus: .fullBody)]
        let i = input(plan, rides: rides, logs: logs, roster: ["roadCycling", "indoorCycling", "strength", "running"])
        let d = TrainingMixModel.build(i, selectedWeek: 6)
        let w = d.week
        XCTAssertEqual(w.cycling, 58 + 35 + 50); XCTAssertEqual(w.strength, 42 + 38)
        XCTAssertEqual(w.plannedCycling, 60 + 60 + 45); XCTAssertEqual(w.plannedStrength, 80)
        let r = i.ledger.riding(weekOf: w.start), s = i.ledger.lifting(weekOf: w.start)
        XCTAssertEqual(w.cycling, r.minutes, "the Home ring's own riding minutes"); XCTAssertEqual(w.strength, s.minutes, "the Home ring's own strength minutes")
        XCTAssertEqual(w.plannedCycling, r.plannedMinutes); XCTAssertEqual(w.plannedStrength, s.plannedMinutes)
        XCTAssertEqual(w.tooltip, ["3 h 43 min · 26 Oct", "Cycling 64% · Strength 36%"])
        // days: Thursday holds a strength session recorded and a planned ride with nothing recorded
        XCTAssertEqual(d.days[3].strength, 38); XCTAssertEqual(d.days[3].cycling, 0); XCTAssertEqual(d.days[3].plannedCycling, 45)
        XCTAssertEqual(d.days[4].kind, .empty); XCTAssertEqual(d.days[4].tooltip, ["No recorded training · Fri"])
        XCTAssertTrue(TrainingMixModel.dayInsight(day: d.days[3], calendar: cal).contains("Planned and not recorded"))
        // sports: two cycling activities share one row; running is never 0 %
        XCTAssertEqual(d.sports.map(\.id), ["cycling", "strength", "running"])
        XCTAssertEqual(d.sports[0].share, 64); XCTAssertEqual(d.sports[1].share, 36)
        XCTAssertFalse(d.sports[2].tracked); XCTAssertNil(d.sports[2].share); XCTAssertEqual(d.sports[2].value, "Not recorded yet")
        XCTAssertTrue(d.weekInsight.contains("Cycling accounted for most of your recorded training in this week (64%)"), d.weekInsight)
        XCTAssertTrue(d.weekInsight.contains("does not record it yet"), d.weekInsight)
        XCTAssertFalse(d.weekInsight.lowercased().contains("balance") || d.weekInsight.lowercased().contains("overtrain"), "no balance is judged")
        // the unplanned Sunday ride is listed with its duration, outside the plan
        XCTAssertEqual(w.sessions.last?.detail, "35 min · not in the plan")
        XCTAssertEqual(TrainingMixDashboard.scale(d.weeks), 300, "the larger of recorded (3 h 43) and planned (4 h 5), up to the whole hour")
    }

    func testTrainingMixWithoutRecordsShowsNoFigureAndNoOtherSport() {
        let d = TrainingMixModel.build(input([], roster: ["running"]))
        XCTAssertFalse(d.hasRecords)
        XCTAssertTrue(d.weeks.allSatisfy { $0.kind == .empty && $0.total == 0 })
        XCTAssertEqual(d.sports.map(\.tracked), [false], "a runner sees no cycling or strength row")
        XCTAssertTrue(d.weekInsight.hasPrefix("No training is recorded yet this week."), d.weekInsight)
        XCTAssertEqual(d.days.map(\.kind), [.empty, .empty, .empty, .empty, .upcoming, .upcoming, .upcoming])
    }

    private func log(_ rows: [(HealthSample.Kind, Int, Double, String)]) -> RecoveryLog {
        var l = RecoveryLog()
        l.entries = rows.map { RecoveryEntry(kind: $0.0, value: $0.2, date: at($0.1, 6), source: $0.3) }.sorted { $0.date < $1.date }
        return l
    }

    func testRecoveryShowsOnlyReadingsThatExistEachMetricOnItsOwnScale() {
        var rows: [(HealthSample.Kind, Int, Double, String)] = []
        for d in [-7, -6, -5, -3, -2] { rows.append((.sleep, d, 7.0 + Double(d + 7) * 0.1, "Watch")) }      // last week: 5 nights
        for d in [0, 1, 3] { rows.append((.sleep, d, 6.5, "Watch")) }                                          // this week: 3 nights
        for d in [-7, -6, 0] { rows.append((.restingHR, d, 52, "Watch")) }
        let l = log(rows)
        let sleep = RecoveryDashModel.build(log: l, enabled: [.sleep, .restingHR, .hrv], metric: .sleep, selectedWeek: 6, now: now, calendar: cal)
        XCTAssertEqual(sleep.week.reading.count, 5); XCTAssertEqual(sleep.week.reading.value ?? 0, 7.24, accuracy: 0.001)
        XCTAssertEqual(sleep.week.tooltip.last, "5 of 7 nights")
        XCTAssertEqual(sleep.days.map(\.kind), [.value, .value, .value, .noReading, .value, .value, .noReading])
        XCTAssertEqual(sleep.days[0].tooltip.first, "7 h · Mon"); XCTAssertTrue(sleep.days[0].tooltip.last?.hasPrefix("Watch · ") ?? false, "the source and the time of the reading")
        XCTAssertNil(sleep.days[3].reading.value, "a day without a reading has none, never a zero")
        XCTAssertEqual(sleep.days[0].all.map { $0.value != nil }, [true, true, false], "the card lists all three, HRV as no reading")
        let scale = RecoveryDashboard.scale(sleep.days)!
        XCTAssertTrue(scale.low <= 7.0 && scale.high >= 7.5 && scale.high < 20, "hours on an hours scale: \(scale)")
        let hr = RecoveryDashModel.build(log: l, enabled: [.sleep, .restingHR, .hrv], metric: .restingHR, now: now, calendar: cal)
        let hrScale = RecoveryDashboard.scale(hr.weeks)!
        XCTAssertTrue(hrScale.low >= 40 && hrScale.high <= 65, "beats per minute on their own scale: \(hrScale)")
        // rows: sleep has a latest value and a source; HRV says no reading; nothing is a score
        XCTAssertEqual(sleep.rows.map { $0.latest != nil }, [true, true, false])
        XCTAssertTrue(sleep.rows[0].source.contains("Watch")); XCTAssertEqual(sleep.rows[2].status, "No reading yet")
        XCTAssertFalse(sleep.rows.contains { ($0.latest ?? "").contains("%") }, "no recovery percentage")
        // summaries
        XCTAssertTrue(sleep.weekInsight.contains("averaged") && sleep.weekInsight.contains("5 nights"), sleep.weekInsight)
        let cur = RecoveryDashModel.build(log: l, enabled: [.sleep], metric: .sleep, now: now, calendar: cal)
        XCTAssertTrue(cur.weekInsight.contains("lower than the week before"), cur.weekInsight)
        XCTAssertFalse(cur.weekInsight.lowercased().contains("ready") || cur.weekInsight.lowercased().contains("fatigue"), "no readiness or diagnosis")
        let hrv = RecoveryDashModel.build(log: l, enabled: [.sleep], metric: .hrv, now: now, calendar: cal)
        XCTAssertFalse(hrv.metricHasData); XCTAssertNil(RecoveryDashboard.scale(hrv.weeks))
        XCTAssertEqual(hrv.weekInsight, "There are no HRV readings yet, so there is nothing to describe.")
        XCTAssertEqual(hrv.rows[2].status, "Not connected")
        XCTAssertTrue(RecoveryDashModel.dayInsight(day: sleep.days[3], calendar: cal).contains("no sleep reading"))
    }

    func testRecoveryWithNoReadingsIsEmptyNotZero() {
        let d = RecoveryDashModel.build(log: RecoveryLog(), enabled: [], metric: .sleep, now: now, calendar: cal)
        XCTAssertFalse(d.hasAny); XCTAssertFalse(d.metricHasData)
        XCTAssertTrue(d.weeks.allSatisfy { $0.kind == .noReading && $0.reading.value == nil })
        XCTAssertEqual(d.rows.map(\.status), ["Not connected", "Not connected", "Not connected"])
        XCTAssertEqual(d.days.map(\.kind), [.noReading, .noReading, .noReading, .noReading, .upcoming, .upcoming, .upcoming])
    }
}
