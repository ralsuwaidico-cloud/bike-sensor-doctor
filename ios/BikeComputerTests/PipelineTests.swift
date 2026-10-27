import XCTest
@testable import BikeComputer

/// SENSOR_DIAG decoding (docs/LINK_V1_2_SPEC.md section 1.2.2), the pipeline health model, message selection, watch
/// heart-rate de-duplication / staleness, the watch version handshake and the privacy of the diagnostic report.
/// Byte vectors are built by hand from the spec table: header `type flags seq(u16) t_ms(u32)` then TLV little-endian.
final class SensorDiagTests: XCTestCase {
    private func bytes(_ hex: String) -> Data { Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! }) }

    /// Power meter VALID: 300 packets, 2 rejected, last packet 0.3 s, last valid 0.5 s.
    let vectorValid = "40 00 05 00 E8 03 00 00 01 01 21 02 01 01 03 01 06 04 04 2C 01 00 00 05 02 02 00 06 02 03 00 07 02 05 00"
    /// Heart-rate strap CONNECTED, nothing received, ages "none" (0xFFFF), last error "no CCCD".
    let vectorConnected = "40 00 06 00 00 00 00 00 01 01 21 02 01 02 03 01 03 04 04 00 00 00 00 05 02 00 00 06 02 FF FF 07 02 FF FF 08 07 6E 6F 20 43 43 43 44"

    func testDecodesValidPowerMeter() {
        let d = BCLink.decodeSensorDiag(bytes(vectorValid))
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.sensor, .power); XCTAssertEqual(d?.stage, .valid)
        XCTAssertEqual(d?.packets, 300); XCTAssertEqual(d?.rejected, 2)
        XCTAssertEqual(d?.packetAgeDs, 3); XCTAssertEqual(d?.validAgeDs, 5)
        XCTAssertEqual(d?.packetAgeS ?? 0, 0.3, accuracy: 0.001); XCTAssertEqual(d?.validAgeS ?? 0, 0.5, accuracy: 0.001)
        XCTAssertNil(d?.lastError)
        XCTAssertEqual(d?.seq, 5); XCTAssertEqual(d?.boardTimeMs, 1000)
        XCTAssertEqual(d?.stage?.words, "Live")
    }

    func testDecodesConnectedStrapWithErrorAndNoneAges() {
        let d = BCLink.decodeSensorDiag(bytes(vectorConnected))
        XCTAssertEqual(d?.sensor, .hrStrap); XCTAssertEqual(d?.stage, .connected)
        XCTAssertEqual(d?.packets, 0); XCTAssertEqual(d?.rejected, 0)
        XCTAssertNil(d?.packetAgeDs); XCTAssertNil(d?.validAgeDs)          /* 0xFFFF = none */
        XCTAssertEqual(d?.lastError, "no CCCD")
        XCTAssertEqual(d?.stage?.words, "Connected — waiting for data")
    }

    func testEncoderMatchesTheSpecVector() {
        var s = BCLink.SensorDiag(); s.sensorRaw = 1; s.stageRaw = 6; s.packets = 300; s.rejected = 2; s.packetAgeDs = 3; s.validAgeDs = 5
        XCTAssertEqual(BCLink.encodeSensorDiag(s, seq: 5, tMs: 1000), bytes(vectorValid))
        var c = BCLink.SensorDiag(); c.sensorRaw = 2; c.stageRaw = 3; c.packets = 0; c.rejected = 0; c.lastError = "no CCCD"
        XCTAssertEqual(BCLink.encodeSensorDiag(c, seq: 6, tMs: 0), bytes(vectorConnected))
    }

    func testAllStagesAndSensorsHaveWords() {
        let words = (0...8).map { BCLink.SensorDiag.Stage(rawValue: UInt8($0))!.words }
        XCTAssertEqual(words, ["Not paired", "Searching", "Connecting", "Connected — waiting for data", "Connected — waiting for data",
                               "Receiving — no valid readings", "Live", "Data stale", "Error"])
        XCTAssertNil(BCLink.SensorDiag.Stage(rawValue: 9))
        XCTAssertEqual(BCLink.SensorDiag.Sensor.csc.rawValue, 3)
        // stale with a 4.0 s valid age (0x0028)
        let st = BCLink.decodeSensorDiag(bytes("40 00 01 00 00 00 00 00 01 01 21 02 01 03 03 01 07 07 02 28 00"))
        XCTAssertEqual(st?.sensor, .csc); XCTAssertEqual(st?.stage, .stale); XCTAssertEqual(st?.validAgeS ?? 0, 4.0, accuracy: 0.001)
    }

    func testUnknownTagsAndWrongLengthsAreSkipped() {
        // unknown tag 7F inserted, tag 04 with 2 bytes instead of 4 → packets absent, the rest still decodes
        let d = BCLink.decodeSensorDiag(bytes("40 00 02 00 00 00 00 00 01 01 21 7F 02 AA BB 02 01 01 03 01 05 04 02 10 00 05 02 07 00"))
        XCTAssertEqual(d?.stage, .receiving); XCTAssertNil(d?.packets); XCTAssertEqual(d?.rejected, 7)
        // error text longer than 20 bytes is not taken
        let long = "08 15 " + Array(repeating: "41", count: 21).joined(separator: " ")
        XCTAssertNil(BCLink.decodeSensorDiag(bytes("40 00 02 00 00 00 00 00 01 01 21 02 01 01 03 01 08 " + long))?.lastError)
    }

    func testRejectsOtherEventsTruncatedAndIncomplete() {
        // LINK_DIAG (event 0x20) is not a SENSOR_DIAG — and still decodes as LINK_DIAG
        let link = bytes("40 00 01 00 00 00 00 00 01 01 20 02 01 03 03 02 01 00 04 01 01")
        XCTAssertNil(BCLink.decodeSensorDiag(link))
        XCTAssertEqual(BCLink.linkDiag(from: BCLink.decodeEvent(link)!)?.reason, 3)
        // truncated: tag 04 says 4 bytes, only 2 follow → whole message rejected
        XCTAssertNil(BCLink.decodeSensorDiag(bytes("40 00 01 00 00 00 00 00 01 01 21 02 01 01 03 01 06 04 04 2C 01")))
        // no stage / no sensor → rejected
        XCTAssertNil(BCLink.decodeSensorDiag(bytes("40 00 01 00 00 00 00 00 01 01 21 02 01 01")))
        XCTAssertNil(BCLink.decodeSensorDiag(bytes("40 00 01 00 00 00 00 00 01 01 21 03 01 06")))
        // not an EVENT at all (LIVE type 0x10)
        XCTAssertNil(BCLink.decodeSensorDiag(bytes("10 00 01 00 00 00 00 00 01 01 21 02 01 01 03 01 06")))
        // short header
        XCTAssertNil(BCLink.decodeSensorDiag(bytes("40 00 01")))
    }
}

