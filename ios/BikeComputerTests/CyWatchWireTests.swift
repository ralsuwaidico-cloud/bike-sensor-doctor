import XCTest
@testable import BikeComputer

/// Protocol v1 codecs must match the firmware byte for byte. Every expected vector below was produced by the firmware's
/// own encoder (watch/firmware/src/domain/payloads.hpp compiled on the host, 8 Nov 2026) — not by hand.
final class CyWatchWireTests: XCTestCase {
    private func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
    private func bytes(_ s: String) -> [UInt8] { stride(from: 0, to: s.count, by: 2).map { i in UInt8(s[s.index(s.startIndex, offsetBy: i)..<s.index(s.startIndex, offsetBy: i + 2)], radix: 16)! } }

    func testLiveMatchesFirmwareIncludingAbsentCadence() {
        var l = CyWatchWire.Live()
        l.powerW = 214; l.powerAgeMs = 120; l.hrBpm = 151; l.hrAgeMs = 900; l.cadenceRpm = nil; l.speedKmh10 = 325; l.speedAgeMs = 1000
        l.ftpKnown = true; l.ftpW = 250; l.powerBandW = (200, 230); l.stepName = "Tempo 2"; l.stepRemainingS = 480; l.stepTotalS = 600
        l.recording = true; l.paused = false; l.elapsedS = 1834; l.distanceM = 15230
        XCTAssertEqual(hex(l.encode()), "d600780097008403ffffffff4501e80301fa00c800e600ffffffffffffffff0754656d706f2032e0015802012a0700007e3b0000")
        let f = CyWatchWire.encode(.init(type: .live, seq: 5, payload: l.encode()))
        XCTAssertEqual(hex(f), "012005003400d600780097008403ffffffff4501e80301fa00c800e600ffffffffffffffff0754656d706f2032e0015802012a0700007e3b0000b14b", "framing + CRC-16/CCITT")
        XCTAssertEqual(CyWatchWire.decode(f)?.payload, l.encode())
        var bad = f; bad[10] ^= 0x01
        XCTAssertNil(CyWatchWire.decode(bad), "a corrupted frame is dropped by its CRC")
    }
    func testGpsTimeCoachPlanCachedMatchFirmware() {
        XCTAssertEqual(hex(CyWatchWire.Gps(latE7: 253_000_000, lonE7: 553_000_000, speedKmh10: 325, headingDeg: 270, phoneUnixS: 1_794_130_860, ageMs: 200).encode()), "4079140f401cf62045010e01ac43f06ac800")
        XCTAssertEqual(hex(CyWatchWire.TimeSync(unixS: 1_794_130_860, ms: 345, tzOffsetMin: 240).encode()), "ac43f06a5901f000")
        XCTAssertEqual(hex(CyWatchWire.Coach(id: 42, priority: 2, context: 1, requiresAction: true, safety: false, expiresInS: 30, instruction: "Ease off", reason: "Power above band", target: "200–230 W").encode()),
                       "2a0000000201011e000845617365206f666610506f7765722061626f76652062616e640b323030e280933233302057")
        let p = CyWatchWire.PlanToday(kind: 2, workoutId: "W1", title: "Full body", startMin: 18 * 60, durationMin: 45,
                                      exercises: [.init(id: "goblet-squat", name: "Goblet squat", sets: 3, reps: 10, weightKg10: 240, restS: 90, superset: UInt8(ascii: "A"))])
        XCTAssertEqual(hex(p.encode()), "020257310946756c6c20626f647938042d00010c676f626c65742d73717561740c476f626c6574207371756174030af0005a0041")
        let c = CyWatchWire.Cached(sleepMin: 444, sleepSource: "Apple Watch", sleepUnixS: 1_794_120_000, hrvMs: 61, hrvUnixS: 1_794_120_000, recoveryPct: nil, recoveryWord: "Train as planned", insight: "Readings typical", loadPct: 70)
        XCTAssertEqual(hex(c.encode()), "bc010b4170706c652057617463684019f06a3d004019f06aff10547261696e20617320706c616e6e65641052656164696e6773207479706963616c46")
        XCTAssertEqual(hex(CyWatchWire.encodeAck(7)), "07000000")
    }
    func testEventAndStatusDecodeFromFirmwareBytes() {
        let e = try! XCTUnwrap(CyWatchWire.Event.decode(bytes("086379772d6162313207000000d443f06a06025731010000000a000000f000000001")))
        XCTAssertEqual(e.deviceId, "cyw-ab12"); XCTAssertEqual(e.seq, 7); XCTAssertEqual(e.watchUnixS, 1_794_130_900); XCTAssertEqual(e.kind, .setLogged)
        XCTAssertEqual(e.workoutId, "W1"); XCTAssertEqual(e.a, 1); XCTAssertEqual(e.b, 10); XCTAssertEqual(e.c, 240); XCTAssertTrue(e.manual)
        let s = try! XCTUnwrap(CyWatchWire.Status.decode(bytes("530040e201000203000000")))
        XCTAssertEqual(s.batteryPct, 83); XCTAssertFalse(s.charging); XCTAssertEqual(s.freeHeap, 123_456); XCTAssertEqual(s.phase, 2); XCTAssertEqual(s.pendingEvents, 3)
        XCTAssertNil(CyWatchWire.Event.decode(bytes("0863")), "a truncated payload is rejected, not zero-filled")
    }
    func testGpsFromDoublesRoundsAndClamps() {
        let g = CyWatchWire.Gps(lat: 25.3, lon: 55.3, speedKmh: 32.54, headingDeg: 270.4, at: Date(timeIntervalSince1970: 1_794_130_860.6), ageMs: 200)
        XCTAssertEqual(g.latE7, 253_000_000); XCTAssertEqual(g.lonE7, 553_000_000); XCTAssertEqual(g.speedKmh10, 325); XCTAssertEqual(g.headingDeg, 270); XCTAssertEqual(g.phoneUnixS, 1_794_130_860)
        XCTAssertEqual(CyWatchWire.Gps(lat: 0, lon: 0, speedKmh: -3, headingDeg: 720, at: Date(timeIntervalSince1970: 0), ageMs: 99_999).speedKmh10, 0)
    }
}
