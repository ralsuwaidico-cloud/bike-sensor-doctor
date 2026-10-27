import XCTest
@testable import BikeComputer

/// QA RC3-01 (P1), end to end on the REAL request path: Cyclift's history (Store), the ride-queue engine and the one
/// Sync handler Link13Center uses (`RideQueueTransfer.handleSync` → BoardSummaryIngest), against a fake board that
/// answers Control (RIDEQ_*) and Sync (SYNC_REQ → SYNC_RIDE… SYNC_END, ids > after_ride_id only, like app_psvc.c) with
/// the FIRMWARE's own bytes for ride 23 (link13_fw_fixture.json). No summary is handed to the engine by the test: it has
/// to obtain each one from the board.
///
/// Before the fix the only SYNC_REQ was the connect-time one, `after_ride_id = highest board ride id in the history`; a ride
/// already in the history (watched live, or just imported from the queue) was therefore never sent, its summary CRC never
/// arrived and no RIDEQ_ACK was ever sent (board samples / RAM slots never freed). These tests fail on that code.
final class RideQueueEndToEndTests: XCTestCase {
    static let board = "02:00:00:c1:f7:01"

    /// Board model: one ride queue + its ride history with the SYNC_RIDE bytes it would send for each ride.
    final class Board {
        struct Ride { var info: BCLink.RideQueueInfo; var samples: Data; var syncRide: Data; var listed = true }
        var rides: [Ride] = []
        var controlOut: [Data] = []
        var syncOut: [Data] = []
        var syncRequests: [(after: Int, max: Int)] = []
        var acks: [Data] = []
        var ramSlotsFreed: [UInt32] = []
        /// firmware ≥ 0.7.4-rc4 answers SYNC_REQ `03 only_ride_id` with exactly that ride; older boards ignore the tag.
        var honoursOnlyRide = true
        var syncOnly: [Int?] = []
        func control(_ d: Data) {
            guard let (h, f) = BCLink.parse(d) else { return }
            func u(_ t: UInt8) -> UInt64 { f.first { $0.tag == t }.map { BCLink.uint($0.value) } ?? 0 }
            switch h.type {
            case 0x90:
                let l = rides.filter { $0.listed }
                for r in l { controlOut.append(BCLink.encodeRideQueueInfo(r.info, seq: 0, tMs: 0)) }
                let un = l.filter { $0.info.needsImport }
                controlOut.append(BCLink.encodeRideQueueListEnd(.init(count: l.count, unsynced: un.count, unsyncedBytes: un.reduce(0) { $0 + $1.info.samplesSize }), seq: 0, tMs: 0))
            case 0x93:
                let id = UInt32(u(1)), off = Int(u(2)), maxLen = Int(u(3))
                guard let r = rides.first(where: { $0.info.rideId == id && $0.listed }) else { controlOut.append(BCLink.encodeRideQueueErr(rideId: id, code: 1, seq: 0, tMs: 0)); return }
                let n = min(maxLen, 155, r.samples.count - off)
                controlOut.append(BCLink.encodeRideQueueChunk(.init(rideId: id, offset: UInt32(off), data: r.samples.subdata(in: off..<(off + n)), last: off + n >= r.samples.count), seq: 0, tMs: 0))
            case 0x95:
                acks.append(d)
                let id = UInt32(u(1)), sc = UInt32(u(2)), su = UInt32(u(3)), del = u(4) == 1
                guard let k = rides.firstIndex(where: { $0.info.rideId == id }) else { return }
                let r = rides[k]
                let samplesOK = r.info.summaryOnly || r.info.ramOnly || r.info.samplesCrc32 == sc       /* ignored for bit3/bit4 (v1.1) */
                guard samplesOK, r.info.summaryCrc32 == su else { controlOut.append(BCLink.encodeRideQueueErr(rideId: id, code: 6, seq: 0, tMs: 0)); return }
                rides[k].info.stateRaw = r.info.ramOnly ? 3 : (del ? 4 : 3)
                controlOut.append(BCLink.encodeRideQueueInfo(rides[k].info, seq: 0, tMs: 0))
                if r.info.ramOnly { rides[k].listed = false; ramSlotsFreed.append(id) }               /* v1.2: RAM slot released */
            default: break
            }
        }
        /// SYNC_REQ on the Sync characteristic: the board streams rides with id > after_ride_id (ascending, ≤ max) + SYNC_END.
        func sync(_ d: Data) -> Bool {
            guard let (h, f) = BCLink.parse(d), h.type == 0x50 else { return false }
            let after = Int(f.first { $0.tag == 1 }.map { BCLink.uint($0.value) } ?? 0), mx = Int(f.first { $0.tag == 2 }.map { BCLink.uint($0.value) } ?? 50)
            let only = f.first { $0.tag == 3 }.map { Int(BCLink.uint($0.value)) }
            syncRequests.append((after, mx)); syncOnly.append(only)
            var all = rides.sorted { $0.info.rideId < $1.info.rideId }.filter { Int($0.info.rideId) > after && !$0.syncRide.isEmpty }   /* empty = not in the board's history */
            if honoursOnlyRide, let o = only { all = all.filter { Int($0.info.rideId) == o } }
            for r in all.prefix(mx) { syncOut.append(r.syncRide) }
            let more: UInt8 = all.count > mx ? 1 : 0
            syncOut.append(BCLink.rawMessage(.syncEnd, seq: 0, tMs: 0, [(0x01, BCLink.le(UInt16(min(mx, all.count)))), (0x02, BCLink.le(UInt16(rides.count))), (0x03, Data([more]))]))
            return true
        }
    }

