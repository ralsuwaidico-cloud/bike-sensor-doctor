import XCTest
@testable import BikeComputer

/// Training Hub v1.4 cycling screen: a zero is shown only when measured; stale and lost values say so.
final class CyclingReadoutTests: XCTestCase {
    private func r(_ p: SensorTruth) -> CyclingReadout {
        CyclingReadout(title: "T", phase: .recording, elapsedSeconds: 10, movingSeconds: 10, power: p, heartRate: .measured(150), cadence: .measured(88),
                       speedKmh: 30, distanceKm: 1, targetLow: 220, targetHigh: 240, laps: 0)
    }
    func testFiveTruths() {
        XCTAssertEqual(r(.measured(231)).powerLine, "In range"); XCTAssertEqual(r(.measured(200)).powerLine, "Below target"); XCTAssertEqual(r(.measured(260)).powerLine, "Above target")
        XCTAssertEqual(r(.measured(0)).powerLine, "Coasting"); XCTAssertEqual(SensorTruth.measured(0).figure, "0"); XCTAssertTrue(SensorTruth.measured(0).recorded, "a measured zero is a real value")
        XCTAssertEqual(r(.stale(last: 231, ageSeconds: 6)).powerLine, "Last reading 6 s ago"); XCTAssertTrue(SensorTruth.stale(last: 231, ageSeconds: 6).dimmed)
        XCTAssertFalse(SensorTruth.stale(last: 231, ageSeconds: 6).recorded, "a stale value is not recorded as new")
        XCTAssertEqual(SensorTruth.disconnected.figure, "—"); XCTAssertEqual(r(.disconnected).powerLine, "No signal"); XCTAssertNotNil(r(.disconnected).warning)
        XCTAssertEqual(SensorTruth.unavailable.figure, "—"); XCTAssertEqual(r(.unavailable).powerLine, "No power meter"); XCTAssertNil(r(.unavailable).warning)
        XCTAssertNil(r(.measured(231)).warning)
    }
    func testALostMeterNeverShowsAZero() {
        for t in 0..<180 {
            let x = CyclingDemoScript.readout(at: t, phase: .recording, laps: 0)
            if case .disconnected = x.power { XCTAssertEqual(x.power.figure, "—") }
            if case .measured(0) = x.power { XCTAssertEqual(x.powerLine, "Coasting") }
        }
    }
    func testTheDemoScriptIsDeterministicAndShowsEveryState() {
        XCTAssertEqual(CyclingDemoScript.readout(at: 42, phase: .recording, laps: 1), CyclingDemoScript.readout(at: 42, phase: .recording, laps: 1))
        let lines = Set((0..<90).map { CyclingDemoScript.readout(at: $0, phase: .recording, laps: 0).powerLine.prefix(4) })
        XCTAssertTrue(lines.isSuperset(of: ["In r", "Coas", "Last", "No s"]), "\(lines)")
    }
    func testClock() { XCTAssertEqual(CyclingReadout.clock(1476), "24:36"); XCTAssertEqual(CyclingReadout.clock(3700), "1:01:40") }
}
