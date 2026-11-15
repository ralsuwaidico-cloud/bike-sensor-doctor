import XCTest
import CoreLocation
@testable import BikeComputer

/// E1-F5: while the health check pauses training, no route may START a ride. Every route (Ride screen, Plan, Apple Watch,
/// Cyclift Watch) goes through `startMode` and `start()`, so the gate is tested where it lives.
final class E1RideGateTests: XCTestCase {
    func testAPausedAthleteCannotStartARideOnAnyRoute() {
        let r = RideRecorder(autoTick: false); r.location = LocationService()
        r.healthHold = true
        XCTAssertEqual(r.startMode(locationAuthorized: true), .blockedByHealthHold)
        XCTAssertFalse(r.start(), "the phone ride is refused")
        XCTAssertFalse(r.isActive); XCTAssertNotNil(r.note, "and the refusal says why")
        r.healthHold = false
        XCTAssertNotEqual(r.startMode(locationAuthorized: true), .blockedByHealthHold)
        XCTAssertTrue(r.start(), "once the hold is lifted a ride starts as before")
        r.pause(); r.end()
    }
}

/// E1-F3: the phone ride's sample count with a clock the test controls. The existing RideRegression test is unchanged; it
/// still runs against the real clock.
final class E1RideClockTests: XCTestCase {
    private func fix(_ i: Int, at t: Date) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 24.45 + Double(i) * 0.0001, longitude: 54.38), altitude: 12, horizontalAccuracy: 5, verticalAccuracy: 8, course: 0, speed: 8.33, timestamp: t)
    }
    func testFiveTicksAreFiveSamplesHoweverSlowTheMachineIs() {
        let loc = LocationService(); let r = RideRecorder(autoTick: false); r.location = loc
        var t = Date(timeIntervalSince1970: 1_800_000_000); r.clock = { t }
        XCTAssertTrue(r.start())
        Thread.sleep(forTimeInterval: 1.6)                              // real time passing must not matter
        for i in 0..<5 { t = t.addingTimeInterval(1); loc.injectForTests(fix(i, at: t)); r.tick() }
        XCTAssertEqual(r.samples.count, 5); XCTAssertEqual(r.gapSeconds, 0)
        XCTAssertEqual(r.samples.compactMap(\.lat).count, 5, "every route fix is kept")
    }
    func testAGapInTheClockIsRecordedAsGapSamplesNeverAsInventedData() {
        let loc = LocationService(); let r = RideRecorder(autoTick: false); r.location = loc
        var t = Date(timeIntervalSince1970: 1_800_000_000); r.clock = { t }
        XCTAssertTrue(r.start())
        t = t.addingTimeInterval(1); loc.injectForTests(fix(0, at: t)); r.tick()
        t = t.addingTimeInterval(6); loc.injectForTests(fix(1, at: t)); r.tick()          // five seconds were not observed
        XCTAssertEqual(r.gapSeconds, 5); XCTAssertEqual(r.samples.count, 7)
        XCTAssertEqual(r.samples.filter { $0.gap == true }.count, 5)
        XCTAssertTrue(r.samples.filter { $0.gap == true }.allSatisfy { $0.lat == nil && $0.speedCms == nil }, "a gap sample carries no position or speed")
        XCTAssertEqual(r.samples.compactMap(\.lat).count, 2)
    }
}
