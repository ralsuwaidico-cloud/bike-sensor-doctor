import XCTest
@testable import BikeComputer

/// Cyclift sources (A3): standard BLE decoders with byte vectors built from the Bluetooth SIG field layouts, revolution
/// rates with wrap-around and the 3 s stop rule, the hub's one-value-per-metric priority, stale handling, source states
/// and the planned providers (never connected).
final class SourcesTests: XCTestCase {
    private func d(_ b: [UInt8]) -> Data { Data(b) }
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Heart Rate Measurement 0x2A37
    func testHeartRate8And16Bit() {
        XCTAssertEqual(BLEDecode.heartRate(d([0x00, 72])), 72)                       // UINT8 value
        XCTAssertEqual(BLEDecode.heartRate(d([0x01, 0x8C, 0x00])), 140)              // UINT16 value (flag bit 0)
        XCTAssertEqual(BLEDecode.heartRate(d([0x01, 0x2C, 0x01])), nil)              // 300 bpm: implausible
        XCTAssertEqual(BLEDecode.heartRate(d([0x01, 0x8C])), nil)                    // truncated UINT16
        XCTAssertEqual(BLEDecode.heartRate(d([0x00])), nil)
        XCTAssertEqual(BLEDecode.heartRate(d([0x00, 0])), nil)                       // 0 = no reading
    }
    func testHeartRateRRAndEnergyIgnored() {
        XCTAssertEqual(BLEDecode.heartRate(d([0x10, 80, 0x00, 0x04, 0x10, 0x04])), 80)        // RR intervals present
        XCTAssertEqual(BLEDecode.heartRate(d([0x19, 0x5A, 0x00, 0x20, 0x00, 0x00, 0x04])), 90) // UINT16 + energy + RR
    }
    func testHeartRateContact() {
        XCTAssertEqual(BLEDecode.heartRate(d([0x04, 70])), nil)    // contact supported, not detected
        XCTAssertEqual(BLEDecode.heartRate(d([0x06, 70])), 70)     // contact supported and detected
        XCTAssertEqual(BLEDecode.heartRate(d([0x02, 70])), 70)     // contact not supported: bit 1 meaningless
    }

    // MARK: Cycling Power Measurement 0x2A63
    func testCyclingPowerBasic() {
        XCTAssertEqual(BLEDecode.cyclingPower(d([0x00, 0x00, 0xFA, 0x00])), CyclingPowerMeasurement(powerW: 250, wheel: nil, crank: nil))
        XCTAssertEqual(BLEDecode.cyclingPower(d([0x00, 0x00, 0xF6, 0xFF]))?.powerW, 0)          // -10 W (SINT16) → 0
        XCTAssertNil(BLEDecode.cyclingPower(d([0x00, 0x00, 0xFA])))
        XCTAssertNil(BLEDecode.cyclingPower(d([0x00, 0x00, 0x10, 0x27])))                       // 10000 W spike
    }
    func testCyclingPowerCrankData() {
        // flags bit 5: crank revolution data — cumulative crank revs 10, last crank event 1024/1024 s
        let m = BLEDecode.cyclingPower(d([0x20, 0x00, 0x2C, 0x01, 0x0A, 0x00, 0x00, 0x04]))
        XCTAssertEqual(m?.powerW, 300)
        XCTAssertEqual(m?.crank, RevSample(revs: 10, eventTime: 1024))
        XCTAssertNil(m?.wheel)
    }
    func testCyclingPowerOptionalFieldOffsets() {
        // flags 0x0035: pedal balance (1) + accumulated torque (2) + wheel data (4+2) + crank data (2+2)
        let m = BLEDecode.cyclingPower(d([0x35, 0x00, 0xC8, 0x00, 0x32, 0x10, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x08, 0x05, 0x00, 0x00, 0x02]))
        XCTAssertEqual(m?.powerW, 200)
        XCTAssertEqual(m?.wheel, RevSample(revs: 1, eventTime: 2048))
        XCTAssertEqual(m?.crank, RevSample(revs: 5, eventTime: 512))
    }

    // MARK: CSC Measurement 0x2A5B
    func testCSC() {
        let both = BLEDecode.csc(d([0x03, 0x64, 0x00, 0x00, 0x00, 0x00, 0x04, 0x32, 0x00, 0x00, 0x08]))
        XCTAssertEqual(both?.wheel, RevSample(revs: 100, eventTime: 1024))
        XCTAssertEqual(both?.crank, RevSample(revs: 50, eventTime: 2048))
        XCTAssertEqual(BLEDecode.csc(d([0x02, 0x07, 0x00, 0x00, 0x01]))?.crank, RevSample(revs: 7, eventTime: 256))
        XCTAssertNil(BLEDecode.csc(d([0x02, 0x07, 0x00, 0x00, 0x01]))?.wheel)
        XCTAssertNil(BLEDecode.csc(d([0x01, 0x64, 0x00])))      // truncated wheel data
        XCTAssertNil(BLEDecode.csc(d([0x00])))                  // nothing present
    }