final class PipelineHealthTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func board(readyFor: TimeInterval = 30, liveAge: TimeInterval? = 0.5, power: Int? = nil, meterLink: Int = 4, fw: String = "0.7.2", diag: (stage: UInt8, since: TimeInterval)? = nil) -> BoardInputs {
        var b = BoardInputs()
        b.remembered = true; b.linkReady = true; b.readyAt = now.addingTimeInterval(-readyFor); b.fw = fw
        if let a = liveAge { b.liveAt = now.addingTimeInterval(-a); var l = BCLink.Live(); l.powerW = power; l.meterLink = meterLink; b.live = l }
        if let d = diag {
            var s = BCLink.SensorDiag(); s.sensorRaw = 1; s.stageRaw = d.stage; s.packets = d.stage >= 5 ? 10 : 0
            b.diag[1] = BoardInputs.DiagEntry(diag: s, at: now, stageSince: now.addingTimeInterval(-d.since))
        }
        return b
    }
    private func power(_ b: BoardInputs, displayed: Bool = false) -> PipelineReport {
        PipelineRules.boardSensor(.power, board: b, metricPresent: b.liveFresh(now) && b.live?.powerW != nil, displayed: displayed, wanted: true, now: now)
    }

    func testConnectedButNoDataIsNeverOK() {
        let waiting = power(board(diag: (3, 2)))
        XCTAssertEqual(waiting.health, .waiting)
        XCTAssertEqual(waiting.message, "Power meter connected — waiting for data")
        XCTAssertEqual(waiting.stage(.connected)?.result, .ok)
        XCTAssertNotEqual(waiting.stage(.valid)?.result, .ok)
        let none = power(board(diag: (4, 12)))
        XCTAssertEqual(none.health, .noData)
        XCTAssertEqual(none.message, "Power meter connected — no readings received")
        XCTAssertEqual(none.stage(.subscribed)?.result, .ok)
        XCTAssertNotEqual(none.health, .live)
    }

    func testLiveOnlyWhenValidForwardedAndDisplayed() {
        let r = power(board(power: 210, diag: (6, 20)), displayed: true)
        XCTAssertEqual(r.health, .live)
        XCTAssertTrue(r.stages.allSatisfy { $0.result == .ok }, "\(r.stages)")
        // valid on the board but not in LIVE
        let lost = power(board(power: nil, diag: (6, 20)))
        XCTAssertEqual(lost.health, .noData)
        XCTAssertEqual(lost.stage(.forwarded)?.result, .failed)
        XCTAssertEqual(lost.message, "Power meter live on the board — not reaching the phone")
        // in LIVE but not on screen
        let hidden = power(board(power: 210, diag: (6, 20)), displayed: false)
        XCTAssertNotEqual(hidden.health, .live)
        XCTAssertEqual(hidden.stage(.displayed)?.result, .failed)
    }

    func testStaleAndReceivingWithoutValid() {
        let stale = power(board(diag: (7, 5)))
        XCTAssertEqual(stale.health, .stale); XCTAssertEqual(stale.message, "Power meter data stale")
        XCTAssertEqual(stale.stage(.valid)?.result, .failed)
        let rx = power(board(diag: (5, 30)))
        XCTAssertEqual(rx.health, .noData); XCTAssertEqual(rx.message, "Power meter connected — no valid readings")
        XCTAssertEqual(rx.stage(.receiving)?.result, .ok)
    }

    func testOldFirmwareFallsBackToLiveAges() {
        let r = power(board(readyFor: 30, power: nil, meterLink: 4, fw: "0.7.1"))
        XCTAssertEqual(r.note, "board firmware too old for detailed diagnostics")
        XCTAssertEqual(r.health, .noData); XCTAssertEqual(r.message, "Power meter connected — no readings received")
        let ok = power(board(power: 180, meterLink: 4, fw: "0.6.3"), displayed: true)
        XCTAssertEqual(ok.health, .live); XCTAssertEqual(ok.note, "board firmware too old for detailed diagnostics")
        let searching = power(board(power: nil, meterLink: 2, fw: "0.7.0"))
        XCTAssertEqual(searching.health, .waiting)
        XCTAssertTrue(BoardInputs.version("0.7.2", atLeast: [0, 7, 2])); XCTAssertTrue(BoardInputs.version("0.10.0", atLeast: [0, 7, 2]))
        XCTAssertFalse(BoardInputs.version("0.7.1", atLeast: [0, 7, 2])); XCTAssertFalse(BoardInputs.version(nil, atLeast: [0, 7, 2]))
        XCTAssertEqual(power(board(power: nil, fw: "0.7.2")).note, "waiting for the board's sensor diagnostics")
    }

    func testBoardLinkStates() {
        var b = BoardInputs(); XCTAssertEqual(power(b).health, .notSetUp)
        b.remembered = true
        XCTAssertEqual(power(b).health, .recovering); XCTAssertEqual(power(b).message, "BikeComputer not connected — reconnecting automatically")
        b.needsRepair = true; XCTAssertEqual(power(b).health, .failed)
        let silent = power(board(readyFor: 12, liveAge: nil))
        XCTAssertEqual(silent.health, .noData); XCTAssertEqual(silent.message, "BikeComputer connected — no live data received")
        XCTAssertEqual(silent.stage(.forwarded)?.result, .failed)
        var refused = board(readyFor: 12, liveAge: nil); refused.liveNotifying = false
        XCTAssertEqual(power(refused).message, "BikeComputer connected — live data subscription failed")
    }

    func testStaleAfterThreeAndSixSeconds() {
        // board LIVE: fresh at 2.9 s, stale at 3.1 s
        XCTAssertTrue(board(liveAge: 2.9).liveFresh(now)); XCTAssertFalse(board(liveAge: 3.1).liveFresh(now))
        // direct power sensor (3 s) and heart-rate sensor (6 s)
        var d = DirectInputs(); d.kindTitle = "Power meter"; d.freshS = Freshness.powerS; d.link = .connected; d.subscribed = true
        d.connectedAt = now.addingTimeInterval(-60); d.packets = 50; d.lastPacketAt = now.addingTimeInterval(-2.5); d.lastValidAt = now.addingTimeInterval(-2.5); d.displayed = true
        XCTAssertEqual(PipelineRules.direct(d, now: now).health, .live)
        d.lastValidAt = now.addingTimeInterval(-3.5); d.lastPacketAt = d.lastValidAt; d.displayed = false
        XCTAssertEqual(PipelineRules.direct(d, now: now).health, .stale); XCTAssertEqual(PipelineRules.direct(d, now: now).message, "Power meter data stale")
        d.kindTitle = "Heart-rate sensor"; d.freshS = Freshness.heartRateS; d.lastValidAt = now.addingTimeInterval(-5.5); d.displayed = true
        XCTAssertEqual(PipelineRules.direct(d, now: now).health, .live)
        d.lastValidAt = now.addingTimeInterval(-6.5); d.displayed = false
        XCTAssertEqual(PipelineRules.direct(d, now: now).health, .stale)
        // watch HR: accepted at 5.9 s, too old at 6.1 s; never held after 6 s
        var ing = WatchHRIngest()
        XCTAssertEqual(ing.offer(bpm: 120, sampleAt: now.addingTimeInterval(-5.9), now: now, via: .mirror), .accepted)
        XCTAssertEqual(ing.offer(bpm: 121, sampleAt: now.addingTimeInterval(-6.1), now: now, via: .mirror), .tooOld)
        XCTAssertEqual(ing.current(now: now), 120)
        XCTAssertNil(ing.current(now: now.addingTimeInterval(0.2)))
    }

    func testDirectSensorConnectedNoData() {
        var d = DirectInputs(); d.kindTitle = "Speed / cadence sensor"; d.link = .connected; d.connectedAt = now.addingTimeInterval(-3)
        XCTAssertEqual(PipelineRules.direct(d, now: now).health, .waiting)
        XCTAssertEqual(PipelineRules.direct(d, now: now).message, "Speed / cadence sensor connected — waiting for data")
        d.connectedAt = now.addingTimeInterval(-20)
        XCTAssertEqual(PipelineRules.direct(d, now: now).message, "Speed / cadence sensor connected — no readings received")
        d.subscribed = false
        XCTAssertEqual(PipelineRules.direct(d, now: now).health, .failed)
        d.link = .connecting
        XCTAssertEqual(PipelineRules.direct(d, now: now).health, .idle)          /* asleep outside a ride: normal */
        d.rideActive = true
        XCTAssertEqual(PipelineRules.direct(d, now: now).health, .recovering)
        d.radioOn = false
        XCTAssertEqual(PipelineRules.direct(d, now: now).health, .failed)
        XCTAssertFalse(PipelineRules.direct(d, now: now).title.contains("RiderA"))
    }

    private func watch(_ f: (inout WatchInputs) -> Void) -> PipelineReport {
        var w = WatchInputs(); w.paired = true; w.appInstalled = true; f(&w)
        return PipelineRules.watchHR(w, now: now)
    }

    func testWatchPath() {
        XCTAssertEqual(PipelineRules.watchHR(WatchInputs(), now: now).health, .notSetUp)      /* no watch paired: silent */
        XCTAssertEqual(watch { $0.appInstalled = false }.health, .failed)
        XCTAssertEqual(watch { _ in }.health, .idle)
        // workout running, mirrored, no heart rate yet → waiting, then "heart rate unavailable"
        let wait = watch { $0.mirrorActive = true; $0.workoutState = "running"; $0.workoutStateAt = self.now.addingTimeInterval(-3) }
        XCTAssertEqual(wait.health, .waiting); XCTAssertEqual(wait.message, "Watch connected — waiting for heart rate")
        XCTAssertEqual(wait.stage(.connected)?.detail, "workout mirroring")
        let none = watch { $0.mirrorActive = true; $0.workoutState = "running"; $0.workoutStateAt = self.now.addingTimeInterval(-30) }
        XCTAssertEqual(none.health, .noData); XCTAssertEqual(none.message, "Watch connected — heart rate unavailable")
        // live and echoed by the board
        let live = watch { $0.mirrorActive = true; $0.workoutState = "running"; $0.hrNow = 130; $0.lastSampleAt = self.now; $0.displayed = true
            $0.boardLinkReady = true; $0.boardLiveFresh = true; $0.boardHRSource = .appleWatch; $0.boardHR = 130; $0.hrSentToBoardAt = self.now }
        XCTAssertEqual(live.health, .live); XCTAssertEqual(live.stage(.forwarded)?.result, .ok)
        // live on the phone, the board never echoes it after the grace time
        let notForwarded = watch { $0.mirrorActive = true; $0.workoutState = "running"; $0.workoutStateAt = self.now.addingTimeInterval(-60); $0.hrNow = 130; $0.lastSampleAt = self.now
            $0.displayed = true; $0.boardLinkReady = true; $0.boardLiveFresh = true; $0.boardHRSource = .unknown; $0.hrSentToBoardAt = self.now }
        XCTAssertEqual(notForwarded.stage(.forwarded)?.result, .failed)
        XCTAssertEqual(notForwarded.message, "Phone connected — watch heart rate not reaching the BikeComputer")
        // had readings, link gone → recovering; ride running without workout → restart / failure
        let lost = watch { $0.workoutState = "running"; $0.lastSampleAt = self.now.addingTimeInterval(-20) }
        XCTAssertEqual(lost.health, .recovering)
        XCTAssertEqual(watch { $0.rideActive = true; $0.startRequestedAt = self.now.addingTimeInterval(-5) }.message, "Starting the watch workout…")
        XCTAssertEqual(watch { $0.rideActive = true }.health, .failed)
        XCTAssertEqual(watch { $0.watchWorkoutAuth = "denied"; $0.workoutState = "running" }.health, .failed)
    }

    func testMessageSelection() {
        let w = PipelineReport(id: "board.power", title: "", stages: [], health: .waiting, message: "Power meter connected — waiting for data")
        let n = PipelineReport(id: "watch.hr", title: "", stages: [], health: .noData, message: "Watch connected — heart rate unavailable")
        let l = PipelineReport(id: "ble.1", title: "", stages: [], health: .live, message: "Heart-rate sensor live")
        let i = PipelineReport(id: "watch.hr", title: "", stages: [], health: .idle, message: "Watch ready")
        XCTAssertEqual(PipelineRules.topMessage([w, n, l])?.message, "Watch connected — heart rate unavailable")
        XCTAssertNil(PipelineRules.topMessage([l, i]))
        XCTAssertEqual(PipelineRules.topMessage([l, w])?.message, "Power meter connected — waiting for data")
        // the watch update notice beats "waiting", never a real failure
        XCTAssertEqual(PipelineRules.topMessage([w], versionNotice: WatchVersion.updateInstruction)?.message, WatchVersion.updateInstruction)
        XCTAssertEqual(PipelineRules.topMessage([n], versionNotice: WatchVersion.updateInstruction)?.message, n.message)
        XCTAssertEqual(PipelineRules.topMessage([l], versionNotice: WatchVersion.updateInstruction)?.message, WatchVersion.updateInstruction)
        // ties keep the path order (power first)
        let n2 = PipelineReport(id: "board.power", title: "", stages: [], health: .noData, message: "Power meter connected — no readings received")
        XCTAssertEqual(PipelineRules.topMessage([n2, n])?.message, n2.message)
        // per-metric labels on the ride screen
        XCTAssertEqual(PipelineRules.missingReasons([w])[.power], "Connected — waiting for data")
        XCTAssertEqual(PipelineRules.missingReasons([n])[.heartRate], "No heart rate data")
        XCTAssertNil(PipelineRules.missingReasons([l, i])[.heartRate])
        let stale = PipelineReport(id: "ble.2", title: "", stages: [], health: .stale, message: "")
        XCTAssertEqual(PipelineRules.missingReasons([stale], directMetrics: ["ble.2": [.speed, .cadence]])[.speed], "Data stale")
    }
}

