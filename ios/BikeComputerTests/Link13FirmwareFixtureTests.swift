import XCTest
@testable import BikeComputer

/// Link 1.3 cross-test against the FIRMWARE's own encoder (firmware/waveshare/test/host/gen_link13_fixture.c, firmware
/// 0.7.5, BLE_CONTRACT.md v1.1): every board → phone vector is decoded by Cyclift and re-encoded byte for byte, every
/// phone → board vector is produced by Cyclift's encoder and compared byte for byte. Same pattern as DiagFirmwareFixtureTests.
final class Link13FirmwareFixtureTests: XCTestCase {
    private var vectors: [String: [String: Any]] = [:]
    private var root: [String: Any] = [:]

    override func setUpWithError() throws {
        root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(Link13FirmwareFixture.json.utf8)) as? [String: Any])
        for v in try XCTUnwrap(root["vectors"] as? [[String: Any]]) { vectors[try XCTUnwrap(v["name"] as? String)] = v }
    }
    private func bytes(_ name: String, _ key: String = "bytes", file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        let v = try XCTUnwrap(vectors[name], "vector \(name)", file: file, line: line)
        let d = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(v[key] as? String)), file: file, line: line)
        if key == "bytes", let n = (v["len"] as? NSNumber)?.intValue { XCTAssertEqual(d.count, n, "\(name) len", file: file, line: line) }
        return d
    }
    private func f(_ name: String) -> [String: Any] { (vectors[name]?["fields"] as? [String: Any]) ?? [:] }
    private func n(_ name: String, _ k: String) -> Int { (f(name)[k] as? NSNumber)?.intValue ?? Int.min }
    private func u32(_ name: String, _ k: String) -> UInt32 { UInt32(truncatingIfNeeded: (f(name)[k] as? NSNumber)?.int64Value ?? -1) }
    /// seq and sender time of a firmware message, to re-encode it with the same header.
    private func hdr(_ d: Data) -> (seq: UInt16, tMs: UInt32) { let h = BCLink.parse(d)!.0; return (h.seq, h.tMs) }

    func testFixtureCopiesAgreeAndEveryVectorIsCovered() throws {
        if let url = Bundle(for: Link13FirmwareFixtureTests.self).url(forResource: "link13_fw_fixture", withExtension: "json") {
            let file = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            XCTAssertEqual(file.trimmingCharacters(in: .whitespacesAndNewlines), Link13FirmwareFixture.json.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        XCTAssertEqual(root["link_max"] as? Int, BCLink.maxMessage)
        let caps = try XCTUnwrap(root["caps"] as? [String: Int])
        XCTAssertEqual(UInt32(caps["hello"]!), BCLink.Info.capHello); XCTAssertEqual(UInt32(caps["coach"]!), BCLink.Info.capCoach)
        XCTAssertEqual(UInt32(caps["ride_queue"]!), BCLink.Info.capRideQueue); XCTAssertEqual(UInt32(caps["storage"]!), BCLink.Info.capStorage)
        XCTAssertEqual(UInt32(caps["diag_auto"]!), BCLink.Info.capDiagAuto)
        let covered: Set<String> = ["app_hello", "hello_ack", "coach_plan_part0", "coach_plan_part1", "coach_plan_ack_part", "coach_plan_ack_complete",
            "coach_state_full", "coach_card_example", "coach_state_keepalive", "coach_end", "rideq_list_req", "ride_23", "rideq_info", "rideq_info_ram_only",
            "rideq_list_end", "rideq_chunk_req", "rideq_chunk", "rideq_ack", "rideq_info_after_ack", "rideq_err_crc", "rideq_err_busy_recording",
            "event_rides_pending", "storage_status_req", "storage_status_dir_corrupted", "storage_clean_req", "storage_clean_refused", "storage_clean_done",
            "storage_clean_rule", "live_with_link13_tags", "diag_ack_delete",
            "coach_state_partial_instruction", "live_link13_zero", "sync_req_only_ride"]
        XCTAssertEqual(Set(vectors.keys), covered, "a new firmware vector needs a check here")
    }

    // MARK: §4
    func testHello() throws {
        let hello = try bytes("app_hello")
        XCTAssertEqual(UInt32(n("app_hello", "app_caps")), BCLink.appCaps13)
        XCTAssertEqual(BCLink.encodeAppHello(appVersion: f("app_hello")["app_version"] as! String, seq: 1, tMs: 0), hello)
        let ackB = try bytes("hello_ack")
        let ack = try XCTUnwrap(BCLink.decodeHelloAck(ackB))
        XCTAssertEqual(ack.enabledCaps, u32("hello_ack", "enabled_caps"))
        XCTAssertEqual(BCLink.encodeHelloAck(enabledCaps: ack.enabledCaps, seq: hdr(ackB).seq, tMs: hdr(ackB).tMs), ackB)
    }

    // MARK: §5
    func testCoachPlanPartsAckStateEnd() throws {
        let p0b = try bytes("coach_plan_part0"), p1b = try bytes("coach_plan_part1")
        let p0 = try XCTUnwrap(BCLink.decodeCoachPlan(p0b)), p1 = try XCTUnwrap(BCLink.decodeCoachPlan(p1b))
        XCTAssertEqual(p0.workoutId, u32("coach_plan_part0", "workout_id")); XCTAssertEqual(p0.parts, 2); XCTAssertEqual(p0.segments.count, 9)
        XCTAssertEqual(p1.firstSegment, 9); XCTAssertEqual(p1.segments.count, 3); XCTAssertEqual(p1.segments.last?.durationS, 0xFFFF, "open-ended last segment (Q-iOS-3)")
        let plan = BCLink.CoachPlan(workoutId: p0.workoutId, name: try XCTUnwrap(p0.name), segments: p0.segments + p1.segments, t0ElapsedS: try XCTUnwrap(p0.t0ElapsedS))
        XCTAssertEqual(plan.name, f("coach_plan_part0")["name"] as? String)
        XCTAssertEqual(plan.segments.count, n("coach_plan_part0", "total_segments")); XCTAssertEqual(Int(plan.totalDurationS), n("coach_plan_part0", "total_duration_s"))
        XCTAssertEqual(plan.crc32, u32("coach_plan_part0", "plan_crc32"), "Cyclift's plan CRC = the firmware's")
        XCTAssertEqual(plan.t0ElapsedS, BCLink.coachT0AtRideStart)
        XCTAssertEqual(plan.partCount, 2)
        XCTAssertEqual(BCLink.encodeCoachPlan(plan, part: 0, seq: 2, tMs: 0), p0b, "Cyclift part 0 = firmware part 0")
        XCTAssertEqual(BCLink.encodeCoachPlan(plan, part: 1, seq: 3, tMs: 0), p1b, "Cyclift part 1 = firmware part 1")
        for (name, status, next) in [("coach_plan_ack_part", BCLink.CoachPlanAck.Status.partReceived, 1), ("coach_plan_ack_complete", .stored, 2)] {
            let b = try bytes(name); let a = try XCTUnwrap(BCLink.decodeCoachPlanAck(b))
            XCTAssertEqual(a.workoutId, plan.workoutId); XCTAssertEqual(a.status, status); XCTAssertEqual(a.nextPart, next)
            XCTAssertEqual(BCLink.encodeCoachPlanAck(a, seq: hdr(b).seq, tMs: hdr(b).tMs), b)
        }
        // the sender walks the firmware's ACKs to "stored"
        var sent: [Data] = []
        let m = CoachMirror { sent.append($0); return true }
        m.setPlan(plan, now: Date(timeIntervalSince1970: 0))
        m.receive(try bytes("coach_plan_ack_part"), now: Date(timeIntervalSince1970: 0))
        m.receive(try bytes("coach_plan_ack_complete"), now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(m.planStatus, .stored)
        XCTAssertEqual(sent.map { $0.dropFirst(8) }, [p0b.dropFirst(8), p1b.dropFirst(8)], "same parts, only Cyclift's own seq differs")

        let sb = try bytes("coach_state_full")
        let s = try XCTUnwrap(BCLink.decodeCoachState(sb))
        let ff = f("coach_state_full")
        XCTAssertEqual(s.workoutId, plan.workoutId); XCTAssertEqual(Int(s.seq), ff["state_seq"] as? Int)
        XCTAssertEqual(s.type, .endurance); XCTAssertEqual(s.targetKind, .powerW); XCTAssertEqual(s.targetLo, 140); XCTAssertEqual(s.targetHi, 155)
        XCTAssertEqual(s.cadLo, 80); XCTAssertEqual(s.cadHi, 90); XCTAssertEqual(s.intervalIndex, 3); XCTAssertEqual(s.intervalCount, 12)
        XCTAssertEqual(s.remainingS, 161); XCTAssertEqual(s.intervalDurationS, 480); XCTAssertEqual(s.nextType, .recovery); XCTAssertEqual(s.nextTargetKind, .powerW)
        XCTAssertEqual(s.nextLo, 100); XCTAssertEqual(s.nextHi, 130); XCTAssertEqual(s.nextDurationS, 180); XCTAssertEqual(s.instruction, .onTarget)
        XCTAssertEqual(s.text, ff["text"] as? String); XCTAssertEqual(s.sessionState, .running); XCTAssertEqual(s.hrSource, 4); XCTAssertEqual(s.zone, 2)
        XCTAssertEqual(s.flags, BCLink.CoachState.flagFtpDerived | BCLink.CoachState.flagWatchHRLive)
        XCTAssertEqual(BCLink.encodeCoachState(s, seq: 4, tMs: 0), sb, "Cyclift COACH_STATE = firmware COACH_STATE")

        // v1.3 keepalive = workout_id + seq only (the board merges; nothing else changes). Cyclift's encoder = firmware's.
        let kb = try bytes("coach_state_keepalive")
        let k = try XCTUnwrap(BCLink.decodeCoachState(kb))
        XCTAssertEqual(k.workoutId, plan.workoutId); XCTAssertEqual(k.seq, 42)
        XCTAssertEqual(BCLink.encodeCoachKeepalive(workoutId: plan.workoutId, stateSeq: 42, seq: 5, tMs: 0), kb)
        // a partial state (instruction only) — merged by the board; Cyclift itself always sends complete states
        let pb = try bytes("coach_state_partial_instruction")
        let (ph, pf) = try XCTUnwrap(BCLink.parse(pb))
        XCTAssertEqual(ph.type, 0xB2); XCTAssertEqual(pf.map { $0.tag }, [0x01, 0x02, 0x12])
        XCTAssertEqual(BCLink.decodeCoachState(pb)?.instruction, .morePower); XCTAssertEqual(BCLink.decodeCoachState(pb)?.seq, 43)
        XCTAssertEqual(BCLink.rawMessage(.coachState, seq: 5, tMs: 0, [(0x01, BCLink.le(plan.workoutId)), (0x02, BCLink.le(UInt16(43))), (0x12, Data([2]))]), pb)
        // Cyclift's complete state carries every tag 01–17 (also next_* and text when there is none), so a merge never
        // leaves a stale value on the board
        var lastSeg = s; lastSeg.nextType = nil; lastSeg.text = ""
        let full = try XCTUnwrap(BCLink.encodeCoachState(lastSeg, seq: 9, tMs: 0))
        XCTAssertEqual(try XCTUnwrap(BCLink.parse(full)).1.map { $0.tag }, Array(0x01...0x17).map { UInt8($0) })

        XCTAssertEqual(BCLink.encodeCoachEnd(workoutId: plan.workoutId, reason: .completed, seq: 6, tMs: 0), try bytes("coach_end"))
    }

    /// The board's coach card uses the same words Cyclift encodes (type labels, instruction texts).
    func testCoachCardWords() throws {
        let lines = try XCTUnwrap(vectors["coach_card_example"]?["lines"] as? [String])
        XCTAssertEqual(lines.first, "CYCLIFT COACH")
        XCTAssertTrue(lines.contains { $0.hasPrefix(BCLink.CoachWorkoutType.endurance.label) })
        XCTAssertTrue(lines.contains("COACH: " + BCLink.CoachInstruction.onTarget.text))
        XCTAssertTrue(lines.contains { $0.hasPrefix("NEXT: " + BCLink.CoachWorkoutType.recovery.label) })
        XCTAssertTrue(lines.allSatisfy { $0.utf8.count <= 24 })
    }

    // MARK: §6
    func testRideDefinitionSummaryCrcAndSamplesGrammar() throws {
        let v = try XCTUnwrap(vectors["ride_23"])
        let sync = try bytes("ride_23", "sync_ride")
        let r = try XCTUnwrap(BCLink.decodeSyncRide(sync))
        XCTAssertEqual(r.id, 23)
        XCTAssertEqual(BoardRideQueueStore.summaryCrc(ofSyncRide: sync), UInt32((v["summary_crc32"] as! NSNumber).int64Value), "summary_crc32 over SYNC_RIDE bytes 8…end (Q-iOS-1)")
        XCTAssertEqual(BCLink.encodeSyncRide(r, seq: hdr(sync).seq, tMs: hdr(sync).tMs), sync, "Cyclift re-encodes the board's SYNC_RIDE byte for byte")
        let samples = try bytes("ride_23", "samples")
        XCTAssertEqual(samples.count, v["samples_size"] as? Int)
        XCTAssertEqual(CRC32.ieee(samples), UInt32((v["samples_crc32"] as! NSNumber).int64Value))
        let g = try XCTUnwrap(v["samples_lines"] as? [String: Any])
        let h = try XCTUnwrap(BoardRideSamples.header(samples))
        XCTAssertEqual("J1 \(h.rideId) \(h.demo ? 1 : 0) \(h.ftpW!) \(h.ftpHow!) \(h.ftpEstablished ? 1 : 0)", g["header"] as? String)
        let secs = BoardRideSamples.parse(samples)
        XCTAssertEqual(secs.count, g["seconds"] as? Int, "header skipped, paused second included")
        XCTAssertEqual(secs.filter { $0.paused }.count, g["paused_seconds"] as? Int)
        XCTAssertTrue(secs.filter { !$0.paused }.allSatisfy { $0.hr == nil }, "-1 = no data, never a value")
        let d = secs.compactMap { $0.distanceM }
        XCTAssertEqual(d, d.sorted(), "cumulative distance")
        // a torn last line (power loss) is ignored
        var torn = samples; torn.append(Data("190 8".utf8))
        XCTAssertEqual(BoardRideSamples.parse(torn), secs)
    }

    func testRideQueueMessages() throws {
        for name in ["rideq_info", "rideq_info_ram_only", "rideq_info_after_ack"] {
            let b = try bytes(name); let i = try XCTUnwrap(BCLink.decodeRideQueueInfo(b), name)
            XCTAssertEqual(i.rideId, u32(name, "ride_id")); XCTAssertEqual(Int(i.stateRaw), n(name, "state"))
            XCTAssertEqual(BCLink.encodeRideQueueInfo(i, seq: hdr(b).seq, tMs: hdr(b).tMs), b, name)
        }
        let info = try XCTUnwrap(BCLink.decodeRideQueueInfo(try bytes("rideq_info")))
        XCTAssertEqual(info.samplesSize, u32("rideq_info", "samples_size")); XCTAssertEqual(info.samplesCrc32, u32("rideq_info", "samples_crc32"))
        XCTAssertEqual(info.summaryCrc32, u32("rideq_info", "summary_crc32")); XCTAssertEqual(info.startEpochS, u32("rideq_info", "start_epoch_s"))
        XCTAssertFalse(info.demo); XCTAssertFalse(info.ramOnly); XCTAssertTrue(info.needsImport)
        let ram = try XCTUnwrap(BCLink.decodeRideQueueInfo(try bytes("rideq_info_ram_only")))
        XCTAssertTrue(ram.ramOnly); XCTAssertEqual(ram.samplesSize, 0); XCTAssertEqual(ram.durationS, 1800)
        XCTAssertEqual(BCLink.decodeRideQueueInfo(try bytes("rideq_info_after_ack"))?.state, .samplesDeleted)
        let eb = try bytes("rideq_list_end"); let e = try XCTUnwrap(BCLink.decodeRideQueueListEnd(eb))
        XCTAssertEqual(e.count, 2); XCTAssertEqual(e.unsynced, 2); XCTAssertEqual(e.unsyncedBytes, 83)
        XCTAssertEqual(BCLink.encodeRideQueueListEnd(e, seq: hdr(eb).seq, tMs: hdr(eb).tMs), eb)
        XCTAssertEqual(BCLink.encodeRideQueueListRequest(seq: 7, tMs: 0), try bytes("rideq_list_req"))
        XCTAssertEqual(BCLink.encodeRideQueueChunkRequest(rideId: 23, offset: 0, maxLen: UInt16(n("rideq_chunk_req", "max_len")), seq: 11, tMs: 0), try bytes("rideq_chunk_req"))
        let cb = try bytes("rideq_chunk"); let c = try XCTUnwrap(BCLink.decodeRideQueueChunk(cb))
        XCTAssertEqual(c.data, try bytes("ride_23", "samples")); XCTAssertTrue(c.last)
        XCTAssertEqual(BCLink.encodeRideQueueChunk(c, seq: hdr(cb).seq, tMs: hdr(cb).tMs), cb)
        XCTAssertEqual(BCLink.encodeRideQueueAck(rideId: 23, samplesCrc32: u32("rideq_ack", "samples_crc32"), summaryCrc32: u32("rideq_ack", "summary_crc32"), deleteSamples: true, seq: 12, tMs: 0),
                       try bytes("rideq_ack"))
        for (name, code) in [("rideq_err_crc", BCLink.DiagErr.Code.crcMismatch), ("rideq_err_busy_recording", .busy)] {
            let b = try bytes(name); let x = try XCTUnwrap(BCLink.decodeRideQueueErr(b))
            XCTAssertEqual(x.reportId, 23); XCTAssertEqual(x.known, code)
            XCTAssertEqual(BCLink.encodeRideQueueErr(rideId: 23, code: code.rawValue, seq: hdr(b).seq, tMs: hdr(b).tMs), b)
        }
        let pb = try bytes("event_rides_pending"); let p = try XCTUnwrap(BCLink.decodeRidesPending(pb))
        XCTAssertEqual(p.unsynced, 2); XCTAssertEqual(p.newestRideId, 24)
        XCTAssertEqual(BCLink.encodeRidesPending(unsynced: 2, newest: 24, seq: hdr(pb).seq, tMs: hdr(pb).tMs), pb)
    }

    /// The engine end to end on the firmware's bytes: list → chunk → stored → the ACK Cyclift sends IS the firmware's
    /// RIDEQ_ACK (only the seq differs); the RAM-only ride is imported first and ACKed once its summary is verified.
    func testEngineProducesTheFirmwareAck() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("l13fx-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BoardRideQueueStore(root: dir)
        var sent: [Data] = []
        let e = RideQueueTransfer(boardId: "02:00:00:c1:f7:01", store: store) { sent.append($0); return true }
        let summary = BoardRideQueueStore.summaryCrc(ofSyncRide: try bytes("ride_23", "sync_ride"))
        let ramSummary = u32("rideq_info_ram_only", "summary_crc32")
        e.summaryCrc = { $0 == 23 ? summary : $0 == 24 ? ramSummary : nil }
        var delivered: [UInt32] = []
        e.deliver = { m, _ in delivered.append(m.rideId); return .stored(UUID()) }
        let now = Date(timeIntervalSince1970: 0)
        e.start(now: now)
        XCTAssertEqual(sent.last?.first, 0x90)
        for name in ["rideq_info", "rideq_info_ram_only", "rideq_list_end"] { e.receive(try bytes(name), now: now) }
        XCTAssertEqual(delivered, [24], "RAM-only ride first: nothing to pull, stored at once")
        let req = try XCTUnwrap(sent.last); XCTAssertEqual(req.first, 0x93)
        XCTAssertEqual(req.dropFirst(8), try bytes("rideq_chunk_req").dropFirst(8), "Cyclift's chunk request = the firmware's")
        e.receive(try bytes("rideq_chunk"), now: now)
        XCTAssertEqual(delivered, [24, 23])
        let acks = sent.filter { $0.first == 0x95 }
        XCTAssertEqual(acks.count, 2)
        XCTAssertEqual(acks.last?.dropFirst(8), try bytes("rideq_ack").dropFirst(8), "Cyclift's RIDEQ_ACK = the firmware's")
        // a mismatch answer from the board (ERR 6): not confirmed, kept, said so
        e.receive(try bytes("rideq_err_crc"), now: now)
        XCTAssertEqual(store.meta("02:00:00:c1:f7:01", 23)?.acked, false)
        if case .failed = e.holds[23] {} else { XCTFail("ERR 6 must hold the ride") }
    }

    // MARK: §7, LIVE, §8
    func testStorageLiveAndDiag() throws {
        let sb = try bytes("storage_status_dir_corrupted"); let s = try XCTUnwrap(BCLink.decodeStorageStatus(sb))
        let ff = f("storage_status_dir_corrupted")
        XCTAssertEqual(s.state, .dirCorrupted); XCTAssertEqual(s.code, ff["code"] as? String); XCTAssertEqual(s.fsTotalKB, 7964); XCTAssertEqual(s.fsFreeKB, 5096)
        XCTAssertEqual(s.crashPartition, 1); XCTAssertEqual(s.ridesUnsynced, 1); XCTAssertEqual(s.appSlotKB, 4032); XCTAssertEqual(s.appUsedKB, 1804)
        XCTAssertEqual(s.nvsUsedEntries, 310); XCTAssertEqual(s.nvsFreeEntries, 320); XCTAssertEqual(s.rootBadEntries, 512); XCTAssertEqual(s.healthRaw, 2)
        XCTAssertEqual(BCLink.encodeStorageStatus(s, seq: hdr(sb).seq, tMs: hdr(sb).tMs), sb)
        XCTAssertEqual(BoardStorageModel.category(s, liveState: nil), "Directory corrupted"); XCTAssertEqual(BoardStorageModel.health(s), .failed)
        XCTAssertEqual(BCLink.encodeStorageStatusRequest(seq: 16, tMs: 0), try bytes("storage_status_req"))
        XCTAssertEqual(BCLink.encodeStorageCleanRequest([.ackedReports, .syncedRideSamples, .caches], seq: 17, tMs: 0), try bytes("storage_clean_req"))
        for (name, status) in [("storage_clean_refused", BCLink.StorageCleanResult.Status.refusedStorageNotOK), ("storage_clean_done", .done)] {
            let b = try bytes(name); let r = try XCTUnwrap(BCLink.decodeStorageCleanResult(b))
            XCTAssertEqual(r.status, status); XCTAssertEqual(Int(r.bytesFreed), n(name, "bytes_freed")); XCTAssertEqual(r.items, n(name, "items"))
            XCTAssertEqual(BCLink.encodeStorageCleanResult(r, seq: hdr(b).seq, tMs: hdr(b).tMs), b)
        }
        // the cleanup rule is the board's: allowed exactly for 0/1/6, refused for 2/3/4/5/7
        let rule = try XCTUnwrap(vectors["storage_clean_rule"])
        for st in try XCTUnwrap(rule["allowed_states"] as? [Int]) {
            var x = BCLink.StorageStatus(); x.stateRaw = UInt8(st)
            XCTAssertTrue(BoardStorageModel.cleanup(status: x, linkEnabled: true, boardRecording: false, unsentReports: 0, unsyncedRides: 0).allowed, "state \(st)")
        }
        for st in try XCTUnwrap(rule["refused_states"] as? [Int]) {
            var x = BCLink.StorageStatus(); x.stateRaw = UInt8(st)
            XCTAssertFalse(BoardStorageModel.cleanup(status: x, linkEnabled: true, boardRecording: false, unsentReports: 0, unsyncedRides: 0).allowed, "state \(st)")
        }
        let l = try XCTUnwrap(BCLink.decodeLive(try bytes("live_with_link13_tags")))
        XCTAssertEqual(l.powerW, 145); XCTAssertEqual(l.cadenceRpm, 84); XCTAssertEqual(l.rideId, 23); XCTAssertEqual(l.elapsedS, 1830)
        XCTAssertEqual(l.coachSeq, 41); XCTAssertEqual(l.coachMode, 2); XCTAssertEqual(l.storageState, 3); XCTAssertEqual(l.ridesUnsynced, 1); XCTAssertEqual(l.btFlags, 0, "rc4: always sent")
        // rc4 sends 13–15 also when 0: a real 0, not "unknown"; 11/12 absent = no workout mirrored
        let z = try XCTUnwrap(BCLink.decodeLive(try bytes("live_link13_zero")))
        XCTAssertEqual(z.storageState, 0); XCTAssertEqual(z.ridesUnsynced, 0); XCTAssertEqual(z.btFlags, 0); XCTAssertNil(z.coachSeq); XCTAssertNil(z.coachMode)
        // v1.3 SYNC_REQ by id: Cyclift's request = the firmware's vector
        XCTAssertEqual(BCLink.encodeSyncRequest(onlyRideId: UInt32(n("sync_req_only_ride", "only_ride_id")), seq: 22, tMs: 0), try bytes("sync_req_only_ride"))
        XCTAssertEqual(n("sync_req_only_ride", "after_ride_id"), 41); XCTAssertEqual(n("sync_req_only_ride", "max_count"), 1)
        XCTAssertEqual(BCLink.encodeDiagAck(reportId: 7, crc32: u32("diag_ack_delete", "crc32"), delete: true, seq: 20, tMs: 0), try bytes("diag_ack_delete"))
    }
}
