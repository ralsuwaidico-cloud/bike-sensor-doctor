import XCTest
@testable import BikeComputer

/// Checkpoint E — Recovery: per-day log (one entry per kind per day, bounded), freshness, the athlete's own usual
/// range (≥ 7 records), conservative wording with source + time, and ONE recommendation. No readiness score exists.
final class RecoveryAnalysisTests: XCTestCase {
    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_794_130_860)   // Sat 8 Nov 2026 ~ morning (UTC)
    private func morning(_ daysAgo: Int, hour: Int = 7) -> Date { cal.date(bySettingHour: hour, minute: 10, second: 0, of: cal.date(byAdding: .day, value: -daysAgo, to: now)!)! }

    private func log(sleep: [Double], rhr: [Int] = [], hrv: [Double] = [], source: String = "Apple Watch") -> RecoveryLog {
        var l = RecoveryLog()
        var xs: [HealthSample] = []
        for (i, v) in sleep.enumerated() { xs.append(HealthSample(kind: .sleep, value: v, date: morning(sleep.count - 1 - i), source: source)) }
        for (i, v) in rhr.enumerated() { xs.append(HealthSample(kind: .restingHR, value: Double(v), date: morning(rhr.count - 1 - i, hour: 6), source: source)) }
        for (i, v) in hrv.enumerated() { xs.append(HealthSample(kind: .hrv, value: v, date: morning(hrv.count - 1 - i, hour: 6), source: source)) }
        l.merge(xs, now: now)
        return l
    }

    func testLogKeepsOneEntryPerKindPerDayAndIsBounded() {
        var l = RecoveryLog()
        XCTAssertEqual(l.merge([HealthSample(kind: .restingHR, value: 52, date: morning(0, hour: 6), source: "Apple Watch")], now: now), 1)
        // a later sample the same day replaces; an earlier one does not
        XCTAssertEqual(l.merge([HealthSample(kind: .restingHR, value: 50, date: morning(0, hour: 9), source: "Apple Watch")], now: now), 1)
        XCTAssertEqual(l.merge([HealthSample(kind: .restingHR, value: 60, date: morning(0, hour: 5), source: "Apple Watch")], now: now), 0)
        XCTAssertEqual(l.entries(.restingHR).map(\.value), [50])
        // the same sample again changes nothing
        XCTAssertEqual(l.merge([HealthSample(kind: .restingHR, value: 50, date: morning(0, hour: 9), source: "Apple Watch")], now: now), 0)
        // entries older than keepDays are dropped
        l.merge([HealthSample(kind: .restingHR, value: 55, date: morning(RecoveryLog.keepDays + 5, hour: 6), source: "Apple Watch")], now: now)
        XCTAssertEqual(l.entries(.restingHR).count, 1, "a reading older than \(RecoveryLog.keepDays) days is not kept")
        XCTAssertEqual(l.entries.first?.id, "restingHR-\(RecoveryLog.dayKey(morning(0)))")
    }

    func testFreshnessAndSourceLineAreExplicit() {
        XCTAssertEqual(RecoveryFreshness.of(now.addingTimeInterval(-3600), now: now), .fresh)
        XCTAssertEqual(RecoveryFreshness.of(now.addingTimeInterval(-30 * 3600), now: now), .aging)
        XCTAssertEqual(RecoveryFreshness.of(now.addingTimeInterval(-4 * 86_400), now: now), .stale)
        XCTAssertEqual(RecoveryFreshness.of(nil, now: now), .missing)
        let m = RecoveryAnalysis.metric(.sleep, log: log(sleep: [7.4]), now: now)
        XCTAssertTrue(m.sourceLine.hasPrefix("Apple Watch · "), m.sourceLine)
        XCTAssertTrue(m.sourceLine.hasSuffix("fresh"), m.sourceLine)
        XCTAssertNil(m.baseline, "one night has no usual range")
        XCTAssertEqual(m.standing, .noBaseline)
        XCTAssertTrue(m.explanation.contains("no usual range to compare with yet"), m.explanation)
        XCTAssertEqual(m.series.count, RecoveryAnalysis.seriesDays); XCTAssertEqual(m.series.last!, 7.4)
    }

    func testUsualRangeNeedsSevenRecordsAndFlagsOnlyClearDeviations() {
        // 6 earlier nights → still no baseline
        XCTAssertNil(RecoveryAnalysis.metric(.sleep, log: log(sleep: [7.5, 7.6, 7.4, 7.8, 7.3, 7.5, 7.5]), now: now).baseline)
        // 7 earlier nights around 7.5 h; tonight 7.3 → typical (inside q1−margin … q3+margin, margin ≥ 0.5 h)
        let typical = RecoveryAnalysis.metric(.sleep, log: log(sleep: [7.5, 7.6, 7.4, 7.8, 7.3, 7.5, 7.5, 7.3]), now: now)
        XCTAssertEqual(typical.baseline?.records, 7); XCTAssertEqual(typical.standing, .typical); XCTAssertFalse(typical.flagged)
        XCTAssertTrue(typical.explanation.contains("inside your usual"), typical.explanation)
        // tonight 5.2 h → below
        let low = RecoveryAnalysis.metric(.sleep, log: log(sleep: [7.5, 7.6, 7.4, 7.8, 7.3, 7.5, 7.5, 5.2]), now: now)
        XCTAssertEqual(low.standing, .lower); XCTAssertTrue(low.flagged)
        XCTAssertTrue(low.explanation.hasPrefix("5 h 12, below your usual"), low.explanation)
        XCTAssertTrue(low.explanation.contains("over 7 nights"), low.explanation)
        // resting HR: higher is the flagged direction; HRV: lower
        let rhr = RecoveryAnalysis.metric(.restingHR, log: log(sleep: [], rhr: [50, 51, 49, 50, 52, 50, 51, 61]), now: now)
        XCTAssertEqual(rhr.standing, .higher); XCTAssertTrue(rhr.flagged)
        let rhrLow = RecoveryAnalysis.metric(.restingHR, log: log(sleep: [], rhr: [50, 51, 49, 50, 52, 50, 51, 44]), now: now)
        XCTAssertEqual(rhrLow.standing, .lower); XCTAssertFalse(rhrLow.flagged, "a lower resting HR is never a fatigue flag")
        let hrv = RecoveryAnalysis.metric(.hrv, log: log(sleep: [], hrv: [60, 58, 62, 61, 59, 60, 63, 40]), now: now)
        XCTAssertEqual(hrv.standing, .lower); XCTAssertTrue(hrv.flagged)
        // weight is never flagged
        var wl = RecoveryLog(); wl.merge((0..<8).map { HealthSample(kind: .weight, value: $0 == 7 ? 90 : 75, date: morning(7 - $0), source: "Scale") }, now: now)
        XCTAssertFalse(RecoveryAnalysis.metric(.weight, log: wl, now: now).flagged)
    }

    func testOneRecommendationFollowsThePrecedence() {
        let ok = log(sleep: [7.5, 7.6, 7.4, 7.8, 7.3, 7.5, 7.5, 7.4], rhr: [50, 51, 49, 50, 52, 50, 51, 50], hrv: [60, 58, 62, 61, 59, 60, 63, 61])
        let ms = RecoveryAnalysis.metrics(log: ok, enabled: [.sleep, .restingHR, .hrv, .weight], now: now)
        XCTAssertEqual(ms.map(\.kind), [.sleep, .restingHR, .hrv, .weight], "weight is shown but never advises")
        // health hold wins over everything
        XCTAssertEqual(RecoveryAnalysis.advice(ms, trainingAllowed: false, todayIsRest: false, now: now).kind, .hold)
        // everything typical → train as planned, with the readings listed
        let plain = RecoveryAnalysis.advice(ms, trainingAllowed: true, todayIsRest: false, now: now)
        XCTAssertEqual(plain.kind, .trainAsPlanned); XCTAssertEqual(plain.title, "Train as planned"); XCTAssertEqual(plain.basis.count, 3)
        XCTAssertTrue(plain.basis[0].hasPrefix("Sleep: 7 h 24, inside your usual"), plain.basis[0])
        XCTAssertEqual(RecoveryAnalysis.advice(ms, trainingAllowed: true, todayIsRest: true, now: now).title, "Rest as planned")
        // one flag → watch
        let one = log(sleep: [7.5, 7.6, 7.4, 7.8, 7.3, 7.5, 7.5, 5.0], rhr: [50, 51, 49, 50, 52, 50, 51, 50], hrv: [60, 58, 62, 61, 59, 60, 63, 61])
        let w = RecoveryAnalysis.advice(RecoveryAnalysis.metrics(log: one, enabled: [.sleep, .restingHR, .hrv], now: now), trainingAllowed: true, todayIsRest: false, now: now)
        XCTAssertEqual(w.kind, .watch); XCTAssertTrue(w.detail.hasPrefix("Sleep is outside your usual range"), w.detail)
        // two flags → easier, named
        let two = log(sleep: [7.5, 7.6, 7.4, 7.8, 7.3, 7.5, 7.5, 5.0], rhr: [50, 51, 49, 50, 52, 50, 51, 62], hrv: [60, 58, 62, 61, 59, 60, 63, 61])
        let e = RecoveryAnalysis.advice(RecoveryAnalysis.metrics(log: two, enabled: [.sleep, .restingHR, .hrv], now: now), trainingAllowed: true, todayIsRest: false, now: now)
        XCTAssertEqual(e.kind, .easier); XCTAssertEqual(e.title, "Make today's session easier")
        XCTAssertTrue(e.detail.contains("sleep and resting heart rate"), e.detail)
        XCTAssertTrue(e.detail.contains("not a diagnosis"), e.detail)
        // readings but no baseline → train as planned, says why
        let young = RecoveryAnalysis.advice(RecoveryAnalysis.metrics(log: log(sleep: [6.0, 5.0]), enabled: [.sleep], now: now), trainingAllowed: true, todayIsRest: false, now: now)
        XCTAssertEqual(young.kind, .trainAsPlanned); XCTAssertTrue(young.detail.contains("fewer than 7"), young.detail)
        // stale readings → no data; stale flags never advise
        var stale = RecoveryLog(); stale.merge((0..<8).map { HealthSample(kind: .sleep, value: $0 == 7 ? 4.0 : 7.5, date: morning(12 - $0), source: "Apple Watch") }, now: now)
        let nd = RecoveryAnalysis.advice(RecoveryAnalysis.metrics(log: stale, enabled: [.sleep], now: now), trainingAllowed: true, todayIsRest: false, now: now)
        XCTAssertEqual(nd.kind, .noData); XCTAssertTrue(nd.detail.hasPrefix("No reading from the last 24 hours."), nd.detail)
        XCTAssertEqual(RecoveryAnalysis.advice([], trainingAllowed: true, todayIsRest: false, now: now).detail.hasPrefix("No recovery reads are turned on."), true)
    }

    func testStoreMergesHistoryWithoutChangingLatestAndPersists() {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let s = Store(directory: d, generatePlan: false)
        s.settings.healthReads.sleep = true; s.settings.healthReads.restingHR = false
        let latest = [HealthSample(kind: .sleep, value: 7.2, date: morning(0), source: "Apple Watch"), HealthSample(kind: .restingHR, value: 50, date: morning(0), source: "Apple Watch")]
        s.applyHealthSamples(latest, now: now)
        XCTAssertEqual(s.profile.sleepHours, 7.2)
        XCTAssertEqual(s.recoveryLog.entries.map(\.kind), [.sleep], "a read that is off is neither applied nor logged")
        s.recordRecoveryHistory((1...10).map { HealthSample(kind: .sleep, value: 7.5, date: morning($0), source: "Apple Watch") }, now: now)
        XCTAssertEqual(s.recoveryLog.entries(.sleep).count, 11)
        XCTAssertEqual(s.profile.sleepHours, 7.2, "history never rewrites the latest value")
        let r = s.recoveryReport(now: now)
        XCTAssertEqual(r.metrics.map(\.kind), [.sleep]); XCTAssertEqual(r.advice.kind, .trainAsPlanned)
        let again = Store(directory: d, generatePlan: false)
        XCTAssertEqual(again.recoveryLog, s.recoveryLog, "the log survives a relaunch")
    }
}