final class WatchPipelineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDedupeAcrossChannels() {
        var g = WatchHRIngest()
        let t = now.addingTimeInterval(-1)
        XCTAssertEqual(g.offer(bpm: 140, sampleAt: t, now: now, via: .mirror), .accepted)
        XCTAssertEqual(g.offer(bpm: 140, sampleAt: t, now: now, via: .connectivity), .duplicate)        /* same sample, second channel */
        XCTAssertEqual(g.offer(bpm: 139, sampleAt: t.addingTimeInterval(-2), now: now, via: .connectivity), .outOfOrder)
        XCTAssertEqual(g.offer(bpm: 300, sampleAt: now, now: now, via: .mirror), .implausible)
        XCTAssertEqual(g.offer(bpm: 141, sampleAt: now.addingTimeInterval(5), now: now, via: .mirror), .future)
        XCTAssertEqual(g.offer(bpm: 142, sampleAt: now, now: now, via: .connectivity), .accepted)
        XCTAssertEqual(g.totalAccepted, 2); XCTAssertEqual(g.duplicates, 1); XCTAssertEqual(g.dropped, 3)
        XCTAssertEqual(g.accepted[.mirror], 1); XCTAssertEqual(g.accepted[.connectivity], 1)
        XCTAssertEqual(g.current(now: now), 142); XCTAssertEqual(g.lastChannel, .connectivity)
        XCTAssertNil(g.current(now: now.addingTimeInterval(6.5)))                                      /* never held */
    }

    func testPayloadRoundTrip() {
        let p = WatchHRPayload(bpm: 128, at: 1_800_000_000.25, state: "running", build: "1.0.0 (65)", battery: 81, seq: 7)
        let d = p.encoded()!
        XCTAssertLessThan(d.count, 120)
        XCTAssertEqual(WatchHRPayload.decode(d), p)
        XCTAssertNil(WatchHRPayload.decode(Data("nonsense".utf8)))
        var v2 = p; v2.v = 2
        XCTAssertNil(WatchHRPayload.decode(v2.encoded()!))
        let stateOnly = WatchHRPayload(bpm: nil, at: 1, state: "paused", build: "", battery: nil, seq: 1)
        XCTAssertNil(WatchHRPayload.decode(stateOnly.encoded()!)?.bpm)
    }

    func testWatchLinkCountsASampleOnceFromBothChannels() {
        let w = WatchLink()
        let at = Date().addingTimeInterval(-0.5).timeIntervalSince1970
        let p = WatchHRPayload(bpm: 133, at: at, state: "running", build: "1.0.0 (60)", battery: nil, seq: 1)
        w.handle(payload: p, via: .mirror)
        w.handle(payload: p, via: .connectivity)
        XCTAssertEqual(w.hrReceived, 1)
        XCTAssertEqual(w.hrBpm, 133)
        XCTAssertTrue(w.hrIsFresh)
        XCTAssertEqual(w.workoutState, "running")
        XCTAssertEqual(w.watchBuild, "1.0.0 (60)")
        // a reading that is already 7 s old is neither shown nor forwarded
        let old = WatchHRPayload(bpm: 150, at: Date().addingTimeInterval(-7).timeIntervalSince1970, state: "running", build: "", battery: nil, seq: 2)
        w.handle(payload: old, via: .connectivity)
        XCTAssertEqual(w.hrReceived, 1); XCTAssertEqual(w.hrBpm, 133)
    }

    func testVersionHandshake() {
        XCTAssertEqual(WatchVersion.buildNumber("1.0.0 (64)"), 64)
        XCTAssertNil(WatchVersion.buildNumber("1.0.0"))
        XCTAssertEqual(WatchVersion.compare(phone: "1.0.0 (65)", watch: "1.0.0 (65)"), .same)
        XCTAssertEqual(WatchVersion.compare(phone: "1.0.0 (65)", watch: "1.0.0 (61)"), .watchOlder)
        XCTAssertEqual(WatchVersion.compare(phone: "1.0.0 (65)", watch: "1.0.0 (66)"), .watchNewer)
        XCTAssertEqual(WatchVersion.compare(phone: "1.0.0 (65)", watch: nil), .unknown)
        XCTAssertEqual(WatchVersion.compare(phone: "1.0.0 (65)", watch: ""), .unknown)
        XCTAssertEqual(WatchVersion.compare(phone: "1.0.0 (65)", watch: "0.9"), .watchOlder)
        XCTAssertEqual(WatchVersion.updateInstruction, "Update the Watch app: Watch app on iPhone › Cyclift › Update/Install")
        let info = WatchMessage.makeWatchInfo(build: "1.0.0 (65)", workoutAuth: "allowed")
        XCTAssertEqual(info[WatchMessage.kind] as? String, WatchMessage.watchInfo); XCTAssertEqual(info[WatchMessage.build] as? String, "1.0.0 (65)")
        XCTAssertEqual(WatchMessage.makeHR(bpm: 120, at: now, workout: "running", battery: nil, build: "1.0.0 (65)")[WatchMessage.build] as? String, "1.0.0 (65)")
    }
}