    // MARK: revolution rates
    func testCadenceFromCrankDeltas() {
        var r = RevolutionRate.crank()
        r.update(RevSample(revs: 10, eventTime: 0), at: t0)
        XCTAssertNil(r.rate(at: t0))                                         // one sample: unknown
        r.update(RevSample(revs: 11, eventTime: 1024), at: t0 + 1)
        XCTAssertEqual(r.rate(at: t0 + 1)!, 60, accuracy: 0.01)
        r.update(RevSample(revs: 13, eventTime: 2048), at: t0 + 2)
        XCTAssertEqual(r.rate(at: t0 + 2)!, 120, accuracy: 0.01)
    }
    func testCrankWrapAround() {
        var r = RevolutionRate.crank()
        r.update(RevSample(revs: 65535, eventTime: 65000), at: t0)
        r.update(RevSample(revs: 1, eventTime: 500), at: t0 + 1)            // both 16-bit counters wrapped
        XCTAssertEqual(r.rate(at: t0 + 1)!, 2.0 / (1036.0 / 1024.0) * 60, accuracy: 0.01)
    }
    func testWheelWrapAndSpeed() {
        var r = RevolutionRate.cscWheel()
        r.update(RevSample(revs: UInt32.max, eventTime: 65024), at: t0)
        r.update(RevSample(revs: 1, eventTime: 512), at: t0 + 1)            // 2 revs in 1024 ticks = 1 s
        let rpm = r.rate(at: t0 + 1)!
        XCTAssertEqual(rpm, 120, accuracy: 0.01)
        XCTAssertEqual(RevolutionRate.speedKmh(wheelRpm: rpm, circumferenceMm: 2096), 15.0912, accuracy: 0.001)
        var p = RevolutionRate.powerWheel()                                  // Cycling Power wheel: 1/2048 s
        p.update(RevSample(revs: 0, eventTime: 0), at: t0)
        p.update(RevSample(revs: 1, eventTime: 2048), at: t0 + 1)
        XCTAssertEqual(p.rate(at: t0 + 1)!, 60, accuracy: 0.01)
    }
    func testCadenceDropsToZeroAfterThreeSeconds() {
        var r = RevolutionRate.crank()
        r.update(RevSample(revs: 10, eventTime: 0), at: t0)
        r.update(RevSample(revs: 11, eventTime: 1024), at: t0 + 1)
        r.update(RevSample(revs: 11, eventTime: 1024), at: t0 + 2)          // repeated notification: no new event
        XCTAssertEqual(r.rate(at: t0 + 3.9)!, 60, accuracy: 0.01)
        XCTAssertEqual(r.rate(at: t0 + 4.0), 0)                              // 3 s since the last crank event
        var fresh = RevolutionRate.crank()
        fresh.update(RevSample(revs: 5, eventTime: 100), at: t0)
        XCTAssertNil(fresh.rate(at: t0 + 1))
        XCTAssertEqual(fresh.rate(at: t0 + 3), 0)                            // connected, nothing turning
    }
    func testFirstTurnAfterStopIsNotASlowRevolution() {
        var r = RevolutionRate.crank()
        r.update(RevSample(revs: 10, eventTime: 0), at: t0)
        r.update(RevSample(revs: 11, eventTime: 10 * 1024), at: t0 + 10)
        XCTAssertEqual(r.rate(at: t0 + 10), 0)
        r.update(RevSample(revs: 12, eventTime: 11 * 1024), at: t0 + 11)
        XCTAssertEqual(r.rate(at: t0 + 11)!, 60, accuracy: 0.01)
    }

    // MARK: hub priority
    private func hub(watchFirst: Bool = false) -> SensorHub {
        let t = t0
        let h = SensorHub(); h.now = { t }; h.hrWatchFirst = { watchFirst }; return h
    }
    private func src(_ id: String, _ name: String, _ m: ConnectionMethod, via: String? = nil) -> SourceDescriptor { SourceDescriptor(id: id, name: name, method: m, relayedBy: via) }

