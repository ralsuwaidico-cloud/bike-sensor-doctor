import XCTest
@testable import BikeComputer

/// Conformance vectors mirroring test/host/test_bc_core.c (t_link) in the firmware: both sides must agree byte for byte.
final class BCLinkTests: XCTestCase {
    func testLiveDecodeFromFirmwareBytes() {
        // Encoded by the C encoder: power 231 W age 400, cadence 88 age 500, no HR, running ride 12, 3600 s, 25000 m,
        // cue 3, battery 77, meter link 4, gaps 2, no demo. seq 7, t 123456.
        var b: [UInt8] = [0x10, 0, 7, 0, 0x40, 0xE2, 0x01, 0x00]
        b += [0x01, 2, 0xE7, 0x00, 0x02, 2, 0x90, 0x01, 0x03, 1, 88, 0x04, 2, 0xF4, 0x01]
        b += [0x08, 1, 1, 0x09, 2, 12, 0, 0x0A, 4, 0x10, 0x0E, 0, 0, 0x0B, 4, 0xA8, 0x61, 0, 0]
        b += [0x0C, 1, 3, 0x0D, 1, 77, 0x0E, 1, 4, 0x0F, 2, 2, 0]
        let l = BCLink.decodeLive(Data(b))
        XCTAssertNotNil(l)
        XCTAssertEqual(l?.powerW, 231); XCTAssertEqual(l?.powerAgeMs, 400)
        XCTAssertEqual(l?.cadenceRpm, 88); XCTAssertNil(l?.hrBpm)
        XCTAssertEqual(l?.rideState, .running); XCTAssertEqual(l?.rideId, 12)
        XCTAssertEqual(l?.elapsedS, 3600); XCTAssertEqual(l?.distanceM, 25000)
        XCTAssertEqual(l?.batteryPct, 77); XCTAssertEqual(l?.meterGaps, 2); XCTAssertEqual(l?.demo, false)
        XCTAssertEqual(l?.seq, 7); XCTAssertEqual(l?.boardTimeMs, 123456)
        // truncated → rejected whole
        XCTAssertNil(BCLink.decodeLive(Data(b.dropLast())))
        XCTAssertNil(BCLink.decodeLive(Data(b.prefix(5))))
        // demo flag
        let d = BCLink.decodeLive(Data(b + [0x10, 1, 1]))
        XCTAssertEqual(d?.demo, true)
        // unknown tag skipped, wrong length ignored
        let m: [UInt8] = [0x10, 0, 1, 0, 0, 0, 0, 0, 0x7E, 3, 1, 2, 3, 0x01, 1, 9, 0x08, 1, 2]
        let u = BCLink.decodeLive(Data(m))
        XCTAssertNil(u?.powerW); XCTAssertEqual(u?.rideState, .paused)
        // wrong type
        XCTAssertNil(BCLink.decodeLive(Data([0x21] + m.dropFirst())))
    }

    func testGPSEncodingMatchesFirmwareLayout() {
        let g = BCLink.GPSFix(latE7: 244667000, lonE7: 544000000, altDm: 120, haccDm: 50, vaccDm: 80, speedCms: 833, courseCdeg: 9000,
                              fixEpochMs: 1761300000000, source: .phoneGPS)
        let d = BCLink.encodeGPS(g, seq: 2, tMs: 0)!
        let b = [UInt8](d)
        XCTAssertEqual(b[0], 0x21); XCTAssertEqual(b[2], 2)
        XCTAssertEqual(Array(b[8..<14]), [0x01, 4, 0x78, 0x3A, 0x95, 0x0E])          // 244667000 LE
        XCTAssertEqual(Array(b[14..<20]), [0x02, 4, 0x00, 0x95, 0x6C, 0x20])         // 544000000 LE
        XCTAssertTrue(d.count <= BCLink.maxMessage)
        // the source byte is last
        XCTAssertEqual(Array(b.suffix(3)), [0x09, 1, 3])
    }

    func testTimeAndHREncoding() {
        let t = [UInt8](BCLink.encodeTime(epochMs: 1761300000000, uncertaintyMs: 50, tzMinutes: 240, seq: 1, tMs: 0)!)
        XCTAssertEqual(t[0], 0x20)
        XCTAssertEqual(Array(t[8..<18]), [0x01, 8, 0x00, 0x0C, 0x16, 0x1A, 0x9A, 0x01, 0x00, 0x00])   // 1761300000000 LE
        XCTAssertEqual(Array(t[18..<22]), [0x02, 2, 50, 0])
        XCTAssertEqual(Array(t[22..<26]), [0x03, 2, 0xF0, 0x00])
        let h = [UInt8](BCLink.encodeHR(bpm: 152, source: .appleWatch, sampleEpochMs: 1761300000000, quality: 2, seq: 3, tMs: 0)!)
        XCTAssertEqual(h[0], 0x22); XCTAssertEqual(Array(h[8..<14]), [0x01, 1, 152, 0x02, 1, 4])
    }

    func testControlRoundTrip() {
        let req = [UInt8](BCLink.encodeControl(reqId: 9, cmd: .stopRequest, rideId: 12, seq: 5, tMs: 0)!)
        XCTAssertEqual(Array(req[8...]), [0x01, 2, 9, 0, 0x02, 1, 4, 0x03, 2, 12, 0])
        // response bytes as the C encoder produces them
        let resp: [UInt8] = [0x31, 0, 6, 0, 0, 0, 0, 0, 0x01, 2, 9, 0, 0x02, 1, 2, 0x03, 1, 1, 0x04, 2, 12, 0]
        let r = BCLink.decodeControlResponse(Data(resp))
        XCTAssertEqual(r?.reqId, 9); XCTAssertEqual(r?.status, .needsConfirm); XCTAssertEqual(r?.rideState, .running); XCTAssertEqual(r?.rideId, 12)
    }

    func testInfo() {
        var w = BCLink.Writer(type: .info, seq: 0, tMs: 0)
        w.u8(0x01, 1); w.u8(0x02, 0); w.str(0x03, "0.4.0"); w.str(0x04, "BikeComputer"); w.u32(0x05, 0x3F); w.u16(0x06, 180)
        let i = BCLink.decodeInfo(w.result!)
        XCTAssertEqual(i?.fw, "0.4.0"); XCTAssertEqual(i?.name, "BikeComputer"); XCTAssertEqual(i?.caps, 0x3F); XCTAssertEqual(i?.maxMsg, 180)
        XCTAssertNil(BCLink.decodeInfo(Data([0x01, 0, 0, 0, 0, 0, 0, 0])))   // no version → invalid
    }

    func testSignedHelper() {
        XCTAssertEqual(BCLink.sint(Data([0xFF, 0xFF])), -1)
        XCTAssertEqual(BCLink.sint(Data([0x00, 0x80, 0xFF, 0xFF])), -32768)
        XCTAssertEqual(BCLink.uint(Data([0x10, 0x0E, 0, 0])), 3600)
    }
}