final class DiagnosticReportPrivacyTests: XCTestCase {
    /// The seeded rider name (LaunchSmokeTests seeds 24/30/33/36/40 use "RiderA"), a sensor's advertised name, an e-mail
    /// address and a board hardware address must never appear in the exported report.
    func testReportContainsNoPersonalData() {
        let now = Date()
        let events = [DiagEvent(at: now, kind: "sensor", text: "RiderA’s HRM connected"),
                      DiagEvent(at: now, kind: "board", text: "Note: a different board (aa:bb:cc:dd:ee:ff); support ridera@example.com"),
                      DiagEvent(at: now, kind: "health", text: "Power meter → BikeComputer → iPhone: live → no data")]
        let report = DiagnosticReport(
            generatedAt: now, app: "1.0.0 (65)", system: "iOS 26.0", watchApp: "1.0.0 (63)", watchVersionCheck: "watch app is OLDER — update it",
            topMessage: "Power meter connected — waiting for data",
            pipelines: [PipelineReport(id: "ble.1", title: "Heart-rate sensor → iPhone (Bluetooth)", stages: [StageStatus(stage: .connected, result: .ok, detail: "connected")], health: .live, message: "Heart-rate sensor live")],
            board: DiagnosticReport.Board(firmware: "0.7.2", protocolVersion: "v1.2", caps: "0x3ff", stage: "Ready", linkUsable: true, connectedForS: 40, liveAgeS: 0.4,
                                          maxNotifyBytes: 244, characteristics: ["Info", "Live", "Events"], notifying: ["Live": true], notifyErrors: [:],
                                          counters: ["liveMessages": 40], parseErrors: [], lastFailure: nil, liveResubscribes: 0, latestSensorDiag: []),
            watch: DiagnosticReport.Watch(enabled: true, paired: true, appInstalled: true, reachable: false, mirrorActive: true, mirrorRemoteState: "running",
                                          mirrorSessions: 1, mirrorPayloads: 30, mirrorBadPayloads: 0, lastMirrorDisconnect: nil, workoutState: "running",
                                          workoutAuthOnWatch: "allowed", hrAcceptedMirror: 30, hrAcceptedConnectivity: 2, hrDuplicates: 12, hrDropped: 0,
                                          lastDeliveryAgeS: 0.8, hrSentToBoard: 32),
            directSensors: [DiagnosticReport.Direct(index: 1, kind: "heartRate", link: "connected", subscribed: true, services: ["180D"], characteristics: ["2A37"], packets: 99, rejected: 0, lastPacketAgeS: 0.5, lastValidAgeS: 0.5)],
            recentEvents: events, sensorDiagHistory: [], boardStageLog: ["2026-10-26T10:00:00Z Found RiderA board (1A2B3C4D)"])
        let json = String(data: report.json(personal: ["RiderA", "RiderA’s HRM"]), encoding: .utf8)!
        XCTAssertFalse(json.localizedCaseInsensitiveContains("ridera"), json)
        XCTAssertFalse(json.contains("@"), "no e-mail address")
        XCTAssertFalse(json.lowercased().contains("aa:bb:cc:dd:ee:ff"), "no hardware address")
        XCTAssertTrue(json.contains("cyclift-diagnostics/1"))
        XCTAssertTrue(json.contains("Heart-rate sensor → iPhone"))
        XCTAssertTrue(json.contains("\"packets\" : 99"))
        // the export carries no location or health history fields at all
        for k in ["latitude", "longitude", "\"name\"", "email", "birth", "weight"] { XCTAssertFalse(json.lowercased().contains(k), k) }
    }

    func testMonitorReportScrubsTheStoredRiderName() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Store(directory: dir, generatePlan: false)
        store.profile.name = "RiderA"
        let m = PipelineMonitor(autoTick: false)
        m.store = store
        m.log("sensor", "RiderA’s strap paired")
        let json = String(data: m.reportJSON(), encoding: .utf8)!
        XCTAssertFalse(json.contains("RiderA"), json)
        XCTAssertTrue(json.contains("cyclift-diagnostics/1"))
        UserDefaults.standard.removeObject(forKey: PipelineMonitor.eventsKey)
    }

    func testEventRingKeepsTheLastFifty() {
        var a: [Int] = []
        for i in 0..<75 { Ring.append(i, to: &a) }
        XCTAssertEqual(a.count, 50); XCTAssertEqual(a.first, 25); XCTAssertEqual(a.last, 74)
    }
}
