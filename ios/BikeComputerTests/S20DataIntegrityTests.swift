import XCTest
@testable import BikeComputer

// S2-0 data integrity (ios/S20_DATA_INTEGRITY.md): no fabricated defaults, provenance + migration, energy units, device
// states, Apple Health precedence. Pure model/engine tests — they run on the Linux harness and on the CI simulator.

final class NoFabricatedDefaultsTests: XCTestCase {
    func testFreshProfileHasNoSampleValues() {
        let p = RiderProfile()
        XCTAssertNil(p.weightKg); XCTAssertNil(p.age); XCTAssertNil(p.dateOfBirth); XCTAssertNil(p.birthYear)
        XCTAssertEqual(p.ftpW, 0); XCTAssertFalse(p.ftpKnown); XCTAssertNil(p.ftpValue); XCTAssertNil(p.targetFTP); XCTAssertEqual(p.ftpDisplay, "Unknown")
        XCTAssertNil(p.effectiveAge); XCTAssertNil(p.maxHRForZones); XCTAssertNil(p.hrZones); XCTAssertFalse(p.hrZonesKnown)
        XCTAssertNil(p.wattsPerKg); XCTAssertTrue(p.powerZones.isEmpty); XCTAssertEqual(p.zone(forWatts: 250), 0)
        XCTAssertEqual(p.provenance(.weight).source, .unknown); XCTAssertEqual(p.provenance(.ftp).source, .unknown)
    }
    func testRideTargetsAreEffortOnlyWithoutFTPOrMaxHR() {
        let p = RiderProfile()
        let w = Workout(date: Date(), kind: .tempo, minutes: 60)
        let work = w.rideSteps.filter { $0.role == .work }
        XCTAssertFalse(work.isEmpty)
        for s in work {
            XCTAssertNil(s.watts(ftp: p.targetFTP))
            XCTAssertEqual(s.targetText(ftp: p.targetFTP, hrZones: p.hrZones), "RPE 5–6", "no FTP and no HR zones → effort only")
        }
        XCTAssertNil(TrainingAnalyzer.hrZone(150, profile: p), "no HR zone from an unknown max HR")
    }
    func testBoardMessageSendsZeroForUnknowns() {
        var p = RiderProfile(); p.name = "Rider A"; p.version = 2
        let m = p.linkMessage(units: .metric)
        XCTAssertEqual(m.ftpW, 0); XCTAssertEqual(m.ftpHow, 0); XCTAssertEqual(m.weightKgX10, 0); XCTAssertEqual(m.birthYear, 0); XCTAssertEqual(m.maxHR, 0)
        // a known value still goes through
        p.setFTP(250, source: .entered); p.setWeight(78); p.setDateOfBirth(Calendar.current.date(from: DateComponents(year: 1990, month: 6, day: 1)))
        let k = p.linkMessage(units: .metric)
        XCTAssertEqual(k.ftpW, 250); XCTAssertEqual(k.ftpHow, 1); XCTAssertEqual(k.weightKgX10, 780); XCTAssertEqual(k.birthYear, 1990)
    }
    func testSettingFTPWithoutWattsKeepsItUnknown() {
        var p = RiderProfile()
        p.setFTP(nil, source: .entered); XCTAssertFalse(p.ftpKnown); XCTAssertEqual(p.ftpW, 0)
        p.setFTP(0, source: .tested); XCTAssertFalse(p.ftpKnown)
        p.setFTP(260, source: .entered); XCTAssertTrue(p.ftpKnown); XCTAssertEqual(p.provenance(.ftp).source, .entered); XCTAssertNotNil(p.provenance(.ftp).recordedAt)
        p.setFTP(nil, source: .unknown); XCTAssertFalse(p.ftpKnown); XCTAssertEqual(p.ftpW, 0); XCTAssertEqual(p.provenance(.ftp).source, .unknown)
    }
    func testRecoveryProfileWithoutAgeAppliesNoAgeRule() {
        var p = RiderProfile(); p.recoveryCapacity = .normal
        let r = p.recovery
        XCTAssertNil(r.age); XCTAssertFalse(r.older); XCTAssertFalse(r.reduced); XCTAssertNil(r.reason)
        p.setDateOfBirth(Calendar.current.date(byAdding: .year, value: -65, to: Date()))
        XCTAssertTrue(p.recovery.older)
    }
    func testMaxHRFromAKnownAgeIsAnEstimate() {
        var p = RiderProfile()
        p.setDateOfBirth(Calendar.current.date(byAdding: .year, value: -40, to: Date()))
        XCTAssertEqual(p.effectiveAge, 40); XCTAssertEqual(p.maxHRForZones, 180); XCTAssertTrue(p.maxHRIsEstimate); XCTAssertEqual(p.hrZones?.count, 5)
        p.setMaxHR(190); XCTAssertEqual(p.maxHRForZones, 190); XCTAssertFalse(p.maxHRIsEstimate)
    }
}