    private var dir: URL!
    private var fixture: [String: [String: Any]] = [:]
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("rq-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(Link13FirmwareFixture.json.utf8)) as? [String: Any])
        for v in try XCTUnwrap(root["vectors"] as? [[String: Any]]) { fixture[v["name"] as! String] = v }
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }
    private func b64(_ name: String, _ key: String) throws -> Data { try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(fixture[name]?[key] as? String))) }

    /// Ride 23 exactly as the firmware encodes it: RIDEQ_INFO, samples file, SYNC_RIDE.
    private func ride23() throws -> Board.Ride {
        let info = try XCTUnwrap(BCLink.decodeRideQueueInfo(try b64("rideq_info", "bytes")))
        return Board.Ride(info: info, samples: try b64("ride_23", "samples"), syncRide: try b64("ride_23", "sync_ride"))
    }
    /// A further ride built with Cyclift's own encoders (the fixture has one full ride), CRCs computed like the board.
    private func ride(_ id: UInt32, ramOnly: Bool = false, seconds: Int = 90) throws -> Board.Ride {
        var s = BCLink.RideSummary(); s.id = Int(id); s.durationS = seconds; s.avgPower = 160; s.maxPower = 240; s.powerS = seconds; s.distanceM = seconds * 7
        s.startEpochS = ramOnly ? 0 : 1_792_860_000 + Int(id) * 3600
        let sync = try XCTUnwrap(BCLink.encodeSyncRide(s, seq: 0, tMs: 0))
        var text = "J1 \(id) 0 250 1 1\n"
        if !ramOnly { for t in 0..<seconds { text += "\(150 + t % 20) \(86 + t % 4) -1 \(t * 7)\n" } }
        let samples = Data(text.utf8)
        let info = BCLink.RideQueueInfo(rideId: id, stateRaw: 1, samplesSize: ramOnly ? 0 : UInt32(samples.count), samplesCrc32: ramOnly ? 0 : CRC32.ieee(samples),
                                        startEpochS: UInt32(s.startEpochS), durationS: UInt32(seconds), flags: ramOnly ? 0x10 : 0,
                                        summaryCrc32: CRC32.ieee(sync.dropFirst(8)))
        return Board.Ride(info: info, samples: ramOnly ? Data() : samples, syncRide: sync)
    }

    /// Wires exactly what Link13Center wires: deliver → Store.importBoardQueueRide, summaryCrc → the queue store,
    /// sendSync → the Sync characteristic, every Sync message → engine.handleSync(history:).
    private func run(_ board: Board, history: Store, seconds: Double = 60) -> RideQueueTransfer {
        let qs = BoardRideQueueStore(root: dir.appendingPathComponent("queue"))
        let e = RideQueueTransfer(boardId: Self.board, store: qs) { board.control($0); return true }
        e.deliver = { m, d in history.importBoardQueueRide(m, samples: d) }
        e.summaryCrc = { qs.summaryCrc(Self.board, $0) }
        e.sendSync = { board.sync($0) }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var now = t0
        var connectSyncSent = false
        e.start(now: now)                       /* HELLO_ACK → ride queue list at once */
        let end = now.addingTimeInterval(seconds)
        while now < end {
            if !board.syncOut.isEmpty { e.handleSync(board.syncOut.removeFirst(), history: history, now: now); continue }
            if !board.controlOut.isEmpty { e.receive(board.controlOut.removeFirst(), now: now); continue }
            // the connect-time history sync DeviceLink.startSync sends 2 s after INFO, after = highest board ride id in the
            // history AT THAT MOMENT — a short / RAM-only ride the queue already imported is above nothing it would send
            if !connectSyncSent, now >= t0.addingTimeInterval(2) {
                connectSyncSent = true
                _ = board.sync(BCLink.encodeSyncRequest(afterRideId: UInt16(clamping: history.highestBoardRideId(for: Self.board)), maxCount: 50, seq: 1, tMs: 0)!)
                continue
            }
            if !e.isBusy, connectSyncSent { break }
            now = now.addingTimeInterval(0.25); e.tick(now: now)
        }
        return e
    }
    private func acked(_ b: Board) -> [UInt32] { b.acks.compactMap { BCLink.parse($0)?.1.first { $0.tag == 1 }.map { UInt32(BCLink.uint($0.value)) } } }

    func testRideWatchedLiveIsVerifiedAgainstTheBoardSummaryAndAcked() throws {
        let b = Board(); b.rides = [try ride23()]
        let history = Store(directory: dir.appendingPathComponent("store"), generatePlan: false)
        // Cyclift was connected during ride 23: the ride recorder's live mirror is already in the history (boardRideId 23)
        var mirror = RideRecord(start: Date(timeIntervalSince1970: 1_792_850_102), durationS: 5, distanceM: 50, recorder: .board, sources: ["BikeComputer", "Phone GPS"])
        mirror.boardRideId = 23; mirror.boardId = Self.board; mirror.avgPower = 999
        mirror.samples = (0..<5).map { RideRecord.Sample(t: $0, w: 999, cad: 85, hr: nil, speedCms: 1000, lat: 25.2, lon: 55.3, alt: nil) }
        history.rides = [mirror]
        _ = run(b, history: history)
        XCTAssertTrue(b.syncRequests.contains { $0.after == 22 && $0.max == 1 }, "the summary of ride 23 is asked for BY ID")
        XCTAssertTrue(b.syncRequests.contains { $0.after == 23 && $0.max == 50 }, "the connect-time sync starts above the ride (the old dead end)")
        XCTAssertEqual(acked(b), [23], "verified against the board's summary, then ACKed")
        XCTAssertEqual(b.acks.first?.dropFirst(8), try b64("rideq_ack", "bytes").dropFirst(8), "the ACK is the firmware's RIDEQ_ACK byte for byte")
        XCTAssertEqual(b.rides[0].info.state, .samplesDeleted, "board samples freed")
        XCTAssertEqual(history.rides.count, 1, "no duplicate of the watched ride")
        XCTAssertEqual(history.rides[0].avgPower, BCLink.decodeSyncRide(try b64("ride_23", "sync_ride"))?.avgPower, "the board's summary replaced the mirror's numbers"); XCTAssertEqual(history.rides[0].samples.first?.lat, 25.2, "the mirror's GPS trace kept")
    }

    func testRideImportedFromTheQueueIsAcked() throws {
        let b = Board(); b.rides = [try ride23()]
        let history = Store(directory: dir.appendingPathComponent("store"), generatePlan: false)
        _ = run(b, history: history)
        XCTAssertTrue(b.syncRequests.contains { $0.after == 22 && $0.max == 1 }, "imported before the connect-time sync: asked for by id")
        XCTAssertEqual(acked(b), [23])
        XCTAssertEqual(history.rides.count, 1); XCTAssertEqual(history.rides[0].boardRideId, 23); XCTAssertEqual(history.rides[0].samples.count, 6)
        XCTAssertEqual(b.rides[0].info.state, .samplesDeleted)
    }

    func testRamOnlyRideSlotIsFreed() throws {
        let b = Board(); b.rides = [try ride(24, ramOnly: true)]
        let history = Store(directory: dir.appendingPathComponent("store"), generatePlan: false)
        _ = run(b, history: history)
        XCTAssertEqual(acked(b), [24]); XCTAssertEqual(b.ramSlotsFreed, [24], "the RAM slot is released after the verified ACK")
        XCTAssertEqual(history.rides.count, 1); XCTAssertEqual(history.rides[0].boardRideId, 24); XCTAssertEqual(history.rides[0].avgPower, 160)
    }

    /// The owner's case: several rides in one power cycle, some watched live, RAM-only ones among them, the newest already
    /// in the history (so the connect-time sync returns nothing) — every one is verified and ACKed, every RAM slot freed.
    func testMultipleRidesAllAckedAndRamSlotsFreed() throws {
        let b = Board(); b.rides = [try ride23(), try ride(24, ramOnly: true), try ride(25), try ride(26, ramOnly: true), try ride(27, ramOnly: true)]
        let history = Store(directory: dir.appendingPathComponent("store"), generatePlan: false)
        for id in [25, 27] {     /* watched live */
            var m = RideRecord(start: Date(timeIntervalSince1970: TimeInterval(id == 25 ? 1_792_860_000 + 25 * 3600 : 1_800_000_000)), durationS: 90, distanceM: 0, recorder: .board, sources: ["BikeComputer"])
            m.boardRideId = id; m.boardId = Self.board; history.rides.append(m)
        }
        let e = run(b, history: history, seconds: 120)
        XCTAssertEqual(Set(acked(b)), [23, 24, 25, 26, 27])
        XCTAssertEqual(Set(b.ramSlotsFreed), [24, 26, 27])
        XCTAssertEqual(b.rides.filter { !$0.info.ramOnly }.map { $0.info.state }, [.samplesDeleted, .samplesDeleted])
        XCTAssertEqual(Set(history.rides.compactMap { $0.boardRideId }), [23, 24, 25, 26, 27]); XCTAssertEqual(history.rides.count, 5, "no duplicates")
        XCTAssertTrue(e.holds.isEmpty, "nothing left held: \(e.holds)")
        XCTAssertEqual(b.syncRequests.filter { $0.max == 1 }.map { $0.after }.sorted(), [22, 23, 24, 25, 26], "one by-id request per held ride")
        XCTAssertEqual(b.syncOnly.compactMap { $0 }.sorted(), [23, 24, 25, 26, 27], "v1.3: each carries only_ride_id = the ride")
    }

    /// The same five rides on a board before rc4 (it ignores `03 only_ride_id` and answers after/max): still all verified,
    /// ACKed and freed — the after = id − 1, max 1 part does the job.
    func testOlderBoardIgnoringOnlyRideIdStillWorks() throws {
        let b = Board(); b.honoursOnlyRide = false
        b.rides = [try ride23(), try ride(24, ramOnly: true), try ride(25), try ride(26, ramOnly: true), try ride(27, ramOnly: true)]
        let history = Store(directory: dir.appendingPathComponent("store"), generatePlan: false)
        let e = run(b, history: history, seconds: 120)
        XCTAssertEqual(Set(acked(b)), [23, 24, 25, 26, 27]); XCTAssertEqual(Set(b.ramSlotsFreed), [24, 26, 27])
        XCTAssertEqual(history.rides.count, 5); XCTAssertTrue(e.holds.isEmpty, "\(e.holds)")
    }

    /// rc4 answers `only_ride_id` with exactly that ride or nothing: a held ride the board can no longer summarise is
    /// NOT confused with the next ride (an older board would send ride 25 for "after 23, max 1").
    func testOnlyRideIdNeverVerifiesAnotherRide() throws {
        var r24 = try ride(24); r24.syncRide = Data()          /* the board can no longer send ride 24's summary */
        let b = Board(); b.rides = [r24, try ride(25)]
        let history = Store(directory: dir.appendingPathComponent("store"), generatePlan: false)
        var m = RideRecord(start: Date(timeIntervalSince1970: TimeInterval(1_792_860_000 + 25 * 3600)), durationS: 90, distanceM: 0, recorder: .board, sources: ["BikeComputer"])
        m.boardRideId = 25; m.boardId = Self.board; history.rides.append(m)
        let e = run(b, history: history, seconds: 60)
        XCTAssertFalse(acked(b).contains(24), "never ACKed against another ride's summary"); XCTAssertEqual(e.holds[24], .summaryNotVerified)
        XCTAssertTrue(acked(b).contains(25))
        XCTAssertTrue(b.syncOnly.contains(24), "asked for ride 24 only")
    }

    /// A wrong summary is never accepted: the board's summary of the ride does not match → no ACK, ride kept.
    func testMismatchingSummaryIsNeverAcked() throws {
        var r = try ride23(); r.info.summaryCrc32 ^= 1
        let b = Board(); b.rides = [r]
        let history = Store(directory: dir.appendingPathComponent("store"), generatePlan: false)
        let e = run(b, history: history)
        XCTAssertTrue(b.acks.isEmpty); XCTAssertEqual(e.holds[23], .summaryNotVerified)
        XCTAssertEqual(b.rides[0].info.state, .closedUnsynced, "kept on the board")
    }
}
