import XCTest
@testable import BikeComputer

/// RA-14 (lead metric follows the live sensors), RA-17 (GPS state), RA-19 (performance maths).
final class RideViewModelTests: XCTestCase {
    private func base() -> RideCockpitModel.Inputs {
        var i = RideCockpitModel.Inputs()
        i.cadence = 89; i.cadenceLive = true; i.speedKmh = 29.8; i.gpsLive = true; i.distanceM = 11600; i.elapsedS = 1458; i.rpe = 6...7
        return i
    }

    func testPowerWithFTPLeadsWithWattTarget() {
        var i = base(); i.power = 214; i.powerLive = true; i.ftpKnown = true; i.ftp = 240; i.powerBand = (205, 235); i.hr = 148; i.hrLive = true; i.hrZonesKnown = true; i.hrBand = (141, 152)
        let m = RideCockpitModel.make(i)
        XCTAssertEqual(m.lead.kind, .power); XCTAssertEqual(m.lead.value, "214"); XCTAssertEqual(m.lead.target, "205–235 W"); XCTAssertTrue(m.lead.targetKnown)
        XCTAssertTrue(m.zonesShown); XCTAssertNil(m.zoneNote)
        XCTAssertEqual(m.tiles.map(\.key), ["hr", "cad", "speed"])
    }

    func testPowerWithoutFTPLetsHeartRateLeadAndShowsWattsWithoutTarget() {
        var i = base(); i.power = 214; i.powerLive = true; i.ftpKnown = false; i.hr = 148; i.hrLive = true; i.hrZonesKnown = true; i.hrBand = (141, 152)
        let m = RideCockpitModel.make(i)
        XCTAssertEqual(m.lead.kind, .heartRate); XCTAssertEqual(m.lead.target, "141–152 bpm")
        let power = m.tiles.first { $0.key == "power" }
        XCTAssertEqual(power?.value, "214"); XCTAssertEqual(power?.note, "no FTP: no watt target")
        XCTAssertFalse(m.tiles.contains { $0.note.contains("W target") || $0.value == "0" }, "no invented watt target, no 0 W")
    }

    func testPowerWithoutFTPAndWithoutZonesIsByEffort() {
        var i = base(); i.power = 214; i.powerLive = true; i.ftpKnown = false
        let m = RideCockpitModel.make(i)
        XCTAssertEqual(m.lead.kind, .power); XCTAssertFalse(m.lead.targetKnown); XCTAssertEqual(m.lead.target, "effort 6–7 of 10")
        XCTAssertFalse(m.zonesShown); XCTAssertNotNil(m.zoneNote)
    }

    func testHeartRateOnlyLeadsAndNoPowerTileAppears() {
        var i = base(); i.hr = 148; i.hrLive = true; i.hrZonesKnown = true; i.hrBand = (141, 152)
        let m = RideCockpitModel.make(i)
        XCTAssertEqual(m.lead.kind, .heartRate); XCTAssertTrue(m.zonesShown)
        XCTAssertFalse(m.tiles.contains { $0.key == "power" }, "a missing meter is never drawn, not even as 0 W")
        XCTAssertEqual(m.tiles.map(\.key), ["cad", "speed", "dist"])
    }

    func testNothingLiveLeadsWithSpeedAndEffort() {
        let m = RideCockpitModel.make(base())
        XCTAssertEqual(m.lead.kind, .speed); XCTAssertEqual(m.lead.value, "29.8"); XCTAssertEqual(m.lead.target, "effort 6–7 of 10")
        XCTAssertFalse(m.zonesShown); XCTAssertEqual(m.tiles.map(\.key), ["cad", "dist", "time"])
        XCTAssertEqual(m.tiles.last?.value, "24:18")
    }

    func testStaleOrMissingPowerNeverLeads() {
        var i = base(); i.power = 0; i.powerLive = false; i.ftpKnown = true; i.ftp = 240; i.powerBand = (205, 235)
        let m = RideCockpitModel.make(i)
        XCTAssertNotEqual(m.lead.kind, .power)
        XCTAssertFalse(m.tiles.contains { $0.key == "power" })
    }

    func testUnverifiedMeterIsLabelled() {
        var i = base(); i.power = 214; i.powerLive = true; i.powerUnverified = true; i.ftpKnown = true; i.ftp = 240; i.powerBand = (205, 235)
        XCTAssertTrue(RideCockpitModel.make(i).lead.label.contains("UNVERIFIED"))
    }

    func testGPSLostOnlyWhenTheFixIsOld() {
        XCTAssertEqual(RideGPSState.make(sharing: true, lastFixAgeS: 2, authorized: true), .good)
        XCTAssertEqual(RideGPSState.make(sharing: true, lastFixAgeS: 31, authorized: true), .lost)
        XCTAssertEqual(RideGPSState.make(sharing: true, lastFixAgeS: nil, authorized: true), .searching)
        XCTAssertEqual(RideGPSState.make(sharing: false, lastFixAgeS: 2, authorized: true), .off)
        XCTAssertEqual(RideGPSState.make(sharing: true, lastFixAgeS: 2, authorized: false), .off)
        XCTAssertNotNil(RideGPSState.lost.banner); XCTAssertNil(RideGPSState.good.banner)
    }