final class ProvenanceMigrationTests: XCTestCase {
    private func decode(_ json: String) throws -> StoreFile {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(StoreFile.self, from: Data(json.utf8))
    }
    /// A build-121-shaped file (schema 2): untouched defaults 75 kg / 35 y / 225 W assumed.
    private let build121 = """
    {"schema":2,"profile":{"name":"R","goal":"endurance","hoursPerWeek":5,"level":"intermediate","weightKg":75,"age":35,"ftpW":225,"ftpHow":"assumed","hrPrefWatchFirst":false,"trainingMode":"hybrid","liftDaysPerWeek":3,"liftingHoursPerWeek":2},
     "settings":{"units":"metric"},"plan":[],"rides":[{"id":"6C1B2B3C-0000-4000-8000-000000000001","healthUUID":"h-1","start":"2026-10-01T06:00:00Z","durationS":3600,"distanceM":25000,"kj":2092,"zoneSeconds":[0,0,0,0,0,0,0],"recorder":"health","sources":["Apple Health"],"demo":false,"samples":[]}],
     "tiles":["power"],"onboarded":true,"guest":true}
    """
    /// A build-127-shaped file (schema 3): the athlete typed 82 kg and 260 W entered, no provenance recorded yet.
    private let build127 = """
    {"schema":3,"profile":{"name":"R","goal":"endurance","hoursPerWeek":5,"level":"intermediate","weightKg":82,"age":35,"birthYear":1988,"ftpW":260,"ftpHow":"entered","maxHR":185,"restHR":52,"hrPrefWatchFirst":false},
     "settings":{"units":"metric"},"plan":[],"rides":[{"id":"6C1B2B3C-0000-4000-8000-000000000002","boardRideId":7,"start":"2026-10-20T06:00:00Z","durationS":3600,"distanceM":30000,"avgPower":180,"kj":648,"zoneSeconds":[0,0,0,0,0,0,0],"recorder":"board","sources":["BikeComputer"],"demo":false,"samples":[]}],
     "tiles":["power"],"onboarded":true,"guest":true}
    """

