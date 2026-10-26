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

// MARK: - the firmware-generated fixture (firmware/waveshare/test/host/gen_diag_fixture.c)

/// Everything in it was produced by the firmware 0.7.3 code on a PC: the crash report by the real report builder, every board
/// reply by the real Link 1.2.3 server at ATT MTU 23 / 100 / 185 / 247 / 517, the phone requests by the firmware codec.
struct FirmwareDiagFixture {
    struct Pair { var request: Data; var reply: Data }
    struct Chunk { var offset: UInt32; var len: Int; var last: Bool; var request: Data; var reply: Data }
    struct Transfer { var attMtu: Int; var phoneMaxLen: Int; var dataMax: Int; var chunks: [Chunk]; var noncompliant: Pair? }
    struct PhoneVector { var type: String; var seq: UInt16; var bytes: Data; var id: UInt32; var offset: UInt32; var maxLen: UInt16; var crc: UInt32 }
    var chunkOverhead = 0, linkMax = 0
    var reportId: UInt32 = 0, size: UInt32 = 0, crc: UInt32 = 0, kind: UInt8 = 0, created: UInt32 = 0
    var summary = "", firmware = ""
    var text = Data()
    var info073 = Data(), info072 = Data(), diagReady = Data()
    var listRequest = Data(); var listReplies: [Data] = []
    var phoneVectors: [PhoneVector] = []
    var transfers: [Transfer] = []
    var cases: [String: Pair] = [:]

    static func load() throws -> FirmwareDiagFixture {
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(DiagFirmwareFixture.json.utf8)) as? [String: Any])
        func b64(_ v: Any?) throws -> Data { try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(v as? String))) }
        func num(_ v: Any?) throws -> Int { try XCTUnwrap((v as? NSNumber)?.intValue) }
        func pair(_ v: Any?) throws -> Pair { let d = try XCTUnwrap(v as? [String: Any]); return Pair(request: try b64(d["request"]), reply: try b64(d["reply"])) }
        var f = FirmwareDiagFixture()
        f.chunkOverhead = try num(root["chunk_overhead"]); f.linkMax = try num(root["link_max"])
        let r = try XCTUnwrap(root["report"] as? [String: Any])
        f.reportId = UInt32(try num(r["id"])); f.size = UInt32(try num(r["size"])); f.crc = UInt32(truncatingIfNeeded: try num(r["crc32"]))
        f.kind = UInt8(try num(r["kind"])); f.created = UInt32(try num(r["created"]))
        f.summary = try XCTUnwrap(r["summary"] as? String); f.firmware = try XCTUnwrap(r["firmware"] as? String); f.text = try b64(r["text"])
        f.info073 = try b64(root["info_073"]); f.info072 = try b64(root["info_072"]); f.diagReady = try b64(root["diag_ready"])
        let l = try XCTUnwrap(root["list"] as? [String: Any])
        f.listRequest = try b64(l["request"]); f.listReplies = try XCTUnwrap(l["replies"] as? [Any]).map { try b64($0) }
        for v in try XCTUnwrap(root["phone_vectors"] as? [[String: Any]]) {
            f.phoneVectors.append(PhoneVector(type: try XCTUnwrap(v["type"] as? String), seq: UInt16(try num(v["seq"])), bytes: try b64(v["bytes"]),
                                              id: UInt32((v["id"] as? NSNumber)?.intValue ?? 0), offset: UInt32((v["offset"] as? NSNumber)?.intValue ?? 0),
                                              maxLen: UInt16((v["max_len"] as? NSNumber)?.intValue ?? 0),
                                              crc: UInt32(truncatingIfNeeded: (v["crc32"] as? NSNumber)?.int64Value ?? 0)))
        }
        for t in try XCTUnwrap(root["transfers"] as? [[String: Any]]) {
            var x = Transfer(attMtu: try num(t["att_mtu"]), phoneMaxLen: try num(t["phone_max_len"]), dataMax: try num(t["data_max"]), chunks: [], noncompliant: nil)
            if let n = t["noncompliant"] { x.noncompliant = try pair(n) }
            for c in (t["chunks"] as? [[String: Any]]) ?? [] {
                x.chunks.append(Chunk(offset: UInt32(try num(c["offset"])), len: try num(c["len"]), last: (c["last"] as? Bool) ?? false,
                                      request: try b64(c["request"]), reply: try b64(c["reply"])))
            }
            f.transfers.append(x)
        }
        for (k, v) in try XCTUnwrap(root["cases"] as? [String: Any]) { f.cases[k] = try pair(v) }
        return f
    }
}

