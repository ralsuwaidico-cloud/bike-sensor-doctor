import XCTest
@testable import BikeComputer

/// Link 1.3 codec (coord/interfaces/BLE_CONTRACT.md v1). Byte vectors are built by hand from the contract tables: the
/// firmware has no Link 1.3 encoder yet (FW-4), so these are contract vectors, not firmware vectors. When the firmware
/// publishes its Link 1.3 fixture it is added next to diag_fw_fixture.json and cross-checked the same way.
final class Link13CodecTests: XCTestCase {
    private func bytes(_ hex: String) -> Data { Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! }) }

    // MARK: §4 negotiation
    func testInfoCapsAndHello() throws {
        var i = BCLink.Info(); i.caps = 0x7FF
        XCTAssertFalse(i.hasHello, "0.7.3 board: no HELLO cap")
        i.caps = 0xFFFF
        XCTAssertTrue(i.hasHello)
        XCTAssertEqual(BCLink.appCaps13, 0xF800)
        XCTAssertEqual(BCLink.encodeAppHello(appVersion: "1.3.0", seq: 1, tMs: 0),
                       bytes("08 00 01 00 00 00 00 00 01 01 01 02 01 03 03 04 00 F8 00 00 04 05 31 2E 33 2E 30"))
        // app_version is cut to 16 bytes at a character boundary
        let long = try XCTUnwrap(BCLink.encodeAppHello(appVersion: "1.3.0 (build 1234567)", seq: 1, tMs: 0))
        XCTAssertEqual(long.count, 8 + 3 + 3 + 6 + 2 + 16)
        let a = try XCTUnwrap(BCLink.decodeHelloAck(bytes("09 00 05 00 00 00 00 00 01 04 00 38 00 00")))
        XCTAssertEqual(a.enabledCaps, 0x3800)
        XCTAssertEqual(BCLink.encodeHelloAck(enabledCaps: 0x3800, seq: 5, tMs: 0), bytes("09 00 05 00 00 00 00 00 01 04 00 38 00 00"))
        XCTAssertNil(BCLink.decodeHelloAck(bytes("09 00 05 00 00 00 00 00 01 02 00 38")), "wrong-length caps skipped → no caps")
        XCTAssertNil(BCLink.decodeHelloAck(bytes("09 00 05 00 00 00 00 00 01 04 00 38 00")), "truncated → rejected whole")
    }

    func testSessionGate() {
        var s = Link13Session()
        var info = BCLink.Info(); info.verMajor = 1; info.caps = 0x7FF
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(s.connected(info: info, now: t0), "no HELLO to a board without cap 0x0800")
        XCTAssertFalse(s.coach || s.rideQueue || s.storage || s.diagAuto)
        info.caps = 0x7FF | 0x0800 | 0x1000 | 0x4000
        XCTAssertTrue(s.connected(info: info, now: t0))
        XCTAssertTrue(s.isWaiting); XCTAssertFalse(s.coach, "nothing before HELLO_ACK")
        s.helloAck(BCLink.HelloAck(enabledCaps: 0x0800 | 0x1000 | 0x4000 | 0x0001_0000))
        XCTAssertTrue(s.coach); XCTAssertTrue(s.storage); XCTAssertFalse(s.rideQueue); XCTAssertFalse(s.diagAuto)
        XCTAssertEqual(s.enabledCaps & 0x0001_0000, 0, "unknown future bits are masked by what the app implements")
        s.linkDown()
        XCTAssertFalse(s.coach, "every connection negotiates again")
        // no answer: one more HELLO, then Link 1.2 behaviour for this connection
        XCTAssertTrue(s.connected(info: info, now: t0))
        XCTAssertFalse(s.tick(now: t0.addingTimeInterval(1)))
        XCTAssertTrue(s.tick(now: t0.addingTimeInterval(4)))
        XCTAssertFalse(s.tick(now: t0.addingTimeInterval(8)))
        XCTAssertEqual(s.phase, .noAnswer); XCTAssertFalse(s.coach)
    }

    // MARK: §4 LIVE tags 11–15, EVENT 0x23
    func testLiveNewTagsAndOldBoards() throws {
        let old = try XCTUnwrap(BCLink.decodeLive(bytes("10 00 01 00 00 00 00 00 01 02 91 00 08 01 01")))
        XCTAssertEqual(old.powerW, 145); XCTAssertNil(old.coachSeq); XCTAssertNil(old.coachMode); XCTAssertNil(old.storageState); XCTAssertNil(old.ridesUnsynced); XCTAssertNil(old.btFlags)
        let l = try XCTUnwrap(BCLink.decodeLive(bytes("10 00 01 00 00 00 00 00 01 02 91 00 11 02 2A 00 12 01 02 13 01 03 14 01 04 15 01 03")))
        XCTAssertEqual(l.powerW, 145); XCTAssertEqual(l.coachSeq, 42); XCTAssertEqual(l.coachMode, 2); XCTAssertEqual(l.storageState, 3)
        XCTAssertEqual(l.ridesUnsynced, 4); XCTAssertEqual(l.btFlags, 3)
    }

    func testRidesPendingEvent() throws {
        let d = bytes("40 00 09 00 00 00 00 00 01 01 23 02 01 02 03 04 0C 00 00 00")
        let r = try XCTUnwrap(BCLink.decodeRidesPending(d))
        XCTAssertEqual(r.unsynced, 2); XCTAssertEqual(r.newestRideId, 12)
        XCTAssertEqual(BCLink.encodeRidesPending(unsynced: 2, newest: 12, seq: 9, tMs: 0), d)
        XCTAssertNil(BCLink.decodeDiagReady(d)); XCTAssertNil(BCLink.decodeSensorDiag(d))
        XCTAssertEqual(BCLink.decodeEvent(d)?.eventId, 0x23, "the generic event decoder still reads it (shipped app: ignored)")
        XCTAssertNil(BCLink.decodeRidesPending(bytes("40 00 08 00 40 00 00 00 01 01 22 02 01 01 03 04 07 00 00 00")), "diag_ready is not rides_pending")
    }

    // MARK: §5 coach
    func testCoachSegmentAndPlanPart0Bytes() throws {
        let s0 = BCLink.CoachSegment(durationS: 300, type: .warmUp, targetKind: .powerW, lo: 70, hi: 145, cadLo: 85, cadHi: 95)
        XCTAssertEqual(s0.bytes, bytes("2C 01 0B 01 46 00 91 00 55 5F"))
        XCTAssertEqual(BCLink.CoachSegment.decode(s0.bytes), s0)
        let s1 = BCLink.CoachSegment(durationS: 2700, type: .endurance, targetKind: .powerW, lo: 140, hi: 155, cadLo: 80, cadHi: 90)
        let p = BCLink.CoachPlan(workoutId: 0x0102_0304, name: "ENDURANCE", segments: [s0, s1], t0ElapsedS: BCLink.coachT0AtRideStart)
        XCTAssertEqual(p.partCount, 1); XCTAssertEqual(p.totalDurationS, 3000)
        XCTAssertEqual(p.crc32, CRC32.ieee(bytes("2C 01 0B 01 46 00 91 00 55 5F 8C 0A 02 01 8C 00 9B 00 50 5A")))
        let crc = BCLink.le(p.crc32).map { String(format: "%02X", $0) }.joined(separator: " ")
        let expect = "B0 00 07 00 00 00 00 00 01 04 04 03 02 01 02 02 00 00 03 02 01 00 04 02 00 00 05 14 2C 01 0B 01 46 00 91 00 55 5F 8C 0A 02 01 8C 00 9B 00 50 5A "
            + "06 09 45 4E 44 55 52 41 4E 43 45 07 02 02 00 08 04 B8 0B 00 00 09 04 \(crc) 0A 04 FF FF FF FF"
        XCTAssertEqual(BCLink.encodeCoachPlan(p, part: 0, seq: 7, tMs: 0), bytes(expect))
        XCTAssertNil(BCLink.encodeCoachPlan(p, part: 1, seq: 7, tMs: 0), "part out of range")
        XCTAssertNil(BCLink.encodeCoachPlan(BCLink.CoachPlan(workoutId: 1, name: "", segments: [], t0ElapsedS: 0), part: 0, seq: 1, tMs: 0))
    }

    func testLargestPlanSplitsIntoPartsUnder180Bytes() throws {
        let seg = BCLink.CoachSegment(durationS: 60, type: .vo2max, targetKind: .powerW, lo: 300, hi: 340, cadLo: 95, cadHi: 105)
        let p = BCLink.CoachPlan(workoutId: 99, name: "A NAME OF TWENTY BYTES+", segments: Array(repeating: seg, count: 64), t0ElapsedS: 0)
        XCTAssertEqual(p.partCount, 1 + 4, "9 + 14 × 4 = 65 ≥ 64")
        var segs: [BCLink.CoachSegment] = []
        for k in 0..<p.partCount {
            let d = try XCTUnwrap(BCLink.encodeCoachPlan(p, part: k, seq: UInt16(k), tMs: 0xFFFF_FFFF))
            XCTAssertLessThanOrEqual(d.count, BCLink.maxMessage, "part \(k)")
            let x = try XCTUnwrap(BCLink.decodeCoachPlan(d))
            XCTAssertEqual(x.part, k); XCTAssertEqual(x.parts, p.partCount); XCTAssertEqual(x.firstSegment, segs.count)
            if k == 0 { XCTAssertEqual(x.name, "A NAME OF TWENTY BYT"); XCTAssertEqual(x.totalSegments, 64); XCTAssertEqual(x.crc32, p.crc32); XCTAssertEqual(x.t0ElapsedS, 0) }
            else { XCTAssertNil(x.name); XCTAssertNil(x.crc32) }
            segs += x.segments
        }
        XCTAssertEqual(segs, p.segments)
        XCTAssertEqual(CRC32.ieee(segs.reduce(into: Data()) { $0.append($1.bytes) }), p.crc32, "the board's reassembly verifies")
        XCTAssertNil(BCLink.encodeCoachPlan(BCLink.CoachPlan(workoutId: 1, name: "", segments: Array(repeating: seg, count: 65), t0ElapsedS: 0), part: 0, seq: 1, tMs: 0))
    }

    func testCoachPlanAckAndEnd() throws {
        let a = try XCTUnwrap(BCLink.decodeCoachPlanAck(bytes("B1 00 03 00 00 00 00 00 01 04 63 00 00 00 02 01 01 03 02 01 00")))
        XCTAssertEqual(a.workoutId, 99); XCTAssertEqual(a.status, .partReceived); XCTAssertEqual(a.nextPart, 1)
        XCTAssertEqual(BCLink.encodeCoachPlanAck(a, seq: 3, tMs: 0), bytes("B1 00 03 00 00 00 00 00 01 04 63 00 00 00 02 01 01 03 02 01 00"))
        XCTAssertNil(BCLink.decodeCoachPlanAck(bytes("B1 00 03 00 00 00 00 00 01 04 63 00 00 00")), "no status")
        XCTAssertEqual(BCLink.encodeCoachEnd(workoutId: 99, reason: .stoppedByRider, seq: 4, tMs: 0), bytes("B3 00 04 00 00 00 00 00 01 04 63 00 00 00 02 01 01"))
    }

    func testCoachStateBytesSizeAndText() throws {
        var s = BCLink.CoachState()
        s.workoutId = 99; s.seq = 5; s.type = .endurance; s.targetKind = .powerW; s.targetLo = 140; s.targetHi = 155; s.cadLo = 80; s.cadHi = 90
        s.intervalIndex = 1; s.intervalCount = 3; s.remainingS = 180; s.intervalDurationS = 2700
        s.instruction = .onTarget; s.sessionState = .running; s.hrSource = 4; s.zone = 2; s.flags = 0x06
        let d = try XCTUnwrap(BCLink.encodeCoachState(s, seq: 11, tMs: 0))
        XCTAssertEqual(d, bytes("B2 00 0B 00 00 00 00 00 01 04 63 00 00 00 02 02 05 00 03 01 02 04 01 01 05 02 8C 00 06 02 9B 00 07 01 50 08 01 5A "
                                + "09 02 01 00 0A 02 03 00 0B 02 B4 00 0C 02 8C 0A 0D 01 FF 0E 01 00 0F 02 00 00 10 02 00 00 11 02 00 00 12 01 01 13 00 14 01 01 15 01 04 16 01 02 17 01 06"),
                       "v1.3 merge: every field is sent — no next interval = next_type 0xFF, no text = empty text (never left out)")
        XCTAssertEqual(BCLink.decodeCoachState(d), s)
        // every field + the longest text stays inside one Link message
        s.nextType = .recovery; s.nextTargetKind = .powerW; s.nextLo = 70; s.nextHi = 100; s.nextDurationS = 180
        s.text = "ÉÉÉÉÉÉÉÉÉÉÉÉÉ"                    /* 13 × 2 bytes = 26 → cut to 12 characters (24 bytes), never half a character */
        let full = try XCTUnwrap(BCLink.encodeCoachState(s, seq: 12, tMs: 0))
        XCTAssertLessThanOrEqual(full.count, 120)
        let back = try XCTUnwrap(BCLink.decodeCoachState(full))
        XCTAssertEqual(back.text, String(repeating: "É", count: 12)); XCTAssertEqual(back.nextType, .recovery); XCTAssertEqual(back.nextDurationS, 180)
        XCTAssertEqual(BCLink.utf8Prefix("ab🚴", max: 5), Data("ab".utf8), "a 4-byte emoji does not fit in 3 bytes")
    }

    // MARK: §6 ride queue
    func testRideQueueVectors() throws {
        XCTAssertEqual(BCLink.encodeRideQueueListRequest(seq: 1, tMs: 0), bytes("90 00 01 00 00 00 00 00"))
        let info = bytes("91 00 02 00 00 00 00 00 01 04 0C 00 00 00 02 01 01 03 04 00 A0 00 00 04 04 26 39 F4 CB 05 04 B4 B8 DC 6A 06 04 10 0E 00 00 07 01 02 08 04 78 56 34 12")
        let i = try XCTUnwrap(BCLink.decodeRideQueueInfo(info))
        XCTAssertEqual(i.rideId, 12); XCTAssertEqual(i.state, .closedUnsynced); XCTAssertEqual(i.samplesSize, 40960); XCTAssertEqual(i.samplesCrc32, 0xCBF43926)
        XCTAssertEqual(i.startEpochS, 1792850100); XCTAssertEqual(i.durationS, 3600); XCTAssertTrue(i.recovered); XCTAssertFalse(i.demo); XCTAssertEqual(i.summaryCrc32, 0x1234_5678)
        XCTAssertTrue(i.needsImport)
        XCTAssertEqual(BCLink.encodeRideQueueInfo(i, seq: 2, tMs: 0), info)
        XCTAssertNil(BCLink.decodeRideQueueInfo(bytes("91 00 02 00 00 00 00 00 01 04 0C 00 00 00 02 01 01")), "size and crc are required")
        let e = try XCTUnwrap(BCLink.decodeRideQueueListEnd(bytes("92 00 03 00 00 00 00 00 01 02 03 00 02 02 02 00 03 04 00 40 01 00")))
        XCTAssertEqual(e.count, 3); XCTAssertEqual(e.unsynced, 2); XCTAssertEqual(e.unsyncedBytes, 81920)
        // chunk request: byte-identical layout to DIAG_CHUNK_REQ, only the type differs
        let rq = try XCTUnwrap(BCLink.encodeRideQueueChunkRequest(rideId: 12, offset: 310, maxLen: 155, seq: 4, tMs: 0))
        let dq = try XCTUnwrap(BCLink.encodeDiagChunkRequest(reportId: 12, offset: 310, maxLen: 155, seq: 4, tMs: 0))
        XCTAssertEqual(rq.first, 0x93); XCTAssertEqual(rq.dropFirst(), dq.dropFirst())
        let c = try XCTUnwrap(BCLink.decodeRideQueueChunk(bytes("94 00 05 00 00 00 00 00 01 04 0C 00 00 00 02 04 36 01 00 00 03 05 31 32 30 20 39 04 01 00")))
        XCTAssertEqual(c.rideId, 12); XCTAssertEqual(c.offset, 310); XCTAssertEqual(c.data, Data("120 9".utf8)); XCTAssertFalse(c.last)
        let full = BCLink.encodeRideQueueChunk(BCLink.RideQueueChunk(rideId: .max, offset: .max, data: Data(repeating: 0x31, count: BCLink.diagChunkDataMax), last: true), seq: 1, tMs: 0)
        XCTAssertEqual(full.count, BCLink.maxMessage, "same 25-byte overhead as DIAG_CHUNK")
        XCTAssertEqual(BCLink.encodeRideQueueAck(rideId: 12, samplesCrc32: 0xCBF43926, summaryCrc32: 0x1234_5678, deleteSamples: true, seq: 6, tMs: 0),
                       bytes("95 00 06 00 00 00 00 00 01 04 0C 00 00 00 02 04 26 39 F4 CB 03 04 78 56 34 12 04 01 01"))
        let err = try XCTUnwrap(BCLink.decodeRideQueueErr(bytes("96 00 07 00 00 00 00 00 01 04 0C 00 00 00 02 01 04")))
        XCTAssertEqual(err.reportId, 12); XCTAssertEqual(err.known, .busy)
        XCTAssertNil(BCLink.decodeRideQueueInfo(bytes("81 00 02 00 00 00 00 00 01 04 0C 00 00 00 02 01 01 03 04 00 A0 00 00 04 04 26 39 F4 CB")), "a DIAG_INFO is not a RIDEQ_INFO")
    }

    // MARK: §7 storage
    func testStorageStatusAndClean() throws {
        let d = bytes("A1 00 01 00 00 00 00 00 01 01 03 02 0D 64 69 72 5F 63 6F 72 72 75 70 74 65 64 03 04 00 0C 00 00 04 04 00 02 00 00 05 01 02 06 04 00 00 01 00 "
                      + "07 02 03 00 08 02 01 00 09 04 00 30 00 00 0A 02 02 00 0B 04 00 A0 00 00 0C 04 00 10 00 00 0D 04 00 0C 00 00 0E 04 30 09 00 00 "
                      + "0F 02 50 00 10 02 B0 01 11 02 00 00 12 02 02 00 13 01 02")
        let s = try XCTUnwrap(BCLink.decodeStorageStatus(d))
        XCTAssertEqual(s.state, .dirCorrupted); XCTAssertEqual(s.code, "dir_corrupted"); XCTAssertEqual(s.fsTotalKB, 3072); XCTAssertEqual(s.fsFreeKB, 512)
        XCTAssertEqual(s.crashPartition, 2); XCTAssertEqual(s.crashDumpBytes, 65536); XCTAssertEqual(s.reportsStored, 3); XCTAssertEqual(s.reportsUnsent, 1)
        XCTAssertEqual(s.diagBytes, 12288); XCTAssertEqual(s.ridesUnsynced, 2); XCTAssertEqual(s.rideBytesUnsynced, 40960); XCTAssertEqual(s.rideBytesSynced, 4096)
        XCTAssertEqual(s.appSlotKB, 3072); XCTAssertEqual(s.appUsedKB, 2352); XCTAssertEqual(s.nvsUsedEntries, 80); XCTAssertEqual(s.nvsFreeEntries, 432)
        XCTAssertEqual(s.rootFreeSlots, 0); XCTAssertEqual(s.rootBadEntries, 2); XCTAssertEqual(s.healthRaw, 2)
        XCTAssertEqual(BCLink.encodeStorageStatus(s, seq: 1, tMs: 0), d)
        XCTAssertLessThanOrEqual(d.count, BCLink.maxMessage)
        XCTAssertEqual(BCLink.encodeStorageStatusRequest(seq: 2, tMs: 0), bytes("A0 00 02 00 00 00 00 00"))
        XCTAssertEqual(BCLink.encodeStorageCleanRequest([.ackedReports, .syncedRideSamples, .caches], seq: 3, tMs: 0), bytes("A2 00 03 00 00 00 00 00 01 01 07"))
        XCTAssertNil(BCLink.encodeStorageCleanRequest(BCLink.StorageCleanWhat(rawValue: 0xFF), seq: 3, tMs: 0), "undefined bits are never sent")
        XCTAssertNil(BCLink.encodeStorageCleanRequest([], seq: 3, tMs: 0))
        let r = try XCTUnwrap(BCLink.decodeStorageCleanResult(bytes("A3 00 04 00 00 00 00 00 01 01 00 02 04 00 30 00 00 03 02 04 00")))
        XCTAssertEqual(r.status, .done); XCTAssertEqual(r.bytesFreed, 12288); XCTAssertEqual(r.items, 4)
        XCTAssertEqual(BCLink.encodeStorageCleanResult(r, seq: 4, tMs: 0), bytes("A3 00 04 00 00 00 00 00 01 01 00 02 04 00 30 00 00 03 02 04 00"))
        XCTAssertNil(BCLink.decodeStorageStatus(bytes("A1 00 01 00 00 00 00 00 02 02 6F 6B")), "no state → not a status")
        for st in BCLink.StorageState.allCases { XCTAssertFalse(st.title.isEmpty) }
        XCTAssertEqual(BCLink.StorageState.dirCorrupted.title, "Directory corrupted")
    }

    // MARK: §8 diag ack
    func testDiagAckDeleteIsOptionalTag() {
        XCTAssertEqual(BCLink.encodeDiagAck(reportId: 7, crc32: 0xCBF43926, delete: true, seq: 6, tMs: 0x30),
                       bytes("85 00 06 00 30 00 00 00 01 04 07 00 00 00 02 04 26 39 F4 CB 03 01 01"))
        XCTAssertEqual(BCLink.encodeDiagAck(reportId: 7, crc32: 0xCBF43926, seq: 6, tMs: 0x30),
                       bytes("85 00 06 00 30 00 00 00 01 04 07 00 00 00 02 04 26 39 F4 CB"), "without DIAG_AUTO: the 1.2.3 bytes exactly")
    }
}
