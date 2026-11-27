import XCTest
@testable import BikeComputer

/// Key Metrics hub (owner's approved design direction, 27 Nov 2026, 11:40). Every figure comes from records the app
/// already holds; a metric with no source has no value; a missing reading is nil, never zero; no score is calculated.
final class KeyMetricsTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }
    private let now = Date(timeIntervalSince1970: 1_795_000_000)       // a fixed moment in Nov 2026
    private func day(_ back: Int, hour: Int = 7) -> Date { cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: now))!)! }
    private func log(_ kind: HealthSample.Kind, _ values: [(back: Int, v: Double)]) -> RecoveryLog {
        RecoveryLog(entries: values.map { RecoveryEntry(kind: kind, value: $0.v, date: day($0.back), source: "Test watch") }.sorted { $0.date < $1.date })
    }
    private func entry(_ id: String, _ name: String, reps: Int, kg: Double?, sets: Int = 3) -> ExerciseEntry {
        let s = (0..<sets).map { _ in "{\"reps\":\(reps),\(kg.map { "\"weightKg\":\($0)," } ?? "")\"bodyweight\":\(kg == nil),\"unilateral\":false,\"done\":true}" }.joined(separator: ",")
        return try! JSONDecoder().decode(ExerciseEntry.self, from: Data("{\"exerciseId\":\"\(id)\",\"name\":\"\(name)\",\"pattern\":\"squat\",\"sets\":[\(s)],\"notes\":\"\"}".utf8))
    }
    private func session(_ back: Int, _ e: [ExerciseEntry], rpe: Int? = nil) -> StrengthSession { var l = StrengthSession(date: day(back, hour: 18), minutes: 40, focus: .fullBody); l.exercises = e; l.rpe = rpe; return l }

    func testTheSixteenMetricsAndTheirFourCategoriesAreExactlyAsApproved() {
        XCTAssertEqual(KeyMetricCategory.allCases.map(\.title), ["Heart & recovery", "Sleep & wellness", "Activity & performance", "Advanced insights"])
        XCTAssertEqual(KeyMetricCategory.heart.metrics.map(\.name), ["Resting heart rate", "HRV", "Blood oxygen (SpO₂)", "Respiratory rate"])
        XCTAssertEqual(KeyMetricCategory.sleep.metrics.map(\.name), ["Sleep duration", "Sleep stages", "Daily energy", "Stress & soreness"])
        XCTAssertEqual(KeyMetricCategory.activity.metrics.map(\.name), ["Daily steps", "Active calories", "Heart rate zones", "Strength progression"])
        XCTAssertEqual(KeyMetricCategory.advanced.metrics.map(\.name), ["Recovery readiness", "Training strain", "Recovery vs. strain", "Personal baselines"])
        let sixteen = KeyMetricCategory.allCases.flatMap(\.metrics)
        XCTAssertEqual(Set(sixteen).count, 16); XCTAssertFalse(sixteen.contains(.ftp), "FTP is an extra Home option, not one of the sixteen")
        // a metric without a source says why, in words — and the scores say that nothing is calculated
        for m in [KeyMetricID.spo2, .respiratory, .sleepStages, .dailyEnergy, .steps, .activeCalories, .hrZones, .readiness, .strain, .recoveryVsStrain] {
            XCTAssertNotNil(m.unavailableLine, m.rawValue); XCTAssertFalse(m.unavailableDetail.isEmpty, m.rawValue)
        }
        XCTAssertEqual(KeyMetricID.readiness.unavailableLine, "No score is calculated")
        for m in [KeyMetricID.restingHR, .hrv, .sleepDuration, .strength, .stressSoreness, .baselines] { XCTAssertNil(m.unavailableLine, m.rawValue) }
    }

    func testAHealthMetricShowsItsReadingsItsUsualRangeAndLeavesAMissingDayEmpty() {
        // 20 days of resting heart rate, with day 3 missing
        let l = log(.restingHR, (0..<21).filter { $0 != 3 }.map { ($0, 50 + Double($0 % 5)) })
        let d = KeyMetricsModel.health(.restingHR, log: l, enabled: [.restingHR], period: 1, now: now, calendar: cal)!
        XCTAssertEqual(d.latest, "50"); XCTAssertEqual(d.unit, "bpm"); XCTAssertEqual(d.source, "Test watch")
        XCTAssertEqual(d.points.count, 30)
        XCTAssertNil(d.points[29 - 3].value, "a day without a reading has no value")
        XCTAssertFalse(d.points.contains { $0.value == 0 }, "and it is never zero")
        XCTAssertNil(d.points[0].value, "nor is a day before the first reading")
        XCTAssertEqual(d.points[29].value, 50)
        XCTAssertNotNil(d.rangeText); XCTAssertTrue(d.standingLine.contains("your usual range"), d.standingLine)
        XCTAssertTrue(d.rangeBasis.hasPrefix("From 19 readings in the 28 days"), d.rangeBasis)
        let lo = d.low!, hi = d.high!
        XCTAssertTrue(lo <= d.bandLow! && d.bandHigh! <= hi, "the scale holds the usual range")
        XCTAssertTrue(d.points.compactMap(\.value).allSatisfy { $0 >= lo && $0 <= hi })
        XCTAssertTrue(d.summary.hasPrefix("Over the last 30 days your recorded resting heart rate averaged"), d.summary)
        // 7 days are days; 90 days are weekly averages
        XCTAssertEqual(KeyMetricsModel.health(.restingHR, log: l, enabled: [.restingHR], period: 0, now: now, calendar: cal)!.points.count, 7)
        let w = KeyMetricsModel.health(.restingHR, log: l, enabled: [.restingHR], period: 2, now: now, calendar: cal)!
        XCTAssertEqual(w.points.count, 13); XCTAssertTrue(w.points.allSatisfy(\.isWeek)); XCTAssertNil(w.bandLow, "a day's range is not drawn over weekly averages")
        XCTAssertNil(w.points[0].value, "a week without a reading has no value")
        // a chosen day outside the range is described, without a conclusion
        var p = d.points[29]; p.value = 70; p.standing = .higher
        let s = KeyMetricsModel.pointInsight(p, kind: .restingHR)
        XCTAssertTrue(s.contains("above your usual range") && s.contains("draws no health conclusion"), s)
        XCTAssertTrue(KeyMetricsModel.pointInsight(d.points[26], kind: .restingHR).hasPrefix("There is no resting heart rate reading for"))
    }

    func testTooFewReadingsGiveNoUsualRangeAndNoReadingsGiveNothing() {
        let few = KeyMetricsModel.health(.hrv, log: log(.hrv, (0..<5).map { ($0, 60) }), enabled: [.hrv], period: 1, now: now, calendar: cal)!
        XCTAssertEqual(few.latest, "60"); XCTAssertNil(few.rangeText); XCTAssertNil(few.bandLow)
        XCTAssertEqual(few.standingLine, "No usual range yet · 4 of the 7 earlier readings needed")
        XCTAssertTrue(few.summary.contains("There is no usual range yet"), few.summary)
        let none = KeyMetricsModel.health(.sleepDuration, log: RecoveryLog(), enabled: [], period: 1, now: now, calendar: cal)!
        XCTAssertNil(none.latest); XCTAssertFalse(none.hasAny); XCTAssertFalse(none.enabled); XCTAssertNil(none.low)
        XCTAssertEqual(none.standingLine, "No reading"); XCTAssertTrue(none.points.allSatisfy { $0.value == nil })
        XCTAssertEqual(none.summary, "There are no sleep readings yet, so there is nothing to describe.")
        XCTAssertNil(KeyMetricsModel.health(.steps, log: RecoveryLog(), enabled: [], period: 1, now: now, calendar: cal), "steps have no stored reading at all")
        // sleep is written as a duration
        let sl = KeyMetricsModel.health(.sleepDuration, log: log(.sleep, (0..<10).map { ($0, 7.2) }), enabled: [.sleep], period: 0, now: now, calendar: cal)!
        XCTAssertEqual(sl.latest, "7 h 12 min"); XCTAssertEqual(sl.unit, "")
    }

    func testStrengthProgressionIsExerciseByExerciseAndUsesTheDayPageRule() {
        let logs = [session(21, [entry("sq", "Squat", reps: 10, kg: 20), entry("row", "Row", reps: 10, kg: 16)]),
                    session(14, [entry("sq", "Squat", reps: 10, kg: 22.5)]),
                    session(7, [entry("sq", "Squat", reps: 10, kg: 22.5), entry("row", "Row", reps: 10, kg: 16, sets: 4)]),
                    session(1, [entry("sq", "Squat", reps: 10, kg: 25)])]
        let s = KeyMetricsModel.strength(logs, selected: nil, period: 2, measure: 0, units: .metric, now: now, calendar: cal)
        XCTAssertEqual(s.exercises.map(\.name), ["Squat", "Row"], "the exercise recorded most often comes first")
        XCTAssertEqual(s.selected, "sq"); XCTAssertEqual(s.points.count, 4); XCTAssertEqual(s.points.map(\.top), [20, 22.5, 22.5, 25])
        XCTAssertEqual(s.comparison?.verdict, .better); XCTAssertEqual(s.comparison?.change, "Top load +2.5 kg")
        XCTAssertEqual(s.comparison?.metrics.first { $0.id == "sq-load" }?.previous, "22.5 kg")
        XCTAssertEqual(s.comparison?.metrics.first { $0.id == "sq-load" }?.current, "25 kg")
        XCTAssertTrue(s.summary.contains("top load was higher 2 times and lower 0 times"), s.summary)
        // 7 days hold only the latest session — nothing to compare inside the period, but the latest comparison still stands
        let week = KeyMetricsModel.strength(logs, selected: "sq", period: 0, measure: 0, units: .metric, now: now, calendar: cal)
        XCTAssertEqual(week.points.count, 1); XCTAssertTrue(week.summary.hasPrefix("One Squat session is recorded in the last 7 days"), week.summary)
        // a different number of sets is not comparable — more work is not called an improvement
        let row = KeyMetricsModel.strength(logs, selected: "row", period: 2, measure: 3, units: .metric, now: now, calendar: cal)
        XCTAssertEqual(row.name, "Row"); XCTAssertEqual(row.comparison?.verdict, .notComparable)
        XCTAssertTrue(row.comparison!.metrics.allSatisfy { $0.verdict != .better && $0.verdict != .worse })
        // a clearly higher reported effort withholds the verdict, as on the Day page
        let hard = KeyMetricsModel.strength([session(7, [entry("sq", "Squat", reps: 10, kg: 20)], rpe: 5), session(1, [entry("sq", "Squat", reps: 10, kg: 25)], rpe: 8)],
                                            selected: nil, period: 2, measure: 0, units: .metric, now: now, calendar: cal)
        XCTAssertEqual(hard.comparison?.verdict, .notComparable)
        // one session: recorded, nothing to compare with; none: nothing
        let one = KeyMetricsModel.strength([session(1, [entry("sq", "Squat", reps: 10, kg: 25)])], selected: nil, period: 2, measure: 0, units: .metric, now: now, calendar: cal)
        XCTAssertNil(one.comparison?.previous); XCTAssertEqual(one.comparison?.verdict, .notComparable)
        let none = KeyMetricsModel.strength([], selected: nil, period: 2, measure: 0, units: .metric, now: now, calendar: cal)
        XCTAssertFalse(none.hasAny); XCTAssertNil(none.comparison); XCTAssertTrue(none.points.isEmpty)
    }

    func testSorenessListsOnlyWhatWasAnsweredAndAnUnansweredReviewIsNotNoSoreness() {
        var a = session(3, [entry("sq", "Squat", reps: 10, kg: 20)]); a.review = SessionReview(pain: .soreness)
        let b = session(1, [entry("sq", "Squat", reps: 10, kg: 20)])          // no review at all
        let s = KeyMetricsModel.soreness(rides: [], strength: [a, b], now: now, calendar: cal)
        XCTAssertEqual(s.sessions, 2); XCTAssertEqual(s.answers.count, 1); XCTAssertEqual(s.answers.first?.answer, "Normal soreness")
        XCTAssertTrue(s.summary.contains("after 1 of your 2 recorded sessions") && s.summary.contains("not counted as no soreness"), s.summary)
        XCTAssertTrue(KeyMetricsModel.soreness(rides: [], strength: [b], now: now, calendar: cal).answers.isEmpty)
    }

    func testTheHomeChoiceIsStoredInItsOwnFileAndHoldsAtMostFour() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("km-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertNil(KeyMetricsPrefs.load(dir), "no file = no choice made = Home keeps its defaults")
        XCTAssertTrue(KeyMetricsPrefs.save([.hrv, .strength, .ftp, .restingHR, .sleepDuration], dir: dir))
        XCTAssertEqual(KeyMetricsPrefs.load(dir), [.hrv, .strength, .ftp, .restingHR], "four at most, in the athlete's order")
        try! Data("[\"hrv\",\"hrv\",\"nonsense\",\"ftp\"]".utf8).write(to: dir.appendingPathComponent(KeyMetricsPrefs.fileName))
        XCTAssertEqual(KeyMetricsPrefs.load(dir), [.hrv, .ftp], "repeats and unknown names are dropped")
        XCTAssertTrue(KeyMetricsPrefs.save([], dir: dir)); XCTAssertEqual(KeyMetricsPrefs.load(dir), [], "an emptied choice is still the athlete's choice")
    }
}