final class DiagFirmwareFixtureTests: XCTestCase {
    var fx: FirmwareDiagFixture!
    override func setUpWithError() throws { fx = try FirmwareDiagFixture.load() }

    /// The JSON committed in Fixtures/ (bundled by xcodegen as a test resource) and the Swift copy are the same bytes.
    func testFixtureCopiesAgree() throws {
        let url = try XCTUnwrap(Bundle(for: DiagFirmwareFixtureTests.self).url(forResource: "diag_fw_fixture", withExtension: "json"),
                                "Fixtures/diag_fw_fixture.json is in the test bundle")
        let file = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertEqual(file.trimmingCharacters(in: .whitespacesAndNewlines), DiagFirmwareFixture.json.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: size contract
    func testChunkOverheadIsExactAndMatchesTheFirmware() {
        XCTAssertEqual(BCLink.diagChunkOverhead, 25)
        XCTAssertEqual(BCLink.diagChunkOverhead, fx.chunkOverhead)
        XCTAssertEqual(BCLink.maxMessage, fx.linkMax)
        XCTAssertEqual(BCLink.diagChunkDataMax, 155)
        for n in 0...BCLink.diagChunkDataMax {
            let d = BCLink.encodeDiagChunk(BCLink.DiagChunk(reportId: .max, offset: .max, data: Data(repeating: 0x41, count: n), last: true), seq: 1, tMs: 0)
            XCTAssertEqual(d.count, n + BCLink.diagChunkOverhead)
        }
        XCTAssertEqual(BCLink.diagRequestMaxLen(linkPayload: 20), nil)        /* MTU 23 */
        XCTAssertEqual(BCLink.diagRequestMaxLen(linkPayload: 25), nil)        /* MTU 28 */
        XCTAssertEqual(BCLink.diagRequestMaxLen(linkPayload: 26), 1)          /* MTU 29 */
        XCTAssertEqual(BCLink.diagRequestMaxLen(linkPayload: 97), 72)         /* MTU 100 */
        XCTAssertEqual(BCLink.diagRequestMaxLen(linkPayload: 182), 155)       /* MTU 185 (iOS) */
        XCTAssertEqual(BCLink.diagRequestMaxLen(linkPayload: 244), 155)       /* MTU 247 */
        XCTAssertEqual(BCLink.diagRequestMaxLen(linkPayload: 514), 155)       /* MTU 517 */
    }

    // MARK: metadata
    func testListAndMetadataFromTheFirmware() throws {
        XCTAssertEqual(BCLink.encodeDiagListRequest(seq: 1, tMs: 0), fx.listRequest)
        XCTAssertEqual(fx.listReplies.count, 3)
        let i = try XCTUnwrap(BCLink.decodeDiagInfo(fx.listReplies[0]))
        XCTAssertEqual(i.reportId, fx.reportId); XCTAssertEqual(i.size, fx.size); XCTAssertEqual(i.crc32, fx.crc)
        XCTAssertEqual(i.kind, .crash); XCTAssertTrue(i.pending); XCTAssertEqual(i.createdEpochS, fx.created)
        XCTAssertEqual(i.summary, fx.summary); XCTAssertEqual(i.firmware, "0.7.3")
        XCTAssertEqual(Int(i.size), fx.text.count); XCTAssertEqual(CRC32.ieee(fx.text), fx.crc, "crc32 over the firmware's own report")
        let sent = try XCTUnwrap(BCLink.decodeDiagInfo(fx.listReplies[1]))
        XCTAssertEqual(sent.reportId, 8); XCTAssertEqual(sent.state, 1); XCTAssertEqual(sent.kind, .manual); XCTAssertFalse(sent.pending)
        let end = try XCTUnwrap(BCLink.decodeDiagListEnd(fx.listReplies[2]))
        XCTAssertEqual(end.count, 2); XCTAssertEqual(end.pending, 1)
        let r = try XCTUnwrap(BCLink.decodeDiagReady(fx.diagReady))
        XCTAssertEqual(r.pending, 1); XCTAssertEqual(r.newestReportId, 8)
        let text = String(decoding: fx.text, as: UTF8.self)
        for s in ["[header]", "[reset]", "[panic]", "[backtrace]", "[tasks]", "[heap]", "[events]", "[sensors]", "[phone]", "[wifi]", "[recovery]"] {
            XCTAssertTrue(text.contains(s), s)
        }
        XCTAssertFalse(text.contains("C1:22"), "Bluetooth addresses cut to 2 bytes by the board")
    }

    // MARK: phone → firmware
    func testCycliftEncoderProducesTheBytesTheFirmwareParses() {
        XCTAssertEqual(fx.phoneVectors.count, 5)
        for v in fx.phoneVectors {
            switch v.type {
            case "list": XCTAssertEqual(BCLink.encodeDiagListRequest(seq: v.seq, tMs: 0), v.bytes)
            case "chunk": XCTAssertEqual(BCLink.encodeDiagChunkRequest(reportId: v.id, offset: v.offset, maxLen: v.maxLen, seq: v.seq, tMs: 0), v.bytes, "chunk req max_len \(v.maxLen)")
            case "ack": XCTAssertEqual(BCLink.encodeDiagAck(reportId: v.id, crc32: v.crc, seq: v.seq, tMs: 0), v.bytes)
            default: XCTFail("unknown vector \(v.type)")
            }
        }
    }

    // MARK: every MTU: offsets, lengths, notification size, CRC over the full multi-chunk report
    func testFirmwareChunksAtEveryMTUReassembleToTheReport() throws {
        XCTAssertEqual(fx.transfers.map(\.attMtu), [23, 100, 185, 247, 517])
        for t in fx.transfers {
            let ours = BCLink.diagRequestMaxLen(linkPayload: t.attMtu - BCLink.attNotifyOverhead)
            XCTAssertEqual(Int(ours ?? 0), t.phoneMaxLen, "MTU \(t.attMtu): Cyclift asks for what the firmware expects")
            if let n = t.noncompliant {
                XCTAssertNil(ours)
                let e = try XCTUnwrap(BCLink.decodeDiagErr(n.reply))
                XCTAssertEqual(e.known, .linkTooSmall, "MTU 23: the board answers DIAG_ERR 5")
                continue
            }
            var data = Data(); var expect: UInt32 = 0
            for (k, c) in t.chunks.enumerated() {
                XCTAssertEqual(BCLink.encodeDiagChunkRequest(reportId: fx.reportId, offset: c.offset, maxLen: UInt16(t.phoneMaxLen), seq: UInt16(k + 1), tMs: 0), c.request)
                XCTAssertLessThanOrEqual(c.reply.count + BCLink.attNotifyOverhead, t.attMtu, "fits one notification at MTU \(t.attMtu)")
                XCTAssertLessThanOrEqual(c.reply.count, BCLink.maxMessage)
                let ch = try XCTUnwrap(BCLink.decodeDiagChunk(c.reply))
                XCTAssertEqual(ch.reportId, fx.reportId); XCTAssertEqual(ch.offset, expect); XCTAssertEqual(ch.data.count, c.len)
                XCTAssertEqual(c.reply.count, ch.data.count + BCLink.diagChunkOverhead)
                if !ch.last { XCTAssertEqual(ch.data.count, t.dataMax) }
                XCTAssertEqual(ch.last, k == t.chunks.count - 1)
                data.append(ch.data); expect += UInt32(ch.data.count)
            }
            XCTAssertEqual(data, fx.text, "MTU \(t.attMtu): \(t.chunks.count) chunks reassemble the report")
            XCTAssertEqual(CRC32.ieee(data), fx.crc)
            XCTAssertEqual(t.chunks.count, (Int(fx.size) + t.dataMax - 1) / t.dataMax)
        }
    }

    // MARK: ACK, duplicates, errors as the firmware sends them
    func testAckRepliesAndErrorCodesFromTheFirmware() throws {
        let ok = try XCTUnwrap(fx.cases["ack_ok"]), bad = try XCTUnwrap(fx.cases["ack_bad_crc"])
        XCTAssertEqual(BCLink.encodeDiagAck(reportId: fx.reportId, crc32: fx.crc, seq: 41, tMs: 0), ok.request)
        XCTAssertEqual(try XCTUnwrap(BCLink.decodeDiagInfo(ok.reply)).state, 1, "matching crc: the board marks it sent")
        XCTAssertEqual(try XCTUnwrap(BCLink.decodeDiagInfo(bad.reply)).state, 0, "wrong crc: the board keeps it pending")
        let first = try XCTUnwrap(BCLink.decodeDiagChunk(try XCTUnwrap(fx.cases["duplicate_first"]).reply))
        let second = try XCTUnwrap(BCLink.decodeDiagChunk(try XCTUnwrap(fx.cases["duplicate_second"]).reply))
        XCTAssertEqual(first.offset, 310); XCTAssertEqual(first.data, second.data); XCTAssertEqual(first.offset, second.offset)
        let end = try XCTUnwrap(BCLink.decodeDiagChunk(try XCTUnwrap(fx.cases["offset_at_end"]).reply))
        XCTAssertTrue(end.data.isEmpty); XCTAssertTrue(end.last)
        let codes: [(String, BCLink.DiagErr.Code)] = [("err_unknown_id", .unknownId), ("err_bad_offset", .badOffset), ("err_storage", .storageReadError),
                                                      ("err_busy_pipeline", .busy), ("err_busy_ride", .busy), ("err_mtu", .linkTooSmall), ("ack_unknown_id", .unknownId)]
        for (name, code) in codes {
            let e = try XCTUnwrap(BCLink.decodeDiagErr(try XCTUnwrap(fx.cases[name]).reply), name)
            XCTAssertEqual(e.known, code, name)
        }
    }

    // MARK: capability 0x400 / version compatibility
    func testCapabilityNegotiationAndOlderSides() throws {
        let new = try XCTUnwrap(BCLink.decodeInfo(fx.info073)), old = try XCTUnwrap(BCLink.decodeInfo(fx.info072))
        XCTAssertEqual(new.fw, "0.7.3"); XCTAssertTrue(new.hasDiagXfer); XCTAssertTrue(DiagReportCenter.transferAllowed(new))
        XCTAssertEqual(old.fw, "0.7.2"); XCTAssertFalse(old.hasDiagXfer)
        XCTAssertFalse(DiagReportCenter.transferAllowed(old), "firmware without cap 0x400: no DIAG byte is ever sent")
        XCTAssertFalse(DiagReportCenter.transferAllowed(nil))
        // an app older than 1.2.3 decodes events with the LINK_DIAG / SENSOR_DIAG decoders only: diag_ready is ignored by them,
        // so the board (cap 0x400) simply keeps its reports (firmware test_old_app_keeps_reports)
        let ev = try XCTUnwrap(BCLink.decodeEvent(fx.diagReady))
        XCTAssertNil(BCLink.linkDiag(from: ev)); XCTAssertNil(BCLink.decodeSensorDiag(fx.diagReady))
    }
}

// MARK: - the transfer engine against the firmware's own replies

/// Replays the firmware's replies (from the fixture) for whatever the engine asks, after checking that the request is the
/// one the firmware expects at this MTU.
final class FirmwareReplayBoard {
    let fx: FirmwareDiagFixture; let t: FirmwareDiagFixture.Transfer
    var silentAfter: Int?; var served = 0; var duplicateAt: UInt32?; var acked: UInt32?
    var wrongMaxLen = 0
    init(_ fx: FirmwareDiagFixture, mtu: Int) { self.fx = fx; t = fx.transfers.first(where: { $0.attMtu == mtu })! }
    func respond(_ d: Data) -> [Data] {
        guard let (_, fields) = BCLink.parse(d), let type = d.first else { return [] }
        var f: [UInt8: Data] = [:]; for x in fields { f[x.tag] = x.value }
        switch type {
        case 0x80: return fx.listReplies
        case 0x83:
            let off = UInt32(BCLink.uint(f[0x02]!)), maxLen = Int(BCLink.uint(f[0x03]!))
            if maxLen != t.phoneMaxLen { wrongMaxLen += 1 }
            if let s = silentAfter, served >= s { return [] }
            guard let c = t.chunks.first(where: { $0.offset == off }) else { return [fx.cases["err_bad_offset"]!.reply] }
            served += 1
            return off == duplicateAt ? [c.reply, c.reply] : [c.reply]
        case 0x85:
            let crc = UInt32(BCLink.uint(f[0x02]!))
            acked = crc
            return [crc == fx.crc ? fx.cases["ack_ok"]!.reply : fx.cases["ack_bad_crc"]!.reply]
        default: return []
        }
    }
}

final class DiagFirmwareEngineTests: XCTestCase {
    var fx: FirmwareDiagFixture!
    var root: URL!
    var store: DiagStore!
    var outbox: [Data] = []
    var sent: [Data] = []
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var payload = 182
    var boardRide = false
    let boardId = "9a:3c:11:22:33:44"

    override func setUpWithError() throws {
        fx = try FirmwareDiagFixture.load()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("diagfw-\(UUID().uuidString)", isDirectory: true)
        store = DiagStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func engine() -> DiagTransfer {
        let e = DiagTransfer(boardId: boardId, store: store) { [unowned self] d in self.outbox.append(d); self.sent.append(d); return true }
        e.linkPayload = { [unowned self] in self.payload }
        e.boardRecording = { [unowned self] in self.boardRide }
        return e
    }
    func pump(_ e: DiagTransfer, _ b: FirmwareReplayBoard) { while !outbox.isEmpty { let m = outbox.removeFirst(); for r in b.respond(m) { e.receive(r, now: now) } } }
    var chunkRequests: Int { sent.filter { $0.first == 0x83 }.count }

    func testFullPullAtEachMTUVerifiesCrcAndAcknowledges() throws {
        for mtu in [100, 185, 247, 517] {
            try setUpWithError(); sent = []; outbox = []
            payload = mtu - 3
            let b = FirmwareReplayBoard(fx, mtu: mtu), e = engine()
            e.start(now: now); pump(e, b)
            XCTAssertEqual(b.wrongMaxLen, 0, "MTU \(mtu): every request has the firmware's max_len")
            XCTAssertEqual(chunkRequests, b.t.chunks.count)
            let m = try XCTUnwrap(store.meta(boardId, fx.reportId), "MTU \(mtu)")
            XCTAssertEqual(store.text(m), String(decoding: fx.text, as: UTF8.self))
            XCTAssertEqual(m.crc32, fx.crc)
            XCTAssertEqual(b.acked, fx.crc, "ACK carries the crc the phone computed, sent only after it matched")
            XCTAssertEqual(store.meta(boardId, fx.reportId)?.boardAcknowledged, true, "the firmware's DIAG_INFO state 1 is remembered")
            XCTAssertNil(store.meta(boardId, 8), "a report the board lists as already sent is not pulled")
            XCTAssertNil(e.lastError)
            tearDown()
        }
    }

    func testDisconnectHalfwayResumesAtTheOffsetWithTheFirmwaresChunks() throws {
        let b = FirmwareReplayBoard(fx, mtu: 185)
        b.silentAfter = 20                                    /* the phone's Bluetooth goes off after 20 chunks */
        var e = engine()
        e.start(now: now); pump(e, b)
        XCTAssertEqual(store.partialLength(boardId, fx.reportId), UInt32(20 * 155))
        e.linkDown()
        e = engine()                                          /* even an app restart: only the disk survives */
        b.silentAfter = nil
        let before = sent.count
        e.start(now: now); pump(e, b)
        let firstAfter = try XCTUnwrap(sent[before...].first(where: { $0.first == 0x83 }))
        let fields = try XCTUnwrap(BCLink.parse(firstAfter)).1
        let offField = try XCTUnwrap(fields.first(where: { $0.tag == 0x02 }))
        XCTAssertEqual(UInt32(BCLink.uint(offField.value)), UInt32(20 * 155), "resumes at the offset reached, not 0")
        XCTAssertEqual(store.meta(boardId, fx.reportId)?.crc32, fx.crc)
        XCTAssertEqual(b.acked, fx.crc)
    }

    func testDuplicateChunkFromTheFirmwareIsIgnored() throws {
        let b = FirmwareReplayBoard(fx, mtu: 185); b.duplicateAt = 310
        let e = engine(); e.start(now: now); pump(e, b)
        let m = try XCTUnwrap(store.meta(boardId, fx.reportId))
        XCTAssertEqual(store.text(m), String(decoding: fx.text, as: UTF8.self), "the second copy of the chunk at 310 is not appended")
        XCTAssertEqual(chunkRequests, b.t.chunks.count)
    }

    func testFirmwareBusyDuringARideBacksOffAndResumes() throws {
        let b = FirmwareReplayBoard(fx, mtu: 185); b.silentAfter = 3
        let e = engine(); e.start(now: now); pump(e, b)
        // the rider starts recording: the board answers the outstanding request BUSY (exact firmware bytes)
        let busy = try XCTUnwrap(fx.cases["err_busy_ride"]).reply
        e.receive(busy, now: now)
        let n = chunkRequests
        for _ in 0..<9 { now = now.addingTimeInterval(1); e.tick(now: now); pump(e, b) }
        XCTAssertEqual(chunkRequests, n, "nothing asked for 10 s after BUSY")
        boardRide = true                                      /* LIVE now says RECORDING: the phone does not ask at all */
        for _ in 0..<60 { now = now.addingTimeInterval(1); e.tick(now: now); pump(e, b) }
        XCTAssertEqual(chunkRequests, n, "no chunk request while the board records")
        boardRide = false; b.silentAfter = nil
        for _ in 0..<12 { now = now.addingTimeInterval(1); e.tick(now: now); pump(e, b) }
        XCTAssertEqual(store.meta(boardId, fx.reportId)?.crc32, fx.crc, "completed after the ride")
    }

    func testLinkTooSmallFromTheFirmwareStopsCleanly() throws {
        let b = FirmwareReplayBoard(fx, mtu: 185); b.silentAfter = 0
        let e = engine(); e.start(now: now); pump(e, b)
        e.receive(try XCTUnwrap(fx.cases["err_mtu"]).reply, now: now)
        XCTAssertEqual(e.phase, .idle); XCTAssertNotNil(e.lastError)
        let n = sent.count
        for _ in 0..<30 { now = now.addingTimeInterval(1); e.tick(now: now) }
        XCTAssertEqual(sent.count, n, "DIAG_ERR 5 is not retried")
    }
}
