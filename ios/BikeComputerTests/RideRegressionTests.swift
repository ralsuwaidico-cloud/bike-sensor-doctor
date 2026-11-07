import XCTest
import CoreLocation
@testable import BikeComputer

/// Owner regression list for the Ride milestone (7 Nov 2026):
///  2. GPS route recording continues when internet connectivity is lost — the recorder has no network dependency.
///  3. Pause / resume / end / review / save stay reliable when the Watch disconnects.
///  7. Old ride-layout settings migrate safely without losing other settings.
final class RideRegressionTests: XCTestCase {
    private func fix(_ lat: Double, _ lon: Double, speed: Double, alt: Double = 12, hacc: Double = 5) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: alt, horizontalAccuracy: hacc, verticalAccuracy: 8, course: 0, speed: speed, timestamp: Date())
    }

    // 2. The recorder stores GPS samples and grows the distance from Core Location fixes alone. Nothing here touches
    //    the network; a map that cannot load tiles only changes what is drawn, never what is recorded (RA-17, RA-18).
    func testGPSRecordingNeedsNoNetworkAndKeepsRouteSamples() {
        let loc = LocationService()
        let r = RideRecorder(autoTick: false); r.location = loc
        XCTAssertTrue(r.start())
        for i in 0..<5 { loc.injectForTests(fix(24.45 + Double(i) * 0.0001, 54.38, speed: 8.33)); r.tick() }
        XCTAssertEqual(r.samples.count, 5)
        XCTAssertEqual(r.samples.compactMap(\.lat).count, 5, "every second carries the fix")
        XCTAssertEqual(r.distanceM, 41, "5 s at 8.33 m/s (30 km/h) → 41 m from GPS speed")
        // a stale or inaccurate fix is not used, but the clock keeps running (distance holds)
        loc.injectForTests(fix(24.46, 54.38, speed: 8.33, hacc: 80)); r.tick()
        XCTAssertEqual(r.samples.count, 6); XCTAssertNil(r.samples.last?.lat); XCTAssertEqual(r.distanceM, 41)
        r.pause(); r.end()
        XCTAssertEqual(r.pendingResult?.samples.filter { $0.lat != nil }.count, 5, "the route is in the record")
    }

    // 3. A phone ride without any Watch heart rate (strap never paired, or the Watch dropped) still pauses, resumes,
    //    ends and produces a reviewable record with no heart-rate value invented.
    func testPhoneRideSurvivesAMissingWatchAndNeverInventsHeartRate() {
        let r = RideRecorder(autoTick: false)       // no watch, no board
        XCTAssertTrue(r.start())
        for _ in 0..<10 { r.tick() }
        r.pause(); XCTAssertEqual(r.state, .paused)
        r.tick(); XCTAssertEqual(r.elapsedS, 10, "paused seconds do not count")
        r.resume(); r.tick(); XCTAssertEqual(r.elapsedS, 11)
        r.pause(); r.end()
        XCTAssertEqual(r.state, .ended)
        XCTAssertNil(r.pendingResult?.avgHR); XCTAssertNil(r.pendingResult?.maxHR)
        XCTAssertTrue(r.pendingResult?.samples.allSatisfy { $0.hr == nil } ?? false)
        XCTAssertEqual(r.pendingResult?.sources, ["Phone GPS"], "no 'Apple Watch' source is claimed without heart-rate samples")
    }

    // 7. Settings saved by builds ≤ 176 carry a `rideLayout` value; it decodes without error and every other setting
    //    survives. The value is ignored by the ride screen (RideLayout is kept for decoding only).
    func testOldRideLayoutSettingDecodesAndOtherSettingsSurvive() throws {
        for old in ["coach", "gauges", "classic", "rings", "analytics"] {
            let json = """
            {"units":"imperial","phoneOnlyMode":true,"hrPref":"watch","keepScreenOn":false,"autoConnectBoard":false,"enabledConnections":["watch"],"rideLayout":"\(old)","coachEnabled":false}
            """.data(using: .utf8)!
            let s = try JSONDecoder().decode(AppSettings.self, from: json)
            XCTAssertEqual(s.units, .imperial, old); XCTAssertTrue(s.phoneOnlyMode); XCTAssertFalse(s.keepScreenOn); XCTAssertFalse(s.autoConnectBoard); XCTAssertFalse(s.coachEnabled)
            XCTAssertEqual(s.rideLayout.rawValue, old, "the old value is kept as data, not rewritten")
            let again = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
            XCTAssertEqual(again, s, "round trip keeps every field")
        }
        // an unknown or missing value never breaks decoding either
        let weird = try JSONDecoder().decode(AppSettings.self, from: #"{"units":"metric","rideLayout":"hologram"}"#.data(using: .utf8)!)
        XCTAssertEqual(weird.rideLayout, .coach); XCTAssertEqual(weird.units, .metric)
    }
}
