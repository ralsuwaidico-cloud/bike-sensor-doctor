import XCTest
@testable import BikeComputer

// MARK: - codec (byte vectors built by hand from docs/LINK_V1_2_SPEC.md "1.2.3"; cross-check against the firmware's
// vectors in firmware/waveshare/docs/BLE_LINK_PROTOCOL.md when the branches meet)

final class DiagCodecTests: XCTestCase {
    private func bytes(_ hex: String) -> Data { Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! }) }

    func testPhoneToBoardVectors() {
        XCTAssertEqual(BCLink.encodeDiagListRequest(seq: 1, tMs: 0), bytes("80 00 01 00 00 00 00 00"))
        XCTAssertEqual(BCLink.encodeDiagChunkRequest(reportId: 7, offset: 320, maxLen: 160, seq: 2, tMs: 0),
                       bytes("83 00 02 00 00 00 00 00 01 04 07 00 00 00 02 04 40 01 00 00 03 02 A0 00"))
        XCTAssertEqual(BCLink.encodeDiagAck(reportId: 7, crc32: 0xCBF43926, seq: 3, tMs: 0),
                       bytes("85 00 03 00 00 00 00 00 01 04 07 00 00 00 02 04 26 39 F4 CB"))
    }

    static let infoHex = "81 00 0A 00 00 00 00 00 01 04 07 00 00 00 02 04 00 10 00 00 03 04 26 39 F4 CB 04 04 B4 B8 DC 6A 05 01 01 06 01 00 07 14 70 61 6E 69 63 20 69 6E 20 6E 69 6D 62 6C 65 5F 68 6F 73 74 08 05 30 2E 37 2E 33"

    func testDiagInfoVector() throws {
        let i = try XCTUnwrap(BCLink.decodeDiagInfo(bytes(Self.infoHex)))
        XCTAssertEqual(i.reportId, 7); XCTAssertEqual(i.size, 4096); XCTAssertEqual(i.crc32, 0xCBF43926)
        XCTAssertEqual(i.createdEpochS, 1792850100); XCTAssertEqual(i.kind, .crash); XCTAssertEqual(i.state, 0); XCTAssertTrue(i.pending)
        XCTAssertEqual(i.summary, "panic in nimble_host"); XCTAssertEqual(i.firmware, "0.7.3")
        // the test encoder mirrors the board byte for byte
        XCTAssertEqual(BCLink.encodeDiagInfo(i, seq: 10, tMs: 0), bytes(Self.infoHex))
    }

    func testUnknownTagsSkippedTruncatedRejected() {
        // unknown tag 0x7F inserted after the crc and an unknown trailing tag 0x20: still decodes
        let withUnknown = bytes("81 00 0A 00 00 00 00 00 01 04 07 00 00 00 02 04 00 10 00 00 03 04 26 39 F4 CB 7F 02 AA BB 06 01 01 20 00")
        let i = BCLink.decodeDiagInfo(withUnknown)
        XCTAssertEqual(i?.reportId, 7); XCTAssertEqual(i?.state, 1)
        // truncated (last byte missing) → rejected whole
        var t = bytes(Self.infoHex); t.removeLast()
        XCTAssertNil(BCLink.decodeDiagInfo(t))
        XCTAssertNil(BCLink.decodeDiagInfo(bytes("81 00 0A 00 00 00 00")))
        // missing crc → not a usable DIAG_INFO
        XCTAssertNil(BCLink.decodeDiagInfo(bytes("81 00 0A 00 00 00 00 00 01 04 07 00 00 00 02 04 00 10 00 00")))
        // wrong-length known field (report_id as u16) is skipped, so the message lacks an id
        XCTAssertNil(BCLink.decodeDiagInfo(bytes("81 00 0A 00 00 00 00 00 01 02 07 00 02 04 00 10 00 00 03 04 26 39 F4 CB")))
        // other types are not DIAG messages
        XCTAssertNil(BCLink.decodeDiagChunk(bytes(Self.infoHex)))
    }

    func testListEndChunkErrVectors() throws {
        let e = try XCTUnwrap(BCLink.decodeDiagListEnd(bytes("82 00 0B 00 00 00 00 00 01 01 02 02 01 01")))
        XCTAssertEqual(e.count, 2); XCTAssertEqual(e.pending, 1)
        let c = try XCTUnwrap(BCLink.decodeDiagChunk(bytes("84 00 0C 00 00 00 00 00 01 04 07 00 00 00 02 04 00 00 00 00 03 09 5B 68 65 61 64 65 72 5D 0A 04 01 00")))
        XCTAssertEqual(c.reportId, 7); XCTAssertEqual(c.offset, 0); XCTAssertEqual(String(decoding: c.data, as: UTF8.self), "[header]\n"); XCTAssertFalse(c.last)
        let last = try XCTUnwrap(BCLink.decodeDiagChunk(bytes("84 00 0D 00 00 00 00 00 01 04 07 00 00 00 02 04 F7 0F 00 00 03 09 5B 72 65 63 6F 76 65 72 79 04 01 01")))
        XCTAssertEqual(last.offset, 4087); XCTAssertTrue(last.last)
        XCTAssertNil(BCLink.decodeDiagChunk(bytes("84 00 0C 00 00 00 00 00 01 04 07 00 00 00 02 04 00 00 00 00 03 09 5B 68")))   /* truncated */
        for (code, k) in [(1, BCLink.DiagErr.Code.unknownId), (2, .badOffset), (3, .storageReadError), (4, .busy)] {
            let err = try XCTUnwrap(BCLink.decodeDiagErr(bytes("86 00 0E 00 00 00 00 00 01 04 07 00 00 00 02 01 0\(code)")))
            XCTAssertEqual(err.reportId, 7); XCTAssertEqual(err.known, k)
        }
        XCTAssertNil(BCLink.decodeDiagErr(bytes("86 00 0E 00 00 00 00 00 01 04 07 00 00 00")))   /* no code */
    }

    func testFullSizeChunkIsLongerThan180AndStillDecodes() throws {
        let payload = Data(repeating: 0x41, count: 160)
        let d = BCLink.encodeDiagChunk(BCLink.DiagChunk(reportId: 1, offset: 160, data: payload, last: false), seq: 1, tMs: 0)
        XCTAssertEqual(d.count, 185)           /* 8 header + 6 id + 6 offset + 2+160 data + 3 last: never sent by 0.7.3 (it clamps to 155) */
        XCTAssertEqual(try XCTUnwrap(BCLink.decodeDiagChunk(d)).data, payload)
    }

    func testDiagReadyEvent() throws {
        let d = bytes("40 00 0F 00 00 00 00 00 01 01 22 02 01 01 03 04 07 00 00 00")
        let r = try XCTUnwrap(BCLink.decodeDiagReady(d))
        XCTAssertEqual(r.pending, 1); XCTAssertEqual(r.newestReportId, 7)
        XCTAssertEqual(BCLink.encodeDiagReady(pending: 1, newest: 7, seq: 15, tMs: 0), d)
        XCTAssertNil(BCLink.decodeSensorDiag(d))                      /* not mistaken for SENSOR_DIAG */
        // SENSOR_DIAG and LINK_DIAG are not diag_ready
        XCTAssertNil(BCLink.decodeDiagReady(bytes("40 00 05 00 A0 86 01 00 01 01 21 02 01 01 03 01 06")))
        XCTAssertNil(BCLink.decodeDiagReady(bytes("40 00 05 00 00 00 00 00 01 01 20 02 01 01")))
        XCTAssertNil(BCLink.decodeDiagReady(bytes("40 00 0F 00 00 00 00 00 01 01 22 02 01")))   /* truncated */
    }

    func testCapAndCrc() {
        var i = BCLink.Info(); i.caps = 0x3F | 0x40 | 0x80 | 0x100 | 0x200
        XCTAssertFalse(i.hasDiagXfer, "firmware without cap 0x400 never gets a report request")
        i.caps |= 0x400
        XCTAssertTrue(i.hasDiagXfer)
        XCTAssertEqual(CRC32.ieee(Data("123456789".utf8)), 0xCBF43926)
        XCTAssertEqual(CRC32.ieee(Data()), 0)
        XCTAssertEqual(CRC32.update(CRC32.ieee(Data("12345".utf8)), Data("6789".utf8)), 0xCBF43926)
    }
}