    private func samples(_ n: Int, w: ((Int) -> Int?)? = nil, hr: ((Int) -> Int?)? = nil, speed: Int? = 800) -> [RidePerformanceModel.Sample] {
        (1...n).map { t in RidePerformanceModel.Sample(t: t, w: w?(t), cad: 88, hr: hr?(t), speedCms: speed) }
    }
    private let zones: [(lo: Int, hi: Int?)] = [(0, 120), (121, 140), (141, 152), (153, 165), (166, nil)]
    private let steps: [(name: String, minutes: Int, hrZone: Int?, rpe: ClosedRange<Int>)] = [("Warm-up", 2, 2, 3...4), ("Interval 1", 2, 3, 6...7), ("Interval 2", 2, 3, 6...7)]

    func testPerformanceWithPowerUsesPowerZonesAndIntervalBands() {
        let s = samples(240, w: { $0 <= 120 ? 160 : 220 }, hr: { _ in 145 })
        let m = RidePerformanceModel.make(samples: s, elapsedS: 240, lapStartS: 0, ftpKnown: true, ftp: 240, hrZones: zones, maxHr: 185, steps: steps)
        XCTAssertEqual(m.series.map(\.key), ["power", "hr", "cad"])
        XCTAssertEqual(m.zoneBasis, "POWER ZONES · FTP 240 W")
        XCTAssertEqual(m.zoneSeconds.reduce(0, +), 240)
        XCTAssertEqual(m.zoneSeconds[1], 120, "160 W = 67 % FTP → Z2 for the first 120 s")
        XCTAssertEqual(m.zoneSeconds[3], 120, "220 W = 92 % FTP → Z4 (Z3 ends at 90 %), same bounds as CoachCore")
        XCTAssertEqual(m.rolling.map(\.key), ["3s", "30s", "lap", "np"])
        XCTAssertEqual(m.intervals.count, 3)
        XCTAssertEqual(m.intervals[0].target, "132–180 W"); XCTAssertEqual(m.intervals[0].actual, "160 W"); XCTAssertEqual(m.intervals[0].inBand, true); XCTAssertTrue(m.intervals[0].done)
        XCTAssertEqual(m.intervals[1].target, "180–216 W"); XCTAssertEqual(m.intervals[1].actual, "220 W"); XCTAssertEqual(m.intervals[1].inBand, false)
        XCTAssertEqual(m.intervals[2].actual, "—", "a step that has not started shows no actual value"); XCTAssertFalse(m.intervals[2].done)
    }

    func testPerformanceWithHeartRateOnlyUsesHRZonesAndNeverPower() {
        let s = samples(180, hr: { $0 <= 120 ? 130 : 147 })
        let m = RidePerformanceModel.make(samples: s, elapsedS: 180, lapStartS: 120, ftpKnown: false, ftp: 0, hrZones: zones, maxHr: 185, steps: steps)
        XCTAssertEqual(m.series.map(\.key), ["hr", "cad"])
        XCTAssertEqual(m.zoneBasis, "HEART-RATE ZONES"); XCTAssertEqual(m.zoneSeconds[1], 120); XCTAssertEqual(m.zoneSeconds[2], 60)
        XCTAssertEqual(m.rolling.map(\.key), ["now", "1m", "lap", "max"])
        XCTAssertEqual(m.rolling[2].value, "147", "lap average counts only samples after the lap start")
        XCTAssertEqual(m.intervals[0].target, "121–140 bpm"); XCTAssertEqual(m.intervals[0].actual, "130 bpm"); XCTAssertEqual(m.intervals[0].inBand, true)
        XCTAssertFalse(m.intervals.contains { $0.target.hasSuffix(" W") }, "no watt targets without a power source")
    }

    func testPerformanceWithGPSOnlyShowsSpeedAndNoZones() {
        let s = samples(100)
        let m = RidePerformanceModel.make(samples: s, elapsedS: 100, lapStartS: 0, ftpKnown: false, ftp: 0, hrZones: nil, maxHr: 0, steps: steps)
        XCTAssertEqual(m.series.map(\.key), ["cad"], "cadence is live; speed only when nothing else is")
        XCTAssertTrue(m.zoneSeconds.isEmpty); XCTAssertNil(m.zoneBasis)
        XCTAssertEqual(m.rolling.first?.label, "SPEED"); XCTAssertEqual(m.rolling.first?.value, "28.8")
        XCTAssertEqual(m.intervals[0].actual, "running"); XCTAssertEqual(m.intervals[0].target, "effort 3–4")
    }

    func testNormalizedPowerNeedsThirtySecondsAndMatchesSteadyState() {
        XCTAssertNil(RidePerformanceModel.normalizedPower(Array(repeating: 200, count: 29)))
        XCTAssertEqual(RidePerformanceModel.normalizedPower(Array(repeating: 200, count: 60)), 200)
    }
}
