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

    // MARK: Focus / Map interface and the real-recorder mapping (pure rules in CyclingReadout.swift)

    func testSensorStateMappingNeverInventsAValue() {
        func t(_ fresh: Int?, _ last: Int?, _ age: Int?, _ link: CyclingLink) -> SensorTruth { CyclingSensorMap.truth(CyclingSensorInput(fresh: fresh, last: last, lastAgeSeconds: age, link: link)) }
        XCTAssertEqual(t(231, 231, 0, .connected), .measured(231))
        XCTAssertEqual(t(0, 0, 0, .connected), .measured(0), "a fresh zero is a measured zero")
        XCTAssertEqual(t(nil, 231, 6, .connected), .stale(last: 231, ageSeconds: 6), "linked, no new reading: the last value with its age")
        XCTAssertEqual(t(nil, 231, CyclingSensorMap.staleLimitSeconds + 1, .connected), .disconnected, "too old to show: no signal")
        XCTAssertEqual(t(nil, nil, nil, .connected), .searching, "linked, nothing received yet")
        XCTAssertEqual(t(nil, 231, 2, .searching), .searching, "a link still coming up shows no old number")
        XCTAssertEqual(t(nil, 231, 2, .lost), .disconnected, "a dropped link shows no old number")
        XCTAssertEqual(t(nil, nil, nil, .notSetUp), .unavailable)
        for link in [CyclingLink.connected, .searching, .lost, .notSetUp] {
            let x = t(nil, nil, nil, link)
            XCTAssertEqual(x.figure, "—", "no reading is never a 0 (\(link))"); XCTAssertFalse(x.recorded); XCTAssertNotNil(x.reason)
        }
        XCTAssertNil(SensorTruth.measured(0).reason)
    }
    func testLinkOverAMetricsSources() {
        func s(_ state: String, _ configured: Bool = true) -> CyclingSourceStatus { CyclingSourceStatus(state: state, configured: configured) }
        XCTAssertEqual(CyclingSensorMap.link([]), .notSetUp)
        XCTAssertEqual(CyclingSensorMap.link([s("notConfigured", false), s("planned", false)]), .notSetUp)
        XCTAssertEqual(CyclingSensorMap.link([s("disconnected", false)]), .notSetUp, "a source the athlete never set up is not lost")
        XCTAssertEqual(CyclingSensorMap.link([s("disconnected")]), .lost)
        XCTAssertEqual(CyclingSensorMap.link([s("notAuthorized")]), .lost)
        XCTAssertEqual(CyclingSensorMap.link([s("disconnected"), s("connecting")]), .searching)
        XCTAssertEqual(CyclingSensorMap.link([s("disconnected"), s("connecting"), s("connected")]), .connected)
    }
    func testLabelsAndLinesPerState() {
        var x = r(.measured(231)); XCTAssertEqual(x.powerLabel, "POWER · 3 S"); XCTAssertEqual(x.elapsedLabel, "ELAPSED"); XCTAssertEqual(x.stateLine, "Cycling")
        x.powerAverageSeconds = nil; XCTAssertEqual(x.powerLabel, "POWER", "no averaging window is claimed when there is none")
        x.powerQuality = .unverified; XCTAssertEqual(x.powerLabel, "POWER · UNVERIFIED"); XCTAssertEqual(x.powerLine, "Meter not verified")
        XCTAssertEqual(r(.stale(last: 231, ageSeconds: 6)).powerLabel, "POWER · NO UPDATE")
        XCTAssertEqual(r(.searching).powerLabel, "POWER · SEARCHING"); XCTAssertEqual(r(.searching).power.figure, "—"); XCTAssertNil(r(.searching).warning)
        var p = r(.measured(0)); p.phase = .paused; p.pausedSeconds = 46; p.cadence = .measured(0)
        XCTAssertEqual(p.elapsedLabel, "PAUSED AT"); XCTAssertEqual(p.powerLabel, "POWER · LIVE"); XCTAssertEqual(p.powerLine, "Measured now · not recorded", "a pause does not turn a reading into coasting")
        XCTAssertEqual(p.cadenceLabel, "CADENCE · LIVE"); XCTAssertEqual(p.heartRateLabel, "HEART RATE")
        XCTAssertEqual(p.timeLine, "Moving 00:10 · lap 1 · paused 0:46"); XCTAssertTrue(p.stateLine.contains("paused"))
        XCTAssertEqual(p.notices.first, CyclingNotice(kind: .paused, text: "Paused. Time and distance are not counting."))
        var h = r(.measured(231)); h.heartRate = .disconnected
        XCTAssertEqual(h.warning, "Heart-rate sensor lost. Heart rate is not being recorded."); XCTAssertEqual(h.heartRate.figure, "—")
        h.heartRate = .stale(last: 150, ageSeconds: 8); XCTAssertEqual(h.heartRateLabel, "HEART RATE · NO UPDATE")
    }
    func testTimeLineShowsOnlyWhatIsKnown() {
        var x = r(.measured(231)); x.laps = 1
        XCTAssertEqual(x.timeLine, "Moving 00:10 · lap 2")
        x.intervalRemainingSeconds = 264; XCTAssertEqual(x.timeLine, "Moving 00:10 · lap 2 · interval −4:24")
        x.movingKnown = false; x.intervalRemainingSeconds = nil; XCTAssertEqual(x.timeLine, "lap 2", "no moving time is shown when the recorder has none")
        x.phase = .paused; XCTAssertEqual(x.timeLine, "lap 2", "an unknown pause length is not shown")
        x.phase = .ready; XCTAssertEqual(x.elapsedLabel, "NOT RECORDING"); XCTAssertNil(x.mini)
    }
    func testSpeedDistanceAndSources() {
        var x = r(.measured(231)); XCTAssertEqual(x.speedText, "30.0 km/h"); XCTAssertEqual(x.distanceText, "1.0 km"); XCTAssertNil(x.speedNote)
        x.speedEstimated = true; XCTAssertEqual(x.speedNote, "estimated")
        x.speedKmh = nil; x.speedReason = CyclingSensorMap.speedReason(gps: "searching"); XCTAssertEqual(x.speedText, "—"); XCTAssertEqual(x.speedNote, "waiting for GPS")
        x.distanceKnown = false; XCTAssertEqual(x.distanceText, "—", "no distance is not 0.0"); XCTAssertEqual(x.mapTiles.map { $0.value }, ["00:10", "—", "231"])
        x.imperial = true; x.distanceKnown = true; x.speedKmh = 16.09344; XCTAssertEqual(x.speedText, "10.0 mph"); XCTAssertEqual(x.mapTiles[1].label, "MI")
        XCTAssertEqual(x.sourceLine, CyclingSourceLine(state: .none, text: "No sensor is sending values"))
        x.sourceNames = CyclingSensorMap.sourceNames(["Power meter via BikeComputer", nil, "Power meter via BikeComputer", "", "Phone GPS"])
        XCTAssertEqual(x.sourceLine, CyclingSourceLine(state: .live, text: "Power meter via BikeComputer · Phone GPS"))
        x.simulated = true; XCTAssertEqual(x.sourceLine.state, .simulated); XCTAssertTrue(x.sourceLine.text.contains("Simulated"))
    }
    func testAPhoneRecordedRideSaysWhatItDoesNotStore() {
        XCTAssertNil(CyclingSensorMap.notStoredNote([]))
        XCTAssertEqual(CyclingSensorMap.notStoredNote(["power"]), "This phone is the recorder. Power is shown live and not stored in this ride.")
        XCTAssertEqual(CyclingSensorMap.notStoredNote(["power", "cadence"]), "This phone is the recorder. Power and cadence are shown live and not stored in this ride.")
        var x = r(.disconnected); x.powerStored = false
        XCTAssertNil(x.warning, "a value that is not stored cannot be reported as not being recorded")
        x.phase = .ready; x.powerStored = true; XCTAssertNil(x.warning, "nothing is warned about before a ride is recorded")
    }
    func testMovingSecondsAndFinishSummary() {
        XCTAssertNil(CyclingSensorMap.movingSeconds(speedsCms: [nil, nil]), "no speed at all: no moving time")
        XCTAssertEqual(CyclingSensorMap.movingSeconds(speedsCms: [0, 49, 50, 800, nil]), 2)
        let s = CyclingFinishSummary.make(elapsedSeconds: 5, movingSeconds: nil, distanceKm: nil, power: [200, nil, 0, nil, 100], heartRate: [nil, nil, nil, nil, nil])
        XCTAssertEqual(s.averagePower, 100, "a measured zero counts, a missing second does not"); XCTAssertEqual(s.powerMissingSeconds, 2)
        XCTAssertEqual(s.powerDetail, "2 s missing — not filled in"); XCTAssertEqual(CyclingFinishSummary.missingText(132), "2 min 12 s missing — not filled in")
        XCTAssertNil(s.averageHeartRate); XCTAssertEqual(s.heartRateText, "—"); XCTAssertEqual(s.heartRateDetail, "no heart-rate values"); XCTAssertEqual(s.distanceText, "—"); XCTAssertNil(s.movingText)
        let d = CyclingDemoScript.summary(seconds: 90)
        XCTAssertEqual(d.powerMissingSeconds, 22, "the script's stale and lost seconds are counted as missing"); XCTAssertEqual(d.heartRateMissingSeconds, 0)
    }
    func testTheDemoIsMarkedSimulatedAndTheMiniValueFollowsIt() {
        let x = CyclingDemoScript.readout(at: 36, phase: .recording, laps: 0)
        XCTAssertTrue(x.simulated); XCTAssertEqual(x.sourceLine.state, .simulated); XCTAssertEqual(x.intervalRemainingSeconds, 264)
        XCTAssertEqual(x.mini, CyclingMiniState(elapsedSeconds: 36, paused: false, simulated: true)); XCTAssertEqual(x.mini?.label, "00:36")
        XCTAssertEqual(CyclingDemoScript.readout(at: 36, phase: .paused, laps: 0).mini?.label, "Paused 00:36")
        XCTAssertNil(CyclingDemoScript.readout(at: 36, phase: .ended, laps: 0).mini)
    }
}