// MARK: - transfer engine with a fake board

/// A board that serves reports exactly as the spec says, with switches for every failure the engine must survive.
final class FakeDiagBoard {
    struct Report { var info: BCLink.DiagInfo; var data: Data }
    var reports: [Report] = []
    var silent = false
    var dropNextChunks = 0
    var stopAfterChunks: Int?
    var chunksServed = 0
    var corruptPasses: [UInt32: Int] = [:]
    var errQueue: [UInt8] = []
    var acks: [(id: UInt32, crc: UInt32)] = []
    /// The board's clamp (firmware bc_diag_chunk_data_max): min(max_len, 155, ATT_MTU − 3 − 25). MTU 185 by default.
    var attMtu = 185
    var ridingOnBoard = false
    private var seq: UInt16 = 0

    func add(id: UInt32, size: Int, kind: UInt8 = 1, state: UInt8 = 0, summary: String = "panic in nimble_host") {
        let data = Data((0..<size).map { UInt8(65 + $0 % 26) })
        reports.append(Report(info: BCLink.DiagInfo(reportId: id, size: UInt32(size), crc32: CRC32.ieee(data), createdEpochS: 1792850100,
                                                    kindRaw: kind, state: state, summary: summary, firmware: "0.7.3"), data: data))
    }
    private func fields(_ d: Data) -> [UInt8: Data] { var m: [UInt8: Data] = [:]; for f in BCLink.parse(d)?.1 ?? [] { m[f.tag] = f.value }; return m }
    private func next() -> UInt16 { seq &+= 1; return seq }

