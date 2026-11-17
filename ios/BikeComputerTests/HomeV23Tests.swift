import XCTest
@testable import BikeComputer

/// Home v2.3 (provisional design): the adapter from the athlete's records to the screen's models. Every number is the
/// ledger's, the plan's or the recovery log's; nothing is estimated; a missing reading stays missing.
final class HomeV23Tests: XCTestCase {
    private let cal = Calendar.current
    private func store() -> Store {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("h23-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return Store(directory: d, generatePlan: false)
    }
    private func day(_ sport: DayAssignment.Sport?, _ minutes: Int = 0) -> DayAvailability {
        guard let s = sport else { return DayAvailability(activity: .rest, minutes: 0) }
        return DayAvailability(assignments: [DayAssignment(sport: s, minutes: minutes)])
    }
    private func hybrid(_ s: Store) {
        var p = RiderProfile.screened(); p.name = "Sam Rider"; p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = 3; p.liftingHoursPerWeek = 1
        p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 2; p.weekIsExplicit = true; p.goal = .endurance; p.goals = [.endurance, .strength]; p.primaryGoal = .endurance
        s.profile = p
        s.availability = WeeklyAvailability(days: [day(.strength, 30), day(.cycling, 60), day(.strength, 30), day(.cycling, 60), day(nil), day(.cycling, 60), day(nil)])
    }
    /// The week under test is NEXT week (regenerate never writes into days before the real today); "now" is its Wednesday 12:00.
    private var monday: Date { cal.date(byAdding: .day, value: 7, to: TrainingLedger.monday(of: Date()))! }
    private var wed: Date { cal.date(byAdding: .hour, value: 12, to: cal.date(byAdding: .day, value: 2, to: monday)!)! }
    private func ride(on d: Date, minutes: Int, km: Double) -> RideRecord {
        RideRecord(start: d, durationS: minutes * 60, distanceM: Int(km * 1000), recorder: .phone, sources: ["Phone GPS"])
    }
    private func sample(_ k: HealthSample.Kind, _ v: Double, daysAgo: Int, from now: Date) -> RecoveryEntry {
        RecoveryEntry(kind: k, value: v, date: cal.date(byAdding: .hour, value: -6, to: cal.date(byAdding: .day, value: -daysAgo, to: now)!)!, source: "Apple Watch")
    }

    func testANewAthleteWithoutAPlanSeesNothingInvented() {
        let s = store()
        var p = RiderProfile.screened(); p.name = "Sam"; p.trainingMode = .hybrid; s.profile = p
        let h = s.homeV23(now: wed)
        XCTAssertEqual(h.name, "Sam"); XCTAssertEqual(h.initials, "S"); XCTAssertEqual(h.athleteType, "Hybrid")
        XCTAssertNil(h.consistency.fraction); XCTAssertEqual(h.consistency.caption, "No plan yet")
        XCTAssertNil(h.mix.ratioText, "no completed time, no ratio")
        XCTAssertEqual(h.recovery.state, .awaiting)
        XCTAssertTrue(h.days.isEmpty, "no plan: the schedule says so instead of drawing seven empty days")
        XCTAssertTrue(h.graph.isEmpty); XCTAssertNotNil(h.trendsEmpty)
        XCTAssertNil(h.sleep.lastNight); XCTAssertNil(h.sleep.average7); XCTAssertNil(h.sleep.target); XCTAssertFalse(h.sleep.canSetTarget)
        XCTAssertTrue(h.metrics.filter { $0.id != "ftp" }.allSatisfy { $0.value == nil }, "no reading is shown as a value")
        XCTAssertNil(h.metrics.first { $0.id == "ftp" }?.value, "the starting FTP assumption is never shown as an FTP")
    }

    func testConsistencyMixScheduleAndCardsComeFromTheLedger() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let week = s.plan.filter { $0.date >= monday && $0.date < cal.date(byAdding: .day, value: 7, to: monday)! && HomeToday.isTraining($0) }
        XCTAssertEqual(week.count, 5)
        let tue = week.first { cal.component(.weekday, from: $0.date) == 3 }!
        _ = s.addRide(ride(on: tue.date, minutes: 62, km: 28.4))
        let h = s.homeV23(now: wed)
        // consistency: 1 of 5 planned sessions done (Monday's lift is missed by Wednesday)
        XCTAssertEqual(h.consistency.fraction ?? -1, 0.2, accuracy: 0.001); XCTAssertEqual(h.consistency.text, "20%"); XCTAssertEqual(h.consistency.caption, "1 of 5 sessions")
        XCTAssertEqual(h.consistency.counts.first { $0.id == "missed" }?.value, "1")
        // mix: 62 of 180 planned ride minutes; no strength time yet; the centre ratio is completed time only
        let rideMinutes = week.filter { $0.kind.isRide }.reduce(0) { $0 + $1.minutes }
        XCTAssertGreaterThan(rideMinutes, 62)
        XCTAssertEqual(h.mix.endurance.minutesDone, 62); XCTAssertEqual(h.mix.endurance.minutesPlanned, rideMinutes)
        XCTAssertEqual(h.mix.endurance.fraction ?? -1, 62.0 / Double(rideMinutes), accuracy: 0.001)
        XCTAssertEqual(h.mix.strength.fraction ?? -1, 0, accuracy: 0.001); XCTAssertEqual(h.mix.ratioText, "100:0")
        // schedule: Monday's lift missed, Tuesday's ride completed, Wednesday's lift planned and today, Friday is a rest day
        XCTAssertEqual(h.days.count, 7)
        XCTAssertEqual(h.days[0].sessions.map(\.state), [.missed]); XCTAssertEqual(h.days[0].sessions.first?.category, .strength)
        XCTAssertEqual(h.days[1].sessions.map(\.state), [.completed]); XCTAssertEqual(h.days[1].sessions.first?.category, .endurance)
        XCTAssertEqual(h.days[2].sessions.map(\.state), [.planned]); XCTAssertTrue(h.days[2].isToday)
        XCTAssertTrue(h.days[4].sessions.isEmpty)
        // cards
        XCTAssertEqual(h.endurance?.done, "1 h 2 min"); XCTAssertEqual(h.endurance?.planned, Fmt.duration(minutes: rideMinutes)); XCTAssertEqual(h.endurance?.secondary, "28.4 km")
        XCTAssertEqual(h.strength?.done, "0"); XCTAssertEqual(h.strength?.planned, "2 sessions"); XCTAssertEqual(h.strength?.fraction ?? -1, 0, accuracy: 0.001)
    }