    func testTwoHeartRateSourcesGiveOneValue() {
        let h = hub()
        h.offer(MetricReading(kind: .heartRate, value: 140, at: t0, source: src("bikecomputer", "Heart-rate strap", .bikeComputer, via: "BikeComputer"), quality: .good))
        h.offer(MetricReading(kind: .heartRate, value: 150, at: t0, source: src("ble:A", "Chest strap", .bleDirect), quality: .good))
        XCTAssertEqual(h.candidates[.heartRate]?.count, 2)
        XCTAssertEqual(h.value(.heartRate), 140)
        XCTAssertEqual(h.reading(.heartRate)?.sourceLabel, "Heart-rate strap via BikeComputer")
        h.withdraw(sourceId: "bikecomputer")
        XCTAssertEqual(h.value(.heartRate), 150)                             // fallback to the direct strap
        XCTAssertEqual(h.reading(.heartRate)?.sourceLabel, "Chest strap")
    }
    func testWatchFirstPreference() {
        for watchFirst in [false, true] {
            let h = hub(watchFirst: watchFirst)
            h.offer(MetricReading(kind: .heartRate, value: 130, at: t0, source: SensorHub.watch, quality: .good))
            h.offer(MetricReading(kind: .heartRate, value: 150, at: t0, source: src("ble:A", "Strap", .bleDirect), quality: .good))
            XCTAssertEqual(h.value(.heartRate), watchFirst ? 130 : 150)
        }
    }
    func testStaleReadingIsNotShownAndIsPruned() {
        let h = hub()
        h.offer(MetricReading(kind: .heartRate, value: 120, at: t0 - 10, source: SensorHub.watch, quality: .good))
        XCTAssertNil(h.reading(.heartRate))                                  // older than 6 s
        h.offer(MetricReading(kind: .power, value: 200, at: t0 - 2, source: src("ble:P", "Power meter", .bleDirect), quality: .unverified))
        XCTAssertEqual(h.value(.power), 200)
        XCTAssertEqual(h.reading(.power)?.quality, .unverified)
        h.offer(MetricReading(kind: .cadence, value: 90, at: t0 - 120, source: src("ble:P", "Power meter", .bleDirect), quality: .good))
        h.pruneStale()
        XCTAssertNil(h.candidates[.cadence]?["ble:P"])
        XCTAssertNotNil(h.candidates[.power]?["ble:P"])
        h.withdraw(sourceId: "ble:P")
        XCTAssertNil(h.reading(.power))
    }
    func testSpeedWheelSensorBeatsGPSAndPowerBoardFirst() {
        let h = hub()
        h.offer(MetricReading(kind: .speed, value: 30, at: t0, source: SensorHub.phoneGPS, quality: .good))
        h.offer(MetricReading(kind: .speed, value: 31.5, at: t0, source: src("ble:W", "Speed sensor", .bleDirect), quality: .good))
        XCTAssertEqual(h.reading(.speed)?.value, 31.5)
        var meter = SensorHub.bikeComputer; meter.name = "Power meter"; meter.relayedBy = "BikeComputer"
        h.offer(MetricReading(kind: .power, value: 210, at: t0, source: src("ble:P", "Power meter", .bleDirect), quality: .unverified))
        h.offer(MetricReading(kind: .power, value: 205, at: t0, source: meter, quality: .unverified))
        XCTAssertEqual(h.value(.power), 205)
        XCTAssertEqual(h.reading(.power)?.sourceLabel, "Power meter via BikeComputer")
    }
    func testMissingTextsAreGeneric() {
        let h = hub()
        for k in MetricKind.allCases { XCTAssertNil(h.reading(k)) }
        XCTAssertEqual(MetricKind.power.missingText, "No power source")
        XCTAssertEqual(MetricKind.heartRate.missingText, "No heart-rate source")
        XCTAssertEqual(MetricKind.cadence.missingText, "No cadence source")
        XCTAssertEqual(MetricKind.speed.missingText, "No speed source")
        for k in MetricKind.allCases { XCTAssertFalse(k.missingText.contains("XDS")); XCTAssertFalse(k.title.contains("XDS")) }
    }
    func testBoardHeartRateEchoIsNotASecondSource() {
        XCTAssertNil(SensorHub.boardHRName(.appleWatch))       // the watch HR this phone sent to the board
        XCTAssertNil(SensorHub.boardHRName(.phoneStrap))       // a direct strap's HR this phone sent to the board
        XCTAssertEqual(SensorHub.boardHRName(.bleStrap), "Heart-rate strap")
        XCTAssertEqual(SensorHub.boardHRName(.xds), "Heart-rate sensor")
    }