    func respond(_ d: Data) -> [Data] {
        guard !silent, let t = d.first else { return [] }
        let f = fields(d)
        switch t {
        case 0x80:
            return reports.map { BCLink.encodeDiagInfo($0.info, seq: next(), tMs: 0) }
                + [BCLink.encodeDiagListEnd(count: UInt8(reports.count), pending: UInt8(reports.filter { $0.info.pending }.count), seq: next(), tMs: 0)]
        case 0x83:
            let id = UInt32(BCLink.uint(f[0x01]!)), off = UInt32(BCLink.uint(f[0x02]!)), maxLen = Int(BCLink.uint(f[0x03]!))
            if dropNextChunks > 0 { dropNextChunks -= 1; return [] }
            if let s = stopAfterChunks, chunksServed >= s { return [] }
            if !errQueue.isEmpty { return [BCLink.encodeDiagErr(reportId: id, code: errQueue.removeFirst(), seq: next(), tMs: 0)] }
            if ridingOnBoard { return [BCLink.encodeDiagErr(reportId: id, code: 4, seq: next(), tMs: 0)] }
            guard let r = reports.first(where: { $0.info.reportId == id }) else { return [BCLink.encodeDiagErr(reportId: id, code: 1, seq: next(), tMs: 0)] }
            guard off <= r.info.size else { return [BCLink.encodeDiagErr(reportId: id, code: 2, seq: next(), tMs: 0)] }
            let room = min(maxLen == 0 ? 155 : maxLen, 155, attMtu - 3 - 25)
            guard room >= 1 else { return [BCLink.encodeDiagErr(reportId: id, code: 5, seq: next(), tMs: 0)] }
            let end = min(Int(off) + room, r.data.count)
            var part = Data(r.data[Int(off)..<end])
            if off == 0, let n = corruptPasses[id], n > 0, !part.isEmpty { corruptPasses[id] = n - 1; part[part.startIndex] ^= 0xFF }
            chunksServed += 1
            return [BCLink.encodeDiagChunk(BCLink.DiagChunk(reportId: id, offset: off, data: part, last: end == r.data.count), seq: next(), tMs: 0)]
        case 0x85:
            let id = UInt32(BCLink.uint(f[0x01]!)), crc = UInt32(BCLink.uint(f[0x02]!))
            acks.append((id, crc))
            guard let k = reports.firstIndex(where: { $0.info.reportId == id }) else { return [BCLink.encodeDiagErr(reportId: id, code: 1, seq: next(), tMs: 0)] }
            if reports[k].info.crc32 == crc { reports[k].info.state = 1 }
            return [BCLink.encodeDiagInfo(reports[k].info, seq: next(), tMs: 0)]
        default: return []
        }
    }
}

