import XCTest
@testable import BikeComputer

/// Byte-for-byte vectors produced by the BikeComputer firmware 0.7.3 encoder (firmware/waveshare/docs/BLE_LINK_PROTOCOL.md,
/// Link 1.2.3 diagnostic transfer). The app must decode exactly what the board sends and encode exactly what it parses.
final class DiagFirmwareVectorTests: XCTestCase {
    private func bytes(_ hex: String) -> Data { Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! }) }

    func testPhoneRequestsMatchFirmwareParser() {
        XCTAssertEqual(BCLink.encodeDiagListRequest(seq: 1, tMs: 0x01020304), bytes("80 00 01 00 04 03 02 01"))
        XCTAssertEqual(BCLink.encodeDiagChunkRequest(reportId: 7, offset: 0, maxLen: 160, seq: 4, tMs: 0x20),
                       bytes("83 00 04 00 20 00 00 00 01 04 07 00 00 00 02 04 00 00 00 00 03 02 A0 00"))
        XCTAssertEqual(BCLink.encodeDiagAck(reportId: 7, crc32: 0xCBF43926, seq: 6, tMs: 0x30),
                       bytes("85 00 06 00 30 00 00 00 01 04 07 00 00 00 02 04 26 39 F4 CB"))
    }

    func testFirmwareInfo() throws {
        let i = try XCTUnwrap(BCLink.decodeDiagInfo(bytes("81 00 02 00 10 00 00 00 01 04 07 00 00 00 02 04 E1 10 00 00 03 04 26 39 F4 CB 04 04 40 0D FE 68 05 01 01 06 01 00 07 14 70 61 6E 69 63 20 69 6E 20 6E 69 6D 62 6C 65 5F 68 6F 73 74 08 05 30 2E 37 2E 33")))
        XCTAssertEqual(i.reportId, 7); XCTAssertEqual(i.size, 4321); XCTAssertEqual(i.crc32, 0xCBF43926)
        XCTAssertEqual(i.createdEpochS, 1761480000); XCTAssertEqual(i.kind, .crash); XCTAssertTrue(i.pending)
        XCTAssertEqual(i.summary, "panic in nimble_host"); XCTAssertEqual(i.firmware, "0.7.3")
    }

    func testFirmwareListEndChunkErrReady() throws {
        let e = try XCTUnwrap(BCLink.decodeDiagListEnd(bytes("82 00 03 00 10 00 00 00 01 01 01 02 01 01")))
        XCTAssertEqual(e.count, 1); XCTAssertEqual(e.pending, 1)
        let c = try XCTUnwrap(BCLink.decodeDiagChunk(bytes("84 00 05 00 21 00 00 00 01 04 07 00 00 00 02 04 00 00 00 00 03 09 5B 68 65 61 64 65 72 5D 0A 04 01 00")))
        XCTAssertEqual(c.reportId, 7); XCTAssertEqual(c.offset, 0); XCTAssertEqual(c.data, Data("[header]\n".utf8)); XCTAssertFalse(c.last)
        let r = try XCTUnwrap(BCLink.decodeDiagErr(bytes("86 00 07 00 31 00 00 00 01 04 09 00 00 00 02 01 01")))
        XCTAssertEqual(r.reportId, 9); XCTAssertEqual(r.code, 1)
        let d = try XCTUnwrap(BCLink.decodeDiagReady(bytes("40 00 08 00 40 00 00 00 01 01 22 02 01 01 03 04 07 00 00 00")))
        XCTAssertEqual(d.pending, 1); XCTAssertEqual(d.newestReportId, 7)
    }
}