    // MARK: source states and colours
    func testSourceStates() {
        XCTAssertEqual(SourceStateRules.board(linkState: .ready, liveFresh: true, remembered: true, autoConnect: true), .connected)
        XCTAssertEqual(SourceStateRules.board(linkState: .idle, liveFresh: false, remembered: false, autoConnect: true), .notConfigured)   // optional device, never set up
        XCTAssertEqual(SourceStateRules.board(linkState: .idle, liveFresh: false, remembered: true, autoConnect: true), .disconnected)
        XCTAssertEqual(SourceStateRules.board(linkState: .unauthorized, liveFresh: false, remembered: true, autoConnect: true), .notAuthorized)
        XCTAssertEqual(SourceStateRules.watch(enabled: true, paired: true, appInstalled: true, hrFresh: false, workoutRunning: true), .connecting)
        XCTAssertEqual(SourceStateRules.watch(enabled: false, paired: true, appInstalled: true, hrFresh: false, workoutRunning: false), .notConfigured)
        XCTAssertEqual(SourceStateRules.gps(authorized: false, sharing: true, fixFresh: false), .notAuthorized)
        XCTAssertEqual(SourceStateRules.gps(authorized: true, sharing: true, fixFresh: true), .connected)
        XCTAssertEqual(SourceStateRules.health(available: true, authorized: false, wanted: true), .notAuthorized)
        XCTAssertEqual(SourceStateRules.health(available: true, authorized: false, wanted: false), .notConfigured)
        XCTAssertEqual(SourceStateRules.bleSensor(radio: .on, link: .connected), .connected)
        XCTAssertEqual(SourceStateRules.bleSensor(radio: .unauthorized, link: .connected), .notAuthorized)
        XCTAssertEqual(SourceStateRules.bleSensor(radio: .off, link: .connecting), .disconnected)
    }
    func testSourceColours() {
        let d = SourceDescriptor(id: "ble:A", name: "Strap", method: .bleDirect)
        XCTAssertEqual(ConnectionRules.source(SourceStatus(descriptor: d, state: .connected, metrics: [.heartRate], provides: "", configured: true)), .green)
        XCTAssertEqual(ConnectionRules.source(SourceStatus(descriptor: d, state: .connecting, metrics: [], provides: "", configured: true)), .amber)
        XCTAssertEqual(ConnectionRules.source(SourceStatus(descriptor: d, state: .disconnected, metrics: [], provides: "", configured: true)), .red)     // paired and missing
        XCTAssertEqual(ConnectionRules.source(SourceStatus(descriptor: d, state: .disconnected, metrics: [], provides: "", configured: false)), .gray)
        XCTAssertEqual(ConnectionRules.source(SourceStatus(descriptor: d, state: .notConfigured, metrics: [], provides: "", configured: true)), .gray)
    }
    func testPlannedProvidersAreNeverConnectedOrLive() {
        XCTAssertEqual(ProviderCatalog.planned.map(\.name), ["Garmin", "WHOOP", "Oura"])
        for p in ProviderCatalog.planned {
            XCTAssertEqual(p.status.state, .planned)
            XCTAssertEqual(p.status.descriptor.timing, .imported)
            XCTAssertEqual(p.status.descriptor.method, .cloudAPI)
            XCTAssertTrue(p.status.metrics.isEmpty)
            XCTAssertEqual(ConnectionRules.source(p.status), .gray)
        }
    }

    // MARK: settings
    func testPairedSensorsSettingIsAdditive() throws {
        let old = #"{"units":"metric","phoneOnlyMode":false,"hrPref":"watch","enabledConnections":["board","watch"]}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertEqual(s.bleSensors, [])
        var n = AppSettings()
        n.bleSensors = [PairedSensor(id: "11111111-2222-3333-4444-555555555555", name: "Chest strap", kinds: [.heartRate], pairedAt: t0)]
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(back.bleSensors, n.bleSensors)
        XCTAssertEqual(back.bleSensors.first?.sourceId, "ble:11111111-2222-3333-4444-555555555555")
        // an unknown future sensor kind is dropped, not fatal
        let future = #"{"bleSensors":[{"id":"X","name":"Thing","kinds":["heartRate","radar"]}]}"#
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: Data(future.utf8)).bleSensors.first?.kinds, [.heartRate])
    }
    func testSensorKindsAndGenericNames() {
        XCTAssertEqual(BLESensorKind.from(serviceId: "180d"), .heartRate)
        XCTAssertEqual(BLESensorKind.from(serviceId: "1818"), .power)
        XCTAssertEqual(BLESensorKind.from(serviceId: "1816"), .speedCadence)
        XCTAssertNil(BLESensorKind.from(serviceId: "FFF0"))
        XCTAssertEqual(PairedSensor(id: "A", name: "P", kinds: [.power, .speedCadence]).metrics, [.power, .cadence, .speed])
        for k in BLESensorKind.allCases { XCTAssertFalse(k.genericName.contains("XDS")) }
    }
}
