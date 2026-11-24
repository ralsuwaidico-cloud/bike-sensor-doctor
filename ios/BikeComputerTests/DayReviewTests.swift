import XCTest
@testable import BikeComputer

/// Daily Training Overview (owner, 24 Nov 2026, 22:42 — proposed). Each session is set beside the most relevant earlier
/// RECORDED session. A change is called favourable or unfavourable only by the stated rules — a bigger number is not
/// better by itself — and nothing is compared that was not recorded.
final class DayReviewTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }
    private func at(_ day: Int, _ hour: Int = 18) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 2 + day, hour: hour))! }
    private func entry(_ id: String, _ name: String, reps: Int, kg: Double?, sets: Int = 3, done: Bool = true) -> ExerciseEntry {
        let s = (0..<sets).map { _ in "{\"reps\":\(reps),\(kg.map { "\"weightKg\":\($0)," } ?? "")\"bodyweight\":\(kg == nil),\"unilateral\":false,\"done\":\(done)}" }.joined(separator: ",")
        return try! JSONDecoder().decode(ExerciseEntry.self, from: Data("{\"exerciseId\":\"\(id)\",\"name\":\"\(name)\",\"pattern\":\"squat\",\"sets\":[\(s)],\"notes\":\"\"}".utf8))
    }
    private func log(_ day: Int, _ e: [ExerciseEntry], focus: StrengthFocus = .fullBody) -> StrengthSession { var l = StrengthSession(date: at(day), minutes: 40, focus: focus); l.exercises = e; return l }
    private func ride(_ day: Int, minutes: Int = 60, power: Int? = nil, hr: Int? = nil, cadence: Int? = nil) -> RideRecord {
        var r = RideRecord(start: at(day, 7), durationS: minutes * 60, distanceM: 28_000, recorder: .phone, sources: ["test"]); r.avgPower = power; r.avgHR = hr; r.avgCadence = cadence
        r.zoneSeconds = [300, minutes * 50, 0, 0, 0, 0, 0]; return r
    }
    private func verdict(_ m: [DayMetric], _ id: String) -> DayVerdict? { m.first { $0.id == id }?.verdict }

    func testStrengthExerciseIsJudgedByLoadAndVolumeTogether() {
        func ex(_ now: ExerciseEntry, _ before: ExerciseEntry) -> DayExercise { DayReviewModel.exercise(planned: nil, current: now, previous: before, units: .metric) }
        let up = ex(entry("a", "Squat", reps: 10, kg: 22.5), entry("a", "Squat", reps: 10, kg: 20))
        XCTAssertEqual(up.verdict, .better); XCTAssertEqual(up.change, "Top load +2.5 kg")
        XCTAssertEqual(up.metrics.map(\.name), ["Sets", "Reps", "Top load", "Volume"])
        XCTAssertEqual(verdict(up.metrics, "a-volume"), .better); XCTAssertEqual(up.metrics[3].previous, "600 kg"); XCTAssertEqual(up.metrics[3].current, "675 kg")
        XCTAssertEqual(verdict(up.metrics, "a-reps"), .notComparable, "reps are judged only at the same load")
        let down = ex(entry("a", "Press", reps: 8, kg: 16), entry("a", "Press", reps: 8, kg: 18))
        XCTAssertEqual(down.verdict, .worse); XCTAssertEqual(down.change, "Top load −2 kg")
        let same = ex(entry("a", "Row", reps: 10, kg: 16), entry("a", "Row", reps: 10, kg: 16))
        XCTAssertEqual(same.verdict, .same); XCTAssertEqual(same.change, "Unchanged")
        // heavier but far fewer reps: load up, volume down — NOT called an improvement or a decline
        let mixed = ex(entry("a", "Squat", reps: 5, kg: 25), entry("a", "Squat", reps: 10, kg: 20))
        XCTAssertEqual(mixed.verdict, .notComparable); XCTAssertTrue(mixed.change.contains("not comparable"), mixed.change)
        // more sets is never an improvement by itself
        XCTAssertEqual(verdict(ex(entry("a", "Row", reps: 10, kg: 16, sets: 4), entry("a", "Row", reps: 10, kg: 16)).metrics, "a-sets"), .notComparable)
        // bodyweight: reps only
        let bw = ex(entry("b", "Push-up", reps: 12, kg: nil), entry("b", "Push-up", reps: 10, kg: nil))
        XCTAssertEqual(bw.verdict, .better); XCTAssertEqual(bw.change, "+6 reps"); XCTAssertNil(bw.metrics[3].current, "no volume without a load")
    }

    func testPlannedStrengthShowsThePrescriptionAndThePreviousButNoVerdict() {
        let e = DayReviewModel.exercise(planned: entry("a", "Squat", reps: 10, kg: 22.5, done: false), current: nil, previous: entry("a", "Squat", reps: 10, kg: 20), units: .metric)
        XCTAssertEqual(e.planned, "3 × 10 · 22.5 kg"); XCTAssertNil(e.current); XCTAssertNotNil(e.previous)
        XCTAssertEqual(e.verdict, .notComparable); XCTAssertEqual(e.change, "Not done yet")
        XCTAssertTrue(e.metrics.allSatisfy { $0.verdict == .notComparable && $0.current == nil }, "nothing planned is shown as achieved")
        let note = DayReviewModel.strengthAnalysis(completed: false, previous: DayPrevious(date: at(0), title: "", line: "", basis: "", record: .none), exercises: [e], metrics: [], calendar: cal)
        XCTAssertTrue(note.hasPrefix("Not done yet."), note)
    }

    func testPreviousComparableLogIsTheMostRecentEarlierOneWithTheseExercises() {
        let logs = [log(-14, [entry("a", "Squat", reps: 10, kg: 18)]), log(-7, [entry("a", "Squat", reps: 10, kg: 20)], focus: .lower), log(-3, [entry("z", "Curl", reps: 10, kg: 8)]), log(5, [entry("a", "Squat", reps: 10, kg: 30)])]
        let same = DayReviewModel.previousLog(for: ["a"], focus: .fullBody, before: at(0), excluding: nil, in: logs)
        XCTAssertEqual(same?.log.id, logs[0].id, "same focus is preferred over a more recent session of another focus")
        XCTAssertEqual(DayReviewModel.previousLog(for: ["a"], focus: .upper, before: at(0), excluding: nil, in: logs)?.log.id, logs[1].id, "else the most recent with the exercise")
        XCTAssertNil(DayReviewModel.previousLog(for: ["q"], focus: .fullBody, before: at(0), excluding: nil, in: logs), "no shared exercise → nothing to compare")
        XCTAssertNil(DayReviewModel.previousLog(for: ["a"], focus: .fullBody, before: at(-20), excluding: nil, in: logs), "a first-ever session has no previous; later sessions are never used")
        let first = DayReviewModel.strengthAnalysis(completed: true, previous: nil, exercises: [], metrics: [], calendar: cal)
        XCTAssertTrue(first.hasPrefix("No earlier session with these exercises is recorded"), first)
    }

    func testCyclingPowerAndHeartRateAreJudgedTogetherAndNothingElseIsJudged() {
        func m(_ c: RideRecord, _ p: RideRecord) -> [DayMetric] { DayReviewModel.rideMetrics(current: c, planned: Workout(date: at(0), kind: .endurance, minutes: 60), previous: p, units: .metric) }
        let better = m(ride(0, power: 168, hr: 134, cadence: 88), ride(-7, power: 160, hr: 136, cadence: 86))
        XCTAssertEqual(verdict(better, "r-power"), .better); XCTAssertEqual(verdict(better, "r-hr"), .same, "2 bpm is within tolerance")
        XCTAssertEqual(verdict(better, "r-cadence"), .notComparable, "cadence is shown, never judged")
        XCTAssertEqual(verdict(better, "r-duration"), .same); XCTAssertEqual(better.first { $0.id == "r-duration" }?.planned, "1 h")
        XCTAssertEqual(verdict(better, "r-zone2"), .same); XCTAssertEqual(better.first { $0.id == "r-zone2" }?.planned, "target zone")
        XCTAssertNil(better.first { $0.id == "r-zone4" }, "zones without time in either ride are not listed")
        // more power bought with more heart rate is NOT called better
        let both = m(ride(0, power: 175, hr: 146), ride(-7, power: 160, hr: 136))
        XCTAssertEqual(verdict(both, "r-power"), .notComparable); XCTAssertEqual(verdict(both, "r-hr"), .notComparable)
        // the same power at a lower heart rate is favourable; less power at the same heart rate is not
        XCTAssertEqual(verdict(m(ride(0, power: 160, hr: 130), ride(-7, power: 160, hr: 136)), "r-hr"), .better)
        XCTAssertEqual(verdict(m(ride(0, power: 150, hr: 136), ride(-7, power: 160, hr: 136)), "r-power"), .worse)
        // a longer ride is not an improvement
        XCTAssertEqual(verdict(m(ride(0, minutes: 75, power: 160, hr: 136), ride(-7, power: 160, hr: 136)), "r-duration"), .notComparable)
        // heart rate without power: shown, not judged, and the note says why
        let noPower = m(ride(0, hr: 130), ride(-7, hr: 136))
        XCTAssertEqual(verdict(noPower, "r-hr"), .notComparable); XCTAssertEqual(noPower.first { $0.id == "r-power" }?.change, "Not measured")
        let prev = DayPrevious(date: at(-7), title: "Endurance", line: "", basis: "", record: .none)
        XCTAssertTrue(DayReviewModel.rideAnalysis(current: ride(0, hr: 130), previous: prev, metrics: noPower, calendar: cal).contains("Heart rate alone does not show whether the ride went better"))
        XCTAssertTrue(DayReviewModel.rideAnalysis(current: ride(0), previous: nil, metrics: [], calendar: cal).hasPrefix("No earlier comparable ride is recorded"))
        // power in both rides but no heart rate (found in check 70, where the note wrongly said neither was measured)
        let noHR = m(ride(0, power: 230), ride(-7, power: 226))
        XCTAssertEqual(verdict(noHR, "r-power"), .notComparable)
        let said = DayReviewModel.rideAnalysis(current: ride(0, power: 230), previous: prev, metrics: noHR, calendar: cal)
        XCTAssertTrue(said.contains("heart rate was not measured in both rides") && said.contains("+4 W") && !said.contains("neither"), said)
    }

    func testHealthRowsShowOnlyStoredReadingsAndNeverZero() {
        var l = RecoveryLog()
        l.entries = [RecoveryEntry(kind: .sleep, value: 7.4, date: at(0, 6), source: "Watch"), RecoveryEntry(kind: .hrv, value: 48, date: at(1, 6), source: "Watch")]
        let rows = DayReviewModel.health(day: at(0), log: l, enabled: [.sleep, .restingHR], soreness: [], future: false, calendar: cal)
        XCTAssertEqual(rows.map(\.id), ["sleep", "restingHR", "hrv", "soreness"])
        XCTAssertEqual(rows[0].value, "7 h 24 min"); XCTAssertEqual(rows[0].detail, "Watch · 06:00")
        XCTAssertNil(rows[1].value); XCTAssertEqual(rows[1].detail, "No reading this day")
        XCTAssertNil(rows[2].value, "another day's reading is not this day's"); XCTAssertEqual(rows[2].detail, "Not connected")
        XCTAssertNil(rows[3].value); XCTAssertEqual(rows[3].detail, "Not answered in a session review")
        XCTAssertTrue(DayReviewModel.health(day: at(3), log: l, enabled: [.sleep], soreness: [], future: true, calendar: cal).prefix(3).allSatisfy { $0.value == nil && $0.detail != "0" })
    }
}