    func testBuild121DefaultsBecomeUnknown() throws {
        let f = StoreFile.migrate(try decode(build121))
        XCTAssertEqual(f.schema, 4)
        let p = f.profile
        XCTAssertNil(p.weightKg, "75 kg with no sign of entry → Unknown")
        XCTAssertNil(p.age); XCTAssertNil(p.effectiveAge, "35 with no birth date → Unknown")
        XCTAssertEqual(p.ftpW, 0); XCTAssertFalse(p.ftpKnown); XCTAssertEqual(p.provenance(.ftp).source, .unknown)
        XCTAssertNil(p.hrZones); XCTAssertEqual(p.linkMessage(units: .metric).weightKgX10, 0)
        XCTAssertTrue(f.migrationLog.contains { $0.contains("75 kg") }); XCTAssertTrue(f.migrationLog.contains { $0.contains("assumed 35") })
        // energy: the Health import's kcal × 4.184 is converted back and labelled, never shown as work from power
        let r = f.rides[0]
        XCTAssertNil(r.kj); XCTAssertEqual(r.energy?.kind, .activeKcalAppleHealth); XCTAssertEqual(r.energy?.value, 500); XCTAssertEqual(r.energyShown?.unit, "kcal")
        XCTAssertFalse(r.energyShown!.isMeasuredWork)
        // nothing historical is lost
        XCTAssertEqual(f.rides.count, 1); XCTAssertEqual(f.rides[0].healthUUID, "h-1"); XCTAssertEqual(f.rides[0].durationS, 3600)
    }
    func testBuild127TypedValuesAreKeptAsUnverifiedLegacy() throws {
        let f = StoreFile.migrate(try decode(build127))
        let p = f.profile
        XCTAssertEqual(p.weightKg, 82); XCTAssertEqual(p.provenance(.weight).source, .legacyUnverified); XCTAssertTrue(p.provenance(.weight).needsConfirmation)
        XCTAssertEqual(p.ftpW, 260); XCTAssertTrue(p.ftpKnown); XCTAssertEqual(p.provenance(.ftp).source, .legacyUnverified, "an entered FTP of unknown provenance is never relabelled as entered")
        XCTAssertEqual(p.maxHR, 185); XCTAssertEqual(p.provenance(.maxHR).source, .legacyUnverified)
        XCTAssertEqual(p.restHR, 52); XCTAssertEqual(p.provenance(.restHR).source, .legacyUnverified)
        XCTAssertEqual(p.effectiveAge, Calendar.current.component(.year, from: Date()) - 1988, "a birth year is real data"); XCTAssertNil(p.age, "the 35 slider default is dropped")
        XCTAssertEqual(p.provenance(.dateOfBirth).source, .legacyUnverified)
        XCTAssertNotNil(p.hrZones, "zones from the entered max HR")
        let r = f.rides[0]
        XCTAssertEqual(r.kj, 648); XCTAssertEqual(r.energy?.kind, .workFromPowerKJ); XCTAssertEqual(r.energyShown?.unit, "kJ"); XCTAssertEqual(r.energyShown?.sourceText, "from power")
    }
    func testMigrationIsIdempotentAndRoundTrips() throws {
        let f1 = StoreFile.migrate(try decode(build127))
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let f2 = StoreFile.migrate(try dec.decode(StoreFile.self, from: try enc.encode(f1)))
        XCTAssertEqual(f2.profile.provenance.mapValues(\.source), f1.profile.provenance.mapValues(\.source)); XCTAssertEqual(f2.rides[0].energy, f1.rides[0].energy); XCTAssertEqual(f2.schema, 4)
        XCTAssertEqual(f2.migrationLog.count, f1.migrationLog.count, "a second migration adds nothing")
    }
    func testAgeMovedOnTheOldSliderIsKept() throws {
        let json = build121.replacingOccurrences(of: "\"age\":35", with: "\"age\":48")
        let f = StoreFile.migrate(try decode(json))
        XCTAssertEqual(f.profile.effectiveAge, 48); XCTAssertEqual(f.profile.provenance(.dateOfBirth).source, .legacyUnverified)
    }
}

final class EnergyUnitTests: XCTestCase {
    func testHealthImportStoresKcalNotKJ() {
        let s = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("s20-energy-\(UUID().uuidString)"), generatePlan: false)
        XCTAssertTrue(s.importHealthRide(start: Date(timeIntervalSince1970: 1_760_000_000), durationS: 3000, distanceM: 20_000, activeKcal: 480, avgHR: nil, healthUUID: "u-1"))
        let r = s.rides.first { $0.healthUUID == "u-1" }!
        XCTAssertNil(r.kj); XCTAssertEqual(r.energy, EnergyValue(kind: .activeKcalAppleHealth, value: 480))
        XCTAssertEqual(r.energyShown?.unit, "kcal"); XCTAssertEqual(r.energyShown?.sourceText, "Apple Health estimate"); XCTAssertFalse(r.energyShown!.isMeasuredWork)
    }
    func testWorkFromPowerStaysKJ() {
        var r = RideRecord(start: Date(), durationS: 600, distanceM: 1000, recorder: .phone, sources: ["Power meter"])
        r.avgPower = 200; r.kj = 120
        XCTAssertEqual(r.energyShown?.unit, "kJ"); XCTAssertTrue(r.energyShown!.isMeasuredWork)
        var h = RideRecord(start: Date(), durationS: 600, distanceM: 1000, recorder: .health, sources: ["Apple Health"])
        h.kj = 120
        XCTAssertNil(h.energyShown, "a Health ride never shows kJ from power")
    }
}

