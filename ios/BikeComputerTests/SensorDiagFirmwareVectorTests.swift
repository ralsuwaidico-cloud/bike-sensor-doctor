import XCTest
@testable import BikeComputer

/// Byte-for-byte vectors produced by the BikeComputer firmware 0.7.2 encoder (firmware/waveshare/docs/BLE_LINK_PROTOCOL.md,
/// SENSOR_DIAG V1/V2/V4/V5). The app must decode exactly what the board sends — not only its own hand-built vectors.
final class SensorDiagFirmwareVectorTests: XCTestCase {
    private func bytes(_ hex: String) -> Data { Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! }) }

    func testV1PowerValid() throws {
        let d = try XCTUnwrap(BCLink.decodeSensorDiag(bytes("40 00 05 00 A0 86 01 00 01 01 21 02 01 01 03 01 06 04 04 8E 00 00 00 05 02 00 00 06 02 04 00 07 02 04 00")))
        XCTAssertEqual(d.sensorRaw, 1); XCTAssertEqual(d.stageRaw, 6); XCTAssertEqual(d.packets, 142); XCTAssertEqual(d.rejected, 0)
        XCTAssertEqual(d.packetAgeDs, 4); XCTAssertEqual(d.validAgeDs, 4); XCTAssertNil(d.lastError)
        XCTAssertEqual(d.seq, 5); XCTAssertEqual(d.boardTimeMs, 100_000)
    }

    func testV2PowerSubscribedNoData() throws {
        let d = try XCTUnwrap(BCLink.decodeSensorDiag(bytes("40 00 06 00 A0 86 01 00 01 01 21 02 01 01 03 01 04 04 04 00 00 00 00 05 02 00 00 06 02 FF FF 07 02 FF FF")))
        XCTAssertEqual(d.stageRaw, 4); XCTAssertEqual(d.packets, 0); XCTAssertNil(d.packetAgeDs); XCTAssertNil(d.validAgeDs)
    }

    func testV4HeartRateUnreadable() throws {
        let d = try XCTUnwrap(BCLink.decodeSensorDiag(bytes("40 00 08 00 A0 86 01 00 01 01 21 02 01 02 03 01 05 04 04 0C 00 00 00 05 02 0C 00 06 02 08 00 07 02 FF FF 08 0F 75 6E 72 65 61 64 61 62 6C 65 20 64 61 74 61")))
        XCTAssertEqual(d.sensorRaw, 2); XCTAssertEqual(d.stageRaw, 5); XCTAssertEqual(d.packets, 12); XCTAssertEqual(d.rejected, 12)
        XCTAssertEqual(d.packetAgeDs, 8); XCTAssertNil(d.validAgeDs); XCTAssertEqual(d.lastError, "unreadable data")
    }

    func testV5CadenceStale() throws {
        let d = try XCTUnwrap(BCLink.decodeSensorDiag(bytes("40 00 09 00 A0 86 01 00 01 01 21 02 01 03 03 01 07 04 04 2C 01 00 00 05 02 02 00 06 02 34 00 07 02 34 00")))
        XCTAssertEqual(d.sensorRaw, 3); XCTAssertEqual(d.stageRaw, 7); XCTAssertEqual(d.packets, 300); XCTAssertEqual(d.rejected, 2)
        XCTAssertEqual(d.packetAgeDs, 52); XCTAssertEqual(d.validAgeDs, 52)
    }
}