    func testTheGraphIsRecordedMinutesAndDaysBeforeTheFirstRecordAreGaps() {
        let s = store(); hybrid(s)
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let tue = cal.date(byAdding: .day, value: 1, to: monday)!
        _ = s.addRide(ride(on: cal.date(byAdding: .hour, value: 8, to: tue)!, minutes: 62, km: 28.4))
        let h = s.homeV23(now: wed)
        XCTAssertEqual(h.graph.map(\.id), ["7d", "4w"])
        guard let r7 = h.graph.first, let act = r7.modes.first(where: { $0.id == "activity" }) else { return XCTFail("7-day activity") }
        XCTAssertEqual(r7.dates.count, 7); XCTAssertEqual(r7.modes.map(\.id), ["activity", "trends"], "no load-against-recovery-score mode exists")
        let e = act.series.first { $0.id == "endurance" }!.values, p = act.series.first { $0.id == "planned" }!.values
        XCTAssertEqual(e[5], 62, "Tuesday (yesterday) shows the recorded 62 minutes"); XCTAssertEqual(e[6], 0, "today: nothing recorded yet is zero, a fact")
        func plannedMinutes(_ d: Date) -> Double { Double(s.plan.filter { cal.isDate($0.date, inSameDayAs: d) && HomeToday.isTraining($0) && !$0.skipped }.reduce(0) { $0 + $1.minutes }) }
        XCTAssertGreaterThan(plannedMinutes(tue), 0)
        XCTAssertEqual(p[5], plannedMinutes(tue), "Tuesday's planned minutes are the plan's"); XCTAssertEqual(p[6], plannedMinutes(wed), "Wednesday's planned minutes are the plan's")
        XCTAssertFalse(act.series.contains { $0.isSampleScore }, "nothing on the graph is sample data")
        // 4 weeks: each point is the total of the day and the six before it
        let e28 = h.graph[1].modes[0].series.first { $0.id == "endurance" }!.values
        XCTAssertEqual(e28.count, 28); XCTAssertEqual(e28[27], 62); XCTAssertEqual(e28[26], 62)
        XCTAssertNil(e28[0], "four weeks ago is before this athlete's first record: a gap, not a zero")
        XCTAssertEqual(HomeV23Builder.rolling7([0, 10, 0, 5], lead: [1, 1, 1, 1, 1, 1]), [6, 15, 14, 18])
        XCTAssertTrue(cal.isDate(HomeV23Builder.date(ofColumn: 5, count: 7, now: wed, calendar: cal), inSameDayAs: tue))
    }