final class DeviceStateTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_780_000_000)
    func testBoardStates() {
        XCTAssertEqual(DeviceStateRules.board(linkState: .idle, remembered: false, lastLiveAt: nil, pairingLost: false, bluetoothOff: false, now: now), .notPaired)
        XCTAssertEqual(DeviceStateRules.board(linkState: .idle, remembered: true, lastLiveAt: nil, pairingLost: false, bluetoothOff: false, now: now), .paired)
        XCTAssertEqual(DeviceStateRules.board(linkState: .ready, remembered: true, lastLiveAt: nil, pairingLost: false, bluetoothOff: false, now: now), .connected)
        XCTAssertEqual(DeviceStateRules.board(linkState: .ready, remembered: true, lastLiveAt: now.addingTimeInterval(-3), pairingLost: false, bluetoothOff: false, now: now), .receivingData(lastSampleAt: now.addingTimeInterval(-3)))
        XCTAssertEqual(DeviceStateRules.board(linkState: .ready, remembered: true, lastLiveAt: now.addingTimeInterval(-30), pairingLost: false, bluetoothOff: false, now: now), .stale(lastSampleAt: now.addingTimeInterval(-30)), "old samples are 'stale', never 'receiving'")
        if case .problem = DeviceStateRules.board(linkState: .ready, remembered: true, lastLiveAt: nil, pairingLost: true, bluetoothOff: false, now: now) {} else { XCTFail("pairing lost is a problem") }
        if case .problem = DeviceStateRules.board(linkState: .off, remembered: true, lastLiveAt: nil, pairingLost: false, bluetoothOff: true, now: now) {} else { XCTFail("bluetooth off with a paired board is a problem") }
    }
    func testWatchStates() {
        XCTAssertEqual(DeviceStateRules.watch(paired: false, appInstalled: false, sessionRunning: false, lastHRAt: nil, now: now), .notPaired)
        XCTAssertEqual(DeviceStateRules.watch(paired: true, appInstalled: true, sessionRunning: false, lastHRAt: nil, now: now), .paired)
        XCTAssertEqual(DeviceStateRules.watch(paired: true, appInstalled: true, sessionRunning: true, lastHRAt: nil, now: now), .connected)
        XCTAssertEqual(DeviceStateRules.watch(paired: true, appInstalled: true, sessionRunning: true, lastHRAt: now.addingTimeInterval(-1), now: now), .receivingData(lastSampleAt: now.addingTimeInterval(-1)))
        if case .problem = DeviceStateRules.watch(paired: true, appInstalled: false, sessionRunning: false, lastHRAt: nil, now: now) {} else { XCTFail("app missing is a problem") }
    }
    func testBLESensorStates() {
        XCTAssertEqual(DeviceStateRules.bleSensor(configured: false, link: .disconnected, radio: .on, lastSampleAt: nil, now: now), .notPaired)
        XCTAssertEqual(DeviceStateRules.bleSensor(configured: true, link: .disconnected, radio: .on, lastSampleAt: nil, now: now), .paired)
        XCTAssertEqual(DeviceStateRules.bleSensor(configured: true, link: .connected, radio: .on, lastSampleAt: nil, now: now), .connected)
        XCTAssertEqual(DeviceStateRules.bleSensor(configured: true, link: .connected, radio: .on, lastSampleAt: now, now: now), .receivingData(lastSampleAt: now))
        if case .problem = DeviceStateRules.bleSensor(configured: true, link: .connected, radio: .off, lastSampleAt: now, now: now) {} else { XCTFail("radio off is a problem") }
        XCTAssertEqual(DeviceStateRules.bleSensor(configured: false, link: .disconnected, radio: .off, lastSampleAt: nil, now: now), .notPaired, "never red for a sensor the athlete did not set up")
    }
    func testBoardSensorAndHealthStates() {
        XCTAssertEqual(DeviceStateRules.boardSensor(boardReceiving: true, meterLink: 4, enabled: true, lastSampleAt: now, now: now), .receivingData(lastSampleAt: now))
        XCTAssertEqual(DeviceStateRules.boardSensor(boardReceiving: true, meterLink: 4, enabled: true, lastSampleAt: nil, now: now), .connected)
        XCTAssertEqual(DeviceStateRules.boardSensor(boardReceiving: true, meterLink: 2, enabled: true, lastSampleAt: nil, now: now), .paired)
        if case .problem = DeviceStateRules.boardSensor(boardReceiving: true, meterLink: 1, enabled: true, lastSampleAt: nil, now: now) {} else { XCTFail("lost sensor") }
        XCTAssertEqual(DeviceStateRules.boardSensor(boardReceiving: false, meterLink: nil, enabled: false, lastSampleAt: nil, now: now), .notPaired)
        XCTAssertEqual(DeviceStateRules.health(available: true, authorized: true, wanted: true, lastSyncAt: nil, now: now), .connected)
        XCTAssertEqual(DeviceStateRules.health(available: false, authorized: false, wanted: true, lastSyncAt: nil, now: now), .notPaired)
        if case .problem = DeviceStateRules.health(available: true, authorized: false, wanted: true, lastSyncAt: nil, now: now) {} else { XCTFail("wanted but not authorized") }
    }
    func testStaleIsItsOwnState() {
        let old = now.addingTimeInterval(-DeviceState.freshWindow - 1), fresh = now.addingTimeInterval(-DeviceState.freshWindow)
        XCTAssertEqual(DeviceState.linked(lastSampleAt: nil, now: now), .connected)
        XCTAssertEqual(DeviceState.linked(lastSampleAt: fresh, now: now), .receivingData(lastSampleAt: fresh))
        XCTAssertEqual(DeviceState.linked(lastSampleAt: old, now: now), .stale(lastSampleAt: old))
        XCTAssertEqual(DeviceStateRules.bleSensor(configured: true, link: .connected, radio: .on, lastSampleAt: old, now: now), .stale(lastSampleAt: old))
        XCTAssertEqual(DeviceStateRules.boardSensor(boardReceiving: true, meterLink: 4, enabled: true, lastSampleAt: old, now: now), .stale(lastSampleAt: old))
        XCTAssertEqual(DeviceStateRules.watch(paired: true, appInstalled: true, sessionRunning: true, lastHRAt: old, now: now), .stale(lastSampleAt: old))
        XCTAssertEqual(DeviceStateRules.watch(paired: true, appInstalled: true, sessionRunning: false, lastHRAt: old, now: now), .paired, "no session: old samples do not make it stale")
        XCTAssertTrue(DeviceState.stale(lastSampleAt: old).isStale); XCTAssertFalse(DeviceState.stale(lastSampleAt: old).isReceiving)
        XCTAssertTrue(DeviceState.stale(lastSampleAt: old).isConnectedOrBetter)
        XCTAssertEqual(DeviceState.stale(lastSampleAt: old).conn, .amber)
        XCTAssertEqual(DeviceState.stale(lastSampleAt: old).title, "Connected · no recent data")
        XCTAssertTrue(DeviceStateRules.detail(.stale(lastSampleAt: old), lastSyncedAt: nil, now: now).hasPrefix("connected · last data"))
        XCTAssertTrue(CyDeviceState.allCases.contains(.stale))
    }
    func testColoursFollowTheConnectionsRule() {
        XCTAssertEqual(DeviceState.receivingData(lastSampleAt: now).conn, .green)
        XCTAssertEqual(DeviceState.connected.conn, .amber); XCTAssertEqual(DeviceState.paired.conn, .amber)
        XCTAssertEqual(DeviceState.notPaired.conn, .gray); XCTAssertEqual(DeviceState.problem(reason: "x").conn, .red)
    }
}