final class DiagTransferTests: XCTestCase {
    static let board = "aa:bb:cc:dd:ee:ff"
    var root: URL!
    var store: DiagStore!
    var fake: FakeDiagBoard!
    var engine: DiagTransfer!
    var outbox: [Data] = []
    var sent: [Data] = []
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var ride = false
    var boardRide = false
    var linkPayload: Int? = 182                              /* iOS: ATT MTU 185 − 3 */
    var saved: [DiagReportMeta] = []

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)", isDirectory: true)
        store = DiagStore(root: root)
        fake = FakeDiagBoard()
        sent = []; outbox = []; saved = []
        engine = makeEngine()
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func makeEngine() -> DiagTransfer {
        let e = DiagTransfer(boardId: Self.board, store: store) { [unowned self] d in self.outbox.append(d); self.sent.append(d); return true }
        e.rideActive = { [unowned self] in self.ride }
        e.boardRecording = { [unowned self] in self.boardRide }
        e.linkPayload = { [unowned self] in self.linkPayload }
        e.onSaved = { [unowned self] m in self.saved.append(m) }
        return e
    }
    func pump() { while !outbox.isEmpty { let m = outbox.removeFirst(); for r in fake.respond(m) { engine.receive(r, now: now) } } }
    func start() { engine.start(now: now); pump() }
    func advance(_ s: TimeInterval) { now = now.addingTimeInterval(s); engine.tick(now: now); pump() }

    struct Req { var id: UInt32; var offset: UInt32; var maxLen: UInt16 }
    func fields(_ d: Data) -> [UInt8: Data] { var m: [UInt8: Data] = [:]; for f in BCLink.parse(d)?.1 ?? [] { m[f.tag] = f.value }; return m }
    var chunkRequests: [Req] {
        sent.filter { $0.first == 0x83 }.map { d -> Req in let f = fields(d); return Req(id: UInt32(BCLink.uint(f[1]!)), offset: UInt32(BCLink.uint(f[2]!)), maxLen: UInt16(BCLink.uint(f[3]!))) }
    }
    var acksSent: [(id: UInt32, crc: UInt32)] { sent.filter { $0.first == 0x85 }.map { d -> (id: UInt32, crc: UInt32) in let f = fields(d); return (UInt32(BCLink.uint(f[1]!)), UInt32(BCLink.uint(f[2]!))) } }
    var listRequests: Int { sent.filter { $0.first == 0x80 }.count }

    func assertSaved(_ id: UInt32, file: StaticString = #filePath, line: UInt = #line) {
        let r = fake.reports.first { $0.info.reportId == id }!
        let m = store.meta(Self.board, id)
        XCTAssertNotNil(m, file: file, line: line)
        XCTAssertEqual(m.flatMap { store.text($0) }, String(decoding: r.data, as: UTF8.self), file: file, line: line)
        XCTAssertEqual(m?.crc32, r.info.crc32, file: file, line: line)
        XCTAssertNil(store.partialLength(Self.board, id), "partial removed after commit", file: file, line: line)
    }

    // MARK: happy path
    func testFullTransferSavesVerifiesAndAcks() {
        fake.add(id: 3, size: 1000)
        start()
        XCTAssertEqual(listRequests, 1)
        XCTAssertEqual(chunkRequests.map(\.offset), [0, 155, 310, 465, 620, 775, 930])
        XCTAssertTrue(chunkRequests.allSatisfy { $0.maxLen == 155 && $0.id == 3 }, "MTU 185: max_len = 182 - 25 = 155")
        assertSaved(3)
        XCTAssertEqual(acksSent.count, 1); XCTAssertEqual(acksSent.first?.crc, fake.reports[0].info.crc32)
        XCTAssertEqual(fake.reports[0].info.state, 1, "board marked it sent")
        XCTAssertEqual(store.meta(Self.board, 3)?.boardAcknowledged, true, "DIAG_INFO state 1 after the ACK is remembered")
        XCTAssertEqual(saved.map(\.reportId), [3])
        XCTAssertEqual(engine.phase, .idle); XCTAssertNil(engine.lastError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("aa-bb-cc-dd-ee-ff/3.txt").path))
        XCTAssertEqual(store.allReports().first?.summary, "panic in nimble_host")
        XCTAssertEqual(store.allReports().first?.kind, .crash)
    }

    func testOnlyPendingReportsArePulledOldestFirst() {
        fake.add(id: 9, size: 200); fake.add(id: 4, size: 50); fake.add(id: 2, size: 70, state: 1)
        start()
        XCTAssertEqual(Array(Set(chunkRequests.map(\.id))).sorted(), [4, 9])
        XCTAssertEqual(chunkRequests.first?.id, 4)
        XCTAssertNil(store.meta(Self.board, 2), "already sent/acknowledged on the board: not pulled")
        assertSaved(4); assertSaved(9)
    }

    // MARK: interruption, restart
    func testInterruptionAtChunkKResumesFromOffset() {
        fake.add(id: 5, size: 1000)
        fake.stopAfterChunks = 3
        start()
        XCTAssertEqual(store.partialLength(Self.board, 5), 465, "bytes persisted as they arrive")
        engine.linkDown()                                   /* disconnect / board restart */
        XCTAssertEqual(acksSent.count, 0)
        fake.stopAfterChunks = nil
        let before = chunkRequests.count
        start()
        XCTAssertEqual(chunkRequests[before].offset, 465, "resumes at the last offset, not 0")
        assertSaved(5)
        XCTAssertEqual(acksSent.count, 1)
    }

    func testAppRestartResumesFromPersistedPartial() {
        fake.add(id: 6, size: 700)
        fake.stopAfterChunks = 2
        start()
        XCTAssertEqual(store.partialLength(Self.board, 6), 310)
        engine = makeEngine()                               /* app killed and relaunched: only the disk survives */
        store = DiagStore(root: root)
        fake.stopAfterChunks = nil
        let before = chunkRequests.count
        start()
        XCTAssertEqual(chunkRequests[before].offset, 310)
        assertSaved(6)
    }

    func testPartialOfADifferentReportIsDiscarded() {
        fake.add(id: 8, size: 500)
        fake.stopAfterChunks = 1
        start()
        engine.linkDown()
        // the board now lists id 8 with different contents (size/crc): the old bytes must not be reused
        fake.reports = []; fake.add(id: 8, size: 400, summary: "other")
        fake.reports[0].data = Data(repeating: 0x7A, count: 400); fake.reports[0].info.crc32 = CRC32.ieee(fake.reports[0].data)
        fake.stopAfterChunks = nil
        let before = chunkRequests.count
        start()
        XCTAssertEqual(chunkRequests[before].offset, 0)
        assertSaved(8)
    }

    // MARK: crc
    func testCrcMismatchDeletesPartialAndRetriesFromZero() {
        fake.add(id: 1, size: 400)
        fake.corruptPasses[1] = 1
        start()
        XCTAssertEqual(chunkRequests.map(\.offset), [0, 155, 310, 0, 155, 310])
        assertSaved(1)
        XCTAssertEqual(acksSent.count, 1, "one ACK, after the good pass")
        XCTAssertEqual(acksSent.first?.crc, fake.reports[0].info.crc32)
    }

    func testAckIsNeverSentForABadChecksum() {
        fake.add(id: 1, size: 300)
        fake.corruptPasses[1] = 99
        start()
        XCTAssertEqual(chunkRequests.filter { $0.offset == 0 }.count, 4, "first try + 3 retries from 0")
        XCTAssertTrue(acksSent.isEmpty)
        XCTAssertNil(store.meta(Self.board, 1)); XCTAssertNil(store.partialLength(Self.board, 1))
        XCTAssertNotNil(engine.lastError)
        XCTAssertEqual(fake.reports[0].info.state, 0, "stays pending on the board")
        XCTAssertEqual(engine.phase, .idle)
        // the same session does not hammer it again on the next list
        let n = chunkRequests.count
        start()
        XCTAssertEqual(chunkRequests.count, n)
    }

    // MARK: dedupe
    func testSavedReportIsNotPulledAgainOnlyReacknowledged() {
        fake.add(id: 3, size: 500)
        start()
        assertSaved(3)
        fake.reports[0].info.state = 0                       /* the board never got / kept the ACK */
        engine = makeEngine()
        let n = chunkRequests.count
        start()
        XCTAssertEqual(chunkRequests.count, n, "no chunk requested for a report stored here")
        XCTAssertEqual(acksSent.count, 2); XCTAssertEqual(acksSent.last?.crc, fake.reports[0].info.crc32)
        XCTAssertEqual(fake.reports[0].info.state, 1)
    }

    func testDeletedByRiderIsNeverPulledAgain() {
        fake.add(id: 3, size: 200)
        start()
        let m = store.meta(Self.board, 3)!
        store.delete(m)
        XCTAssertTrue(store.allReports().isEmpty)
        XCTAssertNil(store.text(m))
        fake.reports[0].info.state = 0
        let n = chunkRequests.count
        start()
        XCTAssertEqual(chunkRequests.count, n)
    }

    // MARK: DIAG_ERR
    func testErrUnknownIdSkipsToNextReport() {
        fake.add(id: 1, size: 100); fake.add(id: 2, size: 100)
        fake.errQueue = [1]
        start()
        XCTAssertNil(store.meta(Self.board, 1)); XCTAssertNil(store.partialLength(Self.board, 1))
        assertSaved(2)
        XCTAssertEqual(acksSent.map(\.id), [2])
    }

    func testErrBadOffsetRestartsFromZero() {
        fake.add(id: 1, size: 400)
        fake.stopAfterChunks = 1
        start()
        engine.linkDown()
        fake.stopAfterChunks = nil; fake.errQueue = [2]
        let before = chunkRequests.count
        start()
        XCTAssertEqual(chunkRequests[before].offset, 155)
        XCTAssertEqual(chunkRequests[before + 1].offset, 0, "bad offset → partial dropped, start again at 0")
        assertSaved(1)
    }

    func testErrStorageReadRetriesSameOffsetAfterDelay() {
        fake.add(id: 1, size: 300)
        fake.errQueue = [3]
        start()
        XCTAssertEqual(chunkRequests.count, 1)
        advance(1)
        XCTAssertEqual(chunkRequests.count, 1, "waits before retrying")
        advance(1)
        XCTAssertEqual(chunkRequests[1].offset, 0)
        assertSaved(1)
    }

    func testErrStorageReadGivesUpAfterThreeRetriesKeepingPartial() {
        fake.add(id: 1, size: 500)
        fake.stopAfterChunks = 1
        start(); engine.linkDown()
        fake.stopAfterChunks = nil; fake.errQueue = [3, 3, 3, 3]
        let before = chunkRequests.count
        start(); advance(2); advance(2); advance(2); advance(2)
        XCTAssertEqual(chunkRequests.count - before, 4)
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNotNil(engine.lastError)
        XCTAssertEqual(store.partialLength(Self.board, 1), 155, "kept for the next connection")
        XCTAssertTrue(acksSent.isEmpty)
    }

    func testErrBusyBacksOffTenSeconds() {
        fake.add(id: 1, size: 200)
        fake.errQueue = [4]
        start()
        advance(9)
        XCTAssertEqual(chunkRequests.count, 1)
        advance(1)
        XCTAssertEqual(chunkRequests[1].offset, 0)
        assertSaved(1)
    }

    // MARK: timeouts
    func testChunkTimeoutRetriesSameOffsetSameSize() {
        fake.add(id: 1, size: 400)
        fake.dropNextChunks = 1
        start()
        XCTAssertEqual(chunkRequests.count, 1)
        advance(4)
        XCTAssertEqual(chunkRequests.count, 1, "5 s per chunk")
        advance(1)
        XCTAssertEqual(chunkRequests[1].offset, 0)
        XCTAssertEqual(chunkRequests[1].maxLen, 155, "the size comes from the link MTU, never from a timeout")
        assertSaved(1)
    }

    func testRepeatedTimeoutsPauseUntilNextTrigger() {
        fake.add(id: 1, size: 400)
        fake.stopAfterChunks = 1
        start()
        for _ in 0..<4 { advance(5) }
        XCTAssertEqual(chunkRequests.count, 5, "1 answered + 1 unanswered + 3 retries")
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNotNil(engine.lastError)
        XCTAssertEqual(store.partialLength(Self.board, 1), 155)
        fake.stopAfterChunks = nil
        start()                                              /* next connect / diag_ready */
        assertSaved(1)
    }

    func testListTimeoutRetries() {
        fake.add(id: 1, size: 100)
        fake.silent = true
        start()
        fake.silent = false
        advance(5)
        XCTAssertEqual(listRequests, 2)
        assertSaved(1)
    }

    // MARK: ride throttling
    func testAtMostOneChunkPerSecondWhileRideIsActive() {
        ride = true
        fake.add(id: 1, size: 1000)                           /* 7 chunks */
        start()
        XCTAssertEqual(chunkRequests.count, 1)
        advance(0.5)
        XCTAssertEqual(chunkRequests.count, 1)
        advance(0.5)
        XCTAssertEqual(chunkRequests.count, 2)
        for _ in 0..<10 { advance(0.5) }                     /* 5 more seconds */
        XCTAssertEqual(chunkRequests.count, 7)
        assertSaved(1)
        // without a ride the remaining chunks go back-to-back
        ride = false
        fake.add(id: 2, size: 1000)
        start()
        XCTAssertNotNil(store.meta(Self.board, 2))
    }

    // MARK: chunk size from the negotiated link (docs/LINK_V1_2_SPEC.md 1.2.3) — never learned from failures
    func testChunkSizeComesFromTheLinkMTU() {
        for (payload, want) in [(182, 155), (244, 155), (514, 155), (97, 72), (26, 1)] {
            setUp(); linkPayload = payload; fake.attMtu = payload + 3
            fake.add(id: 1, size: 400)
            start()
            XCTAssertTrue(chunkRequests.allSatisfy { Int($0.maxLen) == want }, "ATT MTU \(payload + 3): max_len \(want)")
            assertSaved(1)
            XCTAssertEqual(chunkRequests.count, (400 + want - 1) / want)
            tearDown()
        }
        setUp(); linkPayload = nil                            /* size unknown (not connected): the protocol maximum; the board clamps */
        fake.add(id: 1, size: 400); start()
        XCTAssertEqual(chunkRequests.first?.maxLen, 155); assertSaved(1)
    }

    func testLinkTooSmallAsksNothingAndKeepsTheReportOnTheBoard() {
        linkPayload = 20; fake.attMtu = 23                    /* MTU 23: no exchange happened */
        fake.add(id: 1, size: 400)
        start()
        XCTAssertEqual(listRequests, 1)
        XCTAssertTrue(chunkRequests.isEmpty, "no request that could never fit")
        XCTAssertEqual(engine.phase, .idle); XCTAssertNotNil(engine.lastError)
        XCTAssertEqual(fake.reports[0].info.state, 0)
    }

    func testErrLinkTooSmallFromTheBoardPausesWithoutRetry() {
        linkPayload = 182; fake.attMtu = 23                   /* the phone believes 185, the board has 23 */
        fake.add(id: 1, size: 400)
        start()
        XCTAssertEqual(chunkRequests.count, 1)
        for _ in 0..<5 { advance(10) }
        XCTAssertEqual(chunkRequests.count, 1, "DIAG_ERR 5 is not retried")
        XCTAssertEqual(engine.phase, .idle); XCTAssertNotNil(engine.lastError)
        XCTAssertTrue(acksSent.isEmpty)
    }

    // MARK: ride priority on the phone side
    func testNoChunkRequestsWhileTheBoardRecordsARide() {
        fake.add(id: 1, size: 1000)
        boardRide = true; fake.ridingOnBoard = true
        start()
        XCTAssertEqual(listRequests, 1, "the list (one small write) still happens")
        for _ in 0..<12 { advance(5) }                       /* one minute of riding */
        XCTAssertTrue(chunkRequests.isEmpty, "no chunk request during the board's ride: LIVE has the link to itself")
        XCTAssertEqual(sent.count, 1, "one write in a minute")
        boardRide = false; fake.ridingOnBoard = false
        advance(10)
        assertSaved(1)
    }

    func testBusyFromABoardRideIsRetriedEveryTenSeconds() {
        fake.add(id: 1, size: 300)
        fake.ridingOnBoard = true                             /* LIVE not seen yet (older app state): the board says BUSY */
        start()
        for _ in 0..<6 { advance(5) }
        XCTAssertEqual(chunkRequests.count, 4, "first + one every 10 s for 30 s")
        fake.ridingOnBoard = false
        advance(10)
        assertSaved(1)
    }

    func testPhoneRideNeverMoreThanOneChunkRequestPerSecond() {
        ride = true
        fake.add(id: 1, size: 5000)                           /* 33 chunks */
        start()
        var times: [Date] = [now]
        for _ in 0..<160 {
            let n = chunkRequests.count
            advance(0.25)
            if chunkRequests.count > n { times.append(now) }
        }
        assertSaved(1)
        let gaps = zip(times.dropFirst(), times).map { $0.timeIntervalSince($1) }
        XCTAssertTrue(gaps.allSatisfy { $0 >= 0.999 }, "smallest gap \(gaps.min() ?? 0) s")
    }

    // MARK: triggers
    func testDiagReadyEventStartsAListAndRelistsWhenBusy() {
        engine.receive(BCLink.encodeDiagReady(pending: 1, newest: 1, seq: 1, tMs: 0), now: now)
        XCTAssertEqual(listRequests, 1)
        pump()
        XCTAssertEqual(engine.phase, .idle)
        // a new report arrives during a ride-throttled transfer → listed again afterwards
        ride = true
        fake.add(id: 1, size: 400)
        start()
        fake.add(id: 2, size: 100)
        engine.receive(BCLink.encodeDiagReady(pending: 2, newest: 2, seq: 2, tMs: 0), now: now)
        for _ in 0..<6 { advance(1) }
        assertSaved(1); assertSaved(2)
        XCTAssertEqual(listRequests, 3)
    }

    func testEmptyBoardDoesNothing() {
        start()
        XCTAssertEqual(listRequests, 1)
        XCTAssertTrue(chunkRequests.isEmpty); XCTAssertTrue(acksSent.isEmpty)
        XCTAssertEqual(engine.phase, .idle)
    }

    // MARK: export, upload hook, storage
    func testExportListsReportsWithoutTheirText() throws {
        fake.add(id: 3, size: 600)
        start()
        let center = DiagReportCenter(store: DiagStore(root: root))
        let entries = center.exportEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.crc32, String(format: "%08x", fake.reports[0].info.crc32))
        XCTAssertEqual(entries.first?.sizeBytes, 600)
        let json = String(decoding: try JSONEncoder().encode(entries), as: UTF8.self)
        XCTAssertFalse(json.contains("ABCDEFGHIJ"), "never the report text")
        XCTAssertFalse(json.lowercased().contains("aa:bb") || json.lowercased().contains("aa-bb"), "never the board address")
        XCTAssertNotNil(center.unseenCrash)
        center.dismissCrashBanner()
        XCTAssertNil(center.unseenCrash, "banner only for a new crash")
    }

    func testUploadHookIsOffInThisBuild() {
        XCTAssertFalse(ReleaseFlags.diagUploadEnabled)
        XCTAssertFalse(DiagUploadHook.allowed(flag: ReleaseFlags.diagUploadEnabled, consent: true), "consent alone does not enable it")
        XCTAssertFalse(DiagUploadHook.allowed(flag: true, consent: false), "and it needs explicit consent")
        fake.add(id: 1, size: 10)
        start()
        XCTAssertFalse(DiagUploadHook.upload(store.meta(Self.board, 1)!))
    }

    func testBoardFolderNameIsFileSystemSafe() {
        XCTAssertEqual(DiagStore.folderName("aa:bb:cc:dd:ee:ff"), "aa-bb-cc-dd-ee-ff")
        XCTAssertEqual(DiagStore.folderName("../x"), "..-x")
        XCTAssertEqual(DiagStore.folderName(""), "unknown")
    }
}