    func testRecoveryIsAStatusNeverANumber() {
        func metric(_ k: HealthSample.Kind, _ values: [Double], now: Date) -> RecoveryMetric {
            var log = RecoveryLog()
            log.entries = values.enumerated().map { i, v in sample(k, v, daysAgo: values.count - 1 - i, from: now) }
            return RecoveryAnalysis.metric(k, log: log, now: now)
        }
        let now = wed
        let steady = Array(repeating: 7.5, count: 12)
        // nothing connected
        XCTAssertEqual(HomeV23Builder.recovery(metrics: [], advice: nil).state, .awaiting)
        // one of three readings
        let one = HomeV23Builder.recovery(metrics: [metric(.sleep, steady, now: now)], advice: nil)
        XCTAssertEqual(one.state, .partial(word: "1 of 3 readings")); XCTAssertEqual(one.sources.count, 3); XCTAssertNil(one.sources[1].value)
        // all three, fresh, each with a usual range, all inside it
        let all = [metric(.sleep, steady, now: now), metric(.restingHR, Array(repeating: 52, count: 12), now: now), metric(.hrv, Array(repeating: 60, count: 12), now: now)]
        XCTAssertEqual(HomeV23Builder.recovery(metrics: all, advice: nil).state, .qualitative(word: "In your usual range"))
        // a short history has no usual range: no statement is made
        let short = [metric(.sleep, [7.5, 7.4], now: now), metric(.restingHR, [52, 53], now: now), metric(.hrv, [60, 61], now: now)]
        XCTAssertEqual(HomeV23Builder.recovery(metrics: short, advice: nil).state, .partial(word: "No usual range yet"))
        // resting HR clearly above the usual range
        let high = [all[0], metric(.restingHR, Array(repeating: 52, count: 11) + [70], now: now), all[2]]
        XCTAssertEqual(HomeV23Builder.recovery(metrics: high, advice: nil).state, .qualitative(word: "Outside your usual range"))
        // the key-metric row: the value, the athlete's own range, a neutral direction
        let row = HomeV23Builder.metric(.restingHR, high[1])
        XCTAssertEqual(row.value, "70"); XCTAssertEqual(row.unit, "bpm"); XCTAssertEqual(row.direction, .up); XCTAssertTrue(row.baseline?.hasPrefix("usual ") ?? false, row.baseline ?? "nil")
        XCTAssertNil(HomeV23Builder.metric(.hrv, nil).value)
    }

    func testSleepShowsLastNightOnlyWhenFreshAndAnAverageOnlyFromThreeNights() {
        let now = wed
        var log = RecoveryLog()
        log.entries = [sample(.sleep, 7.0, daysAgo: 0, from: now), sample(.sleep, 8.0, daysAgo: 1, from: now)]
        var m = RecoveryAnalysis.metric(.sleep, log: log, now: now)
        var sl = HomeV23Builder.sleep(metric: m, log: log, now: now, calendar: cal)
        XCTAssertEqual(sl.lastNight, 420); XCTAssertNil(sl.average7, "two nights are not an average"); XCTAssertNil(sl.target)
        log.entries.append(sample(.sleep, 6.0, daysAgo: 2, from: now)); log.entries.sort { $0.date < $1.date }
        m = RecoveryAnalysis.metric(.sleep, log: log, now: now)
        sl = HomeV23Builder.sleep(metric: m, log: log, now: now, calendar: cal)
        XCTAssertEqual(sl.average7, 420)
        // the newest night is three days old: it is not "last night"
        var old = RecoveryLog(); old.entries = [sample(.sleep, 7.0, daysAgo: 3, from: now)]
        XCTAssertNil(HomeV23Builder.sleep(metric: RecoveryAnalysis.metric(.sleep, log: old, now: now), log: old, now: now, calendar: cal).lastNight)
    }

    func testACyclingOnlyAthleteHasNoStrengthCardOrLine() {
        let s = store()
        var p = RiderProfile.screened(); p.name = "Lee"; p.trainingMode = .cycling; s.profile = p
        let h = s.homeV23(now: wed)
        XCTAssertNil(h.strength); XCTAssertNotNil(h.endurance)
        XCTAssertNil(h.mix.strength.fraction)
        XCTAssertEqual(HomeV23Builder.initials("  lee  van  dyke "), "LV"); XCTAssertEqual(HomeV23Builder.initials(""), "")
    }
}