final class HealthPrecedenceTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_780_000_000)
    func testNewerWins() {
        let older = ValueProvenance(source: .entered, recordedAt: t0)
        XCTAssertEqual(HealthPrecedence.decide(current: older, sample: HealthSample(kind: .weight, value: 80, date: t0.addingTimeInterval(3600))), .useSample)
        let newer = ValueProvenance(source: .entered, recordedAt: t0.addingTimeInterval(7200))
        XCTAssertEqual(HealthPrecedence.decide(current: newer, sample: HealthSample(kind: .weight, value: 80, date: t0.addingTimeInterval(3600))), .keepCurrent)
        XCTAssertEqual(HealthPrecedence.decide(current: ValueProvenance(source: .entered, recordedAt: t0), sample: HealthSample(kind: .weight, value: 80, date: t0)), .keepCurrent, "equal dates: the manual entry stays")
    }
    func testUnknownAndLegacyNeverBeatASample() {
        XCTAssertEqual(HealthPrecedence.decide(current: nil, sample: HealthSample(kind: .restingHR, value: 50, date: t0)), .useSample)
        XCTAssertEqual(HealthPrecedence.decide(current: .unknown, sample: HealthSample(kind: .restingHR, value: 50, date: t0)), .useSample)
        XCTAssertEqual(HealthPrecedence.decide(current: .legacy(t0.addingTimeInterval(99_999)), sample: HealthSample(kind: .restingHR, value: 50, date: t0)), .useSample)
    }
    func testUndatedManualEntryIsKept() {
        XCTAssertEqual(HealthPrecedence.decide(current: ValueProvenance(source: .entered, recordedAt: nil), sample: HealthSample(kind: .weight, value: 80, date: t0)), .keepCurrent)
    }
    func testProfileApplyRecordsSourceAndDate() {
        var p = RiderProfile()
        XCTAssertTrue(p.apply(healthSample: HealthSample(kind: .weight, value: 79.4, date: t0)))
        XCTAssertEqual(p.weightKg, 79.4); XCTAssertEqual(p.provenance(.weight).source, .appleHealth); XCTAssertEqual(p.provenance(.weight).recordedAt, t0)
        p.setWeight(81, at: t0.addingTimeInterval(60))
        XCTAssertFalse(p.apply(healthSample: HealthSample(kind: .weight, value: 79.0, date: t0)), "an older sample never overrides a newer manual entry")
        XCTAssertEqual(p.weightKg, 81)
        XCTAssertTrue(p.apply(healthSample: HealthSample(kind: .hrv, value: 48, date: t0))); XCTAssertEqual(p.hrvMs, 48)
        XCTAssertTrue(p.apply(healthSample: HealthSample(kind: .sleep, value: 7.2, date: t0))); XCTAssertEqual(p.sleepHours, 7.2)
        XCTAssertTrue(p.apply(healthSample: HealthSample(kind: .restingHR, value: 51.4, date: t0))); XCTAssertEqual(p.restHR, 51)
    }
    func testStoreAppliesOnlyEnabledKinds() {
        let s = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("s20-health-\(UUID().uuidString)"), generatePlan: false)
        s.settings.healthReads.weight = true
        let changed = s.applyHealthSamples([HealthSample(kind: .weight, value: 70, date: t0), HealthSample(kind: .hrv, value: 40, date: t0)], now: t0)
        XCTAssertEqual(changed, [.weight]); XCTAssertEqual(s.profile.weightKg, 70); XCTAssertNil(s.profile.hrvMs, "HRV not enabled → not read")
        XCTAssertEqual(s.settings.lastHealthRead, t0)
    }
}
