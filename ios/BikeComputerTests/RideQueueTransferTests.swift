import XCTest
@testable import BikeComputer

/// Offline ride import (BLE_CONTRACT.md §6) against a fake board that follows the contract: list, chunked pull, CRC,
/// ACK only after the ride is durably stored in Cyclift and the summary is verified, never twice, never for demo,
/// recording or conflicting rides.
final class RideQueueTransferTests: XCTestCase {
    static let board = "02:00:00:c1:f7:01"        /* synthetic device id */

    final class FakeBoard {
        struct Ride { var info: BCLink.RideQueueInfo; var data: Data }
        var rides: [Ride] = []
        var acks: [(id: UInt32, samples: UInt32, summary: UInt32, delete: Bool)] = []
        var chunkRequests = 0
        var dropChunks = 0
        var corruptOnce = false
        var busy = false
        var linkPayload = 182
        var inbox: [Data] = []
        func handle(_ d: Data) {
            guard let (h, f) = BCLink.parse(d) else { return }
            func u32(_ t: UInt8) -> UInt32 { f.first { $0.tag == t }.map { UInt32(BCLink.uint($0.value)) } ?? 0 }
            switch h.type {
            case 0x90:
                for r in rides { inbox.append(BCLink.encodeRideQueueInfo(r.info, seq: 0, tMs: 0)) }
                let un = rides.filter { $0.info.needsImport }
                inbox.append(BCLink.encodeRideQueueListEnd(.init(count: rides.count, unsynced: un.count, unsyncedBytes: un.reduce(0) { $0 + $1.info.samplesSize }), seq: 0, tMs: 0))
            case 0x93:
                chunkRequests += 1
                let id = u32(1), off = Int(u32(2)), maxLen = Int(f.first { $0.tag == 3 }.map { BCLink.uint($0.value) } ?? 0)
                if busy { inbox.append(BCLink.encodeRideQueueErr(rideId: id, code: 4, seq: 0, tMs: 0)); return }
                guard let r = rides.first(where: { $0.info.rideId == id }) else { inbox.append(BCLink.encodeRideQueueErr(rideId: id, code: 1, seq: 0, tMs: 0)); return }
                if dropChunks > 0 { dropChunks -= 1; return }
                let n = min(maxLen, 155, linkPayload - 25, r.data.count - off)
                var data = r.data.subdata(in: off..<(off + n))
                if corruptOnce, off == 0, !data.isEmpty { corruptOnce = false; data[data.startIndex] ^= 0xFF }
                inbox.append(BCLink.encodeRideQueueChunk(.init(rideId: id, offset: UInt32(off), data: data, last: off + n >= r.data.count), seq: 0, tMs: 0))
            case 0x95:
                let id = u32(1), sc = u32(2), su = u32(3)
                let del = f.first { $0.tag == 4 }.map { $0.value.first == 1 } ?? false
                acks.append((id, sc, su, del))
                if let k = rides.firstIndex(where: { $0.info.rideId == id }), rides[k].info.samplesCrc32 == sc, rides[k].info.summaryCrc32 == su {
                    rides[k].info.stateRaw = del ? 4 : 3
                    inbox.append(BCLink.encodeRideQueueInfo(rides[k].info, seq: 0, tMs: 0))
                }
            default: break
            }
        }
    }

    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("rq-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// The firmware's grammar (BLE_CONTRACT.md v1.1 §6.1): header `J1 …`, `-1` = no data, `-` line = paused second.
    static func samplesText(seconds: Int, pausedAt: Int? = nil) -> Data {
        var s = "J1 0 0 250 1 1\n"
        for t in 0..<seconds {
            if t == pausedAt { s += "-\n"; continue }
            s += "\(150 + t % 20) \(85 + t % 5) \(t % 7 == 0 ? -1 : 120 + t % 10) \(t * 8)\n"
        }
        return Data(s.utf8)
    }
    static func ride(_ id: UInt32, seconds: Int = 600, state: UInt8 = 1, flags: UInt8 = 0, summaryCrc: UInt32 = 0xABCD_0000) -> FakeBoard.Ride {
        let d = samplesText(seconds: seconds, pausedAt: 10)
        let i = BCLink.RideQueueInfo(rideId: id, stateRaw: state, samplesSize: UInt32(d.count), samplesCrc32: CRC32.ieee(d), startEpochS: 1_792_850_100 + id * 7200,
                                     durationS: UInt32(seconds), flags: flags, summaryCrc32: summaryCrc + id)
        return .init(info: i, data: d)
    }

    /// Engine + fake board + an in-memory "history" that the test controls.
    private func rig(_ b: FakeBoard, summaries: [UInt32: UInt32]? = nil, deliverOK: Bool = true) -> (RideQueueTransfer, BoardRideQueueStore, () -> [UInt32]) {
        let st = BoardRideQueueStore(root: dir)
        var delivered: [UInt32] = []
        let e = RideQueueTransfer(boardId: Self.board, store: st) { d in b.handle(d); return true }
        e.linkPayload = { b.linkPayload }
        let sums = summaries ?? Dictionary(uniqueKeysWithValues: b.rides.map { ($0.info.rideId, $0.info.summaryCrc32) })
        e.summaryCrc = { sums[$0] }
        e.deliver = { m, data in
            XCTAssertEqual(CRC32.ieee(data), m.samplesCrc32, "only verified bytes are delivered")
            if !deliverOK { return .failed("history not writable") }
            delivered.append(m.rideId); return .stored(UUID())
        }
        return (e, st, { delivered })
    }
    private func pump(_ e: RideQueueTransfer, _ b: FakeBoard, from t0: Date = Date(timeIntervalSince1970: 0), seconds: Double = 120) {
        var now = t0
        while now < t0.addingTimeInterval(seconds) {
            while !b.inbox.isEmpty { e.receive(b.inbox.removeFirst(), now: now) }
            e.tick(now: now)
            if !e.isBusy && b.inbox.isEmpty { break }
            now = now.addingTimeInterval(0.25)
        }
    }

    func testPullVerifyStoreThenAck() throws {
        let b = FakeBoard(); b.rides = [Self.ride(3), Self.ride(4), Self.ride(2, state: 3)]
        let (e, st, delivered) = rig(b)
        e.start(now: Date(timeIntervalSince1970: 0)); pump(e, b)
        XCTAssertEqual(delivered(), [3, 4], "oldest first; the already-verified ride 2 is not pulled")
        XCTAssertEqual(b.acks.map { $0.id }, [3, 4]); XCTAssertTrue(b.acks.allSatisfy { $0.delete })
        for r in b.rides.prefix(2) {
            let m = try XCTUnwrap(st.meta(Self.board, r.info.rideId))
            XCTAssertEqual(st.samples(m), r.data, "byte-identical copy on the phone")
            XCTAssertTrue(m.acked); XCTAssertEqual(m.boardConfirmedState, 4); XCTAssertNotNil(m.historyRideId)
        }
        XCTAssertEqual(b.rides.map { $0.info.stateRaw }, [4, 4, 3])
        // a second connection: nothing pulled, nothing ACKed again
        let pulls = b.chunkRequests
        e.linkDown(); e.start(now: Date(timeIntervalSince1970: 500)); pump(e, b, from: Date(timeIntervalSince1970: 500))
        XCTAssertEqual(b.chunkRequests, pulls); XCTAssertEqual(b.acks.count, 2)
    }

    func testNoAckBeforeTheSummaryIsVerified() throws {
        let b = FakeBoard(); b.rides = [Self.ride(5)]
        var sums: [UInt32: UInt32] = [:]
        let st = BoardRideQueueStore(root: dir)
        let e = RideQueueTransfer(boardId: Self.board, store: st) { d in b.handle(d); return true }
        e.summaryCrc = { sums[$0] }
        var asked = 0
        e.requestSummaries = { asked += 1 }
        e.deliver = { _, _ in .stored(UUID()) }
        e.start(now: Date(timeIntervalSince1970: 0)); pump(e, b)
        XCTAssertTrue(b.acks.isEmpty); XCTAssertEqual(asked, 1); XCTAssertEqual(e.holds[5], .summaryNotVerified)
        // a wrong summary is not accepted either
        sums[5] = 0xDEAD; e.summariesArrived(now: Date(timeIntervalSince1970: 200)); pump(e, b, from: Date(timeIntervalSince1970: 200))
        XCTAssertTrue(b.acks.isEmpty)
        // the summary arrives (SYNC_RIDE) → ACK, without pulling the samples again
        let pulls = b.chunkRequests
        sums[5] = b.rides[0].info.summaryCrc32
        e.summariesArrived(now: Date(timeIntervalSince1970: 300)); pump(e, b, from: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(b.acks.map { $0.id }, [5]); XCTAssertEqual(b.chunkRequests, pulls)
    }

    func testNeverAckedWhenTheHistorySaveFails() {
        let b = FakeBoard(); b.rides = [Self.ride(6)]
        let (e, st, _) = rig(b, deliverOK: false)
        e.start(now: Date(timeIntervalSince1970: 0)); pump(e, b)
        XCTAssertTrue(b.acks.isEmpty); XCTAssertEqual(b.rides[0].info.stateRaw, 1, "the board keeps it unsynced")
        XCTAssertNotNil(st.meta(Self.board, 6), "the verified samples are kept on the phone for the next try")
        if case .failed = e.holds[6] {} else { XCTFail("hold expected") }
    }

    func testDemoRecordingAndConflictingRidesAreLeftAlone() throws {
        let b = FakeBoard(); b.rides = [Self.ride(7, flags: 0x01), Self.ride(8, state: 0), Self.ride(9)]
        let st = BoardRideQueueStore(root: dir)
        // ride 9 is already on this phone with OTHER data (ride number reused after a board reset)
        let other = Data("1 2 3 4\n".utf8)
        _ = st.save(BoardQueueRideMeta(boardId: Self.board, rideId: 9, samplesSize: UInt32(other.count), samplesCrc32: CRC32.ieee(other), summaryCrc32: 0, startEpochS: 0, durationS: 1, flags: 0, receivedAt: Date(), historyRideId: UUID(), acked: true))
        let (e, _, delivered) = rig(b)
        e.start(now: Date(timeIntervalSince1970: 0)); pump(e, b)
        XCTAssertTrue(delivered().isEmpty); XCTAssertTrue(b.acks.isEmpty); XCTAssertEqual(b.chunkRequests, 0)
        XCTAssertEqual(e.holds[7], .demo); XCTAssertEqual(e.holds[8], .recording); XCTAssertEqual(e.holds[9], .conflict)
    }

    func testCorruptionRetriedAndResumeAfterLinkLoss() throws {
        let b = FakeBoard(); b.rides = [Self.ride(10, seconds: 3000)]; b.corruptOnce = true
        let (e, st, delivered) = rig(b)
        e.start(now: Date(timeIntervalSince1970: 0)); pump(e, b)
        XCTAssertEqual(delivered(), [10], "checksum mismatch → pulled again from 0, then stored")
        XCTAssertEqual(st.samples(try XCTUnwrap(st.meta(Self.board, 10))), b.rides[0].data)
        // a second ride, link lost half way, resumed from the bytes already on disk
        let b2 = FakeBoard(); b2.rides = [Self.ride(11, seconds: 3000)]; b2.linkPayload = 97
        let (e2, st2, delivered2) = rig(b2)
        e2.start(now: Date(timeIntervalSince1970: 0))
        var now = Date(timeIntervalSince1970: 0)
        for _ in 0..<10_000 where (e2.progress?.received ?? 0) < 6000 {
            if b2.inbox.isEmpty { e2.tick(now: now) } else { e2.receive(b2.inbox.removeFirst(), now: now) }
            now = now.addingTimeInterval(0.01)
        }
        let had = try XCTUnwrap(e2.progress?.received)
        e2.linkDown(); b2.inbox = []
        let before = b2.chunkRequests
        e2.start(now: now); pump(e2, b2, from: now)
        XCTAssertEqual(delivered2(), [11])
        XCTAssertEqual(st2.samples(try XCTUnwrap(st2.meta(Self.board, 11))), b2.rides[0].data)
        XCTAssertLessThan(b2.chunkRequests - before, (b2.rides[0].data.count - Int(had)) / 72 + 3, "resumed, not restarted")
    }

    func testBusyWhileTheBoardRecords() {
        let b = FakeBoard(); b.rides = [Self.ride(12)]
        let (e, _, delivered) = rig(b)
        var recording = true
        e.boardRecording = { recording }
        e.start(now: Date(timeIntervalSince1970: 0)); pump(e, b, seconds: 30)
        XCTAssertEqual(b.chunkRequests, 0, "no chunk request while the board records")
        recording = false
        pump(e, b, from: Date(timeIntervalSince1970: 30))
        XCTAssertEqual(delivered(), [12])
        // BUSY answers are waited out, not counted as failures
        let b2 = FakeBoard(); b2.rides = [Self.ride(13)]; b2.busy = true
        let (e2, _, d2) = rig(b2)
        e2.start(now: Date(timeIntervalSince1970: 0)); pump(e2, b2, seconds: 25)
        XCTAssertTrue(d2().isEmpty); XCTAssertTrue(e2.isBusy)
        b2.busy = false; pump(e2, b2, from: Date(timeIntervalSince1970: 25))
        XCTAssertEqual(d2(), [13])
    }

    func testSamplesParserNeverInventsValues() {
        let s = BoardRideSamples.parse(Data("# r0012\n150 85 120 0\r\n-\n160 - - 8\n\n9999 300 10 16\n170 90 130\n".utf8))
        XCTAssertEqual(s.count, 5)
        XCTAssertEqual(s[0], .init(paused: false, power: 150, cadence: 85, hr: 120, distanceM: 0))
        XCTAssertTrue(s[1].paused)
        XCTAssertEqual(s[2], .init(paused: false, power: 160, cadence: nil, hr: nil, distanceM: 8))
        XCTAssertEqual(s[3], .init(paused: false, power: nil, cadence: nil, hr: nil, distanceM: 16), "out-of-range values are dropped, not clamped")
        XCTAssertNil(s[4].distanceM)
        let t = BoardRideSamples.totals(s)
        XCTAssertEqual(t.movingS, 4); XCTAssertEqual(t.pausedS, 1); XCTAssertEqual(t.avgPower, 160); XCTAssertEqual(t.maxHR, 130); XCTAssertEqual(t.distanceM, 16)
    }

    /// The Store side: the ride lands in the history with its samples, is saved to disk, is not duplicated by a second
    /// import, and the later SYNC_RIDE summary merges into it keeping the samples.
    func testStoreImportIsDurableAndDeduplicated() throws {
        let s = Store(directory: dir.appendingPathComponent("store"), generatePlan: false)
        let r = Self.ride(14, seconds: 900)
        let m = BoardQueueRideMeta(boardId: Self.board, rideId: 14, samplesSize: r.info.samplesSize, samplesCrc32: r.info.samplesCrc32, summaryCrc32: r.info.summaryCrc32,
                                   startEpochS: r.info.startEpochS, durationS: 900, flags: 0, receivedAt: Date())
        guard case .stored(let id) = s.importBoardQueueRide(m, samples: r.data) else { return XCTFail("not stored") }
        XCTAssertEqual(s.rides.count, 1)
        let ride = try XCTUnwrap(s.rides.first)
        XCTAssertEqual(ride.id, id); XCTAssertEqual(ride.boardRideId, 14); XCTAssertEqual(ride.boardId, Self.board); XCTAssertEqual(ride.samples.count, 900)
        XCTAssertNotNil(ride.avgPower); XCTAssertEqual(ride.powerVerified, PowerTrust.meterVerified)
        XCTAssertNil(ride.samples[10].w, "paused second has no value")
        guard case .stored(let id2) = s.importBoardQueueRide(m, samples: r.data) else { return XCTFail("not stored") }
        XCTAssertEqual(id2, id); XCTAssertEqual(s.rides.count, 1, "no duplicate")
        var sum = BCLink.RideSummary(); sum.id = 14; sum.durationS = 900; sum.avgPower = 158; sum.startEpochS = Int(r.info.startEpochS); sum.distanceM = 7192
        s.importBoardRide(sum, boardId: Self.board)
        XCTAssertEqual(s.rides.count, 1); XCTAssertEqual(s.rides[0].avgPower, 158); XCTAssertEqual(s.rides[0].samples.count, 900, "summary merge keeps the samples")
        let reloaded = Store(directory: dir.appendingPathComponent("store"), generatePlan: false)
        XCTAssertEqual(reloaded.rides.first?.samples.count, 900, "on disk")
    }

    func testSummaryCrcIsOverTheSyncRideFields() throws {
        var sum = BCLink.RideSummary(); sum.id = 3; sum.durationS = 60
        let d = try XCTUnwrap(BCLink.encodeSyncRide(sum, seq: 1, tMs: 0))
        XCTAssertEqual(BoardRideQueueStore.summaryCrc(ofSyncRide: d), CRC32.ieee(d.dropFirst(8)))
        let st = BoardRideQueueStore(root: dir)
        st.saveSummaryCrc(Self.board, 3, 0x1234)
        XCTAssertEqual(st.summaryCrc(Self.board, 3), 0x1234); XCTAssertNil(st.summaryCrc(Self.board, 4))
        XCTAssertTrue(st.all().isEmpty, "the summary table is not a ride")
    }
}
