import XCTest
@testable import BikeComputer

/// APP-031: last night's sleep must come from ONE source and never double-count overlapping samples.
final class SleepAggregationTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_762_560_000)   // 2026-11-08 00:00 UTC
    func h(_ x: Double) -> Date { t0.addingTimeInterval(x * 3600) }

    func testWatchAndSleepAppSameNightIsNotSummed() {
        let watch = [SleepInterval(source: "com.apple.health", start: h(0), end: h(3)), SleepInterval(source: "com.apple.health", start: h(3.2), end: h(7.5))]
        let app = [SleepInterval(source: "com.sleepapp", start: h(0.1), end: h(7.2))]
        let r = SleepAggregation.lastNight(watch + app)!
        XCTAssertEqual(r.hours, 7.3, accuracy: 0.001, "the richer source (7.3 h) wins; 7.3 + 7.1 = 14.4 h is never reported")
        XCTAssertEqual(r.source, "com.apple.health"); XCTAssertEqual(r.sourcesSeen, 2); XCTAssertEqual(r.end, h(7.5))
    }
    func testOverlappingStagesWithinOneSourceMerge() {
        let s = [SleepInterval(source: "w", start: h(0), end: h(2)), SleepInterval(source: "w", start: h(1), end: h(3)), SleepInterval(source: "w", start: h(3), end: h(4)), SleepInterval(source: "w", start: h(5), end: h(6))]
        XCTAssertEqual(SleepAggregation.lastNight(s)!.hours, 5, accuracy: 0.001, "0–4 merged (4 h) + 5–6 (1 h); the overlap hour counts once")
    }
    func testNoSamplesIsNilNotZero() { XCTAssertNil(SleepAggregation.lastNight([])) }
    func testZeroLengthSamplesAreIgnored() { XCTAssertNil(SleepAggregation.lastNight([SleepInterval(source: "w", start: h(1), end: h(1))])) }
}