// MARK: - Link 1.3 DIAG_AUTO (BLE_CONTRACT.md §8): verify-then-ack, `03 delete = 1` only when the board enabled it
extension DiagTransferTests {
    func testAckCarriesDeleteOnlyWithDiagAuto() {
        fake.add(id: 4, size: 400)
        start()
        XCTAssertEqual(sent.filter { $0.first == 0x85 }.count, 1)
        XCTAssertNil(fields(sent.last { $0.first == 0x85 }!)[0x03], "without DIAG_AUTO: the 1.2.3 ACK exactly (no delete tag)")
        // a board that enabled DIAG_AUTO: the verified, saved report is ACKed with delete = 1
        setUp()
        engine.ackWithDelete = { true }
        fake.add(id: 5, size: 400)
        start()
        assertSaved(5)
        let ack = fields(sent.last { $0.first == 0x85 }!)
        XCTAssertEqual(ack[0x03], Data([1])); XCTAssertEqual(UInt32(BCLink.uint(ack[0x02]!)), fake.reports[0].info.crc32)
        // a corrupted transfer is never ACKed at all, with or without delete
        setUp()
        engine.ackWithDelete = { true }
        fake.add(id: 6, size: 400); fake.corruptPasses[6] = 99
        start()
        for _ in 0..<10 { advance(6) }
        XCTAssertTrue(sent.filter { $0.first == 0x85 }.isEmpty)
        XCTAssertNil(store.meta(Self.board, 6))
    }
}
