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
        var skipped = Workout(date: at(-3), kind: .tempo, minutes: 60); skipped.skipped = true
        let plan = [Workout(date: at(-7), kind: .endurance, minutes: 60), Workout(date: at(-6), kind: .strength, minutes: 40, strengthFocus: .fullBody), marked,
                    Workout(date: at(-4, 7), kind: .strength, minutes: 40, strengthFocus: .fullBody), Workout(date: at(-4, 17), kind: .endurance, minutes: 45, sequence: 1), skipped]
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
        // the planned-time line of each period is that period's own planned, not skipped, sessions (owner, 24 Nov 2026)
        XCTAssertEqual(d.days.map(\.planned), [60, 40, 60, 85, 0, 0, 0], "Friday's skipped ride plans nothing; Thursday's two sessions add up")
        XCTAssertEqual(d.days.map(\.planned).reduce(0, +), w.planned, "the days add up to the week")
        XCTAssertTrue(d.days[3].spoken.hasSuffix("1 h 25 min planned") && d.days[4].spoken.hasSuffix("nothing planned"))
        XCTAssertEqual(d.weeks[7].planned, 0); XCTAssertEqual(d.weeks[5].planned, 0, "a week without a plan has no planned line")
        // sports: two cycling activities share one row; running is never 0 %
        XCTAssertEqual(d.sports.map(\.id), ["cycling", "strength", "running"])
        XCTAssertEqual(d.sports[0].share, 64); XCTAssertEqual(d.sports[1].share, 36)
        XCTAssertFalse(d.sports[2].tracked); XCTAssertNil(d.sports[2].share); XCTAssertEqual(d.sports[2].value, "Not recorded yet")
        // Changed 24 Nov 2026 on the owner's instruction: the Coach note is a short interpretation and no longer repeats the
        // graph's figures or the roster note (the sport rows say which sports are not recorded).
        // Changed again 24 Nov 2026 (15:18) on the owner's instruction: the note speaks of training types and sets them
        // beside the athlete's stated priorities; here running cannot be recorded, so it says the comparison cannot be made.
        XCTAssertEqual(d.weekInsight, "Endurance made up most of your recorded training in this week. Road running is not recorded, so this cannot be compared with your priorities.")
        // training types: both cycling activities and running are Endurance; only running is unrecorded
        XCTAssertEqual(d.types.map(\.type), [.endurance, .strength])
        XCTAssertEqual(d.types[0].members, ["Road cycling", "Indoor cycling", "Road running"]); XCTAssertEqual(d.types[0].unrecorded, ["Road running"])
        XCTAssertEqual(d.types[0].share, 64); XCTAssertEqual(d.types[0].completed, 3); XCTAssertEqual(d.types[1].completed, 2)
        XCTAssertNotNil(d.types[0].gap); XCTAssertNil(d.types[1].gap)
        XCTAssertEqual(w.tooltip(byType: true), ["3 h 43 min · 26 Oct", "Endurance 64% · Strength 36%"])
        XCTAssertNil(d.weekInsight.rangeOfCharacter(from: .decimalDigits), "no figure of the graph is repeated")
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
        XCTAssertEqual(d.weekInsight, "Nothing is recorded yet this week.")
        XCTAssertEqual(d.days.map(\.kind), [.empty, .empty, .empty, .empty, .upcoming, .upcoming, .upcoming])
    }

    func testTrainingTypesPlaceOnlyWhatIsPlainAndKeepRecoveryPracticesApart() {
        func t(_ id: String) -> TrainingType? { AthleticRoster.activity(id).flatMap { TrainingType.of($0) } }
        for id in ["roadCycling", "indoorCycling", "mountainBike", "gravel", "commuting", "running", "treadmill", "trailRunning", "swimming", "openWater"] { XCTAssertEqual(t(id), .endurance, id) }
        for id in ["strength", "freeWeights", "machines", "bodyweight", "calisthenics"] { XCTAssertEqual(t(id), .strength, id) }
        XCTAssertEqual(t("mobility"), .mobility)
        XCTAssertEqual(t("walking"), .other); XCTAssertEqual(t("hiking"), .other, "ambiguous purpose: not placed")
        XCTAssertNil(t("breathing")); XCTAssertNil(t("sauna"), "recovery practices are not training")
        let d = TrainingMixModel.build(input([], roster: ["running", "strength", "mobility", "walking", "sauna"]))
        XCTAssertEqual(d.types.map(\.type), [.endurance, .strength, .mobility, .other])
        XCTAssertEqual(d.types.map(\.measurable), [false, true, false, false], "only gym training can be recorded in this roster")
        XCTAssertEqual(d.types[0].value, "Not recorded yet"); XCTAssertNil(d.types[0].share)
        XCTAssertEqual(d.practices.count, 1); XCTAssertEqual(d.unrecorded.count, 3)
    }

    func testCoachNoteSetsRecordedTimeBesideTheStatedPriorityWithoutAnIdealRatio() {
        func p(_ c: Int, _ s: Int, planned: Int = 0) -> MixPoint {
            var m = TrainingMixModel.build(input([], roster: ["roadCycling", "strength"])).weeks[6]
            m.cycling = c; m.strength = s; m.plannedCycling = planned; m.kind = .recorded; return m
        }
        func note(_ c: Int, _ s: Int, _ pr: TrainingPriority?, unrecorded: [String] = []) -> String {
            TrainingMixModel.weekInsight(week: p(c, s), current: false, unrecorded: unrecorded, declared: MixDeclared(priority: pr))
        }
        XCTAssertEqual(note(200, 80, .cycling), "Endurance made up most of your recorded training in this week. By time, that is in line with the endurance-led priority you stated.")
        XCTAssertEqual(note(200, 80, .strength), "Endurance made up most of your recorded training in this week. You stated a strength-led priority; by time, the week leaned to endurance.")
        XCTAssertEqual(note(200, 80, .balanced), "Endurance made up most of your recorded training in this week. You stated a balanced priority; by time, the week leaned to endurance.")
        XCTAssertEqual(note(110, 100, .balanced), "Endurance made up most of your recorded training in this week. By time, that is close to the balanced priority you stated.")
        XCTAssertEqual(note(0, 80, nil, unrecorded: ["Road running"]), "All of your recorded training in this week was strength. Road running is not recorded, so this cannot be compared with your priorities.")
        XCTAssertEqual(note(200, 0, nil), "All of your recorded training in this week was endurance. None of it was planned.")
        for n in [note(200, 80, .cycling), note(200, 80, .strength), note(110, 100, .balanced)] {
            XCTAssertNil(n.rangeOfCharacter(from: .decimalDigits), "no ratio or figure"); XCTAssertFalse(n.lowercased().contains("optimal") || n.lowercased().contains("should"), "no prescription")
        }
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
        XCTAssertEqual(sleep.week.tooltip.count, 1, "one line, placed like the Consistency label"); XCTAssertTrue(sleep.week.tooltip[0].hasPrefix("Avg 7 h 14 min · "), sleep.week.tooltip[0])
        XCTAssertEqual(sleep.days.map(\.kind), [.value, .value, .value, .noReading, .value, .value, .noReading])
        XCTAssertEqual(sleep.days[0].tooltip, ["7 h · Mon"]); XCTAssertEqual(sleep.days[0].reading.source, "Watch", "the source stays with the reading, for the card")
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
        // "your usual range" only with the real personal baseline: at least 7 earlier readings in the 28 days before the latest
        XCTAssertTrue(sleep.rows[0].trend.contains("your usual range · ") && sleep.rows[0].trend.hasSuffix("from 7 nights"), sleep.rows[0].trend)
        XCTAssertEqual(sleep.rows[1].trend, "No usual range yet · 2 of the 7 earlier readings needed")
        XCTAssertFalse(sleep.rows[1].trend.contains("your usual range"), "no range is invented for two earlier readings")
        XCTAssertEqual(sleep.rows[2].trend, "No reading")
        XCTAssertEqual(sleep.rows.map { $0.latestDate != nil }, [true, true, false], "the header can date each latest reading")
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

    func testLineChartLabelStaysAtItsPointWhenTheConsistencyRuleWouldSendItToTheTop() {
        let W = 300.0, H = 212.0, w = 118.0, h = 26.0
        // a zigzag: neighbours above and below on both sides, so no place is free of them
        let px = 150.0, py = 106.0
        let others = [(113.0, 80.0), (187.0, 80.0), (113.0, 132.0), (187.0, 132.0), (76.0, 106.0), (224.0, 106.0)]
        XCTAssertEqual(ConsistencyTooltip.place(px: px, py: py, w: w, h: h, width: W, height: H, others: others).side, .top, "the Consistency rule alone gives up here")
        let r = DashTooltipRule.place(px: px, py: py, w: w, h: h, width: W, height: H, others: others)
        XCTAssertTrue(["above", "below"].contains(r.side), "the label stays at its point (\(r.side))")
        XCTAssertFalse(r.box.covers(px, py, margin: 0), "and never covers it")
        XCTAssertTrue(r.box.minX >= 0 && r.box.maxX <= W && r.box.minY >= 0 && r.box.maxY <= H, "inside the chart")
        XCTAssertLessThanOrEqual(abs(r.box.y - py), ConsistencyTooltip.gap + h, "directly above or below, not at the top")
        // where the Consistency rule finds a free place, it is used unchanged
        let free = DashTooltipRule.place(px: px, py: py, w: w, h: h, width: W, height: H, others: [])
        XCTAssertEqual(free.side, "above"); XCTAssertEqual(free.box, ConsistencyTooltip.place(px: px, py: py, w: w, h: h, width: W, height: H, others: []).box)
        // every point of a dense, irregular line, at every height the scale allows
        for k in 0..<8 {
            let xs = (0..<8).map { 34.0 + 33.25 * (Double($0) + 0.5) }
            let ys = (0..<8).map { 40.0 + Double(($0 * 53 + 17) % 132) }
            let o = (0..<8).filter { $0 != k }.map { (xs[$0], ys[$0]) }
            let t = DashTooltipRule.place(px: xs[k], py: ys[k], w: w, h: h, width: W, height: H, others: o)
            XCTAssertNotEqual(t.side, "top", "point \(k) keeps its label beside it")
            XCTAssertTrue(t.box.minX >= 0 && t.box.maxX <= W && t.box.minY >= 0 && t.box.maxY <= H && !t.box.covers(xs[k], ys[k], margin: 0), "point \(k): \(t)")
        }
    }
}
