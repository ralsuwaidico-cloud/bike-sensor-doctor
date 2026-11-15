import XCTest
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
